// gaze-metrics.js — console metrics + test harness for the gaze pipeline
//
// Load order in exam.html:
//   gaze-core.js -> yolo-eye.js -> exam-gaze-block.js -> gaze-metrics.js -> (inline script that calls faceMesh.onResults(onResults))
//
// It wraps window.onResults (from exam-gaze-block.js) to time every camera frame, and exam-gaze-block.js
// calls a few small hooks (GazeMetrics.onFlag / onEye / onRaw / onGaze / onState).
//
// Console API (open DevTools):
//   GazeMetrics.help()              what everything means
//   GazeMetrics.runAll()            blink + fixation + saccade + false-positive tests, then a summary table
//   GazeMetrics.runFixation()       5 dots x 3 s
//   GazeMetrics.runSaccade()        10 dot jumps (left <-> right)
//   GazeMetrics.runBlink()          10 cued blinks
//   GazeMetrics.runFalsePositive()  3 x 10 s: fixation, saccades, camera moving (all INSIDE the exam area)
//   GazeMetrics.setGate(true|false) click/Space-to-start before every test (default ON)
//   GazeMetrics.live(true)          rolling log every 5 s (fps, latency, face %, alert %)
//   GazeMetrics.summary()           table of everything run so far
//   GazeMetrics.models()            model setup + rolling confidence/tracking metrics
//   GazeMetrics.download()          saves results.json + frames.csv
//   GazeMetrics.showYolo(false)     hide the red YOLO boxes / keypoints
//   Esc                             aborts a running test
//

if (typeof YoloEye !== "undefined") window.YoloEye = YoloEye;

