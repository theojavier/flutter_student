// Loaded by exam.html after gaze-core.js and yolo-eye.js. Trusted, stable exam clicks provide
// additional gaze labels and are kept only for the current exam session.
//
// Camera / face protection added here:
//   1. Face lost for FACE_LOST_MS             -> strike
//   2. Camera stalled / ended / muted         -> strike (watchdog + track events)
//   3. Eyes closed / low EAR for BLINK_MAX_MS -> treated as looking away (no more free pass)
//   4. More than one face in frame            -> strike

const BLINK_EAR = 0.11; // Match YoloEye.cfg.blinkEar to prevent freeze-then-jump
const AWAY_MS = 700; // must be outside the safe zone this long before a strike
const HEAD_LIMIT_RAD = 0.7; // ≈40° from the calibrated pose = "away" no matter where the eyes point

const BLINK_MAX_MS = 1500; // a real blink is ~100-400 ms; longer = eyes closed / looking down
const BLINK_REL = 0.68;
const BLINK_WIN_MS = 1500;
const BLINK_SETTLE_MS = 120;
const FACE_LOST_MS = 1500; // tolerate brief tracking drops before striking
const FACE_LOSS_SUBMIT_MS = 5000;
const MULTI_FACE_MS = 1500; // second face must persist this long before a strike
const CAMERA_STALL_MS = 3000; // no FaceMesh results for this long = camera stopped/blocked
const STALL_STRIKE_INTERVAL_MS = 5000; // at most one camera-loss strike per interval
const WATCHDOG_INTERVAL_MS = 1000;

// Allow a second face to be reported so it can be detected (exam.html sets 1).
faceMesh.setOptions({
  maxNumFaces: 2,
  refineLandmarks: true,
  minDetectionConfidence: 0.55,
  minTrackingConfidence: 0.55,
});

const calData = GazeCore.loadCalibration(); // null if missing or from an older version
const featureRange = (key) => {
  const values = (calData?.rows || [])
    .map((row) => row[key])
    .filter(Number.isFinite);
  return values.length ? [Math.min(...values), Math.max(...values)] : null;
};
const eyeRange = { ox: featureRange("ox"), oy: featureRange("oy") };
const OUT_MARGIN = 0.5;
const limitToCalibratedRange = (value, range) => {
  if (!range) return value;
  const margin = (range[1] - range[0]) * OUT_MARGIN;
  return Math.max(range[0] - margin, Math.min(range[1] + margin, value));
};
const outsideCalibratedRange = (value, range) => {
  if (!range) return false;
  const margin = (range[1] - range[0]) * OUT_MARGIN;
  return value < range[0] - margin || value > range[1] + margin;
};
if (calData) {
  for (const savedModel of [calData.modelLin, calData.modelQuad]) {
    if (savedModel && !savedModel.rng && eyeRange.ox && eyeRange.oy)
      savedModel.rng = eyeRange;
  }
}
let model = calData ? (calData.best === "lin" ? calData.modelLin : calData.modelQuad) : null;
const headBase = calData?.headBase || { yaw: 0, pitch: 0, roll: 0 };

// Use the SAME eye-feature settings (refine / crop averaging / distance compensation) the calibration used.
YoloEye.applyCfg(calData?.yoloCfg);

// EXAM-ONLY overrides for smoother tracking (not saved to exportCfg, calibration keeps its own)
YoloEye.cfg.minCut = 0.8;        // was 1.0 - balanced: smooth when still, responsive when moving
YoloEye.cfg.beta = 4;            // was 6 - less aggressive opening on movement
YoloEye.cfg.boxSmoothing = 0.6;  // was 0.85 - eye crop follows movement faster
YoloEye.cfg.blinkEar = 0.11;     // was 0.14 - fixes bottom gaze (looking down drops EAR)
YoloEye.cfg.disagree = 0.2;      // was 0.10 - average both eyes more often (less switching)

