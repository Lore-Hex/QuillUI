import Foundation

/// A key for an environment value.
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public protocol DynamicProperty {
    mutating func update()
}

public extension DynamicProperty {
    mutating func update() {}
}

/// A reference-typed environment object together with the structural scope
/// that injected it. Backends retain these captures across body rebuilds so
/// same-typed objects installed by sibling views cannot replace one another.
public struct EnvironmentObjectCapture: @unchecked Sendable {
    public let object: AnyObject
    public let scope: String?

    public init(object: AnyObject, scope: String? = nil) {
        self.object = object
        self.scope = scope
    }
}

/// A collection of environment values propagated down the view tree.
public struct EnvironmentValues: @unchecked Sendable {
    private var storage: [ObjectIdentifier: Any] = [:]
    private var objects: [ObjectIdentifier: EnvironmentObjectCapture] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(_ key: K.Type) -> K.Value {
        get { storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }

    /// Create a copy with a value set for a key path.
    public func setting<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, to value: V) -> EnvironmentValues {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }

    /// Store an object by its static type. The constraint is `AnyObject`
    /// rather than `ObservableObject` so this covers both the legacy
    /// `@EnvironmentObject` path (Combine-style `ObservableObject`) and
    /// the newer `@Environment(SomeClass.self)` path (any reference type,
    /// typically an `@Observable` class).
    public mutating func setObject<T: AnyObject>(_ object: T, scope: String? = nil) {
        let id = ObjectIdentifier(T.self)
        objects[id] = EnvironmentObjectCapture(object: object, scope: scope)
        EnvironmentObjectRegistry.shared.setObject(object, id: id, scope: scope)
    }

    /// Retrieve an object previously stored by `setObject`.
    public func getObject<T: AnyObject>(_ type: T.Type) -> T? {
        let id = ObjectIdentifier(type)
        return objects[id]?.object as? T
            ?? EnvironmentObjectRegistry.shared.object(id: id, scope: nil) as? T
    }

    /// Type-erased object insertion for the environment-read tracker
    /// rebuild path. Backends use this to re-push objects that body
    /// previously read via `@Environment(SomeClass.self)` into a fresh
    /// environment before re-running the body on rebuild. The
    /// `ObjectIdentifier` is the key returned by
    /// `endEnvironmentReadTracking()`; the `AnyObject` is the same
    /// reference body originally read.
    public mutating func setObjectByID(
        _ id: ObjectIdentifier,
        _ object: AnyObject,
        scope: String? = nil
    ) {
        objects[id] = EnvironmentObjectCapture(object: object, scope: scope)
        EnvironmentObjectRegistry.shared.setObject(object, id: id, scope: scope)
    }

    /// Store the latest globally injected object for `id` when one exists,
    /// falling back to a previously captured object. Backends use this during
    /// ViewHost rebuilds so a child host does not pin an object that an
    /// ancestor later replaced, such as an unauthenticated client swapped for
    /// an authenticated one after app startup.
    public mutating func setLatestObjectByID(
        _ id: ObjectIdentifier,
        fallback object: AnyObject,
        scope: String? = nil
    ) {
        setObjectByID(
            id,
            EnvironmentObjectRegistry.shared.object(id: id, scope: scope) ?? object,
            scope: scope
        )
    }

    /// Refresh every captured injected object from the global environment
    /// registry when an ancestor has since replaced it. Deferred callbacks such
    /// as NavigationStack destination factories capture an EnvironmentValues
    /// snapshot at render time; this keeps those callbacks from pinning stale
    /// app-wide objects like the current account client.
    public mutating func refreshInjectedObjectsFromRegistry() {
        for (id, capture) in objects {
            setLatestObjectByID(id, fallback: capture.object, scope: capture.scope)
        }
    }

    internal func objectScope(for id: ObjectIdentifier) -> String? {
        objects[id]?.scope
    }
}

public struct DefaultMinListRowHeightKey: EnvironmentKey {
    public static let defaultValue = 44
}

public extension EnvironmentValues {
    var defaultMinListRowHeight: Int {
        get { self[DefaultMinListRowHeightKey.self] }
        set { self[DefaultMinListRowHeightKey.self] = newValue }
    }
}

private final class EnvironmentObjectRegistry: @unchecked Sendable {
    static let shared = EnvironmentObjectRegistry()

    private final class WeakObjectBox {
        weak var object: AnyObject?

