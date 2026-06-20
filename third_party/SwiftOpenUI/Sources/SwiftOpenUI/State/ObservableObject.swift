import Foundation
#if canImport(Combine) && !os(Linux)
import Combine
#else
import OpenCombine
#endif

// MARK: - ObservableObject / @Published

// These ARE Combine's pair (real Combine on Apple platforms, OpenCombine on
// Linux/Web) — exactly as in Apple's stack, where ObservableObject/Published
// live in Combine and SwiftUI re-exports them. SwiftOpenUI used to declare
// its own Mirror-wired clones, which:
//   * made `Published`/`ObservableObject` ambiguous in any file importing
//     both SwiftUI and Combine (i.e. most real view-model files) — the
//     long-documented clash in docs/issues/observable-namespace-conflict.md,
//   * broke `$property` (no projectedValue, so Combine pipelines like
//     `manager.$cameras.receive(on:).assign(to: &$cameras)` could not
//     compile), and
//   * split the ecosystem into two incompatible observable worlds.
//
// One canonical pair fixes all three. Re-render wiring now subscribes to
// `objectWillChange` (Apple's own change-notification granularity) instead
// of Mirror-walking for the old `AnyPublishedProvider`; the storages below
// stay `GenerationTracked` so Phase 6/7 dependency gating still proves
// "nothing I read has changed" before skipping a rebuild.
#if canImport(Combine) && !os(Linux)
public typealias ObservableObject = Combine.ObservableObject
public typealias Published = Combine.Published
public typealias ObservableObjectPublisher = Combine.ObservableObjectPublisher
#else
public typealias ObservableObject = OpenCombine.ObservableObject
public typealias Published = OpenCombine.Published
public typealias ObservableObjectPublisher = OpenCombine.ObservableObjectPublisher
#endif

/// Subscribe to an object's `objectWillChange`. Generic so it works with any
/// `ObjectWillChangePublisher`; callers pass existentials via implicit opening.
func subscribeToObjectWillChange<T: ObservableObject>(
    _ object: T, _ onChange: @escaping () -> Void
) -> AnyCancellable {
    object.objectWillChange.sink { _ in onChange() }
}

/// Existential entry point (e.g. a `@State` value that happens to be an
/// ObservableObject). The `some` parameter opens the existential implicitly.
func subscribeOpaqueObservableObject(
    _ object: some ObservableObject,
    _ onChange: @escaping () -> Void
) -> AnyCancellable {
    subscribeToObjectWillChange(object, onChange)
}

private final class WeakViewHostReference {
    weak var host: AnyViewHost?

    init(_ host: AnyViewHost) {
        self.host = host
    }
}

private final class EnvironmentObservableObjectDependencyStorage: GenerationTracked {
    private let lock = NSLock()
    private var cancellable: AnyCancellable?
    private var hosts: [WeakViewHostReference] = []
    public private(set) var generation: UInt64 = 0

    init<ObjectType: ObservableObject>(_ object: ObjectType) {
        cancellable = subscribeToObjectWillChange(object) { [weak self] in
            self?.objectDidChange()
        }
    }

    func addHost(_ host: AnyViewHost?) {
        guard let host else { return }
        lock.lock()
        hosts.removeAll { $0.host == nil }
        if !hosts.contains(where: { $0.host === host }) {
            hosts.append(WeakViewHostReference(host))
        }
        lock.unlock()
    }

    func objectDidChange() {
        let liveHosts: [AnyViewHost]
        lock.lock()
        generation &+= 1
        hosts.removeAll { $0.host == nil }
        liveHosts = hosts.compactMap(\.host)
        lock.unlock()

        for host in liveHosts {
            host.scheduleRebuildAfterObservableObjectMutation()
        }
    }
}

private final class EnvironmentObservableObjectDependencyRegistry {
    static let shared = EnvironmentObservableObjectDependencyRegistry()

    private let lock = NSLock()
    private var storages: [ObjectIdentifier: EnvironmentObservableObjectDependencyStorage] = [:]

    func storage<ObjectType: ObservableObject>(
        for object: ObjectType
    ) -> EnvironmentObservableObjectDependencyStorage {
        let id = ObjectIdentifier(object)
        lock.lock()
        if let storage = storages[id] {
            lock.unlock()
            return storage
        }
        let storage = EnvironmentObservableObjectDependencyStorage(object)
        storages[id] = storage
        lock.unlock()
        return storage
    }
}

