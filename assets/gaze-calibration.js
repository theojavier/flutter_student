// gaze-calibration.js — replaces the last inline <script> of gaze-calibration.html
// Requires, loaded in this order BEFORE this file:
//   face_mesh.js, camera_utils.js, gaze-core.js, yolo-eye.js
// Same element ids as before.
// MediaPipe = face + head pose.  YOLO eye model = eyelid/iris keypoints (the ox/oy features).
if (YoloEye.debugEnabled)
  console.log("Gaze calibration (head-aware, YOLO eyes) loaded");

// Bridge function for cross-platform communication
window.sendToHost =
  window.sendToHost ||
  function (data) {
    if (window.flutter_inappwebview?.callHandler) {
      window.flutter_inappwebview.callHandler("flutterMessage", data); // mobile
    } else if (window.parent && window.parent !== window) {
      window.parent.postMessage(data, "*"); // web iframe
    }
  };

const $ = (id) => document.getElementById(id);
const video = $("video"),
  canvas = $("canvas"),
  ctx = canvas.getContext("2d");
const dot = $("dot"),
  calMessage = $("calMessage"),
  feedbackMessage = $("feedbackMessage");
const calibrationOverlay = $("calibrationOverlay"),
  mainScreen = $("mainScreen");
const setupStatus = $("setupStatus");
const startBtn = $("startBtn"),
  startLabel = $("startLabel");
const quickVerifyScreen = $("quickVerifyScreen");
const quickVerifyStatus = $("quickVerifyStatus");
const quickVerifyBegin = $("quickVerifyBegin");
const quickVerifyBeginLabel = $("quickVerifyBeginLabel");
const setupParams = new URLSearchParams(location.search);
const examSetupMode = setupParams.get("exam") === "1";
const profileSetupMode = setupParams.get("profile") === "1";
let profileCalibrationBaseline = null;
let profileBaselineReady = !profileSetupMode;
let profileBaselineStatus = null;
const requestedPlatform = setupParams.get("platform");
window.setProfileCalibrationBaseline = (calibrationData) => {
  if (!profileSetupMode) return;
  if (calibrationData && typeof calibrationData === "object") {
    const cloudHistory = getCalibrationHistory(calibrationData);
    const localHistory = getCalibrationHistory(profileCalibrationBaseline);
    if (cloudHistory.length || !localHistory.length) {
      profileCalibrationBaseline = calibrationData;
    } else {
      console.warn(
        "Cloud calibration is unusable; retaining the valid local calibration baseline.",
      );
    }
  }
  profileBaselineReady = true;
  if (modelReady) updateCalibrationStartButton();
  if (profileBaselineStatus) {
    profileBaselineStatus.textContent = profileCalibrationBaseline
      ? "Saved calibration found. Checking compatibility before calibration."
      : "No saved calibration found. This run will create a new nine-point calibration.";
  }
};
window.addEventListener("message", (event) => {
  if (event.origin !== location.origin || event.source !== window.parent) return;
  let message = event.data;
  if (typeof message === "string") {
    try {
      message = JSON.parse(message);
    } catch (error) {
      console.warn("Ignoring malformed profile calibration message:", error);
      return;
    }
  }
  if (message?.action === "setProfileCalibrationBaseline") {
    window.setProfileCalibrationBaseline(message.calibrationData);
  }
});
if (examSetupMode) {
  mainScreen.classList.add("hidden");
  document.body.classList.add("exam-setup-checking");
}

function setSetupView(view) {
  document.documentElement.dataset.setup = view;
}
setSetupView(examSetupMode ? "checking" : "calibrate");

function detectCalibrationPlatform() {
  const ua = navigator.userAgent || "";
  const platform = navigator.userAgentData?.platform || navigator.platform || "";
  const mobileDevice =
    navigator.userAgentData?.mobile === true ||
    /Android|iPhone|iPad|iPod|IEMobile|Windows Phone/i.test(ua) ||
    (/MacIntel/i.test(platform) && navigator.maxTouchPoints > 1);
  if (mobileDevice) return "mobile";

  const desktopDevice =
    /Windows NT|Macintosh|X11|CrOS|Linux x86_64/i.test(ua) ||
    /Win32|Win64|Windows|MacIntel|Linux x86_64/i.test(platform);
  if (desktopDevice) return "pc";

  return matchMedia("(pointer: coarse)").matches ? "mobile" : "pc";
}

const detectedPlatform = detectCalibrationPlatform();
const examPlatform =
  requestedPlatform === "mobile" || requestedPlatform === "pc"
    ? requestedPlatform
    : detectedPlatform;

function loadLocalProfileCalibration() {
  for (const key of [
    `gazeCalibrationData:${examPlatform}`,
    "gazeCalibrationData",
  ]) {
    try {
      const calibration = JSON.parse(localStorage.getItem(key) || "null");
      if (!calibration || typeof calibration !== "object") continue;
      const savedPlatform =
        calibration.platform ||
        (key === "gazeCalibrationData"
          ? localStorage.getItem("gazeCalibrationPlatform")
          : examPlatform);
      if (savedPlatform && savedPlatform !== examPlatform) continue;
      if (
        calibration.version !== GazeCore.VERSION ||
        calibration.geometryOk !== true ||
        !Array.isArray(calibration.rows)
      ) {
        console.warn(`Skipping incompatible local calibration at ${key}.`);
        continue;
      }
      const sourceRows =
        Array.isArray(calibration.calibrationHistory) &&
        calibration.calibrationHistory.length
          ? calibration.calibrationHistory
          : calibration.rows;
      const spots = new Set(
        sourceRows
          .filter((row) => Number.isInteger(row?.spot))
          .map((row) => row.spot),
      );
      if (spots.size < 9) {
        console.warn(`Skipping incomplete local calibration at ${key}.`);
        continue;
      }
      return calibration;
    } catch (error) {
      console.warn(`Ignoring malformed local calibration at ${key}:`, error);
    }
  }
  return null;
}

if (profileSetupMode) {
  profileCalibrationBaseline = loadLocalProfileCalibration();
}
profileBaselineStatus = $("setupStatus");
if (profileSetupMode && profileCalibrationBaseline) {
  profileBaselineStatus.textContent =
    "Checking your saved calibration before starting…";
}

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
  [G[0], G[0]],
  [G[2], G[0]],
  [G[2], G[2]],
  [G[0], G[2]], // corners
  [G[1], G[0]],
  [G[2], G[1]],
  [G[1], G[2]],
  [G[0], G[1]], // edges
];
const PLAN = ORDER.map((_, spot) => ({ spot }));

const IS_MOBILE =
  examSetupMode || profileSetupMode
    ? examPlatform === "mobile"
    : detectedPlatform === "mobile";

// Wait for each dot's glide before collecting, then keep collecting through the full ring.
const GLIDE_MS = 550;
const SETTLE = GLIDE_MS + 350;
const RING_MS = IS_MOBILE ? 3000 : 2500;
const EXTRA_MS = 2000;
const COLLECT_MIN = RING_MS;
const COLLECT_MAX = RING_MS + EXTRA_MS;
const FRAMES_PER_AVG = 3;
const TARGET_SAMPLES = IS_MOBILE ? 8 : 10,
  MIN_SAMPLES = 5;
const SMOOTH_TAU_MS = 350,
  BLINK_EAR = IS_MOBILE ? 0.09 : 0.14;
const HEAD_COMP_DELAY_MS = 450,
  FUSE_TAU_MS = 750;
const MAX_GAZE_MOVEMENT = IS_MOBILE ? 0.4 : 0.35; // VERY RELAXED: validate the AVERAGE, not individual frames
const MAX_HEAD_MOVEMENT = IS_MOBILE ? 0.35 : 0.28; // VERY RELAXED: validate the AVERAGE
// Keep calibration and exam camera constraints aligned for each platform.
const CAM_W = IS_MOBILE ? 1280 : 1920, CAM_H = IS_MOBILE ? 720 : 1080;
const maxTrainPx = () =>
  Math.hypot(innerWidth, innerHeight) * (IS_MOBILE ? 0.22 : 0.15); // RELAXED: we're averaging multiple frames