        init(_ object: AnyObject) {
            self.object = object
        }
    }

    private struct ScopedKey: Hashable {
        let typeID: ObjectIdentifier
        let scope: String
    }

    private let lock = NSLock()
    private var objects: [ObjectIdentifier: WeakObjectBox] = [:]
    private var scopedObjects: [ScopedKey: WeakObjectBox] = [:]

    func setObject(_ object: AnyObject, id: ObjectIdentifier, scope: String?) {
        lock.lock()
        if let scope {
            scopedObjects[ScopedKey(typeID: id, scope: scope)] = WeakObjectBox(object)
        } else {
            objects[id] = WeakObjectBox(object)
        }
        lock.unlock()
    }

    func object(id: ObjectIdentifier, scope: String?) -> AnyObject? {
        lock.lock()
        defer { lock.unlock() }
        if let scope {
            let key = ScopedKey(typeID: id, scope: scope)
            guard let object = scopedObjects[key]?.object else {
                scopedObjects.removeValue(forKey: key)
                return nil
            }
            return object
        }
        guard let object = objects[id]?.object else {
            objects.removeValue(forKey: id)
            return nil
        }
        return object
    }
}

// MARK: - Environment-read tracker
//
// The thread-local read tracker captures every `@Environment(Type.self)`
// lookup that succeeds during a body evaluation. ViewHosts use the
// tracker to remember which injected objects descendant views consumed
// during their last render, so the same objects can be re-pushed into
// a fresh environment before re-running body on rebuild.
//
// Without this mechanism, an env-modifier (`.environment(model)`) that
// lives INSIDE a parent's body — i.e. between two ViewHosts in the
// render tree — pushes the object only during its renderer's
// execution. The inner ViewHost's `capturedEnvironment` snapshot
// (taken at init time, BEFORE the modifier ran) misses the object.
// On rebuild, restoring the captured snapshot leaves the env without
// the object, and the inner body's `@Environment(Type.self).wrappedValue`
// fatal-errors with "lookup failed".
//
// The tracker fixes this by recording each successful object lookup
// during body evaluation, so the ViewHost has the complete set of
// injected objects body needs and can re-push them on subsequent
// rebuilds.
//
// Stack-based so nested reactive hosts can track independently while still
// propagating descendant reads back to their parent render session.
private var _envReadTrackerStack: [[ObjectIdentifier: EnvironmentObjectCapture]] = []

/// Begin a fresh round of environment-read tracking. Pairs with
/// `endEnvironmentReadTracking()` after body evaluation. Backends call
/// this around `buildBody` so reads of `@Environment(Type.self)`
/// performed by descendants are recorded.
public func beginEnvironmentReadTracking() {
    _envReadTrackerStack.append([:])
}

/// Finish the current round and return the recorded reads, or nil if
/// no round was active.
private func endEnvironmentObjectCaptureTracking() -> [ObjectIdentifier: EnvironmentObjectCapture]? {
    guard !_envReadTrackerStack.isEmpty else { return nil }
    let result = _envReadTrackerStack.removeLast()
    if !_envReadTrackerStack.isEmpty {
        let parentIndex = _envReadTrackerStack.count - 1
        for (typeID, capture) in result {
            _envReadTrackerStack[parentIndex][typeID] = capture
        }
    }
    return result
}

/// Finish tracking while preserving each object's structural injection scope.
/// Reactive backends use this form when rebuilding hosts independently.
public func endScopedEnvironmentReadTracking() -> [ObjectIdentifier: EnvironmentObjectCapture]? {
    endEnvironmentObjectCaptureTracking()
}

/// Finish tracking using the original object-only result shape.
public func endEnvironmentReadTracking() -> [ObjectIdentifier: AnyObject]? {
    endEnvironmentObjectCaptureTracking()?.mapValues(\.object)
}

/// Record a successful `@Environment(Type.self)` lookup against the
/// active tracker, if any. No-op when no tracking round is active.
internal func recordEnvironmentRead(typeID: ObjectIdentifier, object: AnyObject) {
    guard !_envReadTrackerStack.isEmpty else { return }
    let index = _envReadTrackerStack.count - 1
    _envReadTrackerStack[index][typeID] = EnvironmentObjectCapture(
        object: object,
        scope: getCurrentEnvironment().objectScope(for: typeID)
    )
    recordEnvironmentObservableObjectRead(object)
}

// MARK: - Thread-local environment for render pass

