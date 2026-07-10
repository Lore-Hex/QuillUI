import CGTK
import CGTKBridge
import SwiftOpenUI
import Foundation

// MARK: - Helpers

private func gtkNavigationDebugLog(_ message: String) {
    let env = ProcessInfo.processInfo.environment
    guard env["QUILLUI_GTK_DEBUG_ACTIONS"] == "1"
        || env["QUILLUI_GTK_DEBUG"] == "1"
        || env["SWIFTOPENUI_GTK_DEBUG"] == "1" else {
        return
    }
    FileHandle.standardError.write(Data("[SwiftOpenUI][Navigation] \(message)\n".utf8))
}

private func gtkNavigationDebugLabelPreview(
    in widget: UnsafeMutablePointer<GtkWidget>,
    limit: Int = 12
) -> [String] {
    var labels: [String] = []

    func walk(_ node: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard depth < 96, labels.count < limit else { return }
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(node)))
        if typeName == "GtkLabel" {
            labels.append(String(cString: gtk_label_get_text(OpaquePointer(node))))
        }

        var child = gtk_widget_get_first_child(node)
        while let current = child, labels.count < limit {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(widget, depth: 0)
    return labels
}

/// Box for passing a widget pointer through a C callback.
private class WidgetRef {
    let widget: UnsafeMutablePointer<GtkWidget>
    init(_ widget: UnsafeMutablePointer<GtkWidget>) { self.widget = widget }
}

/// Result from resolving a navigation destination.
struct GTKResolvedDestination {
    let widget: OpaquePointer
    let title: String
    let toolbarItems: [AnyToolbarItem]
}

private struct GTKDeferredNavigationDestination {
    let title: String
    let toolbarItems: [AnyToolbarItem]
    let render: () -> OpaquePointer
}

private enum GTKNavigationPersistedRoute {
    case value(AnyHashable)
    case destination(
        stateNamespace: String?,
        makeDestination: (GTKNavigationContext) -> GTKDeferredNavigationDestination?
    )
}

private struct GTKPendingPresentedNavigationDestination {
    let stateNamespace: String
    let isPresented: Binding<Bool>
    let route: GTKNavigationPersistedRoute
}

private let gtkNavigationPersistedRoutesLock = NSLock()
private var gtkNavigationPersistedRoutesByNamespace: [String: [GTKNavigationPersistedRoute]] = [:]

private func gtkNavigationPersistedRoutes(for stateNamespace: String) -> [GTKNavigationPersistedRoute] {
    gtkNavigationPersistedRoutesLock.lock()
    defer { gtkNavigationPersistedRoutesLock.unlock() }
    return gtkNavigationPersistedRoutesByNamespace[stateNamespace] ?? []
}

private func gtkNavigationSetPersistedRoutes(
    _ routes: [GTKNavigationPersistedRoute],
    for stateNamespace: String
) {
    gtkNavigationPersistedRoutesLock.lock()
    if routes.isEmpty {
        gtkNavigationPersistedRoutesByNamespace.removeValue(forKey: stateNamespace)
    } else {
        gtkNavigationPersistedRoutesByNamespace[stateNamespace] = routes
    }
    gtkNavigationPersistedRoutesLock.unlock()
}

// MARK: - Navigation context (GTK-specific)

/// Entry in the navigation stack.
struct GTKNavigationEntry {
    let title: String
    let name: String
    let stateNamespace: String
    let widget: UnsafeMutablePointer<GtkWidget>
    var toolbarWidgets: [(widget: UnsafeMutablePointer<GtkWidget>, placement: ToolbarItemPlacement)] = []
}

/// Manages the navigation stack state for GTK4.
/// Shared between NavigationStack and NavigationLink via thread-local capture at render time.
class GTKNavigationContext {
    let stack: OpaquePointer          // GtkStack
    let headerBar: OpaquePointer      // GtkHeaderBar
    let backButton: UnsafeMutablePointer<GtkWidget>
    let stateNamespace: String
    var entries: [GTKNavigationEntry] = []
    var nameCounter = 0

    /// Registry for type-based navigation destinations.
    let destinationRegistry = GTKNavigationDestinationRegistry()

    /// Optional binding to a NavigationPath for programmatic navigation sync.
    var pathBinding: Binding<NavigationPath>?
    var typedPathBinding: AnyNavigationPathBinding?

    /// Guard against re-entrant sync between path and stack.
    private var isSyncing = false
    private var representedPath: [AnyHashable] = []
    private var persistedRoutes: [GTKNavigationPersistedRoute] = []
    private var presentedDestinationBindings: [String: Binding<Bool>] = [:]
    private var pendingPresentedDestinations: [GTKPendingPresentedNavigationDestination] = []

    private var shouldPersistUnboundValueRoutes: Bool {
        pathBinding == nil && typedPathBinding == nil
    }

    init(
        stack: OpaquePointer,
        headerBar: OpaquePointer,
        backButton: UnsafeMutablePointer<GtkWidget>,
        stateNamespace: String
    ) {
        self.stack = stack
        self.headerBar = headerBar
        self.backButton = backButton
        self.stateNamespace = stateNamespace
    }

    /// Push a new view onto the navigation stack.
    @discardableResult
    func push(
        title: String,
        toolbarItems: [AnyToolbarItem] = [],
        stateNamespace: String? = nil,
        content: @escaping () -> OpaquePointer
    ) -> String {
        let name = "nav-\(nameCounter)"
        nameCounter += 1

        // Remove current entry's toolbar widgets
        removeCurrentToolbarWidgets()

        let pageNamespace = stateNamespace ?? "\(self.stateNamespace)::Entry[\(name)]"
        let widget = widgetFromOpaque(
            gtkWithForcedStateIdentityNamespace(pageNamespace) {
                content()
            }
        )
        gtkConfigureNavigationPageToFillAllocation(widget)
        gtk_stack_add_named(stack, widget, name)

        var entry = GTKNavigationEntry(
            title: title,
            name: name,
            stateNamespace: pageNamespace,
            widget: widget
        )

        // Install new toolbar items into header bar
        for item in toolbarItems {
            let itemWidget = widgetFromOpaque(gtkRenderAnyView(item.wrapped))
            switch item.placement {
            case .leading:
                gtk_header_bar_pack_start(headerBar, itemWidget)
            case .center:
                gtk_header_bar_set_title_widget(headerBar, itemWidget)
            case .primaryAction, .trailing:
                gtk_header_bar_pack_end(headerBar, itemWidget)
            }
            g_object_ref(gpointer(itemWidget))
            entry.toolbarWidgets.append((widget: itemWidget, placement: item.placement))
        }

        entries.append(entry)

        // Bound-path reconciliation can happen repeatedly during state-host
        // rebuilds. Avoid restarting a slide transition and exposing stale
        // root content while the path already points at the destination.
        gtk_stack_set_transition_type(
            stack,
            isSyncing ? GTK_STACK_TRANSITION_TYPE_NONE : GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT
        )
        gtk_stack_set_visible_child_name(stack, name)
        gtkResumeViewHostLifecycleForVisibleSubtree(widget)
        g_object_ref(gpointer(widget))
        g_idle_add({ userData -> gboolean in
            let widgetRef = Unmanaged<WidgetRef>.fromOpaque(userData!).takeRetainedValue()
            if gtk_swift_is_widget(widgetRef.widget) != 0 {
                gtkResumeViewHostLifecycleForVisibleSubtree(widgetRef.widget)
            }
            g_object_unref(gpointer(widgetRef.widget))
            return 0
        }, Unmanaged.passRetained(WidgetRef(widget)).toOpaque())
        updateHeaderBar()
        return pageNamespace
    }