func recordEnvironmentObservableObjectRead(_ object: AnyObject) {
    guard let observable = object as? any ObservableObject else { return }
    let storage = EnvironmentObservableObjectDependencyRegistry.shared.storage(for: observable)
    storage.addHost(currentDependencyTrackingHost())
    recordDependencyRead(storage)
}

func wireEnvironmentObservableObjectRead(_ object: AnyObject, host: AnyViewHost?) {
    guard let observable = object as? any ObservableObject else { return }
    let storage = EnvironmentObservableObjectDependencyRegistry.shared.storage(for: observable)
    storage.addHost(host)
}

func environmentObservableObjectGeneration(_ object: AnyObject) -> UInt64? {
    guard let observable = object as? any ObservableObject else { return nil }
    let storage = EnvironmentObservableObjectDependencyRegistry.shared.storage(for: observable)
    return storage.generation
}

func notifyEnvironmentObservableObjectMutation(
    _ object: AnyObject,
    ifGenerationMatches expectedGeneration: UInt64?
) {
    guard let expectedGeneration,
          let observable = object as? any ObservableObject else { return }
    let storage = EnvironmentObservableObjectDependencyRegistry.shared.storage(for: observable)
    guard storage.generation == expectedGeneration else { return }
    storage.objectDidChange()
}

// MARK: - @ObservedObject

/// A property wrapper that observes an external ObservableObject.
/// When the object publishes a change (any @Published mutation), the owning
/// ViewHost schedules a re-render.
@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject>: AnyStateStorageProvider {
    /// Apple's `ObservedObject.Wrapper` — `$object.property` yields Bindings
    /// into the object via dynamic member lookup.
    @dynamicMemberLookup
    public struct Wrapper {
        private let object: ObjectType
        init(_ object: ObjectType) { self.object = object }

        public subscript<Subject>(
            dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>
        ) -> Binding<Subject> {
            Binding(
                get: { self.object[keyPath: keyPath] },
                set: { self.object[keyPath: keyPath] = $0 }
            )
        }
    }

    public let storage: ObservedObjectStorage<ObjectType>

    public init(wrappedValue: ObjectType) {
        storage = ObservedObjectStorage(wrappedValue)
    }

    public var wrappedValue: ObjectType {
        get { storage.access() }
        nonmutating set { storage.update(newValue) }
    }

    public var projectedValue: Wrapper { Wrapper(storage.access()) }

    public var anyStorage: AnyStateStorage { storage }
}

/// Backing storage for @ObservedObject. Conforms to AnyStateStorage so
/// installState in ViewHost can wire it automatically via Mirror, and to
/// GenerationTracked so Phase 7 input-equality gating sees object changes
/// (the generation bumps on every objectWillChange).
public class ObservedObjectStorage<ObjectType: ObservableObject>: AnyStateStorage, GenerationTracked {
    public private(set) var object: ObjectType
    private var cancellable: AnyCancellable?
    public private(set) var generation: UInt64 = 0
    public weak var host: AnyViewHost? {
        didSet { wireObjectWillChange() }
    }

    public init(_ object: ObjectType) {
        self.object = object
    }

    public func update(_ object: ObjectType) {
        self.object = object
        generation &+= 1
        wireObjectWillChange()
        host?.scheduleRebuild()
    }

    /// Read the object, recording the read so dependency gating knows this
    /// host consumed it (object-level granularity — same as Apple's
    /// objectWillChange model).
    func access() -> ObjectType {
        recordDependencyRead(self)
        return object
    }

    private func wireObjectWillChange() {
        guard host != nil else {
            cancellable = nil
            return
        }
        cancellable = subscribeToObjectWillChange(object) { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            self.host?.scheduleRebuildAfterObservableObjectMutation()
        }
    }

    public func restoreValue(from other: AnyStateStorage) {
        // ObservedObject holds a reference — no value to restore
    }
}

// MARK: - @StateObject

/// A property wrapper that creates and owns an ObservableObject with the
/// view's lifecycle. Unlike @ObservedObject (which wraps an externally-provided
/// object), @StateObject creates the object once and keeps it alive across
/// rebuilds — the same pattern as @State but for ObservableObject instances.
@propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: AnyStateStorageProvider {
    public let storage: StateObjectStorage<ObjectType>

    public init(wrappedValue: @autoclosure @escaping @MainActor () -> ObjectType) {
        storage = StateObjectStorage(factory: wrappedValue)
    }

    public var wrappedValue: ObjectType { storage.access() }

    public var projectedValue: ObservedObject<ObjectType>.Wrapper {
        ObservedObject<ObjectType>.Wrapper(storage.access())
    }

    public var anyStorage: AnyStateStorage { storage }
}

