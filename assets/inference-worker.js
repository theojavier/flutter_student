// inference-worker.js
importScripts('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.22.0/dist/tf.min.js');
importScripts('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs-backend-wasm@4.22.0/dist/tf-backend-wasm.js');
importScripts('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs-tflite/dist/tf-tflite.min.js');

let faceModel = null;
let eyeModel = null;
const MODEL_FACE_INPUT_SIZE = 448;
const MODEL_EYE_INPUT_SIZE = 864;
const CONF_THRESHOLD = 0.20;
const KPT_CONF_THRESHOLD = 0.20;
const NUM_EYE_KPTS = 18;
const NUM_FACE_KPTS = 7;
const NUM_KPTS = NUM_EYE_KPTS + NUM_FACE_KPTS;

async function loadModels() {
  if (tf.wasm && typeof tf.wasm.setWasmPaths === 'function') {
    tf.wasm.setWasmPaths('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs-backend-wasm@4.22.0/dist/');
  }
  await tf.setBackend('wasm');
  await tf.ready();
  if (typeof tflite === 'undefined') {
    throw new Error('TensorFlow Lite library failed to load in worker');
  }
  const baseUrl = new URL('.', self.location).href;
  faceModel = await tflite.loadTFLiteModel(new URL('./facekeypoint420/best_float16.tflite', baseUrl).href);
  eyeModel = await tflite.loadTFLiteModel(new URL('./eyekeypoint840/best_float16.tflite', baseUrl).href);
  postMessage({ type: 'modelsLoaded' });
}

function preprocessFrame(canvas, size) {
  return tf.tidy(() => {
    const img = tf.browser.fromPixels(canvas).toFloat().div(255.0);
    const scale = Math.min(size / canvas.width, size / canvas.height);
    const newW = Math.round(canvas.width * scale);
    const newH = Math.round(canvas.height * scale);
    const resized = tf.image.resizeBilinear(img, [newH, newW]);
    const padLeft = Math.floor((size - newW) / 2);
    const padRight = size - newW - padLeft;
    const padTop = Math.floor((size - newH) / 2);
    const padBottom = size - newH - padTop;
    const padded = tf.pad(resized, [[padTop, padBottom], [padLeft, padRight], [0, 0]], 0.45);
    return {
      tensor: padded.expandDims(0),
      scale,
      padX: padLeft,
      padY: padTop
    };
  });
}

function parseKeypointModelOutput(output, inputSize, scale, padX, padY, numKpts) {
  const tensor = output;
  if (!tensor) return null;
  const reader = {
    shape: tensor.shape,
    get: (i, j) => tensor.dataSync()[i * tensor.shape[1] + j]
  };
  const needed = 4 + 1 + numKpts * 3;
  if (reader.shape[1] < needed) return null;
  const detections = [];
  for (let i = 0; i < reader.shape[0]; i++) {
    const x = reader.get(i, 0);
    const y = reader.get(i, 1);
    const w = reader.get(i, 2);
    const h = reader.get(i, 3);
    const score = reader.get(i, 4);
    if (score < CONF_THRESHOLD) continue;
    const kpts = [];
    for (let j = 0; j < numKpts; j++) {
      const kx = reader.get(i, 5 + j * 3 + 0);
      const ky = reader.get(i, 5 + j * 3 + 1);
      const kv = reader.get(i, 5 + j * 3 + 2);
      const origX = (kx - padX) / scale;
      const origY = (ky - padY) / scale;
      kpts.push([origX, origY, kv]);
    }
    detections.push({ score, bbox: [x, y, w, h], kpts });
  }
  detections.sort((a, b) => b.score - a.score);
  return detections.length ? detections[0] : null;
}

onmessage = async function(e) {
  try {
    if (e.data.type === 'loadModels') {
      await loadModels();
    } else if (e.data.type === 'predict') {
      const { canvasData, refreshFace, refreshEye } = e.data;
      const canvas = new OffscreenCanvas(canvasData.width, canvasData.height);
      const ctx = canvas.getContext('2d');
      const uint8Array = new Uint8ClampedArray(canvasData.data);
      const imageData = new ImageData(uint8Array, canvasData.width, canvasData.height);
      ctx.putImageData(imageData, 0, 0);

      let bestFace = null;
      let bestEye = null;

      if (refreshFace) {
        const faceFrame = preprocessFrame(canvas, MODEL_FACE_INPUT_SIZE);
        const faceOutput = faceModel.predict(faceFrame.tensor);
        bestFace = parseKeypointModelOutput(faceOutput, MODEL_FACE_INPUT_SIZE, faceFrame.scale, faceFrame.padX, faceFrame.padY, NUM_FACE_KPTS);
        tf.dispose(faceFrame.tensor);
        tf.dispose(faceOutput);
      }

      if (refreshEye) {
        const eyeFrame = preprocessFrame(canvas, MODEL_EYE_INPUT_SIZE);
        const eyeOutput = eyeModel.predict(eyeFrame.tensor);
        bestEye = parseKeypointModelOutput(eyeOutput, MODEL_EYE_INPUT_SIZE, eyeFrame.scale, eyeFrame.padX, eyeFrame.padY, NUM_EYE_KPTS);
        tf.dispose(eyeFrame.tensor);
        tf.dispose(eyeOutput);
      }

      postMessage({ type: 'prediction', bestFace, bestEye });
    }
  } catch (error) {
    postMessage({ type: 'workerError', message: error.message, stack: error.stack });
  }
};