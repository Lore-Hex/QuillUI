import CGTK
import CGTKBridge
import SwiftOpenUI
import SwiftOpenUISymbols
import Foundation
#if canImport(Observation) && !os(Linux)
import Observation
#endif

/// Register bundled Material Symbols font with FontConfig for this process
/// only, so Pango / GtkLabel can resolve "Material Symbols Rounded" as a
/// font family. The font file is shipped inside SwiftOpenUISymbols' resource
/// bundle; this call makes it visible to FontConfig without installing it
/// to the user's system font directory. Idempotent — calling it more than
/// once just re-adds the same file.
private func gtkRegisterBundledIconFont() {
    let url = MaterialSymbolsResources.roundedRegularFontURL
    let result = url.path.withCString { gtk_swift_fc_app_font_add_file($0) }
    if result == 0 {
        // Non-fatal: icons will render as empty glyphs / fallback text but
        // nothing else breaks. Flag it so a developer notices.
        print("SwiftOpenUI: failed to register bundled Material Symbols font at \(url.path)")
    }
}

/// Recursively search a widget tree for a navigation-provided window titlebar.
private func findTitlebar(in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    if let data = g_object_get_data(gobject, "gtk-swift-window-titlebar") {
        return UnsafeMutableRawPointer(data).assumingMemoryBound(to: GtkWidget.self)
    }

    // Search only the visible child of GtkStack to avoid stale titlebars.
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    if typeName == "GtkStack" {
        let stackOp = OpaquePointer(widget)
        if let visibleChild = gtk_stack_get_visible_child(stackOp) {
            return findTitlebar(in: visibleChild)
        }
        return nil
    }

    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let found = findTitlebar(in: c) {
            return found
        }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}

/// Protocol for scenes that can render onto GTK top-level windows.
protocol GTKWindowRenderable {
    func gtkRender(app: OpaquePointer?)
}

private var gtkCurrentAppStateSource: Any?

private func gtkWithAppStateSource<T>(_ source: Any, _ body: () -> T) -> T {
    let previous = gtkCurrentAppStateSource
    gtkCurrentAppStateSource = source
    defer { gtkCurrentAppStateSource = previous }
    return body()
}

/// Root GTK window content should fill the proposed size; leaf alignment is
/// handled by child containers, not by centering the hosted root widget.
private let gtkRootPresentationOverlayKey = "quillui-root-presentation-overlay"
private var gtkRootPresentationOverlayFallback: OpaquePointer?

func gtkCreateRootPresentationContainer(
    winPtr: UnsafeMutablePointer<GtkWindow>,
    contentWidget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let overlay = gtk_overlay_new()!
    gtk_widget_set_hexpand(overlay, 1)
    gtk_widget_set_vexpand(overlay, 1)
    gtk_widget_set_halign(overlay, GTK_ALIGN_FILL)
    gtk_widget_set_valign(overlay, GTK_ALIGN_FILL)

    gtk_widget_set_hexpand(contentWidget, 1)
    gtk_widget_set_vexpand(contentWidget, 1)
    gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
    gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)
    gtk_overlay_set_child(OpaquePointer(overlay), contentWidget)

    gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: widgetPointer(winPtr))
    gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: overlay)
    gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: contentWidget)
    gtkRootPresentationOverlayFallback = OpaquePointer(overlay)
    return overlay
}

func gtkStoreRootPresentationOverlay(
    _ rootOverlay: OpaquePointer,
    on widget: UnsafeMutablePointer<GtkWidget>
) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, gtkRootPresentationOverlayKey, UnsafeMutableRawPointer(rootOverlay))
}

func gtkStoredRootPresentationOverlay(on widget: gpointer) -> OpaquePointer? {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let overlayPtr = g_object_get_data(gobject, gtkRootPresentationOverlayKey) else { return nil }
    let overlay = overlayPtr.assumingMemoryBound(to: GtkWidget.self)
    return OpaquePointer(overlay)
}

func gtkRootPresentationOverlay(for root: gpointer) -> OpaquePointer? {
    gtkStoredRootPresentationOverlay(on: root) ?? gtkRootPresentationOverlayFallback
}

func gtkFallbackRootPresentationOverlay() -> OpaquePointer? {
    gtkRootPresentationOverlayFallback
}

func gtkConfigureRootContentToFillWindow(_ contentWidget: UnsafeMutablePointer<GtkWidget>) {
    gtk_widget_set_hexpand(contentWidget, 1)
    gtk_widget_set_vexpand(contentWidget, 1)
    gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
    gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)
}