private enum EnvironmentTaskLocal {
    @TaskLocal static var values: EnvironmentValues?
}

public func withSynchronousTaskEnvironment<T>(
    _ env: EnvironmentValues,
    operation: () throws -> T
) rethrows -> T {
    try EnvironmentTaskLocal.$values.withValue(env) {
        try operation()
    }
}

public func withTaskEnvironment<T>(
    _ env: EnvironmentValues,
    operation: () async -> T
) async -> T {
    await EnvironmentTaskLocal.$values.withValue(env) {
        await operation()
    }
}

#if canImport(Glibc) || canImport(Darwin)
private let _envKey: pthread_key_t = {
    var key = pthread_key_t()
    pthread_key_create(&key, nil)
    return key
}()

/// Set the current environment values for the render pass.
public func setCurrentEnvironment(_ env: EnvironmentValues?) {
    if let env = env {
        let box = Unmanaged.passRetained(EnvironmentBox(env)).toOpaque()
        if let prev = pthread_getspecific(_envKey) {
            Unmanaged<EnvironmentBox>.fromOpaque(prev).release()
        }
        pthread_setspecific(_envKey, box)
    } else {
        if let prev = pthread_getspecific(_envKey) {
            Unmanaged<EnvironmentBox>.fromOpaque(prev).release()
        }
        pthread_setspecific(_envKey, nil)
    }
}

/// Get the current environment values (render-time only).
public func getCurrentEnvironment() -> EnvironmentValues {
    if let taskEnvironment = EnvironmentTaskLocal.values {
        return taskEnvironment
    }
    guard let ptr = pthread_getspecific(_envKey) else { return EnvironmentValues() }
    return Unmanaged<EnvironmentBox>.fromOpaque(ptr).takeUnretainedValue().values
}
#elseif canImport(WinSDK)
import WinSDK

private let _tlsIndex: DWORD = TlsAlloc()

public func setCurrentEnvironment(_ env: EnvironmentValues?) {
    if let env = env {
        let box = Unmanaged.passRetained(EnvironmentBox(env)).toOpaque()
        if let prev = TlsGetValue(_tlsIndex) {
            Unmanaged<EnvironmentBox>.fromOpaque(prev).release()
        }
        TlsSetValue(_tlsIndex, box)
    } else {
        if let prev = TlsGetValue(_tlsIndex) {
            Unmanaged<EnvironmentBox>.fromOpaque(prev).release()
        }
        TlsSetValue(_tlsIndex, nil)
    }
}

public func getCurrentEnvironment() -> EnvironmentValues {
    if let taskEnvironment = EnvironmentTaskLocal.values {
        return taskEnvironment
    }
    guard let ptr = TlsGetValue(_tlsIndex) else { return EnvironmentValues() }
    return Unmanaged<EnvironmentBox>.fromOpaque(ptr).takeUnretainedValue().values
}
#else
// WASI / other platforms — single-threaded, use a simple global.
private var _currentEnvironment: EnvironmentValues?

public func setCurrentEnvironment(_ env: EnvironmentValues?) {
    _currentEnvironment = env
}

public func getCurrentEnvironment() -> EnvironmentValues {
    EnvironmentTaskLocal.values ?? _currentEnvironment ?? EnvironmentValues()
}
#endif

/// Box for storing EnvironmentValues in thread-local storage.
private class EnvironmentBox {
    let values: EnvironmentValues
    init(_ values: EnvironmentValues) { self.values = values }
}

// MARK: - Presentation-dismiss context
//
// Backends use this stack to carry the active sheet/popover dismissal closure
// across native callback boundaries. It complements `EnvironmentValues.dismiss`:
// callbacks already restore their captured environment, but presentation content
// can be hosted and rebuilt independently of the native presentation modifier.
// Capturing this context at control registration time keeps legacy
// `@Environment(\.presentationMode).wrappedValue.dismiss()` wired to the
// enclosing presentation without app-specific source changes.

private var _presentationDismissActionStack: [() -> Void] = []

private final class PresentationDismissTaskContext: @unchecked Sendable {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }
}

private enum PresentationDismissTaskLocal {
    @TaskLocal static var context: PresentationDismissTaskContext?
}

public func swiftOpenUIWithPresentationDismissAction<T>(
    _ action: @escaping () -> Void,
    perform body: () -> T
) -> T {
    let context = PresentationDismissTaskContext(action: action)
    return PresentationDismissTaskLocal.$context.withValue(context) {
        _presentationDismissActionStack.append(action)
        defer { _ = _presentationDismissActionStack.popLast() }
        return body()
    }
}

