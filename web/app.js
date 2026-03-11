import { LTEncoder, LTDecoder, BLOCK_SIZE } from './lt.js?v=6';

const VERSION = 2;
const FRAME_HEADER_BYTES = 25; // 1 + 4 + 4 + 4 + 4 + 8
const CRC_BYTES = 4;
const PAYLOAD_PREFIX = 'SS2:'; // marker to avoid accidental scans
const TARGET_OVERHEAD = 1.1; // aim for ~110% symbols for reliability

// ---------- Utility ----------
const crcTable = (() => {
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let j = 0; j < 8; j++) {
      c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[i] = c >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    c = crcTable[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function bytesToBase64(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

function base64ToBytes(str) {
  const bin = atob(str);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function randomUint32() {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return arr[0] >>> 0;
}

function formatBytes(num) {
  if (num < 1024) return `${num} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let n = num / 1024;
  let u = 0;
  while (n >= 1024 && u < units.length - 1) {
    n /= 1024;
    u += 1;
  }
  const decimals = n >= 10 ? 0 : 1;
  return `${n.toFixed(decimals)} ${units[u]}`;
}

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

// ---------- DOM refs ----------
const txFile = document.getElementById('tx-file');
const txStartBtn = document.getElementById('tx-start');
const txStopBtn = document.getElementById('tx-stop');
const txFps = document.getElementById('tx-fps');
const txFpsValue = document.getElementById('tx-fps-value');
const txStatus = document.getElementById('tx-status');
const txCanvas = document.getElementById('tx-canvas');

const rxStartBtn = document.getElementById('rx-start');
const rxStopBtn = document.getElementById('rx-stop');
const rxResetBtn = document.getElementById('rx-reset');
const rxStatus = document.getElementById('rx-status');
const rxVideo = document.getElementById('rx-video');
const rxCanvas = document.getElementById('rx-canvas');
const rxDownload = document.getElementById('rx-download');
const rxLog = document.getElementById('rx-log');

// Decoder setup: prefer jsQR (bundled locally); if missing, try BarcodeDetector.
const jsqr = window.jsQR || null;
let barcodeDetector = null;
if ('BarcodeDetector' in window) {
  try {
    barcodeDetector = new BarcodeDetector({ formats: ['qr_code'] });
  } catch (e) {
    barcodeDetector = null;
  }
}

// ---------- Transmit state ----------
const txState = {
  encoder: null,
  fileSize: 0,
  sessionId: null,
  symbolId: 0,
  timer: null,
  running: false,
  sent: 0,
  target: 0,
};

// ---------- Receive state ----------
const rxState = {
  stream: null,
  scanning: false,
  sessionId: null,
  fileSize: 0,
  decoder: null,
  seenSeeds: new Set(),
  fpsStart: 0,
  frames: 0,
  lastFrameTs: 0,
  lastStatusTs: 0,
  reconstructedUrl: null,
};

// ---------- Transmit ----------
function updateTxStatus(extra = '') {
  if (!txState.encoder) {
    txStatus.textContent = 'Idle';
    return;
  }
  const percent = txState.target
    ? Math.min(100, Math.floor((txState.sent / txState.target) * 100))
    : 0;
  const remaining = txState.target ? Math.max(0, txState.target - txState.sent) : 0;
  txStatus.textContent = `Session ${txState.sessionId} | Planned symbols: ~${txState.target} | Sent: ${txState.sent} (${percent}%) | Remaining: ${remaining} | Blocks: ${txState.encoder.K} | File: ${formatBytes(txState.fileSize)} ${extra}`;
}

function buildFrame(symbolData, { sessionId, symbolId, degree, seed, fileSize }) {
  const header = new ArrayBuffer(FRAME_HEADER_BYTES + symbolData.length + CRC_BYTES);
  const bytes = new Uint8Array(header);
  const view = new DataView(header);

  view.setUint8(0, VERSION);
  view.setUint32(1, sessionId);
  view.setUint32(5, symbolId);
  view.setUint32(9, degree);
  view.setUint32(13, seed);
  view.setBigUint64(17, BigInt(fileSize));

  bytes.set(symbolData, FRAME_HEADER_BYTES);

  const crc = crc32(bytes.subarray(0, bytes.length - CRC_BYTES));
  view.setUint32(bytes.length - CRC_BYTES, crc);
  return bytes;
}

async function drawQr(canvas, payload) {
  // Try default (M). If it overflows, fall back to version 40 + level L.
  const optsPrimary = { width: canvas.width, margin: 2, errorCorrectionLevel: 'M' };
  const optsFallback = { width: canvas.width, margin: 2, errorCorrectionLevel: 'L', version: 40 };

  const render = (opts) =>
    new Promise((resolve, reject) => {
      QRCode.toCanvas(canvas, payload, opts, (err) => (err ? reject(err) : resolve()));
    });

  try {
    await render(optsPrimary);
  } catch (err) {
    // Retry with looser constraints
    try {
      await render(optsFallback);
      console.warn('QR render recovered with fallback (L, v40):', err?.message || err);
    } catch (err2) {
      throw err2;
    }
  }
}

async function txTick() {
  if (!txState.running || !txState.encoder) return;

  const seed = randomUint32();
  const { degree, data } = txState.encoder.generateSymbol(seed);
  const frame = buildFrame(data, {
    sessionId: txState.sessionId,
    symbolId: txState.symbolId,
    degree,
    seed,
    fileSize: txState.fileSize,
  });
  const payload = PAYLOAD_PREFIX + bytesToBase64(frame);

  try {
    await drawQr(txCanvas, payload);
    txState.sent += 1;
    txState.symbolId = (txState.symbolId + 1) >>> 0;
    if (txState.sent >= txState.target) {
      stopTransmit();
      updateTxStatus(' (complete)');
      return;
    }
    updateTxStatus();
  } catch (err) {
    console.error('QR render failed', err);
    const detail = err?.message || String(err);
    updateTxStatus(` (QR render failed; retrying: ${detail})`);
  }

  const fps = clamp(parseInt(txFps.value, 10) || 10, 1, 60);
  const delay = 1000 / fps;
  txState.timer = setTimeout(txTick, delay);
}

async function startTransmit() {
  const file = txFile.files?.[0];
  if (!file) {
    alert('Choose a file to transmit.');
    return;
  }

  const buf = new Uint8Array(await file.arrayBuffer());
  txState.encoder = new LTEncoder(buf, BLOCK_SIZE);
  txState.fileSize = buf.length;
  txState.sessionId = randomUint32();
  txState.symbolId = 0;
  txState.sent = 0;
  txState.target = Math.ceil(txState.encoder.K * TARGET_OVERHEAD);
  txState.running = true;
  txCanvas.width = txCanvas.height = 512;
  updateTxStatus();
  txStartBtn.disabled = true;
  txStopBtn.disabled = false;
  txTick();
}

function stopTransmit() {
  txState.running = false;
  if (txState.timer) {
    clearTimeout(txState.timer);
    txState.timer = null;
  }
  txStartBtn.disabled = false;
  txStopBtn.disabled = true;
  updateTxStatus(' (stopped)');
}

// ---------- Receive ----------
function resetRxSession() {
  rxState.sessionId = null;
  rxState.fileSize = 0;
  rxState.decoder = null;
  rxState.seenSeeds.clear();
  rxState.frames = 0;
  rxState.fpsStart = performance.now();
  rxState.lastStatusTs = performance.now();
  rxDownload.hidden = true;
  rxDownload.removeAttribute('href');
  rxDownload.removeAttribute('download');
  if (rxState.reconstructedUrl) {
    URL.revokeObjectURL(rxState.reconstructedUrl);
    rxState.reconstructedUrl = null;
  }
  rxStatus.textContent = '';
}

function stopReceive() {
  rxState.scanning = false;
  if (rxState.stream) {
    for (const track of rxState.stream.getTracks()) track.stop();
    rxState.stream = null;
  }
  rxStartBtn.disabled = false;
  rxStopBtn.disabled = true;
  rxResetBtn.disabled = false;
}

async function startReceive() {
  try {
    rxState.stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'environment' },
      audio: false,
    });
  } catch (err) {
    alert('Camera access failed: ' + err.message);
    return;
  }
  rxVideo.srcObject = rxState.stream;
  await rxVideo.play();
  rxState.scanning = true;
  rxState.fpsStart = performance.now();
  rxState.frames = 0;
  rxState.lastStatusTs = performance.now();
  rxStartBtn.disabled = true;
  rxStopBtn.disabled = false;
  rxResetBtn.disabled = true;
  resetRxSession();
  rxStatus.textContent = 'Camera on - scanning for QR frames...';
  requestAnimationFrame(scanLoop);
}

function parseFrameString(str) {
  if (!str.startsWith(PAYLOAD_PREFIX)) return null;
  const b64 = str.slice(PAYLOAD_PREFIX.length);
  let bytes;
  try {
    bytes = base64ToBytes(b64);
  } catch (err) {
    return null;
  }
  if (bytes.length < FRAME_HEADER_BYTES + CRC_BYTES) return null;

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const crcRead = view.getUint32(bytes.length - CRC_BYTES);
  const crcCalc = crc32(bytes.subarray(0, bytes.length - CRC_BYTES));
  if (crcRead !== crcCalc) return null;

  const version = view.getUint8(0);
  if (version !== VERSION) return null;

  const sessionId = view.getUint32(1);
  const symbolId = view.getUint32(5);
  const degree = view.getUint32(9);
  const seed = view.getUint32(13);
  const fileSize = Number(view.getBigUint64(17));
  const payload = bytes.subarray(FRAME_HEADER_BYTES, bytes.length - CRC_BYTES);

  return { sessionId, symbolId, degree, seed, fileSize, payload };
}

function ensureDecoder(sessionId, fileSize) {
  if (rxState.sessionId === sessionId && rxState.decoder) return;
  const K = Math.ceil(fileSize / BLOCK_SIZE);
  rxState.sessionId = sessionId;
  rxState.fileSize = fileSize;
  rxState.decoder = new LTDecoder(K, BLOCK_SIZE);
  rxState.seenSeeds.clear();
  rxLog.textContent = '';
}

function handleDecodedPayload(str) {
  const parsed = parseFrameString(str);
  if (!parsed) return false;

  ensureDecoder(parsed.sessionId, parsed.fileSize);

  if (rxState.seenSeeds.has(parsed.seed)) return true; // already processed
  rxState.seenSeeds.add(parsed.seed);

  rxState.decoder.addSymbol(parsed.seed, parsed.payload);

  const progress = rxState.decoder ? rxState.decoder.numRecovered : 0;
  const done = rxState.decoder && rxState.decoder.isDone();
  const percent = rxState.decoder
    ? Math.min(100, Math.floor((progress / rxState.decoder.K) * 100))
    : 0;
  rxStatus.textContent = `Session ${parsed.sessionId} | Recovered blocks: ${progress}/${rxState.decoder.K} (${percent}%) | Seeds seen: ${rxState.seenSeeds.size} | File: ${formatBytes(rxState.fileSize)}`;

  if (done) {
    const reconstructed = rxState.decoder.reconstruct();
    const trimmed = reconstructed.slice(0, rxState.fileSize);
    const blob = new Blob([trimmed]);
    const url = URL.createObjectURL(blob);
    rxState.reconstructedUrl = url;
    const filename = `smokesignal-${parsed.sessionId}.bin`;
    rxDownload.href = url;
    rxDownload.download = filename;
    rxDownload.hidden = false;
    rxStatus.textContent += ' | Complete';
    stopReceive();
  }
  return true;
}

function scanLoop() {
  if (!rxState.scanning) return;
  if (rxVideo.readyState >= HTMLMediaElement.HAVE_ENOUGH_DATA) {
    const w = rxVideo.videoWidth;
    const h = rxVideo.videoHeight;
    rxCanvas.width = w;
    rxCanvas.height = h;
    const ctx = rxCanvas.getContext('2d');
    ctx.drawImage(rxVideo, 0, 0, w, h);
    const imageData = ctx.getImageData(0, 0, w, h);
    rxState.frames += 1;
    const now = performance.now();
    if ((!rxState.decoder || rxState.decoder.numRecovered === 0) && now - rxState.lastStatusTs > 750) {
      rxStatus.textContent = 'Camera on - scanning (no QR detected yet)...';
      rxState.lastStatusTs = now;
    }

    let decoded = null;
    if (typeof jsqr === 'function') {
      const code = jsqr(imageData.data, w, h, { inversionAttempts: 'attemptBoth' });
      if (code && code.data) decoded = code.data;
    } else if (barcodeDetector) {
      barcodeDetector
        .detect(rxVideo)
        .then((results) => {
          if (results && results.length && results[0].rawValue) {
            handleDecodedPayload(results[0].rawValue);
          }
        })
        .catch(() => {});
    } else {
      rxStatus.textContent = 'Decoder unavailable (jsQR not loaded; no BarcodeDetector support).';
      stopReceive();
      return;
    }

    if (decoded) {
      handleDecodedPayload(decoded);
    }
  }
  requestAnimationFrame(scanLoop);
}

// ---------- Wire up ----------
txFps.addEventListener('input', () => {
  txFpsValue.textContent = `${txFps.value} fps`;
});

txStartBtn.addEventListener('click', startTransmit);
txStopBtn.addEventListener('click', stopTransmit);

rxStartBtn.addEventListener('click', startReceive);
rxStopBtn.addEventListener('click', stopReceive);
rxResetBtn.addEventListener('click', resetRxSession);

window.addEventListener('beforeunload', () => {
  stopTransmit();
  stopReceive();
});

resetRxSession();
updateTxStatus();