private func gtkBackendDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else {
        return
    }
    if let data = ("[QuillUI GTK] " + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private func gtkShortcutDebugText(_ shortcut: KeyboardShortcut) -> String {
    var parts: [String] = []
    if shortcut.modifiers.contains(.command) { parts.append("command") }
    if shortcut.modifiers.contains(.shift) { parts.append("shift") }
    if shortcut.modifiers.contains(.option) { parts.append("option") }
    if shortcut.modifiers.contains(.control) { parts.append("control") }
    if shortcut.modifiers.contains(.capsLock) { parts.append("capsLock") }
    if parts.isEmpty { parts.append("none") }

    let keyText: String
    switch shortcut.key {
    case .return: keyText = "return"
    case .escape: keyText = "escape"
    case .delete: keyText = "delete"
    case .tab: keyText = "tab"
    case .space: keyText = "space"
    default: keyText = String(shortcut.key.character)
    }
    return "\(parts.joined(separator: "+"))+\(keyText)"
}

extension WindowGroup: GTKWindowRenderable {
    func gtkResolvedDefaultWindowSize() -> (width: Double, height: Double)? {
        switch windowSizing ?? .automatic {
        case .automatic:
            let environment = ProcessInfo.processInfo.environment
            func environmentDouble(_ canonical: String, legacy: String) -> Double? {
                (environment[canonical] ?? environment[legacy]).flatMap(Double.init)
            }
            let requestedWidth = environmentDouble(
                "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH",
                legacy: "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"
            )
            let requestedHeight = environmentDouble(
                "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT",
                legacy: "QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT"
            )
            return (
                requestedWidth ?? defaultWindowWidth ?? defaultAutomaticWindowWidth,
                requestedHeight ?? defaultWindowHeight ?? defaultAutomaticWindowHeight
            )
        case .content:
            guard let width = defaultWindowWidth, let height = defaultWindowHeight else {
                return nil
            }
            return (width, height)
        case .contentFixed:
            guard let width = defaultWindowWidth, let height = defaultWindowHeight else {
                return nil
            }
            return (width, height)
        case .size(let width, let height):
            return (width, height)
        }
    }

    func gtkRender(app: OpaquePointer?) {
        let appStateSource = gtkCurrentAppStateSource
        if let valueTypeKey = quillValueTypeKey {
            GTK4WindowRegistry.shared.registerValue(typeKey: valueTypeKey) { [self] value in
                self.gtkCreateWindow(
                    app: app,
                    content: self.quillContent(forPresentedValue: value),
                    contentFactory: {
                        self.quillContent(forPresentedValue: value)
                    },
                    dismissesWindow: true,
                    appStateSource: appStateSource
                )
            }
        }

        guard launchesAtStartup else {
            gtkBackendDebugLog("defer WindowGroup title=\(title)")
            return
        }

        gtkBackendDebugLog("WindowGroup render start title=\(title) content=\(Content.self)")
        gtkCreateWindow(
            app: app,
            content: content,
            contentFactory: quillContentFactory,
            appStateSource: appStateSource
        )
    }

    func gtkCreateWindow(
        app: OpaquePointer?,
        content renderedContent: Content,
        contentFactory: @escaping () -> Content,
        dismissesWindow: Bool = false,
        appStateSource: Any? = nil
    ) {
        let window: UnsafeMutablePointer<GtkWidget>
        if let app {
            window = gtk_application_window_new(gtkApplicationPointer(app))!
        } else {
            window = gtk_window_new()!
        }
        let winPtr = windowPointer(window)
        gtkBackendDebugLog("WindowGroup window created title=\(title) handle=\(Int(bitPattern: winPtr))")
        gtk_window_set_title(winPtr, title)
        if quillHidesTitleBar {
            // .windowStyle(.hiddenTitleBar): no server-side decorations, as on
            // macOS where the content extends into the title bar region.
            gtk_window_set_decorated(winPtr, 0)
        }

        // Set window ID in environment for keyboard shortcut scoping
        var wgEnv = getCurrentEnvironment()
        wgEnv.windowID = Int(bitPattern: winPtr)
        if dismissesWindow {
            wgEnv.dismiss = DismissAction(handler: {
                gtkBackendDebugLog("dismiss value WindowGroup title=\(title)")
                gtk_window_destroy(winPtr)
            }, debugName: "gtk value WindowGroup")
        }
        setCurrentEnvironment(wgEnv)

        gtkBackendDebugLog("WindowGroup content render start title=\(title)")
        let contentWidget: UnsafeMutablePointer<GtkWidget>
        if dismissesWindow {
            contentWidget = widgetFromOpaque(swiftOpenUIWithPresentationDismissAction({
                gtkBackendDebugLog("dismiss value WindowGroup presentation title=\(title)")
                gtk_window_destroy(winPtr)
            }) {
                gtkRenderWindowRootView(
                    renderedContent,
                    appStateSource: appStateSource,
                    contentProvider: contentFactory
                )
            })
        } else {
            contentWidget = widgetFromOpaque(
                gtkRenderWindowRootView(
                    renderedContent,
                    appStateSource: appStateSource,
                    contentProvider: contentFactory
                )
            )
        }
        let contentTypeName = String(cString: g_type_name(gtk_swift_get_widget_type(contentWidget)))
        gtkBackendDebugLog("WindowGroup content render end title=\(title) widget=\(contentTypeName)")
        if let titlebarWidget = findTitlebar(in: contentWidget) {
            gtk_window_set_titlebar(winPtr, titlebarWidget)
        }

        // Apply minimum content size where configured. GTK4 window sizing is
        // largely content-driven, so min constraints are expressed on the root.
        let minReqW = minWindowWidth.map { Int32($0) } ?? -1
        let minReqH = minWindowHeight.map { Int32($0) } ?? -1
        if minReqW >= 0 || minReqH >= 0 {
            gtk_widget_set_size_request(contentWidget, minReqW, minReqH)
        }

        if let defaultSize = gtkResolvedDefaultWindowSize() {
            gtk_window_set_default_size(
                winPtr,
                gint(defaultSize.width),
                gint(defaultSize.height)
            )
            gtk_widget_set_size_request(
                contentWidget,
                gint(defaultSize.width),
                gint(defaultSize.height)
            )
        }

        switch windowSizing ?? .automatic {
        case .automatic, .content:
            break
        case .contentFixed:
            gtk_window_set_resizable(winPtr, 0)
        case .size:
            break
        }

        switch windowResizeBehavior ?? .automatic {
        case .automatic:
            break
        case .fixed:
            gtk_window_set_resizable(winPtr, 0)
        case .resizable:
            gtk_window_set_resizable(winPtr, 1)
        }

        // SwiftUI-compatible .windowResizability() — takes precedence
        // over windowResizeBehavior when set.
        switch windowResizability {
        case .contentSize:
            gtk_window_set_resizable(winPtr, 0)
        case .contentMinSize, .automatic:
            break  // resizable (default GTK4 behavior)
        case nil:
            break
        }

        let rootContentWidget = gtkCreateRootPresentationContainer(winPtr: winPtr, contentWidget: contentWidget)
        gtkConfigureRootContentToFillWindow(rootContentWidget)

        gtk_window_set_child(winPtr, rootContentWidget)
        let winWidget = widgetPointer(winPtr)
        if !quillHidesTitleBar && gtkShouldShowWindowMenuBar() {
            gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: rootContentWidget, windowID: Int(bitPattern: winPtr))
        } else {
            gtkSetupCommandShortcutsIfNeeded(winPtr: winWidget, windowID: Int(bitPattern: winPtr))
        }
        gtkAttachKeyboardShortcutController(to: winWidget)
        gtkAttachWindowActivationHandler(to: winWidget)
        gtkBackendDebugLog("WindowGroup present title=\(title) handle=\(Int(bitPattern: winPtr))")
        gtk_window_present(winPtr)
        gtkBackendDebugLog("WindowGroup presented title=\(title)")
    }
}

