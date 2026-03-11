import Foundation
import Testing
@testable import SmokeSignalCore

@Test
func frameEncodeDecodeRoundTrip() throws {
    let payload = Data((0..<32).map { UInt8($0) })
    let frame = SmokeSignalFrame(
        type: .symbol,
        sessionId: 42,
        sequence: 7,
        seed: 123,
        fileSize: 999,
        blockSize: 256,
        payload: payload
    )
    let encoded = frame.encode()
    let decoded = try SmokeSignalFrame.decode(encoded)
    #expect(decoded == frame)
}

@Test
func frameBase64RoundTrip() throws {
    let payload = Data("hello".utf8)
    let frame = SmokeSignalFrame(
        type: .metadata,
        sessionId: 1,
        sequence: 1,
        seed: 0,
        fileSize: 5,
        blockSize: 256,
        payload: payload
    )
    let b64 = frame.encodeBase64()
    let decoded = try SmokeSignalFrame.decodeBase64(b64)
    #expect(decoded == frame)
}

