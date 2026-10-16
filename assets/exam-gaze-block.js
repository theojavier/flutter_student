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

// MUST be the YOLO smoother (median + 1-Euro on the eye offset, then head + distance correction).
// GazeCore.makeSmoother does none of that, so the exam would feed the model different features
// than the ones it was calibrated on and the bubble ends up stuck at an edge.
// EXAM: 3-frame median (150ms tau) for semi-realtime. Calibration keeps 9-frame (250ms tau).
const smoothGaze = YoloEye.makeSmoother(150, 3);
const yoloReady = () => (typeof YoloEye.isReady === "function" ? YoloEye.isReady() : !!YoloEye.ready);
let yoloBusy = false; // the YOLO step is slower than a camera frame: don't let frames pile up
let camWarned = false;

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
const online = GazeCore.createOnline(calData); // null if calibration has no saved rows
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

    const result = online.addClick(e.clientX, e.clientY, performance.now());
    console.debug("gaze online click:", result);
    if (result === "ok") {
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

function checkScreenShare() {
  if (!window.examStarted || !isPcExam()) {
    if (screenLossActive) {
      screenLossActive = false;
      clearFaceLossCountdown("Screen recording stopped or blocked");
    }
    return;
  }

  const stream = window.cheatCaptureStream;
  const track = stream?.getVideoTracks?.()[0];
  const healthy =
    !!stream?.active &&
    track?.readyState === "live" &&
    !track.muted;

  if (healthy) {
    if (screenLossActive) {
      screenLossActive = false;
      clearFaceLossCountdown("Screen recording stopped or blocked");
    }
    return;
  }

  if (screenLossActive) return;
  screenLossActive = true;
  startFaceLossCountdown("Screen recording stopped or blocked");
  if (strikesActive()) {
    registerStrikeOnce().catch((err) =>
      console.error("Could not register screen-share strike:", err),
    );
  }
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
    flagAway("Multiple faces detected", MULTI_FACE_MS);
    updateBubble();
    return;
  }

  if (!model) return;

  const lm = faces[0];
  const W = videoElement.videoWidth, H = videoElement.videoHeight;
  if (!W || !H) return;

  if (!camWarned && calData?.camera && (calData.camera.w !== W || calData.camera.h !== H)) {
    camWarned = true;
    console.warn(
      `Exam camera is ${W}x${H} but calibration used ${calData.camera.w}x${calData.camera.h}. ` +
        "Use the same camera size in exam.html and gaze-calibration.js, then recalibrate.",
    );
  }

  // (3) Blink handling with a time limit.
  // Uses MediaPipe's eye-aspect-ratio, NOT the YOLO result: YoloEye.extract returns null when the
  // eyes are closed, which would silently skip this check and give a free pass for closed eyes.
  const now = performance.now();
  const head = GazeCore.extract(lm, W, H);
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
    yoloBusy = false;
    // If GPU device is lost, show error and stop processing
    if (err.message && err.message.includes('GPU device lost')) {
      alert('GPU error detected. Please reload the page to continue the exam.');
      window.submitting = true; // Stop all processing
      if (window.camera?.stop) window.camera.stop();
    }
    return;
  } finally {
    yoloBusy = false;
  }
  
  // CRITICAL: Check again after async operation completes
  if (window.submitting || window.examFinished) return;
  
  if (!raw) return; // no valid eye result this frame: keep the last bubble position
  if (window.disableGazeDetection) return; // exam may have been submitted while we awaited

  const f = smoothGaze(raw, performance.now());
  if (online) online.push(f, performance.now()); // feed the click-learning buffer

  const p = GazeCore.predict(model, f);
  const pad = 8;
  targetX = Math.max(pad, Math.min(window.innerWidth - pad, p.x * window.innerWidth));
  targetY = Math.max(pad, Math.min(window.innerHeight - pad, p.y * window.innerHeight));

  const targetEl = window.examStarted
    ? document.getElementById("examCard")
    : document.getElementById("examGate");
  const rect = targetEl.getBoundingClientRect();
  if (rect.width < 20 || rect.height < 20) return;

  // left/top are the bubble center because its CSS transform is -50%/-50%.
  // Judge the visible marker against the card edges, without calibration slack.
  const bubbleInsideCard =
    bubbleX >= rect.left &&
    bubbleX <= rect.right &&
    bubbleY >= rect.top &&
    bubbleY <= rect.bottom;
  // extreme head turn/tilt: the iris landmarks are unreliable there, so judge by pose
  const headOk =
    Math.abs(f.yaw - headBase.yaw) < HEAD_LIMIT_RAD &&
    Math.abs(f.pitch - headBase.pitch) < HEAD_LIMIT_RAD;
  const gazeOk = bubbleInsideCard && headOk;

  if (!gazeOk) {
    flagAway("Looking away detected", AWAY_MS);
  } else {
    clearAway();
    setVerification(true, "Face & eyes centered");
  }
  updateBubble();
}