// MARK: - Keyboard shortcut controller

/// Attaches a GtkEventControllerKey to a window to dispatch keyboard shortcuts.
/// The window pointer is passed as user_data so the handler can scope dispatch.
func gtkAttachKeyboardShortcutController(to window: UnsafeMutablePointer<GtkWidget>) {
    let controller = gtk_event_controller_key_new()!
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE)
    let windowUD = gpointer(window)

    g_signal_connect_data(
        gpointer(controller),
        "key-pressed",
        unsafeBitCast(gtkKeyPressedHandler as @convention(c) (OpaquePointer?, guint, guint, guint, gpointer?) -> gboolean, to: GCallback.self),
        windowUD, nil,
        GConnectFlags(rawValue: 0)
    )

    gtk_widget_add_controller(window, controller)
}

/// Handler for GtkEventControllerKey "key-pressed" signal.
/// Signature: (controller, keyval, keycode, state, user_data) -> gboolean
/// user_data carries the window pointer for dispatch scoping.
private let gtkKeyPressedHandler: @convention(c) (OpaquePointer?, guint, guint, guint, gpointer?) -> gboolean = { _, keyval, _, state, userData in
    var modifiers: EventModifiers = []
    // GDK_CONTROL_MASK = 1 << 2 = 4
    if state & 4 != 0 { modifiers.insert(.command) }
    // GDK_SHIFT_MASK = 1 << 0 = 1
    if state & 1 != 0 { modifiers.insert(.shift) }
    // GDK_ALT_MASK = 1 << 3 = 8
    if state & 8 != 0 { modifiers.insert(.option) }
    // GDK_LOCK_MASK = 1 << 1 = 2
    if state & 2 != 0 { modifiers.insert(.capsLock) }

    guard let key = gtkKeyEquivalentFromKeyval(keyval) else {
        gtkBackendDebugLog("key ignored keyval=\(keyval) state=\(state)")
        return 0
    }

    let windowID = Int(bitPattern: userData)
    let shortcut = KeyboardShortcut(key, modifiers: modifiers)
    let handled = KeyboardShortcutRegistry.shared.dispatch(shortcut, windowID: windowID)
    gtkBackendDebugLog("key shortcut=\(gtkShortcutDebugText(shortcut)) keyval=\(keyval) state=\(state) windowID=\(windowID) handled=\(handled)")
    return handled ? 1 : 0
}

/// Maps a GDK keyval to a KeyEquivalent.
private func gtkKeyEquivalentFromKeyval(_ keyval: guint) -> KeyEquivalent? {
    switch keyval {
    case 0xff0d: return .return       // GDK_KEY_Return
    case 0xff8d: return .return       // GDK_KEY_KP_Enter
    case 0xff1b: return .escape       // GDK_KEY_Escape
    case 0xffff: return .delete       // GDK_KEY_Delete
    case 0xff08: return .delete       // GDK_KEY_BackSpace
    case 0xff09: return .tab          // GDK_KEY_Tab
    case 0xff52: return .upArrow      // GDK_KEY_Up
    case 0xff54: return .downArrow    // GDK_KEY_Down
    case 0xff51: return .leftArrow    // GDK_KEY_Left
    case 0xff53: return .rightArrow   // GDK_KEY_Right
    case 0x0020: return .space        // GDK_KEY_space
    default:
        // For ASCII printable characters, GDK keyvals match Unicode codepoints
        // a-z: 0x61-0x7a, A-Z: 0x41-0x5a (normalize to lowercase)
        let lower: guint
        if keyval >= 0x41 && keyval <= 0x5a {
            lower = keyval + 0x20
        } else {
            lower = keyval
        }
        if lower >= 0x20 && lower <= 0x7e {
            return KeyEquivalent(Character(Unicode.Scalar(lower)!))
        }
        return nil
    }
}

// MARK: - Window activation tracking

/// Connects to "notify::is-active" to track window activation for @FocusedValue.
func gtkAttachWindowActivationHandler(to window: UnsafeMutablePointer<GtkWidget>) {
    let windowUD = gpointer(window)
    g_signal_connect_data(
        gpointer(window),
        "notify::is-active",
        unsafeBitCast(gtkWindowActivationHandler as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        windowUD, nil,
        GConnectFlags(rawValue: 0)
    )
}

/// Handler for GtkWindow "notify::is-active" signal.
/// Signature: (object, pspec, user_data) per GObject notify pattern.
private let gtkWindowActivationHandler: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = { widget, _, userData in
    guard let widget else { return }
    let widgetPtr = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkWidget.self)
    if gtk_swift_window_is_active(widgetPtr) != 0 {
        FocusedValuesStore.shared.setActiveWindow(Int(bitPattern: userData))
    }
}

// MARK: - GTK4 menu bar host

/// Mutable closure box whose identity (heap address) must remain stable for the
/// lifetime of its owning GSimpleAction, because the action's activate signal
/// callback holds an unretained pointer to it as user_data. Replacing the entry
/// in `actionClosures` would free the old box while GObject still points at it,
/// so `updateInPlace` mutates `.closure` instead of rebinding the slot.
private final class MenuActionClosure {
    var closure: () -> Void
    init(_ closure: @escaping () -> Void) { self.closure = closure }
}