// MUST be the YOLO smoother (frame averaging + 1-Euro on the eye offset, then head + distance correction).
// GazeCore.makeSmoother does none of that, so the exam would feed the model different features
// than the ones it was calibrated on and the bubble ends up stuck at an edge.
// EXAM: average 2 frames for responsiveness; calibration averages 3-frame groups.
const smoothGaze = YoloEye.makeSmoother(250, 2);
const yoloReady = () => (typeof YoloEye.isReady === "function" ? YoloEye.isReady() : !!YoloEye.ready);
let yoloBusy = false; // the YOLO step is slower than a camera frame: don't let frames pile up
// ---------------------------------------------------------------------------- PART 1
const HEAD_GAIN = 0.05;        // 0 = head pose never moves the dot, 1 = the full calibrated head terms
const GAZE_BIAS_X = -0.03;     // negative shifts predicted gaze left by 3% of viewport width
const R_MIN = 28;              // px: bubble radius when the model is calm
const R_BASE_MAX = 60;         // px: cap calibration-derived radius so a good calibration can look smaller
const R_MAX = 120;             // px: bubble radius when it is very unsure
const SPREAD_WIN_MS = 700;     // window used to measure how much the raw estimate is jumping around
const SPREAD_FULL_PX = 140;    // 80%-cloud radius (px) at which the bubble/rule are most forgiving
const SPREAD_MIN_N = 5;
const CLOUD_PCT = 0.8;
const OUT_FRAC = 0.5;          // strike when LESS than this part of the bubble is inside the card
const OUT_FRAC_UNSURE = 0.3;   // ...and this part when the model is unsure (harder to get a strike)
const BACK_FRAC = 0.1;         // must come back this far above the line before the alert clears
const HEAD_R_GAIN = 120;       // px of extra radius per radian of head turn (looks only, never loosens the rule)
const AWAY_DECAY = 0.7;        // time outside counts 1x, time inside pays it back at 0.7x
 
const clampPx = (v, a, b) => Math.max(a, Math.min(b, v));
const pxA = (cut, dt) => 1 / (1 + 1 / (2 * Math.PI * cut) / dt);
// 1-Euro filter in screen pixels
class PxFilter {
  constructor(minCut = 0.5, beta = 0.004, dCut = 1) {
    Object.assign(this, { minCut, beta, dCut, x: null, dx: 0, t: 0 });
  }
  reset() { this.x = null; }
  filter(v, tMs) {
    if (this.x === null || tMs - this.t > 1000) { this.x = v; this.dx = 0; this.t = tMs; return v; }
    const dt = Math.max((tMs - this.t) / 1000, 1e-3);
    this.t = tMs;
    this.dx += pxA(this.dCut, dt) * ((v - this.x) / dt - this.dx);
    this.x += pxA(this.minCut + this.beta * Math.abs(this.dx), dt) * (v - this.x);
    return this.x;
  }
}
const posX = new PxFilter(), posY = new PxFilter();
const posHist = []; // raw (unfiltered) screen estimates of the last SPREAD_WIN_MS
const earHist = [];
let lastBlinkishAt = -1e9;
let lastGazeT = performance.now();
let awayMs = 0;       // leaky "time spent outside": jitter in and out cancels, real looking away builds up
let gazeWasOk = true;
const Y_BLIP_PX = 90;
const Y_CONFIRM_FRAMES = 2;
const Y_CONFIRM_WINDOW_MS = 350;
let yStable = null;
let yCandidate = null;
let yCandidateCount = 0;
let yCandidateAt = 0;

function filterYBlips(y, now) {
  if (!Number.isFinite(y)) return y;
  if (yStable === null) {
    yStable = y;
    return y;
  }

  if (Math.abs(y - yStable) <= Y_BLIP_PX) {
    yStable = y;
    yCandidate = null;
    yCandidateCount = 0;
    return yStable;
  }

  if (
    yCandidate === null ||
    now - yCandidateAt > Y_CONFIRM_WINDOW_MS ||
    Math.abs(y - yCandidate) > Y_BLIP_PX * 0.5
  ) {
    yCandidate = y;
    yCandidateCount = 1;
    yCandidateAt = now;
    return yStable;
  }

  yCandidate = y;
  yCandidateCount++;
  if (yCandidateCount >= Y_CONFIRM_FRAMES) {
    yStable = y;
    yCandidate = null;
    yCandidateCount = 0;
  }
  return yStable;
}

function resetYBlipFilter() {
  yStable = null;
  yCandidate = null;
  yCandidateCount = 0;
  yCandidateAt = 0;
}

