// gaze-calibration.js — replaces the last inline <script> of gaze-calibration.html
// Requires gaze-core.js (loaded first) and the same element ids as before.
console.log("🎯 Gaze calibration (head-aware) loaded");

const $ = (id) => document.getElementById(id);
const video = $("video"), canvas = $("canvas"), ctx = canvas.getContext("2d");
const dot = $("dot"), calMessage = $("calMessage"), feedbackMessage = $("feedbackMessage");
const calibrationOverlay = $("calibrationOverlay"), mainScreen = $("mainScreen");
const startBtn = $("startBtn"), startLabel = $("startLabel");

const med = GazeCore.med;
const range = (a) => Math.max(...a) - Math.min(...a);

// ---------------- plan ----------------
const G = [0.08, 0.5, 0.92];
const ORDER = [
  [G[1], G[1]], // 0 center
  [G[0], G[0]], [G[2], G[0]], [G[2], G[2]], [G[0], G[2]], // corners
  [G[1], G[0]], [G[2], G[1]], [G[1], G[2]], [G[0], G[1]], // edges
];
const PLAN = ORDER.map((_, spot) => ({ spot }));

const SETTLE = 700, COLLECT = 1000;
const MIN_SAMPLES = 12;
const SMOOTH_TAU_MS = 250, BLINK_EAR = 0.14;
const MAX_TRAIN_PX = 220;
const MAX_GAZE_MOVEMENT = 0.18; // eye widths (still stage only)
const MAX_HEAD_MOVEMENT = 0.12; // radians ≈ 7° (still stage only)
const smooth = GazeCore.makeSmoother(SMOOTH_TAU_MS);

const cal = {
  active: false, i: 0, t0: 0, phase: "", samples: [], rows: [],
  fx: 0, fy: 0, invalidAttempts: 0, maxInvalidAttempts: 3,
  modelFails: 0, restartAll: false,
  baselineGaze: null, baselineHead: null, lastFeedback: "",
};

// ---------------- feedback ----------------
function showFeedback(message, type = "warning") {
  if (cal.lastFeedback === message) return;
  cal.lastFeedback = message;
  feedbackMessage.textContent = message;
  feedbackMessage.className = type === "error" ? "error show" : "warning show";
  setTimeout(() => {
    if (cal.lastFeedback === message) {
      feedbackMessage.classList.remove("show");
      cal.lastFeedback = "";
    }
  }, 2000);
}
function clearFeedback() {
  feedbackMessage.classList.remove("show");
  cal.lastFeedback = "";
}

function checkRealtimeMovement(s) {
  if (!cal.active || cal.phase !== "collect") return;
  if (!cal.baselineGaze) {
    cal.baselineGaze = { ox: s.ox, oy: s.oy };
    cal.baselineHead = { yaw: s.yaw, pitch: s.pitch, roll: s.roll };
    clearFeedback();
    return;
  }
  const gazeDrift = Math.max(
    Math.abs(s.ox - cal.baselineGaze.ox),
    Math.abs(s.oy - cal.baselineGaze.oy),
  );
  const headMove = Math.max(
    Math.abs(s.yaw - cal.baselineHead.yaw),
    Math.abs(s.pitch - cal.baselineHead.pitch),
    Math.abs(s.roll - cal.baselineHead.roll),
  );
  if (headMove > MAX_HEAD_MOVEMENT * 0.7) showFeedback("⚠️ Keep your head still!", "error");
  else if (gazeDrift > MAX_GAZE_MOVEMENT * 0.7) showFeedback("⚠️ Keep looking at the dot!", "error");
  else if (headMove > MAX_HEAD_MOVEMENT * 0.4) showFeedback("Head moving - try to stay still", "warning");
  else if (gazeDrift > MAX_GAZE_MOVEMENT * 0.4) showFeedback("Eyes drifting - focus on the dot", "warning");
  else if (cal.samples.length > 5) clearFeedback();
}

// ---------------- validation ----------------
function validateSamples(samples) {
  if (samples.length < MIN_SAMPLES)
    return { valid: false, reason: `Not enough samples (${samples.length} of ${MIN_SAMPLES}). Is your face fully visible?` };

  const gaze = Math.max(range(samples.map((s) => s.ox)), range(samples.map((s) => s.oy)));
  if (gaze > MAX_GAZE_MOVEMENT)
    return { valid: false, reason: `Eyes moved too much! Keep looking at the dot.\n(gaze movement: ${(gaze * 100).toFixed(1)}% - limit: ${MAX_GAZE_MOVEMENT * 100}%)` };

  const head = Math.max(
    range(samples.map((s) => s.yaw)),
    range(samples.map((s) => s.pitch)),
    range(samples.map((s) => s.roll)),
  );
  if (head > MAX_HEAD_MOVEMENT)
    return { valid: false, reason: `Head moved too much! Keep your head still.\n(head movement: ${((head * 180) / Math.PI).toFixed(1)}° - limit: ${((MAX_HEAD_MOVEMENT * 180) / Math.PI).toFixed(0)}°)` };

  return { valid: true };
}