    /// Push a hashable value, resolving destination via the registry.
    @discardableResult
    func pushValue(_ value: AnyHashable, persist: Bool = true) -> Bool {
        guard let resolved = destinationRegistry.resolve(value) else {
            gtkNavigationDebugLog("unresolved path element type=\(type(of: value.base))")
            return false
        }

        let title = resolved.title
        gtkNavigationDebugLog(
            "push value type=\(type(of: value.base)) title=\(title) "
            + "labels=\(gtkNavigationDebugLabelPreview(in: widgetFromOpaque(resolved.widget)))"
        )
        push(
            title: title,
            toolbarItems: resolved.toolbarItems,
            stateNamespace: navigationDestinationStateNamespace(for: value)
        ) {
            resolved.widget
        }
        representedPath.append(value)
        if persist && shouldPersistUnboundValueRoutes && !isSyncing {
            appendPersistedRoute(.value(value))
        }
        syncPathAfterPush(value)
        return true
    }

    func nextDestinationStateNamespace() -> String {
        "\(stateNamespace)::Entry[nav-\(nameCounter)]"
    }

    @discardableResult
    fileprivate func pushDestinationRoute(
        _ route: GTKNavigationPersistedRoute,
        persist: Bool = true
    ) -> Bool {
        guard case let .destination(routeStateNamespace, makeDestination) = route,
              let resolved = makeDestination(self) else {
            return false
        }
        let destinationStateNamespace = routeStateNamespace ?? nextDestinationStateNamespace()
        let routeToPersist: GTKNavigationPersistedRoute
        if routeStateNamespace == nil {
            routeToPersist = .destination(
                stateNamespace: destinationStateNamespace,
                makeDestination: makeDestination
            )
        } else {
            routeToPersist = route
        }

        gtkNavigationDebugLog(
            "push destination title=\(resolved.title) stateNamespace=\(destinationStateNamespace)"
        )
        push(
            title: resolved.title,
            toolbarItems: resolved.toolbarItems,
            stateNamespace: destinationStateNamespace
        ) {
            resolved.render()
        }
        if persist && !isSyncing {
            appendPersistedRoute(routeToPersist)
        }
        return true
    }

    func restorePersistedRoutesIfNeeded() {
        guard representedPath.isEmpty, entries.count == 1 else {
            return
        }
        let routes = gtkNavigationPersistedRoutes(for: stateNamespace)
        guard !routes.isEmpty else { return }

        gtkNavigationDebugLog("restore persisted routes count=\(routes.count)")
        isSyncing = true
        persistedRoutes = routes
        for route in routes {
            switch route {
            case .value(let value):
                _ = pushValue(value, persist: false)
            case .destination:
                _ = pushDestinationRoute(route, persist: false)
            }
        }
        isSyncing = false
    }

    private func appendPersistedRoute(_ route: GTKNavigationPersistedRoute) {
        persistedRoutes.append(route)
        gtkNavigationSetPersistedRoutes(persistedRoutes, for: stateNamespace)
    }

    private func removeLastPersistedRouteAfterPop() {
        guard !isSyncing else { return }
        if !persistedRoutes.isEmpty {
            persistedRoutes.removeLast()
        }
        gtkNavigationSetPersistedRoutes(persistedRoutes, for: stateNamespace)
    }

    func hasPresentedDestination(stateNamespace: String) -> Bool {
        entries.contains { $0.stateNamespace == stateNamespace }
    }

    fileprivate func enqueuePresentedDestination(
        stateNamespace: String,
        isPresented: Binding<Bool>,
        route: GTKNavigationPersistedRoute
    ) {
        guard isPresented.wrappedValue else { return }
        guard !hasPresentedDestination(stateNamespace: stateNamespace) else { return }
        guard !pendingPresentedDestinations.contains(where: { $0.stateNamespace == stateNamespace }) else {
            return
        }
        pendingPresentedDestinations.append(
            GTKPendingPresentedNavigationDestination(
                stateNamespace: stateNamespace,
                isPresented: isPresented,
                route: route
            )
        )
    }

    func flushPendingPresentedDestinations() {
        let pending = pendingPresentedDestinations
        pendingPresentedDestinations.removeAll()

        for destination in pending where destination.isPresented.wrappedValue {
            guard !hasPresentedDestination(stateNamespace: destination.stateNamespace) else { continue }
            if pushDestinationRoute(destination.route) {
                presentedDestinationBindings[destination.stateNamespace] = destination.isPresented
            }
        }
    }

    private func clearPresentedDestinationBindingIfNeeded(for stateNamespace: String) {
        guard let binding = presentedDestinationBindings.removeValue(forKey: stateNamespace) else {
            return
        }
        if binding.wrappedValue {
            binding.wrappedValue = false
        }
    }

    /// Pop the top view from the navigation stack.
    func pop() {
        guard entries.count > 1 else { return }

        removeCurrentToolbarWidgets()
        let removed = entries.removeLast()
        clearPresentedDestinationBindingIfNeeded(for: removed.stateNamespace)
        if !representedPath.isEmpty {
            representedPath.removeLast()
        }
        removeLastPersistedRouteAfterPop()
        let previous = entries.last!

        // Restore previous entry's toolbar widgets
        for item in previous.toolbarWidgets {
            switch item.placement {
            case .leading:
                gtk_header_bar_pack_start(headerBar, item.widget)
            case .center:
                gtk_header_bar_set_title_widget(headerBar, item.widget)
            case .primaryAction, .trailing:
                gtk_header_bar_pack_end(headerBar, item.widget)
            }
        }

        // Slide right for pop
        gtk_stack_set_transition_type(stack, GTK_STACK_TRANSITION_TYPE_SLIDE_RIGHT)
        gtk_stack_set_visible_child_name(stack, previous.name)

        // Defer widget removal until after the slide transition completes,
        // so GTK doesn't destroy a widget mid-animation.
        let stackOp = stack
        let widget = removed.widget
        g_object_ref(gpointer(widget))
        let duration = gtk_stack_get_transition_duration(stackOp)
        g_timeout_add(duration + 50, { userData -> gboolean in
            let w = Unmanaged<WidgetRef>.fromOpaque(userData!).takeRetainedValue()
            if gtk_swift_is_widget(w.widget) != 0,
               let parent = gtk_widget_get_parent(w.widget) {
                let parentOp = OpaquePointer(parent)
                gtk_stack_remove(parentOp, w.widget)
            }
            g_object_unref(gpointer(w.widget))
            return 0 // G_SOURCE_REMOVE
        }, Unmanaged.passRetained(WidgetRef(widget)).toOpaque())

        updateHeaderBar()
        syncPathAfterPop()
    }

    /// Pop to the root view.
    func popToRoot() {
        while entries.count > 1 {
            pop()
        }
    }

    func syncFromBoundPath() {
        guard !isSyncing else { return }
        guard pathBinding != nil || typedPathBinding != nil else { return }
        let targetPath = pathBinding?.wrappedValue.elements
            ?? typedPathBinding?.elements()
            ?? []
        guard targetPath != representedPath else { return }

        var commonPrefixCount = 0
        while commonPrefixCount < targetPath.count,
              commonPrefixCount < representedPath.count,
              targetPath[commonPrefixCount] == representedPath[commonPrefixCount] {
            commonPrefixCount += 1
        }

        gtkNavigationDebugLog(
            "sync path current=\(representedPath.count) target=\(targetPath.count) common=\(commonPrefixCount)"
        )

        isSyncing = true
        while representedPath.count > commonPrefixCount, entries.count > 1 {
            pop()
        }
        for element in targetPath.dropFirst(commonPrefixCount) {
            if !pushValue(element) {
                break
            }
        }
        isSyncing = false
    }

