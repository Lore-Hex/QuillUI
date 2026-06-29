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

public typealias kern_return_t = Int32
public let KERN_SUCCESS: kern_return_t = 0
public typealias AutoreleasingUnsafeMutablePointer<Pointee> = UnsafeMutablePointer<Pointee>

public struct mach_timebase_info_data_t: Sendable {
    public var numer: UInt32
    public var denom: UInt32

    public init(numer: UInt32 = 0, denom: UInt32 = 0) {
        self.numer = numer
        self.denom = denom
    }
}

public func mach_timebase_info() -> mach_timebase_info_data_t {
    mach_timebase_info_data_t()
}

@discardableResult
public func mach_timebase_info(_ info: UnsafeMutablePointer<mach_timebase_info_data_t>?) -> kern_return_t {
    info?.pointee = mach_timebase_info_data_t(numer: 1, denom: 1)
    return KERN_SUCCESS
}

public func mach_absolute_time() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
}

public extension NSString {
    /// AppKit text components use this macOS enumeration mode to move across
    /// caret positions. swift-corelibs currently lacks the symbol; preserving
    /// the bit lets the call sites compile and keeps the option inert where the
    /// Linux Foundation implementation does not consume it.
    static let quillByCaretPositionsRawValue: UInt = 1 << 13

    static var quillByCaretPositionsOption: EnumerationOptions {
        EnumerationOptions(rawValue: quillByCaretPositionsRawValue)
    }

    /// Clone of Apple's `NSString.localizedStringWithFormat(_:_:)`, absent from
    /// swift-corelibs-foundation. Formats the arguments into `format` (the
    /// Apple version is current-locale-aware; locale only affects numeric
    /// formatting, which the cases we hit so far don't use).
    static func localizedStringWithFormat(_ format: NSString, _ args: CVarArg...) -> NSString {
        NSString(string: String(format: format as String, arguments: args))
    }
}

public extension NSString.EnumerationOptions {
    static let byCaretPositions = NSString.quillByCaretPositionsOption
}

public extension NSMutableString {
    func appendFormat(_ format: String, _ args: CVarArg...) {
        append(String(format: format, arguments: args))
    }
}

public extension NSKeyedUnarchiver {
    class func unarchivedArrayOfObjects<DecodedObjectType>(
        ofClass cls: DecodedObjectType.Type,
        from data: Data
    ) throws -> [DecodedObjectType]? where DecodedObjectType: NSObject {
        let decoded = try unarchivedObject(ofClasses: [NSArray.self, cls], from: data)
        return decoded as? [DecodedObjectType]
    }

    class func unarchivedDictionary<DecodedKeyType, DecodedObjectType>(
        ofKeyClass keyCls: DecodedKeyType.Type,
        objectClass valueCls: DecodedObjectType.Type,
        from data: Data
    ) throws -> [DecodedKeyType: DecodedObjectType]?
    where DecodedKeyType: NSObject, DecodedObjectType: NSObject {
        let decoded = try unarchivedObject(ofClasses: [NSDictionary.self, keyCls, valueCls], from: data)
        return decoded as? [DecodedKeyType: DecodedObjectType]
    }
}

public extension NSString {
    struct EncodingDetectionOptionsKey: Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public static let suggestedEncodingsKey = EncodingDetectionOptionsKey(rawValue: "NSSuggestedEncodingsKey")
        public static let likelyLanguageKey = EncodingDetectionOptionsKey(rawValue: "NSLikelyLanguageKey")
        public static let allowLossyKey = EncodingDetectionOptionsKey(rawValue: "NSAllowLossyKey")
        public static let useOnlySuggestedEncodingsKey = EncodingDetectionOptionsKey(rawValue: "NSUseOnlySuggestedEncodingsKey")
    }

    static func stringEncoding(
        for data: Data,
        encodingOptions: [EncodingDetectionOptionsKey: Any]? = nil,
        convertedString: UnsafeMutablePointer<NSString?>?,
        usedLossyConversion: UnsafeMutablePointer<ObjCBool>?
    ) -> UInt {
        _ = encodingOptions
        let string = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
        convertedString?.pointee = string as NSString
        usedLossyConversion?.pointee = false
        return String.Encoding.utf8.rawValue
    }
}