YoloEye.cfg.blinkEar = BLINK_EAR;
YoloEye.cfg.headCompDelay = HEAD_COMP_DELAY_MS;
YoloEye.cfg.fuseTau = FUSE_TAU_MS;
YoloEye.cfg.inferenceIntervalMs = IS_MOBILE ? 125 : 100;
const smooth = YoloEye.makeSmoother(SMOOTH_TAU_MS, 1);

const cal = {
  active: false,
  i: 0,
  t0: 0,
  phase: "",
  samples: [],
  frameBuf: [],
  rows: [],
  fx: 0,
  fy: 0,
  invalidAttempts: 0,
  maxInvalidAttempts: 3,
  modelFails: 0,
  restartAll: false,
  baselineGaze: null,
  baselineHead: null,
  lastFeedback: "",
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
  if (headMove > MAX_HEAD_MOVEMENT * 0.7)
    showFeedback("Keep your head still!", "error");
  else if (gazeDrift > MAX_GAZE_MOVEMENT * 0.7)
    showFeedback("Keep looking at the dot!", "error");
  else if (headMove > MAX_HEAD_MOVEMENT * 0.4)
    showFeedback("Head moving - try to stay still", "warning");
  else if (gazeDrift > MAX_GAZE_MOVEMENT * 0.4)
    showFeedback("Eyes drifting - focus on the dot", "warning");
  else if (cal.samples.length > 3) clearFeedback();
}

// ---------------- validation ----------------
function validateSamples(samples) {
  if (samples.length < MIN_SAMPLES)
    return {
      valid: false,
      reason: `Not enough averaged eye-tracking readings (${samples.length} of ${MIN_SAMPLES}). Keep your face and eyes visible, then try again.`,
    };

  const gaze = Math.max(
    trimmedRange(samples.map((s) => s.ox)),
    trimmedRange(samples.map((s) => s.oy)),
  );
  if (gaze > MAX_GAZE_MOVEMENT)
    return {
      valid: false,
      reason: `Eyes moved too much! Keep looking at the dot.\n(gaze movement: ${(gaze * 100).toFixed(1)}% - limit: ${MAX_GAZE_MOVEMENT * 100}%)`,
    };

  const head = Math.max(
    range(samples.map((s) => s.yaw)),
    range(samples.map((s) => s.pitch)),
    range(samples.map((s) => s.roll)),
  );
  if (head > MAX_HEAD_MOVEMENT)
    return {
      valid: false,
      reason: `Head moved too much! Keep your head still.\n(head movement: ${((head * 180) / Math.PI).toFixed(1)}° - limit: ${((MAX_HEAD_MOVEMENT * 180) / Math.PI).toFixed(0)}°)`,
    };

  return { valid: true };
}

// drop noisy frames of ONE dot (outside ~6 MAD of that dot's median) — more aggressive outlier rejection
function cleanSamples(r) {
  const mx = med(r.map((x) => x.ox)),
    my = med(r.map((x) => x.oy));
  const dx = 6.0 * med(r.map((x) => Math.abs(x.ox - mx))) + 0.004; // INCREASED from 4.5 to 6.0
  const dy = 6.0 * med(r.map((x) => Math.abs(x.oy - my))) + 0.004;
  const kept = r.filter(
    (x) => Math.abs(x.ox - mx) <= dx && Math.abs(x.oy - my) <= dy,
  );
  return kept.length ? kept : r;
}

function validateFinalModel(rows, train, accuracy) {
  const MAXPX = maxTrainPx();
  if (train > MAXPX)
    return {
      valid: false,
      reason: `Calibration accuracy too low!\nError: ${train.toFixed(0)}px (max acceptable: ${MAXPX.toFixed(0)}px)\n\nPlease look directly at each dot.`,
    };

  const MAXLOO = maxTrainPx();
  if (accuracy > MAXLOO)
    return {
      valid: false,
      reason: `Calibration accuracy too low!\nHeld-out-position error: ${accuracy.toFixed(0)}px (max acceptable: ${MAXLOO.toFixed(0)}px)\n\nPlease look directly at each dot.`,
    };

  const unique = new Set(
    rows
      .filter((r) => r.stage === "still")
      .map((r) => `${r.ox.toFixed(2)},${r.oy.toFixed(2)}`),
  );
  if (unique.size < 7)
    return {
      valid: false,
      reason: `Not enough variation in gaze!\nOnly ${unique.size} distinct positions detected.\n\nPlease look at each dot carefully.`,
    };

  return { valid: true };
}

