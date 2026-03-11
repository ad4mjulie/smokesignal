import Foundation
import Testing
@testable import SmokeSignalCore

@Test
func crc32KnownVector() {
    let data = Data("123456789".utf8)
    #expect(CRC32.checksum(data) == 0xCBF43926)
}

