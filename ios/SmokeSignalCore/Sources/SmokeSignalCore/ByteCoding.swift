import Foundation

public enum ByteCodingError: Error, Equatable {
    case outOfBounds
}

struct ByteWriter {
    private(set) var data = Data()

    mutating func writeUInt8(_ value: UInt8) {
        data.append(value)
    }

    mutating func writeUInt16BE(_ value: UInt16) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt32BE(_ value: UInt32) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt64BE(_ value: UInt64) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    mutating func writeData(_ value: Data) {
        data.append(value)
    }
}

struct ByteReader {
    private let data: Data
    private var offset: Int = 0

    init(_ data: Data) {
        self.data = data
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset + 1 <= data.count else { throw ByteCodingError.outOfBounds }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16BE() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw ByteCodingError.outOfBounds }
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        offset += 2
        return (b0 << 8) | b1
    }

    mutating func readUInt32BE() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ByteCodingError.outOfBounds }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        offset += 4
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    mutating func readUInt64BE() throws -> UInt64 {
        guard offset + 8 <= data.count else { throw ByteCodingError.outOfBounds }
        var out: UInt64 = 0
        for _ in 0..<8 {
            out = (out << 8) | UInt64(data[offset])
            offset += 1
        }
        return out
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw ByteCodingError.outOfBounds }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    var remainingCount: Int {
        data.count - offset
    }
}