function validateFinalModel(rows, train) {
  if (train > MAX_TRAIN_PX)
    return { valid: false, reason: `Calibration accuracy too low!\nError: ${train.toFixed(0)}px (max acceptable: ${MAX_TRAIN_PX}px)\n\nPlease look directly at each dot.` };

  const unique = new Set(
    rows.filter((r) => r.stage === "still").map((r) => `${r.ox.toFixed(2)},${r.oy.toFixed(2)}`),
  );
  if (unique.size < 7)
    return { valid: false, reason: `Not enough variation in gaze!\nOnly ${unique.size} distinct positions detected.\n\nPlease look at each dot carefully.` };

  return { valid: true };
}

function showCalibrationError(message) {
  calMessage.innerHTML = `
    <div style="background: rgba(255,107,107,0.2); border: 2px solid #ff6b6b; border-radius: 8px; padding: 16px; max-width: 500px; margin: 0 auto;">
      <div style="font-size: 20px; margin-bottom: 8px;">⚠️ Calibration Failed</div>
      <div style="font-size: 14px; line-height: 1.5; white-space: pre-line;">${message}</div>
      <div style="margin-top: 12px; font-size: 13px; color: #ffa0a0;">Attempt ${cal.invalidAttempts} of ${cal.maxInvalidAttempts}</div>
    </div>`;

  setTimeout(() => {
    if (cal.invalidAttempts >= cal.maxInvalidAttempts) {
      calMessage.innerHTML = `
        <div style="background: rgba(255,107,107,0.3); border: 2px solid #ff6b6b; border-radius: 8px; padding: 20px; max-width: 500px; margin: 0 auto;">
          <div style="font-size: 22px; margin-bottom: 12px;">❌ Maximum Attempts Reached</div>
          <div style="font-size: 15px; line-height: 1.6;">
            You've failed calibration ${cal.maxInvalidAttempts} times.<br><br>
            Please ensure:<br>
            • Your face is clearly visible<br>
            • You look directly at each dot<br>
            • Keep your face visible while looking at each dot
          </div>
        </div>`;
      if (window.parent && window.parent !== window)
        window.parent.postMessage({ action: "calibrationFailed" }, "*");
    } else {
      if (cal.restartAll) { cal.i = 0; cal.rows = []; }
      cal.active = true;
      dot.style.display = "block";
      beginDot();
    }
  }, 3000);
}

function failAttempt(reason, restartAll = false) {
  cal.active = false;
  cal.phase = "";
  cal.restartAll = restartAll;
  dot.classList.remove("collecting");
  dot.style.display = "none";
  clearFeedback();
  if (restartAll) {
    cal.modelFails++;
    cal.invalidAttempts = cal.modelFails;
  } else {
    cal.invalidAttempts++;
  }
  showCalibrationError(reason);
}

// ---------------- flow ----------------
function beginDot() {
  const st = PLAN[cal.i];
  [cal.fx, cal.fy] = ORDER[st.spot];
  dot.style.left = cal.fx * 100 + "%";
  dot.style.top = cal.fy * 100 + "%";
  cal.t0 = performance.now();
  cal.phase = "settle";
  cal.samples = [];
  cal.baselineGaze = null;
  cal.baselineHead = null;
  clearFeedback();
  calMessage.textContent = `Look at the dot and keep your head still  (${cal.i + 1}/${PLAN.length})`;
}

function startCalibration() {
  localStorage.removeItem("gazeCalibrationData");
  sessionStorage.removeItem("gazeOnlineClicks");
  smooth.reset();
  Object.assign(cal, { active: true, i: 0, rows: [], modelFails: 0, invalidAttempts: 0 });
  mainScreen.classList.add("hidden");
  calibrationOverlay.classList.add("active");
  beginDot();
}

