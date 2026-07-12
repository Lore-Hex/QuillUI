import CGTK
import CGTKBridge
import SwiftOpenUI
import Foundation
#if canImport(Observation) && !os(Linux)
import Observation
#endif

private func gtkViewHostDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else {
        return
    }
    if let data = ("[QuillUI GTK] " + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private struct GTKActiveTask {
    var lifecycleID: String?
    var task: Task<Void, Never>
}

private struct GTKViewHostLifecycleSnapshot {
    var appearedOnAppearIdentities: Set<GTK4DescriptorIdentity>
    var activeTasksByIdentity: [GTK4DescriptorIdentity: GTKActiveTask]
}

private let gtkViewHostLifecycleRemountLock = NSLock()
private var gtkViewHostLifecycleRemountDepth = 0
private var gtkViewHostLifecycleRemountCache: [String: GTKViewHostLifecycleSnapshot] = [:]

private func gtkViewHostLifecycleRemountIsActive() -> Bool {
    gtkViewHostLifecycleRemountLock.lock()
    defer { gtkViewHostLifecycleRemountLock.unlock() }
    return gtkViewHostLifecycleRemountDepth > 0
}

private func gtkBeginViewHostLifecycleRemountPass() {
    gtkViewHostLifecycleRemountLock.lock()
    gtkViewHostLifecycleRemountDepth += 1
    gtkViewHostLifecycleRemountLock.unlock()
}

private func gtkEndViewHostLifecycleRemountPass() {
    let tasksToCancel: [Task<Void, Never>]

    gtkViewHostLifecycleRemountLock.lock()
    gtkViewHostLifecycleRemountDepth = max(0, gtkViewHostLifecycleRemountDepth - 1)
    if gtkViewHostLifecycleRemountDepth == 0 {
        tasksToCancel = gtkViewHostLifecycleRemountCache.values.flatMap {
            $0.activeTasksByIdentity.values.map(\.task)
        }
        gtkViewHostLifecycleRemountCache.removeAll()
    } else {
        tasksToCancel = []
    }
    gtkViewHostLifecycleRemountLock.unlock()

    tasksToCancel.forEach { $0.cancel() }
}

private func gtkStoreViewHostLifecycleSnapshot(
    _ snapshot: GTKViewHostLifecycleSnapshot,
    for namespace: String
) {
    gtkViewHostLifecycleRemountLock.lock()
    if gtkViewHostLifecycleRemountDepth > 0 {
        if var existing = gtkViewHostLifecycleRemountCache[namespace] {
            existing.appearedOnAppearIdentities.formUnion(snapshot.appearedOnAppearIdentities)
            for (identity, task) in snapshot.activeTasksByIdentity {
                existing.activeTasksByIdentity[identity] = task
            }
            gtkViewHostLifecycleRemountCache[namespace] = existing
        } else {
            gtkViewHostLifecycleRemountCache[namespace] = snapshot
        }
        gtkViewHostDebugLog(
            "host lifecycle snapshot store ns=\(namespace) onAppear=\(snapshot.appearedOnAppearIdentities.count) tasks=\(snapshot.activeTasksByIdentity.count)"
        )
    }
    gtkViewHostLifecycleRemountLock.unlock()
}

private func gtkTakeViewHostLifecycleSnapshot(
    for namespace: String
) -> GTKViewHostLifecycleSnapshot? {
    gtkViewHostLifecycleRemountLock.lock()
    let snapshot = gtkViewHostLifecycleRemountCache.removeValue(forKey: namespace)
    gtkViewHostLifecycleRemountLock.unlock()
    gtkViewHostDebugLog(
        "host lifecycle snapshot take ns=\(namespace) hit=\(snapshot != nil)"
    )
    return snapshot
}

func gtkRestoreViewHostLifecycleIfAvailable(_ host: GTKViewHost) {
    guard let snapshot = gtkTakeViewHostLifecycleSnapshot(for: host.stateIdentityNamespace) else {
        return
    }
    gtkViewHostDebugLog(
        "host lifecycle snapshot restore host=\(ObjectIdentifier(host)) ns=\(host.stateIdentityNamespace) onAppear=\(snapshot.appearedOnAppearIdentities.count) tasks=\(snapshot.activeTasksByIdentity.count)"
    )
    host.restoreLifecycleSnapshot(snapshot)
}

private struct GTKScrollAxisSnapshot {
    let value: Double
    let isAtEnd: Bool
}

private struct GTKScrollAdjustmentSnapshot {
    let horizontal: GTKScrollAxisSnapshot?
    let vertical: GTKScrollAxisSnapshot?
}

private final class GTKScrollRestorationContext {
    let root: UnsafeMutablePointer<GtkWidget>
    let snapshots: [GTKScrollAdjustmentSnapshot]

    init(root: UnsafeMutablePointer<GtkWidget>, snapshots: [GTKScrollAdjustmentSnapshot]) {
        self.root = root
        self.snapshots = snapshots
        g_object_ref(gpointer(root))
    }

    deinit {
        g_object_unref(gpointer(root))
    }
}

private func gtkWidgetIsScrolledWindow(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkScrolledWindow"
}

private func gtkSnapshotAdjustment(_ adjustment: UnsafeMutablePointer<GtkAdjustment>?) -> GTKScrollAxisSnapshot? {
    guard let adjustment else { return nil }
    let lower = gtk_adjustment_get_lower(adjustment)
    let upper = gtk_adjustment_get_upper(adjustment)
    let pageSize = gtk_adjustment_get_page_size(adjustment)
    let maxValue = max(lower, upper - pageSize)
    let value = gtk_adjustment_get_value(adjustment)
    return GTKScrollAxisSnapshot(value: value, isAtEnd: maxValue > lower && value >= maxValue - 2.0)
}

private func gtkCollectScrollAdjustmentSnapshots(in widget: UnsafeMutablePointer<GtkWidget>) -> [GTKScrollAdjustmentSnapshot] {
    guard gtk_swift_is_widget(widget) != 0 else { return [] }

    var snapshots: [GTKScrollAdjustmentSnapshot] = []

    func walk(_ current: UnsafeMutablePointer<GtkWidget>) {
        guard gtk_swift_is_widget(current) != 0 else { return }

        if gtkWidgetIsScrolledWindow(current) {
            let scrolled = OpaquePointer(current)
            snapshots.append(
                GTKScrollAdjustmentSnapshot(
                    horizontal: gtkSnapshotAdjustment(gtk_scrolled_window_get_hadjustment(scrolled)),
                    vertical: gtkSnapshotAdjustment(gtk_scrolled_window_get_vadjustment(scrolled))
                )
            )
        }

        var child = gtk_widget_get_first_child(current)
        while let c = child {
            walk(c)
            child = gtk_widget_get_next_sibling(c)
        }
    }

    walk(widget)
    return snapshots
}

private func gtkRestoreAdjustment(_ adjustment: UnsafeMutablePointer<GtkAdjustment>?, snapshot: GTKScrollAxisSnapshot?) {
    guard let adjustment, let snapshot else { return }
    let lower = gtk_adjustment_get_lower(adjustment)
    let upper = gtk_adjustment_get_upper(adjustment)
    let pageSize = gtk_adjustment_get_page_size(adjustment)
    let maxValue = max(lower, upper - pageSize)
    let value = snapshot.isAtEnd ? maxValue : min(max(snapshot.value, lower), maxValue)
    gtk_adjustment_set_value(adjustment, value)
}

private func gtkRestoreScrollAdjustmentSnapshots(
    _ snapshots: [GTKScrollAdjustmentSnapshot],
    in widget: UnsafeMutablePointer<GtkWidget>
) {
    guard !snapshots.isEmpty, gtk_swift_is_widget(widget) != 0 else { return }

    var index = 0

    func walk(_ current: UnsafeMutablePointer<GtkWidget>) {
        guard gtk_swift_is_widget(current) != 0 else { return }

        if gtkWidgetIsScrolledWindow(current), index < snapshots.count {
            let snapshot = snapshots[index]
            let scrolled = OpaquePointer(current)
            gtkRestoreAdjustment(
                gtk_scrolled_window_get_hadjustment(scrolled),
                snapshot: snapshot.horizontal
            )
            gtkRestoreAdjustment(
                gtk_scrolled_window_get_vadjustment(scrolled),
                snapshot: snapshot.vertical
            )
            index += 1
        }

        var child = gtk_widget_get_first_child(current)
        while let c = child {
            walk(c)
            child = gtk_widget_get_next_sibling(c)
        }
    }

    walk(widget)
}

private func gtkScheduleScrollAdjustmentSnapshotRestore(
    _ snapshots: [GTKScrollAdjustmentSnapshot],
    in widget: UnsafeMutablePointer<GtkWidget>
) {
    guard !snapshots.isEmpty else { return }
    let context = GTKScrollRestorationContext(root: widget, snapshots: snapshots)
    g_idle_add({ userData -> gboolean in
        let context = Unmanaged<GTKScrollRestorationContext>.fromOpaque(userData!).takeRetainedValue()
        gtkRestoreScrollAdjustmentSnapshots(context.snapshots, in: context.root)
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

/// Thread-local key for the ViewHost currently performing a rebuild.
private var rebuildingViewHostKey: pthread_key_t = {
    var key: pthread_key_t = 0
    pthread_key_create(&key, nil)
    return key
}()

/// GTK4-specific ViewHost that manages a stable GtkBox container.
/// On state change, rebuilds the body and swaps children.
/// Preserves focus and cursor position across rebuilds.
public class GTKViewHost: AnyViewHost, DependencyTrackingHost {
    public var lastReadSet: Set<ObjectIdentifier>?
    public var lastInputSnapshot: [StorageSnapshot]?
    public let container: UnsafeMutablePointer<GtkWidget>
    let buildBody: () -> OpaquePointer
    /// Describes the body as a descriptor tree without creating widgets.
    var describeBody: (() -> GTK4DescriptorNode)?
    /// Retained descriptor state for narrow mutation path.
    var lastRetainedDescriptor: GTK4RetainedDescriptorNode?
    var retainedExecutor: GTK4RetainedExecutorNode?
    private let lock = NSLock()
    private var scheduled = false
    private var isContainerAlive = true
    private var suppressFocusRestoreOnce = false
    private var interactiveUpdateDepth = 0
    private var rebuildDeferredDuringInteraction = false
    private var observableObjectMutationSchedulePending = false
    private var pendingAnimation: Animation?
    private var lastConstrainedChildWidth: gint = -1
    private var lastConstrainedChildHeight: gint = -1
    private var onAppearPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4OnAppearPayload] = [:]
    private var appearedOnAppearIdentities: Set<GTK4DescriptorIdentity> = []
    private var taskPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4TaskPayload] = [:]
    private var activeTasksByIdentity: [GTK4DescriptorIdentity: GTKActiveTask] = [:]
    var lastRenderOnAppearPayloads: [GTK4OnAppearPayload] = []
    var lastRenderTaskPayloads: [GTK4TaskPayload] = []
    private var taskLifecycleSuspended = true
    /// True when the pending/next rebuild was requested by withObservationTracking's
    /// onChange callback. withObservationTracking is one-shot: once it fires, the
    /// observation is no longer registered, and the only way to re-subscribe is to
    /// run body through buildBodyWithTracking again. Therefore an observation-
    /// triggered rebuild must NOT be short-circuited by the Phase 7 inputsUnchanged
    /// optimization — that optimization only tracks @State / @Published generations
    /// and can't see @Observable mutations, so it would wrongly declare the inputs
    /// unchanged and leave observation permanently unsubscribed.
    private var observationDidFire = false
    var rebuildPresentationRoot: gpointer?
    var stateIdentityNamespace = "root"
    var capturedEnvironment: EnvironmentValues

    /// Objects read by body via `@Environment(Type.self)` during the
    /// last successful render. Re-pushed into the environment before
    /// each rebuild so body's lookups find the same objects even when
    /// the originating `.environment(object)` modifier lives below
    /// this ViewHost in the render tree (and therefore isn't
    /// guaranteed to re-run the push before body's next read). Filled
    /// by `endEnvironmentReadTracking()` after each buildBody.
    private var capturedInjectedObjects: [ObjectIdentifier: AnyObject] = [:]

    /// Install the captured ancestor environment plus every injected
    /// object body read during its last render. Called at each
    /// rebuild entry point instead of `setCurrentEnvironment(
    /// capturedEnvironment)` alone, so descendant `@Environment(
    /// Type.self)` lookups survive even when the pushing modifier
    /// lives inside a parent's body.
    private func installRebuildEnvironment() {
        var env = capturedEnvironment
        for (typeID, object) in capturedInjectedObjects {
            env.setLatestObjectByID(typeID, fallback: object)
        }
        setCurrentEnvironment(env)
    }

    public init(buildBody: @escaping () -> OpaquePointer) {
        self.buildBody = buildBody
        self.capturedEnvironment = getCurrentEnvironment()
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        self.container = box
        gtk_widget_set_hexpand(box, 0)
        gtk_widget_set_vexpand(box, 0)
        // Transparent so content backgrounds fill edge-to-edge
        applyCSSToWidget(box, properties: "background: transparent;")

        // Attach self to the GTK widget for lifetime management.
        let retained = Unmanaged.passRetained(self).toOpaque()
        let gobject = UnsafeMutableRawPointer(box).assumingMemoryBound(to: GObject.self)
        g_object_set_data_full(
            gobject,
            "gtk-swift-view-host",
            retained,
            { userData in
                let hostRef = Unmanaged<GTKViewHost>.fromOpaque(userData!)
                hostRef.takeUnretainedValue().markContainerDestroyed()
                hostRef.release()
            }
        )
        let hostPointer = Unmanaged.passUnretained(self).toOpaque()
        g_signal_connect_data(
            gpointer(box),
            "realize",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let host = Unmanaged<GTKViewHost>.fromOpaque(userData!).takeUnretainedValue()
                host.resumeTasksAfterAppear()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            hostPointer,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(box),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let host = Unmanaged<GTKViewHost>.fromOpaque(userData!).takeUnretainedValue()
                host.resumeTasksAfterAppear()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            hostPointer,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(box),
            "unmap",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let host = Unmanaged<GTKViewHost>.fromOpaque(userData!).takeUnretainedValue()
                host.suspendTasksForDisappear()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            hostPointer,
            nil,
            GConnectFlags(rawValue: 0)
        )
        _ = gtk_widget_add_tick_callback(
            box,
            gtkViewHostWidthTickCallback,
            hostPointer,
            nil
        )
    }

    private func markContainerDestroyed() {
        let tasksToCancel: [Task<Void, Never>]
        let lifecycleSnapshot: GTKViewHostLifecycleSnapshot?
        lock.lock()
        isContainerAlive = false
        scheduled = false
        taskLifecycleSuspended = true
        if gtkViewHostLifecycleRemountIsActive() {
            lifecycleSnapshot = GTKViewHostLifecycleSnapshot(
                appearedOnAppearIdentities: appearedOnAppearIdentities,
                activeTasksByIdentity: activeTasksByIdentity
            )
            tasksToCancel = []
        } else {
            lifecycleSnapshot = nil
            tasksToCancel = activeTasksByIdentity.values.map(\.task)
        }
        onAppearPayloadsByIdentity.removeAll()
        appearedOnAppearIdentities.removeAll()
        taskPayloadsByIdentity.removeAll()
        activeTasksByIdentity.removeAll()
        lock.unlock()
        if let lifecycleSnapshot {
            gtkStoreViewHostLifecycleSnapshot(lifecycleSnapshot, for: stateIdentityNamespace)
        }
        tasksToCancel.forEach { $0.cancel() }
    }

    func updateTaskLifecycle(
        descriptorRoot: GTK4IdentifiedDescriptorNode,
        taskPayloads: [GTK4TaskPayload]
    ) {
        let payloadsByIdentity = gtkTaskPayloadsByIdentity(
            descriptorRoot: descriptorRoot,
            payloads: taskPayloads,
            includingListRowScopes: false
        )
        gtkViewHostDebugLog(
            "host task lifecycle host=\(ObjectIdentifier(self)) ns=\(stateIdentityNamespace) payloads=\(taskPayloads.count) mapped=\(payloadsByIdentity.count)"
        )
        reconcileTaskPayloads(
            payloadsByIdentity
        )
        resumeTasksIfAlreadyMapped()
    }

    func updateOnAppearLifecycle(
        descriptorRoot: GTK4IdentifiedDescriptorNode,
        onAppearPayloads: [GTK4OnAppearPayload]
    ) {
        reconcileOnAppearPayloads(
            gtkOnAppearPayloadsByIdentity(
                descriptorRoot: descriptorRoot,
                payloads: onAppearPayloads,
                includingListRowScopes: false
            )
        )
        resumeTasksIfAlreadyMapped()
    }

    private func reconcileOnAppearPayloads(
        _ newPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4OnAppearPayload]
    ) {
        let actionsToRun: [() -> Void]

        lock.lock()
        onAppearPayloadsByIdentity = newPayloadsByIdentity

        let liveIdentities = Set(newPayloadsByIdentity.keys)
        appearedOnAppearIdentities = appearedOnAppearIdentities.intersection(liveIdentities)

        if taskLifecycleSuspended {
            actionsToRun = []
        } else {
            let newAppearances = liveIdentities.subtracting(appearedOnAppearIdentities)
            gtkViewHostDebugLog(
                "host onAppear reconcile host=\(ObjectIdentifier(self)) live=\(liveIdentities.count) appeared=\(appearedOnAppearIdentities.count) new=\(newAppearances.count) suspended=false"
            )
            appearedOnAppearIdentities.formUnion(newAppearances)
            actionsToRun = newAppearances.compactMap { newPayloadsByIdentity[$0]?.action }
        }
        lock.unlock()

        actionsToRun.forEach { $0() }
    }

    private func reconcileTaskPayloads(
        _ newPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4TaskPayload]
    ) {
        var tasksToCancel: [Task<Void, Never>] = []

        lock.lock()
        taskPayloadsByIdentity = newPayloadsByIdentity
        gtkViewHostDebugLog(
            "host task reconcile host=\(ObjectIdentifier(self)) live=\(newPayloadsByIdentity.count) active=\(activeTasksByIdentity.count) suspended=\(taskLifecycleSuspended)"
        )

        let staleIdentities = activeTasksByIdentity.keys.filter { identity in
            guard let newPayload = newPayloadsByIdentity[identity] else { return true }
            return activeTasksByIdentity[identity]?.lifecycleID != newPayload.lifecycleID
        }
        for identity in staleIdentities {
            if let active = activeTasksByIdentity.removeValue(forKey: identity) {
                tasksToCancel.append(active.task)
            }
        }

        if !taskLifecycleSuspended {
            for (identity, payload) in newPayloadsByIdentity where activeTasksByIdentity[identity] == nil {
                startTaskLocked(identity: identity, payload: payload)
            }
        }
        lock.unlock()

        tasksToCancel.forEach { $0.cancel() }
    }

    private func startTaskLocked(identity: GTK4DescriptorIdentity, payload: GTK4TaskPayload) {
        let action = payload.action
        gtkViewHostDebugLog("host task start host=\(ObjectIdentifier(self)) identity=\(identity) lifecycleID=\(payload.lifecycleID ?? "<none>")")
        activeTasksByIdentity[identity] = GTKActiveTask(
            lifecycleID: payload.lifecycleID,
            task: Task(priority: payload.priority) {
                await action()
            }
        )
    }

    private func suspendTasksForDisappear() {
        let tasksToCancel: [Task<Void, Never>]
        lock.lock()
        taskLifecycleSuspended = true
        if gtkViewHostLifecycleRemountIsActive() {
            let lifecycleSnapshot = GTKViewHostLifecycleSnapshot(
                appearedOnAppearIdentities: appearedOnAppearIdentities,
                activeTasksByIdentity: activeTasksByIdentity
            )
            activeTasksByIdentity.removeAll()
            lock.unlock()
            gtkViewHostDebugLog(
                "host lifecycle snapshot transfer-on-unmap host=\(ObjectIdentifier(self)) ns=\(stateIdentityNamespace) onAppear=\(lifecycleSnapshot.appearedOnAppearIdentities.count) tasks=\(lifecycleSnapshot.activeTasksByIdentity.count)"
            )
            gtkStoreViewHostLifecycleSnapshot(lifecycleSnapshot, for: stateIdentityNamespace)
            return
        }
        appearedOnAppearIdentities.removeAll()
        tasksToCancel = activeTasksByIdentity.values.map(\.task)
        activeTasksByIdentity.removeAll()
        lock.unlock()

        tasksToCancel.forEach { $0.cancel() }
    }

    private func resumeTasksAfterAppear() {
        let actionsToRun: [() -> Void]

        lock.lock()
        guard isContainerAlive else {
            lock.unlock()
            return
        }
        taskLifecycleSuspended = false
        gtkViewHostDebugLog(
            "host task resume host=\(ObjectIdentifier(self)) payloads=\(taskPayloadsByIdentity.count) active=\(activeTasksByIdentity.count)"
        )
        for (identity, payload) in taskPayloadsByIdentity where activeTasksByIdentity[identity] == nil {
            startTaskLocked(identity: identity, payload: payload)
        }
        let newAppearances = Set(onAppearPayloadsByIdentity.keys).subtracting(appearedOnAppearIdentities)
        gtkViewHostDebugLog(
            "host onAppear resume host=\(ObjectIdentifier(self)) live=\(onAppearPayloadsByIdentity.count) appeared=\(appearedOnAppearIdentities.count) new=\(newAppearances.count)"
        )
        appearedOnAppearIdentities.formUnion(newAppearances)
        actionsToRun = newAppearances.compactMap { onAppearPayloadsByIdentity[$0]?.action }
        lock.unlock()

        actionsToRun.forEach { $0() }
    }

    private func resumeTasksIfAlreadyMapped() {
        guard gtk_widget_get_mapped(container) != 0 else { return }
        resumeTasksAfterAppear()
    }

    fileprivate func restoreLifecycleSnapshot(_ snapshot: GTKViewHostLifecycleSnapshot) {
        lock.lock()
        appearedOnAppearIdentities.formUnion(snapshot.appearedOnAppearIdentities)
        for (identity, activeTask) in snapshot.activeTasksByIdentity {
            activeTasksByIdentity[identity] = activeTask
        }
        lock.unlock()
    }

    func resumeLifecycleAfterProgrammaticVisibilityChange() {
        resumeTasksAfterAppear()
    }

    public func scheduleRebuild() {
        lock.lock()
        let currentAnimation = getCurrentAnimation()
        defer { lock.unlock() }
        guard isContainerAlive else {
            gtkViewHostDebugLog("host schedule ignored alive=false host=\(ObjectIdentifier(self))")
            return
        }
        // Defer rebuild while interactive (e.g. slider drag)
        if interactiveUpdateDepth > 0 {
            rebuildDeferredDuringInteraction = true
            return
        }
        if let currentAnimation {
            pendingAnimation = currentAnimation
        }
        guard !scheduled else {
            gtkViewHostDebugLog("host schedule coalesced host=\(ObjectIdentifier(self))")
            return
        }
        scheduled = true
        gtkViewHostDebugLog("host schedule host=\(ObjectIdentifier(self))")
        let retained = Unmanaged.passRetained(self)
        g_idle_add({ userData -> gboolean in
            let host = Unmanaged<GTKViewHost>.fromOpaque(userData!).takeRetainedValue()
            host.rebuild()
            return 0 // G_SOURCE_REMOVE
        }, retained.toOpaque())
    }

    public func scheduleRebuildAfterObservableObjectMutation() {
        lock.lock()
        guard isContainerAlive else {
            lock.unlock()
            gtkViewHostDebugLog("host observable schedule ignored alive=false host=\(ObjectIdentifier(self))")
            return
        }
        guard !observableObjectMutationSchedulePending else {
            lock.unlock()
            gtkViewHostDebugLog("host observable schedule coalesced host=\(ObjectIdentifier(self))")
            return
        }
        observableObjectMutationSchedulePending = true
        lock.unlock()

        gtkViewHostDebugLog("host observable schedule host=\(ObjectIdentifier(self))")
        let retained = Unmanaged.passRetained(self)
        g_timeout_add(1, { userData -> gboolean in
            let host = Unmanaged<GTKViewHost>.fromOpaque(userData!).takeRetainedValue()
            host.lock.lock()
            host.observableObjectMutationSchedulePending = false
            host.observationDidFire = true
            let alive = host.isContainerAlive
            host.lock.unlock()
            if alive {
                host.scheduleRebuild()
            }
            return 0 // G_SOURCE_REMOVE
        }, retained.toOpaque())
    }

    public func beginInteractiveUpdate() {
        lock.lock()
        defer { lock.unlock() }
        guard isContainerAlive else { return }
        interactiveUpdateDepth += 1
    }

    public func endInteractiveUpdate() {
        lock.lock()
        guard interactiveUpdateDepth > 0 else {
            lock.unlock()
            return
        }
        interactiveUpdateDepth -= 1
        guard interactiveUpdateDepth == 0,
              rebuildDeferredDuringInteraction,
              isContainerAlive,
              !scheduled else {
            lock.unlock()
            return
        }
        rebuildDeferredDuringInteraction = false
        scheduled = true
        lock.unlock()

        let retained = Unmanaged.passRetained(self)
        g_idle_add({ userData -> gboolean in
            let host = Unmanaged<GTKViewHost>.fromOpaque(userData!).takeRetainedValue()
            host.rebuild()
            return 0
        }, retained.toOpaque())
    }

    public func suppressNextFocusRestore() {
        lock.lock()
        suppressFocusRestoreOnce = true
        lock.unlock()
    }

    /// Build the body with observation tracking.  Any @Observable properties
    /// accessed during rendering are automatically tracked; when they change,
    /// scheduleRebuild() fires and the next rebuild re-registers tracking.
    func buildBodyWithTracking() -> OpaquePointer {
        // Track `@Environment(Type.self)` reads so we can re-push the
        // same objects into env on rebuild even if the pushing
        // modifier lives below us in the render tree. Pairs with
        // `endEnvironmentReadTracking()` after body evaluates.
        beginEnvironmentReadTracking()

        #if canImport(Observation) && !os(Linux)
        if #available(macOS 14.0, iOS 17.0, *) {
            var result: OpaquePointer!
            withObservationTracking {
                result = buildBodyCapturingRenderLifecyclePayloads()
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

        let result = buildBodyCapturingRenderLifecyclePayloads()
        if let reads = endEnvironmentReadTracking() {
            capturedInjectedObjects = reads
        }
        return result
    }

    private func buildBodyCapturingRenderLifecyclePayloads() -> OpaquePointer {
        gtkBeginStateIdentityPass()
        let captured = gtkCaptureRenderLifecyclePayloads {
            buildBody()
        }
        lastRenderOnAppearPayloads = captured.onAppearPayloads
        lastRenderTaskPayloads = captured.taskPayloads
        return captured.value
    }

    func renderCapturedOnAppearPayloads(fallback described: [GTK4OnAppearPayload]) -> [GTK4OnAppearPayload] {
        lastRenderOnAppearPayloads.count == described.count ? lastRenderOnAppearPayloads : described
    }

    func renderCapturedTaskPayloads(fallback described: [GTK4TaskPayload]) -> [GTK4TaskPayload] {
        lastRenderTaskPayloads.count == described.count ? lastRenderTaskPayloads : described
    }

    /// Re-runs the describe pass under a fresh withObservationTracking
    /// registration. onChange is one-shot: once an @Observable mutation has
    /// fired it, the narrow mutation path may keep the existing widgets only
    /// if something re-subscribes. The describe pass evaluates the same body
    /// (and therefore reads the same observable properties) as a full render,
    /// so tracking it restores the subscription without any widget teardown.
    private func describeReestablishingObservation(
        _ describeBody: () -> GTK4DescriptorNode
    ) -> (
        descriptor: GTK4DescriptorNode,
        canvasPayloads: [GTK4CanvasPayload],
        onAppearPayloads: [GTK4OnAppearPayload],
        taskPayloads: [GTK4TaskPayload],
        buttonPayloads: [GTK4ButtonPayload]
    ) {
        #if canImport(Observation) && !os(Linux)
        if #available(macOS 14.0, iOS 17.0, *) {
            var result: (
                descriptor: GTK4DescriptorNode,
                canvasPayloads: [GTK4CanvasPayload],
                onAppearPayloads: [GTK4OnAppearPayload],
                taskPayloads: [GTK4TaskPayload],
                buttonPayloads: [GTK4ButtonPayload]
            )!
            withObservationTracking {
                result = describeBodyCapturingPayloads(describeBody)
            } onChange: { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.observationDidFire = true
                self.lock.unlock()
                self.scheduleRebuild()
            }
            return result
        }
        #endif
        return describeBodyCapturingPayloads(describeBody)
    }

    func describeBodyCapturingPayloads(
        _ describeBody: () -> GTK4DescriptorNode
    ) -> (
        descriptor: GTK4DescriptorNode,
        canvasPayloads: [GTK4CanvasPayload],
        onAppearPayloads: [GTK4OnAppearPayload],
        taskPayloads: [GTK4TaskPayload],
        buttonPayloads: [GTK4ButtonPayload]
    ) {
        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(self)
        gtkBeginStateIdentityPass()
        defer { GTKViewHost.setCurrentRebuilding(previousHost) }
        return gtkDescribeCapturingCanvasPayloads(describeBody)
    }

    func rebuild() {
        gtkViewHostDebugLog("host rebuild start host=\(ObjectIdentifier(self))")
        lock.lock()
        scheduled = false
        guard isContainerAlive else {
            lock.unlock()
            gtkViewHostDebugLog("host rebuild ignored alive=false host=\(ObjectIdentifier(self))")
            return
        }
        let shouldRestoreFocus = !suppressFocusRestoreOnce
        let animation = pendingAnimation
        pendingAnimation = nil
        suppressFocusRestoreOnce = false
        let fromObservation = observationDidFire
        observationDidFire = false
        lock.unlock()

        // --- Narrow mutation path: try text/color in-place update ---
        // Observation-driven rebuilds stay eligible: withObservationTracking's
        // onChange is one-shot, so re-subscribe by running the DESCRIBE pass
        // (which evaluates the same body and reads the same @Observable
        // properties) under a fresh tracking registration. Without this, every
        // @Observable mutation — e.g. each keystroke in a TextField bound to a
        // SwiftData model — forces a full teardown that destroys the focused
        // entry mid-typing. SwiftUI never rebuilds widgets on model mutation.
        if let describeBody = describeBody,
           let oldRetained = lastRetainedDescriptor,
           let oldExecutor = retainedExecutor {

            let previousEnv = getCurrentEnvironment()
            installRebuildEnvironment()
            let described: (
                descriptor: GTK4DescriptorNode,
                canvasPayloads: [GTK4CanvasPayload],
                onAppearPayloads: [GTK4OnAppearPayload],
                taskPayloads: [GTK4TaskPayload],
                buttonPayloads: [GTK4ButtonPayload]
            )
            if fromObservation {
                described = describeReestablishingObservation(describeBody)
            } else {
                described = describeBodyCapturingPayloads(describeBody)
            }
            setCurrentEnvironment(previousEnv)

            let newIdentified = gtkIdentifyDescriptorTree(described.descriptor)
            let canvasPayloads = gtkCanvasPayloadsByIdentity(
                descriptorRoot: newIdentified,
                payloads: described.canvasPayloads
            )
            let buttonPayloads = gtkButtonPayloadsByIdentity(
                descriptorRoot: newIdentified,
                payloads: described.buttonPayloads
            )
            let plan = gtkPlanDescriptorTree(old: oldRetained, new: newIdentified)

            if gtkCanApplyTextColorHostMutation(plan: plan) {
                let action = gtkExecuteDescriptorPlan(
                    old: oldExecutor,
                    plan: plan,
                    canvasPayloadsByIdentity: canvasPayloads
                )

                // Verify all slots are still valid before mutating
                let allSlotsValid = gtkAllSlotsValid(action: action)
                if allSlotsValid {
                    let result = gtkApplyHookMutation(action: action)
                    let buttonActionsUpdated = gtkUpdateButtonActions(
                        in: action.resultingNode,
                        payloadsByIdentity: buttonPayloads
                    )
                    if gtkHookMutationSucceeded(result), buttonActionsUpdated {
                        // Success — update retained state, skip full rebuild
                        updateOnAppearLifecycle(
                            descriptorRoot: newIdentified,
                            onAppearPayloads: renderCapturedOnAppearPayloads(fallback: described.onAppearPayloads)
                        )
                        lastRetainedDescriptor = gtkRetainDescriptorTree(newIdentified)
                        retainedExecutor = action.resultingNode
                        return
                    }
                    if !buttonActionsUpdated {
                        debugLogRebuild("narrow button action update failed ns=\(stateIdentityNamespace)")
                    }
                    debugLogRebuild("narrow hook mutation failed ns=\(stateIdentityNamespace)")
                } else {
                    debugLogRebuild("narrow slots invalid ns=\(stateIdentityNamespace)")
                }
            } else {
                debugLogRebuild(
                    "narrow plan ineligible ns=\(stateIdentityNamespace) "
                        + "plan=\(gtkDescribeDescriptorPlanSummary(plan))"
                )
            }
            // Fall through to full rebuild
        }

        // Phase 7: skip body evaluation if no storage was mutated since last render.
        // But NOT when withObservationTracking's onChange fired — that callback
        // only runs once, and re-subscribing requires running body through
        // buildBodyWithTracking again. inputsUnchanged only tracks @State /
        // @Published generations, so it can't detect @Observable mutations and
        // would wrongly report "unchanged" here, leaving observation dead.
        if !fromObservation,
           let snapshot = lastInputSnapshot,
           inputsUnchanged(snapshot: snapshot) {
            gtkViewHostDebugLog("host rebuild skipped inputs unchanged host=\(ObjectIdentifier(self))")
            return
        }

        g_object_ref(gpointer(container))
        defer { g_object_unref(gpointer(container)) }
        let presentationRoot = gtk_widget_get_root(container).map { gpointer($0) }
        if let presentationRoot {
            g_object_ref(presentationRoot)
        }
        rebuildPresentationRoot = presentationRoot
        defer {
            if let presentationRoot {
                g_object_unref(presentationRoot)
            }
            rebuildPresentationRoot = nil
        }

        // Always save focus state before teardown — cursor/selection must
        // survive even when focus restore is suppressed (parity with Win32/Web).
        let focusInfo = saveFocusInfo(in: container)
        let scrollSnapshots = gtkCollectScrollAdjustmentSnapshots(in: container)

        // Capture old animatable state before teardown
        var oldOpacity: Double? = nil
        var oldOffsetX: Double? = nil
        var oldOffsetY: Double? = nil
        var oldScaleX: Double? = nil
        var oldScaleY: Double? = nil
        var oldRotation: Double? = nil
        if animation != nil, let oldChild = gtk_widget_get_first_child(container) {
            oldOpacity = gtk_widget_get_opacity(oldChild)
            oldOffsetX = getWidgetDouble(oldChild, key: "gtk-swift-offset-x")
            oldOffsetY = getWidgetDouble(oldChild, key: "gtk-swift-offset-y")
            oldScaleX = getWidgetDouble(oldChild, key: "gtk-swift-scale-x")
            oldScaleY = getWidgetDouble(oldChild, key: "gtk-swift-scale-y")
            oldRotation = getWidgetDouble(oldChild, key: "gtk-swift-rotation")
        }

        gtkBeginViewHostLifecycleRemountPass()
        defer { gtkEndViewHostLifecycleRemountPass() }

        // Remove old children
        while gtk_swift_is_widget(container) != 0, let child = gtk_widget_get_first_child(container) {
            gtk_box_remove(boxPointer(container), child)
        }

        // Set up rebuild context
        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(self)

        // Restore environment for the rebuild pass
        let previousEnv = getCurrentEnvironment()
        installRebuildEnvironment()
        resetOnChangeTracking()
        // Note: clearViewIDRegistry() is NOT called here because the registry
        // is global. Clearing it during one host's rebuild would wipe IDs from
        // sibling hosts. Instead, registerViewID() overwrites stale entries
        // during rebuild, and the scrollTo liveness check handles any remaining
        // stale pointers.
        beginDependencyTracking(host: self)
        let widget = buildBodyWithTracking()
        if let tracking = endDependencyTracking() {
            lastReadSet = tracking.readSet
            lastInputSnapshot = tracking.snapshots
        }
        setCurrentEnvironment(previousEnv)

        GTKViewHost.setCurrentRebuilding(previousHost)

        let newChild = widgetFromOpaque(widget)
        let childHexpand = gtk_widget_get_hexpand(newChild) != 0
        let childVexpand = gtk_widget_get_vexpand(newChild) != 0
        gtk_widget_set_hexpand(container, childHexpand ? 1 : 0)
        gtk_widget_set_vexpand(container, childVexpand ? 1 : 0)
        if childHexpand {
            gtk_widget_set_halign(newChild, GTK_ALIGN_FILL)
        }
        if childVexpand {
            gtk_widget_set_valign(newChild, GTK_ALIGN_FILL)
        }
        gtk_box_append(boxPointer(container), newChild)
        constrainCurrentChildToAllocatedWidth()
        gtkRestoreScrollAdjustmentSnapshots(scrollSnapshots, in: newChild)
        gtkScheduleScrollAdjustmentSnapshotRestore(scrollSnapshots, in: newChild)

        // If this subtree contains a NavigationStack titlebar, refresh it on the window.
        // We intentionally do NOT clear (pass nil) when no titlebar is found, because
        // sibling ViewHosts (e.g. GestureDemo) would clear the NavigationStack's
        // header bar that lives in a different subtree.
        if let titlebar = findTitlebarInRebuiltTree(newChild) {
            gtk_swift_set_root_window_titlebar(newChild, titlebar)
        }

        // Animate the transition: set old values, add CSS transition, then
        // schedule idle callback to apply new values — triggers CSS transition.
        if let animation = animation {
            let newOpacity = gtk_widget_get_opacity(newChild)
            let newOffsetX = getWidgetDouble(newChild, key: "gtk-swift-offset-x") ?? 0
            let newOffsetY = getWidgetDouble(newChild, key: "gtk-swift-offset-y") ?? 0
            let newScaleX = getWidgetDouble(newChild, key: "gtk-swift-scale-x") ?? 1
            let newScaleY = getWidgetDouble(newChild, key: "gtk-swift-scale-y") ?? 1
            let newRotation = getWidgetDouble(newChild, key: "gtk-swift-rotation") ?? 0

            let opacityChanged = oldOpacity != nil && oldOpacity != newOpacity
            let transformChanged = (oldOffsetX != nil && (oldOffsetX != newOffsetX || oldOffsetY != newOffsetY))
                || (oldScaleX != nil && (oldScaleX != newScaleX || oldScaleY != newScaleY))
                || (oldRotation != nil && oldRotation != newRotation)

            if opacityChanged || transformChanged {
                let timing: String
                switch animation.curve {
                case .linear:    timing = "linear"
                case .easeIn:    timing = "ease-in"
                case .easeOut:   timing = "ease-out"
                case .easeInOut: timing = "ease-in-out"
                case .spring:    timing = "cubic-bezier(0.5, 1.8, 0.3, 0.8)"
                }
                let duration = String(format: "%.2f", animation.duration)
                let delay = String(format: "%.2f", animation.delay)
                applyCSSToWidget(newChild, properties: "transition: all \(duration)s \(timing) \(delay)s;")

                // Set old values on the new widget
                if opacityChanged, let oldOp = oldOpacity {
                    gtk_widget_set_opacity(newChild, oldOp)
                }
                if transformChanged {
                    let ox = oldOffsetX ?? newOffsetX
                    let oy = oldOffsetY ?? newOffsetY
                    let sx = oldScaleX ?? newScaleX
                    let sy = oldScaleY ?? newScaleY
                    let r = oldRotation ?? newRotation
                    let oldTransform = buildTransformCSS(offsetX: ox, offsetY: oy, scaleX: sx, scaleY: sy, rotation: r)
                    if !oldTransform.isEmpty {
                        applyCSSToWidget(newChild, properties: oldTransform)
                    }
                }

                // On next frame, apply final values — CSS transition interpolates
                let ctx = AnimationTransitionContext(
                    widget: newChild,
                    targetOpacity: opacityChanged ? newOpacity : nil,
                    targetTransform: transformChanged
                        ? buildTransformCSS(offsetX: newOffsetX, offsetY: newOffsetY, scaleX: newScaleX, scaleY: newScaleY, rotation: newRotation)
                        : nil
                )
                let retained = Unmanaged.passRetained(ctx).toOpaque()
                g_idle_add({ userData -> gboolean in
                    let ctx = Unmanaged<AnimationTransitionContext>.fromOpaque(userData!).takeRetainedValue()
                    guard gtk_swift_is_widget(ctx.widget) != 0 else { return 0 }
                    if let opacity = ctx.targetOpacity {
                        gtk_widget_set_opacity(ctx.widget, opacity)
                    }
                    if let transform = ctx.targetTransform {
                        applyCSSToWidget(ctx.widget, properties: transform)
                    }
                    return 0 // G_SOURCE_REMOVE
                }, retained)
            }
        }

        let rebuiltDescriptorState: RebuiltDescriptorState?
        if let describeBody = describeBody {
            let previousEnvForDesc = getCurrentEnvironment()
            installRebuildEnvironment()
            let described = describeBodyCapturingPayloads(describeBody)
            setCurrentEnvironment(previousEnvForDesc)

            let identified = gtkIdentifyDescriptorTree(described.descriptor)
            let canvasPayloads = gtkCanvasPayloadsByIdentity(
                descriptorRoot: identified,
                payloads: described.canvasPayloads
            )
            updateOnAppearLifecycle(
                descriptorRoot: identified,
                onAppearPayloads: renderCapturedOnAppearPayloads(fallback: described.onAppearPayloads)
            )
            updateTaskLifecycle(
                descriptorRoot: identified,
                taskPayloads: renderCapturedTaskPayloads(fallback: described.taskPayloads)
            )
            gtkTagFocusableInputIdentities(in: newChild, descriptorRoot: identified)
            rebuiltDescriptorState = RebuiltDescriptorState(
                identified: identified,
                canvasPayloadsByIdentity: canvasPayloads
            )
        } else {
            rebuiltDescriptorState = nil
        }

        // Restore focus/cursor to the matching input after rebuild.
        // When suppressed, skip grab_focus but still restore cursor/selection.
        if let info = focusInfo {
            restoreFocusInfo(info, in: newChild, suppressFocus: !shouldRestoreFocus)
        }

        // Capture descriptor state for next rebuild's narrow mutation path
        if let rebuiltDescriptorState {
            lastRetainedDescriptor = gtkRetainDescriptorTree(rebuiltDescriptorState.identified)
            var executor = gtkMakeExecutorTree(
                from: rebuiltDescriptorState.identified,
                canvasPayloadsByIdentity: rebuiltDescriptorState.canvasPayloadsByIdentity
            )
            executor = gtkCaptureSupportedNativeSlots(
                from: newChild,
                descriptorRoot: rebuiltDescriptorState.identified,
                executorRoot: executor
            )
            executor = gtkCaptureButtonNativeSlots(
                from: newChild,
                descriptorRoot: rebuiltDescriptorState.identified,
                executorRoot: executor
            )
            retainedExecutor = executor
        }
    }

    // MARK: - Thread-local rebuild context

    static func getCurrentRebuilding() -> GTKViewHost? {
        guard let ptr = pthread_getspecific(rebuildingViewHostKey) else { return nil }
        return Unmanaged<GTKViewHost>.fromOpaque(ptr).takeUnretainedValue()
    }

    static func setCurrentRebuilding(_ host: GTKViewHost?) {
        if let host = host {
            let ptr = Unmanaged.passUnretained(host).toOpaque()
            pthread_setspecific(rebuildingViewHostKey, ptr)
        } else {
            pthread_setspecific(rebuildingViewHostKey, nil)
        }
    }

    func constrainCurrentChildToAllocatedWidth() {
        let width = gtk_widget_get_width(container)
        let height = gtk_widget_get_height(container)
        guard let child = gtk_widget_get_first_child(container) else {
            return
        }
        guard (width > 1 && width != lastConstrainedChildWidth)
            || (height > 1 && height != lastConstrainedChildHeight && gtk_widget_get_vexpand(child) != 0)
        else {
            return
        }
        if width > 1 {
            lastConstrainedChildWidth = width
        }
        if height > 1 {
            lastConstrainedChildHeight = height
        }
        let horizontalMargins = gtk_widget_get_margin_start(child)
            + gtk_widget_get_margin_end(child)
        let verticalMargins = gtk_widget_get_margin_top(child)
            + gtk_widget_get_margin_bottom(child)
        let childWidth = width > 1 ? max(gint(1), width - horizontalMargins) : -1
        let childHeight = height > 1 && gtk_widget_get_vexpand(child) != 0
            ? max(gint(1), height - verticalMargins)
            : -1
        gtk_widget_set_size_request(child, childWidth, childHeight)
        if childWidth > 0 {
            gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        }
        if childHeight > 0 {
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        }
        gtk_widget_queue_resize(child)
        gtk_widget_queue_resize(container)
    }
}

