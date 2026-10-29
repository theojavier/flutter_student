// gaze-calibration.js — replaces the last inline <script> of gaze-calibration.html
// Requires, loaded in this order BEFORE this file:
//   face_mesh.js, camera_utils.js, gaze-core.js, yolo-eye.js
// Same element ids as before.
// MediaPipe = face + head pose.  YOLO eye model = eyelid/iris keypoints (the ox/oy features).
console.log("Gaze calibration (head-aware, YOLO eyes) loaded");

// Bridge function for cross-platform communication
window.sendToHost = window.sendToHost || function (data) {
  if (window.flutter_inappwebview?.callHandler) {
    window.flutter_inappwebview.callHandler("flutterMessage", data); // mobile
  } else if (window.parent && window.parent !== window) {
    window.parent.postMessage(data, "*"); // web iframe
  }
};

const $ = (id) => document.getElementById(id);
const video = $("video"), canvas = $("canvas"), ctx = canvas.getContext("2d");
const dot = $("dot"), calMessage = $("calMessage"), feedbackMessage = $("feedbackMessage");
const calibrationOverlay = $("calibrationOverlay"), mainScreen = $("mainScreen");
const startBtn = $("startBtn"), startLabel = $("startLabel");

const med = GazeCore.med;
const range = (a) => Math.max(...a) - Math.min(...a);
// range that ignores the top/bottom 15% (INCREASED: more aggressive outlier rejection)
const trimmedRange = (a, p = 0.15) => {
  const s = [...a].sort((x, y) => x - y);
  return s[Math.ceil(s.length * (1 - p)) - 1] - s[Math.floor(s.length * p)];
};

// ---------------- plan ----------------
const G = [0.08, 0.5, 0.92];
const ORDER = [
  [G[1], G[1]], // 0 center
  [G[0], G[0]], [G[2], G[0]], [G[2], G[2]], [G[0], G[2]], // corners
  [G[1], G[0]], [G[2], G[1]], [G[1], G[2]], [G[0], G[1]], // edges
];
const PLAN = ORDER.map((_, spot) => ({ spot }));

const IS_MOBILE =
  matchMedia("(pointer: coarse)").matches ||
  /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);

// Wait for each dot's glide before collecting, then keep collecting through the full ring.
const GLIDE_MS = 550;
const SETTLE = GLIDE_MS + 350;
const RING_MS = IS_MOBILE ? 3000 : 2500;
const EXTRA_MS = 2000;
const COLLECT_MIN = RING_MS;
const COLLECT_MAX = RING_MS + EXTRA_MS;
const FRAMES_PER_AVG = 3;
const TARGET_SAMPLES = IS_MOBILE ? 8 : 10, MIN_SAMPLES = 5;
const SMOOTH_TAU_MS = 250, BLINK_EAR = IS_MOBILE ? 0.09 : 0.14;
const MAX_GAZE_MOVEMENT = IS_MOBILE ? 0.40 : 0.35; // VERY RELAXED: validate the AVERAGE, not individual frames
const MAX_HEAD_MOVEMENT = IS_MOBILE ? 0.35 : 0.28; // VERY RELAXED: validate the AVERAGE
// More camera pixels on the eye = the biggest accuracy win. exam.html must use the SAME size.
const CAM_W = IS_MOBILE ? 1280 : 1920, CAM_H = IS_MOBILE ? 720 : 1080;
const maxTrainPx = () => Math.hypot(innerWidth, innerHeight) * (IS_MOBILE ? 0.22 : 0.15); // RELAXED: we're averaging multiple frames

YoloEye.cfg.blinkEar = BLINK_EAR;
const smooth = YoloEye.makeSmoother(SMOOTH_TAU_MS, 1);