public func swiftOpenUICurrentPresentationDismissAction() -> (() -> Void)? {
    PresentationDismissTaskLocal.context?.action ?? _presentationDismissActionStack.last
}

/// Resolve the dismiss handler captured in an environment snapshot, falling
/// back to the active presentation context while presentation content renders.
/// Native backends use this when registering controls so a child `Task` can
/// still dismiss its sheet after the synchronous control callback returns.
public func swiftOpenUIResolvePresentationDismissAction(
    in environment: EnvironmentValues
) -> (() -> Void)? {
    environment.dismiss.handler ?? swiftOpenUICurrentPresentationDismissAction()
}

private func swiftOpenUIDismissDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else {
        return
    }
    if let data = ("[SwiftOpenUI] " + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

// MARK: - @Environment property wrapper

/// Reads a value from the current environment at render time.
///
/// Two initializers are supported, matching SwiftUI:
///
/// - `@Environment(\.colorScheme)` — keyPath-based access to built-in
///   environment values keyed by `EnvironmentKey`.
/// - `@Environment(SomeClass.self)` — type-based access to a reference
///   object (typically `@Observable`) that an ancestor injected via
///   `.environment(object)`. Matches SwiftUI's `@Environment(T.self)`
///   introduced alongside the Observation framework.
/// Type-erased marker for `Environment<Value>` instances that read
/// an injected reference object by type (the
/// `@Environment(SomeClass.self)` form). The view-host's reactive-
/// property detection checks for this so that views with only
/// injected-object @Environment properties (no @State, no directly-
/// stored @Observable) still get wrapped in `withObservationTracking`
/// for their body evaluation — otherwise property reads on the
/// injected object don't register with Observation and mutations
/// never trigger rebuilds.
public protocol AnyObjectInjectionEnvironment {
    func wireInjectedObject(to host: AnyViewHost?)
}

private final class EnvironmentInjectedObjectStorage {
    private let lock = NSLock()
    private var object: AnyObject?

    func store(_ object: AnyObject) {
        lock.lock()
        self.object = object
        lock.unlock()
    }

    func load() -> AnyObject? {
        lock.lock()
        defer { lock.unlock() }
        return object
    }
}

@propertyWrapper
public struct Environment<Value> {
    /// How the wrapper reads its value at render time. A keyPath reads
    /// from `EnvironmentValues`; the closure variant looks up an
    /// injected reference object, capturing its `AnyObject` constraint
    /// from the constrained init.
    private enum Reader {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case injectedObject(() -> Value)
    }

    private let reader: Reader

    /// True when this wrapper was constructed via
    /// `init(_ type: Value.Type)` (the object-injection form) rather
    /// than the keyPath form. Read by the view-host's reactive-
    /// property detection.
    internal var isInjectedObject: Bool {
        if case .injectedObject = reader { return true }
        return false
    }

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.reader = .keyPath(keyPath)
    }

    /// Look up an injected reference object by type. Matches SwiftUI's
    /// `@Environment(SomeClass.self)` usage for `@Observable` classes.
    ///
    /// The object must have been injected by an ancestor via
    /// `.environment(object)`; otherwise `wrappedValue` traps with a
    /// diagnostic message, because silently returning a default would
    /// hide a programmer error that SwiftUI callers expect to surface.
    public init(_ type: Value.Type) where Value: AnyObject {
        // Capturing `type` in the closure lets us reference the
        // `AnyObject` constraint at read time without propagating it
        // to the outer Environment<Value> struct.
        let storage = EnvironmentInjectedObjectStorage()
        self.reader = .injectedObject {
            if let object = getCurrentEnvironment().getObject(type) {
                storage.store(object)
                // Record the read so the enclosing ViewHost can re-push
                // this object into env on rebuild, even if the
                // `.environment(object)` modifier that originally pushed
                // it lives inside a parent's body (between two ViewHosts
                // in the render tree) and wouldn't otherwise be
                // guaranteed to re-run before this read fires again.
                recordEnvironmentRead(typeID: ObjectIdentifier(type), object: object)
                return object
            }
            if let object = storage.load() as? Value {
                return object
            }
            fatalError(
                "@Environment(\(type).self) lookup failed — no object of this type was injected. " +
                "Call `.environment(object)` on an ancestor view."
            )
        }
    }

    public var wrappedValue: Value {
        switch reader {
        case .keyPath(let keyPath):
            return getCurrentEnvironment()[keyPath: keyPath]
        case .injectedObject(let read):
            return read()
        }
    }
}