func gtkResumeViewHostLifecycleForVisibleSubtree(_ widget: UnsafeMutablePointer<GtkWidget>) {
    func walk(_ node: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard depth < 128, gtk_swift_is_widget(node) != 0 else { return }
        if let rawHost = g_object_get_data(
            UnsafeMutableRawPointer(node).assumingMemoryBound(to: GObject.self),
            "gtk-swift-view-host"
        ) {
            let host = Unmanaged<GTKViewHost>.fromOpaque(rawHost).takeUnretainedValue()
            host.resumeLifecycleAfterProgrammaticVisibilityChange()
        }

        var child = gtk_widget_get_first_child(node)
        while let current = child {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(widget, depth: 0)
}

private let gtkViewHostWidthTickCallback: GtkTickCallback = { _, _, userData in
    guard let userData else { return 0 }
    let host = Unmanaged<GTKViewHost>.fromOpaque(userData).takeUnretainedValue()
    host.constrainCurrentChildToAllocatedWidth()
    return 1
}

/// Recursively search a rebuilt subtree for a window titlebar attachment point.
private func findTitlebarInRebuiltTree(_ widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    if let data = g_object_get_data(gobject, "gtk-swift-window-titlebar") {
        return UnsafeMutableRawPointer(data).assumingMemoryBound(to: GtkWidget.self)
    }

    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    if typeName == "GtkStack" {
        let stackOp = OpaquePointer(widget)
        if let visibleChild = gtk_stack_get_visible_child(stackOp) {
            return findTitlebarInRebuiltTree(visibleChild)
        }
        return nil
    }

    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let found = findTitlebarInRebuiltTree(c) {
            return found
        }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}

// MARK: - Animation transition context

/// Holds state for deferred animation on a rebuilt widget.
private class AnimationTransitionContext {
    let widget: UnsafeMutablePointer<GtkWidget>
    let targetOpacity: Double?
    let targetTransform: String?

    init(widget: UnsafeMutablePointer<GtkWidget>, targetOpacity: Double?, targetTransform: String?) {
        self.widget = widget
        self.targetOpacity = targetOpacity
        self.targetTransform = targetTransform
        g_object_ref(gpointer(widget))
    }

    deinit {
        g_object_unref(gpointer(widget))
    }
}

private struct RebuiltDescriptorState {
    let identified: GTK4IdentifiedDescriptorNode
    let canvasPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4CanvasPayload]
}

private func gtkUpdateButtonActions(
    in node: GTK4RetainedExecutorNode,
    payloadsByIdentity: [GTK4DescriptorIdentity: GTK4ButtonPayload]
) -> Bool {
    var succeeded = true
    if node.kind == .button {
        guard let slotID = node.nativeSlotID,
              let payload = payloadsByIdentity[node.identity],
              gtkSetButtonAction(slotID: slotID, action: payload.action) else {
            return false
        }
    }
    for child in node.children {
        succeeded = gtkUpdateButtonActions(in: child, payloadsByIdentity: payloadsByIdentity) && succeeded
    }
    return succeeded
}

// MARK: - Focus preservation across rebuilds

/// Info about a focused editable widget, used to restore focus after rebuild.
private struct FocusInfo {
    /// DFS index of the focused input within the container tree.
    let editableIndex: Int
    /// Descriptor identity attached to the focused input, when available.
    let descriptorIdentity: GTK4DescriptorIdentity?
    /// Stable binding/view-derived key attached to the focused input, when available.
    let stableFocusKey: String?
    /// Cursor position within the editable text.
    let cursorPosition: Int
    /// Whether the focused widget was a GtkTextView (vs GtkEditable).
    let isTextView: Bool
    /// Whether the focused widget was a GtkScale/GtkRange (no cursor needed).
    let isScale: Bool
    /// Selection start offset (-1 if no selection).
    let selectionStart: Int
    /// Selection end offset (-1 if no selection).
    let selectionEnd: Int
}

/// Check if a widget is a focusable input (GtkEditable, GtkTextView, or GtkScale).
private func isFocusableInput(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    guard gtk_swift_is_widget(widget) != 0 else { return false }
    if gtk_swift_widget_is_editable(widget) != 0 { return true }
    if gtk_swift_widget_is_scale(widget) != 0 { return true }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    return typeName == "GtkTextView"
}

/// Check if a widget is a GtkScale/GtkRange.
private func isScale(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    guard gtk_swift_is_widget(widget) != 0 else { return false }
    return gtk_swift_widget_is_scale(widget) != 0
}

/// Check if a widget is a GtkTextView.
private func isTextView(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    guard gtk_swift_is_widget(widget) != 0 else { return false }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    return typeName == "GtkTextView"
}

private enum FocusableInputKind {
    case editable
    case textView
    case scale
}

private struct FocusableDescriptorEntry {
    let descriptorIdentity: GTK4DescriptorIdentity
    let stableFocusKey: String?
    let inputKind: FocusableInputKind
}

private final class FocusIdentityBox {
    let descriptorIdentity: GTK4DescriptorIdentity
    let stableFocusKey: String?

    init(descriptorIdentity: GTK4DescriptorIdentity, stableFocusKey: String?) {
        self.descriptorIdentity = descriptorIdentity
        self.stableFocusKey = stableFocusKey
    }
}

private let focusIdentityKey = "gtk-swift-focus-identity"

func gtkTagFocusableInputIdentities(
    in widgetRoot: UnsafeMutablePointer<GtkWidget>,
    descriptorRoot: GTK4IdentifiedDescriptorNode
) {
    let descriptors = collectFocusableDescriptorEntries(from: descriptorRoot)
    var widgets: [UnsafeMutablePointer<GtkWidget>] = []
    collectFocusableInputWidgets(in: widgetRoot, into: &widgets)

    guard descriptors.count == widgets.count else { return }
    for (descriptor, widget) in zip(descriptors, widgets) {
        guard focusableDescriptor(descriptor, matches: widget) else { return }
    }
    for (descriptor, widget) in zip(descriptors, widgets) {
        setFocusIdentityRecursively(
            descriptorIdentity: descriptor.descriptorIdentity,
            stableFocusKey: descriptor.stableFocusKey,
            on: widget
        )
    }
}

private func collectFocusableDescriptorEntries(
    from node: GTK4IdentifiedDescriptorNode
) -> [FocusableDescriptorEntry] {
    var result: [FocusableDescriptorEntry] = []
    if let entry = focusableDescriptorEntry(for: node) {
        result.append(entry)
    }
    for child in node.children {
        result.append(contentsOf: collectFocusableDescriptorEntries(from: child))
    }
    return result
}

private func focusableDescriptorEntry(
    for node: GTK4IdentifiedDescriptorNode
) -> FocusableDescriptorEntry? {
    switch node.descriptor.typeName {
    case "TextField", "SecureField":
        return FocusableDescriptorEntry(
            descriptorIdentity: node.identity,
            stableFocusKey: stableFocusKey(from: node.descriptor),
            inputKind: .editable
        )
    case "TextEditor":
        return FocusableDescriptorEntry(
            descriptorIdentity: node.identity,
            stableFocusKey: stableFocusKey(from: node.descriptor),
            inputKind: .textView
        )
    default:
        break
    }

    if node.descriptor.kind == .slider {
        return FocusableDescriptorEntry(
            descriptorIdentity: node.identity,
            stableFocusKey: nil,
            inputKind: .scale
        )
    }
    return nil
}

private func stableFocusKey(from descriptor: GTK4DescriptorNode) -> String? {
    guard case let .text(textDescriptor) = descriptor.props else { return nil }
    return textDescriptor.content
}

private func collectFocusableInputWidgets(
    in widget: UnsafeMutablePointer<GtkWidget>,
    into result: inout [UnsafeMutablePointer<GtkWidget>]
) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    if isFocusableInput(widget) {
        result.append(widget)
        return
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        collectFocusableInputWidgets(in: c, into: &result)
        child = gtk_widget_get_next_sibling(c)
    }
}

