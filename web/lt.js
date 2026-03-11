// Lightweight fountain encoder/decoder + deterministic PRNG (XorShift32)
// Mirrors the Swift SmokeSignalCore logic so sessions stay stable across JS/Swift.

// Keep frames small so they fit comfortably in QR version <= 10 with EC level M.
export const BLOCK_SIZE = 96; // bytes per symbol payload

class XorShift32 {
  constructor(seed) {
    // xorshift32 gets stuck at 0, so seed with a non-zero constant if needed
    this.state = seed === 0 ? 0xA341316C : seed >>> 0;
  }

  nextUInt32() {
    let x = this.state >>> 0;
    x ^= (x << 13) >>> 0;
    x ^= (x >>> 17) >>> 0;
    x ^= (x << 5) >>> 0;
    this.state = x >>> 0;
    return this.state;
  }

  nextDouble01() {
    return this.nextUInt32() / 4294967296; // 2^32
  }

  nextInt(upperBound) {
    if (upperBound <= 0) throw new Error('upperBound must be > 0');
    const bound = BigInt(upperBound);
    const threshold = (1n << 32n) % bound;
    while (true) {
      const r = BigInt(this.nextUInt32());
      const m = r * bound;
      const low = m & 0xffffffffn;
      if (low >= threshold) {
        return Number(m >> 32n);
      }
    }
  }
}

function robustSolitonDistribution(K, c = 0.1, delta = 0.5) {
  if (K === 0) return [1.0];
  if (K === 1) return [0.0, 1.0];

  const rho = new Array(K + 1).fill(0);
  rho[1] = 1 / K;
  for (let d = 2; d <= K; d++) {
    rho[d] = 1 / (d * (d - 1));
  }

  const R = c * Math.log(K / delta) * Math.sqrt(K);
  const tau = new Array(K + 1).fill(0);
  if (R > 0) {
    const limit = Math.min(K, Math.max(1, Math.round(K / R)));
    for (let d = 1; d < limit; d++) {
      tau[d] = R / (d * K);
    }
    tau[limit] = (R * Math.log(R / delta)) / K;
  }

  const mu = new Array(K + 1);
  for (let d = 0; d <= K; d++) mu[d] = rho[d] + tau[d];
  const beta = mu.reduce((a, b) => a + b, 0);
  return mu.map((m) => m / beta);
}

function cdfFromDistribution(mu) {
  // mu[0] unused; degrees are 1..K
  if (mu.length <= 2) return [1.0];
  const K = mu.length - 1;
  const cdf = [];
  let acc = 0;
  for (let d = 1; d <= K; d++) {
    acc += mu[d];
    cdf.push(acc);
  }
  cdf[cdf.length - 1] = 1.0;
  return cdf;
}

function sampleDegree(cdf, prng) {
  const r = prng.nextDouble01();
  let low = 0;
  let high = cdf.length - 1;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (r < cdf[mid]) high = mid;
    else low = mid + 1;
  }
  return low + 1;
}

function sampleUniqueIndices(count, upperBound, prng) {
  if (count <= 0 || upperBound <= 0) return [];
  if (count >= upperBound) return [...Array(upperBound).keys()];
  const chosen = new Set();
  while (chosen.size < count) {
    chosen.add(prng.nextInt(upperBound));
  }
  return Array.from(chosen);
}

function xorInto(target, other) {
  for (let i = 0; i < target.length; i++) {
    target[i] ^= other[i];
  }
}

export class LTEncoder {
  constructor(data, blockSize = BLOCK_SIZE, c = 0.1, delta = 0.5) {
    if (!(data instanceof Uint8Array)) throw new Error('data must be Uint8Array');
    if (blockSize <= 0) throw new Error('blockSize must be > 0');
    this.blockSize = blockSize;
    this.K = Math.ceil(data.length / blockSize);
    this.blocks = [];
    for (let i = 0; i < this.K; i++) {
      const start = i * blockSize;
      const end = Math.min(start + blockSize, data.length);
      const chunk = new Uint8Array(blockSize);
      chunk.set(data.subarray(start, end));
      this.blocks.push(chunk);
    }
    const mu = robustSolitonDistribution(this.K, c, delta);
    this.degreeCDF = cdfFromDistribution(mu);
  }