    func navigationDestinationStateNamespace(for value: AnyHashable) -> String {
        "\(stateNamespace)::NavigationDestination[\(String(reflecting: value))]"
    }

    // MARK: - Path binding sync

    /// Suppress path sync (used during initial path consumption).
    func beginSync() { isSyncing = true }
    func endSync() { isSyncing = false }

    /// After a UI-driven push, append the value to the bound path.
    private func syncPathAfterPush(_ value: AnyHashable) {
        guard !isSyncing else { return }
        isSyncing = true
        if let pathBinding = pathBinding {
            var path = pathBinding.wrappedValue
            path.elements.append(value)
            pathBinding.wrappedValue = path
        } else if let typedPathBinding = typedPathBinding {
            typedPathBinding.append(value)
        }
        isSyncing = false
    }

    /// After a UI-driven pop, remove the last element from the bound path.
    private func syncPathAfterPop() {
        guard !isSyncing else { return }
        isSyncing = true
        if let pathBinding = pathBinding {
            var path = pathBinding.wrappedValue
            if !path.isEmpty {
                path.removeLast()
            }
            pathBinding.wrappedValue = path
        } else if let typedPathBinding = typedPathBinding {
            typedPathBinding.removeLast(1)
        }
        isSyncing = false
    }

    /// Remove current entry's toolbar widgets from the header bar.
    private func removeCurrentToolbarWidgets() {
        guard let current = entries.last else { return }
        for item in current.toolbarWidgets {
            if item.placement == .center {
                gtk_header_bar_set_title_widget(headerBar, gtk_label_new(""))
            } else {
                gtk_header_bar_remove(headerBar, item.widget)
            }
        }
    }

    private func updateHeaderBar() {
        let title = entries.last?.title ?? ""
        if let principal = entries.last?.toolbarWidgets.first(where: { $0.placement == .center })?.widget {
            gtk_header_bar_set_title_widget(headerBar, principal)
        } else {
            gtk_header_bar_set_title_widget(headerBar, gtk_label_new(title))
        }
        gtk_widget_set_visible(backButton, entries.count > 1 ? 1 : 0)
    }
}

private struct GTKNavigationContextEnvironmentKey: EnvironmentKey {
    static let defaultValue: GTKNavigationContext? = nil
}

private func gtkEnvironmentWithNavigationContext(
    _ base: EnvironmentValues,
    context: GTKNavigationContext
) -> EnvironmentValues {
    var env = base
    env[GTKNavigationContextEnvironmentKey.self] = context
    env[NavigateKey.self] = NavigateAction(
        push: { [weak context] value in context?.pushValue(value) },
        pop: { [weak context] in context?.pop() },
        popToRoot: { [weak context] in context?.popToRoot() }
    )
    return env
}

private func gtkEnvironmentWithNavigationDestinationDismiss(
    _ base: EnvironmentValues,
    context: GTKNavigationContext
) -> EnvironmentValues {
    var env = base
    env.dismiss = DismissAction(handler: { [weak context] in
        context?.pop()
    }, debugName: "gtk navigation destination")
    return env
}

private let gtkNavigationPathSyncTickCallback: GtkTickCallback = { _, _, userData in
    guard let userData else { return 0 }
    let context = Unmanaged<GTKNavigationContext>.fromOpaque(userData).takeUnretainedValue()
    context.syncFromBoundPath()
    return 1
}

func gtkTestSyncNavigationPath(
    in stack: UnsafeMutablePointer<GtkWidget>
) -> Int {
    guard let data = g_object_get_data(
        UnsafeMutableRawPointer(stack).assumingMemoryBound(to: GObject.self),
        "nav-context"
    ) else {
        return -1
    }
    let context = Unmanaged<GTKNavigationContext>.fromOpaque(data).takeUnretainedValue()
    context.syncFromBoundPath()
    return context.entries.count
}

func gtkTestNavigationEntryCount(
    in stack: UnsafeMutablePointer<GtkWidget>
) -> Int {
    guard let data = g_object_get_data(
        UnsafeMutableRawPointer(stack).assumingMemoryBound(to: GObject.self),
        "nav-context"
    ) else {
        return -1
    }
    let context = Unmanaged<GTKNavigationContext>.fromOpaque(data).takeUnretainedValue()
    return context.entries.count
}

func gtkTestPopNavigation(
    in stack: UnsafeMutablePointer<GtkWidget>
) -> Int {
    guard let data = g_object_get_data(
        UnsafeMutableRawPointer(stack).assumingMemoryBound(to: GObject.self),
        "nav-context"
    ) else {
        return -1
    }
    let context = Unmanaged<GTKNavigationContext>.fromOpaque(data).takeUnretainedValue()
    context.pop()
    return context.entries.count
}

// MARK: - Destination registry

/// Registry of type-to-view factories for path-based navigation.
class GTKNavigationDestinationRegistry {
    private var factories: [ObjectIdentifier: (AnyHashable) -> GTKResolvedDestination] = [:]

    func register<V: Hashable>(for type: V.Type, factory: @escaping (V) -> GTKResolvedDestination) {
        factories[ObjectIdentifier(type)] = { anyValue in
            factory(anyValue.base as! V)
        }
    }

    func resolve(_ value: AnyHashable) -> GTKResolvedDestination? {
        let typeId = ObjectIdentifier(type(of: value.base))
        return factories[typeId]?(value)
    }
}

// MARK: - Thread-local context for render-time access

#if canImport(Glibc) || canImport(Darwin)
private let _navContextKey: pthread_key_t = {
    var key = pthread_key_t()
    pthread_key_create(&key, nil)
    return key
}()

func setCurrentNavigationContext(_ context: GTKNavigationContext?) {
    if let context = context {
        let ptr = Unmanaged.passUnretained(context).toOpaque()
        pthread_setspecific(_navContextKey, ptr)
    } else {
        pthread_setspecific(_navContextKey, nil)
    }
}

func getCurrentNavigationContext() -> GTKNavigationContext? {
    if let ptr = pthread_getspecific(_navContextKey) {
        return Unmanaged<GTKNavigationContext>.fromOpaque(ptr).takeUnretainedValue()
    }
    return getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]
}
#else
private var _currentNavContext: GTKNavigationContext?

func setCurrentNavigationContext(_ context: GTKNavigationContext?) {
    _currentNavContext = context
}

func getCurrentNavigationContext() -> GTKNavigationContext? {
    _currentNavContext ?? getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]
}
#endif

// MARK: - Title extraction

/// Extract navigation title from a view via NavigationTitled conformance.
/// Walks the view tree recursively so .navigationTitle() works regardless
/// of modifier ordering or nesting depth.
func gtkExtractTitle<V: View>(from view: V) -> String {
    return gtkExtractTitleAny(from: view)
}

private func gtkExtractTitleAny(from view: Any, depth: Int = 0) -> String {
    guard depth < 20 else { return "" }
    if let titled = view as? NavigationTitled {
        return titled.navigationTitle
    }
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
        if let titled = child.value as? NavigationTitled {
            return titled.navigationTitle
        }
    }
    for child in mirror.children {
        if child.value is any View {
            let result = gtkExtractTitleAny(from: child.value, depth: depth + 1)
            if !result.isEmpty { return result }
        }
    }
    return ""
}

// MARK: - Toolbar extraction

/// Extract toolbar items from a view tree via ToolbarProvider protocol.
/// Walks Mirror children recursively (depth-limited) to find ToolbarProvider
/// regardless of modifier ordering.
func gtkExtractToolbarItems<V: View>(from view: V) -> [AnyToolbarItem] {
    return gtkExtractToolbarItemsAny(from: view)
}

