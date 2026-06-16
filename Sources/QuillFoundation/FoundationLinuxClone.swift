#if os(Linux)
import Foundation
#if canImport(Glibc)
import Glibc
#endif

// macOS Foundation APIs that are missing from swift-corelibs-foundation on
// Linux, cloned here so verbatim Apple-source compiles unchanged. QuillFoundation
// `@_exported import`s Foundation, so a target that links it (and whose source
// `import`s QuillFoundation) sees these alongside the real Foundation surface.
// Grows one gap at a time as vendored upstream code surfaces them.

public extension NSString {
    /// Clone of Apple's `NSString.localizedStringWithFormat(_:_:)`, absent from
    /// swift-corelibs-foundation. Formats the arguments into `format` (the
    /// Apple version is current-locale-aware; locale only affects numeric
    /// formatting, which the cases we hit so far don't use).
    static func localizedStringWithFormat(_ format: NSString, _ args: CVarArg...) -> NSString {
        NSString(string: String(format: format as String, arguments: args))
    }
}

public extension NSMutableString {
    func appendFormat(_ format: String, _ args: CVarArg...) {
        append(String(format: format, arguments: args))
    }
}

public extension NSDictionary {
    func fileSize() -> UInt64 {
        for key in [FileAttributeKey.size, "NSFileSize", "size"] as [Any] {
            if let number = self[key] as? NSNumber {
                return number.uint64Value
            }
            if let value = self[key] as? UInt64 {
                return value
            }
            if let value = self[key] as? Int {
                return UInt64(Swift.max(0, value))
            }
        }
        return 0
    }
}

public extension FileManager {
    /// Clone of Apple's app-group container API, absent from
    /// swift-corelibs-foundation. There are no app groups on Linux, so this
    /// returns nil — callers degrade gracefully (e.g. WireGuard's
    /// FileManager+Extension shared-folder / last-error URLs become nil).
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        nil
    }
}

public extension Thread {
    /// swift-corelibs-foundation exposes `Thread` but not the Apple
    /// `threadPriority` property. Linux pthread priority mapping is deferred;
    /// this stores no state and lets scheduling callers compile unchanged.
    var threadPriority: Double {
        get { 0.5 }
        set { _ = newValue }
    }
}

public func NSSelectorFromString(_ string: String) -> Selector {
    Selector(string)
}

private func quillInvokeSelectorPayload(_ object: Any?) {
    if let action = object as? () -> Void {
        action()
        return
    }
    if let action = object as? (@convention(block) () -> Void) {
        action()
        return
    }
}

private struct QuillUncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

public extension Thread {
    convenience init(target: Any, selector: Selector, object argument: Any?) {
        _ = (target, selector)
        let argumentBox = QuillUncheckedSendable(value: argument)
        self.init {
            quillInvokeSelectorPayload(argumentBox.value)
        }
    }
}

public extension NSObject {
    var className: String {
        String(describing: type(of: self))
    }

    func performSelector(onMainThread selector: Selector, with object: Any?, waitUntilDone: Bool) {
        _ = (selector, waitUntilDone)
        quillInvokeSelectorPayload(object)
    }

    class func perform(_ selector: Selector, on thread: Thread, with object: Any?, waitUntilDone: Bool) {
        _ = (selector, thread, waitUntilDone)
        quillInvokeSelectorPayload(object)
    }

    func perform(_ selector: Selector, with object: Any? = nil) -> Unmanaged<AnyObject>? {
        _ = selector
        quillInvokeSelectorPayload(object)
        return nil
    }

    // KVC entry points. corelibs has no ObjC-runtime key-value coding, so
    // these forward to QuillKeyValueCoding when the receiver adopts it
    // (CALayer/CAAnimation in the QuartzCore shim carry real key tables);
    // for every other NSObject they remain the historical no-op stubs.
    func value(forKey key: String) -> Any? {
        (self as? QuillKeyValueCoding)?.quillValue(forKey: key)
    }

    func value(forKeyPath keyPath: String) -> Any? {
        (self as? QuillKeyValueCoding)?.quillValue(forKeyPath: keyPath)
    }

    func setValue(_ value: Any?, forKey key: String) {
        (self as? QuillKeyValueCoding)?.quillSetValue(value, forKey: key)
    }

    func setValue(_ value: Any?, forKeyPath keyPath: String) {
        (self as? QuillKeyValueCoding)?.quillSetValue(value, forKeyPath: keyPath)
    }
}

