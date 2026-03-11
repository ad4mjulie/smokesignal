import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct SmokeSignalMetadata: Codable, Equatable {
    public var fileName: String?
    public var mimeType: String?
    public var sha256Hex: String?

    public init(fileName: String? = nil, mimeType: String? = nil, sha256Hex: String? = nil) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.sha256Hex = sha256Hex
    }
}

public func smokeSignalSHA256Hex(of data: Data) -> String? {
    #if canImport(CryptoKit)
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
    #else
    return nil
    #endif
}
