import Foundation
import Testing
@testable import SmokeSignalCore

@Test
func fountainRoundTripWithLoss() {
    let original = Data((0..<10_000).map { _ in UInt8.random(in: 0...255) })
    let blockSize = 256
    let encoder = FountainEncoder(data: original, blockSize: blockSize)
    let K = encoder.K
    let decoder = FountainDecoder(K: K, blockSize: blockSize)

    var sent = 0
    var received = 0
    while !decoder.isDone() && sent < 200_000 {
        sent += 1
        // Drop ~35% of symbols.
        if Double.random(in: 0..<1) < 0.35 {
            continue
        }
        let seed = UInt32.random(in: 0...UInt32.max)
        let symbol = encoder.generateSymbol(seed: seed)
        decoder.addSymbol(seed: seed, symbolData: symbol.data)
        received += 1
    }

    #expect(decoder.isDone())
    let reconstructed = decoder.reconstruct()!
    let trimmed = reconstructed.prefix(original.count)
    #expect(Data(trimmed) == original)
}

