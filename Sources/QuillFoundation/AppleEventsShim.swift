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
public typealias DescType = FourCharCode

// Real four-char-code values (for faithfulness; never actually compared on Linux).
public let kCoreEventClass: AEEventClass = 0x6165_7674   // 'aevt'
public let kAEOpenApplication: AEEventID = 0x6F61_7070   // 'oapp'
public let kAEQuitApplication: AEEventID = 0x7175_6974   // 'quit'
public let keySenderPIDAttr: AEKeyword = 0x7370_6964     // 'spid'
public let kInternetEventClass: AEEventClass = 0x4755_524C // 'GURL'
public let kAEGetURL: AEEventID = 0x4755_524C             // 'GURL'
public let keyDirectObject: AEKeyword = 0x2D2D_2D2D       // '----'
public let keyAEInsertHere: AEKeyword = 0x696E_7368       // 'insh'

public extension String {
    var fourCharCode: FourCharCode {
        precondition(count == 4)
        return unicodeScalars.reduce(UInt32(0)) { ($0 << 8) + $1.value }
    }
}

public extension Int {
    var fourCharCode: FourCharCode {
        UInt32(self)
    }
}

/// Minimal NSAppleEventDescriptor shadow: the detectors read `eventClass`/`eventID`,
/// fetch an attribute descriptor by keyword, and read its `int32Value` (the sender PID).
open class NSAppleEventDescriptor {
    private var attributes: [AEKeyword: NSAppleEventDescriptor] = [:]
    private var parameters: [AEKeyword: NSAppleEventDescriptor] = [:]

    open var eventClass: AEEventClass
    open var eventID: AEEventID
    open var descriptorType: DescType
    open var int32Value: Int32
    open var stringValue: String?

    public init(
        eventClass: AEEventClass = 0,
        eventID: AEEventID = 0,
        descriptorType: DescType = 0,
        int32Value: Int32 = 0,
        stringValue: String? = nil
    ) {
        self.eventClass = eventClass
        self.eventID = eventID
        self.descriptorType = descriptorType
        self.int32Value = int32Value
        self.stringValue = stringValue
    }

    public convenience init(string: String) {
        self.init(descriptorType: 0x7574_6638, stringValue: string) // 'utf8'
    }

    public static func record() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(descriptorType: 0x7265_636F) // 'reco'
    }

    open func attributeDescriptor(forKeyword keyword: AEKeyword) -> NSAppleEventDescriptor? {
        attributes[keyword]
    }

    open func setAttribute(_ descriptor: NSAppleEventDescriptor?, forKeyword keyword: AEKeyword) {
        attributes[keyword] = descriptor
    }

    open func paramDescriptor(forKeyword keyword: AEKeyword) -> NSAppleEventDescriptor? {
        parameters[keyword]
    }

    open func setParam(_ descriptor: NSAppleEventDescriptor, forKeyword keyword: AEKeyword) {
        parameters[keyword] = descriptor
    }

    open func forKeyword(_ keyword: AEKeyword) -> NSAppleEventDescriptor? {
        parameters[keyword] ?? attributes[keyword]
    }
}

/// NSAppleEventManager shadow — AppDelegate reads `.shared().currentAppleEvent` to get
/// the open/quit Apple event at launch. nil on Linux (no Apple Events subsystem).
open class NSAppleEventManager: @unchecked Sendable {
    private static let _shared = NSAppleEventManager()
    public static func shared() -> NSAppleEventManager { _shared }
    public init() {}
    open var currentAppleEvent: NSAppleEventDescriptor? { nil }
    public private(set) var installedHandlers: [InstalledAppleEventHandler] = []

    public struct InstalledAppleEventHandler: Sendable, Equatable {
        public let selector: Selector
        public let eventClass: AEEventClass
        public let eventID: AEEventID
    }

    open func setEventHandler(_ handler: Any, andSelector selector: Selector, forEventClass eventClass: AEEventClass, andEventID eventID: AEEventID) {
        _ = handler
        installedHandlers.append(InstalledAppleEventHandler(selector: selector, eventClass: eventClass, eventID: eventID))
    }
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