private func gtkExtractToolbarItemsAny(from view: Any, depth: Int = 0) -> [AnyToolbarItem] {
    guard depth < 20 else { return [] }

    if let provider = view as? ToolbarProvider {
        return provider.toolbarItems
    }

    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
        if let provider = child.value as? ToolbarProvider {
            return provider.toolbarItems
        }
    }

    for child in mirror.children {
        if child.value is any View {
            let result = gtkExtractToolbarItemsAny(from: child.value, depth: depth + 1)
            if !result.isEmpty { return result }
        }
    }

    return []
}

/// Extract toolbar configuration from a view tree via ToolbarConfigurationProvider.
func gtkExtractToolbarConfiguration<V: View>(from view: V) -> ToolbarConfiguration? {
    return gtkExtractToolbarConfigurationAny(from: view)
}

private func gtkExtractToolbarConfigurationAny(from view: Any, depth: Int = 0) -> ToolbarConfiguration? {
    guard depth < 20 else { return nil }

    if let provider = view as? ToolbarConfigurationProvider {
        return provider.toolbarConfiguration
    }

    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
        if let provider = child.value as? ToolbarConfigurationProvider {
            return provider.toolbarConfiguration
        }
    }

    for child in mirror.children {
        if child.value is any View {
            if let result = gtkExtractToolbarConfigurationAny(from: child.value, depth: depth + 1) {
                return result
            }
        }
    }

    return nil
}

/// Filter toolbar items based on configuration (remove placements, respect visibility).
func gtkApplyToolbarConfiguration(
    items: [AnyToolbarItem],
    configuration: ToolbarConfiguration?
) -> (items: [AnyToolbarItem], hidden: Bool) {
    guard let config = configuration else { return (items, false) }

    // GTK only renders navigation-bar-style toolbar; only hide for matching targets
    let targetAppliesToGTK = config.visibilityTarget == nil
        || config.visibilityTarget == .automatic
        || config.visibilityTarget == .navigationBar
    let hidden = config.visibility == .hidden && targetAppliesToGTK
    let filtered = items.filter { !config.removedPlacements.contains($0.placement) }
    return (filtered, hidden)
}

// MARK: - GTK rendering extensions

extension NavigationStack: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        // Create header bar
        let headerBar = gtk_header_bar_new()!
        let headerBarOp = OpaquePointer(headerBar)

        // Create back button (hidden initially)
        let backButton = gtk_button_new_with_label("Back")!
        gtk_widget_set_visible(backButton, 0)
        gtk_header_bar_pack_start(headerBarOp, backButton)

        // Create stack for content
        let stack = gtk_stack_new()!
        let stackOp = OpaquePointer(stack)
        gtk_stack_set_transition_duration(stackOp, 200)
        gtk_widget_set_vexpand(stack, 1)
        gtk_widget_set_hexpand(stack, 1)

        // Create context
        let navigationStateNamespace = gtkClaimStateIdentityNamespace("NavigationStack")
        let context = GTKNavigationContext(
            stack: stackOp,
            headerBar: headerBarOp,
            backButton: backButton,
            stateNamespace: navigationStateNamespace
        )
        if let pathBinding = pathBinding {
            context.pathBinding = pathBinding
        }
        if let typedPathBinding = typedPathBinding {
            context.typedPathBinding = typedPathBinding
        }

        // Attach context to stack widget for lifetime management
        let retained = Unmanaged.passRetained(context).toOpaque()
        let gobject = UnsafeMutableRawPointer(stack).assumingMemoryBound(to: GObject.self)
        g_object_set_data_full(gobject, "nav-context", retained, { userData in
            Unmanaged<GTKNavigationContext>.fromOpaque(userData!).release()
        })
        _ = gtk_widget_add_tick_callback(
            stack,
            gtkNavigationPathSyncTickCallback,
            Unmanaged.passUnretained(context).toOpaque(),
            nil
        )

        // Connect back button
        let backBox = Unmanaged.passRetained(ClosureBox { [weak context] in
            context?.pop()
        }).toOpaque()
        g_signal_connect_data(
            gpointer(backButton),
            "clicked",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                box.closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            backBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<ClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        // Set context for render pass
        setCurrentNavigationContext(context)
        let prevEnv = getCurrentEnvironment()
        let env = gtkEnvironmentWithNavigationContext(prevEnv, context: context)
        setCurrentEnvironment(env)
        let title = gtkExtractTitle(from: content)
        let rootWidget = widgetFromOpaque(gtkRenderView(content))
        gtkConfigureNavigationPageToFillAllocation(rootWidget)

        // Extract and install root toolbar items while the same navigation and
        // presentation environment is active. Toolbar button actions capture
        // this environment for deferred GTK callbacks; restoring too early
        // drops values such as WindowGroup(for:) dismiss.
        let rawToolbarItems = gtkExtractToolbarItems(from: content)
        let toolbarConfig = gtkExtractToolbarConfiguration(from: content)
        let (toolbarItems, toolbarHidden) = gtkApplyToolbarConfiguration(items: rawToolbarItems, configuration: toolbarConfig)
        var rootEntry = GTKNavigationEntry(
            title: title,
            name: "nav-root",
            stateNamespace: navigationStateNamespace,
            widget: rootWidget
        )
        if !toolbarHidden {
        for item in toolbarItems {
            let itemWidget = widgetFromOpaque(gtkRenderAnyView(item.wrapped))
            switch item.placement {
            case .leading:
                gtk_header_bar_pack_start(headerBarOp, itemWidget)
            case .center:
                gtk_header_bar_set_title_widget(headerBarOp, itemWidget)
            case .primaryAction, .trailing:
                gtk_header_bar_pack_end(headerBarOp, itemWidget)
            }
            g_object_ref(gpointer(itemWidget))
            rootEntry.toolbarWidgets.append((widget: itemWidget, placement: item.placement))
        }
        } // end if !toolbarHidden
        setCurrentEnvironment(prevEnv)
        setCurrentNavigationContext(nil)

        // Add root as first stack entry
        gtk_stack_add_named(stackOp, rootWidget, "nav-root")
        gtk_stack_set_visible_child_name(stackOp, "nav-root")
        context.entries.append(rootEntry)

        // Set initial title
        if let principal = rootEntry.toolbarWidgets.first(where: { $0.placement == .center })?.widget {
            gtk_header_bar_set_title_widget(headerBarOp, principal)
        } else {
            gtk_header_bar_set_title_widget(headerBarOp, gtk_label_new(title))
        }

        // Consume any initial path elements (suppress sync — these are already in the binding)
        let initialPathElements = pathBinding?.wrappedValue.elements
            ?? typedPathBinding?.elements()
            ?? []
        if !initialPathElements.isEmpty {
            context.beginSync()
            setCurrentNavigationContext(context)
            setCurrentEnvironment(env)
            for element in initialPathElements {
                context.pushValue(element)
            }
            setCurrentEnvironment(prevEnv)
            setCurrentNavigationContext(nil)
            context.endSync()
        } else {
            setCurrentNavigationContext(context)
            setCurrentEnvironment(env)
            context.restorePersistedRoutesIfNeeded()
            setCurrentEnvironment(prevEnv)
            setCurrentNavigationContext(nil)
        }
        setCurrentNavigationContext(context)
        setCurrentEnvironment(env)
        context.flushPendingPresentedDestinations()
        setCurrentEnvironment(prevEnv)
        setCurrentNavigationContext(nil)

        if getCurrentEnvironment().isPresentedInSheet {
            let container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
            let inlineBar = gtkCreateInlineNavigationBar(
                title: title,
                toolbarItems: toolbarItems,
                hidden: toolbarHidden
            )
            gtk_widget_set_hexpand(container, 1)
            gtk_widget_set_vexpand(container, 1)
            gtk_widget_set_halign(container, GTK_ALIGN_FILL)
            gtk_widget_set_valign(container, GTK_ALIGN_FILL)
            gtk_box_append(boxPointer(container), inlineBar)
            gtk_box_append(boxPointer(container), stack)
            return opaqueFromWidget(container)
        } else {
            // Expose the header bar to Window via widget data
            g_object_ref(gpointer(headerBar))
            let stackObject = UnsafeMutableRawPointer(stack).assumingMemoryBound(to: GObject.self)
            g_object_set_data_full(stackObject, "gtk-swift-window-titlebar", headerBar, { userData in
                g_object_unref(userData)
            })

            return opaqueFromWidget(stack)
        }
    }
}

