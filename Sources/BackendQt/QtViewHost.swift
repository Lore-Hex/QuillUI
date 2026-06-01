// QtViewHost.swift — reactive rebuild host for BackendQt.
//
// Qt analogue of SwiftOpenUI's GTKViewHost. A QtViewHost owns a STABLE Qt
// container widget. When @State / @Published / @Observable storage it read
// during the last build mutates, it coalesces a rebuild onto the next main-loop
// turn via QTimer::singleShot(0, ...) (the Qt equivalent of GTK's g_idle_add),
// tears down the previous body, and re-renders.
//
// SLICE #1 deliberately implements the *minimal* correct host:
//   * full-subtree rebuild (no GTK-style narrow text/color mutation path)
//   * no focus/cursor restoration across rebuilds
//   * no animation transition capture
//   * Phase-7 inputsUnchanged short-circuit IS kept (cheap + avoids redundant
//     rebuilds), and withObservationTracking IS wired so @Observable models work.
// The continuation plan lists focus restoration + narrow mutation as follow-ups.

#if canImport(CQtBridge)
import CQtBridge
import SwiftOpenUI
import Foundation
#if canImport(Observation)
import Observation
#endif

public final class QtViewHost: AnyViewHost, DependencyTrackingHost {
    public var lastReadSet: Set<ObjectIdentifier>?
    public var lastInputSnapshot: [StorageSnapshot]?

    /// Stable container widget handed to the parent layout. Children are
    /// swapped on each rebuild; the handle itself never changes.
    public let container: OpaquePointer

    private let buildBody: () -> OpaquePointer
    private let capturedEnvironment: EnvironmentValues
    private var capturedInjectedObjects: [ObjectIdentifier: AnyObject] = [:]

    private let lock = NSLock()
    private var scheduled = false
    private var observationDidFire = false

    public init(buildBody: @escaping () -> OpaquePointer) {
        self.buildBody = buildBody
        self.capturedEnvironment = getCurrentEnvironment()
        self.container = qtOpaque(quill_qt_bridge_container_create())
    }

    /// Build the body once, synchronously, during initial render. Separate from
    /// `rebuild()` so the very first build happens inline (parents need the
    /// child widget immediately), while later builds are coalesced.
    func performInitialBuild() {
        renderBodyIntoContainer()
    }

    // MARK: - AnyViewHost

    public func scheduleRebuild() {
        lock.lock()
        guard !scheduled else { lock.unlock(); return }
        scheduled = true
        lock.unlock()

        let retained = Unmanaged.passRetained(self).toOpaque()
        quill_qt_bridge_post_idle({ userData in
            guard let userData else { return }
            let host = Unmanaged<QtViewHost>.fromOpaque(userData).takeRetainedValue()
            host.rebuild()
        }, retained)
    }

    public func suppressNextFocusRestore() {
        // Focus restoration is a continuation item; no-op for slice #1.
    }

    // MARK: - Rebuild

    private func rebuild() {
        lock.lock()
        scheduled = false
        let fromObservation = observationDidFire
        observationDidFire = false
        lock.unlock()

        // Phase 7: if no tracked storage changed since last render, skip.
        // Skipped when withObservationTracking fired (one-shot subscription
        // must be re-armed by re-running body) — same rule as GTKViewHost.
        if !fromObservation,
           let snapshot = lastInputSnapshot,
           inputsUnchanged(snapshot: snapshot) {
            return
        }

        renderBodyIntoContainer()
    }

    /// Tear down the previous body and render a fresh one into the container,
    /// re-pushing the captured environment and re-registering dependency +
    /// observation tracking.
    private func renderBodyIntoContainer() {
        quill_qt_bridge_widget_delete_children(qtHandle(container))

        let previousEnv = getCurrentEnvironment()
        installRebuildEnvironment()
        beginDependencyTracking()
        let child = buildBodyWithTracking()
        if let tracking = endDependencyTracking() {
            lastReadSet = tracking.readSet
            lastInputSnapshot = tracking.snapshots
        }
        setCurrentEnvironment(previousEnv)

        quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))

        // Position the freshly-built child at the container origin using its
        // RESOLVED size (the size the child already computed for itself —
        // a container's fixed size, or a leaf's size hint). We intentionally
        // do NOT impose a fixed size on the host container: at the window root
        // the backend sets the container's geometry to fill the window, and a
        // fixed size would fight that. Measuring a nested host from a parent
        // stack (so the host reports its content size) is a continuation item
        // — slice #1's smoke has a single root host.
        var w: Int32 = 0
        var h: Int32 = 0
        quill_qt_bridge_widget_resolved_size(qtHandle(child), &w, &h)
        quill_qt_bridge_widget_set_geometry(qtHandle(child), 0, 0, w, h)
    }

    /// Build body under withObservationTracking so @Observable reads re-arm a
    /// rebuild, mirroring GTKViewHost.buildBodyWithTracking.
    private func buildBodyWithTracking() -> OpaquePointer {
        beginEnvironmentReadTracking()

        #if canImport(Observation)
        if #available(macOS 14.0, iOS 17.0, *) {
            var result: OpaquePointer!
            withObservationTracking {
                result = buildBody()
            } onChange: { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.observationDidFire = true
                self.lock.unlock()
                self.scheduleRebuild()
            }
            if let reads = endEnvironmentReadTracking() {
                capturedInjectedObjects = reads
            }
            return result
        }
        #endif

        let result = buildBody()
        if let reads = endEnvironmentReadTracking() {
            capturedInjectedObjects = reads
        }
        return result
    }

    private func installRebuildEnvironment() {
        var env = capturedEnvironment
        for (typeID, object) in capturedInjectedObjects {
            env.setObjectByID(typeID, object)
        }
        setCurrentEnvironment(env)
    }
}

#endif
