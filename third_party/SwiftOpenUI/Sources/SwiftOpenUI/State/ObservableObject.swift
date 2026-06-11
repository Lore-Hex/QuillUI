import Foundation
#if canImport(Combine)
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
#if canImport(Combine)
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

    public var wrappedValue: ObjectType { storage.access() }

    public var projectedValue: Wrapper { Wrapper(storage.access()) }

    public var anyStorage: AnyStateStorage { storage }
}

/// Backing storage for @ObservedObject. Conforms to AnyStateStorage so
/// installState in ViewHost can wire it automatically via Mirror, and to
/// GenerationTracked so Phase 7 input-equality gating sees object changes
/// (the generation bumps on every objectWillChange).
public class ObservedObjectStorage<ObjectType: ObservableObject>: AnyStateStorage, GenerationTracked {
    public let object: ObjectType
    private var cancellable: AnyCancellable?
    public private(set) var generation: UInt64 = 0
    public weak var host: AnyViewHost? {
        didSet { wireObjectWillChange() }
    }

    public init(_ object: ObjectType) {
        self.object = object
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
            self.host?.scheduleRebuild()
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

    public init(wrappedValue: @autoclosure @escaping () -> ObjectType) {
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
    private let factory: () -> ObjectType
    var _object: ObjectType?  // internal for restoreValue cross-storage adoption
    private var cancellable: AnyCancellable?
    public private(set) var generation: UInt64 = 0
    public weak var host: AnyViewHost? {
        didSet { wireObjectWillChange() }
    }

    public init(factory: @escaping () -> ObjectType) {
        self.factory = factory
    }

    public var object: ObjectType {
        if let obj = _object { return obj }
        let obj = factory()
        _object = obj
        wireObjectWillChange()
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
            self.host?.scheduleRebuild()
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
            self.host?.scheduleRebuild()
        }
    }

    public func restoreValue(from other: AnyStateStorage) {
        // EnvironmentObject is resolved from environment — no value to restore
    }
}