function showCalibrationError(message) {
  calMessage.innerHTML = `
    <div style="background: rgba(255,107,107,0.2); border: 2px solid #ff6b6b; border-radius: 8px; padding: 16px; max-width: 500px; margin: 0 auto;">
      <div style="font-size: 20px; margin-bottom: 8px;">Calibration Failed</div>
      <div style="font-size: 14px; line-height: 1.5; white-space: pre-line;">${message}</div>
      <div style="margin-top: 12px; font-size: 13px; color: #ffa0a0;">Attempt ${cal.invalidAttempts} of ${cal.maxInvalidAttempts}</div>
    </div>`;

  setTimeout(() => {
    if (cal.invalidAttempts >= cal.maxInvalidAttempts) {
      calMessage.innerHTML = `
        <div style="background: rgba(255,107,107,0.3); border: 2px solid #ff6b6b; border-radius: 8px; padding: 20px; max-width: 500px; margin: 0 auto;">
          <div style="font-size: 22px; margin-bottom: 12px;">Maximum Attempts Reached</div>
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
      if (cal.restartAll) {
        cal.i = 0;
        cal.rows = [];
      }
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
const RING_R = 20.5,
  RING_C = 2 * Math.PI * RING_R;

dot.insertAdjacentHTML(
  "beforeend",
  `
  <svg viewBox="0 0 44 44">
    <circle cx="22" cy="22" r="${RING_R}" fill="none" stroke="rgba(255,255,255,0.25)" stroke-width="3"/>
    <circle id="ringArc" cx="22" cy="22" r="${RING_R}" fill="none" stroke="#ffffff" stroke-width="3"
            stroke-dasharray="${RING_C}" stroke-dashoffset="${RING_C}"
            transform="rotate(-90 22 22)"/>
  </svg>`,
);
const ringArc = document.getElementById("ringArc");
const setRing = (p) =>
  ringArc.setAttribute("stroke-dashoffset", RING_C * (1 - p));

const ease = (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
let pos = null;
let glide = null;

function drawDot(x, y) {
  pos = { x, y };
  dot.style.transform = `translate3d(${x}px, ${y}px, 0) translate(-50%, -50%)`;
}

function placeDot(animate = true) {
  const x = cal.fx * innerWidth,
    y = cal.fy * innerHeight;
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
    setRing(
      cal.phase === "collect" ? Math.min(1, (now - cal.t0) / RING_MS) : 0,
    );
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
  calMessage.textContent =
    `Keep your face centered in the camera preview. Look at the dot and keep your head still (${cal.i + 1}/${PLAN.length})`;
}

function startCalibration() {
  if (profileSetupMode && !profileBaselineReady) {
    setupStatus.textContent = "Still loading your saved calibration. Please wait.";
    return;
  }
  if (profileSetupMode && !profileCalibrationBaseline) {
    profileCalibrationBaseline = loadLocalProfileCalibration();
  }
  localStorage.removeItem("gazeCalibrationData");
  sessionStorage.removeItem("gazeOnlineClicks");
  sessionStorage.removeItem("gazeBias");
  smooth.reset();
  dot.style.display = "block";
  Object.assign(cal, {
    active: true,
    i: 0,
    rows: [],
    modelFails: 0,
    invalidAttempts: 0,
  });
  document.body.classList.add("calibrating");
  mainScreen.classList.add("hidden");
  calibrationOverlay.classList.add("active");
  beginDot();
}

// Keep one robust sample per dot and session; these are the independent observations.
const MAX_CALIBRATION_SESSIONS = 4;
const MAX_IMPORTED_CALIBRATION_SESSIONS = 16;

function compactRows(rows, perSpot = 1) {
  const rd = (v) => Math.round(v * 1e4) / 1e4;
  const groups = new Map();
  const sessionOrder = [];
  rows.forEach((r) => {
    const sessionId = r.sessionId || "legacy";
    if (!sessionOrder.includes(sessionId)) sessionOrder.push(sessionId);
    const key = JSON.stringify([sessionId, r.spot, r.stage]);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(r);
  });
  const out = [];
  const retainedSessions = new Set(
    sessionOrder.slice(-MAX_CALIBRATION_SESSIONS),
  );
  for (const [key, arr] of groups) {
    const [sessionId] = JSON.parse(key);
    if (!retainedSessions.has(sessionId)) continue;
    const count = Math.min(arr.length, perSpot);
    for (let n = 0; n < count; n++) {
      const index =
        count === 1 ? 0 : Math.round((n * (arr.length - 1)) / (count - 1));
      const r = arr[index];
      const compact = {
        ox: rd(r.ox),
        oy: rd(r.oy),
        yaw: rd(r.yaw),
        pitch: rd(r.pitch),
        roll: rd(r.roll),
        cx: rd(r.cx),
        cy: rd(r.cy),
        scale: rd(r.scale),
        sx: r.sx,
        sy: r.sy,
        spot: r.spot,
        sessionId: r.sessionId || "legacy",
      };
      if (Number.isFinite(r.w)) compact.w = r.w;
      out.push(compact);
    }
  }
  return out;
}

function aggregateCalibrationSession(rows, sessionId) {
  const featureKeys = [
    "ox", "oy", "yaw", "pitch", "roll", "cx", "cy", "scale", "sx", "sy",
  ];
  const aggregated = [];
  for (let spot = 0; spot < PLAN.length; spot++) {
    const spotRows = rows.filter((row) => row.spot === spot);
    if (!spotRows.length) return null;
    const row = { spot, stage: "still", sessionId };
    for (const key of featureKeys) {
      row[key] = med(spotRows.map((sample) => sample[key]));
    }
    aggregated.push(row);
  }
  return aggregated;
}

function groupBySession(rows) {
  const groups = new Map();
  for (const row of rows) {
    if (!groups.has(row.sessionId)) groups.set(row.sessionId, []);
    groups.get(row.sessionId).push(row);
  }
  return groups;
}

function sessionDisagreement(rows) {
  const groups = groupBySession(rows);
  const ids = [...groups.keys()];
  const usable = ids.filter(
    (id) =>
      new Set(groups.get(id).map((row) => row.spot)).size === PLAN.length,
  );
  const models = new Map();
  for (const id of usable) {
    const sessionRows = groups.get(id);
    const linear = GazeCore.fit(sessionRows, false);
    const quadratic = GazeCore.fit(sessionRows, true);
    const model =
      GazeCore.looErr(sessionRows, true) < GazeCore.looErr(sessionRows, false)
        ? quadratic
        : linear;
    models.set(id, model);
  }

  const matrix = {};
  for (const trainId of usable) {
    matrix[trainId] = {};
    for (const testId of usable) {
      if (trainId !== testId) {
        matrix[trainId][testId] = GazeCore.trainErr(
          groups.get(testId),
          models.get(trainId),
        );
      }
    }
  }

  const scores = {};
  for (const id of usable) {
    const otherIds = usable.filter((otherId) => otherId !== id);
    scores[id] = otherIds.length
      ? otherIds.reduce(
          (sum, otherId) =>
            sum +
            (matrix[id][otherId] + matrix[otherId][id]) / 2,
          0,
        ) / otherIds.length
      : null;
  }
  return { ids, usable, matrix, scores };
}

function mergeCalibrationHistory(previousRows, currentRows) {
  let rows = [...previousRows, ...currentRows];
  const initialDisagreement = sessionDisagreement(rows);
  const dropped = [];
  const newestSessionId = currentRows[0]?.sessionId;

  while (new Set(rows.map((row) => row.sessionId)).size > MAX_CALIBRATION_SESSIONS) {
    const disagreement = sessionDisagreement(rows);
    const olderSessionIds = [...new Set(rows.map((row) => row.sessionId))]
      .filter((id) => id !== newestSessionId);
    const incompleteOlderSession = olderSessionIds.find(
      (id) => !disagreement.usable.includes(id),
    );
    const candidates = disagreement.usable.filter((id) => id !== newestSessionId);
    if (!incompleteOlderSession && !candidates.length) {
      throw new Error("Cannot prune calibration history: no complete session is usable.");
    }
    const worst = incompleteOlderSession || candidates.reduce((currentWorst, id) =>
      disagreement.scores[id] > disagreement.scores[currentWorst] ? id : currentWorst,
    );
    dropped.push(worst);
    rows = rows.filter((row) => row.sessionId !== worst);
  }

  const report = {
    sessions: initialDisagreement.ids.map((id) => ({
      sessionId: id,
      score: Number.isFinite(initialDisagreement.scores[id])
        ? Math.round(initialDisagreement.scores[id])
        : null,
      dropped: dropped.includes(id),
      isNew: id === newestSessionId,
    })),
    matrix: Object.fromEntries(
      Object.entries(initialDisagreement.matrix).map(([trainId, testErrors]) => [
        trainId,
        Object.fromEntries(
          Object.entries(testErrors).map(([testId, error]) => [
            testId,
            Math.round(error),
          ]),
        ),
      ]),
    ),
    droppedSessionIds: dropped,
  };
  return { rows, report };
}

function getCalibrationHistory(calibrationData) {
  if (!calibrationData) return [];
  if (calibrationData.version !== GazeCore.VERSION) {
    console.warn("Saved calibration version differs; starting a fresh calibration.");
    return [];
  }
  if (calibrationData.platform !== examPlatform) {
    console.warn("Saved calibration platform differs; starting a fresh calibration.");
    return [];
  }
  if (calibrationData.geometryOk !== true) {
    console.warn("Saved calibration geometry is invalid; starting a fresh calibration.");
    return [];
  }
  if (!isUsableCalibration(calibrationData)) {
    console.warn("Saved calibration structure is incomplete; starting a fresh calibration.");
    return [];
  }

  const sourceRows = Array.isArray(calibrationData.calibrationHistory) &&
      calibrationData.calibrationHistory.length
    ? calibrationData.calibrationHistory
    : calibrationData.rows;
  const required = [
    "ox", "oy", "yaw", "pitch", "roll", "cx", "cy", "scale", "sx", "sy",
  ];
  const validRows = sourceRows.filter(
    (row) =>
      Number.isInteger(row.spot) &&
      row.spot >= 0 &&
      row.spot < PLAN.length &&
      required.every((key) => Number.isFinite(row[key])),
  );
  if (!validRows.length) {
    console.warn("Saved calibration has no usable nine-point rows.");
    return [];
  }

  const legacySession =
    `legacy-${calibrationData.timestamp || "saved"}`;
  const sessions = new Map();
  for (const row of validRows) {
    const sessionId =
      typeof row.sessionId === "string" && row.sessionId
        ? row.sessionId
        : legacySession;
    if (!sessions.has(sessionId)) sessions.set(sessionId, []);
    sessions.get(sessionId).push(row);
  }

  const history = [];
  for (const [sessionId, rows] of sessions) {
    const sessionRows = aggregateCalibrationSession(rows, sessionId);
    if (!sessionRows) {
      console.warn(`Skipping incomplete saved calibration session: ${sessionId}`);
      continue;
    }
    history.push(...sessionRows);
  }
  if (!history.length) {
    console.warn("Saved calibration is missing one or more screen positions.");
  }
  const retainedSessions = new Set(
    [...new Set(history.map((row) => row.sessionId))].slice(
      -MAX_IMPORTED_CALIBRATION_SESSIONS,
    ),
  );
  return history.filter((row) => retainedSessions.has(row.sessionId));
}

function latestCalibrationSession(rows) {
  const sessions = [...new Set(rows.map((row) => row.sessionId))];
  if (!sessions.length) return [];
  const latestId = sessions[sessions.length - 1];
  return rows.filter((row) => row.sessionId === latestId);
}

function getCalibrationRows(calibrationData) {
  const history = getCalibrationHistory(calibrationData);
  if (!history.length) {
    return null;
  }
  return history;
}
// ---------------- geometry sanity check ----------------
// Starting guesses for an "average PC". Tune them from the console log (see below).
const GEOM_ENFORCE = true;
const GEOM_DEBUG = true; // false = log only, never block
const EYE_PER_RAD_X = IS_MOBILE ? 0.16 : 0.4; // phones: tiny iris movement
const EYE_PER_RAD_Y = IS_MOBILE ? 0.08 : 0.3;
const FACE_W_CM = 14.5;
const LONG_SIDE_FOV_DEG = IS_MOBILE ? 70 : 65; // FOV along the camera frame's LONG side
const NOISE_X = IS_MOBILE ? 0.012 : 0.003; // keypoint noise floor (eye-widths)
const NOISE_Y = IS_MOBILE ? 0.012 : 0.003;
const CSS_PX_PER_CM = IS_MOBILE ? 55 : 40;
// More forgiving gaze calibration
const OVER = IS_MOBILE ? 2.5 : 2.2;
const TOL_X = IS_MOBILE ? 1.5 : 1.3;
const TOL_Y = IS_MOBILE ? 1.5 : 1.6;
const UNDER = IS_MOBILE ? 0.12 : 0.15; // allowed deviation of each dot from its ideal position
const DOT_NAMES = [
  "center",
  "top-left",
  "top-right",
  "bottom-right",
  "bottom-left",
  "top",
  "right",
  "bottom",
  "left",
];

function validateGeometry(rows) {
  const by = [];
  for (let s = 0; s < ORDER.length; s++) {
    const r = rows.filter((x) => x.spot === s);
    if (!r.length)
      return {
        valid: false,
        reason: "Missing data for a calibration dot. Please try again.",
      };
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
  const expX =
    EYE_PER_RAD_X * Math.atan((edge * innerWidth) / CSS_PX_PER_CM / distCm);
  const expY =
    EYE_PER_RAD_Y * Math.atan((edge * innerHeight) / CSS_PX_PER_CM / distCm);

  // ---- template: where each dot should sit relative to the centre dot ----
  const dbg = [];
  const bad = [];
  if (Math.abs(hx) > 1e-3 && Math.abs(hy) > 1e-3) {
    const scaleX = Math.max(Math.abs(hx), expX),
      scaleY = Math.max(Math.abs(hy), expY);
    for (let s = 1; s < ORDER.length; s++) {
      const ix = (ORDER[s][0] - G[1]) / edge,
        iy = (ORDER[s][1] - G[1]) / edge; // -1, 0 or +1
      const dX = by[s].ox - by[0].ox,
        dY = by[s].oy - by[0].oy;
      const devX = Math.abs(dX - ix * hx),
        devY = Math.abs(dY - iy * hy); // absolute deviation
      const nx = dX / hx,
        ny = dY / hy;
      dbg.push(
        `${DOT_NAMES[s]}: nx ${nx.toFixed(2)} (ideal ${ix.toFixed(0)}), ny ${ny.toFixed(2)} (ideal ${iy.toFixed(0)})`,
      );
      if (devX > TOL_X * scaleX + NOISE_X || devY > TOL_Y * scaleY + NOISE_Y) {
        const reach = Math.hypot(nx, ny),
          ideal = Math.hypot(ix, iy) || 0.5;
        bad.push({
          s,
          why:
            reach > ideal
              ? "too far (past the screen?)"
              : "not far enough / wrong direction",
        });
      }
    }
  }
  console.log("dots:\n" + dbg.join("\n"));
  console.log(
    `geometry: dist≈${distCm.toFixed(0)}cm | hx ${hx.toFixed(3)} (expected ${expX.toFixed(3)}) | ` +
      `hy ${hy.toFixed(3)} (expected ${expY.toFixed(3)}) | bad dots: ${bad.map((b) => DOT_NAMES[b.s]).join(", ") || "none"}`,
  );
  if (!GEOM_ENFORCE) return { valid: true };

  const rx = Math.abs(hx) / expX,
    ry = Math.abs(hy) / expY; // measured ÷ expected
  const info = GEOM_DEBUG
    ? `\n\n[geometry: dist≈${distCm.toFixed(0)}cm | ` +
      `hx ${hx.toFixed(3)} (expected ${expX.toFixed(3)}, ${rx.toFixed(2)}×) | ` +
      `hy ${hy.toFixed(3)} (expected ${expY.toFixed(3)}, ${ry.toFixed(2)}×) | ` +
      `allowed ${UNDER}×–${OVER}× | ` +
      `bad dots: ${bad.map((b) => DOT_NAMES[b.s]).join(", ") || "none"}]\n` +
      dbg.join("\n")
    : "";

  if (Math.abs(hx) < 1e-3 || Math.abs(hy) < 1e-3)
    return {
      valid: false,
      reason:
        "Your eyes barely moved between dots.\nKeep your head still and look AT each dot." +
        info,
    };
  if (rx > OVER || ry > OVER)
    return {
      valid: false,
      reason:
        `You looked past the edges of the screen (${rx > OVER ? "left/right" : "up/down"}).\nLook directly AT each dot, not beyond it.` +
        info,
    };
  if (rx < UNDER || ry < UNDER)
    return {
      valid: false,
      reason:
        `Your eyes didn't move enough (${rx < UNDER ? "left/right" : "up/down"}).\nKeep your head still and move only your eyes to each dot.` +
        info,
    };
  if (bad.length)
    return {
      valid: false,
      reason:
        "These dots were not looked at correctly:\n" +
        bad.map((b) => `• ${DOT_NAMES[b.s]} dot: ${b.why}`).join("\n") +
        info,
    };
  return { valid: true };
}

function finishCalibration() {
  const currentRows = cal.rows;
  const geo = validateGeometry(currentRows);
  if (!geo.valid) {
    console.warn("Geometry rejected:", geo.reason);
    failAttempt(geo.reason, true);
    return;
  }
  const previousRows = profileSetupMode
    ? getCalibrationRows(profileCalibrationBaseline)
    : null;
  const sessionId = `session-${Date.now()}`;
  const currentSessionRows = aggregateCalibrationSession(
    currentRows,
    sessionId,
  );
  if (!currentSessionRows) {
    failAttempt("Calibration did not produce all nine dot positions.", true);
    return;
  }
  const evaluateCandidate = (label, rows) => {
    const modelLin = GazeCore.fit(rows, false);
    const modelQuad = GazeCore.fit(rows, true);
    const errs = {
      lin: {
        train: GazeCore.trainErr(rows, modelLin),
        loo: GazeCore.looErr(rows, false),
      },
      quad: {
        train: GazeCore.trainErr(rows, modelQuad),
        loo: GazeCore.looErr(rows, true),
      },
    };
    const best =
      IS_MOBILE && errs.lin.loo <= errs.quad.loo * 1.15
        ? "lin"
        : errs.quad.loo <= errs.lin.loo
          ? "quad"
          : "lin";
    const check = validateFinalModel(rows, errs[best].train, errs[best].loo);
    const still = rows.filter((row) => row.stage === "still");
    return {
      label,
      check,
      rows,
      modelLin,
      modelQuad,
      errs,
      best,
      headBase: {
        yaw: med(still.map((row) => row.yaw)),
        pitch: med(still.map((row) => row.pitch)),
        roll: med(still.map((row) => row.roll)),
      },
    };
  };

  const currentCandidate = evaluateCandidate("current", currentSessionRows);
  if (!currentCandidate.check.valid) {
    console.warn("Final model rejected:", currentCandidate.check.reason);
    failAttempt(currentCandidate.check.reason, true);
    return;
  }

  let selected = currentCandidate;
  let calibrationHistory = currentSessionRows;
  let sessionReport = {
    sessions: [
      {
        sessionId,
        score: null,
        dropped: false,
        isNew: true,
      },
    ],
    matrix: {},
    droppedSessionIds: [],
  };
  if (previousRows) {
    const merged = mergeCalibrationHistory(previousRows, currentSessionRows);
    calibrationHistory = merged.rows;
    sessionReport = merged.report;
    console.log("Calibration session disagreement (px, lower is closer):");
    console.table(sessionReport.sessions);
    console.log("Model trained on row session, tested on column session (px):");
    console.table(sessionReport.matrix);

    const previousCandidate = evaluateCandidate("previous", previousRows);
    if (previousCandidate.check.valid) {
      const previousSessionRows = latestCalibrationSession(previousRows);
      const previousModel =
        previousCandidate[previousCandidate.best === "lin" ? "modelLin" : "modelQuad"];
      const currentModel =
        currentCandidate[currentCandidate.best === "lin" ? "modelLin" : "modelQuad"];
      const crossSessionErrors = {
        previousOnCurrent: GazeCore.trainErr(currentSessionRows, previousModel),
        currentOnPrevious: GazeCore.trainErr(previousSessionRows, currentModel),
      };
      const crossSessionLimit = maxTrainPx();
      const sessionsAgree =
        crossSessionErrors.previousOnCurrent <= crossSessionLimit &&
        crossSessionErrors.currentOnPrevious <= crossSessionLimit;
      console.log(
        `Cross-session error: previous on new ${crossSessionErrors.previousOnCurrent.toFixed(0)}px, new on previous ${crossSessionErrors.currentOnPrevious.toFixed(0)}px (limit ${crossSessionLimit.toFixed(0)}px)`,
      );

      if (sessionsAgree) {
        const combinedCandidate = evaluateCandidate(
          "combined",
          calibrationHistory,
        );
        if (combinedCandidate.check.valid) {
          selected = combinedCandidate;
        } else {
          console.warn(
            "Combined calibration failed validation; saving the new session only:",
            combinedCandidate.check.reason,
          );
        }
      } else {
        console.warn(
          "Calibration sessions disagree; saving the new session as the active model and retaining prior sessions in history.",
        );
      }
    } else {
      console.warn(
        "Saved calibration did not pass model validation; saving the new session and retaining usable history.",
      );
    }
  } else if (profileSetupMode && profileCalibrationBaseline) {
    console.warn(
      "Saved calibration was incompatible or incomplete; saving the new session only.",
    );
  }

  if (!previousRows && profileSetupMode) {
    console.log("First calibration session saved; repeat nine-point runs to compare session agreement.");
  }

  const { rows, modelLin, modelQuad, errs, best, headBase } = selected;
  console.log(
    `Selected ${selected.label} calibration; train lin ${errs.lin.train.toFixed(0)} / quad ${errs.quad.train.toFixed(0)}px | loo lin ${errs.lin.loo.toFixed(0)} / quad ${errs.quad.loo.toFixed(0)}px`,
  );

  cal.active = false;
  document.body.classList.remove("calibrating");
  const calibrationData = {
    version: GazeCore.VERSION,
    source: "yolo",
    geometryOk: true,
    yoloCfg: YoloEye.exportCfg(),
    camera: { w: video.videoWidth, h: video.videoHeight },
    headBase,
    modelQuad,
    modelLin,
    best,
    smoothTauMs: SMOOTH_TAU_MS,
    timestamp: Date.now(),
    accuracy: errs[best].loo,
    rows: compactRows(rows),
    calibrationHistory: compactRows(calibrationHistory),
    sessionReport,
    platform: examPlatform,
  };
  localStorage.setItem("gazeCalibrationData", JSON.stringify(calibrationData));
  console.log(
    `✓ Saved ${best} model; leave-one-position-out error ${errs[best].loo.toFixed(0)}px`,
  );

  const calibrationMessage =
    selected.label === "combined"
      ? "Sessions agreed; calibration history was combined."
      : previousRows
        ? "Sessions differed; this new 9-point run is active. The worst older session was removed if over the 4-session limit."
        : profileCalibrationBaseline
          ? "Saved calibration was incompatible; this new 9-point run is active."
          : "New 9-point calibration saved.";
  calMessage.classList.add("complete");
  const header = document.createElement("div");
  header.className = "cal-complete-header";
  const icon = document.createElement("span");
  icon.className = "cal-complete-icon";
  icon.textContent = "✓";
  const heading = document.createElement("div");
  const title = document.createElement("strong");
  title.className = "cal-complete-title";
  title.textContent = "Calibration complete";
  const summary = document.createElement("p");
  summary.className = "cal-complete-copy";
  summary.textContent = calibrationMessage;
  heading.append(title, summary);
  header.append(icon, heading);
  const accuracy = document.createElement("div");
  accuracy.className = "cal-complete-accuracy";
  accuracy.textContent = `Accuracy · ${errs[best].loo.toFixed(0)} px`;
  calMessage.replaceChildren(header, accuracy);

  if (!profileSetupMode && sessionReport.sessions.length > 1) {
    const report = document.createElement("div");
    report.className = "cal-complete-report";
    sessionReport.sessions.forEach((session) => {
      const row = document.createElement("div");
      row.className = "cal-complete-report-row";
      const label = document.createElement("span");
      label.textContent = session.isNew ? "New session" : "Previous session";
      const value = document.createElement("strong");
      value.textContent =
        session.score == null
          ? "Need another run"
          : `${session.score} px${session.dropped ? " · removed" : ""}`;
      row.append(label, value);
      report.append(row);
    });
    calMessage.append(report);
  }
  dot.style.display = "none";
  if (profileSetupMode) {
    window.disposeGazeTracking?.();
    window.sendToHost({
      action: "saveCalibration",
      platform: examPlatform,
      calibrationData,
    });
  } else if (examSetupMode) {
    void saveExamCalibration(calibrationData);
  } else {
    window.disposeGazeTracking?.();
    window.sendToHost({ action: "calibrationComplete" });
    setTimeout(() => calibrationOverlay.classList.remove("active"), 2000);
  }
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
        console.warn("Samples rejected:", v.reason);
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
        console.log(
          `${DOT_NAMES[st.spot]}: ${cal.samples.length} samples, ${cleaned.length} kept`,
        );
      }
      cal.invalidAttempts = 0;
      cal.i++;
      cal.i >= PLAN.length ? finishCalibration() : beginDot();
    }
  }
}, 50);