private func gtkEnvironmentFlag(_ canonical: String, legacy: String) -> Bool? {
    guard let rawValue = ProcessInfo.processInfo.environment[canonical]
        ?? ProcessInfo.processInfo.environment[legacy]
    else {
        return nil
    }
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["1", "true", "yes", "on"].contains(normalized) { return true }
    if ["0", "false", "no", "off"].contains(normalized) { return false }
    return nil
}

private func gtkShouldShowWindowMenuBar() -> Bool {
    if let explicitShow = gtkEnvironmentFlag(
        "QUILLUI_BACKEND_SHOW_WINDOW_MENUBAR",
        legacy: "QUILLUI_GTK_SHOW_WINDOW_MENUBAR"
    ) {
        return explicitShow
    }
    if let explicitHide = gtkEnvironmentFlag(
        "QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR",
        legacy: "QUILLUI_GTK_HIDE_WINDOW_MENUBAR"
    ) {
        return !explicitHide
    }
    return false
}

/// Manages a GtkPopoverMenuBar on a GTK4 window.
/// Handles command dispatch via GAction, keyboard shortcut registration,
/// and observation-based re-evaluation of Commands.
///
/// Note: GtkPopoverMenuBar renders as a horizontal bar with dropdown menus
/// inside the window. This differs from Win32's native HMENU (integrated
/// into the window frame) but provides equivalent functionality.
final class GTK4MenuBarHost {
    let winPtr: UnsafeMutablePointer<GtkWidget>
    let factory: AnyCommandsFactory
    let windowID: Int
    private var menuBar: UnsafeMutablePointer<GtkWidget>?
    private var actionGroup: OpaquePointer?
    private var actions: [String: OpaquePointer] = [:]  // actionName → GSimpleAction
    private var actionClosures: [String: MenuActionClosure] = [:]  // kept alive for signal handlers
    private var menuStructureSignature: [String] = []
    private var shortcutRegIDs: [ShortcutRegistrationID] = []
    private var focusedValuesObserverID: FocusedValuesObserverID?
    private var containerBox: UnsafeMutablePointer<GtkWidget>?

    init(winPtr: UnsafeMutablePointer<GtkWidget>, factory: @escaping AnyCommandsFactory, windowID: Int) {
        self.winPtr = winPtr
        self.factory = factory
        self.windowID = windowID
    }

    /// Build the initial menu bar and start observation.
    func setup(contentWidget: UnsafeMutablePointer<GtkWidget>) {
        // Create a vertical box: menu bar on top, content below
        let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        containerBox = vbox

        // Move content into the box
        g_object_ref(gpointer(contentWidget))
        gtk_window_set_child(windowPointer(winPtr), nil)
        gtk_box_append(UnsafeMutableRawPointer(vbox).assumingMemoryBound(to: GtkBox.self), contentWidget)
        gtk_widget_set_hexpand(contentWidget, 1)
        gtk_widget_set_vexpand(contentWidget, 1)
        gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
        gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(vbox, 1)
        gtk_widget_set_vexpand(vbox, 1)
        g_object_unref(gpointer(contentWidget))

        // Set the box as window child
        gtk_window_set_child(windowPointer(winPtr), vbox)

        // Register for focused-value changes
        focusedValuesObserverID = FocusedValuesStore.shared.addObserver(windowID: nil) { [weak self] in
            self?.scheduleReevaluation()
        }

        evaluateWithTracking()
    }

    /// Schedule a re-evaluation on the main thread via GLib idle.
    private func scheduleReevaluation() {
        let box = Unmanaged.passRetained(ClosureBox { [weak self] in
            self?.evaluateWithTracking()
        }).toOpaque()
        g_idle_add({ (userData: gpointer?) -> gboolean in
            guard let userData else { return 0 }
            let box = Unmanaged<ClosureBox>.fromOpaque(userData).takeRetainedValue()
            box.closure()
            return 0  // G_SOURCE_REMOVE
        }, box)
    }