private func focusableDescriptor(
    _ descriptor: FocusableDescriptorEntry,
    matches widget: UnsafeMutablePointer<GtkWidget>
) -> Bool {
    switch descriptor.inputKind {
    case .editable:
        return gtk_swift_widget_is_editable(widget) != 0
    case .textView:
        return isTextView(widget)
    case .scale:
        return isScale(widget)
    }
}

private func setFocusIdentityRecursively(
    descriptorIdentity: GTK4DescriptorIdentity,
    stableFocusKey: String?,
    on widget: UnsafeMutablePointer<GtkWidget>
) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    if isFocusableInput(widget) {
        setFocusIdentity(
            descriptorIdentity: descriptorIdentity,
            stableFocusKey: stableFocusKey,
            on: widget
        )
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        setFocusIdentityRecursively(
            descriptorIdentity: descriptorIdentity,
            stableFocusKey: stableFocusKey,
            on: c
        )
        child = gtk_widget_get_next_sibling(c)
    }
}

private func setFocusIdentity(
    descriptorIdentity: GTK4DescriptorIdentity,
    stableFocusKey: String?,
    on widget: UnsafeMutablePointer<GtkWidget>
) {
    let box = FocusIdentityBox(
        descriptorIdentity: descriptorIdentity,
        stableFocusKey: stableFocusKey
    )
    let retained = Unmanaged.passRetained(box).toOpaque()
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data_full(
        gobject,
        focusIdentityKey,
        retained,
        { data in
            guard let data else { return }
            Unmanaged<FocusIdentityBox>.fromOpaque(data).release()
        }
    )
}