// swift-corelibs-foundation marks the old NSStringEncoding constants as
// unavailable aliases to `String.Encoding`. AppKit-era macOS app source still
// uses the Apple UInt constants directly, e.g. CodeEdit's file-encoding model.
// Re-export the Apple raw values from QuillFoundation so Linux builds can keep
// that source shape unchanged.
public let NSASCIIStringEncoding: UInt = String.Encoding.ascii.rawValue
public let NSNEXTSTEPStringEncoding: UInt = 2
public let NSJapaneseEUCStringEncoding: UInt = 3
public let NSUTF8StringEncoding: UInt = String.Encoding.utf8.rawValue
public let NSISOLatin1StringEncoding: UInt = String.Encoding.isoLatin1.rawValue
public let NSSymbolStringEncoding: UInt = 6
public let NSNonLossyASCIIStringEncoding: UInt = String.Encoding.nonLossyASCII.rawValue
public let NSShiftJISStringEncoding: UInt = String.Encoding.shiftJIS.rawValue
public let NSISOLatin2StringEncoding: UInt = String.Encoding.isoLatin2.rawValue
public let NSUnicodeStringEncoding: UInt = String.Encoding.unicode.rawValue
public let NSUTF16StringEncoding: UInt = String.Encoding.utf16.rawValue
public let NSUTF16BigEndianStringEncoding: UInt = String.Encoding.utf16BigEndian.rawValue
public let NSUTF16LittleEndianStringEncoding: UInt = String.Encoding.utf16LittleEndian.rawValue
public let NSUTF32StringEncoding: UInt = String.Encoding.utf32.rawValue
public let NSUTF32BigEndianStringEncoding: UInt = String.Encoding.utf32BigEndian.rawValue
public let NSUTF32LittleEndianStringEncoding: UInt = String.Encoding.utf32LittleEndian.rawValue

public extension URL {
    static var libraryDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
    }

    struct BookmarkCreationOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let minimalBookmark = BookmarkCreationOptions(rawValue: 1 << 0)
        public static let suitableForBookmarkFile = BookmarkCreationOptions(rawValue: 1 << 1)
        public static let withSecurityScope = BookmarkCreationOptions(rawValue: 1 << 2)
        public static let securityScopeAllowOnlyReadAccess = BookmarkCreationOptions(rawValue: 1 << 3)
    }

    struct BookmarkResolutionOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let withoutUI = BookmarkResolutionOptions(rawValue: 1 << 0)
        public static let withoutMounting = BookmarkResolutionOptions(rawValue: 1 << 1)
        public static let withSecurityScope = BookmarkResolutionOptions(rawValue: 1 << 2)
    }

    func bookmarkData(
        options: BookmarkCreationOptions = [],
        includingResourceValuesForKeys keys: Set<URLResourceKey>? = nil,
        relativeTo url: URL? = nil
    ) throws -> Data {
        _ = (options, keys, url)
        return Data(absoluteString.utf8)
    }

    init(
        resolvingBookmarkData data: Data,
        options: BookmarkResolutionOptions = [],
        relativeTo url: URL? = nil,
        bookmarkDataIsStale isStale: inout Bool
    ) throws {
        _ = options
        isStale = false
        let string = String(data: data, encoding: .utf8) ?? ""
        if let resolved = URL(string: string, relativeTo: url) {
            self = resolved
        } else {
            self = URL(fileURLWithPath: string)
        }
    }

    func startAccessingSecurityScopedResource() -> Bool { true }
    func stopAccessingSecurityScopedResource() {}
}

public extension NSDictionary {
    convenience init?(contentsOf url: URL, error outError: AutoreleasingUnsafeMutablePointer<NSError?>?) {
        do {
            let data = try Data(contentsOf: url)
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = object as? [AnyHashable: Any] else {
                outError?.pointee = NSError(
                    domain: NSCocoaErrorDomain,
                    code: CocoaError.fileReadCorruptFile.rawValue
                )
                return nil
            }
            self.init(dictionary: dictionary)
        } catch {
            outError?.pointee = error as NSError
            return nil
        }
    }

    convenience init?(contentsOf url: URL, error: ()) {
        self.init(contentsOf: url, error: nil as AutoreleasingUnsafeMutablePointer<NSError?>?)
    }

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

public extension NSIndexPath {
    convenience init(row: Int, section: Int) {
        self.init(indexes: [section, row], length: 2)
    }

    convenience init(item: Int, section: Int) {
        self.init(indexes: [section, item], length: 2)
    }

    var row: Int { length >= 2 ? index(atPosition: 1) : 0 }
    var item: Int { row }
    var section: Int { length >= 1 ? index(atPosition: 0) : 0 }
}

public extension FileManager {
    /// Clone of Apple's app-group container API, absent from
    /// swift-corelibs-foundation. Linux has no entitlement-backed app groups;
    /// use a deterministic user data directory so cross-process helpers can
    /// still share files by group identifier.
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        let trimmed = groupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let root: URL
        if let override = ProcessInfo.processInfo.environment["QUILLUI_APP_GROUP_CONTAINER_ROOT"], !override.isEmpty {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdgDataHome.isEmpty {
            root = URL(fileURLWithPath: xdgDataHome, isDirectory: true)
                .appendingPathComponent("QuillUI", isDirectory: true)
                .appendingPathComponent("AppGroups", isDirectory: true)
        } else {
            root = homeDirectoryForCurrentUser
                .appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true)
                .appendingPathComponent("QuillUI", isDirectory: true)
                .appendingPathComponent("AppGroups", isDirectory: true)
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let safeIdentifier = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }.map(String.init).joined()
        let url = root.appendingPathComponent(safeIdentifier, isDirectory: true)
        try? createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func trashItem(
        at url: URL,
        resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        let trashRoot = homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("Trash", isDirectory: true)
            .appendingPathComponent("files", isDirectory: true)
        try createDirectory(at: trashRoot, withIntermediateDirectories: true)

        let destination = trashRoot.appendingPathComponent(url.lastPathComponent)
        let finalDestination = uniqueTrashDestination(for: destination)
        try moveItem(at: url, to: finalDestination)
        outResultingURL?.pointee = finalDestination as NSURL
    }