  generateSymbol(seed) {
    if (this.K === 0) return { degree: 0, data: new Uint8Array() };
    const prng = new XorShift32(seed >>> 0);
    const degree = sampleDegree(this.degreeCDF, prng);
    const indices = sampleUniqueIndices(degree, this.K, prng);
    const bytes = new Uint8Array(this.blocks[indices[0]]);
    for (let i = 1; i < indices.length; i++) {
      xorInto(bytes, this.blocks[indices[i]]);
    }
    return { degree, data: bytes };
  }
}

export class LTDecoder {
  constructor(K, blockSize = BLOCK_SIZE, c = 0.1, delta = 0.5) {
    if (K < 0) throw new Error('K must be >= 0');
    if (blockSize <= 0) throw new Error('blockSize must be > 0');
    this.K = K;
    this.blockSize = blockSize;
    this.blocks = new Array(K).fill(null);
    this.symbols = [];
    this.recoveredQueue = [];
    this.queueCursor = 0;
    const mu = robustSolitonDistribution(K, c, delta);
    this.degreeCDF = cdfFromDistribution(mu);
    this.numRecovered = K === 0 ? 0 : 0;
  }

  isDone() {
    return this.numRecovered === this.K;
  }

  addSymbol(seed, symbolData) {
    if (this.isDone() || this.K === 0) return;
    if (!(symbolData instanceof Uint8Array)) return;
    if (symbolData.length !== this.blockSize) return;

    const prng = new XorShift32(seed >>> 0);
    const degree = sampleDegree(this.degreeCDF, prng);
    const indicesArr = sampleUniqueIndices(degree, this.K, prng);
    const indices = new Set(indicesArr);

    let reduced = new Uint8Array(symbolData);
    if (indices.size) {
      const toRemove = [];
      for (const idx of indices) {
        const block = this.blocks[idx];
        if (block) {
          xorInto(reduced, block);
          toRemove.push(idx);
        }
      }
      for (const idx of toRemove) indices.delete(idx);
    }

    if (indices.size === 0) return;

    if (indices.size === 1) {
      const [idx] = indices;
      if (!this.blocks[idx]) {
        this.recoveredQueue.push({ index: idx, data: reduced });
        this._propagate();
      }
      return;
    }

    for (const sym of this.symbols) {
      if (sym.indices.size === indices.size) {
        let same = true;
        for (const v of sym.indices) {
          if (!indices.has(v)) {
            same = false;
            break;
          }
        }
        if (same) return;
      }
    }
    this.symbols.push({ indices, data: reduced });
  }

  _propagate() {
    while (this.queueCursor < this.recoveredQueue.length) {
      const { index, data } = this.recoveredQueue[this.queueCursor++];
      if (this.blocks[index]) continue;
      this.blocks[index] = data;
      this.numRecovered += 1;
      if (this.isDone()) return;

      const newSymbols = [];
      for (const sym of this.symbols) {
        if (sym.indices.has(index)) {
          sym.indices.delete(index);
          xorInto(sym.data, data);
          if (sym.indices.size === 1) {
            const [idx] = sym.indices;
            if (!this.blocks[idx]) this.recoveredQueue.push({ index: idx, data: sym.data });
          } else if (sym.indices.size > 1) {
            newSymbols.push(sym);
          }
        } else {
          newSymbols.push(sym);
        }
      }
      this.symbols = newSymbols;
    }
  }

  reconstruct() {
    if (!this.isDone()) return null;
    const out = new Uint8Array(this.K * this.blockSize);
    for (let i = 0; i < this.K; i++) {
      out.set(this.blocks[i], i * this.blockSize);
    }
    return out;
  }
}