private func focusIdentity(
    of widget: UnsafeMutablePointer<GtkWidget>
) -> FocusIdentityBox? {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let raw = g_object_get_data(gobject, focusIdentityKey) else { return nil }
    return Unmanaged<FocusIdentityBox>.fromOpaque(raw).takeUnretainedValue()
}

/// Walk the widget subtree and find the focused editable, recording its DFS index and cursor.
private func saveFocusInfo(in container: UnsafeMutablePointer<GtkWidget>) -> FocusInfo? {
    var index = 0
    return findFocusedEditable(in: container, index: &index)
}

private func findFocusedEditable(in widget: UnsafeMutablePointer<GtkWidget>, index: inout Int) -> FocusInfo? {
    guard gtk_swift_is_widget(widget) != 0 else { return nil }
    if gtk_widget_is_focus(widget) != 0 && isFocusableInput(widget) {
        let identity = focusIdentity(of: widget)
        if isScale(widget) {
            // Scale/Range widgets need focus restored but have no cursor or selection.
            return FocusInfo(
                editableIndex: index,
                descriptorIdentity: identity?.descriptorIdentity,
                stableFocusKey: identity?.stableFocusKey,
                cursorPosition: 0,
                isTextView: false,
                isScale: true,
                selectionStart: -1,
                selectionEnd: -1
            )
        } else if isTextView(widget) {
            let tvPtr = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkTextView.self)
            let buffer = gtk_text_view_get_buffer(tvPtr)!
            var iter = GtkTextIter()
            gtk_text_buffer_get_iter_at_mark(buffer, &iter, gtk_text_buffer_get_insert(buffer))
            let pos = Int(gtk_text_iter_get_offset(&iter))
            // Check for text selection
            var selStart = GtkTextIter()
            var selEnd = GtkTextIter()
            let hasSel = gtk_text_buffer_get_selection_bounds(buffer, &selStart, &selEnd)
            let ss = hasSel != 0 ? Int(gtk_text_iter_get_offset(&selStart)) : -1
            let se = hasSel != 0 ? Int(gtk_text_iter_get_offset(&selEnd)) : -1
            return FocusInfo(
                editableIndex: index,
                descriptorIdentity: identity?.descriptorIdentity,
                stableFocusKey: identity?.stableFocusKey,
                cursorPosition: pos,
                isTextView: true,
                isScale: false,
                selectionStart: ss,
                selectionEnd: se
            )
        } else {
            let editable = OpaquePointer(widget)
            let pos = Int(gtk_editable_get_position(editable))
            // Check for text selection
            var ss: gint = 0
            var se: gint = 0
            let hasSel = gtk_editable_get_selection_bounds(editable, &ss, &se)
            let selStart = hasSel != 0 ? Int(ss) : -1
            let selEnd = hasSel != 0 ? Int(se) : -1
            return FocusInfo(
                editableIndex: index,
                descriptorIdentity: identity?.descriptorIdentity,
                stableFocusKey: identity?.stableFocusKey,
                cursorPosition: pos,
                isTextView: false,
                isScale: false,
                selectionStart: selStart,
                selectionEnd: selEnd
            )
        }
    }
    if isFocusableInput(widget) {
        index += 1
    }

    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let info = findFocusedEditable(in: c, index: &index) {
            return info
        }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}

