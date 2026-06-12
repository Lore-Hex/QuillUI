// Swift clone of the upstream Objective-C LokiRng (Loki GPU-style hash RNG:
// three seeds, Tausworthe/LCG combination, returns floats in [0, 1)).
import Foundation

public final class LokiRng {
    private var seed: UInt32

    public init(seed0: UInt, seed1: UInt, seed2: UInt) {
        func tausStep(_ z: UInt32, _ s1: UInt32, _ s2: UInt32, _ s3: UInt32, _ m: UInt32) -> UInt32 {
            let b = ((z << s1) ^ z) >> s2
            return ((z & m) << s3) ^ b
        }
        let s0 = UInt32(truncatingIfNeeded: seed0) &* 1099087573
        let z1 = tausStep(s0, 13, 19, 12, 4294967294)
        let z2 = tausStep(s0, 2, 25, 4, 4294967288)
        let z3 = tausStep(s0, 3, 11, 17, 4294967280)
        let z4 = 1664525 &* s0 &+ 1013904223
        let combined = z1 ^ z2 ^ z3 ^ z4
        self.seed = combined ^ (UInt32(truncatingIfNeeded: seed1) &* 1099087573) ^ (UInt32(truncatingIfNeeded: seed2) &* 1099087573)
        if self.seed == 0 { self.seed = 1 }
    }

    public func next() -> Float {
        seed = 1664525 &* seed &+ 1013904223
        return Float(seed) / Float(UInt32.max)
    }
}
