import CGTK
import CGTKBridge
import SwiftOpenUI
import SwiftOpenUISymbols
import Foundation

/// Marker string for Spacer widgets.
let gtkSwiftSpacerMarker = "gtk-swift-spacer"
/// Marker string for Divider widgets.
let gtkSwiftDividerMarker = "gtk-swift-divider"
/// Marker string for backend-only layout helpers that should not be
/// considered rendered SwiftOpenUI content by snapshot capture.
let gtkSwiftLayoutHelperMarker = "gtk-swift-layout-helper"
/// Marker string for SwiftUI EmptyView/absent-builder branches. Wrappers
/// propagate this so modifiers on an absent branch do not become hittable,
/// full-size GTK overlays.
let gtkSwiftEmptyViewMarker = "gtk-swift-empty-view"
/// Marker string for SwiftUI ScrollView widgets that should receive
/// ScrollViewReader target adjustments.
let gtkSwiftScrollViewMarker = "gtk-swift-scroll-view"
/// Marker string for vertical SwiftUI ScrollViews.
let gtkSwiftVerticalScrollViewMarker = "gtk-swift-vertical-scroll-view"
/// Marker string for views that intentionally fill the parent's vertical
/// proposal, rather than merely inheriting GTK vexpand from descendants.
private let gtkSwiftVerticalFillIntentMarker = "gtk-swift-vertical-fill-intent"
/// Marker string for `.fixedSize(horizontal: false, ...)` widgets. SwiftUI lets
/// these views accept the parent's proposed width, so GTK must not advertise
/// their unconstrained text width as the row's natural width.
private let gtkSwiftHorizontallyCompressibleFixedSizeMarker = "gtk-swift-horizontal-compressible-fixed-size"
/// Marker string for indeterminate SwiftUI ProgressView widgets.
let gtkSwiftIndeterminateProgressMarker = "gtk-swift-indeterminate-progress"

private final class GTKMainActorIsolatedResult<Value>: @unchecked Sendable {
    var value: Value!
}

func gtkAssumeMainActorIsolated<Value>(_ body: @MainActor () -> Value) -> Value {
    let result = GTKMainActorIsolatedResult<Value>()
    MainActor.assumeIsolated {
        result.value = body()
    }
    return result.value
}

private func gtkMarkLayoutHelper(_ widget: UnsafeMutablePointer<GtkWidget>) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, gtkSwiftLayoutHelperMarker, UnsafeMutableRawPointer(bitPattern: 1))
}

private func gtkHasLayoutMarker(_ widget: UnsafeMutablePointer<GtkWidget>, key: String) -> Bool {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    return g_object_get_data(gobject, key) != nil
}

private func gtkSetLayoutMarker(_ widget: UnsafeMutablePointer<GtkWidget>, key: String) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, key, UnsafeMutableRawPointer(bitPattern: 1))
}

private func gtkMarkVerticalFillIntent(_ widget: UnsafeMutablePointer<GtkWidget>) {
    gtkSetLayoutMarker(widget, key: gtkSwiftVerticalFillIntentMarker)
}

private func gtkHasVerticalFillIntent(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    gtkHasLayoutMarker(widget, key: gtkSwiftVerticalFillIntentMarker)
}

private func gtkMarkEmptyView(_ widget: UnsafeMutablePointer<GtkWidget>) {
    gtkSetLayoutMarker(widget, key: gtkSwiftEmptyViewMarker)
    gtk_widget_set_can_target(widget, 0)
    gtk_widget_set_size_request(widget, 0, 0)
}

private func gtkIsEmptyViewWidget(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    gtkHasLayoutMarker(widget, key: gtkSwiftEmptyViewMarker)
}

private func gtkCreateEmptyViewWidget() -> UnsafeMutablePointer<GtkWidget> {
    let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    gtkMarkEmptyView(box)
    return box
}

private func gtkMarkSwiftUIScrollView(_ widget: UnsafeMutablePointer<GtkWidget>, hasVerticalAxis: Bool) {
    gtkSetLayoutMarker(widget, key: gtkSwiftScrollViewMarker)
    if hasVerticalAxis {
        gtkSetLayoutMarker(widget, key: gtkSwiftVerticalScrollViewMarker)
    }
}

private func gtkIsSwiftUIVerticalScrollView(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    gtkHasLayoutMarker(widget, key: gtkSwiftVerticalScrollViewMarker)
}

private func gtkPropagateSingleChildLayoutMarkers(
    from children: [UnsafeMutablePointer<GtkWidget>],
    to wrapper: UnsafeMutablePointer<GtkWidget>
) {
    guard children.count == 1, let child = children.first else { return }
    if gtkHasLayoutMarker(child, key: gtkSwiftSpacerMarker) {
        gtkSetLayoutMarker(wrapper, key: gtkSwiftSpacerMarker)
    }
    if gtkHasLayoutMarker(child, key: gtkSwiftDividerMarker) {
        gtkSetLayoutMarker(wrapper, key: gtkSwiftDividerMarker)
    }
    if gtkHasLayoutMarker(child, key: gtkSwiftEmptyViewMarker) {
        gtkMarkEmptyView(wrapper)
    }
    if gtkHasVerticalFillIntent(child) {
        gtkMarkVerticalFillIntent(wrapper)
    }
}

private func gtkLayoutChildViews(from view: any View, depth: Int = 0) -> [any View] {
    guard depth < 24 else { return [view] }

    let mirror = Mirror(reflecting: view)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first?.value as? any View else { return [] }
        return gtkLayoutChildViews(from: child, depth: depth + 1)
    }

    if mirror.displayStyle == .enum,
       String(reflecting: Swift.type(of: view)).contains("_ConditionalView") {
        for child in mirror.children {
            if let nested = child.value as? any View {
                return gtkLayoutChildViews(from: nested, depth: depth + 1)
            }
        }
        return []
    }

    if let keyedRows = view as? GTKKeyedListRowProducer {
        return keyedRows.gtkKeyedListRows(depth: depth + 1).flatMap {
            gtkLayoutChildViews(from: $0, depth: depth + 1)
        }
    }

    if let transparent = view as? any TransparentMultiChildView {
        return transparent.children.flatMap { gtkLayoutChildViews(from: $0, depth: depth + 1) }
    }

    return [view]
}

private func gtkVStackSpacing(_ spacing: Int) -> Int {
    spacing == stackDefaultSpacing ? 0 : resolveStackSpacing(spacing)
}

private final class GTKScrollViewCrossAxisContext {
    let child: UnsafeMutablePointer<GtkWidget>
    let fillWidth: Bool
    let fillHeight: Bool
    var lastWidth: gint = -1
    var lastHeight: gint = -1

    init(child: UnsafeMutablePointer<GtkWidget>, fillWidth: Bool, fillHeight: Bool) {
        self.child = child
        self.fillWidth = fillWidth
        self.fillHeight = fillHeight
    }
}

private let gtkScrollViewCrossAxisTickCallback: GtkTickCallback = { widget, _, userData in
    guard let widget, let userData else { return 0 }
    let context = Unmanaged<GTKScrollViewCrossAxisContext>.fromOpaque(userData).takeUnretainedValue()
    let width = gtk_widget_get_width(widget)
    let height = gtk_widget_get_height(widget)

    if context.fillWidth, width > 1, width != context.lastWidth {
        context.lastWidth = width
        let horizontalMargins = gtk_widget_get_margin_start(context.child)
            + gtk_widget_get_margin_end(context.child)
        gtk_widget_set_size_request(context.child, max(gint(1), width - horizontalMargins), -1)
        gtk_widget_queue_resize(context.child)
    }
    if context.fillWidth {
        gtkClampHiddenHorizontalScrollOffset(widget)
    }
    if context.fillHeight, height > 1, height != context.lastHeight {
        context.lastHeight = height
        let verticalMargins = gtk_widget_get_margin_top(context.child)
            + gtk_widget_get_margin_bottom(context.child)
        gtk_widget_set_size_request(context.child, -1, max(gint(1), height - verticalMargins))
        gtk_widget_queue_resize(context.child)
    }

    return 1
}

private func gtkClampHiddenHorizontalScrollOffset(_ scrolled: UnsafeMutablePointer<GtkWidget>) {
    guard let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) else {
        return
    }
    let lower = gtk_adjustment_get_lower(hadjustment)
    if gtk_adjustment_get_value(hadjustment) != lower {
        gtk_adjustment_set_value(hadjustment, lower)
    }
}

private func gtkInstallScrollViewCrossAxisFill(
    on scrolled: UnsafeMutablePointer<GtkWidget>,
    child: UnsafeMutablePointer<GtkWidget>,
    fillWidth: Bool,
    fillHeight: Bool
) {
    guard fillWidth || fillHeight else { return }
    let context = GTKScrollViewCrossAxisContext(
        child: child,
        fillWidth: fillWidth,
        fillHeight: fillHeight
    )
    let contextPtr = Unmanaged.passRetained(context).toOpaque()
    _ = gtk_widget_add_tick_callback(
        scrolled,
        gtkScrollViewCrossAxisTickCallback,
        contextPtr,
        { userData in Unmanaged<GTKScrollViewCrossAxisContext>.fromOpaque(userData!).release() }
    )
}

private final class GTKRowWidthContext {
    let child: UnsafeMutablePointer<GtkWidget>
    var lastWidth: gint = -1
    var lastHeight: gint = -1

    init(child: UnsafeMutablePointer<GtkWidget>) {
        self.child = child
    }
}

private func gtkResolveRowWidth(
    widget: UnsafeMutablePointer<GtkWidget>,
    context: GTKRowWidthContext
) {
    let width = gtk_widget_get_width(widget)
    guard width > 1, width != context.lastWidth else { return }

    context.lastWidth = width
    let horizontalMargins = gtk_widget_get_margin_start(context.child)
        + gtk_widget_get_margin_end(context.child)
    let childWidth = max(gint(1), width - horizontalMargins)
    gtkUpdateWrappingRowLabelWidths(context.child, forWidth: childWidth)
    var minimumHeight: gint = 0
    var naturalHeight: gint = 0
    gtk_widget_measure(
        context.child,
        GTK_ORIENTATION_VERTICAL,
        childWidth,
        &minimumHeight,
        &naturalHeight,
        nil,
        nil
    )
    gtkListDebugLog(
        "row-width widget=\(String(cString: g_type_name(gtk_swift_get_widget_type(widget)))) child=\(String(cString: g_type_name(gtk_swift_get_widget_type(context.child)))) width=\(width) childWidth=\(childWidth) measured=\(minimumHeight)x\(naturalHeight)"
    )
    gtkDebugCollapsedRowTree(
        root: context.child,
        proposedWidth: childWidth,
        measuredHeight: max(minimumHeight, naturalHeight)
    )
    let height = max(gint(1), minimumHeight, naturalHeight)
    context.lastHeight = height
    gtk_widget_set_size_request(context.child, childWidth, height)
    gtk_widget_queue_resize(context.child)
    gtk_widget_queue_resize(widget)
}

private let gtkRowWidthTickCallback: GtkTickCallback = { widget, _, userData in
    guard let widget, let userData else { return 0 }
    let context = Unmanaged<GTKRowWidthContext>.fromOpaque(userData).takeUnretainedValue()
    gtkResolveRowWidth(widget: widget, context: context)
    return 1
}

private let gtkRowWidthNotifyCallback: @convention(c) (
    gpointer?,
    gpointer?,
    gpointer?
) -> Void = { object, _, userData in
    guard let object, let userData else { return }
    let widget = object.assumingMemoryBound(to: GtkWidget.self)
    guard gtk_swift_is_widget(widget) != 0 else { return }
    let context = Unmanaged<GTKRowWidthContext>.fromOpaque(userData).takeUnretainedValue()
    gtkResolveRowWidth(widget: widget, context: context)
}

private func gtkInstallRowWidthFill(
    on row: UnsafeMutablePointer<GtkWidget>,
    child: UnsafeMutablePointer<GtkWidget>
) {
    let context = GTKRowWidthContext(child: child)
    let contextPtr = Unmanaged.passRetained(context).toOpaque()
    _ = gtk_widget_add_tick_callback(
        row,
        gtkRowWidthTickCallback,
        contextPtr,
        { userData in Unmanaged<GTKRowWidthContext>.fromOpaque(userData!).release() }
    )
    g_signal_connect_data(
        gpointer(row),
        "notify::width",
        unsafeBitCast(gtkRowWidthNotifyCallback, to: GCallback.self),
        contextPtr,
        nil,
        GConnectFlags(rawValue: 0)
    )
}

private func gtkDebugCollapsedRowTree(
    root: UnsafeMutablePointer<GtkWidget>,
    proposedWidth: gint,
    measuredHeight: gint
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_LIST_TREE"] == "1" else {
        return
    }
    guard measuredHeight <= gtkComplexListRowMinimumHeight else { return }

    var lines: [String] = []
    gtkCollectDebugRowTreeLines(
        node: root,
        root: root,
        proposedWidth: proposedWidth,
        depth: 0,
        lines: &lines
    )
    gtkListDebugLog("collapsed-row-tree\n\(lines.joined(separator: "\n"))")
}

private func gtkCollectDebugRowTreeLines(
    node: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    proposedWidth: gint,
    depth: Int,
    lines: inout [String]
) {
    guard depth < 8, lines.count < 120 else { return }

    var minW: gint = 0
    var natW: gint = 0
    var minH: gint = 0
    var natH: gint = 0
    gtk_widget_measure(node, GTK_ORIENTATION_HORIZONTAL, -1, &minW, &natW, nil, nil)
    gtk_widget_measure(node, GTK_ORIENTATION_VERTICAL, proposedWidth, &minH, &natH, nil, nil)
    var rootX = 0.0
    var rootY = 0.0
    _ = gtk_widget_translate_coordinates(node, root, 0, 0, &rootX, &rootY)
    let indent = String(repeating: "  ", count: depth)
    lines.append(
        "\(indent)\(String(cString: g_type_name(gtk_swift_get_widget_type(node)))) alloc=\(gtk_widget_get_width(node))x\(gtk_widget_get_height(node)) origin=\(Int(rootX)),\(Int(rootY)) nat=\(natW)x\(natH) min=\(minW)x\(minH) hex=\(gtk_widget_get_hexpand(node)) vex=\(gtk_widget_get_vexpand(node)) margins=\(gtk_widget_get_margin_start(node)),\(gtk_widget_get_margin_top(node)),\(gtk_widget_get_margin_end(node)),\(gtk_widget_get_margin_bottom(node))"
    )

    var child = gtk_widget_get_first_child(node)
    while let current = child {
        gtkCollectDebugRowTreeLines(
            node: current,
            root: root,
            proposedWidth: proposedWidth,
            depth: depth + 1,
            lines: &lines
        )
        child = gtk_widget_get_next_sibling(current)
    }
}

private final class GTKWidthResolvedHeightContext {
    var lastWidth: gint = -1
    var lastHeight: gint = -1
}

private let gtkWidthResolvedHeightTickCallback: GtkTickCallback = { widget, _, userData in
    guard let widget, let userData else { return 0 }
    let context = Unmanaged<GTKWidthResolvedHeightContext>.fromOpaque(userData).takeUnretainedValue()
    let width = gtk_widget_get_width(widget)
    guard width > 1, width != context.lastWidth else { return 1 }

    context.lastWidth = width
    var minimumHeight: gint = 0
    var naturalHeight: gint = 0
    gtk_widget_measure(
        widget,
        GTK_ORIENTATION_VERTICAL,
        width,
        &minimumHeight,
        &naturalHeight,
        nil,
        nil
    )
    let resolvedHeight = max(gint(1), minimumHeight, naturalHeight)
    guard resolvedHeight != context.lastHeight else { return 1 }

    context.lastHeight = resolvedHeight
    let requestedWidth: gint = gtkHasLayoutMarker(
        widget,
        key: gtkSwiftHorizontallyCompressibleFixedSizeMarker
    ) ? 1 : -1
    gtk_widget_set_size_request(widget, requestedWidth, resolvedHeight)
    gtk_widget_queue_resize(widget)
    return 1
}

private func gtkInstallWidthResolvedHeight(on widget: UnsafeMutablePointer<GtkWidget>) {
    let context = GTKWidthResolvedHeightContext()
    let contextPtr = Unmanaged.passRetained(context).toOpaque()
    _ = gtk_widget_add_tick_callback(
        widget,
        gtkWidthResolvedHeightTickCallback,
        contextPtr,
        { userData in Unmanaged<GTKWidthResolvedHeightContext>.fromOpaque(userData!).release() }
    )
}

/// Convert a Double pixel dimension into an integer GTK size. GTK widgets
/// use integer pixels, so plain `gint(x)` truncates — a 0.5pt divider
/// collapses to 0 and becomes invisible. Round positive sub-pixel values
/// up so that hairline dividers and similar sub-pixel shapes are at least
/// one device pixel tall. Larger positive values keep their integer part
/// so existing whole-pixel layouts are unchanged.
@inline(__always)
private func gtkPixelSize(_ value: Double) -> gint {
    if value > 0 && value < 1 { return 1 }
    return gint(value)
}

private func gtkTextInputFocusDescriptorContent(
    typeName: String,
    binding: Binding<String>,
    label: String = "",
    includeValueWhenUnidentified: Bool = false
) -> String {
    if let identity = binding.quillUIIdentity {
        return "\(typeName)|binding:\(identity)"
    }

    if includeValueWhenUnidentified {
        return "\(typeName)|label:\(label)|value:\(binding.wrappedValue)"
    }
    return "\(typeName)|label:\(label)"
}

public var quill_gtk_button_paint_hook: ((OpaquePointer, OpaquePointer, Bool) -> Bool)? = nil
public var quill_gtk_text_field_paint_hook: ((OpaquePointer, Bool) -> OpaquePointer?)? = nil
public var quill_gtk_text_editor_paint_hook: ((OpaquePointer, OpaquePointer) -> OpaquePointer?)? = nil
public var quill_gtk_toggle_paint_hook: ((OpaquePointer, Bool, Bool, String) -> OpaquePointer?)? = nil
public var quill_gtk_list_row_paint_hook: ((OpaquePointer, OpaquePointer, Bool, Bool) -> Bool)? = nil

private final class GTKTextBindingIdleUpdate {
    let binding: Binding<String>
    let value: String

    init(binding: Binding<String>, value: String) {
        self.binding = binding
        self.value = value
    }

    func apply() {
        if binding.wrappedValue != value {
            binding.wrappedValue = value
        }
    }
}

private var gtkPendingTextBindingUpdate: GTKTextBindingIdleUpdate?
private var gtkPendingTextBindingSourceID: guint = 0

func gtkFlushPendingTextBindingUpdate() {
    if gtkPendingTextBindingSourceID != 0 {
        g_source_remove(gtkPendingTextBindingSourceID)
        gtkPendingTextBindingSourceID = 0
    }
    let pending = gtkPendingTextBindingUpdate
    gtkPendingTextBindingUpdate = nil
    pending?.apply()
}

/// Debounced entry->binding writes. Writing the binding on every keystroke
/// schedules a rebuild per keystroke, and any host whose plan is not
/// narrow-eligible then tears down the focused entry mid-typing — the rest
/// of the typed keys land on whatever GTK focuses next (Space activates it).
/// One pending write replaces the previous and flushes after a typing pause,
/// or eagerly before any app action, keyboard shortcut, or submit runs
/// (actions read the model, never the entry). Same-field edits always keep a
/// prefix relation between successive values; unrelated values mean a
/// different field, so the previous field's pending write flushes first and
/// is never lost.
private func gtkScheduleTextBindingUpdate(_ binding: Binding<String>, value: String) {
    if let pending = gtkPendingTextBindingUpdate,
       !value.hasPrefix(pending.value), !pending.value.hasPrefix(value) {
        gtkFlushPendingTextBindingUpdate()
    }
    if gtkPendingTextBindingSourceID != 0 {
        g_source_remove(gtkPendingTextBindingSourceID)
        gtkPendingTextBindingSourceID = 0
    }
    gtkPendingTextBindingUpdate = GTKTextBindingIdleUpdate(binding: binding, value: value)
    gtkPendingTextBindingSourceID = g_timeout_add(250, { _ -> gboolean in
        gtkPendingTextBindingSourceID = 0
        let pending = gtkPendingTextBindingUpdate
        gtkPendingTextBindingUpdate = nil
        pending?.apply()
        return 0
    }, nil)
}

private func gtkPerformSubmitAction(_ submitAction: SubmitAction) {
    gtkFlushPendingTextBindingUpdate()
    submitAction()
}

private let gtkTextInputSubmitActivateHandler: @convention(c) (gpointer?, gpointer?) -> Void = { _, userData in
    guard let userData else { return }
    Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
}

private func gtkKeyEquivalent(for keyval: guint) -> KeyEquivalent? {
    switch keyval {
    case 0xff0d, 0xff8d:
        return .return
    case 0xff09, 0xfe20:
        return .tab
    case 0xff52:
        return .upArrow
    case 0xff54:
        return .downArrow
    case 0xff51:
        return .leftArrow
    case 0xff53:
        return .rightArrow
    case 0xff1b:
        return .escape
    case 0xffff:
        return .deleteForward
    case 0xff08:
        return .delete
    case 0x20:
        return .space
    default:
        guard let scalar = UnicodeScalar(UInt32(keyval)) else { return nil }
        return KeyEquivalent(Character(scalar))
    }
}

private final class GTKTextInputKeyControllerBox {
    let submitAction: SubmitAction?
    let keyPressActions: [KeyPressAction]

    init(submitAction: SubmitAction?, keyPressActions: [KeyPressAction]) {
        self.submitAction = submitAction
        self.keyPressActions = keyPressActions
    }

    func handle(keyval: guint) -> gboolean {
        if let key = gtkKeyEquivalent(for: keyval) {
            for keyPressAction in keyPressActions.reversed() where keyPressAction.key == key {
                gtkFlushPendingTextBindingUpdate()
                if keyPressAction.handler() == .handled {
                    return 1
                }
            }
        }

        switch keyval {
        case 0xff0d, 0xff8d:
            guard let submitAction else { return 0 }
            gtkPerformSubmitAction(submitAction)
            return 1
        default:
            return 0
        }
    }
}

private let gtkTextInputKeyPressedHandler: @convention(c) (OpaquePointer?, guint, guint, guint, gpointer?) -> gboolean = { _, keyval, _, _, userData in
    guard let userData else { return 0 }
    return Unmanaged<GTKTextInputKeyControllerBox>.fromOpaque(userData).takeUnretainedValue().handle(keyval: keyval)
}

private func gtkInstallTextInputKeyController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    submitAction: SubmitAction?,
    keyPressActions: [KeyPressAction]
) {
    guard submitAction != nil || !keyPressActions.isEmpty else { return }

    let keyController = gtk_swift_key_capture_controller()!
    let keyBox = Unmanaged.passRetained(GTKTextInputKeyControllerBox(
        submitAction: submitAction,
        keyPressActions: keyPressActions
    )).toOpaque()
    g_signal_connect_data(
        gpointer(keyController), "key-pressed",
        unsafeBitCast(gtkTextInputKeyPressedHandler, to: GCallback.self),
        keyBox,
        { data, _ in
            guard let data else { return }
            Unmanaged<GTKTextInputKeyControllerBox>.fromOpaque(data).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(widget, keyController)
}

private func gtkWireTextInputSubmit(
    widget: UnsafeMutablePointer<GtkWidget>,
    signalTarget: gpointer,
    submitAction: SubmitAction,
    keyPressActions: [KeyPressAction] = []
) {
    let submit = {
        gtkPerformSubmitAction(submitAction)
    }

    let activateBox = Unmanaged.passRetained(ClosureBox(submit)).toOpaque()
    g_signal_connect_data(
        signalTarget, "activate",
        unsafeBitCast(gtkTextInputSubmitActivateHandler, to: GCallback.self),
        activateBox,
        { data, _ in
            guard let data else { return }
            Unmanaged<ClosureBox>.fromOpaque(data).release()
        },
        GConnectFlags(rawValue: 0)
    )

    gtkInstallTextInputKeyController(
        on: widget,
        submitAction: submitAction,
        keyPressActions: keyPressActions
    )
}

let gtkSwiftInheritedTextInputForegroundMarker = "gtk-swift-inherited-text-input-foreground"
let gtkSwiftFontMonospacedMarker = "gtk-swift-font-monospaced"
let gtkSwiftFontRoundedMarker = "gtk-swift-font-rounded"
let gtkSwiftFontSerifMarker = "gtk-swift-font-serif"

private let gtkFontDescendantSelectors = [
    "entry",
    "entry text",
    "passwordentry",
    "passwordentry text",
    "textview",
    "textview text"
]

private func gtkApplyInheritedTextInputForegroundIfNeeded(to widget: UnsafeMutablePointer<GtkWidget>) {
    guard let foregroundColor = _gtkCurrentForegroundColor else { return }
    gtkApplyTextInputForeground(foregroundColor, to: widget)
}

private func gtkApplyTextInputForeground(_ color: Color, to widget: UnsafeMutablePointer<GtkWidget>) {
    let textCSS = "color: \(gtkCSSRGBA(color));"
    let disabledCSS = "color: \(gtkCSSRGBA(color.opacity(color.alpha * 0.45)));"
    applyCSSToWidget(
        widget,
        properties: textCSS,
        disabledProperties: disabledCSS,
        descendantSelectors: ["text"]
    )

    let placeholderColor = color.opacity(color.alpha * 0.62)
    applyCSSToWidget(
        widget,
        properties: "color: \(gtkCSSRGBA(placeholderColor));",
        descendantSelectors: ["placeholder", "text placeholder"]
    )
    gtk_widget_add_css_class(widget, gtkSwiftInheritedTextInputForegroundMarker)
}

private func gtkCSSRGBA(_ color: Color) -> String {
    let red = Int((color.red * 255).rounded())
    let green = Int((color.green * 255).rounded())
    let blue = Int((color.blue * 255).rounded())
    return "rgba(\(red), \(green), \(blue), \(color.alpha))"
}

private func gtkFontCSS(_ font: Font) -> (properties: String, designMarker: String?) {
    var declarations: [String] = []
    var designMarker: String?

    func appendWeight(_ weight: FontWeight) {
        declarations.append("font-weight: \(gtkFontWeightCSS(weight));")
    }

    func appendDesign(_ design: FontDesign) {
        guard let family = gtkFontFamilyCSS(design) else { return }
        declarations.append("font-family: \(family);")
        designMarker = gtkFontDesignMarker(design)
    }

    switch font {
    case .largeTitle:
        declarations.append("font-size: 28px;")
    case .title:
        declarations.append("font-size: 24px;")
    case .title2:
        declarations.append("font-size: 20px;")
        declarations.append("font-weight: bold;")
    case .title3:
        declarations.append("font-size: 18px;")
    case .headline:
        declarations.append("font-weight: bold;")
    case .subheadline:
        declarations.append("font-size: 12px;")
        declarations.append("font-weight: bold;")
    case .body:
        declarations.append("font-size: 14px;")
    case .callout:
        declarations.append("font-size: 12px;")
    case .footnote:
        declarations.append("font-size: 10px;")
    case .caption:
        declarations.append("font-size: 12px;")
    case .caption2:
        declarations.append("font-size: 10px;")
        declarations.append("font-weight: bold;")
    case .custom(let size, let weight, let design):
        declarations.append("font-size: \(gtkCSSFontSizePixels(forApplePointSize: size))px;")
        appendWeight(weight)
        appendDesign(design)
    }

    return (declarations.joined(separator: " "), designMarker)
}

private func gtkFontSizeCSS(_ size: Double) -> String {
    let rounded = size.rounded()
    if abs(size - rounded) < 0.001 {
        return "\(Int(rounded))"
    }
    return String(format: "%.2f", size)
}

private func gtkFontWeightCSS(_ weight: FontWeight) -> Int {
    switch weight {
    case .ultraLight: return 100
    case .thin: return 200
    case .light: return 300
    case .regular: return 400
    case .medium: return 500
    case .semibold: return 600
    case .bold: return 700
    case .heavy: return 800
    case .black: return 900
    }
}

private func gtkFontFamilyCSS(_ design: FontDesign) -> String? {
    switch design {
    case .default:
        return nil
    case .monospaced:
        return #""SF Mono", Menlo, Monaco, Consolas, "Liberation Mono", monospace"#
    case .rounded:
        return #""SF Pro Rounded", "Nunito", Cantarell, sans-serif"#
    case .serif:
        return #"Georgia, "Times New Roman", serif"#
    }
}

private func gtkFontDesignMarker(_ design: FontDesign) -> String? {
    switch design {
    case .default:
        return nil
    case .monospaced:
        return gtkSwiftFontMonospacedMarker
    case .rounded:
        return gtkSwiftFontRoundedMarker
    case .serif:
        return gtkSwiftFontSerifMarker
    }
}

// MARK: - GTK rendering protocol

/// Protocol that views implement (via extensions) to provide GTK widget creation.
/// Backend code extends each SwiftOpenUI view type to conform.
/// @MainActor: View is whole-protocol main-actor isolated (Apple shape), so
/// conforming view types are isolated and their witnesses must match the
/// requirement's isolation; widget creation always runs on the GTK main
/// loop == main thread.
@MainActor
public protocol GTKRenderable {
    func gtkCreateWidget() -> OpaquePointer
}

/// Protocol for views that provide multiple GTK child widgets.
/// @MainActor: same reasoning as GTKRenderable.
@MainActor
public protocol GTKMultiChildRenderable {
    func gtkRenderChildren() -> [OpaquePointer]
}

// MARK: - Stateful view identity

private var gtkStateCache: [String: [AnyStateStorage]] = [:]
private var gtkStateTypeCounters: [String: [String: Int]] = [:]

private var gtkForcedStateIdentityNamespace: String?

private func gtkStateIdentityNamespace() -> String {
    gtkForcedStateIdentityNamespace
        ?? GTKViewHost.getCurrentRebuilding()?.stateIdentityNamespace
        ?? "root"
}

public func gtkBeginStateIdentityPass() {
    gtkStateTypeCounters[gtkStateIdentityNamespace()] = [:]
    gtkMountTypeCounters[gtkStateIdentityNamespace()] = [:]
}

// MARK: - Mount identity for external renderable leaves

// Renderable LEAF views (GTKRenderable) skip state install, so a leaf that
// owns long-lived native state (e.g. the SwiftUI shim's NSViewRepresentable
// host, which owns a Coordinator + NSView + GtkDrawingArea) needs its own
// stable identity across rebuilds to reuse that state instead of remounting
// per re-render. Same scheme as gtkStateCacheKey: enclosing stateful-view
// namespace + leaf type + per-pass occurrence index. The pass-begin reset is
// public so offscreen render entry points (ImageRenderer parity) can open a
// fresh identity pass per render.
private var gtkMountTypeCounters: [String: [String: Int]] = [:]

public func gtkMountIdentity(for type: Any.Type) -> String {
    let namespace = gtkStateIdentityNamespace()
    let typeName = String(reflecting: type)
    var counters = gtkMountTypeCounters[namespace] ?? [:]
    let index = counters[typeName] ?? 0
    counters[typeName] = index + 1
    gtkMountTypeCounters[namespace] = counters
    return "\(namespace)|mount|\(typeName)#\(index)"
}

/// Claims a stable child namespace slot in the current namespace. Deferred
/// render paths (GeometryReader map/idle/tick callbacks) run with no
/// rebuilding host; without a captured namespace their whole subtree keys
/// on the shared never-reset "root" pool, so every @State below them is
/// reborn on each deferred render (observed: the sidebar's sheet flags
/// resetting ~1s after presentation).
func gtkClaimStateIdentityNamespace(_ kind: String) -> String {
    let namespace = gtkStateIdentityNamespace()
    let marker = "<\(kind)>"
    var counters = gtkStateTypeCounters[namespace] ?? [:]
    let index = counters[marker] ?? 0
    counters[marker] = index + 1
    gtkStateTypeCounters[namespace] = counters
    return "\(namespace)::\(marker)#\(index)"
}

private func gtkForEachStateIdentityComponent<ID: Hashable>(for id: ID) -> String {
    "ForEach[\(String(reflecting: AnyHashable(id)))]"
}

private func gtkWithStateIdentityNamespaceComponent<T>(_ component: String, _ body: () -> T) -> T {
    let previous = gtkForcedStateIdentityNamespace
    let namespace = "\(gtkStateIdentityNamespace())::\(component)"
    gtkForcedStateIdentityNamespace = namespace
    gtkStateTypeCounters[namespace] = [:]
    gtkMountTypeCounters[namespace] = [:]
    defer { gtkForcedStateIdentityNamespace = previous }
    return body()
}

/// Runs a deferred render under a captured namespace, starting a fresh
/// counter pass for it so keys inside the subtree are stable per render.
func gtkWithForcedStateIdentityNamespace<T>(_ namespace: String, _ body: () -> T) -> T {
    let previous = gtkForcedStateIdentityNamespace
    gtkForcedStateIdentityNamespace = namespace
    gtkStateTypeCounters[namespace] = [:]
    gtkMountTypeCounters[namespace] = [:]
    defer { gtkForcedStateIdentityNamespace = previous }
    return body()
}

private func gtkNextStateIdentityKey<V>(for view: V) -> String {
    let namespace = gtkStateIdentityNamespace()
    let typeName = String(reflecting: type(of: view))
    var counters = gtkStateTypeCounters[namespace] ?? [:]
    let index = counters[typeName] ?? 0
    counters[typeName] = index + 1
    gtkStateTypeCounters[namespace] = counters
    return "\(namespace)::\(typeName)#\(index)"
}

private func gtkStateCacheKey<V>(for view: V) -> String {
    gtkNextStateIdentityKey(for: view)
}

private func gtkRestoreAndInstallState<V>(_ view: V, host: GTKViewHost) {
    // EVERY composite view consumes a key slot and namespaces its children,
    // including stateless wrappers. If stateless hosts kept the shared parent
    // namespace, all stateful views under different wrappers would draw from
    // one counter pool, and conditional content (an open sheet, a banner)
    // would shift sibling indices between passes — alternating cache
    // lineages and silently dropping interim @State writes.
    let key = gtkStateCacheKey(for: view)
    host.stateIdentityNamespace = key
    let mirror = Mirror(reflecting: view)
    let providers = mirror.children.compactMap { $0.value as? AnyStateStorageProvider }
    guard !providers.isEmpty else { return }

    gtkDebugLog("state install type=\(String(reflecting: type(of: view))) key=\(key) providers=\(providers.count) cached=\(gtkStateCache[key] != nil)")
    if let cached = gtkStateCache[key], cached.count == providers.count {
        for (provider, old) in zip(providers, cached) {
            provider.anyStorage.restoreValue(from: old)
            old.forwardMutations(to: provider.anyStorage)
        }
    }

    for provider in providers {
        provider.anyStorage.host = host
    }
    gtkStateCache[key] = providers.map { $0.anyStorage }
}

private func gtkRestoreAndInstallInlineState<V>(_ view: V, host: AnyViewHost?) -> String {
    let key = gtkStateCacheKey(for: view)
    let mirror = Mirror(reflecting: view)
    let providers = mirror.children.compactMap { $0.value as? AnyStateStorageProvider }

    if !providers.isEmpty {
        gtkDebugLog("inline state install type=\(String(reflecting: type(of: view))) key=\(key) providers=\(providers.count) cached=\(gtkStateCache[key] != nil)")
        if let cached = gtkStateCache[key], cached.count == providers.count {
            for (provider, old) in zip(providers, cached) {
                provider.anyStorage.restoreValue(from: old)
                old.forwardMutations(to: provider.anyStorage)
            }
        }
        gtkStateCache[key] = providers.map { $0.anyStorage }
    }

    if let host {
        installState(view, host: host)
    }

    return key
}

private struct GTKStateNamespaceView<Content: View>: View {
    typealias Body = Never

    let component: String
    let content: Content

    var body: Never { fatalError("GTKStateNamespaceView is a primitive view") }
}

private protocol GTKStateNamespaceActionProvider {
    var gtkStateNamespaceComponent: String { get }
    var gtkStateNamespaceContent: any View { get }
}

extension GTKStateNamespaceView: GTKStateNamespaceActionProvider {
    fileprivate var gtkStateNamespaceComponent: String { component }
    fileprivate var gtkStateNamespaceContent: any View { content }
}

private protocol GTKBackgroundActionProvider {
    var gtkPrimaryActionBackground: any View { get }
    var gtkPrimaryActionContent: any View { get }
}

extension BackgroundView: GTKBackgroundActionProvider {
    fileprivate var gtkPrimaryActionBackground: any View { background }
    fileprivate var gtkPrimaryActionContent: any View { content }
}

private protocol GTKOverlayActionProvider {
    var gtkPrimaryActionContent: any View { get }
    var gtkPrimaryActionOverlay: any View { get }
}

extension OverlayView: GTKOverlayActionProvider {
    fileprivate var gtkPrimaryActionContent: any View { content }
    fileprivate var gtkPrimaryActionOverlay: any View { overlay }
}

extension GTKStateNamespaceView: GTKRenderable, GTKDescribable {
    func gtkCreateWidget() -> OpaquePointer {
        gtkWithStateIdentityNamespaceComponent(component) {
            gtkRenderView(content)
        }
    }

    func gtkDescribeNode() -> GTK4DescriptorNode {
        gtkWithStateIdentityNamespaceComponent(component) {
            GTK4DescriptorNode(
                kind: .composite,
                typeName: "GTKStateNamespaceView<\(component)>",
                children: [gtkDescribeView(content)]
            )
        }
    }
}

// MARK: - Rendering dispatch

/// Render any SwiftOpenUI View into a GTK widget pointer.
public func gtkRenderView<V: View>(_ view: V) -> OpaquePointer {
    // Primitive views with known GTK rendering. gtkCreateWidget is @MainActor
    // (GTKRenderable); the renderer runs on the GTK main loop == main thread.
    if let renderable = view as? GTKRenderable {
        return gtkAssumeMainActorIsolated { renderable.gtkCreateWidget() }
    }

    // Transparent multi-child views (ViewList, TupleView, Group, ForEach, etc.)
    // render their children directly. Layout containers that also expose
    // children for introspection (HStack/VStack/ZStack/GridRow) must keep their
    // own renderer; flattening them changes their layout semantics.
    // into a vertical box.  This must come before the reactive/body checks
    // because these types have Body = Never.
    if let multi = view as? any TransparentMultiChildView {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        var needsHExpand = false
        var needsVExpand = false
        var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []
        for child in multi.children.flatMap({ gtkLayoutChildViews(from: $0) }) {
            let widget = widgetFromOpaque(gtkRenderAnyView(child))
            if gtkIsEmptyViewWidget(widget) { continue }
            renderedChildren.append(widget)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
        if gtk_widget_get_vexpand(widget) != 0 {
            needsVExpand = true
            gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
        }
        gtk_box_append(boxPointer(box), widget)
        }
        if renderedChildren.isEmpty {
            return opaqueFromWidget(gtkCreateEmptyViewWidget())
        }
        gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
        if needsVExpand { gtk_widget_set_vexpand(box, 1) }
        return opaqueFromWidget(box)
    }

    if Swift.type(of: view) is any PrimitiveView.Type {
        gtkDebugLog("unsupported primitive view rendered as EmptyView: \(String(reflecting: V.self))")
        return opaqueFromWidget(gtkCreateEmptyViewWidget())
    }

    // Composite view with reactive state — wrap in GTKViewHost
    if hasReactiveProperties(view) {
        return gtkRenderStatefulView(view)
    }

    // Stateless composite view — recurse through body under its own namespace.
    // Stateful descendants must keep the same structural key whether their
    // ancestors are rendered from a fresh existential path (e.g. TabView pages)
    // or from a ViewHost rebuild.
    let namespace = gtkNextStateIdentityKey(for: view)
    return gtkWithForcedStateIdentityNamespace(namespace) {
        return gtkAssumeMainActorIsolated { gtkRenderView(view.body) }
    }
}

/// Render children from a view.
public func gtkRenderChildren<V: View>(_ view: V) -> [OpaquePointer] {
    if let multi = view as? GTKMultiChildRenderable {
        return gtkAssumeMainActorIsolated { multi.gtkRenderChildren() }
    }
    if let keyedRows = view as? GTKKeyedListRowProducer {
        return keyedRows.gtkKeyedListRows(depth: 0).flatMap { child in
            func render<C: View>(_ c: C) -> OpaquePointer { gtkRenderView(c) }
            return gtkLayoutChildViews(from: child).map { render($0) }
        }
    }
    if let multi = view as? any TransparentMultiChildView {
        return multi.children.flatMap { child in
            func render<C: View>(_ c: C) -> OpaquePointer { gtkRenderView(c) }
            return gtkLayoutChildViews(from: child).map { render($0) }
        }
    }
    return gtkLayoutChildViews(from: view).map { gtkRenderAnyView($0) }
}

/// Render an existential (any View).
public func gtkRenderAnyView(_ view: any View) -> OpaquePointer {
    func render<V: View>(_ v: V) -> OpaquePointer { gtkRenderView(v) }
    return render(view)
}

private struct GTKLayoutMeasureContext: LayoutMeasureContext {
    let widgets: [UnsafeMutablePointer<GtkWidget>]

    func measure(_ subview: LayoutSubview, proposal: ProposedViewSize) -> LayoutMeasurement {
        let widget = widgets[subview.index]
        let widthProposal: gint = if let width = proposal.width, width.isFinite {
            gtkPixelSize(width)
        } else {
            -1
        }
        let heightProposal: gint = if let height = proposal.height, height.isFinite {
            gtkPixelSize(height)
        } else {
            -1
        }
        var widthMin: gint = 0
        var widthNat: gint = 0
        var heightMin: gint = 0
        var heightNat: gint = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, heightProposal, &widthMin, &widthNat, nil, nil)
        gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, widthProposal, &heightMin, &heightNat, nil, nil)
        return LayoutMeasurement(
            size: ViewSize(width: Double(max(widthMin, widthNat)), height: Double(max(heightMin, heightNat))),
            expandsToFillWidth: gtk_widget_get_hexpand(widget) != 0,
            expandsToFillHeight: gtk_widget_get_vexpand(widget) != 0
        )
    }
}

private func gtkMeasureLayoutSubviews(
    _ widgets: [UnsafeMutablePointer<GtkWidget>]
) -> [LayoutMeasurement] {
    let context = GTKLayoutMeasureContext(widgets: widgets)
    return widgets.indices.map { index in
        context.measure(LayoutSubview(index: index), proposal: .unspecified)
    }
}

// MARK: - Deferred callback environment binding

/// Capture the current environment at registration time and restore it around
/// a deferred callback that may read `@Environment(...)`.  See
/// `docs/architecture/deferred-callback-environment-binding.md`.
func bindActionToCurrentEnvironment(_ action: @escaping () -> Void) -> () -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUICurrentPresentationDismissAction()
    return {
        gtkFlushPendingTextBindingUpdate()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(capturedEnvironment)
        defer { setCurrentEnvironment(previousEnvironment) }
        if let capturedPresentationDismissAction {
            swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                action()
            }
        } else {
            action()
        }
    }
}

func bindActionToCurrentEnvironment<T>(_ action: @escaping (T) -> Void) -> (T) -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUICurrentPresentationDismissAction()
    return { value in
        gtkFlushPendingTextBindingUpdate()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(capturedEnvironment)
        defer { setCurrentEnvironment(previousEnvironment) }
        if let capturedPresentationDismissAction {
            swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                action(value)
            }
        } else {
            action(value)
        }
    }
}

private final class GTKEnvironmentCapture: @unchecked Sendable {
    let environment: EnvironmentValues

    init(_ environment: EnvironmentValues) {
        self.environment = environment
    }
}

func bindTaskActionToCurrentEnvironment(
    _ action: @escaping @Sendable () async -> Void
) -> @Sendable () async -> Void {
    let capturedEnvironment = GTKEnvironmentCapture(getCurrentEnvironment())
    return {
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(capturedEnvironment.environment)
        defer { setCurrentEnvironment(previousEnvironment) }
        await action()
    }
}

private func gtkDisplayTextContent(_ text: String) -> String {
    // U+2E31 is a valid word-separator middle dot used by some SwiftUI apps,
    // but common Linux GTK font stacks render it as tofu. U+00B7 preserves the
    // visual intent and is broadly available.
    text.replacingOccurrences(of: "\u{2E31}", with: "\u{00B7}")
}

private func gtkPangoMarkup(for text: String, foregroundColor: Color? = nil) -> String {
    let displayText = gtkDisplayTextContent(text)
    func span(_ markup: String, color: Color?) -> String {
        guard let color else { return markup }
        return "<span foreground=\"\(gtkPangoColorHex(color))\">\(markup)</span>"
    }

    guard QuillInlineImageText.containsMarker(displayText) else {
        return span(gtkEscapeMarkup(displayText), color: foregroundColor)
    }

    return QuillInlineImageText.parse(displayText).map { segment in
        switch segment {
        case .text(let text):
            return span(gtkEscapeMarkup(text), color: foregroundColor)
        case .image(let token):
            guard let materialName = gtkMaterialNameForInlineImage(token) else {
                return ""
            }
            let familyName = gtkEscapeMarkup(MaterialSymbolsRoundedFamilyName)
            let escapedName = gtkEscapeMarkup(materialName)
            return span(
                "<span font_family=\"\(familyName)\">\(escapedName)</span>",
                color: foregroundColor
            )
        }
    }.joined()
}

private func gtkMaterialNameForInlineImage(_ token: QuillInlineImageText.Token) -> String? {
    switch token.kind {
    case .systemName:
        return gtkMaterialNameForSystemImage(token.name)
    case .material:
        return token.name
    case .filePath:
        return nil
    }
}

// MARK: - View GTK extensions

extension Text: GTKRenderable, GTKDescribable {
    public func gtkCreateWidget() -> OpaquePointer {
        let displayContent = gtkDisplayTextContent(content)
        let label = gtk_label_new(displayContent)!
        let inheritedForeground = gtkCurrentForegroundColorIfSet()
        if hasStyledRuns || QuillInlineImageText.containsMarker(content) || inheritedForeground != nil {
            gtk_swift_label_set_markup(label, pangoMarkup(defaultColor: inheritedForeground))
        }
        gtkPrepareRowTextLabel(label, text: displayContent)
        gtk_swift_label_set_xalign(label, 0)
        gtk_swift_label_set_yalign(label, 0.5)
        // SwiftUI Text wraps to intrinsic size — prevent GTK expansion.
        gtk_widget_set_hexpand(label, 0)
        gtk_widget_set_vexpand(label, 0)
        gtkMarkHostedNodeKind(label, kind: .text)
        return opaqueFromWidget(label)
    }

    /// Pango markup for styled runs: each colored run becomes a
    /// `<span foreground='#RRGGBB'>…</span>`; plain runs pass through escaped.
    private func pangoMarkup(defaultColor: Color? = nil) -> String {
        runs.map { run in
            let color = run.color ?? defaultColor
            return gtkPangoMarkup(for: run.text, foregroundColor: color)
        }.joined()
    }

    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(kind: .text, typeName: "Text",
                           props: .text(GTK4TextDescriptor(content: content)))
    }
}

extension EmptyView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        opaqueFromWidget(gtkCreateEmptyViewWidget())
    }
}

extension Spacer: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(kind: .spacer, typeName: "Spacer")
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let label = gtk_label_new(nil)!
        let gobject = UnsafeMutableRawPointer(label).assumingMemoryBound(to: GObject.self)
        g_object_set_data(gobject, gtkSwiftSpacerMarker, UnsafeMutableRawPointer(bitPattern: 1))
        return opaqueFromWidget(label)
    }
}

extension Divider: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(kind: .divider, typeName: "Divider")
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)!
        gtk_widget_set_hexpand(sep, 1)
        let gobject = UnsafeMutableRawPointer(sep).assumingMemoryBound(to: GObject.self)
        g_object_set_data(gobject, gtkSwiftDividerMarker, UnsafeMutableRawPointer(bitPattern: 1))
        return opaqueFromWidget(sep)
    }
}

private final class GTKMultilineTextFieldBindingBox {
    let binding: Binding<String>
    let placeholderLabel: UnsafeMutablePointer<GtkWidget>?

    init(
        binding: Binding<String>,
        placeholderLabel: UnsafeMutablePointer<GtkWidget>?
    ) {
        self.binding = binding
        self.placeholderLabel = placeholderLabel
    }

    func apply(_ newText: String) {
        gtkScheduleTextBindingUpdate(binding, value: newText)
        updatePlaceholderVisibility(text: newText)
    }

    func updatePlaceholderVisibility(text: String) {
        guard let placeholderLabel else { return }
        gtk_widget_set_visible(placeholderLabel, text.isEmpty ? 1 : 0)
    }
}

private final class GTKTextInputFocusTarget {
    let widget: UnsafeMutablePointer<GtkWidget>

    init(widget: UnsafeMutablePointer<GtkWidget>) {
        self.widget = widget
        g_object_ref(gpointer(widget))
    }

    deinit {
        g_object_unref(gpointer(widget))
    }
}

private func gtkFocusTextInputWidget(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    gtk_widget_set_can_target(widget, 1)
    gtk_widget_set_can_focus(widget, 1)
    gtk_widget_set_focusable(widget, 1)
    _ = gtk_swift_root_grab_focus(widget)
    gtkScheduleTextInputFocus(widget)
}

private func gtkScheduleTextInputFocus(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    let target = GTKTextInputFocusTarget(widget: widget)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let target = Unmanaged<GTKTextInputFocusTarget>.fromOpaque(userData).takeRetainedValue()
        guard gtk_swift_is_widget(target.widget) != 0 else { return 0 }
        gtk_widget_set_can_target(target.widget, 1)
        gtk_widget_set_can_focus(target.widget, 1)
        gtk_widget_set_focusable(target.widget, 1)
        _ = gtk_swift_root_grab_focus(target.widget)
        return 0
    }, Unmanaged.passRetained(target).toOpaque())
}

private func gtkInstallTextInputFocusGesture(
    on widget: UnsafeMutablePointer<GtkWidget>,
    target: UnsafeMutablePointer<GtkWidget>
) {
    let gesture = gtk_gesture_click_new()!
    let targetBox = Unmanaged.passRetained(GTKTextInputFocusTarget(widget: target)).toOpaque()
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, _: Double, _: Double, userData: gpointer?) in
            guard let userData else { return }
            let target = Unmanaged<GTKTextInputFocusTarget>.fromOpaque(userData).takeUnretainedValue()
            gtkFocusTextInputWidget(target.widget)
        } as @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void, to: GCallback.self),
        targetBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<GTKTextInputFocusTarget>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(widget, gesture)
}

private func gtkTextBufferString(_ buffer: UnsafeMutablePointer<GtkTextBuffer>) -> String {
    var start = GtkTextIter()
    var end = GtkTextIter()
    gtk_text_buffer_get_bounds(buffer, &start, &end)
    let cStr = gtk_text_buffer_get_text(buffer, &start, &end, 0)!
    let result = String(cString: cStr)
    g_free(gpointer(mutating: cStr))
    return result
}

private let gtkPlainMultilineTextInputCSS = """
    background: transparent;
    background-color: transparent;
    background-image: none;
    border: none;
    outline: none;
    box-shadow: none;
    padding: 0;
    min-width: 0;
    min-height: 0;
    """

private let gtkPlainMultilineScrolledDescendants = [
    "viewport",
    "textview",
    "textview text",
    "viewport textview",
    "viewport textview text",
    "text"
]

private func gtkApplyPlainMultilineTextFieldChrome(
    scrolledWindow: UnsafeMutablePointer<GtkWidget>,
    textView: UnsafeMutablePointer<GtkWidget>
) {
    applyCSSToWidget(
        scrolledWindow,
        properties: gtkPlainMultilineTextInputCSS,
        descendantSelectors: gtkPlainMultilineScrolledDescendants
    )
    applyCSSToWidget(
        textView,
        properties: gtkPlainMultilineTextInputCSS,
        descendantSelectors: ["text"]
    )
}

private func gtkCreateMultilineTextField(
    title: String,
    text: Binding<String>
) -> OpaquePointer {
    let textView = gtk_text_view_new()!
    let textViewPtr = UnsafeMutableRawPointer(textView).assumingMemoryBound(to: GtkTextView.self)
    gtk_text_view_set_wrap_mode(textViewPtr, GTK_WRAP_WORD_CHAR)
    gtk_text_view_set_accepts_tab(textViewPtr, 0)
    let environment = getCurrentEnvironment()
    let textFieldStyleType = environment.textFieldStyle

    let current = text.wrappedValue
    let buffer = gtk_text_view_get_buffer(textViewPtr)!
    if !current.isEmpty {
        gtk_text_buffer_set_text(buffer, current, gint(current.utf8.count))
    }

    let placeholderLabel: UnsafeMutablePointer<GtkWidget>? = title.isEmpty ? nil : gtk_label_new(title)
    if let placeholderLabel {
        let labelPtr = OpaquePointer(placeholderLabel)
        gtk_label_set_xalign(labelPtr, 0)
        gtk_widget_set_halign(placeholderLabel, GTK_ALIGN_START)
        gtk_widget_set_valign(placeholderLabel, GTK_ALIGN_START)
        gtk_widget_set_margin_start(placeholderLabel, textFieldStyleType == .plain ? 0 : 6)
        gtk_widget_set_margin_top(placeholderLabel, textFieldStyleType == .plain ? 0 : 8)
        gtk_widget_set_opacity(placeholderLabel, 0.45)
        gtk_widget_set_can_target(placeholderLabel, 0)
        gtk_widget_set_visible(placeholderLabel, current.isEmpty ? 1 : 0)
    }

    let box = Unmanaged.passRetained(GTKMultilineTextFieldBindingBox(
        binding: text,
        placeholderLabel: placeholderLabel
    )).toOpaque()
    g_signal_connect_data(
        gpointer(buffer),
        "changed",
        unsafeBitCast({ (bufferPtr: gpointer?, userData: gpointer?) in
            let box = Unmanaged<GTKMultilineTextFieldBindingBox>.fromOpaque(userData!).takeUnretainedValue()
            let buf = UnsafeMutableRawPointer(bufferPtr!).assumingMemoryBound(to: GtkTextBuffer.self)
            box.apply(gtkTextBufferString(buf))
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        box,
        { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
            Unmanaged<GTKMultilineTextFieldBindingBox>.fromOpaque(userData!).release()
        },
        GConnectFlags(rawValue: 0)
    )

    gtkInstallTextInputKeyController(
        on: textView,
        submitAction: environment.submitAction,
        keyPressActions: environment.keyPressActions
    )

    let scrolled = gtk_scrolled_window_new()!
    gtk_scrolled_window_set_policy(OpaquePointer(scrolled), GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
    gtk_scrolled_window_set_child(OpaquePointer(scrolled), textView)
    gtk_widget_set_hexpand(scrolled, 1)
    gtk_widget_set_vexpand(scrolled, 0)

    gtkApplyEnabledState(to: textView)
    let rendered: OpaquePointer
    var useQuillPaintTextEditor = false
    switch textFieldStyleType {
    case .plain:
        gtkApplyPlainMultilineTextFieldChrome(scrolledWindow: scrolled, textView: textView)
    case .automatic, .roundedBorder:
        useQuillPaintTextEditor = true
    }

    if useQuillPaintTextEditor,
       let paintedEditor = quill_gtk_text_editor_paint_hook?(
        OpaquePointer(scrolled),
        OpaquePointer(textView)
    ) {
        gtkApplyInheritedTextInputForegroundIfNeeded(to: textView)
        rendered = paintedEditor
    } else {
        gtkApplyInheritedTextInputForegroundIfNeeded(to: textView)
        rendered = opaqueFromWidget(scrolled)
    }

    guard let placeholderLabel else {
        return rendered
    }

    let overlay = gtk_overlay_new()!
    gtk_widget_set_can_focus(overlay, 0)
    gtk_widget_set_focusable(overlay, 0)
    gtk_widget_set_can_target(overlay, 1)
    let renderedWidget = widgetFromOpaque(rendered)
    gtk_widget_set_hexpand(overlay, gtk_widget_get_hexpand(renderedWidget))
    gtk_widget_set_vexpand(overlay, gtk_widget_get_vexpand(renderedWidget))
    gtk_widget_set_halign(overlay, GTK_ALIGN_FILL)
    gtk_widget_set_valign(overlay, GTK_ALIGN_FILL)
    gtk_overlay_set_child(OpaquePointer(overlay), renderedWidget)
    gtk_overlay_add_overlay(OpaquePointer(overlay), placeholderLabel)
    gtkInstallTextInputFocusGesture(on: overlay, target: textView)
    gtkInstallTextInputFocusGesture(on: renderedWidget, target: textView)
    return opaqueFromWidget(overlay)
}

extension TextField: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let content = gtkTextInputFocusDescriptorContent(
            typeName: "TextField",
            binding: text,
            label: title
        )
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "TextField",
            props: .text(GTK4TextDescriptor(content: "\(content)|axis:\(axis.rawValue)"))
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        if axis.contains(.vertical) {
            return gtkCreateMultilineTextField(title: title, text: text)
        }

        let entry = gtk_entry_new()!
        gtk_widget_set_hexpand(entry, 1)
        let entryPtr = UnsafeMutableRawPointer(entry).assumingMemoryBound(to: GtkEntry.self)
        let bufferPtr = gtk_entry_get_buffer(entryPtr)
        gtk_entry_buffer_set_text(bufferPtr, text.wrappedValue, -1)
        if !title.isEmpty {
            gtk_entry_set_placeholder_text(entryPtr, title)
        }

        // Wire text changes back through Binding<String>.
        // Listen on the GtkEntryBuffer's "notify::text" signal so we catch
        // all changes (typing, paste, programmatic).
        let binding = text
        let box = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()

        g_signal_connect_data(
            gpointer(bufferPtr),
            "notify::text",
            unsafeBitCast({ (buffer: gpointer?, _: gpointer?, userData: gpointer?) in
                let box = Unmanaged<StringClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let bufPtr = UnsafeMutableRawPointer(buffer!).assumingMemoryBound(to: GtkEntryBuffer.self)
                let cStr = gtk_entry_buffer_get_text(bufPtr)!
                let text = String(cString: cStr)
                box.closure(text)
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<StringClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        // GtkEntry also emits "changed" as a GtkEditable; keep this in sync with
        // SecureField so user edits always reach SwiftUI bindings before dismissal.
        let changedBox = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(entry),
            "changed",
            unsafeBitCast({ (editable: gpointer?, userData: gpointer?) in
                let box = Unmanaged<StringClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let cStr = gtk_editable_get_text(OpaquePointer(editable))!
                box.closure(String(cString: cStr))
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            changedBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<StringClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        // Apply text field style from environment
        let textFieldStyleType = getCurrentEnvironment().textFieldStyle
        var useQuillPaintTextField = false
        switch textFieldStyleType {
        case .plain:
            applyCSSToWidget(entry, properties: "background: transparent; background-color: transparent; border: none; outline: none; box-shadow: none; padding: 0;")
        case .automatic, .roundedBorder:
            useQuillPaintTextField = true
        }

        // Wire keyboard actions: GtkEntry fires "activate" on Enter key.
        let environment = getCurrentEnvironment()
        if let submitAction = environment.submitAction {
            gtkWireTextInputSubmit(
                widget: entry,
                signalTarget: gpointer(entry),
                submitAction: submitAction,
                keyPressActions: environment.keyPressActions
            )
        } else {
            gtkInstallTextInputKeyController(
                on: entry,
                submitAction: nil,
                keyPressActions: environment.keyPressActions
            )
        }

        gtkApplyEnabledState(to: entry)
        if useQuillPaintTextField,
           let paintedEntry = quill_gtk_text_field_paint_hook?(
               OpaquePointer(entry),
               textFieldStyleType == .roundedBorder
           ) {
            gtkApplyInheritedTextInputForegroundIfNeeded(to: entry)
            return paintedEntry
        }
        gtkApplyInheritedTextInputForegroundIfNeeded(to: entry)
        return opaqueFromWidget(entry)
    }
}

extension FocusedView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "FocusedView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_focusable(widget, 1)

        let state = focusState
        let controller = gtk_event_controller_focus_new()!

        // Focus-in: set @FocusState to true
        let enterBox = Unmanaged.passRetained(ClosureBox {
            if !state.wrappedValue { state.storage.setValue(true) }
        }).toOpaque()
        g_signal_connect_data(
            gpointer(controller), "enter",
            unsafeBitCast({ (_: gpointer?, ud: gpointer?) in
                Unmanaged<ClosureBox>.fromOpaque(ud!).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            enterBox,
            { (ud: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<ClosureBox>.fromOpaque(ud!).release()
            }, GConnectFlags(rawValue: 0))

        // Focus-out: set @FocusState to false
        let leaveBox = Unmanaged.passRetained(ClosureBox {
            if state.wrappedValue { state.storage.setValue(false) }
        }).toOpaque()
        g_signal_connect_data(
            gpointer(controller), "leave",
            unsafeBitCast({ (_: gpointer?, ud: gpointer?) in
                Unmanaged<ClosureBox>.fromOpaque(ud!).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            leaveBox,
            { (ud: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<ClosureBox>.fromOpaque(ud!).release()
            }, GConnectFlags(rawValue: 0))

        // Register programmatic focus handler: when user code sets
        // @FocusState = true, grab GTK focus on this widget.
        // No g_object_ref — check liveness before use to avoid leaking widgets.
        state.storage.onProgrammaticFocusChange = { [weak storage = state.storage] newValue in
            guard storage != nil else { return }
            guard gtk_swift_is_widget(widget) != 0 else { return }
            if newValue == true {
                gtk_swift_grab_focus(widget)
            } else {
                gtk_swift_clear_focus(widget)
            }
        }

        gtk_widget_add_controller(widget, controller)
        return opaqueFromWidget(widget)
    }
}

extension FocusedEqualsView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "FocusedEqualsView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_focusable(widget, 1)

        let state = focusState
        let matchValue = value
        let controller = gtk_event_controller_focus_new()!

        // Focus-in: set @FocusState to this value
        let enterBox = Unmanaged.passRetained(ClosureBox {
            state.storage.setValue(matchValue)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(controller), "enter",
            unsafeBitCast({ (_: gpointer?, ud: gpointer?) in
                Unmanaged<ClosureBox>.fromOpaque(ud!).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            enterBox,
            { (ud: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<ClosureBox>.fromOpaque(ud!).release()
            }, GConnectFlags(rawValue: 0))

        // Focus-out: clear @FocusState to nil if still this value
        let leaveBox = Unmanaged.passRetained(ClosureBox {
            if state.storage.value == matchValue { state.storage.setValue(nil) }
        }).toOpaque()
        g_signal_connect_data(
            gpointer(controller), "leave",
            unsafeBitCast({ (_: gpointer?, ud: gpointer?) in
                Unmanaged<ClosureBox>.fromOpaque(ud!).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            leaveBox,
            { (ud: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<ClosureBox>.fromOpaque(ud!).release()
            }, GConnectFlags(rawValue: 0))

        // Register programmatic focus handler: when user code sets
        // @FocusState to this value, grab GTK focus on this widget.
        // No g_object_ref — check liveness before use to avoid leaking widgets.
        let prevHandler = state.storage.onProgrammaticFocusChange
        state.storage.onProgrammaticFocusChange = { newValue in
            if newValue == matchValue {
                guard gtk_swift_is_widget(widget) != 0 else { return }
                gtk_swift_grab_focus(widget)
            } else if newValue == nil {
                if gtk_swift_is_widget(widget) != 0 {
                    gtk_swift_clear_focus(widget)
                }
            } else {
                prevHandler?(newValue)
            }
        }

        gtk_widget_add_controller(widget, controller)
        return opaqueFromWidget(widget)
    }
}

extension Color: GTKRenderable, GTKDescribable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
        gtkMarkVerticalFillIntent(box)
        let css = String(format: "background-color: rgba(%d, %d, %d, %.3f);",
                         Int(red * 255), Int(green * 255), Int(blue * 255), alpha)
        applyCSSToWidget(box, properties: css)
        gtkMarkHostedNodeKind(box, kind: .color)
        return opaqueFromWidget(box)
    }

    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(kind: .color, typeName: "Color",
                           props: .color(gtkColorDescriptor(self)))
    }
}

private func gtkDisableButtonChildTargeting(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    gtk_widget_set_can_target(widget, 0)
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        gtkDisableButtonChildTargeting(c)
        child = gtk_widget_get_next_sibling(c)
    }
}

private let gtkSwiftMenuOwnerButtonKey = "gtk-swift-menu-owner-button"

private func gtkMarkMenuOwner(
    under widget: UnsafeMutablePointer<GtkWidget>,
    menuButton: UnsafeMutablePointer<GtkWidget>,
    depth: Int = 0
) {
    guard depth < 160, gtk_swift_is_widget(widget) != 0 else { return }
    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data(object, gtkSwiftMenuOwnerButtonKey, gpointer(menuButton))

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkMarkMenuOwner(under: current, menuButton: menuButton, depth: depth + 1)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkMenuOwnerButton(
    for widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget>? {
    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let raw = g_object_get_data(object, gtkSwiftMenuOwnerButtonKey) else {
        return nil
    }
    let owner = raw.assumingMemoryBound(to: GtkWidget.self)
    guard gtk_swift_is_widget(owner) != 0 else { return nil }
    return owner
}

private func gtkDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else {
        return
    }
    if let data = ("[QuillUI GTK] " + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private func gtkDebugGeometryLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_GEOMETRY"] == "1" else {
        return
    }
    if let data = ("[QuillUI GTK Geometry] " + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

/// Decides whether a button-activation signal may fire the action.
///
/// One physical click reaches the action box through several redundant
/// paths: the click gesture, the legacy capture controller, and the
/// root-event fallback all fire on pointer PRESS, while GtkButton's
/// `clicked` signal fires on RELEASE. Wall-clock dedup alone is
/// load-sensitive: on a busy runner the press→release gap can exceed any
/// reasonable window, so a single click fired the action twice (#502).
/// A pointer press therefore arms the gate and the following `clicked`
/// consumes it — suppressed regardless of elapsed time — while keyboard
/// activation (a `clicked` with no preceding pointer press) still fires.
/// The wall-clock window keeps deduplicating the press-side paths, which
/// always dispatch within one main-loop iteration of each other.
struct GTKButtonActivationGate {
    enum Phase {
        case pointerPress
        case clicked
    }

    private var lastActivationTime: TimeInterval = -.infinity
    private var pointerPressAwaitingClicked = false

    mutating func shouldFire(_ phase: Phase, now: TimeInterval) -> Bool {
        switch phase {
        case .pointerPress:
            pointerPressAwaitingClicked = true
        case .clicked:
            if pointerPressAwaitingClicked {
                pointerPressAwaitingClicked = false
                return false
            }
        }
        if now - lastActivationTime < 0.08 {
            return false
        }
        lastActivationTime = now
        return true
    }
}

private final class GTKButtonActionBox {
    var action: () -> Void
    var activationGate = GTKButtonActivationGate()

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

private final class GTKButtonIdleActionContext {
    let box: GTKButtonActionBox
    let source: String

    init(box: GTKButtonActionBox, source: String) {
        self.box = box
        self.source = source
    }
}

private final class GTKButtonRootEventContext {
    let widget: UnsafeMutablePointer<GtkWidget>
    let box: GTKButtonActionBox
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?

    init(widget: UnsafeMutablePointer<GtkWidget>, box: GTKButtonActionBox) {
        self.widget = widget
        self.box = box
    }

    func removeController() {
        guard let root, let controller else { return }
        gtk_swift_remove_event_controller(root, controller)
        self.root = nil
        self.controller = nil
    }
}

private let gtkCustomButtonStyleContextKey = "quill-custom-button-style-context"

private final class GTKCustomButtonStyleContext {
    let button: UnsafeMutablePointer<GtkWidget>
    let label: AnyView
    let style: AnyButtonStyle
    let environment: EnvironmentValues
    var isPressed = false

    init(
        button: UnsafeMutablePointer<GtkWidget>,
        label: AnyView,
        style: AnyButtonStyle,
        environment: EnvironmentValues
    ) {
        self.button = button
        self.label = label
        self.style = style
        self.environment = environment
    }

    @MainActor
    func makeChild(isPressed: Bool) -> UnsafeMutablePointer<GtkWidget> {
        var renderEnvironment = environment
        // The style body is the button label, not another descendant button
        // scope. Clearing the custom style avoids accidental recursive restyling
        // if a style implementation contains a Button internally.
        renderEnvironment.customButtonStyle = nil
        renderEnvironment.buttonStyle = .plain
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(renderEnvironment)
        defer { setCurrentEnvironment(previousEnvironment) }

        let styledBody = style.makeBody(configuration: .init(label: label, isPressed: isPressed))
        let child = widgetFromOpaque(gtkRenderView(styledBody))
        gtkDisableButtonChildTargeting(child)
        return child
    }

    @MainActor
    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        let child = makeChild(isPressed: pressed)
        let buttonPointer = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
        gtk_button_set_child(buttonPointer, child)
    }
}

@discardableResult
private func gtkSetCustomButtonStylePressed(_ widget: UnsafeMutablePointer<GtkWidget>, pressed: Bool) -> Bool {
    guard let pointer = g_object_get_data(
        UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
        gtkCustomButtonStyleContextKey
    ) else {
        return false
    }
    let context = Unmanaged<GTKCustomButtonStyleContext>.fromOpaque(pointer).takeUnretainedValue()
    MainActor.assumeIsolated {
        context.setPressed(pressed)
    }
    return true
}

@discardableResult
func gtkTestSetCustomButtonStylePressed(_ widget: UnsafeMutablePointer<GtkWidget>, pressed: Bool) -> Bool {
    gtkSetCustomButtonStylePressed(widget, pressed: pressed)
}

/// Debug-only: tags a button activation source with the widget's root-frame
/// so QUILLUI_GTK_DEBUG_ACTIONS logs identify WHICH button fired.
private func gtkDebugButtonAncestorChain(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    guard let root = gtk_swift_widget_root_widget(widget) else { return }

    var current: UnsafeMutablePointer<GtkWidget>? = widget
    var depth = 0
    while let node = current, depth < 18 {
        var rootX = 0.0
        var rootY = 0.0
        _ = gtk_widget_translate_coordinates(node, root, 0, 0, &rootX, &rootY)
        var minimumWidth: gint = 0
        var naturalWidth: gint = 0
        gtk_swift_widget_measure(node, GTK_ORIENTATION_HORIZONTAL, -1, &minimumWidth, &naturalWidth)
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(node)))
        gtkDebugLog(
            "button ancestor[\(depth)] \(typeName) @\(Int(rootX)),\(Int(rootY)) \(gtk_widget_get_width(node))x\(gtk_widget_get_height(node)) naturalW=\(naturalWidth) minW=\(minimumWidth) hexpand=\(gtk_widget_get_hexpand(node)) halign=\(gtk_widget_get_halign(node).rawValue)"
        )
        current = gtk_widget_get_parent(node)
        depth += 1
    }
}

private func gtkButtonDebugSource(_ source: String, widget: UnsafeMutablePointer<GtkWidget>) -> String {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return source }
    guard gtk_swift_is_widget(widget) != 0, let root = gtk_swift_widget_root_widget(widget) else { return source }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(widget, root, 0, 0, &rootX, &rootY) != 0 else { return source }
    if source.hasPrefix("root-legacy@") {
        gtkDebugButtonAncestorChain(widget)
    }
    return "\(source)@\(Int(rootX)),\(Int(rootY)) \(gtk_widget_get_width(widget))x\(gtk_widget_get_height(widget))"
}

private func gtkWidgetCumulativeOffset(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>
) -> (x: Double, y: Double) {
    var offsetX = 0.0
    var offsetY = 0.0
    var current: UnsafeMutablePointer<GtkWidget>? = widget
    var depth = 0
    while let node = current, depth < 64 {
        offsetX += getWidgetDouble(node, key: gtkSwiftOffsetXKey) ?? 0
        offsetY += getWidgetDouble(node, key: gtkSwiftOffsetYKey) ?? 0
        if node == root { break }
        current = gtk_widget_get_parent(node)
        depth += 1
    }
    return (offsetX, offsetY)
}

private func gtkWidgetVisuallyContainsRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    guard let frame = gtkWidgetVisualFrameInRoot(widget, root: root) else { return false }
    let localX = x - frame.x
    let localY = y - frame.y
    return localX >= 0 && localX < frame.width && localY >= 0 && localY < frame.height
}

private func gtkWidgetOrDescendantVisuallyContainsRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> Bool {
    guard depth < 96 else { return false }
    guard gtk_widget_get_visible(widget) != 0 else { return false }
    if gtkWidgetVisuallyContainsRootPoint(widget, root: root, x: x, y: y) {
        return true
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if gtkWidgetOrDescendantVisuallyContainsRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            return true
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return false
}

private func gtkWidgetVisualFrameInRoot(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>
) -> (x: Double, y: Double, width: Double, height: Double)? {
    let offset = gtkWidgetCumulativeOffset(widget, root: root)

    var boundsX = 0.0
    var boundsY = 0.0
    var boundsWidth = 0.0
    var boundsHeight = 0.0
    if gtk_swift_widget_compute_bounds(
        widget,
        root,
        &boundsX,
        &boundsY,
        &boundsWidth,
        &boundsHeight
    ) != 0,
       boundsWidth > 0,
       boundsHeight > 0 {
        return (
            boundsX + offset.x,
            boundsY + offset.y,
            boundsWidth,
            boundsHeight
        )
    }

    let width = Double(gtk_widget_get_width(widget))
    let height = Double(gtk_widget_get_height(widget))
    guard width > 0, height > 0 else { return nil }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_swift_widget_compute_point(widget, root, 0, 0, &rootX, &rootY) != 0 else {
        return nil
    }
    return (rootX + offset.x, rootY + offset.y, width, height)
}

private func gtkDebugVisualFrameDescription(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>
) -> String {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return "" }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    let state = "visible=\(gtk_widget_get_visible(widget)) mapped=\(gtk_widget_get_mapped(widget))"
    guard let frame = gtkWidgetVisualFrameInRoot(widget, root: root) else {
        return "type=\(typeName) frame=nil \(state) size=\(gtk_widget_get_width(widget))x\(gtk_widget_get_height(widget))"
    }
    return "type=\(typeName) frame=\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height)) \(state)"
}

private func gtkWidgetTreeContainsVisualButtonAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> Bool {
    guard depth < 96 else { return false }
    guard gtk_widget_get_visible(widget) != 0,
          gtk_widget_get_sensitive(widget) != 0,
          gtk_widget_get_opacity(widget) > 0.001 else { return false }
    if let menuButton = gtkMenuOwnerButton(for: widget),
       gtk_widget_get_visible(menuButton) != 0,
       gtk_widget_get_sensitive(menuButton) != 0,
       gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y) {
        gtkDebugLog("visual button hit menu owner root@\(Int(x)),\(Int(y))")
        return true
    }
    let isButton = gtk_swift_widget_is_button(widget) != 0
    if isButton {
        guard let frame = gtkWidgetVisualFrameInRoot(widget, root: root),
              frame.width >= 1,
              frame.height >= 1 else {
            gtkDebugVisualButtonCandidate(widget, root: root, x: x, y: y, isHit: false, frame: nil)
            return false
        }
        let localX = x - frame.x
        let localY = y - frame.y
        let isHit = localX >= 0 && localX < frame.width && localY >= 0 && localY < frame.height
        gtkDebugVisualButtonCandidate(widget, root: root, x: x, y: y, isHit: isHit, frame: frame)
        if isHit {
            return true
        }
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if gtkWidgetTreeContainsVisualButtonAtRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            return true
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return false
}

private func gtkWidgetTreeFindVisualMenuButtonAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> UnsafeMutablePointer<GtkWidget>? {
    guard depth < 96 else { return nil }
    if let menuButton = gtkMenuOwnerButton(for: widget),
       gtk_widget_get_visible(menuButton) != 0,
       gtk_widget_get_sensitive(menuButton) != 0,
       gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y) {
        gtkDebugLog("visual menu owner hit root@\(Int(x)),\(Int(y))")
        return menuButton
    }
    if gtk_swift_widget_is_menu_button(widget) != 0,
       gtk_widget_get_visible(widget) != 0,
       gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y) {
        return widget
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let match = gtkWidgetTreeFindVisualMenuButtonAtRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            return match
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return nil
}

private final class GTKMenuPopupRootPointContext {
    let root: UnsafeMutablePointer<GtkWidget>
    let x: Double
    let y: Double
    let source: String

    init(root: UnsafeMutablePointer<GtkWidget>, x: Double, y: Double, source: String) {
        self.root = root
        self.x = x
        self.y = y
        self.source = source
    }
}

private func gtkScheduleVisualMenuButtonPopup(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) {
    let context = Unmanaged.passRetained(
        GTKMenuPopupRootPointContext(root: root, x: x, y: y, source: source)
    ).toOpaque()
    g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKMenuPopupRootPointContext>
            .fromOpaque(userData)
            .takeRetainedValue()
        let menuButton = gtkWidgetTreeFindVisualMenuButtonAtRootPoint(
            context.root,
            root: context.root,
            x: context.x,
            y: context.y
        ) ?? gtk_swift_root_point_pick_menu_button(context.root, context.x, context.y)
        guard let menuButton else {
            gtkDebugLog("list row tap missed visual menu button \(context.source)")
            return 0
        }
        if gtkOpenMenuOverlay(menuButton: menuButton, root: context.root, source: context.source) {
            return 0
        }
        let visible = gtk_swift_menu_button_popup_if_closed(menuButton) != 0
        gtkDebugLog("list row tap opened visual menu button \(context.source) visible=\(visible)")
        return 0
    }, context)
}

private func gtkDebugVisualButtonCandidate(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    isHit: Bool,
    frame: (x: Double, y: Double, width: Double, height: Double)?
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    guard isHit || frame != nil else { return }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    let frameText: String
    if let frame {
        frameText = "\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height))"
    } else {
        var rootX = 0.0
        var rootY = 0.0
        _ = gtk_widget_translate_coordinates(widget, root, 0, 0, &rootX, &rootY)
        let offset = gtkWidgetCumulativeOffset(widget, root: root)
        frameText = "\(Int(rootX + offset.x)),\(Int(rootY + offset.y)) \(gtk_widget_get_width(widget))x\(gtk_widget_get_height(widget))"
    }
    gtkDebugLog(
        "visual button candidate hit=\(isHit) point=\(Int(x)),\(Int(y)) type=\(typeName) frame=\(frameText)"
    )
}

private func gtkOpenVisualMenuButtonAtWidgetPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) -> Bool {
    guard let root = gtk_swift_widget_root_widget(widget) else { return false }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(widget, root, x, y, &rootX, &rootY) != 0 else {
        return false
    }
    return gtkOpenVisualMenuButtonAtRootPoint(root: root, x: rootX, y: rootY, source: source)
}

private func gtkRootTreeContainsVisualButtonAtWidgetPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    guard let root = gtk_swift_widget_root_widget(widget) else { return false }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(widget, root, x, y, &rootX, &rootY) != 0 else {
        return false
    }
    return gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: rootX, y: rootY)
}

private func gtkWidgetTreeContainsVisualTapActionAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> Bool {
    guard depth < 160 else { return false }
    guard gtk_widget_get_visible(widget) != 0,
          gtk_widget_get_sensitive(widget) != 0,
          gtk_widget_get_opacity(widget) > 0.001 else { return false }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if gtkWidgetTreeContainsVisualTapActionAtRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            return true
        }
        child = gtk_widget_get_next_sibling(current)
    }

    guard gtk_swift_widget_is_button(widget) == 0,
          gtk_swift_widget_is_menu_button(widget) == 0,
          gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y),
          let actionData = g_object_get_data(
              UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
              gtkTapGestureActionDataKey
          )
    else {
        return false
    }

    let box = Unmanaged<GTKTapGestureActionBox>.fromOpaque(actionData).takeUnretainedValue()
    return box.requiredCount == 1
}

private func gtkRootTreeContainsVisualTapActionAtWidgetPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    guard let root = gtk_swift_widget_root_widget(widget) else { return false }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(widget, root, x, y, &rootX, &rootY) != 0 else {
        return false
    }
    return gtkWidgetTreeContainsVisualTapActionAtRootPoint(root, root: root, x: rootX, y: rootY)
}

func gtkTestWidgetVisuallyContainsRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    gtkWidgetVisuallyContainsRootPoint(widget, root: root, x: x, y: y)
}

func gtkTestWidgetTreeContainsVisualButtonAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    gtkWidgetTreeContainsVisualButtonAtRootPoint(widget, root: root, x: x, y: y)
}

func gtkTestWidgetTreeContainsVisualTapActionAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    gtkWidgetTreeContainsVisualTapActionAtRootPoint(widget, root: root, x: x, y: y)
}

func gtkTestPreferredTapActionMatchesWidgetTapData(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    guard let widgetBox = gtkTapGestureActionBox(from: widget),
          let preferredBox = gtkPreferredTapGestureActionBoxAtRootPoint(root: root, x: x, y: y)
    else {
        return false
    }
    return widgetBox === preferredBox
}

func gtkTestFindVisualMenuButtonAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> UnsafeMutablePointer<GtkWidget>? {
    gtkWidgetTreeFindVisualMenuButtonAtRootPoint(widget, root: root, x: x, y: y)
}

func gtkTestMenuOwnerButton(
    for widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget>? {
    gtkMenuOwnerButton(for: widget)
}

func gtkSetButtonAction(slotID: Int, action: @escaping () -> Void) -> Bool {
    guard let widget = gtkWidgetFromSlotID(slotID) else { return false }
    guard gtk_swift_is_widget(widget) != 0 else { return false }
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let raw = g_object_get_data(gobject, gtkSwiftButtonActionBoxDataKey) else {
        return false
    }
    let box = Unmanaged<GTKButtonActionBox>.fromOpaque(raw).takeUnretainedValue()
    box.action = action
    return true
}

func gtkTestSetButtonAction(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    action: @escaping () -> Void
) -> Bool {
    gtkSetButtonAction(slotID: gtkNativeSlotID(for: widget), action: action)
}

func gtkTestActivateButton(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    guard gtk_swift_is_widget(widget) != 0 else { return false }
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let raw = g_object_get_data(gobject, gtkSwiftButtonActionBoxDataKey) else {
        return false
    }
    let box = Unmanaged<GTKButtonActionBox>.fromOpaque(raw).takeUnretainedValue()
    gtkScheduleButtonAction(box, source: "test")
    return true
}

func gtkTestActivateCollapsedListRowControlAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    gtkActivateCollapsedListRowControlAtRootPoint(root: root, x: x, y: y, source: "test")
}

func gtkTestDismissActiveMenuOverlay() {
    gtkDismissActiveMenuOverlay()
}

func gtkTestHasActiveMenuOverlay() -> Bool {
    gtkActiveMenuOverlayState != nil
}

func gtkTestActiveMenuOverlayLayerTypeName() -> String? {
    guard let layer = gtkActiveMenuOverlayLayer else { return nil }
    return String(cString: g_type_name(gtk_swift_get_widget_type(layer)))
}

private func gtkScheduleButtonAction(
    _ box: GTKButtonActionBox,
    source: String,
    phase: GTKButtonActivationGate.Phase = .pointerPress
) {
    gtkFlushPendingTextBindingUpdate()
    let now = Date().timeIntervalSinceReferenceDate
    guard box.activationGate.shouldFire(phase, now: now) else {
        gtkDebugLog("button duplicate \(source)")
        return
    }
    gtkDebugLog("button \(source)")
    let context = Unmanaged.passRetained(GTKButtonIdleActionContext(box: box, source: source)).toOpaque()
    g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKButtonIdleActionContext>.fromOpaque(userData).takeRetainedValue()
        gtkDebugLog("button action \(context.source)")
        context.box.action()
        return 0
    }, context)
}

private func gtkInstallButtonRootEventFallback(_ context: GTKButtonRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.widget) else { return }

    let controller = gtk_swift_legacy_capture_controller()!
    context.root = root
    context.controller = controller
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return 0 }
            var x: Double = 0
            var y: Double = 0
            guard gtk_swift_event_get_position(event, &x, &y) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: x, y: y)
            }
            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0
            let isVisualHit = gtkWidgetVisuallyContainsRootPoint(context.widget, root: root, x: x, y: y)
            guard isTopmost || isVisualHit else { return 0 }
            let source = isTopmost ? "root-legacy" : "root-visual"
            gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("\(source)@\(Int(x)),\(Int(y))", widget: context.widget), phase: .pointerPress)
            return 0
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

extension Button: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        gtkCollectButtonPayload(GTK4ButtonPayload(action: bindActionToCurrentEnvironment(action)))
        // Opaque stable leaf. The descriptor payload collector captures the
        // current action closure and the host refreshes reused GtkButtons
        // during narrow mutation, so model-dependent actions do not go stale.
        return GTK4DescriptorNode(kind: .button, typeName: "Button")
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let button: UnsafeMutablePointer<GtkWidget>
        let childWidget: UnsafeMutablePointer<GtkWidget>
        let styleContext: GTKCustomButtonStyleContext?
        var buttonWantsHExpand = false
        var buttonWantsVExpand = false

        button = gtk_button_new()!
        let environment = getCurrentEnvironment()
        if let customButtonStyle = environment.customButtonStyle {
            let context = GTKCustomButtonStyleContext(
                button: button,
                label: AnyView(label),
                style: customButtonStyle,
                environment: environment
            )
            childWidget = context.makeChild(isPressed: false)
            styleContext = context
            if gtk_widget_get_hexpand(childWidget) != 0 {
                buttonWantsHExpand = true
                gtk_widget_set_halign(childWidget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(childWidget) != 0 {
                buttonWantsVExpand = true
                gtk_widget_set_valign(childWidget, GTK_ALIGN_FILL)
            }
        } else if let textLabel = label as? Text {
            childWidget = widgetFromOpaque(textLabel.gtkCreateWidget())
            styleContext = nil
        } else {
            childWidget = widgetFromOpaque(gtkRenderView(label))
            styleContext = nil
            if gtk_widget_get_hexpand(childWidget) != 0 {
                buttonWantsHExpand = true
                gtk_widget_set_halign(childWidget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(childWidget) != 0 {
                buttonWantsVExpand = true
                gtk_widget_set_valign(childWidget, GTK_ALIGN_FILL)
            }
        }

        let buttonStyleType = getCurrentEnvironment().buttonStyle
        let handledByQuillPaint: Bool
        if styleContext != nil {
            handledByQuillPaint = false
        } else {
            switch buttonStyleType {
            case .quillPaintMacDefault:
                handledByQuillPaint = quill_gtk_button_paint_hook?(OpaquePointer(button), OpaquePointer(childWidget), true) ?? false
            case .quillPaintMacBordered:
                handledByQuillPaint = quill_gtk_button_paint_hook?(OpaquePointer(button), OpaquePointer(childWidget), false) ?? false
            case let .quillPaintMacListRow(isSelected, drawsIdleBackground):
                handledByQuillPaint = quill_gtk_list_row_paint_hook?(
                    OpaquePointer(button),
                    OpaquePointer(childWidget),
                    isSelected,
                    drawsIdleBackground
                ) ?? false
            default:
                handledByQuillPaint = false
            }
        }

        if !handledByQuillPaint {
            let btnPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
            gtk_button_set_child(btnPtr, childWidget)
            gtkDisableButtonChildTargeting(childWidget)
            if styleContext != nil || !(label is Text) {
                // Remove GTK default button border/padding so custom-styled
                // labels (with .background/.frame) render cleanly.
                applyCSSToWidget(button, properties: """
                    background: transparent;
                    background-color: transparent;
                    background-image: none;
                    border: none;
                    border-radius: 0;
                    box-shadow: none;
                    outline: none;
                    padding: 0;
                    min-height: 0;
                    min-width: 0;
                    text-shadow: none;
                    """)
            }
        }

        if let styleContext {
            let retained = Unmanaged.passRetained(styleContext).toOpaque()
            g_object_set_data_full(
                UnsafeMutableRawPointer(button).assumingMemoryBound(to: GObject.self),
                gtkCustomButtonStyleContextKey,
                retained,
                { userData in
                    guard let userData else { return }
                    Unmanaged<GTKCustomButtonStyleContext>.fromOpaque(userData).release()
                }
            )
        }

        if !handledByQuillPaint {
            switch buttonStyleType {
            case .plain:
                gtk_widget_add_css_class(button, "flat")
                applyCSSToWidget(button, properties: """
                    background: transparent;
                    background-color: transparent;
                    background-image: none;
                    border: none;
                    border-radius: 0;
                    box-shadow: none;
                    outline: none;
                    padding: 0;
                    min-height: 0;
                    min-width: 0;
                    text-shadow: none;
                    """)
            case .borderedProminent, .quillPaintMacDefault:
                // Concrete macOS-like accent blue with explicit overrides of
                // GTK's default button gradient and inset shadow, both of which
                // stack on top of `background-color` and render it invisible
                // otherwise. App-configurable tint via a future `.tint()`
                // modifier; theme-aware tint via `@theme_selected_bg_color` /
                // `@accent_bg_color` is a future refinement — a previous attempt
                // at a CSS cascade `background-color: X; background-color: Y;`
                // made the button vanish (GTK CSS doesn't skip undefined-named-
                // color declarations gracefully), so that's parked.
                //
                // Disabled state: use a faded translucent blue with muted text
                // so .disabled() has a visual signal. Without this override, our
                // base rules apply even when the button is insensitive, so a
                // .borderedProminent + .disabled() button looks identical to the
                // enabled version (only click handling differs).
                applyCSSToWidget(
                    button,
                    properties: """
                        background-color: #3584e4;
                        background-image: none;
                        color: white;
                        border: none;
                        border-radius: 6px;
                        padding: 6px 12px;
                        box-shadow: none;
                        text-shadow: none;
                        min-height: 0;
                        """,
                    disabledProperties: """
                        background-color: rgba(53, 132, 228, 0.4);
                        color: rgba(255, 255, 255, 0.7);
                        """
                )
            case .bordered, .accessoryBarAction, .quillPaintMacBordered:
                applyCSSToWidget(button, properties: """
                    border: 1px solid @borders; border-radius: 6px;
                    padding: 6px 12px;
                    """)
            case .automatic, .quillPaintMacListRow(_, _):
                break // default GTK button styling
            }
        }

        gtk_widget_set_hexpand(button, buttonWantsHExpand ? 1 : 0)
        gtk_widget_set_vexpand(button, buttonWantsVExpand ? 1 : 0)
        gtk_widget_set_halign(button, buttonWantsHExpand ? GTK_ALIGN_FILL : GTK_ALIGN_START)
        gtk_widget_set_valign(button, buttonWantsVExpand ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER)

        let boundAction = bindActionToCurrentEnvironment(action)
        let buttonActionBox = Unmanaged.passRetained(GTKButtonActionBox(boundAction)).toOpaque()
        g_object_set_data(
            UnsafeMutableRawPointer(button).assumingMemoryBound(to: GObject.self),
            gtkSwiftButtonActionBoxDataKey,
            buttonActionBox
        )
        let buttonRootEventContext = Unmanaged.passRetained(
            GTKButtonRootEventContext(
                widget: button,
                box: Unmanaged<GTKButtonActionBox>.fromOpaque(buttonActionBox).takeUnretainedValue()
            )
        ).toOpaque()
        g_signal_connect_data(
            gpointer(button),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkInstallButtonRootEventFallback(context)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(button),
            "unmap",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(button),
            "clicked",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                _ = gtkSetCustomButtonStylePressed(context.widget, pressed: false)
                gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("clicked", widget: context.widget), phase: .clicked)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        let gesture = gtk_gesture_click_new()!
        gtk_swift_gesture_single_set_button(gesture, 1)
        g_signal_connect_data(
            gpointer(gesture),
            "pressed",
            unsafeBitCast({ (_: gpointer?, _: gint, _: gdouble, _: gdouble, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                _ = gtkSetCustomButtonStylePressed(context.widget, pressed: true)
                gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("gesture", widget: context.widget), phase: .pointerPress)
            } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        gtk_swift_add_capture_gesture(button, gesture)
        let legacyController = gtk_swift_legacy_capture_controller()!
        g_signal_connect_data(
            legacyController,
            "event",
            unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
                guard let event, let userData else { return 0 }
                guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
                let box = Unmanaged<GTKButtonActionBox>.fromOpaque(userData).takeUnretainedValue()
                gtkScheduleButtonAction(box, source: "legacy", phase: .pointerPress)
                return 0
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
            buttonActionBox,
            nil,
            GConnectFlags(rawValue: 0)
        )
        gtk_swift_add_event_controller(button, legacyController)
        g_signal_connect_data(
            gpointer(button),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeRetainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(button),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<GTKButtonActionBox>.fromOpaque(userData).release()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonActionBox,
            nil,
            GConnectFlags(rawValue: 0)
        )
        // Register keyboard shortcut if present in environment
        if let ks = getCurrentEnvironment().keyboardShortcut {
            let windowID = getCurrentEnvironment().windowID
            let boundShortcutAction = bindActionToCurrentEnvironment(action)
            // Shortcut-driven actions (e.g. Return firing Send) must observe
            // the typed text: flush the debounced binding write first.
            let actionClosure = {
                gtkFlushPendingTextBindingUpdate()
                boundShortcutAction()
            }
            let regID = KeyboardShortcutRegistry.shared.register(ks, windowID: windowID, action: actionClosure)

            // Unregister by registration ID when the button widget is destroyed
            let destroyBox = Unmanaged.passRetained(ClosureBox {
                KeyboardShortcutRegistry.shared.unregister(id: regID)
            }).toOpaque()
            g_signal_connect_data(
                gpointer(button), "destroy",
                unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                    guard let userData else { return }
                    Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
                } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                destroyBox,
                { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
                },
                GConnectFlags(rawValue: 0)
            )
        }

        gtkApplyEnabledState(to: button)
        return opaqueFromWidget(button)
    }
}

// MARK: - keyboardShortcut GTK extension

extension KeyboardShortcutView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let prev = getCurrentEnvironment()
        var env = prev
        env.keyboardShortcut = shortcut
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(prev) }
        return gtkRenderView(content)
    }
}

// MARK: - onExitCommand GTK extension

extension ExitCommandView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let windowID = getCurrentEnvironment().windowID
        let widget = gtkRenderView(content)

        guard let action else {
            return widget
        }

        let boundAction = bindActionToCurrentEnvironment(action)
        let regID = KeyboardShortcutRegistry.shared.register(.cancelAction, windowID: windowID) {
            gtkFlushPendingTextBindingUpdate()
            boundAction()
        }

        let destroyBox = Unmanaged.passRetained(ClosureBox {
            KeyboardShortcutRegistry.shared.unregister(id: regID)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(widget), "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            destroyBox,
            { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
            },
            GConnectFlags(rawValue: 0)
        )

        return widget
    }
}

// MARK: - focusedValue GTK extension

extension FocusedValueView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let windowID = getCurrentEnvironment().windowID
        let providerID = FocusedValuesStore.shared.register(
            windowID: windowID, key: keyType, value: value
        )

        let widget = gtkRenderView(content)

        // Unregister provider when the widget is destroyed
        let destroyBox = Unmanaged.passRetained(ClosureBox {
            FocusedValuesStore.shared.unregister(id: providerID)
        }).toOpaque()
        let widgetPtr = widgetFromOpaque(widget)
        g_signal_connect_data(
            gpointer(widgetPtr), "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            destroyBox,
            { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
            },
            GConnectFlags(rawValue: 0)
        )

        return widget
    }
}

// MARK: - dropDestination GTK extension

/// State for GTK4 drop target signal handlers.
private class GTKDropState {
    let action: ([URL], CGPoint) -> Bool
    let isTargeted: ((Bool) -> Void)?
    weak var host: GTKViewHost?
    var isHovering = false
    var pendingLeaveSource: guint = 0
    init(action: @escaping ([URL], CGPoint) -> Bool, isTargeted: ((Bool) -> Void)?) {
        self.action = action
        self.isTargeted = isTargeted
    }

    func beginHoverIfNeeded() {
        cancelPendingLeave()
        guard !isHovering else { return }
        isHovering = true
        host?.beginInteractiveUpdate()
        isTargeted?(true)
    }

    func endHoverIfNeeded() {
        cancelPendingLeave()
        guard isHovering else { return }
        isHovering = false
        isTargeted?(false)
        host?.endInteractiveUpdate()
    }

    func scheduleLeave() {
        cancelPendingLeave()
        let statePtr = Unmanaged.passRetained(self).toOpaque()
        pendingLeaveSource = g_timeout_add(50, { userData -> gboolean in
            guard let userData else { return 0 }
            let state = Unmanaged<GTKDropState>.fromOpaque(userData).takeRetainedValue()
            state.pendingLeaveSource = 0
            state.endHoverIfNeeded()
            return 0
        }, statePtr)
    }

    func cancelPendingLeave() {
        if pendingLeaveSource != 0 {
            g_source_remove(pendingLeaveSource)
            pendingLeaveSource = 0
        }
    }
}

/// Keep the controller's widget alive until the next main-loop turn.
/// Drop handlers often mutate Swift state, which can synchronously rebuild
/// and destroy the target widget before GTK finishes its internal drag-state
/// cleanup for the current signal dispatch.
private func gtkPinDropTargetWidgetUntilIdle(_ target: OpaquePointer?) {
    guard let target,
          let widget = gtk_swift_event_controller_get_widget(gpointer(target)) else { return }
    let raw = UnsafeMutableRawPointer(widget)
    g_object_ref(raw)
    g_idle_add({ userData -> gboolean in
        if let userData { g_object_unref(userData) }
        return 0  // G_SOURCE_REMOVE
    }, raw)
}

extension DropDestinationView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = gtkRenderView(content)
        let widgetPtr = widgetFromOpaque(widget)

        // Create GtkDropTarget for file list drops
        let dropTarget = gtk_swift_drop_target_new_for_file_list()!

        let state = GTKDropState(action: action, isTargeted: isTargeted)
        state.host = GTKViewHost.getCurrentRebuilding()
        let stateUD = Unmanaged.passRetained(state).toOpaque()

        // "enter" signal → isTargeted(true), return GDK_ACTION_COPY
        g_signal_connect_data(
            gpointer(dropTarget), "enter",
            unsafeBitCast({ (_target: OpaquePointer?, _x: Double, _y: Double, userData: gpointer?) -> Int32 in
                guard let userData else { return 0 }
                let state = Unmanaged<GTKDropState>.fromOpaque(userData).takeUnretainedValue()
                state.beginHoverIfNeeded()
                gtkPinDropTargetWidgetUntilIdle(_target)
                return 1  // GDK_ACTION_COPY
            } as @convention(c) (OpaquePointer?, Double, Double, gpointer?) -> Int32, to: GCallback.self),
            stateUD, nil,
            GConnectFlags(rawValue: 0)
        )

        // "leave" signal → isTargeted(false)
        g_signal_connect_data(
            gpointer(dropTarget), "leave",
            unsafeBitCast({ (_target: OpaquePointer?, userData: gpointer?) in
                guard let userData else { return }
                let state = Unmanaged<GTKDropState>.fromOpaque(userData).takeUnretainedValue()
                state.scheduleLeave()
                gtkPinDropTargetWidgetUntilIdle(_target)
            } as @convention(c) (OpaquePointer?, gpointer?) -> Void, to: GCallback.self),
            stateUD, nil,
            GConnectFlags(rawValue: 0)
        )

        // "drop" signal → extract file paths, call action
        g_signal_connect_data(
            gpointer(dropTarget), "drop",
            unsafeBitCast({ (_target: OpaquePointer?, value: UnsafePointer<GValue>?, x: Double, y: Double, userData: gpointer?) -> gboolean in
                guard let userData, let value else { return 0 }
                let state = Unmanaged<GTKDropState>.fromOpaque(userData).takeUnretainedValue()
                state.cancelPendingLeave()

                // Keep the widget alive through GTK's post-drop cleanup.
                gtkPinDropTargetWidgetUntilIdle(_target)

                // Extract file list from the GValue
                let fileList = gtk_swift_file_list_get_gslist(value)
                let count = gtk_swift_gslist_length(fileList)

                var urls: [URL] = []
                for i in 0..<count {
                    if let gfile = gtk_swift_gslist_nth_data(fileList, i) {
                        if let pathPtr = gtk_swift_gfile_get_path(gfile) {
                            let path = String(cString: pathPtr)
                            urls.append(URL(fileURLWithPath: path))
                            g_free(gpointer(mutating: pathPtr))
                        }
                    }
                }

                let location = CGPoint(x: x, y: y)
                let accepted = state.action(urls, location)

                // End hover after the user action has run. If GTK already
                // sent "leave", this is a no-op.
                state.endHoverIfNeeded()

                return accepted ? 1 : 0
            } as @convention(c) (OpaquePointer?, UnsafePointer<GValue>?, Double, Double, gpointer?) -> gboolean, to: GCallback.self),
            stateUD, nil,
            GConnectFlags(rawValue: 0)
        )

        // Tie GTKDropState's lifetime to the GtkDropTarget GObject, NOT to
        // the child widget's destroy signal. When `isTargeted` mutates
        // @State, SwiftOpenUI rebuilds the view and replaces the drop
        // target mid-drag — if state were released only at child-widget
        // destroy, a still-queued "drop" signal on the old controller
        // would fire with a dangling stateUD and crash in state.action().
        // With g_object_set_data_full on the drop target itself, state is
        // released exactly when the controller that references it is
        // finalized, which is after GTK has stopped dispatching signals
        // to it. Bypass the widget-destroy race entirely.
        let dropTargetGObject = UnsafeMutableRawPointer(dropTarget)
            .assumingMemoryBound(to: GObject.self)
        g_object_set_data_full(dropTargetGObject, "gtk-swift-drop-state", stateUD) { ud in
            guard let ud else { return }
            let state = Unmanaged<GTKDropState>.fromOpaque(ud).takeUnretainedValue()
            state.cancelPendingLeave()
            state.endHoverIfNeeded()
            Unmanaged<GTKDropState>.fromOpaque(ud).release()
        }

        // Attach drop target to widget. GtkDropTarget IS-A GtkEventController,
        // so gtk_widget_add_controller accepts it directly; dropTarget is
        // already OpaquePointer from gtk_swift_drop_target_new_for_file_list().
        gtk_widget_add_controller(widgetPtr, dropTarget)

        return widget
    }
}

// MARK: - Container GTK extensions

extension VStack: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let childDescs: [GTK4DescriptorNode]
        if let multi = content as? MultiChildView {
            childDescs = multi.children.map(gtkDescribeAnyView)
        } else {
            childDescs = [gtkDescribeView(content)]
        }
        return GTK4DescriptorNode(
            kind: .vStack, typeName: "VStack",
            props: .vStack(GTK4VStackDescriptor(
                spacing: gtkVStackSpacing(spacing),
                alignment: gtkHorizontalAlignmentDescriptor(alignment))),
            children: childDescs)
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let effectiveSpacing = gtkVStackSpacing(spacing)
        let children = gtkRenderChildren(content)
            .map(widgetFromOpaque)
            .filter { !gtkIsEmptyViewWidget($0) }
        if children.isEmpty {
            return opaqueFromWidget(gtkCreateEmptyViewWidget())
        }
        if !gtkIsRenderingRowContent, gtkCanUseSharedVStackLayout(children) {
            return gtkRenderSharedVStack(children, spacing: effectiveSpacing, alignment: alignment)
        }

        return gtkRenderFallbackVStack(children, spacing: effectiveSpacing, alignment: alignment)
    }
}

private func gtkCanUseSharedVStackLayout(_ children: [UnsafeMutablePointer<GtkWidget>]) -> Bool {
    for widget in children {
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            return false
        }
        if gtk_widget_get_hexpand(widget) != 0 || gtk_widget_get_vexpand(widget) != 0 {
            return false
        }
    }
    return true
}

private func gtkRenderSharedVStack(
    _ children: [UnsafeMutablePointer<GtkWidget>],
    spacing: Int,
    alignment: HorizontalAlignment
) -> OpaquePointer {
    let wrapper = gtk_swift_fixed_new()!
    let context = GTKLayoutMeasureContext(widgets: children)
    let layout = computeVStackLayout(
        subviews: children.indices.map(LayoutSubview.init(index:)),
        context: context,
        spacing: Double(spacing),
        alignment: alignment
    )

    gtk_widget_set_size_request(
        wrapper,
        gint(layout.containerSize.width),
        gint(layout.containerSize.height)
    )

    for (widget, placement) in zip(children, layout.childPlacements) {
        gtk_widget_set_halign(widget, GTK_ALIGN_START)
        gtk_widget_set_valign(widget, GTK_ALIGN_START)
        gtk_swift_fixed_put(wrapper, widget, placement.origin.x, placement.origin.y)
    }

    return opaqueFromWidget(wrapper)
}

private func gtkRenderFallbackVStack(
    _ children: [UnsafeMutablePointer<GtkWidget>],
    spacing: Int,
    alignment: HorizontalAlignment
) -> OpaquePointer {
    let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, gint(spacing))!
    var needsHExpand = false
    var needsVExpand = false
    var hasVerticalFillIntent = false

    let gtkAlign: GtkAlign
    switch alignment {
    case .leading:  gtkAlign = GTK_ALIGN_START
    case .center:   gtkAlign = GTK_ALIGN_CENTER
    case .trailing: gtkAlign = GTK_ALIGN_END
    }

    for originalWidget in children {
        var widget = originalWidget
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            gtk_widget_set_hexpand(widget, 0)
            gtk_widget_set_vexpand(widget, 1)
        }
        if gtk_widget_get_hexpand(widget) != 0 {
            needsHExpand = true
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        } else {
            gtk_widget_set_halign(widget, gtkAlign)
        }
        if gtk_widget_get_vexpand(widget) != 0 && gtkHasVerticalFillIntent(widget) {
            widget = gtkCompressibleHeightClamp(widget)
        }
        if gtkHasVerticalFillIntent(widget) {
            hasVerticalFillIntent = true
        }
        if gtk_widget_get_vexpand(widget) != 0 { needsVExpand = true; gtk_widget_set_valign(widget, GTK_ALIGN_FILL) }
        gtk_box_append(boxPointer(box), widget)
    }
    if needsHExpand { gtk_widget_set_hexpand(box, 1) }
    if needsVExpand { gtk_widget_set_vexpand(box, 1) }
    if hasVerticalFillIntent { gtkMarkVerticalFillIntent(box) }
    return opaqueFromWidget(box)
}

extension HStack: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let childDescs: [GTK4DescriptorNode]
        if let multi = content as? MultiChildView {
            childDescs = multi.children.map(gtkDescribeAnyView)
        } else {
            childDescs = [gtkDescribeView(content)]
        }
        return GTK4DescriptorNode(
            kind: .hStack, typeName: "HStack",
            props: .hStack(GTK4HStackDescriptor(
                spacing: resolveStackSpacing(spacing),
                alignment: gtkVerticalAlignmentDescriptor(alignment))),
            children: childDescs)
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let effectiveSpacing = resolveStackSpacing(spacing)
        let childViews: [any View]
        if let multi = content as? MultiChildView {
            childViews = multi.children.flatMap { gtkLayoutChildViews(from: $0) }
        } else {
            childViews = gtkLayoutChildViews(from: content)
        }
        let children = gtkRenderChildren(content)
            .map(widgetFromOpaque)
            .filter { !gtkIsEmptyViewWidget($0) }
        if children.isEmpty {
            return opaqueFromWidget(gtkCreateEmptyViewWidget())
        }
        gtkDebugRowHStack(
            contentType: String(reflecting: Swift.type(of: content)),
            childViews: childViews,
            widgets: children
        )
        if !gtkIsRenderingRowContent, gtkCanUseSharedHStackLayout(children) {
            return gtkRenderSharedHStack(children, spacing: effectiveSpacing, alignment: alignment)
        }

        return gtkRenderFallbackHStack(children, spacing: effectiveSpacing, alignment: alignment)
    }
}

private func gtkCanUseSharedHStackLayout(_ children: [UnsafeMutablePointer<GtkWidget>]) -> Bool {
    for widget in children {
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            return false
        }
        if gtk_widget_get_hexpand(widget) != 0 || gtk_widget_get_vexpand(widget) != 0 {
            return false
        }
    }
    return true
}

private func gtkRenderSharedHStack(
    _ children: [UnsafeMutablePointer<GtkWidget>],
    spacing: Int,
    alignment: VerticalAlignment
) -> OpaquePointer {
    let wrapper = gtk_swift_fixed_new()!
    let context = GTKLayoutMeasureContext(widgets: children)
    let layout = computeHStackLayout(
        subviews: children.indices.map(LayoutSubview.init(index:)),
        context: context,
        spacing: Double(spacing),
        alignment: alignment
    )

    gtk_widget_set_size_request(
        wrapper,
        gint(layout.containerSize.width),
        gint(layout.containerSize.height)
    )

    for (widget, placement) in zip(children, layout.childPlacements) {
        gtk_widget_set_halign(widget, GTK_ALIGN_START)
        gtk_widget_set_valign(widget, GTK_ALIGN_START)
        gtk_swift_fixed_put(wrapper, widget, placement.origin.x, placement.origin.y)
    }

    return opaqueFromWidget(wrapper)
}

private func gtkRenderFallbackHStack(
    _ children: [UnsafeMutablePointer<GtkWidget>],
    spacing: Int,
    alignment: VerticalAlignment
) -> OpaquePointer {
    let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, gint(spacing))!
    var needsHExpand = false
    var needsVExpand = false
    var hasVerticalFillIntent = false
    let hasNonSpacerHExpand = children.contains { widget in
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        return g_object_get_data(gobject, gtkSwiftSpacerMarker) == nil
            && gtk_widget_get_hexpand(widget) != 0
    }

    let gtkAlign: GtkAlign
    switch alignment {
    case .top:    gtkAlign = GTK_ALIGN_START
    case .center: gtkAlign = GTK_ALIGN_CENTER
    case .bottom: gtkAlign = GTK_ALIGN_END
    }

    for widget in children {
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            if hasNonSpacerHExpand {
                gtk_widget_set_size_request(widget, 8, -1)
                gtk_widget_set_hexpand(widget, 0)
            } else {
                gtk_widget_set_hexpand(widget, 1)
            }
            gtk_widget_set_vexpand(widget, 0)
        }
        if g_object_get_data(gobject, gtkSwiftDividerMarker) != nil {
            gtk_swift_orientable_set_orientation(widget, GTK_ORIENTATION_VERTICAL)
            gtk_widget_set_hexpand(widget, 0)
            gtk_widget_set_vexpand(widget, 1)
        }
        if gtk_widget_get_hexpand(widget) != 0 {
            needsHExpand = true
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        } else {
            gtk_widget_set_halign(widget, GTK_ALIGN_START)
        }
        if gtk_widget_get_vexpand(widget) != 0 {
            needsVExpand = true
            gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
        } else {
            gtk_widget_set_valign(widget, gtkAlign)
        }
        if gtkHasVerticalFillIntent(widget) {
            hasVerticalFillIntent = true
        }
        gtk_box_append(boxPointer(box), widget)
    }
    if needsHExpand { gtk_widget_set_hexpand(box, 1) }
    if needsVExpand { gtk_widget_set_vexpand(box, 1) }
    if hasVerticalFillIntent { gtkMarkVerticalFillIntent(box) }
    return opaqueFromWidget(box)
}

private func gtkDebugRowHStack(
    contentType: String,
    childViews: [any View],
    widgets: [UnsafeMutablePointer<GtkWidget>]
) {
    let debugHStacks = ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_HSTACK"]
    guard debugHStacks == "1" || debugHStacks == "all" else {
        return
    }
    let viewTypes = childViews.map { String(reflecting: Swift.type(of: $0)) }.joined(separator: ", ")
    guard debugHStacks == "all"
            || viewTypes.contains("StatusActionButton")
            || viewTypes.contains("ShareLink")
            || viewTypes.contains("StatusRowActionsView")
            || viewTypes.contains("Menu") else {
        return
    }
    let widgetInfo = widgets.enumerated().map { index, widget -> String in
        var minW: gint = 0
        var natW: gint = 0
        var minH: gint = 0
        var natH: gint = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, &minW, &natW, nil, nil)
        gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, -1, &minH, &natH, nil, nil)
        return "#\(index):hex=\(gtk_widget_get_hexpand(widget)) vex=\(gtk_widget_get_vexpand(widget)) nat=\(natW)x\(natH)"
    }.joined(separator: "; ")
    gtkListDebugLog("hstack content=\(contentType) views=[\(viewTypes)] widgets=[\(widgetInfo)]")
}

extension ZStack: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let childDescs: [GTK4DescriptorNode]
        if let multi = content as? MultiChildView {
            childDescs = multi.children.map(gtkDescribeAnyView)
        } else {
            childDescs = [gtkDescribeView(content)]
        }
        return GTK4DescriptorNode(
            kind: .zStack, typeName: "ZStack",
            props: .zStack(GTK4ZStackDescriptor(
                alignment: gtkAlignmentDescriptor(alignment))),
            children: childDescs)
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let children = gtkRenderChildren(content)
            .map(widgetFromOpaque)
            .filter { !gtkIsEmptyViewWidget($0) }
        if children.isEmpty {
            return opaqueFromWidget(gtkCreateEmptyViewWidget())
        }
        if !gtkIsRenderingRowContent, gtkCanUseSharedZStackLayout(children) {
            return gtkRenderSharedZStack(children, alignment: alignment)
        }

        return gtkRenderFallbackZStack(children, alignment: alignment)
    }
}

private func gtkCanUseSharedZStackLayout(_ children: [UnsafeMutablePointer<GtkWidget>]) -> Bool {
    for widget in children {
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            return false
        }
        if gtk_widget_get_hexpand(widget) != 0 || gtk_widget_get_vexpand(widget) != 0 {
            return false
        }
    }
    return true
}

private func gtkRenderSharedZStack(
    _ children: [UnsafeMutablePointer<GtkWidget>],
    alignment: Alignment
) -> OpaquePointer {
    let wrapper = gtk_swift_fixed_new()!
    let context = GTKLayoutMeasureContext(widgets: children)
    let layout = computeZStackLayout(
        subviews: children.indices.map(LayoutSubview.init(index:)),
        context: context,
        alignment: alignment
    )

    gtk_widget_set_size_request(
        wrapper,
        gint(layout.containerSize.width),
        gint(layout.containerSize.height)
    )

    for (widget, placement) in zip(children, layout.childPlacements) {
        gtk_widget_set_halign(widget, GTK_ALIGN_START)
        gtk_widget_set_valign(widget, GTK_ALIGN_START)
        gtk_swift_fixed_put(wrapper, widget, placement.origin.x, placement.origin.y)
    }

    return opaqueFromWidget(wrapper)
}

private func gtkRenderFallbackZStack(
    _ children: [UnsafeMutablePointer<GtkWidget>],
    alignment: Alignment
) -> OpaquePointer {
    let overlay = gtk_overlay_new()!
    let (hAlign, vAlign) = gtkAlignFromAlignment(alignment)
    var first = true
    var hasVerticalFillIntent = false
    for widget in children {
        if gtkHasVerticalFillIntent(widget) {
            hasVerticalFillIntent = true
        }
        if first {
            gtk_overlay_set_child(OpaquePointer(overlay), widget)
            // Propagate first child's expand to the overlay
            if gtk_widget_get_hexpand(widget) != 0 {
                gtk_widget_set_hexpand(overlay, 1)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                gtk_widget_set_vexpand(overlay, 1)
            }
            first = false
        } else {
            let overlayWantsVerticalFill =
                gtk_widget_get_vexpand(widget) != 0 && gtkHasVerticalFillIntent(widget)
            // Align non-expanding overlays according to the ZStack alignment.
            if gtk_widget_get_hexpand(widget) == 0 {
                gtk_widget_set_halign(widget, hAlign)
            }
            if overlayWantsVerticalFill {
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            } else {
                gtk_widget_set_vexpand(widget, 0)
                gtk_widget_set_valign(widget, vAlign)
            }
            gtk_overlay_add_overlay(OpaquePointer(overlay), widget)
            gtk_swift_overlay_set_measure_overlay(overlay, widget, 1)
        }
    }
    if hasVerticalFillIntent {
        gtkMarkVerticalFillIntent(overlay)
    }
    return opaqueFromWidget(overlay)
}

extension Group: GTKRenderable where Content: View {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        var needsHExpand = false
        var needsVExpand = false
        var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []
        for child in gtkRenderChildren(content) {
            let widget = widgetFromOpaque(child)
            if gtkIsEmptyViewWidget(widget) { continue }
            renderedChildren.append(widget)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        if renderedChildren.isEmpty {
            return opaqueFromWidget(gtkCreateEmptyViewWidget())
        }
        gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
        if needsVExpand { gtk_widget_set_vexpand(box, 1) }
        return opaqueFromWidget(box)
    }
}

extension ForEach: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: String(describing: type(of: self)),
            children: data.map { item in
                gtkWithStateIdentityNamespaceComponent(
                    gtkForEachStateIdentityComponent(for: item[keyPath: id])
                ) {
                    gtkDescribeView(content(item))
                }
            }
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        var needsHExpand = false
        var needsVExpand = false
        for item in data {
            let widget = widgetFromOpaque(
                gtkWithStateIdentityNamespaceComponent(
                    gtkForEachStateIdentityComponent(for: item[keyPath: id])
                ) {
                    gtkRenderView(content(item))
                }
            )
            // SwiftUI lays repeated vertical rows against the parent's
            // proposed width. This keeps ScrollView/List rows from collapsing
            // to their natural text width and then being centered.
            needsHExpand = true
            gtk_widget_set_hexpand(widget, 1)
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
        if needsVExpand { gtk_widget_set_vexpand(box, 1) }
        return opaqueFromWidget(box)
    }
}

extension AnyView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkRenderAnyView(wrapped)
    }
}

extension _ConditionalView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        switch self {
        case .trueContent(let view): return gtkRenderView(view)
        case .falseContent(let view): return gtkRenderView(view)
        }
    }
}

extension Optional: GTKRenderable where Wrapped: View {
    public func gtkCreateWidget() -> OpaquePointer {
        switch self {
        case .some(let view): return gtkRenderView(view)
        case .none: return opaqueFromWidget(gtkCreateEmptyViewWidget())
        }
    }
}

// MARK: - Modifier GTK extensions

extension PaddedView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .padding, typeName: "PaddedView",
            props: .padding(GTK4PaddingDescriptor(
                top: top, bottom: bottom, leading: leading, trailing: trailing)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let child = widgetFromOpaque(gtkRenderView(content))
        if gtkIsEmptyViewWidget(child) {
            return opaqueFromWidget(child)
        }
        let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        // Use GTK widget margins (not CSS padding) for the spacing. CSS
        // padding-X in GTK4 interacts poorly with hexpand-distributed
        // GtkBox allocations: children that inherit expand through a
        // CSS-padded wrapper end up shrunk by the padding amount during
        // natural-size distribution, producing an unfilled gap in HStacks
        // like the LayoutStress dashboard cards. Margins on the inner
        // child are respected by measurement and don't hit that path.
        gtk_widget_set_margin_top(child, gint(top))
        gtk_widget_set_margin_bottom(child, gint(bottom))
        gtk_widget_set_margin_start(child, gint(leading))
        gtk_widget_set_margin_end(child, gint(trailing))
        // PaddedView must let expanding content fill its margin wrapper.
        // This is what carries a fixed frame's proposed width into a
        // padded VStack/HStack instead of clipping Spacer-based rows at
        // their natural size.
        if gtk_widget_get_hexpand(child) != 0 {
            gtk_widget_set_hexpand(wrapper, 1)
            gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        }
        if gtk_widget_get_vexpand(child) != 0 {
            gtk_widget_set_vexpand(wrapper, 1)
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        }
        gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)
        gtkMarkHostedNodeKind(wrapper, kind: .padding)
        gtk_box_append(boxPointer(wrapper), child)
        return opaqueFromWidget(wrapper)
    }
}

extension FrameView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .frame, typeName: "FrameView",
            props: .frame(GTK4FrameDescriptor(
                width: width, height: height,
                minWidth: minWidth, minHeight: minHeight,
                maxWidth: maxWidth, maxHeight: maxHeight,
                alignment: gtkAlignmentDescriptor(alignment))),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let child = widgetFromOpaque(gtkRenderView(content))
        if gtkIsEmptyViewWidget(child) {
            return opaqueFromWidget(child)
        }
        let childExpH = gtk_widget_get_hexpand(child) != 0
        let childExpV = gtk_widget_get_vexpand(child) != 0

        // Detect when the frame constrains one axis but the child wants to
        // expand on the unconstrained axis.  GtkFixed positions children at
        // fixed coordinates computed at creation time, so it can't propagate
        // the parent's allocation to the child.  Use a plain GtkBox wrapper
        // in these cases so GTK's expand/fill system handles the flexible axis.
        let heightFree = height == nil && minHeight == nil && maxHeight == nil
        let widthFree  = width == nil && minWidth == nil && (maxWidth == nil || maxWidth == .infinity)
        let widthMayGrowWithParent = width == nil
            && (
                (maxWidth != nil)
                || (maxWidth == nil && childExpH)
            )
        let heightMayGrowWithParent = height == nil
            && (
                (maxHeight != nil)
                || (maxHeight == nil && childExpV)
            )

        if !widthFree && heightFree && childExpV {
            // Width-constrained, height-flexible, child expands vertically.
            // Example: Color.blue.frame(width: 120) inside an HStack.
            return gtkFrameFlexibleAxis(child: child, childExpH: childExpH,
                                        constrainedWidth: true)
        }
        if widthFree && !heightFree && childExpH {
            // Height-constrained, width-flexible, child expands horizontally.
            return gtkFrameFlexibleAxis(child: child, childExpH: childExpH,
                                        constrainedWidth: false)
        }

        if widthMayGrowWithParent || heightMayGrowWithParent {
            return gtkFrameParentFlexibleAxes(
                child: child,
                childExpH: childExpH,
                childExpV: childExpV
            )
        }

        // General case: use GtkFixed for alignment positioning.
        let wrapper = gtk_swift_fixed_new()!
        let naturalSize = gtkMeasureWidgetNaturalSize(child)
        let layout = computeFrameLayout(
            childNaturalSize: naturalSize,
            width: width,
            height: height,
            minWidth: minWidth,
            minHeight: minHeight,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            alignment: alignment,
            expandsToFillWidth: childExpH || (width == nil && maxWidth != nil && maxWidth != .infinity),
            expandsToFillHeight: childExpV || (height == nil && maxHeight != nil && maxHeight != .infinity)
        )
        let clampsChild =
            layout.childPlacement.size.width < naturalSize.width
            || layout.childPlacement.size.height < naturalSize.height
        // Fixed-frame clipping uses a normal GtkBox allocation.
        // GtkScrolledWindow preserves the child's wider natural width
        // internally, which breaks SwiftUI Spacer rows inside clipped
        // fixed-width sheets.
        let slot: UnsafeMutablePointer<GtkWidget> = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!

        // Expanding fixed-frame children receive the proposed frame size
        // even when the child does not need clipping. Otherwise a padded
        // VStack/HStack can keep its natural width and lose trailing
        // Spacer-aligned controls.
        if childExpH || childExpV {
            gtk_widget_set_size_request(
                child,
                childExpH ? gtkPixelSize(layout.childPlacement.size.width) : -1,
                childExpV ? gtkPixelSize(layout.childPlacement.size.height) : -1
            )
        }

        // Expanding children should fill the slot; non-expanding ones
        // are positioned by GtkFixed placement math.
        gtk_widget_set_halign(child, childExpH ? GTK_ALIGN_FILL : GTK_ALIGN_START)
        gtk_widget_set_valign(child, childExpV ? GTK_ALIGN_FILL : GTK_ALIGN_START)
        gtk_widget_set_halign(slot, GTK_ALIGN_START)
        gtk_widget_set_valign(slot, GTK_ALIGN_START)
        if clampsChild {
            gtk_widget_set_overflow(wrapper, GTK_OVERFLOW_HIDDEN)
            // SwiftUI proposes the clamped fixed-frame size to children.
            // Without this, HStacks with Spacer() inside fixed-width
            // sheets keep their oversized natural width and GTK clips
            // trailing controls such as Close/New/Edit/Delete buttons.
            gtk_widget_set_size_request(
                child,
                gtkPixelSize(layout.childPlacement.size.width),
                gtkPixelSize(layout.childPlacement.size.height)
            )
        }
        gtk_widget_set_size_request(
            slot,
            gtkPixelSize(layout.childPlacement.size.width),
            gtkPixelSize(layout.childPlacement.size.height)
        )
        gtk_widget_set_size_request(
            wrapper,
            gtkPixelSize(layout.containerSize.width),
            gtkPixelSize(layout.containerSize.height)
        )

        if width != nil {
            gtk_widget_set_hexpand(wrapper, 0)
        }
        if height != nil {
            gtk_widget_set_vexpand(wrapper, 0)
        }
        if maxWidth != nil {
            gtk_widget_set_hexpand(wrapper, 1)
        }
        if maxHeight != nil {
            gtk_widget_set_vexpand(wrapper, 1)
            gtkMarkVerticalFillIntent(wrapper)
        }
        // Propagate child expand flags to wrapper when the frame doesn't
        // constrain that axis.  Without this, a Spacer inside an HStack
        // inside .frame(height:) loses its horizontal expansion.
        if width == nil && maxWidth == nil && gtk_widget_get_hexpand(child) != 0 {
            gtk_widget_set_hexpand(wrapper, 1)
        }
        if height == nil && maxHeight == nil && gtk_widget_get_vexpand(child) != 0 {
            gtk_widget_set_vexpand(wrapper, 1)
            if gtkHasVerticalFillIntent(child) {
                gtkMarkVerticalFillIntent(wrapper)
            }
        }
        gtk_box_append(boxPointer(slot), child)
        gtk_swift_fixed_put(
            wrapper,
            slot,
            layout.childPlacement.origin.x,
            layout.childPlacement.origin.y
        )
        gtk_swift_fixed_move(
            wrapper,
            slot,
            layout.childPlacement.origin.x,
            layout.childPlacement.origin.y
        )
        return opaqueFromWidget(wrapper)
    }

    /// Build a frame wrapper for cases where the parent may later allocate
    /// extra space on one or both axes (`maxWidth/maxHeight == .infinity`),
    /// but the child itself does not expand on that axis. GtkFixed computes
    /// placement once at creation time, so it cannot recenter/realign the
    /// child when the wrapper grows later. A GtkBox-based wrapper keeps the
    /// child aligned inside the live parent allocation.
    private func gtkFrameParentFlexibleAxes(
        child: UnsafeMutablePointer<GtkWidget>,
        childExpH: Bool,
        childExpV: Bool
    ) -> OpaquePointer {
        let naturalSize = gtkMeasureWidgetNaturalSize(child)
        let layout = computeFrameLayout(
            childNaturalSize: naturalSize,
            width: width,
            height: height,
            minWidth: minWidth,
            minHeight: minHeight,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            alignment: alignment,
            expandsToFillWidth: childExpH || (width == nil && maxWidth != nil && maxWidth != .infinity),
            expandsToFillHeight: childExpV || (height == nil && maxHeight != nil && maxHeight != .infinity)
        )

        let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!

        let widthMayGrowWithParent = width == nil
            && (
                (maxWidth != nil)
                || (maxWidth == nil && childExpH)
            )
        let heightMayGrowWithParent = height == nil
            && (
                (maxHeight != nil)
                || (maxHeight == nil && childExpV)
            )

        if !widthMayGrowWithParent && heightMayGrowWithParent && childExpV {
            return gtkFrameFixedWidthFlexibleHeightClip(
                child: child,
                width: gtkPixelSize(layout.containerSize.width)
            )
        }

        let requestWidth = widthMayGrowWithParent
            ? minWidth.map(gtkPixelSize) ?? -1
            : gtkPixelSize(layout.containerSize.width)
        let requestHeight = heightMayGrowWithParent
            ? minHeight.map(gtkPixelSize) ?? -1
            : gtkPixelSize(layout.containerSize.height)
        if widthMayGrowWithParent && !heightMayGrowWithParent {
            return gtkFrameFlexibleWidthFixedHeightClip(
                child: child,
                height: gtkPixelSize(layout.containerSize.height)
            )
        }
        gtk_widget_set_size_request(wrapper, requestWidth, requestHeight)
        if childExpH || childExpV {
            gtk_widget_set_size_request(
                child,
                childExpH && !widthMayGrowWithParent ? gtkPixelSize(layout.childPlacement.size.width) : -1,
                childExpV && !heightMayGrowWithParent ? gtkPixelSize(layout.childPlacement.size.height) : -1
            )
        }
        if widthMayGrowWithParent {
            gtk_widget_set_hexpand(wrapper, 1)
        } else {
            // Prevent flexible children such as Color from making an
            // explicitly width-constrained frame participate as flexible
            // space in a parent HStack.
            gtk_widget_set_hexpand(wrapper, 0)
        }
        if heightMayGrowWithParent {
            gtk_widget_set_vexpand(wrapper, 1)
            if maxHeight != nil || gtkHasVerticalFillIntent(child) {
                gtkMarkVerticalFillIntent(wrapper)
            }
        } else {
            // Explicit 0: alignment spacers inside the wrapper have
            // vexpand=1 for internal vertical centering. Without an
            // explicit value, GTK auto-computes vexpand from children
            // and inherits the spacers' expansion — leaking vexpand
            // to the parent container.
            gtk_widget_set_vexpand(wrapper, 0)
        }

        let horizontalAlign: GtkAlign
        if childExpH {
            horizontalAlign = GTK_ALIGN_FILL
            gtk_widget_set_hexpand(child, 1)
        } else {
            switch alignment {
            case .topLeading, .leading, .bottomLeading:
                horizontalAlign = GTK_ALIGN_START
            case .top, .center, .bottom:
                horizontalAlign = GTK_ALIGN_CENTER
            case .topTrailing, .trailing, .bottomTrailing:
                horizontalAlign = GTK_ALIGN_END
            }
        }
        gtk_widget_set_halign(child, horizontalAlign)

        if childExpV {
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
            gtk_widget_set_vexpand(child, heightMayGrowWithParent ? 1 : 0)
            gtk_box_append(boxPointer(wrapper), child)
            let output = heightMayGrowWithParent && maxHeight == .infinity
                ? gtkCompressibleHeightClamp(wrapper)
                : wrapper
            return opaqueFromWidget(output)
        }

        if heightMayGrowWithParent {
            switch alignment {
            case .topLeading, .top, .topTrailing:
                gtk_box_append(boxPointer(wrapper), child)
            case .leading, .center, .trailing:
                let topSpacer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                let bottomSpacer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                gtkMarkLayoutHelper(topSpacer)
                gtkMarkLayoutHelper(bottomSpacer)
                gtk_widget_set_vexpand(topSpacer, 1)
                gtk_widget_set_vexpand(bottomSpacer, 1)
                gtk_box_append(boxPointer(wrapper), topSpacer)
                gtk_box_append(boxPointer(wrapper), child)
                gtk_box_append(boxPointer(wrapper), bottomSpacer)
            case .bottomLeading, .bottom, .bottomTrailing:
                let topSpacer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                gtkMarkLayoutHelper(topSpacer)
                gtk_widget_set_vexpand(topSpacer, 1)
                gtk_box_append(boxPointer(wrapper), topSpacer)
                gtk_box_append(boxPointer(wrapper), child)
            }
        } else {
            // Height is fixed (minHeight / height pinned the wrapper at
            // `layout.containerSize.height`), but the child's natural
            // height may be smaller. GtkBox packs children from the
            // start of its packing axis and doesn't honor `valign` on
            // children along that axis, so just appending leaves the
            // child visually top-aligned even if the wrapper has
            // plenty of extra height. Insert vexpand spacers to split
            // the extra space according to the frame's alignment
            // intent — matching SwiftUI's default of centering when
            // the frame is larger than content.
            switch alignment {
            case .topLeading, .top, .topTrailing:
                gtk_box_append(boxPointer(wrapper), child)
            case .leading, .center, .trailing:
                let topSpacer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                let bottomSpacer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                gtkMarkLayoutHelper(topSpacer)
                gtkMarkLayoutHelper(bottomSpacer)
                gtk_widget_set_vexpand(topSpacer, 1)
                gtk_widget_set_vexpand(bottomSpacer, 1)
                gtk_box_append(boxPointer(wrapper), topSpacer)
                gtk_box_append(boxPointer(wrapper), child)
                gtk_box_append(boxPointer(wrapper), bottomSpacer)
            case .bottomLeading, .bottom, .bottomTrailing:
                let topSpacer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                gtkMarkLayoutHelper(topSpacer)
                gtk_widget_set_vexpand(topSpacer, 1)
                gtk_box_append(boxPointer(wrapper), topSpacer)
                gtk_box_append(boxPointer(wrapper), child)
            }
        }

        let output = heightMayGrowWithParent && maxHeight == .infinity
            ? gtkCompressibleHeightClamp(wrapper)
            : wrapper
        return opaqueFromWidget(output)
    }

    private func gtkFrameFlexibleWidthFixedHeightClip(
        child: UnsafeMutablePointer<GtkWidget>,
        height: gint
    ) -> OpaquePointer {
        let scrolled = gtk_scrolled_window_new()!
        let scrolledOp = OpaquePointer(scrolled)
        gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL)
        gtk_scrolled_window_set_has_frame(scrolledOp, 0)
        gtk_scrolled_window_set_min_content_height(scrolledOp, height)
        gtk_scrolled_window_set_max_content_height(scrolledOp, height)
        gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
        gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)

        gtk_widget_set_hexpand(scrolled, 1)
        gtk_widget_set_vexpand(scrolled, 0)
        gtk_widget_set_hexpand(child, 1)
        gtk_widget_set_vexpand(child, 0)
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        gtk_widget_set_size_request(child, -1, height)
        gtk_scrolled_window_set_child(scrolledOp, child)
        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: true,
            fillHeight: false
        )
        return opaqueFromWidget(scrolled)
    }

    private func gtkFrameFixedWidthFlexibleHeightClip(
        child: UnsafeMutablePointer<GtkWidget>,
        width: gint
    ) -> OpaquePointer {
        let scrolled = gtk_scrolled_window_new()!
        let scrolledOp = OpaquePointer(scrolled)
        gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL)
        gtk_scrolled_window_set_has_frame(scrolledOp, 0)
        gtk_scrolled_window_set_min_content_width(scrolledOp, width)
        gtk_scrolled_window_set_max_content_width(scrolledOp, width)
        gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
        gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)

        gtk_widget_set_size_request(scrolled, width, -1)
        gtk_widget_set_hexpand(scrolled, 0)
        gtk_widget_set_vexpand(scrolled, 1)
        gtk_widget_set_hexpand(child, 1)
        gtk_widget_set_vexpand(child, 1)
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        gtk_widget_set_size_request(child, width, -1)
        gtk_scrolled_window_set_child(scrolledOp, child)
        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: true,
            fillHeight: true
        )
        if gtkHasVerticalFillIntent(child) {
            gtkMarkVerticalFillIntent(scrolled)
        }
        return opaqueFromWidget(scrolled)
    }

    /// Build a frame wrapper using GtkBox instead of GtkFixed, for frames
    /// that constrain one axis while the child expands on the other.
    /// GtkFixed can't propagate allocation to children, so we let GTK's
    /// expand/fill system handle the flexible axis naturally.
    private func gtkFrameFlexibleAxis(
        child: UnsafeMutablePointer<GtkWidget>,
        childExpH: Bool,
        constrainedWidth: Bool
    ) -> OpaquePointer {
        let naturalSize = gtkMeasureWidgetNaturalSize(child)
        let layout = computeFrameLayout(
            childNaturalSize: naturalSize,
            width: width,
            height: height,
            minWidth: minWidth,
            minHeight: minHeight,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            alignment: alignment,
            expandsToFillWidth: childExpH || (width == nil && maxWidth != nil && maxWidth != .infinity),
            expandsToFillHeight: gtk_widget_get_vexpand(child) != 0 || (height == nil && maxHeight != nil && maxHeight != .infinity)
        )

        // Use GtkBox as wrapper — child fills the flexible axis via expand.
        let orientation = constrainedWidth ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
        let wrapper = gtk_box_new(orientation, 0)!

        if constrainedWidth {
            // Width constrained, height flexible
            return gtkFrameFixedWidthFlexibleHeightClip(
                child: child,
                width: gtkPixelSize(layout.containerSize.width)
            )
        } else {
            // Height constrained, width flexible
            gtk_widget_set_size_request(wrapper, -1, gtkPixelSize(layout.containerSize.height))
            let vexp: gint = (maxHeight != nil) ? 1 : 0
            gtk_widget_set_hexpand(wrapper, 1)
            gtk_widget_set_vexpand(wrapper, vexp)
            if maxHeight != nil {
                gtkMarkVerticalFillIntent(wrapper)
            }
        }

        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        gtk_box_append(boxPointer(wrapper), child)

        return opaqueFromWidget(wrapper)
    }
}

private func gtkMeasureWidgetNaturalSize(_ widget: UnsafeMutablePointer<GtkWidget>) -> ViewSize {
    var widthMin: Int32 = 0
    var widthNat: Int32 = 0
    var heightMin: Int32 = 0
    var heightNat: Int32 = 0
    gtk_swift_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, &widthMin, &widthNat)
    gtk_swift_widget_measure(widget, GTK_ORIENTATION_VERTICAL, -1, &heightMin, &heightNat)
    let width = max(widthMin, widthNat)
    let height = max(heightMin, heightNat)
    return ViewSize(width: Double(width), height: Double(height))
}

private func gtkCompressibleHeightClamp(
    _ child: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let wrapper = gtk_swift_compressible_height_clamp_new(child)!
    if gtk_widget_get_hexpand(child) != 0 {
        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
    }
    if gtk_widget_get_vexpand(child) != 0 {
        gtk_widget_set_vexpand(wrapper, 1)
        gtk_widget_set_valign(wrapper, GTK_ALIGN_FILL)
    }
    gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)
    return wrapper
}

private func gtkCompressibleProposalClamp(
    _ child: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let heightWrapper = gtkCompressibleHeightClamp(child)
    let widthWrapper = gtk_swift_compressible_width_clamp_new(heightWrapper)!
    if gtk_widget_get_hexpand(heightWrapper) != 0 {
        gtk_widget_set_hexpand(widthWrapper, 1)
        gtk_widget_set_halign(widthWrapper, GTK_ALIGN_FILL)
    }
    if gtk_widget_get_vexpand(heightWrapper) != 0 {
        gtk_widget_set_vexpand(widthWrapper, 1)
        gtk_widget_set_valign(widthWrapper, GTK_ALIGN_FILL)
    }
    gtkPropagateSingleChildLayoutMarkers(from: [heightWrapper], to: widthWrapper)
    return widthWrapper
}

extension ForegroundColorView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .foregroundColor, typeName: "ForegroundColorView",
            props: .foregroundColor(gtkColorDescriptor(color)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = gtkWithCurrentForegroundColor(color) {
            widgetFromOpaque(gtkRenderView(content))
        }
        applyCSSToWidget(widget, properties: "color: \(color.hex);")
        return opaqueFromWidget(widget)
    }
}

extension OptionalForegroundColorView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        guard let color else {
            return gtkDescribeView(content)
        }
        return content.foregroundColor(color).gtkDescribeNode()
    }

    public func gtkCreateWidget() -> OpaquePointer {
        guard let color else {
            return gtkRenderView(content)
        }
        return content.foregroundColor(color).gtkCreateWidget()
    }
}

extension BackgroundView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        if let color = background as? Color {
            return GTK4DescriptorNode(
                kind: .background, typeName: "BackgroundView",
                props: .background(gtkColorDescriptor(color)),
                children: [gtkDescribeView(content)])
        }

        if gtkCanRenderNativeBackground(background) {
            return GTK4DescriptorNode(
                kind: .background, typeName: "BackgroundView",
                props: .backgroundLayout(GTK4BackgroundLayoutDescriptor(
                    alignment: gtkAlignmentDescriptor(alignment))),
                children: [
                    gtkDescribeView(content),
                    gtkDescribeView(background),
                ])
        }

        return gtkDescribeView(ZStack(alignment: alignment) {
            self.background
            content
        })
    }

	    public func gtkCreateWidget() -> OpaquePointer {
	        if let color = background as? Color {
	            let widget = widgetFromOpaque(gtkRenderView(content))
	            if gtkIsEmptyViewWidget(widget) {
	                return opaqueFromWidget(widget)
            }
            applyCSSToWidget(widget, properties: "background-color: \(color.hex);")
            return opaqueFromWidget(widget)
        }

        if gtkCanRenderNativeBackground(background) {
            return gtkRenderBackground(content: content, background: background, alignment: alignment)
        }

	        let contentWidget = widgetFromOpaque(gtkRenderView(content))
	        if gtkIsEmptyViewWidget(contentWidget) {
	            return opaqueFromWidget(contentWidget)
	        }
        let backgroundTapActionBox = gtkPrimaryTapAction(inAny: background).map {
            GTKTapGestureActionBox(
                requiredCount: 1,
                action: $0,
                source: String(reflecting: Swift.type(of: background))
            )
        }
	        if let backgroundTapActionBox {
	            gtkAttachTapGestureActionData(to: contentWidget, box: backgroundTapActionBox)
	        }
	        let fallback = gtkRenderFallbackBackground(
	            contentWidget: contentWidget,
	            background: background,
	            alignment: alignment
	        )
	        if let backgroundTapActionBox {
	            gtkAttachTapGestureActionData(to: widgetFromOpaque(fallback), box: backgroundTapActionBox)
	        }
	        return fallback
    }
}

private func gtkCanRenderNativeBackground<Background: View>(_ background: Background) -> Bool {
    background is FilledShape<RoundedRectangle>
        || background is FilledShape<Rectangle>
        || background is FilledShape<Capsule>
}

private func gtkRenderBackground<Content: View, Background: View>(
    content: Content,
    background: Background,
    alignment: Alignment
) -> OpaquePointer {
    let contentWidget = widgetFromOpaque(gtkRenderView(content))
    if gtkIsEmptyViewWidget(contentWidget) {
        return opaqueFromWidget(contentWidget)
    }

    if let rounded = background as? FilledShape<RoundedRectangle> {
        return gtkRenderFilledShapeBackground(
            contentWidget: contentWidget,
            color: rounded.color,
            cornerRadius: rounded.shape.cornerRadius
        )
    }

    if let rectangle = background as? FilledShape<Rectangle> {
        return gtkRenderFilledShapeBackground(
            contentWidget: contentWidget,
            color: rectangle.color,
            cornerRadius: 0
        )
    }

    if let capsule = background as? FilledShape<Capsule> {
        return gtkRenderFilledShapeBackground(
            contentWidget: contentWidget,
            color: capsule.color,
            cornerRadius: 9999
        )
    }

    return gtkRenderFallbackBackground(
        contentWidget: contentWidget,
        background: background,
        alignment: alignment
    )
}

private func gtkRenderFallbackBackground<Background: View>(
    contentWidget: UnsafeMutablePointer<GtkWidget>,
    background: Background,
    alignment: Alignment
) -> OpaquePointer {
    let backgroundWidget = widgetFromOpaque(gtkRenderView(background))
    if gtkIsEmptyViewWidget(backgroundWidget) {
        return opaqueFromWidget(contentWidget)
    }
    return gtkRenderFallbackZStack([backgroundWidget, contentWidget], alignment: alignment)
}

private func gtkRenderFilledShapeBackground(
    contentWidget: UnsafeMutablePointer<GtkWidget>,
    color: Color,
    cornerRadius: Double
) -> OpaquePointer {
    let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    if gtk_widget_get_hexpand(contentWidget) != 0 {
        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
    }
    if gtk_widget_get_vexpand(contentWidget) != 0 {
        gtk_widget_set_vexpand(wrapper, 1)
        gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)
    }
    gtkPropagateSingleChildLayoutMarkers(from: [contentWidget], to: wrapper)

    let css: String
    if cornerRadius > 0 {
        css = String(
            format: "background-color: rgba(%d, %d, %d, %.3f); border-radius: %.1fpx;",
            Int(color.red * 255),
            Int(color.green * 255),
            Int(color.blue * 255),
            color.alpha,
            cornerRadius
        )
    } else {
        css = String(
            format: "background-color: rgba(%d, %d, %d, %.3f);",
            Int(color.red * 255),
            Int(color.green * 255),
            Int(color.blue * 255),
            color.alpha
        )
    }
    applyCSSToWidget(wrapper, properties: css)
    gtk_box_append(boxPointer(wrapper), contentWidget)
    return opaqueFromWidget(wrapper)
}

extension FontModifiedView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .font, typeName: "FontModifiedView",
            props: .font(GTK4FontDescriptor(font: font)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        let css = gtkFontCSS(font)
        applyCSSToWidget(
            widget,
            properties: css.properties,
            descendantSelectors: gtkFontDescendantSelectors
        )
        if let designMarker = css.designMarker {
            gtk_widget_add_css_class(widget, designMarker)
        }
        return opaqueFromWidget(widget)
    }
}

private func gtkCSSFontSizePixels(forApplePointSize size: Double) -> Int {
    let pointSize = size
    if pointSize < 14 {
        return max(1, Int(pointSize.rounded()))
    }
    return max(1, Int((pointSize * 0.875).rounded()))
}

extension BorderView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .border, typeName: "BorderView",
            props: .border(GTK4BorderDescriptor(
                color: gtkColorDescriptor(color), width: width)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        applyCSSToWidget(widget, properties: "border: \(width)px solid \(color.hex);")
        return opaqueFromWidget(widget)
    }
}

// MARK: - Text Formatting GTK extensions

/// Collect all GtkLabel descendants in a widget subtree via DFS.
/// Text modifiers apply to every label in the subtree, not just the first,
/// so that container-level modifiers like VStack { ... }.lineLimit(1) work.
private func findAllGtkLabels(in widget: UnsafeMutablePointer<GtkWidget>) -> [UnsafeMutablePointer<GtkWidget>] {
    var result: [UnsafeMutablePointer<GtkWidget>] = []
    collectGtkLabels(in: widget, into: &result)
    return result
}

private func collectGtkLabels(in widget: UnsafeMutablePointer<GtkWidget>, into result: inout [UnsafeMutablePointer<GtkWidget>]) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    if typeName == "GtkLabel" {
        result.append(widget)
        return // GtkLabel has no label children
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        collectGtkLabels(in: c, into: &result)
        child = gtk_widget_get_next_sibling(c)
    }
}

extension LineLimitView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        for label in findAllGtkLabels(in: widget) {
            let labelOp = OpaquePointer(label)
            if let limit = lineLimit {
                if limit == 1 {
                    gtk_label_set_wrap(labelOp, 0)
                    gtk_label_set_lines(labelOp, 1)
                    // Default tail truncation for single-line, but don't
                    // overwrite an explicit truncation mode already set.
                    if gtk_label_get_ellipsize(labelOp) == PANGO_ELLIPSIZE_NONE {
                        gtk_label_set_ellipsize(labelOp, PANGO_ELLIPSIZE_END)
                    }
                    // Leave hexpand/halign alone. SwiftUI semantics for
                    // Text(...).lineLimit(1) is "draw at natural size;
                    // ellipsize only if the parent allocates less than
                    // natural." The label must not grab horizontal space
                    // — a trailing `Text(value).lineLimit(1)` inside a
                    // Spacer-packed HStack (e.g. a settings row) must
                    // stay at natural width and let the Spacer fill the
                    // gap so the value ends up right-aligned.
                    //
                    // `max-width-chars = -1` keeps the natural request
                    // at the full text width so short text displays in
                    // full; ellipsize kicks in only when the allocation
                    // is smaller than natural.
                    gtk_label_set_width_chars(labelOp, -1)
                    gtk_label_set_max_width_chars(labelOp, -1)
                } else {
                    gtk_label_set_wrap(labelOp, 1)
                    gtk_label_set_wrap_mode(labelOp, PANGO_WRAP_WORD_CHAR)
                    gtk_label_set_lines(labelOp, gint(limit))
                    // Default tail truncation for multi-line overflow, but
                    // don't overwrite an explicit truncation mode already set.
                    if gtk_label_get_ellipsize(labelOp) == PANGO_ELLIPSIZE_NONE {
                        gtk_label_set_ellipsize(labelOp, PANGO_ELLIPSIZE_END)
                    }
                }
            } else {
                // nil = unlimited wrapping — reset any prior line/ellipsis constraints
                gtk_label_set_wrap(labelOp, 1)
                gtk_label_set_wrap_mode(labelOp, PANGO_WRAP_WORD_CHAR)
                gtk_label_set_lines(labelOp, -1)
                gtk_label_set_ellipsize(labelOp, PANGO_ELLIPSIZE_NONE)
            }
        }
        return opaqueFromWidget(widget)
    }
}

extension TruncationModeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        for label in findAllGtkLabels(in: widget) {
            let labelOp = OpaquePointer(label)
            switch mode {
            case .head:   gtk_label_set_ellipsize(labelOp, PANGO_ELLIPSIZE_START)
            case .tail:   gtk_label_set_ellipsize(labelOp, PANGO_ELLIPSIZE_END)
            case .middle: gtk_label_set_ellipsize(labelOp, PANGO_ELLIPSIZE_MIDDLE)
            }
        }
        return opaqueFromWidget(widget)
    }
}

extension LineSpacingView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        let lineHeight = String(format: "%.1f", spacing)
        for label in findAllGtkLabels(in: widget) {
            applyCSSToWidget(label, properties: "line-height: calc(1em + \(lineHeight)px);")
        }
        return opaqueFromWidget(widget)
    }
}

extension MultilineTextAlignmentView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        for label in findAllGtkLabels(in: widget) {
            let labelOp = OpaquePointer(label)
            switch alignment {
            case .leading:
                gtk_label_set_justify(labelOp, GTK_JUSTIFY_LEFT)
                gtk_swift_label_set_xalign(label, 0)
            case .center:
                gtk_label_set_justify(labelOp, GTK_JUSTIFY_CENTER)
                gtk_swift_label_set_xalign(label, 0.5)
            case .trailing:
                gtk_label_set_justify(labelOp, GTK_JUSTIFY_RIGHT)
                gtk_swift_label_set_xalign(label, 1.0)
            }
        }
        return opaqueFromWidget(widget)
    }
}

// MARK: - fullScreenCover GTK extension

extension FullScreenCoverView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        // Use the host container as a stable anchor that survives rebuilds,
        // same pattern as SheetView. Falls back to the rendered widget if
        // not inside a rebuilding host.
        let anchor: UnsafeMutablePointer<GtkWidget>
        if let host = GTKViewHost.getCurrentRebuilding() {
            anchor = host.container
        } else {
            anchor = widget
        }
        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

        if isPresented.wrappedValue {
            // Prevent duplicate fullscreen window
            guard g_object_get_data(gobject, "swift-fullscreen-window") == nil else {
                return opaqueFromWidget(widget)
            }

            let window = gtk_window_new()!
            gtk_swift_window_set_modal(window, 1)

            // Set transient parent to the actual GtkWindow root
            if let rootWidget = gtk_widget_get_root(anchor) {
                let rootAsWidget = UnsafeMutableRawPointer(rootWidget)
                    .assumingMemoryBound(to: GtkWidget.self)
                gtk_swift_window_set_transient_for(window, rootAsWidget)
            }

            // Inject dismiss action
            let binding = isPresented
            let dismiss = onDismiss
            var env = getCurrentEnvironment()
            env.dismiss = DismissAction(handler: {
                binding.wrappedValue = false
            }, debugName: "gtk fullScreenCover")
            let prevEnv = getCurrentEnvironment()
            setCurrentEnvironment(env)
            let coverWidget = widgetFromOpaque(gtkRenderView(coverContent))
            setCurrentEnvironment(prevEnv)

            gtk_swift_window_set_child(window, coverWidget)
            gtk_swift_window_fullscreen(window)

            // Store the window on the anchor for programmatic dismissal
            g_object_set_data(gobject, "swift-fullscreen-window",
                              UnsafeMutableRawPointer(window))

            // Ref anchor for safe access in close callback
            g_object_ref(gpointer(anchor))
            let anchorWidget = anchor
            // Handle close-request (Escape, window close button)
            let closeBox = Unmanaged.passRetained(ClosureBox {
                binding.wrappedValue = false
                if gtk_swift_is_widget(anchorWidget) != 0 {
                    let obj = UnsafeMutableRawPointer(anchorWidget).assumingMemoryBound(to: GObject.self)
                    g_object_set_data(obj, "swift-fullscreen-window", nil)
                }
                g_object_unref(gpointer(anchorWidget))
                dismiss?()
            }).toOpaque()
            g_signal_connect_data(
                gpointer(window), "close-request",
                unsafeBitCast({ (_: gpointer?, ud: gpointer?) -> gboolean in
                    guard let ud = ud else { return 0 }
                    Unmanaged<ClosureBox>.fromOpaque(ud).takeUnretainedValue().closure()
                    return 0
                } as @convention(c) (gpointer?, gpointer?) -> gboolean,
                to: GCallback.self),
                closeBox,
                { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    guard let data = data else { return }
                    Unmanaged<ClosureBox>.fromOpaque(data).release()
                },
                GConnectFlags(rawValue: 0)
            )

            gtk_widget_set_visible(window, 1)
        } else {
            // Programmatic dismissal: destroy the fullscreen window
            if let raw = g_object_get_data(gobject, "swift-fullscreen-window") {
                let window = raw.assumingMemoryBound(to: GtkWidget.self)
                gtk_swift_window_destroy(window)
                g_object_set_data(gobject, "swift-fullscreen-window", nil)
                onDismiss?()
            }
        }

        return opaqueFromWidget(widget)
    }
}

// MARK: - onSubmit GTK extension

extension OnSubmitView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "OnSubmitView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.submitAction = SubmitAction(handler: action)
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(prev) }
        return gtkRenderView(content)
    }
}

// MARK: - onKeyPress GTK extension

extension OnKeyPressView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "OnKeyPressView",
            props: .text(GTK4TextDescriptor(content: String(key.character))),
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.keyPressActions.append(KeyPressAction(key: key, handler: action))
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(prev) }
        return gtkRenderView(content)
    }
}

// MARK: - Tag GTK extension

extension TagView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        setCurrentTagValue(tagValue)
        defer { clearCurrentTagValue() }
        return gtkRenderView(content)
    }
}

// MARK: - Aspect ratio GTK extension

extension AspectRatioView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        var css = ""
        if let ratio {
            css += "aspect-ratio: \(ratio);"
        }
        switch contentMode {
        case .fit:
            css += ""
        case .fill:
            css += ""
        }
        if !css.isEmpty {
            applyCSSToWidget(widget, properties: css)
        }
        return opaqueFromWidget(widget)
    }
}

// MARK: - Gradient GTK extensions

private func gtkGradientStopsCSS(_ stops: [Gradient.Stop]) -> String {
    stops.map { stop in
        let c = stop.color
        let r = Int(c.red * 255)
        let g = Int(c.green * 255)
        let b = Int(c.blue * 255)
        let a = c.alpha
        return "rgba(\(r), \(g), \(b), \(a)) \(Int(stop.location * 100))%"
    }.joined(separator: ", ")
}

extension LinearGradient: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let div = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(div, 1)
        gtk_widget_set_vexpand(div, 1)
        let sx = Int(startPoint.x * 100)
        let sy = Int(startPoint.y * 100)
        let ex = Int(endPoint.x * 100)
        let ey = Int(endPoint.y * 100)
        let stops = gtkGradientStopsCSS(gradient.stops)
        applyCSSToWidget(div, properties: "background: linear-gradient(from \(sx)% \(sy)% to \(ex)% \(ey)%, \(stops)); min-height: 20px;")
        return opaqueFromWidget(div)
    }
}

extension RadialGradient: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let div = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(div, 1)
        gtk_widget_set_vexpand(div, 1)
        let cx = Int(center.x * 100)
        let cy = Int(center.y * 100)
        let stops = gtkGradientStopsCSS(gradient.stops)
        applyCSSToWidget(div, properties: "background: radial-gradient(circle at \(cx)% \(cy)%, \(stops)); min-height: 20px;")
        return opaqueFromWidget(div)
    }
}

// MARK: - Text decoration GTK extensions

private let gtkSwiftOriginalLabelTextKey = "gtk-swift-original-label-text"

private final class WidgetStringBox {
    let value: String
    init(_ value: String) { self.value = value }
}

private func storeOriginalLabelTextIfNeeded(_ label: UnsafeMutablePointer<GtkWidget>) {
    let gobject = UnsafeMutableRawPointer(label).assumingMemoryBound(to: GObject.self)
    guard g_object_get_data(gobject, gtkSwiftOriginalLabelTextKey) == nil else { return }
    let current = String(cString: gtk_label_get_text(OpaquePointer(label)))
    let retained = Unmanaged.passRetained(WidgetStringBox(current)).toOpaque()
    g_object_set_data_full(gobject, gtkSwiftOriginalLabelTextKey, retained) { userData in
        Unmanaged<WidgetStringBox>.fromOpaque(userData!).release()
    }
}

private func originalLabelText(_ label: UnsafeMutablePointer<GtkWidget>) -> String? {
    let gobject = UnsafeMutableRawPointer(label).assumingMemoryBound(to: GObject.self)
    guard let raw = g_object_get_data(gobject, gtkSwiftOriginalLabelTextKey) else { return nil }
    return Unmanaged<WidgetStringBox>.fromOpaque(raw).takeUnretainedValue().value
}

extension BoldView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        applyCSSToWidget(widget, properties: "font-weight: bold;")
        return opaqueFromWidget(widget)
    }
}

extension ItalicView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        applyCSSToWidget(widget, properties: "font-style: italic;")
        return opaqueFromWidget(widget)
    }
}

extension FontWeightView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        let css: String?
        switch weight {
        case nil:         css = nil
        case .ultraLight: css = "font-weight: 100;"
        case .thin:       css = "font-weight: 200;"
        case .light:      css = "font-weight: 300;"
        case .regular:    css = "font-weight: 400;"
        case .medium:     css = "font-weight: 500;"
        case .semibold:   css = "font-weight: 600;"
        case .bold:       css = "font-weight: 700;"
        case .heavy:      css = "font-weight: 800;"
        case .black:      css = "font-weight: 900;"
        }
        if let css {
            applyCSSToWidget(widget, properties: css)
        }
        return opaqueFromWidget(widget)
    }
}

extension UnderlineView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        // GTK4 CSS does not support text-decoration. Use Pango attributes.
        for label in findAllGtkLabels(in: widget) {
            gtk_swift_label_set_underline(label, isActive ? 1 : 0)
        }
        return opaqueFromWidget(widget)
    }
}

extension StrikethroughView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        // GTK4 CSS does not support text-decoration. Use Pango attributes.
        for label in findAllGtkLabels(in: widget) {
            gtk_swift_label_set_strikethrough(label, isActive ? 1 : 0)
        }
        return opaqueFromWidget(widget)
    }
}

extension TextCaseView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        // GTK4 CSS does not support text-transform. Transform label text directly.
        // Skip markup labels — transforming markup source would break entities
        // like &amp; → &AMP; and potentially corrupt tag syntax.
        for label in findAllGtkLabels(in: widget) {
            guard gtk_swift_label_get_use_markup(label) == 0 else { continue }
            storeOriginalLabelTextIfNeeded(label)
            let base = originalLabelText(label)
                ?? String(cString: gtk_label_get_text(OpaquePointer(label)))
            switch textCase {
            case .uppercase?:
                gtk_swift_label_set_text(label, base.uppercased())
            case .lowercase?:
                gtk_swift_label_set_text(label, base.lowercased())
            case nil:
                gtk_swift_label_set_text(label, base)
            }
        }
        return opaqueFromWidget(widget)
    }
}

// MARK: - ScrollViewReader + ID GTK extensions

private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let targetID: AnyHashable?
    let anchor: UnitPoint?
    var remainingTicks: Int
    var remainingTotalTicks: Int

    init(
        target: UnsafeMutablePointer<GtkWidget>,
        targetID: AnyHashable? = nil,
        anchor: UnitPoint?,
        remainingTicks: Int = 180,
        remainingTotalTicks: Int = 600
    ) {
        self.target = target
        self.targetID = targetID
        self.anchor = anchor
        self.remainingTicks = remainingTicks
        self.remainingTotalTicks = remainingTotalTicks
    }
}

private struct GTKPendingScrollRequest {
    let anchor: UnitPoint?
}

private var gtkScrollTargetRegistry: [AnyHashable: UnsafeMutablePointer<GtkWidget>] = [:]
private var gtkPendingScrollRequests: [AnyHashable: GTKPendingScrollRequest] = [:]

private func gtkRegisterScrollTarget(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    g_object_ref(gpointer(widget))
    if let previous = gtkScrollTargetRegistry.updateValue(widget, forKey: id) {
        g_object_unref(gpointer(previous))
    }
    registerViewID(id, element: widget)
    gtkResolvePendingScrollTo(id: id, widget: widget)
}

private func gtkLookupLiveScrollTarget(_ id: AnyHashable) -> UnsafeMutablePointer<GtkWidget>? {
    if let widget = gtkScrollTargetRegistry[id] {
        if gtk_swift_is_widget(widget) != 0 {
            return widget
        }
        gtkScrollTargetRegistry.removeValue(forKey: id)
        g_object_unref(gpointer(widget))
    }

    guard let widget = lookupViewID(id) as? UnsafeMutablePointer<GtkWidget>,
          gtk_swift_is_widget(widget) != 0 else {
        return nil
    }
    return widget
}

private func gtkResolvePendingScrollTo(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    guard let request = gtkPendingScrollRequests.removeValue(forKey: id) else { return }
    gtkScheduleIdleScrollTo(id: id, widget, anchor: request.anchor)
}

private func gtkClampScrollValue(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}

@discardableResult
private func gtkApplyScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) -> Bool {
    guard gtk_swift_is_widget(target) != 0 else { return false }

    var fallbackVerticalApplied = false
    var parent = gtk_widget_get_parent(target)
    while let scrolled = parent {
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(scrolled)))
        if typeName == "GtkScrolledWindow" {
            let anchorPoint = anchor ?? .top
            let requiresVerticalAnchor = anchorPoint.y > 0.0
            let isSwiftUIVerticalScrollView = gtkIsSwiftUIVerticalScrollView(scrolled)
            var targetX = 0.0
            var targetY = 0.0
            let hasTargetCoordinates = gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY) != 0
            if !hasTargetCoordinates && anchorPoint.y < 1.0 {
                parent = gtk_widget_get_parent(scrolled)
                continue
            }

            var verticalApplied = false
            var horizontalApplied = false

            if let vadjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(vadjustment)
                let upper = gtk_adjustment_get_upper(vadjustment)
                let pageSize = gtk_adjustment_get_page_size(vadjustment)
                if upper - lower > pageSize + 1.0 {
                    let currentValue = gtk_adjustment_get_value(vadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                    if anchorPoint.y >= 1.0 {
                        gtk_adjustment_set_value(vadjustment, maxValue)
                    } else {
                        let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                        gtk_adjustment_set_value(
                            vadjustment,
                            gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                        )
                    }
                    verticalApplied = true
                }
            }

            if hasTargetCoordinates,
               !isSwiftUIVerticalScrollView,
               let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(hadjustment)
                let upper = gtk_adjustment_get_upper(hadjustment)
                let pageSize = gtk_adjustment_get_page_size(hadjustment)
                if upper - lower > pageSize + 1.0 {
                    let currentValue = gtk_adjustment_get_value(hadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetWidth = max(1.0, Double(gtk_widget_get_width(target)))
                    let desired = currentValue + targetX - ((pageSize - targetWidth) * anchorPoint.x)
                    gtk_adjustment_set_value(
                        hadjustment,
                        gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                    )
                    horizontalApplied = true
                }
            }

            if requiresVerticalAnchor {
                if verticalApplied && isSwiftUIVerticalScrollView { return true }
                if verticalApplied { fallbackVerticalApplied = true }
            } else if verticalApplied || horizontalApplied {
                return true
            }
        }
        parent = gtk_widget_get_parent(scrolled)
    }

    return fallbackVerticalApplied
}

private func gtkScheduleScrollTo(
    id: AnyHashable? = nil,
    _ target: UnsafeMutablePointer<GtkWidget>,
    anchor: UnitPoint?
) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, targetID: id, anchor: anchor)
    _ = g_timeout_add(16, { userData -> gboolean in
        guard let userData else { return 0 }
        let unmanaged = Unmanaged<GTKScrollToContext>.fromOpaque(userData)
        let context = unmanaged.takeUnretainedValue()
        let target = context.targetID.flatMap { gtkLookupLiveScrollTarget($0) } ?? context.target
        guard gtk_swift_is_widget(target) != 0 else {
            g_object_unref(gpointer(context.target))
            unmanaged.release()
            return 0
        }

        let applied = gtkApplyScrollTo(target, anchor: context.anchor)
        if applied {
            context.remainingTicks -= 1
        }
        context.remainingTotalTicks -= 1
        if context.remainingTicks > 0 && context.remainingTotalTicks > 0 { return 1 }

        g_object_unref(gpointer(context.target))
        unmanaged.release()
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

private func gtkScheduleIdleScrollTo(
    id: AnyHashable? = nil,
    _ target: UnsafeMutablePointer<GtkWidget>,
    anchor: UnitPoint?
) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, targetID: id, anchor: anchor)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKScrollToContext>.fromOpaque(userData).takeRetainedValue()
        defer { g_object_unref(gpointer(context.target)) }
        let target = context.targetID.flatMap { gtkLookupLiveScrollTarget($0) } ?? context.target
        guard gtk_swift_is_widget(target) != 0 else { return 0 }
        gtkApplyOrScheduleScrollTo(id: context.targetID, target, anchor: context.anchor)
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

private func gtkApplyOrScheduleScrollTo(
    id: AnyHashable? = nil,
    _ widget: UnsafeMutablePointer<GtkWidget>,
    anchor: UnitPoint?
) {
    _ = gtkApplyScrollTo(widget, anchor: anchor)
    gtkScheduleScrollTo(id: id, widget, anchor: anchor)
}

private func gtkExplicitIdentityComponent<ID: Hashable>(for id: ID) -> String {
    "Id[\(String(reflecting: AnyHashable(id)))]"
}

extension IdView: GTKRenderable, GTKDescribable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkWithStateIdentityNamespaceComponent(gtkExplicitIdentityComponent(for: id)) {
            let widget = widgetFromOpaque(gtkRenderView(content))
            let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
            gtk_box_append(boxPointer(wrapper), widget)
            gtkPropagateSingleChildLayoutMarkers(from: [widget], to: wrapper)
            if gtk_widget_get_hexpand(widget) != 0 {
                gtk_widget_set_hexpand(wrapper, 1)
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                gtk_widget_set_vexpand(wrapper, 1)
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtkRegisterScrollTarget(id: AnyHashable(id), widget: wrapper)
            return opaqueFromWidget(wrapper)
        }
    }

    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let component = gtkExplicitIdentityComponent(for: id)
        return gtkWithStateIdentityNamespaceComponent(component) {
            GTK4DescriptorNode(
                kind: .composite,
                typeName: "IdView<\(component)>",
                children: [gtkDescribeView(content)]
            )
        }
    }
}

extension ScrollViewReader: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let proxy = ScrollViewProxy()
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "ScrollViewReader",
            children: [gtkDescribeView(content(proxy))]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var proxy = ScrollViewProxy()
        proxy.scrollToAction = { anyID, anchor in
            if let widget = gtkLookupLiveScrollTarget(anyID) {
                gtkApplyOrScheduleScrollTo(id: anyID, widget, anchor: anchor)
            } else {
                gtkPendingScrollRequests[anyID] = GTKPendingScrollRequest(anchor: anchor)
            }
        }
        return gtkRenderView(content(proxy))
    }
}

// MARK: - Popover GTK extension

extension PopoverView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let anchor = widgetFromOpaque(gtkRenderView(content))
        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

        if isPresented.wrappedValue {
            // Prevent duplicate popover
            guard g_object_get_data(gobject, "swift-popover-widget") == nil else {
                return opaqueFromWidget(anchor)
            }

            let popover = gtk_popover_new()!
            let popChild = widgetFromOpaque(gtkRenderView(popoverContent))
            gtk_swift_popover_set_child(popover, popChild)
            gtk_widget_set_parent(popover, anchor)

            // Store the popover widget on the anchor so a rebuild with
            // isPresented=false can find and dismiss it programmatically.
            g_object_set_data(gobject, "swift-popover-widget",
                              UnsafeMutableRawPointer(popover))

            let binding = isPresented
            // Ref the anchor so the closed callback can safely write back
            // even if the anchor widget is destroyed before the popover closes.
            g_object_ref(gpointer(anchor))
            let anchorWidget = anchor
            // Dismiss on close — update binding and clear stored popover
            let dismissBox = Unmanaged.passRetained(ClosureBox {
                binding.wrappedValue = false
                // Check liveness before writing GObject data — the anchor
                // may have been finalized if this fires during teardown.
                if gtk_swift_is_widget(anchorWidget) != 0 {
                    let obj = UnsafeMutableRawPointer(anchorWidget).assumingMemoryBound(to: GObject.self)
                    g_object_set_data(obj, "swift-popover-widget", nil)
                }
                g_object_unref(gpointer(anchorWidget))
            }).toOpaque()
            g_signal_connect_data(
                gpointer(popover), "closed",
                unsafeBitCast({ (_: gpointer?, ud: gpointer?) in
                    guard let ud = ud else { return }
                    Unmanaged<ClosureBox>.fromOpaque(ud).takeUnretainedValue().closure()
                } as @convention(c) (gpointer?, gpointer?) -> Void,
                to: GCallback.self),
                dismissBox,
                { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    guard let data = data else { return }
                    Unmanaged<ClosureBox>.fromOpaque(data).release()
                },
                GConnectFlags(rawValue: 0)
            )

            gtk_swift_popover_popup(popover)
        } else {
            // Programmatic dismissal: if a popover was previously shown,
            // close it when the binding becomes false.
            if let raw = g_object_get_data(gobject, "swift-popover-widget") {
                let popover = raw.assumingMemoryBound(to: GtkWidget.self)
                gtk_swift_popover_popdown(popover)
                g_object_set_data(gobject, "swift-popover-widget", nil)
            }
        }

        return opaqueFromWidget(anchor)
    }
}

// MARK: - Layout modifier GTK extensions

extension PositionView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let child = widgetFromOpaque(gtkRenderView(content))
        let fixed = gtk_fixed_new()!
        // SwiftUI .position() centers the view at (x, y).
        // gtk_fixed_put places the top-left corner. Measure the child
        // and offset by half its natural size to center it.
        var natW: gint = 0
        var natH: gint = 0
        gtk_widget_measure(child, GTK_ORIENTATION_HORIZONTAL, -1, nil, &natW, nil, nil)
        gtk_widget_measure(child, GTK_ORIENTATION_VERTICAL, -1, nil, &natH, nil, nil)
        let cx = x - Double(natW) / 2
        let cy = y - Double(natH) / 2
        gtk_swift_fixed_put(fixed, child, cx, cy)
        return opaqueFromWidget(fixed)
    }
}

extension LayoutPriorityView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        // Priority value stored on the modifier — backends can read it
        // during stack layout. For now, pass through content unchanged.
        gtkRenderView(content)
    }
}

extension FixedSizeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let child = widgetFromOpaque(gtkRenderView(content))
        var widget = child
        // Lock the widget to its natural size so containers cannot shrink it.
        // Measure horizontal first, then measure vertical with the resolved
        // width so wrapping content gets the correct height.
        var reqW: gint = -1
        var reqH: gint = -1
        if horizontal {
            gtk_widget_measure(child, GTK_ORIENTATION_HORIZONTAL, -1, nil, &reqW, nil, nil)
        }
        if vertical {
            if horizontal {
                // Fully fixed content can be measured at its natural width.
                gtk_widget_measure(child, GTK_ORIENTATION_VERTICAL, reqW, nil, &reqH, nil, nil)
            } else {
                // SwiftUI's fixedSize(horizontal: false, vertical: true)
                // fixes vertical growth after the parent proposes a width.
                // Measuring at -1 here treats wrapped labels as one long
                // line, which clamps rows such as IceCubes status cells to a
                // single-line height. Resolve the fixed height once GTK has
                // allocated a concrete width to the widget.
                reqH = -1
            }
        }
        if !horizontal {
            gtk_widget_set_hexpand(child, 1)
            gtk_widget_set_halign(child, GTK_ALIGN_FILL)
            widget = gtk_swift_width_clamp_new(child)!
            gtkSetLayoutMarker(widget, key: gtkSwiftHorizontallyCompressibleFixedSizeMarker)
            reqW = 1
        }
        if reqW >= 0 || reqH >= 0 {
            gtk_widget_set_size_request(widget, reqW, reqH)
        }
        if !horizontal {
            gtk_widget_set_hexpand(widget, 1)
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        }
        if vertical && !horizontal {
            gtkInstallWidthResolvedHeight(on: widget)
        }
        return opaqueFromWidget(widget)
    }
}

// MARK: - contextMenu GTK extension

extension ContextMenuView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        // Build GMenu model + action group reusing the existing Menu pattern
        let actionGroup = g_simple_action_group_new()!
        let menuModel = gtk_swift_menu_new()!
        let actionBox = MenuActionBox()
        var actionIndex = 0

        gtkBuildMenuModel(elements: menuElements, menu: menuModel,
                          actionGroup: actionGroup, actionBox: actionBox,
                          actionIndex: &actionIndex)

        // Create popover menu from the model
        let popover = gtk_swift_popover_menu_new_from_model(menuModel)!
        gtk_widget_set_parent(popover, widget)

        // Attach action group to the content widget so menu items can resolve actions
        gtk_swift_widget_insert_action_group(widget, "menu", gpointer(actionGroup))

        // Attach actionBox for lifetime management
        let retained = Unmanaged.passRetained(actionBox).toOpaque()
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        g_object_set_data_full(gobject, "gtk-swift-context-actions", retained,
            { userData in Unmanaged<MenuActionBox>.fromOpaque(userData!).release() })

        // Right-click gesture (button 3) to show the popover at click position
        let gesture = gtk_gesture_click_new()!
        gtk_swift_gesture_single_set_button(gesture, 3)
        let popoverBox = Unmanaged.passRetained(DoubleDoubleClosureBox { x, y in
            gtk_swift_popover_set_pointing_to(popover, Int32(x), Int32(y), 1, 1)
            gtk_swift_popover_popup(popover)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(gesture), "pressed",
            unsafeBitCast({ (_: gpointer?, _: gint, x: Double, y: Double, ud: gpointer?) in
                guard let ud = ud else { return }
                Unmanaged<DoubleDoubleClosureBox>.fromOpaque(ud).takeUnretainedValue().closure(x, y)
            } as @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void,
            to: GCallback.self),
            popoverBox,
            { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                guard let data = data else { return }
                Unmanaged<DoubleDoubleClosureBox>.fromOpaque(data).release()
            },
            GConnectFlags(rawValue: 0)
        )
        gtk_swift_add_gesture(widget, gesture)

        return opaqueFromWidget(widget)
    }
}

// MARK: - onChange GTK extension

extension OnChangeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        onChangeCheckAndFire(
            namespace: gtkStateIdentityNamespace(),
            value: value,
            action: action
        )
        return gtkRenderView(content)
    }
}

extension OnChangeTwoArgView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        onChangeCheckAndFireTwoArg(
            namespace: gtkStateIdentityNamespace(),
            value: value,
            action: action
        )
        return gtkRenderView(content)
    }
}

// MARK: - Appearance modifier GTK extensions

extension HiddenView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let inner = widgetFromOpaque(gtkRenderView(content))
        // Wrap in a GtkBox so that the hidden opacity lives on a separate
        // widget from any .opacity() modifier applied to the content.
        // This prevents .hidden().opacity(0.5) from making the view visible.
        let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_box_append(boxPointer(wrapper), inner)
        // Preserve layout space (unlike gtk_widget_set_visible(0) which
        // collapses layout). Opacity on the wrapper is independent of
        // any opacity on the content widget.
        gtk_widget_set_opacity(wrapper, 0)
        // Block all interaction: pointer, keyboard focus, and sensitivity
        gtk_widget_set_can_target(wrapper, 0)
        gtk_widget_set_can_focus(wrapper, 0)
        gtk_widget_set_sensitive(wrapper, 0)
        gtkPropagateSingleChildLayoutMarkers(from: [inner], to: wrapper)
        // Propagate expand flags from content
        gtk_widget_set_hexpand(wrapper, gtk_widget_get_hexpand(inner))
        gtk_widget_set_vexpand(wrapper, gtk_widget_get_vexpand(inner))
        return opaqueFromWidget(wrapper)
    }
}

extension BlurView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        if radius > 0 {
            applyCSSToWidget(widget, properties: "filter: blur(\(radius)px);")
        }
        return opaqueFromWidget(widget)
    }
}

// MARK: - Style modifier GTK extensions

extension ButtonStyleModifier: GTKRenderable, GTKDescribable {
    /// Describe through to the styled content (the modifier's widget IS the
    /// content's widget). Without this the describe pass terminates here as a
    /// childless composite, which disqualifies every ancestor host from the
    /// narrow mutation path — e.g. each keystroke in a sheet whose buttons are
    /// styled forces a full teardown that destroys the focused text field.
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "ButtonStyleModifier",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.buttonStyle = style
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension CustomButtonStyleModifier: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "CustomButtonStyleModifier",
            props: .text(GTK4TextDescriptor(content: style.invalidationToken)),
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.customButtonStyle = style
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension ToggleStyleModifier: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.toggleStyle = style
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension CustomToggleStyleModifier: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.customToggleStyle = style
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension ControlGroupStyleModifier: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkRenderView(content)
    }
}

extension TextFieldStyleModifier: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "TextFieldStyleModifier",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.textFieldStyle = style
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

// MARK: - Gesture GTK extensions

/// Box for tap gesture that carries the required tap count.
private class TapClosureBox {
    let requiredCount: Int
    let action: () -> Void
    init(count: Int, action: @escaping () -> Void) {
        self.requiredCount = count
        self.action = action
    }
}

private final class GTKTapGestureActionBox {
    let requiredCount: Int
    let action: () -> Void
    let source: String
    var lastActivationTime: TimeInterval = 0

    init(requiredCount: Int, action: @escaping () -> Void, source: String) {
        self.requiredCount = requiredCount
        self.action = action
        self.source = source
    }
}

private let gtkTapGestureActionDataKey = "gtk-swift-tap-gesture-action"
private let gtkTapGestureGlobalDispatcherDataKey = "gtk-swift-tap-gesture-global-dispatcher"

private final class GTKTapGestureRootEventContext {
    let widget: UnsafeMutablePointer<GtkWidget>
    let box: GTKTapGestureActionBox
    let source: String
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?

    init(widget: UnsafeMutablePointer<GtkWidget>, box: GTKTapGestureActionBox, source: String) {
        self.widget = widget
        self.box = box
        self.source = source
    }

    func removeController() {
        guard let root, let controller else { return }
        gtk_swift_remove_event_controller(root, controller)
        self.root = nil
        self.controller = nil
    }
}

private final class GTKTapGestureGlobalRootDispatcher {
    let root: UnsafeMutablePointer<GtkWidget>
    var controller: gpointer?

    init(root: UnsafeMutablePointer<GtkWidget>) {
        self.root = root
    }
}

private func gtkScheduleTapGestureAction(_ box: GTKTapGestureActionBox, source: String) {
    gtkFlushPendingTextBindingUpdate()
    let now = Date().timeIntervalSinceReferenceDate
    if now - box.lastActivationTime < 0.08 {
        gtkDebugLog("tap gesture duplicate \(source)")
        return
    }
    box.lastActivationTime = now
    gtkDebugLog("tap gesture pressed \(source)")
    let context = Unmanaged.passRetained(GTKTapGestureIdleActionContext(box: box, source: source)).toOpaque()
    g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKTapGestureIdleActionContext>.fromOpaque(userData).takeRetainedValue()
        gtkDebugLog("tap gesture action \(context.source)")
        context.box.action()
        return 0
    }, context)
}

private final class GTKTapGestureIdleActionContext {
    let box: GTKTapGestureActionBox
    let source: String

    init(box: GTKTapGestureActionBox, source: String) {
        self.box = box
        self.source = source
    }
}

private func gtkVisualTapActionWidgetAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> UnsafeMutablePointer<GtkWidget>? {
    guard depth < 160 else { return nil }
    guard gtk_widget_get_visible(widget) != 0, gtk_widget_get_mapped(widget) != 0 else { return nil }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let match = gtkVisualTapActionWidgetAtRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            return match
        }
        child = gtk_widget_get_next_sibling(current)
    }

    guard gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y),
          let actionData = g_object_get_data(
              UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
              gtkTapGestureActionDataKey
          )
    else {
        return nil
    }
    let box = Unmanaged<GTKTapGestureActionBox>.fromOpaque(actionData).takeUnretainedValue()
    return box.requiredCount == 1 ? widget : nil
}

private func gtkTapGestureActionBox(
    from widget: UnsafeMutablePointer<GtkWidget>
) -> GTKTapGestureActionBox? {
    guard let actionData = g_object_get_data(
        UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
        gtkTapGestureActionDataKey
    ) else {
        return nil
    }
    return Unmanaged<GTKTapGestureActionBox>.fromOpaque(actionData).takeUnretainedValue()
}

private func gtkPickedTapActionWidgetAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> UnsafeMutablePointer<GtkWidget>? {
    var current = gtk_swift_root_point_pick_widget(root, x, y)
    var depth = 0
    while let widget = current, depth < 96 {
        if gtk_swift_widget_is_button(widget) == 0,
           gtk_swift_widget_is_menu_button(widget) == 0,
           let actionData = g_object_get_data(
               UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
               gtkTapGestureActionDataKey
           ) {
            let box = Unmanaged<GTKTapGestureActionBox>.fromOpaque(actionData).takeUnretainedValue()
            if box.requiredCount == 1 {
                return widget
            }
        }
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }
    return nil
}

private func gtkPreferredTapGestureActionBoxAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> GTKTapGestureActionBox? {
    if let widget = gtkPickedTapActionWidgetAtRootPoint(root: root, x: x, y: y),
       let box = gtkTapGestureActionBox(from: widget) {
        return box
    }
    if let widget = gtkVisualTapActionWidgetAtRootPoint(root, root: root, x: x, y: y),
       let box = gtkTapGestureActionBox(from: widget) {
        return box
    }
    return nil
}

private func gtkPointPrefersDifferentTapGestureAction(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    current box: GTKTapGestureActionBox
) -> Bool {
    guard let preferred = gtkPreferredTapGestureActionBoxAtRootPoint(root: root, x: x, y: y) else {
        return false
    }
    if gtkTapGestureBoxIsLayoutBackground(preferred), !gtkTapGestureBoxIsLayoutBackground(box) {
        return false
    }
    return preferred !== box
}

private func gtkTapGestureBoxIsLayoutBackground(_ box: GTKTapGestureActionBox) -> Bool {
    box.source == "SwiftOpenUI.Color"
        || box.source.hasPrefix("SwiftOpenUI.FilledShape<")
}

private func gtkDebugPickedWidgetChain(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    var current = gtk_swift_root_point_pick_widget(root, x, y)
    guard current != nil else {
        gtkDebugLog("\(source) picked-chain root@\(Int(x)),\(Int(y)) empty")
        return
    }

    var depth = 0
    while let widget = current, depth < 24 {
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
        let hasTap = g_object_get_data(object, gtkTapGestureActionDataKey) != nil
        let hasRow = g_object_get_data(object, gtkListRowTapActionDataKey) != nil
        gtkDebugLog(
            "\(source) picked-chain[\(depth)] type=\(typeName) "
            + "tap=\(hasTap ? 1 : 0) row=\(hasRow ? 1 : 0) "
            + "isRow=\(gtk_swift_widget_is_list_box_row(widget)) "
            + "isButton=\(gtk_swift_widget_is_button(widget)) "
            + gtkDebugVisualFrameDescription(widget, root: root)
        )
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }
}

private func gtkAttachTapGestureActionData(
    to widget: UnsafeMutablePointer<GtkWidget>,
    box: GTKTapGestureActionBox,
    depth: Int = 0
) {
    guard depth < 160 else { return }
    guard gtk_swift_widget_is_button(widget) == 0,
          gtk_swift_widget_is_menu_button(widget) == 0
    else {
        return
    }

    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    if g_object_get_data(object, gtkTapGestureActionDataKey) == nil {
        g_object_set_data_full(
            object,
            gtkTapGestureActionDataKey,
            Unmanaged.passRetained(box).toOpaque(),
            { userData in
                guard let userData else { return }
                Unmanaged<GTKTapGestureActionBox>.fromOpaque(userData).release()
            }
        )
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkAttachTapGestureActionData(to: current, box: box, depth: depth + 1)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkInstallGlobalTapGestureRootDispatcher(for widget: UnsafeMutablePointer<GtkWidget>) {
    guard let root = gtk_swift_widget_root_widget(widget) else { return }
    let rootObject = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GObject.self)
    guard g_object_get_data(rootObject, gtkTapGestureGlobalDispatcherDataKey) == nil else { return }

    let dispatcher = GTKTapGestureGlobalRootDispatcher(root: root)
    let controller = gtk_swift_legacy_capture_controller()!
    dispatcher.controller = controller

    let dispatcherPointer = Unmanaged.passRetained(dispatcher).toOpaque()
    g_object_set_data_full(
        rootObject,
        gtkTapGestureGlobalDispatcherDataKey,
        dispatcherPointer,
        { userData in
            guard let userData else { return }
            Unmanaged<GTKTapGestureGlobalRootDispatcher>.fromOpaque(userData).release()
        }
    )

    gtkDebugLog("tap gesture global root dispatcher installed")
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let dispatcher = Unmanaged<GTKTapGestureGlobalRootDispatcher>.fromOpaque(userData).takeUnretainedValue()
            let root = dispatcher.root
            var rootX: Double = 0
            var rootY: Double = 0
            guard gtk_swift_event_get_position(event, &rootX, &rootY) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }
            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "tap-root-dispatch@\(Int(rootX)),\(Int(rootY))"
            ) {
                return 1
            }

            if gtkOpenVisualMenuButtonAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "tap-root-dispatch@\(Int(rootX)),\(Int(rootY))"
            ) {
                return 1
            }
            guard gtk_swift_root_point_picks_button(root, rootX, rootY) == 0 else {
                gtkDebugLog("tap gesture global dispatch skipped button root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: rootX, y: rootY) else {
                gtkDebugLog("tap gesture global dispatch skipped visual button root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }

            var widget = gtkPickedTapActionWidgetAtRootPoint(root: root, x: rootX, y: rootY)
            if widget != nil {
                gtkDebugLog("tap gesture global dispatch picked fallback root@\(Int(rootX)),\(Int(rootY))")
            } else {
                widget = gtkVisualTapActionWidgetAtRootPoint(root, root: root, x: rootX, y: rootY)
            }
            guard let widget,
                  let actionData = g_object_get_data(
                      UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
                      gtkTapGestureActionDataKey
                  )
            else {
                gtkDebugPickedWidgetChain(
                    root: root,
                    x: rootX,
                    y: rootY,
                    source: "tap gesture global dispatch"
                )
                gtkDebugLog("tap gesture global dispatch miss root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            let box = Unmanaged<GTKTapGestureActionBox>.fromOpaque(actionData).takeUnretainedValue()
            gtkScheduleTapGestureAction(box, source: "root-dispatch@\(Int(rootX)),\(Int(rootY))")
            return 1
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        dispatcherPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

private func gtkInstallTapGestureRootEventFallback(_ context: GTKTapGestureRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.widget) else { return }

    let controller = gtk_swift_legacy_capture_controller()!
    context.root = root
    context.controller = controller
    gtkDebugLog("tap gesture root fallback installed \(context.source)")
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKTapGestureRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard context.box.requiredCount == 1, let root = context.root else { return 0 }
            var x: Double = 0
            var y: Double = 0
            guard gtk_swift_event_get_position(event, &x, &y) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: x, y: y)
            }
            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: x,
                y: y,
                source: "tap-root@\(Int(x)),\(Int(y))"
            ) {
                return 1
            }

            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0
            let isVisualHit = gtkWidgetOrDescendantVisuallyContainsRootPoint(context.widget, root: root, x: x, y: y)
            guard isTopmost || isVisualHit else {
                gtkDebugLog(
                    "tap gesture miss root@\(Int(x)),\(Int(y)) \(context.source) "
                    + gtkDebugVisualFrameDescription(context.widget, root: root)
                )
                return 0
            }

            let source = isTopmost ? "root" : "root-visual"
            if gtkOpenVisualMenuButtonAtRootPoint(
                root: root,
                x: x,
                y: y,
                source: "tap-\(source)@\(Int(x)),\(Int(y))"
            ) {
                return 1
            }
            guard gtk_swift_root_point_picks_button(root, x, y) == 0 else {
                gtkDebugLog("tap gesture skipped button \(source)@\(Int(x)),\(Int(y))")
                return 0
            }
            guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: x, y: y) else {
                gtkDebugLog("tap gesture skipped visual button \(source)@\(Int(x)),\(Int(y))")
                return 0
            }
            guard !gtkPointPrefersDifferentTapGestureAction(root: root, x: x, y: y, current: context.box) else {
                gtkDebugLog("tap gesture skipped deeper visual tap \(source)@\(Int(x)),\(Int(y)) \(context.source)")
                return 0
            }
            gtkScheduleTapGestureAction(context.box, source: "\(source)@\(Int(x)),\(Int(y)) \(context.source)")
            return 1
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

private func gtkTapGestureRootInstallTickCallback(
    _ widget: UnsafeMutablePointer<GtkWidget>?,
    _ frameClock: OpaquePointer?,
    _ userData: gpointer?
) -> gboolean {
    guard let userData else { return 0 }
    let context = Unmanaged<GTKTapGestureRootEventContext>.fromOpaque(userData).takeUnretainedValue()
    gtkInstallTapGestureRootEventFallback(context)
    gtkInstallGlobalTapGestureRootDispatcher(for: context.widget)
    return context.controller == nil ? 1 : 0
}

private protocol GTKPrimaryTapActionProvider {
    var gtkTapGestureCount: Int { get }
    var gtkTapGestureAction: () -> Void { get }
}

extension TapGestureView: GTKPrimaryTapActionProvider {
    fileprivate var gtkTapGestureCount: Int { count }
    fileprivate var gtkTapGestureAction: () -> Void { action }
}

extension TapGestureView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        // Transparent wrapper: describe content so sibling Canvas nodes
        // participate in the narrow mutation path. This preserves gesture
        // widgets across state-driven redraws.
        let childDescriptor = gtkDescribeView(content)
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "TapGestureView",
            children: [childDescriptor]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let contentWidget = widgetFromOpaque(gtkRenderView(content))
        if gtkIsEmptyViewWidget(contentWidget) {
            return opaqueFromWidget(contentWidget)
        }

        let widget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_can_target(widget, 1)
        gtk_widget_set_hexpand(widget, gtk_widget_get_hexpand(contentWidget))
        gtk_widget_set_vexpand(widget, gtk_widget_get_vexpand(contentWidget))
        gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
        gtk_box_append(boxPointer(widget), contentWidget)
        gtkPropagateSingleChildLayoutMarkers(from: [contentWidget], to: widget)

        let gesture = gtk_gesture_click_new()!

        let boundAction = bindActionToCurrentEnvironment(action)
        let actionBoxObject = GTKTapGestureActionBox(
            requiredCount: count,
            action: boundAction,
            source: String(reflecting: Swift.type(of: content))
        )
        let box = Unmanaged.passRetained(actionBoxObject).toOpaque()
        gtkAttachTapGestureActionData(to: widget, box: actionBoxObject)
        let rootContextObject = GTKTapGestureRootEventContext(
            widget: widget,
            box: actionBoxObject,
            source: String(reflecting: Swift.type(of: content))
        )
        let rootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
        g_signal_connect_data(
            gpointer(widget),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKTapGestureRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkInstallTapGestureRootEventFallback(context)
                gtkInstallGlobalTapGestureRootDispatcher(for: context.widget)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(widget),
            "unmap",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKTapGestureRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        let tickRootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
        _ = gtk_widget_add_tick_callback(
            widget,
            gtkTapGestureRootInstallTickCallback,
            tickRootEventContext,
            { userData in
                guard let userData else { return }
                Unmanaged<GTKTapGestureRootEventContext>.fromOpaque(userData).release()
            }
        )
        g_signal_connect_data(
            gpointer(widget),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKTapGestureRootEventContext>.fromOpaque(userData).takeRetainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(gesture),
            "pressed",
            unsafeBitCast({ (gesture: gpointer?, nPress: gint, x: gdouble, y: gdouble, userData: gpointer?) in
                let box = Unmanaged<GTKTapGestureActionBox>.fromOpaque(userData!).takeUnretainedValue()
                if Int(nPress) == box.requiredCount {
                    if let gesture,
                       let widget = gtk_swift_event_controller_widget(gesture),
                       let root = gtk_swift_widget_root_widget(widget) {
                        var rootX = 0.0
                        var rootY = 0.0
                        if gtk_widget_translate_coordinates(widget, root, x, y, &rootX, &rootY) != 0,
                           gtkPointPrefersDifferentTapGestureAction(root: root, x: rootX, y: rootY, current: box) {
                            gtkDebugLog("tap gesture skipped deeper visual tap gesture@\(Int(rootX)),\(Int(rootY))")
                            return
                        }
                    }
                    gtkScheduleTapGestureAction(box, source: "gesture")
                }
            } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<GTKTapGestureActionBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        gtk_swift_add_capture_gesture(widget, gesture)
        return opaqueFromWidget(widget)
    }
}

extension LongPressGestureView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        let gesture = gtk_gesture_long_press_new()!

        // Set delay threshold
        g_object_set_double(gpointer(gesture), "delay-factor", minimumDuration / 0.5)

        let boundAction = bindActionToCurrentEnvironment(action)
        let box = Unmanaged.passRetained(ClosureBox(boundAction)).toOpaque()
        g_signal_connect_data(
            gpointer(gesture),
            "pressed",
            unsafeBitCast({ (_: gpointer?, _: gdouble, _: gdouble, userData: gpointer?) in
                let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                box.closure()
            } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<ClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        gtk_swift_add_gesture(widget, gesture)
        return opaqueFromWidget(widget)
    }
}

/// Mutable state for tracking drag start location across GTK signal callbacks.
private class GTKDragState {
    var startX: Double = 0
    var startY: Double = 0
    var dragStarted = false
}

extension DragGestureView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        // Transparent wrapper: describe content so Canvas (and other
        // describable children) participate in the narrow mutation path.
        // This preserves the gesture widget across state-driven redraws.
        let childDescriptor = gtkDescribeView(content)
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "DragGestureView",
            children: [childDescriptor]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        let gesture = gtk_gesture_drag_new()!

        let dragState = GTKDragState()

        if let onChanged = onChanged {
            let boundOnChanged = bindActionToCurrentEnvironment(onChanged)
            let state = dragState
            let minimumDistance = self.minimumDistance
            let box = Unmanaged.passRetained(DoubleDoubleClosureBox { offsetX, offsetY in
                if !state.dragStarted {
                    let distance = hypot(offsetX, offsetY)
                    guard distance >= minimumDistance else { return }
                    state.dragStarted = true
                }
                let value = DragGestureValue(
                    startLocation: (x: state.startX, y: state.startY),
                    location: (x: state.startX + offsetX, y: state.startY + offsetY),
                    translation: (width: offsetX, height: offsetY)
                )
                boundOnChanged(value)
            }).toOpaque()

            // drag-begin: record start position
            let beginBox = Unmanaged.passRetained(DoubleDoubleClosureBox { x, y in
                state.startX = x
                state.startY = y
                state.dragStarted = false
            }).toOpaque()
            g_signal_connect_data(
                gpointer(gesture),
                "drag-begin",
                unsafeBitCast({ (_: gpointer?, x: gdouble, y: gdouble, userData: gpointer?) in
                    Unmanaged<DoubleDoubleClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure(x, y)
                } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
                beginBox,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<DoubleDoubleClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )

            // drag-update: fire onChanged
            g_signal_connect_data(
                gpointer(gesture),
                "drag-update",
                unsafeBitCast({ (_: gpointer?, offsetX: gdouble, offsetY: gdouble, userData: gpointer?) in
                    Unmanaged<DoubleDoubleClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure(offsetX, offsetY)
                } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
                box,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<DoubleDoubleClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }

        if let onEnded = onEnded {
            let boundOnEnded = bindActionToCurrentEnvironment(onEnded)
            let state = dragState
            let minimumDistance = self.minimumDistance
            // If no onChanged handler registered drag-begin, we need to capture start here too.
            if self.onChanged == nil {
                let beginBox = Unmanaged.passRetained(DoubleDoubleClosureBox { x, y in
                    state.startX = x
                    state.startY = y
                    state.dragStarted = false
                }).toOpaque()
                g_signal_connect_data(
                    gpointer(gesture),
                    "drag-begin",
                    unsafeBitCast({ (_: gpointer?, x: gdouble, y: gdouble, userData: gpointer?) in
                        Unmanaged<DoubleDoubleClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure(x, y)
                    } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
                    beginBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<DoubleDoubleClosureBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
            }

            let endBox = Unmanaged.passRetained(DoubleDoubleClosureBox { offsetX, offsetY in
                if !state.dragStarted {
                    let distance = hypot(offsetX, offsetY)
                    guard distance >= minimumDistance else { return }
                    state.dragStarted = true
                }
                let value = DragGestureValue(
                    startLocation: (x: state.startX, y: state.startY),
                    location: (x: state.startX + offsetX, y: state.startY + offsetY),
                    translation: (width: offsetX, height: offsetY)
                )
                boundOnEnded(value)
            }).toOpaque()
            g_signal_connect_data(
                gpointer(gesture),
                "drag-end",
                unsafeBitCast({ (_: gpointer?, offsetX: gdouble, offsetY: gdouble, userData: gpointer?) in
                    Unmanaged<DoubleDoubleClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure(offsetX, offsetY)
                } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
                endBox,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<DoubleDoubleClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }

        gtk_swift_add_gesture(widget, gesture)
        return opaqueFromWidget(widget)
    }
}

// MARK: - Animation & Transform GTK extensions

/// GObject data keys for storing animatable state on widgets.
private let gtkSwiftOffsetXKey = "gtk-swift-offset-x"
private let gtkSwiftOffsetYKey = "gtk-swift-offset-y"
private let gtkSwiftScaleXKey = "gtk-swift-scale-x"
private let gtkSwiftScaleYKey = "gtk-swift-scale-y"
private let gtkSwiftRotationKey = "gtk-swift-rotation"

/// Box for storing a Double in GObject data without losing 0.0 as nil.
private final class WidgetDoubleBox {
    let value: Double
    init(_ value: Double) { self.value = value }
}

/// Store a Double value on a widget via GObject data (bit-pattern encoded).
private func setWidgetDouble(_ widget: UnsafeMutablePointer<GtkWidget>, key: String, value: Double) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    let retained = Unmanaged.passRetained(WidgetDoubleBox(value)).toOpaque()
    g_object_set_data_full(gobject, key, retained) { userData in
        Unmanaged<WidgetDoubleBox>.fromOpaque(userData!).release()
    }
}

/// Read a Double value from a widget via GObject data.
func getWidgetDouble(_ widget: UnsafeMutablePointer<GtkWidget>, key: String) -> Double? {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let raw = g_object_get_data(gobject, key) else { return nil }
    return Unmanaged<WidgetDoubleBox>.fromOpaque(raw).takeUnretainedValue().value
}

/// Build a combined CSS transform string from offset, scale, and rotation values.
/// Order: translate → rotate → scale (matches CSS transform application order).
func buildTransformCSS(offsetX: Double, offsetY: Double, scaleX: Double, scaleY: Double, rotation: Double = 0) -> String {
    var parts: [String] = []
    if offsetX != 0 || offsetY != 0 {
        parts.append("translate(\(Int(offsetX))px, \(Int(offsetY))px)")
    }
    if rotation != 0 {
        parts.append("rotate(\(rotation)deg)")
    }
    if scaleX != 1 || scaleY != 1 {
        parts.append("scale(\(scaleX), \(scaleY))")
    }
    guard !parts.isEmpty else { return "" }
    return "transform: \(parts.joined(separator: " "));"
}

extension OpacityView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .opacity, typeName: "OpacityView",
            props: .opacity(GTK4OpacityDescriptor(opacity: opacity)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_opacity(widget, opacity)
        return opaqueFromWidget(widget)
    }
}

extension OffsetView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .offset, typeName: "OffsetView",
            props: .offset(GTK4OffsetDescriptor(x: x, y: y)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        setWidgetDouble(widget, key: gtkSwiftOffsetXKey, value: x)
        setWidgetDouble(widget, key: gtkSwiftOffsetYKey, value: y)
        if x != 0 || y != 0 {
            let scaleX = getWidgetDouble(widget, key: gtkSwiftScaleXKey) ?? 1
            let scaleY = getWidgetDouble(widget, key: gtkSwiftScaleYKey) ?? 1
            let rotation = getWidgetDouble(widget, key: gtkSwiftRotationKey) ?? 0
            applyCSSToWidget(widget, properties: buildTransformCSS(offsetX: x, offsetY: y, scaleX: scaleX, scaleY: scaleY, rotation: rotation))
        }
        return opaqueFromWidget(widget)
    }
}

extension ScaleEffectView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .scale, typeName: "ScaleEffectView",
            props: .scale(GTK4ScaleDescriptor(scaleX: scaleX, scaleY: scaleY)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        setWidgetDouble(widget, key: gtkSwiftScaleXKey, value: scaleX)
        setWidgetDouble(widget, key: gtkSwiftScaleYKey, value: scaleY)
        if scaleX != 1 || scaleY != 1 {
            let offsetX = getWidgetDouble(widget, key: gtkSwiftOffsetXKey) ?? 0
            let offsetY = getWidgetDouble(widget, key: gtkSwiftOffsetYKey) ?? 0
            let rotation = getWidgetDouble(widget, key: gtkSwiftRotationKey) ?? 0
            applyCSSToWidget(widget, properties: buildTransformCSS(offsetX: offsetX, offsetY: offsetY, scaleX: scaleX, scaleY: scaleY, rotation: rotation))
        }
        return opaqueFromWidget(widget)
    }
}

extension AnimatedView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let props: GTK4DescriptorProps
        if let anim = animation {
            props = .animated(GTK4AnimatedDescriptor(
                curve: String(describing: anim.curve),
                duration: anim.duration,
                delay: anim.delay,
                repeatsForever: anim.repeatsForever,
                autoreverses: anim.autoreverses))
        } else {
            props = .none
        }
        return GTK4DescriptorNode(
            kind: .animated, typeName: "AnimatedView",
            props: props,
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        if let animation = animation ?? getCurrentAnimation() {
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
            applyCSSToWidget(widget, properties: "transition: all \(duration)s \(timing) \(delay)s;")
        }
        return opaqueFromWidget(widget)
    }
}

// MARK: - OnAppear / OnDisappear GTK extensions

private let gtkStandaloneTaskBoxKey = "gtk-swift-standalone-task-box"

private final class GTKStandaloneTaskBox {
    let priority: TaskPriority
    let lifecycleID: String?
    let action: @Sendable () async -> Void
    var task: Task<Void, Never>?

    init(
        priority: TaskPriority,
        lifecycleID: String?,
        action: @escaping @Sendable () async -> Void
    ) {
        self.priority = priority
        self.lifecycleID = lifecycleID
        self.action = action
    }

    func start() {
        guard task == nil else { return }
        let action = action
        gtkDebugLog("standalone task start lifecycleID=\(lifecycleID ?? "<none>")")
        task = Task(priority: priority) {
            await action()
        }
    }

    func cancel() {
        if task != nil {
            gtkDebugLog("standalone task cancel lifecycleID=\(lifecycleID ?? "<none>")")
        }
        task?.cancel()
        task = nil
    }
}

private final class GTKStandaloneTaskGroup {
    var boxes: [GTKStandaloneTaskBox] = []
    var mapHandlerID: gulong = 0
    var unmapHandlerID: gulong = 0

    func append(_ box: GTKStandaloneTaskBox, to widget: UnsafeMutablePointer<GtkWidget>) {
        boxes.append(box)
        if gtk_widget_get_mapped(widget) != 0 {
            box.start()
        }
    }

    func startAll() {
        boxes.forEach { $0.start() }
    }

    func cancelAll() {
        boxes.forEach { $0.cancel() }
    }
}

private func gtkAttachStandaloneTaskLifecycle(
    to widget: UnsafeMutablePointer<GtkWidget>,
    priority: TaskPriority,
    lifecycleID: String?,
    action: @escaping @Sendable () async -> Void
) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    let group: GTKStandaloneTaskGroup
    if let existing = g_object_get_data(gobject, gtkStandaloneTaskBoxKey) {
        group = Unmanaged<GTKStandaloneTaskGroup>.fromOpaque(existing).takeUnretainedValue()
    } else {
        let newGroup = GTKStandaloneTaskGroup()
        let groupPointer = Unmanaged.passRetained(newGroup).toOpaque()
        g_object_set_data_full(
            gobject,
            gtkStandaloneTaskBoxKey,
            groupPointer,
            { userData in
                let group = Unmanaged<GTKStandaloneTaskGroup>.fromOpaque(userData!).takeRetainedValue()
                group.cancelAll()
            }
        )
        newGroup.mapHandlerID = g_signal_connect_data(
            gpointer(widget),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let group = Unmanaged<GTKStandaloneTaskGroup>.fromOpaque(userData!).takeUnretainedValue()
                group.startAll()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            groupPointer,
            nil,
            GConnectFlags(rawValue: 0)
        )
        newGroup.unmapHandlerID = g_signal_connect_data(
            gpointer(widget),
            "unmap",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let group = Unmanaged<GTKStandaloneTaskGroup>.fromOpaque(userData!).takeUnretainedValue()
                group.cancelAll()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            groupPointer,
            nil,
            GConnectFlags(rawValue: 0)
        )
        group = newGroup
    }

    let taskBox = GTKStandaloneTaskBox(priority: priority, lifecycleID: lifecycleID, action: action)
    gtkDebugLog("standalone task attach index=\(group.boxes.count) lifecycleID=\(lifecycleID ?? "<none>") mapped=\(gtk_widget_get_mapped(widget))")
    group.append(taskBox, to: widget)
}

private func gtkScheduleOnAppear(_ action: @escaping () -> Void, on widget: UnsafeMutablePointer<GtkWidget>) {
    let rawWidget = UnsafeMutableRawPointer(widget)
    g_object_ref(rawWidget)

    let box = Unmanaged.passRetained(ClosureBox {
        action()
        g_object_unref(rawWidget)
    }).toOpaque()

    g_idle_add({ userData -> gboolean in
        let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeRetainedValue()
        box.closure()
        return 0
    }, box)
}

extension TaskView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let boundAction: @Sendable () async -> Void = bindTaskActionToCurrentEnvironment {
            await action()
        }
        gtkCollectTaskPayload(
            GTK4TaskPayload(
                priority: priority,
                lifecycleID: lifecycleID,
                action: boundAction
            )
        )
        return GTK4DescriptorNode(
            kind: .task,
            typeName: "TaskView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        let boundAction: @Sendable () async -> Void = bindTaskActionToCurrentEnvironment {
            await action()
        }

        // Stateful hosts reconcile `.task` by descriptor identity so a full
        // child teardown during rebuild does not re-run the task. Standalone
        // renders still need native map/unmap hooks.
        if GTKViewHost.getCurrentRebuilding() == nil {
            gtkAttachStandaloneTaskLifecycle(
                to: widget,
                priority: priority,
                lifecycleID: lifecycleID,
                action: boundAction
            )
        }
        return opaqueFromWidget(widget)
    }
}

extension OnAppearView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        gtkCollectOnAppearPayload(
            GTK4OnAppearPayload(action: bindActionToCurrentEnvironment(action))
        )
        return GTK4DescriptorNode(
            kind: .onAppear,
            typeName: "OnAppearView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        // Stateful hosts reconcile `onAppear` by descriptor identity so actions
        // run once per appearance even when the subtree rebuilds.  Stateless
        // standalone renders still use the native map signal.
        let boundAction = bindActionToCurrentEnvironment(action)
        if GTKViewHost.getCurrentRebuilding() == nil {
            let box = Unmanaged.passRetained(ClosureBox(boundAction)).toOpaque()
            g_signal_connect_data(
                gpointer(widget),
                "map",
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
        }

        return opaqueFromWidget(widget)
    }
}

/// Holds the disappear callback and a reference to the host container
/// for distinguishing rebuild unmaps from real disappears.
private class DisappearBox {
    let action: () -> Void
    let hostContainer: UnsafeMutablePointer<GtkWidget>?
    // GTK OnDisappear requires a prior map before firing. Sheet content can
    // be temporarily unrealized while it is being attached to a window; SwiftUI
    // does not treat that construction churn as a disappearance.
    var hasMapped: Bool = false
    init(action: @escaping () -> Void, hostContainer: UnsafeMutablePointer<GtkWidget>?) {
        self.action = action
        self.hostContainer = hostContainer
    }
}

extension OnDisappearView: GTKRenderable, GTKDescribable {
    /// Describe through to the content (the wrapper's widget IS the content's
    /// widget; the disappear callback rides the existing widget's unmap
    /// signal, which the narrow mutation path leaves untouched). Without this
    /// the describe pass terminates here as a childless composite, so every
    /// ancestor host — e.g. a sheet whose root view chains
    /// .onAppear/.onDisappear — falls off the narrow path and tears down its
    /// widgets on every rebuild.
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "OnDisappearView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        let hostContainer: UnsafeMutablePointer<GtkWidget>?
        if let host = GTKViewHost.getCurrentRebuilding() {
            hostContainer = host.container
        } else {
            hostContainer = nil
        }

        let boundAction = bindActionToCurrentEnvironment(action)
        if let sheetLifecycleScope = gtkCurrentSheetLifecycleScope() {
            sheetLifecycleScope.registerOnDisappear(boundAction)
            return opaqueFromWidget(widget)
        }

        let box = Unmanaged.passRetained(
            DisappearBox(action: boundAction, hostContainer: hostContainer)
        ).toOpaque()
        g_signal_connect_data(
            gpointer(widget),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<DisappearBox>.fromOpaque(userData!).takeUnretainedValue()
                box.hasMapped = true
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(widget),
            "unmap",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<DisappearBox>.fromOpaque(userData!).takeUnretainedValue()
                guard box.hasMapped else { return }
                // If the host container is still mapped, this is a rebuild — suppress.
                if let container = box.hostContainer,
                   gtk_widget_get_mapped(container) != 0 {
                    return
                }
                box.action()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<DisappearBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        return opaqueFromWidget(widget)
    }
}

// MARK: - Sheet GTK extension

/// Holds sheet configuration for deferred presentation.
/// Extract dismissal-confirmation configuration from a view tree.
private func gtkExtractDismissalConfig(from view: Any, depth: Int = 0) -> DismissalConfirmationConfiguration? {
    _ = depth
    if let provider = view as? DismissalConfirmationProvider {
        if let config = provider.dismissalConfirmationConfiguration {
            return config
        }
    }
    // Do not recursively Mirror arbitrary app view values here. Large SwiftUI
    // trees often contain existential closures and opaque storage; reflecting
    // those values can crash the Swift runtime on Linux. Nested dismissal
    // interception should be carried explicitly by wrapper metadata instead.
    return nil
}

/// Present a confirmation dialog directly on top of a sheet window.
private func gtkPresentConfirmationDialog(
    config: DismissalConfirmationConfiguration,
    transientFor sheetWin: UnsafeMutablePointer<GtkWindow>,
    onActualDismiss: @escaping () -> Void
) {
    let dialog = gtk_window_new()!
    let dialogWin = windowPointer(dialog)
    gtk_window_set_modal(dialogWin, 1)
    gtk_window_set_title(dialogWin, config.titleVisibility == .hidden ? "" : config.title)
    gtk_window_set_default_size(dialogWin, 300, -1)
    gtk_window_set_resizable(dialogWin, 0)
    gtk_window_set_transient_for(dialogWin, sheetWin)

    let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)!
    gtk_widget_set_margin_top(vbox, 20)
    gtk_widget_set_margin_bottom(vbox, 20)
    gtk_widget_set_margin_start(vbox, 20)
    gtk_widget_set_margin_end(vbox, 20)

    if config.titleVisibility != .hidden {
        let titleLabel = gtk_label_new(nil)!
        let escaped = config.title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        gtk_swift_label_set_markup(titleLabel, "<b>\(escaped)</b>")
        gtk_box_append(boxPointer(vbox), titleLabel)
    }

    if !config.message.isEmpty {
        let msgLabel = gtk_label_new(config.message)!
        gtk_label_set_wrap(OpaquePointer(msgLabel), 1)
        gtk_box_append(boxPointer(vbox), msgLabel)
    }

    let sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)!
    gtk_box_append(boxPointer(vbox), sep)

    for alertButton in config.buttons {
        let btn = gtk_button_new_with_label(alertButton.label)!
        gtk_widget_set_hexpand(btn, 1)
        if alertButton.role == .destructive {
            gtk_widget_add_css_class(btn, "destructive-action")
        }
        // Non-cancel buttons confirm dismissal: run action, close confirmation, then close sheet
        let shouldDismissSheet = alertButton.role != .cancel
        let wrappedAction: () -> Void = {
            alertButton.action()
            if shouldDismissSheet {
                onActualDismiss()
            }
        }
        let actionBox = Unmanaged.passRetained(AlertActionBox(
            action: wrappedAction, dialog: dialog
        )).toOpaque()
        g_signal_connect_data(
            gpointer(btn),
            "clicked",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<AlertActionBox>.fromOpaque(userData!).takeUnretainedValue()
                box.action()
                gtk_window_destroy(windowPointer(box.dialog))
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            actionBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<AlertActionBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )
        gtk_box_append(boxPointer(vbox), btn)
    }

    gtk_window_set_child(dialogWin, vbox)

    // Close confirmation dialog resets shouldPresent
    let binding = config.isPresented
    let closeBox = Unmanaged.passRetained(ClosureBox {
        binding.wrappedValue = false
    }).toOpaque()
    g_signal_connect_data(
        gpointer(dialog),
        "close-request",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) -> gboolean in
            Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure()
            return 0
        } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        closeBox,
        { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
            Unmanaged<ClosureBox>.fromOpaque(userData!).release()
        },
        GConnectFlags(rawValue: 0)
    )

    gtk_window_present(dialogWin)
}

private final class GTKSheetLifecycleScope {
    private var disappearActions: [() -> Void] = []
    private var didRunDisappearActions = false

    func registerOnDisappear(_ action: @escaping () -> Void) {
        disappearActions.append(action)
    }

    func runDisappearActions() {
        guard !didRunDisappearActions else { return }
        didRunDisappearActions = true
        for action in disappearActions {
            action()
        }
    }
}

private var gtkSheetLifecycleScopes: [GTKSheetLifecycleScope] = []

private func gtkCurrentSheetLifecycleScope() -> GTKSheetLifecycleScope? {
    gtkSheetLifecycleScopes.last
}

private func gtkWithSheetLifecycleScope<T>(
    _ scope: GTKSheetLifecycleScope,
    perform body: () -> T
) -> T {
    gtkSheetLifecycleScopes.append(scope)
    defer { _ = gtkSheetLifecycleScopes.popLast() }
    return body()
}

private func gtkSheetDefaultWidth() -> gint {
    guard let rawWidth = ProcessInfo.processInfo.environment["QUILLUI_GTK_SHEET_DEFAULT_WIDTH"],
          let width = Int(rawWidth),
          width > 0
    else {
        return 900
    }
    return gint(width)
}

private func gtkSheetDefaultHeight() -> gint {
    guard let rawHeight = ProcessInfo.processInfo.environment["QUILLUI_GTK_SHEET_DEFAULT_HEIGHT"],
          let height = Int(rawHeight),
          height > 0
    else {
        return 650
    }
    return gint(height)
}

private let gtkSheetOverlayHorizontalMargins: gint = 32
private let gtkSheetOverlayVerticalMargins: gint = 32

private final class GTKSheetPanelSizeContext {
    let preferredWidth: gint
    let preferredHeight: gint
    var lastWidth: gint = -1
    var lastHeight: gint = -1

    init(preferredWidth: gint, preferredHeight: gint) {
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
    }
}

private func gtkClampedSheetPanelDimension(
    preferred: gint,
    hostSize: gint,
    margins: gint
) -> gint {
    guard hostSize > 1 else { return preferred }
    return min(preferred, max(gint(1), hostSize - margins))
}

private let gtkSheetPanelSizeTickCallback: GtkTickCallback = { widget, _, userData in
    guard let panel = widget, let userData else { return 0 }
    let context = Unmanaged<GTKSheetPanelSizeContext>.fromOpaque(userData).takeUnretainedValue()
    let host = gtk_widget_get_parent(panel)
    let hostWidth = host.map { gtk_widget_get_width($0) } ?? gtk_widget_get_width(panel)
    let hostHeight = host.map { gtk_widget_get_height($0) } ?? gtk_widget_get_height(panel)
    let nextWidth = gtkClampedSheetPanelDimension(
        preferred: context.preferredWidth,
        hostSize: hostWidth,
        margins: gtkSheetOverlayHorizontalMargins
    )
    let nextHeight = gtkClampedSheetPanelDimension(
        preferred: context.preferredHeight,
        hostSize: hostHeight,
        margins: gtkSheetOverlayVerticalMargins
    )
    guard nextWidth != context.lastWidth || nextHeight != context.lastHeight else { return 1 }

    context.lastWidth = nextWidth
    context.lastHeight = nextHeight
    gtk_widget_set_size_request(panel, nextWidth, nextHeight)
    gtk_widget_queue_resize(panel)
    return 1
}

private func gtkInstallSheetPanelOverlaySizeClamp(
    on panel: UnsafeMutablePointer<GtkWidget>,
    preferredWidth: gint,
    preferredHeight: gint
) {
    let context = GTKSheetPanelSizeContext(
        preferredWidth: preferredWidth,
        preferredHeight: preferredHeight
    )
    let contextPtr = Unmanaged.passRetained(context).toOpaque()
    _ = gtk_widget_add_tick_callback(
        panel,
        gtkSheetPanelSizeTickCallback,
        contextPtr,
        { userData in Unmanaged<GTKSheetPanelSizeContext>.fromOpaque(userData!).release() }
    )
}

private func gtkSheetPresentationMode() -> String {
    return (ProcessInfo.processInfo.environment["QUILLUI_BACKEND_SHEET_PRESENTATION"]
        ?? ProcessInfo.processInfo.environment["QUILLUI_GTK_SHEET_PRESENTATION"]
        ?? "root-overlay")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func gtkShouldRenderSheetInRootOverlay() -> Bool {
    let mode = gtkSheetPresentationMode()
    return mode.isEmpty || mode == "root" || mode == "root-overlay" || mode == "window-overlay"
}

private func gtkShouldRenderSheetInWindow() -> Bool {
    let mode = gtkSheetPresentationMode()
    return mode == "overlay" || mode == "in-window" || mode == "inline"
}

private var gtkRootSheetOverlayStack: [OpaquePointer] = []

// Presented root-overlay sheet layers, keyed by the type-derived activeKey.
// Anchors (GTKViewHost containers) are recreated on every parent render, so
// per-anchor g_object data is lost after the first rebuild — a layer tracked
// there could never be dismissed (or deduplicated) again. The activeKey is
// stable across hosts, so a global registry survives parent rebuilds.
private var gtkRootSheetLayers: [String: UnsafeMutablePointer<GtkWidget>] = [:]
private var gtkRootSheetItemIDs: [String: Int] = [:]

private func gtkCurrentRootSheetOverlay() -> OpaquePointer? {
    gtkRootSheetOverlayStack.last
}

private func gtkWithRootSheetOverlay<T>(_ rootOverlay: OpaquePointer, _ body: () -> T) -> T {
    gtkRootSheetOverlayStack.append(rootOverlay)
    defer { _ = gtkRootSheetOverlayStack.popLast() }
    return body()
}

private func gtkSheetRootOverlay(for anchor: UnsafeMutablePointer<GtkWidget>) -> OpaquePointer? {
    if let rootOverlay = gtkCurrentRootSheetOverlay() {
        return rootOverlay
    }
    if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(anchor)) {
        return rootOverlay
    }
    var ancestor = gtk_widget_get_parent(anchor)
    while let current = ancestor {
        if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(current)) {
            return rootOverlay
        }
        ancestor = gtk_widget_get_parent(current)
    }
    if let root = gtk_widget_get_root(anchor).map({ gpointer($0) }),
       let rootOverlay = gtkRootPresentationOverlay(for: root) {
        return rootOverlay
    }
    if let root = GTKViewHost.getCurrentRebuilding()?.rebuildPresentationRoot,
       let rootOverlay = gtkRootPresentationOverlay(for: root) {
        return rootOverlay
    }
    if let rootOverlay = gtkFallbackRootPresentationOverlay() {
        return rootOverlay
    }
    return nil
}

private func gtkRemoveSheetRootOverlay(
    anchor: UnsafeMutablePointer<GtkWidget>,
    overlayKey: String,
    activeKey: String,
    itemIDKey: String? = nil,
    onDismiss: (() -> Void)? = nil
) {
    guard gtkRemoveRootSheetLayer(activeKey: activeKey) else {
        return
    }
    // Clear any legacy per-anchor markers so a same-anchor re-render starts clean.
    let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, overlayKey, nil)
    g_object_set_data(gobject, activeKey, nil)
    if let itemIDKey {
        g_object_set_data(gobject, itemIDKey, nil)
    }
    onDismiss?()
}

@discardableResult
private func gtkRemoveRootSheetLayer(
    activeKey: String,
    fallbackLayer: UnsafeMutablePointer<GtkWidget>? = nil
) -> Bool {
    let layer: UnsafeMutablePointer<GtkWidget>
    let usedFallback: Bool
    if let registeredLayer = gtkRootSheetLayers.removeValue(forKey: activeKey) {
        layer = registeredLayer
        usedFallback = false
    } else if let fallbackLayer,
              gtk_swift_is_widget(fallbackLayer) != 0,
              gtk_widget_get_parent(fallbackLayer) != nil {
        layer = fallbackLayer
        usedFallback = true
    } else {
        gtkDebugLog("sheet root dismiss miss activeKey=\(activeKey)")
        return false
    }
    gtkRootSheetItemIDs[activeKey] = nil
    gtkDebugLog("sheet root dismiss activeKey=\(activeKey) fallback=\(usedFallback)")
    gtk_widget_unparent(layer)
    return true
}

private func gtkCreateSheetOverlayPanel(
    sheetWidget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let panel = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    let preferredWidth = gtkSheetDefaultWidth()
    let preferredHeight = gtkSheetDefaultHeight()
    gtk_widget_set_size_request(panel, preferredWidth, preferredHeight)
    gtkInstallSheetPanelOverlaySizeClamp(
        on: panel,
        preferredWidth: preferredWidth,
        preferredHeight: preferredHeight
    )
    gtk_widget_set_halign(panel, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(panel, GTK_ALIGN_CENTER)
    applyCSSToWidget(
        panel,
        properties: "background: #f8f8fb; border: 1px solid rgba(0,0,0,0.12); border-radius: 12px; box-shadow: 0 18px 48px rgba(0,0,0,0.18);"
    )

    gtk_widget_set_hexpand(sheetWidget, 1)
    gtk_widget_set_vexpand(sheetWidget, 1)
    gtk_widget_set_halign(sheetWidget, GTK_ALIGN_FILL)
    gtk_widget_set_valign(sheetWidget, GTK_ALIGN_FILL)
    gtk_box_append(boxPointer(panel), sheetWidget)
    gtkInstallSheetPanelFocusBridge(on: panel)
    gtkScheduleFirstSheetEditableFocus(in: panel)
    return panel
}

private func gtkCreateSheetOverlayLayer(
    panel: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let layer = gtk_overlay_new()!
    gtk_widget_set_hexpand(layer, 1)
    gtk_widget_set_vexpand(layer, 1)
    gtk_widget_set_halign(layer, GTK_ALIGN_FILL)
    gtk_widget_set_valign(layer, GTK_ALIGN_FILL)

    let backdrop = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    gtk_widget_set_hexpand(backdrop, 1)
    gtk_widget_set_vexpand(backdrop, 1)
    gtk_widget_set_halign(backdrop, GTK_ALIGN_FILL)
    gtk_widget_set_valign(backdrop, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(backdrop, 1)
    applyCSSToWidget(backdrop, properties: "background: #f8f8fb;")

    gtk_overlay_set_child(OpaquePointer(layer), backdrop)
    gtk_overlay_add_overlay(OpaquePointer(layer), panel)
    return layer
}

private func gtkAttachRootSheetOverlay(
    _ layer: UnsafeMutablePointer<GtkWidget>,
    to rootOverlay: OpaquePointer
) {
    let overlayWidget = UnsafeMutableRawPointer(rootOverlay).assumingMemoryBound(to: GtkWidget.self)
    let previousTop = gtk_widget_get_last_child(overlayWidget)
    gtk_overlay_add_overlay(rootOverlay, layer)
    if let previousTop, previousTop != layer {
        gtk_widget_insert_after(layer, overlayWidget, previousTop)
    }
}

private final class GTKSheetPanelFocusBox {
    let panel: UnsafeMutablePointer<GtkWidget>

    init(panel: UnsafeMutablePointer<GtkWidget>) {
        self.panel = panel
    }
}

private final class GTKSheetEditableFocusTarget {
    let widget: UnsafeMutablePointer<GtkWidget>

    init(widget: UnsafeMutablePointer<GtkWidget>) {
        self.widget = widget
    }
}

private final class GTKSheetPanelFocusTarget {
    let panel: UnsafeMutablePointer<GtkWidget>
    var retries = 0

    init(panel: UnsafeMutablePointer<GtkWidget>) {
        self.panel = panel
    }
}

private func gtkInstallSheetPanelFocusBridge(on panel: UnsafeMutablePointer<GtkWidget>) {
    let gesture = gtk_gesture_click_new()!
    let box = Unmanaged.passRetained(GTKSheetPanelFocusBox(panel: panel)).toOpaque()
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, x: Double, y: Double, userData: gpointer?) in
            guard let userData else { return }
            let box = Unmanaged<GTKSheetPanelFocusBox>.fromOpaque(userData).takeUnretainedValue()
            gtkFocusSheetEditable(in: box.panel, localX: x, localY: y)
        } as @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void, to: GCallback.self),
        box,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<GTKSheetPanelFocusBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(panel, gesture)
}

private func gtkFocusSheetEditable(
    in panel: UnsafeMutablePointer<GtkWidget>,
    localX: Double,
    localY: Double
) {
    guard gtk_swift_is_widget(panel) != 0 else { return }
    guard let root = gtk_swift_widget_root_widget(panel) else { return }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(panel, root, localX, localY, &rootX, &rootY) != 0 else {
        return
    }
    guard let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY) else {
        return
    }
    gtkScheduleSheetEditableFocus(editable)
}

private func gtkFocusSheetEditableWidget(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    gtk_widget_set_can_target(widget, 1)
    gtk_widget_set_can_focus(widget, 1)
    gtk_widget_set_focusable(widget, 1)
    let grabbed = gtk_swift_root_grab_focus(widget)
    gtkDebugLog("sheet focus widget grab=\(grabbed) target=\(gtkButtonDebugSource("editable", widget: widget))")
    if gtk_swift_widget_is_editable(widget) != 0,
       let delegate = gtk_editable_get_delegate(OpaquePointer(widget)) {
        let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
        gtk_widget_set_can_target(delegateWidget, 1)
        gtk_widget_set_can_focus(delegateWidget, 1)
        gtk_widget_set_focusable(delegateWidget, 1)
        _ = gtk_swift_root_grab_focus(delegateWidget)
        gtkScheduleSheetEditableFocus(delegateWidget)
    }
    gtkScheduleSheetEditableFocus(widget)
}

private func gtkScheduleSheetEditableFocus(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    g_object_ref(gpointer(widget))
    let target = GTKSheetEditableFocusTarget(widget: widget)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let target = Unmanaged<GTKSheetEditableFocusTarget>.fromOpaque(userData).takeRetainedValue()
        defer { g_object_unref(gpointer(target.widget)) }
        guard gtk_swift_is_widget(target.widget) != 0 else { return 0 }
        gtk_widget_set_can_target(target.widget, 1)
        gtk_widget_set_can_focus(target.widget, 1)
        gtk_widget_set_focusable(target.widget, 1)
        let grabbed = gtk_swift_root_grab_focus(target.widget)
        gtkDebugLog("sheet focus idle grab=\(grabbed) target=\(gtkButtonDebugSource("editable", widget: target.widget))")
        return 0
    }, Unmanaged.passRetained(target).toOpaque())
}

private func gtkScheduleFirstSheetEditableFocus(in panel: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(panel) != 0 else { return }
    g_object_ref(gpointer(panel))
    let target = GTKSheetPanelFocusTarget(panel: panel)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let target = Unmanaged<GTKSheetPanelFocusTarget>.fromOpaque(userData).takeUnretainedValue()
        func finish() -> gboolean {
            g_object_unref(gpointer(target.panel))
            Unmanaged<GTKSheetPanelFocusTarget>.fromOpaque(userData).release()
            return 0
        }
        guard gtk_swift_is_widget(target.panel) != 0 else { return finish() }
        // The panel attaches in the same main-loop tick that presents the
        // sheet, so the first idle can run before GTK allocates it; a focus
        // grab then silently fails and the keyboard stays on the sheet's
        // first focusable button (typed spaces activate Cancel). Retry until
        // the panel has a real allocation.
        if gtk_widget_get_width(target.panel) <= 1 {
            target.retries += 1
            if target.retries <= 120 {
                return 1
            }
            gtkDebugLog("sheet first-focus gave up: panel never allocated")
            return finish()
        }
        if let editable = gtkFindFirstSheetEditable(in: target.panel) {
            gtkDebugLog("sheet first-focus found editable after \(target.retries) retries")
            gtkFocusSheetEditableWidget(editable)
        } else {
            gtkDebugLog("sheet first-focus found NO editable in panel")
        }
        return finish()
    }, Unmanaged.passRetained(target).toOpaque())
}

private func gtkFindSheetEditable(
    in widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    rootX: Double,
    rootY: Double
) -> UnsafeMutablePointer<GtkWidget>? {
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = gtkFindSheetEditable(in: current, root: root, rootX: rootX, rootY: rootY) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    guard gtkSheetWidgetIsTextInput(widget),
          gtk_swift_widget_is_topmost_at_root_point(root, widget, rootX, rootY) != 0
    else {
        return nil
    }
    return widget
}

private func gtkFindFirstSheetEditable(
    in widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget>? {
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = gtkFindFirstSheetEditable(in: current) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    return gtkSheetWidgetIsTextInput(widget) ? widget : nil
}

private func gtkSheetWidgetIsTextInput(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    guard gtk_swift_is_widget(widget) != 0 else { return false }
    if gtk_swift_widget_is_editable(widget) != 0 { return true }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    return typeName == "GtkTextView"
}

private func gtkCreateSheetOverlay(
    contentWidget: UnsafeMutablePointer<GtkWidget>,
    sheetWidget: UnsafeMutablePointer<GtkWidget>
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

    let panel = gtkCreateSheetOverlayPanel(sheetWidget: sheetWidget)
    let layer = gtkCreateSheetOverlayLayer(panel: panel)
    gtk_overlay_add_overlay(OpaquePointer(overlay), layer)
    return overlay
}

private func gtkSheetDataKey(_ suffix: String, modifierType: Any.Type) -> String {
    return "swift-sheet-\(String(reflecting: modifierType))-\(suffix)"
}

private class SheetInfo {
    let anchor: UnsafeMutablePointer<GtkWidget>
    let activeKey: String
    let windowKey: String
    let itemIDKey: String
    let transientRoot: gpointer?
    let lifecycleScope: GTKSheetLifecycleScope
    let render: () -> OpaquePointer
    let onDismiss: () -> Void
    /// Dismissal config from sheet content, used to present confirmation dialog on intercept.
    let dismissalConfig: DismissalConfirmationConfiguration?

    init(anchor: UnsafeMutablePointer<GtkWidget>,
         activeKey: String,
         windowKey: String,
         itemIDKey: String = "",
         transientRoot: gpointer?,
         lifecycleScope: GTKSheetLifecycleScope,
         render: @escaping () -> OpaquePointer,
         onDismiss: @escaping () -> Void,
         dismissalConfig: DismissalConfirmationConfiguration? = nil) {
        self.anchor = anchor
        self.activeKey = activeKey
        self.windowKey = windowKey
        self.itemIDKey = itemIDKey
        self.transientRoot = transientRoot
        self.lifecycleScope = lifecycleScope
        self.render = render
        self.onDismiss = onDismiss
        self.dismissalConfig = dismissalConfig
    }
}

private func gtkScheduleSheetDismissal(_ action: @escaping () -> Void) {
    let box = Unmanaged.passRetained(ClosureBox(action)).toOpaque()
    g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        Unmanaged<ClosureBox>.fromOpaque(userData).takeRetainedValue().closure()
        return 0
    }, box)
}

extension SheetModifierView: GTKDescribable {
    /// Describe through to the anchor content; the sheet panel lives on the
    /// root overlay (or a dialog window), not in this widget tree.
    /// Presentation state is encoded in props so flipping isPresented diffs
    /// the descriptor and forces the full rebuild that runs the
    /// present/dismiss path — while steady-state rebuilds stay narrow and
    /// never tear the anchor subtree down.
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "SheetModifierView",
            props: .text(GTK4TextDescriptor(
                content: isPresented.wrappedValue ? "presented" : "dismissed"
            )),
            children: [gtkDescribeView(content)]
        )
    }
}

extension SheetModifierView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        let anchor: UnsafeMutablePointer<GtkWidget>
        if let host = GTKViewHost.getCurrentRebuilding() {
            anchor = host.container
        } else {
            anchor = widget
        }
        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
        let activeKey = gtkSheetDataKey("active", modifierType: type(of: self))
        let windowKey = gtkSheetDataKey("window", modifierType: type(of: self))
        let overlayKey = gtkSheetDataKey("overlay", modifierType: type(of: self))
        gtkDebugLog("sheet bool presented=\(isPresented.wrappedValue) activeKey=\(activeKey)")

        if !isPresented.wrappedValue {
            gtkRemoveSheetRootOverlay(
                anchor: anchor,
                overlayKey: overlayKey,
                activeKey: activeKey,
                onDismiss: onDismiss
            )
            // Dismiss active sheet if binding turned false
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
                let dialog = dialogPtr.assumingMemoryBound(to: GtkWindow.self)
                g_object_set_data(gobject, activeKey, nil)
                g_object_set_data(gobject, windowKey, nil)
                gtk_window_destroy(dialog)
                onDismiss?()
            }
            return opaqueFromWidget(widget)
        }

        if gtkShouldRenderSheetInWindow() {
            let sheetView = sheetContent()
            let binding = isPresented
            let userOnDismiss = onDismiss
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            dismissAction = {
                gtkScheduleSheetDismissal {
                    binding.wrappedValue = false
                    lifecycleScope.runDisappearActions()
                    userOnDismiss?()
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet bool window")
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetView) }
                }
            )
            setCurrentEnvironment(previous)
            return opaqueFromWidget(gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget))
        }

        if gtkShouldRenderSheetInRootOverlay(),
           let rootOverlay = gtkSheetRootOverlay(for: anchor) {
            guard gtkRootSheetLayers[activeKey] == nil else {
                return opaqueFromWidget(widget)
            }
            let sheetView = sheetContent()
            let binding = isPresented
            let userOnDismiss = onDismiss
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            var presentedLayer: UnsafeMutablePointer<GtkWidget>?
            let dismissAction: () -> Void
            dismissAction = {
                gtkScheduleSheetDismissal {
                    binding.wrappedValue = false
                    lifecycleScope.runDisappearActions()
                    _ = gtkRemoveRootSheetLayer(activeKey: activeKey, fallbackLayer: presentedLayer)
                    userOnDismiss?()
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet bool root overlay")
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithRootSheetOverlay(rootOverlay) {
                        gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetView) }
                    }
                }
            )
            setCurrentEnvironment(previous)
            let panel = gtkCreateSheetOverlayPanel(sheetWidget: sheetWidget)
            let layer = gtkCreateSheetOverlayLayer(panel: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: layer)
            gtkStoreRootPresentationOverlay(rootOverlay, on: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)
            presentedLayer = layer
            gtkRootSheetLayers[activeKey] = layer
            gtkAttachRootSheetOverlay(layer, to: rootOverlay)
            return opaqueFromWidget(widget)
        }

        // Guard against duplicate presentation on rebuild
        guard g_object_get_data(gobject, activeKey) == nil else {
            return opaqueFromWidget(widget)
        }
        g_object_set_data(gobject, activeKey, gpointer(bitPattern: 1))
        gtkDebugLog("sheet bool scheduling present activeKey=\(activeKey)")
        g_object_ref(gpointer(anchor))

        let sheetView = sheetContent()
        let binding = isPresented
        let userOnDismiss = onDismiss
        let dismissalConfig = gtkExtractDismissalConfig(from: sheetView)
        let transientRoot = gtk_widget_get_root(anchor).map { gpointer($0) }
            ?? GTKViewHost.getCurrentRebuilding()?.rebuildPresentationRoot
        if let transientRoot {
            g_object_ref(transientRoot)
        }

        let lifecycleScope = GTKSheetLifecycleScope()
        let info = Unmanaged.passRetained(SheetInfo(
            anchor: anchor,
            activeKey: activeKey,
            windowKey: windowKey,
            transientRoot: transientRoot,
            lifecycleScope: lifecycleScope,
            render: { gtkRenderView(sheetView) },
            onDismiss: {
                let obj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
                // Idempotent: guard against double-dismiss from both programmatic and signal paths
                guard g_object_get_data(obj, activeKey) != nil else { return }
                g_object_set_data(obj, activeKey, nil)
                g_object_set_data(obj, windowKey, nil)
                binding.wrappedValue = false
                lifecycleScope.runDisappearActions()
                userOnDismiss?()
            },
            dismissalConfig: dismissalConfig
        )).toOpaque()

        g_idle_add({ userData -> gboolean in
            let info = Unmanaged<SheetInfo>.fromOpaque(userData!).takeRetainedValue()
            let liveRoot = gtk_widget_get_root(info.anchor).map { gpointer($0) }
            guard let root = liveRoot ?? info.transientRoot else {
                info.onDismiss()
                if let transientRoot = info.transientRoot {
                    g_object_unref(transientRoot)
                }
                g_object_unref(gpointer(info.anchor))
                return 0
            }

            let dialog = gtk_window_new()!
            let dialogWin = windowPointer(dialog)
            gtk_window_set_modal(dialogWin, 1)
            gtk_window_set_title(dialogWin, "")
            gtk_window_set_default_size(dialogWin, gtkSheetDefaultWidth(), gtkSheetDefaultHeight())
            gtk_window_set_transient_for(
                dialogWin,
                UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
            )

            // Inject dismiss action into environment
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void = {
                gtkScheduleSheetDismissal {
                    gtk_window_destroy(dialogWin)
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet bool dialog")
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithSheetLifecycleScope(info.lifecycleScope) { info.render() }
                }
            )
            setCurrentEnvironment(previous)
            gtk_window_set_child(dialogWin, sheetWidget)

            let anchorObj = UnsafeMutableRawPointer(info.anchor).assumingMemoryBound(to: GObject.self)
            g_object_set_data(anchorObj, info.windowKey, gpointer(dialogWin))

            if let config = info.dismissalConfig {
                // User-triggered close: show confirmation dialog on top of the sheet
                let closeHandler: () -> Void = {
                    config.isPresented.wrappedValue = true
                    gtkPresentConfirmationDialog(config: config, transientFor: dialogWin, onActualDismiss: info.onDismiss)
                }
                let interceptBox = Unmanaged.passRetained(ClosureBox(closeHandler)).toOpaque()
                g_signal_connect_data(
                    gpointer(dialog),
                    "close-request",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) -> gboolean in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure()
                        return 1 // suppress default close
                    } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self),
                    interceptBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
            } else {
                let dismissBox = Unmanaged.passRetained(ClosureBox(info.onDismiss)).toOpaque()
                g_signal_connect_data(
                    gpointer(dialog),
                    "close-request",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) -> gboolean in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure()
                        return 0
                    } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self),
                    dismissBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
            }

            gtkDebugLog("sheet bool idle present window=\(dialogWin)")
            gtk_window_present(dialogWin)
            if let transientRoot = info.transientRoot {
                g_object_unref(transientRoot)
            }
            g_object_unref(gpointer(info.anchor))
            return 0
        }, info)

        return opaqueFromWidget(widget)
    }
}

extension ItemSheetModifierView: GTKDescribable {
    /// Same contract as SheetModifierView: describe the anchor content and
    /// encode the presented item's identity in props so item changes (present,
    /// dismiss, or switch) force the full rebuild that drives the sheet, and
    /// steady-state rebuilds stay narrow.
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let itemState: String
        if let currentItem = item.wrappedValue {
            itemState = "item-\(currentItem.id.hashValue)"
        } else {
            itemState = "dismissed"
        }
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "ItemSheetModifierView",
            props: .text(GTK4TextDescriptor(content: itemState)),
            children: [gtkDescribeView(content)]
        )
    }
}

extension ItemSheetModifierView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        let anchor: UnsafeMutablePointer<GtkWidget>
        if let host = GTKViewHost.getCurrentRebuilding() {
            anchor = host.container
        } else {
            anchor = widget
        }
        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
        let activeKey = gtkSheetDataKey("active", modifierType: type(of: self))
        let windowKey = gtkSheetDataKey("window", modifierType: type(of: self))
        let overlayKey = gtkSheetDataKey("overlay", modifierType: type(of: self))
        let itemIDKey = gtkSheetDataKey("item-id", modifierType: type(of: self))

        guard let currentItem = item.wrappedValue else {
            gtkRemoveSheetRootOverlay(
                anchor: anchor,
                overlayKey: overlayKey,
                activeKey: activeKey,
                itemIDKey: itemIDKey,
                onDismiss: onDismiss
            )
            // Dismiss active sheet if item became nil
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
                let dialog = dialogPtr.assumingMemoryBound(to: GtkWindow.self)
                g_object_set_data(gobject, activeKey, nil)
                g_object_set_data(gobject, windowKey, nil)
                g_object_set_data(gobject, itemIDKey, nil)
                gtk_window_destroy(dialog)
                onDismiss?()
            }
            return opaqueFromWidget(widget)
        }

        if gtkShouldRenderSheetInWindow() {
            let sheetBuilder = sheetContent
            let itemBinding = item
            let userOnDismiss = onDismiss
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            dismissAction = {
                gtkScheduleSheetDismissal {
                    itemBinding.wrappedValue = nil
                    lifecycleScope.runDisappearActions()
                    userOnDismiss?()
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet item window")
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetBuilder(currentItem)) }
                }
            )
            setCurrentEnvironment(previous)
            return opaqueFromWidget(gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget))
        }

        if gtkShouldRenderSheetInRootOverlay(),
           let rootOverlay = gtkSheetRootOverlay(for: anchor) {
            let currentIdHash = currentItem.id.hashValue
            gtkDebugLog("sheet item root present activeKey=\(activeKey) itemID=\(currentIdHash)")
            if gtkRootSheetLayers[activeKey] != nil {
                if gtkRootSheetItemIDs[activeKey] == currentIdHash {
                    return opaqueFromWidget(widget)
                }
                gtkRemoveSheetRootOverlay(
                    anchor: anchor,
                    overlayKey: overlayKey,
                    activeKey: activeKey,
                    itemIDKey: itemIDKey,
                    onDismiss: onDismiss
                )
            }
            gtkRootSheetItemIDs[activeKey] = currentIdHash
            let sheetBuilder = sheetContent
            let itemBinding = item
            let userOnDismiss = onDismiss
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            var presentedLayer: UnsafeMutablePointer<GtkWidget>?
            let dismissAction: () -> Void
            dismissAction = {
                gtkScheduleSheetDismissal {
                    itemBinding.wrappedValue = nil
                    lifecycleScope.runDisappearActions()
                    _ = gtkRemoveRootSheetLayer(activeKey: activeKey, fallbackLayer: presentedLayer)
                    userOnDismiss?()
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet item root overlay")
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithRootSheetOverlay(rootOverlay) {
                        gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetBuilder(currentItem)) }
                    }
                }
            )
            setCurrentEnvironment(previous)
            let panel = gtkCreateSheetOverlayPanel(sheetWidget: sheetWidget)
            let layer = gtkCreateSheetOverlayLayer(panel: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: layer)
            gtkStoreRootPresentationOverlay(rootOverlay, on: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)
            presentedLayer = layer
            gtkRootSheetLayers[activeKey] = layer
            gtkAttachRootSheetOverlay(layer, to: rootOverlay)
            return opaqueFromWidget(widget)
        }
        gtkDebugLog("sheet item root unavailable activeKey=\(activeKey)")

        // Check if the item identity changed while a sheet is already active
        let currentIdHash = currentItem.id.hashValue
        if g_object_get_data(gobject, activeKey) != nil {
            let storedHash = Int(bitPattern: g_object_get_data(gobject, itemIDKey))
            if storedHash == currentIdHash {
                // Same item — no change needed
                return opaqueFromWidget(widget)
            }
            // Different item — dismiss old sheet, then fall through to present new one
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
                let dialog = dialogPtr.assumingMemoryBound(to: GtkWindow.self)
                g_object_set_data(gobject, activeKey, nil)
                g_object_set_data(gobject, windowKey, nil)
                g_object_set_data(gobject, itemIDKey, nil)
                gtk_window_destroy(dialog)
                onDismiss?()
            }
        }
        g_object_set_data(gobject, activeKey, gpointer(bitPattern: 1))
        g_object_set_data(gobject, itemIDKey, gpointer(bitPattern: currentIdHash))
        g_object_ref(gpointer(anchor))

        let sheetBuilder = sheetContent
        let itemBinding = item
        let userOnDismiss = onDismiss
        let itemDismissalConfig = gtkExtractDismissalConfig(from: sheetBuilder(currentItem))
        let transientRoot = gtk_widget_get_root(anchor).map { gpointer($0) }
            ?? GTKViewHost.getCurrentRebuilding()?.rebuildPresentationRoot
        if let transientRoot {
            g_object_ref(transientRoot)
        }
        let lifecycleScope = GTKSheetLifecycleScope()
        let info = Unmanaged.passRetained(SheetInfo(
            anchor: anchor,
            activeKey: activeKey,
            windowKey: windowKey,
            itemIDKey: itemIDKey,
            transientRoot: transientRoot,
            lifecycleScope: lifecycleScope,
            render: { gtkRenderView(sheetBuilder(currentItem)) },
            onDismiss: {
                let obj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
                // Idempotent: guard against double-dismiss from both programmatic and signal paths
                guard g_object_get_data(obj, activeKey) != nil else { return }
                g_object_set_data(obj, activeKey, nil)
                g_object_set_data(obj, windowKey, nil)
                g_object_set_data(obj, itemIDKey, nil)
                itemBinding.wrappedValue = nil
                lifecycleScope.runDisappearActions()
                userOnDismiss?()
            },
            dismissalConfig: itemDismissalConfig
        )).toOpaque()

        g_idle_add({ userData -> gboolean in
            let info = Unmanaged<SheetInfo>.fromOpaque(userData!).takeRetainedValue()
            let liveRoot = gtk_widget_get_root(info.anchor).map { gpointer($0) }
            guard let root = liveRoot ?? info.transientRoot else {
                info.onDismiss()
                if let transientRoot = info.transientRoot {
                    g_object_unref(transientRoot)
                }
                g_object_unref(gpointer(info.anchor))
                return 0
            }

            let dialog = gtk_window_new()!
            let dialogWin = windowPointer(dialog)
            gtk_window_set_modal(dialogWin, 1)
            gtk_window_set_title(dialogWin, "")
            gtk_window_set_default_size(dialogWin, gtkSheetDefaultWidth(), gtkSheetDefaultHeight())
            gtk_window_set_transient_for(
                dialogWin,
                UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
            )

            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void = {
                gtkScheduleSheetDismissal {
                    gtk_window_destroy(dialogWin)
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet item dialog")
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithSheetLifecycleScope(info.lifecycleScope) { info.render() }
                }
            )
            setCurrentEnvironment(previous)
            gtk_window_set_child(dialogWin, sheetWidget)

            let anchorObj = UnsafeMutableRawPointer(info.anchor).assumingMemoryBound(to: GObject.self)
            g_object_set_data(anchorObj, info.windowKey, gpointer(dialogWin))

            if let config = info.dismissalConfig {
                let closeHandler: () -> Void = {
                    config.isPresented.wrappedValue = true
                    gtkPresentConfirmationDialog(config: config, transientFor: dialogWin, onActualDismiss: info.onDismiss)
                }
                let interceptBox = Unmanaged.passRetained(ClosureBox(closeHandler)).toOpaque()
                g_signal_connect_data(
                    gpointer(dialog),
                    "close-request",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) -> gboolean in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure()
                        return 1
                    } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self),
                    interceptBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
            } else {
                let dismissBox = Unmanaged.passRetained(ClosureBox(info.onDismiss)).toOpaque()
                g_signal_connect_data(
                    gpointer(dialog),
                    "close-request",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) -> gboolean in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure()
                        return 0
                    } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self),
                    dismissBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
            }

            gtk_window_present(dialogWin)
            if let transientRoot = info.transientRoot {
                g_object_unref(transientRoot)
            }
            g_object_unref(gpointer(info.anchor))
            return 0
        }, info)

        return opaqueFromWidget(widget)
    }
}

// MARK: - Alert GTK extension

/// Holds alert button action + dialog reference for cleanup.
private class AlertActionBox {
    let action: () -> Void
    let dialog: UnsafeMutablePointer<GtkWidget>
    init(action: @escaping () -> Void, dialog: UnsafeMutablePointer<GtkWidget>) {
        self.action = action
        self.dialog = dialog
    }
}

extension AlertModifierView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        let anchor: UnsafeMutablePointer<GtkWidget>
        if let host = GTKViewHost.getCurrentRebuilding() {
            anchor = host.container
        } else {
            anchor = widget
        }
        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

        if !isPresented.wrappedValue {
            if let dialogPtr = g_object_get_data(gobject, "swift-alert-window") {
                let dialog = dialogPtr.assumingMemoryBound(to: GtkWindow.self)
                g_object_set_data(gobject, "swift-alert-window", nil)
                gtk_window_destroy(dialog)
            }
            return opaqueFromWidget(widget)
        }

        guard g_object_get_data(gobject, "swift-alert-active") == nil else {
            return opaqueFromWidget(widget)
        }
        g_object_set_data(gobject, "swift-alert-active", gpointer(bitPattern: 1))
        g_object_ref(gpointer(anchor))

        let alertTitle = title
        let alertMessage = message
        let alertButtons = buttons
        let binding = isPresented

        let onDismiss: () -> Void = {
            let obj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
            g_object_set_data(obj, "swift-alert-active", nil)
            g_object_set_data(obj, "swift-alert-window", nil)
            binding.wrappedValue = false
        }

        g_idle_add({ userData -> gboolean in
            let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeRetainedValue()
            // Re-read captured values from the enclosing scope via the closure
            box.closure()
            return 0
        }, Unmanaged.passRetained(ClosureBox { [anchor, alertTitle, alertMessage, alertButtons, onDismiss] in
            guard let root = gtk_widget_get_root(anchor) else {
                onDismiss()
                g_object_unref(gpointer(anchor))
                return
            }

            let dialog = gtk_window_new()!
            let dialogWin = windowPointer(dialog)
            gtk_window_set_modal(dialogWin, 1)
            gtk_window_set_title(dialogWin, alertTitle)
            gtk_window_set_default_size(dialogWin, 350, -1)
            gtk_window_set_resizable(dialogWin, 0)
            gtk_window_set_transient_for(
                dialogWin,
                UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
            )

            let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)!
            gtk_widget_set_margin_top(vbox, 20)
            gtk_widget_set_margin_bottom(vbox, 20)
            gtk_widget_set_margin_start(vbox, 20)
            gtk_widget_set_margin_end(vbox, 20)

            if !alertMessage.isEmpty {
                let msgLabel = gtk_label_new(alertMessage)!
                gtk_label_set_wrap(OpaquePointer(msgLabel), 1)
                gtk_box_append(boxPointer(vbox), msgLabel)
            }

            let buttonBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
            gtk_widget_set_halign(buttonBox, GTK_ALIGN_END)

            for alertButton in alertButtons {
                let btn = gtk_button_new_with_label(alertButton.label)!
                if alertButton.role == .destructive {
                    gtk_widget_add_css_class(btn, "destructive-action")
                }
                let actionBox = Unmanaged.passRetained(AlertActionBox(
                    action: alertButton.action, dialog: dialog
                )).toOpaque()
                g_signal_connect_data(
                    gpointer(btn),
                    "clicked",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                        let box = Unmanaged<AlertActionBox>.fromOpaque(userData!).takeUnretainedValue()
                        box.action()
                        gtk_window_destroy(windowPointer(box.dialog))
                    } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                    actionBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<AlertActionBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
                gtk_box_append(boxPointer(buttonBox), btn)
            }

            gtk_box_append(boxPointer(vbox), buttonBox)
            gtk_window_set_child(dialogWin, vbox)

            let anchorObj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
            g_object_set_data(anchorObj, "swift-alert-window", gpointer(dialogWin))

            let closeDismiss = Unmanaged.passRetained(ClosureBox(onDismiss)).toOpaque()
            g_signal_connect_data(
                gpointer(dialog),
                "close-request",
                unsafeBitCast({ (_: gpointer?, userData: gpointer?) -> gboolean in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure()
                    return 0
                } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self),
                closeDismiss,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )

            gtk_window_present(dialogWin)
            g_object_unref(gpointer(anchor))
        }).toOpaque())

        return opaqueFromWidget(widget)
    }
}

// MARK: - Link GTK extension

extension Link: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let button = gtk_link_button_new_with_label(destination, title)!
        return opaqueFromWidget(button)
    }
}

// MARK: - SecureField GTK extension

extension SecureField: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "SecureField",
            props: .text(GTK4TextDescriptor(content: gtkTextInputFocusDescriptorContent(
                typeName: "SecureField",
                binding: text,
                label: placeholder,
                includeValueWhenUnidentified: false
            )))
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let entry = gtk_password_entry_new()!
        gtk_swift_password_entry_set_show_peek_icon(entry, 1)

        let current = text.wrappedValue
        if !current.isEmpty {
            gtk_editable_set_text(OpaquePointer(entry), current)
        }

        if !placeholder.isEmpty {
            if let delegate = gtk_editable_get_delegate(OpaquePointer(entry)) {
                let textWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkText.self)
                gtk_text_set_placeholder_text(textWidget, placeholder)
            }
        }

        let binding = text
        let box = Unmanaged.passRetained(StringClosureBox { newText in
            if newText != binding.wrappedValue {
                binding.wrappedValue = newText
            }
        }).toOpaque()
        g_signal_connect_data(
            gpointer(entry),
            "changed",
            unsafeBitCast({ (editable: gpointer?, userData: gpointer?) in
                let box = Unmanaged<StringClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let cStr = gtk_editable_get_text(OpaquePointer(editable))!
                box.closure(String(cString: cStr))
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<StringClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        // Wire keyboard actions from environment (same as TextField).
        let environment = getCurrentEnvironment()
        if let submitAction = environment.submitAction {
            gtkWireTextInputSubmit(
                widget: entry,
                signalTarget: gpointer(entry),
                submitAction: submitAction,
                keyPressActions: environment.keyPressActions
            )
        } else {
            gtkInstallTextInputKeyController(
                on: entry,
                submitAction: nil,
                keyPressActions: environment.keyPressActions
            )
        }

        gtkApplyEnabledState(to: entry)
        if let paintedEntry = quill_gtk_text_field_paint_hook?(OpaquePointer(entry), true) {
            gtkApplyInheritedTextInputForegroundIfNeeded(to: entry)
            return paintedEntry
        }
        gtkApplyInheritedTextInputForegroundIfNeeded(to: entry)
        return opaqueFromWidget(entry)
    }
}

// MARK: - TextEditor GTK extension

extension TextEditor: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "TextEditor",
            props: .text(GTK4TextDescriptor(content: gtkTextInputFocusDescriptorContent(
                typeName: "TextEditor",
                binding: text
            )))
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let textView = gtk_text_view_new()!
        let textViewPtr = UnsafeMutableRawPointer(textView).assumingMemoryBound(to: GtkTextView.self)
        gtk_text_view_set_wrap_mode(textViewPtr, GTK_WRAP_WORD_CHAR)
        gtk_text_view_set_accepts_tab(textViewPtr, 1)

        let current = text.wrappedValue
        if !current.isEmpty {
            let buffer = gtk_text_view_get_buffer(textViewPtr)
            gtk_text_buffer_set_text(buffer, current, gint(current.utf8.count))
        }

        let binding = text
        let buffer = gtk_text_view_get_buffer(textViewPtr)!
        let box = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(buffer),
            "changed",
            unsafeBitCast({ (bufferPtr: gpointer?, userData: gpointer?) in
                let box = Unmanaged<StringClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let buf = UnsafeMutableRawPointer(bufferPtr!).assumingMemoryBound(to: GtkTextBuffer.self)
                var start = GtkTextIter()
                var end = GtkTextIter()
                gtk_text_buffer_get_bounds(buf, &start, &end)
                let cStr = gtk_text_buffer_get_text(buf, &start, &end, 0)!
                let result = String(cString: cStr)
                g_free(gpointer(mutating: cStr))
                box.closure(result)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<StringClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        gtkInstallTextInputKeyController(
            on: textView,
            submitAction: nil,
            keyPressActions: getCurrentEnvironment().keyPressActions
        )

        let scrolled = gtk_scrolled_window_new()!
        gtk_scrolled_window_set_policy(OpaquePointer(scrolled), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
        gtk_scrolled_window_set_child(OpaquePointer(scrolled), textView)
        gtk_widget_set_vexpand(scrolled, 1)
        gtk_widget_set_hexpand(scrolled, 1)

        gtkApplyEnabledState(to: textView)
        if let paintedEditor = quill_gtk_text_editor_paint_hook?(
            OpaquePointer(scrolled),
            OpaquePointer(textView)
        ) {
            gtkApplyInheritedTextInputForegroundIfNeeded(to: textView)
            return paintedEditor
        }
        gtkApplyInheritedTextInputForegroundIfNeeded(to: textView)
        return opaqueFromWidget(scrolled)
    }
}

// MARK: - ProgressView GTK extension

extension ProgressView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let bar = gtk_progress_bar_new()!
        if let value = value {
            gtk_progress_bar_set_fraction(
                OpaquePointer(bar),
                gtkSanitizedProgressFraction(value: value, total: total)
            )
        } else {
            gtk_widget_add_css_class(bar, gtkSwiftIndeterminateProgressMarker)
            gtk_progress_bar_set_pulse_step(OpaquePointer(bar), 0.015)
            gtk_progress_bar_pulse(OpaquePointer(bar))
            _ = gtk_widget_add_tick_callback(bar, gtkProgressViewPulseTickCallback, nil, nil)
        }
        gtk_widget_set_hexpand(bar, 1)
        return opaqueFromWidget(bar)
    }
}

private let gtkProgressViewPulseTickCallback: GtkTickCallback = { widget, _, _ in
    guard let widget else { return 0 }
    gtk_progress_bar_pulse(OpaquePointer(widget))
    return 1
}

private func gtkSanitizedProgressFraction(value: Double, total: Double) -> Double {
    guard value.isFinite, total.isFinite, total > 0 else { return 0 }
    return max(0, min(1, value / total))
}

// MARK: - Stepper GTK extension

extension Stepper: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let spin = gtk_swift_spin_button_new_with_range(
            range.lowerBound,
            range.upperBound,
            step
        )!

        gtk_swift_spin_button_set_value(spin, value.wrappedValue)

        let binding = value
        let stepVal = step
        let box = Unmanaged.passRetained(DoubleClosureBox { newValue in
            if abs(newValue - binding.wrappedValue) > stepVal * 0.01 {
                binding.wrappedValue = newValue
            }
        }).toOpaque()
        g_signal_connect_data(
            gpointer(spin),
            "value-changed",
            unsafeBitCast({ (widget: gpointer?, userData: gpointer?) in
                let box = Unmanaged<DoubleClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let val = gtk_swift_spin_button_get_value(
                    UnsafeMutableRawPointer(widget!).assumingMemoryBound(to: GtkWidget.self)
                )
                box.closure(val)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<DoubleClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        if !label.isEmpty {
            let hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
            let lbl = gtk_label_new(label)!
            gtk_box_append(boxPointer(hbox), lbl)
            gtk_box_append(boxPointer(hbox), spin)
            gtkApplyEnabledState(to: spin)
            return opaqueFromWidget(hbox)
        }

        gtkApplyEnabledState(to: spin)
        return opaqueFromWidget(spin)
    }
}

// MARK: - Label GTK extension

private func gtkMaterialNameForSystemImage(_ sfName: String) -> String {
    if let materialName = SFSymbolCompatibility.materialName(for: sfName) {
        return materialName
    }
    #if DEBUG
    FileHandle.standardError.write(Data(
        "[SwiftOpenUI] system image \"\(sfName)\" has no Material mapping; rendering placeholder\n".utf8
    ))
    #endif
    return SFSymbolCompatibility.missingSymbolPlaceholderName
}

extension Label: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!

        if let iconView {
            gtk_box_append(boxPointer(box), widgetFromOpaque(gtkRenderView(iconView)))
        } else if let iconName = systemImage {
            let materialName = gtkMaterialSymbolName(forSystemName: iconName)
            gtk_box_append(boxPointer(box), gtkRenderMaterialSymbolLabel(materialName, scale: .small))
        } else if let path = imagePath {
            let img = gtk_image_new_from_file(path)!
            gtk_box_append(boxPointer(box), img)
        }

        if let titleView, !(titleView is Text) {
            gtk_box_append(boxPointer(box), widgetFromOpaque(gtkRenderView(titleView)))
        } else {
            let lbl = gtk_label_new(title)!
            gtk_box_append(boxPointer(box), lbl)
        }

        return opaqueFromWidget(box)
    }
}

// MARK: - Corner Radius GTK extension

extension CornerRadiusView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        if gtkIsEmptyViewWidget(widget) {
            return opaqueFromWidget(widget)
        }
        applyCSSToWidget(widget, properties: "border-radius: \(Int(radius))px;")
        return opaqueFromWidget(widget)
    }
}

// MARK: - Labels hidden modifier (no-op pass-through)

extension LabelsHiddenView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        // Push `labelsHidden = true` into the env for the content
        // subtree. Picker's renderer (and any future label-bearing
        // control) consults this flag and omits its inline label
        // prefix. Restored on exit so siblings aren't affected.
        var env = getCurrentEnvironment()
        env.labelsHidden = true
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

// MARK: - Help / tooltip modifier

extension HelpView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        // GTK interprets a non-NULL tooltip string (including empty) as
        // "show a tooltip on hover"; passing NULL clears it. Forward
        // whatever the caller provided — empty strings still register
        // so callers can intentionally clear a prior help value.
        gtk_widget_set_tooltip_text(widget, text)
        text.withCString { textPointer in
            gtk_swift_accessible_update_description(widget, textPointer)
        }
        return opaqueFromWidget(widget)
    }
}

// MARK: - Clip Shape GTK extensions

extension ClippedView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let inner = widgetFromOpaque(gtkRenderView(content))
        let widthWrapper = gtk_swift_width_clamp_new(inner)!
        gtk_widget_set_overflow(widthWrapper, GTK_OVERFLOW_HIDDEN)
        if gtk_widget_get_hexpand(inner) != 0 {
            gtk_widget_set_hexpand(widthWrapper, 1)
            gtk_widget_set_halign(inner, GTK_ALIGN_FILL)
        }
        if gtk_widget_get_vexpand(inner) != 0 {
            gtk_widget_set_vexpand(widthWrapper, 1)
            gtk_widget_set_valign(inner, GTK_ALIGN_FILL)
        }
        gtkPropagateSingleChildLayoutMarkers(from: [inner], to: widthWrapper)
        let wrapper = gtk_widget_get_vexpand(inner) != 0 && gtkHasVerticalFillIntent(inner)
            ? gtkCompressibleHeightClamp(widthWrapper)
            : widthWrapper
        return opaqueFromWidget(wrapper)
    }
}

extension ClipShapeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let inner = widgetFromOpaque(gtkRenderView(content))
        let wrapper = gtk_swift_width_clamp_new(inner)!
        gtk_widget_set_overflow(wrapper, GTK_OVERFLOW_HIDDEN)
        if gtk_widget_get_hexpand(inner) != 0 {
            gtk_widget_set_hexpand(wrapper, 1)
            gtk_widget_set_halign(inner, GTK_ALIGN_FILL)
        }
        if gtk_widget_get_vexpand(inner) != 0 {
            gtk_widget_set_vexpand(wrapper, 1)
            gtk_widget_set_valign(inner, GTK_ALIGN_FILL)
        }
        gtkPropagateSingleChildLayoutMarkers(from: [inner], to: wrapper)

        // Map shape type to CSS border-radius for clipping.
        let css: String
        if shape is Circle || shape is Ellipse {
            css = "border-radius: 50%;"
        } else if let rr = shape as? RoundedRectangle {
            css = "border-radius: \(Int(rr.cornerRadius))px;"
        } else if shape is Capsule {
            // Capsule = fully rounded ends (half the shorter dimension).
            // Use a large fixed value; GTK clamps to half the box size.
            css = "border-radius: 9999px;"
        } else {
            // Rectangle or unknown — rect clip only, no border-radius needed
            css = ""
        }
        if !css.isEmpty {
            applyCSSToWidget(wrapper, properties: css)
        }
        return opaqueFromWidget(wrapper)
    }
}

// MARK: - Shadow GTK extension

extension ShadowView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        let r = Int(color.red * 255)
        let g = Int(color.green * 255)
        let b = Int(color.blue * 255)
        let a = String(format: "%.2f", color.alpha)
        let css = """
            box-shadow: \(Int(x))px \(Int(y))px \(Int(radius))px rgba(\(r),\(g),\(b),\(a));
            margin: \(Int(radius))px;
            """
        applyCSSToWidget(widget, properties: css)
        return opaqueFromWidget(widget)
    }
}

// MARK: - Rotation GTK extension

extension RotationView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .rotation, typeName: "RotationView",
            props: .rotation(GTK4RotationDescriptor(angle: angle)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        setWidgetDouble(widget, key: gtkSwiftRotationKey, value: angle)
        let offsetX = getWidgetDouble(widget, key: gtkSwiftOffsetXKey) ?? 0
        let offsetY = getWidgetDouble(widget, key: gtkSwiftOffsetYKey) ?? 0
        let scaleX = getWidgetDouble(widget, key: gtkSwiftScaleXKey) ?? 1
        let scaleY = getWidgetDouble(widget, key: gtkSwiftScaleYKey) ?? 1
        applyCSSToWidget(widget, properties: buildTransformCSS(offsetX: offsetX, offsetY: offsetY, scaleX: scaleX, scaleY: scaleY, rotation: angle))
        return opaqueFromWidget(widget)
    }
}

private protocol GTKDecorativeOverlay {}
extension Circle: GTKDecorativeOverlay {}
extension Rectangle: GTKDecorativeOverlay {}
extension RoundedRectangle: GTKDecorativeOverlay {}
extension Capsule: GTKDecorativeOverlay {}
extension Ellipse: GTKDecorativeOverlay {}
extension FilledShape: GTKDecorativeOverlay {}
extension StrokedShape: GTKDecorativeOverlay {}


// MARK: - Overlay GTK extension

extension OverlayView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let baseWidget = widgetFromOpaque(gtkRenderView(content))
        if gtkIsEmptyViewWidget(baseWidget) {
            return opaqueFromWidget(baseWidget)
        }

        let overlayWidget = widgetFromOpaque(gtkRenderView(overlay))
        if gtkIsEmptyViewWidget(overlayWidget) {
            return opaqueFromWidget(baseWidget)
        }

        let container = gtk_overlay_new()!
        gtk_overlay_set_child(OpaquePointer(container), baseWidget)

        if gtk_widget_get_hexpand(baseWidget) != 0 {
            gtk_widget_set_hexpand(container, 1)
            gtk_widget_set_halign(baseWidget, GTK_ALIGN_FILL)
        }
        if gtk_widget_get_vexpand(baseWidget) != 0 {
            gtk_widget_set_vexpand(container, 1)
            gtk_widget_set_valign(baseWidget, GTK_ALIGN_FILL)
        }

        let (hAlign, vAlign) = gtkAlignFromAlignment(alignment)
        // Respect the overlay widget's own expansion intent. A Shape (or any
        // view with hexpand/vexpand set via .frame(maxWidth: .infinity)) wants
        // to fill its container — overwriting halign to CENTER would shrink
        // it to its natural size (0x0 for GtkDrawingArea) and make it vanish.
        // Only apply the requested alignment on the axes where the widget
        // isn't asking to expand. This matches SwiftUI's "overlay fills when
        // its content fills" semantics; explicit alignment still governs
        // non-filling overlays like Text or Image.
        let overlayWantsHExpand = gtk_widget_get_hexpand(overlayWidget) != 0
        let overlayWantsVExpand =
            gtk_widget_get_vexpand(overlayWidget) != 0 && gtkHasVerticalFillIntent(overlayWidget)
        gtk_widget_set_halign(overlayWidget, overlayWantsHExpand ? GTK_ALIGN_FILL : hAlign)
        gtk_widget_set_valign(overlayWidget, overlayWantsVExpand ? GTK_ALIGN_FILL : vAlign)
        if !overlayWantsVExpand {
            gtk_widget_set_vexpand(overlayWidget, 0)
        }
        if overlay is GTKDecorativeOverlay {
            gtk_widget_set_can_target(overlayWidget, 0)
        }
        gtk_overlay_add_overlay(OpaquePointer(container), overlayWidget)

        return opaqueFromWidget(container)
    }
}

/// Convert SwiftOpenUI Alignment to GTK align pair.
private func gtkAlignFromAlignment(_ alignment: Alignment) -> (GtkAlign, GtkAlign) {
    let h: GtkAlign
    let v: GtkAlign
    switch alignment {
    case .topLeading:     h = GTK_ALIGN_START;  v = GTK_ALIGN_START
    case .top:            h = GTK_ALIGN_CENTER; v = GTK_ALIGN_START
    case .topTrailing:    h = GTK_ALIGN_END;    v = GTK_ALIGN_START
    case .leading:        h = GTK_ALIGN_START;  v = GTK_ALIGN_CENTER
    case .center:         h = GTK_ALIGN_CENTER; v = GTK_ALIGN_CENTER
    case .trailing:       h = GTK_ALIGN_END;    v = GTK_ALIGN_CENTER
    case .bottomLeading:  h = GTK_ALIGN_START;  v = GTK_ALIGN_END
    case .bottom:         h = GTK_ALIGN_CENTER; v = GTK_ALIGN_END
    case .bottomTrailing: h = GTK_ALIGN_END;    v = GTK_ALIGN_END
    }
    return (h, v)
}

// MARK: - Toggle GTK extension

extension Toggle: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let environment = getCurrentEnvironment()

        if let customToggleStyle = environment.customToggleStyle {
            let configuration = ToggleStyleConfiguration(label: AnyView(Text(label)), isOn: isOn)
            return gtkRenderView(customToggleStyle.makeBody(configuration: configuration))
        }

        let toggleStyleType = environment.toggleStyle

        if toggleStyleType == .switch {
            return gtkCreateSwitchWidget()
        }
        // .automatic and .checkbox use GtkCheckButton
        return gtkCreateCheckButtonWidget()
    }

    private func gtkCreateCheckButtonWidget() -> OpaquePointer {
        let check = label.isEmpty || quill_gtk_toggle_paint_hook != nil
            ? gtk_check_button_new()!
            : gtk_check_button_new_with_label(label)!
        let checkPtr = checkButtonPointer(check)

        gtk_check_button_set_active(checkPtr, isOn.wrappedValue ? 1 : 0)

        let binding = isOn
        let box = Unmanaged.passRetained(BoolClosureBox { newValue in
            if newValue != binding.wrappedValue {
                binding.wrappedValue = newValue
            }
        }).toOpaque()
        g_signal_connect_data(
            gpointer(check),
            "toggled",
            unsafeBitCast({ (widget: gpointer?, userData: gpointer?) in
                let box = Unmanaged<BoolClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let ptr = UnsafeMutableRawPointer(widget!).assumingMemoryBound(to: GtkCheckButton.self)
                let active = gtk_check_button_get_active(ptr) != 0
                box.closure(active)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<BoolClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        gtkApplyEnabledState(to: check)
        if let paintedToggle = quill_gtk_toggle_paint_hook?(
            OpaquePointer(check),
            isOn.wrappedValue,
            false,
            label
        ) {
            return paintedToggle
        }
        return opaqueFromWidget(check)
    }

    private func gtkCreateSwitchWidget() -> OpaquePointer {
        let sw = gtk_swift_switch_new()!
        gtk_swift_switch_set_active(sw, isOn.wrappedValue ? 1 : 0)

        let binding = isOn
        let box = Unmanaged.passRetained(BoolClosureBox { newValue in
            if newValue != binding.wrappedValue {
                binding.wrappedValue = newValue
            }
        }).toOpaque()
        g_signal_connect_data(
            gpointer(sw),
            "notify::active",
            unsafeBitCast({ (widget: gpointer?, _: gpointer?, userData: gpointer?) in
                let box = Unmanaged<BoolClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let w = UnsafeMutableRawPointer(widget!).assumingMemoryBound(to: GtkWidget.self)
                let active = gtk_swift_switch_get_active(w) != 0
                box.closure(active)
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<BoolClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        gtkApplyEnabledState(to: sw)
        if let paintedToggle = quill_gtk_toggle_paint_hook?(
            OpaquePointer(sw),
            isOn.wrappedValue,
            true,
            label
        ) {
            return paintedToggle
        }

        if label.isEmpty {
            return opaqueFromWidget(sw)
        }

        // Wrap switch + label in a horizontal box.
        // Add a click gesture on the box so clicking the label toggles the switch.
        let hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
        let lbl = gtk_label_new(label)!
        gtk_box_append(boxPointer(hbox), lbl)
        gtk_box_append(boxPointer(hbox), sw)

        // Add click gesture on the label (not the box) so clicking the label
        // toggles the switch. Attaching to the box would double-toggle when
        // the click lands directly on the GtkSwitch.
        let gesture = gtk_gesture_click_new()!
        let toggleBox = Unmanaged.passRetained(ClosureBox {
            let active = gtk_swift_switch_get_active(sw) != 0
            gtk_swift_switch_set_active(sw, active ? 0 : 1)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(gesture),
            "released",
            unsafeBitCast({ (_: gpointer?, _: gint, _: Double, _: Double, userData: gpointer?) in
                guard let userData = userData else { return }
                Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void, to: GCallback.self),
            toggleBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<ClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )
        gtk_swift_add_gesture(lbl, gesture)

        // Apply enabled state to the whole wrapper so label dims too
        gtkApplyEnabledState(to: hbox)
        return opaqueFromWidget(hbox)
    }
}

// MARK: - Slider GTK extension

/// Debounced slider state. Accumulates value changes and commits after
/// a short delay so dragging doesn't trigger constant rebuilds.
/// Also manages interactive update deferral: suppresses host rebuilds
/// during pointer drag, commits one rebuild on pointer release.
private class SliderState {
    let closure: (Double) -> Void
    weak var host: GTKViewHost?
    var pendingValue: Double = 0
    var timerSource: guint = 0
    var dragging = false

    init(closure: @escaping (Double) -> Void) {
        self.closure = closure
    }

    func scheduleCommit(_ value: Double) {
        pendingValue = value
        if timerSource != 0 {
            g_source_remove(timerSource)
            timerSource = 0
        }
        let ptr = Unmanaged.passRetained(self).toOpaque()
        timerSource = g_timeout_add_full(
            G_PRIORITY_DEFAULT_IDLE,
            150,
            { userData -> gboolean in
                let state = Unmanaged<SliderState>.fromOpaque(userData!).takeUnretainedValue()
                state.timerSource = 0
                state.closure(state.pendingValue)
                return 0 // G_SOURCE_REMOVE
            },
            ptr,
            { userData in
                Unmanaged<SliderState>.fromOpaque(userData!).release()
            }
        )
    }
}

extension Slider: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .slider, typeName: "Slider",
            props: .slider(GTK4SliderDescriptor(
                value: value.wrappedValue, range: range, step: step)))
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let scale = gtk_scale_new_with_range(
            GTK_ORIENTATION_HORIZONTAL,
            range.lowerBound,
            range.upperBound,
            step
        )!

        gtk_widget_set_hexpand(scale, 1)
        gtk_range_set_value(rangePointer(scale), value.wrappedValue)
        gtkMarkHostedNodeKind(scale, kind: .slider)

        let binding = value
        let stepVal = step
        let state = SliderState { newValue in
            if abs(newValue - binding.wrappedValue) > stepVal * 0.01 {
                binding.wrappedValue = newValue
            }
        }
        state.host = GTKViewHost.getCurrentRebuilding()
        let statePtr = Unmanaged.passRetained(state).toOpaque()

        // Value-changed: debounced binding update
        g_signal_connect_data(
            gpointer(scale),
            "value-changed",
            unsafeBitCast({ (widget: gpointer?, userData: gpointer?) in
                let state = Unmanaged<SliderState>.fromOpaque(userData!).takeUnretainedValue()
                let rng = UnsafeMutableRawPointer(widget!).assumingMemoryBound(to: GtkRange.self)
                state.scheduleCommit(gtk_range_get_value(rng))
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            statePtr,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<SliderState>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        // Note: interactive deferral (beginInteractiveUpdate/endInteractiveUpdate)
        // removed — GtkGestureClick's "released" doesn't fire when the slider
        // drag starts (GTK cancels the click gesture). This left
        // interactiveUpdateDepth stuck > 0, blocking all future rebuilds.
        // The debounced commit (150ms) already prevents constant rebuilds.

        gtkApplyEnabledState(to: scale)
        return opaqueFromWidget(scale)
    }
}

// MARK: - ScrollView GTK extension

private let gtkRefreshActionDataKey = "gtk-swift-refresh-action-box"
private let gtkRefreshOverscrollAttachedKey = "gtk-swift-refresh-overscroll-attached"

private func gtkRefreshDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_REFRESHABLE"] == "1" else { return }
    if let data = ("[QuillUI GTK Refreshable] " + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private final class GTKRefreshActionBox {
    let action: @Sendable () async -> Void
    private var activeTask: Task<Void, Never>?

    init(action: @escaping @Sendable () async -> Void) {
        self.action = action
    }

    deinit {
        activeTask?.cancel()
    }

    func trigger(source: String) {
        guard activeTask == nil else {
            gtkRefreshDebugLog("ignored overlapping refresh source=\(source)")
            return
        }

        gtkRefreshDebugLog("trigger source=\(source)")
        gtkFlushPendingTextBindingUpdate()
        let action = action
        activeTask = Task { @MainActor [weak self] in
            await action()
            self?.activeTask = nil
            gtkRefreshDebugLog("completed source=\(source)")
        }
    }
}

private func gtkWidgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func gtkIsScrolledWindowWidget(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    gtkWidgetTypeName(widget) == "GtkScrolledWindow"
}

private func gtkAttachRefreshOverscrollHandler(
    to scrolled: UnsafeMutablePointer<GtkWidget>,
    actionBox: GTKRefreshActionBox
) {
    let gobject = UnsafeMutableRawPointer(scrolled).assumingMemoryBound(to: GObject.self)
    guard g_object_get_data(gobject, gtkRefreshOverscrollAttachedKey) == nil else {
        return
    }
    g_object_set_data(gobject, gtkRefreshOverscrollAttachedKey, UnsafeMutableRawPointer(bitPattern: 1))

    let pointer = Unmanaged.passUnretained(actionBox).toOpaque()
    g_signal_connect_data(
        gpointer(scrolled),
        "edge-overshot",
        unsafeBitCast({ (_: gpointer?, position: GtkPositionType, userData: gpointer?) in
            guard position == GTK_POS_TOP, let userData else { return }
            let box = Unmanaged<GTKRefreshActionBox>.fromOpaque(userData).takeUnretainedValue()
            box.trigger(source: "edge-overshot")
        } as @convention(c) (gpointer?, GtkPositionType, gpointer?) -> Void, to: GCallback.self),
        pointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtkRefreshDebugLog("attached overscroll handler")
}

private func gtkAttachRefreshHandlersInTree(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    actionBox: GTKRefreshActionBox
) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    if gtkIsScrolledWindowWidget(widget) {
        gtkAttachRefreshOverscrollHandler(to: widget, actionBox: actionBox)
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkAttachRefreshHandlersInTree(current, actionBox: actionBox)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkAttachRefreshAction(
    to widget: UnsafeMutablePointer<GtkWidget>,
    action: @escaping @Sendable () async -> Void
) {
    let actionBox = GTKRefreshActionBox(action: action)
    let actionBoxPointer = Unmanaged.passRetained(actionBox).toOpaque()
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data_full(
        gobject,
        gtkRefreshActionDataKey,
        actionBoxPointer,
        { userData in
            guard let userData else { return }
            Unmanaged<GTKRefreshActionBox>.fromOpaque(userData).release()
        }
    )

    let windowID = getCurrentEnvironment().windowID
    let registrationID = KeyboardShortcutRegistry.shared.register(
        KeyboardShortcut(KeyEquivalent("r"), modifiers: .command),
        windowID: windowID
    ) {
        actionBox.trigger(source: "keyboard")
    }
    let unregisterBox = Unmanaged.passRetained(ClosureBox {
        KeyboardShortcutRegistry.shared.unregister(id: registrationID)
    }).toOpaque()
    g_signal_connect_data(
        gpointer(widget),
        "destroy",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        unregisterBox,
        { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
            if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
        },
        GConnectFlags(rawValue: 0)
    )

    gtkAttachRefreshHandlersInTree(widget, actionBox: actionBox)
    gtkRefreshDebugLog("attached refresh action windowID=\(windowID)")
}

extension RefreshableView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "RefreshableView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        gtkAttachRefreshAction(to: widget, action: action)
        return opaqueFromWidget(widget)
    }
}

extension ScrollView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        // Transparent wrapper: describe content so child Canvas nodes
        // participate in the narrow mutation path.
        let childDescriptor = gtkDescribeView(content)
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "ScrollView",
            children: [childDescriptor]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let scrolled = gtk_scrolled_window_new()!
        gtkMarkSwiftUIScrollView(scrolled, hasVerticalAxis: axes.contains(.vertical))
        let scrolledOp = OpaquePointer(scrolled)

        let visibleScrollPolicy: GtkPolicyType = showsIndicators ? GTK_POLICY_AUTOMATIC : GTK_POLICY_EXTERNAL
        let hPolicy: GtkPolicyType = axes.contains(.horizontal) ? visibleScrollPolicy : GTK_POLICY_NEVER
        let vPolicy: GtkPolicyType = axes.contains(.vertical) ? visibleScrollPolicy : GTK_POLICY_NEVER
        gtk_scrolled_window_set_policy(scrolledOp, hPolicy, vPolicy)

        // Prevent GTK from allocating the child's full natural size
        // in the scroll direction — otherwise scrolling never activates.
        if axes.contains(.horizontal) {
            gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
            gtk_scrolled_window_set_min_content_width(scrolledOp, 1)
        }
        if axes.contains(.vertical) {
            gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)
            gtk_scrolled_window_set_min_content_height(scrolledOp, 1)
        }

        let child = widgetFromOpaque(gtkRenderView(content))
        let childWantsVerticalFill = gtkHasVerticalFillIntent(child)
        if axes.contains(.vertical) {
            gtk_widget_set_vexpand(child, 0)
        }
        if axes.contains(.horizontal) {
            gtk_widget_set_hexpand(child, 0)
        }
        if axes.contains(.vertical) && !axes.contains(.horizontal) {
            // SwiftUI lays vertical ScrollView content out in the viewport
            // width. This lets rows that rely on HStack + Spacer, such as
            // chat bubbles and settings rows, align against the visible
            // scroll area instead of their natural text width.
            gtk_widget_set_hexpand(child, 1)
            gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        }
        if axes.contains(.horizontal) && !axes.contains(.vertical) {
            // A horizontal-only SwiftUI ScrollView has the natural height of
            // its content. If it advertises vertical expansion, fixed-height
            // rows such as IceCubes' status summary buttons allocate the
            // scroller as the row's fill child and clip neighboring labels.
            // Keep explicit container-relative/full-height pagers fillable.
            gtk_widget_set_vexpand(child, childWantsVerticalFill ? 1 : 0)
            gtk_widget_set_valign(child, childWantsVerticalFill ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER)
        }
        gtk_scrolled_window_set_child(scrolledOp, child)
        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: axes.contains(.horizontal) && !axes.contains(.vertical)
        )

        let scrollerWantsVerticalFill = axes.contains(.vertical)
            || (axes.contains(.horizontal) && !axes.contains(.vertical) && childWantsVerticalFill)
        gtk_widget_set_vexpand(scrolled, scrollerWantsVerticalFill ? 1 : 0)
        if scrollerWantsVerticalFill {
            gtkMarkVerticalFillIntent(scrolled)
        }
        gtk_widget_set_hexpand(scrolled, 1)

        return opaqueFromWidget(scrolled)
    }
}

// MARK: - Image GTK extension

extension Image: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        switch source {
        case .systemName(let sfName):
            // M-Symbols-3: route Image(systemName:) through the curated
            // SF→Material compatibility map. Mapped names render the
            // corresponding Material glyph (uniform across all GTK4
            // themes/distros); unmapped names render the "missing icon"
            // placeholder glyph so the gap is visible rather than silent.
            //
            // This replaces the previous GTK icon-name path. Any app
            // that was passing a freedesktop-style icon
            // name (e.g. "folder-new-symbolic") — not SwiftUI-canonical —
            // will now see the placeholder; it should switch to a real
            // SF name or use `Image(material:)` for direct Material
            // names.
            let materialName = gtkMaterialSymbolName(forSystemName: sfName)
            return opaqueFromWidget(gtkRenderMaterialSymbolLabel(materialName, scale: scale))

        case .filePath(let path):
            // Use GtkPicture (GTK4's scalable image widget) rather than
            // GtkImage (fixed-size icon widget).  GtkPicture honors its
            // parent's allocation and scales the loaded pixbuf accordingly,
            // which matches SwiftUI's `.resizable()` semantics.
            let picture = gtk_swift_picture_new_for_filename(path)!
            if isResizable {
                // Stretch to fill the surrounding frame.  GTK_CONTENT_FIT_FILL
                // disables aspect-ratio preservation to match SwiftUI.
                gtk_swift_picture_set_content_fit(picture, GTK_CONTENT_FIT_FILL)
                gtk_swift_picture_set_can_shrink(picture, 1)
                gtk_widget_set_hexpand(picture, 1)
                gtk_widget_set_vexpand(picture, 1)
                gtkMarkVerticalFillIntent(picture)
                gtk_widget_set_halign(picture, GTK_ALIGN_FILL)
                gtk_widget_set_valign(picture, GTK_ALIGN_FILL)
            } else {
                // Natural size: GtkPicture reports the pixbuf's intrinsic
                // dimensions as its natural size.  Surrounding frames
                // position but do not scale the image.
                gtk_swift_picture_set_content_fit(picture, GTK_CONTENT_FIT_CONTAIN)
                gtk_swift_picture_set_can_shrink(picture, 0)
            }
            return opaqueFromWidget(picture)

        case .materialSymbol(let name):
            return opaqueFromWidget(gtkRenderMaterialSymbolLabel(name, scale: scale))
        }
    }
}

private func gtkMaterialSymbolName(forSystemName sfName: String) -> String {
    guard let materialName = SFSymbolCompatibility.materialName(for: sfName) else {
        #if DEBUG
        FileHandle.standardError.write(Data(
            "[SwiftOpenUI] Image(systemName: \"\(sfName)\") has no Material mapping; rendering placeholder\n".utf8
        ))
        #endif
        return SFSymbolCompatibility.missingSymbolPlaceholderName
    }
    return materialName
}

/// Render a Material Symbols glyph as a GtkLabel via Pango markup.
/// Shared helper used by both `.materialSymbol` and `.systemName` (the
/// latter via the SF→Material compatibility map). The Material Symbols
/// Rounded family is registered process-locally at backend startup by
/// `gtkRegisterBundledIconFont()`; OpenType ligatures in the font
/// substitute the literal name ("search", "folder_open", ...) into the
/// icon glyph during text shaping.
///
/// Pango's font_size attribute uses thousandths of a point. Material
/// Symbols' Linux line metrics run taller than SF Symbols; keep the
/// requested box at `ImageScale.pointSize`, but draw medium/large glyphs
/// slightly smaller so system icons do not inflate 20pt SwiftUI rows.
private func gtkRenderMaterialSymbolLabel(
    _ name: String,
    scale: ImageScale
) -> UnsafeMutablePointer<GtkWidget> {
    let label = gtk_label_new(nil)!
    let familyName = gtkEscapeMarkup(MaterialSymbolsRoundedFamilyName)
    let codepoint = MaterialSymbolsCodepoints.codepoint(for: name)
        ?? MaterialSymbolsCodepoints.missingGlyphCodepoint
    let glyph = Unicode.Scalar(codepoint).map(String.init) ?? "?"
    let escapedGlyph = gtkEscapeMarkup(glyph)
    let glyphPointSize = gtkMaterialSymbolGlyphPointSize(for: scale)
    let foreground = gtkPangoColorHex(gtkGetCurrentForegroundColor())
    let markup = """
        <span font_family="\(familyName)" font_size="\(glyphPointSize * 1000)" foreground="\(foreground)">\(escapedGlyph)</span>
        """
    gtk_swift_label_set_markup(label, markup)
    let px = gint(scale.pointSize)
    gtk_widget_set_size_request(label, px, px)
    return label
}

private func gtkPangoColorHex(_ color: Color) -> String {
    let r = Int(min(max(color.red, 0), 1) * 255)
    let g = Int(min(max(color.green, 0), 1) * 255)
    let b = Int(min(max(color.blue, 0), 1) * 255)
    return String(format: "#%02X%02X%02X", r, g, b)
}

private func gtkMaterialSymbolGlyphPointSize(for scale: ImageScale) -> Int {
    switch scale {
    case .small:
        return scale.pointSize
    case .medium, .large:
        return max(1, Int((Double(scale.pointSize) * 0.8).rounded()))
    }
}

/// Material Symbols Rounded font family name, resolved via SwiftOpenUISymbols.
/// Used by the .materialSymbol Image renderer. Kept as a file-scope constant
/// to keep the Pango markup construction tight.
private let MaterialSymbolsRoundedFamilyName: String =
    MaterialSymbolsResources.roundedRegularFamilyName

/// Minimal Pango-markup-safe escape. Pango's markup parser treats these
/// characters specially; escape the four that show up in user-supplied icon
/// names or family strings. Not a general-purpose XML escape; sufficient
/// for internal use where the inputs are known to be icon tokens like
/// "folder_open".
private func gtkEscapeMarkup(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        default: out.append(ch)
        }
    }
    return out
}

// MARK: - List GTK extension

private struct GTKRowMetadata {
    var insets: EdgeInsets?
    var separatorVisibility: Visibility = .automatic
    var separatorEdges: Edge.Set = .all
}

private let gtkDefaultRowInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
private let gtkListRowLifecycleDataKey = "gtk-swift-list-row-lifecycle-box"

private func gtkListDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_LIST"] == "1" else { return }
    if let data = ("[QuillUI GTK List] " + message + "\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private protocol GTKListRowWrapper {
    func gtkFlattenedListRows(depth: Int) -> [any View]
}

private protocol GTKKeyedListRowProducer {
    func gtkKeyedListRows(depth: Int) -> [any View]
}

private struct GTKListRowActiveTask {
    let lifecycleID: String?
    let task: Task<Void, Never>
}

private final class GTKListRowLifecycleBox {
    let source: String
    let onAppearPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4OnAppearPayload]
    let taskPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4TaskPayload]
    private var isVisible = false
    private var activeTasksByIdentity: [GTK4DescriptorIdentity: GTKListRowActiveTask] = [:]

    init(
        source: String,
        onAppearPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4OnAppearPayload],
        taskPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4TaskPayload]
    ) {
        self.source = source
        self.onAppearPayloadsByIdentity = onAppearPayloadsByIdentity
        self.taskPayloadsByIdentity = taskPayloadsByIdentity
    }

    deinit {
        cancelActiveTasks()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard !isVisible else { return }
            isVisible = true
            gtkListDebugLog(
                "row lifecycle visible source=\(source) onAppear=\(onAppearPayloadsByIdentity.count) tasks=\(taskPayloadsByIdentity.count)"
            )
            onAppearPayloadsByIdentity.values.forEach { $0.action() }
            for (identity, payload) in taskPayloadsByIdentity {
                startTask(identity: identity, payload: payload)
            }
        } else if isVisible {
            gtkListDebugLog("row lifecycle hidden source=\(source)")
            isVisible = false
            cancelActiveTasks()
        }
    }

    private func startTask(identity: GTK4DescriptorIdentity, payload: GTK4TaskPayload) {
        if activeTasksByIdentity[identity]?.lifecycleID == payload.lifecycleID {
            return
        }
        activeTasksByIdentity[identity]?.task.cancel()
        let action = payload.action
        activeTasksByIdentity[identity] = GTKListRowActiveTask(
            lifecycleID: payload.lifecycleID,
            task: Task(priority: payload.priority) {
                await action()
            }
        )
    }

    private func cancelActiveTasks() {
        activeTasksByIdentity.values.forEach { $0.task.cancel() }
        activeTasksByIdentity.removeAll()
    }
}

private final class GTKListViewportLifecycleController {
    let scrolled: UnsafeMutablePointer<GtkWidget>
    let listBox: UnsafeMutablePointer<GtkWidget>

    init(scrolled: UnsafeMutablePointer<GtkWidget>, listBox: UnsafeMutablePointer<GtkWidget>) {
        self.scrolled = scrolled
        self.listBox = listBox
    }

    func updateVisibleRows() -> gboolean {
        guard gtk_swift_is_widget(scrolled) != 0,
              gtk_swift_is_widget(listBox) != 0 else {
            return 0
        }

        var row = gtk_widget_get_first_child(listBox)
        while let current = row {
            if let lifecycle = gtkListRowLifecycleBox(from: current) {
                lifecycle.setVisible(gtkListRowIsVisible(current, in: scrolled))
            }
            row = gtk_widget_get_next_sibling(current)
        }

        return 1
    }
}

private let gtkListViewportLifecycleTickCallback: GtkTickCallback = { _, _, userData in
    guard let userData else { return 0 }
    let controller = Unmanaged<GTKListViewportLifecycleController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return controller.updateVisibleRows()
}

extension ForEach: GTKKeyedListRowProducer {
    fileprivate func gtkKeyedListRows(depth: Int) -> [any View] {
        data.map { item in
            GTKStateNamespaceView(
                component: gtkForEachStateIdentityComponent(for: item[keyPath: id]),
                content: content(item)
            )
        }
    }
}

extension EnvironmentModifierView: GTKListRowWrapper {
    fileprivate func gtkFlattenedListRows(depth: Int) -> [any View] {
        gtkDirectChildViews(of: content, depth: depth + 1).map {
            AnyView($0).environment(keyPath, value)
        }
    }
}

extension EnvironmentObjectModifierView: GTKListRowWrapper {
    fileprivate func gtkFlattenedListRows(depth: Int) -> [any View] {
        gtkDirectChildViews(of: content, depth: depth + 1).map {
            AnyView($0).environmentObject(object)
        }
    }
}

extension EnvironmentObservableModifierView: GTKListRowWrapper {
    fileprivate func gtkFlattenedListRows(depth: Int) -> [any View] {
        gtkDirectChildViews(of: content, depth: depth + 1).map {
            AnyView($0).environment(object)
        }
    }
}

private func gtkDirectChildViews<V: View>(of view: V, depth: Int = 0) -> [any View] {
    guard depth < 24 else { return [view] }

    let mirror = Mirror(reflecting: view)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first?.value as? any View else { return [] }
        return gtkDirectChildViews(ofAny: child, depth: depth + 1)
    }

    if mirror.displayStyle == .enum,
       String(reflecting: Swift.type(of: view)).contains("_ConditionalView") {
        for child in mirror.children {
            if let nested = child.value as? any View {
                return gtkDirectChildViews(ofAny: nested, depth: depth + 1)
            }
        }
        return []
    }

    if let keyedRows = view as? GTKKeyedListRowProducer {
        let children = keyedRows.gtkKeyedListRows(depth: depth + 1)
        if depth == 0 {
            gtkListDebugLog("root keyed=\(String(reflecting: type(of: view))) rows=\(children.count)")
        }
        return children
    }

    if let multi = view as? any TransparentMultiChildView {
        let children = multi.children.flatMap { gtkDirectChildViews(ofAny: $0, depth: depth + 1) }
        if depth == 0 {
            gtkListDebugLog("root multi=\(String(reflecting: type(of: view))) rows=\(children.count)")
            for (index, child) in children.enumerated() {
                gtkListDebugLog("  row[\(index)]=\(String(reflecting: type(of: child)))")
            }
        }
        return children
    }
    if let wrapper = view as? GTKListRowWrapper {
        let children = wrapper.gtkFlattenedListRows(depth: depth + 1)
        gtkListDebugLog(
            "wrapper=\(String(reflecting: type(of: view))) rows=\(children.count)"
        )
        if !children.isEmpty {
            return children
        }
    }
    if V.Body.self != Never.self, gtkViewTypeNameSuggestsListRowProducer(view) {
        let bodyChildren: [any View]
        if hasReactiveProperties(view), let host = GTKViewHost.getCurrentRebuilding() {
            let namespace = gtkRestoreAndInstallInlineState(view, host: host)
            bodyChildren = gtkWithForcedStateIdentityNamespace(namespace) {
                MainActor.assumeIsolated {
                    gtkDirectChildViews(of: view.body, depth: depth + 1)
                }
            }
        } else {
            bodyChildren = MainActor.assumeIsolated {
                gtkDirectChildViews(of: view.body, depth: depth + 1)
            }
        }
        gtkListDebugLog(
            "producer=\(String(reflecting: type(of: view))) bodyRows=\(bodyChildren.count)"
        )
        if !bodyChildren.isEmpty {
            return bodyChildren
        }
    }
    return [view]
}

private func gtkDirectChildViews(ofAny view: any View, depth: Int = 0) -> [any View] {
    func unwrap<V: View>(_ typedView: V) -> [any View] {
        gtkDirectChildViews(of: typedView, depth: depth)
    }
    return unwrap(view)
}

private func gtkDescribeListRowLifecycleScope(
    _ view: any View,
    index: Int
) -> GTK4DescriptorNode {
    GTK4DescriptorNode(
        kind: .listRowLifecycleScope,
        typeName: "GTKListRowLifecycleScope<\(index)>",
        children: [
            gtkWithSuppressedDescriptorLifecyclePayloads {
                gtkDescribeAnyView(view)
            }
        ]
    )
}

private func gtkBuildListRowLifecycleBox(
    for view: any View,
    source: String
) -> GTKListRowLifecycleBox? {
    let described = gtkDescribeCapturingCanvasPayloads {
        gtkDescribeAnyView(view)
    }
    guard !described.onAppearPayloads.isEmpty || !described.taskPayloads.isEmpty else {
        return nil
    }

    let identified = gtkIdentifyDescriptorTree(described.descriptor)
    let onAppearPayloads = gtkOnAppearPayloadsByIdentity(
        descriptorRoot: identified,
        payloads: described.onAppearPayloads
    )
    let taskPayloads = gtkTaskPayloadsByIdentity(
        descriptorRoot: identified,
        payloads: described.taskPayloads
    )
    guard !onAppearPayloads.isEmpty || !taskPayloads.isEmpty else {
        return nil
    }

    return GTKListRowLifecycleBox(
        source: source,
        onAppearPayloadsByIdentity: onAppearPayloads,
        taskPayloadsByIdentity: taskPayloads
    )
}

private func gtkAttachListRowLifecycleData(
    to row: UnsafeMutablePointer<GtkWidget>,
    view: any View,
    source: String
) {
    guard let lifecycle = gtkBuildListRowLifecycleBox(for: view, source: source) else {
        return
    }
    gtkListDebugLog(
        "row lifecycle attach source=\(source) onAppear=\(lifecycle.onAppearPayloadsByIdentity.count) tasks=\(lifecycle.taskPayloadsByIdentity.count)"
    )
    g_object_set_data_full(
        UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
        gtkListRowLifecycleDataKey,
        Unmanaged.passRetained(lifecycle).toOpaque(),
        { userData in
            guard let userData else { return }
            Unmanaged<GTKListRowLifecycleBox>.fromOpaque(userData).release()
        }
    )
}

private func gtkListRowLifecycleBox(
    from row: UnsafeMutablePointer<GtkWidget>
) -> GTKListRowLifecycleBox? {
    guard let lifecycleData = g_object_get_data(
        UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
        gtkListRowLifecycleDataKey
    ) else {
        return nil
    }
    return Unmanaged<GTKListRowLifecycleBox>
        .fromOpaque(lifecycleData)
        .takeUnretainedValue()
}

private func gtkListRowIsVisible(
    _ row: UnsafeMutablePointer<GtkWidget>,
    in scrolled: UnsafeMutablePointer<GtkWidget>
) -> Bool {
    guard gtk_widget_get_mapped(scrolled) != 0,
          gtk_widget_get_mapped(row) != 0,
          gtk_widget_get_visible(row) != 0 else {
        return false
    }

    var rowX: gdouble = 0
    var rowY: gdouble = 0
    guard gtk_widget_translate_coordinates(row, scrolled, 0, 0, &rowX, &rowY) != 0 else {
        return false
    }

    let rowHeight = Double(max(1, gtk_widget_get_height(row)))
    let viewportHeight = Double(max(1, gtk_widget_get_height(scrolled)))
    let margin = 8.0
    return Double(rowY) < viewportHeight + margin
        && Double(rowY) + rowHeight > -margin
}

private func gtkInstallListViewportLifecycleController(
    on scrolled: UnsafeMutablePointer<GtkWidget>,
    listBox: UnsafeMutablePointer<GtkWidget>
) {
    let controller = GTKListViewportLifecycleController(scrolled: scrolled, listBox: listBox)
    let pointer = Unmanaged.passRetained(controller).toOpaque()
    _ = gtk_widget_add_tick_callback(
        scrolled,
        gtkListViewportLifecycleTickCallback,
        pointer,
        { userData in
            guard let userData else { return }
            Unmanaged<GTKListViewportLifecycleController>.fromOpaque(userData).release()
        }
    )
}

private func gtkFormChildViews<V: View>(of view: V, depth: Int = 0) -> [any View] {
    guard depth < 24 else { return [view] }
    return gtkDirectChildViews(of: view, depth: depth).flatMap { child in
        gtkFlattenSectionProducingFormChild(child, depth: depth + 1)
    }
}

private func gtkFlattenSectionProducingFormChild(_ view: any View, depth: Int) -> [any View] {
    func flatten<V: View>(_ typedView: V) -> [any View] {
        gtkFlattenSectionProducingTypedFormChild(typedView, depth: depth)
    }
    return flatten(view)
}

private func gtkFlattenSectionProducingTypedFormChild<V: View>(_ view: V, depth: Int) -> [any View] {
    guard depth < 24 else { return [view] }
    if gtkIsSectionView(view) {
        return [view]
    }

    if V.Body.self != Never.self, gtkViewTypeNameSuggestsFormSectionProducer(view) {
        let bodyChildren = MainActor.assumeIsolated {
            gtkFormChildViews(of: view.body, depth: depth + 1)
        }
        if bodyChildren.contains(where: gtkIsSectionView) {
            return bodyChildren
        }
    }

    return [view]
}

private func gtkViewTypeNameSuggestsFormSectionProducer(_ view: any View) -> Bool {
    let typeName = String(describing: type(of: view))
    let reflectedTypeName = String(reflecting: type(of: view))
    return typeName.hasSuffix("Section")
        || typeName.hasSuffix("Sections")
        || reflectedTypeName.hasSuffix("Section")
        || reflectedTypeName.hasSuffix("Sections")
}

private func gtkViewTypeNameSuggestsListRowProducer(_ view: any View) -> Bool {
    let typeName = String(describing: type(of: view))
    let reflectedTypeName = String(reflecting: type(of: view))
    return typeName.contains("ListView")
        || typeName.contains("Rows")
        || typeName.contains("RowsView")
        || reflectedTypeName.contains("ListView")
        || reflectedTypeName.contains("Rows")
        || reflectedTypeName.contains("RowsView")
}

private func gtkRowMetadata(from view: any View) -> GTKRowMetadata {
    var metadata = GTKRowMetadata()
    gtkCollectRowMetadata(from: view, into: &metadata, depth: 0)
    return metadata
}

private func gtkCollectRowMetadata(from value: Any, into metadata: inout GTKRowMetadata, depth: Int) {
    guard depth < 24 else { return }

    if let insetsProvider = value as? any ListRowInsetsProvider {
        metadata.insets = insetsProvider.listRowInsets
        gtkCollectRowMetadata(from: insetsProvider.listRowContent, into: &metadata, depth: depth + 1)
        return
    }

    if let separatorProvider = value as? any ListRowSeparatorProvider {
        metadata.separatorVisibility = separatorProvider.listRowSeparatorVisibility
        metadata.separatorEdges = separatorProvider.listRowSeparatorEdges
        gtkCollectRowMetadata(from: separatorProvider.listRowSeparatorContent, into: &metadata, depth: depth + 1)
        return
    }

    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        guard child.label == "content" || child.label == "wrapped" || child.label == "base" else {
            continue
        }
        if let nested = child.value as? any View {
            gtkCollectRowMetadata(from: nested, into: &metadata, depth: depth + 1)
            return
        }
    }
}

private func gtkRowInsets(_ metadata: GTKRowMetadata) -> EdgeInsets {
    metadata.insets ?? gtkDefaultRowInsets
}

private func gtkSeparatorIsHidden(_ metadata: GTKRowMetadata) -> Bool {
    metadata.separatorVisibility == .hidden || metadata.separatorVisibility == .never
}

private func gtkViewIsPlainTextRow(_ value: Any, depth: Int = 0) -> Bool {
    guard depth < 24 else { return false }
    if value is Text { return true }

    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first?.value as? any View else { return false }
        return gtkViewIsPlainTextRow(child, depth: depth + 1)
    }
    if mirror.displayStyle == .enum {
        for child in mirror.children {
            if let nested = child.value as? any View {
                return gtkViewIsPlainTextRow(nested, depth: depth + 1)
            }
        }
    }

    if value is any MultiChildView { return false }

    let typeName = String(describing: Swift.type(of: value))
    if typeName.contains("Button<")
        || typeName.contains("HStack<")
        || typeName.contains("VStack<")
        || typeName.contains("ZStack<")
        || typeName.contains("LabeledContent<")
        || typeName.contains("LayoutContainer<")
        || typeName.contains("Form<")
        || typeName.contains("Section<") {
        return false
    }

    if let insetsProvider = value as? any ListRowInsetsProvider {
        return gtkViewIsPlainTextRow(insetsProvider.listRowContent, depth: depth + 1)
    }
    if let separatorProvider = value as? any ListRowSeparatorProvider {
        return gtkViewIsPlainTextRow(separatorProvider.listRowSeparatorContent, depth: depth + 1)
    }

    for child in mirror.children {
        guard child.label == "content" || child.label == "wrapped" || child.label == "base" else {
            continue
        }
        if let nested = child.value as? any View {
            return gtkViewIsPlainTextRow(nested, depth: depth + 1)
        }
    }
    return false
}

private let gtkRowLabelWrapThreshold = 40
private let gtkRowLabelMinWidthChars: gint = 24
private let gtkRowLabelMaxWidthChars: gint = 88
private let gtkRowLabelAverageCharWidth: gint = 9
private let gtkPlainListRowMinimumHeight: gint = 56
private let gtkComplexListRowMinimumHeight: gint = 112
private var gtkRowTextRenderContextStack: [Bool] = []

private var gtkIsRenderingRowContent: Bool {
    !gtkRowTextRenderContextStack.isEmpty
}

private func gtkWithRowTextRenderContext<Result>(
    includeShortPlainText: Bool,
    _ body: () -> Result
) -> Result {
    gtkRowTextRenderContextStack.append(includeShortPlainText)
    defer { _ = gtkRowTextRenderContextStack.popLast() }
    return body()
}

private func gtkPrepareRowTextLabel(_ label: UnsafeMutablePointer<GtkWidget>, text: String) {
    guard let includeShortPlainText = gtkRowTextRenderContextStack.last else { return }
    guard includeShortPlainText || text.count >= gtkRowLabelWrapThreshold else { return }
    let labelOp = OpaquePointer(label)
    gtk_label_set_wrap(labelOp, 1)
    gtk_label_set_wrap_mode(labelOp, PANGO_WRAP_WORD_CHAR)
    gtk_label_set_lines(labelOp, -1)
    gtk_label_set_width_chars(labelOp, gtkRowLabelMaxWidthChars)
    gtk_label_set_max_width_chars(labelOp, gtkRowLabelMaxWidthChars)
}

private func gtkConstrainRowTextLabels(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    includeShortPlainText: Bool
) {
    gtkConstrainRowTextLabels(
        widget,
        includeShortPlainText: includeShortPlainText,
        widthChars: gtkRowLabelMaxWidthChars
    )
}

private func gtkConstrainRowTextLabels(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    includeShortPlainText: Bool,
    widthChars: gint
) {
    for label in findAllGtkLabels(in: widget) {
        let labelOp = OpaquePointer(label)
        let existingLines = gtk_label_get_lines(labelOp)
        if existingLines == 1 {
            continue
        }
        let text = originalLabelText(label) ?? String(cString: gtk_label_get_text(labelOp))
        if !includeShortPlainText && text.count < gtkRowLabelWrapThreshold {
            continue
        }
        gtk_label_set_wrap(labelOp, 1)
        gtk_label_set_wrap_mode(labelOp, PANGO_WRAP_WORD_CHAR)
        gtk_label_set_lines(labelOp, existingLines > 1 ? existingLines : -1)
        gtk_label_set_width_chars(labelOp, widthChars)
        gtk_label_set_max_width_chars(labelOp, widthChars)
        gtk_widget_set_hexpand(label, 1)
        gtk_widget_set_halign(label, GTK_ALIGN_FILL)
    }
}

private func gtkRowLabelWidthChars(forWidth width: gint) -> gint {
    max(gtkRowLabelMinWidthChars, min(gtkRowLabelMaxWidthChars, width / gtkRowLabelAverageCharWidth))
}

private func gtkUpdateWrappingRowLabelWidths(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    forWidth width: gint
) {
    let widthChars = gtkRowLabelWidthChars(forWidth: width)
    for label in findAllGtkLabels(in: widget) {
        let labelOp = OpaquePointer(label)
        guard gtk_label_get_wrap(labelOp) != 0 else { continue }
        gtk_label_set_width_chars(labelOp, widthChars)
        gtk_label_set_max_width_chars(labelOp, widthChars)
        gtk_widget_set_hexpand(label, 1)
        gtk_widget_set_halign(label, GTK_ALIGN_FILL)
    }
}

private func gtkRenderRowContent(
    _ view: any View,
    metadata: GTKRowMetadata? = nil,
    minimumHeight: gint? = nil,
    installPrimaryActionFallback: Bool = false
) -> UnsafeMutablePointer<GtkWidget> {
    let resolvedMetadata = metadata ?? gtkRowMetadata(from: view)
    let insets = gtkRowInsets(resolvedMetadata)
    let includeShortPlainText = gtkViewIsPlainTextRow(view)
    let primaryAction = installPrimaryActionFallback ? gtkPrimaryTapAction(inAny: view) : nil
    let primaryActionAllowsButtonTarget = view is any GTKNavigationPrimaryActionProvider
    let child = gtkWithRowTextRenderContext(includeShortPlainText: includeShortPlainText) {
        widgetFromOpaque(gtkRenderAnyView(view))
    }
    if gtkIsEmptyViewWidget(child) {
        return gtkCreateEmptyViewWidget()
    }
    gtkConstrainRowTextLabels(child, includeShortPlainText: includeShortPlainText)
    gtk_widget_set_hexpand(child, 1)
    gtk_widget_set_vexpand(child, 0)
    gtk_widget_set_halign(child, GTK_ALIGN_FILL)
    gtk_widget_set_valign(child, GTK_ALIGN_START)
    gtk_widget_set_margin_top(child, gint(insets.top))
    gtk_widget_set_margin_bottom(child, gint(insets.bottom))
    gtk_widget_set_margin_start(child, gint(insets.leading))
    gtk_widget_set_margin_end(child, gint(insets.trailing))

    let wrapper = gtk_swift_compressible_width_clamp_new(child)!
    gtk_widget_set_hexpand(wrapper, 1)
    gtk_widget_set_vexpand(wrapper, 0)
    gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
    gtk_widget_set_valign(wrapper, GTK_ALIGN_START)
    if let minimumHeight {
        gtk_widget_set_size_request(wrapper, -1, minimumHeight)
    }
    gtkInstallRowWidthFill(on: wrapper, child: child)
    if let primaryAction {
        let source = "FormRow<\(String(reflecting: Swift.type(of: view)))>"
        let rowTapActionBox = gtkInstallListRowTapFallback(
            on: wrapper,
            source: source,
            action: primaryAction,
            allowButtonTarget: primaryActionAllowsButtonTarget
        )
        gtkAttachListRowTapActionData(to: child, box: rowTapActionBox)
    }
    return wrapper
}

private func gtkListRowMinimumHeight(for view: any View) -> gint {
    let environmentMinimum = max(gint(1), gint(getCurrentEnvironment().defaultMinListRowHeight))
    if let explicitHeight = gtkExplicitFrameHeight(in: view) {
        return max(environmentMinimum, gtkPixelSize(explicitHeight))
    }
    let contentMinimum = gtkViewIsPlainTextRow(view)
        ? gtkPlainListRowMinimumHeight
        : gtkComplexListRowMinimumHeight
    return max(environmentMinimum, contentMinimum)
}

private func gtkExplicitFrameHeight(in value: Any, depth: Int = 0) -> Double? {
    guard depth < 24 else { return nil }

    let typeName = String(reflecting: Swift.type(of: value))
    if typeName.contains("FrameView") {
        for child in Mirror(reflecting: value).children where child.label == "height" {
            return child.value as? Double
        }
    }

    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first else { return nil }
        return gtkExplicitFrameHeight(in: child.value, depth: depth + 1)
    }
    if mirror.displayStyle == .enum {
        for child in mirror.children {
            if let height = gtkExplicitFrameHeight(in: child.value, depth: depth + 1) {
                return height
            }
        }
    }

    for child in mirror.children {
        guard child.label == "content" || child.label == "wrapped" || child.label == "base" else {
            continue
        }
        if let height = gtkExplicitFrameHeight(in: child.value, depth: depth + 1) {
            return height
        }
    }
    return nil
}

private func gtkAppendRows(
    _ rows: [any View],
    to box: UnsafeMutablePointer<GtkWidget>,
    includeOuterSeparators: Bool = false,
    installPrimaryActionFallback: Bool = true
) {
    guard !rows.isEmpty else { return }
    for (index, rowView) in rows.enumerated() {
        let metadata = gtkRowMetadata(from: rowView)
        gtk_box_append(
            boxPointer(box),
            gtkRenderRowContent(
                rowView,
                metadata: metadata,
                installPrimaryActionFallback: installPrimaryActionFallback
            )
        )
        let isLast = index == rows.count - 1
        if (!isLast || includeOuterSeparators) && !gtkSeparatorIsHidden(metadata) {
            gtk_box_append(boxPointer(box), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))
        }
    }
}

private final class GTKListRowTapActionBox {
    let action: () -> Void
    let source: String
    let allowButtonTarget: Bool
    var lastActivationTime: TimeInterval = 0

    init(action: @escaping () -> Void, source: String, allowButtonTarget: Bool = false) {
        self.action = action
        self.source = source
        self.allowButtonTarget = allowButtonTarget
    }
}

private final class GTKListRowGeometryBox {
    let estimatedHeight: Double
    let source: String
    let namespace: String

    init(estimatedHeight: Double, source: String, namespace: String) {
        self.estimatedHeight = estimatedHeight
        self.source = source
        self.namespace = namespace
    }
}

private enum GTKCollapsedRowControl {
    case button(box: GTKButtonActionBox, naturalWidth: Double)
    case menu(button: UnsafeMutablePointer<GtkWidget>, naturalWidth: Double)

    var naturalWidth: Double {
        switch self {
        case .button(_, let naturalWidth), .menu(_, let naturalWidth):
            naturalWidth
        }
    }
}

private final class GTKCollapsedRowControlsBox {
    let controls: [GTKCollapsedRowControl]

    init(controls: [GTKCollapsedRowControl]) {
        self.controls = controls
    }
}

private let gtkListRowTapActionDataKey = "gtk-swift-list-row-tap-action"
private let gtkListRowGeometryDataKey = "gtk-swift-list-row-geometry"
private let gtkCollapsedListRowControlsDataKey = "gtk-swift-collapsed-list-row-controls"
private let gtkListRowGlobalDispatcherDataKey = "gtk-swift-list-row-global-dispatcher"

private final class GTKListRowIdleActionContext {
    let box: GTKListRowTapActionBox
    let source: String

    init(box: GTKListRowTapActionBox, source: String) {
        self.box = box
        self.source = source
    }
}

private final class GTKListRowRootEventContext {
    let row: UnsafeMutablePointer<GtkWidget>
    let box: GTKListRowTapActionBox
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?
    var loggedRootUnavailable = false

    init(row: UnsafeMutablePointer<GtkWidget>, box: GTKListRowTapActionBox) {
        self.row = row
        self.box = box
    }

    func removeController() {
        guard let root, let controller else { return }
        gtk_swift_remove_event_controller(root, controller)
        self.root = nil
        self.controller = nil
    }
}

private final class GTKListBoxRootEventContext {
    let listBox: UnsafeMutablePointer<GtkWidget>
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?
    var loggedRootUnavailable = false

    init(listBox: UnsafeMutablePointer<GtkWidget>) {
        self.listBox = listBox
    }

    func removeController() {
        guard let root, let controller else { return }
        gtk_swift_remove_event_controller(root, controller)
        self.root = nil
        self.controller = nil
    }
}

private final class GTKListRowGlobalRootDispatcher {
    let root: UnsafeMutablePointer<GtkWidget>
    var controller: gpointer?

    init(root: UnsafeMutablePointer<GtkWidget>) {
        self.root = root
    }
}

private func gtkPrimaryTapAction(inAny view: any View, depth: Int = 0) -> (() -> Void)? {
    func inspect<V: View>(_ typedView: V) -> (() -> Void)? {
        gtkPrimaryTapAction(in: typedView, depth: depth)
    }
    return inspect(view)
}

private func gtkPrimaryTapAction<V: View>(in view: V, depth: Int = 0) -> (() -> Void)? {
    guard depth < 32 else { return nil }

    if let tapProvider = view as? any GTKPrimaryTapActionProvider,
       tapProvider.gtkTapGestureCount == 1 {
        gtkDebugLog("list primary action tap depth=\(depth) type=\(String(reflecting: Swift.type(of: view)))")
        return bindActionToCurrentEnvironment(tapProvider.gtkTapGestureAction)
    }

    if let navigationProvider = view as? any GTKNavigationPrimaryActionProvider,
       let action = navigationProvider.gtkNavigationPrimaryAction {
        gtkDebugLog("list primary action navigation depth=\(depth) type=\(String(reflecting: Swift.type(of: view)))")
        return action
    }

    if let erased = view as? AnyView {
        return gtkPrimaryTapAction(inAny: erased.wrapped, depth: depth + 1)
    }

    if let background = view as? any GTKBackgroundActionProvider {
        if let action = gtkPrimaryTapAction(
            inAny: background.gtkPrimaryActionBackground,
            depth: depth + 1
        ) {
            gtkDebugLog("list primary action background depth=\(depth) type=\(String(reflecting: Swift.type(of: view)))")
            return action
        }
        return gtkPrimaryTapAction(inAny: background.gtkPrimaryActionContent, depth: depth + 1)
    }

    if let overlay = view as? any GTKOverlayActionProvider {
        if let action = gtkPrimaryTapAction(
            inAny: overlay.gtkPrimaryActionContent,
            depth: depth + 1
        ) {
            return action
        }
        return gtkPrimaryTapAction(inAny: overlay.gtkPrimaryActionOverlay, depth: depth + 1)
    }

    if let namespaced = view as? any GTKStateNamespaceActionProvider {
        return gtkWithStateIdentityNamespaceComponent(namespaced.gtkStateNamespaceComponent) {
            gtkPrimaryTapAction(inAny: namespaced.gtkStateNamespaceContent, depth: depth + 1)
        }
    }

    let mirror = Mirror(reflecting: view)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first?.value as? any View else { return nil }
        return gtkPrimaryTapAction(inAny: child, depth: depth + 1)
    }

    if mirror.displayStyle == .enum,
       String(reflecting: Swift.type(of: view)).contains("_ConditionalView") {
        for child in mirror.children {
            if let nested = child.value as? any View {
                return gtkPrimaryTapAction(inAny: nested, depth: depth + 1)
            }
        }
        return nil
    }

    for child in mirror.children {
        guard child.label == "content"
            || child.label == "wrapped"
            || child.label == "base"
            || child.label == "label"
        else {
            continue
        }
        if let nested = child.value as? any View,
           let action = gtkPrimaryTapAction(inAny: nested, depth: depth + 1) {
            return action
        }
    }

    if V.Body.self != Never.self {
        return MainActor.assumeIsolated {
            gtkPrimaryTapAction(in: view.body, depth: depth + 1)
        }
    }

    return nil
}

private func gtkScheduleListRowTapAction(
    _ box: GTKListRowTapActionBox,
    source: String,
    deferAction: Bool = true
) {
    let now = Date().timeIntervalSinceReferenceDate
    if now - box.lastActivationTime < 0.08 {
        gtkDebugLog("list row tap duplicate \(source) \(box.source)")
        return
    }
    box.lastActivationTime = now
    gtkDebugLog("list row tap pressed \(source) \(box.source)")
    gtkFlushPendingTextBindingUpdate()
    if !deferAction {
        gtkDebugLog("list row tap action \(source) \(box.source)")
        box.action()
        return
    }
    let context = Unmanaged.passRetained(
        GTKListRowIdleActionContext(box: box, source: source)
    ).toOpaque()
    g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKListRowIdleActionContext>.fromOpaque(userData).takeRetainedValue()
        gtkDebugLog("list row tap action \(context.source) \(context.box.source)")
        context.box.action()
        return 0
    }, context)
}

private func gtkVisualListBoxActionRowAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> UnsafeMutablePointer<GtkWidget>? {
    guard depth < 160 else { return nil }
    guard gtk_widget_get_visible(widget) != 0, gtk_widget_get_mapped(widget) != 0 else { return nil }

    if gtk_swift_widget_is_list_box_row(widget) != 0,
       gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y),
       g_object_get_data(
           UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
           gtkListRowTapActionDataKey
       ) != nil {
        return widget
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let row = gtkVisualListBoxActionRowAtRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            return row
        }
        child = gtk_widget_get_next_sibling(current)
    }

    return nil
}

private func gtkVisualListRowActionWidgetAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> UnsafeMutablePointer<GtkWidget>? {
    guard depth < 160 else { return nil }
    guard gtk_widget_get_visible(widget) != 0, gtk_widget_get_mapped(widget) != 0 else { return nil }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let match = gtkVisualListRowActionWidgetAtRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            return match
        }
        child = gtk_widget_get_next_sibling(current)
    }

    guard gtk_swift_widget_is_button(widget) == 0,
          gtk_swift_widget_is_menu_button(widget) == 0,
          gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y),
          g_object_get_data(
              UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
              gtkListRowTapActionDataKey
          ) != nil
    else {
        return nil
    }
    return widget
}

private func gtkPickedListBoxActionRowAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> UnsafeMutablePointer<GtkWidget>? {
    var current = gtk_swift_root_point_pick_widget(root, x, y)
    var depth = 0
    while let widget = current, depth < 96 {
        if gtk_swift_widget_is_list_box_row(widget) != 0,
           g_object_get_data(
               UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
               gtkListRowTapActionDataKey
           ) != nil {
            return widget
        }
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }
    return nil
}

private func gtkPickedListRowActionWidgetAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> UnsafeMutablePointer<GtkWidget>? {
    var current = gtk_swift_root_point_pick_widget(root, x, y)
    var depth = 0
    while let widget = current, depth < 96 {
        if gtk_swift_widget_is_button(widget) == 0,
           gtk_swift_widget_is_menu_button(widget) == 0,
           g_object_get_data(
               UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
               gtkListRowTapActionDataKey
           ) != nil {
            return widget
        }
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }
    return nil
}

private func gtkListRowTapActionData(
    from widget: UnsafeMutablePointer<GtkWidget>?
) -> gpointer? {
    guard let widget else { return nil }
    return g_object_get_data(
        UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self),
        gtkListRowTapActionDataKey
    )
}

private func gtkAttachListRowGeometryData(
    to row: UnsafeMutablePointer<GtkWidget>,
    estimatedHeight: Double,
    source: String,
    namespace: String
) {
    let object = UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self)
    g_object_set_data_full(
        object,
        gtkListRowGeometryDataKey,
        Unmanaged.passRetained(
            GTKListRowGeometryBox(estimatedHeight: estimatedHeight, source: source, namespace: namespace)
        ).toOpaque(),
        { userData in
            guard let userData else { return }
            Unmanaged<GTKListRowGeometryBox>.fromOpaque(userData).release()
        }
    )
}

private func gtkListRowGeometry(
    _ row: UnsafeMutablePointer<GtkWidget>
) -> GTKListRowGeometryBox? {
    guard let geometryData = g_object_get_data(
        UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
        gtkListRowGeometryDataKey
    ) else {
        return nil
    }
    return Unmanaged<GTKListRowGeometryBox>.fromOpaque(geometryData).takeUnretainedValue()
}

private func gtkEstimatedListRowHeight(
    _ row: UnsafeMutablePointer<GtkWidget>
) -> Double {
    if let geometry = gtkListRowGeometry(row) {
        return max(1, geometry.estimatedHeight)
    }
    return Double(gtkComplexListRowMinimumHeight)
}

private func gtkMeasuredNaturalWidth(
    _ widget: UnsafeMutablePointer<GtkWidget>
) -> Double {
    var minimumWidth: gint = 0
    var naturalWidth: gint = 0
    gtk_swift_widget_measure(
        widget,
        GTK_ORIENTATION_HORIZONTAL,
        -1,
        &minimumWidth,
        &naturalWidth
    )
    return Double(max(minimumWidth, naturalWidth, gtk_widget_get_width(widget)))
}

private func gtkCollectCollapsedRowControls(
    in widget: UnsafeMutablePointer<GtkWidget>,
    into controls: inout [GTKCollapsedRowControl],
    depth: Int = 0
) {
    guard depth < 160 else { return }
    guard gtk_widget_get_visible(widget) != 0,
          gtk_widget_get_sensitive(widget) != 0,
          gtk_widget_get_opacity(widget) > 0.001 else { return }

    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    if gtk_swift_widget_is_menu_button(widget) != 0,
       let modelData = g_object_get_data(object, gtkSwiftMenuOverlayModelKey) {
        let model = Unmanaged<GTKMenuOverlayModel>.fromOpaque(modelData).takeUnretainedValue()
        guard !model.elements.isEmpty else { return }
        controls.append(.menu(button: widget, naturalWidth: gtkMeasuredNaturalWidth(widget)))
        return
    }

    if gtk_swift_widget_is_button(widget) != 0,
       let actionData = g_object_get_data(object, gtkSwiftButtonActionBoxDataKey) {
        let box = Unmanaged<GTKButtonActionBox>.fromOpaque(actionData).takeUnretainedValue()
        controls.append(.button(box: box, naturalWidth: gtkMeasuredNaturalWidth(widget)))
        return
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkCollectCollapsedRowControls(in: current, into: &controls, depth: depth + 1)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkAttachCollapsedListRowControlsData(
    to row: UnsafeMutablePointer<GtkWidget>,
    content: UnsafeMutablePointer<GtkWidget>
) {
    var controls: [GTKCollapsedRowControl] = []
    gtkCollectCollapsedRowControls(in: content, into: &controls)
    guard !controls.isEmpty else { return }
    let summary = controls.enumerated().map { index, control -> String in
        let kind: String
        switch control {
        case .button:
            kind = "button"
        case .menu:
            kind = "menu"
        }
        return "#\(index):\(kind):\(Int(control.naturalWidth))"
    }.joined(separator: ",")
    gtkDebugLog("collapsed-list controls attached count=\(controls.count) [\(summary)]")

    let object = UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self)
    g_object_set_data_full(
        object,
        gtkCollapsedListRowControlsDataKey,
        Unmanaged.passRetained(GTKCollapsedRowControlsBox(controls: controls)).toOpaque(),
        { userData in
            guard let userData else { return }
            Unmanaged<GTKCollapsedRowControlsBox>.fromOpaque(userData).release()
        }
    )
}

private func gtkCollapsedListRowControls(
    from row: UnsafeMutablePointer<GtkWidget>
) -> GTKCollapsedRowControlsBox? {
    guard let controlsData = g_object_get_data(
        UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
        gtkCollapsedListRowControlsDataKey
    ) else {
        return nil
    }
    return Unmanaged<GTKCollapsedRowControlsBox>
        .fromOpaque(controlsData)
        .takeUnretainedValue()
}

private struct GTKCollapsedListRowHit {
    let row: UnsafeMutablePointer<GtkWidget>
    let rowLocalY: Double
    let estimatedHeight: Double
    let namespace: String
    let actionData: gpointer?
    let controls: GTKCollapsedRowControlsBox?
}

private struct GTKCollapsedListContentHit {
    let widget: UnsafeMutablePointer<GtkWidget>
    let frame: (x: Double, y: Double, width: Double, height: Double)
}

private func gtkFirstCollapsedListRowHit(
    in widget: UnsafeMutablePointer<GtkWidget>,
    localY: Double,
    depth: Int = 0
) -> GTKCollapsedListRowHit? {
    guard depth < 160 else { return nil }
    guard gtk_widget_get_visible(widget) != 0, gtk_widget_get_mapped(widget) != 0 else { return nil }

    if gtk_swift_widget_is_list_box(widget) != 0 {
        var cursor = 0.0
        var child = gtk_widget_get_first_child(widget)
        while let row = child {
            defer { child = gtk_widget_get_next_sibling(row) }
            guard gtk_swift_widget_is_list_box_row(row) != 0 else { continue }
            let height = gtkEstimatedListRowHeight(row)
            let rowMinY = cursor
            let rowMaxY = cursor + height
            if localY >= rowMinY && localY < rowMaxY {
                let geometry = gtkListRowGeometry(row)
                return GTKCollapsedListRowHit(
                    row: row,
                    rowLocalY: localY - rowMinY,
                    estimatedHeight: height,
                    namespace: geometry?.namespace ?? "",
                    actionData: gtkListRowTapActionData(from: row),
                    controls: gtkCollapsedListRowControls(from: row)
                )
            }
            cursor = rowMaxY
        }
        if cursor > localY {
            return nil
        }
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let hit = gtkFirstCollapsedListRowHit(
            in: current,
            localY: localY,
            depth: depth + 1
        ) {
            return hit
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return nil
}

private func gtkFirstCollapsedListRowHitWithControls(
    in widget: UnsafeMutablePointer<GtkWidget>,
    localY: Double,
    depth: Int = 0
) -> GTKCollapsedListRowHit? {
    guard depth < 160 else { return nil }
    guard gtk_widget_get_visible(widget) != 0, gtk_widget_get_mapped(widget) != 0 else { return nil }

    if gtk_swift_widget_is_list_box(widget) != 0 {
        var cursor = 0.0
        var child = gtk_widget_get_first_child(widget)
        while let row = child {
            defer { child = gtk_widget_get_next_sibling(row) }
            guard gtk_swift_widget_is_list_box_row(row) != 0 else { continue }
            let height = gtkEstimatedListRowHeight(row)
            let rowMinY = cursor
            let rowMaxY = cursor + height
            let controls = gtkCollapsedListRowControls(from: row)
            let controlsHitSlop = controls == nil ? 0 : 64.0
            if localY >= rowMinY && localY < rowMaxY + controlsHitSlop,
               let controls {
                let geometry = gtkListRowGeometry(row)
                let rowLocalY = min(max(localY - rowMinY, 0), max(1, height) - 1)
                return GTKCollapsedListRowHit(
                    row: row,
                    rowLocalY: rowLocalY,
                    estimatedHeight: height,
                    namespace: geometry?.namespace ?? "",
                    actionData: gtkListRowTapActionData(from: row),
                    controls: controls
                )
            }
            cursor = rowMaxY
        }
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let hit = gtkFirstCollapsedListRowHitWithControls(
            in: current,
            localY: localY,
            depth: depth + 1
        ) {
            return hit
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return nil
}

private func gtkCollapsedListRowHit(
    inListBox listBox: UnsafeMutablePointer<GtkWidget>,
    localY: Double
) -> GTKCollapsedListRowHit? {
    guard gtk_swift_widget_is_list_box(listBox) != 0 else { return nil }
    var cursor = 0.0
    var child = gtk_widget_get_first_child(listBox)
    while let row = child {
        defer { child = gtk_widget_get_next_sibling(row) }
        guard gtk_swift_widget_is_list_box_row(row) != 0 else { continue }
        let height = gtkEstimatedListRowHeight(row)
        let rowMinY = cursor
        let rowMaxY = cursor + height
        if localY >= rowMinY && localY < rowMaxY {
            let geometry = gtkListRowGeometry(row)
            return GTKCollapsedListRowHit(
                row: row,
                rowLocalY: localY - rowMinY,
                estimatedHeight: height,
                namespace: geometry?.namespace ?? "",
                actionData: gtkListRowTapActionData(from: row),
                controls: gtkCollapsedListRowControls(from: row)
            )
        }
        cursor = rowMaxY
    }
    return nil
}

private func gtkPickedCollapsedListRowHitAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> GTKCollapsedListRowHit? {
    var current = gtk_swift_root_point_pick_widget(root, x, y)
    var depth = 0
    while let widget = current, depth < 96 {
        if gtk_swift_widget_is_list_box(widget) != 0 {
            var listX = 0.0
            var listY = 0.0
            guard gtk_swift_widget_compute_point(root, widget, x, y, &listX, &listY) != 0 else {
                return nil
            }
            return gtkCollapsedListRowHit(inListBox: widget, localY: listY)
        }
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }
    return nil
}

private func gtkVisualCollapsedListRowHitAtRootPoint(
    in widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    contentFrame: (x: Double, y: Double, width: Double, height: Double),
    depth: Int = 0
) -> GTKCollapsedListRowHit? {
    guard depth < 160 else { return nil }
    guard gtk_widget_get_visible(widget) != 0, gtk_widget_get_mapped(widget) != 0 else { return nil }

    if gtk_swift_widget_is_list_box(widget) != 0,
       let frame = gtkWidgetVisualFrameInRoot(widget, root: root) {
        let containsPoint = x >= frame.x
            && x < frame.x + frame.width
            && y >= frame.y
            && y < frame.y + frame.height
        let overlapsContent = frame.x < contentFrame.x + contentFrame.width
            && frame.x + frame.width > contentFrame.x
            && frame.y < contentFrame.y + contentFrame.height
            && frame.y + frame.height > contentFrame.y
        if containsPoint && overlapsContent {
            var listX = 0.0
            var listY = 0.0
            if gtk_swift_widget_compute_point(root, widget, x, y, &listX, &listY) != 0,
               let hit = gtkCollapsedListRowHit(inListBox: widget, localY: listY) {
                return hit
            }
        }
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let hit = gtkVisualCollapsedListRowHitAtRootPoint(
            in: current,
            root: root,
            x: x,
            y: y,
            contentFrame: contentFrame,
            depth: depth + 1
        ) {
            return hit
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return nil
}

private func gtkFirstCollapsedListRowActionData(
    in widget: UnsafeMutablePointer<GtkWidget>,
    localY: Double,
    depth: Int = 0
) -> gpointer? {
    gtkFirstCollapsedListRowHit(in: widget, localY: localY, depth: depth)?.actionData
}

private func gtkCollapsedListContentHitAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> GTKCollapsedListContentHit? {
    var current = gtk_swift_root_point_pick_widget(root, x, y)
    var depth = 0
    let rootWidth = Double(max(1, gtk_widget_get_width(root)))
    let rootHeight = Double(max(1, gtk_widget_get_height(root)))
    let minimumContentWidth = min(240, max(160, rootWidth * 0.30))
    let minimumContentHeight = min(120, max(64, rootHeight * 0.20))
    var firstHit: GTKCollapsedListContentHit?
    var bestHit: GTKCollapsedListContentHit?
    var bestScore = -Double.greatestFiniteMagnitude

    func frameContainsPoint(_ frame: (x: Double, y: Double, width: Double, height: Double)) -> Bool {
        x >= frame.x
            && x < frame.x + frame.width
            && y >= frame.y
            && y < frame.y + frame.height
    }

    func contentScore(_ frame: (x: Double, y: Double, width: Double, height: Double)) -> Double {
        var score = 0.0
        let contentSized = frame.width >= minimumContentWidth && frame.height >= minimumContentHeight
        if contentSized {
            score += 100_000
        }

        let desktopChromeWidth = gtkCollapsedListDesktopChromeWidth(rootWidth: rootWidth)
        let isDesktopDetailClick = rootWidth >= 700 && x >= desktopChromeWidth
        if isDesktopDetailClick {
            let fullWindowLike = frame.x < 4 && frame.width >= rootWidth * 0.90
            if frame.x >= desktopChromeWidth - 16 {
                score += 20_000
            }
            if fullWindowLike {
                score -= 15_000
            }
            if frame.height >= rootHeight * 0.65 {
                score += 5_000
            }
            if frame.width < rootWidth * 0.90 {
                score += 2_000
            }
            score -= abs(frame.x - desktopChromeWidth) * 20
        } else if frame.height >= rootHeight * 0.55 {
            score += 1_000
        }

        let rootArea = max(1, rootWidth * rootHeight)
        let areaRatio = min(1, (frame.width * frame.height) / rootArea)
        score -= areaRatio * 500
        return score
    }

    func consider(
        widget: UnsafeMutablePointer<GtkWidget>,
        frame: (x: Double, y: Double, width: Double, height: Double)
    ) {
        guard widget != root,
              frame.width > 1,
              frame.height > 1,
              frameContainsPoint(frame) else { return }
        if firstHit == nil {
            firstHit = GTKCollapsedListContentHit(widget: widget, frame: frame)
        }
        guard frame.width >= minimumContentWidth,
              frame.height >= minimumContentHeight else { return }
        let score = contentScore(frame)
        if score > bestScore {
            bestScore = score
            bestHit = GTKCollapsedListContentHit(widget: widget, frame: frame)
        }
    }

    while let widget = current, depth < 96 {
        if let frame = gtkWidgetVisualFrameInRoot(widget, root: root) {
            consider(widget: widget, frame: frame)
        }
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }

    func searchTree(_ widget: UnsafeMutablePointer<GtkWidget>, depth: Int = 0) {
        guard depth < 160 else { return }
        guard gtk_widget_get_visible(widget) != 0,
              gtk_widget_get_mapped(widget) != 0 else { return }
        if let frame = gtkWidgetVisualFrameInRoot(widget, root: root) {
            consider(widget: widget, frame: frame)
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            searchTree(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }
    var child = gtk_widget_get_first_child(root)
    while let current = child {
        searchTree(current)
        child = gtk_widget_get_next_sibling(current)
    }

    return bestHit ?? firstHit
}

private func gtkCollapsedListRowActionDataAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> gpointer? {
    gtkCollapsedListRowHitAtRootPoint(root: root, x: x, y: y)?.hit.actionData
}

private func gtkCollapsedListRowHitCandidatesAtRootPoint(
    in widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    contentFrame: (x: Double, y: Double, width: Double, height: Double),
    depth: Int = 0,
    into hits: inout [GTKCollapsedListRowHit]
) {
    guard depth < 160 else { return }
    guard gtk_widget_get_visible(widget) != 0, gtk_widget_get_mapped(widget) != 0 else { return }

    if gtk_swift_widget_is_list_box(widget) != 0,
       let frame = gtkWidgetVisualFrameInRoot(widget, root: root) {
        let containsPoint = x >= frame.x
            && x < frame.x + frame.width
            && y >= frame.y
            && y < frame.y + frame.height
        let overlapsContent = frame.x < contentFrame.x + contentFrame.width
            && frame.x + frame.width > contentFrame.x
            && frame.y < contentFrame.y + contentFrame.height
            && frame.y + frame.height > contentFrame.y
        if containsPoint && overlapsContent {
            var listX = 0.0
            var listY = 0.0
            if gtk_swift_widget_compute_point(root, widget, x, y, &listX, &listY) != 0,
               let hit = gtkCollapsedListRowHit(inListBox: widget, localY: listY) {
                hits.append(hit)
            }
        }
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkCollapsedListRowHitCandidatesAtRootPoint(
            in: current,
            root: root,
            x: x,
            y: y,
            contentFrame: contentFrame,
            depth: depth + 1,
            into: &hits
        )
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkBestCollapsedListRowHit(_ hits: [GTKCollapsedListRowHit]) -> GTKCollapsedListRowHit? {
    guard !hits.isEmpty else { return nil }
    return hits.enumerated().max { lhs, rhs in
        func score(_ candidate: (offset: Int, element: GTKCollapsedListRowHit)) -> Int {
            var value = candidate.offset
            let namespace = candidate.element.namespace
            if !namespace.contains("::Tab[") {
                value += 10_000
            }
            if candidate.element.controls != nil {
                value += 1_000
            }
            if candidate.element.actionData != nil {
                value += 100
            }
            return value
        }
        return score(lhs) < score(rhs)
    }?.element
}

private func gtkCollapsedListDesktopChromeWidth(rootWidth: Double) -> Double {
    min(240, max(160, rootWidth * 0.25))
}

private func gtkCollapsedListContentStartX(
    contentFrame: (x: Double, y: Double, width: Double, height: Double),
    rootWidth: Double
) -> Double {
    guard rootWidth >= 700, contentFrame.x < 4 else {
        return contentFrame.x
    }
    return contentFrame.x + gtkCollapsedListDesktopChromeWidth(rootWidth: rootWidth)
}

private func gtkCollapsedListInlineControlsStartX(
    contentFrame: (x: Double, y: Double, width: Double, height: Double),
    rootWidth: Double
) -> Double {
    let contentStartX = gtkCollapsedListContentStartX(contentFrame: contentFrame, rootWidth: rootWidth)
    return contentStartX + (rootWidth >= 700 && contentFrame.x < 4 ? 56 : 16)
}

private func gtkCollapsedListRowHitAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> (hit: GTKCollapsedListRowHit, contentFrame: (x: Double, y: Double, width: Double, height: Double))? {
    guard let contentHit = gtkCollapsedListContentHitAtRootPoint(root: root, x: x, y: y) else {
        return nil
    }
    let contentFrame = contentHit.frame
    let rootWidth = max(Double(gtk_widget_get_width(root)), contentFrame.width)
    if rootWidth >= 700 {
        let minimumContentX = gtkCollapsedListContentStartX(contentFrame: contentFrame, rootWidth: rootWidth)
        guard x >= minimumContentX else {
            gtkDebugLog(
                "collapsed-list dispatch skipped leading chrome root@\(Int(x)),\(Int(y)) "
                + "minX=\(Int(minimumContentX))"
            )
            return nil
        }
    }
    let localY = y - contentFrame.y
    guard localY >= 0, localY < contentFrame.height else { return nil }
    gtkDebugLog(
        "collapsed-list candidate root@\(Int(x)),\(Int(y)) "
        + "content=\(Int(contentFrame.x)),\(Int(contentFrame.y)) "
        + "\(Int(contentFrame.width))x\(Int(contentFrame.height)) "
        + "localY=\(Int(localY))"
    )
    var candidates: [GTKCollapsedListRowHit] = []
    gtkCollapsedListRowHitCandidatesAtRootPoint(
        in: root,
        root: root,
        x: x,
        y: y,
        contentFrame: contentFrame,
        into: &candidates
    )
    if let bestHit = gtkBestCollapsedListRowHit(candidates) {
        gtkDebugLog(
            "collapsed-list best row root@\(Int(x)),\(Int(y)) "
            + "candidates=\(candidates.count) namespace=\(bestHit.namespace)"
        )
        return (bestHit, contentFrame)
    }
    if let pickedHit = gtkPickedCollapsedListRowHitAtRootPoint(root: root, x: x, y: y) {
        gtkDebugLog("collapsed-list picked row root@\(Int(x)),\(Int(y))")
        return (pickedHit, contentFrame)
    }
    if let contentScopedHit = gtkFirstCollapsedListRowHit(in: contentHit.widget, localY: localY) {
        if contentScopedHit.controls == nil {
            if let controlsHit = gtkFirstCollapsedListRowHitWithControls(in: contentHit.widget, localY: localY) {
                gtkDebugLog("collapsed-list content controls row root@\(Int(x)),\(Int(y))")
                return (controlsHit, contentFrame)
            }
            if let controlsHit = gtkFirstCollapsedListRowHitWithControls(in: root, localY: localY) {
                gtkDebugLog("collapsed-list root controls row root@\(Int(x)),\(Int(y))")
                return (controlsHit, contentFrame)
            }
        }
        gtkDebugLog("collapsed-list content row root@\(Int(x)),\(Int(y))")
        return (contentScopedHit, contentFrame)
    }
    guard let hit = gtkVisualCollapsedListRowHitAtRootPoint(
        in: root,
        root: root,
        x: x,
        y: y,
        contentFrame: contentFrame
    ) else {
        return nil
    }
    return (hit, contentFrame)
}

private func gtkCollapsedListRowControlAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> GTKCollapsedRowControl? {
    guard let result = gtkCollapsedListRowHitAtRootPoint(root: root, x: x, y: y),
          let controls = result.hit.controls?.controls,
          !controls.isEmpty
    else {
        return nil
    }

    let rowHeight = max(1, result.hit.estimatedHeight)
    let actionBandStart = max(36, rowHeight - 64)
    let usesWideInlineControls = controls.contains { $0.naturalWidth > 96 }
    guard usesWideInlineControls || result.hit.rowLocalY >= actionBandStart else {
        gtkDebugLog(
            "collapsed-list controls skipped row y=\(Int(result.hit.rowLocalY)) "
            + "band=\(Int(actionBandStart)) root@\(Int(x)),\(Int(y))"
        )
        return nil
    }

    let rootWidth = max(Double(gtk_widget_get_width(root)), result.contentFrame.width)
    if rootWidth >= 700,
       x >= result.contentFrame.x + rootWidth - 96,
       let trailingControl = controls.last {
        gtkDebugLog("collapsed-list controls trailing hit root@\(Int(x)),\(Int(y))")
        return trailingControl
    }

    var cursor = gtkCollapsedListInlineControlsStartX(
        contentFrame: result.contentFrame,
        rootWidth: rootWidth
    )
    let inlineLimit = min(4, controls.count)
    for index in 0..<inlineLimit {
        let control = controls[index]
        let width = max(44, control.naturalWidth)
        if x >= cursor && x <= cursor + width {
            gtkDebugLog(
                "collapsed-list controls hit index=\(index) "
                + "frame=\(Int(cursor)),\(Int(result.contentFrame.y + result.hit.rowLocalY)) "
                + "\(Int(width))w root@\(Int(x)),\(Int(y))"
            )
            return control
        }
        cursor += width + 8
    }

    gtkDebugLog("collapsed-list controls miss root@\(Int(x)),\(Int(y)) count=\(controls.count)")
    return nil
}

private func gtkActivateCollapsedListRowControlAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) -> Bool {
    guard let control = gtkCollapsedListRowControlAtRootPoint(root: root, x: x, y: y) else {
        return false
    }
    switch control {
    case .button(let box, _):
        gtkScheduleButtonAction(box, source: source)
        return true
    case .menu(let button, _):
        return gtkOpenMenuButton(button, root: root, anchorX: x, anchorY: y, source: source)
    }
}

private func gtkDebugListRowActionCandidates(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    var total = 0
    var hits = 0
    var logged = 0

    func walk(_ widget: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard depth < 160 else { return }
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(object, gtkListRowTapActionDataKey) != nil {
            let contains = gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y)
            total += 1
            if contains { hits += 1 }
            if contains || logged < 40 {
                let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
                gtkDebugLog(
                    "\(source) row-action-candidate[\(total - 1)] hit=\(contains ? 1 : 0) "
                    + "type=\(typeName) isRow=\(gtk_swift_widget_is_list_box_row(widget)) "
                    + gtkDebugVisualFrameDescription(widget, root: root)
                )
                logged += 1
            }
        }

        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(root, depth: 0)
    gtkDebugLog("\(source) row-action-candidates total=\(total) hits=\(hits) root@\(Int(x)),\(Int(y))")
}

private func gtkDebugNonzeroWidgetsAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    var total = 0
    var hits = 0
    var logged = 0

    func walk(_ widget: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard depth < 160 else { return }
        let width = gtk_widget_get_width(widget)
        let height = gtk_widget_get_height(widget)
        if width > 0 && height > 0 {
            total += 1
            let contains = gtkWidgetVisuallyContainsRootPoint(widget, root: root, x: x, y: y)
            if contains { hits += 1 }
            if contains || logged < 80 {
                let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
                let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
                let hasTap = g_object_get_data(object, gtkTapGestureActionDataKey) != nil
                let hasRow = g_object_get_data(object, gtkListRowTapActionDataKey) != nil
                gtkDebugLog(
                    "\(source) nonzero-widget[\(total - 1)] hit=\(contains ? 1 : 0) "
                    + "type=\(typeName) tap=\(hasTap ? 1 : 0) row=\(hasRow ? 1 : 0) "
                    + gtkDebugVisualFrameDescription(widget, root: root)
                )
                logged += 1
            }
        }

        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(root, depth: 0)
    gtkDebugLog("\(source) nonzero-widgets total=\(total) hits=\(hits) root@\(Int(x)),\(Int(y))")
}

private func gtkInstallGlobalListRowRootDispatcher(for widget: UnsafeMutablePointer<GtkWidget>) {
    guard let root = gtk_swift_widget_root_widget(widget) else { return }
    let rootObject = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GObject.self)
    guard g_object_get_data(rootObject, gtkListRowGlobalDispatcherDataKey) == nil else { return }

    let dispatcher = GTKListRowGlobalRootDispatcher(root: root)
    let controller = gtk_swift_legacy_capture_controller()!
    dispatcher.controller = controller

    let dispatcherPointer = Unmanaged.passRetained(dispatcher).toOpaque()
    g_object_set_data_full(
        rootObject,
        gtkListRowGlobalDispatcherDataKey,
        dispatcherPointer,
        { userData in
            guard let userData else { return }
            Unmanaged<GTKListRowGlobalRootDispatcher>.fromOpaque(userData).release()
        }
    )

    gtkDebugLog("list row global root dispatcher installed")
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let dispatcher = Unmanaged<GTKListRowGlobalRootDispatcher>.fromOpaque(userData).takeUnretainedValue()
            let root = dispatcher.root
            var rootX: Double = 0
            var rootY: Double = 0
            guard gtk_swift_event_get_position(event, &rootX, &rootY) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }
            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "list-row-root-dispatch@\(Int(rootX)),\(Int(rootY))"
            ) {
                return 1
            }

            if gtkOpenVisualMenuButtonAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "list-row-root-dispatch@\(Int(rootX)),\(Int(rootY))"
            ) {
                return 1
            }
            guard gtk_swift_root_point_picks_button(root, rootX, rootY) == 0 else {
                gtkDebugLog("list row global dispatch skipped button root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: rootX, y: rootY) else {
                gtkDebugLog("list row global dispatch skipped visual button root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            guard !gtkWidgetTreeContainsVisualTapActionAtRootPoint(root, root: root, x: rootX, y: rootY) else {
                gtkDebugLog("list row global dispatch skipped visual tap root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }

            let pickedGTKRow = gtk_swift_root_point_pick_list_box_row(root, rootX, rootY)
            var actionData = gtkListRowTapActionData(from: pickedGTKRow)
            var deferRowAction = true
            if actionData == nil,
               let pickedRow = gtkPickedListBoxActionRowAtRootPoint(root: root, x: rootX, y: rootY) {
                actionData = gtkListRowTapActionData(from: pickedRow)
                gtkDebugLog("list row global dispatch picked fallback root@\(Int(rootX)),\(Int(rootY))")
            }
            if actionData == nil,
               let pickedActionWidget = gtkPickedListRowActionWidgetAtRootPoint(root: root, x: rootX, y: rootY) {
                actionData = gtkListRowTapActionData(from: pickedActionWidget)
                gtkDebugLog("list row global dispatch picked action fallback root@\(Int(rootX)),\(Int(rootY))")
            }
            if actionData == nil,
               let visualRow = gtkVisualListBoxActionRowAtRootPoint(root, root: root, x: rootX, y: rootY) {
                actionData = gtkListRowTapActionData(from: visualRow)
                gtkDebugLog("list row global dispatch visual fallback root@\(Int(rootX)),\(Int(rootY))")
            }
            if actionData == nil,
               let visualActionWidget = gtkVisualListRowActionWidgetAtRootPoint(root, root: root, x: rootX, y: rootY) {
                actionData = gtkListRowTapActionData(from: visualActionWidget)
                gtkDebugLog("list row global dispatch visual action fallback root@\(Int(rootX)),\(Int(rootY))")
            }
            if actionData == nil,
               gtkActivateCollapsedListRowControlAtRootPoint(
                   root: root,
                   x: rootX,
                   y: rootY,
                   source: "collapsed-list-control@\(Int(rootX)),\(Int(rootY))"
               ) {
                return 1
            }
            if actionData == nil,
               let collapsedActionData = gtkCollapsedListRowActionDataAtRootPoint(root: root, x: rootX, y: rootY) {
                actionData = collapsedActionData
                deferRowAction = false
                gtkDebugLog("list row global dispatch collapsed-list fallback root@\(Int(rootX)),\(Int(rootY))")
            }
            guard let actionData else {
                gtkDebugListRowActionCandidates(
                    root: root,
                    x: rootX,
                    y: rootY,
                    source: "list row global dispatch"
                )
                gtkDebugNonzeroWidgetsAtRootPoint(
                    root: root,
                    x: rootX,
                    y: rootY,
                    source: "list row global dispatch"
                )
                gtkDebugPickedWidgetChain(
                    root: root,
                    x: rootX,
                    y: rootY,
                    source: "list row global dispatch"
                )
                gtkDebugLog("list row global dispatch miss root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(actionData).takeUnretainedValue()
            gtkScheduleListRowTapAction(
                box,
                source: "root-dispatch@\(Int(rootX)),\(Int(rootY))",
                deferAction: deferRowAction
            )
            return 1
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        dispatcherPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

private func gtkInstallListBoxRootEventFallback(_ context: GTKListBoxRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.listBox) else {
        if !context.loggedRootUnavailable {
            context.loggedRootUnavailable = true
            gtkDebugLog("list box root fallback root unavailable")
        }
        return
    }

    let controller = gtk_swift_legacy_capture_controller()!
    context.root = root
    context.controller = controller
    gtkDebugLog("list box root fallback installed")
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKListBoxRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return 0 }
            var rootX: Double = 0
            var rootY: Double = 0
            guard gtk_swift_event_get_position(event, &rootX, &rootY) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }

            let visibleContainer = gtk_widget_get_parent(context.listBox) ?? context.listBox
            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.listBox, rootX, rootY) != 0
            let isVisualHit = gtkWidgetOrDescendantVisuallyContainsRootPoint(visibleContainer, root: root, x: rootX, y: rootY)
                || gtkWidgetOrDescendantVisuallyContainsRootPoint(context.listBox, root: root, x: rootX, y: rootY)
            guard isTopmost || isVisualHit else {
                gtkDebugLog(
                    "listbox-root missed root@\(Int(rootX)),\(Int(rootY)) list="
                    + gtkDebugVisualFrameDescription(context.listBox, root: root)
                    + " container="
                    + gtkDebugVisualFrameDescription(visibleContainer, root: root)
                )
                return 0
            }
            gtkDebugPickedWidgetChain(
                root: root,
                x: rootX,
                y: rootY,
                source: "listbox-root candidate"
            )
            gtkDebugLog(
                "listbox-root candidate root@\(Int(rootX)),\(Int(rootY)) "
                + "topmost=\(isTopmost ? 1 : 0) visual=\(isVisualHit ? 1 : 0) list="
                + gtkDebugVisualFrameDescription(context.listBox, root: root)
                + " container="
                + gtkDebugVisualFrameDescription(visibleContainer, root: root)
            )

            if gtkOpenVisualMenuButtonAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "listbox-root@\(Int(rootX)),\(Int(rootY))"
            ) {
                return 1
            }
            guard gtk_swift_root_point_picks_button(root, rootX, rootY) == 0 else {
                gtkDebugLog("list row tap skipped button listbox-root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: rootX, y: rootY) else {
                gtkDebugLog("list row tap skipped visual button listbox-root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            guard !gtkWidgetTreeContainsVisualTapActionAtRootPoint(root, root: root, x: rootX, y: rootY) else {
                gtkDebugLog("list row tap skipped visual tap listbox-root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }

            var listX: Double = 0
            var listY: Double = 0
            guard gtk_swift_widget_compute_point(root, context.listBox, rootX, rootY, &listX, &listY) != 0 else {
                return 0
            }
            guard let row = gtk_swift_list_box_row_at_point(context.listBox, listX, listY) else {
                gtkDebugLog("list row tap miss listbox-root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            guard let actionData = g_object_get_data(
                UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
                gtkListRowTapActionDataKey
            ) else {
                gtkDebugLog("list row tap no action listbox-root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(actionData).takeUnretainedValue()
            gtkDebugLog(
                "listbox-root row root@\(Int(rootX)),\(Int(rootY)) list@\(Int(listX)),\(Int(listY)) "
                + gtkDebugVisualFrameDescription(row, root: root)
                + " source=\(box.source)"
            )
            gtkScheduleListRowTapAction(box, source: "listbox-root@\(Int(rootX)),\(Int(rootY))")
            return 1
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

private func gtkListBoxRootInstallTickCallback(
    _ widget: UnsafeMutablePointer<GtkWidget>?,
    _ frameClock: OpaquePointer?,
    _ userData: gpointer?
) -> gboolean {
    guard let userData else { return 0 }
    let context = Unmanaged<GTKListBoxRootEventContext>.fromOpaque(userData).takeUnretainedValue()
    gtkInstallListBoxRootEventFallback(context)
    gtkInstallGlobalListRowRootDispatcher(for: context.listBox)
    return context.controller == nil ? 1 : 0
}

private func gtkInstallListRowRootEventFallback(_ context: GTKListRowRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.row) else {
        if !context.loggedRootUnavailable {
            context.loggedRootUnavailable = true
            gtkDebugLog("list row root fallback root unavailable \(context.box.source)")
        }
        return
    }

    let controller = gtk_swift_legacy_capture_controller()!
    context.root = root
    context.controller = controller
    gtkDebugLog("list row root fallback installed \(context.box.source)")
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKListRowRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return 0 }
            var x: Double = 0
            var y: Double = 0
            guard gtk_swift_event_get_position(event, &x, &y) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: x, y: y)
            }
            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.row, x, y) != 0
            let isVisualHit = gtkWidgetOrDescendantVisuallyContainsRootPoint(context.row, root: root, x: x, y: y)
            guard isTopmost || isVisualHit else {
                gtkDebugLog(
                    "list row tap missed root@\(Int(x)),\(Int(y)) \(context.box.source) "
                    + gtkDebugVisualFrameDescription(context.row, root: root)
                )
                return 0
            }
            let source = isTopmost ? "root" : "root-visual"
            if gtkOpenVisualMenuButtonAtRootPoint(
                root: root,
                x: x,
                y: y,
                source: "\(source)@\(Int(x)),\(Int(y)) \(context.box.source)"
            ) {
                return 1
            }
            if !context.box.allowButtonTarget {
                guard gtk_swift_root_point_picks_button(root, x, y) == 0 else {
                    gtkDebugLog("list row tap skipped button \(source)@\(Int(x)),\(Int(y)) \(context.box.source)")
                    return 0
                }
                guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: x, y: y) else {
                    gtkDebugLog("list row tap skipped visual button \(source)@\(Int(x)),\(Int(y)) \(context.box.source)")
                    return 0
                }
                guard !gtkWidgetTreeContainsVisualTapActionAtRootPoint(root, root: root, x: x, y: y) else {
                    gtkDebugLog("list row tap skipped visual tap \(source)@\(Int(x)),\(Int(y)) \(context.box.source)")
                    return 0
                }
            }
            gtkScheduleListRowTapAction(context.box, source: "\(source)@\(Int(x)),\(Int(y))")
            return 1
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

private func gtkListRowRootInstallTickCallback(
    _ widget: UnsafeMutablePointer<GtkWidget>?,
    _ frameClock: OpaquePointer?,
    _ userData: gpointer?
) -> gboolean {
    guard let userData else { return 0 }
    let context = Unmanaged<GTKListRowRootEventContext>.fromOpaque(userData).takeUnretainedValue()
    gtkInstallListRowRootEventFallback(context)
    return context.controller == nil ? 1 : 0
}

private func gtkAttachListRowTapActionData(
    to widget: UnsafeMutablePointer<GtkWidget>,
    box: GTKListRowTapActionBox,
    depth: Int = 0
) {
    guard depth < 160 else { return }
    guard gtk_swift_widget_is_button(widget) == 0,
          gtk_swift_widget_is_menu_button(widget) == 0
    else {
        return
    }

    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    if g_object_get_data(object, gtkListRowTapActionDataKey) == nil {
        g_object_set_data_full(
            object,
            gtkListRowTapActionDataKey,
            Unmanaged.passRetained(box).toOpaque(),
            { userData in
                guard let userData else { return }
                Unmanaged<GTKListRowTapActionBox>.fromOpaque(userData).release()
            }
        )
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        gtkAttachListRowTapActionData(to: current, box: box, depth: depth + 1)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func gtkInstallListRowTapFallback(
    on row: UnsafeMutablePointer<GtkWidget>,
    source: String,
    action: @escaping () -> Void,
    allowButtonTarget: Bool = false
) -> GTKListRowTapActionBox {
    let gesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(gesture, 1)

    gtkDebugLog("list row tap fallback installed \(source)")
    let actionBox = GTKListRowTapActionBox(
        action: action,
        source: source,
        allowButtonTarget: allowButtonTarget
    )
    let box = Unmanaged.passRetained(actionBox).toOpaque()
    gtkAttachListRowTapActionData(to: row, box: actionBox)
    let rootContextObject = GTKListRowRootEventContext(row: row, box: actionBox)
    let rootEventContext = Unmanaged.passRetained(
        rootContextObject
    ).toOpaque()
    g_signal_connect_data(
        gpointer(row),
        "map",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKListRowRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            gtkInstallListRowRootEventFallback(context)
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        rootEventContext,
        nil,
        GConnectFlags(rawValue: 0)
    )
    g_signal_connect_data(
        gpointer(row),
        "unmap",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKListRowRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            context.removeController()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        rootEventContext,
        nil,
        GConnectFlags(rawValue: 0)
    )
    let tickRootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
    _ = gtk_widget_add_tick_callback(
        row,
        gtkListRowRootInstallTickCallback,
        tickRootEventContext,
        { userData in
            guard let userData else { return }
            Unmanaged<GTKListRowRootEventContext>.fromOpaque(userData).release()
        }
    )
    g_signal_connect_data(
        gpointer(row),
        "destroy",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKListRowRootEventContext>.fromOpaque(userData).takeRetainedValue()
            context.removeController()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        rootEventContext,
        nil,
        GConnectFlags(rawValue: 0)
    )
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (gesture: gpointer?, nPress: gint, x: gdouble, y: gdouble, userData: gpointer?) in
            guard Int(nPress) == 1, let userData else { return }
            let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(userData).takeUnretainedValue()
            guard let row = gtk_swift_event_controller_widget(gesture) else {
                gtkScheduleListRowTapAction(box, source: "gesture")
                return
            }
            if gtkHandleActiveMenuOverlayClick(from: row, x: x, y: y) != 0 {
                gtk_swift_gesture_claim(gesture)
                return
            }
            if gtkOpenVisualMenuButtonAtWidgetPoint(row, x: x, y: y, source: "gesture@\(Int(x)),\(Int(y)) \(box.source)") {
                gtk_swift_gesture_claim(gesture)
                return
            }
            if !box.allowButtonTarget {
                guard gtk_swift_root_point_picks_button(row, x, y) == 0 else {
                    gtkDebugLog("list row tap skipped button gesture@\(Int(x)),\(Int(y)) \(box.source)")
                    return
                }
                guard !gtkRootTreeContainsVisualButtonAtWidgetPoint(row, x: x, y: y) else {
                    gtkDebugLog("list row tap skipped visual button gesture@\(Int(x)),\(Int(y)) \(box.source)")
                    return
                }
                guard !gtkRootTreeContainsVisualTapActionAtWidgetPoint(row, x: x, y: y) else {
                    gtkDebugLog("list row tap skipped visual tap gesture@\(Int(x)),\(Int(y)) \(box.source)")
                    return
                }
            }
            gtkScheduleListRowTapAction(box, source: "gesture")
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        box,
        { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
            Unmanaged<GTKListRowTapActionBox>.fromOpaque(userData!).release()
        },
        GConnectFlags(rawValue: 0)
    )

    gtk_swift_add_gesture(row, gesture)
    return actionBox
}

private func gtkInstallListBoxTapFallback(on listBox: UnsafeMutablePointer<GtkWidget>) {
    let gesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(gesture, 1)

    let rootContextObject = GTKListBoxRootEventContext(listBox: listBox)
    let rootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
    g_signal_connect_data(
        gpointer(listBox),
        "map",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKListBoxRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            gtkInstallListBoxRootEventFallback(context)
            gtkInstallGlobalListRowRootDispatcher(for: context.listBox)
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        rootEventContext,
        nil,
        GConnectFlags(rawValue: 0)
    )
    g_signal_connect_data(
        gpointer(listBox),
        "unmap",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKListBoxRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            context.removeController()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        rootEventContext,
        nil,
        GConnectFlags(rawValue: 0)
    )
    let tickRootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
    _ = gtk_widget_add_tick_callback(
        listBox,
        gtkListBoxRootInstallTickCallback,
        tickRootEventContext,
        { userData in
            guard let userData else { return }
            Unmanaged<GTKListBoxRootEventContext>.fromOpaque(userData).release()
        }
    )
    g_signal_connect_data(
        gpointer(listBox),
        "destroy",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKListBoxRootEventContext>.fromOpaque(userData).takeRetainedValue()
            context.removeController()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        rootEventContext,
        nil,
        GConnectFlags(rawValue: 0)
    )

    gtkDebugLog("list box tap fallback installed")
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (gesture: gpointer?, nPress: gint, x: gdouble, y: gdouble, userData: gpointer?) in
            guard Int(nPress) == 1, let userData else { return }
            let listBox = userData.assumingMemoryBound(to: GtkWidget.self)
            if gtkHandleActiveMenuOverlayClick(from: listBox, x: x, y: y) != 0 {
                gtk_swift_gesture_claim(gesture)
                return
            }
            if gtkOpenVisualMenuButtonAtWidgetPoint(listBox, x: x, y: y, source: "listbox@\(Int(x)),\(Int(y))") {
                gtk_swift_gesture_claim(gesture)
                return
            }
            guard gtk_swift_root_point_picks_button(listBox, x, y) == 0 else {
                gtkDebugLog("list row tap skipped button listbox@\(Int(x)),\(Int(y))")
                return
            }
            guard !gtkRootTreeContainsVisualButtonAtWidgetPoint(listBox, x: x, y: y) else {
                gtkDebugLog("list row tap skipped visual button listbox@\(Int(x)),\(Int(y))")
                return
            }
            guard !gtkRootTreeContainsVisualTapActionAtWidgetPoint(listBox, x: x, y: y) else {
                gtkDebugLog("list row tap skipped visual tap listbox@\(Int(x)),\(Int(y))")
                return
            }
            guard let row = gtk_swift_list_box_row_at_point(listBox, x, y) else {
                gtkDebugLog("list row tap miss listbox@\(Int(x)),\(Int(y))")
                return
            }
            guard let actionData = g_object_get_data(
                UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
                gtkListRowTapActionDataKey
            ) else {
                gtkDebugLog("list row tap no action listbox@\(Int(x)),\(Int(y))")
                return
            }
            let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(actionData).takeUnretainedValue()
            gtkScheduleListRowTapAction(box, source: "listbox@\(Int(x)),\(Int(y))")
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        gpointer(listBox),
        nil,
        GConnectFlags(rawValue: 0)
    )

    gtk_swift_add_gesture(listBox, gesture)
}

private func gtkInstallListBoxRowActivationFallback(on listBox: UnsafeMutablePointer<GtkWidget>) {
    gtk_swift_list_box_set_activate_on_single_click(listBox, 1)
    g_signal_connect_data(
        gpointer(listBox),
        "row-activated",
        unsafeBitCast({ (_: gpointer?, row: gpointer?, _: gpointer?) in
            guard let row else { return }
            guard let actionData = g_object_get_data(
                UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
                gtkListRowTapActionDataKey
            ) else {
                return
            }
            let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(actionData).takeUnretainedValue()
            gtkScheduleListRowTapAction(box, source: "row-activated")
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        nil,
        nil,
        GConnectFlags(rawValue: 0)
    )
}

/// Track which GdkDisplays have had list CSS installed.
private var listCSSDisplays: Set<ObjectIdentifier> = []

private func ensureListCSS(_ widget: UnsafeMutablePointer<GtkWidget>) {
    let display = gtk_widget_get_display(widget)!
    let displayId = ObjectIdentifier(display as AnyObject)
    guard !listCSSDisplays.contains(displayId) else { return }
    listCSSDisplays.insert(displayId)

    let provider = gtk_css_provider_new()!
    let css = """
        .swiftopenui-list { background: @view_bg_color; border-radius: 10px; padding: 0; }
        .swiftopenui-list row { border-bottom: 1px solid alpha(currentColor, 0.18); min-height: 56px; padding: 0; }
        .swiftopenui-list row.separator-hidden { border-bottom: none; }
        .swiftopenui-list row:last-child { border-bottom: none; }
        """
    gtk_css_provider_load_from_string(provider, css)
    gtk_swift_add_css_provider_to_display(
        display,
        provider,
        UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
    )
    g_object_unref(gpointer(provider))
}

extension List: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let rowDescriptors = gtkDirectChildViews(of: content).enumerated().map { index, child in
            gtkDescribeListRowLifecycleScope(child, index: index)
        }
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "List",
            children: rowDescriptors
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let listBox = gtk_list_box_new()!
        let listBoxOp = OpaquePointer(listBox)
        gtk_widget_set_hexpand(listBox, 1)
        gtk_widget_set_halign(listBox, GTK_ALIGN_FILL)
        gtk_list_box_set_selection_mode(listBoxOp, GTK_SELECTION_NONE)

        ensureListCSS(listBox)
        gtk_widget_add_css_class(listBox, "swiftopenui-list")
        gtkInstallListBoxRowActivationFallback(on: listBox)
        gtkInstallListBoxTapFallback(on: listBox)

        for child in gtkDirectChildViews(of: content) {
            let metadata = gtkRowMetadata(from: child)
            let minimumHeight = gtkListRowMinimumHeight(for: child)
            let rowSource = String(reflecting: Swift.type(of: child))
            let widget = gtkRenderRowContent(
                child,
                metadata: metadata,
                minimumHeight: minimumHeight
            )
            if gtkIsEmptyViewWidget(widget) {
                continue
            }
            let row = gtk_list_box_row_new()!
            gtk_swift_list_box_row_set_activatable(row, 1)
            if gtkSeparatorIsHidden(metadata) {
                gtk_widget_add_css_class(row, "separator-hidden")
            }
            gtk_widget_set_hexpand(row, 1)
            gtk_widget_set_halign(row, GTK_ALIGN_FILL)
            gtkAttachListRowLifecycleData(to: row, view: child, source: rowSource)
            gtkAttachListRowGeometryData(
                to: row,
                estimatedHeight: Double(minimumHeight),
                source: rowSource,
                namespace: gtkStateIdentityNamespace()
            )
            var rowTapActionBox: GTKListRowTapActionBox?
            if let tapAction = gtkPrimaryTapAction(inAny: child) {
                rowTapActionBox = gtkInstallListRowTapFallback(
                    on: row,
                    source: rowSource,
                    action: tapAction
                )
            }
            gtk_list_box_row_set_child(
                UnsafeMutableRawPointer(row).assumingMemoryBound(to: GtkListBoxRow.self),
                widget
            )
            if let rowTapActionBox {
                gtkAttachListRowTapActionData(to: widget, box: rowTapActionBox)
            }
            gtkAttachCollapsedListRowControlsData(to: row, content: widget)
            gtkInstallRowWidthFill(on: row, child: widget)
            gtk_list_box_append(listBoxOp, row)
        }

        // Wrap in scrolled window
        let scrolled = gtk_scrolled_window_new()!
        let scrolledOp = OpaquePointer(scrolled)
        gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
        // A vertical SwiftUI List lays rows out in the viewport width.
        // Propagating natural width lets fixed-width row content push
        // trailing controls outside the visible sheet.
        gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
        // Mirror ScrollView: don't let the child listbox's full natural
        // height dictate the scroll's natural size. Otherwise a List
        // inside a VStack reports "I need N×row-height" as natural, and
        // the VStack's allocation pass leaves too little slack — trailing
        // siblings (status bars, footers) swallow the remainder.
        gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)
        gtk_scrolled_window_set_child(scrolledOp, listBox)
        gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox, fillWidth: true, fillHeight: false)
        gtkInstallListViewportLifecycleController(on: scrolled, listBox: listBox)
        gtk_widget_set_vexpand(scrolled, 1)
        gtk_widget_set_hexpand(scrolled, 1)

        return opaqueFromWidget(scrolled)
    }
}

extension EnvironmentObjectModifierView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        var env = getCurrentEnvironment()
        env.setObject(object)
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(prev) }
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "EnvironmentObjectModifierView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.setObject(object)
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension EnvironmentObservableModifierView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        var env = getCurrentEnvironment()
        env.setObject(object)
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(prev) }
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "EnvironmentObservableModifierView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env.setObject(object)
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension EnvironmentModifierView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        var env = getCurrentEnvironment()
        env[keyPath: keyPath] = value
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(prev) }
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "EnvironmentModifierView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        env[keyPath: keyPath] = value
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension TransformEnvironmentModifierView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        transform(&env[keyPath: keyPath])
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension DisabledView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .disabled, typeName: "DisabledView",
            props: .disabled(GTK4DisabledDescriptor(isDisabled: isDisabled)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        var env = getCurrentEnvironment()
        // Ancestor composition: parent disabled(true) cannot be undone by child disabled(false)
        let effectiveIsEnabled = env.isEnabled && !isDisabled
        env.isEnabled = effectiveIsEnabled
        let prev = getCurrentEnvironment()
        setCurrentEnvironment(env)
        let widget = gtkRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

/// Apply GTK sensitivity from the current environment's isEnabled state.
private func gtkApplyEnabledState(to widget: UnsafeMutablePointer<GtkWidget>) {
    let env = getCurrentEnvironment()
    if !env.isEnabled {
        gtk_widget_set_sensitive(widget, 0)
    }
}

extension _ViewModifierContent: GTKRenderable, GTKDescribable {
    /// Describe through to the wrapped view (this placeholder's widget IS the
    /// wrapped view's widget). Without this, every custom ViewModifier in a
    /// host's subtree terminates the describe pass as a childless composite
    /// and knocks the host off the narrow mutation path.
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "_ViewModifierContent",
            children: [gtkDescribeAnyView(wrapped.wrapped)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        gtkRenderAnyView(wrapped.wrapped)
    }
}

// MARK: - TupleView GTK extensions

extension TupleView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        for child in children {
            let widget = gtkRenderAnyView(child)
            gtk_box_append(boxPointer(box), widgetFromOpaque(widget))
        }
        return opaqueFromWidget(box)
    }
}

// MARK: - TabView GTK extension

// Note: `Tab<Content>` intentionally has no `GTKRenderable` conformance.
// `TabBuilder` wraps every `Tab` into `AnyTab` at construction time, so
// `TabView` iterates `[AnyTab]` and renders each `tab.wrapped` directly.
// This matches the Win32 backend, which also does not render bare `Tab`.

private func gtkTabViewShouldShowSwitcher(_ tabs: [AnyTab]) -> Bool {
    tabs.count > 1 && tabs.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

private func gtkTabViewShouldShowSidebar(_ tabs: [AnyTab]) -> Bool {
    tabs.count > 1 && tabs.contains { tab in
        tab.label != nil || tab.placement == "pinned" || tab.placement == "sidebarOnly"
    }
}

private func gtkTabDebugLog(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_TABS"] == "1" else {
        return
    }
    let line = "[SwiftOpenUI][TabView] \(message())\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private final class GTKTabActivationBox {
    let button: UnsafeMutablePointer<GtkWidget>
    let stack: UnsafeMutablePointer<GtkWidget>
    let id: String
    let selectionHandler: ((String) -> Void)?
    private var lastActivationTime: TimeInterval = 0

    init(
        button: UnsafeMutablePointer<GtkWidget>,
        stack: UnsafeMutablePointer<GtkWidget>,
        id: String,
        selectionHandler: ((String) -> Void)?
    ) {
        self.button = button
        self.stack = stack
        self.id = id
        self.selectionHandler = selectionHandler
    }

    func activate(button: UnsafeMutablePointer<GtkWidget>?) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastActivationTime > 0.05 else {
            return
        }
        lastActivationTime = now

        gtkTabDebugLog("clicked requested=\(id)")
        selectionHandler?(id)
        gtk_swift_stack_set_visible_child_name(stack, id)
        gtkSelectSidebarTabButton(button ?? self.button)
        let visibleName = gtk_swift_stack_get_visible_child_name(stack)
            .map { String(cString: $0) } ?? "<nil>"
        gtkTabDebugLog("clicked visible=\(visibleName)")
    }
}

private final class GTKSidebarTabFallbackContext {
    let sidebar: UnsafeMutablePointer<GtkWidget>
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?

    init(sidebar: UnsafeMutablePointer<GtkWidget>) {
        self.sidebar = sidebar
    }

    func removeController() {
        if let root, let controller {
            gtk_swift_remove_event_controller(root, controller)
        }
        root = nil
        controller = nil
    }

    deinit {
        removeController()
    }
}

private let gtkSidebarTabClass = "swiftopenui-tab-sidebar"
private let gtkSidebarTabButtonClass = "swiftopenui-tab-sidebar-button"
private let gtkSidebarTabSelectedClass = "swiftopenui-tab-selected"
private let gtkSidebarTabActivationBoxDataKey = "gtk-swift-sidebar-tab-activation-box"
private var gtkSidebarTabCSSDisplays: Set<ObjectIdentifier> = []

private func ensureSidebarTabCSS(_ widget: UnsafeMutablePointer<GtkWidget>) {
    let display = gtk_widget_get_display(widget)!
    let displayId = ObjectIdentifier(display as AnyObject)
    guard !gtkSidebarTabCSSDisplays.contains(displayId) else { return }
    gtkSidebarTabCSSDisplays.insert(displayId)

    let provider = gtk_css_provider_new()!
    let css = """
        .\(gtkSidebarTabClass) {
            background: alpha(currentColor, 0.03);
            padding: 8px;
        }
        .\(gtkSidebarTabClass) button.\(gtkSidebarTabButtonClass) {
            border-radius: 8px;
            padding: 0;
            margin: 0;
            background: transparent;
        }
        .\(gtkSidebarTabClass) button.\(gtkSidebarTabButtonClass):hover {
            background: alpha(currentColor, 0.08);
        }
        .\(gtkSidebarTabClass) button.\(gtkSidebarTabButtonClass).\(gtkSidebarTabSelectedClass) {
            background: rgb(225, 237, 250);
            color: rgb(26, 95, 180);
        }
        .\(gtkSidebarTabClass) button.\(gtkSidebarTabButtonClass).\(gtkSidebarTabSelectedClass) label {
            font-weight: 600;
        }
        """
    gtk_css_provider_load_from_string(provider, css)
    gtk_swift_add_css_provider_to_display(
        display,
        provider,
        UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
    )
    g_object_unref(gpointer(provider))
}

private func gtkSelectSidebarTabButton(_ button: UnsafeMutablePointer<GtkWidget>) {
    if let parent = gtk_widget_get_parent(button) {
        var child = gtk_widget_get_first_child(parent)
        while let current = child {
            gtk_widget_remove_css_class(current, gtkSidebarTabSelectedClass)
            child = gtk_widget_get_next_sibling(current)
        }
    }
    gtk_widget_add_css_class(button, gtkSidebarTabSelectedClass)
}

private func gtkActivateSidebarTab(buttonPtr: gpointer?, userData: gpointer?) {
    guard let userData else { return }
    let context = Unmanaged<GTKTabActivationBox>.fromOpaque(userData).takeUnretainedValue()
    let button = buttonPtr.map {
        UnsafeMutableRawPointer($0).assumingMemoryBound(to: GtkWidget.self)
    }
    context.activate(button: button)
}

private func gtkInstallSidebarTabActivationGesture(
    on widget: UnsafeMutablePointer<GtkWidget>,
    context: gpointer
) {
    let gesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(gesture, 1)
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, _: gdouble, _: gdouble, userData: gpointer?) in
            gtkActivateSidebarTab(buttonPtr: nil, userData: userData)
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        context,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(widget, gesture)
}

private func gtkAttachSidebarTabActivationContext(
    _ context: gpointer,
    to button: UnsafeMutablePointer<GtkWidget>
) {
    g_object_set_data(
        UnsafeMutableRawPointer(button).assumingMemoryBound(to: GObject.self),
        gtkSidebarTabActivationBoxDataKey,
        context
    )
}

private func gtkSidebarTabActivationContext(
    from button: UnsafeMutablePointer<GtkWidget>
) -> GTKTabActivationBox? {
    guard let pointer = g_object_get_data(
        UnsafeMutableRawPointer(button).assumingMemoryBound(to: GObject.self),
        gtkSidebarTabActivationBoxDataKey
    ) else {
        return nil
    }
    return Unmanaged<GTKTabActivationBox>.fromOpaque(pointer).takeUnretainedValue()
}

private func gtkActivateSidebarTabAt(
    sidebar: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) {
    var child = gtk_widget_get_first_child(sidebar)
    while let button = child {
        var buttonX = 0.0
        var buttonY = 0.0
        let hasCoordinates = gtk_widget_translate_coordinates(button, sidebar, 0, 0, &buttonX, &buttonY) != 0
        let width = Double(max(0, gtk_widget_get_width(button)))
        let height = Double(max(0, gtk_widget_get_height(button)))
        if hasCoordinates,
           x >= buttonX,
           x <= buttonX + width,
           y >= buttonY,
           y <= buttonY + height,
           let context = gtkSidebarTabActivationContext(from: button) {
            gtkTabDebugLog("sidebar fallback requested=\(context.id) at=\(Int(x)),\(Int(y))")
            context.activate(button: button)
            return
        }
        child = gtk_widget_get_next_sibling(button)
    }
}

private func gtkInstallSidebarTabRootActivationFallback(
    on widget: UnsafeMutablePointer<GtkWidget>,
    sidebar: UnsafeMutablePointer<GtkWidget>
) {
    gtk_widget_set_can_target(widget, 1)
    let context = Unmanaged.passRetained(GTKSidebarTabFallbackContext(sidebar: sidebar)).toOpaque()
    g_signal_connect_data(
        gpointer(widget),
        "map",
        unsafeBitCast({ (widgetPtr: gpointer?, userData: gpointer?) in
            guard let widgetPtr, let userData else { return }
            let widget = UnsafeMutableRawPointer(widgetPtr).assumingMemoryBound(to: GtkWidget.self)
            let context = Unmanaged<GTKSidebarTabFallbackContext>.fromOpaque(userData).takeUnretainedValue()
            guard context.controller == nil,
                  let root = gtk_swift_widget_root_widget(widget) else {
                return
            }
            let controller = gtk_swift_legacy_capture_controller()!
            context.root = root
            context.controller = controller
            g_signal_connect_data(
                controller,
                "event",
                unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
                    guard let event, let userData else { return 0 }
                    guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
                    let context = Unmanaged<GTKSidebarTabFallbackContext>.fromOpaque(userData).takeUnretainedValue()
                    guard let root = context.root else { return 0 }
                    var rootX = 0.0
                    var rootY = 0.0
                    guard gtk_swift_event_get_position(event, &rootX, &rootY) != 0 else { return 0 }
                    var sidebarX = 0.0
                    var sidebarY = 0.0
                    guard gtk_widget_translate_coordinates(root, context.sidebar, rootX, rootY, &sidebarX, &sidebarY) != 0 else {
                        return 0
                    }
                    gtkActivateSidebarTabAt(sidebar: context.sidebar, x: sidebarX, y: sidebarY)
                    return 0
                } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
                userData,
                nil,
                GConnectFlags(rawValue: 0)
            )
            gtk_swift_add_event_controller(root, controller)
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        context,
        nil,
        GConnectFlags(rawValue: 0)
    )
    g_signal_connect_data(
        gpointer(widget),
        "unmap",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKSidebarTabFallbackContext>.fromOpaque(userData).takeUnretainedValue()
            context.removeController()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        context,
        nil,
        GConnectFlags(rawValue: 0)
    )
    g_signal_connect_data(
        gpointer(widget),
        "destroy",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKSidebarTabFallbackContext>.fromOpaque(userData).takeRetainedValue()
            context.removeController()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        context,
        nil,
        GConnectFlags(rawValue: 0)
    )

    let gesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(gesture, 1)
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (gesturePtr: gpointer?, _: gint, x: gdouble, y: gdouble, userData: gpointer?) in
            guard let gesturePtr,
                  let widget = gtk_swift_event_controller_get_widget(gesturePtr),
                  let userData else {
                return
            }
            let context = Unmanaged<GTKSidebarTabFallbackContext>.fromOpaque(userData).takeUnretainedValue()
            let source = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkWidget.self)
            var sidebarX = x
            var sidebarY = y
            if source != context.sidebar {
                guard gtk_widget_translate_coordinates(source, context.sidebar, x, y, &sidebarX, &sidebarY) != 0 else {
                    return
                }
            }
            gtkActivateSidebarTabAt(sidebar: context.sidebar, x: sidebarX, y: sidebarY)
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        context,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(widget, gesture)
}

private func gtkCreateSidebarTabButton(
    tab: AnyTab,
    id: String,
    stack: UnsafeMutablePointer<GtkWidget>,
    selectionHandler: ((String) -> Void)?,
    isSelected: Bool
) -> UnsafeMutablePointer<GtkWidget> {
    let button = gtk_button_new()!
    gtk_widget_add_css_class(button, "flat")
    gtk_widget_add_css_class(button, gtkSidebarTabButtonClass)
    if isSelected {
        gtk_widget_add_css_class(button, gtkSidebarTabSelectedClass)
    }
    gtk_widget_set_hexpand(button, 1)
    gtk_widget_set_halign(button, GTK_ALIGN_FILL)

    let child: UnsafeMutablePointer<GtkWidget>
    if let label = tab.label {
        child = widgetFromOpaque(gtkRenderAnyView(label))
    } else {
        child = gtk_label_new(tab.title.isEmpty ? id : tab.title)!
        gtk_swift_label_set_xalign(child, 0)
    }
    gtk_widget_set_hexpand(child, 1)
    gtk_widget_set_halign(child, GTK_ALIGN_FILL)
    gtk_widget_set_margin_top(child, 6)
    gtk_widget_set_margin_bottom(child, 6)
    gtk_widget_set_margin_start(child, 10)
    gtk_widget_set_margin_end(child, 10)
    gtk_button_set_child(UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self), child)
    gtkDisableButtonChildTargeting(child)

    let context = Unmanaged.passRetained(GTKTabActivationBox(
        button: button,
        stack: stack,
        id: id,
        selectionHandler: selectionHandler
    )).toOpaque()
    gtkAttachSidebarTabActivationContext(context, to: button)
    g_signal_connect_data(
        gpointer(button),
        "clicked",
        unsafeBitCast({ (buttonPtr: gpointer?, userData: gpointer?) in
            gtkActivateSidebarTab(buttonPtr: buttonPtr, userData: userData)
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        context,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<GTKTabActivationBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtkInstallSidebarTabActivationGesture(on: button, context: context)
    gtkInstallSidebarTabActivationGesture(on: child, context: context)

    return button
}

extension TabView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        var usedIds = Set<String>()
        var children: [GTK4DescriptorNode] = []

        for tab in tabs {
            var id = tab.id
            if usedIds.contains(id) {
                var suffix = 2
                while usedIds.contains("\(id)-\(suffix)") { suffix += 1 }
                id = "\(id)-\(suffix)"
            }
            usedIds.insert(id)

            children.append(
                gtkWithStateIdentityNamespaceComponent("Tab[\(id)]") {
                    gtkDescribeAnyView(tab.wrapped)
                }
            )
        }

        return GTK4DescriptorNode(
            kind: .composite,
            typeName: "TabView",
            children: children
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let stack = gtk_stack_new()!
        gtk_swift_stack_set_transition_type(stack, GTK_STACK_TRANSITION_TYPE_SLIDE_LEFT_RIGHT)
        gtk_widget_set_hexpand(stack, 1)
        gtk_widget_set_vexpand(stack, 1)
        gtk_widget_set_halign(stack, GTK_ALIGN_FILL)
        gtk_widget_set_valign(stack, GTK_ALIGN_FILL)

        var usedIds = Set<String>()
        var resolvedTabs: [(tab: AnyTab, id: String)] = []
        var selectedResolvedId: String?
        for tab in tabs {
            var id = tab.id
            if usedIds.contains(id) {
                var suffix = 2
                while usedIds.contains("\(id)-\(suffix)") { suffix += 1 }
                id = "\(id)-\(suffix)"
            }
            usedIds.insert(id)
            resolvedTabs.append((tab, id))
            if selectedResolvedId == nil, tab.id == selectedID {
                selectedResolvedId = id
            }
        }

        let initialResolvedId: String?
        if let tabIndex = initialTab, tabIndex >= 0, tabIndex < resolvedTabs.count {
            initialResolvedId = resolvedTabs[tabIndex].id
        } else {
            initialResolvedId = nil
        }
        let activeResolvedId = selectedResolvedId ?? initialResolvedId ?? resolvedTabs.first?.id
        let lazilyRenderInactiveTabs = selectionHandler != nil

        for (tab, id) in resolvedTabs {
            let childWidget = widgetFromOpaque(gtkWithStateIdentityNamespaceComponent("Tab[\(id)]") {
                if lazilyRenderInactiveTabs, id != activeResolvedId {
                    opaqueFromWidget(gtkCreateEmptyViewWidget())
                } else {
                    gtkRenderAnyView(tab.wrapped)
                }
            })
            gtk_widget_set_hexpand(childWidget, 1)
            gtk_widget_set_vexpand(childWidget, 1)
            gtk_widget_set_halign(childWidget, GTK_ALIGN_FILL)
            gtk_widget_set_valign(childWidget, GTK_ALIGN_FILL)
            gtk_swift_stack_add_titled(stack, childWidget, id, tab.title)
        }

        if let activeResolvedId {
            gtk_swift_stack_set_visible_child_name(stack, activeResolvedId)
        }
        let visibleName = gtk_swift_stack_get_visible_child_name(stack)
            .map { String(cString: $0) } ?? "<nil>"
        gtkTabDebugLog("created selectedID=\(selectedID ?? "<nil>") ordered=\(resolvedTabs.map(\.id).joined(separator: ",")) visible=\(visibleName)")

        if gtkTabViewShouldShowSidebar(tabs) {
            let root = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
            gtk_widget_set_hexpand(root, 1)
            gtk_widget_set_vexpand(root, 1)
            gtk_widget_set_halign(root, GTK_ALIGN_FILL)
            gtk_widget_set_valign(root, GTK_ALIGN_FILL)

            let sidebar = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)!
            gtk_widget_set_size_request(sidebar, 240, -1)
            gtk_widget_set_hexpand(sidebar, 0)
            gtk_widget_set_hexpand_set(sidebar, 1)
            gtk_widget_set_halign(sidebar, GTK_ALIGN_START)
            gtk_widget_set_vexpand(sidebar, 1)
            gtk_widget_set_valign(sidebar, GTK_ALIGN_FILL)
            gtk_widget_set_can_target(sidebar, 1)
            ensureSidebarTabCSS(sidebar)
            gtk_widget_add_css_class(sidebar, gtkSidebarTabClass)
            gtkInstallSidebarTabRootActivationFallback(on: sidebar, sidebar: sidebar)

            for (tab, id) in resolvedTabs {
                let button = gtkCreateSidebarTabButton(
                    tab: tab,
                    id: id,
                    stack: stack,
                    selectionHandler: selectionHandler,
                    isSelected: id == visibleName
                )
                gtk_box_append(boxPointer(sidebar), button)
            }

            gtk_box_append(boxPointer(root), sidebar)
            gtk_box_append(boxPointer(root), stack)
            gtkInstallSidebarTabRootActivationFallback(on: root, sidebar: sidebar)
            return opaqueFromWidget(root)
        }

        let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        if gtkTabViewShouldShowSwitcher(tabs) {
            let switcher = gtk_stack_switcher_new()!
            gtk_swift_stack_switcher_set_stack(switcher, stack)
            gtk_box_append(boxPointer(vbox), switcher)
        }
        gtk_box_append(boxPointer(vbox), stack)
        gtk_widget_set_hexpand(vbox, 1)
        gtk_widget_set_vexpand(vbox, 1)

        return opaqueFromWidget(vbox)
    }
}

// MARK: - Grid GTK extension

extension Grid: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        if useExplicitRows {
            let rows = gtkCollectGridRows(content)
            if gtkCanUseSharedExplicitGridLayout(rows) {
                return gtkRenderSharedExplicitGrid(
                    rows,
                    hSpacing: hSpacing,
                    vSpacing: vSpacing
                )
            }
        } else {
            let children = gtkRenderChildren(content).map(widgetFromOpaque)
            if gtkCanUseSharedGridLayout(children) {
                return gtkRenderSharedAutoGrid(
                    children,
                    columns: columns,
                    hSpacing: hSpacing,
                    vSpacing: vSpacing
                )
            }
        }

        let grid = gtk_grid_new()!
        gtk_swift_grid_set_row_spacing(grid, guint(vSpacing))
        gtk_swift_grid_set_column_spacing(grid, guint(hSpacing))
        gtk_swift_grid_set_column_homogeneous(grid, 1)

        if useExplicitRows {
            gtkLayoutExplicitRows(grid: grid)
            gtk_widget_set_hexpand(grid, 1)
        } else {
            let children = gtkRenderChildren(content)
            for (index, child) in children.enumerated() {
                let row = index / columns
                let col = index % columns
                gtk_swift_grid_attach(grid, widgetFromOpaque(child), gint(col), gint(row), 1, 1)
            }
        }

        return opaqueFromWidget(grid)
    }

    private func gtkLayoutExplicitRows(grid: UnsafeMutablePointer<GtkWidget>) {
        let rowViews = gtkCollectGridRows(content)
        var row = 0
        for rowContent in rowViews {
            var col = 0
            for cell in rowContent {
                let widget = widgetFromOpaque(cell.widget)
                gtk_widget_set_hexpand(widget, 1)
                gtk_widget_set_vexpand(widget, 1)
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
                gtk_swift_grid_attach(grid, widget, gint(col), gint(row), gint(cell.columnSpan), 1)
                col += cell.columnSpan
            }
            row += 1
        }
    }
}

private func gtkCanUseSharedGridLayout(_ children: [UnsafeMutablePointer<GtkWidget>]) -> Bool {
    for widget in children {
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            return false
        }
        if gtk_widget_get_hexpand(widget) != 0 || gtk_widget_get_vexpand(widget) != 0 {
            return false
        }
    }
    return true
}

private func gtkRenderSharedAutoGrid(
    _ children: [UnsafeMutablePointer<GtkWidget>],
    columns: Int,
    hSpacing: Int,
    vSpacing: Int
) -> OpaquePointer {
    let wrapper = gtk_swift_fixed_new()!
    let subviews = children.indices.map(LayoutSubview.init(index:))
    let context = GTKLayoutMeasureContext(widgets: children)
    let layout = computeGridLayout(
        subviews: subviews,
        context: context,
        columns: columns,
        hSpacing: Double(hSpacing),
        vSpacing: Double(vSpacing)
    )

    gtk_widget_set_size_request(
        wrapper,
        gint(layout.containerSize.width),
        gint(layout.containerSize.height)
    )

    for (widget, placement) in zip(children, layout.childPlacements) {
        gtk_widget_set_halign(widget, GTK_ALIGN_START)
        gtk_widget_set_valign(widget, GTK_ALIGN_START)
        gtk_swift_fixed_put(wrapper, widget, placement.origin.x, placement.origin.y)
    }

    return opaqueFromWidget(wrapper)
}

private func gtkCanUseSharedExplicitGridLayout(_ rows: [[GTKGridCell]]) -> Bool {
    for row in rows {
        for cell in row {
            let widget = widgetFromOpaque(cell.widget)
            let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
            if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
                return false
            }
            if gtk_widget_get_hexpand(widget) != 0 || gtk_widget_get_vexpand(widget) != 0 {
                return false
            }
        }
    }
    return true
}

private func gtkRenderSharedExplicitGrid(
    _ rows: [[GTKGridCell]],
    hSpacing: Int,
    vSpacing: Int
) -> OpaquePointer {
    let wrapper = gtk_swift_fixed_new()!
    let flattenedCells = rows.flatMap { $0 }
    let widgets = flattenedCells.map { widgetFromOpaque($0.widget) }
    let context = GTKLayoutMeasureContext(widgets: widgets)
    var subviewIndex = 0
    let layout = computeExplicitGridLayout(
        rows: rows.map { row in
            row.map { cell in
                let subview = LayoutSubview(index: subviewIndex)
                subviewIndex += 1
                return (
                    subview: subview,
                    columnSpan: cell.columnSpan
                )
            }
        },
        context: context,
        hSpacing: Double(hSpacing),
        vSpacing: Double(vSpacing)
    )

    gtk_widget_set_size_request(
        wrapper,
        gint(layout.containerSize.width),
        gint(layout.containerSize.height)
    )

    for (cell, placement) in zip(flattenedCells, layout.childPlacements) {
        let widget = widgetFromOpaque(cell.widget)
        gtk_widget_set_halign(widget, GTK_ALIGN_START)
        gtk_widget_set_valign(widget, GTK_ALIGN_START)
        gtk_widget_set_size_request(
            widget,
            gint(placement.size.width),
            gint(placement.size.height)
        )
        gtk_swift_fixed_put(wrapper, widget, placement.origin.x, placement.origin.y)
    }

    return opaqueFromWidget(wrapper)
}

/// Grid cell info for layout.
private struct GTKGridCell {
    let widget: OpaquePointer
    let columnSpan: Int
}

/// Flatten a view into its top-level child views using the MultiChildView
/// contract.  Stops at GridRow boundaries — GridRow is a row delimiter,
/// not a transparent container, so its children must stay grouped.
private func gtkFlattenChildren(_ view: any View) -> [any View] {
    // GridRow is a MultiChildView but must NOT be flattened — it's a
    // semantic boundary that gtkExtractRowCells needs to see intact.
    let typeName = String(describing: type(of: view))
    if typeName.contains("GridRow") {
        return [view]
    }
    if let multi = view as? MultiChildView {
        return multi.children.flatMap { gtkFlattenChildren($0) }
    }
    return [view]
}

/// Walk the content view tree and extract GridRow children with their cell spans.
private func gtkCollectGridRows<V: View>(_ view: V) -> [[GTKGridCell]] {
    let topLevel = gtkFlattenChildren(view)
    var rows: [[GTKGridCell]] = []

    for child in topLevel {
        if let rowCells = gtkExtractRowCells(child) {
            rows.append(rowCells)
        } else {
            func render<C: View>(_ c: C) -> OpaquePointer { gtkRenderView(c) }
            rows.append([GTKGridCell(widget: render(child), columnSpan: 1)])
        }
    }

    if rows.isEmpty {
        rows.append([GTKGridCell(widget: gtkRenderView(view), columnSpan: 1)])
    }

    return rows
}

/// Try to extract cells from a GridRow view.
private func gtkExtractRowCells(_ view: any View) -> [GTKGridCell]? {
    let typeName = String(describing: type(of: view))
    guard typeName.contains("GridRow") else { return nil }

    // GridRow conforms to MultiChildView — use its children for cell extraction
    if let multi = view as? MultiChildView {
        return multi.children.map { child in
            gtkMakeCell(from: child)
        }
    }

    // Fallback: render as single cell
    func render<V: View>(_ v: V) -> OpaquePointer { gtkRenderView(v) }
    return [GTKGridCell(widget: render(view), columnSpan: 1)]
}

/// Create a GTKGridCell from a view, checking for GridCellSpanProvider.
private func gtkMakeCell(from view: any View) -> GTKGridCell {
    let span = gtkFindColumnSpan(in: view)
    return GTKGridCell(widget: gtkRenderAnyView(view), columnSpan: span)
}

/// Recursively walk through modifier wrappers to find a GridCellSpanProvider.
private func gtkFindColumnSpan(in view: Any) -> Int {
    if let spanProvider = view as? GridCellSpanProvider {
        return spanProvider.gridColumnSpan
    }
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
        if child.label == "content" {
            let innerSpan = gtkFindColumnSpan(in: child.value)
            if innerSpan > 1 { return innerSpan }
        }
    }
    return 1
}

extension GridRow: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        // Fallback if used outside Grid — wrap in HStack
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        for child in gtkRenderChildren(content) {
            gtk_box_append(boxPointer(box), widgetFromOpaque(child))
        }
        return opaqueFromWidget(box)
    }
}

extension GridCellSpanView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkRenderView(content)
    }
}

// MARK: - DisclosureGroup GTK extension

/// Closure box for expander state change.
private class ExpandedClosureBox {
    let closure: (Bool) -> Void
    init(_ closure: @escaping (Bool) -> Void) { self.closure = closure }
}

extension DisclosureGroup: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let expander: UnsafeMutablePointer<GtkWidget>
        if let labelView = labelView {
            // Custom label view — create expander without title and set
            // a custom label widget instead.
            expander = gtk_swift_expander_new("")!
            let labelWidget = widgetFromOpaque(gtkRenderView(labelView))
            gtk_swift_expander_set_label_widget(expander, labelWidget)
        } else {
            expander = gtk_swift_expander_new(title)!
        }
        gtk_swift_expander_set_expanded(expander, isExpanded ? 1 : 0)

        let childWidget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_margin_start(childWidget, 16)
        gtk_swift_expander_set_child(expander, childWidget)

        if let onChange = onExpandedChange {
            let boundOnChange = bindActionToCurrentEnvironment(onChange)
            let box = Unmanaged.passRetained(ExpandedClosureBox(boundOnChange)).toOpaque()
            g_signal_connect_data(
                gpointer(expander),
                "notify::expanded",
                unsafeBitCast({ (expanderPtr: gpointer?, _: gpointer?, userData: gpointer?) in
                    guard let expanderPtr = expanderPtr, let userData = userData else { return }
                    let widget = UnsafeMutableRawPointer(expanderPtr).assumingMemoryBound(to: GtkWidget.self)
                    let box = Unmanaged<ExpandedClosureBox>.fromOpaque(userData).takeUnretainedValue()
                    let expanded = gtk_swift_expander_get_expanded(widget) != 0
                    box.closure(expanded)
                } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
                box,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<ExpandedClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }

        return opaqueFromWidget(expander)
    }
}

// MARK: - Form GTK extension

extension Form: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)!
        let boxPtr = boxPointer(box)
        let formChildren = gtkFormChildViews(of: content)

        if formChildren.contains(where: gtkIsSectionView) {
            for child in gtkFormChildViews(of: content) {
                if gtkIsSectionView(child) {
                    gtk_box_append(boxPtr, widgetFromOpaque(gtkRenderAnyView(child)))
                } else {
                    let rows = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                    gtk_widget_set_hexpand(rows, 1)
                    gtk_widget_set_halign(rows, GTK_ALIGN_FILL)
                    gtkAppendRows([child], to: rows)
                    gtk_box_append(boxPtr, rows)
                }
            }
        } else {
            let rows = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
            gtk_widget_set_hexpand(rows, 1)
            gtk_widget_set_halign(rows, GTK_ALIGN_FILL)
            gtkAppendRows(gtkDirectChildViews(of: content), to: rows)
            gtk_box_append(boxPtr, rows)
        }

        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
        let scrolled = gtk_scrolled_window_new()!
        let scrolledOp = OpaquePointer(scrolled)
        gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
        gtk_scrolled_window_set_has_frame(scrolledOp, 0)
        gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
        gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)
        let clampedBox = gtk_swift_width_clamp_new(box)!
        let viewport = gtk_swift_min_width_viewport_new(clampedBox)!
        gtk_scrolled_window_set_child(scrolledOp, viewport)
        gtkInstallScrollViewCrossAxisFill(on: scrolled, child: viewport, fillWidth: true, fillHeight: false)
        gtk_widget_set_hexpand(scrolled, 1)
        gtk_widget_set_vexpand(scrolled, 1)
        gtk_widget_set_margin_top(scrolled, 16)
        gtk_widget_set_margin_bottom(scrolled, 16)
        gtk_widget_set_margin_start(scrolled, 16)
        gtk_widget_set_margin_end(scrolled, 16)

        return opaqueFromWidget(scrolled)
    }
}

// MARK: - Section GTK extension

private func gtkIsSectionView(_ view: any View) -> Bool {
    let typeName = String(describing: type(of: view))
    let reflectedTypeName = String(reflecting: type(of: view))
    return typeName.hasPrefix("Section<")
        || reflectedTypeName.contains("SwiftOpenUI.Section<")
}

extension Section: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4)!
        let boxPtr = boxPointer(box)

        if let header = header {
            let label = gtk_label_new(nil)!
            let escaped = header
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            gtk_swift_label_set_markup(label, "<b>\(escaped)</b>")
            gtk_widget_set_halign(label, GTK_ALIGN_START)
            gtk_box_append(boxPtr, label)
        }

        let rows = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(rows, 1)
        gtk_widget_set_halign(rows, GTK_ALIGN_FILL)
        gtkAppendRows(gtkDirectChildViews(of: content), to: rows)
        gtk_box_append(boxPtr, rows)

        if let footer = footer {
            let label = gtk_label_new(footer)!
            gtk_widget_set_halign(label, GTK_ALIGN_START)
            applyCSSToWidget(label, properties: "font-size: 11px; opacity: 0.6;")
            gtk_box_append(boxPtr, label)
        }

        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_halign(box, GTK_ALIGN_FILL)

        return opaqueFromWidget(box)
    }
}

// MARK: - LazyVStack / LazyHStack GTK extensions

/// Context holding item count and render closure for factory callbacks.
private class LazyListContext {
    let itemCount: Int
    let renderItem: (Int) -> UnsafeMutablePointer<GtkWidget>

    init<Data, Content: View>(items: [Data], contentBuilder: @escaping (Data) -> Content) {
        self.itemCount = items.count
        let foregroundColor = _gtkCurrentForegroundColor
        self.renderItem = { index in
            gtkWithCurrentForegroundColor(foregroundColor) {
                widgetFromOpaque(gtkRenderView(contentBuilder(items[index])))
            }
        }
    }
}

private let gtkStaticLazyStackItemLimit = 64

private func gtkCreateStaticLazyStackWidget<Data, Content: View>(
    items: [Data],
    contentBuilder: @escaping (Data) -> Content,
    orientation: GtkOrientation
) -> OpaquePointer? {
    guard items.count <= gtkStaticLazyStackItemLimit else { return nil }

    let box = gtk_box_new(orientation, 0)!
    var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []
    renderedChildren.reserveCapacity(items.count)

    for item in items {
        let child = widgetFromOpaque(gtkRenderView(contentBuilder(item)))
        renderedChildren.append(child)
        gtk_box_append(boxPointer(box), child)
    }

    let hasHorizontalExpansion = renderedChildren.contains {
        gtk_widget_get_hexpand($0) != 0
    }
    let hasVerticalExpansion = renderedChildren.contains {
        gtk_widget_get_vexpand($0) != 0
    }
    let hasVerticalFillIntent = renderedChildren.contains {
        gtkHasVerticalFillIntent($0)
    }

    if orientation == GTK_ORIENTATION_VERTICAL {
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_halign(box, GTK_ALIGN_FILL)
        if hasVerticalExpansion {
            gtk_widget_set_vexpand(box, 1)
            gtk_widget_set_valign(box, GTK_ALIGN_FILL)
        }
    } else {
        if hasHorizontalExpansion {
            gtk_widget_set_hexpand(box, 1)
            gtk_widget_set_halign(box, GTK_ALIGN_FILL)
        }
        if hasVerticalExpansion || hasVerticalFillIntent {
            gtk_widget_set_vexpand(box, 1)
            gtk_widget_set_valign(box, GTK_ALIGN_FILL)
        }
    }

    if hasVerticalFillIntent {
        gtkMarkVerticalFillIntent(box)
    }
    gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)
    return opaqueFromWidget(box)
}

/// Create a GtkListView-based lazy list widget.
private func gtkCreateLazyListWidget<Data, Content: View>(
    items: [Data],
    contentBuilder: @escaping (Data) -> Content,
    orientation: GtkOrientation
) -> OpaquePointer {
    let stringList = gtk_swift_string_list_new()!
    for i in 0..<items.count {
        gtk_swift_string_list_append(stringList, "\(i)")
    }

    let noSelection = gtk_swift_no_selection_new(stringList)
    let factory = gtk_swift_signal_list_item_factory_new()!

    let context = LazyListContext(items: items, contentBuilder: contentBuilder)
    let contextPtr = Unmanaged.passRetained(context).toOpaque()
    g_object_set_data_full(
        factory.assumingMemoryBound(to: GObject.self),
        "gtk-swift-lazy-context",
        contextPtr,
        { userData in Unmanaged<LazyListContext>.fromOpaque(userData!).release() }
    )

    g_signal_connect_data(factory, "setup",
        unsafeBitCast(lazyListSetupCallback, to: GCallback.self),
        nil, nil, GConnectFlags(rawValue: 0))
    g_signal_connect_data(factory, "bind",
        unsafeBitCast(lazyListBindCallback, to: GCallback.self),
        nil, nil, GConnectFlags(rawValue: 0))
    g_signal_connect_data(factory, "unbind",
        unsafeBitCast(lazyListUnbindCallback, to: GCallback.self),
        nil, nil, GConnectFlags(rawValue: 0))

    let listView = gtk_swift_list_view_new(noSelection, factory)!
    gtk_swift_orientable_set_orientation(listView, orientation)

    // Transparent background so parent shows through
    applyCSSToWidget(listView, properties: "background-color: transparent;")
    let rowCSS = "listview.gtk-swift-lazy-transparent row { background-color: transparent; }"
    let rowProvider = gtk_css_provider_new()!
    gtk_css_provider_load_from_string(rowProvider, rowCSS)
    gtk_swift_add_css_provider_to_display(
        gtk_widget_get_display(listView),
        rowProvider,
        UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
    )
    g_object_unref(gpointer(rowProvider))
    gtk_widget_add_css_class(listView, "gtk-swift-lazy-transparent")

    // Wrap in scrolled window
    let scrolled = gtk_scrolled_window_new()!
    gtk_scrolled_window_set_policy(
        OpaquePointer(scrolled),
        GTK_POLICY_EXTERNAL,
        GTK_POLICY_EXTERNAL
    )
    gtk_scrolled_window_set_has_frame(OpaquePointer(scrolled), 0)
    gtk_scrolled_window_set_child(OpaquePointer(scrolled), listView)
    gtk_widget_set_vexpand(scrolled, orientation == GTK_ORIENTATION_VERTICAL ? 1 : 0)
    gtk_widget_set_hexpand(scrolled, 1)
    applyCSSToWidget(scrolled, properties: "background-color: transparent;")

    return opaqueFromWidget(scrolled)
}

// Factory callbacks for lazy lists

private let lazyListSetupCallback: @convention(c) (
    gpointer?, gpointer?, gpointer?
) -> Void = { factory, listItem, userData in
    guard let listItem = listItem else { return }
    let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    gtk_widget_set_hexpand(box, 1)
    gtk_swift_list_item_set_child(listItem, box)
}

private let lazyListBindCallback: @convention(c) (
    gpointer?, gpointer?, gpointer?
) -> Void = { factoryPtr, listItem, userData in
    guard let factoryPtr = factoryPtr, let listItem = listItem else { return }

    guard let gobject = gtk_swift_list_item_get_item(listItem) else { return }
    guard let cStr = gtk_swift_string_object_get_string(gobject) else { return }
    guard let index = Int(String(cString: cStr)) else {
        lazyListClearChild(listItem)
        return
    }

    guard let contextPtr = g_object_get_data(
        factoryPtr.assumingMemoryBound(to: GObject.self),
        "gtk-swift-lazy-context"
    ) else { return }
    let context = Unmanaged<LazyListContext>.fromOpaque(contextPtr).takeUnretainedValue()

    guard index >= 0 && index < context.itemCount else {
        lazyListClearChild(listItem)
        return
    }

    guard let box = gtk_swift_list_item_get_child(listItem) else { return }
    while let child = gtk_widget_get_first_child(box) {
        gtk_box_remove(boxPointer(box), child)
    }
    gtk_box_append(boxPointer(box), context.renderItem(index))
}

private let lazyListUnbindCallback: @convention(c) (
    gpointer?, gpointer?, gpointer?
) -> Void = { factory, listItem, userData in
    guard let listItem = listItem else { return }
    lazyListClearChild(listItem)
}

private func lazyListClearChild(_ listItem: gpointer) {
    guard let box = gtk_swift_list_item_get_child(listItem) else { return }
    while let child = gtk_widget_get_first_child(box) {
        gtk_box_remove(boxPointer(box), child)
    }
}

extension LazyVStack: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        if let staticWidget = gtkCreateStaticLazyStackWidget(
            items: items,
            contentBuilder: contentBuilder,
            orientation: GTK_ORIENTATION_VERTICAL
        ) {
            return staticWidget
        }
        return gtkCreateLazyListWidget(items: items, contentBuilder: contentBuilder,
                                       orientation: GTK_ORIENTATION_VERTICAL)
    }
}

extension LazyHStack: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        if let staticWidget = gtkCreateStaticLazyStackWidget(
            items: items,
            contentBuilder: contentBuilder,
            orientation: GTK_ORIENTATION_HORIZONTAL
        ) {
            return staticWidget
        }
        return gtkCreateLazyListWidget(items: items, contentBuilder: contentBuilder,
                                       orientation: GTK_ORIENTATION_HORIZONTAL)
    }
}

// MARK: - LazyVGrid / LazyHGrid GTK extensions

/// Context for lazy grid factory callbacks.
private class LazyGridContext {
    let itemCount: Int
    let renderItem: (Int) -> UnsafeMutablePointer<GtkWidget>
    let cellMinWidth: Int

    init<Data, Content: View>(items: [Data], contentBuilder: @escaping (Data) -> Content,
                              cellMinWidth: Int) {
        self.itemCount = items.count
        self.cellMinWidth = cellMinWidth
        let foregroundColor = _gtkCurrentForegroundColor
        self.renderItem = { index in
            gtkWithCurrentForegroundColor(foregroundColor) {
                widgetFromOpaque(gtkRenderView(contentBuilder(items[index])))
            }
        }
    }

    init(views: [any View], cellMinWidth: Int) {
        self.itemCount = views.count
        self.cellMinWidth = cellMinWidth
        let foregroundColor = _gtkCurrentForegroundColor
        self.renderItem = { index in
            gtkWithCurrentForegroundColor(foregroundColor) {
                widgetFromOpaque(gtkRenderAnyView(views[index]))
            }
        }
    }
}

/// Create a GtkGridView-based lazy grid widget.
private func gtkCreateStaticLazyGridWidget(
    views: [any View],
    configuration: LazyGridConfiguration,
    cellMinWidth: Int,
    orientation: GtkOrientation
) -> OpaquePointer? {
    guard !views.isEmpty else { return nil }
    guard orientation == GTK_ORIENTATION_VERTICAL else { return nil }
    guard views.count <= 64 else { return nil }

    let columns = max(1, min(max(configuration.maxColumns, configuration.minColumns), views.count))
    let grid = gtk_grid_new()!
    gtk_swift_grid_set_row_spacing(grid, 15)
    gtk_swift_grid_set_column_spacing(grid, 15)
    gtk_swift_grid_set_column_homogeneous(grid, 1)
    gtk_widget_set_hexpand(grid, 1)
    gtk_widget_set_halign(grid, GTK_ALIGN_FILL)

    for (index, view) in views.enumerated() {
        let child = widgetFromOpaque(gtkRenderAnyView(view))
        let slot = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(slot, 1)
        gtk_widget_set_halign(slot, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(child, 1)
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        if cellMinWidth > 0 {
            gtk_widget_set_size_request(slot, gint(cellMinWidth), -1)
        }
        gtk_box_append(boxPointer(slot), child)
        gtk_swift_grid_attach(
            grid,
            slot,
            gint(index % columns),
            gint(index / columns),
            1,
            1
        )
    }

    return opaqueFromWidget(grid)
}

private func gtkCreateLazyGridWidget<Data, Content: View>(
    items: [Data],
    contentBuilder: @escaping (Data) -> Content,
    gridItems: [GridItem],
    orientation: GtkOrientation
) -> OpaquePointer {
    let expandedChildren: [any View]? = {
        guard items.count == 1 else { return nil }
        let built = contentBuilder(items[0])
        guard let multi = built as? MultiChildView else { return nil }
        return multi.children
    }()
    let itemCount = expandedChildren?.count ?? items.count

    let stringList = gtk_swift_string_list_new()!
    for i in 0..<itemCount {
        gtk_swift_string_list_append(stringList, "\(i)")
    }

    let noSelection = gtk_swift_no_selection_new(stringList)
    let factory = gtk_swift_signal_list_item_factory_new()!

    let configuration = computeLazyGridConfiguration(gridItems: gridItems)
    let cellMinWidth = configuration.adaptiveMinimum > 0
        ? configuration.adaptiveMinimum
        : (configuration.maxColumns > 1 ? 160 : 0)
    if let expandedChildren,
       let staticGrid = gtkCreateStaticLazyGridWidget(
            views: expandedChildren,
            configuration: configuration,
            cellMinWidth: cellMinWidth,
            orientation: orientation
       ) {
        return staticGrid
    }

    let context: LazyGridContext
    if let expandedChildren {
        context = LazyGridContext(views: expandedChildren, cellMinWidth: cellMinWidth)
    } else {
        context = LazyGridContext(items: items, contentBuilder: contentBuilder,
                                  cellMinWidth: cellMinWidth)
    }
    let contextPtr = Unmanaged.passRetained(context).toOpaque()
    g_object_set_data_full(
        factory.assumingMemoryBound(to: GObject.self),
        "gtk-swift-lazy-grid-context",
        contextPtr,
        { userData in Unmanaged<LazyGridContext>.fromOpaque(userData!).release() }
    )

    g_signal_connect_data(factory, "setup",
        unsafeBitCast(lazyGridSetupCallback, to: GCallback.self),
        nil, nil, GConnectFlags(rawValue: 0))
    g_signal_connect_data(factory, "bind",
        unsafeBitCast(lazyGridBindCallback, to: GCallback.self),
        nil, nil, GConnectFlags(rawValue: 0))
    g_signal_connect_data(factory, "unbind",
        unsafeBitCast(lazyGridUnbindCallback, to: GCallback.self),
        nil, nil, GConnectFlags(rawValue: 0))

    let gridView = gtk_swift_grid_view_new(noSelection, factory)!
    gtk_swift_orientable_set_orientation(gridView, orientation)

    gtk_swift_grid_view_set_min_columns(gridView, guint(configuration.minColumns))
    gtk_swift_grid_view_set_max_columns(gridView, guint(configuration.maxColumns))

    gtk_widget_set_vexpand(gridView, 1)
    gtk_widget_set_hexpand(gridView, 1)

    return opaqueFromWidget(gridView)
}

// Factory callbacks for lazy grids

private let lazyGridSetupCallback: @convention(c) (
    gpointer?, gpointer?, gpointer?
) -> Void = { factoryPtr, listItem, userData in
    guard let listItem = listItem else { return }
    let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    gtk_widget_set_hexpand(box, 1)

    if let factoryPtr = factoryPtr,
       let contextPtr = g_object_get_data(
           factoryPtr.assumingMemoryBound(to: GObject.self),
           "gtk-swift-lazy-grid-context") {
        let context = Unmanaged<LazyGridContext>.fromOpaque(contextPtr).takeUnretainedValue()
        if context.cellMinWidth > 0 {
            gtk_widget_set_size_request(box, gint(context.cellMinWidth), -1)
        }
    }

    gtk_swift_list_item_set_child(listItem, box)
}

private let lazyGridBindCallback: @convention(c) (
    gpointer?, gpointer?, gpointer?
) -> Void = { factoryPtr, listItem, userData in
    guard let factoryPtr = factoryPtr, let listItem = listItem else { return }

    guard let gobject = gtk_swift_list_item_get_item(listItem) else { return }
    guard let cStr = gtk_swift_string_object_get_string(gobject) else { return }
    guard let index = Int(String(cString: cStr)) else {
        lazyGridClearChild(listItem)
        return
    }

    guard let contextPtr = g_object_get_data(
        factoryPtr.assumingMemoryBound(to: GObject.self),
        "gtk-swift-lazy-grid-context"
    ) else { return }
    let context = Unmanaged<LazyGridContext>.fromOpaque(contextPtr).takeUnretainedValue()

    guard index >= 0 && index < context.itemCount else {
        lazyGridClearChild(listItem)
        return
    }

    guard let box = gtk_swift_list_item_get_child(listItem) else { return }
    while let child = gtk_widget_get_first_child(box) {
        gtk_box_remove(boxPointer(box), child)
    }
    gtk_box_append(boxPointer(box), context.renderItem(index))
}

private let lazyGridUnbindCallback: @convention(c) (
    gpointer?, gpointer?, gpointer?
) -> Void = { factory, listItem, userData in
    guard let listItem = listItem else { return }
    lazyGridClearChild(listItem)
}

private func lazyGridClearChild(_ listItem: gpointer) {
    guard let box = gtk_swift_list_item_get_child(listItem) else { return }
    while let child = gtk_widget_get_first_child(box) {
        gtk_box_remove(boxPointer(box), child)
    }
}

extension LazyVGrid: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkCreateLazyGridWidget(items: items, contentBuilder: contentBuilder,
                                gridItems: gridItems, orientation: GTK_ORIENTATION_VERTICAL)
    }
}

extension LazyHGrid: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkCreateLazyGridWidget(items: items, contentBuilder: contentBuilder,
                                gridItems: gridItems, orientation: GTK_ORIENTATION_HORIZONTAL)
    }
}

// MARK: - Picker GTK extension

/// Closure box for segmented picker toggle events.
private class SegmentClosureBox {
    let index: Int
    let closure: (Int) -> Void
    init(index: Int, closure: @escaping (Int) -> Void) {
        self.index = index
        self.closure = closure
    }
}

extension Picker: GTKRenderable, GTKDescribable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget: OpaquePointer
        switch style {
        case .segmented, .palette:
            widget = gtkCreateSegmentedWidget()
        default:
            widget = gtkCreateDropdownWidget()
        }
        gtkApplyEnabledState(to: widgetFromOpaque(widget))
        return widget
    }

    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "Picker",
            props: .text(GTK4TextDescriptor(
                content: "\(label)|\(selected)|\(style)|\(options.joined(separator: "\u{1f}"))"
            ))
        )
    }

    /// True iff the caller wrapped us in `.labelsHidden()`. The
    /// env flag is set by `LabelsHiddenView`'s GTK renderer; when on,
    /// both the dropdown and segmented variants omit the label prefix
    /// they'd otherwise inline before the control.
    private var effectiveLabel: String {
        getCurrentEnvironment().labelsHidden ? "" : label
    }

    private func gtkCreateDropdownWidget() -> OpaquePointer {
        let stringList = gtk_swift_string_list_new()!
        for option in options {
            gtk_swift_string_list_append(stringList, option)
        }

        let dropdown = gtk_swift_drop_down_new(stringList)!
        let dropdownOp = OpaquePointer(dropdown)
        let clampedSelection = max(0, min(selected, options.count - 1))
        if !options.isEmpty {
            gtk_drop_down_set_selected(dropdownOp, guint(clampedSelection))
        }

        if let onChanged = onChanged {
            let boundOnChanged = bindActionToCurrentEnvironment(onChanged)
            let box = Unmanaged.passRetained(IntClosureBox { newIndex in
                guard options.indices.contains(newIndex), newIndex != clampedSelection else {
                    return
                }
                boundOnChanged(newIndex)
            }).toOpaque()
            g_signal_connect_data(
                gpointer(dropdown),
                "notify::selected",
                unsafeBitCast({ (widget: gpointer?, _: gpointer?, userData: gpointer?) in
                    let box = Unmanaged<IntClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                    let sel = Int(gtk_drop_down_get_selected(OpaquePointer(widget!)))
                    box.closure(sel)
                } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
                box,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<IntClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }

        let displayedLabel = effectiveLabel
        if !displayedLabel.isEmpty {
            let hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
            let labelWidget = gtk_label_new(displayedLabel)!
            gtk_box_append(boxPointer(hbox), labelWidget)
            gtk_box_append(boxPointer(hbox), dropdown)
            return opaqueFromWidget(hbox)
        }

        return opaqueFromWidget(dropdown)
    }

    private func gtkCreateSegmentedWidget() -> OpaquePointer {
        let hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        gtk_widget_add_css_class(hbox, "linked")

        var firstButton: UnsafeMutablePointer<GtkWidget>?
        let clampedSelection = options.isEmpty ? 0 : max(0, min(selected, options.count - 1))
        var buttons: [UnsafeMutablePointer<GtkWidget>] = []

        for option in options {
            let button = gtk_toggle_button_new_with_label(option)!

            if let first = firstButton {
                gtk_swift_toggle_button_set_group(button, first)
            } else {
                firstButton = button
            }

            buttons.append(button)
            gtk_box_append(boxPointer(hbox), button)
        }

        if buttons.indices.contains(clampedSelection) {
            gtk_swift_toggle_button_set_active(buttons[clampedSelection], 1)
        }

        let boundOnChanged = onChanged.map { bindActionToCurrentEnvironment($0) }
        for (index, button) in buttons.enumerated() {
            if let boundOnChanged = boundOnChanged {
                let box = Unmanaged.passRetained(
                    SegmentClosureBox(index: index, closure: boundOnChanged)
                ).toOpaque()
                g_signal_connect_data(
                    gpointer(button),
                    "toggled",
                    unsafeBitCast({ (buttonPtr: gpointer?, userData: gpointer?) in
                        guard let buttonPtr = buttonPtr, let userData = userData else { return }
                        let widget = UnsafeMutableRawPointer(buttonPtr)
                            .assumingMemoryBound(to: GtkWidget.self)
                        let box = Unmanaged<SegmentClosureBox>.fromOpaque(userData).takeUnretainedValue()
                        if gtk_swift_toggle_button_get_active(widget) != 0 {
                            box.closure(box.index)
                        }
                    } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                    box,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<SegmentClosureBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
            }
        }

        let displayedLabel = effectiveLabel
        if !displayedLabel.isEmpty {
            let outer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
            let labelWidget = gtk_label_new(displayedLabel)!
            gtk_box_append(boxPointer(outer), labelWidget)
            gtk_box_append(boxPointer(outer), hbox)
            return opaqueFromWidget(outer)
        }

        return opaqueFromWidget(hbox)
    }
}

// MARK: - DatePicker GTK extension

private class DatePickerBox {
    let calendar: UnsafeMutablePointer<GtkWidget>
    let binding: Binding<SwiftOpenUI.DateComponents>?
    let onChange: ((SwiftOpenUI.DateComponents) -> Void)?

    init(calendar: UnsafeMutablePointer<GtkWidget>,
         binding: Binding<SwiftOpenUI.DateComponents>?,
         onChange: ((SwiftOpenUI.DateComponents) -> Void)?) {
        self.calendar = calendar
        self.binding = binding
        self.onChange = onChange
    }
}

extension DatePicker: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4)!
        let boxPtr = boxPointer(box)

        if !title.isEmpty {
            let label = gtk_label_new(title)!
            gtk_widget_set_halign(label, GTK_ALIGN_START)
            gtk_box_append(boxPtr, label)
        }

        let calendar = gtk_calendar_new()!
        gtk_box_append(boxPtr, calendar)

        if let sel = selection {
            let dc = sel.wrappedValue
            gtk_swift_calendar_select_ymd(calendar, gint(dc.year), gint(dc.month), gint(dc.day))
        }

        let callbackBox = Unmanaged.passRetained(DatePickerBox(
            calendar: calendar, binding: selection, onChange: onChange
        )).toOpaque()

        g_signal_connect_data(
            gpointer(calendar),
            "day-selected",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<DatePickerBox>.fromOpaque(userData!).takeUnretainedValue()
                var y: gint = 0, m: gint = 0, d: gint = 0
                gtk_swift_calendar_get_ymd(box.calendar, &y, &m, &d)
                let dc = SwiftOpenUI.DateComponents(year: Int(y), month: Int(m), day: Int(d))
                if let binding = box.binding, dc != binding.wrappedValue {
                    binding.wrappedValue = dc
                }
                box.onChange?(dc)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            callbackBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<DatePickerBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        gtkApplyEnabledState(to: box)
        return opaqueFromWidget(box)
    }
}

// MARK: - GeometryReader GTK extension

/// Context holding the content builder for deferred rendering.
private class GeometryReaderContext {
    let renderContent: (GeometryProxy) -> OpaquePointer
    let box: UnsafeMutablePointer<GtkWidget>
    var renderScheduled = false
    var idleRetryCount = 0
    var lastWidth: Double = 0
    var lastHeight: Double = 0

    init<Content: View>(content: @escaping (GeometryProxy) -> Content,
                        box: UnsafeMutablePointer<GtkWidget>) {
        self.box = box
        // Deferred geometry renders run from GTK map/idle/tick callbacks
        // with no rebuilding host. Capture a stable state-identity namespace
        // now (inside the live render pass) so @State under this reader
        // keeps one cache lineage across geometry re-renders.
        let stateNamespace = gtkClaimStateIdentityNamespace("GeometryReader")
        self.renderContent = { proxy in
            gtkWithForcedStateIdentityNamespace(stateNamespace) {
                gtkRenderView(content(proxy))
            }
        }
    }
}

private func geometryRenderContent(_ context: GeometryReaderContext,
                                    widget: UnsafeMutablePointer<GtkWidget>,
                                    width: Double, height: Double) {
    gtkDebugGeometryLog(
        "render requested=\(Int(width))x\(Int(height)) widget=\(gtk_widget_get_width(widget))x\(gtk_widget_get_height(widget))"
    )
    let proxy = GeometryProxy(size: GeometrySize(width: width, height: height))
    while let child = gtk_widget_get_first_child(widget) {
        gtk_box_remove(boxPointer(widget), child)
    }
    let rendered = context.renderContent(proxy)
    let child = widgetFromOpaque(rendered)
    if gtk_widget_get_hexpand(child) != 0 {
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
    }
    if gtk_widget_get_vexpand(child) != 0 {
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
    }
    if gtk_widget_get_hexpand(child) != 0 || gtk_widget_get_vexpand(child) != 0 {
        gtk_widget_set_size_request(
            child,
            gtk_widget_get_hexpand(child) != 0 ? gtkPixelSize(width) : -1,
            gtk_widget_get_vexpand(child) != 0 ? gtkPixelSize(height) : -1
        )
    }
    gtk_box_append(boxPointer(widget), child)
}

private let geometryMapCallback: @convention(c) (
    gpointer?, gpointer?
) -> Void = { widgetPtr, _ in
    guard let widgetPtr = widgetPtr else { return }
    let widget = UnsafeMutableRawPointer(widgetPtr).assumingMemoryBound(to: GtkWidget.self)
    let gobject = UnsafeMutableRawPointer(widgetPtr).assumingMemoryBound(to: GObject.self)
    guard let contextPtr = g_object_get_data(gobject, "gtk-swift-geometry-context") else { return }
    let context = Unmanaged<GeometryReaderContext>.fromOpaque(contextPtr).takeUnretainedValue()
    guard !context.renderScheduled else { return }

    // Walk ancestors to find one with valid dimensions
    var ancestor = gtk_widget_get_parent(widget)
    while let a = ancestor {
        let aw = Double(gtk_widget_get_width(a))
        let ah = Double(gtk_widget_get_height(a))
        if aw > 1, ah > 1 {
            gtkDebugGeometryLog("map ancestor=\(Int(aw))x\(Int(ah)) self=\(gtk_widget_get_width(widget))x\(gtk_widget_get_height(widget))")
            geometryRenderContent(context, widget: widget, width: aw, height: ah)
            return
        }
        ancestor = gtk_widget_get_parent(a)
    }

    // Defer to idle handler
    context.renderScheduled = true
    context.idleRetryCount = 0
    g_object_ref(gpointer(widgetPtr))
    g_idle_add({ userData -> gboolean in
        guard let userData = userData else { return 0 }
        let widget = UnsafeMutableRawPointer(userData).assumingMemoryBound(to: GtkWidget.self)
        guard gtk_swift_is_widget(widget) != 0 else {
            g_object_unref(userData)
            return 0
        }

        let gobject = UnsafeMutableRawPointer(userData).assumingMemoryBound(to: GObject.self)
        guard let contextPtr = g_object_get_data(gobject, "gtk-swift-geometry-context") else {
            g_object_unref(userData)
            return 0
        }
        let context = Unmanaged<GeometryReaderContext>.fromOpaque(contextPtr).takeUnretainedValue()

        let width = Double(gtk_widget_get_width(widget))
        let height = Double(gtk_widget_get_height(widget))

        if width <= 1 || height <= 1 {
            gtkDebugGeometryLog("idle retry self=\(Int(width))x\(Int(height))")
            context.idleRetryCount += 1
            if context.idleRetryCount <= 10 {
                return 1 // retry
            }
            context.renderScheduled = false
            g_object_unref(userData)
            return 0
        }

        context.renderScheduled = false
        gtkDebugGeometryLog("idle self=\(Int(width))x\(Int(height))")
        geometryRenderContent(context, widget: widget, width: width, height: height)
        g_object_unref(userData)
        return 0
    }, widgetPtr)
}

/// Tick callback: checks if the widget's allocated size changed since the last
/// render and re-renders content if so.  The tick callback fires once per frame
/// (~60 Hz) but only re-renders on actual size changes, so the cost is just two
/// integer reads per frame.  The callback is removed when the widget is unmapped.
private let geometryTickCallback: GtkTickCallback = { widget, _, userData in
    guard let widget = widget else { return 0 }
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let contextPtr = g_object_get_data(gobject, "gtk-swift-geometry-context") else {
        return 0 // G_SOURCE_REMOVE
    }
    let context = Unmanaged<GeometryReaderContext>.fromOpaque(contextPtr).takeUnretainedValue()

    let w = Double(gtk_widget_get_width(widget))
    let h = Double(gtk_widget_get_height(widget))
    if w > 1, h > 1, (w != context.lastWidth || h != context.lastHeight) {
        context.lastWidth = w
        context.lastHeight = h
        gtkDebugGeometryLog("tick self=\(Int(w))x\(Int(h))")
        geometryRenderContent(context, widget: widget, width: w, height: h)
    }
    return 1 // G_SOURCE_CONTINUE
}

extension GeometryReader: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
        gtkMarkVerticalFillIntent(box)

        let context = GeometryReaderContext(content: content, box: box)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        let gobject = UnsafeMutableRawPointer(box).assumingMemoryBound(to: GObject.self)
        g_object_set_data_full(gobject, "gtk-swift-geometry-context", contextPtr,
            { userData in Unmanaged<GeometryReaderContext>.fromOpaque(userData!).release() })

        // Initial render on first display
        g_signal_connect_data(
            gpointer(box), "map",
            unsafeBitCast(geometryMapCallback, to: GCallback.self),
            nil, nil, GConnectFlags(rawValue: 0))

        // Track size changes via tick callback (fires per frame, re-renders
        // only when allocated size actually changes).  The tick callback is
        // automatically paused when the widget is unmapped.
        _ = gtk_widget_add_tick_callback(
            box,
            geometryTickCallback,
            nil, nil
        )

        return opaqueFromWidget(gtkCompressibleProposalClamp(box))
    }
}

// MARK: - Searchable GTK extension

private class SearchSuggestionActionBox {
    let completion: String
    let textBinding: Binding<String>
    let entry: UnsafeMutablePointer<GtkWidget>

    init(completion: String, textBinding: Binding<String>, entry: UnsafeMutablePointer<GtkWidget>) {
        self.completion = completion
        self.textBinding = textBinding
        self.entry = entry
    }
}

private class SearchScopeActionBox {
    let scopeID: String
    let button: UnsafeMutablePointer<GtkWidget>
    let selectScope: (String) -> Void

    init(scopeID: String, button: UnsafeMutablePointer<GtkWidget>, selectScope: @escaping (String) -> Void) {
        self.scopeID = scopeID
        self.button = button
        self.selectScope = selectScope
    }
}

private class SearchBox {
    let entry: UnsafeMutablePointer<GtkWidget>
    let binding: Binding<String>
    let isPresented: Binding<Bool>?

    init(entry: UnsafeMutablePointer<GtkWidget>, binding: Binding<String>, isPresented: Binding<Bool>? = nil) {
        self.entry = entry
        self.binding = binding
        self.isPresented = isPresented
    }
}

private let gtkSearchableFocusDataKey = "gtk-swift-searchable-focus"
private let gtkSearchableTopSurfaceDataKey = "gtk-swift-searchable-top-surface-focus"
private let gtkSearchableDefaultHitHeight = 48.0

private final class GTKSearchRootEventContext {
    let entry: UnsafeMutablePointer<GtkWidget>
    let box: SearchBox
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?
    var loggedRootUnavailable = false

    init(entry: UnsafeMutablePointer<GtkWidget>, box: SearchBox) {
        self.entry = entry
        self.box = box
    }

    func removeController() {
        guard let root, let controller else { return }
        gtk_swift_remove_event_controller(root, controller)
        self.root = nil
        self.controller = nil
    }
}

private func gtkSearchableKeepsChromeVisible(for placement: SearchFieldPlacement) -> Bool {
    switch placement {
    case .navigationBarDrawer(let displayMode):
        return displayMode == .always
    case .automatic, .toolbar, .sidebar:
        return false
    }
}

private func gtkAttachSearchFocusData(to widget: UnsafeMutablePointer<GtkWidget>, box: SearchBox) {
    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    let retained = Unmanaged.passRetained(box).toOpaque()
    g_object_set_data_full(object, gtkSearchableFocusDataKey, retained) { userData in
        guard let userData else { return }
        Unmanaged<SearchBox>.fromOpaque(userData).release()
    }
}

private func gtkAttachSearchTopSurfaceData(to widget: UnsafeMutablePointer<GtkWidget>, box: SearchBox) {
    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    let retained = Unmanaged.passRetained(box).toOpaque()
    g_object_set_data_full(object, gtkSearchableTopSurfaceDataKey, retained) { userData in
        guard let userData else { return }
        Unmanaged<SearchBox>.fromOpaque(userData).release()
    }
}

private func gtkFocusSearchBox(_ box: SearchBox, source: String) -> Bool {
    box.isPresented?.wrappedValue = true
    gtk_widget_set_focusable(box.entry, 1)
    gtk_widget_set_focus_on_click(box.entry, 1)
    let entryGrabbed = gtk_swift_root_grab_focus(box.entry) != 0
    var delegateGrabbed = false
    if let delegate = gtk_editable_get_delegate(OpaquePointer(box.entry)) {
        let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
        gtk_widget_set_focusable(delegateWidget, 1)
        gtk_widget_set_focus_on_click(delegateWidget, 1)
        delegateGrabbed = gtk_swift_root_grab_focus(delegateWidget) != 0
    }
    gtkDebugLog(
        "searchable focus \(source) entryGrabbed=\(entryGrabbed ? 1 : 0) "
        + "delegateGrabbed=\(delegateGrabbed ? 1 : 0)"
    )
    return entryGrabbed || delegateGrabbed
}

private func gtkSearchFocusBoxAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> SearchBox? {
    var result: SearchBox?

    func walk(_ widget: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard result == nil, depth < 160 else { return }
        guard gtk_widget_get_visible(widget) != 0 else { return }
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if let raw = g_object_get_data(object, gtkSearchableTopSurfaceDataKey),
           let box = Optional(Unmanaged<SearchBox>.fromOpaque(raw).takeUnretainedValue()) {
            if gtkSearchEntryAllocationContainsRootPoint(box.entry, root: root, x: x, y: y)
                || gtkSearchEntryEstimatedChromeContainsRootPoint(box.entry, root: root, x: x, y: y) {
                result = box
                return
            }
            if let frame = gtkWidgetVisualFrameInRoot(widget, root: root),
               x >= frame.x, x < frame.x + frame.width,
               y >= frame.y, y < frame.y + gtkSearchableDefaultHitHeight {
                result = box
                return
            }
        }
        if let raw = g_object_get_data(object, gtkSearchableFocusDataKey),
           let box = Optional(Unmanaged<SearchBox>.fromOpaque(raw).takeUnretainedValue()) {
            if gtkSearchEntryAllocationContainsRootPoint(box.entry, root: root, x: x, y: y)
                || gtkSearchEntryEstimatedChromeContainsRootPoint(box.entry, root: root, x: x, y: y)
                || gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y) {
                result = box
                return
            }
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(root, depth: 0)
    return result
}

private func gtkSearchEntryEstimatedChromeContainsRootPoint(
    _ entry: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    guard gtk_widget_get_mapped(entry) != 0 else { return false }
    guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: x, y: y) else {
        return false
    }
    guard let frame = gtkWidgetVisualFrameInRoot(entry, root: root) else { return false }
    let rootWidth = Double(gtk_widget_get_width(root))
    guard rootWidth > 0 else { return false }
    return x >= 0
        && x < rootWidth
        && y >= frame.y
        && y < frame.y + gtkSearchableDefaultHitHeight
}

private func gtkSearchEntryAllocationContainsRootPoint(
    _ entry: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    let width = Double(gtk_widget_get_width(entry))
    let height = Double(gtk_widget_get_height(entry))
    guard width > 0, height > 0 else { return false }
    var entryX = 0.0
    var entryY = 0.0
    guard gtk_swift_widget_compute_point(entry, root, 0, 0, &entryX, &entryY) != 0 else {
        return false
    }
    return x >= entryX
        && x < entryX + width
        && y >= entryY
        && y < entryY + max(height, gtkSearchableDefaultHitHeight)
}

private func gtkDebugSearchFocusCandidates(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    var total = 0
    var hits = 0

    func walk(_ widget: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard depth < 160 else { return }
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        let hasEntryData = g_object_get_data(object, gtkSearchableFocusDataKey) != nil
        let hasTopSurfaceData = g_object_get_data(object, gtkSearchableTopSurfaceDataKey) != nil
        if hasEntryData || hasTopSurfaceData {
            let raw = g_object_get_data(object, gtkSearchableTopSurfaceDataKey)
                ?? g_object_get_data(object, gtkSearchableFocusDataKey)
            let allocationHit = raw.map {
                let box = Unmanaged<SearchBox>.fromOpaque($0).takeUnretainedValue()
                return gtkSearchEntryAllocationContainsRootPoint(box.entry, root: root, x: x, y: y)
            } ?? false
            let estimatedChromeHit = raw.map {
                let box = Unmanaged<SearchBox>.fromOpaque($0).takeUnretainedValue()
                return gtkSearchEntryEstimatedChromeContainsRootPoint(box.entry, root: root, x: x, y: y)
            } ?? false
            let containsEntry = gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y)
            var containsTopSurface = false
            if hasTopSurfaceData,
               let frame = gtkWidgetVisualFrameInRoot(widget, root: root),
               x >= frame.x, x < frame.x + frame.width,
               y >= frame.y, y < frame.y + gtkSearchableDefaultHitHeight {
                containsTopSurface = true
            }
            let contains = allocationHit || estimatedChromeHit || containsEntry || containsTopSurface
            total += 1
            if contains { hits += 1 }
            gtkDebugLog(
                "\(source) search-candidate[\(total - 1)] hit=\(contains ? 1 : 0) "
                + "surface=\(hasTopSurfaceData ? 1 : 0) "
                + "allocation=\(allocationHit ? 1 : 0) "
                + "estimated=\(estimatedChromeHit ? 1 : 0) "
                + gtkDebugVisualFrameDescription(widget, root: root)
            )
        }

        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(root, depth: 0)
    gtkDebugLog("\(source) search-candidates total=\(total) hits=\(hits) root@\(Int(x)),\(Int(y))")
}

private func gtkFocusSearchEntryAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) -> Bool {
    guard let box = gtkSearchFocusBoxAtRootPoint(root: root, x: x, y: y) else {
        gtkDebugSearchFocusCandidates(root: root, x: x, y: y, source: source)
        return false
    }
    return gtkFocusSearchBox(box, source: source)
}

private func gtkInstallSearchRootEventFallback(_ context: GTKSearchRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.entry) else {
        if !context.loggedRootUnavailable {
            context.loggedRootUnavailable = true
            gtkDebugLog("searchable root fallback root unavailable")
        }
        return
    }

    let controller = gtk_swift_legacy_capture_controller()!
    context.root = root
    context.controller = controller
    gtkDebugLog("searchable root fallback installed")
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return 0 }
            var rootX: Double = 0
            var rootY: Double = 0
            guard gtk_swift_event_get_position(event, &rootX, &rootY) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }
            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "search-root@\(Int(rootX)),\(Int(rootY))"
            ) {
                return 1
            }
            return 0
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

private func gtkSearchRootInstallTickCallback(
    _ widget: UnsafeMutablePointer<GtkWidget>?,
    _ frameClock: OpaquePointer?,
    _ userData: gpointer?
) -> gboolean {
    guard let userData else { return 0 }
    let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeUnretainedValue()
    gtkInstallSearchRootEventFallback(context)
    return context.controller == nil ? 1 : 0
}

private func gtkInstallSearchFocusGesture(
    on widget: UnsafeMutablePointer<GtkWidget>,
    entry: UnsafeMutablePointer<GtkWidget>,
    binding: Binding<String>,
    isPresented: Binding<Bool>?
) {
    let focusGesture = gtk_gesture_click_new()!
    let focusBox = Unmanaged.passRetained(
        SearchBox(entry: entry, binding: binding, isPresented: isPresented)
    ).toOpaque()
    gtk_swift_gesture_single_set_button(focusGesture, 1)
    g_signal_connect_data(
        gpointer(focusGesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, _: gdouble, _: gdouble, userData: gpointer?) in
            guard let userData else { return }
            let box = Unmanaged<SearchBox>.fromOpaque(userData).takeUnretainedValue()
            _ = gtkFocusSearchBox(box, source: "gesture")
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        focusBox,
        { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
            Unmanaged<SearchBox>.fromOpaque(userData!).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(widget, focusGesture)
}

extension SearchableView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .searchable, typeName: "SearchableView",
            props: .searchable(GTK4SearchableDescriptor(
                text: text.wrappedValue,
                prompt: prompt,
                placement: placement,
                isPresented: isPresented?.wrappedValue,
                tokens: tokens,
                tokenMode: tokenMode,
                suggestions: suggestions,
                suggestionMode: suggestionMode,
                scopes: scopes,
                scopeMode: scopeMode,
                selectedScopeID: selectedScopeID)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let boxPtr = boxPointer(box)
        gtk_widget_set_can_target(box, 1)
        let binding = text
        let presentedBinding = isPresented

        let entry = gtk_swift_search_entry_new()!
        gtkDebugLog("searchable create placement=\(placement) prompt='\(prompt)' text='\(binding.wrappedValue)'")
        gtk_widget_set_focusable(entry, 1)
        gtk_widget_set_focus_on_click(entry, 1)
        let searchFocusBox = SearchBox(entry: entry, binding: binding, isPresented: presentedBinding)
        gtkAttachSearchTopSurfaceData(to: box, box: searchFocusBox)
        gtkAttachSearchFocusData(to: entry, box: searchFocusBox)
        let entryContainer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_can_target(entryContainer, 1)
        gtk_widget_set_hexpand(entryContainer, 1)
        gtk_widget_set_halign(entryContainer, GTK_ALIGN_FILL)
        gtk_widget_set_valign(entryContainer, GTK_ALIGN_START)
        gtkAttachSearchFocusData(to: entryContainer, box: searchFocusBox)
        if let delegate = gtk_editable_get_delegate(OpaquePointer(entry)) {
            let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
            gtk_widget_set_focusable(delegateWidget, 1)
            gtk_widget_set_focus_on_click(delegateWidget, 1)
            gtkAttachSearchFocusData(to: delegateWidget, box: searchFocusBox)
            gtkInstallSearchFocusGesture(
                on: delegateWidget,
                entry: entry,
                binding: binding,
                isPresented: presentedBinding
            )
        }
        gtkInstallSearchFocusGesture(on: entry, entry: entry, binding: binding, isPresented: presentedBinding)
        gtkInstallSearchFocusGesture(on: box, entry: entry, binding: binding, isPresented: presentedBinding)
        let rootContextObject = GTKSearchRootEventContext(entry: entry, box: searchFocusBox)
        let rootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
        g_signal_connect_data(
            gpointer(entry),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkInstallSearchRootEventFallback(context)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(entry),
            "unmap",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        let tickRootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
        _ = gtk_widget_add_tick_callback(
            entry,
            gtkSearchRootInstallTickCallback,
            tickRootEventContext,
            { userData in
                guard let userData else { return }
                Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).release()
            }
        )
        g_signal_connect_data(
            gpointer(entry),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeRetainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        if !prompt.isEmpty {
            g_object_set_property_string(entry, "placeholder-text", prompt)
        }
        gtk_box_append(boxPointer(entryContainer), entry)
        gtk_box_append(boxPtr, entryContainer)

        if !text.wrappedValue.isEmpty {
            gtk_swift_editable_set_text(entry, text.wrappedValue)
        }

        // Honor isPresented: hide entire search UI surface when false
        let isDismissed = isPresented.map {
            !$0.wrappedValue && !gtkSearchableKeepsChromeVisible(for: placement)
        } ?? false
        if isDismissed {
            gtk_widget_set_visible(entry, 0)
            gtk_widget_set_visible(entryContainer, 0)
        }

        let callbackBox = Unmanaged.passRetained(
            SearchBox(entry: entry, binding: binding, isPresented: presentedBinding)
        ).toOpaque()

        g_signal_connect_data(
            gpointer(entry),
            "search-changed",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<SearchBox>.fromOpaque(userData!).takeUnretainedValue()
                let cStr = gtk_swift_editable_get_text(box.entry)
                let newValue = cStr.map { String(cString: $0) } ?? ""
                if newValue != box.binding.wrappedValue {
                    gtkDebugLog("searchable search-changed text='\(newValue)'")
                    gtkScheduleTextBindingUpdate(box.binding, value: newValue)
                }
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            callbackBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<SearchBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        let changedBox = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(entry),
            "changed",
            unsafeBitCast({ (editable: gpointer?, userData: gpointer?) in
                let box = Unmanaged<StringClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let cStr = gtk_editable_get_text(OpaquePointer(editable))!
                let newText = String(cString: cStr)
                gtkDebugLog("searchable changed text='\(newText)'")
                box.closure(newText)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            changedBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<StringClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        // Render token labels between search entry and content
        if !tokens.isEmpty {
            let tokenRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4)!
            gtk_widget_set_margin_start(tokenRow, 4)
            gtk_widget_set_margin_end(tokenRow, 4)
            gtk_widget_set_margin_top(tokenRow, 2)
            gtk_widget_set_margin_bottom(tokenRow, 2)
            for token in tokens {
                let label = gtk_label_new(token.label)!
                gtk_widget_add_css_class(label, "dim-label")
                gtk_box_append(boxPointer(tokenRow), label)
            }
            if isDismissed { gtk_widget_set_visible(tokenRow, 0) }
            gtk_box_append(boxPtr, tokenRow)
        }

        // Render suggestion rows as clickable buttons
        if !suggestions.isEmpty {
            let suggestionBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)!
            gtk_widget_set_margin_start(suggestionBox, 4)
            gtk_widget_set_margin_end(suggestionBox, 4)
            for suggestion in suggestions {
                let btn = gtk_button_new_with_label(suggestion.label)!
                gtk_widget_set_halign(btn, GTK_ALIGN_START)
                let completionText = suggestion.completion ?? suggestion.label
                let textBinding = text
                let searchEntry = entry
                let actionBox = Unmanaged.passRetained(
                    SearchSuggestionActionBox(completion: completionText, textBinding: textBinding, entry: searchEntry)
                ).toOpaque()
                g_signal_connect_data(
                    gpointer(btn),
                    "clicked",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                        let box = Unmanaged<SearchSuggestionActionBox>.fromOpaque(userData!).takeUnretainedValue()
                        box.textBinding.wrappedValue = box.completion
                        gtk_swift_editable_set_text(box.entry, box.completion)
                    } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                    actionBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<SearchSuggestionActionBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
                gtk_box_append(boxPointer(suggestionBox), btn)
            }
            if isDismissed { gtk_widget_set_visible(suggestionBox, 0) }
            gtk_box_append(boxPtr, suggestionBox)
        }

        // Render scope row as horizontal toggle buttons
        if !scopes.isEmpty {
            let scopeRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4)!
            gtk_widget_set_margin_start(scopeRow, 4)
            gtk_widget_set_margin_end(scopeRow, 4)
            gtk_widget_set_margin_top(scopeRow, 2)
            gtk_widget_set_margin_bottom(scopeRow, 2)
            let scopeSelector: (String) -> Void = { [self] id in self.selectScope(id: id) }
            var firstScopeBtn: UnsafeMutablePointer<GtkWidget>? = nil
            for scope in scopes {
                let btn = gtk_toggle_button_new_with_label(scope.label)!
                // Group all scope buttons so only one can be active
                if let group = firstScopeBtn {
                    gtk_swift_toggle_button_set_group(btn, group)
                } else {
                    firstScopeBtn = btn
                }
                if selectedScopeID == scope.id {
                    gtk_swift_toggle_button_set_active(btn, 1)
                }
                let actionBox = Unmanaged.passRetained(
                    SearchScopeActionBox(scopeID: scope.id, button: btn, selectScope: scopeSelector)
                ).toOpaque()
                g_signal_connect_data(
                    gpointer(btn),
                    "toggled",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                        let box = Unmanaged<SearchScopeActionBox>.fromOpaque(userData!).takeUnretainedValue()
                        // Only write back when toggling on, not off
                        guard gtk_swift_toggle_button_get_active(box.button) != 0 else { return }
                        box.selectScope(box.scopeID)
                    } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                    actionBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<SearchScopeActionBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
                gtk_box_append(boxPointer(scopeRow), btn)
            }
            if isDismissed { gtk_widget_set_visible(scopeRow, 0) }
            gtk_box_append(boxPtr, scopeRow)
        }

        let contentWidget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_vexpand(contentWidget, 1)
        gtk_swift_search_entry_set_key_capture_widget(entry, box)
        gtk_box_append(boxPtr, contentWidget)

        return opaqueFromWidget(box)
    }
}

// MARK: - Menu GTK extension

/// Holds menu action closures for lifetime management.
private class MenuActionBox {
    var actions: [ClosureBox] = []
}

private final class GTKMenuOverlayModel {
    let elements: [GTKBoundMenuElement]

    init(elements: [GTKBoundMenuElement]) {
        self.elements = elements
    }
}

private enum GTKBoundMenuElement {
    case item(label: String, action: () -> Void)
    case divider
    case submenu(label: String, children: [GTKBoundMenuElement])
}

private final class GTKActiveMenuOverlayState {
    let root: UnsafeMutablePointer<GtkWidget>
    let controller: gpointer
    let elements: [GTKBoundMenuElement]
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(
        root: UnsafeMutablePointer<GtkWidget>,
        controller: gpointer,
        elements: [GTKBoundMenuElement],
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.root = root
        self.controller = controller
        self.elements = elements
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    func removeController() {
        gtk_swift_remove_event_controller(root, controller)
    }
}

private let gtkSwiftMenuPopupGestureInstalledKey = "gtk-swift-menu-popup-gesture-installed"
private let gtkSwiftMenuOverlayModelKey = "gtk-swift-menu-overlay-model"
private let gtkMenuOverlayPreferredWidth: gint = 156
private let gtkMenuOverlayRowHeight = 48.0
private let gtkMenuOverlayDividerHeight = 10.0
private var gtkActiveMenuOverlayLayer: UnsafeMutablePointer<GtkWidget>?
private var gtkActiveMenuOverlayState: GTKActiveMenuOverlayState?

private func gtkMenuPresentationMode() -> String {
    (ProcessInfo.processInfo.environment["QUILLUI_GTK_MENU_PRESENTATION"]
        ?? "root-overlay")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func gtkShouldUseRootMenuOverlay() -> Bool {
    let mode = gtkMenuPresentationMode()
    return mode.isEmpty || mode == "root" || mode == "root-overlay" || mode == "overlay"
}

private final class GTKMenuPopupEventContext {
    let menuButton: UnsafeMutablePointer<GtkWidget>

    init(menuButton: UnsafeMutablePointer<GtkWidget>) {
        self.menuButton = menuButton
    }
}

private func gtkDismissActiveMenuOverlay() {
    let activeLayer = gtkActiveMenuOverlayLayer
    let activeState = gtkActiveMenuOverlayState
    gtkActiveMenuOverlayLayer = nil
    gtkActiveMenuOverlayState = nil
    if let activeState {
        activeState.removeController()
    }
    if let layer = activeLayer, gtk_swift_is_widget(layer) != 0 {
        if gtk_widget_get_parent(layer) != nil {
            gtk_widget_unparent(layer)
        }
    }
    gtkDebugLog("menu overlay dismissed")
}

private func gtkBindMenuElementsToCurrentEnvironment(
    _ elements: [MenuElement]
) -> [GTKBoundMenuElement] {
    elements.map { element in
        switch element {
        case .item(let label, let action):
            return .item(label: label, action: bindActionToCurrentEnvironment(action))
        case .divider:
            return .divider
        case .submenu(let label, let children):
            return .submenu(
                label: label,
                children: gtkBindMenuElementsToCurrentEnvironment(children)
            )
        }
    }
}

private func gtkMenuOverlayContentHeight(
    elements: [GTKBoundMenuElement]
) -> Double {
    elements.reduce(0) { height, element in
        switch element {
        case .item, .submenu:
            return height + gtkMenuOverlayRowHeight
        case .divider:
            return height + gtkMenuOverlayDividerHeight
        }
    }
}

private func gtkMenuOverlayAction(
    in elements: [GTKBoundMenuElement],
    at offsetY: Double
) -> (label: String, action: () -> Void)? {
    var cursor = 0.0
    for element in elements {
        switch element {
        case .item(let label, let action):
            let next = cursor + gtkMenuOverlayRowHeight
            if offsetY >= cursor && offsetY < next {
                return (label, action)
            }
            cursor = next
        case .submenu:
            cursor += gtkMenuOverlayRowHeight
        case .divider:
            cursor += gtkMenuOverlayDividerHeight
        }
    }
    return nil
}

private func gtkHandleActiveMenuOverlayClick(x: Double, y: Double) -> gboolean {
    guard let state = gtkActiveMenuOverlayState else { return 0 }
    guard x >= state.x, x <= state.x + state.width,
          y >= state.y, y <= state.y + state.height else {
        gtkDebugLog("menu overlay action miss root@\(Int(x)),\(Int(y))")
        gtkDismissActiveMenuOverlay()
        return 1
    }
    guard let item = gtkMenuOverlayAction(in: state.elements, at: y - state.y) else {
        gtkDebugLog("menu overlay action skipped root@\(Int(x)),\(Int(y))")
        gtkDismissActiveMenuOverlay()
        return 1
    }
    gtkDebugLog("menu overlay action hit root@\(Int(x)),\(Int(y)) label='\(item.label)'")
    gtkDismissActiveMenuOverlay()
    item.action()
    return 1
}

private func gtkHandleActiveMenuOverlayClick(
    from widget: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> gboolean {
    guard gtkActiveMenuOverlayState != nil else { return 0 }
    guard let root = gtk_swift_widget_root_widget(widget) else { return 0 }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(widget, root, x, y, &rootX, &rootY) != 0 else {
        return 0
    }
    return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
}

private func gtkInstallActiveMenuOverlayController(
    root: UnsafeMutablePointer<GtkWidget>,
    elements: [GTKBoundMenuElement],
    x: Double,
    y: Double,
    width: Double,
    height: Double
) {
    let controller = gtk_swift_legacy_capture_controller()!
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, _: gpointer?) -> gboolean in
            guard let event else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            var x: Double = 0
            var y: Double = 0
            guard gtk_swift_event_get_position(event, &x, &y) != 0 else { return 0 }
            return gtkHandleActiveMenuOverlayClick(x: x, y: y)
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        nil,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtkActiveMenuOverlayState = GTKActiveMenuOverlayState(
        root: root,
        controller: controller,
        elements: elements,
        x: x,
        y: y,
        width: width,
        height: height
    )
    gtk_swift_add_event_controller(root, controller)
}

private func gtkMenuOverlayRoot(
    for anchor: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>
) -> OpaquePointer? {
    if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(anchor)) {
        return rootOverlay
    }
    var ancestor = gtk_widget_get_parent(anchor)
    while let current = ancestor {
        if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(current)) {
            return rootOverlay
        }
        ancestor = gtk_widget_get_parent(current)
    }
    if let rootOverlay = gtkRootPresentationOverlay(for: gpointer(root)) {
        return rootOverlay
    }
    if let gtkRoot = gtk_widget_get_root(anchor),
       let rootOverlay = gtkRootPresentationOverlay(for: gpointer(gtkRoot)) {
        return rootOverlay
    }
    return gtkFallbackRootPresentationOverlay()
}

private func gtkClampMenuOverlayCoordinate(
    _ value: Double,
    preferredSize: gint,
    hostSize: gint
) -> Double {
    let margin = 8.0
    guard hostSize > preferredSize + gint(margin * 2) else {
        return max(margin, value)
    }
    let upper = Double(hostSize - preferredSize) - margin
    return min(max(margin, value), upper)
}

private func gtkAttachMenuOverlayLayer(
    _ layer: UnsafeMutablePointer<GtkWidget>,
    to rootOverlay: OpaquePointer
) {
    let overlayWidget = UnsafeMutableRawPointer(rootOverlay).assumingMemoryBound(to: GtkWidget.self)
    let previousTop = gtk_widget_get_last_child(overlayWidget)
    gtk_overlay_add_overlay(rootOverlay, layer)
    if let previousTop, previousTop != layer {
        gtk_widget_insert_after(layer, overlayWidget, previousTop)
    }
}

private func gtkOpenMenuOverlay(
    menuButton: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    source: String,
    anchorFrame: (x: Double, y: Double, width: Double, height: Double)? = nil
) -> Bool {
    guard gtkShouldUseRootMenuOverlay() else { return false }

    let gobject = UnsafeMutableRawPointer(menuButton).assumingMemoryBound(to: GObject.self)
    guard let modelData = g_object_get_data(gobject, gtkSwiftMenuOverlayModelKey) else {
        return false
    }
    let model = Unmanaged<GTKMenuOverlayModel>.fromOpaque(modelData).takeUnretainedValue()
    guard !model.elements.isEmpty else { return false }
    guard let rootOverlay = gtkMenuOverlayRoot(for: menuButton, root: root) else { return false }
    let overlayWidget = UnsafeMutableRawPointer(rootOverlay).assumingMemoryBound(to: GtkWidget.self)

    let frame = anchorFrame
        ?? gtkWidgetVisualFrameInRoot(menuButton, root: root)
        ?? (x: 0, y: 0, width: Double(gtk_widget_get_width(menuButton)), height: Double(gtk_widget_get_height(menuButton)))
    let hostWidth = max(gtk_widget_get_width(overlayWidget), gtk_widget_get_width(root))
    let hostHeight = max(gtk_widget_get_height(overlayWidget), gtk_widget_get_height(root))
    let panelX = gtkClampMenuOverlayCoordinate(
        frame.x,
        preferredSize: gtkMenuOverlayPreferredWidth,
        hostSize: hostWidth
    )
    let panelY = gtkClampMenuOverlayCoordinate(
        frame.y + frame.height + 4,
        preferredSize: 96,
        hostSize: hostHeight
    )
    let panelHeight = max(gtkMenuOverlayRowHeight, gtkMenuOverlayContentHeight(elements: model.elements))

    gtkDismissActiveMenuOverlay()

    let panel = gtkCreateMenuOverlayPanel(elements: model.elements)
    gtk_widget_set_margin_start(panel, gint(panelX))
    gtk_widget_set_margin_top(panel, gint(panelY))
    gtk_widget_set_size_request(panel, gtkMenuOverlayPreferredWidth, gint(panelHeight))
    gtk_widget_set_visible(panel, 1)
    let layer = gtkCreateMenuOverlayLayer(panel: panel)
    gtkStoreRootPresentationOverlay(rootOverlay, on: layer)
    gtkStoreRootPresentationOverlay(rootOverlay, on: panel)
    gtkAttachMenuOverlayLayer(layer, to: rootOverlay)
    gtk_widget_queue_draw(overlayWidget)
    gtkActiveMenuOverlayLayer = layer
    gtkInstallActiveMenuOverlayController(
        root: root,
        elements: model.elements,
        x: panelX,
        y: panelY,
        width: Double(gtkMenuOverlayPreferredWidth),
        height: panelHeight
    )
    gtkDebugLog(
        "menu overlay opened \(source) host=\(hostWidth)x\(hostHeight) frame=\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height)) panel=\(Int(panelX)),\(Int(panelY)) \(Int(panelHeight))h"
    )
    return true
}

private func gtkOpenMenuOverlayFromButton(
    _ menuButton: UnsafeMutablePointer<GtkWidget>,
    source: String
) -> Bool {
    guard let root = gtk_swift_widget_root_widget(menuButton) else { return false }
    return gtkOpenMenuOverlay(menuButton: menuButton, root: root, source: source)
}

private func gtkOpenMenuButton(
    _ menuButton: UnsafeMutablePointer<GtkWidget>,
    source: String
) -> Bool {
    if gtkOpenMenuOverlayFromButton(menuButton, source: source) {
        return true
    }
    let visible = gtk_swift_menu_button_popup_if_closed(menuButton) != 0
    gtkDebugLog("menu popup \(source) visible=\(visible)")
    return visible
}

private func gtkOpenMenuButton(
    _ menuButton: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    anchorX: Double,
    anchorY: Double,
    source: String
) -> Bool {
    if gtkOpenMenuOverlay(
        menuButton: menuButton,
        root: root,
        source: source,
        anchorFrame: (x: anchorX - 32, y: anchorY - 16, width: 64, height: 36)
    ) {
        return true
    }
    return gtkOpenMenuButton(menuButton, source: source)
}

private func gtkOpenVisualMenuButtonAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) -> Bool {
    let menuButton = gtkWidgetTreeFindVisualMenuButtonAtRootPoint(root, root: root, x: x, y: y)
        ?? gtk_swift_root_point_pick_menu_button(root, x, y)
    guard let menuButton else { return false }
    return gtkOpenMenuButton(menuButton, source: source)
}

private func gtkInstallMenuPopupGesture(
    on widget: UnsafeMutablePointer<GtkWidget>,
    menuButton: UnsafeMutablePointer<GtkWidget>
) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard g_object_get_data(gobject, gtkSwiftMenuPopupGestureInstalledKey) == nil else { return }
    g_object_set_data(gobject, gtkSwiftMenuPopupGestureInstalledKey, gpointer(bitPattern: 1))

    let popupGesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(popupGesture, 1)
    let popupBox = Unmanaged.passRetained(ClosureBox { [menuButton] in
        _ = gtkOpenMenuButton(menuButton, source: "menu popup gesture")
    }).toOpaque()
    g_signal_connect_data(
        gpointer(popupGesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, _: gdouble, _: gdouble, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        popupBox,
        { data, _ in
            if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(widget, popupGesture)

    let legacyController = gtk_swift_legacy_capture_controller()!
    let legacyContext = Unmanaged.passRetained(GTKMenuPopupEventContext(menuButton: menuButton)).toOpaque()
    g_signal_connect_data(
        legacyController,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKMenuPopupEventContext>.fromOpaque(userData).takeUnretainedValue()
            var x: Double = 0
            var y: Double = 0
            let source: String
            if gtk_swift_event_get_position(event, &x, &y) != 0 {
                source = "menu legacy@\(Int(x)),\(Int(y))"
            } else {
                source = "menu legacy"
            }
            return gtkOpenMenuButton(context.menuButton, source: source) ? 1 : 0
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        legacyContext,
        { data, _ in
            if let data { Unmanaged<GTKMenuPopupEventContext>.fromOpaque(data).release() }
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(widget, legacyController)
}

private func gtkInstallMenuPopupGestures(
    under widget: UnsafeMutablePointer<GtkWidget>,
    menuButton: UnsafeMutablePointer<GtkWidget>
) {
    gtkInstallMenuPopupGesture(on: widget, menuButton: menuButton)
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        gtkInstallMenuPopupGestures(under: c, menuButton: menuButton)
        child = gtk_widget_get_next_sibling(c)
    }
}

private func gtkApplyPlainMenuButtonChrome(to button: UnsafeMutablePointer<GtkWidget>) {
    let className = "gtk-swift-plain-menu-button"
    let css = """
    .\(className),
    menubutton.\(className),
    menubutton.\(className) > button,
    menubutton.\(className) button {
        background: transparent;
        background-color: transparent;
        background-image: none;
        border: none;
        border-radius: 0;
        box-shadow: none;
        outline: none;
        padding: 0;
        min-height: 0;
        min-width: 0;
        -gtk-icon-shadow: none;
        text-shadow: none;
    }
    """

    let provider = gtk_css_provider_new()!
    gtk_css_provider_load_from_string(provider, css)
    if let display = gtk_widget_get_display(button) {
        gtk_swift_add_css_provider_to_display(
            display,
            provider,
            UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
        )
    }
    gtk_widget_add_css_class(button, "flat")
    gtk_widget_add_css_class(button, className)
    g_object_unref(gpointer(provider))
}

extension Menu: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let button = gtk_menu_button_new()!
        gtkDebugLog("menu render title='\(title)' elements=\(elements.count) labels=[\(gtkDebugMenuLabels(elements).joined(separator: ", "))]")
        let buttonStyleType = getCurrentEnvironment().buttonStyle
        if let labelView {
            let environment = getCurrentEnvironment()
            gtkDebugLog(
                "menu label environment customButtonStyle=\(environment.customButtonStyle != nil) buttonStyle=\(environment.buttonStyle)"
            )
            let childWidget: UnsafeMutablePointer<GtkWidget>
            if let customButtonStyle = environment.customButtonStyle {
                var renderEnvironment = environment
                renderEnvironment.customButtonStyle = nil
                renderEnvironment.buttonStyle = .plain
                let previousEnvironment = getCurrentEnvironment()
                setCurrentEnvironment(renderEnvironment)
                let styledBody = customButtonStyle.makeBody(
                    configuration: .init(label: labelView, isPressed: false)
                )
                childWidget = widgetFromOpaque(gtkRenderView(styledBody))
                setCurrentEnvironment(previousEnvironment)
                applyCSSToWidget(button, properties: """
                    background: transparent;
                    background-color: transparent;
                    background-image: none;
                    border: none;
                    border-radius: 0;
                    box-shadow: none;
                    outline: none;
                    padding: 0;
                    min-height: 0;
                    min-width: 0;
                    text-shadow: none;
                    """)
            } else {
                childWidget = widgetFromOpaque(gtkRenderView(labelView))
            }
            gtkDisableButtonChildTargeting(childWidget)
            gtk_swift_menu_button_set_child(button, childWidget)
            gtk_swift_menu_button_set_always_show_arrow(button, 0)
            gtkApplyPlainMenuButtonChrome(to: button)
            gtkMarkMenuOwner(under: childWidget, menuButton: button)
        } else {
            gtk_swift_menu_button_set_label(button, title)
            if buttonStyleType == .plain {
                gtk_swift_menu_button_set_always_show_arrow(button, 0)
                gtkApplyPlainMenuButtonChrome(to: button)
            }
        }

        let actionBox = MenuActionBox()
        let overlayModel = GTKMenuOverlayModel(
            elements: gtkBindMenuElementsToCurrentEnvironment(elements)
        )

        let popover = gtk_popover_new()!
        let popoverContent = gtkBuildMenuPopoverContent(
            elements: elements,
            popover: popover,
            actionBox: actionBox
        )
        gtk_swift_popover_set_child(popover, popoverContent)
        gtk_swift_menu_button_set_popover(button, popover)

        gtkMarkMenuOwner(under: button, menuButton: button)
        gtkInstallMenuPopupGestures(under: button, menuButton: button)
        let installBox = Unmanaged.passRetained(ClosureBox { [button] in
            gtkMarkMenuOwner(under: button, menuButton: button)
            gtkInstallMenuPopupGestures(under: button, menuButton: button)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(button),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            installBox,
            { data, _ in
                if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
            },
            GConnectFlags(rawValue: 0)
        )

        // Attach actionBox to button for lifetime management
        let retained = Unmanaged.passRetained(actionBox).toOpaque()
        let gobject = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GObject.self)
        g_object_set_data_full(gobject, "gtk-swift-menu-actions", retained,
            { userData in Unmanaged<MenuActionBox>.fromOpaque(userData!).release() })
        let retainedOverlayModel = Unmanaged.passRetained(overlayModel).toOpaque()
        g_object_set_data_full(gobject, gtkSwiftMenuOverlayModelKey, retainedOverlayModel,
            { userData in Unmanaged<GTKMenuOverlayModel>.fromOpaque(userData!).release() })

        return opaqueFromWidget(button)
    }
}

private func gtkBuildMenuPopoverContent(
    elements: [MenuElement],
    popover: UnsafeMutablePointer<GtkWidget>,
    actionBox: MenuActionBox
) -> UnsafeMutablePointer<GtkWidget> {
    let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)!
    gtk_widget_set_margin_top(box, 6)
    gtk_widget_set_margin_bottom(box, 6)
    gtk_widget_set_margin_start(box, 6)
    gtk_widget_set_margin_end(box, 6)

    for element in elements {
        gtkAppendMenuPopoverElement(element, to: box, popover: popover, actionBox: actionBox)
    }

    return box
}

private func gtkCreateMenuOverlayPanel(
    elements: [GTKBoundMenuElement]
) -> UnsafeMutablePointer<GtkWidget> {
    let panel = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2)!
    gtk_widget_set_size_request(panel, gtkMenuOverlayPreferredWidth, -1)
    gtk_widget_set_halign(panel, GTK_ALIGN_START)
    gtk_widget_set_valign(panel, GTK_ALIGN_START)
    gtk_widget_set_can_target(panel, 1)
    gtk_widget_set_margin_top(panel, 0)
    gtk_widget_set_margin_bottom(panel, 0)
    gtk_widget_set_margin_start(panel, 0)
    gtk_widget_set_margin_end(panel, 0)
    applyCSSToWidget(panel, properties: """
        background: #ffffff;
        border: 1px solid rgba(0,0,0,0.16);
        border-radius: 8px;
        box-shadow: 0 12px 32px rgba(0,0,0,0.22);
        padding: 6px;
        """)

    for element in elements {
        gtkAppendMenuOverlayElement(element, to: panel)
    }

    return panel
}

private func gtkCreateMenuOverlayLayer(
    panel: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let layer = gtk_overlay_new()!
    gtk_widget_set_hexpand(layer, 1)
    gtk_widget_set_vexpand(layer, 1)
    gtk_widget_set_halign(layer, GTK_ALIGN_FILL)
    gtk_widget_set_valign(layer, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(layer, 0)

    let backing = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    gtk_widget_set_hexpand(backing, 1)
    gtk_widget_set_vexpand(backing, 1)
    gtk_widget_set_halign(backing, GTK_ALIGN_FILL)
    gtk_widget_set_valign(backing, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(backing, 0)
    applyCSSToWidget(backing, properties: "background: transparent;")

    gtk_overlay_set_child(OpaquePointer(layer), backing)
    gtk_overlay_add_overlay(OpaquePointer(layer), panel)
    gtk_widget_set_visible(backing, 1)
    gtk_widget_set_visible(panel, 1)
    gtk_widget_set_visible(layer, 1)
    return layer
}

private func gtkAppendMenuOverlayElement(
    _ element: GTKBoundMenuElement,
    to box: UnsafeMutablePointer<GtkWidget>
) {
    switch element {
    case .item(let label, let action):
        let button = gtk_button_new()!
        let labelWidget = gtk_label_new(label)!
        gtk_swift_label_set_xalign(labelWidget, 0)
        gtk_widget_set_hexpand(labelWidget, 1)
        gtk_button_set_child(
            UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self),
            labelWidget
        )
        gtk_widget_set_hexpand(button, 1)
        gtk_widget_set_halign(button, GTK_ALIGN_FILL)
        gtk_widget_set_size_request(button, gtkMenuOverlayPreferredWidth - 12, -1)
        gtk_widget_set_visible(button, 1)
        gtk_widget_set_visible(labelWidget, 1)
        applyCSSToWidget(button, properties: """
            background: transparent;
            background-image: none;
            border: none;
            border-radius: 6px;
            box-shadow: none;
            color: #1d1d1f;
            padding: 8px 10px;
            min-height: 0;
            """)

        let clickBox = Unmanaged.passRetained(ClosureBox {
            gtkDismissActiveMenuOverlay()
            action()
        }).toOpaque()
        g_signal_connect_data(
            gpointer(button),
            "clicked",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            clickBox,
            { data, _ in
                if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
            },
            GConnectFlags(rawValue: 0)
        )
        gtk_box_append(boxPointer(box), button)

    case .submenu(let label, let children):
        let subButton = gtk_menu_button_new()!
        gtk_swift_menu_button_set_label(subButton, label)
        let subPopover = gtk_popover_new()!
        let child = gtkCreateMenuOverlayPanel(elements: children)
        gtk_swift_popover_set_child(subPopover, child)
        gtk_swift_menu_button_set_popover(subButton, subPopover)
        gtk_widget_set_hexpand(subButton, 1)
        gtk_widget_set_halign(subButton, GTK_ALIGN_FILL)
        gtk_widget_set_size_request(subButton, gtkMenuOverlayPreferredWidth - 12, -1)
        gtk_widget_set_visible(subButton, 1)
        gtk_box_append(boxPointer(box), subButton)

    case .divider:
        let separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)!
        gtk_widget_set_margin_top(separator, 4)
        gtk_widget_set_margin_bottom(separator, 4)
        gtk_widget_set_visible(separator, 1)
        gtk_box_append(boxPointer(box), separator)
    }
}

private func gtkAppendMenuPopoverElement(
    _ element: MenuElement,
    to box: UnsafeMutablePointer<GtkWidget>,
    popover: UnsafeMutablePointer<GtkWidget>,
    actionBox: MenuActionBox
) {
    switch element {
    case .item(let label, let action):
        let button = gtk_button_new()!
        let labelWidget = gtk_label_new(label)!
        gtk_swift_label_set_xalign(labelWidget, 0)
        gtk_widget_set_hexpand(labelWidget, 1)
        gtk_button_set_child(UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self), labelWidget)
        gtk_widget_set_hexpand(button, 1)
        gtk_widget_set_halign(button, GTK_ALIGN_FILL)
        gtk_widget_set_size_request(button, 132, -1)
        applyCSSToWidget(button, properties: """
            background: transparent;
            background-image: none;
            border: none;
            border-radius: 6px;
            box-shadow: none;
            padding: 7px 10px;
            min-height: 0;
            """)

        let actionClosure = ClosureBox(bindActionToCurrentEnvironment(action))
        actionBox.actions.append(actionClosure)
        let clickBox = Unmanaged.passRetained(ClosureBox { [actionClosure, popover] in
            actionClosure.closure()
            gtk_swift_popover_popdown(popover)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(button),
            "clicked",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            clickBox,
            { data, _ in
                if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
            },
            GConnectFlags(rawValue: 0)
        )
        gtk_box_append(boxPointer(box), button)

    case .submenu(let label, let children):
        let subButton = gtk_menu_button_new()!
        gtk_swift_menu_button_set_label(subButton, label)
        let subPopover = gtk_popover_new()!
        let child = gtkBuildMenuPopoverContent(
            elements: children,
            popover: subPopover,
            actionBox: actionBox
        )
        gtk_swift_popover_set_child(subPopover, child)
        gtk_swift_menu_button_set_popover(subButton, subPopover)
        gtkInstallMenuPopupGestures(under: subButton, menuButton: subButton)
        gtk_widget_set_hexpand(subButton, 1)
        gtk_widget_set_halign(subButton, GTK_ALIGN_FILL)
        gtk_widget_set_size_request(subButton, 132, -1)
        gtk_box_append(boxPointer(box), subButton)

    case .divider:
        let separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)!
        gtk_widget_set_margin_top(separator, 4)
        gtk_widget_set_margin_bottom(separator, 4)
        gtk_box_append(boxPointer(box), separator)
    }
}

private func gtkDebugMenuLabels(_ elements: [MenuElement]) -> [String] {
    elements.flatMap { element -> [String] in
        switch element {
        case .item(let label, _):
            return [label]
        case .divider:
            return ["---"]
        case .submenu(let label, let children):
            return [label] + gtkDebugMenuLabels(children)
        }
    }
}

private func gtkBuildMenuModel(elements: [MenuElement], menu: gpointer,
                                actionGroup: UnsafeMutablePointer<GSimpleActionGroup>,
                                actionBox: MenuActionBox,
                                actionIndex: inout Int) {
    // Split elements by dividers into sections for visual separation.
    var sections: [[MenuElement]] = [[]]
    for element in elements {
        if case .divider = element {
            sections.append([])
        } else {
            sections[sections.count - 1].append(element)
        }
    }

    if sections.count <= 1 {
        // No dividers — add items directly
        for element in elements {
            gtkAddMenuElement(element, to: menu, actionGroup: actionGroup,
                              actionBox: actionBox, actionIndex: &actionIndex)
        }
    } else {
        // Multiple sections — wrap each group in a GMenu section
        for section in sections where !section.isEmpty {
            let sectionMenu = gtk_swift_menu_new()!
            for element in section {
                gtkAddMenuElement(element, to: sectionMenu, actionGroup: actionGroup,
                                  actionBox: actionBox, actionIndex: &actionIndex)
            }
            gtk_swift_menu_append_section(menu, nil, sectionMenu)
        }
    }
}

private func gtkAddMenuElement(_ element: MenuElement, to menu: gpointer,
                                actionGroup: UnsafeMutablePointer<GSimpleActionGroup>,
                                actionBox: MenuActionBox,
                                actionIndex: inout Int) {
    switch element {
    case .item(let label, let action):
        let actionName = "action\(actionIndex)"
        actionIndex += 1

        let gAction = g_simple_action_new(actionName, nil)!

        let box = ClosureBox(bindActionToCurrentEnvironment(action))
        actionBox.actions.append(box)
        let boxPtr = Unmanaged.passUnretained(box).toOpaque()

        g_signal_connect_data(
            gpointer(gAction),
            "activate",
            unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
                let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                box.closure()
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
            boxPtr, nil,
            GConnectFlags(rawValue: 0)
        )

        gtk_swift_action_map_add_action(gpointer(actionGroup), gpointer(gAction))
        gtk_swift_menu_append(menu, label, "menu.\(actionName)")

    case .submenu(let label, let children):
        let submenu = gtk_swift_menu_new()!
        gtkBuildMenuModel(elements: children, menu: submenu,
                          actionGroup: actionGroup, actionBox: actionBox,
                          actionIndex: &actionIndex)
        gtk_swift_menu_append_submenu(menu, label, submenu)

    case .divider:
        break // handled at section level
    }
}

// MARK: - Toolbar GTK extension

extension ToolbarItem: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkRenderView(content)
    }
}

extension ToolbarView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        // Render the content; toolbar items are extracted by NavigationStack
        // via the ToolbarProvider protocol during header bar construction.
        gtkRenderView(content)
    }
}

extension ToolbarConfigurationView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        gtkRenderView(content)
    }
}

// MARK: - ConfirmationDialog GTK extension

extension ConfirmationDialogView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        let anchor: UnsafeMutablePointer<GtkWidget>
        if let host = GTKViewHost.getCurrentRebuilding() {
            anchor = host.container
        } else {
            anchor = widget
        }
        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

        if !isPresented.wrappedValue {
            if let dialogPtr = g_object_get_data(gobject, "swift-dialog-window") {
                let dialog = dialogPtr.assumingMemoryBound(to: GtkWindow.self)
                g_object_set_data(gobject, "swift-dialog-window", nil)
                gtk_window_destroy(dialog)
            }
            return opaqueFromWidget(widget)
        }

        guard g_object_get_data(gobject, "swift-dialog-active") == nil else {
            return opaqueFromWidget(widget)
        }
        g_object_set_data(gobject, "swift-dialog-active", gpointer(bitPattern: 1))
        g_object_ref(gpointer(anchor))

        let dialogTitle = title
        let dialogTitleVisibility = titleVisibility
        let dialogMessage = message
        let dialogButtons = buttons
        let binding = isPresented

        let onDismiss: () -> Void = {
            let obj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
            g_object_set_data(obj, "swift-dialog-active", nil)
            g_object_set_data(obj, "swift-dialog-window", nil)
            binding.wrappedValue = false
        }

        g_idle_add({ userData -> gboolean in
            let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeRetainedValue()
            box.closure()
            return 0
        }, Unmanaged.passRetained(ClosureBox { [anchor, dialogTitle, dialogTitleVisibility, dialogMessage, dialogButtons, onDismiss] in
            guard let root = gtk_widget_get_root(anchor) else {
                onDismiss()
                g_object_unref(gpointer(anchor))
                return
            }

            let dialog = gtk_window_new()!
            let dialogWin = windowPointer(dialog)
            gtk_window_set_modal(dialogWin, 1)
            gtk_window_set_title(dialogWin, dialogTitleVisibility == .hidden ? "" : dialogTitle)
            gtk_window_set_default_size(dialogWin, 300, -1)
            gtk_window_set_resizable(dialogWin, 0)
            gtk_window_set_transient_for(
                dialogWin,
                UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
            )

            let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8)!
            gtk_widget_set_margin_top(vbox, 20)
            gtk_widget_set_margin_bottom(vbox, 20)
            gtk_widget_set_margin_start(vbox, 20)
            gtk_widget_set_margin_end(vbox, 20)

            // Title — honor titleVisibility
            if dialogTitleVisibility != .hidden {
                let titleLabel = gtk_label_new(nil)!
                let escaped = dialogTitle
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                gtk_swift_label_set_markup(titleLabel, "<b>\(escaped)</b>")
                gtk_box_append(boxPointer(vbox), titleLabel)
            }

            // Message
            if !dialogMessage.isEmpty {
                let msgLabel = gtk_label_new(dialogMessage)!
                gtk_label_set_wrap(OpaquePointer(msgLabel), 1)
                gtk_box_append(boxPointer(vbox), msgLabel)
            }

            let sep = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)!
            gtk_box_append(boxPointer(vbox), sep)

            // Vertical buttons
            for alertButton in dialogButtons {
                let btn = gtk_button_new_with_label(alertButton.label)!
                gtk_widget_set_hexpand(btn, 1)

                if alertButton.role == .destructive {
                    gtk_widget_add_css_class(btn, "destructive-action")
                }

                let actionBox = Unmanaged.passRetained(AlertActionBox(
                    action: alertButton.action, dialog: dialog
                )).toOpaque()
                g_signal_connect_data(
                    gpointer(btn),
                    "clicked",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                        let box = Unmanaged<AlertActionBox>.fromOpaque(userData!).takeUnretainedValue()
                        box.action()
                        gtk_window_destroy(windowPointer(box.dialog))
                    } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                    actionBox,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<AlertActionBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )

                gtk_box_append(boxPointer(vbox), btn)
            }

            let anchorObj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
            g_object_set_data(anchorObj, "swift-dialog-window", gpointer(dialogWin))

            let closeDismiss = Unmanaged.passRetained(ClosureBox(onDismiss)).toOpaque()
            g_signal_connect_data(
                gpointer(dialog),
                "close-request",
                unsafeBitCast({ (_: gpointer?, userData: gpointer?) -> gboolean in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue().closure()
                    return 0
                } as @convention(c) (gpointer?, gpointer?) -> gboolean, to: GCallback.self),
                closeDismiss,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )

            gtk_window_set_child(dialogWin, vbox)
            gtk_window_present(dialogWin)
            g_object_unref(gpointer(anchor))
        }).toOpaque())

        return opaqueFromWidget(widget)
    }
}

// MARK: - Canvas GTK extension

/// Wraps draw closure for C callback bridging.
class DrawClosureBox {
    var closure: (DrawingContext, Int, Int) -> Void
    init(_ closure: @escaping (DrawingContext, Int, Int) -> Void) {
        self.closure = closure
    }
}

class SizedDrawClosureBox {
    var closure: (DrawingContext, Int, Int) -> Void
    var sizedClosure: ((DrawingContext, CGSize) -> Void)?
    init(_ closure: @escaping (DrawingContext, Int, Int) -> Void,
         sized: ((DrawingContext, CGSize) -> Void)? = nil) {
        self.closure = closure
        self.sizedClosure = sized
    }
}

extension DrawingContext {
    // MARK: - Color
    public func setColor(r: Double, g: Double, b: Double) {
        gtk_swift_cairo_set_source_rgb(cr, r, g, b)
    }
    public func setColor(r: Double, g: Double, b: Double, a: Double) {
        gtk_swift_cairo_set_source_rgba(cr, r, g, b, a)
    }

    // MARK: - Line style
    public func setLineWidth(_ width: Double) {
        gtk_swift_cairo_set_line_width(cr, width)
    }
    public func setLineCap(_ cap: LineCap) {
        let v: cairo_line_cap_t
        switch cap {
        case .butt:   v = CAIRO_LINE_CAP_BUTT
        case .round:  v = CAIRO_LINE_CAP_ROUND
        case .square: v = CAIRO_LINE_CAP_SQUARE
        }
        gtk_swift_cairo_set_line_cap(cr, v)
    }
    public func setLineJoin(_ join: LineJoin) {
        let v: cairo_line_join_t
        switch join {
        case .miter: v = CAIRO_LINE_JOIN_MITER
        case .round: v = CAIRO_LINE_JOIN_ROUND
        case .bevel: v = CAIRO_LINE_JOIN_BEVEL
        }
        gtk_swift_cairo_set_line_join(cr, v)
    }

    // MARK: - Path operations
    public func moveTo(x: Double, y: Double) {
        gtk_swift_cairo_move_to(cr, x, y)
    }
    public func lineTo(x: Double, y: Double) {
        gtk_swift_cairo_line_to(cr, x, y)
    }
    public func rectangle(x: Double, y: Double, width: Double, height: Double) {
        gtk_swift_cairo_rectangle(cr, x, y, width, height)
    }
    public func arc(centerX: Double, centerY: Double, radius: Double,
                    startAngle: Double = 0, endAngle: Double = .pi * 2) {
        gtk_swift_cairo_arc(cr, centerX, centerY, radius, startAngle, endAngle)
    }

    // MARK: - Drawing
    public func stroke() { gtk_swift_cairo_stroke(cr) }
    public func fill() { gtk_swift_cairo_fill(cr) }
    public func paint() { gtk_swift_cairo_paint(cr) }

    // MARK: - State
    public func save() { gtk_swift_cairo_save(cr) }
    public func restore() { gtk_swift_cairo_restore(cr) }
    public func scale(x: Double, y: Double) { gtk_swift_cairo_scale(cr, x, y) }

    // MARK: - Surface painting
    public func setSourceSurface(_ surface: OpaquePointer, x: Double = 0, y: Double = 0) {
        gtk_swift_cairo_set_source_surface(cr, surface, x, y)
    }

    // MARK: - Path-based drawing

    /// Stroke a Path with the given shading and style.
    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle = StrokeStyle()) {
        let (r, g, b, a) = shading.colorComponents
        gtk_swift_cairo_set_source_rgba(cr, r, g, b, a)
        gtk_swift_cairo_set_line_width(cr, Double(style.lineWidth))

        let cairoCap: cairo_line_cap_t
        switch style.lineCap {
        case .butt:   cairoCap = CAIRO_LINE_CAP_BUTT
        case .round:  cairoCap = CAIRO_LINE_CAP_ROUND
        case .square: cairoCap = CAIRO_LINE_CAP_SQUARE
        }
        gtk_swift_cairo_set_line_cap(cr, cairoCap)

        let cairoJoin: cairo_line_join_t
        switch style.lineJoin {
        case .miter: cairoJoin = CAIRO_LINE_JOIN_MITER
        case .bevel: cairoJoin = CAIRO_LINE_JOIN_BEVEL
        case .round: cairoJoin = CAIRO_LINE_JOIN_ROUND
        }
        gtk_swift_cairo_set_line_join(cr, cairoJoin)

        // Apply dash pattern if specified. Empty = solid; a non-empty array
        // draws alternating on/off segments (e.g. [8, 4] = 8pt dash, 4pt gap).
        if style.dash.isEmpty {
            gtk_swift_cairo_set_dash(cr, nil, 0, 0)
        } else {
            let dashes = style.dash.map { Double($0) }
            dashes.withUnsafeBufferPointer { buf in
                gtk_swift_cairo_set_dash(cr, buf.baseAddress, Int32(buf.count), Double(style.dashPhase))
            }
        }

        applyPathElements(path)
        gtk_swift_cairo_stroke(cr)
    }

    /// Fill a Path with the given shading.
    public func fill(_ path: Path, with shading: Shading) {
        let (r, g, b, a) = shading.colorComponents
        gtk_swift_cairo_set_source_rgba(cr, r, g, b, a)
        applyPathElements(path)
        gtk_swift_cairo_fill(cr)
    }

    /// Walk path elements and emit corresponding Cairo calls.
    private func applyPathElements(_ path: Path) {
        gtk_swift_cairo_new_path(cr)
        for element in path.elements {
            switch element {
            case .moveTo(let pt):
                gtk_swift_cairo_move_to(cr, Double(pt.x), Double(pt.y))
            case .lineTo(let pt):
                gtk_swift_cairo_line_to(cr, Double(pt.x), Double(pt.y))
            case .curve(let end, let c1, let c2):
                gtk_swift_cairo_curve_to(cr,
                    Double(c1.x), Double(c1.y),
                    Double(c2.x), Double(c2.y),
                    Double(end.x), Double(end.y))
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                // SwiftUI clockwise = visually CW in y-down = cairo_arc_negative
                if clockwise {
                    gtk_swift_cairo_arc_negative(cr,
                        Double(center.x), Double(center.y), Double(radius),
                        Double(startAngle), Double(endAngle))
                } else {
                    gtk_swift_cairo_arc(cr,
                        Double(center.x), Double(center.y), Double(radius),
                        Double(startAngle), Double(endAngle))
                }
            case .ellipse(let center, let rx, let ry):
                guard rx > 0 && ry > 0 else { continue }
                gtk_swift_cairo_save(cr)
                gtk_swift_cairo_scale(cr, 1.0, Double(ry / rx))
                gtk_swift_cairo_arc(cr,
                    Double(center.x), Double(center.y) * Double(rx / ry), Double(rx),
                    0, 2 * .pi)
                gtk_swift_cairo_restore(cr)
            case .closeSubpath:
                gtk_swift_cairo_close_path(cr)
            }
        }
    }
}

extension Canvas: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        gtkCollectCanvasPayload(GTK4CanvasPayload(
            width: width,
            height: height,
            drawHandler: drawHandler,
            sizedDrawHandler: sizedDrawHandler
        ))
        return GTK4DescriptorNode(
            kind: .canvas,
            typeName: "Canvas",
            props: .canvas(GTK4CanvasDescriptor(width: width, height: height))
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let area = gtk_drawing_area_new()!

        if width > 0 {
            gtk_swift_drawing_area_set_content_width(area, gint(width))
        }
        if height > 0 {
            gtk_swift_drawing_area_set_content_height(area, gint(height))
        }

        // When no explicit size is set, expand to fill available space
        // (matches SwiftUI Canvas which fills its proposed size).
        if width <= 0 {
            gtk_widget_set_hexpand(area, 1)
        }
        if height <= 0 {
            gtk_widget_set_vexpand(area, 1)
            gtkMarkVerticalFillIntent(area)
        }

        let box = Unmanaged.passRetained(
            SizedDrawClosureBox(drawHandler, sized: sizedDrawHandler)
        ).toOpaque()
        let gobject = UnsafeMutableRawPointer(area).assumingMemoryBound(to: GObject.self)
        g_object_set_data(gobject, "gtk-swift-canvas-draw-box", box)
        gtkMarkHostedNodeKind(area, kind: .canvas)

        gtk_swift_drawing_area_set_draw_func(
            area,
            { (widget: UnsafeMutablePointer<GtkWidget>?,
               cr: OpaquePointer?,
               w: gint, h: gint,
               userData: gpointer?) in
                guard let cr = cr, let userData = userData else { return }
                let box = Unmanaged<SizedDrawClosureBox>.fromOpaque(userData).takeUnretainedValue()
                let context = DrawingContext(cr: cr)
                if let sizedHandler = box.sizedClosure {
                    sizedHandler(context, CGSize(width: CGFloat(w), height: CGFloat(h)))
                } else {
                    box.closure(context, Int(w), Int(h))
                }
            },
            box,
            { (userData: gpointer?) in
                guard let userData = userData else { return }
                Unmanaged<SizedDrawClosureBox>.fromOpaque(userData).release()
            }
        )

        return opaqueFromWidget(area)
    }
}

// MARK: - Foreground color propagation for text and Cairo rendering
//
// ForegroundColorView applies CSS color: to widgets, but GtkDrawingArea
// Cairo callbacks can't read CSS properties. Track the current foreground
// color in a render-time thread-local so bare shapes can read it.

private var _gtkCurrentForegroundColor: Color?

func gtkGetCurrentForegroundColor() -> Color {
    _gtkCurrentForegroundColor ?? Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 1.0)
}

func gtkCurrentForegroundColorIfSet() -> Color? {
    _gtkCurrentForegroundColor
}

func gtkSetCurrentForegroundColor(_ color: Color?) {
    _gtkCurrentForegroundColor = color
}

private func gtkWithCurrentForegroundColor<T>(_ color: Color?, _ body: () -> T) -> T {
    let previous = _gtkCurrentForegroundColor
    gtkSetCurrentForegroundColor(color)
    defer { gtkSetCurrentForegroundColor(previous) }
    return body()
}

// MARK: - Shape view rendering

/// Closure box for shape draw callbacks. Holds the path generator and
/// fill/stroke configuration so the Cairo callback can render the shape.
private class ShapeDrawBox {
    enum Mode {
        case fill(r: Double, g: Double, b: Double, a: Double)
        case stroke(r: Double, g: Double, b: Double, a: Double, style: StrokeStyle)
    }
    let pathGenerator: (CGRect) -> Path
    let mode: Mode

    init(pathGenerator: @escaping (CGRect) -> Path, mode: Mode) {
        self.pathGenerator = pathGenerator
        self.mode = mode
    }
}

/// Create a GtkDrawingArea that renders a shape via Cairo.
private func gtkCreateShapeWidget(box: ShapeDrawBox) -> OpaquePointer {
    let area = gtk_drawing_area_new()!
    gtk_widget_set_hexpand(area, 1)
    gtk_widget_set_vexpand(area, 1)
    gtkMarkVerticalFillIntent(area)

    let retained = Unmanaged.passRetained(box).toOpaque()

    gtk_swift_drawing_area_set_draw_func(
        area,
        { (widget: UnsafeMutablePointer<GtkWidget>?,
           cr: OpaquePointer?,
           w: gint, h: gint,
           userData: gpointer?) in
            guard let cr = cr, let userData = userData else { return }
            let box = Unmanaged<ShapeDrawBox>.fromOpaque(userData).takeUnretainedValue()
            let rect = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
            let path = box.pathGenerator(rect)
            let context = DrawingContext(cr: cr)

            switch box.mode {
            case .fill(let r, let g, let b, let a):
                context.fill(path, with: .color(Color(red: r, green: g, blue: b, opacity: a)))
            case .stroke(let r, let g, let b, let a, let style):
                context.stroke(path, with: .color(Color(red: r, green: g, blue: b, opacity: a)), style: style)
            }
        },
        retained,
        { (userData: gpointer?) in
            guard let userData = userData else { return }
            Unmanaged<ShapeDrawBox>.fromOpaque(userData).release()
        }
    )

    return opaqueFromWidget(area)
}

/// Render a bare shape (no .fill() or .stroke()) filled with the current
/// foreground color (default black).
private func gtkRenderBareShape<S: Shape>(_ shape: S) -> OpaquePointer {
    let fg = gtkGetCurrentForegroundColor()
    let box = ShapeDrawBox(
        pathGenerator: { rect in shape.path(in: rect) },
        mode: .fill(r: fg.red, g: fg.green, b: fg.blue, a: fg.alpha))
    return gtkCreateShapeWidget(box: box)
}

extension Circle: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer { gtkRenderBareShape(self) }
}

extension Rectangle: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer { gtkRenderBareShape(self) }
}

extension RoundedRectangle: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer { gtkRenderBareShape(self) }
}

extension Capsule: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer { gtkRenderBareShape(self) }
}

extension Ellipse: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer { gtkRenderBareShape(self) }
}

extension FilledShape: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = ShapeDrawBox(
            pathGenerator: { rect in self.shape.path(in: rect) },
            mode: .fill(r: color.red, g: color.green, b: color.blue, a: color.alpha))
        return gtkCreateShapeWidget(box: box)
    }
}

extension StrokedShape: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = ShapeDrawBox(
            pathGenerator: { rect in self.shape.path(in: rect) },
            mode: .stroke(r: color.red, g: color.green, b: color.blue, a: color.alpha, style: style))
        return gtkCreateShapeWidget(box: box)
    }
}

// MARK: - Stateful view rendering

private func gtkRenderStatefulView<V: View>(_ view: V) -> OpaquePointer {
    // body reads hop onto the main actor (View.body is @MainActor; host
    // rebuilds always run on the GTK main loop == main thread).
    let host = GTKViewHost(buildBody: {
        gtkAssumeMainActorIsolated { gtkRenderView(view.body) }
    })
    host.describeBody = {
        MainActor.assumeIsolated { gtkDescribeView(view.body) }
    }

    gtkRestoreAndInstallState(view, host: host)
    gtkRestoreViewHostLifecycleIfAvailable(host)

    let previousHost = GTKViewHost.getCurrentRebuilding()
    GTKViewHost.setCurrentRebuilding(host)
    beginDependencyTracking(host: host)
    let widget = host.buildBodyWithTracking()
    if let tracking = endDependencyTracking() {
        host.lastReadSet = tracking.readSet
        host.lastInputSnapshot = tracking.snapshots
    }
    GTKViewHost.setCurrentRebuilding(previousHost)

    let child = widgetFromOpaque(widget)
    let childHexpand = gtk_widget_get_hexpand(child) != 0
    let childVexpand = gtk_widget_get_vexpand(child) != 0
    gtk_widget_set_hexpand(host.container, childHexpand ? 1 : 0)
    gtk_widget_set_vexpand(host.container, childVexpand ? 1 : 0)
    if childHexpand {
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
    }
    if childVexpand {
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
    }
    gtk_box_append(boxPointer(host.container), child)
    gtkPropagateSingleChildLayoutMarkers(from: [child], to: host.container)

    // Capture initial descriptor state so the narrow mutation path is
    // available from the very first @State change.  Without this, the
    // first rebuild always takes the full-teardown path, which destroys
    // gesture recognisers attached to child widgets (e.g. Canvas + onDrag).
    if let describeBody = host.describeBody {
        let previousEnvForDesc = getCurrentEnvironment()
        setCurrentEnvironment(host.capturedEnvironment)
        let described = host.describeBodyCapturingPayloads(describeBody)
        setCurrentEnvironment(previousEnvForDesc)

        let identified = gtkIdentifyDescriptorTree(described.descriptor)
        let canvasPayloads = gtkCanvasPayloadsByIdentity(
            descriptorRoot: identified,
            payloads: described.canvasPayloads
        )
        host.updateOnAppearLifecycle(
            descriptorRoot: identified,
            onAppearPayloads: described.onAppearPayloads
        )
        host.updateTaskLifecycle(
            descriptorRoot: identified,
            taskPayloads: described.taskPayloads
        )
        gtkTagFocusableInputIdentities(in: child, descriptorRoot: identified)
        host.lastRetainedDescriptor = gtkRetainDescriptorTree(identified)
        var executor = gtkMakeExecutorTree(
            from: identified,
            canvasPayloadsByIdentity: canvasPayloads
        )
        executor = gtkCaptureSupportedNativeSlots(
            from: child,
            descriptorRoot: identified,
            executorRoot: executor
        )
        executor = gtkCaptureButtonNativeSlots(
            from: child,
            descriptorRoot: identified,
            executorRoot: executor
        )
        host.retainedExecutor = executor
    }

    return opaqueFromWidget(host.container)
}

private func gtkInstallStateProviders(from source: Any, host: GTKViewHost) -> Int {
    let providers = Mirror(reflecting: source).children.compactMap { $0.value as? AnyStateStorageProvider }
    for provider in providers {
        provider.anyStorage.host = host
    }
    return providers.count
}

func gtkRenderWindowRootView<V: View>(_ view: V, appStateSource: Any? = nil) -> OpaquePointer {
    let host = GTKViewHost(buildBody: {
        MainActor.assumeIsolated { gtkRenderView(view) }
    })
    host.describeBody = {
        MainActor.assumeIsolated { gtkDescribeView(view) }
    }

    if let appStateSource {
        let installed = gtkInstallStateProviders(from: appStateSource, host: host)
        gtkDebugLog(
            "app state install type=\(String(reflecting: type(of: appStateSource))) providers=\(installed)"
        )
    }
    gtkRestoreViewHostLifecycleIfAvailable(host)

    let previousHost = GTKViewHost.getCurrentRebuilding()
    GTKViewHost.setCurrentRebuilding(host)
    beginDependencyTracking(host: host)
    let widget = host.buildBodyWithTracking()
    if let tracking = endDependencyTracking() {
        host.lastReadSet = tracking.readSet
        host.lastInputSnapshot = tracking.snapshots
    }
    GTKViewHost.setCurrentRebuilding(previousHost)

    let child = widgetFromOpaque(widget)
    let childHexpand = gtk_widget_get_hexpand(child) != 0
    let childVexpand = gtk_widget_get_vexpand(child) != 0
    gtk_widget_set_hexpand(host.container, childHexpand ? 1 : 0)
    gtk_widget_set_vexpand(host.container, childVexpand ? 1 : 0)
    if childHexpand {
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
    }
    if childVexpand {
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
    }
    gtk_box_append(boxPointer(host.container), child)
    gtkPropagateSingleChildLayoutMarkers(from: [child], to: host.container)

    if let describeBody = host.describeBody {
        let previousEnvForDesc = getCurrentEnvironment()
        setCurrentEnvironment(host.capturedEnvironment)
        let described = host.describeBodyCapturingPayloads(describeBody)
        setCurrentEnvironment(previousEnvForDesc)

        let identified = gtkIdentifyDescriptorTree(described.descriptor)
        let canvasPayloads = gtkCanvasPayloadsByIdentity(
            descriptorRoot: identified,
            payloads: described.canvasPayloads
        )
        host.updateOnAppearLifecycle(
            descriptorRoot: identified,
            onAppearPayloads: described.onAppearPayloads
        )
        host.updateTaskLifecycle(
            descriptorRoot: identified,
            taskPayloads: described.taskPayloads
        )
        gtkTagFocusableInputIdentities(in: child, descriptorRoot: identified)
        host.lastRetainedDescriptor = gtkRetainDescriptorTree(identified)
        var executor = gtkMakeExecutorTree(
            from: identified,
            canvasPayloadsByIdentity: canvasPayloads
        )
        executor = gtkCaptureSupportedNativeSlots(
            from: child,
            descriptorRoot: identified,
            executorRoot: executor
        )
        executor = gtkCaptureButtonNativeSlots(
            from: child,
            descriptorRoot: identified,
            executorRoot: executor
        )
        host.retainedExecutor = executor
    }

    return opaqueFromWidget(host.container)
}

// MARK: - Safe Area GTK extensions

extension IgnoresSafeAreaView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite, typeName: "IgnoresSafeAreaView",
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        // Passthrough in Batch 1 — GTK has no native safe-area reservation yet
        gtkRenderView(content)
    }
}

extension SafeAreaInsetView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let insetFirst = edge == .top || edge == .leading
        let children = insetFirst
            ? [gtkDescribeView(inset), gtkDescribeView(content)]
            : [gtkDescribeView(content), gtkDescribeView(inset)]
        return GTK4DescriptorNode(
            kind: .safeAreaInset, typeName: "SafeAreaInsetView",
            props: .safeAreaInset(GTK4SafeAreaInsetDescriptor(
                edge: edge, alignment: alignment, spacing: spacing)),
            children: children)
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let isVertical: Bool
        let insetFirst: Bool

        switch edge {
        case .top:
            isVertical = true
            insetFirst = true
        case .bottom:
            isVertical = true
            insetFirst = false
        case .leading:
            isVertical = false
            insetFirst = true
        case .trailing:
            isVertical = false
            insetFirst = false
        }

        let orientation = isVertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
        let box = gtk_box_new(orientation, gint(spacing))!

        let contentWidget = widgetFromOpaque(gtkRenderView(content))
        let insetWidget = widgetFromOpaque(gtkRenderView(inset))

        // Cross-axis alignment for the inset content
        let crossAlign: GtkAlign
        switch alignment {
        case .horizontal(let hAlign):
            switch hAlign {
            case .leading:  crossAlign = GTK_ALIGN_START
            case .center:   crossAlign = GTK_ALIGN_CENTER
            case .trailing: crossAlign = GTK_ALIGN_END
            }
        case .vertical(let vAlign):
            switch vAlign {
            case .top:    crossAlign = GTK_ALIGN_START
            case .center: crossAlign = GTK_ALIGN_CENTER
            case .bottom: crossAlign = GTK_ALIGN_END
            }
        }

        if isVertical {
            gtk_widget_set_halign(insetWidget, crossAlign)
        } else {
            gtk_widget_set_valign(insetWidget, crossAlign)
        }

        if insetFirst {
            gtk_box_append(boxPointer(box), insetWidget)
            gtk_box_append(boxPointer(box), contentWidget)
        } else {
            gtk_box_append(boxPointer(box), contentWidget)
            gtk_box_append(boxPointer(box), insetWidget)
        }

        // Preserve expand flags from content — do not manufacture expansion
        if gtk_widget_get_hexpand(contentWidget) != 0 { gtk_widget_set_hexpand(box, 1) }
        if gtk_widget_get_vexpand(contentWidget) != 0 { gtk_widget_set_vexpand(box, 1) }

        return opaqueFromWidget(box)
    }
}

/// Synthetic safe-area padding default when length is nil (Batch A).
private let gtkSyntheticSafeAreaPadding = 16

/// Resolve per-edge safe-area padding. Negative lengths clamp to 0.
private func gtkResolveSafeAreaPadding(edges: Edge.Set, length: Int?) -> (top: Int, bottom: Int, leading: Int, trailing: Int) {
    let resolved = max(0, length ?? gtkSyntheticSafeAreaPadding)
    return (
        top: edges.contains(.top) ? resolved : 0,
        bottom: edges.contains(.bottom) ? resolved : 0,
        leading: edges.contains(.leading) ? resolved : 0,
        trailing: edges.contains(.trailing) ? resolved : 0
    )
}

extension SafeAreaPaddingView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        let p = gtkResolveSafeAreaPadding(edges: edges, length: length)
        return GTK4DescriptorNode(
            kind: .safeAreaPadding, typeName: "SafeAreaPaddingView",
            props: .safeAreaPadding(GTK4SafeAreaPaddingDescriptor(
                top: p.top, bottom: p.bottom, leading: p.leading, trailing: p.trailing)),
            children: [gtkDescribeView(content)])
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let p = gtkResolveSafeAreaPadding(edges: edges, length: length)

        let child = widgetFromOpaque(gtkRenderView(content))
        let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        applyCSSToWidget(wrapper, properties: """
            padding-top: \(p.top)px;
            padding-bottom: \(p.bottom)px;
            padding-left: \(p.leading)px;
            padding-right: \(p.trailing)px;
            """)
        if gtk_widget_get_hexpand(child) != 0 { gtk_widget_set_hexpand(wrapper, 1) }
        if gtk_widget_get_vexpand(child) != 0 { gtk_widget_set_vexpand(wrapper, 1) }
        gtk_box_append(boxPointer(wrapper), child)
        return opaqueFromWidget(wrapper)
    }
}

// MARK: - Custom Layout GTK extension

private final class GTKLayoutContainerContext {
    let child: UnsafeMutablePointer<GtkWidget>
    private let measureSize: (ProposedViewSize) -> CGSize

    init(child: UnsafeMutablePointer<GtkWidget>, measureSize: @escaping (ProposedViewSize) -> CGSize) {
        self.child = child
        self.measureSize = measureSize
    }

    func sizeThatFits(width: Double?) -> CGSize {
        measureSize(ProposedViewSize(width: width, height: nil))
    }

    func unspecifiedSize() -> CGSize {
        measureSize(.unspecified)
    }

    func measure(
        orientation: GtkOrientation,
        forSize: gint,
        minimum: UnsafeMutablePointer<gint>?,
        natural: UnsafeMutablePointer<gint>?
    ) {
        let size: CGSize
        if orientation == GTK_ORIENTATION_HORIZONTAL {
            let minimumSize = sizeThatFits(width: 0)
            let naturalSize = unspecifiedSize()
            minimum?.pointee = gtkPixelSize(minimumSize.width)
            natural?.pointee = gtkPixelSize(naturalSize.width)
            return
        }

        let proposedWidth: Double?
        if forSize >= 0 {
            proposedWidth = Double(forSize)
        } else {
            proposedWidth = unspecifiedSize().width
        }
        size = sizeThatFits(width: proposedWidth)
        let value = gtkPixelSize(size.height)
        minimum?.pointee = value
        natural?.pointee = value
    }

    func allocate(width: gint, height: gint, baseline: gint) {
        let proposedWidth = width >= 0 ? Double(width) : nil
        let size = sizeThatFits(width: proposedWidth)
        let childWidth = min(Double(max(0, width)), max(0, size.width))
        let childHeight = min(Double(max(0, height)), max(0, size.height))
        gtk_widget_allocate(
            child,
            gtkPixelSize(childWidth),
            gtkPixelSize(childHeight),
            baseline,
            nil
        )
    }
}

private let gtkLayoutContainerMeasureCallback: @convention(c) (
    gpointer?,
    GtkOrientation,
    gint,
    UnsafeMutablePointer<gint>?,
    UnsafeMutablePointer<gint>?
) -> Void = { userData, orientation, forSize, minimum, natural in
    guard let userData else { return }
    let context = Unmanaged<GTKLayoutContainerContext>.fromOpaque(userData).takeUnretainedValue()
    context.measure(orientation: orientation, forSize: forSize, minimum: minimum, natural: natural)
}

private let gtkLayoutContainerAllocateCallback: @convention(c) (
    gpointer?,
    gint,
    gint,
    gint
) -> Void = { userData, width, height, baseline in
    guard let userData else { return }
    let context = Unmanaged<GTKLayoutContainerContext>.fromOpaque(userData).takeUnretainedValue()
    context.allocate(width: width, height: height, baseline: baseline)
}

private let gtkLayoutContainerDestroyCallback: @convention(c) (gpointer?) -> Void = { userData in
    guard let userData else { return }
    Unmanaged<GTKLayoutContainerContext>.fromOpaque(userData).release()
}

extension LayoutContainer: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let child = widgetFromOpaque(gtkRenderView(content))
        let subviews = LayoutSubviews([LayoutSubview(index: 0)])
        let context = GTKLayoutContainerContext(child: child) { proposal in
            var cache: () = ()
            return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        }
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        let wrapper = gtk_swift_custom_layout_new(
            child,
            contextPointer,
            gtkLayoutContainerMeasureCallback,
            gtkLayoutContainerAllocateCallback,
            gtkLayoutContainerDestroyCallback
        )!

        if gtk_widget_get_hexpand(child) != 0 {
            gtk_widget_set_hexpand(wrapper, 1)
            gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        }
        if gtk_widget_get_vexpand(child) != 0 {
            gtk_widget_set_vexpand(wrapper, 1)
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        }
        gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)
        return opaqueFromWidget(wrapper)
    }
}

// MARK: - ViewThatFits GTK extension

private class GTKViewThatFitsContext {
    let stack: UnsafeMutablePointer<GtkWidget>
    let childWidgets: [UnsafeMutablePointer<GtkWidget>]
    let childCount: Int
    private var currentIndex: Int = 0
    private var lastWidth: Int = -1
    private var lastHeight: Int = -1

    init(stack: UnsafeMutablePointer<GtkWidget>,
         childWidgets: [UnsafeMutablePointer<GtkWidget>],
         childCount: Int) {
        self.stack = stack
        self.childWidgets = childWidgets
        self.childCount = childCount
    }

    /// Called each frame via tick callback. Re-evaluates only when size changes.
    func tickCheck() {
        guard childCount > 0 else { return }
        let w = Int(gtk_widget_get_width(stack))
        let h = Int(gtk_widget_get_height(stack))
        guard w > 0 && h > 0 else { return }
        guard w != lastWidth || h != lastHeight else { return }
        lastWidth = w
        lastHeight = h
        selectBestFit(allocWidth: w, allocHeight: h)
    }

    private func selectBestFit(allocWidth: Int, allocHeight: Int) {
        var bestIndex = childCount - 1 // fallback to last
        for i in 0..<childCount {
            let child = childWidgets[i]
            var naturalWidth: gint = 0
            var naturalHeight: gint = 0
            gtk_widget_measure(child, GTK_ORIENTATION_HORIZONTAL, -1,
                               nil, &naturalWidth, nil, nil)
            gtk_widget_measure(child, GTK_ORIENTATION_VERTICAL, gint(allocWidth),
                               nil, &naturalHeight, nil, nil)

            if Int(naturalWidth) <= allocWidth && Int(naturalHeight) <= allocHeight {
                bestIndex = i
                break
            }
        }

        if bestIndex != currentIndex {
            currentIndex = bestIndex
            gtk_stack_set_visible_child_name(
                OpaquePointer(stack), "vtf-\(bestIndex)")
        }
    }
}

/// Tick callback for ViewThatFits — re-evaluates child selection on size changes.
private func gtkViewThatFitsTickCallback(
    _ widget: UnsafeMutablePointer<GtkWidget>?,
    _ frameClock: OpaquePointer?,
    _ userData: gpointer?
) -> gboolean {
    guard let userData = userData else { return 1 }
    let ctx = Unmanaged<GTKViewThatFitsContext>.fromOpaque(userData).takeUnretainedValue()
    ctx.tickCheck()
    return 1 // keep running
}

extension ViewThatFits: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let stack = gtk_stack_new()!
        let stackOp = OpaquePointer(stack)
        gtk_stack_set_transition_type(stackOp, GTK_STACK_TRANSITION_TYPE_NONE)

        var childWidgets: [UnsafeMutablePointer<GtkWidget>] = []
        for (i, child) in children.enumerated() {
            let widget = widgetFromOpaque(gtkRenderAnyView(child))
            gtk_stack_add_named(stackOp, widget, "vtf-\(i)")
            childWidgets.append(widget)
        }

        if !children.isEmpty {
            gtk_stack_set_visible_child_name(stackOp, "vtf-0")
        }

        let context = GTKViewThatFitsContext(
            stack: stack,
            childWidgets: childWidgets,
            childCount: children.count
        )

        // Tick callback re-evaluates which child fits on each frame when size changes.
        // Automatically paused when the widget is unmapped.
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        _ = gtk_widget_add_tick_callback(
            stack,
            gtkViewThatFitsTickCallback,
            contextPtr,
            { userData in Unmanaged<GTKViewThatFitsContext>.fromOpaque(userData!).release() }
        )

        return opaqueFromWidget(stack)
    }
}