const BIAS_K = 0.25;           // share of each click's miss that is corrected (0.25 = about 4 clicks to converge)
const BIAS_MAX = 0.12;         // never shift the dot by more than 12% of the viewport
const BIAS_GATE_PX = 260;      // ignore clicks the model was further away from than this (looking elsewhere)
const BIAS_MAX_SPREAD = 150;   // ignore clicks where the gaze was not steady before the click (px)
let biasX = 0, biasY = 0;      // screen-pixel corrections; vertical correction is disabled
try {
  const saved = JSON.parse(sessionStorage.getItem("gazeBias") || "null"); // survives a page reload
  if (saved && Number.isFinite(saved.x)) { biasX = saved.x; biasY = 0; }
  else biasX = GAZE_BIAS_X * window.innerWidth; // start from your manual x shift
} catch (_) {}
 
// px error of the last fixation before a click -> nudge the correction. Returns true if the click was used.
function learnBias(x, now) {
  const w = posHist.filter((q) => now - q.t >= 150 && now - q.t <= 600); // fixation just before the click
  if (w.length < 3) return false;
  const mx = GazeCore.med(w.map((q) => q.x));
  const my = GazeCore.med(w.map((q) => q.y));
  if (Math.max(...w.map((q) => Math.hypot(q.x - mx, q.y - my))) > BIAS_MAX_SPREAD) return false; // not steady
  if (Math.abs(x - mx) > BIAS_GATE_PX) return false; // outlier: not looking near the click horizontally
  biasX = clampPx(biasX + BIAS_K * (x - mx), -BIAS_MAX * window.innerWidth, BIAS_MAX * window.innerWidth);
  try { sessionStorage.setItem("gazeBias", JSON.stringify({ x: biasX, y: 0 })); } catch (err) {
    console.warn("Could not persist horizontal gaze bias:", err);
  }
  return true;
}

const GATE_SKIP_MS = 1200;
const GATE_MIN_FRAMES = 8;
const GATE_MAX_SPREAD = 120;
const GATE_GATE_PX = 320;
const gateFrames = [];
let gateLearned = !!window.examStarted;

function gateTarget() {
  const el =
    document.querySelector("#examContentGate img") ||
    document.getElementById("examGate");
  if (!el) return null;
  const rect = el.getBoundingClientRect();
  if (rect.width < 1 || rect.height < 1) return null;
  return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
}

function gateRecord(now, x, y, target) {
  gateFrames.push({
    t: now,
    x,
    y,
    tx: target.x,
    ty: target.y,
  });
  while (gateFrames.length && now - gateFrames[0].t > 5000)
    gateFrames.shift();
}

function learnFromGate(now) {
  gateLearned = true;
  if (!gateFrames.length) return "no-gate-frames";

  const firstFrameAt = gateFrames[0].t;
  const stableFrames = gateFrames.filter(
    (frame) => frame.t - firstFrameAt >= GATE_SKIP_MS,
  );
  if (stableFrames.length < GATE_MIN_FRAMES) return "too-few-frames";

  const median = GazeCore.med;
  const mx = median(stableFrames.map((frame) => frame.x));
  const my = median(stableFrames.map((frame) => frame.y));
  if (
    Math.max(
      ...stableFrames.map((frame) => Math.hypot(frame.x - mx, frame.y - my)),
    ) > GATE_MAX_SPREAD
  )
    return "unstable";

  const tx = stableFrames[stableFrames.length - 1].tx;
  const ty = stableFrames[stableFrames.length - 1].ty;
  if (Math.abs(tx - mx) > GATE_GATE_PX) return "outlier";

  biasX = clampPx(
    biasX + (tx - mx),
    -BIAS_MAX * window.innerWidth,
    BIAS_MAX * window.innerWidth,
  );
  biasY = 0;
  try {
    sessionStorage.setItem("gazeBias", JSON.stringify({ x: biasX, y: 0 }));
  } catch (err) {
    console.warn("Could not persist gate gaze bias:", err);
  }

  if (online) {
    const firstWindowAt = now - 900;
    const firstResult = online.addClick(tx, ty, now, true);
    const secondResult = online.addClick(tx, ty, firstWindowAt);
    if (firstResult === "ok" || secondResult === "ok") {
      model = online.getModel();
      try {
        sessionStorage.setItem(
          "gazeOnlineClicks",
          JSON.stringify(online.exportClicks()),
        );
      } catch (err) {
        console.warn("Could not persist gate gaze samples:", err);
      }
    }
    console.debug("gate gaze samples:", firstResult, secondResult);
  }

  gateFrames.length = 0;
  return "ok";
}
 