    /// Evaluate Commands with observation tracking and re-arm on change.
    func evaluateWithTracking() {
        #if canImport(Observation) && !os(Linux)
        if #available(macOS 14.0, iOS 17.0, *) {
            withObservationTracking {
                let groups = self.factory()
                self.updateMenu(groups)
            } onChange: { [weak self] in
                self?.scheduleReevaluation()
            }
            return
        }
        #endif
        let groups = factory()
        updateMenu(groups)
    }

    /// Update the native menu bar from evaluated command groups.
    private func updateMenu(_ groups: [CommandGroupPlacement: [CommandMenuItem]]) {
        let sections = commandMenuSections(from: groups)
        let allItems = sections.flatMap { $0.items }
        let newStructureSignature = menuStructureSignature(for: sections)

        if menuBar == nil {
            buildMenu(sections, structureSignature: newStructureSignature)
        } else {
            if menuStructureSignature == newStructureSignature {
                updateInPlace(allItems)
            } else {
                teardown(widgetsValid: true)
                buildMenu(sections, structureSignature: newStructureSignature)
            }
        }
    }

    /// Build GMenu + GtkPopoverMenuBar from scratch.
    private func buildMenu(_ sections: [CommandMenuSection], structureSignature: [String]) {
        let group = g_simple_action_group_new()!
        actionGroup = OpaquePointer(group)

        // GtkPopoverMenuBar expects the top-level GMenu to contain submenus,
        // not action items directly.
        let menuModel = gtk_swift_menu_new()!
        let hideMenuLabels = (
            ProcessInfo.processInfo.environment["QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL"]
                ?? ProcessInfo.processInfo.environment["QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL"]
        ) == "1"

        var itemIndex = 0
        for section in sections {
            let submenu = gtk_swift_menu_new()!

            for item in section.items {
                let actionName = actionName(for: item, at: itemIndex)
                itemIndex += 1
                let action = g_simple_action_new(actionName, nil)!

                // Set enabled state
                gtk_swift_action_set_enabled(gpointer(action), item.isDisabled ? 0 : 1)

                // Connect activate signal. The closure box identity must remain
                // stable across updateInPlace, because GObject stores user_data as
                // a raw pointer (passUnretained). See MenuActionClosure docstring.
                let closureBox = MenuActionClosure(item.action)
                actionClosures[actionName] = closureBox
                let ud = Unmanaged.passUnretained(closureBox).toOpaque()
                g_signal_connect_data(
                    gpointer(action), "activate",
                    unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
                        guard let userData else { return }
                        Unmanaged<MenuActionClosure>.fromOpaque(userData).takeUnretainedValue().closure()
                    } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
                    ud, nil,
                    GConnectFlags(rawValue: 0)
                )

                gtk_swift_action_map_add_action(gpointer(group), gpointer(action))
                actions[actionName] = action

                // Build label with shortcut hint
                var label = item.label
                if let shortcut = item.shortcut {
                    label += "  (\(shortcutHintText(shortcut)))"
                }
                gtk_swift_menu_append(submenu, label, "menu.\(actionName)")

                // Register keyboard shortcut
                if let shortcut = item.shortcut, !item.isDisabled {
                    let regID = KeyboardShortcutRegistry.shared.register(
                        shortcut, windowID: windowID, action: item.action
                    )
                    shortcutRegIDs.append(regID)
                }
            }

            gtk_swift_menu_append_submenu(menuModel, hideMenuLabels ? " " : section.title, submenu)
        }

        // Create the popover menu bar
        let bar = gtk_swift_popover_menu_bar_new_from_model(menuModel)!
        menuBar = bar

        // Insert action group on the bar
        gtk_swift_widget_insert_action_group(bar, "menu", gpointer(group))

        // Prepend menu bar to the container box
        if let box = containerBox {
            let boxPtr = UnsafeMutableRawPointer(box).assumingMemoryBound(to: GtkBox.self)
            gtk_box_prepend(boxPtr, bar)
        }
        menuStructureSignature = structureSignature
    }

    /// Update enabled state and action closures in place.
    private func updateInPlace(_ items: [CommandMenuItem]) {
        // Unregister old shortcuts
        for regID in shortcutRegIDs {
            KeyboardShortcutRegistry.shared.unregister(id: regID)
        }
        shortcutRegIDs.removeAll()

        for (index, item) in items.enumerated() {
            let actionName = actionName(for: item, at: index)

            // Update enabled state
            if let action = actions[actionName] {
                gtk_swift_action_set_enabled(gpointer(action), item.isDisabled ? 0 : 1)
            }

            // Update action closure IN PLACE — the GSimpleAction activate
            // signal holds an unretained pointer to this box as user_data,
            // so we must not replace the box (would dangle the pointer).
            actionClosures[actionName]?.closure = item.action

            // Re-register shortcut with new closure
            if let shortcut = item.shortcut, !item.isDisabled {
                let regID = KeyboardShortcutRegistry.shared.register(
                    shortcut, windowID: windowID, action: item.action
                )
                shortcutRegIDs.append(regID)
            }
        }
    }

    private func actionName(for item: CommandMenuItem, at index: Int) -> String {
        var slug = ""
        for scalar in item.label.lowercased().unicodeScalars {
            switch scalar.value {
            case 48...57, 97...122:
                slug.unicodeScalars.append(scalar)
            default:
                slug.append("_")
            }
        }
        return "cmd_\(index)_\(slug)"
    }

    private func menuStructureSignature(for sections: [CommandMenuSection]) -> [String] {
        var signature: [String] = []
        var itemIndex = 0
        for section in sections {
            signature.append("section:\(section.title)")
            for item in section.items {
                signature.append(actionName(for: item, at: itemIndex))
                itemIndex += 1
            }
        }
        return signature
    }

    /// Clean up all resources.
    ///
    /// `widgetsValid` must be false when called from the window-destroy
    /// path: GTK has already torn down the containerBox/menuBar widget
    /// tree by the time our g_object_set_data_full destroy notifier
    /// fires, so calling gtk_box_remove on them triggers a GTK_IS_BOX
    /// assertion failure. During a live menu rebuild the widgets are
    /// still valid and the caller must pass true so the old menu bar
    /// is actually unparented before a new one is appended.
    private func teardown(widgetsValid: Bool) {
        // Unregister shortcuts
        for regID in shortcutRegIDs {
            KeyboardShortcutRegistry.shared.unregister(id: regID)
        }
        shortcutRegIDs.removeAll()

        // Remove menu bar widget — only when the widget tree is still live.
        if widgetsValid, let bar = menuBar, let box = containerBox {
            let boxPtr = UnsafeMutableRawPointer(box).assumingMemoryBound(to: GtkBox.self)
            gtk_box_remove(boxPtr, bar)
        }
        menuBar = nil

        // Clear actions
        actions.removeAll()
        actionClosures.removeAll()
        menuStructureSignature.removeAll()
        actionGroup = nil
    }

    /// Full cleanup on window destruction. The widget tree is already
    /// gone at this point — only release non-widget resources.
    func destroy() {
        teardown(widgetsValid: false)
        if let observerID = focusedValuesObserverID {
            FocusedValuesStore.shared.removeObserver(id: observerID)
        }
    }

    /// Format shortcut for display in menu label.
    private func shortcutHintText(_ shortcut: KeyboardShortcut) -> String {
        var parts: [String] = []
        if shortcut.modifiers.contains(.command) { parts.append("Ctrl") }
        if shortcut.modifiers.contains(.shift) { parts.append("Shift") }
        if shortcut.modifiers.contains(.option) { parts.append("Alt") }
        let keyText: String
        switch shortcut.key {
        case .return: keyText = "Enter"
        case .escape: keyText = "Esc"
        case .delete: keyText = "Del"
        case .tab: keyText = "Tab"
        case .space: keyText = "Space"
        default: keyText = String(shortcut.key.character).uppercased()
        }
        parts.append(keyText)
        return parts.joined(separator: "+")
    }
}