/// Find the nth focusable input in the new subtree and grab focus + set cursor/selection.
private func restoreFocusInfo(_ info: FocusInfo, in widget: UnsafeMutablePointer<GtkWidget>, suppressFocus: Bool = false) {
    var target: UnsafeMutablePointer<GtkWidget>?
    if let stableFocusKey = info.stableFocusKey {
        target = findUniqueEditable(in: widget, stableFocusKey: stableFocusKey)
    }
    if target == nil, let descriptorIdentity = info.descriptorIdentity {
        target = findEditable(in: widget, descriptorIdentity: descriptorIdentity)
    }
    if target == nil {
        var index = 0
        target = findNthEditable(in: widget, targetIndex: info.editableIndex, index: &index)
    }

    guard let target else { return }
    guard focusInfo(info, matches: target) else { return }
    restoreFocusAndSelection(info, to: target, suppressFocus: suppressFocus)
}

private func focusInfo(_ info: FocusInfo, matches target: UnsafeMutablePointer<GtkWidget>) -> Bool {
    guard gtk_swift_is_widget(target) != 0 else { return false }
    if info.isScale {
        return isScale(target)
    }
    if info.isTextView {
        return isTextView(target)
    }
    return gtk_swift_widget_is_editable(target) != 0 && !isTextView(target)
}

