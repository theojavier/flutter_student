// yolo-eye.js — YOLO eyelid/iris keypoints (LiteRT .tflite) for the gaze pipeline.
// Load order:  gaze-core.js  ->  yolo-eye.js  ->  gaze-calibration.js / exam-gaze-block.js
//
// MediaPipe still finds the face, eye corners and head pose (GazeCore.extract).
// This module only replaces the iris-offset part (ox, oy) with the YOLO keypoints, using the
// same maths as gaze-test-9ptyolo.html. Calibration and exam MUST both use this module.
//
//   await YoloEye.init();                                   // load model once (safe to call many times)
//   const raw = await YoloEye.extract(lm, W, H, videoEl);   // null = no usable eye result this frame
//   const smooth = YoloEye.makeSmoother(250);               // drop-in for GazeCore.makeSmoother
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
    disagree: 0.10, // ox difference threshold: above this, pick best eye instead of averaging
    minCut: 0.5, // VERY LOW: maximum smoothing when still
    beta: 4, // VERY LOW: minimal reaction to noise
    boxSmoothing: 0.85, // MAXIMUM: very stable box
    gpuRetries: 0, // 0 = go straight to CPU after GPU reset
  };

  const NK = 13, CONF = 0.05, KCONF = 0.30, DISAGREE = 0.10;
  const VARS = [[0.025, -0.02, 1.03], [-0.025, 0.02, 0.97]]; // extra crops: shift (x, y in eye-widths) and zoom
  const IRIS_Y_NO_TB = true; // vertical gaze ignores the noisy iris top/bottom points
  const FLIP = { L: false, R: true };
  const EYES = { L: [33, 133, 159, 145], R: [362, 263, 386, 374] };
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

  // iris offset in IMAGE axes (eye-widths): x vs corner midpoint, y vs centre of the lid opening
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

  const trk = {}; // smoothed MediaPipe corners per eye (a steadier crop)
  let busy = false; // prevent concurrent extract calls
  
  async function yoloEye(lab, [a, b, u, l], lm, W, H) {
    const P = (i) => ({ x: lm[i].x * W, y: lm[i].y * H });
    const ear = Math.hypot((lm[u].x - lm[l].x) * W, (lm[u].y - lm[l].y) * H) / Math.hypot((lm[b].x - lm[a].x) * W, (lm[b].y - lm[a].y) * H);
    if (ear < cfg.blinkEar) { why += `${lab}: eye closed (ear ${ear.toFixed(2)}) `; return null; }
    let A = P(a), B = P(b);
    const t = trk[lab];
    if (t) { 
      // Smooth the box position to reduce jitter
      const alpha = cfg.boxSmoothing;
      A = { x: t.A.x + (A.x - t.A.x) * (1 - alpha), y: t.A.y + (A.y - t.A.y) * (1 - alpha) }; 
      B = { x: t.B.x + (B.x - t.B.x) * (1 - alpha), y: t.B.y + (B.y - t.B.y) * (1 - alpha) }; 
    }
    trk[lab] = { A, B };
    let r = await runEye(lab, A, B);
    if (!r) { why += `${lab}: model score ${lastScore.toFixed(3)} < ${CONF} `; return null; }
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
    return { lab, ox: mean("ox"), oy: mean("oy"), q: rs.reduce((s, x) => s + eyeQuality(x), 0) / rs.length, r, eyePx: r.w };
  }
  async function yoloGaze(lm, W, H) {
    why = "";
    const per = [];
    for (const [lab, ids] of Object.entries(EYES)) { const e = await yoloEye(lab, ids, lm, W, H); if (e) per.push(e); }
    if (!per.length) return null;
    let use = per, note = per.length > 1 ? "eyes agree" : "one eye";
    // Use configurable disagree threshold (0.10 calibration, 0.2 exam = less switching)
    if (per.length === 2 && Math.abs(per[0].ox - per[1].ox) > cfg.disagree) { use = [per[0].q >= per[1].q ? per[0] : per[1]]; note = "DISAGREE -> " + use[0].lab; }
    const ws = use.map((p) => Math.max(p.q, 1e-3)), sw = ws.reduce((a, b) => a + b, 0);
    const avg = (k) => use.reduce((s, p, i) => s + p[k] * ws[i], 0) / sw;
    return { ox: avg("ox"), oy: avg("oy"), eyePx: avg("eyePx"), per, note };
  }

  // ---------- public: one frame -> raw features ----------
  // Same shape as GazeCore.extract (ear, yaw, pitch, roll, cx, cy, scale) except:
  //  - ox / oy are the EYE-ONLY iris offsets from YOLO (head compensation happens in the smoother)
  //  - eyePx is the eye width in camera pixels (used to smooth small/far eyes harder)
  //  - returns null when YOLO has no usable result (blink, low score, model not loaded yet, OR still processing previous frame)
  // Call it from ONE place at a time (use a busy flag in onResults) — it shares one crop canvas.
  let lastResult = null;
  async function extract(lm, W, H, video) {
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
      const r = { ...raw };
      for (const k of ["ox", "oy"]) {
        hist[k].push(r[k]);
        if (hist[k].length > avgN) hist[k].shift(); // configurable window (9 for calibration, 2 for exam)
        const h = hist[k];
        // For 2 frames: use mean instead of median to avoid bias (median of 2 = always pick larger)
        r[k] = avgN <= 2 ? h.reduce((a, b) => a + b, 0) / h.length : med(h);
      }
      if (!s.init) { HEAD.forEach((k) => (s[k] = r[k])); s.init = true; s.t = now; }
      const a = 1 - Math.exp(-(now - s.t) / tauMs);
      s.t = now;
      HEAD.forEach((k) => (s[k] += (r[k] - s[k]) * a)); // head features: plain smoothing
      const mc = cfg.minCut * clamp((raw.eyePx || REF_EYE_PX) / REF_EYE_PX, 0.4, 1); // small/far eyes -> steadier
      const eox = euro.ox.f(r.ox, now, mc, cfg.beta), eoy = euro.oy.f(r.oy, now, mc, cfg.beta);
      const ratio = cfg.distanceComp ? clamp(SCALE_REF / s.scale, 0.4, 2.5) : 1; // screen offset grows with distance
      s.ox = (eox - EYE_PER_RAD * s.yaw) * ratio;
      s.oy = (eoy - EYE_PER_RAD * s.pitch) * ratio;
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
  const exportCfg = () => ({ refine: cfg.refine, tta: cfg.tta, distanceComp: cfg.distanceComp });
  function applyCfg(c) {
    if (!c) return;
    for (const k of ["refine", "tta", "distanceComp"]) if (c[k] !== undefined) cfg[k] = c[k];
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
    cfg, init, extract, makeSmoother, exportCfg, applyCfg, drawKeypoints,
    get ready() { return !!eyeModel; },
    isReady() { return !!eyeModel; }, // alias
    isBusy() { return busy; }, // check if processing frame
    get error() { return error; },
    get info() { return info; },
    get why() { return why; },
    get lastGaze() { return lastGaze; },
    get accelerator() { return usedAccel; },
    get status() { return failed ? "failed" : recovering ? "recovering" : eyeModel ? "ok" : "loading"; },
    get gpuLosses() { return gpuLosses; },
  };
})();
