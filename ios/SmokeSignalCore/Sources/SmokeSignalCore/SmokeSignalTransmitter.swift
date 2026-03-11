import Foundation

public struct SmokeSignalTransmitConfig: Equatable {
    public var blockSize: Int
    public var metadataEveryNSymbols: Int

    public init(blockSize: Int = 256, metadataEveryNSymbols: Int = 25) {
        self.blockSize = blockSize
        self.metadataEveryNSymbols = metadataEveryNSymbols
    }
}

public final class SmokeSignalTransmitter {
    public let sessionId: UInt32
    public let fileSize: Int
    public let config: SmokeSignalTransmitConfig
    public let metadata: SmokeSignalMetadata

    private let encoder: FountainEncoder
    private var symbolSequence: UInt32 = 0
    private var metaSequence: UInt32 = 0
    private var shouldSendMetadata = true
    private var symbolsSinceMetadata = 0

    public init(data: Data, metadata: SmokeSignalMetadata, sessionId: UInt32 = UInt32.random(in: 0...UInt32.max), config: SmokeSignalTransmitConfig = SmokeSignalTransmitConfig()) {
        precondition(config.blockSize > 0 && config.blockSize <= Int(UInt16.max))
        self.sessionId = sessionId
        self.fileSize = data.count
        self.metadata = metadata
        self.config = config
        self.encoder = FountainEncoder(data: data, blockSize: config.blockSize)
    }

    public func nextFrame() -> SmokeSignalFrame {
        // Send metadata once at start, then periodically to help receivers that join mid-stream.
        if shouldSendMetadata {
            shouldSendMetadata = false
            symbolsSinceMetadata = 0
            metaSequence &+= 1
            let json = (try? JSONEncoder().encode(metadata)) ?? Data()
            return SmokeSignalFrame(
                type: .metadata,
                sessionId: sessionId,
                sequence: metaSequence,
                seed: 0,
                fileSize: UInt64(fileSize),
                blockSize: UInt16(config.blockSize),
                payload: json
            )
        }

        symbolSequence &+= 1
        symbolsSinceMetadata += 1
        if config.metadataEveryNSymbols > 0, symbolsSinceMetadata >= config.metadataEveryNSymbols {
            shouldSendMetadata = true
        }
        let seed = UInt32.random(in: 0...UInt32.max)
        let symbol = encoder.generateSymbol(seed: seed)
        return SmokeSignalFrame(
            type: .symbol,
            sessionId: sessionId,
            sequence: symbolSequence,
            seed: seed,
            fileSize: UInt64(fileSize),
            blockSize: UInt16(config.blockSize),
            payload: symbol.data
        )
    }

    public func nextBase64Frame() -> String {
        nextFrame().encodeBase64()
    }
}