(function (root) {
  "use strict";

  // ======================= settings =======================
  const CFG = {
    maxFrames: 60000,
    gate: true, // wait for a click / Space / Enter before every test starts
    tolPx: 150, // a gaze sample counts as "on the dot" when it is within this many px
    tolsPx: [75, 100, 150, 200, 300], // accuracy is also reported at these tolerances
    settleMs: 700, // ignore this long after a dot appears (human reaction + settling)
    idt: { winMs: 200, dispPx: 250, minMs: 120 }, // fixation = gaze stays inside dispPx (x range + y range) for >= minMs (webcam gaze jitters ~50-100 px, so this is looser than a hardware tracker)
    sacc: { winMs: 150, minAmpPx: 100, minLatMs: 80, maxLatMs: 900, refractoryMs: 300, dirMin: 0.1 },
    blink: { cueWindowMs: [80, 900], mergeGapMs: 100, preMs: [300, 50], postMs: [250, 600] },
    liveEveryMs: 5000,
  };

  // ======================= pure helpers (unit-testable in Node) =======================
  const num = Number.isFinite;
  const sum = (a) => a.reduce((s, v) => s + v, 0);
  const mean = (a) => (a.length ? sum(a) / a.length : null);
  const sortedCopy = (a) => [...a].sort((x, y) => x - y);
  const pctile = (a, p) => {
    if (!a.length) return null;
    const s = sortedCopy(a);
    return s[Math.min(s.length - 1, Math.max(0, Math.ceil((p / 100) * s.length) - 1))];
  };
  const median = (a) => {
    if (!a.length) return null;
    const s = sortedCopy(a), m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
  };
  const r1 = (v) => (v == null || !num(v) ? null : Math.round(v * 10) / 10);
  const pc = (n, d) => (d ? r1((100 * n) / d) : null);
  const dist = (ax, ay, bx, by) => Math.hypot(ax - bx, ay - by);
  const stats = (a) => {
    const v = a.filter(num);
    if (!v.length) return { n: 0, mean: null, median: null, p95: null, min: null, max: null };
    return { n: v.length, mean: r1(mean(v)), median: r1(median(v)), p95: r1(pctile(v, 95)), min: r1(Math.min(...v)), max: r1(Math.max(...v)) };
  };
  const validFrames = (fr) => fr.filter((f) => num(f.gx) && num(f.gy));

  // I-DT style fixation label for every valid frame (frames sorted by t)
  function labelFixations(fr, o = CFG.idt) {
    const out = new Array(fr.length).fill(false);
    let j = 0;
    for (let i = 0; i < fr.length; i++) {
      while (fr[i].t - fr[j].t > o.winMs) j++;
      if (fr[i].t - fr[j].t < o.minMs) continue;
      let minx = Infinity, maxx = -Infinity, miny = Infinity, maxy = -Infinity;
      for (let k = j; k <= i; k++) {
        minx = Math.min(minx, fr[k].gx); maxx = Math.max(maxx, fr[k].gx);
        miny = Math.min(miny, fr[k].gy); maxy = Math.max(maxy, fr[k].gy);
      }
      out[i] = maxx - minx + (maxy - miny) <= o.dispPx;
    }
    return out;
  }

  // gaze displacement over the last winMs for every valid frame (null while there is not enough history)
  function burstFlags(fr, o = CFG.sacc) {
    const out = [];
    let j = 0;
    for (let i = 0; i < fr.length; i++) {
      while (j < i && fr[i].t - fr[j].t > o.winMs) j++;
      const span = fr[i].t - fr[j].t;
      if (span < o.winMs * 0.5) { out.push(null); continue; }
      const dx = fr[i].gx - fr[j].gx, dy = fr[i].gy - fr[j].gy;
      out.push({ amp: Math.hypot(dx, dy), dx, dy, span });
    }
    return out;
  }

  // number of fast-movement events that happen outside the excluded windows ([[t0,t1], ...])
  function countBursts(frames, o = CFG.sacc, excl = []) {
    const v = validFrames(frames), b = burstFlags(v, o);
    let events = 0, last = -1e9;
    for (let i = 0; i < v.length; i++) {
      const q = b[i];
      if (!q || q.amp < o.minAmpPx) continue;
      const t = v[i].t;
      if (excl.some(([a, z]) => t >= a && t <= z)) continue;
      if (t - last > o.refractoryMs) events++;
      last = t;
    }
    return events;
  }

  // ---------- FIXATION ----------
  // steps: [{x, y, ts, te}] (px, ms). Accuracy = share of frames whose gaze estimate is within tol of the dot.
  function analyzeFixation(frames, steps, o = {}) {
    const c = { ...CFG, ...o };
    const tol = c.tolPx, tols = c.tolsPx;
    const dots = [];
    const dotToleranceAccuracy = [];
    const tot = { n: 0, valid: 0, hit: 0, hitTols: tols.map(() => 0), fixLab: 0, errs: [], bubbleHit: 0, bubbleN: 0 };
    steps.forEach((s, i) => {
      const w = frames.filter((f) => f.t >= s.ts + c.settleMs && f.t <= s.te);
      const v = validFrames(w);
      const errs = v.map((f) => dist(f.gx, f.gy, s.x, s.y));
      const lab = labelFixations(v, c.idt);
      const hit = errs.filter((e) => e <= tol).length;
      const tolHits = tols.map((t) => errs.filter((e) => e <= t).length);
      dotToleranceAccuracy.push(tolHits.map((hits) => pc(hits, v.length)));
      const cx = mean(v.map((f) => f.gx)), cy = mean(v.map((f) => f.gy));
      const rms = v.length ? Math.sqrt(mean(v.map((f) => (f.gx - cx) ** 2 + (f.gy - cy) ** 2))) : null;
      const bw = w.filter((f) => num(f.bx) && num(f.by));
      const bHit = bw.filter((f) => dist(f.bx, f.by, s.x, s.y) <= tol).length;
      dots.push({
        dot: i + 1, x: Math.round(s.x), y: Math.round(s.y), eligibleFrames: w.length, framesWithGaze: v.length,
        coveragePct: pc(v.length, w.length), accuracyPct: pc(hit, v.length),
        meanErrPx: r1(mean(errs)), offsetPx: v.length ? r1(dist(cx, cy, s.x, s.y)) : null, jitterRmsPx: r1(rms),
        fixationLabelPct: pc(lab.filter(Boolean).length, v.length), bubbleOnDotPct: pc(bHit, bw.length),
      });
      tot.n += w.length; tot.valid += v.length; tot.hit += hit; tot.errs.push(...errs);
      tols.forEach((t, k) => (tot.hitTols[k] += tolHits[k]));
      tot.fixLab += lab.filter(Boolean).length; tot.bubbleHit += bHit; tot.bubbleN += bw.length;
    });
    const excl = steps.map((s) => [s.ts, s.ts + c.sacc.maxLatMs]);
    const all = steps.length ? frames.filter((f) => f.t >= steps[0].ts && f.t <= steps[steps.length - 1].te) : [];
    const exclMs = excl.reduce((s, [a, z]) => s + (z - a), 0);
    const obsMs = steps.length ? steps[steps.length - 1].te - steps[0].ts - exclMs : 0;
    const spurious = countBursts(all, c.sacc, excl);
    const dotAccuracies = dots.map((dot) => dot.accuracyPct).filter(num);
    const dotCoverages = dots.map((dot) => dot.coveragePct).filter(num);
    return {
      test: "fixation", tolPx: tol, settleMs: c.settleMs, dots,
      framesTotal: tot.n, framesWithGaze: tot.valid,
      coveragePct: pc(tot.valid, tot.n),
      meanDotCoveragePct: r1(mean(dotCoverages)),
      fixationAccuracyPct: r1(mean(dotAccuracies)), // equal-weight mean of per-dot accuracy, among available gaze estimates
      fixationAccuracyOfValidPct: pc(tot.hit, tot.valid), // pooled conditional accuracy, retained for sample-weighted comparison
      accuracyByTolerance: tols.map((t, k) => ({
        tolPx: t,
        accuracyPct: r1(mean(dotToleranceAccuracy.map((dot) => dot[k]).filter(num))),
        pooledAccuracyPct: pc(tot.hitTols[k], tot.valid),
      })),
      fixationLabelPct: pc(tot.fixLab, tot.valid), // % of frames the system itself classified as a fixation
      bubbleOnDotPct: pc(tot.bubbleHit, tot.bubbleN),
      meanErrPx: r1(mean(tot.errs)), medianErrPx: r1(median(tot.errs)),
      meanDotErrorPx: r1(mean(dots.map((dot) => dot.meanErrPx).filter(num))),
      spuriousSaccades: spurious, spuriousSaccadesPerMin: obsMs > 0 ? r1((spurious * 60000) / obsMs) : null,
    };
  }

  // ---------- SACCADE ----------
  // steps[k] for k>=1 is a jump from steps[k-1] to steps[k] (ts = the moment the dot moved).
  function analyzeSaccades(frames, steps, bubble = [], o = {}) {
    const c = { ...CFG, ...o };
    const v = validFrames(frames), bf = burstFlags(v, c.sacc);
    const jumps = [];
    for (let k = 1; k < steps.length; k++) {
      const a = steps[k - 1], b = steps[k];
      const D = dist(a.x, a.y, b.x, b.y);
      if (D < 50) continue;
      const ux = (b.x - a.x) / D, uy = (b.y - a.y) / D, ts = b.ts, te = b.te;
      const pre = v.filter((f) => f.t >= ts - 250 && f.t < ts);
      const base = pre.length ? { x: median(pre.map((f) => f.gx)), y: median(pre.map((f) => f.gy)) } : null;
      let detT = null, peak = 0, t50 = null, landT = null;
      for (let i = 0; i < v.length; i++) {
        const t = v[i].t;
        if (t < ts + c.sacc.minLatMs || t > ts + c.sacc.maxLatMs) continue;
        const q = bf[i];
        if (!q) continue;
        const cos = (q.dx * ux + q.dy * uy) / (q.amp || 1);
        if (cos > c.sacc.dirMin) {
          peak = Math.max(peak, q.amp / (q.span / 1000));
          if (q.amp >= c.sacc.minAmpPx && detT == null) detT = t - ts;
        }
      }
      if (base) {
        for (const f of v) {
          if (f.t < ts || f.t > te) continue;
          if (((f.gx - base.x) * ux + (f.gy - base.y) * uy) / D >= 0.5) { t50 = f.t - ts; break; }
        }
      }
      const inStep = v.filter((f) => f.t >= ts && f.t <= te);
      for (const f of inStep) {
        if (dist(f.gx, f.gy, b.x, b.y) > c.tolPx) continue;
        const win = inStep.filter((g) => g.t >= f.t && g.t <= f.t + 200);
        if (win.length && win[win.length - 1].t - f.t >= 150 && win.every((g) => dist(g.gx, g.gy, b.x, b.y) <= c.tolPx)) { landT = f.t - ts; break; }
      }
      const tail = v.filter((f) => f.t >= te - 400 && f.t <= te);
      const landErr = tail.length ? median(tail.map((f) => dist(f.gx, f.gy, b.x, b.y))) : null;
      let bubT50 = null;
      const bs = bubble.filter((s) => num(s.x));
      const b0 = [...bs].reverse().find((s) => s.t <= ts);
      if (b0) {
        for (const s of bs) {
          if (s.t < ts || s.t > te) continue;
          if (((s.x - b0.x) * ux + (s.y - b0.y) * uy) / D >= 0.5) { bubT50 = s.t - ts; break; }
        }
      }
      jumps.push({
        jump: k, amplitudePx: Math.round(D), detected: detT != null, detectLatencyMs: detT == null ? null : Math.round(detT),
        peakSpeedPxS: Math.round(peak), gazeHalfwayMs: t50 == null ? null : Math.round(t50),
        gazeLandedMs: landT == null ? null : Math.round(landT), landingErrPx: r1(landErr),
        bubbleHalfwayMs: bubT50 == null ? null : Math.round(bubT50),
      });
    }
    const detected = jumps.filter((j) => j.detected).length;
    const excl = steps.slice(1).map((s) => [s.ts, s.ts + c.sacc.maxLatMs]);
    const exclMs = excl.reduce((s, [a, z]) => s + (z - a), 0);
    const all = steps.length ? frames.filter((f) => f.t >= steps[0].ts && f.t <= steps[steps.length - 1].te) : [];
    const obsMs = steps.length ? steps[steps.length - 1].te - steps[0].ts - exclMs : 0;
    const spurious = countBursts(all, c.sacc, excl);
    return {
      test: "saccade", jumps, total: jumps.length, detected,
      detectionRatePct: pc(detected, jumps.length), // HEADLINE
      detectLatencyMs: stats(jumps.map((j) => j.detectLatencyMs)),
      gazeHalfwayMs: stats(jumps.map((j) => j.gazeHalfwayMs)),
      gazeLandedMs: stats(jumps.map((j) => j.gazeLandedMs)),
      bubbleHalfwayMs: stats(jumps.map((j) => j.bubbleHalfwayMs)),
      landingErrPx: stats(jumps.map((j) => j.landingErrPx)),
      spuriousSaccades: spurious, spuriousSaccadesPerMin: obsMs > 0 ? r1((spurious * 60000) / obsMs) : null,
      rule: `saccade = gaze moved >= ${c.sacc.minAmpPx}px within ${c.sacc.winMs}ms toward the new dot, seen ${c.sacc.minLatMs}-${c.sacc.maxLatMs}ms after it moved`,
    };
  }

  // ---------- BLINK ----------
  function blinkEvents(frames, gap = CFG.blink.mergeGapMs) {
    const ev = [];
    let cur = null;
    for (const f of frames) {
      if (!(f.blinkish || f.closed)) continue;
      if (cur && f.t - cur.end <= gap) { cur.end = f.t; if (num(f.ear)) cur.earMin = Math.min(cur.earMin, f.ear); }
      else { cur = { start: f.t, end: f.t, earMin: num(f.ear) ? f.ear : 1 }; ev.push(cur); }
    }
    return ev;
  }

  // cues: [ms timestamps when the student was told to blink]
  function analyzeBlink(frames, cues = [], o = {}) {
    const c = { ...CFG, ...o }, B = c.blink;
    const events = blinkEvents(frames, B.mergeGapMs);
    const v = validFrames(frames);
    const used = new Set();
    const cueRows = cues.map((tc, i) => {
      const k = events.findIndex((e, idx) => !used.has(idx) && e.start >= tc + B.cueWindowMs[0] && e.start <= tc + B.cueWindowMs[1]);
      if (k >= 0) used.add(k);
      return { cue: i + 1, detected: k >= 0, latencyMs: k >= 0 ? Math.round(events[k].start - tc) : null };
    });
    const rows = events.map((e, idx) => {
      const fw = frames.filter((f) => f.t >= e.start && f.t <= e.end);
      const landmark = fw.filter((f) => f.faceOk).length;
      const rawOk = fw.filter((f) => f.rawOk).length;
      const yoloNew = frames.some((f) => f.t >= e.start && f.t <= e.end && f.yoloOk && f.yoloAt > e.start);
      const rec = frames.find((f) => f.t > e.end && f.rawOk && num(f.gx));
      const yRec = frames.find((f) => f.t > e.end && f.yoloOk && f.yoloAt > e.end);
      const pre = v.filter((f) => f.t >= e.start - B.preMs[0] && f.t <= e.start - B.preMs[1]);
      const post = v.filter((f) => f.t >= e.end + B.postMs[0] && f.t <= e.end + B.postMs[1]);
      const shift = pre.length && post.length
        ? dist(median(pre.map((f) => f.gx)), median(pre.map((f) => f.gy)), median(post.map((f) => f.gx)), median(post.map((f) => f.gy))) : null;
      return {
        blink: idx + 1, cueMatched: used.has(idx), durationMs: Math.round(e.end - e.start), earMin: r1(e.earMin * 100) / 100,
        frames: fw.length, landmarkFrames: landmark, featureFrames: rawOk, landmarkTrackedPct: pc(landmark, fw.length), featuresAvailablePct: pc(rawOk, fw.length),
        yoloNewResultDuringBlink: yoloNew, featuresRecoveredMs: rec ? Math.round(rec.t - e.end) : null,
        yoloRecoveredMs: yRec ? Math.round(yRec.yoloAt - e.end) : null, gazeShiftPx: r1(shift),
      };
    });
    const fAll = rows.reduce((s, r) => s + r.frames, 0);
    const detected = cueRows.filter((r) => r.detected).length;
    return {
      test: "blink", cues: cues.length, cuesDetected: detected,
      blinkDetectionPct: cues.length ? pc(detected, cues.length) : null, // HEADLINE (needs cues)
      eventsSeen: events.length, extraEvents: events.length - used.size,
      cueLatencyMs: stats(cueRows.map((r) => r.latencyMs)),
      durationMs: stats(rows.map((r) => r.durationMs)),
      landmarkTrackedDuringBlinkPct: pc(rows.reduce((s, r) => s + r.landmarkFrames, 0), fAll),
      yoloNewResultDuringBlinkPct: pc(rows.filter((r) => r.yoloNewResultDuringBlink).length, rows.length),
      featuresAvailableDuringBlinkPct: pc(rows.reduce((s, r) => s + r.featureFrames, 0), fAll),
      featuresRecoveredMs: stats(rows.map((r) => r.featuresRecoveredMs)),
      yoloRecoveredMs: stats(rows.map((r) => r.yoloRecoveredMs)),
      gazeShiftPx: stats(rows.map((r) => r.gazeShiftPx)),
      cueRows, rows,
    };
  }

  // ---------- FALSE POSITIVES ----------
  // phases: [{name, t0, t1}]. In every phase the student is doing the right thing, so any alert is a false positive.
  function analyzeFP(frames, phases, strikeEq = []) {
    const out = [];
    const T = { n: 0, alert: 0, flagged: 0, warn: 0, gazeNotOk: 0, strikes: 0, ms: 0, win: 0, winBad: 0 };
    for (const p of phases) {
      const w = frames.filter((f) => f.t >= p.t0 && f.t <= p.t1);
      const reasons = {};
      w.filter((f) => f.flagged).forEach((f) => (reasons[f.flagReason] = (reasons[f.flagReason] || 0) + 1));
      const alert = w.filter((f) => f.alert).length, flagged = w.filter((f) => f.flagged).length, warn = w.filter((f) => f.warn && !f.flagged).length;
      const gnok = w.filter((f) => f.gazeOk === false).length, withState = w.filter((f) => f.gazeOk != null).length;
      const strikes = strikeEq.filter((s) => s.t >= p.t0 && s.t <= p.t1);
      const secs = Math.max(1, Math.round((p.t1 - p.t0) / 1000));
      let winBad = 0;
      for (let s = 0; s < secs; s++) {
        const a = p.t0 + s * 1000;
        if (w.some((f) => f.t >= a && f.t < a + 1000 && f.alert)) winBad++;
      }
      out.push({
        phase: p.name, seconds: secs, frames: w.length, alertFrames: alert, cleanFrames: w.length - alert,
        falsePositiveRatePct: pc(alert, w.length), // FP / (FP + TN), frame level
        flaggedFrames: flagged, warningOnlyFrames: warn, gazeOutsideFrames: gnok, gazeOutsidePct: pc(gnok, withState),
        wouldBeStrikes: strikes.length, alertSecondsPct: pc(winBad, secs), reasons,
      });
      T.n += w.length; T.alert += alert; T.flagged += flagged; T.warn += warn; T.gazeNotOk += gnok; T.strikes += strikes.length;
      T.ms += p.t1 - p.t0; T.win += secs; T.winBad += winBad;
    }
    return {
      test: "falsePositive", phases: out, frames: T.n, falsePositiveFrames: T.alert, trueNegativeFrames: T.n - T.alert,
      falsePositiveRatePct: pc(T.alert, T.n), // HEADLINE: frame-level FPR
      alertSecondsPct: pc(T.winBad, T.win), // share of 1-second windows that contained any alert
      wouldBeStrikes: T.strikes, wouldBeStrikesPerMin: T.ms ? r1((T.strikes * 60000) / T.ms) : null,
      definition: "FPR = frames with an alert / all frames, while the student looks at the exam area (every alert is false)",
    };
  }

  // ---------- LATENCY (pipeline) ----------
  function analyzeLatency(frames, y0, y1) {
    const n = frames.length;
    const span = n > 1 ? frames[n - 1].t - frames[0].t : 0;
    const confidenceStats = (key) => stats(frames.map((f) => f[key]).filter(num).map((v) => v * 100));
    let yolo = null;
    if (y0 && y1) {
      const runs = y1.runs - y0.runs;
      const ms = y1.recent.slice(-Math.min(runs, y1.recent.length));
      yolo = { runs, ok: y1.ok - y0.ok, foundPct: pc(y1.ok - y0.ok, runs), runsPerSec: span ? r1((runs * 1000) / span) : null, inferenceMs: stats(ms) };
    }
    return {
      test: "latency", frames: n, fps: span ? r1(((n - 1) * 1000) / span) : null,
      frameIntervalMs: stats(frames.map((f) => f.dt)), pipelineMs: stats(frames.map((f) => f.pipeMs)), yolo,
      faceDetectedPct: pc(frames.filter((f) => f.faceOk).length, n), featuresAvailablePct: pc(frames.filter((f) => f.rawOk).length, n),
      alertPct: pc(frames.filter((f) => f.alert).length, n),
      modelMetrics: {
        eyeModelConfidencePct: confidenceStats("eyeModelConfidence"),
        eyeKeypointConfidencePct: confidenceStats("eyeKeypointConfidence"),
        eyeQualityPct: confidenceStats("eyeQuality"),
        detectedEyesPerFrame: stats(frames.map((f) => f.detectedEyes)),
        eyeResultAgeMs: stats(frames.map((f) => f.eyeResultAgeMs)),
      },
    };
  }

  // ======================= runtime (browser only) =======================
  const rt = { frames: [], cur: null, lastBegin: 0, flagRuns: {}, strikeEq: [], rec: null, busy: false, abort: false, ui: null, liveTimer: null, results: {}, modelInfo: {} };
  const GM = { CFG, results: rt.results };

  const ystats = () => {
    const y = root.YoloEye;
    return y && y.stats ? { runs: y.stats.runs, ok: y.stats.ok, miss: y.stats.miss, recent: y.stats.recent.slice() } : null;
  };

  function begin(results) {
    const t = performance.now();
    const n = (results && results.multiFaceLandmarks && results.multiFaceLandmarks.length) || 0;
    const fr = {
      t, dt: rt.lastBegin ? t - rt.lastBegin : null, nFaces: n, faceOk: n > 0, ear: null, closed: false, blinkish: false,
      rawOk: false, yoloAt: 0, yoloOk: false, ex: null, ey: null, gx: null, gy: null, bx: null, by: null,
      gazeOk: null, awayMs: null, warn: false, flagged: false, flagReason: null, alert: false, pipeMs: null,
      eyeModelConfidence: null, eyeKeypointConfidence: null,
      eyeQuality: null, detectedEyes: 0, eyeResultAgeMs: null, eyeBoxes: [],
    };
    rt.lastBegin = t;
    rt.cur = fr;
    return fr;
  }
  function end(fr) {
    fr.pipeMs = performance.now() - fr.t;
    fr.warn = fr.awayMs != null && fr.awayMs > 250;
    fr.alert = fr.flagged || fr.warn;
    const y = root.YoloEye;
    if (y) {
      fr.yoloAt = y.lastGazeAt || 0;
      fr.yoloOk = !!y.lastGaze;
      fr.eyeResultAgeMs = y.lastGazeAt ? Math.max(0, performance.now() - y.lastGazeAt) : null;
      const eyes = y.lastGaze && Array.isArray(y.lastGaze.per) ? y.lastGaze.per : [];
      const meanOf = (values) => values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
      const boxCorners = (matrix, box) => {
        const [a, b, tx, d, e, ty] = matrix;
        const determinant = a * e - b * d;
        return [[box[0], box[1]], [box[2], box[1]], [box[2], box[3]], [box[0], box[3]]].map(([x, y]) => {
          const dx = x - tx, dy = y - ty;
          return { x: (e * dx - b * dy) / determinant, y: (-d * dx + a * dy) / determinant };
        });
      };
      fr.detectedEyes = eyes.length;
      fr.eyeModelConfidence = meanOf(eyes.map((eye) => eye.r && eye.r.score).filter(num));
      fr.eyeKeypointConfidence = meanOf(eyes.flatMap((eye) => eye.r && Array.isArray(eye.r.k) ? eye.r.k.map((point) => point[2]).filter(num) : []));
      fr.eyeQuality = meanOf(eyes.map((eye) => eye.q).filter(num));
      fr.eyeBoxes = eyes.filter((eye) => eye.r && eye.r.box && eye.r.M).map((eye) => {
        const corners = boxCorners(eye.r.M, eye.r.box);
        const xs = corners.map((point) => point.x), ys = corners.map((point) => point.y);
        const x = Math.min(...xs), y = Math.min(...ys);
        return { eye: eye.lab, x, y, width: Math.max(...xs) - x, height: Math.max(...ys) - y, confidence: eye.r.score };
      });
    }
    try { fr.bx = bubbleX; fr.by = bubbleY; } catch (_) { /* bubble globals not defined */ }
    rt.frames.push(fr);
    if (rt.frames.length > CFG.maxFrames) rt.frames.splice(0, 5000);
    if (rt.cur === fr) rt.cur = null;
  }

  // ---- hooks called from exam-gaze-block.js ----
  GM.onEye = (ear, blinkish, closed) => { const f = rt.cur; if (f) { f.ear = ear; f.blinkish = !!blinkish; f.closed = !!closed; } };
  GM.onModelMetrics = (metrics) => {
    rt.modelInfo = {
      faceMesh: { confidenceExposed: false, minDetectionConfidence: metrics.faceMeshMinConfidence, minTrackingConfidence: metrics.faceMeshMinConfidence },
    };
  };
  GM.onRaw = (raw) => { const f = rt.cur; if (f) f.rawOk = !!raw; };
  GM.onGaze = (t, ex, ey, gx, gy) => { const f = rt.cur; if (f) { f.ex = ex; f.ey = ey; f.gx = gx; f.gy = gy; } };
  GM.onState = (gazeOk, awayMs) => { const f = rt.cur; if (f) { f.gazeOk = !!gazeOk; f.awayMs = awayMs; } };
  GM.onFlag = (reason, ms) => {
    const now = performance.now(), f = rt.cur;
    if (f) { f.flagged = true; f.flagReason = reason; }
    let r = rt.flagRuns[reason];
    if (!r || now - r.last > 400) r = rt.flagRuns[reason] = { since: now, last: now, lastFire: -1e9 };
    r.last = now;
    // same rule as flagAway + registerStrikeOnce: flagged longer than `ms`, then at most one strike per 1.2 s
    if (now - r.since > ms && now - r.lastFire >= 1200) { r.lastFire = now; rt.strikeEq.push({ t: now, reason }); }
  };

  function install() {
    if (typeof root.onResults !== "function") return false;
    if (root.onResults.__gmWrapped) return true;
    const orig = root.onResults;
    const wrapped = async function (results) {
      const fr = begin(results);
      try { return await orig.call(this, results); } finally { end(fr); }
    };
    wrapped.__gmWrapped = true;
    root.onResults = wrapped;
    return true;
  }

  // ---- recording ----
  function startRec(name) {
    const rec = { name, t0: performance.now(), t1: null, y0: ystats(), y1: null, bubble: [], frames: [] };
    rt.rec = rec;
    (function loop() {
      if (rt.rec !== rec) return;
      try { rec.bubble.push({ t: performance.now(), x: bubbleX, y: bubbleY }); } catch (_) { /* no bubble */ }
      requestAnimationFrame(loop);
    })();
    return rec;
  }
  function stopRec(rec) {
    rec.t1 = performance.now();
    rec.y1 = ystats();
    if (rt.rec === rec) rt.rec = null;
    rec.frames = rt.frames.filter((f) => f.t >= rec.t0 && f.t <= rec.t1);
    return rec;
  }

  // ---- stimulus UI ----
  const sleep = (ms) => new Promise((r) => setTimeout(r, Math.max(0, ms)));
  const nextFrame = () => new Promise((r) => requestAnimationFrame(() => r()));
  function ensureUI() {
    if (rt.ui) return rt.ui;
    const wrap = document.createElement("div");
    wrap.style.cssText = "position:fixed;inset:0;pointer-events:none;z-index:2147483000;display:none;";
    const dot = document.createElement("div");
    dot.style.cssText = "position:absolute;width:26px;height:26px;border-radius:50%;background:#ffd400;border:3px solid #000;box-shadow:0 0 0 3px #fff;transform:translate(-50%,-50%);transition:none;";
    const bar = document.createElement("div");
    bar.style.cssText = "position:absolute;top:10px;left:50%;transform:translateX(-50%);padding:8px 16px;border-radius:8px;background:rgba(0,0,0,.85);color:#fff;font:600 15px system-ui,sans-serif;white-space:nowrap;";
    wrap.append(dot, bar);
    document.body.appendChild(wrap);
    rt.ui = { wrap, dot, bar };
    return rt.ui;
  }
  const setDot = (x, y) => { const u = ensureUI(); u.dot.style.left = x + "px"; u.dot.style.top = y + "px"; };
  const setBar = (t) => { ensureUI().bar.textContent = t; };
  function flashDot() {
    const d = ensureUI().dot;
    d.style.background = "#00e676"; d.style.width = d.style.height = "44px";
    setTimeout(() => { d.style.background = "#ffd400"; d.style.width = d.style.height = "26px"; }, 300);
  }

  // Waits for a click / Space / Enter (Esc aborts). The overlay only captures clicks while it is waiting.
  function waitForStart(label, x, y) {
    const u = ensureUI();
    setDot(x, y);
    setBar(`${label} — click or press Space when ready (Esc cancels)`);
    u.wrap.style.pointerEvents = "auto";
    u.wrap.style.cursor = "pointer";
    return new Promise((resolve) => {
      let finished = false;
      const finish = () => {
        if (finished) return;
        finished = true;
        document.removeEventListener("keydown", onKey, true);
        u.wrap.removeEventListener("click", finish);
        clearInterval(poll);
        u.wrap.style.pointerEvents = "none";
        u.wrap.style.cursor = "";
        resolve();
      };
      const onKey = (e) => {
        if (e.key === " " || e.key === "Enter") { e.preventDefault(); e.stopPropagation(); finish(); }
        else if (e.key === "Escape") { rt.abort = true; finish(); }
      };
      const poll = setInterval(() => { if (rt.abort) finish(); }, 200); // GM.stop() also releases the wait
      document.addEventListener("keydown", onKey, true);
      u.wrap.addEventListener("click", finish);
    });
  }

  async function countdown(label, x, y, sec = 3, gate = CFG.gate) {
    setDot(x, y);
    if (gate) await waitForStart(label, x, y);
    for (let s = sec; s > 0 && !rt.abort; s--) { setBar(`${label} — starting in ${s}…`); await sleep(1000); }
  }

  // steps: [{x, y, dur, label, cues?: [ms offsets]}] -> fills ts / te (and cueTimes) on every step
  async function runPlan(steps, title) {
    const total = steps.reduce((s, st) => s + st.dur, 0);
    const t00 = performance.now();
    const tick = setInterval(() => { /* keeps the banner countdown fresh */
      const left = Math.max(0, Math.ceil((total - (performance.now() - t00)) / 1000));
      if (rt.curLabel) setBar(`${title} — ${rt.curLabel} — ${left}s`);
    }, 250);
    try {
      for (let i = 0; i < steps.length && !rt.abort; i++) {
        const s = steps[i];
        rt.curLabel = s.label || `${i + 1}/${steps.length}`;
        setDot(s.x, s.y);
        await nextFrame();
        s.ts = performance.now();
        s.cueTimes = [];
        (s.cues || []).forEach((off) => setTimeout(() => { if (rt.abort) return; flashDot(); s.cueTimes.push(performance.now()); }, off));
        await sleep(s.ts + s.dur - performance.now());
        s.te = performance.now();
      }
    } finally { clearInterval(tick); rt.curLabel = null; }
    return steps.filter((s) => s.te);
  }

  function preflight() {
    const y = root.YoloEye;
    if (!y || !y.isReady()) return { ok: false, why: "YoloEye is not ready yet (model still loading)." };
    let hasModel = true;
    try { hasModel = !!model; } catch (_) { /* model global missing */ }
    if (!hasModel) return { ok: false, why: "No gaze calibration loaded - calibrate first." };
    const last = rt.frames[rt.frames.length - 1];
    if (!last || performance.now() - last.t > 1500) return { ok: false, why: "No camera frames are arriving (is the camera running and onResults wrapped?)." };
    if (typeof root.onResults === "function" && !root.onResults.__gmWrapped) return { ok: false, why: "onResults is not wrapped - load gaze-metrics.js right after exam-gaze-block.js." };
    return { ok: true };
  }

  async function withTest(name, fn) {
    if (rt.busy) { console.warn("[GazeMetrics] a test is already running (Esc aborts it)."); return null; }
    const pf = preflight();
    if (!pf.ok) { console.error("[GazeMetrics] cannot start:", pf.why); return null; }
    rt.busy = true; rt.abort = false;
    const prev = root.allowStrikes;
    root.allowStrikes = false; // tests must never create real strikes
    ensureUI().wrap.style.display = "block";
    const onKey = (e) => { if (e.key === "Escape") { rt.abort = true; console.warn("[GazeMetrics] aborted"); } };
    document.addEventListener("keydown", onKey, true);
    console.log(`%c[GazeMetrics] ${name} test started - Esc aborts. Real strikes are OFF during the test.`, "color:#0a7");
    try { return await fn(); }
    finally {
      document.removeEventListener("keydown", onKey, true);
      root.allowStrikes = (root.examStarted && !root.examFinished && !root.submitting) ? true : prev;
      const u = ensureUI();
      u.wrap.style.display = "none";
      u.wrap.style.pointerEvents = "none";
      rt.busy = false;
    }
  }

  const VW = () => root.innerWidth, VH = () => root.innerHeight;
  function fixationPoints(n) {
    const W = VW(), H = VH();
    const P = (fx, fy) => ({ x: fx * W, y: fy * H });
    const five = [P(0.5, 0.5), P(0.2, 0.25), P(0.8, 0.25), P(0.8, 0.75), P(0.2, 0.75)];
    if (n <= 5) return five.slice(0, n);
    return five.concat([P(0.5, 0.2), P(0.5, 0.8), P(0.2, 0.5), P(0.8, 0.5)]).slice(0, n);
  }
  function safeRect() {
    const el = root.examStarted ? document.getElementById("examCard") : document.getElementById("examGate");
    const r = el ? el.getBoundingClientRect() : null;
    const left = Math.max(r ? r.left : 0, 0), top = Math.max(r ? r.top : 0, 0);
    const right = Math.min(r ? r.right : VW(), VW()), bottom = Math.min(r ? r.bottom : VH(), VH());
    return right - left > 120 && bottom - top > 120 ? { left, top, right, bottom } : { left: 0, top: 0, right: VW(), bottom: VH() };
  }

  // ======================= tests =======================
  // every test accepts { gate: false } to skip the click-to-start step for that run
  GM.runFixation = (opt = {}) => withTest("fixation", async () => {
    const o = { dots: 5, dwellMs: 3000, ...opt };
    const pts = fixationPoints(o.dots);
    const steps = pts.map((p, i) => ({ ...p, dur: o.dwellMs, label: `dot ${i + 1}/${pts.length}` }));
    await countdown("FIXATION: stare at the yellow dot, it will move between points", steps[0].x, steps[0].y, 3, o.gate ?? CFG.gate);
    if (rt.abort) return null;
    const rec = startRec("fixation");
    const done = await runPlan(steps, "FIXATION");
    stopRec(rec);
    const res = analyzeFixation(rec.frames, done, o);
    res.latency = analyzeLatency(rec.frames, rec.y0, rec.y1);
    rt.results.fixation = res; printFixation(res);
    return res;
  });

  GM.runSaccade = (opt = {}) => withTest("saccade", async () => {
    const o = { jumps: 10, holdMs: 1300, pattern: "horizontal", ...opt };
    const W = VW(), H = VH();
    const sets = {
      horizontal: [{ x: 0.2 * W, y: 0.5 * H }, { x: 0.8 * W, y: 0.5 * H }],
      diagonal: [{ x: 0.2 * W, y: 0.25 * H }, { x: 0.8 * W, y: 0.75 * H }],
      mixed: [{ x: 0.2 * W, y: 0.25 * H }, { x: 0.8 * W, y: 0.75 * H }, { x: 0.8 * W, y: 0.25 * H }, { x: 0.2 * W, y: 0.75 * H }],
    };
    const set = sets[o.pattern] || sets.horizontal;
    const steps = [{ x: 0.5 * W, y: 0.5 * H, dur: 1500, label: "start" }];
    for (let i = 0; i < o.jumps; i++) steps.push({ ...set[i % set.length], dur: o.holdMs, label: `jump ${i + 1}/${o.jumps}` });
    await countdown("SACCADE: follow the dot with your eyes as FAST as you can", steps[0].x, steps[0].y, 3, o.gate ?? CFG.gate);
    if (rt.abort) return null;
    const rec = startRec("saccade");
    const done = await runPlan(steps, "SACCADE");
    stopRec(rec);
    const res = analyzeSaccades(rec.frames, done, rec.bubble, o);
    res.latency = analyzeLatency(rec.frames, rec.y0, rec.y1);
    rt.results.saccade = res; printSaccade(res);
    return res;
  });

  GM.runBlink = (opt = {}) => withTest("blink", async () => {
    const o = { cues: 10, gapMs: 1600, ...opt };
    const W = VW(), H = VH();
    const cues = Array.from({ length: o.cues }, (_, i) => 1500 + i * o.gapMs);
    const steps = [{ x: 0.5 * W, y: 0.5 * H, dur: cues[cues.length - 1] + 1200, cues, label: "blink when the dot turns GREEN" }];
    await countdown("BLINK: keep looking at the dot, blink ONCE each time it turns green", steps[0].x, steps[0].y, 3, o.gate ?? CFG.gate);
    if (rt.abort) return null;
    const rec = startRec("blink");
    const done = await runPlan(steps, "BLINK");
    stopRec(rec);
    const res = analyzeBlink(rec.frames, (done[0] && done[0].cueTimes) || [], o);
    res.latency = analyzeLatency(rec.frames, rec.y0, rec.y1);
    rt.results.blink = res; printBlink(res);
    return res;
  });

  GM.runFalsePositive = (opt = {}) => withTest("false-positive", async () => {
    const o = { phaseMs: 10000, ...opt };
    const R = safeRect(), w = R.right - R.left, h = R.bottom - R.top;
    const P = (fx, fy) => ({ x: R.left + fx * w, y: R.top + fy * h });
    const c0 = P(0.5, 0.5);
    const sacc = [P(0.25, 0.3), P(0.75, 0.7), P(0.75, 0.3), P(0.25, 0.7)];
    const phases = [
      { name: "FIXATION", intro: "Look at the dot and keep still", steps: [{ ...c0, dur: o.phaseMs, label: "fixation" }] },
      { name: "SACCADES", intro: "Follow the dot with your eyes (stay inside the exam area)", steps: Array.from({ length: 10 }, (_, i) => ({ ...sacc[i % 4], dur: o.phaseMs / 10, label: `saccade ${i + 1}/10` })) },
      { name: "CAMERA MOVING", intro: "Look at the dot and gently move / tilt the laptop or camera", steps: [{ ...c0, dur: o.phaseMs, label: "camera moving" }] },
    ];
    const marks = [];
    for (const ph of phases) {
      if (rt.abort) return null;
      await countdown(`FALSE-POSITIVE · ${ph.name}: ${ph.intro}`, ph.steps[0].x, ph.steps[0].y, 3, o.gate ?? CFG.gate);
      if (rt.abort) return null;
      const rec = startRec("fp-" + ph.name);
      const done = await runPlan(ph.steps, ph.name);
      stopRec(rec);
      if (done.length) marks.push({ name: ph.name, t0: done[0].ts, t1: done[done.length - 1].te });
    }
    const res = analyzeFP(rt.frames, marks, rt.strikeEq);
    rt.results.falsePositive = res; printFP(res);
    return res;
  });

  // runs every test in order; stops as soon as you press Esc
  GM.runAll = async (opt = {}) => {
    const steps = [GM.runBlink, GM.runFixation, GM.runSaccade, GM.runFalsePositive];
    for (const run of steps) {
      const res = await run(opt);
      if (res == null || rt.abort) { console.warn("[GazeMetrics] runAll stopped (aborted or could not start)."); break; }
    }
    GM.summary();
  };

  GM.setGate = (on = true) => { CFG.gate = !!on; return CFG.gate; };

  // ======================= console output =======================
  const H1 = "font-weight:700;color:#0a7;font-size:13px";
  function printFixation(r) {
    console.groupCollapsed("%c[Fixation] conditional accuracy " + r.fixationAccuracyPct + "% (within " + r.tolPx + " px)", H1);
    console.table(r.dots);
    console.log(`Conditional accuracy (equal-weight mean across dots; only available gaze estimates): ${r.fixationAccuracyPct}%`);
    console.log(`Pooled conditional accuracy: ${r.fixationAccuracyOfValidPct}% · gaze coverage (reported separately, not counted as an accuracy miss): ${r.coveragePct}% overall / ${r.meanDotCoveragePct}% mean per dot`);
    console.log(`System-labelled "fixation" frames: ${r.fixationLabelPct}% · bubble on dot: ${r.bubbleOnDotPct}%`);
    console.log(`Mean error ${r.meanErrPx}px pooled / ${r.meanDotErrorPx}px equal-weight per dot · median ${r.medianErrPx}px · spurious saccades while fixating: ${r.spuriousSaccades} (${r.spuriousSaccadesPerMin}/min)`);
    console.table(r.accuracyByTolerance);
    console.groupEnd();
    console.log(`%c[Fixation] ${r.fixationAccuracyPct}% mean per-dot conditional accuracy (≤${r.tolPx}px)`, H1);
  }
  function printSaccade(r) {
    console.groupCollapsed("%c[Saccade] detected " + r.detected + "/" + r.total + " (" + r.detectionRatePct + "%)", H1);
    console.table(r.jumps);
    console.log(r.rule);
    console.log("Stimulus → saccade detected (ms):", r.detectLatencyMs);
    console.log("Stimulus → gaze halfway (ms):", r.gazeHalfwayMs, " · → bubble halfway (ms):", r.bubbleHalfwayMs);
    console.log("Gaze landed on the new dot (ms):", r.gazeLandedMs, " · landing error (px):", r.landingErrPx);
    console.log(`Spurious saccades while the dot was still: ${r.spuriousSaccades} (${r.spuriousSaccadesPerMin}/min)`);
    console.log("NB: these times include the human reaction time (~150-300 ms); the camera/model part alone is under Response latency.");
    console.groupEnd();
    console.log(`%c[Saccade] ${r.detected}/${r.total} saccades detected (${r.detectionRatePct}%), median ${r.detectLatencyMs.median} ms after the dot moved`, H1);
  }
  function printBlink(r) {
    console.groupCollapsed("%c[Blink] " + r.cuesDetected + "/" + r.cues + " cued blinks detected", H1);
    console.table(r.rows);
    console.log(`Blinks detected vs cues: ${r.cuesDetected}/${r.cues} (${r.blinkDetectionPct}%) · extra blink events: ${r.extraEvents}`);
    console.log(`During a blink: face landmarks tracked ${r.landmarkTrackedDuringBlinkPct}% · YOLO produced a new eye result ${r.yoloNewResultDuringBlinkPct}% · gaze features available ${r.featuresAvailableDuringBlinkPct}%`);
    console.log("Recovery after the eye re-opens (ms) - features:", r.featuresRecoveredMs, " YOLO:", r.yoloRecoveredMs);
    console.log("Gaze shift caused by the blink (px):", r.gazeShiftPx, " · blink duration (ms, includes the ~120 ms settle window):", r.durationMs);
    console.log("By design YOLO is not run while the eye is closed (EAR below threshold), so a low YOLO / feature % during the blink itself is expected; the recovery time is what matters.");
    console.groupEnd();
    console.log(`%c[Blink] landmarks tracked through blinks ${r.landmarkTrackedDuringBlinkPct}%, gaze shift median ${r.gazeShiftPx.median} px`, H1);
  }
  function printFP(r) {
    console.groupCollapsed("%c[False positives] FPR " + r.falsePositiveRatePct + "%", H1);
    console.table(r.phases.map((p) => ({ ...p, reasons: JSON.stringify(p.reasons) })));
    console.log(`FP frames ${r.falsePositiveFrames} · TN frames ${r.trueNegativeFrames} · FPR = ${r.falsePositiveRatePct}%`);
    console.log(`Seconds that contained an alert: ${r.alertSecondsPct}% · would-be strikes: ${r.wouldBeStrikes} (${r.wouldBeStrikesPerMin}/min)`);
    console.log(r.definition);
    console.groupEnd();
    console.log(`%c[False positives] FPR ${r.falsePositiveRatePct}% (${r.falsePositiveFrames}/${r.frames} frames), ${r.wouldBeStrikes} would-be strikes`, H1);
  }
  function printLatency(r) {
    console.log(`%c[Latency] ${r.fps} fps · pipeline median ${r.pipelineMs.median} ms (p95 ${r.pipelineMs.p95}) · YOLO ${r.yolo ? r.yolo.inferenceMs.median : "-"} ms`, H1);
    const t = { "frame interval (ms)": r.frameIntervalMs, "pipeline per frame (ms)": r.pipelineMs };
    if (r.yolo) t["YOLO inference (ms)"] = r.yolo.inferenceMs;
    t["YOLO eye confidence (%)"] = r.modelMetrics.eyeModelConfidencePct;
    t["YOLO keypoint confidence (%)"] = r.modelMetrics.eyeKeypointConfidencePct;
    t["YOLO eye quality (%)"] = r.modelMetrics.eyeQualityPct;
    console.table(t);
  }

  function modelSnapshot() {
    const y = root.YoloEye;
    return {
      faceMesh: { ...rt.modelInfo.faceMesh },
      yoloEye: y ? {
        ready: !!y.isReady(),
        accelerator: y.accelerator || null,
        info: y.info || null,
        config: y.exportCfg ? y.exportCfg() : null,
        stats: y.stats ? { runs: y.stats.runs, found: y.stats.ok, missed: y.stats.miss, errors: y.stats.err } : null,
      } : { ready: false },
    };
  }

  GM.models = () => {
    const snapshot = modelSnapshot();
    console.group("%c[Model telemetry]", H1);
    console.log("Model setup:", snapshot);
    const frames = rt.frames.slice(-300);
    const metrics = analyzeLatency(frames, null, null).modelMetrics;
    console.table({
      "FaceMesh tracking rate (%)": pc(frames.filter((f) => f.faceOk).length, frames.length),
      "YOLO eye confidence (%)": metrics.eyeModelConfidencePct,
      "YOLO keypoint confidence (%)": metrics.eyeKeypointConfidencePct,
      "YOLO eye quality (%)": metrics.eyeQualityPct,
      "YOLO eyes found per frame": metrics.detectedEyesPerFrame,
      "YOLO result age (ms)": metrics.eyeResultAgeMs,
    });
    const latestBoxes = [...frames].reverse().find((frame) => frame.eyeBoxes.length);
    if (latestBoxes) {
      console.log("Latest YOLO eye bounding boxes (camera-frame pixels):");
      console.table(latestBoxes.eyeBoxes);
    } else console.log("Latest YOLO eye bounding boxes: no eye boxes yet");
    console.log("Confidence values are model scores, not calibrated accuracy. FaceMesh does not provide a confidence score.");
    console.groupEnd();
    return snapshot;
  };

  GM.latency = (sinceMs = 10000) => {
    const t = performance.now();
    const f = rt.frames.filter((x) => x.t >= t - sinceMs);
    const res = analyzeLatency(f, null, null);
    const y = ystats();
    if (y && y.recent.length) res.yolo = { runs: y.runs, ok: y.ok, foundPct: pc(y.ok, y.runs), inferenceMs: stats(y.recent) };
    rt.results.latency = res; printLatency(res);
    return res;
  };

  GM.summary = () => {
    const R = rt.results, rows = [];
    if (R.fixation) {
      const tol = (R.fixation.accuracyByTolerance || []).map((x) => `${x.tolPx}px ${x.accuracyPct}%`).join(" · ");
      rows.push({ Metric: "Fixation accuracy (conditional, mean per dot)", Result: R.fixation.fixationAccuracyPct + " %", Detail: `within ${R.fixation.tolPx}px · pooled conditional accuracy ${R.fixation.fixationAccuracyOfValidPct}% · coverage ${R.fixation.coveragePct}% (separate) · mean per-dot error ${R.fixation.meanDotErrorPx}px · by tolerance: ${tol}` });
    }
    if (R.blink) rows.push({ Metric: "Blink detection", Result: (R.blink.blinkDetectionPct ?? "-") + " %", Detail: `${R.blink.cuesDetected}/${R.blink.cues} cued · landmarks tracked in blink ${R.blink.landmarkTrackedDuringBlinkPct}% · YOLO result in blink ${R.blink.yoloNewResultDuringBlinkPct}% · gaze shift ${R.blink.gazeShiftPx.median}px` });
    if (R.saccade) rows.push({ Metric: "Saccade detection", Result: R.saccade.detectionRatePct + " %", Detail: `${R.saccade.detected}/${R.saccade.total} · detected ${R.saccade.detectLatencyMs.median} ms after the dot moved (incl. human reaction) · bubble halfway ${R.saccade.bubbleHalfwayMs.median} ms` });
    const L = (R.saccade || R.fixation || R.blink || {}).latency || R.latency;
    if (L) rows.push({ Metric: "Response latency (system)", Result: (L.pipelineMs.median ?? "-") + " ms", Detail: `per frame, p95 ${L.pipelineMs.p95} ms · ${L.fps} fps · YOLO ${L.yolo ? L.yolo.inferenceMs.median : "-"} ms` });
    if (R.falsePositive) rows.push({ Metric: "False-positive rate", Result: R.falsePositive.falsePositiveRatePct + " %", Detail: `${R.falsePositive.falsePositiveFrames}/${R.falsePositive.frames} frames · ${R.falsePositive.wouldBeStrikes} would-be strikes (${R.falsePositive.wouldBeStrikesPerMin}/min)` });
    if (!rows.length) { console.log("[GazeMetrics] nothing to summarise yet - run GazeMetrics.runAll()"); return rows; }
    console.log("%c==== GAZE SYSTEM SUMMARY ====", H1);
    console.table(rows);
    // console.table shows "[object Object]" when copied as text, so also print plain lines you can paste
    rows.forEach((r) => console.log(`${r.Metric}: ${r.Result} — ${r.Detail}`));
    return rows;
  };

  // ---- live rolling log ----
  GM.live = (on = true, everyMs = CFG.liveEveryMs) => {
    if (rt.liveTimer) { clearInterval(rt.liveTimer); rt.liveTimer = null; }
    if (!on) return;
    rt.liveTimer = setInterval(() => {
      const f = rt.frames.filter((x) => x.t >= performance.now() - everyMs);
      if (!f.length) return console.log("[GazeMetrics live] no frames");
      const r = analyzeLatency(f, null, null);
      const m = r.modelMetrics;
      console.log(`[GazeMetrics live ${everyMs / 1000}s] ${r.fps} fps · pipeline ${r.pipelineMs.median} ms · FaceMesh tracked ${r.faceDetectedPct}% · YOLO eye conf ${m.eyeModelConfidencePct.mean ?? "-"}% · keypoints ${m.eyeKeypointConfidencePct.mean ?? "-"}% · YOLO age ${m.eyeResultAgeMs.median ?? "-"} ms · features ${r.featuresAvailablePct}% · alert ${r.alertPct}%`);
    }, everyMs);
  };

  // ---- export ----
  GM.csv = () => {
    const cols = ["t", "dt", "pipeMs", "nFaces", "faceOk", "eyeModelConfidence", "eyeKeypointConfidence", "eyeQuality", "detectedEyes", "eyeResultAgeMs", "eyeBoxes", "ear", "closed", "blinkish", "rawOk", "yoloAt", "yoloOk", "ex", "ey", "gx", "gy", "bx", "by", "gazeOk", "awayMs", "warn", "flagged", "flagReason", "alert"];
    return [cols.join(","), ...rt.frames.map((f) => cols.map((k) => (f[k] == null ? "" : k === "eyeBoxes" ? JSON.stringify(f[k]) : typeof f[k] === "number" ? Math.round(f[k] * 1000) / 1000 : f[k])).join(","))].join("\n");
  };
  GM.export = () => ({ when: new Date().toISOString(), viewport: [VW(), VH()], cfg: CFG, models: modelSnapshot(), results: rt.results, strikeEquivalents: rt.strikeEq });
  GM.download = () => {
    const save = (name, text, type) => {
      const a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob([text], { type }));
      a.download = name; document.body.appendChild(a); a.click(); a.remove();
    };
    save("gaze-results.json", JSON.stringify(GM.export(), null, 2), "application/json");
    save("gaze-frames.csv", GM.csv(), "text/csv");
  };

  GM.showYolo = (on = true) => { root.SHOW_YOLO_OVERLAY = !!on; return root.SHOW_YOLO_OVERLAY; };
  GM.stop = () => { rt.abort = true; };
  GM.frames = () => rt.frames;

  GM.help = () => console.log(`GazeMetrics
  runAll()            blink -> fixation -> saccade -> false-positive, then summary()  (stops on Esc)
  runFixation({dots:5, dwellMs:3000})      runSaccade({jumps:10, pattern:'horizontal'|'diagonal'|'mixed'})
  runBlink({cues:10})                       runFalsePositive({phaseMs:10000})
  setGate(true|false)  click/Space-to-start before every test (now: ${CFG.gate ? "ON" : "OFF"}); a single run can override with { gate:false }
  latency(10000)  live(true|false)  models()  summary()  download()  showYolo(true|false)  stop()  (Esc also aborts)

Definitions
  Fixation accuracy  = equal-weight mean of each dot's within-${CFG.tolPx}px rate among frames with a gaze estimate (first ${CFG.settleMs} ms of each dot ignored). Missing estimates are excluded from accuracy and reported separately as coverage; do not treat camera frames as independent trials.
  Blink detection    = cued blinks the system saw / cues. Also: landmarks tracked during blinks, YOLO result during blinks, gaze shift and recovery time.
  Saccade detection  = dot jumps where the gaze moved >= ${CFG.sacc.minAmpPx}px within ${CFG.sacc.winMs}ms toward the new dot / jumps. Latency includes human reaction time.
  Response latency   = per-frame pipeline time (camera frame -> MediaPipe result -> gaze estimate) + YOLO inference time + frame rate.
  False-positive rate= alert frames / all frames while the student looks at the exam area (3 x 10 s: fixation, saccades, camera moving).`);

  root.GazeMetrics = GM;
  if (typeof module !== "undefined" && module.exports) {
    module.exports = { analyzeFixation, analyzeSaccades, analyzeBlink, analyzeFP, analyzeLatency, labelFixations, burstFlags, countBursts, blinkEvents, stats };
  }

  if (typeof document !== "undefined") {
    if (install()) console.log("[GazeMetrics] ready - GazeMetrics.help()");
    else console.warn("[GazeMetrics] window.onResults not found: load gaze-metrics.js AFTER exam-gaze-block.js");
  }
})(typeof window !== "undefined" ? window : globalThis);