import Foundation

public enum SmokeSignalFrameError: Error, Equatable {
    case invalidBase64
    case decodeFailed
    case badCRC
    case unsupportedVersion
    case invalidPayloadSize
}

public enum SmokeSignalFrameType: UInt8, Codable {
    case metadata = 1
    case symbol = 2
}

public struct SmokeSignalFrame: Equatable {
    public static let version: UInt8 = 1

    public var type: SmokeSignalFrameType
    public var sessionId: UInt32
    public var sequence: UInt32
    public var seed: UInt32
    public var fileSize: UInt64
    public var blockSize: UInt16
    public var payload: Data

    public init(
        type: SmokeSignalFrameType,
        sessionId: UInt32,
        sequence: UInt32,
        seed: UInt32,
        fileSize: UInt64,
        blockSize: UInt16,
        payload: Data
    ) {
        self.type = type
        self.sessionId = sessionId
        self.sequence = sequence
        self.seed = seed
        self.fileSize = fileSize
        self.blockSize = blockSize
        self.payload = payload
    }

    public func encode() -> Data {
        var w = ByteWriter()
        w.writeUInt8(Self.version)
        w.writeUInt8(type.rawValue)
        w.writeUInt32BE(sessionId)
        w.writeUInt32BE(sequence)
        w.writeUInt32BE(seed)
        w.writeUInt64BE(fileSize)
        w.writeUInt16BE(blockSize)
        w.writeUInt16BE(UInt16(payload.count))
        w.writeData(payload)

        let crc = CRC32.checksum(w.data)
        w.writeUInt32BE(crc)
        return w.data
    }

    public static func decode(_ data: Data) throws -> SmokeSignalFrame {
        // Minimum header + CRC.
        let minBytes = 1 + 1 + 4 + 4 + 4 + 8 + 2 + 2 + 4
        guard data.count >= minBytes else { throw SmokeSignalFrameError.decodeFailed }

        // CRC is last 4 bytes.
        let withoutCRC = data.prefix(data.count - 4)
        let crcBytes = data.suffix(4)
        let expectedCRC =
            (UInt32(crcBytes[crcBytes.startIndex]) << 24) |
            (UInt32(crcBytes[crcBytes.startIndex + 1]) << 16) |
            (UInt32(crcBytes[crcBytes.startIndex + 2]) << 8) |
            UInt32(crcBytes[crcBytes.startIndex + 3])
        let actualCRC = CRC32.checksum(withoutCRC)
        guard expectedCRC == actualCRC else { throw SmokeSignalFrameError.badCRC }

        var r = ByteReader(Data(withoutCRC))
        let version = try r.readUInt8()
        guard version == Self.version else { throw SmokeSignalFrameError.unsupportedVersion }

        let typeRaw = try r.readUInt8()
        guard let type = SmokeSignalFrameType(rawValue: typeRaw) else { throw SmokeSignalFrameError.decodeFailed }

        let sessionId = try r.readUInt32BE()
        let sequence = try r.readUInt32BE()
        let seed = try r.readUInt32BE()
        let fileSize = try r.readUInt64BE()
        let blockSize = try r.readUInt16BE()
        let payloadSize = Int(try r.readUInt16BE())

        guard payloadSize >= 0, payloadSize <= r.remainingCount else {
            throw SmokeSignalFrameError.invalidPayloadSize
        }
        let payload = try r.readData(count: payloadSize)
        return SmokeSignalFrame(
            type: type,
            sessionId: sessionId,
            sequence: sequence,
            seed: seed,
            fileSize: fileSize,
            blockSize: blockSize,
            payload: payload
        )
    }

    public func encodeBase64() -> String {
        encode().base64EncodedString()
    }

    public static func decodeBase64(_ string: String) throws -> SmokeSignalFrame {
        guard let data = Data(base64Encoded: string) else { throw SmokeSignalFrameError.invalidBase64 }
        return try decode(data)
    }
}