/// Functional key-value coding opt-in. NSObject's KVC stubs above cannot be
/// overridden (extension methods), so types that genuinely answer KVC —
/// QuartzCore's CALayer and CAAnimation, whose consumers address properties
/// by key path constantly — adopt this protocol; the stubs dynamic-cast and
/// forward. Mirrors the QuillSelectorDispatching pattern.
public protocol QuillKeyValueCoding {
    func quillValue(forKey key: String) -> Any?
    func quillValue(forKeyPath keyPath: String) -> Any?
    func quillSetValue(_ value: Any?, forKey key: String)
    func quillSetValue(_ value: Any?, forKeyPath keyPath: String)
}

public extension QuillKeyValueCoding {
    // Key-path forms default to the plain-key forms for adopters without
    // path-structured keys.
    func quillValue(forKeyPath keyPath: String) -> Any? {
        quillValue(forKey: keyPath)
    }
    func quillSetValue(_ value: Any?, forKeyPath keyPath: String) {
        quillSetValue(value, forKey: keyPath)
    }
}

private struct QuillNSSortDescriptorKeyRoot {
    let value: String
}

private final class QuillNSSortDescriptorMetadataStore: @unchecked Sendable {
    static let shared = QuillNSSortDescriptorMetadataStore()

    private final class Entry {
        weak var descriptor: NSSortDescriptor?
        let key: String?

        init(descriptor: NSSortDescriptor, key: String?) {
            self.descriptor = descriptor
            self.key = key
        }
    }

    private let lock = NSLock()
    private var keys: [ObjectIdentifier: Entry] = [:]

    func setKey(_ key: String?, for descriptor: NSSortDescriptor) {
        lock.lock()
        keys[ObjectIdentifier(descriptor)] = Entry(descriptor: descriptor, key: key)
        lock.unlock()
    }

    func key(for descriptor: NSSortDescriptor) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let identifier = ObjectIdentifier(descriptor)
        guard let entry = keys[identifier] else {
            return nil
        }
        guard entry.descriptor === descriptor else {
            keys[identifier] = nil
            return nil
        }
        return entry.key
    }
}

public extension NSSortDescriptor {
    /// Builds a Linux-safe descriptor for Apple-source that uses KVC string
    /// sort keys. swift-corelibs marks `init(key:ascending:)` unavailable and
    /// traps if availability is suppressed, so source lowering rewrites those
    /// calls to this adapter and preserves the key in a side table.
    static func quillKey(_ key: String?, ascending: Bool) -> NSSortDescriptor {
        let descriptor = NSSortDescriptor(
            keyPath: \QuillNSSortDescriptorKeyRoot.value,
            ascending: ascending
        )
        QuillNSSortDescriptorMetadataStore.shared.setKey(key, for: descriptor)
        return descriptor
    }

    /// Linux companion for Apple's `key` property. Source lowering rewrites
    /// `sortDescriptor.key` to `sortDescriptor.quillKey` for values created
    /// by `NSSortDescriptor.quillKey(_:ascending:)`.
    var quillKey: String? {
        QuillNSSortDescriptorMetadataStore.shared.key(for: self)
    }
}

public func NSStringFromSelector(_ selector: Selector) -> String {
    selector.name
}

public func object_getClassName(_ object: Any?) -> UnsafePointer<CChar>? {
    _ = object
    return nil
}

public extension NotificationCenter {
    func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?) {
        _ = (observer, selector)
        _ = addObserver(forName: name, object: object, queue: nil) { _ in }
    }

    // swift-corelibs Foundation types the block-based `addObserver` closure as
    // `@Sendable`, which makes it nonisolated; SignalUI's observers call
    // @MainActor members (`self.updateContents(...)`) on `self` from inside. On
    // Apple the UI thread invariant makes this safe; on Linux we model it by
    // typing the closure `@MainActor` so the body may touch main-actor state.
    // Distinct closure isolation = a separate overload that wins for these calls.
    @discardableResult
    func addObserver(
        forName name: NSNotification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @MainActor @escaping (Notification) -> Void
    ) -> any NSObjectProtocol {
        quillAddObserver(forName: name, object: obj, queue: queue, using: block)
    }

    /// DISTINCT-name @MainActor `addObserver`. A same-name `@MainActor` overload
    /// does NOT win resolution against corelibs' `@Sendable` one (the @Sendable
    /// closure is an equally-valid match), so SignalUI's observers still bound to
    /// the nonisolated overload. `AppKitLowering` rewrites
    /// `<nc>.addObserver(forName:object:queue:using:){…}` → `.quillAddObserver(…)`,
    /// a unique symbol whose @MainActor block lets the closure call @MainActor
    /// members. Inert hop on Linux (notifications post synchronously).
    @discardableResult
    func quillAddObserver(
        forName name: NSNotification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @MainActor @escaping (Notification) -> Void
    ) -> any NSObjectProtocol {
        addObserver(forName: name, object: obj, queue: queue) { notification in
            // corelibs posts synchronously on the calling thread on Linux, so the
            // value never actually crosses threads; `nonisolated(unsafe)` tells the
            // Swift 6 sending-check what the runtime already guarantees here.
            nonisolated(unsafe) let n = notification
            MainActor.assumeIsolated {
                block(n)
            }
        }
    }
}