private func debugLogRebuild(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    FileHandle.standardError.write(Data(("[QuillUI GTK] " + message + "\n").utf8))
}

/// Debug-only: names the first node that disqualifies a plan from the narrow
/// mutation path, mirroring gtkCanApplyTextColorHostMutation's walk.
private func gtkDescribeDescriptorPlanSummary(_ plan: GTK4DescriptorPlan) -> String {
    gtkFirstNarrowRejection(plan) ?? "no-rejection-found"
}

private func gtkFirstNarrowRejection(_ plan: GTK4DescriptorPlan) -> String? {
    switch plan.kind {
    case .create:
        return "create \(plan.newDescriptor.kind) \(plan.newDescriptor.typeName)"
    case .replace:
        return "replace \(plan.newDescriptor.kind) \(plan.newDescriptor.typeName)"
    case .reuse:
        if plan.newDescriptor.kind == .composite && plan.children.isEmpty {
            if case .none = plan.newDescriptor.props {
                return "reuse empty composite \(plan.newDescriptor.typeName)"
            }
        }
        for child in plan.children {
            if let reason = gtkFirstNarrowRejection(child) { return reason }
        }
        return nil
    case .update:
        if plan.newDescriptor.kind == .button {
            return "update button \(plan.newDescriptor.typeName)"
        }
        guard plan.updateIntent == .textContent || plan.updateIntent == .colorFill
                || plan.updateIntent == .canvasContent
                || plan.updateIntent == .sliderValue
                || plan.updateIntent == .paddingLayout else {
            return "update \(plan.newDescriptor.kind) intent=\(plan.updateIntent) \(plan.newDescriptor.typeName)"
        }
        for child in plan.children {
            if let reason = gtkFirstNarrowRejection(child) { return reason }
        }
        return nil
    }
}