// ---------------- UI wiring ----------------
let modelReady = false;
let examSetupState = examSetupMode ? "checking" : "calibrating";
let calibrationSetupCancelled = false;
let storedCalibrationRecord = null;
let modelLoadError = null;
let quickVerifyActive = false;
let quickVerifyStep = "idle";
let quickVerifySince = 0;
let quickVerifyBaselineYaw = 0;
let quickVerifyFirstTurnDirection = 0;
let quickVerifyYawSamples = [];
let quickVerifyEyeSamples = [];
let quickVerifyLastYoloAt = 0;
const QUICK_VERIFY_CENTER_MS = 2000;
const QUICK_VERIFY_EYE_SAMPLE_COUNT = 3;
const QUICK_VERIFY_MAX_EYE_JITTER = 0.12;
const QUICK_VERIFY_MAX_EAR_JITTER = 0.06;

function isUsableCalibration(data) {
  const required = [
    "ox",
    "oy",
    "yaw",
    "pitch",
    "roll",
    "cx",
    "cy",
    "scale",
    "sx",
    "sy",
  ];
  return (
    !!data &&
    data.version === GazeCore.VERSION &&
    data.geometryOk === true &&
    data.modelQuad &&
    typeof data.modelQuad === "object" &&
    data.modelLin &&
    typeof data.modelLin === "object" &&
    Array.isArray(data.rows) &&
    data.rows.length >= 9 &&
    data.rows.every(
      (row) =>
        row &&
        required.every((key) => Number.isFinite(row[key])) &&
        row.sx >= 0 &&
        row.sx <= 1 &&
        row.sy >= 0 &&
        row.sy <= 1,
    )
  );
}