public extension Timer {
    // Same @Sendable-vs-@MainActor mismatch as NotificationCenter above: corelibs
    // types `scheduledTimer(withTimeInterval:repeats:block:)`'s block `@Sendable`,
    // but SignalUI's timer fires call @MainActor methods on captured `self`. Type
    // the block `@MainActor` and assume main-actor isolation when it runs (timers
    // are scheduled on the main run loop at these call sites).
    @discardableResult
    class func scheduledTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        block: @MainActor @escaping (Timer) -> Void
    ) -> Timer {
        scheduledTimer(withTimeInterval: interval, repeats: repeats) { timer in
            // Timers fire on the run loop that scheduled them (the main loop at
            // these call sites); the value never crosses threads, so the
            // sending-check escape hatch is honest here.
            nonisolated(unsafe) let t = timer
            MainActor.assumeIsolated {
                block(t)
            }
        }
    }
}

#if canImport(Glibc)
public typealias __darwin_ino64_t = UInt64

public let MAXPATHLEN: Int32 = 1024
public let F_GETPATH: Int32 = -1000

public extension stat {
    var st_mtimespec: timespec { st_mtim }
}

public extension DispatchSource {
    static func makeFileSystemObjectSource(
        fileDescriptor: Int32,
        eventMask: DispatchSource.FileSystemEvent,
        queue: DispatchQueue? = nil
    ) -> DispatchSourceUserDataAdd {
        _ = (fileDescriptor, eventMask)
        return DispatchSource.makeUserDataAddSource(queue: queue)
    }
}

/// CoreFoundation's absolute-time clock does not resolve via plain
/// `import Foundation` on Linux, so Telegram sources that consult it compile
/// against this clone. Disfavored because the Telegram source lowering adds
/// `import CoreFoundation` to files that use it, and corelibs CoreFoundation
/// exports the real function.
public typealias CFAbsoluteTime = Double

@_disfavoredOverload
public func CFAbsoluteTimeGetCurrent() -> CFAbsoluteTime {
    Date().timeIntervalSinceReferenceDate
}

// glibc 2.36+ exports its own arc4random_buf, and Glibc is visible here, so
// internal callers route through this helper instead of the ambiguous name.
private func quillRandomFill(_ buffer: UnsafeMutableRawPointer, _ length: Int) {
    let bytes = buffer.assumingMemoryBound(to: UInt8.self)
    for index in 0 ..< Swift.max(0, length) {
        bytes[index] = UInt8.random(in: UInt8.min ... UInt8.max)
    }
}

// Disfavored for the same reason as arc4random()/arc4random_uniform(_:) in
// QuillFoundation.swift: glibc 2.36+ has its own, and both can be visible.
@_disfavoredOverload
public func arc4random_buf(_ buffer: UnsafeMutableRawPointer?, _ length: Int) {
    guard let buffer else { return }
    quillRandomFill(buffer, length)
}

// @_disfavoredOverload: the Security shim also declares errSecSuccess (it is
// the canonical owner of errSec* constants), and SignalServiceKit sees BOTH —
// QuillFoundation arrives module-wide via the UIKit→QuartzCore re-export
// chain. Disfavoring this copy keeps it available to QuillFoundation-only
// consumers (the Telegram package islands) without making every
// `== errSecSuccess` in SSK ambiguous.
@_disfavoredOverload public let errSecSuccess: Int32 = 0

public func SecRandomCopyBytes(_ rnd: Any?, _ count: Int, _ bytes: UnsafeMutablePointer<UInt8>?) -> Int32 {
    _ = rnd
    guard let bytes else { return -1 }
    quillRandomFill(bytes, count)
    return errSecSuccess
}

public func SecRandomCopyBytes(_ rnd: Any?, _ count: Int, _ bytes: UnsafeMutablePointer<Int8>?) -> Int32 {
    _ = rnd
    guard let bytes else { return -1 }
    quillRandomFill(bytes, count)
    return errSecSuccess
}