private func gtkConfigureNavigationPageToFillAllocation(_ widget: UnsafeMutablePointer<GtkWidget>) {
    gtk_widget_set_hexpand(widget, 1)
    gtk_widget_set_vexpand(widget, 1)
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
}

private func gtkNavigationDisableButtonChildTargeting(_ widget: UnsafeMutablePointer<GtkWidget>) {
    gtk_widget_set_can_target(widget, 0)
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkNavigationDisableButtonChildTargeting(current)
        child = gtk_widget_get_next_sibling(current)
    }
}

protocol GTKNavigationPrimaryActionProvider {
    var gtkNavigationPrimaryAction: (() -> Void)? { get }
}

private func gtkNavigationDestinationRoute<Destination: View>(
    in context: GTKNavigationContext,
    title: String,
    stateNamespace: String? = nil,
    destination: @escaping () -> Destination,
    capturedEnvironment: EnvironmentValues
) -> GTKNavigationPersistedRoute {
    return .destination(stateNamespace: stateNamespace) { context in
        let previousContext = getCurrentNavigationContext()
        setCurrentNavigationContext(context)
        let prevEnv = getCurrentEnvironment()
        var env = capturedEnvironment
        env.refreshInjectedObjectsFromRegistry()
        env = gtkEnvironmentWithNavigationContext(env, context: context)
        env = gtkEnvironmentWithNavigationDestinationDismiss(env, context: context)
        setCurrentEnvironment(env)
        let destView = destination()
        let extracted = gtkExtractTitle(from: destView)
        let finalTitle = extracted.isEmpty ? title : extracted
        let rawItems = gtkExtractToolbarItems(from: destView)
        let destConfig = gtkExtractToolbarConfiguration(from: destView)
        let (toolbarItems, destHidden) = gtkApplyToolbarConfiguration(items: rawItems, configuration: destConfig)
        setCurrentEnvironment(prevEnv)
        setCurrentNavigationContext(previousContext)
        return GTKDeferredNavigationDestination(
            title: finalTitle,
            toolbarItems: destHidden ? [] : toolbarItems,
            render: {
                let previousContext = getCurrentNavigationContext()
                setCurrentNavigationContext(context)
                let prevEnv = getCurrentEnvironment()
                var env = capturedEnvironment
                env.refreshInjectedObjectsFromRegistry()
                env = gtkEnvironmentWithNavigationContext(env, context: context)
                env = gtkEnvironmentWithNavigationDestinationDismiss(env, context: context)
                setCurrentEnvironment(env)
                let widget = gtkRenderView(destView)
                setCurrentEnvironment(prevEnv)
                setCurrentNavigationContext(previousContext)
                return widget
            }
        )
    }
}

extension NavigationLink: GTKNavigationPrimaryActionProvider {
    var gtkNavigationPrimaryAction: (() -> Void)? {
        guard let context = getCurrentNavigationContext() else {
            return nil
        }

        if let value = pushValue {
            return { [weak context] in
                context?.pushValue(value)
            }
        }

        let destTitle = title
        let dest = destination
        let capturedEnv = getCurrentEnvironment()
        let route = gtkNavigationDestinationRoute(
            in: context,
            title: destTitle,
            destination: dest,
            capturedEnvironment: capturedEnv
        )
        return {
            context.pushDestinationRoute(route)
        }
    }
}

extension NavigationLink: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let button: UnsafeMutablePointer<GtkWidget>
        if label.isEmpty {
            button = gtk_button_new()!
            let childWidget = widgetFromOpaque(gtkRenderView(labelView))
            let btnPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
            gtk_button_set_child(btnPtr, childWidget)
            gtkNavigationDisableButtonChildTargeting(childWidget)
            applyCSSToWidget(button, properties: """
                border: none;
                outline: none;
                padding: 0;
                min-height: 0;
                min-width: 0;
                """)
        } else {
            button = gtk_button_new_with_label(label)!
        }
        gtk_widget_set_hexpand(button, 1)
        gtk_widget_set_halign(button, GTK_ALIGN_FILL)

        // Capture context strongly at render time
        guard let context = getCurrentNavigationContext() else {
            // Not inside a NavigationStack — render as plain button
            return opaqueFromWidget(button)
        }

        let destTitle = self.title

        // Value-based NavigationLink — push value via registry
        if let value = pushValue {
            let box = Unmanaged.passRetained(ClosureBox { [weak context] in
                context?.pushValue(value)
            }).toOpaque()

            g_signal_connect_data(
                gpointer(button),
                "clicked",
                unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                    let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                    box.closure()
                } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                box,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )

            return opaqueFromWidget(button)
        }

        // Destination-based NavigationLink
        let dest = self.destination

        // Capture the render-time environment so the deferred click callback
        // restores the correct ancestor environment (not whatever is ambient
        // at dispatch time). See deferred-callback-environment-binding.md.
        let capturedEnv = getCurrentEnvironment()
        let route = gtkNavigationDestinationRoute(
            in: context,
            title: destTitle,
            destination: dest,
            capturedEnvironment: capturedEnv
        )

        let box = Unmanaged.passRetained(ClosureBox {
            context.pushDestinationRoute(route)
        }).toOpaque()

        g_signal_connect_data(
            gpointer(button),
            "clicked",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                box.closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<ClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        return opaqueFromWidget(button)
    }
}

extension NavigationDestinationModifier: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        // Register the destination factory on the current context
        if let context = getCurrentNavigationContext() {
            let destinationBuilder = destination
            // Capture render-time environment for the deferred factory callback.
            let capturedEnv = getCurrentEnvironment()
            context.destinationRegistry.register(for: dataType) { value in
                setCurrentNavigationContext(context)
                let prevEnv = getCurrentEnvironment()
                var env = capturedEnv
                env.refreshInjectedObjectsFromRegistry()
                env = gtkEnvironmentWithNavigationContext(env, context: context)
                env = gtkEnvironmentWithNavigationDestinationDismiss(env, context: context)
                setCurrentEnvironment(env)
                let destView = destinationBuilder(value)
                let title = gtkExtractTitle(from: destView)
                let rawItems = gtkExtractToolbarItems(from: destView)
                let destConfig = gtkExtractToolbarConfiguration(from: destView)
                let (filteredItems, destHidden) = gtkApplyToolbarConfiguration(items: rawItems, configuration: destConfig)
                let widget = gtkWithForcedStateIdentityNamespace(
                    context.navigationDestinationStateNamespace(for: value)
                ) {
                    gtkRenderView(destView)
                }
                setCurrentEnvironment(prevEnv)
                setCurrentNavigationContext(nil)
                return GTKResolvedDestination(widget: widget, title: title, toolbarItems: destHidden ? [] : filteredItems)
            }
        }

        // Render the wrapped content
        return gtkRenderView(content)
    }
}