private final class DeferredFocusGrabTarget {
    let widget: UnsafeMutablePointer<GtkWidget>
    var retries = 0

    init(widget: UnsafeMutablePointer<GtkWidget>) {
        self.widget = widget
    }
}

/// A focus grab on a widget GTK has not allocated yet fails silently, and
/// restoreFocusInfo runs immediately after a rebuild creates its children —
/// before the next frame maps them. Keyboard focus then falls to the window's
/// first focusable button and typed keys (especially Space) activate it.
/// Defer the grab until the widget has a real allocation.
private func scheduleDeferredFocusGrab(_ widget: UnsafeMutablePointer<GtkWidget>) {
    g_object_ref(gpointer(widget))
    let target = DeferredFocusGrabTarget(widget: widget)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let target = Unmanaged<DeferredFocusGrabTarget>.fromOpaque(userData).takeUnretainedValue()
        func finish() -> gboolean {
            g_object_unref(gpointer(target.widget))
            Unmanaged<DeferredFocusGrabTarget>.fromOpaque(userData).release()
            return 0
        }
        guard gtk_swift_is_widget(target.widget) != 0 else { return finish() }
        if gtk_widget_get_width(target.widget) <= 1 {
            target.retries += 1
            return target.retries <= 120 ? 1 : finish()
        }
        gtk_widget_grab_focus(target.widget)
        return finish()
    }, Unmanaged.passRetained(target).toOpaque())
}

