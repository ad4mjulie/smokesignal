import Foundation

// Portable, deterministic PRNG to keep encoder/decoder behavior stable across
// platforms and languages (unlike system RNGs).
struct XorShift32 {
    private var state: UInt32

    init(seed: UInt32) {
        // xorshift32 gets stuck at 0, so force a non-zero state.
        self.state = seed == 0 ? 0xA341_316C : seed
    }

    mutating func nextUInt32() -> UInt32 {
        var x = state
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
        state = x
        return x
    }

    mutating func nextDouble01() -> Double {
        // Uniform in [0, 1).
        Double(nextUInt32()) / 4294967296.0
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        let bound = UInt64(upperBound)
        let threshold = (UInt64(1) << 32) % bound
        while true {
            let r = UInt64(nextUInt32())
            let m = r * bound
            let low = m & 0xFFFF_FFFF
            if low >= threshold {
                return Int(m >> 32)
            }
        }
    }
}