// Radius containing CLOUD_PCT of recent raw gaze estimates (px).
function recordSpread(now, x, y) {
  posHist.push({ t: now, x, y });
  while (posHist.length && now - posHist[0].t > SPREAD_WIN_MS) posHist.shift();
  const n = posHist.length;
  if (n < SPREAD_MIN_N) return 0;
  const mx = GazeCore.med(posHist.map((q) => q.x));
  const my = GazeCore.med(posHist.map((q) => q.y));
  const distances = posHist
    .map((q) => Math.hypot(q.x - mx, q.y - my))
    .sort((a, b) => a - b);
  return distances[Math.ceil(CLOUD_PCT * n) - 1];
}

const EXIT_WIN = 5;
const EXIT_VOTES = 4;
const EXIT_MIN_MS = 250;
const JUMP_PX = 220;
const JUMP_EXTRA_MS = 250;
const EXIT_INSET = 3;
let exitOutSince = 0;
let exitOpen = false;
let exitNeedMs = EXIT_MIN_MS;
let lastInsideX = null;
let lastInsideY = null;

function exitReset() {
  exitOutSince = 0;
  exitOpen = false;
  exitNeedMs = EXIT_MIN_MS;
  lastInsideX = null;
  lastInsideY = null;
}

function exitGate(rect, now, x, y) {
  const inside = (px, py) =>
    px >= rect.left &&
    px <= rect.right &&
    py >= rect.top &&
    py <= rect.bottom;

  if (inside(x, y)) {
    exitOutSince = 0;
    exitOpen = false;
    lastInsideX = x;
    lastInsideY = y;
    return { x, y };
  }

  if (!exitOpen) {
    if (!exitOutSince) {
      exitOutSince = now;
      const raw = posHist[posHist.length - 1];
      const jump =
        raw && lastInsideX !== null
          ? Math.hypot(raw.x - lastInsideX, raw.y - lastInsideY)
          : 0;
      exitNeedMs = EXIT_MIN_MS + (jump > JUMP_PX ? JUMP_EXTRA_MS : 0);
    }

    const outsideVotes = posHist
      .slice(-EXIT_WIN)
      .filter((point) => !inside(point.x, point.y)).length;
    if (
      outsideVotes >= EXIT_VOTES &&
      now - exitOutSince >= exitNeedMs
    ) {
      exitOpen = true;
    }
  }

  if (exitOpen) return { x, y };
  return {
    x: clampPx(x, rect.left + EXIT_INSET, rect.right - EXIT_INSET),
    y: clampPx(y, rect.top + EXIT_INSET, rect.bottom - EXIT_INSET),
  };
}

function blinkGuard(now, ear) {
  earHist.push({ t: now, e: ear });
  while (earHist.length && now - earHist[0].t > BLINK_WIN_MS) earHist.shift();
  const openEar = Math.max(...earHist.map((q) => q.e));
  const blinkish = ear < Math.max(BLINK_EAR, openEar * BLINK_REL);
  if (blinkish) lastBlinkishAt = now;
  return blinkish || now - lastBlinkishAt < BLINK_SETTLE_MS;
}

function resetBlinkGuard() {
  earHist.length = 0;
  lastBlinkishAt = -1e9;
}

// share (0..1) of the circle that lies inside the rectangle (strip integration, 24 strips: cheap)
function circleInsideFrac(cx, cy, r, rect) {
  const N = 24, step = (2 * r) / N;
  let inside = 0;
  for (let i = 0; i < N; i++) {
    const x = cx - r + (i + 0.5) * step;
    if (x < rect.left || x > rect.right) continue;
    const h = Math.sqrt(Math.max(0, r * r - (x - cx) ** 2));
    const y0 = Math.max(cy - h, rect.top), y1 = Math.min(cy + h, rect.bottom);
    if (y1 > y0) inside += (y1 - y0) * step;
  }
  return Math.min(1, inside / (Math.PI * r * r));
}
 
