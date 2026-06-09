#if os(Linux)
import Foundation
#if canImport(Glibc)
import Glibc
#endif

// Apple Events + Darwin-C surface for WireGuard's macOS launch/quit detectors
// (LaunchedAtLoginDetector reads the open-app Apple event; MacAppStoreUpdateDetector
// reads the quit Apple event's sender PID). None of this exists on Linux, and the
// detectors are only ever invoked from the macOS app's Apple-Event handlers, so this
// is a compile-faithful shadow whose bodies are inert stubs — it exists so the
// unmodified detector source recompiles against QuillFoundation.

public typealias FourCharCode = UInt32
public typealias OSType = UInt32
public typealias AEEventClass = FourCharCode
public typealias AEEventID = FourCharCode
public typealias AEKeyword = FourCharCode

// Real four-char-code values (for faithfulness; never actually compared on Linux).
public let kCoreEventClass: AEEventClass = 0x6165_7674   // 'aevt'
public let kAEOpenApplication: AEEventID = 0x6F61_7070   // 'oapp'
public let kAEQuitApplication: AEEventID = 0x7175_6974   // 'quit'
public let keySenderPIDAttr: AEKeyword = 0x7370_6964     // 'spid'

/// Minimal NSAppleEventDescriptor shadow: the detectors read `eventClass`/`eventID`,
/// fetch an attribute descriptor by keyword, and read its `int32Value` (the sender PID).
open class NSAppleEventDescriptor {
    public init() {}
    open var eventClass: AEEventClass { 0 }
    open var eventID: AEEventID { 0 }
    open var int32Value: Int32 { 0 }
    open func attributeDescriptor(forKeyword keyword: AEKeyword) -> NSAppleEventDescriptor? { nil }
}

/// NSAppleEventManager shadow — AppDelegate reads `.shared().currentAppleEvent` to get
/// the open/quit Apple event at launch. nil on Linux (no Apple Events subsystem).
open class NSAppleEventManager: @unchecked Sendable {
    private static let _shared = NSAppleEventManager()
    public static func shared() -> NSAppleEventManager { _shared }
    public init() {}
    open var currentAppleEvent: NSAppleEventDescriptor? { nil }
}

// Darwin-only C APIs the detectors call. Linux has no exact equivalents
// (CLOCK_UPTIME_RAW and clock_gettime_nsec_np are Apple extensions; proc_pidpath
// is Darwin libproc). pid_t/clockid_t come from Glibc.
public let CLOCK_UPTIME_RAW: clockid_t = clockid_t(CLOCK_MONOTONIC)

// Faithful Linux port of Apple's `clock_gettime_nsec_np`: returns the value of
// the given clock in nanoseconds (0 on error, matching Apple). Backed by the
// POSIX `clock_gettime`. SignalServiceKit's MonotonicDate calls this on EVERY
// DBRead/DBWriteTransaction (and owsFail()s if it returns 0), so it must be a
// real implementation, not a stub.
public func clock_gettime_nsec_np(_ clockId: clockid_t) -> UInt64 {
    var ts = timespec()
    guard clock_gettime(clockId, &ts) == 0 else { return 0 }
    return UInt64(ts.tv_sec) &* 1_000_000_000 &+ UInt64(ts.tv_nsec)
}
public func proc_pidpath(_ pid: pid_t, _ buffer: UnsafeMutableRawPointer?, _ bufferSize: UInt32) -> Int32 { 0 }
#endif