/// Backing storage for @StateObject. Creates the object lazily on first
/// access and caches it. Since this is a class (reference type), copying
/// the view struct shares the same storage — the object persists.
public class StateObjectStorage<ObjectType: ObservableObject>: AnyStateStorage, GenerationTracked {
    private let factory: @MainActor () -> ObjectType
    var _object: ObjectType?  // internal for restoreValue cross-storage adoption
    private var cancellable: AnyCancellable?
    public private(set) var generation: UInt64 = 0
    public weak var host: AnyViewHost? {
        didSet { wireObjectWillChange() }
    }

    public init(factory: @escaping @MainActor () -> ObjectType) {
        self.factory = factory
    }

    public var object: ObjectType {
        if let obj = _object { return obj }
        // The factory autoclosure is @MainActor (Apple's StateObject shape:
        // `init(wrappedValue: @autoclosure @escaping @MainActor () -> ObjectType)`).
        // First access only ever happens during state install / body
        // evaluation on the backend main loop, which IS the main thread, so
        // this assumption always holds (blessed boundary pattern).
        let obj = MainActor.assumeIsolated { factory() }
        _object = obj
        wireObjectWillChange()
        return obj
    }

    func access() -> ObjectType {
        recordDependencyRead(self)
        return object
    }

    private func wireObjectWillChange() {
        // Subscribe only to an ALREADY-created object: host attachment must
        // not force the lazy factory (Apple defers creation to first access,
        // and eager creation here would race restoreValue's adoption of the
        // previous instance — creating a second object only to discard it).
        // The `object` getter wires after first creation; restoreValue
        // re-wires after adoption.
        guard host != nil, let existing = _object else {
            cancellable = nil
            return
        }
        cancellable = subscribeToObjectWillChange(existing) { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            self.host?.scheduleRebuildAfterObservableObjectMutation()
        }
    }

    public func restoreValue(from other: AnyStateStorage) {
        // Adopt the previously-created object so the StateObject lifecycle
        // (create once, persist across rebuilds) holds even when the host
        // hands us a fresh storage instance for a re-rendered view struct.
        if let typed = other as? StateObjectStorage<ObjectType>, let existing = typed._object {
            _object = existing
            wireObjectWillChange()
        }
    }
}

// MARK: - @EnvironmentObject

/// A property wrapper that reads an ObservableObject from the environment.
/// The object must be injected by an ancestor view using `.environmentObject()`.
@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject>: AnyStateStorageProvider {
    public let storage: EnvironmentObjectStorage<ObjectType>

    public init() {
        storage = EnvironmentObjectStorage()
    }

    public var wrappedValue: ObjectType { storage.access() }

    public var projectedValue: ObservedObject<ObjectType>.Wrapper {
        ObservedObject<ObjectType>.Wrapper(storage.access())
    }

    public var anyStorage: AnyStateStorage { storage }
}

/// Backing storage for @EnvironmentObject. Resolves the object lazily
/// from the environment on first access.
public class EnvironmentObjectStorage<ObjectType: ObservableObject>: AnyStateStorage, GenerationTracked {
    private var _object: ObjectType?
    private var cancellable: AnyCancellable?
    public private(set) var generation: UInt64 = 0
    public weak var host: AnyViewHost? {
        didSet { wireObjectWillChange() }
    }

    public init() {}

    public var object: ObjectType {
        if let obj = _object { return obj }
        guard let obj = getEnvironmentObject(ObjectType.self) else {
            fatalError("No ObservableObject of type \(ObjectType.self) found in environment. Use .environmentObject() to inject it.")
        }
        _object = obj
        return obj
    }

    func access() -> ObjectType {
        recordDependencyRead(self)
        return object
    }

    private func wireObjectWillChange() {
        guard host != nil else {
            cancellable = nil
            return
        }
        cancellable = subscribeToObjectWillChange(object) { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            self.host?.scheduleRebuildAfterObservableObjectMutation()
        }
    }

    public func restoreValue(from other: AnyStateStorage) {
        // EnvironmentObject is resolved from environment — no value to restore
    }
}