function resetGazeFilters() {
  posX.reset();
  posY.reset();
  posHist.length = 0;
  resetYBlipFilter();
  exitReset();
  resetBlinkGuard();
  awayMs = 0;
  gazeWasOk = true;
}
let awaySince = 0;
let eyesClosedSince = 0;
let lastFrameAt = performance.now();
let lastFaceDetected = false;
let lastStallStrikeAt = 0;
let watchedTrack = null;
let lossTimer = null;
let lossDeadline = 0;
const missingSignals = new Set();
let screenLossActive = false;

// Online learning: every real click on an answer / Next becomes a labeled gaze sample.
const online = GazeCore.createOnline(calData, { xOnly: true }); // exam clicks only adjust horizontal gaze
let firstExamClick = true;
if (online) {
  try {
    const storedClicks = sessionStorage.getItem("gazeOnlineClicks");
    if (storedClicks) {
      const parsedClicks = JSON.parse(storedClicks);
      const imported = online.importClicks(parsedClicks);
      if (!imported && Array.isArray(parsedClicks) && parsedClicks.length)
        console.warn("Saved gaze click samples failed validation and were discarded.");
    }
    model = online.getModel();
  } catch (err) {
    console.warn("Could not restore online gaze samples:", err);
  }
}

document.addEventListener(
  "pointerdown",
  (e) => {
    if (!online || !e.isTrusted || !window.examStarted || awaySince) return;
    if (e.clientX === 0 && e.clientY === 0) return; // keyboard-generated
    const t = e.target;
    if (!t.closest || !t.closest("#examCard") || !t.closest("label, input, select, button")) return;

    const result = online.addClick(
      e.clientX,
      e.clientY,
      performance.now(),
      firstExamClick,
    );
    learnBias(e.clientX, performance.now());
    console.debug("gaze online click:", result);
    if (result === "ok") {
      firstExamClick = false;
      model = online.getModel();
      try {
        sessionStorage.setItem("gazeOnlineClicks", JSON.stringify(online.exportClicks()));
      } catch (err) {
        console.warn("Could not persist online gaze samples:", err);
      }
    }
  },
  true,
);

