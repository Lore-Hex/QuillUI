#if os(Linux)
import Foundation

@discardableResult
func sysctlbyname(
    _ name: UnsafePointer<CChar>!,
    _ oldp: UnsafeMutableRawPointer!,
    _ oldlenp: UnsafeMutablePointer<Int>!,
    _ newp: UnsafeMutableRawPointer!,
    _ newlen: Int
) -> Int32 {
    oldlenp?.pointee = 0
    _ = (name, oldp, newp, newlen)
    return -1
}
#endif
