// Loaded by exam.html after gaze-core.js and yolo-eye.js. Trusted, stable exam clicks provide
// additional gaze labels and are kept only for the current exam session.
//
// Camera / face protection added here:
//   1. Face lost for FACE_LOST_MS             -> strike
//   2. Camera stalled / ended / muted         -> strike (watchdog + track events)
//   3. Eyes closed / low EAR for BLINK_MAX_MS -> treated as looking away (no more free pass)
//   4. More than one face in frame            -> strike

// FaceMesh drawing utilities
const FACEMESH_TESSELATION = [
  [127,34],[34,139],[139,127],[11,0],[0,37],[37,11],[232,231],[231,120],[120,232],
  [72,37],[37,39],[39,72],[128,121],[121,47],[47,128],[232,121],[121,128],[128,232],
  [104,69],[69,67],[67,104],[175,171],[171,148],[148,175],[118,50],[50,101],[101,118],
  [73,39],[39,40],[40,73],[9,151],[151,108],[108,9],[48,115],[115,131],[131,48],
  [194,204],[204,211],[211,194],[74,40],[40,185],[185,74],[80,42],[42,183],[183,80],
  [40,92],[92,186],[186,40],[230,229],[229,118],[118,230],[202,212],[212,214],[214,202],
  [83,18],[18,17],[17,83],[76,61],[61,146],[146,76],[160,29],[29,30],[30,160],
  [56,157],[157,173],[173,56],[106,204],[204,194],[194,106],[135,214],[214,192],[192,135],
  [203,165],[165,98],[98,203],[21,71],[71,68],[68,21],[51,45],[45,4],[4,51],
  [144,24],[24,23],[23,144],[77,146],[146,91],[91,77],[205,50],[50,187],[187,205],
  [201,200],[200,18],[18,201],[91,106],[106,182],[182,91],[90,91],[91,181],[181,90],
  [85,84],[84,17],[17,85],[206,203],[203,36],[36,206],[148,171],[171,140],[140,148],
  [92,40],[40,39],[39,92],[193,189],[189,244],[244,193],[159,158],[158,28],[28,159],
  [247,246],[246,161],[161,247],[236,3],[3,196],[196,236],[54,68],[68,104],[104,54],
  [193,168],[168,8],[8,193],[117,228],[228,31],[31,117],[189,193],[193,55],[55,189],
  [98,97],[97,99],[99,98],[126,47],[47,100],[100,126],[166,79],[79,218],[218,166],
  [155,154],[154,26],[26,155],[209,49],[49,131],[131,209],[135,136],[136,150],[150,135],
  [47,126],[126,217],[217,47],[223,52],[52,53],[53,223],[45,51],[51,134],[134,45],
  [211,170],[170,140],[140,211],[67,69],[69,108],[108,67],[43,106],[106,91],[91,43],
  [230,119],[119,120],[120,230],[226,130],[130,247],[247,226],[63,53],[53,52],[52,63],
  [238,20],[20,242],[242,238],[46,70],[70,156],[156,46],[78,62],[62,96],[96,78],
  [46,53],[53,63],[63,46],[143,34],[34,227],[227,143],[123,117],[117,111],[111,123],
  [44,125],[125,19],[19,44],[236,134],[134,51],[51,236],[216,206],[206,205],[205,216],
  [154,153],[153,22],[22,154],[39,37],[37,167],[167,39],[200,201],[201,208],[208,200],
  [36,142],[142,100],[100,36],[57,212],[212,202],[202,57],[20,60],[60,99],[99,20],
  [28,158],[158,157],[157,28],[35,226],[226,113],[113,35],[160,159],[159,27],[27,160],
  [204,202],[202,210],[210,204],[113,225],[225,46],[46,113],[43,202],[202,204],[204,43],
  [62,76],[76,77],[77,62],[137,123],[123,116],[116,137],[41,38],[38,72],[72,41],
  [203,129],[129,142],[142,203],[64,98],[98,240],[240,64],[49,102],[102,64],[64,49],
  [41,73],[73,74],[74,41],[212,216],[216,207],[207,212],[42,74],[74,184],[184,42],
  [169,170],[170,211],[211,169],[170,149],[149,176],[176,170],[105,66],[66,69],[69,105],
  [122,6],[6,168],[168,122],[123,147],[147,187],[187,123],[96,77],[77,90],[90,96],
  [65,55],[55,107],[107,65],[89,90],[90,180],[180,89],[101,100],[100,120],[120,101],
  [63,105],[105,104],[104,63],[93,137],[137,227],[227,93],[15,86],[86,85],[85,15],
  [129,102],[102,49],[49,129],[14,87],[87,86],[86,14],[55,8],[8,9],[9,55],
  [100,47],[47,121],[121,100],[145,23],[23,22],[22,145],[88,89],[89,179],[179,88],
  [6,122],[122,196],[196,6],[88,95],[95,96],[96,88],[138,172],[172,136],[136,138],
  [215,58],[58,172],[172,215],[115,48],[48,219],[219,115],[42,80],[80,81],[81,42],
  [195,3],[3,51],[51,195],[43,146],[146,61],[61,43],[171,175],[175,199],[199,171],
  [81,82],[82,38],[38,81],[53,46],[46,225],[225,53],[144,163],[163,110],[110,144],
  [52,65],[65,66],[66,52],[229,228],[228,117],[117,229],[34,127],[127,234],[234,34],
  [107,108],[108,69],[69,107],[109,108],[108,151],[151,109],[48,64],[64,235],[235,48],
  [62,78],[78,191],[191,62],[129,209],[209,126],[126,129],[111,35],[35,143],[143,111],
  [117,123],[123,50],[50,117],[222,65],[65,52],[52,222],[19,125],[125,141],[141,19],
  [221,55],[55,65],[65,221],[3,195],[195,197],[197,3],[25,7],[7,33],[33,25],
  [220,237],[237,44],[44,220],[70,71],[71,139],[139,70],[122,193],[193,245],[245,122],
  [247,130],[130,33],[33,247],[71,21],[21,162],[162,71],[170,169],[169,150],[150,170],
  [188,174],[174,196],[196,188],[216,186],[186,92],[92,216],[2,97],[97,167],[167,2],
  [141,125],[125,241],[241,141],[164,167],[167,37],[37,164],[72,38],[38,12],[12,72],
  [38,82],[82,13],[13,38],[63,68],[68,71],[71,63],[226,35],[35,111],[111,226],
  [101,50],[50,205],[205,101],[206,92],[92,165],[165,206],[209,198],[198,217],[217,209],
  [165,167],[167,97],[97,165],[220,115],[115,218],[218,220],[133,112],[112,243],[243,133],
  [239,238],[238,241],[241,239],[214,135],[135,169],[169,214],[190,173],[173,133],[133,190],
  [171,208],[208,32],[32,171],[125,44],[44,237],[237,125],[86,87],[87,178],[178,86],
  [85,86],[86,179],[179,85],[84,85],[85,180],[180,84],[83,84],[84,181],[181,83],
  [201,83],[83,182],[182,201],[137,93],[93,132],[132,137],[76,62],[62,183],[183,76],
  [61,76],[76,184],[184,61],[57,61],[61,185],[185,57],[212,57],[57,186],[186,212],
  [214,207],[207,187],[187,214],[34,143],[143,156],[156,34],[79,239],[239,237],[237,79],
  [123,137],[137,177],[177,123],[44,1],[1,4],[4,44],[201,194],[194,32],[32,201],
  [64,102],[102,129],[129,64],[213,215],[215,138],[138,213],[59,166],[166,219],[219,59],
  [242,99],[99,97],[97,242],[2,94],[94,141],[141,2],[75,59],[59,235],[235,75],
  [24,110],[110,228],[228,24],[25,130],[130,226],[226,25],[23,24],[24,229],[229,23],
  [22,23],[23,230],[230,22],[26,22],[22,231],[231,26],[112,26],[26,232],[232,112],
  [189,190],[190,243],[243,189],[221,56],[56,190],[190,221],[28,56],[56,221],[221,28],
  [27,28],[28,222],[222,27],[29,27],[27,223],[223,29],[30,29],[29,224],[224,30],
  [247,30],[30,225],[225,247],[238,79],[79,20],[20,238],[166,59],[59,75],[75,166],
  [60,75],[75,240],[240,60],[147,177],[177,215],[215,147],[20,79],[79,166],[166,20],
  [187,147],[147,213],[213,187],[112,233],[233,244],[244,112],[233,128],[128,245],[245,233],
  [128,114],[114,188],[188,128],[114,217],[217,174],[174,114],[131,115],[115,220],[220,131],
  [217,198],[198,236],[236,217],[198,131],[131,134],[134,198],[177,132],[132,58],[58,177],
  [143,35],[35,124],[124,143],[110,163],[163,7],[7,110],[228,110],[110,25],[25,228],
  [356,389],[389,368],[368,356],[11,302],[302,267],[267,11],[452,350],[350,349],[349,452],
  [302,303],[303,269],[269,302],[357,343],[343,277],[277,357],[452,343],[343,357],[357,452],
  [333,298],[298,296],[296,333],[389,400],[400,377],[377,389],[278,279],[279,277],[277,278],
  [395,344],[344,440],[440,395],[344,330],[330,269],[269,344],[303,302],[302,408],[408,303],
  [269,303],[303,410],[410,269],[338,337],[337,336],[336,338],[337,299],[299,338],[338,337],
  [279,420],[420,360],[360,279],[279,394],[394,379],[379,279],[378,379],[379,394],[394,378],
  [395,379],[379,378],[378,395],[400,377],[377,152],[152,400],[379,395],[395,431],[431,379],
  [394,422],[422,430],[430,394],[395,318],[318,279],[279,395],[359,279],[279,277],[277,359],
  [350,452],[452,381],[381,350],[295,331],[331,278],[278,295],[305,292],[292,308],[308,305],
  [291,292],[292,285],[285,291],[328,324],[324,307],[307,328],[449,350],[350,381],[381,449],
  [346,340],[340,385],[385,346],[372,345],[345,352],[352,372],[376,433],[433,416],[416,376],
  [291,285],[285,295],[295,291],[311,313],[313,319],[319,311],[374,361],[361,405],[405,374],
  [321,294],[294,358],[358,321],[277,343],[343,452],[452,277],[440,344],[344,386],[386,440],
  [389,390],[390,279],[279,389],[356,316],[316,403],[403,356],[319,325],[325,304],[304,319],
  [299,333],[333,297],[297,299],[389,356],[356,383],[383,389],[356,403],[403,382],[382,356],
  [352,345],[345,361],[361,352],[345,465],[465,344],[344,345],[372,368],[368,401],[401,372],
  [376,307],[307,405],[405,376],[405,321],[321,375],[375,405],[291,410],[410,292],[292,291],
  [328,409],[409,410],[410,328],[319,304],[304,320],[320,319],[297,331],[331,294],[294,297],
  [331,384],[384,298],[298,331],[324,323],[323,308],[308,324],[324,308],[308,307],[307,324],
  [390,373],[373,387],[387,390],[387,373],[373,386],[386,387],[387,386],[386,337],[337,387],
  [336,296],[296,336],[336,296],[296,285],[285,336],[321,375],[375,427],[427,321],
  [421,322],[322,294],[294,421],[428,355],[355,416],[416,428],[429,355],[355,437],[437,429],
  [391,327],[327,326],[326,391],[326,2],[2,97],[97,326],[2,326],[326,327],[327,2],
  [360,420],[420,437],[437,360],[299,333],[333,332],[332,299],[332,333],[333,331],[331,332]
];