@discardableResult
public func OSAtomicIncrement32(_ value: UnsafeMutablePointer<Int32>) -> Int32 {
    value.pointee += 1
    return value.pointee
}

public extension Data.ReadingOptions {
    static var mappedRead: Data.ReadingOptions { .mappedIfSafe }
}

open class NSUbiquitousKeyValueStore: NSObject, @unchecked Sendable {
    public static let `default` = NSUbiquitousKeyValueStore()
    public static let didChangeExternallyNotification = Notification.Name("NSUbiquitousKeyValueStoreDidChangeExternallyNotification")

    private let lock = NSLock()
    private var values: [String: Any] = [:]

    open func object(forKey aKey: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[aKey]
    }

    open func set(_ anObject: Any?, forKey aKey: String) {
        lock.lock()
        values[aKey] = anObject
        lock.unlock()
    }

    open func set(_ value: Bool, forKey aKey: String) {
        set(value as Any, forKey: aKey)
    }

    open func set(_ value: Double, forKey aKey: String) {
        set(value as Any, forKey: aKey)
    }

    open func set(_ value: Int64, forKey aKey: String) {
        set(value as Any, forKey: aKey)
    }

    open func data(forKey aKey: String) -> Data? {
        object(forKey: aKey) as? Data
    }

    open func string(forKey aKey: String) -> String? {
        object(forKey: aKey) as? String
    }

    open func array(forKey aKey: String) -> [Any]? {
        object(forKey: aKey) as? [Any]
    }

    open func dictionary(forKey aKey: String) -> [String: Any]? {
        object(forKey: aKey) as? [String: Any]
    }

    open func bool(forKey aKey: String) -> Bool {
        object(forKey: aKey) as? Bool ?? false
    }

    open func double(forKey aKey: String) -> Double {
        object(forKey: aKey) as? Double ?? 0
    }

    open func longLong(forKey aKey: String) -> Int64 {
        object(forKey: aKey) as? Int64 ?? 0
    }

    open func removeObject(forKey aKey: String) {
        lock.lock()
        values[aKey] = nil
        lock.unlock()
    }

    open var dictionaryRepresentation: [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    @discardableResult
    open func synchronize() -> Bool {
        true
    }
}

public func open(_ path: String, _ flags: Int32, _ mode: UInt16) -> Int32 {
    var linuxFlags = flags
    if flags & O_CREAT != 0 {
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(
                atPath: path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: mode)]
            )
        }
        linuxFlags &= ~O_CREAT
    }
    return Glibc.open(path, linuxFlags)
}

public func lseek(_ fd: Int32, _ offset: Int64, _ whence: Int32) -> Int64 {
    Int64(Glibc.lseek(fd, off_t(offset), whence))
}

@discardableResult
public func ftruncate(_ fd: Int32, _ length: Int64) -> Int32 {
    Glibc.ftruncate(fd, off_t(length))
}
#endif

public func setxattr(_ path: String, _ name: String, _ value: UnsafeRawPointer?, _ size: Int, _ flags: Int32) -> Int32 {
    _ = (path, name, value, size, flags)
    return 0
}

public func removexattr(_ path: String, _ name: String) -> Int32 {
    _ = (path, name)
    return 0
}

public func getxattr(_ path: String, _ name: String, _ value: UnsafeMutableRawPointer?, _ size: Int) -> Int {
    _ = (path, name, value, size)
    return -1
}

public final class QuillMeasurementFormatter {
    public struct UnitOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let providedUnit = UnitOptions(rawValue: 1 << 0)
        public static let naturalScale = UnitOptions(rawValue: 1 << 1)
        public static let temperatureWithoutUnit = UnitOptions(rawValue: 1 << 2)
    }

    public enum UnitStyle: Int, Sendable {
        case short
        case medium
        case long
    }

    public var locale: Locale = .current
    public var unitStyle: UnitStyle = .medium
    public var unitOptions: UnitOptions = []
    public let numberFormatter = NumberFormatter()

    public init() {}

    public func string<UnitType>(from measurement: Measurement<UnitType>) -> String where UnitType: Unit {
        let value = measurement.value
        let fractionDigits = max(0, numberFormatter.maximumFractionDigits)
        let formatted = String(format: "%.\(fractionDigits)f", value)
        if unitOptions.contains(.temperatureWithoutUnit) {
            return formatted
        }
        return "\(formatted) \(measurement.unit.symbol)"
    }
}
#endif
