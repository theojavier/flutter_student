// yolo-eye.js — YOLO eyelid/iris keypoints (LiteRT .tflite) for the gaze pipeline.
// Load order:  gaze-core.js  ->  yolo-eye.js  ->  gaze-calibration.js / exam-gaze-block.js
//
// MediaPipe finds the face, eye corners and head pose (GazeCore.extract).
//
// FUSION MODE (cfg.fuse = true, default):
//   * Every camera frame, the iris offset comes from MediaPipe (468 / 473), measured against
//     MediaPipe's own eye corners. Smooth, no waiting for the model.
//   * YOLO runs in the background. Its iris is measured against the SAME MediaPipe corners, so
//     (YOLO - MediaPipe) is pure iris error. That difference is low-passed (cfg.fuseTau) and added
//     to MediaPipe as a slowly-corrected bias. YOLO's own corner / eyelid keypoints are NOT used
//     for the offset any more, so their noise no longer reaches the features.
//
// Other modes:
//   fuse:false, ref:"mp"    -> YOLO iris vs MediaPipe corners, updated only when YOLO finishes
//   fuse:false, ref:"yolo"  -> the old behaviour (YOLO iris vs YOLO corners / lid centre)
//
// Calibration and exam MUST use the same mode. Features changed -> recalibrate (GazeCore.VERSION 5).
//
//   await YoloEye.init();
//   const raw = await YoloEye.extract(lm, W, H, videoEl);   // null = no usable result yet. In fusion
//                                                           // mode this returns instantly (not a promise).
//   const smooth = YoloEye.makeSmoother(250);
//   const s = smooth(raw, performance.now());               // s.ox/s.oy are already head + distance corrected

