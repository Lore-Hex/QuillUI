import Foundation
#if canImport(Combine) && !os(Linux)
import Combine
#else
import OpenCombine
#endif

private func swiftOpenUIStateDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else {
        return
    }
    if let data = ("[QuillUI GTK] " + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

/// Protocol for type-erased access to StateStorage from @State wrappers.
public protocol AnyStateStorageProvider {
    var anyStorage: AnyStateStorage { get }
}

/// Protocol for type-erased StateStorage, allowing ViewHost connection.
public protocol AnyStateStorage: AnyObject {
    var host: AnyViewHost? { get set }
    /// Copy the stored value from another storage of the same concrete type.
    func restoreValue(from other: AnyStateStorage)
    /// Forward writes from stale widget closures to the current render storage.
    func forwardMutations(to other: AnyStateStorage)
}

public extension AnyStateStorage {
    func forwardMutations(to other: AnyStateStorage) {}
}

/// A property wrapper that stores mutable state for a view.
/// When the value changes, the owning ViewHost schedules a re-render.
///
/// `@State` is a struct wrapping a `StateStorage` class. Copying a view
/// shares the same storage identity (same as SwiftUI). This is intentional:
/// the view struct is recreated on each re-render, but the storage persists.
@propertyWrapper
public struct State<Value>: AnyStateStorageProvider {
    public let storage: StateStorage<Value>

    public init(wrappedValue: Value) {
        storage = StateStorage(wrappedValue)
    }

    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.setValue(newValue) }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.storage.value },
            set: { self.storage.setValue($0) },
            quillUIIdentity: BindingIdentity(objectIdentifier: ObjectIdentifier(storage))
        )
    }

    public var anyStorage: AnyStateStorage { storage }
}

/// The backing storage for @State. Thread-safe value access with
/// coalesced re-render scheduling via the owning ViewHost.
public class StateStorage<Value>: AnyStateStorage, GenerationTracked {
    private let lock = NSLock()
    var _value: Value  // internal for restoreValue cross-storage access
    private var forwardedStorage: StateStorage<Value>?
    private var observableCancellable: AnyCancellable?
    public weak var host: AnyViewHost? {
        didSet { wireObservableStateValue() }
    }
    public private(set) var generation: UInt64 = 0

    private func bumpGeneration() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }

    private func scheduleObservableStateMutationRebuild() {
        let objectReference: AnyObject?
        lock.lock()
        generation &+= 1
        let forwarded = forwardedStorage
        let currentHost = host
        if let object = _value as? any ObservableObject {
            objectReference = object as AnyObject
        } else {
            objectReference = nil
        }
        lock.unlock()

        forwarded?.bumpGeneration()
        if let objectReference {
            wireEnvironmentObservableObjectRead(objectReference, host: currentHost)
            wireEnvironmentObservableObjectRead(objectReference, host: forwarded?.host)
        }
        let targetHost = forwarded?.host ?? currentHost
        let hostDescription = currentHost.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        let forwardedHostDescription = forwarded?.host.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        swiftOpenUIStateDebugLog(
            "observable state change type=\(Value.self) host=\(hostDescription) forwardedHost=\(forwardedHostDescription)"
        )
        targetHost?.scheduleRebuildAfterObservableObjectMutation()
    }

    public init(_ value: Value) {
        _value = value
    }

    public var value: Value {
        lock.lock()
        let value = _value
        lock.unlock()
        recordDependencyRead(self)
        if let object = value as? any ObservableObject {
            recordEnvironmentObservableObjectRead(object as AnyObject)
        }
        return value
    }

    public func setValue(_ newValue: Value) {
        lock.lock()
        if let forwarded = forwardedStorage {
            lock.unlock()
            forwarded.setValue(newValue)
            return
        }
        _value = newValue
        generation += 1
        let forwarded = forwardedStorage
        let currentHost = host
        lock.unlock()
        let hostDescription = currentHost.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        let forwardedHostDescription = forwarded?.host.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        swiftOpenUIStateDebugLog("state set type=\(Value.self) forwarded=\(forwarded != nil) host=\(hostDescription) forwardedHost=\(forwardedHostDescription)")
        wireObservableStateValue()
        // @State always rebuilds its declaring host — no dependency gating.
        // The declaring host is the only host notified, and it may pass
        // the value to children via Binding. Skipping its rebuild would
        // leave bound children stale.
        host?.scheduleRebuild()
    }

    public func forwardMutations(to other: AnyStateStorage) {
        lock.lock()
        guard let typed = other as? StateStorage<Value>, typed !== self else {
            forwardedStorage = nil
            lock.unlock()
            wireObservableStateValue()
            return
        }
        forwardedStorage = typed
        let currentHost = host.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        let forwardedHost = typed.host.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
        lock.unlock()
        wireObservableStateValue()
        swiftOpenUIStateDebugLog("state forward type=\(Value.self) host=\(currentHost) forwardedHost=\(forwardedHost)")
    }

    public func restoreValue(from other: AnyStateStorage) {
        if let typed = other as? StateStorage<Value> {
            // Direct access without lock — called only during render pass (single-threaded)
            _value = typed._value
            forwardedStorage = nil
            wireObservableStateValue()
        }
    }

    private func wireObservableStateValue() {
        guard let object = _value as? any ObservableObject else { return }
        let objectReference = object as AnyObject
        let forwarded = forwardedStorage
        let currentHost = host
        wireEnvironmentObservableObjectRead(objectReference, host: currentHost)
        wireEnvironmentObservableObjectRead(objectReference, host: forwarded?.host)
        // objectWillChange-based wiring (Apple's granularity). Bump our own
        // generation so Phase 7 input-equality gating sees the object's
        // internal mutation even though `_value` (the reference) is unchanged.
        observableCancellable = subscribeOpaqueObservableObject(object) { [weak self] in
            guard let self else { return }
            self.scheduleObservableStateMutationRebuild()
        }
    }
}