if (!model) {
  faceText.textContent = "Gaze calibration missing or outdated — please recalibrate.";
  console.warn("No v" + GazeCore.VERSION + " gaze calibration found in localStorage.");
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function strikesActive() {
  return !!(
    window.examStarted &&
    window.allowStrikes &&
    !window.disableGazeDetection &&
    !window.examFinished
  );
}

// Mark the student as "away" for a given reason; strike once it lasts longer than `ms`.
function flagAway(reason, ms) {
  examCard.classList.add("alert");
  gazeBubble.classList.add("alert");
  setVerification(false, reason);
  if (window.allowStrikes) {
    if (!awaySince) awaySince = performance.now();
    if (performance.now() - awaySince > ms) registerStrikeOnce();
  } else {
    awaySince = 0;
  }
}

function clearAway() {
  awaySince = 0;
  examCard.classList.remove("alert");
  gazeBubble.classList.remove("alert");
}

function clearFaceLossCountdown(reason) {
  if (reason === undefined) {
    missingSignals.clear();
  } else {
    missingSignals.delete(reason);
  }
  if (missingSignals.size === 0 && lossTimer !== null) {
    clearInterval(lossTimer);
    lossTimer = null;
    lossDeadline = 0;
  }
}

function updateFaceLossWarning() {
  if (!window.examStarted || window.examFinished) {
    clearFaceLossCountdown();
    return;
  }
  if (missingSignals.size === 0) {
    clearFaceLossCountdown();
    return;
  }

  const secondsLeft = Math.max(
    0,
    Math.ceil((lossDeadline - performance.now()) / 1000),
  );
  const reason = Array.from(missingSignals).join(" and ");
  faceText.textContent = `${reason} — submitting in ${secondsLeft}s`;

  if (secondsLeft === 0) {
  console.warn("[auto-submit] triggered by:", reason, {
    camera: window.getCameraHealth?.(),
    screen: {
      hasStream: !!window.cheatCaptureStream,
      active: window.cheatCaptureStream?.active,
      state: window.cheatCaptureStream?.getVideoTracks?.()[0]?.readyState,
      muted: window.cheatCaptureStream?.getVideoTracks?.()[0]?.muted,
    },
  });
  clearFaceLossCountdown();
  faceText.textContent = `${reason} — submitting exam`;
  window.submitExam(true);
}
}

function startFaceLossCountdown(reason) {
  if (!window.examStarted || window.examFinished) return;

  missingSignals.add(reason);
  if (lossTimer === null) {
    lossDeadline = performance.now() + FACE_LOSS_SUBMIT_MS;
    lossTimer = setInterval(updateFaceLossWarning, 200);
  }

  updateFaceLossWarning();
  examCard.classList.add("alert");
  gazeBubble.classList.add("alert");
}

// Camera stopped / frozen / ended / muted.
function cameraLost(reason) {
  setVerification(false, reason);
  examCard.classList.add("alert");
  gazeBubble.classList.add("alert");
  startFaceLossCountdown(reason);
  if (!strikesActive() || document.hidden) return;
  const now = performance.now();
  if (now - lastStallStrikeAt < STALL_STRIKE_INTERVAL_MS) return;
  lastStallStrikeAt = now;
  registerStrikeOnce();
}

function isPcExam() {
  if (typeof window.__examIsPcDoc === "boolean") {
    return window.__examIsPcDoc;
  }
  try {
    if (typeof window.parent.__examIsPc === "boolean") {
      return window.parent.__examIsPc;
    }
  } catch (err) {
    console.warn("Could not read the exam device setting:", err);
  }
  return true;
}

const SCREEN_LOSS_GRACE_MS = 3000;
let screenBadSince = 0;

function checkScreenShare() {
  const REASON = "Screen recording stopped or blocked";
  if (!window.examStarted || !isPcExam()) {
    screenBadSince = 0;
    if (screenLossActive) { screenLossActive = false; clearFaceLossCountdown(REASON); }
    return;
  }

  const stream = window.cheatCaptureStream;
  const track = stream?.getVideoTracks?.()[0];
  const healthy = !!stream?.active && track?.readyState === "live"; // muted is NOT a loss

  if (healthy) {
    screenBadSince = 0;
    if (screenLossActive) { screenLossActive = false; clearFaceLossCountdown(REASON); }
    return;
  }

  const now = performance.now();
  if (!screenBadSince) { screenBadSince = now; return; }
  if (now - screenBadSince < SCREEN_LOSS_GRACE_MS || screenLossActive) return;

  screenLossActive = true;
  console.warn("[screen] lost:", { hasStream: !!stream, state: track?.readyState, muted: track?.muted });
  startFaceLossCountdown(REASON);
  if (strikesActive()) registerStrikeOnce().catch(console.error);
}

window.getCameraHealth = function getCameraHealth() {
  const stream = videoElement.srcObject;
  const track = stream?.getVideoTracks?.()[0];
  const frameAgeMs = Math.max(0, performance.now() - lastFrameAt);
  let status = "ok";

  if (!track || track.readyState !== "live" || track.muted) {
    status = "ended";
  } else if (frameAgeMs > CAMERA_STALL_MS) {
    status = "stalled";
  } else if (!lastFaceDetected) {
    status = "no_face";
  }

  return {
    status,
    frameAgeMs,
    phase: window.examStarted ? "exam" : "gate",
  };
};

// Attach listeners to the live camera track (the track exists only after camera.start()).
function watchCameraTrack() {
  const track = videoElement.srcObject?.getVideoTracks?.()[0];
  if (!track || track === watchedTrack) return;
  watchedTrack = track;
  track.addEventListener("ended", () => cameraLost("Camera stopped or blocked"));
  track.addEventListener("mute", () => cameraLost("Camera stopped or blocked"));
  track.addEventListener("unmute", () => {
    lastFrameAt = performance.now();
  });
}

// Browsers throttle frames while the tab is hidden; don't treat that as a camera failure.
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) lastFrameAt = performance.now();
});

// Watchdog: if onResults stops being called, the camera is dead, frozen or blocked.
setInterval(() => {
  watchCameraTrack();
  checkScreenShare();
  if (document.hidden || window.disableGazeDetection || window.examFinished) return;

  const trackEnded = watchedTrack && watchedTrack.readyState === "ended";
  const stalled = trackEnded || performance.now() - lastFrameAt > CAMERA_STALL_MS;
  if (!stalled) return;

  if (!window.examStarted) {
    // Gate: make sure a frozen camera can't keep a stale "verified" countdown running.
    setVerification(false, "Camera stopped or blocked");
    return;
  }
  cameraLost("Camera stopped or blocked");
}, WATCHDOG_INTERVAL_MS);