    private func uniqueTrashDestination(for destination: URL) -> URL {
        guard fileExists(atPath: destination.path) else { return destination }
        let base = destination.deletingPathExtension()
        let pathExtension = destination.pathExtension
        for index in 1...10_000 {
            let candidateBase = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent) \(index)")
            let candidate = pathExtension.isEmpty
                ? candidateBase
                : candidateBase.appendingPathExtension(pathExtension)
            if !fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return destination.deletingLastPathComponent()
            .appendingPathComponent("\(destination.lastPathComponent)-\(UUID().uuidString)")
    }
}

public typealias NSErrorPointer = UnsafeMutablePointer<NSError?>?

public protocol NSFilePresenter: AnyObject {
    var presentedItemURL: URL? { get }
    var presentedItemOperationQueue: OperationQueue { get }
    func presentedItemDidChange()
}

public extension NSFilePresenter {
    func presentedItemDidChange() {}
}

public final class NSFileCoordinator {
    public struct WritingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let forDeleting = WritingOptions(rawValue: 1 << 0)
        public static let forMoving = WritingOptions(rawValue: 1 << 1)
        public static let forMerging = WritingOptions(rawValue: 1 << 4)
        public static let forReplacing = WritingOptions(rawValue: 1 << 5)
        public static let contentIndependentMetadataOnly = WritingOptions(rawValue: 1 << 4)
    }

    public struct ReadingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let withoutChanges = ReadingOptions(rawValue: 1 << 0)
        public static let resolvesSymbolicLink = ReadingOptions(rawValue: 1 << 1)
        public static let immediatelyAvailableMetadataOnly = ReadingOptions(rawValue: 1 << 2)
    }

    private static let presentersLock = NSLock()
    nonisolated(unsafe) private static var presenters = [ObjectIdentifier: any NSFilePresenter]()

    public init(filePresenter: (any NSFilePresenter)? = nil) {
        if let filePresenter {
            Self.addFilePresenter(filePresenter)
        }
    }

    public static func addFilePresenter(_ filePresenter: any NSFilePresenter) {
        presentersLock.lock()
        presenters[ObjectIdentifier(filePresenter)] = filePresenter
        presentersLock.unlock()
    }

    public static func removeFilePresenter(_ filePresenter: any NSFilePresenter) {
        presentersLock.lock()
        presenters.removeValue(forKey: ObjectIdentifier(filePresenter))
        presentersLock.unlock()
    }

    public func coordinate(
        writingItemAt url: URL,
        options: WritingOptions = [],
        error outError: NSErrorPointer = nil,
        byAccessor accessor: (URL) -> Void
    ) {
        accessor(url)
    }

    public func coordinate(
        readingItemAt url: URL,
        options: ReadingOptions = [],
        error outError: NSErrorPointer = nil,
        byAccessor accessor: (URL) -> Void
    ) {
        accessor(url)
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
    typealias FileSystemObject = DispatchSourceUserDataAdd

    static func makeFileSystemObjectSource(
        fileDescriptor: Int32,
        eventMask: DispatchSource.FileSystemEvent,
        queue: DispatchQueue? = nil
    ) -> DispatchSourceUserDataAdd {
        _ = (fileDescriptor, eventMask)
        return DispatchSource.makeUserDataAddSource(queue: queue)
    }
}

public typealias DispatchSourceFileSystemObject = DispatchSourceUserDataAdd

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

public func setxattr(
    _ path: UnsafePointer<CChar>?,
    _ name: String,
    _ value: UnsafeRawPointer?,
    _ size: Int,
    _ position: UInt32,
    _ options: Int32
) -> Int32 {
    let stringPath = path.map(String.init(cString:)) ?? ""
    _ = position
    return setxattr(stringPath, name, value, size, options)
}

public func removexattr(_ path: UnsafePointer<CChar>?, _ name: String, _ options: Int32) -> Int32 {
    let stringPath = path.map(String.init(cString:)) ?? ""
    _ = options
    return removexattr(stringPath, name)
}

public func getxattr(
    _ path: UnsafePointer<CChar>?,
    _ name: String,
    _ value: UnsafeMutableRawPointer?,
    _ size: Int,
    _ position: UInt32,
    _ options: Int32
) -> Int {
    let stringPath = path.map(String.init(cString:)) ?? ""
    _ = (position, options)
    return getxattr(stringPath, name, value, size)
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