const YoloEye = (() => {
  const cfg = {
    modelUrl: "./model_1024/best_w8a32_640.tflite", // w8a32: balanced speed + accuracy
    jsonUrl: "./model_1024/eye_keypoint_names.json",
    accelerators: ["webgpu", "wasm"], // tried in order; wasm (CPU) is the fallback if WebGPU is missing
    litertBase: "https://cdn.jsdelivr.net/npm/@litertjs/core@2.5.3",
    refine: false, // DISABLED: 2nd pass is slow, skip it
    tta: 1, // DISABLED: test-time averaging is slow, 1 = off
    distanceComp: true, // scale the offset by (SCALE_REF / face scale)
    blinkEar: 0.14, // MediaPipe eye-aspect-ratio below this = eye closed
    disagree: 0.10, // (non-fusion modes) ox difference above this: pick best eye instead of averaging
    minCut: 0.5, // 1-Euro min cutoff on the eye offset (lower = steadier when still)
    beta: 4, // 1-Euro speed coefficient (features are in eye-widths, so this needs to be SMALL; try 1)
    boxSmoothing: 0.85, // smoothing of the crop box position
    gpuRetries: 0, // 0 = go straight to CPU after GPU reset

    // ---- LOCKED CROP BOX ----
    // The crop is cut from the MediaPipe eye corners. It used to follow them every frame, so the same eye was cut
    // out slightly differently each time and the YOLO keypoints moved with it. Now the box stays put and only
    // moves when the eye really moved. Distances are in eye-widths.
    boxMove: 0.08, // move the box when the eye centre has shifted by more than this
    boxScale: 0.08, // ...or the eye width changed by more than this (fraction)
    boxAngle: 0.06, // ...or the eye line turned by more than this (rad, about 3.4 deg)
    boxRecenter: 0.12, // ...or YOLO's own corners say the eye sits this far off-centre in the box
    boxMissMax: 3, // YOLO found nothing this many frames in a row: drop the box and re-find the eye

    // ---- FUSION ----
    fuse: true, // MediaPipe iris every frame + slow YOLO bias correction
    ref: "mp", // used when fuse is false: "mp" = MediaPipe corners, "yolo" = YOLO corners/lid centre
    fuseTau: 500, // ms: how fast YOLO corrects MediaPipe's bias (lower = trust YOLO more)
    fuseGate: 0.12, // eye-widths: YOLO samples further than this from the running bias are rejected
    fuseMinQ: 0.25, // skip bias updates when YOLO eye quality is below this
    fuseMinEar: 0.16, // skip bias updates when the lid partly covers the iris (both sources unreliable)
    fuseSkipFirst: 3, // ignore initial YOLO results while the GPU and exposure settle
    fuseSeedN: 5, // seed the bias from the median of this many samples
    fuseSeedSpread: 0.05, // maximum seed-sample spread in eye-widths
    fuseWarmMaxMs: 3000, // wait this long for both eyes before allowing one
  };

  const NK = 13, CONF = 0.05, KCONF = 0.30, DISAGREE = 0.10;
  const VARS = [[0.025, -0.02, 1.03], [-0.025, 0.02, 0.97]]; // extra crops: shift (x, y in eye-widths) and zoom
  const IRIS_Y_NO_TB = true; // vertical gaze ignores the noisy iris top/bottom points
  const FLIP = { L: false, R: true };
  const EYES = { L: [33, 133, 159, 145], R: [362, 263, 386, 374] }; // [corner a, corner b, lid up, lid low]
  const IRIS = { L: 468, R: 473 }; // MediaPipe iris centres (refineLandmarks: true)
  const SCALE_REF = 0.28; // face-width / frame-width the distance factor is relative to
  const REF_EYE_PX = 50; // eye width (px) at which smoothing is at its base value
  const EYE_PER_RAD = GazeCore.EYE_PER_RAD ?? 0.4;
  const HEAD = ["yaw", "pitch", "roll", "cx", "cy", "scale"];
  const med = GazeCore.med;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  let S = 128, J = null, eyeModel = null, LTensor = null, NHWC = false, V = null;
  let lastScore = 0, why = "", initPromise = null, error = null, info = "", usedAccel = "", lastGaze = null;

  // GPU-reset recovery state
  let recovering = null;   // Promise while the model is being rebuilt
  let gpuLosses = 0;
  let failed = false;      // true only if even the CPU fallback could not load
  let litert = null;       // LiteRT module, loaded once and reused

  class GpuLost extends Error {}
  const isGpuLoss = (e) => {
    const m = String((e && e.message) || e || "");
    return (
      (m.includes("Device") && m.includes("lost")) ||
      m.includes("mapAsync") ||
      m.includes("DXGI") ||
      (e && e.name === "OperationError")
    );
  };

  const cc = document.createElement("canvas");
  cc.width = cc.height = S;
  const cctx = cc.getContext("2d", { willReadFrequently: true });
  cctx.imageSmoothingEnabled = true;
  cctx.imageSmoothingQuality = "high";
  // NB: resizing the canvas in load() resets these two settings, exactly like in the test page.
  // Left as-is on purpose so the features match what you validated there.

  const shapeOf = (d) => (d && d.shape ? Array.from(d.shape) : null);

  // ---------- model loading ----------
  async function getLiteRt() {
    if (!litert) {
      const m = await import(cfg.litertBase + "/+esm");
      await m.loadLiteRt(cfg.litertBase + "/wasm/");
      litert = m;
    }
    return litert;
  }

  // Compile the model with the first accelerator in `accels` that works.
  async function compile(accels) {
    const m = await getLiteRt();
    let lastErr = null;
    for (const accel of accels) {
      try {
        if (accel === "webgpu") {
          if (!navigator.gpu) throw new Error("WebGPU is unavailable");
          const adapter = await navigator.gpu.requestAdapter();
          if (!adapter) throw new Error("no WebGPU adapter");
        }
        eyeModel = await m.loadAndCompile(cfg.modelUrl, { accelerator: accel });
        usedAccel = accel;
        LTensor = m.Tensor;
        return;
      } catch (e) {
        lastErr = e;
        console.warn(`YoloEye: ${accel} failed:`, e);
      }
    }
    throw lastErr || new Error("Eye model could not be loaded");
  }

  async function load() {
    const jr = await fetch(cfg.jsonUrl);
    if (!jr.ok) throw new Error(`Could not load ${cfg.jsonUrl} (HTTP ${jr.status})`);
    J = await jr.json();
    S = J.imgsz || 128;
    cc.width = cc.height = S;

    await compile(cfg.accelerators);

    info = `Eye model loaded (${usedAccel}).`;
    try {
      const inS = shapeOf(eyeModel.getInputDetails?.()[0]);
      if (inS && inS.length === 4) {
        NHWC = inS[3] === 3 && inS[1] !== 3;
        const ms = NHWC ? inS[1] : inS[2];
        info += `\nmodel input ${JSON.stringify(inS)} -> ${NHWC ? "NHWC" : "NCHW"}, page crop ${S}`;
        if (ms !== S) info += `\n!! model wants ${ms}px but eye_keypoint_names.json imgsz is ${S}`;
      }
    } catch (e) {
      console.warn("YoloEye: could not read model details:", e);
    }
    console.log(info);
  }

  // Called when the GPU resets mid-exam: drop the dead model, rebuild in the background.
  // In fusion mode the bubble keeps running on MediaPipe + the last bias while this happens.
  function handleGpuLoss(err) {
    if (recovering) return;
    gpuLosses++;
    console.error(`YoloEye: GPU device lost (#${gpuLosses}), recovering…`, err);

    const old = eyeModel;
    eyeModel = null;
    lastResult = null;
    try { old?.delete?.(); } catch (_) {}
    for (const k of Object.keys(trk)) delete trk[k];

    const accels = gpuLosses <= cfg.gpuRetries ? cfg.accelerators : ["wasm"];
    recovering = compile(accels)
      .then(() => console.warn(`YoloEye: recovered on ${usedAccel} after GPU reset #${gpuLosses}.`))
      .catch((e) => {
        failed = true;
        error = e;
        console.error("YoloEye: recovery failed:", e);
      })
      .finally(() => { recovering = null; });
  }

  function init(opts = {}) {
    Object.assign(cfg, opts);
    if (!initPromise) {
      initPromise = load().catch((e) => {
        error = e;
        initPromise = null; // allow a retry
        console.error("YoloEye init failed:", e);
        throw e;
      });
    }
    return initPromise;
  }

  // ---------- crop + inference ----------
  function eyeM(A, B, flip) {
    const cx = (A.x + B.x) / 2, cy = (A.y + B.y) / 2, w = Math.hypot(B.x - A.x, B.y - A.y), ang = Math.atan2(B.y - A.y, B.x - A.x);
    const s = S / (w * J.K), c = Math.cos(-ang), n = Math.sin(-ang), f = flip ? -1 : 1;
    const a = s * f * c, b = -s * f * n, d = s * n, e = s * c;
    return { M: [a, b, J.center_px[0] - (a * cx + b * cy), d, e, J.center_px[1] - (d * cx + e * cy)], w, ang };
  }
  function unmap(M, x, y) {
    const det = M[0] * M[4] - M[1] * M[3], dx = x - M[2], dy = y - M[5];
    return { x: (M[4] * dx - M[1] * dy) / det, y: (-M[3] * dx + M[0] * dy) / det };
  }
  function cropTensor(M) {
    cctx.setTransform(1, 0, 0, 1, 0, 0);
    cctx.fillStyle = "#727272";
    cctx.fillRect(0, 0, S, S);
    cctx.setTransform(M[0], M[3], M[1], M[4], M[2], M[5]);
    cctx.drawImage(V, 0, 0, V.videoWidth, V.videoHeight);
    const d = cctx.getImageData(0, 0, S, S).data, n = S * S, t = new Float32Array(3 * n);
    if (NHWC) for (let i = 0; i < n; i++) { t[3 * i] = d[4 * i] / 255; t[3 * i + 1] = d[4 * i + 1] / 255; t[3 * i + 2] = d[4 * i + 2] / 255; }
    else for (let i = 0; i < n; i++) { t[i] = d[4 * i] / 255; t[n + i] = d[4 * i + 1] / 255; t[2 * n + i] = d[4 * i + 2] / 255; }
    return t;
  }
  async function infer(t) {
    if (!eyeModel) throw new GpuLost("model not available");

    const inp = new LTensor(t, NHWC ? [1, S, S, 3] : [1, 3, S, S]);
    let out, f;
    try {
      out = await eyeModel.run([inp]);
      f = Float32Array.from(await out[0].data());
    } catch (e) {
      if (usedAccel === "webgpu" && isGpuLoss(e)) {
        handleGpuLoss(e);
        throw new GpuLost("GPU device lost");
      }
      throw e;
    } finally {
      try { inp.delete(); } catch (_) {}
      try { out && out.forEach((o) => o.delete()); } catch (_) {}
    }
    const NC = NK * 3;
    let rows, get, ks;
    if (f.length % (5 + NC) === 0 && f.length % (6 + NC) !== 0) { rows = f.length / (5 + NC); get = (r, c) => f[c * rows + r]; ks = 5; }
    else { rows = f.length / (6 + NC); get = (r, c) => f[r * (6 + NC) + c]; ks = 6; }
    let bi = 0, bs = -1;
    for (let r = 0; r < rows; r++) { const s = get(r, 4); if (s > bs) { bs = s; bi = r; } }
    lastScore = bs;
    if (bs < CONF) return null;
    const k = [];
    for (let j = 0; j < NK; j++) k.push([get(bi, ks + 3 * j), get(bi, ks + 3 * j + 1), get(bi, ks + 3 * j + 2)]);
    if (Math.max(...k.map((p) => Math.max(Math.abs(p[0]), Math.abs(p[1])))) <= 2) k.forEach((p) => { p[0] *= S; p[1] *= S; });
    return { score: bs, k };
  }
  async function runEye(lab, A, B) {
    const { M, w, ang } = eyeM(A, B, FLIP[lab]);
    const res = await infer(cropTensor(M));
    return res && { ...res, M, w, ang, flip: FLIP[lab], A, B };
  }
  // same eye, crop nudged by v = [shift x, shift y (eye-widths), zoom]
  function runVariant(lab, A, B, v) {
    const w = Math.hypot(B.x - A.x, B.y - A.y), cx = (A.x + B.x) / 2 + v[0] * w, cy = (A.y + B.y) / 2 + v[1] * w;
    const hx = ((B.x - A.x) / 2) * v[2], hy = ((B.y - A.y) / 2) * v[2];
    return runEye(lab, { x: cx - hx, y: cy - hy }, { x: cx + hx, y: cy + hy });
  }

  // OLD reference (cfg.ref === "yolo", fuse off): iris offset in IMAGE axes (eye-widths),
  // x vs YOLO corner midpoint, y vs centre of YOLO's lid opening
  function eyeOff(r) {
    const k = r.k, cl = k[J.idx.corner_left], cr = k[J.idx.corner_right];
    const wc = Math.max(Math.hypot(cr[0] - cl[0], cr[1] - cl[1]), 1);
    const mean = (ids) => [ids.reduce((s, i) => s + k[i][0], 0) / ids.length, ids.reduce((s, i) => s + k[i][1], 0) / ids.length];
    let yIds = J.iris_idx;
    if (IRIS_Y_NO_TB) { const side = yIds.filter((i) => !/top|bottom/.test(J.names[i])); if (side.length) yIds = side; }
    const irisX = mean(J.iris_idx)[0], irisY = mean(yIds)[1], up = mean(J.upper_idx), lo = mean(J.lower_idx);
    let fx = (irisX - (cl[0] + cr[0]) / 2) / wc;
    const fy = (irisY - (up[1] + lo[1]) / 2) / wc;
    if (r.flip) fx = -fx;
    const c = Math.cos(r.ang), s = Math.sin(r.ang); // undo the crop rotation -> camera axes
    return { ox: c * fx - s * fy, oy: s * fx + c * fy };
  }
  function eyeQuality(r) {
    const core = [...J.iris_idx, J.idx.corner_left, J.idx.corner_right];
    const kc = clamp(core.reduce((s, i) => s + r.k[i][2], 0) / core.length, 0, 1);
    return r.score * kc * clamp((r.ear - cfg.blinkEar) / 0.10, 0, 1);
  }

  // ---------- FUSION helpers ----------
  // MediaPipe eye-aspect-ratio for one eye (lid opening / eye width)
  const earOf = (lab, lm, W, H) => {
    const [a, b, u, l] = EYES[lab];
    return Math.hypot((lm[u].x - lm[l].x) * W, (lm[u].y - lm[l].y) * H) /
      (Math.hypot((lm[b].x - lm[a].x) * W, (lm[b].y - lm[a].y) * H) || 1);
  };
  // MediaPipe corner midpoint, eye width (px) and MediaPipe iris offset, all in camera pixels / image axes
  function mpGeom(lab, lm, W, H) {
    const [a, b] = EYES[lab], I = lm[IRIS[lab]];
    const ax = lm[a].x * W, ay = lm[a].y * H, bx = lm[b].x * W, by = lm[b].y * H;
    const w = Math.hypot(bx - ax, by - ay) || 1, mx = (ax + bx) / 2, my = (ay + by) / 2;
    return { w, mx, my, ox: (I.x * W - mx) / w, oy: (I.y * H - my) / w };
  }
  // YOLO iris centre in CAMERA pixels (along-eye from all iris points, across-eye from the side points only)
  function yoloIrisPx(r) {
    const k = r.k, mean = (ids, c) => ids.reduce((s, i) => s + k[i][c], 0) / ids.length;
    let yIds = J.iris_idx;
    if (IRIS_Y_NO_TB) { const side = yIds.filter((i) => !/top|bottom/.test(J.names[i])); if (side.length) yIds = side; }
    return unmap(r.M, mean(J.iris_idx, 0), mean(yIds, 1));
  }

  // Slowly-varying bias per eye: (YOLO iris - MediaPipe iris), both vs MediaPipe corners.
  const newFz = () => ({ bx: 0, by: 0, n: 0, t: 0, rej: 0, skip: 0, seed: [] });
  const fz = { L: newFz(), R: newFz() };
  let warmed = false, warmSince = 0;

  function fuseUpdate(lab, dx, dy, now, q, ear) {
    if (q < cfg.fuseMinQ || ear < cfg.fuseMinEar) return;
    const f = fz[lab];
    if (f.skip < cfg.fuseSkipFirst) { f.skip++; return; }
    if (f.n === 0) {
      f.seed.push([dx, dy]);
      if (f.seed.length > cfg.fuseSeedN) f.seed.shift();
      if (f.seed.length < cfg.fuseSeedN) return;
      const mx = med(f.seed.map((s) => s[0])), my = med(f.seed.map((s) => s[1]));
      const spread = Math.max(...f.seed.map((s) => Math.hypot(s[0] - mx, s[1] - my)));
      if (spread > cfg.fuseSeedSpread) return;
      f.bx = mx; f.by = my; f.n = cfg.fuseSeedN; f.t = now; f.rej = 0; f.seed = [];
      return;
    }
    if (Math.hypot(dx - f.bx, dy - f.by) > cfg.fuseGate) {
      if (++f.rej < 10) return;
      f.bx = dx; f.by = dy; f.n = 1; f.t = now; f.rej = 0;
      return;
    }
    f.rej = 0;
    const k = Math.max(1 - Math.exp(-(now - f.t) / cfg.fuseTau), 1 / (f.n + 1));
    f.bx += k * (dx - f.bx);
    f.by += k * (dy - f.by);
    f.n++;
    f.t = now;
  }

  // Every camera frame: MediaPipe iris + YOLO's bias, both eyes weighted by how open they are.
  function fusedFrame(lm, W, H) {
    const ready = Object.keys(EYES).filter((lab) => fz[lab].n > 0);
    if (!ready.length) return null;
    if (!warmed) {
      const now = performance.now();
      if (!warmSince) warmSince = now;
      if (ready.length < 2 && now - warmSince < cfg.fuseWarmMaxMs) return null;
      warmed = true;
    }
    let sx = 0, sy = 0, sp = 0, sw = 0;
    for (const lab of ready) {
      const f = fz[lab];
      const g = mpGeom(lab, lm, W, H);
      const wt = clamp((earOf(lab, lm, W, H) - cfg.blinkEar) / 0.10, 0.05, 1);
      sx += wt * (g.ox + f.bx);
      sy += wt * (g.oy + f.by);
      sp += wt * g.w;
      sw += wt;
    }
    return sw ? { ox: sx / sw, oy: sy / sw, eyePx: sp / sw } : null;
  }

  const trk = {}; // locked crop box per eye: { A, B (box corners, camera px), cA, cB (averaged raw corners), t, miss, rc }
  let busy = false; // prevent concurrent YOLO runs (one shared crop canvas)

  // Box that stays put. Returns the locked box; it only moves when the eye really moved.
  function lockBox(lab, A, B, now) {
    const L = trk[lab];
    if (!L || now - L.t > 500) return (trk[lab] = { A, B, cA: A, cB: B, t: now, miss: 0, rc: 0 }); // first frame / after a gap
    const k = 0.3; // light average of the raw corners so one noisy frame can't trigger a move
    L.cA = { x: L.cA.x + (A.x - L.cA.x) * k, y: L.cA.y + (A.y - L.cA.y) * k };
    L.cB = { x: L.cB.x + (B.x - L.cB.x) * k, y: L.cB.y + (B.y - L.cB.y) * k };
    L.t = now;
    const lw = Math.hypot(L.B.x - L.A.x, L.B.y - L.A.y) || 1;
    const cw = Math.hypot(L.cB.x - L.cA.x, L.cB.y - L.cA.y) || 1;
    const shift = Math.hypot((L.cA.x + L.cB.x - L.A.x - L.B.x) / 2, (L.cA.y + L.cB.y - L.A.y - L.B.y) / 2) / lw;
    let da = Math.atan2(L.cB.y - L.cA.y, L.cB.x - L.cA.x) - Math.atan2(L.B.y - L.A.y, L.B.x - L.A.x);
    da = Math.atan2(Math.sin(da), Math.cos(da));
    if (shift > cfg.boxMove || Math.abs(cw / lw - 1) > cfg.boxScale || Math.abs(da) > cfg.boxAngle) {
      L.A = L.cA; // the eye really moved: take the new position and hold it again
      L.B = L.cB;
    }
    return L;
  }

  // YOLO's own corners say the eye sits off-centre in the box: move the box onto them.
  function recenterBox(lab, r, A, B, now) {
    const L = trk[lab];
    if (!L || now - L.rc < 400) return; // (cooldown: never chase YOLO's corners every frame)
    const kl = r.k[J.idx.corner_left], kr = r.k[J.idx.corner_right];
    if (kl[2] < KCONF || kr[2] < KCONF) return;
    const p1 = unmap(r.M, kl[0], kl[1]), p2 = unmap(r.M, kr[0], kr[1]);
    const [A2, B2] = r.flip ? [p2, p1] : [p1, p2];
    const w = Math.hypot(B.x - A.x, B.y - A.y) || 1, w2 = Math.hypot(B2.x - A2.x, B2.y - A2.y);
    if (Math.abs(w2 / w - 1) > 0.3) return; // implausible corners
    const off = Math.hypot((A2.x + B2.x - A.x - B.x) / 2, (A2.y + B2.y - A.y - B.y) / 2) / w;
    if (off > cfg.boxRecenter) { L.A = A2; L.B = B2; L.cA = A2; L.cB = B2; L.rc = now; }
  }

  async function yoloEye(lab, [a, b, u, l], lm, W, H) {
    const P = (i) => ({ x: lm[i].x * W, y: lm[i].y * H });
    const ear = earOf(lab, lm, W, H);
    if (ear < cfg.blinkEar) { why += `${lab}: eye closed (ear ${ear.toFixed(2)}) `; return null; }
    const nowT = performance.now();
    const { A, B } = lockBox(lab, P(a), P(b), nowT); // stays put until the eye really moves
    let r = await runEye(lab, A, B);
    if (!r) {
      why += `${lab}: model score ${lastScore.toFixed(3)} < ${CONF} `;
      if (trk[lab] && ++trk[lab].miss >= cfg.boxMissMax) delete trk[lab]; // lost the eye: re-find it from the face landmarks
      return null;
    }
    if (trk[lab]) trk[lab].miss = 0;
    recenterBox(lab, r, A, B, nowT); // eye drifted off-centre in the box: re-centre on what YOLO found
    if (cfg.refine) {
      const p1 = unmap(r.M, ...r.k[J.idx.corner_left].slice(0, 2)), p2 = unmap(r.M, ...r.k[J.idx.corner_right].slice(0, 2));
      const [A2, B2] = r.flip ? [p2, p1] : [p1, p2];
      if (Math.abs(Math.hypot(B2.x - A2.x, B2.y - A2.y) / Math.hypot(B.x - A.x, B.y - A.y) - 1) < 0.3) {
        const r2 = await runEye(lab, A2, B2);
        if (r2 && r2.score >= r.score * 0.8) r = r2;
      }
    }
    const rs = [r]; // test-time averaging: nudged crops, same eye
    for (const v of VARS.slice(0, Math.max(0, cfg.tta - 1))) {
      const rv = await runVariant(lab, r.A, r.B, v);
      if (rv && rv.score >= r.score * 0.8) rs.push(rv);
    }
    rs.forEach((x) => (x.ear = ear));
    const offs = rs.map((x) => eyeOff(x)), mean = (k) => offs.reduce((s, o) => s + o[k], 0) / offs.length;
    let ox = mean("ox"), oy = mean("oy");
    const q = rs.reduce((s, x) => s + eyeQuality(x), 0) / rs.length;

    if (cfg.fuse || cfg.ref === "mp") {
      // Measure YOLO's iris against MediaPipe's corners instead of YOLO's own corners / lids.
      const g = mpGeom(lab, lm, W, H), p = yoloIrisPx(r);
      ox = (p.x - g.mx) / g.w;
      oy = (p.y - g.my) / g.w;
      if (cfg.fuse) fuseUpdate(lab, ox - g.ox, oy - g.oy, performance.now(), q, ear);
    }
    return { lab, ox, oy, q, r, eyePx: r.w };
  }
  async function yoloGaze(lm, W, H) {
    why = "";
    const per = [];
    for (const [lab, ids] of Object.entries(EYES)) { const e = await yoloEye(lab, ids, lm, W, H); if (e) per.push(e); }
    if (!per.length) return null;
    let use = per, note = per.length > 1 ? "eyes agree" : "one eye";
    // (non-fusion modes only matter here; in fusion mode the per-eye bias is already updated above)
    if (per.length === 2 && Math.abs(per[0].ox - per[1].ox) > cfg.disagree) { use = [per[0].q >= per[1].q ? per[0] : per[1]]; note = "DISAGREE -> " + use[0].lab; }
    const ws = use.map((p) => Math.max(p.q, 1e-3)), sw = ws.reduce((a, b) => a + b, 0);
    const avg = (k) => use.reduce((s, p, i) => s + p[k] * ws[i], 0) / sw;
    return { ox: avg("ox"), oy: avg("oy"), eyePx: avg("eyePx"), per, note };
  }

  // ---------- public: one frame -> raw features ----------
  // Same shape as GazeCore.extract (ear, yaw, pitch, roll, cx, cy, scale) except:
  //  - ox / oy are the EYE-ONLY iris offsets (head compensation happens in the smoother)
  //  - eyePx is the eye width in camera pixels (used to smooth small/far eyes harder)
  //  - null = no usable result yet
  let lastResult = null;

  // fusion mode: synchronous. YOLO is kicked off in the background and only updates the bias.
  function extractFused(lm, W, H, video) {
    if (eyeModel && !recovering && !failed && !busy) {
      busy = true;
      V = video;
      yoloGaze(lm, W, H)
        .then((g) => { lastGaze = g; })
        .catch((e) => { if (!(e instanceof GpuLost)) console.error("YOLO eye failed:", e); })
        .finally(() => { busy = false; });
    }
    const f = fusedFrame(lm, W, H);
    if (!f) return null; // no bias learned yet (first YOLO frame, or eyes closed so far)
    const h = GazeCore.extract(lm, W, H); // fresh head pose every frame
    return { ear: h.ear, ox: f.ox, oy: f.oy, yaw: h.yaw, pitch: h.pitch, roll: h.roll, cx: h.cx, cy: h.cy, scale: h.scale, eyePx: f.eyePx };
  }

  // non-fusion modes: original behaviour (async, features only update when YOLO finishes)
  async function extractYolo(lm, W, H, video) {
    if (recovering || failed) return null; // rebuilding (or dead): skip frames quietly
    if (!eyeModel) return lastResult;
    if (busy) return lastResult;

    busy = true;
    try {
      V = video;
      const g = await yoloGaze(lm, W, H);
      lastGaze = g;
      if (!g) return lastResult;
      const h = GazeCore.extract(lm, W, H);
      lastResult = { ear: h.ear, ox: g.ox, oy: g.oy, yaw: h.yaw, pitch: h.pitch, roll: h.roll, cx: h.cx, cy: h.cy, scale: h.scale, eyePx: g.eyePx };
      return lastResult;
    } catch (e) {
      if (e instanceof GpuLost) return null; // recovery already started; just skip this frame
      throw e;
    } finally {
      busy = false;
    }
  }

  const extract = (lm, W, H, video) => (cfg.fuse ? extractFused(lm, W, H, video) : extractYolo(lm, W, H, video));

  // forget learned bias + crop tracker (call after the face was gone for a while)
  function reset() {
    fz.L = newFz();
    fz.R = newFz();
    warmed = false;
    warmSince = 0;
    for (const k of Object.keys(trk)) delete trk[k];
    lastResult = null;
  }

  // ---------- smoothing (drop-in for GazeCore.makeSmoother) ----------
  // 1 Euro filter: heavy smoothing while the eye is still (kills jitter), light while it moves (no lag)
  class OneEuro {
    constructor() { this.x = null; this.dx = 0; this.t = 0; }
    static a(c, dt) { return 1 / (1 + 1 / (2 * Math.PI * c) / dt); }
    f(x, t, minC, beta) {
      if (this.x === null) { this.x = x; this.t = t; return x; }
      const dt = Math.max((t - this.t) / 1000, 1e-3);
      this.t = t;
      this.dx += OneEuro.a(1, dt) * ((x - this.x) / dt - this.dx);
      this.x += OneEuro.a(minC + beta * Math.abs(this.dx), dt) * (x - this.x);
      return this.x;
    }
  }

  function makeSmoother(tauMs = 250, avgN = 9) {
    const s = { init: false, t: 0 };
    let hist = { ox: [], oy: [] };
    let euro = { ox: new OneEuro(), oy: new OneEuro() };
    const fn = (raw, now) => {
      // Head-compensate each frame FIRST (same frame as the eye measurement), then filter the combined signal.
      // Subtracting a separately smoothed yaw/pitch made the dot swing whenever the head moved, because the
      // head filter and the eye filter lag by different amounts. Steady-state values are unchanged.
      const r = { ...raw, ox: raw.ox - EYE_PER_RAD * raw.yaw, oy: raw.oy - EYE_PER_RAD * raw.pitch };
      for (const k of ["ox", "oy"]) {
        hist[k].push(r[k]);
        if (hist[k].length > avgN) hist[k].shift(); // configurable frame window
        const h = hist[k];
        // Use a mean for the short calibration/exam windows; retain median outlier rejection for longer windows.
        r[k] = avgN <= 3 ? h.reduce((a, b) => a + b, 0) / h.length : med(h);
      }
      if (!s.init) { HEAD.forEach((k) => (s[k] = r[k])); s.init = true; s.t = now; }
      const a = 1 - Math.exp(-(now - s.t) / tauMs);
      s.t = now;
      HEAD.forEach((k) => (s[k] += (r[k] - s[k]) * a)); // head features: plain smoothing
      const mc = cfg.minCut * clamp((raw.eyePx || REF_EYE_PX) / REF_EYE_PX, 0.4, 1); // small/far eyes -> steadier
      const eox = euro.ox.f(r.ox, now, mc, cfg.beta), eoy = euro.oy.f(r.oy, now, mc, cfg.beta);
      // cheek-to-cheek width shrinks by cos(yaw) when the head turns: undo that so a head turn isn't read as "farther away"
      const scaleEff = s.scale / Math.max(Math.cos(s.yaw), 0.6);
      const ratio = cfg.distanceComp ? clamp(SCALE_REF / scaleEff, 0.4, 2.5) : 1; // screen offset grows with distance
      s.ox = eox * ratio; // eox/eoy are already head-compensated (see above)
      s.oy = eoy * ratio;
      s.ratio = ratio;
      return s;
    };
    fn.reset = () => {
      s.init = false;
      hist = { ox: [], oy: [] };
      euro = { ox: new OneEuro(), oy: new OneEuro() };
    };
    return fn;
  }

  // ---------- helpers ----------
  // Settings that change what the features MEAN. Saved with the calibration and re-applied by the exam.
  const exportCfg = () => ({ refine: cfg.refine, tta: cfg.tta, distanceComp: cfg.distanceComp, fuse: cfg.fuse, ref: cfg.ref });
  function applyCfg(c) {
    if (!c) return;
    for (const k of ["refine", "tta", "distanceComp", "fuse", "ref"]) if (c[k] !== undefined) cfg[k] = c[k];
  }

  // draw the model keypoints of the last frame; sx, sy = canvas px per camera px
  function drawKeypoints(ctx, g = lastGaze, sx = 1, sy = 1) {
    if (!g) return;
    g.per.forEach((p) => p.r.k.forEach((k, j) => {
      if (k[2] < KCONF) return;
      const q = unmap(p.r.M, k[0], k[1]);
      ctx.fillStyle = `hsl(${j * 27},90%,60%)`;
      ctx.beginPath();
      ctx.arc(q.x * sx, q.y * sy, 2.5, 0, 7);
      ctx.fill();
    }));
  }

  return {
    cfg, init, extract, reset, makeSmoother, exportCfg, applyCfg, drawKeypoints,
    get ready() { return !!eyeModel; },
    isReady() { return !!eyeModel; }, // alias
    isBusy() { return busy; }, // YOLO is processing a frame (in fusion mode this does NOT block features)
    get error() { return error; },
    get info() { return info; },
    get why() { return why; },
    get lastGaze() { return lastGaze; },
    get fusion() { return { L: { ...fz.L }, R: { ...fz.R } }; }, // debug: learned bias per eye (eye-widths)
    get accelerator() { return usedAccel; },
    get status() { return failed ? "failed" : recovering ? "recovering" : eyeModel ? "ok" : "loading"; },
    get gpuLosses() { return gpuLosses; },
  };
})();