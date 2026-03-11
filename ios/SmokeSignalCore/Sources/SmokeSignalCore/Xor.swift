import Foundation

func xorData(_ a: Data, _ b: Data) -> Data {
    precondition(a.count == b.count)
    var out = Data(count: a.count)
    out.withUnsafeMutableBytes { outBytes in
        a.withUnsafeBytes { aBytes in
            b.withUnsafeBytes { bBytes in
                let oa = aBytes.bindMemory(to: UInt8.self)
                let ob = bBytes.bindMemory(to: UInt8.self)
                let oo = outBytes.bindMemory(to: UInt8.self)
                for i in 0..<a.count {
                    oo[i] = oa[i] ^ ob[i]
                }
            }
        }
    }
    return out
}

func xorInPlace(_ buffer: inout [UInt8], with data: Data) {
    precondition(buffer.count == data.count)
    data.withUnsafeBytes { bytes in
        let other = bytes.bindMemory(to: UInt8.self)
        for i in 0..<buffer.count {
            buffer[i] ^= other[i]
        }
    }
}

