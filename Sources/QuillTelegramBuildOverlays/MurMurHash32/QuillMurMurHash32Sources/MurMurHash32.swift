// Swift overlay for the upstream Objective-C MurMurHash32 island (a single
// murMurHash32/murMurHashString32 utility pair on Apple). Implemented
// directly: MurmurHash3 x86_32 with upstream's 0 seed.
import Foundation

private func quillMurMur3(_ data: [UInt8]) -> Int32 {
    let c1: UInt32 = 0xcc9e2d51
    let c2: UInt32 = 0x1b873593
    var h1: UInt32 = 0
    let blocks = data.count / 4
    for index in 0..<blocks {
        var k1 = UInt32(data[index * 4])
            | UInt32(data[index * 4 + 1]) << 8
            | UInt32(data[index * 4 + 2]) << 16
            | UInt32(data[index * 4 + 3]) << 24
        k1 = k1 &* c1
        k1 = (k1 << 15) | (k1 >> 17)
        k1 = k1 &* c2
        h1 ^= k1
        h1 = (h1 << 13) | (h1 >> 19)
        h1 = h1 &* 5 &+ 0xe6546b64
    }
    var k1: UInt32 = 0
    let tail = blocks * 4
    let remainder = data.count & 3
    if remainder >= 3 { k1 ^= UInt32(data[tail + 2]) << 16 }
    if remainder >= 2 { k1 ^= UInt32(data[tail + 1]) << 8 }
    if remainder >= 1 {
        k1 ^= UInt32(data[tail])
        k1 = k1 &* c1
        k1 = (k1 << 15) | (k1 >> 17)
        k1 = k1 &* c2
        h1 ^= k1
    }
    h1 ^= UInt32(data.count)
    h1 ^= h1 >> 16
    h1 = h1 &* 0x85ebca6b
    h1 ^= h1 >> 13
    h1 = h1 &* 0xc2b2ae35
    h1 ^= h1 >> 16
    return Int32(bitPattern: h1)
}

public func murMurHash32(_ data: Data) -> Int32 {
    quillMurMur3([UInt8](data))
}

public func murMurHashString32(_ string: String) -> Int32 {
    quillMurMur3([UInt8](string.utf8))
}