/// Registers app-level command shortcuts directly on a window without
/// creating a visible menu bar. Hidden-title-bar windows use this so
/// CommandMenu keyboard accelerators remain available while the in-window
/// GtkPopoverMenuBar is intentionally suppressed.
final class GTK4CommandShortcutHost {
    let factory: AnyCommandsFactory
    let windowID: Int
    private var shortcutRegIDs: [ShortcutRegistrationID] = []
    private var focusedValuesObserverID: FocusedValuesObserverID?

    init(factory: @escaping AnyCommandsFactory, windowID: Int) {
        self.factory = factory
        self.windowID = windowID
    }

    func setup() {
        focusedValuesObserverID = FocusedValuesStore.shared.addObserver(windowID: nil) { [weak self] in
            self?.scheduleReevaluation()
        }

        evaluateWithTracking()
    }

    private func scheduleReevaluation() {
        let box = Unmanaged.passRetained(ClosureBox { [weak self] in
            self?.evaluateWithTracking()
        }).toOpaque()
        g_idle_add({ (userData: gpointer?) -> gboolean in
            guard let userData else { return 0 }
            let box = Unmanaged<ClosureBox>.fromOpaque(userData).takeRetainedValue()
            box.closure()
            return 0
        }, box)
    }

    func evaluateWithTracking() {
        #if canImport(Observation) && !os(Linux)
        if #available(macOS 14.0, iOS 17.0, *) {
            withObservationTracking {
                let groups = self.factory()
                self.updateShortcuts(groups)
            } onChange: { [weak self] in
                self?.scheduleReevaluation()
            }
            return
        }
        #endif
        let groups = factory()
        updateShortcuts(groups)
    }

    private func updateShortcuts(_ groups: [CommandGroupPlacement: [CommandMenuItem]]) {
        for regID in shortcutRegIDs {
            KeyboardShortcutRegistry.shared.unregister(id: regID)
        }
        shortcutRegIDs.removeAll()

        let allItems = commandMenuSections(from: groups).flatMap { $0.items }

        for item in allItems {
            guard let shortcut = item.shortcut, !item.isDisabled else { continue }
            let regID = KeyboardShortcutRegistry.shared.register(
                shortcut,
                windowID: windowID,
                action: item.action
            )
            shortcutRegIDs.append(regID)
            gtkBackendDebugLog("registered command shortcut label='\(item.label)' shortcut=\(gtkShortcutDebugText(shortcut)) windowID=\(windowID)")
        }
        gtkBackendDebugLog("registered \(shortcutRegIDs.count) command shortcuts for windowID=\(windowID)")
    }

    func destroy() {
        for regID in shortcutRegIDs {
            KeyboardShortcutRegistry.shared.unregister(id: regID)
        }
        shortcutRegIDs.removeAll()

        if let observerID = focusedValuesObserverID {
            FocusedValuesStore.shared.removeObserver(id: observerID)
        }
        focusedValuesObserverID = nil
    }

    func shortcutCountForTesting() -> Int {
        shortcutRegIDs.count
    }
}

/// Attach a menu bar host to a window if Commands are declared.
func gtkSetupMenuBarIfNeeded(
    winPtr: UnsafeMutablePointer<GtkWidget>,
    contentWidget: UnsafeMutablePointer<GtkWidget>,
    windowID: Int
) {
    guard let commandsFactory = globalCommandsFactory else { return }
    let host = GTK4MenuBarHost(winPtr: winPtr, factory: commandsFactory, windowID: windowID)
    host.setup(contentWidget: contentWidget)

    // Store the host on the window for lifecycle management
    let retained = Unmanaged.passRetained(host).toOpaque()
    let gobject = UnsafeMutableRawPointer(winPtr).assumingMemoryBound(to: GObject.self)
    g_object_set_data_full(gobject, "gtk-swift-menu-bar-host", retained) { userData in
        guard let userData else { return }
        let host = Unmanaged<GTK4MenuBarHost>.fromOpaque(userData).takeRetainedValue()
        host.destroy()
    }
}

/// Attach command shortcuts to a hidden-title-bar window if Commands are declared.
func gtkSetupCommandShortcutsIfNeeded(
    winPtr: UnsafeMutablePointer<GtkWidget>,
    windowID: Int
) {
    guard let commandsFactory = globalCommandsFactory else { return }
    let host = GTK4CommandShortcutHost(factory: commandsFactory, windowID: windowID)
    host.setup()

    let retained = Unmanaged.passRetained(host).toOpaque()
    let gobject = UnsafeMutableRawPointer(winPtr).assumingMemoryBound(to: GObject.self)
    g_object_set_data_full(gobject, "gtk-swift-command-shortcut-host", retained) { userData in
        guard let userData else { return }
        let host = Unmanaged<GTK4CommandShortcutHost>.fromOpaque(userData).takeRetainedValue()
        host.destroy()
    }
}

/// GTK4 rendering backend for SwiftOpenUI.
public struct GTK4Backend: RenderBackend {
    public init() {
        installImageRendererBackend()
    }

    public func installImageRendererBackend() {
        installGTK4ImageRendererBackend()
    }