// ---------------------------------------------------------------------------
// Main per-frame handler
// ---------------------------------------------------------------------------

async function onResults(results) {
  // CRITICAL: Exit immediately if submitting to avoid blocking submission
  if (window.submitting || window.examFinished) return;
  
  lastFrameAt = performance.now(); // heartbeat for the watchdog
  lastFaceDetected =
    Array.isArray(results.multiFaceLandmarks) &&
    results.multiFaceLandmarks.length > 0;
  clearFaceLossCountdown("Camera stopped or blocked");
  if (window.disableGazeDetection) return;
  if (!YoloEye.isReady()) return; // wait for YOLO model to load

  const vw = videoElement.clientWidth, vh = videoElement.clientHeight;
  canvasElement.width = vw;
  canvasElement.height = vh;
  canvasCtx.clearRect(0, 0, vw, vh);

  const faces = results.multiFaceLandmarks;

  // (1) No face: left the frame, hand/cover over the lens, etc.
  if (!faces || faces.length === 0) {
    eyesClosedSince = 0;
    resetGazeFilters();
    flagAway("Face not found", FACE_LOST_MS);
    startFaceLossCountdown("Face not found");
    targetX = window.innerWidth / 2;
    targetY = window.innerHeight / 2;
    updateBubble();
    return;
  }
  clearFaceLossCountdown("Face not found");

  // (4) More than one face: someone else is in view.
  if (faces.length > 1) {
    eyesClosedSince = 0;
    resetBlinkGuard();
    flagAway("Multiple faces detected", MULTI_FACE_MS);
    updateBubble();
    return;
  }

  if (!model) return;

  const lm = faces[0];
  const W = videoElement.videoWidth, H = videoElement.videoHeight;
  if (!W || !H) return;

  // (3) Blink handling with a time limit.
  // Uses MediaPipe's eye-aspect-ratio, NOT the YOLO result: YoloEye.extract returns null when the
  // eyes are closed, which would silently skip this check and give a free pass for closed eyes.
  const now = performance.now();
  const head = GazeCore.extract(lm, W, H);
  const blinkish = blinkGuard(now, head.ear);
  if (head.ear < BLINK_EAR) {
    if (!eyesClosedSince) eyesClosedSince = now;
    if (now - eyesClosedSince <= BLINK_MAX_MS) {
      updateBubble();
      return; // normal blink: hold last value
    }
    // Eyes closed / lids dropped too long: iris is unreliable, so count it as away.
    flagAway("Eyes closed or looking down", AWAY_MS);
    updateBubble();
    return;
  }
  eyesClosedSince = 0;

  if (blinkish) {
    updateBubble();
    return; // hold the last gaze through a blink and brief iris-settling period
  }

  // Eye features from YOLO (async). Frames that arrive while it is still busy are dropped.
  if (yoloBusy) return;
  
  // CRITICAL: Don't start YOLO processing if we're submitting
  if (window.submitting || window.examFinished) return;
  
  yoloBusy = true;
  let raw;
  try {
    raw = await YoloEye.extract(lm, W, H, videoElement); // lm = full MediaPipe landmarks array
  } catch (err) {
    console.error("YOLO extract failed:", err);
    return;
  } finally {
    yoloBusy = false;
  }
  
  // CRITICAL: Check again after async operation completes
  if (window.submitting || window.examFinished) return;
  
  if (!raw) return; // no valid eye result this frame: keep the last bubble position
  if (window.disableGazeDetection) return; // exam may have been submitted while we awaited
 
// ---------------------------------------------------------------------------- PART 2
// (this is the tail of onResults; `raw`, `model`, `headBase`, `calData`, `online` come from the code above it)
  const tNow = performance.now();
  const f = smoothGaze(raw, tNow);
  if (online) online.push(f, tNow); // feed the click-learning buffer
 
  // Screen estimate. HEAD_GAIN < 1 keeps the head terms from dragging the dot around.
  const p = GazeCore.predict(
    model,
    {
      ...f,
      ox: limitToCalibratedRange(f.ox, eyeRange.ox),
      oy: limitToCalibratedRange(f.oy, eyeRange.oy),
    },
    HEAD_GAIN,
  );
  const estimateX = p.x * window.innerWidth + biasX;
  const rawEstimateY = p.y * window.innerHeight + biasY;
  const estimateY = filterYBlips(rawEstimateY, tNow);
  const spread = recordSpread(tNow, estimateX, estimateY);
  // 1) median of the last 3 gaze estimates removes one-frame "teleports"
  // 2) 1-Euro smooths what is left
  // 3) the CENTRE is clamped to the viewport, so the bubble can sit on the edge (half visible) but never leaves
  const last3 = posHist.slice(-3);
  const mid = (k) => (last3.length < 3 ? last3[last3.length - 1][k] : GazeCore.med(last3.map((q) => q[k])));
  targetX = clampPx(posX.filter(mid("x"), tNow), 0, window.innerWidth);
  targetY = clampPx(posY.filter(mid("y"), tNow), 0, window.innerHeight);
 
  // Grow from the calibrated baseline radius toward R_MAX using the same spread ratio as the strike rule.
  const headDev = Math.max(Math.abs(f.yaw - headBase.yaw), Math.abs(f.pitch - headBase.pitch));
  const baseR = clampPx(0.6 * (calData?.accuracy || 0), R_MIN, R_BASE_MAX);
  const unsureR = Math.min(spread / SPREAD_FULL_PX, 1);
  targetR = Math.min(
    R_MAX,
    baseR + (R_MAX - baseR) * unsureR + HEAD_R_GAIN * headDev,
  );
 
  const targetEl = window.examStarted
    ? document.getElementById("examCard")
    : document.getElementById("examGate");
  if (!targetEl) return;
  const rect = targetEl.getBoundingClientRect();
  if (rect.width < 20 || rect.height < 20) return;

  if (window.examStarted) {
    const allowed = exitGate(rect, tNow, targetX, targetY);
    targetX = allowed.x;
    targetY = allowed.y;
  }
 
  // Strike rule: judged on what the student SEES (the eased bubble position and radius).
  // The more the raw estimate jumps, the more of the bubble has to be outside before it counts.
  const needIn = OUT_FRAC - (OUT_FRAC - OUT_FRAC_UNSURE) * unsureR;
  const judgeR = Math.min(bubbleR, 0.5 * Math.min(rect.width, rect.height));
  const frac = circleInsideFrac(bubbleX, bubbleY, judgeR, rect);
  const bubbleOk = frac >= (gazeWasOk ? needIn : needIn + BACK_FRAC); // hysteresis
  // extreme head turn/tilt: the iris landmarks are unreliable there, so judge by pose
  const headOk =
    Math.abs(f.yaw - headBase.yaw) < HEAD_LIMIT_RAD &&
    Math.abs(f.pitch - headBase.pitch) < HEAD_LIMIT_RAD;
  const gazeOk =
    bubbleOk &&
    headOk &&
    !outsideCalibratedRange(f.ox, eyeRange.ox) &&
    !outsideCalibratedRange(f.oy, eyeRange.oy);
  gazeWasOk = gazeOk;

  if (!window.examStarted) {
    if (gazeOk) {
      const target = gateTarget();
      if (target) gateRecord(tNow, estimateX, estimateY, target);
    } else {
      gateFrames.length = 0;
    }
  } else if (!gateLearned) {
    console.debug("gate learning:", learnFromGate(tNow));
  }
 
  // Leaky timer instead of "reset on every good frame": a few jittery frames can't build a strike
  const dtG = Math.min(tNow - lastGazeT, 200);
  lastGazeT = tNow;
  awayMs = gazeOk
    ? Math.max(0, awayMs - dtG * AWAY_DECAY)
    : Math.min(awayMs + dtG, AWAY_MS * 1.6);
 
  if (awayMs >= AWAY_MS) {
    flagAway("Looking away detected", 0); // alert + strike (registerStrikeOnce rate-limits to one per 1.2 s)
  } else if (awayMs > 250) {
    examCard.classList.add("alert"); // early warning, no strike yet
    gazeBubble.classList.add("alert");
  } else if (gazeOk) {
    clearAway();
    setVerification(true, "Face & eyes centered");
  }
  updateBubble();
}
 