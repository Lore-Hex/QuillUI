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

    func value(forKey key: String) -> Any? {
        _ = key
        return nil
    }

    func setValue(_ value: Any?, forKey key: String) {
        _ = (value, key)
    }

    func setValue(_ value: Any?, forKeyPath keyPath: String) {
        _ = (value, keyPath)
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

public func arc4random_buf(_ buffer: UnsafeMutableRawPointer?, _ length: Int) {
    guard let buffer else { return }
    let bytes = buffer.assumingMemoryBound(to: UInt8.self)
    for index in 0 ..< Swift.max(0, length) {
        bytes[index] = UInt8.random(in: UInt8.min ... UInt8.max)
    }
}

public let errSecSuccess: Int32 = 0

public func SecRandomCopyBytes(_ rnd: Any?, _ count: Int, _ bytes: UnsafeMutablePointer<UInt8>?) -> Int32 {
    _ = rnd
    guard let bytes else { return -1 }
    arc4random_buf(bytes, count)
    return errSecSuccess
}

public func SecRandomCopyBytes(_ rnd: Any?, _ count: Int, _ bytes: UnsafeMutablePointer<Int8>?) -> Int32 {
    _ = rnd
    guard let bytes else { return -1 }
    arc4random_buf(bytes, count)
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

    private var values: [String: Any] = [:]

    open func object(forKey aKey: String) -> Any? {
        values[aKey]
    }

    open func set(_ anObject: Any?, forKey aKey: String) {
        values[aKey] = anObject
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