function drawFaceMesh(ctx, landmarks, width, height) {
  ctx.strokeStyle = 'rgba(8, 123, 79, 0.25)';
  ctx.lineWidth = 1;
  
  // Draw tesselation connections
  for (const [start, end] of FACEMESH_TESSELATION) {
    const startPoint = landmarks[start];
    const endPoint = landmarks[end];
    
    if (startPoint && endPoint) {
      ctx.beginPath();
      ctx.moveTo(startPoint.x * width, startPoint.y * height);
      ctx.lineTo(endPoint.x * width, endPoint.y * height);
      ctx.stroke();
    }
  }
  
  // Draw landmark points
  ctx.fillStyle = 'rgba(8, 123, 79, 0.5)';
  for (const landmark of landmarks) {
    ctx.beginPath();
    ctx.arc(landmark.x * width, landmark.y * height, 1, 0, 2 * Math.PI);
    ctx.fill();
  }
}

const BLINK_EAR = 0.11; // Match YoloEye.cfg.blinkEar to prevent freeze-then-jump
const AWAY_MS = 700; // must be outside the safe zone this long before a strike
const HEAD_LIMIT_RAD = 0.7; // ≈40° from the calibrated pose = "away" no matter where the eyes point

const BLINK_MAX_MS = 1500; // a real blink is ~100-400 ms; longer = eyes closed / looking down
const BLINK_REL = 0.70;
const BLINK_WIN_MS = 1500;
const BLINK_SETTLE_MS = 120;
const BLINK_VEL = 1.5;
const BLINK_VEL_MIN_EAR_RATIO = 0.9;
const BLINK_WARM_FRAMES = 1;
let blinkWarmFrames = 0;
let blinkHoldGeneration = 0;
let blinkHoldActive = false;
window.gazeBlinkHolding = false;
const FACE_LOST_MS = 1500; // tolerate brief tracking drops before striking
const FACE_LOSS_SUBMIT_MS = 5000;
const MULTI_FACE_MS = 1500; // second face must persist this long before a strike
const CAMERA_STALL_MS = 3000; // no FaceMesh results for this long = camera stopped/blocked
const STALL_STRIKE_INTERVAL_MS = 5000; // at most one camera-loss strike per interval
const WATCHDOG_INTERVAL_MS = 1000;