extension Environment: DynamicProperty {}

/// `Environment<Value>` is an object-injection environment only when
/// its reader was constructed via `init(_ type: Value.Type)`. Every
/// instance conforms, but the runtime check on `isInjectedObject`
/// distinguishes the two constructors.
extension Environment: AnyObjectInjectionEnvironment {
    public func wireInjectedObject(to host: AnyViewHost?) {
        guard isInjectedObject else { return }
        guard let object = wrappedValue as? AnyObject else { return }
        wireEnvironmentObservableObjectRead(object, host: host)
    }
}

// MARK: - Environment object lookup

/// Retrieve an injected reference object from the current thread-local
/// environment by type. Returns nil if none was injected.
public func getEnvironmentObject<T: AnyObject>(_ type: T.Type) -> T? {
    getCurrentEnvironment().getObject(type)
}

// MARK: - Built-in keys

/// SwiftUI-compatible color scheme enum.
public enum ColorScheme: String, Equatable {
    case light
    case dark
}

/// Color scheme key.
public struct ColorSchemeKey: EnvironmentKey {
    public static let defaultValue: ColorScheme = .light
}

extension EnvironmentValues {
    public var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
}


/// Environment key describing whether descendant controls are enabled.
public struct IsEnabledKey: EnvironmentKey {
    public static let defaultValue: Bool = true
}

extension EnvironmentValues {
    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }
}

/// A callable action that opens a window by its identifier.
public struct OpenWindowAction {
    let handler: (String) -> Void
    let valueHandler: (String, Any) -> Void

    public init(
        handler: @escaping (String) -> Void = { _ in },
        valueHandler: @escaping (String, Any) -> Void = { _, _ in }
    ) {
        self.handler = handler
        self.valueHandler = valueHandler
    }

    /// Open the window with the given identifier.
    public func callAsFunction(id: String) {
        handler(id)
    }

    /// Open the value-based window group registered for this value's type.
    public func callAsFunction<Value>(value: Value) {
        valueHandler(quillOpenWindowValueTypeKey(for: Value.self), value)
    }

    /// Open the value-based window group registered for the given id and
    /// value type.
    public func callAsFunction<Value>(id: String, value: Value) {
        valueHandler(quillOpenWindowValueTypeKey(id: id, for: Value.self), value)
    }
}

/// Environment key for the open-window action.
public struct OpenWindowKey: EnvironmentKey {
    public static let defaultValue: OpenWindowAction = OpenWindowAction()
}

extension EnvironmentValues {
    public var openWindow: OpenWindowAction {
        get { self[OpenWindowKey.self] }
        set { self[OpenWindowKey.self] = newValue }
    }
}

/// A callable action that dismisses the current sheet or dialog.
public struct DismissAction {
    let handler: (() -> Void)?
    let debugName: String

    public init(handler: (() -> Void)? = nil, debugName: String = "custom") {
        self.handler = handler
        self.debugName = debugName
    }

    /// Dismiss the enclosing presentation (sheet, alert, etc.).
    public func callAsFunction() {
        if let handler {
            swiftOpenUIDismissDebugLog("dismiss handler \(debugName)")
            handler()
            return
        }
        #if os(Linux)
        if let fallback = swiftOpenUICurrentPresentationDismissAction() {
            swiftOpenUIDismissDebugLog("dismiss presentation fallback")
            fallback()
        } else {
            swiftOpenUIDismissDebugLog("dismiss missing presentation context")
        }
        #endif
    }
}

/// Environment key for the dismiss action.
public struct DismissKey: EnvironmentKey {
    public static let defaultValue: DismissAction = DismissAction()
}

extension EnvironmentValues {
    public var dismiss: DismissAction {
        get { self[DismissKey.self] }
        set { self[DismissKey.self] = newValue }
    }
}

/// Internal presentation context used by backends to distinguish root
/// window navigation chrome from navigation chrome inside sheets.
public struct IsPresentedInSheetKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var isPresentedInSheet: Bool {
        get { self[IsPresentedInSheetKey.self] }
        set { self[IsPresentedInSheetKey.self] = newValue }
    }
}