const cal = {
  active: false, i: 0, t0: 0, phase: "", samples: [], frameBuf: [], rows: [],
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

function avgFrames(frames) {
  const out = {};
  for (const k of Object.keys(frames[0])) {
    if (typeof frames[0][k] === "number")
      out[k] = frames.reduce((sum, frame) => sum + frame[k], 0) / frames.length;
  }
  return out;
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
  else if (cal.samples.length > 3) clearFeedback();
}

// ---------------- validation ----------------
function validateSamples(samples) {
  if (samples.length < MIN_SAMPLES)
    return { valid: false, reason: `Not enough averaged eye-tracking readings (${samples.length} of ${MIN_SAMPLES}). Keep your face and eyes visible, then try again.` };

  const gaze = Math.max(trimmedRange(samples.map((s) => s.ox)), trimmedRange(samples.map((s) => s.oy)));
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

// drop noisy frames of ONE dot (outside ~6 MAD of that dot's median) — more aggressive outlier rejection
function cleanSamples(r) {
  const mx = med(r.map((x) => x.ox)), my = med(r.map((x) => x.oy));
  const dx = 6.0 * med(r.map((x) => Math.abs(x.ox - mx))) + 0.004; // INCREASED from 4.5 to 6.0
  const dy = 6.0 * med(r.map((x) => Math.abs(x.oy - my))) + 0.004;
  const kept = r.filter((x) => Math.abs(x.ox - mx) <= dx && Math.abs(x.oy - my) <= dy);
  return kept.length ? kept : r;
}

function validateFinalModel(rows, train, accuracy) {
  const MAXPX = maxTrainPx();
  if (train > MAXPX)
    return { valid: false, reason: `Calibration accuracy too low!\nError: ${train.toFixed(0)}px (max acceptable: ${MAXPX.toFixed(0)}px)\n\nPlease look directly at each dot.` };

  const MAXLOO = maxTrainPx();
  if (accuracy > MAXLOO)
    return { valid: false, reason: `Calibration accuracy too low!\nHeld-out-position error: ${accuracy.toFixed(0)}px (max acceptable: ${MAXLOO.toFixed(0)}px)\n\nPlease look directly at each dot.` };

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
      window.sendToHost({ action: "calibrationFailed" });
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
// Dot glide and progress ring are driven by requestAnimationFrame.
const RING_R = 20.5, RING_C = 2 * Math.PI * RING_R;

dot.insertAdjacentHTML("beforeend", `
  <svg viewBox="0 0 44 44">
    <circle cx="22" cy="22" r="${RING_R}" fill="none" stroke="rgba(255,255,255,0.25)" stroke-width="3"/>
    <circle id="ringArc" cx="22" cy="22" r="${RING_R}" fill="none" stroke="#ffffff" stroke-width="3"
            stroke-dasharray="${RING_C}" stroke-dashoffset="${RING_C}"
            transform="rotate(-90 22 22)"/>
  </svg>`);
const ringArc = document.getElementById("ringArc");
const setRing = (p) => ringArc.setAttribute("stroke-dashoffset", RING_C * (1 - p));

const ease = (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
let pos = null;
let glide = null;

function drawDot(x, y) {
  pos = { x, y };
  dot.style.transform = `translate3d(${x}px, ${y}px, 0) translate(-50%, -50%)`;
}

function placeDot(animate = true) {
  const x = cal.fx * innerWidth, y = cal.fy * innerHeight;
  if (!animate || !pos) {
    glide = null;
    drawDot(x, y);
    return;
  }
  glide = { x0: pos.x, y0: pos.y, x1: x, y1: y, t0: performance.now() };
}

addEventListener("resize", () => {
  if (cal.active) placeDot(false);
});

function uiFrame(now) {
  if (glide) {
    const u = Math.min(1, (now - glide.t0) / GLIDE_MS);
    const e = ease(u);
    drawDot(
      glide.x0 + (glide.x1 - glide.x0) * e,
      glide.y0 + (glide.y1 - glide.y0) * e,
    );
    if (u >= 1) glide = null;
  }
  if (cal.active) {
    setRing(cal.phase === "collect" ? Math.min(1, (now - cal.t0) / RING_MS) : 0);
  }
  requestAnimationFrame(uiFrame);
}
requestAnimationFrame(uiFrame);

function beginDot() {
  const st = PLAN[cal.i];
  [cal.fx, cal.fy] = ORDER[st.spot];
  placeDot();
  cal.t0 = performance.now();
  cal.phase = "settle";
  cal.samples = [];
  cal.frameBuf = [];
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

// Keep up to 14 evenly spaced rows per dot so exam.html can refit with them.
function compactRows(rows, perSpot = 14) {
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
// ---------------- geometry sanity check ----------------
// Starting guesses for an "average PC". Tune them from the console log (see below).
const GEOM_ENFORCE = true;
const GEOM_DEBUG = true;                 // false = log only, never block
const EYE_PER_RAD_X = IS_MOBILE ? 0.16 : 0.4;   // phones: tiny iris movement
const EYE_PER_RAD_Y = IS_MOBILE ? 0.08 : 0.3;
const FACE_W_CM = 14.5;
const LONG_SIDE_FOV_DEG = IS_MOBILE ? 70 : 65;  // FOV along the camera frame's LONG side
const NOISE_X = IS_MOBILE ? 0.012 : 0.003;      // keypoint noise floor (eye-widths)
const NOISE_Y = IS_MOBILE ? 0.012 : 0.003;
const CSS_PX_PER_CM = IS_MOBILE ? 55 : 40; 
// More forgiving gaze calibration
const OVER = IS_MOBILE ? 2.5 : 2.2;
const TOL_X = IS_MOBILE ? 1.5 : 1.3;
const TOL_Y = IS_MOBILE ? 1.5 : 1.6;
const UNDER = IS_MOBILE ? 0.12 : 0.15;    // allowed deviation of each dot from its ideal position
const DOT_NAMES = ["center", "top-left", "top-right", "bottom-right", "bottom-left",
                   "top", "right", "bottom", "left"];

function validateGeometry(rows) {
  const by = [];
  for (let s = 0; s < ORDER.length; s++) {
    const r = rows.filter((x) => x.spot === s);
    if (!r.length) return { valid: false, reason: "Missing data for a calibration dot. Please try again." };
    by[s] = { ox: med(r.map((x) => x.ox)), oy: med(r.map((x) => x.oy)) };
  }
  const mean = (idx, k) => idx.reduce((a, s) => a + by[s][k], 0) / idx.length;
  // signed half-spans of the eye offset across the screen (sign depends on camera mirroring)
  const hx = (mean([2, 3, 6], "ox") - mean([1, 4, 8], "ox")) / 2; // right - left
  const hy = (mean([3, 4, 7], "oy") - mean([1, 2, 5], "oy")) / 2; // bottom - top

  // ---- expected span from an average PC ----
  const scale = med(rows.map((r) => r.scale));
const aspect = Math.min(1, video.videoWidth / video.videoHeight); // portrait frame => narrower width FOV
const tanHalf = Math.tan((LONG_SIDE_FOV_DEG * Math.PI) / 360) * aspect;
const distCm = FACE_W_CM / (2 * scale * tanHalf);
  const edge = G[2] - G[1]; // centre dot -> edge dot, as a fraction of the screen
  const expX = EYE_PER_RAD_X * Math.atan((edge * innerWidth / CSS_PX_PER_CM) / distCm);
  const expY = EYE_PER_RAD_Y * Math.atan((edge * innerHeight / CSS_PX_PER_CM) / distCm);

  // ---- template: where each dot should sit relative to the centre dot ----
  const dbg = [];
  const bad = [];
   if (Math.abs(hx) > 1e-3 && Math.abs(hy) > 1e-3) {
    const scaleX = Math.max(Math.abs(hx), expX), scaleY = Math.max(Math.abs(hy), expY);
    for (let s = 1; s < ORDER.length; s++) {
      const ix = (ORDER[s][0] - G[1]) / edge, iy = (ORDER[s][1] - G[1]) / edge; // -1, 0 or +1
      const dX = by[s].ox - by[0].ox, dY = by[s].oy - by[0].oy;
      const devX = Math.abs(dX - ix * hx), devY = Math.abs(dY - iy * hy);     // absolute deviation
      const nx = dX / hx, ny = dY / hy;
      dbg.push(`${DOT_NAMES[s]}: nx ${nx.toFixed(2)} (ideal ${ix.toFixed(0)}), ny ${ny.toFixed(2)} (ideal ${iy.toFixed(0)})`);
      if (devX > TOL_X * scaleX + NOISE_X || devY > TOL_Y * scaleY + NOISE_Y) {
        const reach = Math.hypot(nx, ny), ideal = Math.hypot(ix, iy) || 0.5;
        bad.push({ s, why: reach > ideal ? "too far (past the screen?)" : "not far enough / wrong direction" });
      }
    }
  }
    console.log("dots:\n" + dbg.join("\n"));
  console.log(
    `geometry: dist≈${distCm.toFixed(0)}cm | hx ${hx.toFixed(3)} (expected ${expX.toFixed(3)}) | ` +
    `hy ${hy.toFixed(3)} (expected ${expY.toFixed(3)}) | bad dots: ${bad.map((b) => DOT_NAMES[b.s]).join(", ") || "none"}`);
  if (!GEOM_ENFORCE) return { valid: true };

  const rx = Math.abs(hx) / expX, ry = Math.abs(hy) / expY; // measured ÷ expected
  const info = GEOM_DEBUG
    ? `\n\n[geometry: dist≈${distCm.toFixed(0)}cm | ` +
      `hx ${hx.toFixed(3)} (expected ${expX.toFixed(3)}, ${rx.toFixed(2)}×) | ` +
      `hy ${hy.toFixed(3)} (expected ${expY.toFixed(3)}, ${ry.toFixed(2)}×) | ` +
      `allowed ${UNDER}×–${OVER}× | ` +
      `bad dots: ${bad.map((b) => DOT_NAMES[b.s]).join(", ") || "none"}]\n` +
      dbg.join("\n")
    : "";

  if (Math.abs(hx) < 1e-3 || Math.abs(hy) < 1e-3)
    return { valid: false, reason: "Your eyes barely moved between dots.\nKeep your head still and look AT each dot." + info };
  if (rx > OVER || ry > OVER)
    return { valid: false, reason: `You looked past the edges of the screen (${rx > OVER ? "left/right" : "up/down"}).\nLook directly AT each dot, not beyond it.` + info };
  if (rx < UNDER || ry < UNDER)
    return { valid: false, reason: `Your eyes didn't move enough (${rx < UNDER ? "left/right" : "up/down"}).\nKeep your head still and move only your eyes to each dot.` + info };
  if (bad.length)
    return { valid: false, reason: "These dots were not looked at correctly:\n" +
      bad.map((b) => `• ${DOT_NAMES[b.s]} dot: ${b.why}`).join("\n") + info };
  return { valid: true };
}

function finishCalibration() {
  const rows = cal.rows;
  const geo = validateGeometry(rows);            // NEW
  if (!geo.valid) {
    console.warn("❌ Geometry rejected:", geo.reason);
    failAttempt(geo.reason, true);               // restart all dots
    return;
  }
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
  const best =
    IS_MOBILE && errs.lin.loo <= errs.quad.loo * 1.15
      ? "lin"
      : errs.quad.loo <= errs.lin.loo
        ? "quad"
        : "lin";
  console.log(
    `train lin ${errs.lin.train.toFixed(0)} / quad ${errs.quad.train.toFixed(0)}px | loo lin ${errs.lin.loo.toFixed(0)} / quad ${errs.quad.loo.toFixed(0)}px`,
  );

  const check = validateFinalModel(rows, errs[best].train, errs[best].loo);
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
      source: "yolo",
      geometryOk: true, 
      yoloCfg: YoloEye.exportCfg(), // the exam re-applies these so it computes features the same way
      camera: { w: video.videoWidth, h: video.videoHeight },
      headBase, modelQuad, modelLin, best,
      smoothTauMs: SMOOTH_TAU_MS,
      timestamp: Date.now(),
      accuracy: errs[best].loo,
      rows: compactRows(rows),
    }),
  );
  console.log(`✓ Saved ${best} model; leave-one-position-out error ${errs[best].loo.toFixed(0)}px`);

  window.disposeGazeTracking?.();
  window.sendToHost({ action: "calibrationComplete" });

  calMessage.textContent = `✓ Calibration Complete! Accuracy: ${errs[best].loo.toFixed(0)}px`;
  dot.style.display = "none";
  setTimeout(() => calibrationOverlay.classList.remove("active"), 2000);
}

// calibration clock
const calibrationTimer = setInterval(() => {
  if (!cal.active) return;
  const st = PLAN[cal.i];
  const t = performance.now() - cal.t0;

  if (cal.phase === "settle" && t > SETTLE) {
    cal.phase = "collect";
    cal.t0 = performance.now();
    cal.samples = [];
    cal.frameBuf = [];
  } else if (cal.phase === "collect") {
    const ringDone = t >= COLLECT_MIN;
    const enough = cal.samples.length >= TARGET_SAMPLES;
    if (ringDone && (enough || t >= COLLECT_MAX)) {
      const v = validateSamples(cal.samples);
      if (!v.valid) {
        console.warn("❌ Samples rejected:", v.reason);
        failAttempt(v.reason);
        return;
      }
      
      // Keep each cleaned three-frame average as a separate training row.
      const cleaned = cleanSamples(cal.samples);
      for (const sample of cleaned) {
        cal.rows.push({
          ...sample,
          spot: st.spot,
          stage: "still",
          sx: cal.fx,
          sy: cal.fy,
        });
        console.log(`${DOT_NAMES[st.spot]}: ${cal.samples.length} samples, ${cleaned.length} kept`);
      }
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
  window.disposeGazeTracking?.();
  window.sendToHost({ action: "calibrationCancelled" });
});
startBtn.onclick = () => { if (modelReady) startCalibration(); };

// ---------------- MediaPipe (face + head pose) ----------------
const fm = new FaceMesh({
  locateFile: (f) => `https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh/${f}`,
});
let calibrationCamera = null;
let trackingDisposed = false;

function disposeGazeTracking() {
  if (trackingDisposed) return;
  trackingDisposed = true;
  cal.active = false;
  clearInterval(calibrationTimer);
  try {
    calibrationCamera?.stop();
  } catch (e) {
    console.warn("Calibration camera stop failed:", e);
  }
  calibrationCamera = null;
  for (const track of video.srcObject?.getTracks?.() ?? []) track.stop();
  video.srcObject = null;
  try {
    Promise.resolve(fm.close()).catch((e) =>
      console.warn("Calibration face detector close failed:", e),
    );
  } catch (e) {
    console.warn("Calibration face detector close failed:", e);
  }
  YoloEye.dispose();
}

window.disposeGazeTracking = disposeGazeTracking;
window.addEventListener("pagehide", disposeGazeTracking, { once: true });
window.addEventListener("message", (event) => {
  if (event.data?.action === "dispose") disposeGazeTracking();
});

fm.setOptions({
  maxNumFaces: 1,
  refineLandmarks: true, // GazeCore.extract still reads iris landmarks for the head features
  minDetectionConfidence: 0.55,
  minTrackingConfidence: 0.55,
});

let busy = false; // the YOLO step is async and slower than a camera frame: drop frames while it runs
fm.onResults(async (res) => {
  if (trackingDisposed || busy || !YoloEye.ready) return;
  busy = true;
  try {
    setReady();
    if (canvas.width !== video.clientWidth || canvas.height !== video.clientHeight) {
      canvas.width = video.clientWidth;
      canvas.height = video.clientHeight;
    }
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    if (!res.multiFaceLandmarks?.length) return;

    const lm = res.multiFaceLandmarks[0];
    const W = video.videoWidth, H = video.videoHeight;
    if (!W) return;

    const raw = await YoloEye.extract(lm, W, H, video); // returns last valid result if busy/failed
    if (!raw) return; // only skip if never had a valid result
    YoloEye.drawKeypoints(ctx, YoloEye.lastGaze, canvas.width / W, canvas.height / H);

    if (raw.ear < BLINK_EAR) return;
    const s = smooth(raw, performance.now());

    if (cal.active && cal.phase === "collect") {
      checkRealtimeMovement(s);
      cal.frameBuf.push({ ...s });
      if (cal.frameBuf.length === FRAMES_PER_AVG) {
        cal.samples.push(avgFrames(cal.frameBuf));
        cal.frameBuf = [];
      }
    }
  } catch (e) {
    console.error(e);
  } finally {
    busy = false;
  }
});

(async () => {
  try {
    startLabel.textContent = "Loading eye model…";
    // Initialize YOLO first to avoid WebAssembly Module conflicts with MediaPipe
    await YoloEye.init();
    if (trackingDisposed) return;
    startLabel.textContent = "Loading face detector…";
    await fm.initialize();
    if (trackingDisposed) {
      await fm.close();
      return;
    }
    startLabel.textContent = "Starting camera…";
    calibrationCamera = new Camera(video, {
      onFrame: async () => { await fm.send({ image: video }); },
      facingMode: "user",
      width: CAM_W,
      height: CAM_H,
    });
    await calibrationCamera.start();
    if (trackingDisposed) {
      calibrationCamera.stop();
      calibrationCamera = null;
    }
  } catch (e) {
    if (!trackingDisposed) setLoadError(e);
  }
})();