//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// On Apple, a few SignalServiceKit call sites qualify libc calls with the
// `Darwin` module (Darwin.ceil/floor/round in OWSMath, Darwin.close/fcntl in
// ConnectionLock). These usages are NOT wrapped in `#if canImport(Darwin)`, so
// on Linux -- where there is no `Darwin` module -- they fail to resolve. This
// caseless `Darwin` enum provides exactly those members, forwarding to the
// standard library / Glibc, so the qualified calls compile and behave.
//
import Foundation
#if canImport(Glibc)
import Glibc
#endif

public enum Darwin {
    // Rounding (CGFloat) -- forwarded to the stdlib so no libc dependency.
    public static func ceil(_ x: CGFloat) -> CGFloat { x.rounded(.up) }
    public static func floor(_ x: CGFloat) -> CGFloat { x.rounded(.down) }
    public static func round(_ x: CGFloat) -> CGFloat { x.rounded(.toNearestOrAwayFromZero) }

    // POSIX file-descriptor calls (ConnectionLock's advisory lock).
    @discardableResult
    public static func close(_ fd: Int32) -> Int32 {
        #if canImport(Glibc)
        return Glibc.close(fd)
        #else
        return -1
        #endif
    }

    @discardableResult
    public static func fcntl(_ fd: Int32, _ cmd: Int32, _ lock: UnsafeMutablePointer<flock>) -> Int32 {
        #if canImport(Glibc)
        return Glibc.fcntl(fd, cmd, lock)
        #else
        return -1
        #endif
    }
}
