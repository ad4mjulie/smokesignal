import Foundation

func robustSolitonDistribution(K: Int, c: Double = 0.1, delta: Double = 0.5) -> [Double] {
    precondition(K >= 0)
    if K == 0 {
        return [1.0]
    }
    if K == 1 {
        // Index 0 unused, degree 1 has full weight.
        return [0.0, 1.0]
    }

    var rho = Array(repeating: 0.0, count: K + 1)
    rho[1] = 1.0 / Double(K)
    if K >= 2 {
        for d in 2...K {
            rho[d] = 1.0 / (Double(d) * Double(d - 1))
        }
    }

    let R = c * log(Double(K) / delta) * sqrt(Double(K))
    var tau = Array(repeating: 0.0, count: K + 1)
    if R > 0 {
        let limit = min(K, max(1, Int((Double(K) / R).rounded())))
        if limit > 1 {
            for d in 1..<limit {
                tau[d] = R / (Double(d) * Double(K))
            }
        }
        tau[limit] = R * log(R / delta) / Double(K)
    }

    var mu = Array(repeating: 0.0, count: K + 1)
    for d in 0...K {
        mu[d] = rho[d] + tau[d]
    }
    let beta = mu.reduce(0.0, +)
    return mu.map { $0 / beta }
}

func cdfFromDistribution(_ mu: [Double]) -> [Double] {
    // mu[0] is unused; degrees are 1..K
    if mu.count <= 2 {
        return [1.0]
    }
    let K = mu.count - 1
    var cdf: [Double] = []
    cdf.reserveCapacity(K)
    var acc = 0.0
    for d in 1...K {
        acc += mu[d]
        cdf.append(acc)
    }
    cdf[cdf.count - 1] = 1.0
    return cdf
}

func sampleDegree(cdf: [Double], prng: inout XorShift32) -> Int {
    let r = prng.nextDouble01()
    var low = 0
    var high = cdf.count - 1
    while low < high {
        let mid = (low + high) / 2
        if r < cdf[mid] {
            high = mid
        } else {
            low = mid + 1
        }
    }
    return low + 1
}

func sampleUniqueIndices(count: Int, upperBound: Int, prng: inout XorShift32) -> [Int] {
    precondition(count >= 0)
    precondition(upperBound >= 0)
    if count == 0 || upperBound == 0 {
        return []
    }
    if count >= upperBound {
        return Array(0..<upperBound)
    }
    var chosen = Set<Int>()
    chosen.reserveCapacity(count)
    while chosen.count < count {
        chosen.insert(prng.nextInt(upperBound: upperBound))
    }
    return Array(chosen)
}

public final class FountainEncoder {
    public let blockSize: Int
    public let K: Int

    private let blocks: [Data]
    private let degreeCDF: [Double]

    public init(data: Data, blockSize: Int, c: Double = 0.1, delta: Double = 0.5) {
        precondition(blockSize > 0)
        self.blockSize = blockSize
        self.K = (data.count + blockSize - 1) / blockSize

        if K == 0 {
            self.blocks = []
        } else {
            var tmp: [Data] = []
            tmp.reserveCapacity(K)
            for i in 0..<K {
                let start = i * blockSize
                let end = min(start + blockSize, data.count)
                var chunk = data.subdata(in: start..<end)
                if chunk.count < blockSize {
                    chunk.append(contentsOf: repeatElement(0, count: blockSize - chunk.count))
                }
                tmp.append(chunk)
            }
            self.blocks = tmp
        }

        let mu = robustSolitonDistribution(K: K, c: c, delta: delta)
        self.degreeCDF = cdfFromDistribution(mu)
    }

    public func generateSymbol(seed: UInt32) -> (degree: Int, data: Data) {
        if K == 0 {
            return (0, Data())
        }
        var prng = XorShift32(seed: seed)
        let degree = sampleDegree(cdf: degreeCDF, prng: &prng)
        let indices = sampleUniqueIndices(count: degree, upperBound: K, prng: &prng)

        var bytes = Array(blocks[indices[0]])
        if indices.count > 1 {
            for idx in indices.dropFirst() {
                xorInPlace(&bytes, with: blocks[idx])
            }
        }
        return (degree, Data(bytes))
    }
}

public final class FountainDecoder {
    public let blockSize: Int
    public let K: Int
    public private(set) var numRecovered: Int = 0

    private var blocks: [Data?]
    private var symbols: [(indices: Set<Int>, data: Data)] = []
    private var recoveredQueue: [(index: Int, data: Data)] = []
    private var queueCursor: Int = 0
    private let degreeCDF: [Double]

    public init(K: Int, blockSize: Int, c: Double = 0.1, delta: Double = 0.5) {
        precondition(K >= 0)
        precondition(blockSize > 0)
        self.K = K
        self.blockSize = blockSize
        self.blocks = Array(repeating: nil, count: K)
        let mu = robustSolitonDistribution(K: K, c: c, delta: delta)
        self.degreeCDF = cdfFromDistribution(mu)

        if K == 0 {
            self.numRecovered = 0
        }
    }

    public func isDone() -> Bool {
        numRecovered == K
    }

    public func addSymbol(seed: UInt32, symbolData: Data) {
        if isDone() || K == 0 {
            return
        }
        guard symbolData.count == blockSize else {
            return
        }

        var prng = XorShift32(seed: seed)
        let degree = sampleDegree(cdf: degreeCDF, prng: &prng)
        let indicesArr = sampleUniqueIndices(count: degree, upperBound: K, prng: &prng)
        var indices = Set(indicesArr)

        var reduced = symbolData
        if !indices.isEmpty {
            var toRemove: [Int] = []
            toRemove.reserveCapacity(indices.count)
            for idx in indices {
                if let block = blocks[idx] {
                    reduced = xorData(reduced, block)
                    toRemove.append(idx)
                }
            }
            for idx in toRemove {
                indices.remove(idx)
            }
        }

        if indices.isEmpty {
            return
        }

        if indices.count == 1, let idx = indices.first {
            if blocks[idx] == nil {
                recoveredQueue.append((idx, reduced))
                propagate()
            }
            return
        }

        for existing in symbols {
            if existing.indices == indices {
                return
            }
        }
        symbols.append((indices, reduced))
    }

    private func propagate() {
        while queueCursor < recoveredQueue.count {
            let (index, data) = recoveredQueue[queueCursor]
            queueCursor += 1

            if blocks[index] != nil {
                continue
            }
            blocks[index] = data
            numRecovered += 1

            if isDone() {
                return
            }

            var newSymbols: [(indices: Set<Int>, data: Data)] = []
            newSymbols.reserveCapacity(symbols.count)

            for var sym in symbols {
                if sym.indices.contains(index) {
                    sym.indices.remove(index)
                    sym.data = xorData(sym.data, data)

                    if sym.indices.count == 1, let last = sym.indices.first {
                        if blocks[last] == nil {
                            recoveredQueue.append((last, sym.data))
                        }
                        continue
                    }
                    if sym.indices.isEmpty {
                        continue
                    }
                }
                newSymbols.append(sym)
            }
            symbols = newSymbols
        }

        // Compact queue storage after batch propagation.
        if queueCursor > 0 {
            recoveredQueue.removeFirst(queueCursor)
            queueCursor = 0
        }
    }

    public func reconstruct() -> Data? {
        if K == 0 {
            return Data()
        }
        guard isDone() else { return nil }
        var out = Data()
        out.reserveCapacity(K * blockSize)
        for block in blocks {
            guard let b = block else { return nil }
            out.append(b)
        }
        return out
    }
}