extension NavigationPresentedDestinationModifier: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let presentedStateNamespace = gtkClaimStateIdentityNamespace("NavigationPresentedDestination")
        let capturedEnv = getCurrentEnvironment()
        let widget = gtkRenderView(content)

        guard let context = getCurrentNavigationContext(), isPresented.wrappedValue else {
            return widget
        }

        let route = gtkNavigationDestinationRoute(
            in: context,
            title: "",
            stateNamespace: presentedStateNamespace,
            destination: destination,
            capturedEnvironment: capturedEnv
        )
        context.enqueuePresentedDestination(
            stateNamespace: presentedStateNamespace,
            isPresented: isPresented,
            route: route
        )
        if !context.entries.isEmpty {
            context.flushPendingPresentedDestinations()
        }

        return widget
    }
}

extension NavigationPresentedDestinationModifier: GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "NavigationPresentedDestinationModifier",
            props: .text(GTK4TextDescriptor(
                content: isPresented.wrappedValue ? "presented" : "dismissed"
            )),
            children: [gtkDescribeView(content)]
        )
    }
}

extension TitledView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkRenderView(content)
    }
}

// MARK: - NavigationSplitView GTK extension

/// Extract column width provider from a view tree, walking through modifier
/// wrappers recursively so modifier ordering doesn't matter.
private func gtkExtractColumnWidthProvider<V: View>(from view: V) -> NavigationSplitViewColumnWidthProvider? {
    return gtkExtractColumnWidthProviderAny(from: view)
}

private func gtkExtractColumnWidthProviderAny(from view: Any, depth: Int = 0) -> NavigationSplitViewColumnWidthProvider? {
    guard depth < 20 else { return nil }
    if let provider = view as? NavigationSplitViewColumnWidthProvider {
        return provider
    }
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
        if let provider = child.value as? NavigationSplitViewColumnWidthProvider {
            return provider
        }
    }
    for child in mirror.children {
        if child.value is any View {
            if let result = gtkExtractColumnWidthProviderAny(from: child.value, depth: depth + 1) {
                return result
            }
        }
    }
    return nil
}

/// Extract column ideal width from a view with .navigationSplitViewColumnWidth applied.
private func gtkExtractColumnWidth<V: View>(from view: V) -> Double? {
    gtkExtractColumnWidthProvider(from: view)?.columnIdealWidth
}

/// Install toolbar items from a view tree into a GtkHeaderBar, attaching
/// it to the given widget via "gtk-swift-window-titlebar" for Window pickup.
private func gtkRenderToolbarWidgets<V: View>(from view: V) -> [UnsafeMutablePointer<GtkWidget>] {
    if view is GTKRenderable {
        return [widgetFromOpaque(gtkRenderView(view))]
    }
    if let multi = view as? MultiChildView {
        return multi.children.flatMap { child in
            gtkRenderToolbarWidgets(from: child)
        }
    }
    if V.Body.self != Never.self {
        // View.body is @MainActor (#513); toolbar walk runs on the GTK main loop.
        return gtkAssumeMainActorIsolated { gtkRenderToolbarWidgets(from: view.body) }
    }
    return [widgetFromOpaque(gtkRenderView(view))]
}

private func gtkRenderToolbarItemWidgets(_ item: AnyToolbarItem) -> [UnsafeMutablePointer<GtkWidget>] {
    item.renderedViews.flatMap { view in
        gtkRenderToolbarWidgets(from: view)
    }
}

private func gtkBackendEnvironmentValue(_ canonical: String, legacy: String) -> String? {
    let environment = ProcessInfo.processInfo.environment
    return environment[canonical] ?? environment[legacy]
}

private func gtkBackendEnvironmentDouble(_ canonical: String, legacy: String) -> Double? {
    gtkBackendEnvironmentValue(canonical, legacy: legacy).flatMap(Double.init)
}

private var gtkBackendLayoutDebugEnabled: Bool {
    gtkBackendEnvironmentValue(
        "QUILLUI_BACKEND_LAYOUT_DEBUG",
        legacy: "QUILLUI_GTK_LAYOUT_DEBUG"
    ) == "1"
}

private func gtkRequestedDefaultWindowHeight() -> gint {
    guard let height = gtkBackendEnvironmentDouble(
        "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT",
        legacy: "QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT"
    ), height > 0
    else {
        return -1
    }
    return gint(height)
}

private func gtkResolvedDefaultSidebarWidth(fallback: Double) -> Double {
    guard let width = gtkBackendEnvironmentDouble(
        "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH",
        legacy: "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"
    ), width > 0
    else {
        if gtkBackendLayoutDebugEnabled {
            print("QuillUI GTK split fallback sidebar width=\(max(320.0, fallback)) env=nil")
        }
        return max(320.0, fallback)
    }
    let resolved = max(320.0, min(600.0, width * 0.27))
    if gtkBackendLayoutDebugEnabled {
        print("QuillUI GTK split env width=\(width) sidebar=\(resolved)")
    }
    return resolved
}

private let gtkProportionalSidebarMapCallback: @convention(c) (gpointer?, gpointer?) -> Void = { widgetPtr, _ in
    guard let widgetPtr else { return }
    let widget = UnsafeMutableRawPointer(widgetPtr).assumingMemoryBound(to: GtkWidget.self)
    let width = Double(gtk_widget_get_width(widget))
    guard width > 0 else { return }
    let sidebarW = max(320.0, min(600.0, width * 0.27))
    gtk_swift_paned_set_position(widget, gint(sidebarW))
}

private let gtkProportionalSidebarTickCallback: GtkTickCallback = { widget, _, _ in
    guard let widget else { return 1 }
    let width = Double(gtk_widget_get_width(widget))
    guard width > 0 else { return 1 }
    let sidebarW = max(320.0, min(600.0, width * 0.27))
    gtk_swift_paned_set_position(widget, gint(sidebarW))
    return 1
}

private func gtkInstallProportionalSidebarPosition(on paned: UnsafeMutablePointer<GtkWidget>) {
    g_signal_connect_data(
        gpointer(paned),
        "map",
        unsafeBitCast(gtkProportionalSidebarMapCallback, to: GCallback.self),
        nil, nil,
        GConnectFlags(rawValue: 0)
    )
    _ = gtk_widget_add_tick_callback(
        paned,
        gtkProportionalSidebarTickCallback,
        nil, nil
    )
}

private func gtkCreateToolbarRow<V: View>(from view: V) -> UnsafeMutablePointer<GtkWidget>? {
    let rawItems = gtkExtractToolbarItems(from: view)
    let config = gtkExtractToolbarConfiguration(from: view)
    let (toolbarItems, hidden) = gtkApplyToolbarConfiguration(items: rawItems, configuration: config)
    guard !hidden, !toolbarItems.isEmpty else { return nil }

    let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14)!
    gtk_widget_set_size_request(row, -1, 48)
    gtk_widget_set_hexpand(row, 1)
    gtk_widget_set_halign(row, GTK_ALIGN_FILL)

    for item in toolbarItems where item.placement == .leading {
        for widget in gtkRenderToolbarItemWidgets(item) {
            gtk_box_append(boxPointer(row), widget)
        }
    }

    let trailingCluster = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14)!
    gtk_widget_set_margin_start(trailingCluster, 620)

    for item in toolbarItems where item.placement != .leading && item.placement != .center {
        for widget in gtkRenderToolbarItemWidgets(item) {
            gtk_box_append(boxPointer(trailingCluster), widget)
        }
    }
    gtk_box_append(boxPointer(row), trailingCluster)

    return row
}