// Allow a second face to be reported so it can be detected (exam.html sets 1).
const FACE_MIN_CONF = 0.55; // MediaPipe only return
// s a face whose confidence is at or above this
faceMesh.setOptions({
  maxNumFaces: 2,
  refineLandmarks: true,
  minDetectionConfidence: FACE_MIN_CONF,
  minTrackingConfidence: FACE_MIN_CONF,
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
const baseModel = model;
const headBase = calData?.headBase || { yaw: 0, pitch: 0, roll: 0 };

// Use the SAME eye-feature settings (refine / crop averaging / distance compensation) the calibration used.
YoloEye.applyCfg(calData?.yoloCfg);

// EXAM-ONLY overrides for smoother tracking (not saved to exportCfg, calibration keeps its own)
YoloEye.cfg.minCut = 0.8;       // lower cutoff adds steadiness while the eyes are still
YoloEye.cfg.beta = 4;            // was 6 - less aggressive opening on movement
YoloEye.cfg.boxSmoothing = 0.6;  // was 0.85 - eye crop follows movement faster
YoloEye.cfg.blinkEar = 0.11;     // was 0.14 - fixes bottom gaze (looking down drops EAR)
YoloEye.cfg.disagree = 0.2;      // was 0.10 - average both eyes more often (less switching)

// MUST be the YOLO smoother (frame averaging + 1-Euro on the eye offset, then head + distance correction).
// GazeCore.makeSmoother does none of that, so the exam would feed the model different features
// than the ones it was calibrated on and the bubble ends up stuck at an edge.
// Use a shorter exam-only smoothing window to keep gaze responsive.
const examSmoothTauMs = Math.max(
  Number.isFinite(calData?.smoothTauMs) ? calData.smoothTauMs : 250,
  450,
);
const smoothGaze = YoloEye.makeSmoother(examSmoothTauMs, 3);
const yoloReady = () => (typeof YoloEye.isReady === "function" ? YoloEye.isReady() : !!YoloEye.ready);
let yoloBusy = false; // the YOLO step is slower than a camera frame: don't let frames pile up
// ---------------------------------------------------------------------------- PART 1
const HEAD_GAIN = 0.05;        // 0 = head pose never moves the dot, 1 = the full calibrated head terms
const GAZE_BIAS_X = -0.03;
const R_MIN = 28;              // px: bubble radius when the model is calm
const R_BASE_MAX = 60;         // px: cap calibration-derived radius so a good calibration can look smaller
const R_MAX = 120;             // px: bubble radius when it is very unsure
const SPREAD_WIN_MS = 700;     // window used to measure how much the raw estimate is jumping around
const SPREAD_FULL_PX = 140;    // 80%-cloud radius (px) at which the bubble/rule are most forgiving
const SPREAD_MIN_N = 5;
const CLOUD_PCT = 0.8;
const HEAD_R_GAIN = 120;       // px of extra radius per radian of head turn (looks only, never loosens the rule)
const AWAY_DECAY = 0.7;        // time outside counts 1x, time inside pays it back at 0.7x
const HEAD_EYE_FALLBACK_MIN_RAD = 0.15; // use eyes alone if head motion pushes the estimate outside the exam area
 
const clampPx = (v, a, b) => Math.max(a, Math.min(b, v));
const pxA = (cut, dt) => 1 / (1 + 1 / (2 * Math.PI * cut) / dt);
// 1-Euro filter in screen pixels
class PxFilter {
  constructor(minCut = 0.4, beta = 0.004, dCut = 1) {
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
let usingEyeFirstFallbackX = false;
let usingEyeFirstFallbackY = false;
const FALLBACK_FADE_MS = 500;
let fallbackBlendX = 0;
let fallbackBlendY = 0;
let lastFallbackBlendAt = performance.now();
const IRIS_LOCK_FRAC = 0.05;
const IRIS_UNLOCK_FRAC = 0.06;
const IRIS_WIN_MS = 400;
const IRIS_HEAD_MAX_RAD = 0.5;
const irisHistory = [];
let irisLock = null;
const jitterSamples = [];
let lastJitterLogAt = 0;
const earHist = [];
let lastBlinkishAt = -1e9;
let lastGazeT = performance.now();
let awayMs = 0;       // leaky "time spent outside": jitter in and out cancels, real looking away builds up
const Y_BLIP_PX = 140;       // was 90
const Y_CONFIRM_FRAMES = 2;
let yStable = null;
let yCandidate = null;
let yCandidateCount = 0;
let yCandidateDirection = 0;

function filterYBlips(y) {
  if (!Number.isFinite(y)) return y;
  if (yStable === null) {
    yStable = y;
    return y;
  }

  if (Math.abs(y - yStable) <= Y_BLIP_PX) {
    yStable = y;
    yCandidate = null;
    yCandidateCount = 0;
    yCandidateDirection = 0;
    return yStable;
  }

  const direction = Math.sign(y - yStable);
  if (yCandidate === null || direction !== yCandidateDirection) {
    yCandidate = y;
    yCandidateCount = 1;
    yCandidateDirection = direction;
    return yStable;
  }

  yCandidate = y;
  yCandidateCount++;
  if (yCandidateCount >= Y_CONFIRM_FRAMES) {
    yStable = y;
    yCandidate = null;
    yCandidateCount = 0;
    yCandidateDirection = 0;
  }
  return yStable;
}

function resetYBlipFilter() {
  yStable = null;
  yCandidate = null;
  yCandidateCount = 0;
  yCandidateDirection = 0;
}

const biasX = GAZE_BIAS_X * window.innerWidth;
const biasY = 0;

const GATE_SKIP_MS = 1200;
const GATE_MIN_FRAMES = 8;
const GATE_MAX_SPREAD = 120;
const GATE_MAX_FRAME_GAP_MS = 750;
const gateFrames = [];
let gateLearned = !!window.examStarted;
let gateCaptureStartedAt = null;

function gateTarget() {
  const now = performance.now();
  if (cachedGateTarget && now - cachedGateTargetAt < 200) {
    return cachedGateTarget;
  }
  const el =
    document.querySelector("#examContentGate .record-icon--gate") ||
    document.getElementById("examGate");
  if (!el) {
    cachedGateTarget = null;
    return null;
  }
  const rect = el.getBoundingClientRect();
  if (rect.width < 1 || rect.height < 1) {
    cachedGateTarget = null;
    return null;
  }
  cachedGateTarget = {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
  cachedGateTargetAt = now;
  return cachedGateTarget;
}

let cachedGateTarget = null;
let cachedGateTargetAt = 0;

window.beginExamGateLearning = () => {
  gateFrames.length = 0;
  gateCaptureStartedAt = performance.now();
  gateLearned = false;
};

window.resetExamGateLearning = () => {
  gateFrames.length = 0;
  gateCaptureStartedAt = null;
};

function gateRecord(now, x, y, target, features) {
  gateFrames.push({
    t: now,
    x,
    y,
    tx: target.x,
    ty: target.y,
    features: {
      ox: features.ox,
      oy: features.oy,
      yaw: features.yaw,
      pitch: features.pitch,
      roll: features.roll,
      cx: features.cx,
      cy: features.cy,
      scale: features.scale,
    },
  });
  while (gateFrames.length && now - gateFrames[0].t > 6000)
    gateFrames.shift();
}

async function learnFromGate(now) {
  const captureStartedAt = gateCaptureStartedAt;
  if (
    captureStartedAt === null ||
    now - captureStartedAt < 5000
  ) {
    gateFrames.length = 0;
    gateCaptureStartedAt = null;
    gateLearned = true;
    console.warn("Recording-icon gaze sample skipped: the full 5-second gate did not finish.");
    return "gate-not-completed";
  }
  gateCaptureStartedAt = null;
  gateLearned = true;
  if (!online) {
    gateFrames.length = 0;
    return "no-online-model";
  }
  if (!gateFrames.length) {
    console.warn("Recording-icon gaze sample skipped: no gate frames were recorded.");
    return "no-gate-frames";
  }

  const firstFrameAt = gateFrames[0].t;
  const lastFrameAt = gateFrames[gateFrames.length - 1].t;
  const hasContinuousCoverage =
    firstFrameAt - captureStartedAt <= 1000 &&
    now - lastFrameAt <= 500 &&
    gateFrames.every(
      (frame, index) =>
        index === 0 || frame.t - gateFrames[index - 1].t <= GATE_MAX_FRAME_GAP_MS,
    );
  if (!hasContinuousCoverage) {
    gateFrames.length = 0;
    console.warn("Recording-icon gaze sample skipped: gaze tracking did not cover the full 5-second gate.");
    return "incomplete-gate-coverage";
  }

  const stableFrames = gateFrames.filter(
    (frame) => frame.t - firstFrameAt >= GATE_SKIP_MS,
  );
  if (stableFrames.length < GATE_MIN_FRAMES) {
    console.warn("Recording-icon gaze sample skipped: too few stable frames.");
    return "too-few-frames";
  }

  const median = GazeCore.med;
  const mx = median(stableFrames.map((frame) => frame.x));
  const my = median(stableFrames.map((frame) => frame.y));
  if (
    Math.max(
      ...stableFrames.map((frame) => Math.hypot(frame.x - mx, frame.y - my)),
    ) > GATE_MAX_SPREAD
  ) {
    console.warn("Recording-icon gaze sample skipped: gaze was not stable.");
    return "unstable";
  }

  const tx = median(stableFrames.map((frame) => frame.tx));
  const ty = median(stableFrames.map((frame) => frame.ty));
  const featureKeys = ["ox", "oy", "yaw", "pitch", "roll", "cx", "cy", "scale"];
  const sample = Object.fromEntries(
    featureKeys.map((key) => [
      key,
      median(stableFrames.map((frame) => frame.features[key])),
    ]),
  );
  Object.assign(sample, {
    sx: tx / window.innerWidth,
    sy: ty / window.innerHeight,
    spot: -1,
    gate: true,
    w: 6,
  });
  if (
    !featureKeys.every((key) => Number.isFinite(sample[key])) ||
    !Number.isFinite(sample.sx) ||
    !Number.isFinite(sample.sy) ||
    sample.sx < 0 ||
    sample.sx > 1 ||
    sample.sy < 0 ||
    sample.sy > 1
  ) {
    gateFrames.length = 0;
    console.warn("Recording-icon gaze sample skipped: invalid features or target.");
    return "invalid-sample";
  }
  const result = online.addClick(tx, ty, now, true, "gate");
  console.log("gate gaze sample:", result);
  const clicks = online.exportClicks();
  if (result === "ok") {
    model = online.getModel();
    try {
      sessionStorage.setItem("gazeOnlineClicks", JSON.stringify(clicks));
    } catch (err) {
      console.warn("Could not persist gate gaze samples:", err);
    }
  } else if (result === "refit-rejected") {
    console.warn("Gate sample is being saved although the local refit was rejected.");
  }

  gateFrames.length = 0;
  const saved = await saveGazeLearningSample(sample, "recording-icon-gate");
  if (!saved) return `${result}; cloud-save-failed`;
  return `${result}; cloud-saved`;
}

window.learnFromRecordingIconGate = () => learnFromGate(performance.now());
 
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

const EXIT_WIN = 4;
const EXIT_VOTES = 3;
const EXIT_MIN_MS = 300;
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
  const previous = earHist[earHist.length - 1];
  earHist.push({ t: now, e: ear });
  while (earHist.length && now - earHist[0].t > BLINK_WIN_MS) earHist.shift();
  const openEar = Math.max(...earHist.map((q) => q.e));
  const earVelocity =
    previous
      ? Math.abs(ear - previous.e) /
        Math.max((now - previous.t) / 1000, 0.01)
      : 0;
  const lidMoving =
    earVelocity > BLINK_VEL &&
    Math.min(ear, previous?.e ?? ear) < openEar * BLINK_VEL_MIN_EAR_RATIO;
  const blinkish =
    lidMoving || ear < Math.max(BLINK_EAR, openEar * BLINK_REL);
  if (blinkish) lastBlinkishAt = now;
  return blinkish || now - lastBlinkishAt < BLINK_SETTLE_MS;
}

function resetIrisHold() {
  irisHistory.length = 0;
  irisLock = null;
  window.gazeIrisBubbleLocked = false;
}

function holdBubbleWhileIrisStill(now, features, headDev, x, y) {
  const spanX = eyeRange.ox
    ? Math.max(eyeRange.ox[1] - eyeRange.ox[0], 0.05)
    : 0.3;
  const spanY = eyeRange.oy
    ? Math.max(eyeRange.oy[1] - eyeRange.oy[0], 0.05)
    : 0.3;

  if (
    headDev > IRIS_HEAD_MAX_RAD ||
    outsideCalibratedRange(features.ox, eyeRange.ox) ||
    outsideCalibratedRange(features.oy, eyeRange.oy)
  ) {
    resetIrisHold();
    return { x, y };
  }

  if (irisLock) {
    const movement = Math.max(
      Math.abs(features.ox - irisLock.ox) / spanX,
      Math.abs(features.oy - irisLock.oy) / spanY,
    );
    if (movement <= IRIS_UNLOCK_FRAC) {
      window.gazeIrisBubbleLocked = true;
      return { x: irisLock.x, y: irisLock.y };
    }
    resetIrisHold();
  }

  irisHistory.push({ t: now, ox: features.ox, oy: features.oy });
  while (irisHistory.length && now - irisHistory[0].t > IRIS_WIN_MS)
    irisHistory.shift();

  if (
    irisHistory.length >= 6 &&
    now - irisHistory[0].t >= IRIS_WIN_MS * 0.8
  ) {
    const xs = irisHistory.map((sample) => sample.ox);
    const ys = irisHistory.map((sample) => sample.oy);
    const movement = Math.max(
      (Math.max(...xs) - Math.min(...xs)) / spanX,
      (Math.max(...ys) - Math.min(...ys)) / spanY,
    );
    if (movement < IRIS_LOCK_FRAC) {
      irisLock = {
        ox: GazeCore.med(xs),
        oy: GazeCore.med(ys),
        x,
        y,
      };
      window.gazeIrisBubbleLocked = true;
      return { x, y };
    }
  }

  window.gazeIrisBubbleLocked = false;
  return { x, y };
}

function setBlinkHold(hold) {
  if (hold && !blinkHoldActive) blinkHoldGeneration++;
  if (hold && !blinkHoldActive) resetIrisHold();
  if (!hold && blinkHoldActive) {
    targetX = bubbleX;
    targetY = bubbleY;
    smoothGaze.reset();
    blinkWarmFrames = BLINK_WARM_FRAMES;
    lastGazeT = performance.now();
  }
  blinkHoldActive = hold;
  window.gazeBlinkHolding = hold;
}

function resetBlinkGuard() {
  earHist.length = 0;
  lastBlinkishAt = -1e9;
}

function visibleRect(rect) {
  const zone = document.getElementById("examZone")?.getBoundingClientRect();
  const left = Math.max(rect.left, 0, zone ? zone.left : 0);
  const top = Math.max(rect.top, 0, zone ? zone.top : 0);
  const right = Math.min(
    rect.right,
    window.innerWidth,
    zone ? zone.right : Infinity,
  );
  const bottom = Math.min(
    rect.bottom,
    window.innerHeight,
    zone ? zone.bottom : Infinity,
  );
  return {
    left,
    top,
    right,
    bottom,
    width: Math.max(0, right - left),
    height: Math.max(0, bottom - top),
  };
}

let cachedGazeRect = null;
let cachedGazeRectAt = 0;
let cachedGazeRectStarted = null;

function invalidateGazeRect() {
  cachedGazeRect = null;
  cachedGazeRectStarted = null;
  cachedGateTarget = null;
}

function getGazeRect(now) {
  const started = !!window.examStarted;
  if (
    cachedGazeRect &&
    cachedGazeRectStarted === started &&
    now - cachedGazeRectAt < 200
  ) {
    return cachedGazeRect;
  }

  const element = document.getElementById(started ? "examCard" : "examGate");
  if (!element) return null;

  let rect = element.getBoundingClientRect();
  if (started) {
    const control = document.getElementById("nextQuestion");
    const controlRect = control?.getBoundingClientRect();
    if (controlRect && controlRect.width > 0 && controlRect.height > 0) {
      const left = Math.min(rect.left, controlRect.left);
      const top = Math.min(rect.top, controlRect.top);
      const right = Math.max(rect.right, controlRect.right);
      const bottom = Math.max(rect.bottom, controlRect.bottom);
      rect = {
        left,
        top,
        right,
        bottom,
        width: right - left,
        height: bottom - top,
      };
    }
  }

  cachedGazeRect = visibleRect(rect);
  cachedGazeRectAt = now;
  cachedGazeRectStarted = started;
  return cachedGazeRect;
}

window.addEventListener("resize", invalidateGazeRect);
window.addEventListener("scroll", invalidateGazeRect, true);
window.visualViewport?.addEventListener("resize", invalidateGazeRect);
window.visualViewport?.addEventListener("scroll", invalidateGazeRect);
 
function resetGazeFilters() {
  posX.reset();
  posY.reset();
  posHist.length = 0;
  fallbackBlendX = 0;
  fallbackBlendY = 0;
  lastFallbackBlendAt = performance.now();
  usingEyeFirstFallbackX = false;
  usingEyeFirstFallbackY = false;
  resetIrisHold();
  resetYBlipFilter();
  exitReset();
  resetBlinkGuard();
  awayMs = 0;
}
let awaySince = 0;
let eyesClosedSince = 0;
let eyeVisibilityBadSince = 0;
const EYE_VISIBILITY_GRACE_MS = 750;
let lastFrameAt = performance.now();
let lastFaceDetected = false;
let lastStallStrikeAt = 0;
let watchedTrack = null;
let lossTimer = null;
let lossDeadline = 0;
const missingSignals = new Set();
let screenLossActive = false;

// Online exam learning uses the recording-icon gate as its only labeled target.
const online = GazeCore.createOnline(calData, {
  gateWeight: 6,
  maxClicks: 0,
  maxGate: 5,
  maxSpreadPx: 100,
});
const isRecordingIconLearningSample = (sample) =>
  sample?.gate === true || sample?.source === "recording-icon-gate";

if (online) {
  try {
    const storedClicks = sessionStorage.getItem("gazeOnlineClicks");
    if (storedClicks) {
      const parsedClicks = JSON.parse(storedClicks);
      const gateSamples = Array.isArray(parsedClicks)
        ? parsedClicks.filter(isRecordingIconLearningSample)
        : [];
      const imported = online.importClicks(gateSamples);
      if (!imported && gateSamples.length)
        console.warn("Saved recording-icon gaze samples failed validation and were discarded.");
    }
    model = online.getModel();
  } catch (err) {
    console.warn("Could not restore online gaze samples:", err);
  }
}

async function saveGazeLearningSample(sample, source) {
  if (!sample || !window.httpsCallable || !window.functions) {
    console.warn(
      `Could not save ${source} gaze sample: Firebase Functions is unavailable.`,
    );
    return false;
  }

  try {
    const addGazeLearning = window.httpsCallable(
      window.functions,
      "addGazeLearning",
      { timeout: 10000 },
    );
    const result = await addGazeLearning({
      platform: window.examGazePlatform || calData.platform,
      samples: [{ ...sample, source }],
      ...(typeof window.examData?.examId === "string"
        ? { examId: window.examData.examId }
        : {}),
    });
    console.log(`Saved ${source} gaze sample:`, result.data);
    return true;
  } catch (err) {
    console.error(`Could not save ${source} gaze sample:`, err);
    return false;
  }
}

window.gazeLearningReady = Promise.resolve(window.examGazeCalibrationReady)
  .then((status) => {
    if (!status?.ready || !online) return;

    const persistedSamples = (
      window.examGazeCalibrationRecord?.learningSamples || []
    ).filter(isRecordingIconLearningSample);
    if (!persistedSamples.length) return;

    const currentClicks = online.exportClicks();
    const sampleKey = (sample) =>
      `${sample.ox}|${sample.oy}|${sample.sx}|${sample.sy}`;
    const currentKeys = new Set(currentClicks.map(sampleKey));
    const freshPersistedSamples = persistedSamples.filter(
      (click) => !currentKeys.has(sampleKey(click)),
    );
    const imported = online.importClicks(
      [...freshPersistedSamples, ...currentClicks],
      true,
    );
    if (!imported) {
      console.warn("Saved gaze-learning samples failed validation.");
      return;
    }

    model = online.getModel();
    console.log("Restored saved gaze-learning samples:", imported);
  })
  .catch((err) => {
    console.error("Could not restore recording-icon gaze samples:", err);
  });

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
  window.GazeMetrics?.onFlag(reason, ms);
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
const SCREEN_RESHARE_MS = 45000;
let screenBadSince = 0;
let screenTimer = null;
let screenDeadline = 0;
let screenLostAt = 0;

function showReshare(show) {
  const modal = document.getElementById("screenShareModal");
  if (modal) {
    modal.style.display = show ? "block" : "none";
    modal.setAttribute("aria-hidden", show ? "false" : "true");
  }
}

function stopScreenCountdown() {
  if (screenTimer !== null) {
    clearInterval(screenTimer);
    screenTimer = null;
  }
  screenDeadline = 0;
  screenLostAt = 0;
  showReshare(false);
}

function restoreScreenShare() {
  if (screenTimer === null) return;
  const durationMs = Math.max(0, performance.now() - screenLostAt);
  stopScreenCountdown();
  if (window.examStarted && !window.examFinished && !window.submitting) {
    window.reportProctorEvent?.("screen_share_restored", durationMs);
  }
}

function startScreenCountdown() {
  if (screenTimer !== null) return;
  screenLostAt = performance.now();
  screenDeadline = performance.now() + SCREEN_RESHARE_MS;
  window.reportProctorEvent?.("screen_share_lost");
  showReshare(true);
  screenTimer = setInterval(() => {
    if (!window.examStarted || window.examFinished || window.submitting) {
      stopScreenCountdown();
      return;
    }

    const secondsLeft = Math.max(
      0,
      Math.ceil((screenDeadline - performance.now()) / 1000),
    );
    const countdown = document.getElementById("reshareLeft");
    if (countdown) countdown.textContent = String(secondsLeft);

    if (secondsLeft === 0) {
      console.warn("[auto-submit] screen share was not restored");
      stopScreenCountdown();
      window.submitExam(true);
    }
  }, 250);
}

function checkScreenShare() {
  if (!window.examStarted || !isPcExam()) {
    screenBadSince = 0;
    if (screenLossActive || screenTimer !== null) {
      screenLossActive = false;
      stopScreenCountdown();
    }
    return;
  }

  const stream = window.cheatCaptureStream;
  const track = stream?.getVideoTracks?.()[0];
  const healthy = !!stream?.active && track?.readyState === "live"; // muted is NOT a loss

  if (healthy) {
    screenBadSince = 0;
    screenLossActive = false;
    restoreScreenShare();
    return;
  }

  const now = performance.now();
  if (!screenBadSince) { screenBadSince = now; return; }
  if (now - screenBadSince < SCREEN_LOSS_GRACE_MS || screenLossActive) return;

  screenLossActive = true;
  console.warn("[screen] lost:", { hasStream: !!stream, state: track?.readyState, muted: track?.muted });
  startScreenCountdown();
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

// Camera pixels -> overlay canvas pixels, respecting the <video> object-fit. null until the video size is known.
function overlayMap(vw, vh) {
  const cw = videoElement.videoWidth, ch = videoElement.videoHeight;
  if (!cw || !ch) return null;
  const fit = getComputedStyle(videoElement).objectFit;
  let sx, sy, ox = 0, oy = 0;
  if (fit === "cover" || fit === "contain") {
    const k = fit === "cover" ? Math.max(vw / cw, vh / ch) : Math.min(vw / cw, vh / ch);
    sx = sy = k; ox = (vw - cw * k) / 2; oy = (vh - ch * k) / 2;
  } else { sx = vw / cw; sy = vh / ch; }
  const mirrored = /^matrix\(-1/.test(getComputedStyle(canvasElement).transform);
  return { cw, ch, sx, sy, ox, oy, mirrored };
}

// YOLO eye overlay is available only while YoloEye debug mode is enabled.
function drawYoloOverlay(vw, vh) {
  const m = overlayMap(vw, vh);
  if (!m || typeof YoloEye.drawYolo !== "function") return;
  YoloEye.drawYolo(canvasCtx, YoloEye.lastGaze, { sx: m.sx, sy: m.sy, ox: m.ox, oy: m.oy, mirrored: m.mirrored });
}

// Small button on the camera preview: hides / shows the face mesh.
// (Set window.GAZE_DEBUG_BUTTON = false before this script loads to not create it.)
function addOverlayToggle() {
  if (window.GAZE_DEBUG_BUTTON === false) return;
  const host = videoElement.parentElement;
  if (!host || document.getElementById("overlayToggleBtn")) return;
  if (getComputedStyle(host).position === "static") host.style.position = "relative";
  const btn = document.createElement("button");
  btn.id = "overlayToggleBtn";
  btn.type = "button";
  btn.style.cssText =
    "position:absolute;top:6px;right:6px;z-index:5;padding:3px 8px;font:600 11px system-ui,sans-serif;" +
    "color:#fff;background:rgba(17,18,23,.78);border:1px solid #66c192;border-radius:4px;cursor:pointer;";
  const paint = () => {
    const on = window.SHOW_FACEMESH !== false;
    btn.textContent = on ? "Hide mesh" : "Show mesh";
    btn.setAttribute("aria-pressed", String(on));
  };
  btn.addEventListener("click", () => {
    const next = window.SHOW_FACEMESH === false;
    window.SHOW_FACEMESH = next;
    paint();
  });
  paint();
  host.appendChild(btn);
}
addOverlayToggle();

async function onResults(results) {
  // CRITICAL: Exit immediately if submitting to avoid blocking submission
  if (window.submitting || window.examFinished || window.__examTrackingDisposed) return;
  
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
  canvasCtx.save();
  canvasCtx.clearRect(0, 0, vw, vh);

  const faces = results.multiFaceLandmarks;
  window.GazeMetrics?.onModelMetrics({ faceMeshMinConfidence: FACE_MIN_CONF });
  
  // Draw FaceMesh if faces detected
  if (faces && faces.length > 0) {
    for (const landmarks of faces) {
      if (window.SHOW_FACEMESH !== false) {
        const m = overlayMap(vw, vh);
        if (m) {
          // same cover-aware mapping as the camera preview
          canvasCtx.save();
          canvasCtx.translate(m.ox, m.oy);
          drawFaceMesh(canvasCtx, landmarks, m.cw * m.sx, m.ch * m.sy);
          canvasCtx.restore();
        } else drawFaceMesh(canvasCtx, landmarks, vw, vh);
      }
    }
  }

  // Keep the YOLO visualization out of the normal camera preview.
  if (YoloEye.debugEnabled && window.SHOW_YOLO_OVERLAY !== false && faces && faces.length > 0) drawYoloOverlay(vw, vh);

  // (1) No face: left the frame, hand/cover over the lens, etc.
  if (!faces || faces.length === 0) {
    setBlinkHold(false);
    eyesClosedSince = 0;
    resetGazeFilters();
    flagAway("Face not found", FACE_LOST_MS);
    startFaceLossCountdown("Face not found");
    const bubbleHome = window.getExamBubbleHome?.() || {
      x: window.innerWidth / 2,
      y: window.innerHeight / 2,
    };
    targetX = bubbleHome.x;
    targetY = bubbleHome.y;
    updateBubble();
    return;
  }
  clearFaceLossCountdown("Face not found");

  // (4) More than one face: someone else is in view.
  if (faces.length > 1) {
    setBlinkHold(false);
    resetIrisHold();
    eyesClosedSince = 0;
    resetBlinkGuard();
    flagAway("Multiple faces detected", MULTI_FACE_MS);
    updateBubble();
    return;
  }

  const lm = faces[0];
  const W = videoElement.videoWidth, H = videoElement.videoHeight;
  if (!W || !H) return;
  const head = GazeCore.extract(lm, W, H);
  if (!model) return;

  // (3) Blink handling with a time limit.
  // Uses MediaPipe's eye-aspect-ratio, NOT the YOLO result: YoloEye.extract returns null when the
  // eyes are closed, which would silently skip this check and give a free pass for closed eyes.
  const now = performance.now();
  const blinkish = blinkGuard(now, head.ear);
  const eyesClosed = head.ear < BLINK_EAR;
  setBlinkHold(eyesClosed || blinkish);
  window.GazeMetrics?.onEye(head.ear, blinkish, head.ear < BLINK_EAR);
  if (eyesClosed) {
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
  const frameBlinkGeneration = blinkHoldGeneration;

  // Eye features from YOLO (async). Frames that arrive while it is still busy are dropped.
  if (yoloBusy) return;
  
  // CRITICAL: Don't start YOLO processing if we're submitting
  if (window.submitting || window.examFinished || window.__examTrackingDisposed) return;
  
  yoloBusy = true;
  let raw;
  let eyeTrackingFailed = false;
  try {
    raw = await YoloEye.extract(lm, W, H, videoElement); // lm = full MediaPipe landmarks array
  } catch (err) {
    console.error("YOLO extract failed:", err);
    eyeTrackingFailed = true;
  } finally {
    yoloBusy = false;
  }
  
  // CRITICAL: Check again after async operation completes
  if (window.submitting || window.examFinished || window.__examTrackingDisposed) return;
  if (
    frameBlinkGeneration !== blinkHoldGeneration ||
    window.gazeBlinkHolding
  ) return;
  
  window.GazeMetrics?.onRaw(raw);
  if (window.disableGazeDetection) return; // exam may have been submitted while we awaited
  const eyeVisibility = eyeTrackingFailed
    ? {
        visible: false,
        reason: "Eye tracking is unavailable. Check your camera and lighting.",
      }
    : YoloEye.checkEyeVisibility(lm, W, H, videoElement);
  if (!eyeVisibility.visible || !raw) {
    const reason =
      eyeVisibility.reason ||
      "Both eyes are not clearly visible. Improve the lighting and center your face.";
    const failedAt = performance.now();
    if (!eyeVisibilityBadSince) eyeVisibilityBadSince = failedAt;
    examCard.classList.add("alert");
    gazeBubble.classList.add("alert");
    setVerification(false, reason);
    if (
      window.examStarted &&
      failedAt - eyeVisibilityBadSince >= EYE_VISIBILITY_GRACE_MS
    ) {
      flagAway(reason, AWAY_MS);
    }
    updateBubble();
    return;
  }
  eyeVisibilityBadSince = 0;
 
// ---------------------------------------------------------------------------- PART 2
// (this is the tail of onResults; `raw`, `model`, `headBase`, `calData`, `online` come from the code above it)
  const tNow = performance.now();
  const f = smoothGaze(raw, tNow);
  if (blinkWarmFrames > 0) {
    blinkWarmFrames--;
    lastGazeT = tNow;
    updateBubble();
    return;
  }
  if (online) online.push(f, tNow); // feed the click-learning buffer

  // Screen estimate. HEAD_GAIN < 1 keeps the head terms from dragging the dot around.
  const features = {
    ...f,
    ox: limitToCalibratedRange(f.ox, eyeRange.ox),
    oy: limitToCalibratedRange(f.oy, eyeRange.oy),
  };
  const activeModel = window.GAZE_NO_LEARNING ? baseModel : model;
  const headGain = window.GAZE_HEAD_GAIN ?? HEAD_GAIN;
  const p = GazeCore.predict(activeModel, features, headGain);
  const headDev = Math.max(Math.abs(f.yaw - headBase.yaw), Math.abs(f.pitch - headBase.pitch));
  const eyeOnly = GazeCore.predict(activeModel, features, 0);
  let estimateX = p.x * window.innerWidth + biasX;
  const fullEstimateY = p.y * window.innerHeight + biasY;
  let estimateY = fullEstimateY;
  const eyeEstimateX = eyeOnly.x * window.innerWidth + biasX;
  const eyeEstimateY = eyeOnly.y * window.innerHeight + biasY;

  const rect = getGazeRect(tNow);
  if (!rect) return;
  if (rect.width < 20 || rect.height < 20) return;

  if (
    window.SHOW_GAZE_DIAGNOSTICS === true &&
    (!window.__dbgAt || tNow - window.__dbgAt > 1000)
  ) {
    window.__dbgAt = tNow;
    const predictYpx = (candidate, gain) =>
      Math.round(
        GazeCore.predict(candidate, features, gain).y * window.innerHeight,
      );
    const centerRow = (calData?.rows || []).find((row) => row.spot === 0);
    console.log(
      `y px | calib, full head ${predictYpx(baseModel, 1)} | calib, gain ${headGain} ${predictYpx(baseModel, headGain)} | with learning ${predictYpx(model, headGain)} | card center ${Math.round((rect.top + rect.bottom) / 2)}` +
        (centerRow
          ? ` || vs center dot: oy ${(f.oy - centerRow.oy).toFixed(3)} pitch ${(f.pitch - centerRow.pitch).toFixed(2)} cy ${(f.cy - centerRow.cy).toFixed(2)} scale ${(f.scale - centerRow.scale).toFixed(2)}`
          : "") +
        ` || cam ${W}x${H} vs ${calData?.camera?.w ?? "?"}x${calData?.camera?.h ?? "?"}`,
    );
  }

  const inside = (x, y) =>
    x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
  const eyeXUsable = !outsideCalibratedRange(f.ox, eyeRange.ox);
  const eyeYUsable = !outsideCalibratedRange(f.oy, eyeRange.oy);
  const eyeFirstFallbackX =
    window.examStarted &&
    headDev >= HEAD_EYE_FALLBACK_MIN_RAD &&
    headDev < HEAD_LIMIT_RAD &&
    eyeXUsable &&
    (estimateX < rect.left || estimateX > rect.right) &&
    eyeEstimateX >= rect.left &&
    eyeEstimateX <= rect.right;
  const eyeFirstFallbackY =
    window.examStarted &&
    headDev >= HEAD_EYE_FALLBACK_MIN_RAD &&
    headDev < HEAD_LIMIT_RAD &&
    eyeYUsable &&
    (estimateY < rect.top || estimateY > rect.bottom) &&
    eyeEstimateY >= rect.top &&
    eyeEstimateY <= rect.bottom;
  const usingEyeFirstFallback = eyeFirstFallbackX || eyeFirstFallbackY;

  const blendDt = Math.min(tNow - lastFallbackBlendAt, 200);
  lastFallbackBlendAt = tNow;
  const blendStep = blendDt / FALLBACK_FADE_MS;
  fallbackBlendX += clampPx(
    (eyeFirstFallbackX ? 1 : 0) - fallbackBlendX,
    -blendStep,
    blendStep,
  );
  fallbackBlendY += clampPx(
    (eyeFirstFallbackY ? 1 : 0) - fallbackBlendY,
    -blendStep,
    blendStep,
  );
  usingEyeFirstFallbackX = eyeFirstFallbackX;
  usingEyeFirstFallbackY = eyeFirstFallbackY;
  estimateX =
    estimateX + (eyeEstimateX - estimateX) * fallbackBlendX;
  estimateY = filterYBlips(
    fullEstimateY + (eyeEstimateY - fullEstimateY) * fallbackBlendY,
  );

  const spread = recordSpread(tNow, estimateX, estimateY);
  // 1) median of the last 3 gaze estimates removes one-frame "teleports"
  // 2) 1-Euro smooths what is left
  // 3) the CENTRE is clamped to the viewport, so the bubble can sit on the edge (half visible) but never leaves
  const last3 = posHist.slice(-3);
  const mid = (k) => (last3.length < 3 ? last3[last3.length - 1][k] : GazeCore.med(last3.map((q) => q[k])));
  targetX = clampPx(posX.filter(mid("x"), tNow), 0, window.innerWidth);
  targetY = clampPx(posY.filter(mid("y"), tNow), 0, window.innerHeight);

  // Grow from the calibrated baseline radius toward R_MAX using the same spread ratio as the strike rule.
  const baseR = clampPx(0.6 * (calData?.accuracy || 0), R_MIN, R_BASE_MAX);
  const unsureR = Math.min(spread / SPREAD_FULL_PX, 1);
  targetR = Math.min(
    R_MAX,
    baseR + (R_MAX - baseR) * unsureR + HEAD_R_GAIN * headDev,
  );

  if (window.examStarted) {
    const allowed = exitGate(rect, tNow, targetX, targetY);
    targetX = allowed.x;
    targetY = allowed.y;
    const held = holdBubbleWhileIrisStill(
      tNow,
      f,
      headDev,
      targetX,
      targetY,
    );
    targetX = held.x;
    targetY = held.y;
  }
  window.GazeMetrics?.onGaze(tNow, estimateX, estimateY, targetX, targetY);
  if (window.SHOW_GAZE_JITTER_METER === true) {
    jitterSamples.push({ t: tNow, rx: estimateX, ry: estimateY, tx: targetX, ty: targetY });
    while (jitterSamples.length && tNow - jitterSamples[0].t > 1000)
      jitterSamples.shift();
    if (tNow - lastJitterLogAt >= 2000 && jitterSamples.length >= 3) {
      lastJitterLogAt = tNow;
      const standardDeviation = (key) => {
        const values = jitterSamples.map((sample) => sample[key]);
        const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
        return Math.sqrt(
          values.reduce((sum, value) => sum + (value - mean) ** 2, 0) /
            values.length,
        );
      };
      console.log(
        `Gaze jitter (1s SD): estimate ${Math.hypot(standardDeviation("rx"), standardDeviation("ry")).toFixed(0)}px; filtered target ${Math.hypot(standardDeviation("tx"), standardDeviation("ty")).toFixed(0)}px`,
      );
    }
  }
 
  const bubbleCenterInside =
    bubbleX > rect.left &&
    bubbleX < rect.right &&
    bubbleY > rect.top &&
    bubbleY < rect.bottom;
  // extreme head turn/tilt: the iris landmarks are unreliable there, so judge by pose
  const headOk =
    Math.abs(f.yaw - headBase.yaw) < HEAD_LIMIT_RAD &&
    Math.abs(f.pitch - headBase.pitch) < HEAD_LIMIT_RAD;
  const gazeOk =
    bubbleCenterInside &&
    (headOk || usingEyeFirstFallback) &&
    !outsideCalibratedRange(f.ox, eyeRange.ox) &&
    !outsideCalibratedRange(f.oy, eyeRange.oy);
  if (window.examStarted && !gazeOk) {
    if (!window.awayStartedAt) window.awayStartedAt = Date.now();
  } else if (gazeOk && awayMs <= 0) {
    window.awayStartedAt = 0;
  }
  if (!window.examStarted) {
    const target = gateTarget();
    if (target && gazeOk && gateCaptureStartedAt !== null)
      gateRecord(tNow, estimateX, estimateY, target, f);
  } else if (!gateLearned) {
    learnFromGate(tNow);
  }
 
  // Leaky timer instead of "reset on every good frame": a few jittery frames can't build a strike
  const dtG = Math.min(tNow - lastGazeT, 200);
  lastGazeT = tNow;
  awayMs = gazeOk
    ? Math.max(0, awayMs - dtG * AWAY_DECAY)
    : Math.min(awayMs + dtG, AWAY_MS * 1.6);
  window.GazeMetrics?.onState(gazeOk, awayMs);
 
  if (awayMs >= AWAY_MS) {
    flagAway("Looking away detected", 0); // alert + strike (registerStrikeOnce rate-limits to one per 1.2 s)
  } else if (!bubbleCenterInside) {
    examCard.classList.add("alert");
    gazeBubble.classList.add("alert");
  } else if (gazeOk) {
    clearAway();
    setVerification(
      true,
      usingEyeFirstFallback
        ? "Eyes centered; accounting for head movement"
        : "Face & eyes centered",
    );
  } else {
    examCard.classList.remove("alert");
    gazeBubble.classList.remove("alert");
  }
  updateBubble();
}