// keep ~10 evenly spaced rows per dot so exam.html can refit with them (small localStorage footprint)
function compactRows(rows, perSpot = 10) {
  const rd = (v) => Math.round(v * 1e4) / 1e4;
  const groups = new Map();
  rows.forEach((r) => {
    const key = `${r.spot}-${r.stage}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(r);
  });
  const out = [];
  for (const arr of groups.values()) {
    const count = Math.min(arr.length, perSpot);
    for (let n = 0; n < count; n++) {
      const index = count === 1 ? 0 : Math.round((n * (arr.length - 1)) / (count - 1));
      const r = arr[index];
      out.push({
        ox: rd(r.ox), oy: rd(r.oy), yaw: rd(r.yaw), pitch: rd(r.pitch), roll: rd(r.roll),
        cx: rd(r.cx), cy: rd(r.cy), scale: rd(r.scale),
        sx: r.sx, sy: r.sy, spot: r.spot,
      });
    }
  }
  return out;
}

function finishCalibration() {
  const rows = cal.rows;
  const still = rows.filter((r) => r.stage === "still");
  const headBase = {
    yaw: med(still.map((r) => r.yaw)),
    pitch: med(still.map((r) => r.pitch)),
    roll: med(still.map((r) => r.roll)),
  };

  const modelLin = GazeCore.fit(rows, false);
  const modelQuad = GazeCore.fit(rows, true);
  const errs = {
    lin: { train: GazeCore.trainErr(rows, modelLin), loo: GazeCore.looErr(rows, false) },
    quad: { train: GazeCore.trainErr(rows, modelQuad), loo: GazeCore.looErr(rows, true) },
  };
  const best = errs.quad.loo <= errs.lin.loo ? "quad" : "lin";
  console.log(
    `train lin ${errs.lin.train.toFixed(0)} / quad ${errs.quad.train.toFixed(0)}px | loo lin ${errs.lin.loo.toFixed(0)} / quad ${errs.quad.loo.toFixed(0)}px`,
  );

  const check = validateFinalModel(rows, errs[best].train);
  if (!check.valid) {
    console.warn("❌ Final model rejected:", check.reason);
    failAttempt(check.reason, true);
    return;
  }

  cal.active = false;
  localStorage.setItem(
    "gazeCalibrationData",
    JSON.stringify({
      version: GazeCore.VERSION,
      headBase, modelQuad, modelLin, best,
      smoothTauMs: SMOOTH_TAU_MS,
      timestamp: Date.now(),
      accuracy: errs[best].loo,
      rows: compactRows(rows),
    }),
  );
  console.log(`✓ Saved ${best} model; leave-one-position-out error ${errs[best].loo.toFixed(0)}px`);

  if (window.parent && window.parent !== window)
    window.parent.postMessage({ action: "calibrationComplete" }, "*");

  calMessage.textContent = `✓ Calibration Complete! Accuracy: ${errs[best].loo.toFixed(0)}px`;
  dot.style.display = "none";
  setTimeout(() => calibrationOverlay.classList.remove("active"), 2000);
}

// calibration clock
setInterval(() => {
  if (!cal.active) return;
  const st = PLAN[cal.i];
  const t = performance.now() - cal.t0;
  const collectMs = COLLECT;

  if (cal.phase === "settle" && t > SETTLE) {
    cal.phase = "collect";
    cal.t0 = performance.now();
    cal.samples = [];
    dot.style.animationDuration = collectMs + "ms";
    dot.classList.add("collecting");
  } else if (cal.phase === "collect") {
    if (t > collectMs) {
      dot.classList.remove("collecting");
      const v = validateSamples(cal.samples);
      if (!v.valid) {
        console.warn("❌ Samples rejected:", v.reason);
        failAttempt(v.reason);
        return;
      }
      cal.samples.forEach((s) =>
        cal.rows.push({ ...s, spot: st.spot, stage: "still", sx: cal.fx, sy: cal.fy }),
      );
      cal.invalidAttempts = 0;
      cal.i++;
      cal.i >= PLAN.length ? finishCalibration() : beginDot();
    }
  }
}, 50);

// ---------------- UI wiring ----------------
let modelReady = false;
function setReady() {
  if (modelReady) return;
  modelReady = true;
  startBtn.disabled = false;
  startBtn.classList.remove("loading");
  startLabel.textContent = "Start 9-Point Calibration";
}
function setLoadError(e) {
  console.error("Calibration setup failed:", e);
  startBtn.classList.remove("loading");
  startLabel.textContent = "Camera or model failed to load. Reload the page.";
}

mainScreen.addEventListener("click", (e) => {
  if (e.target !== mainScreen || cal.active) return;
  if (window.parent && window.parent !== window)
    window.parent.postMessage({ action: "calibrationCancelled" }, "*");
});
startBtn.onclick = () => { if (modelReady) startCalibration(); };

// ---------------- MediaPipe ----------------
const fm = new FaceMesh({
  locateFile: (f) => `https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh/${f}`,
});
fm.setOptions({
  maxNumFaces: 1,
  refineLandmarks: true,
  minDetectionConfidence: 0.55,
  minTrackingConfidence: 0.55,
});

fm.onResults((res) => {
  setReady();
  canvas.width = video.clientWidth;
  canvas.height = video.clientHeight;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  if (!res.multiFaceLandmarks?.length) return;

  const lm = res.multiFaceLandmarks[0];
  const W = video.videoWidth, H = video.videoHeight;
  if (!W) return;

  ctx.fillStyle = "#1e90ff";
  [468, 473].forEach((i) => {
    ctx.beginPath();
    ctx.arc(lm[i].x * canvas.width, lm[i].y * canvas.height, 4, 0, 7);
    ctx.fill();
  });

  const raw = GazeCore.extract(lm, W, H);
  if (raw.ear < BLINK_EAR) return;
  const s = smooth(raw, performance.now());

  if (cal.active && cal.phase === "collect") {
    if (PLAN[cal.i].stage === "still") checkRealtimeMovement(s);
    cal.samples.push({ ...s });
  }
});

(async () => {
  try {
    await fm.initialize();
    startLabel.textContent = "Starting camera…";
    await new Camera(video, {
      onFrame: async () => { await fm.send({ image: video }); },
      width: 1280,
      height: 720,
    }).start();
  } catch (e) {
    setLoadError(e);
  }
})();