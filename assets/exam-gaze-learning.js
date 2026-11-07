// exam-gaze-learning.js — Progressive learning from exam fixations
// Load after gaze-core.js and before exam-gaze-block.js.
// 
// This module learns from three types of fixations:
// 1. Logo area (top-left of exam card) - 2s+ dwelling
// 2. Question/answer text - stable gaze during reading
// 3. Submit/Next button - pre-click gaze position
//
// Samples are batched and sent to Firebase every 5 samples or when exam ends.
// The model rebuild happens client-side using GazeCore.createOnline.

if (typeof GazeCore === 'undefined') {
  throw new Error('exam-gaze-learning.js requires gaze-core.js to be loaded first');
}

const ExamGazeLearning = (() => {
  const DEBUG = false; // Set to true for detailed logging

  // Configuration
  const cfg = {
    enabled: true, // Can be disabled if needed
    logoEnabled: true,
    textEnabled: false, // DISABLED - was causing lag with DOM queries every 300ms
    buttonEnabled: false, // DISABLED - was causing lag
    
    // Logo learning
    logoDwellMs: 2000, // How long to look at logo to trigger learning
    logoCheckInterval: 200, // Check logo fixation every 200ms
    logoMaxSamplesPerExam: 3, // Maximum logo samples per exam
    
    // Text learning (DISABLED)
    textDwellMs: 1500, // Stable gaze on text
    textCheckInterval: 300,
    textMaxSamplesPerExam: 5,
    
    // Button learning (DISABLED)
    buttonPreClickMs: 400, // Gaze position 400ms before click
    buttonMaxSamplesPerExam: 10,
    
    // Validation
    maxSpreadPx: 120, // Maximum pixel spread for stable fixation
    minFrames: 4, // Minimum frames to average
    gatePx: 350, // Reject samples too far from model prediction
    
    // Batch upload
    batchSize: 5, // Upload every 5 samples
    uploadTimeoutMs: 30000, // Also upload every 30 seconds
  };

  // State
  const state = {
    platform: null, // 'pc' or 'mobile'
    examId: null,
    online: null, // GazeCore.createOnline instance
    persistedSamplesPromise: null,
    samples: [], // Accumulated samples for upload
    uploaded: 0,
    rejected: 0,
    
    // Logo tracking
    logoSamples: 0,
    logoFixationStart: null,
    logoBuffer: [],
    
    // Text tracking
    textSamples: 0,
    textFixationStart: null,
    textBuffer: [],
    textZones: [], // Bounding boxes for question/answer text
    
    // Button tracking
    buttonSamples: 0,
    buttonBuffer: [],
    lastButtonClick: null,
    
    lastUpload: 0,
  };

  // ============================================================================
  // Platform Detection
  // ============================================================================
  
  function detectPlatform() {
    const queryPlatform = new URLSearchParams(location.search).get('platform');
    if (queryPlatform === 'pc' || queryPlatform === 'mobile') return queryPlatform;
    const ua = navigator.userAgent || '';
    const platform = navigator.userAgentData?.platform || navigator.platform || '';
    const mobileDevice =
      navigator.userAgentData?.mobile === true ||
      /Android|iPhone|iPad|iPod|IEMobile|Windows Phone/i.test(ua) ||
      (/MacIntel/i.test(platform) && navigator.maxTouchPoints > 1);
    if (mobileDevice) return 'mobile';
    const desktopDevice =
      /Windows NT|Macintosh|X11|CrOS|Linux x86_64/i.test(ua) ||
      /Win32|Win64|Windows|MacIntel|Linux x86_64/i.test(platform);
    if (desktopDevice) return 'pc';
    return matchMedia('(pointer: coarse)').matches ? 'mobile' : 'pc';
  }

  // ============================================================================
  // Zone Detection
  // ============================================================================
  
  function getLogoZone() {
    // Logo is in the exam card header, top-left area
    // During GATE: This looks for the recording icon area
    // During EXAM: No logo exists, so this returns null
    
    // Only check during gate phase
    if (window.examStarted) {
      return null; // No logo during exam, stop checking
    }
    
    const examCard = document.getElementById('examCard');
    if (!examCard || examCard.style.display === 'none') return null;
    
    const rect = examCard.getBoundingClientRect();
    // Logo typically in top-left corner, about 80x80px
    return {
      left: rect.left + 20,
      top: rect.top + 20,
      right: rect.left + 100,
      bottom: rect.top + 100,
      centerX: rect.left + 60,
      centerY: rect.top + 60,
    };
  }

  function updateTextZones() {
    state.textZones = [];
    
    // Get question text
    const questionEl = document.querySelector('#examContent .question');
    if (questionEl) {
      const rect = questionEl.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) {
        state.textZones.push({
          type: 'question',
          ...rect.toJSON(),
          centerX: rect.left + rect.width / 2,
          centerY: rect.top + rect.height / 2,
        });
      }
    }
    
    // Get answer options
    const answers = document.querySelectorAll('#examContent .answer-option');
    answers.forEach((el, idx) => {
      const rect = el.getBoundingClientRect();
      if (rect.width > 0 && rect.height > 0) {
        state.textZones.push({
          type: 'answer',
          index: idx,
          ...rect.toJSON(),
          centerX: rect.left + rect.width / 2,
          centerY: rect.top + rect.height / 2,
        });
      }
    });
  }

  function getButtonZone() {
    const btn = document.getElementById('nextQuestion');
    if (!btn || btn.offsetParent === null) return null;
    
    const rect = btn.getBoundingClientRect();
    return {
      ...rect.toJSON(),
      centerX: rect.left + rect.width / 2,
      centerY: rect.top + rect.height / 2,
    };
  }

  function isInZone(x, y, zone) {
    return x >= zone.left && x <= zone.right && y >= zone.top && y <= zone.bottom;
  }

  function findTextZone(x, y) {
    return state.textZones.find(zone => isInZone(x, y, zone));
  }

  // ============================================================================
  // Sample Validation
  // ============================================================================
  
  const med = GazeCore.med;

  function getCallable(name) {
    if (window.httpsCallable && window.functions) {
      return window.httpsCallable(window.functions, name);
    }
    if (typeof firebase !== 'undefined' && firebase.functions) {
      return firebase.functions().httpsCallable(name);
    }
    throw new Error('Firebase Functions is not available for gaze learning');
  }

  function validateStableFixation(frames, targetX, targetY) {
    if (frames.length < cfg.minFrames) {
      if (DEBUG) console.log('[learning] Too few frames:', frames.length);
      return { valid: false, reason: 'too-few-frames' };
    }

    // Predict each recorded frame so spread reflects actual gaze stability.
    const model = state.online.getModel();
    const predGaze = frames.map(frame => GazeCore.predict(model, frame.f));
    if (predGaze.some(p => !p || !Number.isFinite(p.x) || !Number.isFinite(p.y))) {
      return { valid: false, reason: 'invalid-prediction' };
    }
    const px = predGaze.map(p => p.x * innerWidth);
    const py = predGaze.map(p => p.y * innerHeight);

    // Check spread
    const spreadX = Math.max(...px) - Math.min(...px);
    const spreadY = Math.max(...py) - Math.min(...py);
    
    if (spreadX > cfg.maxSpreadPx || spreadY > cfg.maxSpreadPx) {
      if (DEBUG) console.log('[learning] Unstable fixation:', { spreadX, spreadY });
      return { valid: false, reason: 'unstable' };
    }

    // Check distance from target
    const medX = med(px);
    const medY = med(py);
    const dist = Math.hypot(medX - targetX, medY - targetY);
    
    if (dist > cfg.gatePx) {
      if (DEBUG) console.log('[learning] Too far from target:', { dist, target: [targetX, targetY], predicted: [medX, medY] });
      return { valid: false, reason: 'outlier' };
    }

    return { valid: true };
  }

  // ============================================================================
  // Logo Learning
  // ============================================================================
  
  function checkLogoFixation() {
    if (!cfg.logoEnabled || state.logoSamples >= cfg.logoMaxSamplesPerExam) return;
    
    // Stop checking once exam starts (no logo in exam card)
    if (window.examStarted) {
      if (logoTimer) {
        clearInterval(logoTimer);
        logoTimer = null;
        if (DEBUG) console.log('[learning] Logo timer stopped - exam started');
      }
      return;
    }
    
    const zone = getLogoZone();
    if (!zone) return;

    const gazeBubble = document.getElementById('gazeBubble');
    if (!gazeBubble) return;

    const bubbleX = parseFloat(gazeBubble.style.left) || 0;
    const bubbleY = parseFloat(gazeBubble.style.top) || 0;

    const inZone = isInZone(bubbleX, bubbleY, zone);

    if (inZone) {
      if (!state.logoFixationStart) {
        state.logoFixationStart = performance.now();
      } else {
        const dwellTime = performance.now() - state.logoFixationStart;
        if (dwellTime >= cfg.logoDwellMs && state.logoBuffer.length >= cfg.minFrames) {
          // Try to create learning sample
          const validation = validateStableFixation(
            state.logoBuffer,
            zone.centerX,
            zone.centerY
          );

          if (validation.valid) {
            addLearningSample(state.logoBuffer, zone.centerX, zone.centerY, 'logo');
            state.logoSamples++;
            if (DEBUG) console.log('[learning] Logo sample added', { total: state.logoSamples });
          } else {
            if (DEBUG) console.log('[learning] Logo sample rejected:', validation.reason);
            state.rejected++;
          }

          // Reset
          state.logoFixationStart = null;
          state.logoBuffer = [];
        }
      }
    } else {
      // Left logo zone
      state.logoFixationStart = null;
      state.logoBuffer = [];
    }
  }

  // ============================================================================
  // Text Learning
  // ============================================================================
  
  function checkTextFixation() {
    if (!cfg.textEnabled || state.textSamples >= cfg.textMaxSamplesPerExam) return;

    const gazeBubble = document.getElementById('gazeBubble');
    if (!gazeBubble) return;

    const bubbleX = parseFloat(gazeBubble.style.left) || 0;
    const bubbleY = parseFloat(gazeBubble.style.top) || 0;

    const zone = findTextZone(bubbleX, bubbleY);

    if (zone) {
      if (!state.textFixationStart) {
        state.textFixationStart = performance.now();
      } else {
        const dwellTime = performance.now() - state.textFixationStart;
        if (dwellTime >= cfg.textDwellMs && state.textBuffer.length >= cfg.minFrames) {
          const validation = validateStableFixation(
            state.textBuffer,
            zone.centerX,
            zone.centerY
          );

          if (validation.valid) {
            addLearningSample(state.textBuffer, zone.centerX, zone.centerY, `text-${zone.type}`);
            state.textSamples++;
            if (DEBUG) console.log('[learning] Text sample added', { type: zone.type, total: state.textSamples });
          } else {
            if (DEBUG) console.log('[learning] Text sample rejected:', validation.reason);
            state.rejected++;
          }

          state.textFixationStart = null;
          state.textBuffer = [];
        }
      }
    } else {
      state.textFixationStart = null;
      state.textBuffer = [];
    }
  }

  // ============================================================================
  // Button Learning
  // ============================================================================
  
  function setupButtonLearning() {
    const btn = document.getElementById('nextQuestion');
    if (!btn) return;

    btn.addEventListener('click', () => {
      if (!cfg.buttonEnabled || state.buttonSamples >= cfg.buttonMaxSamplesPerExam) return;

      const clickTime = performance.now();
      const zone = getButtonZone();
      if (!zone) return;

      // Find frames from cfg.buttonPreClickMs before click
      const relevantFrames = state.buttonBuffer.filter(
        f => clickTime - f.t >= 0 && clickTime - f.t <= cfg.buttonPreClickMs
      );

      if (relevantFrames.length < cfg.minFrames) {
        if (DEBUG) console.log('[learning] Button: too few pre-click frames');
        return;
      }

      const validation = validateStableFixation(
        relevantFrames,
        zone.centerX,
        zone.centerY
      );

      if (validation.valid) {
        addLearningSample(relevantFrames, zone.centerX, zone.centerY, 'button');
        state.buttonSamples++;
        if (DEBUG) console.log('[learning] Button sample added', { total: state.buttonSamples });
      } else {
        if (DEBUG) console.log('[learning] Button sample rejected:', validation.reason);
        state.rejected++;
      }

      state.buttonBuffer = [];
    });
  }

  // ============================================================================
  // Sample Creation
  // ============================================================================
  
  function addLearningSample(frames, targetX, targetY, source) {
    if (!state.online) return;

    // Average features from frames
    const feat = {};
    const keys = ['ox', 'oy', 'yaw', 'pitch', 'roll', 'cx', 'cy', 'scale'];
    
    keys.forEach(k => {
      feat[k] = frames.reduce((sum, f) => sum + f.f[k], 0) / frames.length;
    });

    // Add target position
    feat.sx = targetX / innerWidth;
    feat.sy = targetY / innerHeight;
    feat.spot = -1; // Learning samples marked with -1
    feat.w = 4; // Weight (same as GazeCore online learning)
    feat.source = source;
    feat.timestamp = Date.now();

    // Add to local model
    try {
      const result = state.online.addClick(targetX, targetY, performance.now(), false);
      
      if (result === 'ok') {
        // Add to upload batch
        state.samples.push(feat);
        
        if (DEBUG) console.log('[learning] Sample queued for upload', {
          source,
          target: [targetX.toFixed(0), targetY.toFixed(0)],
          queueSize: state.samples.length,
        });

        // Check if we should upload
        checkUpload();
      } else {
        if (DEBUG) console.log('[learning] Model rejected sample:', result);
        state.rejected++;
      }
    } catch (err) {
      console.error('[learning] Failed to add sample:', err);
    }
  }

  // ============================================================================
  // Firebase Upload
  // ============================================================================
  
  async function checkUpload() {
    const now = Date.now();
    const timeSinceLastUpload = now - state.lastUpload;

    if (
      state.samples.length >= cfg.batchSize ||
      (state.samples.length > 0 && timeSinceLastUpload > cfg.uploadTimeoutMs)
    ) {
      await uploadSamples();
    }
  }

  async function uploadSamples() {
    if (state.samples.length === 0) return;
    if (!state.examId || !state.platform) return;

    const samplesToUpload = [...state.samples];
    state.samples = []; // Clear immediately to prevent duplicates
    state.lastUpload = Date.now();

    try {
      if (DEBUG) console.log('[learning] Uploading batch:', { count: samplesToUpload.length, platform: state.platform });

      // Call Firebase function
      const addGazeLearning = getCallable('addGazeLearning');
      const result = await addGazeLearning({
        platform: state.platform,
        samples: samplesToUpload,
        examId: state.examId,
      });

      state.uploaded += samplesToUpload.length;
      
      if (DEBUG) console.log('[learning] Upload successful', {
        uploaded: samplesToUpload.length,
        total: state.uploaded,
        response: result.data,
      });
    } catch (err) {
      console.error('[learning] Upload failed:', err);
      // Put samples back in queue for retry
      state.samples.unshift(...samplesToUpload);
    }
  }

  // ============================================================================
  // Frame Recording
  // ============================================================================
  
  function recordFrame(features, now) {
    if (!state.online) return;

    const frame = {
      f: { ...features },
      t: now,
    };

    // Add to logo buffer
    state.logoBuffer.push(frame);
    if (state.logoBuffer.length > 20) state.logoBuffer.shift();

    // Add to text buffer
    state.textBuffer.push(frame);
    if (state.textBuffer.length > 20) state.textBuffer.shift();

    // Add to button buffer (keep last 1 second)
    state.buttonBuffer.push(frame);
    const oneSecondAgo = now - 1000;
    state.buttonBuffer = state.buttonBuffer.filter(f => f.t >= oneSecondAgo);
  }

  // ============================================================================
  // Main Loop
  // ============================================================================
  
  let logoTimer = null;
  let textTimer = null;

  function startLearning() {
    if (!cfg.enabled) return;

    // Update text zones when question changes (DISABLED - not needed without text learning)
    // updateTextZones();

    // Logo check timer (ONLY ACTIVE LEARNING)
    if (cfg.logoEnabled && !logoTimer) {
      logoTimer = setInterval(checkLogoFixation, cfg.logoCheckInterval);
    }

    // Text check timer (DISABLED - was causing performance issues)
    // if (cfg.textEnabled && !textTimer) {
    //   textTimer = setInterval(checkTextFixation, cfg.textCheckInterval);
    // }

    // Button learning (DISABLED - was causing performance issues)
    // if (cfg.buttonEnabled) {
    //   setupButtonLearning();
    // }

    console.log('[learning] Started exam gaze learning', {
      platform: state.platform,
      examId: state.examId,
      logo: cfg.logoEnabled,
      text: cfg.textEnabled, // Will show false
      button: cfg.buttonEnabled, // Will show false
    });
  }

  function stopLearning() {
    if (logoTimer) {
      clearInterval(logoTimer);
      logoTimer = null;
    }
    if (textTimer) {
      clearInterval(textTimer);
      textTimer = null;
    }

    // Upload any remaining samples
    if (state.samples.length > 0) {
      uploadSamples().catch(err => console.error('[learning] Final upload failed:', err));
    }

    console.log('[learning] Stopped exam gaze learning', {
      uploaded: state.uploaded,
      rejected: state.rejected,
      remaining: state.samples.length,
    });
  }

  function loadPersistedLearning() {
    if (state.persistedSamplesPromise) return state.persistedSamplesPromise;

    state.persistedSamplesPromise = (async () => {
      if (!state.platform) return [];
      const getCalibration = getCallable('getGazeCalibration');
      const result = await getCalibration({ platform: state.platform });
      const data = result.data || {};
      return data.exists && Array.isArray(data.learningSamples)
        ? data.learningSamples.sort((a, b) =>
          (a.timestamp || a.addedAt || 0) - (b.timestamp || b.addedAt || 0))
        : [];
    })();

    return state.persistedSamplesPromise;
  }

  // ============================================================================
  // Public API
  // ============================================================================
  
  return {
    init(examId, calibrationData, learningSamples) {
      state.examId = examId;
      state.platform = window.examGazePlatform || detectPlatform();
      state.persistedSamplesPromise = Array.isArray(learningSamples)
        ? Promise.resolve(learningSamples)
        : null;
      const persistedSamples = loadPersistedLearning();

      // Create online learning instance
      if (calibrationData) {
        state.online = GazeCore.createOnline(calibrationData, {
          xOnly: false, // Learn both X and Y
          minClicks: 2, // Start refitting after 2 samples
          refitEvery: 2, // Refit every 2 samples
          gatePx: cfg.gatePx,
          maxSpreadPx: cfg.maxSpreadPx,
        });

        if (state.online) {
          console.log('[learning] Online learning initialized', {
            platform: state.platform,
            examId,
          });
        } else {
          console.warn('[learning] Failed to create online learning instance');
        }
      }

      if (state.online) {
        persistedSamples.then(samples => {
          if (samples.length) {
            const currentClicks = state.online.exportClicks();
            const imported = state.online.importClicks([...samples, ...currentClicks]);
            if (!imported) {
              console.warn('[learning] Persisted gaze samples failed validation');
            } else {
              console.log('[learning] Restored persisted gaze samples', { imported });
            }
          }
        }).catch(err => {
          console.warn('[learning] Could not restore persisted gaze samples:', err);
        });
      }
    },

    loadPersistedLearning,

    start() {
      if (state.online) {
        startLearning();
      }
    },

    stop() {
      stopLearning();
    },

    recordFrame(features, now) {
      recordFrame(features, now);
      // Also push to online learning buffer
      if (state.online) {
        state.online.push(features, now);
      }
    },

    onQuestionChange() {
      // Update text zones when question changes (DISABLED - text learning disabled)
      // updateTextZones();
      
      // Reset text fixation state (DISABLED - text learning disabled)
      // state.textFixationStart = null;
      // state.textBuffer = [];
    },

    getStats() {
      return {
        uploaded: state.uploaded,
        rejected: state.rejected,
        queued: state.samples.length,
        logo: state.logoSamples,
        text: state.textSamples,
        button: state.buttonSamples,
      };
    },

    configure(options) {
      Object.assign(cfg, options);
    },
  };
})();
