// gaze-core.js — shared by gaze-calibration.html and exam.html
// Load it BEFORE each page's own script:  <script src="gaze-core.js"></script>
//
// Idea: screen position = f(eye-in-head) + g(head pose / head position).
// The old code only learned f and then added a hand-tuned head term. Here BOTH
// parts are learned from data, so the head term is correct by construction.

const GazeCore = (() => {
  const VERSION = 4; // calibration rows are required for online click learning + YOLO features differ from MediaPipe
  const R_EYE = { a: 33, b: 133, iris: 468, up: 159, low: 145 };
  const L_EYE = { a: 362, b: 263, iris: 473, up: 386, low: 374 };

  const HEAD_KEYS = ["yaw", "pitch", "roll", "cx", "cy", "scale"];
  const KEYS = ["ox", "oy", ...HEAD_KEYS];
  const RIDGE_EYE = 0.02;
  const RIDGE_HEAD = 0.3; // head terms are regularised harder
  const HEAD_CLAMP = 3; // std-devs; stops wild extrapolation on extreme poses
  // Minimum "typical spread" per head feature (yaw,pitch,roll rad; cx,cy,scale frame fractions).
  // Without head-move data the calibration rows barely vary in these, and dividing by a tiny
  // std-dev would amplify noise. With the floor the head terms stay ~0 until real data arrives.
  const HEAD_SD_FLOOR = [0.1, 0.1, 0.1, 0.05, 0.05, 0.03];

  // ---------- small vector helpers ----------
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const dot3 = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const cross = (a, b) => [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
  const unit = (a) => {
    const n = Math.hypot(a[0], a[1], a[2]) || 1;
    return [a[0] / n, a[1] / n, a[2] / n];
  };
  const med = (a) => {
    const s = [...a].sort((x, y) => x - y);
    return s[s.length >> 1];
  };

  // ---------- features ----------
  // Iris offset from the eye-corner midpoint, in IMAGE axes, as a fraction of eye width.
  // (Image axes, not eye-corner axes: when the head rolls, the eyeball keeps pointing at
  // the same screen spot, so the image-frame offset stays put. The old eye-axis
  // projection rotated with the head and dragged the bubble.)
  function eyeOffset(lm, e, W, H) {
    const A = lm[e.a], B = lm[e.b], I = lm[e.iris];
    const ax = A.x * W, ay = A.y * H, bx = B.x * W, by = B.y * H;
    const w = Math.hypot(bx - ax, by - ay) || 1;
    return {
      ox: (I.x * W - (ax + bx) / 2) / w,
      oy: (I.y * H - (ay + by) / 2) / w,
      ear:
        Math.hypot(
          (lm[e.up].x - lm[e.low].x) * W,
          (lm[e.up].y - lm[e.low].y) * H,
        ) / w,
    };
  }

  // 3D head orientation from cheeks (234,454) + forehead/chin (10,152), plus
  // where the face sits in the frame (cx, cy) and how big it is (scale ~ distance).
  function headFeatures(lm, W, H) {
    const P = (i) => [lm[i].x * W, lm[i].y * H, lm[i].z * W];
    const L = P(234), R = P(454), T = P(10), C = P(152);
    const xAxis = unit(sub(R, L));
    const yRaw = sub(C, T);
    const k = dot3(yRaw, xAxis);
    const yAxis = unit([
      yRaw[0] - k * xAxis[0],
      yRaw[1] - k * xAxis[1],
      yRaw[2] - k * xAxis[2],
    ]);
    const zAxis = cross(xAxis, yAxis);
    return {
      yaw: Math.atan2(zAxis[0], zAxis[2]),
      pitch: Math.atan2(zAxis[1], Math.hypot(zAxis[0], zAxis[2])),
      roll: Math.atan2(xAxis[1], xAxis[0]),
      cx: (L[0] + R[0]) / 2 / W - 0.5,
      cy: (T[1] + C[1]) / 2 / H - 0.5,
      scale: Math.hypot(R[0] - L[0], R[1] - L[1]) / W,
    };
  }

  // Geometric head normalisation (no training needed).
  // Gaze direction = eye-in-head angle + head angle. Turning the head by θ makes the eyes
  // counter-rotate to keep a fixation, shifting the iris by about (eyeball radius / eye width)·θ
  // ≈ 12mm / 30mm ≈ 0.4 eye-widths per radian. Subtracting that gives an iris offset that
  // describes where the eyes point in the CAMERA frame, whatever the head is doing.
  // Rough constant: if the bubble still moves when you turn your head while fixating a dot,
  // raise/lower it (and recalibrate — calibration and exam must use the same value).
  const EYE_PER_RAD = 0.4;

  function extract(lm, W, H) {
    const r = eyeOffset(lm, R_EYE, W, H);
    const l = eyeOffset(lm, L_EYE, W, H);
    const head = headFeatures(lm, W, H);
    return {
      ear: Math.min(r.ear, l.ear),
      ox: (r.ox + l.ox) / 2 - EYE_PER_RAD * head.yaw,
      oy: (r.oy + l.oy) / 2 - EYE_PER_RAD * head.pitch,
      ...head,
    };
  }

  // time-based exponential smoothing over all features
  function makeSmoother(tauMs = 250) {
    const s = { init: false, t: 0 };
    const fn = (raw, now) => {
      if (!s.init) {
        KEYS.forEach((k) => (s[k] = raw[k]));
        s.init = true;
        s.t = now;
        return s;
      }
      const a = 1 - Math.exp(-(now - s.t) / tauMs);
      s.t = now;
      KEYS.forEach((k) => (s[k] += (raw[k] - s[k]) * a));
      return s;
    };
    fn.reset = () => {
      s.init = false;
    };
    return fn;
  }

  // ---------- model: quadratic (or linear) in the eye, linear in the head ----------
  const nEyeTerms = (quad) => (quad ? 6 : 3);
  function feats(s, quad) {
    const eye = quad
      ? [1, s.ox, s.oy, s.ox * s.ox, s.oy * s.oy, s.ox * s.oy]
      : [1, s.ox, s.oy];
    return eye.concat(HEAD_KEYS.map((k) => s[k]));
  }

  function solve(A, b) {
    const n = b.length;
    for (let i = 0; i < n; i++) {
      let p = i;
      for (let r = i + 1; r < n; r++)
        if (Math.abs(A[r][i]) > Math.abs(A[p][i])) p = r;
      [A[i], A[p]] = [A[p], A[i]];
      [b[i], b[p]] = [b[p], b[i]];
      for (let r = i + 1; r < n; r++) {
        const f = A[r][i] / A[i][i];
        for (let c = i; c < n; c++) A[r][c] -= f * A[i][c];
        b[r] -= f * b[i];
      }
    }
    const x = Array(n).fill(0);
    for (let i = n - 1; i >= 0; i--) {
      let s = b[i];
      for (let c = i + 1; c < n; c++) s -= A[i][c] * x[c];
      x[i] = s / A[i][i];
    }
    return x;
  }

  // rows: [{ox,oy,yaw,pitch,roll,cx,cy,scale, sx,sy (target in 0..1), spot}]
  function fit(rows, quad) {
    const F = rows.map((r) => feats(r, quad));
    const wts = rows.map((r) => r.w ?? 1); // optional per-row weight
    const k = F[0].length, n = wts.reduce((a, b) => a + b, 0), nEye = nEyeTerms(quad);
    const mu = Array(k).fill(0), sd = Array(k).fill(1);
    for (let j = 1; j < k; j++) {
      mu[j] = F.reduce((s, f, i) => s + wts[i] * f[j], 0) / n;
      sd[j] =
        Math.sqrt(F.reduce((s, f, i) => s + wts[i] * (f[j] - mu[j]) ** 2, 0) / n) || 1;
      if (j >= nEye) sd[j] = Math.max(sd[j], HEAD_SD_FLOOR[j - nEye]);
    }
    const Z = F.map((f) => f.map((v, j) => (j ? (v - mu[j]) / sd[j] : 1)));
    const lambda = (j) => (j === 0 ? 0 : j < nEye ? RIDGE_EYE : RIDGE_HEAD) * n;
    const fitOne = (key) => {
      const A = Array.from({ length: k }, () => Array(k).fill(0));
      const b = Array(k).fill(0);
      Z.forEach((z, i) => {
        const wt = wts[i];
        for (let p = 0; p < k; p++) {
          b[p] += wt * z[p] * rows[i][key];
          for (let q = 0; q < k; q++) A[p][q] += wt * z[p] * z[q];
        }
      });
      for (let p = 1; p < k; p++) A[p][p] += lambda(p);
      return solve(A, b);
    };
    return { quad, mu, sd, wx: fitOne("sx"), wy: fitOne("sy") };
  }

  function predict(m, s) {
    const nEye = nEyeTerms(m.quad);
    const z = feats(s, m.quad).map((v, j) => {
      if (!j) return 1;
      const t = (v - m.mu[j]) / m.sd[j];
      return j >= nEye ? Math.max(-HEAD_CLAMP, Math.min(HEAD_CLAMP, t)) : t;
    });
    const d = (w) => z.reduce((s, v, j) => s + v * w[j], 0);
    return { x: d(m.wx), y: d(m.wy) };
  }

  // ---------- validation helpers ----------
  const pxErr = (r, m) => {
    const p = predict(m, r);
    return Math.hypot((p.x - r.sx) * innerWidth, (p.y - r.sy) * innerHeight);
  };
  const trainErr = (rows, m) => rows.reduce((s, r) => s + pxErr(r, m), 0) / rows.length;

  // leave-one-screen-position-out (still + head-move samples of a position leave together)
  function looErr(rows, quad) {
    let sum = 0, n = 0;
    for (const s of new Set(rows.map((r) => r.spot))) {
      const m = fit(rows.filter((r) => r.spot !== s), quad);
      const test = rows.filter((r) => r.spot === s);
      const preds = test.map((r) => predict(m, r));
      const x = med(preds.map((p) => p.x)), y = med(preds.map((p) => p.y));
      sum += Math.hypot((x - test[0].sx) * innerWidth, (y - test[0].sy) * innerHeight);
      n++;
    }
    return sum / n;
  }

  function loadCalibration() {
    try {
      const d = JSON.parse(localStorage.getItem("gazeCalibrationData"));
      return d && d.version === VERSION ? d : null;
    } catch (_) {
      return null;
    }
  }

  // ---------- online learning from clicks ----------
  const range = (a) => Math.max(...a) - Math.min(...a);
  const snapshot = (f) => {
    const o = {};
    KEYS.forEach((k) => (o[k] = f[k]));
    return o;
  };

  // Every real click on an answer / Next button is a labeled sample: the student was looking
  // at the click position just before pressing. We keep the last 2s of smoothed features,
  // take the stable fixation window just before the click, and refit with the calibration rows.
  // Returns null if the saved calibration has no rows (old calibration).
  function createOnline(calData, opts = {}) {
    if (!calData || !Array.isArray(calData.rows) || !calData.rows.length) return null;
    const o = {
      winFromMs: 600, // use frames from 600ms ... 150ms before the click
      winToMs: 150,
      minFrames: 4,
      maxSpreadPx: 150, // fixation must be stable (model-predicted spread)
      gatePx: Math.max(350, 3 * (calData.accuracy || 0)), // reject clicks far from what the model sees
      clickWeight: 4, // a clean averaged click ≈ 4 raw calibration frames
      maxClicks: 40, // keep the most recent N
      minClicks: 5,
      refitEvery: 5,
      ...opts,
    };
    const quad = calData.best !== "lin";
    let model = quad ? calData.modelQuad : calData.modelLin;
    if (!model) return null;
    const featureKeys = [...KEYS, ...HEAD_KEYS];
    const base = calData.rows
      .filter((r) =>
        r &&
        featureKeys.every((k) => Number.isFinite(r[k])) &&
        Number.isFinite(r.sx) &&
        Number.isFinite(r.sy),
      )
      .map((r) => ({ ...r, w: 10 })); // Calibration dots have weight 10 (was 1). Prevents clicks from overpowering edges after ~5 answers.
    if (!base.length) return null;
    const baseTrain = trainErr(base, model);
    let clicks = [];
    let accepted = 0;
    const buf = [];

    function push(f, now) {
      buf.push({ t: now, f: snapshot(f) });
      while (buf.length && now - buf[0].t > 2000) buf.shift();
    }

    function refit(nextClicks = clicks) {
      const m = fit([...base, ...nextClicks], quad);
      // safety: the new model must still explain the calibration dots reasonably
      if (trainErr(base, m) > 1.6 * baseTrain + 40) return false;
      model = m;
      return true;
    }

    function addClick(x, y, now) {
      if (
        !Number.isFinite(x) ||
        !Number.isFinite(y) ||
        !Number.isFinite(now) ||
        innerWidth <= 0 ||
        innerHeight <= 0 ||
        x < 0 ||
        x > innerWidth ||
        y < 0 ||
        y > innerHeight
      ) return "invalid-click";
      const frames = buf.filter((b) => now - b.t >= o.winToMs && now - b.t <= o.winFromMs);
      if (frames.length < o.minFrames) return "too-few-frames";
      const preds = frames.map((b) => predict(model, b.f));
      const px = preds.map((p) => p.x * innerWidth);
      const py = preds.map((p) => p.y * innerHeight);
      if (range(px) > o.maxSpreadPx || range(py) > o.maxSpreadPx) return "unstable";
      if (Math.hypot(med(px) - x, med(py) - y) > o.gatePx) return "outlier";
      const feat = {};
      KEYS.forEach((k) => (feat[k] = med(frames.map((b) => b.f[k]))));
      HEAD_KEYS.forEach((k) => (feat[k] = med(frames.map((b) => b.f[k]))));
      const nextClicks = [
        ...clicks,
        { ...feat, sx: x / innerWidth, sy: y / innerHeight, spot: -1, w: o.clickWeight },
      ].slice(-o.maxClicks);
      const nextAccepted = accepted + 1;
      if (
        nextAccepted >= o.minClicks &&
        nextAccepted % o.refitEvery === 0 &&
        !refit(nextClicks)
      ) return "refit-rejected";
      clicks = nextClicks;
      accepted = nextAccepted;
      return "ok";
    }

    return {
      push,
      addClick,
      getModel: () => model,
      exportClicks: () => clicks,
      importClicks: (arr) => {
        const safeClicks = Array.isArray(arr)
          ? arr
              .filter((r) =>
                r &&
                featureKeys.every((k) => Number.isFinite(r[k])) &&
                Number.isFinite(r.sx) &&
                Number.isFinite(r.sy) &&
                r.sx >= 0 &&
                r.sx <= 1 &&
                r.sy >= 0 &&
                r.sy <= 1,
              )
              .map((r) => ({
                ...snapshot(r),
                sx: r.sx,
                sy: r.sy,
                spot: -1,
                w: o.clickWeight,
              }))
              .slice(-o.maxClicks)
          : [];
        if (safeClicks.length >= o.minClicks && !refit(safeClicks)) {
          clicks = [];
          accepted = 0;
          return 0;
        }
        clicks = safeClicks;
        accepted = clicks.length;
        return clicks.length;
        if (clicks.length >= o.minClicks) refit();
      },
    };
  }

  return {
    VERSION, extract, makeSmoother, fit, predict,
    trainErr, looErr, loadCalibration, med, createOnline,
  };
})();