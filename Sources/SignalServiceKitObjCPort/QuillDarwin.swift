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

// MARK: - Mach task-info + malloc-zone shims (Linux)
//
// Bench + LocalDevice read the process memory footprint via Mach task_info /
// task_vm_info and malloc-zone statistics. None of Mach exists on Linux. These
// inert shims make the call sites compile; task_info returns KERN_SUCCESS with
// the caller's info struct left zeroed (so the reported footprint is 0 until a
// /proc-based implementation lands). Top-level because upstream uses these
// symbols unqualified (Darwin makes them implicit on Apple).

public typealias natural_t = UInt32
public typealias integer_t = Int32
public typealias mach_msg_type_number_t = natural_t
public typealias kern_return_t = Int32
public typealias mach_vm_size_t = UInt64
public typealias mach_port_t = UInt32
public typealias task_t = mach_port_t
public typealias task_flavor_t = natural_t

public let KERN_SUCCESS: kern_return_t = 0
public let mach_task_self_: task_t = 0
public let MACH_TASK_BASIC_INFO: integer_t = 20
public let TASK_VM_INFO: integer_t = 22

public struct time_value_t {
    public var seconds: integer_t = 0
    public var microseconds: integer_t = 0
    public init() {}
}

public struct mach_task_basic_info {
    public var virtual_size: mach_vm_size_t = 0
    public var resident_size: mach_vm_size_t = 0
    public var resident_size_max: mach_vm_size_t = 0
    public var user_time: time_value_t = time_value_t()
    public var system_time: time_value_t = time_value_t()
    public var policy: integer_t = 0
    public var suspend_count: integer_t = 0
    public init() {}
}

public struct task_vm_info_data_t {
    public var phys_footprint: UInt64 = 0
    public var ledger_phys_footprint_peak: Int64 = 0
    public var limit_bytes_remaining: UInt64 = 0
    public init() {}
}

@discardableResult
public func task_info(_ target_task: task_t,
                      _ flavor: task_flavor_t,
                      _ task_info_out: UnsafeMutablePointer<integer_t>?,
                      _ task_info_outCnt: UnsafeMutablePointer<mach_msg_type_number_t>?) -> kern_return_t {
    _ = (target_task, flavor, task_info_out, task_info_outCnt)
    return KERN_SUCCESS
}

public func mach_error_string(_ error_value: kern_return_t) -> UnsafeMutablePointer<CChar>! {
    _ = error_value
    #if canImport(Glibc)
    return strdup("mach error (quill shim)")
    #else
    return nil
    #endif
}

// malloc-zone statistics (Darwin malloc/malloc.h). LocalDevice reads size_in_use
// / size_allocated; inert -> zeroed statistics.
public struct malloc_statistics_t {
    public var blocks_in_use: UInt32 = 0
    public var size_in_use: Int = 0
    public var max_size_in_use: Int = 0
    public var size_allocated: Int = 0
    public init() {}
}
public func malloc_default_zone() -> OpaquePointer? { nil }
public func malloc_zone_statistics(_ zone: OpaquePointer?, _ stats: UnsafeMutablePointer<malloc_statistics_t>?) {
    _ = (zone, stats)
}

// sysctlbyname (BSD/Darwin by-name sysctl; Linux has no by-name sysctl).
// String(sysctlKey:) queries hardware strings (hw.machine etc). Inert: report
// zero length + failure so the caller's `guard size > 0` returns nil (no value,
// no allocation) rather than reading uninitialized size.
@discardableResult
public func sysctlbyname(_ name: UnsafePointer<CChar>!,
                         _ oldp: UnsafeMutableRawPointer!,
                         _ oldlenp: UnsafeMutablePointer<Int>!,
                         _ newp: UnsafeMutableRawPointer!,
                         _ newlen: Int) -> Int32 {
    oldlenp?.pointee = 0
    _ = (name, oldp, newp, newlen)
    return -1
}

// Dispatch QoS class (Darwin <sys/qos.h>; absent on Linux libdispatch).
// DispatchQueue+OWS floors a qos_class_t to a DispatchQoS.QoSClass by comparing
// rawValue ranges, so the constants need their real Darwin values + .rawValue.
public struct qos_class_t: RawRepresentable, Equatable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
}
public let QOS_CLASS_USER_INTERACTIVE = qos_class_t(rawValue: 0x21)
public let QOS_CLASS_USER_INITIATED = qos_class_t(rawValue: 0x19)
public let QOS_CLASS_DEFAULT = qos_class_t(rawValue: 0x15)
public let QOS_CLASS_UTILITY = qos_class_t(rawValue: 0x11)
public let QOS_CLASS_BACKGROUND = qos_class_t(rawValue: 0x09)
public let QOS_CLASS_UNSPECIFIED = qos_class_t(rawValue: 0x00)
