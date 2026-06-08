//
// SignalServiceKit libc port for QuillOS (Track B).
//
// `timingsafe_bcmp` is a BSD/Darwin libc function (constant-time memory compare)
// used by Data.ows_constantTimeIsEqual. glibc on Linux does not provide it
// ("cannot find 'timingsafe_bcmp' in scope"), so this is a faithful Swift port:
// it compares all `n` bytes with no early-out (constant time w.r.t. the data) to
// avoid leaking equality position via timing — the whole point of the call.
//
// Signature matches BSD's `int timingsafe_bcmp(const void *b1, const void *b2,
// size_t n)`: returns 0 iff the regions are equal, non-zero otherwise.
//
import Foundation

public func timingsafe_bcmp(_ b1: UnsafeRawPointer?, _ b2: UnsafeRawPointer?, _ n: Int) -> Int32 {
    guard n > 0 else { return 0 }
    guard let b1, let b2 else { return 1 }
    let p1 = b1.assumingMemoryBound(to: UInt8.self)
    let p2 = b2.assumingMemoryBound(to: UInt8.self)
    var diff: UInt8 = 0
    for i in 0..<n {
        diff |= p1[i] ^ p2[i]
    }
    return diff == 0 ? 0 : 1
}