function postExamSetupMessage(action, payload = {}) {
  if (!examSetupMode) return;
  const message = { action, ...payload };
  if (window.flutter_inappwebview?.callHandler) {
    void window.flutter_inappwebview.callHandler("flutterMessage", message);
  } else if (window.parent !== window) {
    window.parent.postMessage(message, location.origin);
  }
}

function requestFlutterSetupAction(action, payload = {}) {
  const message = { action, ...payload };
  if (window.flutter_inappwebview?.callHandler) {
    return window.flutter_inappwebview.callHandler("flutterMessage", message);
  }
  if (window.parent === window) {
    return Promise.reject(new Error("The calibration host is unavailable."));
  }

  const requestId = `gaze-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      window.removeEventListener("message", receiveResponse);
      reject(new Error("The calibration host did not respond within 90 seconds."));
    }, 90000);

    function receiveResponse(event) {
      let response = event.data;
      if (typeof response === "string") {
        try {
          response = JSON.parse(response);
        } catch {
          return;
        }
      }
      if (
        event.origin !== location.origin ||
        !response ||
        response.requestId !== requestId
      ) {
        return;
      }
      clearTimeout(timeout);
      window.removeEventListener("message", receiveResponse);
      if (response.error) reject(new Error(response.error));
      else resolve(response.result);
    }

    window.addEventListener("message", receiveResponse);
    window.parent.postMessage(
      JSON.stringify({ ...message, requestId }),
      location.origin,
    );
  });
}

function setLocalExamCalibration(calibrationData, record) {
  const key = `${examPlatform}:${calibrationData.timestamp || record?.calibratedAt || "saved"}`;
  localStorage.setItem(
    `gazeCalibrationData:${examPlatform}`,
    JSON.stringify(calibrationData),
  );
  localStorage.setItem("gazeCalibrationData", JSON.stringify(calibrationData));
  localStorage.setItem("gazeCalibrationPlatform", examPlatform);
  localStorage.setItem("gazeCalibrationLoadedKey", key);
  storedCalibrationRecord = record || {
    platform: examPlatform,
    calibrationData,
  };
  return key;
}

function showExamSetupError(message, { canCheckAgain = true } = {}) {
  examSetupState = canCheckAgain ? "error" : "calibrating";
  setSetupView("calibrate");
  document.documentElement.classList.remove("exam-setup-checking");
  document.body.classList.remove("exam-setup-checking");
  document.body.classList.remove("quick-verifying", "calibrating");
  quickVerifyScreen.classList.remove("visible");
  mainScreen.classList.remove("hidden");
  calibrationOverlay.classList.remove("active");
  setupStatus.textContent = message;
  startBtn.classList.remove("loading");
  startBtn.disabled = false;
  startLabel.textContent = canCheckAgain
    ? "Check calibration again"
    : "Start calibration again";
}

function showQuickVerification() {
  examSetupState = "verify";
  setSetupView("verify");
  document.documentElement.classList.remove("exam-setup-checking");
  document.body.classList.remove("exam-setup-checking");
  mainScreen.classList.add("hidden");
  calibrationOverlay.classList.remove("active");
  quickVerifyScreen.classList.add("visible");
  dot.style.display = "none";
  $("quickVerifyTitle").textContent = "Verify your camera";
  quickVerifyBegin.disabled = true;
  quickVerifyBeginLabel.textContent = "Loading camera…";
  quickVerifyStatus.textContent = "Loading gaze and face-tracking models…";
  void startTracking();
}

async function prepareExamSetup() {
  if (!examSetupMode) return;
  calibrationSetupCancelled = false;
  examSetupState = "checking";
  startBtn.disabled = true;
  startLabel.textContent = "Checking saved calibration…";
  try {
    const parentHost =
      window.parent !== window ? window.parent.examGazeHost : null;
    let status;
    if (typeof parentHost?.getCalibration === "function") {
      await window.parent.examGazeHostReady;
      status = await parentHost.getCalibration(examPlatform);
    } else {
      status = await requestFlutterSetupAction("getGazeCalibration", {
        platform: examPlatform,
      });
    }
    if (!status || (status.platform && status.platform !== examPlatform)) {
      throw new Error("The calibration service returned an invalid platform.");
    }

    const record = status.record || status.data || status;
    const calibrationData =
      status.calibrationData ||
      status.record?.calibrationData ||
      status.data?.calibrationData ||
      status.calibration ||
      status.data?.calibration ||
      status.record?.calibration ||
      (status.version ? status : null);
    const calibrationExists =
      status.exists === true ||
      calibrationData != null;
    if (calibrationExists && isUsableCalibration(calibrationData)) {
      localStorage.setItem(
        `gazeCalibrationData:${examPlatform}`,
        JSON.stringify(calibrationData),
      );
      localStorage.setItem(
        "gazeCalibrationData",
        JSON.stringify(calibrationData),
      );
      localStorage.setItem("gazeCalibrationPlatform", examPlatform);
      localStorage.setItem(
        "gazeCalibrationLoadedKey",
        `${examPlatform}:${calibrationData.timestamp || record?.calibratedAt || "saved"}`,
      );
      storedCalibrationRecord = record?.calibrationData
        ? record
        : { ...record, calibrationData };
      showQuickVerification();
      return;
    }

    localStorage.removeItem("gazeCalibrationData");
    localStorage.removeItem("gazeCalibrationPlatform");
    localStorage.removeItem("gazeCalibrationLoadedKey");
    sessionStorage.removeItem("gazeOnlineClicks");
    sessionStorage.removeItem("gazeBias");
    if (status.checkError) {
      throw new Error(status.checkError);
    }
    if (calibrationExists || status.hasInvalidRecord) {
      calMessage.textContent =
        `A calibration exists for ${examPlatform}, but it is incompatible with this version. Complete a new calibration to update it.`;
    } else {
      calMessage.textContent =
        "No saved calibration was found. Complete the nine-point calibration once to save it to your profile.";
    }
    examSetupState = "calibrating";
    setSetupView("calibrate");
    document.documentElement.classList.remove("exam-setup-checking");
    document.body.classList.remove("exam-setup-checking");
    document.body.classList.remove("quick-verifying");
    quickVerifyScreen.classList.remove("visible");
    mainScreen.classList.remove("hidden");
    startLabel.textContent = "Loading eye model…";
    startBtn.disabled = true;
    void startTracking();
  } catch (error) {
    console.error("Could not load saved gaze calibration:", error);
    showExamSetupError(
      `Could not check your saved calibration: ${error.message || "Check your connection, then select Check calibration again."}`,
    );
  }
}

async function saveExamCalibration(calibrationData) {
  examSetupState = "saving";
  setSetupView("verify");
  quickVerifyScreen.classList.add("visible");
  mainScreen.classList.add("hidden");
  calibrationOverlay.classList.remove("active");
  $("quickVerifyTitle").textContent = "Saving your calibration";
  quickVerifyStatus.textContent =
    "Saving your calibration securely to your profile…";

  try {
    const parentHost =
      window.parent !== window ? window.parent.examGazeHost : null;
    const record =
      typeof parentHost?.saveCalibration === "function"
        ? await parentHost.saveCalibration(examPlatform, calibrationData)
        : await requestFlutterSetupAction("saveGazeCalibration", {
            platform: examPlatform,
            calibrationData,
          });
    if (!record || record.success !== true) {
      throw new Error(record?.message || "The calibration was not saved.");
    }
    setLocalExamCalibration(calibrationData, record);
    quickVerifyStatus.textContent = "Calibration saved. Preparing your exam…";
    window.disposeGazeTracking?.();
    postExamSetupMessage("gazeSetupComplete", {
      platform: examPlatform,
      calibrationData,
      record,
      needsReload: false,
    });
  } catch (error) {
    console.error("Could not save gaze calibration:", error);
    $("quickVerifyTitle").textContent = "Calibration was not saved";
    setSetupView("calibrate");
    quickVerifyScreen.classList.remove("visible");
    mainScreen.classList.remove("hidden");
    setupStatus.textContent =
      `Your calibration was not saved: ${error.message || "Check your connection."} Start calibration again after fixing the issue.`;
    calibrationOverlay.classList.remove("active");
    examSetupState = "calibrating";
    startBtn.classList.remove("loading");
    startBtn.disabled = !modelReady;
    startLabel.textContent = "Start calibration again";
  }
}

function setQuickVerifyStatus(message) {
  quickVerifyStatus.textContent = message;
  if (quickVerifyActive) {
    quickVerifyBeginLabel.textContent = message;
  }
}

function processQuickVerification(
  sample,
  faceCount = 1,
  yoloAt = 0,
  eyeVisibility = null,
) {
  if (!quickVerifyActive) return;
  const { yaw, cx, cy, ear } = sample || {};
  if (
    faceCount !== 1 ||
    ![yaw, cx, cy, ear].every(Number.isFinite) ||
    ear < BLINK_EAR
  ) {
    quickVerifySince = 0;
    quickVerifyYawSamples = [];
    if (quickVerifyStep === "center" || quickVerifyStep === "eyeCheck") {
      quickVerifyStep = "center";
      quickVerifyEyeSamples = [];
    }
    setQuickVerifyStatus(
      faceCount > 1
        ? "Only one face should be visible."
        : "Keep your face visible and your eyes open.",
    );
    return;
  }

  const faceCentered = Math.abs(cx) < 0.14 && Math.abs(cy) < 0.16;
  const now = performance.now();
  if (quickVerifyStep === "center") {
    if (!faceCentered) {
      quickVerifySince = 0;
      quickVerifyYawSamples = [];
      setQuickVerifyStatus(
        "Move your face to the center of the camera preview.",
      );
      return;
    }
    if (!quickVerifySince) quickVerifySince = now;
    quickVerifyYawSamples.push(yaw);
    if (now - quickVerifySince >= QUICK_VERIFY_CENTER_MS) {
      const sortedYaw = [...quickVerifyYawSamples].sort((a, b) => a - b);
      quickVerifyBaselineYaw = sortedYaw[Math.floor(sortedYaw.length / 2)];
      quickVerifyStep = "eyeCheck";
      quickVerifySince = 0;
      quickVerifyEyeSamples = [];
      quickVerifyLastYoloAt = YoloEye.lastGazeAt;
      setQuickVerifyStatus(
        "Face centered. Hold still while YOLO checks both eyes…",
      );
    } else {
      setQuickVerifyStatus("Keep your face centered and eyes open for 2 seconds…");
    }
    return;
  }

  if (quickVerifyStep === "eyeCheck") {
    if (Math.abs(cx) > 0.14 || Math.abs(cy) > 0.16) {
      quickVerifyStep = "center";
      quickVerifySince = 0;
      quickVerifyYawSamples = [];
      quickVerifyEyeSamples = [];
      setQuickVerifyStatus(
        "Keep your face centered while both eyes are checked.",
      );
      return;
    }
    if (!Number.isFinite(yoloAt) || yoloAt <= quickVerifyLastYoloAt) return;
    quickVerifyLastYoloAt = yoloAt;

    if (!eyeVisibility?.visible || !Array.isArray(eyeVisibility.eyes)) {
      quickVerifyEyeSamples = [];
      setQuickVerifyStatus(
        eyeVisibility?.reason ||
          "Both eyes must be open, clear, and in focus. Hold still while YOLO checks again.",
      );
      return;
    }

    quickVerifyEyeSamples.push({
      eyes: eyeVisibility.eyes.map((eye) => ({
        ox: eye.ox,
        oy: eye.oy,
        ear: eye.ear,
      })),
    });
    if (quickVerifyEyeSamples.length < QUICK_VERIFY_EYE_SAMPLE_COUNT) {
      setQuickVerifyStatus(
        `Both eyes detected. Checking stability (${quickVerifyEyeSamples.length}/${QUICK_VERIFY_EYE_SAMPLE_COUNT})…`,
      );
      return;
    }

    const average = (values) =>
      values.reduce((sum, value) => sum + value, 0) /
      quickVerifyEyeSamples.length;
    const eyeAverages = [0, 1].map((lab) => ({
      ox: average(quickVerifyEyeSamples.map((reading) => reading.eyes[lab].ox)),
      oy: average(quickVerifyEyeSamples.map((reading) => reading.eyes[lab].oy)),
      ear: average(quickVerifyEyeSamples.map((reading) => reading.eyes[lab].ear)),
    }));
    const gazeJitter = Math.max(
      ...quickVerifyEyeSamples.flatMap((reading) =>
        reading.eyes.flatMap((eye, lab) => [
          Math.abs(eye.ox - eyeAverages[lab].ox),
          Math.abs(eye.oy - eyeAverages[lab].oy),
        ]),
      ),
    );
    const eyelidJitter = Math.max(
      ...quickVerifyEyeSamples.flatMap((reading) =>
        reading.eyes.map((eye, lab) =>
          Math.abs(eye.ear - eyeAverages[lab].ear),
        ),
      ),
    );
    if (
      gazeJitter > QUICK_VERIFY_MAX_EYE_JITTER ||
      eyelidJitter > QUICK_VERIFY_MAX_EAR_JITTER
    ) {
      quickVerifyEyeSamples = [];
      setQuickVerifyStatus(
        "Eye tracking is too unsteady. Improve the lighting, keep both eyes open, and hold still.",
      );
      return;
    }

    quickVerifyStep = "firstTurn";
    quickVerifySince = 0;
    setQuickVerifyStatus("Both eyes are clear and steady. Gently turn your head to one side…");
    return;
  }

  if (Math.abs(cx) > 0.22 || Math.abs(cy) > 0.24) {
    quickVerifySince = 0;
    setQuickVerifyStatus("Keep your face in view while turning your head.");
    return;
  }

  const yawDelta = yaw - quickVerifyBaselineYaw;
  if (quickVerifyStep === "firstTurn") {
    if (Math.abs(yawDelta) < 0.1) {
      quickVerifySince = 0;
      setQuickVerifyStatus("Gently turn your head to one side…");
      return;
    }
    if (!quickVerifySince) quickVerifySince = now;
    if (now - quickVerifySince >= 300) {
      quickVerifyFirstTurnDirection = Math.sign(yawDelta);
      quickVerifyStep = "oppositeTurn";
      quickVerifySince = 0;
      setQuickVerifyStatus(
        "Good. Now turn your head to the opposite side…",
      );
    }
    return;
  }

  if (quickVerifyStep === "oppositeTurn") {
    if (yawDelta * quickVerifyFirstTurnDirection > -0.1) {
      quickVerifySince = 0;
      setQuickVerifyStatus("Turn your head to the opposite side…");
      return;
    }
    if (!quickVerifySince) quickVerifySince = now;
    if (now - quickVerifySince >= 300) {
      quickVerifyStep = "return";
      quickVerifySince = 0;
      setQuickVerifyStatus("Now face forward and hold still…");
    }
    return;
  }

  if (quickVerifyStep === "return") {
    if (!faceCentered || Math.abs(yawDelta) > 0.08) {
      quickVerifySince = 0;
      setQuickVerifyStatus("Face forward and center yourself again…");
      return;
    }
    if (!quickVerifySince) quickVerifySince = now;
    if (now - quickVerifySince >= 500) {
      quickVerifyActive = false;
      quickVerifyStep = "done";
      document.body.classList.remove("quick-verifying");
      setQuickVerifyStatus("Face verification passed. Preparing your exam…");
      quickVerifyBeginLabel.textContent = "Face verification passed";
      window.disposeGazeTracking?.();
      postExamSetupMessage("gazeSetupComplete", {
        platform: examPlatform,
        calibrationData: storedCalibrationRecord.calibrationData,
        record: storedCalibrationRecord,
        needsReload: false,
      });
    }
  }
}

function updateCalibrationStartButton() {
  if (!modelReady) return;
  startBtn.classList.remove("loading");
  if (examSetupState === "checking") {
    startBtn.disabled = true;
    startLabel.textContent = "Checking saved calibration…";
  } else if (examSetupState === "calibrating") {
    startBtn.disabled = profileSetupMode && !profileBaselineReady;
    startLabel.textContent =
      profileSetupMode && !profileBaselineReady
        ? "Loading saved calibration…"
        : "Start 9-Point Calibration";
  } else if (examSetupState === "error") {
    startBtn.disabled = false;
    startLabel.textContent = "Check calibration again";
  }
  if (examSetupState === "verify") {
    quickVerifyStatus.textContent =
      "Camera ready. Center your face in the oval, then select Start face verification.";
    quickVerifyBegin.disabled = false;
    quickVerifyBeginLabel.textContent = "Start face verification";
  }
}

function setReady() {
  if (modelReady) return;
  modelReady = true;
  updateCalibrationStartButton();
}

function startQuickVerification() {
  if (
    !modelReady ||
    examSetupState !== "verify" ||
    quickVerifyActive
  ) {
    return;
  }
  quickVerifyActive = true;
  quickVerifyStep = "center";
  quickVerifySince = 0;
  quickVerifyBaselineYaw = 0;
  quickVerifyFirstTurnDirection = 0;
  quickVerifyYawSamples = [];
  quickVerifyEyeSamples = [];
  quickVerifyLastYoloAt = YoloEye.lastGazeAt;
  document.body.classList.add("quick-verifying");
  quickVerifyBegin.disabled = true;
  setQuickVerifyStatus(
    "Center your face in the preview, keep both eyes open, and hold still for 2 seconds.",
  );
}

quickVerifyBegin.addEventListener("click", startQuickVerification);
function setLoadError(e) {
  console.error("Calibration setup failed:", e);
  modelLoadError = e;
  startBtn.classList.remove("loading");
  startLabel.textContent = "Camera or model failed to load. Reload the page.";
  if (examSetupMode) {
    showExamSetupError(
      `Camera or model failed to load: ${e.message || "Reload the page and check camera permission."}`,
    );
    startLabel.textContent = "Reload setup";
  }
}

mainScreen.addEventListener("click", (e) => {
  if (e.target !== mainScreen) return;
  cancelCalibrationSetup();
});

quickVerifyScreen.addEventListener("click", (e) => {
  if (e.target !== quickVerifyScreen) return;
  cancelCalibrationSetup();
});

calibrationOverlay.addEventListener("click", (e) => {
  if (e.target !== calibrationOverlay) return;
  cancelCalibrationSetup();
});

function cancelCalibrationSetup() {
  if (!examSetupMode && !profileSetupMode) {
    window.disposeGazeTracking?.();
    window.sendToHost({ action: "calibrationCancelled" });
    return;
  }
  if (calibrationSetupCancelled) return;
  calibrationSetupCancelled = true;
  window.disposeGazeTracking?.();
  if (examSetupMode) {
    postExamSetupMessage("calibrationCancelled");
  } else {
    window.sendToHost({ action: "calibrationCancelled" });
  }
}
startBtn.onclick = () => {
  if (examSetupMode && examSetupState === "error") {
    if (modelLoadError) {
      location.reload();
      return;
    }
    void prepareExamSetup();
    return;
  }
  if (!modelReady) return;
  if (!examSetupMode || examSetupState === "calibrating") startCalibration();
};
// ---------------- MediaPipe (face + head pose) ----------------
const fm = new FaceMesh({
  locateFile: (f) => `https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh/${f}`,
});
const faceInputCropper = GazeCore.createFaceInputCropper();
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
  maxNumFaces: examSetupMode ? 2 : 1,
  refineLandmarks: true, // GazeCore.extract still reads iris landmarks for the head features
  minDetectionConfidence: 0.55,
  minTrackingConfidence: 0.55,
});

let busy = false; // the YOLO step is async and slower than a camera frame: drop frames while it runs
let trackingStartPromise = null;
function startTracking() {
  if (trackingStartPromise) return trackingStartPromise;
  trackingStartPromise = (async () => {
    try {
      startLabel.textContent = "Loading eye model…";
      if (examSetupState === "verify") {
        setQuickVerifyStatus("Loading the eye-tracking model…");
      }
      await YoloEye.init();
      if (trackingDisposed) return;
      startLabel.textContent = "Loading face detector…";
      if (examSetupState === "verify") {
        setQuickVerifyStatus("Eye model ready. Loading the face mesh…");
      }
      await fm.initialize();
      if (trackingDisposed) {
        await fm.close();
        return;
      }
      startLabel.textContent = "Starting camera…";
      if (examSetupState === "verify") {
        setQuickVerifyStatus("Face mesh ready. Starting your camera…");
      }
      calibrationCamera = new Camera(video, {
        onFrame: async () => {
          await fm.send({ image: faceInputCropper.prepare(video) });
        },
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
  return trackingStartPromise;
}
fm.onResults(async (res) => {
  res = faceInputCropper.mapResults(res);
  if (trackingDisposed || busy || !YoloEye.ready) return;
  busy = true;
  try {
    setReady();
    if (
      canvas.width !== (video.videoWidth || video.clientWidth) ||
      canvas.height !== (video.videoHeight || video.clientHeight)
    ) {
      canvas.width = video.videoWidth || video.clientWidth;
      canvas.height = video.videoHeight || video.clientHeight;
    }
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    if (!res.multiFaceLandmarks?.length) {
      processQuickVerification(null, 0);
      return;
    }
    if (quickVerifyActive && res.multiFaceLandmarks.length > 1) {
      processQuickVerification(null, 2);
      return;
    }

    const lm = res.multiFaceLandmarks[0];
    const W = video.videoWidth,
      H = video.videoHeight;
    if (!W) return;

    if (
      typeof drawConnectors === "function" &&
      typeof FACEMESH_TESSELATION !== "undefined"
    ) {
      ctx.save();
      drawConnectors(ctx, lm, FACEMESH_TESSELATION, {
        color: "#72e0a7",
        lineWidth: Math.max(1, W / 1600),
      });
      ctx.restore();
    }

    const faceSample = GazeCore.extract(lm, W, H);
    if (quickVerifyActive && quickVerifyStep !== "eyeCheck") {
      processQuickVerification(faceSample);
      return;
    }

    const raw = await YoloEye.extract(lm, W, H, video); // returns last valid result if busy/failed
    if (YoloEye.debugEnabled)
      YoloEye.drawKeypoints(
        ctx,
        YoloEye.lastGaze,
        canvas.width / W,
        canvas.height / H,
      );

    if (quickVerifyActive) {
      processQuickVerification(
        faceSample,
        1,
        YoloEye.lastGazeAt,
        YoloEye.checkEyeVisibility(lm, W, H, video),
      );
      return;
    }
    if (!raw) return; // only skip if never had a valid result

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

if (examSetupMode) {
  void prepareExamSetup();
} else {
  void startTracking();
}
