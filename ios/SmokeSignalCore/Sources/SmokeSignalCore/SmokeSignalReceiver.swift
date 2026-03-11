import Foundation

public struct SmokeSignalReceiveLimits: Equatable {
    public var maxFileSizeBytes: Int

    public init(maxFileSizeBytes: Int = 50 * 1024 * 1024) {
        self.maxFileSizeBytes = maxFileSizeBytes
    }
}

public struct SmokeSignalReceivedFile: Equatable {
    public var sessionId: UInt32
    public var data: Data
    public var metadata: SmokeSignalMetadata
}

public enum SmokeSignalReceiverEvent: Equatable {
    case ignored
    case updated(progress: Double)
    case completed(file: SmokeSignalReceivedFile)
}

public final class SmokeSignalReceiver {
    public private(set) var metadata = SmokeSignalMetadata()
    public private(set) var sessionId: UInt32?
    public private(set) var fileSize: Int?
    public private(set) var blockSize: Int?
    public private(set) var recoveredBlocks: Int = 0
    public private(set) var totalBlocks: Int = 0

    private let limits: SmokeSignalReceiveLimits
    private var decoder: FountainDecoder?
    private var seenSeeds = Set<UInt32>()

    public init(limits: SmokeSignalReceiveLimits = SmokeSignalReceiveLimits()) {
        self.limits = limits
    }

    public func reset() {
        metadata = SmokeSignalMetadata()
        sessionId = nil
        fileSize = nil
        blockSize = nil
        recoveredBlocks = 0
        totalBlocks = 0
        decoder = nil
        seenSeeds.removeAll(keepingCapacity: false)
    }

    public func ingest(base64: String) -> SmokeSignalReceiverEvent {
        guard let raw = Data(base64Encoded: base64) else { return .ignored }
        guard let frame = try? SmokeSignalFrame.decode(raw) else { return .ignored }

        guard frame.fileSize <= UInt64(Int.max) else { return .ignored }
        let size = Int(frame.fileSize)
        if size > limits.maxFileSizeBytes {
            return .ignored
        }

        if sessionId != frame.sessionId {
            // New session.
            reset()
            sessionId = frame.sessionId
            fileSize = size
            blockSize = Int(frame.blockSize)
            let bs = max(1, Int(frame.blockSize))
            totalBlocks = (size + bs - 1) / bs
            decoder = FountainDecoder(K: totalBlocks, blockSize: bs)
        }

        if frame.type == .metadata {
            if let decoded = try? JSONDecoder().decode(SmokeSignalMetadata.self, from: frame.payload) {
                metadata = decoded
            }
            return .updated(progress: progress)
        }

        guard frame.type == .symbol else { return .ignored }
        guard let decoder else { return .ignored }
        if seenSeeds.contains(frame.seed) {
            return .ignored
        }
        seenSeeds.insert(frame.seed)

        decoder.addSymbol(seed: frame.seed, symbolData: frame.payload)
        recoveredBlocks = decoder.numRecovered

        if decoder.isDone() {
            guard let reconstructed = decoder.reconstruct() else { return .ignored }
            let trimmed = reconstructed.prefix(size)

            // If sender didn't provide a hash, accept as-is.
            if let expected = metadata.sha256Hex, let actual = smokeSignalSHA256Hex(of: Data(trimmed)), expected.lowercased() != actual.lowercased() {
                return .ignored
            }
            return .completed(
                file: SmokeSignalReceivedFile(
                    sessionId: frame.sessionId,
                    data: Data(trimmed),
                    metadata: metadata
                )
            )
        }

        return .updated(progress: progress)
    }

    public var progress: Double {
        guard totalBlocks > 0 else { return 0.0 }
        return Double(recoveredBlocks) / Double(totalBlocks)
    }
}