private func gtkCreateInlineNavigationBar(
    title: String,
    toolbarItems: [AnyToolbarItem],
    hidden: Bool
) -> UnsafeMutablePointer<GtkWidget> {
    gtkNavigationDebugLog("inline title=\(title.isEmpty ? "<empty>" : title) items=\(toolbarItems.count) hidden=\(hidden)")
    let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12)!
    gtk_widget_set_size_request(row, -1, 52)
    gtk_widget_set_hexpand(row, 1)
    gtk_widget_set_vexpand(row, 0)
    gtk_widget_set_halign(row, GTK_ALIGN_FILL)
    gtk_widget_set_valign(row, GTK_ALIGN_START)
    applyCSSToWidget(
        row,
        properties: "background: #f8f8fb; border-bottom: 1px solid rgba(0,0,0,0.12); min-height: 52px; padding: 6px 10px;"
    )

    let leading = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
    let trailing = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
    gtk_widget_set_halign(leading, GTK_ALIGN_START)
    gtk_widget_set_halign(trailing, GTK_ALIGN_END)
    gtk_widget_set_valign(leading, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(trailing, GTK_ALIGN_CENTER)
    gtk_widget_set_margin_top(leading, 18)
    gtk_widget_set_margin_top(trailing, 18)

    if !hidden {
        for item in toolbarItems where item.placement == .leading {
            for widget in gtkRenderToolbarItemWidgets(item) {
                gtk_box_append(boxPointer(leading), widget)
            }
        }
        for item in toolbarItems where item.placement != .leading && item.placement != .center {
            for widget in gtkRenderToolbarItemWidgets(item) {
                gtk_box_append(boxPointer(trailing), widget)
            }
        }
    }

    let titleLabel: UnsafeMutablePointer<GtkWidget>
    if let principal = toolbarItems.first(where: { $0.placement == .center }),
       let principalWidget = gtkRenderToolbarItemWidgets(principal).first {
        titleLabel = principalWidget
    } else {
        titleLabel = gtk_label_new(title)!
        applyCSSToWidget(titleLabel, properties: "font-weight: 600;")
    }
    gtk_widget_set_hexpand(titleLabel, 1)
    gtk_widget_set_halign(titleLabel, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(titleLabel, GTK_ALIGN_CENTER)
    gtk_widget_set_margin_top(titleLabel, 18)

    gtk_box_append(boxPointer(row), leading)
    gtk_box_append(boxPointer(row), titleLabel)
    gtk_box_append(boxPointer(row), trailing)
    return row
}

private func gtkWrapWithToolbarRow<V: View>(
    _ contentWidget: UnsafeMutablePointer<GtkWidget>,
    toolbarSource view: V
) -> UnsafeMutablePointer<GtkWidget> {
    guard let toolbarRow = gtkCreateToolbarRow(from: view) else {
        return contentWidget
    }

    let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    gtk_box_append(boxPointer(box), toolbarRow)
    gtk_box_append(boxPointer(box), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))
    gtk_box_append(boxPointer(box), contentWidget)
    gtk_widget_set_hexpand(box, 1)
    gtk_widget_set_vexpand(box, 1)
    gtk_widget_set_hexpand(contentWidget, 1)
    gtk_widget_set_vexpand(contentWidget, 1)
    return box
}

private func gtkApplyFixedSplitColumnWidth(_ widget: UnsafeMutablePointer<GtkWidget>, width: Double) {
    let pixelWidth = gint(width)
    gtk_widget_set_size_request(widget, pixelWidth, gtkRequestedDefaultWindowHeight())
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    if typeName == "GtkScrolledWindow" {
        let scrolledOp = OpaquePointer(widget)
        gtk_scrolled_window_set_min_content_width(scrolledOp, pixelWidth)
        gtk_scrolled_window_set_max_content_width(scrolledOp, pixelWidth)
    }
}

private func gtkConfigureFixedSplitColumn(_ widget: UnsafeMutablePointer<GtkWidget>, width: Double) {
    gtkApplyFixedSplitColumnWidth(widget, width: width)
    gtk_widget_set_hexpand(widget, 0)
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
    gtk_widget_set_vexpand(widget, 1)
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
}

private func gtkCreateFixedSplitColumnContainer(
    child: UnsafeMutablePointer<GtkWidget>,
    width: Double
) -> UnsafeMutablePointer<GtkWidget> {
    let scrolled = gtk_scrolled_window_new()!
    let scrolledOp = OpaquePointer(scrolled)
    gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL)
    gtk_scrolled_window_set_has_frame(scrolledOp, 0)
    gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
    gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)
    gtkConfigureFixedSplitColumn(scrolled, width: width)

    gtk_widget_set_hexpand(child, 1)
    gtk_widget_set_halign(child, GTK_ALIGN_FILL)
    gtk_widget_set_vexpand(child, 1)
    gtk_widget_set_valign(child, GTK_ALIGN_FILL)
    gtk_scrolled_window_set_child(scrolledOp, child)
    return scrolled
}

private func gtkConfigureFillingSplitColumn(_ widget: UnsafeMutablePointer<GtkWidget>) {
    gtk_widget_set_hexpand(widget, 1)
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
    gtk_widget_set_vexpand(widget, 1)
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
}

private func gtkCreateSplitDivider() -> UnsafeMutablePointer<GtkWidget> {
    let divider = gtk_separator_new(GTK_ORIENTATION_VERTICAL)!
    gtk_widget_set_size_request(divider, 1, gtkRequestedDefaultWindowHeight())
    applyCSSToWidget(divider, properties: "background: #d1d2cf; min-width: 1px;")
    return divider
}

private let gtkFixedSplitSidebarTickCallback: GtkTickCallback = { widget, _, userData in
    guard let widget, let userData else { return 1 }
    let sidebar = Unmanaged<WidgetRef>.fromOpaque(userData).takeUnretainedValue().widget
    let width = Double(gtk_widget_get_width(widget))
    guard width > 0 else { return 1 }
    let sidebarW = max(320.0, min(600.0, width * 0.27))
    gtkApplyFixedSplitColumnWidth(sidebar, width: sidebarW)
    gtk_widget_queue_resize(sidebar)
    gtk_widget_queue_resize(widget)
    if gtkBackendLayoutDebugEnabled {
        print("QuillUI GTK split allocated width=\(width) sidebar=\(sidebarW)")
    }
    return 1
}

private func gtkInstallProportionalFixedSidebar(
    on splitBox: UnsafeMutablePointer<GtkWidget>,
    sidebarWidget: UnsafeMutablePointer<GtkWidget>
) {
    _ = gtk_widget_add_tick_callback(
        splitBox,
        gtkFixedSplitSidebarTickCallback,
        Unmanaged.passRetained(WidgetRef(sidebarWidget)).toOpaque(),
        { userData in
            if let userData {
                Unmanaged<WidgetRef>.fromOpaque(userData).release()
            }
        }
    )
}

private func gtkCreateTwoColumnSplitBox(
    sidebarWidget: UnsafeMutablePointer<GtkWidget>,
    detailWidget: UnsafeMutablePointer<GtkWidget>,
    sidebarWidth: Double
) -> UnsafeMutablePointer<GtkWidget> {
    let splitBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    gtkConfigureFixedSplitColumn(sidebarWidget, width: sidebarWidth)
    applyCSSToWidget(sidebarWidget, properties: "background: #e8e9e6;")
    gtkConfigureFillingSplitColumn(detailWidget)

    gtk_box_append(boxPointer(splitBox), sidebarWidget)
    gtk_box_append(boxPointer(splitBox), gtkCreateSplitDivider())
    gtk_box_append(boxPointer(splitBox), detailWidget)
    gtkConfigureFillingSplitColumn(splitBox)
    gtkInstallProportionalFixedSidebar(on: splitBox, sidebarWidget: sidebarWidget)
    return splitBox
}