private func restoreFocusAndSelection(
    _ info: FocusInfo,
    to target: UnsafeMutablePointer<GtkWidget>,
    suppressFocus: Bool
) {
    if !suppressFocus {
        if gtk_widget_get_width(target) > 1 {
            gtk_widget_grab_focus(target)
        } else {
            scheduleDeferredFocusGrab(target)
        }
    }
    if info.isScale {
        // Scale only needs focus, no cursor or selection to restore.
        return
    }
    if info.isTextView {
        guard isTextView(target) else { return }
        let tvPtr = UnsafeMutableRawPointer(target).assumingMemoryBound(to: GtkTextView.self)
        guard let buffer = gtk_text_view_get_buffer(tvPtr) else { return }
        if info.selectionStart >= 0 && info.selectionEnd >= 0 {
            // Restore selection range
            var selStart = GtkTextIter()
            var selEnd = GtkTextIter()
            gtk_text_buffer_get_iter_at_offset(buffer, &selStart, gint(info.selectionStart))
            gtk_text_buffer_get_iter_at_offset(buffer, &selEnd, gint(info.selectionEnd))
            gtk_text_buffer_select_range(buffer, &selStart, &selEnd)
        } else {
            // Restore cursor position only
            var iter = GtkTextIter()
            gtk_text_buffer_get_iter_at_offset(buffer, &iter, gint(info.cursorPosition))
            gtk_text_buffer_place_cursor(buffer, &iter)
        }
    } else {
        guard gtk_swift_widget_is_editable(target) != 0 else { return }
        let editable = OpaquePointer(target)
        if info.selectionStart >= 0 && info.selectionEnd >= 0 {
            // Restore selection range (also moves cursor to selectionEnd)
            gtk_editable_select_region(editable, gint(info.selectionStart), gint(info.selectionEnd))
        } else {
            // Restore cursor position only
            gtk_editable_set_position(editable, gint(info.cursorPosition))
        }
    }
}

private func findUniqueEditable(
    in widget: UnsafeMutablePointer<GtkWidget>,
    stableFocusKey: String
) -> UnsafeMutablePointer<GtkWidget>? {
    var matches: [UnsafeMutablePointer<GtkWidget>] = []
    collectEditableMatches(in: widget, stableFocusKey: stableFocusKey, into: &matches)
    return matches.count == 1 ? matches[0] : nil
}

private func collectEditableMatches(
    in widget: UnsafeMutablePointer<GtkWidget>,
    stableFocusKey: String,
    into matches: inout [UnsafeMutablePointer<GtkWidget>]
) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    if isFocusableInput(widget), focusIdentity(of: widget)?.stableFocusKey == stableFocusKey {
        matches.append(widget)
        return
    }
    if isFocusableInput(widget) {
        return
    }

    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        collectEditableMatches(in: c, stableFocusKey: stableFocusKey, into: &matches)
        child = gtk_widget_get_next_sibling(c)
    }
}

private func findEditable(
    in widget: UnsafeMutablePointer<GtkWidget>,
    descriptorIdentity: GTK4DescriptorIdentity
) -> UnsafeMutablePointer<GtkWidget>? {
    guard gtk_swift_is_widget(widget) != 0 else { return nil }
    if isFocusableInput(widget), focusIdentity(of: widget)?.descriptorIdentity == descriptorIdentity {
        return widget
    }
    if isFocusableInput(widget) {
        return nil
    }

    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let found = findEditable(in: c, descriptorIdentity: descriptorIdentity) {
            return found
        }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}

private func findNthEditable(in widget: UnsafeMutablePointer<GtkWidget>, targetIndex: Int, index: inout Int) -> UnsafeMutablePointer<GtkWidget>? {
    guard gtk_swift_is_widget(widget) != 0 else { return nil }
    if isFocusableInput(widget) {
        if index == targetIndex {
            return widget
        }
        index += 1
    }

    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let found = findNthEditable(in: c, targetIndex: targetIndex, index: &index) {
            return found
        }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}