    public func run<A: App>(_ appType: A.Type) {
        installImageRendererBackend()

        // Load bundled icon fonts into FontConfig before GTK/Pango builds
        // its default font map. Safe to call multiple times but cheapest
        // to do exactly once per process, and must happen before any widget
        // asks Pango to resolve the "Material Symbols Rounded" family.
        gtkRegisterBundledIconFont()

        // Dark scheme (QUILLUI_COLOR_SCHEME=dark): ask GTK for the dark
        // theme variant before init so widget chrome matches the semantic
        // colors' dark resolution. An explicit GTK_THEME wins.
        if Color.quillPrefersDarkScheme,
           ProcessInfo.processInfo.environment["GTK_THEME"] == nil {
            setenv("GTK_THEME", "Adwaita:dark", 1)
        }

        let factory: (OpaquePointer?) -> Void = { appPtr in
            gtkBackendDebugLog("app activate type=\(A.self)")
            // Inject openWindow action into the environment so views
            // can programmatically open Window scenes by id.
            var env = getCurrentEnvironment()
            env.openWindow = OpenWindowAction(
                handler: { id in
                    GTK4WindowRegistry.shared.open(id: id)
                },
                valueHandler: { valueTypeKey, value in
                    GTK4WindowRegistry.shared.openValue(typeKey: valueTypeKey, value: value)
                }
            )
            setCurrentEnvironment(env)

            // App.init/App.body are @MainActor (Apple semantics); the GTK app
            // activate callback runs on the GTK main loop == main thread.
            MainActor.assumeIsolated {
                gtkBackendDebugLog("app init start type=\(A.self)")
                let instance = A()
                SwiftOpenUIAppLifecycle.appDidInitialize()
                gtkBackendDebugLog("app body render start type=\(A.self) body=\(A.Body.self)")
                gtkWithAppStateSource(instance) {
                    gtkRenderScene(instance.body, app: appPtr)
                }
                gtkBackendDebugLog("app body render end type=\(A.self)")
            }
        }

        // Pump Foundation RunLoop sources (Timer, etc.) periodically.
        // GTK4's GMainLoop blocks the thread, so Foundation
        // timers (e.g. Timer.scheduledTimer) never fire unless we
        // explicitly spin RunLoop.main from a GLib timeout source.
        g_timeout_add(5, { _ -> gboolean in
            let limit = Date(timeIntervalSinceNow: 0.001)
            _ = RunLoop.main.run(mode: .default, before: limit)
            return 1 // G_SOURCE_CONTINUE
        }, nil)

        if gtk_init_check() == 0 {
            return
        }
        factory(nil)

        let loop = g_main_loop_new(nil, 0)
        g_main_loop_run(loop)
        g_main_loop_unref(loop)
    }
}

/// GTK4 rendering for Window scenes (single-instance, identified windows).
extension Window: GTKWindowRenderable {
    func gtkRender(app: OpaquePointer?) {
        let appStateSource = gtkCurrentAppStateSource
        // Register a factory for all Window scenes so openWindow(id:) works
        // regardless of launch behavior.
        GTK4WindowRegistry.shared.register(id: id) { [self] in
            self.gtkCreateWindow(app: app, appStateSource: appStateSource)
        }

        // For non-suppressed windows, use the registry's open(id:) to
        // create or refocus. This prevents duplicates when the GtkApplication
        // "activate" signal fires more than once (e.g., app re-activation).
        if launchBehavior != .suppressed {
            GTK4WindowRegistry.shared.open(id: id)
        }
    }

    func gtkCreateWindow(app: OpaquePointer?, appStateSource: Any? = nil) {
        let window: UnsafeMutablePointer<GtkWidget>
        if let app {
            window = gtk_application_window_new(gtkApplicationPointer(app))!
        } else {
            window = gtk_window_new()!
        }
        let winPtr = windowPointer(window)
        gtk_window_set_title(winPtr, title)
        SwiftOpenUIWindowLifecycle.notifyWindowOpened(
            id: id,
            title: title,
            nativeHandle: Int(bitPattern: winPtr)
        )

        // Set window ID in environment for keyboard shortcut scoping
        var wsEnv = getCurrentEnvironment()
        wsEnv.windowID = Int(bitPattern: winPtr)
        setCurrentEnvironment(wsEnv)

        let contentWidget = widgetFromOpaque(
            gtkRenderWindowRootView(content, appStateSource: appStateSource)
        )

        if let w = defaultWindowWidth, let h = defaultWindowHeight {
            gtk_window_set_default_size(winPtr, gint(w), gint(h))
        }

        let minReqW = minWindowWidth.map { Int32($0) } ?? -1
        let minReqH = minWindowHeight.map { Int32($0) } ?? -1
        if minReqW >= 0 || minReqH >= 0 {
            gtk_widget_set_size_request(contentWidget, minReqW, minReqH)
        }

        let rootContentWidget = gtkCreateRootPresentationContainer(winPtr: winPtr, contentWidget: contentWidget)
        gtkConfigureRootContentToFillWindow(rootContentWidget)

        gtk_window_set_child(winPtr, rootContentWidget)
        let winWidget = widgetPointer(winPtr)
        if gtkShouldShowWindowMenuBar() {
            gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: rootContentWidget, windowID: Int(bitPattern: winPtr))
        } else {
            gtkSetupCommandShortcutsIfNeeded(winPtr: winWidget, windowID: Int(bitPattern: winPtr))
        }
        gtkAttachKeyboardShortcutController(to: winWidget)
        gtkAttachWindowActivationHandler(to: winWidget)
        gtk_window_present(winPtr)

        // Track the live window so repeated openWindow(id:) refocuses
        // instead of creating duplicates. Hook the destroy signal to
        // clear the pointer when the window is closed, preventing
        // use-after-free on subsequent open(id:) calls.
        let windowId = id
        GTK4WindowRegistry.shared.setLiveWindow(id: windowId, window: winPtr)
        let windowTitle = title
        let nativeHandle = Int(bitPattern: winPtr)

        let box = ClosureBox {
            GTK4WindowRegistry.shared.clearLiveWindow(id: windowId)
            SwiftOpenUIWindowLifecycle.notifyWindowClosed(
                id: windowId,
                title: windowTitle,
                nativeHandle: nativeHandle
            )
        }
        let ud = Unmanaged.passRetained(box).toOpaque()
        g_signal_connect_data(
            gpointer(winPtr), "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            ud,
            { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
            },
            GConnectFlags(rawValue: 0)
        )
    }
}

