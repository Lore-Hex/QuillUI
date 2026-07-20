import Foundation
#if canImport(Observation) && !os(Linux)
import Observation
#endif

/// Protocol for the reactive view container that manages rebuild scheduling.
/// Platform backends provide concrete implementations (GTK ViewHost, Win32 ViewHost, etc.).
public protocol AnyViewHost: AnyObject {
    /// Schedule a coalesced rebuild of the hosted view subtree.
    func scheduleRebuild()

    /// Schedule a rebuild after an `ObservableObject.objectWillChange`
    /// publication has completed. Combine/OpenCombine publish from `willSet`,
    /// so backends with run-loop driven rendering may need a small deferral
    /// before reading the changed value.
    func scheduleRebuildAfterObservableObjectMutation()

    /// Suppress the next automatic focus restoration during rebuild.
    func suppressNextFocusRestore()

    /// Enter interactive mode (e.g. slider drag). While active, rebuilds
    /// are deferred until `endInteractiveUpdate()`. Supports nesting.
    func beginInteractiveUpdate()

    /// Leave interactive mode. When the last nested level exits and a
    /// rebuild was deferred, one rebuild is scheduled.
    func endInteractiveUpdate()

    /// Whether a host that now reads forwarded state still owns visible
    /// native content and must be refreshed alongside the newest host.
    var isActiveForForwardedStateUpdates: Bool { get }
}

extension AnyViewHost {
    public func scheduleRebuildAfterObservableObjectMutation() {
        scheduleRebuild()
    }

    public func beginInteractiveUpdate() {}
    public func endInteractiveUpdate() {}
    public var isActiveForForwardedStateUpdates: Bool { true }
}

/// Resolve injected `@Environment(Type.self)` wrappers while the view's
/// render-time environment is active. The wrapper retains the resolved object,
/// allowing callbacks created from this view value to outlive that environment
/// scope in the same way SwiftUI's dynamic-property update phase does.
public func primeInjectedEnvironmentObjects<V>(_ view: V) {
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
        if let environment = child.value as? AnyObjectInjectionEnvironment {
            environment.wireInjectedObject(to: nil)
        }
    }
}

/// Connect all @State / @ObservedObject / @StateObject / @EnvironmentObject
/// storages found on a view (via Mirror) to the given ViewHost.
public func installState<V>(_ view: V, host: AnyViewHost) {
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
        if let provider = child.value as? AnyStateStorageProvider {
            provider.anyStorage.host = host
        }
        if let environment = child.value as? AnyObjectInjectionEnvironment {
            environment.wireInjectedObject(to: host)
        }
    }
}

/// Check if a view has any reactive properties (@State, @ObservedObject,
/// @Observable stored properties, or `@Environment(SomeClass.self)`
/// object-injection wrappers) via reflection.
public func hasReactiveProperties<V>(_ view: V) -> Bool {
    // Fast path: primitive views never have reactive properties
    if V.self is any PrimitiveView.Type {
        return false
    }

    let mirror = Mirror(reflecting: view)
    return mirror.children.contains { child in
        if child.value is AnyStateStorageProvider { return true }
        #if canImport(Observation) && !os(Linux)
        if #available(macOS 14.0, iOS 17.0, *) {
            if child.value is Observable { return true }
        }
        #endif
        // `@Environment(SomeClass.self)` reads an injected reference
        // object whose properties are typically `@Observable`. The
        // wrapper itself isn't `Observable` (it holds a lookup
        // function, not the object directly), so we recognize the
        // object-injection variant via a dedicated marker and route
        // the view through the reactive wrapper so its body is
        // evaluated under `withObservationTracking`.
        if let env = child.value as? AnyObjectInjectionEnvironment,
           let reflected = env as? (any _EnvironmentObjectInjectionProbe),
           reflected.isInjectedObjectProbe {
            return true
        }
        return false
    }
}

/// Internal probe used by `hasReactiveProperties` to distinguish the
/// keyPath and object-injection variants of `Environment<Value>`
/// without exposing the enum to callers. Conforming only in the
/// Environment.swift file lets the `internal` runtime check stay
/// private to the module.
public protocol _EnvironmentObjectInjectionProbe {
    var isInjectedObjectProbe: Bool { get }
}

extension Environment: _EnvironmentObjectInjectionProbe {
    public var isInjectedObjectProbe: Bool { isInjectedObject }
}