private func gtkCreateThreeColumnSplitBox(
    sidebarWidget: UnsafeMutablePointer<GtkWidget>,
    contentWidget: UnsafeMutablePointer<GtkWidget>,
    detailWidget: UnsafeMutablePointer<GtkWidget>,
    sidebarWidth: Double,
    contentWidth: Double
) -> UnsafeMutablePointer<GtkWidget> {
    let splitBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    gtkConfigureFixedSplitColumn(sidebarWidget, width: sidebarWidth)
    gtkConfigureFixedSplitColumn(contentWidget, width: contentWidth)
    applyCSSToWidget(sidebarWidget, properties: "background: #e8e9e6;")
    applyCSSToWidget(contentWidget, properties: "background: #f6f6f4;")
    gtkConfigureFillingSplitColumn(detailWidget)

    gtk_box_append(boxPointer(splitBox), sidebarWidget)
    gtk_box_append(boxPointer(splitBox), gtkCreateSplitDivider())
    gtk_box_append(boxPointer(splitBox), contentWidget)
    gtk_box_append(boxPointer(splitBox), gtkCreateSplitDivider())
    gtk_box_append(boxPointer(splitBox), detailWidget)
    gtkConfigureFillingSplitColumn(splitBox)
    gtkInstallProportionalFixedSidebar(on: splitBox, sidebarWidget: sidebarWidget)
    return splitBox
}

private func gtkApplyFixedSplitVisibility(
    _ visibility: NavigationSplitViewVisibility,
    sidebar: UnsafeMutablePointer<GtkWidget>,
    content: UnsafeMutablePointer<GtkWidget>?
) {
    switch visibility {
    case .automatic, .all:
        gtk_widget_set_visible(sidebar, 1)
        if let content = content { gtk_widget_set_visible(content, 1) }
    case .doubleColumn:
        gtk_widget_set_visible(sidebar, 1)
        if let content = content { gtk_widget_set_visible(content, 0) }
    case .detailOnly:
        gtk_widget_set_visible(sidebar, 0)
        if let content = content { gtk_widget_set_visible(content, 0) }
    }
}

private func gtkInstallToolbar<V: View>(from view: V, on widget: UnsafeMutablePointer<GtkWidget>) {
    let rawItems = gtkExtractToolbarItems(from: view)
    let config = gtkExtractToolbarConfiguration(from: view)
    let (toolbarItems, hidden) = gtkApplyToolbarConfiguration(items: rawItems, configuration: config)
    guard !hidden, !toolbarItems.isEmpty else { return }

    let headerBar = gtk_header_bar_new()!
    let headerBarOp = OpaquePointer(headerBar)
    gtk_header_bar_set_title_widget(headerBarOp, gtk_label_new(""))
    for item in toolbarItems {
        for itemWidget in gtkRenderToolbarItemWidgets(item) {
            switch item.placement {
            case .leading:
                gtk_header_bar_pack_start(headerBarOp, itemWidget)
            case .center:
                gtk_header_bar_set_title_widget(headerBarOp, itemWidget)
            case .primaryAction, .trailing:
                gtk_header_bar_pack_end(headerBarOp, itemWidget)
            }
        }
    }

    g_object_ref(gpointer(headerBar))
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data_full(gobject, "gtk-swift-window-titlebar", headerBar,
        { userData in g_object_unref(userData) })
}

/// Apply visibility state to NavigationSplitView columns.
private func gtkApplyVisibility(
    _ visibility: NavigationSplitViewVisibility,
    sidebar: UnsafeMutablePointer<GtkWidget>,
    content: UnsafeMutablePointer<GtkWidget>?,
    paned: UnsafeMutablePointer<GtkWidget>
) {
    switch visibility {
    case .automatic, .all:
        gtk_widget_set_visible(sidebar, 1)
        if let content = content { gtk_widget_set_visible(content, 1) }
    case .doubleColumn:
        gtk_widget_set_visible(sidebar, 1)
        if let content = content { gtk_widget_set_visible(content, 0) }
    case .detailOnly:
        gtk_widget_set_visible(sidebar, 0)
        if let content = content { gtk_widget_set_visible(content, 0) }
        gtk_swift_paned_set_position(paned, 0)
    }
}

extension NavigationSplitView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        if hasContentColumn {
            return gtkCreateThreeColumnWidget()
        } else {
            return gtkCreateTwoColumnWidget()
        }
    }

    private func gtkCreateTwoColumnWidget() -> OpaquePointer {
        let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))
        let sidebarMinW = gtkExtractColumnWidthProvider(from: sidebar)?.columnMinWidth ?? 0
        let resolvedSidebarW = max(sidebarMinW, sidebarW)

        let sidebarContentWidget = widgetFromOpaque(gtkRenderView(sidebar))
        let sidebarWidget = gtkCreateFixedSplitColumnContainer(
            child: sidebarContentWidget,
            width: resolvedSidebarW
        )

        let detailWidget = gtkWrapWithToolbarRow(widgetFromOpaque(gtkRenderView(detail)), toolbarSource: detail)
        let splitBox = gtkCreateTwoColumnSplitBox(
            sidebarWidget: sidebarWidget,
            detailWidget: detailWidget,
            sidebarWidth: resolvedSidebarW
        )

        if let visibility = columnVisibility {
            gtkApplyFixedSplitVisibility(visibility.wrappedValue,
                                         sidebar: sidebarWidget,
                                         content: nil)
        }

        return opaqueFromWidget(splitBox)
    }

    private func gtkCreateThreeColumnWidget() -> OpaquePointer {
        let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))
        let contentW = gtkExtractColumnWidth(from: content) ?? 250.0
        let sidebarMinW = gtkExtractColumnWidthProvider(from: sidebar)?.columnMinWidth ?? 0
        let contentMinW = gtkExtractColumnWidthProvider(from: content)?.columnMinWidth ?? 0
        let resolvedSidebarW = max(sidebarMinW, sidebarW)
        let resolvedContentW = max(contentMinW, contentW)

        let sidebarContentWidget = widgetFromOpaque(gtkRenderView(sidebar))
        let sidebarWidget = gtkCreateFixedSplitColumnContainer(
            child: sidebarContentWidget,
            width: resolvedSidebarW
        )

        let contentWidget = gtkCreateFixedSplitColumnContainer(
            child: widgetFromOpaque(gtkRenderView(content)),
            width: resolvedContentW
        )
        let detailWidget = gtkWrapWithToolbarRow(widgetFromOpaque(gtkRenderView(detail)), toolbarSource: detail)
        let splitBox = gtkCreateThreeColumnSplitBox(
            sidebarWidget: sidebarWidget,
            contentWidget: contentWidget,
            detailWidget: detailWidget,
            sidebarWidth: resolvedSidebarW,
            contentWidth: resolvedContentW
        )

        if let visibility = columnVisibility {
            gtkApplyFixedSplitVisibility(visibility.wrappedValue,
                                         sidebar: sidebarWidget,
                                         content: contentWidget)
        }

        return opaqueFromWidget(splitBox)
    }

}

extension NavigationSplitViewColumnWidthView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        if let minW = columnMinWidth {
            gtk_widget_set_size_request(widget, gint(minW), -1)
        }
        return opaqueFromWidget(widget)
    }
}