/// GTK4 rendering for TupleScene — renders both child scenes.
extension TupleScene: GTKWindowRenderable {
    func gtkRender(app: OpaquePointer?) {
        gtkBackendDebugLog("TupleScene render scene0=\(S0.self) scene1=\(S1.self)")
        gtkRenderScene(scene0, app: app)
        gtkRenderScene(scene1, app: app)
    }
}

/// GTK fallback for SwiftUI's MenuBarExtra.
///
/// GTK4 has no cross-desktop tray primitive in core GTK, so this renders a
/// small auxiliary menu-button window. The label is always visible and clicking
/// it opens the scene's SwiftUI content in a GTK popover. Applications that
/// provide an AppIndicator/libayatana integration can opt out with
/// `QUILLUI_GTK_MENU_BAR_EXTRA_FALLBACK=0`.
extension MenuBarExtra: GTKWindowRenderable {
    func gtkRender(app: OpaquePointer?) {
        guard ProcessInfo.processInfo.environment["QUILLUI_GTK_MENU_BAR_EXTRA_FALLBACK"] != "0" else {
            gtkBackendDebugLog("MenuBarExtra fallback disabled label=\(LabelContent.self)")
            return
        }

        gtkBackendDebugLog("MenuBarExtra render start label=\(LabelContent.self) content=\(Content.self)")
        let window: UnsafeMutablePointer<GtkWidget>
        if let app {
            window = gtk_application_window_new(gtkApplicationPointer(app))!
        } else {
            window = gtk_window_new()!
        }
        let winPtr = windowPointer(window)
        gtk_window_set_title(winPtr, "MenuBarExtra")
        gtk_window_set_decorated(winPtr, 0)
        gtk_window_set_resizable(winPtr, 0)
        gtk_window_set_default_size(winPtr, 180, 44)

        let button = gtk_menu_button_new()!
        gtk_widget_set_margin_top(button, 6)
        gtk_widget_set_margin_bottom(button, 6)
        gtk_widget_set_margin_start(button, 8)
        gtk_widget_set_margin_end(button, 8)
        gtk_widget_set_halign(button, GTK_ALIGN_FILL)
        gtk_widget_set_valign(button, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(button, 1)
        gtk_widget_set_vexpand(button, 1)

        let labelWidget = widgetFromOpaque(gtkRenderView(label))
        gtk_swift_menu_button_set_always_show_arrow(button, 0)
        gtk_swift_menu_button_set_child(button, labelWidget)

        let contentWidget = widgetFromOpaque(gtkRenderView(content))
        let scrolled = gtk_scrolled_window_new()!
        gtk_widget_set_size_request(scrolled, 340, 560)
        gtk_scrolled_window_set_child(OpaquePointer(scrolled), contentWidget)

        let popover = gtk_popover_new()!
        gtk_swift_popover_set_child(popover, scrolled)
        gtk_swift_menu_button_set_popover(button, popover)

        gtk_window_set_child(winPtr, button)
        gtkBackendDebugLog("MenuBarExtra present handle=\(Int(bitPattern: winPtr))")
        gtk_window_present(winPtr)
        gtkBackendDebugLog("MenuBarExtra presented handle=\(Int(bitPattern: winPtr))")
    }
}

/// GTK4 rendering for Group<Scene> — transparent scene grouping.
extension Group: GTKWindowRenderable where Content: Scene {
    func gtkRender(app: OpaquePointer?) {
        gtkBackendDebugLog("Group<Scene> render content=\(Content.self)")
        gtkRenderScene(content, app: app)
    }
}

/// Registry for single-instance Window scenes. Tracks factories and live
/// window pointers to enforce the one-window-per-id contract.
class GTK4WindowRegistry {
    static let shared = GTK4WindowRegistry()
    private var factories: [String: () -> Void] = [:]
    private var valueFactories: [String: (Any) -> Void] = [:]
    private var liveWindows: [String: UnsafeMutablePointer<GtkWindow>] = [:]

    func register(id: String, factory: @escaping () -> Void) {
        factories[id] = factory
    }

    func registerValue(typeKey: String, factory: @escaping (Any) -> Void) {
        valueFactories[typeKey] = factory
    }

    /// Record a live GTK window for the given id.
    func setLiveWindow(id: String, window: UnsafeMutablePointer<GtkWindow>) {
        liveWindows[id] = window
    }

    /// Clear the live window pointer (called from the destroy signal handler).
    func clearLiveWindow(id: String) {
        liveWindows.removeValue(forKey: id)
    }

    /// Open or refocus the window with the given id.
    /// If a live window exists, it is presented (refocused).
    /// Otherwise, the factory creates a new one.
    func open(id: String) {
        if let existing = liveWindows[id] {
            gtk_window_present(existing)
            return
        }
        // Window was closed or never created — invoke the factory.
        factories[id]?()
    }

    /// Open a value-based WindowGroup. SwiftUI treats these as window groups,
    /// so this deliberately creates a fresh top-level window for each request.
    func openValue(typeKey: String, value: Any) {
        valueFactories[typeKey]?(value)
    }
}

/// Recursively render a Scene. Terminal scenes (WindowGroup, Window) render
/// directly; composite scenes recurse through their body.
private func gtkRenderScene<S: Scene>(_ scene: S, app: OpaquePointer?) {
    gtkBackendDebugLog("render scene type=\(S.self) body=\(S.Body.self)")
    if let renderable = scene as? GTKWindowRenderable {
        gtkBackendDebugLog("render primitive scene type=\(S.self)")
        renderable.gtkRender(app: app)
        return
    }
    // Composite scene — recurse through body. Scene.body is @MainActor
    // (Apple semantics); scene rendering only runs on the GTK main loop.
    if S.Body.self != Never.self {
        MainActor.assumeIsolated { gtkRenderScene(scene.body, app: app) }
    } else {
        gtkBackendDebugLog("skip primitive scene without GTK renderer type=\(S.self)")
    }
}
