// QtRenderer.swift — generic SwiftUI→Qt rendering dispatch for BackendQt.
//
// This is the Qt analogue of SwiftOpenUI's GTKRenderer.swift. It walks a real
// SwiftOpenUI view tree and produces native Qt widgets through the CQtBridge
// C ABI. The contract mirrors GTK exactly:
//
//   * Each primitive view conforms to `QtRenderable` via an extension and
//     returns an `OpaquePointer` widget handle from `qtCreateWidget()`.
//   * `qtRenderView` is the single dispatch entry: primitive → renderable;
//     multi-child aggregate → vertical container; stateful composite → host;
//     stateless composite → recurse through `body`.
//   * Containers (VStack/HStack) measure children with the SHARED layout engine
//     (`computeVStackLayout` / `computeHStackLayout` in SwiftOpenUI core) and
//     place them at absolute coordinates inside a plain QWidget. This reuses
//     the exact SwiftUI proposal/intrinsic math the GTK backend uses, instead
//     of nesting QBoxLayouts.
//
// SLICE #1 conforms only: Text, Image, VStack, HStack, Button, Spacer, Color,
// EmptyView. The continuation plan fans the remaining views out from here.

#if canImport(CQtBridge)
import CQtBridge
import QuillSwiftUICompatibility
import SwiftOpenUI
import SwiftOpenUISymbols
import Foundation

// MARK: - Qt rendering protocol

/// Protocol that views implement (via extensions) to provide Qt widget
/// creation. Backend code extends each SwiftOpenUI view type to conform.
/// Direct mirror of `GTKRenderable`.
public protocol QtRenderable {
    func qtCreateWidget() -> OpaquePointer
}

/// Protocol for views that provide multiple Qt child widgets to their parent.
/// This lets transparent aggregators like ForEach expand into stacks/lists
/// while still having a fallback widget when rendered directly.
public protocol QtMultiChildRenderable {
    func qtRenderChildren() -> [OpaquePointer]
}

/// Marker stored as an objectName prefix so containers can recognise Spacer
/// widgets and opt out of the shared (absolute) layout, exactly like GTK's
/// `gtkSwiftSpacerMarker`.
let qtSwiftSpacerObjectName = "quill-qt-spacer"

// MARK: - Pointer helpers

/// CQtBridge surfaces every handle as a C `void *`, which Swift imports as
/// `UnsafeMutableRawPointer?`. We standardise on `OpaquePointer` in the
/// renderer (matching GTK's convention) and convert at the bridge boundary.
@inline(__always)
func qtHandle(_ ptr: OpaquePointer) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer(ptr)
}

@inline(__always)
func qtOpaque(_ raw: UnsafeMutableRawPointer?) -> OpaquePointer {
    OpaquePointer(raw!)
}

// MARK: - Rendering dispatch

/// Render any SwiftOpenUI View into a Qt widget handle. Direct structural
/// mirror of `gtkRenderView`.
public func qtRenderView<V: View>(_ view: V) -> OpaquePointer {
    // Primitive views with known Qt rendering.
    if let renderable = view as? QtRenderable {
        return renderable.qtCreateWidget()
    }

    // MultiChildView (TupleView, Group, ForEach, ViewList, etc.) — render
    // children into a vertical container. Must precede the reactive/body
    // checks because these types have Body == Never.
    if let multi = view as? MultiChildView {
        let children = qtRenderExpandedChildren(multi.children)
        return qtRenderVerticalContainer(children, spacing: 0, alignment: .leading)
    }

    // Composite view with reactive state — wrap in a QtViewHost so @State /
    // @Observable mutations rebuild the subtree.
    if hasReactiveProperties(view) {
        return qtRenderStatefulView(view)
    }

    // Unhandled primitive: degrade instead of crashing into body's
    // fatalError. Checked via Body == Never (not the PrimitiveView marker —
    // several primitives like ItemSheetModifierView omit it). Modifier
    // wrappers (sheet, transition, …) expose their wrapped subtree as
    // `content`: pass it through so the UI stays visible; true leaves render
    // an empty placeholder. The trace lines let one launch smoke enumerate
    // every missing Qt renderable.
    if V.Body.self == Never.self {
        for child in Mirror(reflecting: view).children where child.label == "content" {
            if let inner = child.value as? any View {
                qtBackendTrace("unhandled primitive \(type(of: view)); passing through content")
                return qtRenderAnyView(inner)
            }
        }
        qtBackendTrace("unhandled primitive \(type(of: view)); rendering empty placeholder")
        let container = qtOpaque(quill_qt_bridge_container_create())
        quill_qt_bridge_widget_set_fixed_size(qtHandle(container), 0, 0)
        return container
    }

    // Stateless composite view — recurse through body. SwiftOpenUI's body is
    // @MainActor; the Qt renderer runs on the Qt GUI thread, so assume the
    // isolation that is true by construction.
    nonisolated(unsafe) var rendered: OpaquePointer?
    MainActor.assumeIsolated {
        rendered = qtRenderView(view.body)
    }
    return rendered!
}

// MARK: - onChange Qt extensions (mirror of the GTK pair)

extension OnChangeView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        _ = onChangeCheckAndFire(value: value, action: action)
        return qtRenderView(content)
    }
}

extension OnChangeTwoArgView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        _ = onChangeCheckAndFireTwoArg(value: value, action: action)
        return qtRenderView(content)
    }
}

extension InitialOnChangeView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        _ = onChangeCheckAndFire(value: value, initial: initial, action: action)
        return qtRenderView(content)
    }
}

extension InitialOnChangeTwoArgView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        _ = onChangeCheckAndFireTwoArg(value: value, initial: initial, action: action)
        return qtRenderView(content)
    }
}

/// Render an existential (any View).
public func qtRenderAnyView(_ view: any View) -> OpaquePointer {
    func render<V: View>(_ v: V) -> OpaquePointer { qtRenderView(v) }
    return render(view)
}

/// Enumerate a view's children as individual widgets (VStack/HStack use this).
func qtRenderChildren<V: View>(_ view: V) -> [OpaquePointer] {
    if let multi = view as? QtMultiChildRenderable {
        return multi.qtRenderChildren()
    }
    if let transparent = view as? any TransparentMultiChildView {
        return qtRenderExpandedChildren(transparent.children)
    }
    if let multi = view as? MultiChildView {
        return qtRenderExpandedChildren(multi.children)
    }
    return [qtRenderView(view)]
}

func qtRenderExpandedChildren(_ children: [any View]) -> [OpaquePointer] {
    children.flatMap { child in
        if let multi = child as? QtMultiChildRenderable {
            return multi.qtRenderChildren()
        }
        if let transparent = child as? any TransparentMultiChildView {
            return qtRenderExpandedChildren(transparent.children)
        }
        return [qtRenderAnyView(child)]
    }
}

/// Wrap a reactive composite view in a QtViewHost and return its container.
func qtRenderStatefulView<V: View>(_ view: V) -> OpaquePointer {
    let host = QtViewHost {
        nonisolated(unsafe) var rendered: OpaquePointer?
        MainActor.assumeIsolated {
            rendered = qtRenderView(view.body)
        }
        return rendered!
    }
    installState(view, host: host)
    host.performInitialBuild()
    return host.container
}

// MARK: - Shared-layout container

/// A `LayoutMeasureContext` that measures Qt widgets via the bridge's
/// sizeHint(), feeding the shared SwiftOpenUI layout engine. Direct analogue of
/// GTK's `GTKLayoutMeasureContext` (which calls gtk_widget_measure).
struct QtLayoutMeasureContext: LayoutMeasureContext {
    let widgets: [OpaquePointer]

    func measure(_ subview: LayoutSubview, proposal: ProposedViewSize) -> LayoutMeasurement {
        let widget = widgets[subview.index]
        var w: Int32 = 0
        var h: Int32 = 0
        // Use the resolved size, not sizeHint(): container children (VStack /
        // HStack / FrameView) carry an explicit fixed size that sizeHint() does
        // not report, while leaf widgets (Text / Button) fall back to sizeHint()
        // inside resolved_size. This keeps measurement correct for both.
        quill_qt_bridge_widget_resolved_size(qtHandle(widget), &w, &h)
        return LayoutMeasurement(size: ViewSize(width: Double(w), height: Double(h)))
    }
}

/// Place children vertically inside an absolute-placement QWidget using the
/// shared `computeVStackLayout`. Mirrors GTK's `gtkRenderSharedVStack`.
func qtRenderVerticalContainer(
    _ children: [OpaquePointer],
    spacing: Int,
    alignment: HorizontalAlignment
) -> OpaquePointer {
    #if QUILLUI_QT_GENERIC
    for child in children {
        quill_qt_divider_set_orientation(qtHandle(child), 0)
    }
    #endif

    let container = qtOpaque(quill_qt_bridge_container_create())
    let context = QtLayoutMeasureContext(widgets: children)
    let layout = computeVStackLayout(
        subviews: children.indices.map(LayoutSubview.init(index:)),
        context: context,
        spacing: Double(spacing),
        alignment: alignment
    )

    quill_qt_bridge_widget_set_fixed_size(
        qtHandle(container),
        Int32(layout.containerSize.width),
        Int32(layout.containerSize.height)
    )

    for (child, placement) in zip(children, layout.childPlacements) {
        #if QUILLUI_QT_GENERIC
        let divider = quill_qt_widget_is_divider(qtHandle(child)) != 0
        let childX = divider ? 0 : placement.origin.x
        let childY = placement.origin.y
        let childWidth = divider ? max(1, layout.containerSize.width) : placement.size.width
        let childHeight = divider ? max(1, placement.size.height) : placement.size.height
        #else
        let childX = placement.origin.x
        let childY = placement.origin.y
        let childWidth = placement.size.width
        let childHeight = placement.size.height
        #endif

        quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))
        quill_qt_bridge_widget_set_geometry(
            qtHandle(child),
            Int32(childX),
            Int32(childY),
            Int32(childWidth),
            Int32(childHeight)
        )
    }
    return container
}

/// Place children horizontally inside an absolute-placement QWidget using the
/// shared `computeHStackLayout`. Mirrors GTK's `gtkRenderSharedHStack`.
func qtRenderHorizontalContainer(
    _ children: [OpaquePointer],
    spacing: Int,
    alignment: VerticalAlignment
) -> OpaquePointer {
    #if QUILLUI_QT_GENERIC
    for child in children {
        quill_qt_divider_set_orientation(qtHandle(child), 1)
    }
    #endif

    let container = qtOpaque(quill_qt_bridge_container_create())
    let context = QtLayoutMeasureContext(widgets: children)
    let layout = computeHStackLayout(
        subviews: children.indices.map(LayoutSubview.init(index:)),
        context: context,
        spacing: Double(spacing),
        alignment: alignment
    )

    quill_qt_bridge_widget_set_fixed_size(
        qtHandle(container),
        Int32(layout.containerSize.width),
        Int32(layout.containerSize.height)
    )

    for (child, placement) in zip(children, layout.childPlacements) {
        #if QUILLUI_QT_GENERIC
        let divider = quill_qt_widget_is_divider(qtHandle(child)) != 0
        let childX = placement.origin.x
        let childY = divider ? 0 : placement.origin.y
        let childWidth = divider ? max(1, placement.size.width) : placement.size.width
        let childHeight = divider ? max(1, layout.containerSize.height) : placement.size.height
        #else
        let childX = placement.origin.x
        let childY = placement.origin.y
        let childWidth = placement.size.width
        let childHeight = placement.size.height
        #endif

        quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))
        quill_qt_bridge_widget_set_geometry(
            qtHandle(child),
            Int32(childX),
            Int32(childY),
            Int32(childWidth),
            Int32(childHeight)
        )
    }
    return container
}

#if QUILLUI_QT_GENERIC
private enum QtOverlayHorizontalAlignment: Int32 {
    case leading = 0
    case center = 1
    case trailing = 2
}

private enum QtOverlayVerticalAlignment: Int32 {
    case top = 0
    case center = 1
    case bottom = 2
}

private func qtOverlayAlignmentAxes(
    _ alignment: Alignment
) -> (QtOverlayHorizontalAlignment, QtOverlayVerticalAlignment) {
    switch alignment {
    case .topLeading:
        return (.leading, .top)
    case .top:
        return (.center, .top)
    case .topTrailing:
        return (.trailing, .top)
    case .leading:
        return (.leading, .center)
    case .center:
        return (.center, .center)
    case .trailing:
        return (.trailing, .center)
    case .bottomLeading:
        return (.leading, .bottom)
    case .bottom:
        return (.center, .bottom)
    case .bottomTrailing:
        return (.trailing, .bottom)
    }
}

func qtRenderOverlayContainer(
    _ children: [OpaquePointer],
    alignment: Alignment
) -> OpaquePointer {
    let container = qtOpaque(quill_qt_make_overlay_container())
    let (horizontal, vertical) = qtOverlayAlignmentAxes(alignment)
    for child in children {
        quill_qt_overlay_container_add_child(
            qtHandle(container),
            qtHandle(child),
            horizontal.rawValue,
            vertical.rawValue
        )
    }
    return container
}

private enum QtPresentationKind {
    case sheet
    case popover

    var padding: Int32 {
        switch self {
        case .sheet: return 16
        case .popover: return 12
        }
    }

    var minimumSize: (width: Int32, height: Int32) {
        switch self {
        case .sheet: return (360, 180)
        case .popover: return (240, 120)
        }
    }

    var maximumSize: (width: Int32, height: Int32) {
        switch self {
        case .sheet: return (760, 620)
        case .popover: return (420, 420)
        }
    }

    var styleSheet: String {
        switch self {
        case .sheet:
            return """
            background-color: #f8f8fb;
            border: 1px solid rgba(0, 0, 0, 0.16);
            border-radius: 12px;
            """
        case .popover:
            return """
            background-color: #ffffff;
            border: 1px solid rgba(0, 0, 0, 0.14);
            border-radius: 10px;
            """
        }
    }
}

private func qtClamp(_ value: Int32, minimum: Int32, maximum: Int32) -> Int32 {
    min(max(value, minimum), maximum)
}

private func qtResolvedSize(_ widget: OpaquePointer) -> (width: Int32, height: Int32) {
    var width: Int32 = 0
    var height: Int32 = 0
    quill_qt_bridge_widget_resolved_size(qtHandle(widget), &width, &height)
    return (width, height)
}

private func qtRenderPresentationPanel(
    child: OpaquePointer,
    kind: QtPresentationKind
) -> OpaquePointer {
    let natural = qtResolvedSize(child)
    let padding = kind.padding
    let minimum = kind.minimumSize
    let maximum = kind.maximumSize
    let panelWidth = qtClamp(
        natural.width + padding * 2,
        minimum: minimum.width,
        maximum: maximum.width
    )
    let panelHeight = qtClamp(
        natural.height + padding * 2,
        minimum: minimum.height,
        maximum: maximum.height
    )

    let panel = qtOpaque(quill_qt_bridge_container_create())
    quill_qt_bridge_widget_set_stylesheet(qtHandle(panel), kind.styleSheet)
    quill_qt_bridge_widget_set_fixed_size(qtHandle(panel), panelWidth, panelHeight)
    quill_qt_bridge_widget_add_child(qtHandle(panel), qtHandle(child))
    quill_qt_bridge_widget_set_geometry(
        qtHandle(child),
        padding,
        padding,
        max(1, panelWidth - padding * 2),
        max(1, panelHeight - padding * 2)
    )
    return panel
}

private func qtRenderPresentedView<V: View>(
    _ view: V,
    dismiss: @escaping () -> Void
) -> OpaquePointer {
    let previous = getCurrentEnvironment()
    var environment = previous
    environment.dismiss = DismissAction(handler: dismiss)
    environment.isPresentedInSheet = true
    setCurrentEnvironment(environment)
    defer { setCurrentEnvironment(previous) }

    return swiftOpenUIWithPresentationDismissAction(dismiss) {
        qtRenderView(view)
    }
}

private func qtRenderPresentationOverlay(
    base: OpaquePointer,
    presented: OpaquePointer,
    horizontal: QtOverlayHorizontalAlignment,
    vertical: QtOverlayVerticalAlignment
) -> OpaquePointer {
    let baseSize = qtResolvedSize(base)
    let presentedSize = qtResolvedSize(presented)
    let overlay = qtOpaque(quill_qt_make_overlay_container())
    quill_qt_bridge_widget_set_fixed_size(
        qtHandle(overlay),
        max(baseSize.width, presentedSize.width),
        max(baseSize.height, presentedSize.height)
    )
    quill_qt_overlay_container_add_child(
        qtHandle(overlay),
        qtHandle(base),
        QtOverlayHorizontalAlignment.leading.rawValue,
        QtOverlayVerticalAlignment.top.rawValue
    )
    quill_qt_overlay_container_add_child(
        qtHandle(overlay),
        qtHandle(presented),
        horizontal.rawValue,
        vertical.rawValue
    )
    return overlay
}

private let qtLazyVGridDefaultSpacing = 4

private func qtLazyVGridColumnCount(gridItems: [GridItem], childCount: Int) -> Int {
    let configuration = computeLazyGridConfiguration(gridItems: gridItems)

    if configuration.adaptiveMinimum > 0 {
        return max(1, min(max(1, childCount), max(1, gridItems.count)))
    }

    return max(1, configuration.maxColumns)
}

func qtRenderLazyVGridContainer(
    _ children: [OpaquePointer],
    gridItems: [GridItem]
) -> OpaquePointer {
    let columnCount = qtLazyVGridColumnCount(
        gridItems: gridItems,
        childCount: children.count
    )
    let container = qtOpaque(quill_qt_make_grid_container(Int32(columnCount)))
    quill_qt_grid_container_set_spacing(
        qtHandle(container),
        Int32(qtLazyVGridDefaultSpacing),
        Int32(qtLazyVGridDefaultSpacing)
    )

    for (index, child) in children.enumerated() {
        quill_qt_grid_container_add_child(
            qtHandle(container),
            qtHandle(child),
            Int32(index / columnCount),
            Int32(index % columnCount)
        )
    }

    return container
}

func qtRenderLazyVGridCells<V: View>(_ view: V) -> [OpaquePointer] {
    if let transparent = view as? any TransparentMultiChildView {
        return qtRenderExpandedChildren(transparent.children)
    }

    if let multi = view as? QtMultiChildRenderable {
        return multi.qtRenderChildren()
    }

    return [qtRenderView(view)]
}
#endif

// MARK: - Deferred callback environment binding
//
// Capture the environment at registration time and restore it around a
// deferred button callback, mirroring GTK's `bindActionToCurrentEnvironment`.

func qtBindActionToCurrentEnvironment(_ action: @escaping () -> Void) -> () -> Void {
    let captured = getCurrentEnvironment()
    return {
        let previous = getCurrentEnvironment()
        setCurrentEnvironment(captured)
        defer { setCurrentEnvironment(previous) }
        action()
    }
}

// MARK: - Closure box for C callbacks

/// Wraps a Swift closure so it can cross the C `void *` boundary, mirroring
/// CGTKBridge's `ClosureBox`.
final class QtClosureBox {
    let closure: () -> Void
    init(_ closure: @escaping () -> Void) { self.closure = closure }
}

final class QtBoolClosureBox {
    let closure: (Bool) -> Void
    init(_ closure: @escaping (Bool) -> Void) { self.closure = closure }
}

final class QtFocusClosureBox {
    let focusChanged: (Bool) -> Void
    let destroyed: () -> Void

    init(
        focusChanged: @escaping (Bool) -> Void,
        destroyed: @escaping () -> Void
    ) {
        self.focusChanged = focusChanged
        self.destroyed = destroyed
    }
}

final class QtStringClosureBox {
    let closure: (String) -> Void
    init(_ closure: @escaping (String) -> Void) { self.closure = closure }
}

final class QtKeyPressActionBox {
    let actions: [KeyPressAction]

    init(actions: [KeyPressAction]) {
        self.actions = actions
    }

    func handle(keyCode: Int32) -> Bool {
        guard let key = qtKeyEquivalent(for: keyCode) else { return false }
        for action in actions.reversed() where action.key == key {
            if action.handler() == .handled {
                return true
            }
        }
        return false
    }
}

final class QtShortcutDispatchBox {
    let windowID: Int

    init(windowID: Int) {
        self.windowID = windowID
    }

    func handle(keyCode: Int32, modifiersRawValue: Int32) -> Bool {
        guard let key = qtKeyEquivalent(for: keyCode) else { return false }
        let shortcut = KeyboardShortcut(
            key,
            modifiers: EventModifiers(rawValue: Int(modifiersRawValue))
        )
        return KeyboardShortcutRegistry.shared.dispatch(shortcut, windowID: windowID)
    }
}

final class QtIntClosureBox {
    let closure: (Int) -> Void
    init(_ closure: @escaping (Int) -> Void) { self.closure = closure }
}

final class QtDoubleClosureBox {
    let closure: (Double) -> Void
    init(_ closure: @escaping (Double) -> Void) { self.closure = closure }
}

final class QtDateClosureBox {
    let closure: (SwiftOpenUI.DateComponents) -> Void
    init(_ closure: @escaping (SwiftOpenUI.DateComponents) -> Void) { self.closure = closure }
}

private final class QtEnvironmentCapture: @unchecked Sendable {
    let environment: EnvironmentValues
    init(_ environment: EnvironmentValues) { self.environment = environment }
}

func qtBindTaskActionToCurrentEnvironment(
    _ action: @escaping @Sendable () async -> Void
) -> @Sendable () async -> Void {
    let captured = QtEnvironmentCapture(getCurrentEnvironment())
    return {
        let previous = getCurrentEnvironment()
        setCurrentEnvironment(captured.environment)
        defer { setCurrentEnvironment(previous) }
        await action()
    }
}

func qtPostIdleAction(_ action: @escaping () -> Void) {
    let box = Unmanaged.passRetained(QtClosureBox(action)).toOpaque()
    let callback: quill_qt_bridge_idle_callback = { userData in
        guard let userData else { return }
        Unmanaged<QtClosureBox>.fromOpaque(userData).takeRetainedValue().closure()
    }
    quill_qt_bridge_post_idle(callback, box)
}

func qtKeyEquivalent(for keyCode: Int32) -> KeyEquivalent? {
    guard let scalar = UnicodeScalar(UInt32(bitPattern: keyCode)) else { return nil }
    return KeyEquivalent(Character(scalar))
}

func qtInstallKeyPressActions(
    on widget: OpaquePointer,
    actions: [KeyPressAction],
    environment: EnvironmentValues
) {
    guard !actions.isEmpty else { return }

    let boundActions = actions.map { action in
        KeyPressAction(key: action.key) {
            let previous = getCurrentEnvironment()
            setCurrentEnvironment(environment)
            defer { setCurrentEnvironment(previous) }
            return action.handler()
        }
    }
    let box = Unmanaged.passRetained(QtKeyPressActionBox(actions: boundActions)).toOpaque()
    let callback: quill_qt_bridge_key_callback = { key, userData in
        guard let userData else { return 0 }
        return Unmanaged<QtKeyPressActionBox>
            .fromOpaque(userData)
            .takeUnretainedValue()
            .handle(keyCode: key) ? 1 : 0
    }
    let destroy: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QtKeyPressActionBox>.fromOpaque(userData).release()
    }
    quill_qt_widget_install_key_press_recursive(qtHandle(widget), callback, box, destroy)
}

func qtInstallKeyboardShortcutDispatcher(on window: OpaquePointer, windowID: Int) {
    let box = Unmanaged.passRetained(QtShortcutDispatchBox(windowID: windowID)).toOpaque()
    let callback: quill_qt_bridge_shortcut_callback = { key, modifiers, userData in
        guard let userData else { return 0 }
        return Unmanaged<QtShortcutDispatchBox>
            .fromOpaque(userData)
            .takeUnretainedValue()
            .handle(keyCode: key, modifiersRawValue: modifiers) ? 1 : 0
    }
    let destroy: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QtShortcutDispatchBox>.fromOpaque(userData).release()
    }
    quill_qt_widget_install_shortcut_dispatcher(qtHandle(window), callback, box, destroy)
}

func qtRegisterKeyboardShortcut(
    _ shortcut: KeyboardShortcut,
    on widget: OpaquePointer,
    action: @escaping () -> Void,
    environment: EnvironmentValues
) {
    let boundAction = {
        let previous = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previous) }
        action()
    }
    let registrationID = KeyboardShortcutRegistry.shared.register(
        shortcut,
        windowID: environment.windowID,
        action: boundAction
    )
    let box = Unmanaged.passRetained(QtClosureBox {
        KeyboardShortcutRegistry.shared.unregister(id: registrationID)
    }).toOpaque()
    let destroyed: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QtClosureBox>
            .fromOpaque(userData)
            .takeUnretainedValue()
            .closure()
    }
    let destroy: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QtClosureBox>.fromOpaque(userData).release()
    }
    quill_qt_widget_connect_destroyed(qtHandle(widget), destroyed, box, destroy)
}

func qtTextLabel(from view: any View) -> String {
    if let anyView = view as? AnyView {
        return qtTextLabel(from: anyView.wrapped)
    }

    if let text = view as? Text {
        return text.content
    }

    if let label = view as? any AnyLabelView {
        return label.title
    }

    if let image = view as? Image {
        switch image.source {
        case .systemName(let name), .materialSymbol(let name):
            return name
        case .filePath:
            return "Image"
        }
    }

    if let multi = view as? MultiChildView {
        for child in multi.children {
            let label = qtTextLabel(from: child)
            if !label.isEmpty {
                return label
            }
        }
    }

    return ""
}

// MARK: - Leaf view conformances

extension Text: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        return qtOpaque(quill_qt_bridge_label_create(content))
    }
}

extension Image: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        switch source {
        case .systemName(let sfName):
            let materialName = SFSymbolCompatibility.materialName(for: sfName)
                ?? SFSymbolCompatibility.missingSymbolPlaceholderName
            #if DEBUG
            if SFSymbolCompatibility.materialName(for: sfName) == nil {
                FileHandle.standardError.write(Data(
                    "[BackendQt] Image(systemName: \"\(sfName)\") has no Material mapping; rendering placeholder\n".utf8
                ))
            }
            #endif
            return qtRenderMaterialSymbol(materialName, scale: scale)

        case .filePath(let path):
            return qtOpaque(
                quill_qt_bridge_image_create_from_file(
                    path,
                    Int32(isResizable ? 1 : 0)
                )
            )

        case .materialSymbol(let name):
            return qtRenderMaterialSymbol(name, scale: scale)
        }
    }
}

private func qtRenderMaterialSymbol(_ name: String, scale: ImageScale) -> OpaquePointer {
    let glyph: String
    if let codepoint = MaterialSymbolsCodepoints.codepoint(for: name),
       let scalar = Unicode.Scalar(codepoint) {
        glyph = String(scalar)
    } else {
        glyph = name
    }
    return qtOpaque(
        quill_qt_bridge_material_symbol_label_create(
            glyph,
            MaterialSymbolsResources.roundedRegularFamilyName,
            Int32(scale.pointSize)
        )
    )
}

extension EmptyView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        // A zero-size container, matching GTK's empty box.
        let container = qtOpaque(quill_qt_bridge_container_create())
        quill_qt_bridge_widget_set_fixed_size(qtHandle(container), 0, 0)
        return container
    }
}

extension Spacer: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        // A marked, zero-intrinsic widget. Slice #1 treats Spacer as a
        // zero-size placeholder (flex distribution is a continuation item —
        // see the PR's "layout risks" section). The marker lets future stack
        // code detect Spacers and switch to a flexible layout path.
        let label = qtOpaque(quill_qt_bridge_label_create(""))
        quill_qt_bridge_widget_set_object_name(qtHandle(label), qtSwiftSpacerObjectName)
        return label
    }
}

#if QUILLUI_QT_GENERIC
extension Divider: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtOpaque(quill_qt_make_divider())
    }
}
#endif

extension Color: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let container = qtOpaque(quill_qt_bridge_container_create())
        let css = String(
            format: "background-color: rgba(%d, %d, %d, %.3f);",
            Int(red * 255), Int(green * 255), Int(blue * 255), alpha
        )
        quill_qt_bridge_widget_set_stylesheet(qtHandle(container), css)
        return container
    }
}

extension ProgressView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let bar = qtOpaque(quill_qt_make_progress_bar())
        if let value {
            quill_qt_progress_bar_set_fraction(
                qtHandle(bar),
                qtSanitizedProgressFraction(value: value, total: total)
            )
        } else {
            quill_qt_progress_bar_set_indeterminate(qtHandle(bar))
        }
        return bar
    }
}

private func qtSanitizedProgressFraction(value: Double, total: Double) -> Double {
    guard value.isFinite, total.isFinite, total > 0 else { return 0 }
    return max(0, min(1, value / total))
}

extension QuillCompatibilityTextSelectionView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        switch selection {
        case .enabled:
            quill_qt_widget_set_text_selectable_recursive(qtHandle(widget), 1)
        case .disabled:
            quill_qt_widget_set_text_selectable_recursive(qtHandle(widget), 0)
        }
        return widget
    }
}

extension QuillCompatibilityOnHoverView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        let captured = getCurrentEnvironment()
        let box = Unmanaged.passRetained(QtBoolClosureBox { hovered in
            let previous = getCurrentEnvironment()
            setCurrentEnvironment(captured)
            defer { setCurrentEnvironment(previous) }
            action(hovered)
        }).toOpaque()

        let callback: quill_qt_bridge_hover_callback = { hovered, userData in
            guard let userData else { return }
            Unmanaged<QtBoolClosureBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .closure(hovered != 0)
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtBoolClosureBox>.fromOpaque(userData).release()
        }

        quill_qt_widget_install_hover_recursive(qtHandle(widget), callback, box, destroy)
        return widget
    }
}

extension QuillCompatibilityAllowsHitTestingView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        if !enabled {
            quill_qt_widget_set_allows_hit_testing_recursive(qtHandle(widget), 0)
        }
        return widget
    }
}

extension QuillCompatibilityContentShapeView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        let container = qtOpaque(quill_qt_bridge_container_create())

        var naturalW: Int32 = 0
        var naturalH: Int32 = 0
        quill_qt_bridge_widget_resolved_size(qtHandle(child), &naturalW, &naturalH)

        quill_qt_bridge_widget_set_fixed_size(qtHandle(container), naturalW, naturalH)
        quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))
        quill_qt_bridge_widget_set_geometry(qtHandle(child), 0, 0, naturalW, naturalH)
        return container
    }
}

extension HelpView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        quill_qt_widget_set_tooltip_recursive(qtHandle(widget), text)
        return widget
    }
}

extension DisabledView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let previous = getCurrentEnvironment()
        var environment = previous
        environment.isEnabled = environment.isEnabled && !isDisabled
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previous) }

        let widget = qtRenderView(content)
        if isDisabled {
            quill_qt_widget_set_enabled_recursive(qtHandle(widget), 0)
        }
        return widget
    }
}

extension FocusedView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        let state = focusState
        let callbackKey = AnyHashable(Int(bitPattern: qtHandle(widget)))

        state.storage.addPlatformFocusCallback(key: callbackKey) { newValue in
            if newValue == true {
                quill_qt_widget_request_focus_recursive(qtHandle(widget))
            } else {
                quill_qt_widget_clear_focus_recursive(qtHandle(widget))
            }
        }

        let box = Unmanaged.passRetained(QtFocusClosureBox(
            focusChanged: { focused in
                if focused {
                    if !state.wrappedValue {
                        state.storage.setValue(true)
                    }
                } else if state.wrappedValue {
                    state.storage.setValue(false)
                }
            },
            destroyed: {
                state.storage.removePlatformFocusCallback(key: callbackKey)
            }
        )).toOpaque()

        let focusChanged: quill_qt_bridge_focus_callback = { focused, userData in
            guard let userData else { return }
            Unmanaged<QtFocusClosureBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .focusChanged(focused != 0)
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            let retained = Unmanaged<QtFocusClosureBox>.fromOpaque(userData)
            retained.takeUnretainedValue().destroyed()
            retained.release()
        }

        quill_qt_widget_install_focus_recursive(qtHandle(widget), focusChanged, box, destroy)
        return widget
    }
}

extension FocusedEqualsView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        let state = focusState
        let matchValue = value
        let callbackKey = AnyHashable(Int(bitPattern: qtHandle(widget)))

        state.storage.addPlatformFocusCallback(key: callbackKey) { newValue in
            if newValue == matchValue {
                quill_qt_widget_request_focus_recursive(qtHandle(widget))
            } else if newValue == nil {
                quill_qt_widget_clear_focus_recursive(qtHandle(widget))
            }
        }

        let box = Unmanaged.passRetained(QtFocusClosureBox(
            focusChanged: { focused in
                if focused {
                    state.storage.setValue(matchValue)
                } else if state.storage.value == matchValue {
                    state.storage.setValue(nil)
                }
            },
            destroyed: {
                state.storage.removePlatformFocusCallback(key: callbackKey)
            }
        )).toOpaque()

        let focusChanged: quill_qt_bridge_focus_callback = { focused, userData in
            guard let userData else { return }
            Unmanaged<QtFocusClosureBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .focusChanged(focused != 0)
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            let retained = Unmanaged<QtFocusClosureBox>.fromOpaque(userData)
            retained.takeUnretainedValue().destroyed()
            retained.release()
        }

        quill_qt_widget_install_focus_recursive(qtHandle(widget), focusChanged, box, destroy)
        return widget
    }
}

extension AccessibilityIdentifierView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        quill_qt_bridge_widget_set_object_name(qtHandle(widget), identifier)
        return widget
    }
}

extension AccessibilityLabelView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        quill_qt_widget_set_accessible_name_recursive(qtHandle(widget), label)
        return widget
    }
}

extension AccessibilityValueView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        quill_qt_widget_set_accessible_description_recursive(qtHandle(widget), value)
        return widget
    }
}

extension AccessibilityHintView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        quill_qt_widget_set_accessible_description_recursive(qtHandle(widget), hint)
        return widget
    }
}

extension AccessibilityElementView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderView(content)
    }
}

extension Button: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let environment = getCurrentEnvironment()
        let title = qtTextLabel(from: label)
        let bound = qtBindActionToCurrentEnvironment(action)
        let box = Unmanaged.passRetained(QtClosureBox(bound)).toOpaque()

        let click: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtClosureBox>.fromOpaque(userData).release()
        }

        let button = qtOpaque(quill_qt_bridge_button_create(title, click, box, destroy))
        if let shortcut = environment.keyboardShortcut {
            qtRegisterKeyboardShortcut(
                shortcut,
                on: button,
                action: action,
                environment: environment
            )
        }
        return button
    }
}

extension KeyboardShortcutView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let previous = getCurrentEnvironment()
        var environment = previous
        environment.keyboardShortcut = shortcut
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previous) }
        return qtRenderView(content)
    }
}

#if QUILLUI_QT_GENERIC
extension MenuBuilder {
    static func buildExpression<Label: View>(_ button: Button<Label>) -> [MenuElement] {
        [.item(label: qtTextLabel(from: button.label), action: button.action)]
    }
}

extension Menu: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let button = qtOpaque(quill_qt_make_menu_button())
        let resolvedTitle: String
        if let labelView {
            let labelText = qtTextLabel(from: labelView.wrapped)
            resolvedTitle = labelText.isEmpty ? title : labelText
        } else {
            resolvedTitle = title
        }
        quill_qt_menu_button_set_text(qtHandle(button), resolvedTitle)
        qtPopulateMenuButton(button, elements: elements)
        quill_qt_menu_button_show_as_popup(qtHandle(button))
        return button
    }
}

private func qtPopulateMenuButton(_ button: OpaquePointer, elements: [MenuElement]) {
    for element in elements {
        switch element {
        case .item(let label, let action):
            qtAddMenuAction(to: button, label: label, action: action)
        case .divider:
            quill_qt_menu_button_add_separator(qtHandle(button))
        case .submenu(_, let children):
            qtPopulateMenuButton(button, elements: children)
        }
    }
}

private func qtAddMenuAction(
    to button: OpaquePointer,
    label: String,
    action: @escaping () -> Void
) {
    let bound = qtBindActionToCurrentEnvironment(action)
    let box = Unmanaged.passRetained(QtClosureBox(bound)).toOpaque()

    let triggered: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QtClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
    }
    let destroy: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QtClosureBox>.fromOpaque(userData).release()
    }

    quill_qt_menu_button_add_action(qtHandle(button), label, triggered, box, destroy)
}

extension TextField: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let environment = getCurrentEnvironment()
        let lineEdit = qtOpaque(quill_qt_make_line_edit())
        quill_qt_line_edit_set_placeholder_text(qtHandle(lineEdit), title)
        quill_qt_line_edit_set_text(qtHandle(lineEdit), text.wrappedValue)

        let binding = text
        let box = Unmanaged.passRetained(QtStringClosureBox { newText in
            if newText != binding.wrappedValue {
                binding.wrappedValue = newText
            }
        }).toOpaque()

        let textChanged: quill_qt_bridge_text_callback = { newText, userData in
            guard let newText, let userData else { return }
            Unmanaged<QtStringClosureBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .closure(String(cString: newText))
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtStringClosureBox>.fromOpaque(userData).release()
        }

        quill_qt_line_edit_connect_text_changed(qtHandle(lineEdit), textChanged, box, destroy)

        if let submitAction = environment.submitAction {
            let submit = qtBindActionToCurrentEnvironment {
                submitAction()
            }
            let submitBox = Unmanaged.passRetained(QtClosureBox(submit)).toOpaque()
            let returnPressed: quill_qt_bridge_click_callback = { userData in
                guard let userData else { return }
                Unmanaged<QtClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
            }
            let submitDestroy: quill_qt_bridge_click_callback = { userData in
                guard let userData else { return }
                Unmanaged<QtClosureBox>.fromOpaque(userData).release()
            }
            quill_qt_line_edit_connect_return_pressed(
                qtHandle(lineEdit),
                returnPressed,
                submitBox,
                submitDestroy
            )
        }

        qtInstallKeyPressActions(
            on: lineEdit,
            actions: environment.keyPressActions,
            environment: environment
        )

        return lineEdit
    }
}

extension OnKeyPressView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let previous = getCurrentEnvironment()
        var environment = previous
        environment.keyPressActions.append(KeyPressAction(key: key, handler: action))
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previous) }
        return qtRenderView(content)
    }
}

extension OnSubmitView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let previous = getCurrentEnvironment()
        var environment = previous
        environment.submitAction = SubmitAction(handler: action)
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previous) }
        return qtRenderView(content)
    }
}

extension Toggle: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let checkBox = qtOpaque(quill_qt_make_check_box())
        quill_qt_check_box_set_text(qtHandle(checkBox), label)
        quill_qt_check_box_set_checked(qtHandle(checkBox), isOn.wrappedValue ? 1 : 0)

        let binding = isOn
        let box = Unmanaged.passRetained(QtBoolClosureBox { newValue in
            if newValue != binding.wrappedValue {
                binding.wrappedValue = newValue
            }
        }).toOpaque()

        let toggled: quill_qt_bridge_toggle_callback = { checked, userData in
            guard let userData else { return }
            Unmanaged<QtBoolClosureBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .closure(checked != 0)
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtBoolClosureBox>.fromOpaque(userData).release()
        }

        quill_qt_check_box_connect_toggled(qtHandle(checkBox), toggled, box, destroy)
        return checkBox
    }
}

extension Picker: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let comboBox = qtOpaque(quill_qt_make_combo_box())
        for option in options {
            quill_qt_combo_box_add_item(qtHandle(comboBox), option)
        }

        let selectedIndex = options.indices.contains(selected)
            ? selected
            : (options.isEmpty ? -1 : 0)
        quill_qt_combo_box_set_current_index(qtHandle(comboBox), Int32(selectedIndex))

        guard let onChanged else {
            return comboBox
        }

        let box = Unmanaged.passRetained(QtIntClosureBox { newIndex in
            guard options.indices.contains(newIndex), newIndex != selected else {
                return
            }
            onChanged(newIndex)
        }).toOpaque()

        let currentIndexChanged: quill_qt_bridge_index_callback = { index, userData in
            guard let userData else { return }
            Unmanaged<QtIntClosureBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .closure(Int(index))
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtIntClosureBox>.fromOpaque(userData).release()
        }

        quill_qt_combo_box_connect_current_index_changed(
            qtHandle(comboBox),
            currentIndexChanged,
            box,
            destroy
        )
        return comboBox
    }
}
#endif

// MARK: - Control-flow view conformances
//
// ViewBuilder lowers `if`/`if-else` to `Optional` and `_ConditionalView`, both
// of which are PrimitiveView with Body == Never (so the generic body-recursion
// path would trap). They must render explicitly, exactly as GTK does. This is
// what makes the smoke's `if isOpen { panel }` toggle work.

extension _ConditionalView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        switch self {
        case .trueContent(let view): return qtRenderView(view)
        case .falseContent(let view): return qtRenderView(view)
        }
    }
}

extension Optional: QtRenderable where Wrapped: View {
    public func qtCreateWidget() -> OpaquePointer {
        switch self {
        case .some(let view):
            return qtRenderView(view)
        case .none:
            let container = qtOpaque(quill_qt_bridge_container_create())
            quill_qt_bridge_widget_set_fixed_size(qtHandle(container), 0, 0)
            return container
        }
    }
}

// MARK: - Container view conformances

extension VStack: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let effectiveSpacing = spacing == stackDefaultSpacing ? 0 : resolveStackSpacing(spacing)
        let children = qtRenderChildren(content)
        return qtRenderVerticalContainer(children, spacing: effectiveSpacing, alignment: alignment)
    }
}

extension HStack: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let effectiveSpacing = resolveStackSpacing(spacing)
        let children = qtRenderChildren(content)
        return qtRenderHorizontalContainer(children, spacing: effectiveSpacing, alignment: alignment)
    }
}

#if QUILLUI_QT_GENERIC
extension ZStack: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let children = qtRenderExpandedChildren(self.children)
        return qtRenderOverlayContainer(children, alignment: alignment)
    }
}

extension LazyVGrid: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let children = items.flatMap { item in
            qtRenderLazyVGridCells(contentBuilder(item))
        }
        return qtRenderLazyVGridContainer(children, gridItems: gridItems)
    }
}
#endif

extension Form: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderVerticalContainer(qtRenderChildren(content), spacing: 8, alignment: .leading)
    }
}

extension ForEach: QtRenderable, QtMultiChildRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderVerticalContainer(qtRenderChildren(), spacing: 0, alignment: .leading)
    }

    public func qtRenderChildren() -> [OpaquePointer] {
        data.map { item in
            qtRenderView(content(item))
        }
    }
}

extension List: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let list = qtOpaque(quill_qt_bridge_list_widget_create())
        for child in qtRenderChildren(content) {
            quill_qt_bridge_list_widget_add_row_widget(qtHandle(list), qtHandle(child))
        }
        return list
    }
}

#if QUILLUI_QT_GENERIC
extension ScrollView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let scroll = qtOpaque(quill_qt_make_scroll_area())
        quill_qt_scroll_area_set_axis(
            qtHandle(scroll),
            axes.contains(.horizontal) ? 1 : 0,
            axes.contains(.vertical) ? 1 : 0
        )

        let child = qtRenderView(content)
        quill_qt_scroll_area_set_widget(qtHandle(scroll), qtHandle(child))
        return scroll
    }
}

extension SheetModifierView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let base = qtRenderView(content)
        guard isPresented.wrappedValue else {
            return base
        }

        let binding = isPresented
        let dismissAction = {
            binding.wrappedValue = false
            onDismiss?()
        }
        let sheet = qtRenderPresentedView(sheetContent(), dismiss: dismissAction)
        let panel = qtRenderPresentationPanel(child: sheet, kind: .sheet)
        return qtRenderPresentationOverlay(
            base: base,
            presented: panel,
            horizontal: .center,
            vertical: .center
        )
    }
}

extension ItemSheetModifierView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let base = qtRenderView(content)
        guard let presentedItem = item.wrappedValue else {
            return base
        }

        let binding = item
        let dismissAction = {
            binding.wrappedValue = nil
            onDismiss?()
        }
        let sheet = qtRenderPresentedView(sheetContent(presentedItem), dismiss: dismissAction)
        let panel = qtRenderPresentationPanel(child: sheet, kind: .sheet)
        return qtRenderPresentationOverlay(
            base: base,
            presented: panel,
            horizontal: .center,
            vertical: .center
        )
    }
}

extension PopoverView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let base = qtRenderView(content)
        guard isPresented.wrappedValue else {
            return base
        }

        let binding = isPresented
        let dismissAction = {
            binding.wrappedValue = false
        }
        let popover = qtRenderPresentedView(popoverContent, dismiss: dismissAction)
        let panel = qtRenderPresentationPanel(child: popover, kind: .popover)
        return qtRenderPresentationOverlay(
            base: base,
            presented: panel,
            horizontal: .center,
            vertical: .top
        )
    }
}
#endif

// MARK: - Frame modifier (slice subset)
//
// `.frame()` is technically a modifier, but FrameView is the load-bearing piece
// for the LAYOUT problem this spike is really about: it is how a SwiftUI tree
// gives an explicit size to an otherwise-intrinsic view (e.g. a Color panel).
// Slice #1 supports the fixed-size and bounded cases via the SHARED
// `computeFrameLayout` engine — the exact code GTK uses — placing the child at
// the computed alignment origin inside a sized QWidget. The full GTK-style
// flexible-axis matrix (parent-driven expansion) is a continuation item.
extension FrameView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)

        var naturalW: Int32 = 0
        var naturalH: Int32 = 0
        quill_qt_bridge_widget_resolved_size(qtHandle(child), &naturalW, &naturalH)

        let childImage = content as? Image
        let expandsWidth = width != nil && (childImage?.isResizable ?? true)
        let expandsHeight = height != nil && (childImage?.isResizable ?? true)

        let layout = computeFrameLayout(
            childNaturalSize: ViewSize(width: Double(naturalW), height: Double(naturalH)),
            width: width,
            height: height,
            minWidth: minWidth,
            minHeight: minHeight,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            alignment: alignment,
            // Color/Rectangle and similar fills expand to fill the frame; the
            // continuation plan reads a real per-view expansion flag. For the
            // slice we preserve SwiftUI's non-resizable Image behavior while
            // keeping explicit frames expansive for existing fill views.
            expandsToFillWidth: expandsWidth,
            expandsToFillHeight: expandsHeight
        )

        let container = qtOpaque(quill_qt_bridge_container_create())
        quill_qt_bridge_widget_set_fixed_size(
            qtHandle(container),
            Int32(layout.containerSize.width),
            Int32(layout.containerSize.height)
        )
        quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))
        quill_qt_bridge_widget_set_geometry(
            qtHandle(child),
            Int32(layout.childPlacement.origin.x),
            Int32(layout.childPlacement.origin.y),
            Int32(layout.childPlacement.size.width),
            Int32(layout.childPlacement.size.height)
        )
        return container
    }
}

extension ContainerRelativeFrameView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderView(
            content.frame(
                maxWidth: axes.contains(.horizontal) ? .infinity : nil,
                maxHeight: axes.contains(.vertical) ? .infinity : nil,
                alignment: alignment
            )
        )
    }
}

// MARK: - Shape views

private func qtColorCSS(_ color: Color) -> String {
    String(format: "rgba(%d, %d, %d, %.3f)",
           Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255), color.alpha)
}

private func qtCreateStyledContainer(_ css: String) -> OpaquePointer {
    let container = qtOpaque(quill_qt_bridge_container_create())
    quill_qt_bridge_widget_set_stylesheet(qtHandle(container), css)
    return container
}

private func qtShapeCSS(_ shape: Any) -> String {
    switch shape {
    case let r as RoundedRectangle: return "border-radius: \(r.cornerRadius)px;"
    case is Circle, is Ellipse, is Capsule: return "border-radius: 50%;"
    default: return ""
    }
}

private func qtFilledShapeColor(from filledShape: Any) -> Color? {
    for child in Mirror(reflecting: filledShape).children
        where child.label == "fill" || child.label == "color" {
        if let c = child.value as? Color { return c }
    }
    return nil
}

private func qtFilledShapeInnerShape(from filledShape: Any) -> Any? {
    Mirror(reflecting: filledShape).children.first { $0.label == "shape" }?.value
}

private func qtGradientStopsCSS(_ stops: [Gradient.Stop]) -> String {
    stops.map { "\(qtColorCSS($0.color)) \(Int($0.location * 100))%" }.joined(separator: ", ")
}

extension Rectangle: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtCreateStyledContainer("background-color: currentColor;")
    }
}

extension RoundedRectangle: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtCreateStyledContainer("background-color: currentColor; border-radius: \(cornerRadius)px;")
    }
}

extension Circle: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtCreateStyledContainer("background-color: currentColor; border-radius: 50%;")
    }
}

extension Ellipse: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtCreateStyledContainer("background-color: currentColor; border-radius: 50%;")
    }
}

extension Capsule: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtCreateStyledContainer("background-color: currentColor; border-radius: 50%;")
    }
}

extension LinearGradient: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        guard !gradient.stops.isEmpty else {
            return qtCreateStyledContainer("background-color: transparent;")
        }
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let angleDeg = Int((atan2(dx, -dy) * 180 / .pi).rounded())
        let stops = qtGradientStopsCSS(gradient.stops)
        return qtCreateStyledContainer("background: linear-gradient(\(angleDeg)deg, \(stops));")
    }
}

extension FilledShape: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let fillCSS = qtFilledShapeColor(from: self)
            .map { "background-color: \(qtColorCSS($0));" }
            ?? "background-color: currentColor;"
        let shapeCSS = qtFilledShapeInnerShape(from: self).map(qtShapeCSS) ?? ""
        return qtCreateStyledContainer("\(fillCSS) \(shapeCSS)")
    }
}

// MARK: - Style modifiers

extension ForegroundColorView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "color: \(color.hex);")
        return child
    }
}

extension OptionalForegroundColorView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        guard let color else {
            return qtRenderView(content)
        }
        return qtRenderView(content.foregroundColor(color))
    }
}

extension FontModifiedView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        let css: String
        switch font {
        case .largeTitle:    css = "font-size: 28px;"
        case .title:         css = "font-size: 24px;"
        case .title2:        css = "font-size: 20px; font-weight: bold;"
        case .title3:        css = "font-size: 18px;"
        case .headline:      css = "font-weight: bold;"
        case .subheadline:   css = "font-size: 12px; font-weight: bold;"
        case .body:          css = "font-size: 14px;"
        case .callout:       css = "font-size: 12px;"
        case .footnote:      css = "font-size: 10px;"
        case .caption:       css = "font-size: 12px;"
        case .caption2:      css = "font-size: 10px; font-weight: bold;"
        case .custom(let size, _, _): css = "font-size: \(Int(size))px;"
        }
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), css)
        return child
    }
}

extension OpacityView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "opacity: \(opacity);")
        return child
    }
}

extension CornerRadiusView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "border-radius: \(Int(radius))px;")
        return child
    }
}

extension HiddenView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_visible(qtHandle(child), 0)
        return child
    }
}

extension BorderView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(
            qtHandle(child), "border: \(width)px solid \(color.hex);")
        return child
    }
}

extension FixedSizeView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

// MARK: - AnyView

extension AnyView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderAnyView(wrapped)
    }
}

// MARK: - Link

extension Link: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let text = title.isEmpty ? qtTextLabel(from: labelView.wrapped) : title
        let box = Unmanaged.passRetained(QtClosureBox({})).toOpaque()
        let click: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtClosureBox>.fromOpaque(userData).release()
        }
        return qtOpaque(quill_qt_bridge_button_create(text, click, box, destroy))
    }
}

// MARK: - Navigation views

private func qtRenderFirstChildOrView<V: View>(_ view: V) -> OpaquePointer {
    if let multi = view as? MultiChildView, let first = multi.children.first {
        return qtRenderAnyView(first)
    }
    return qtRenderView(view)
}

extension NavigationStack: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderFirstChildOrView(content)
    }
}

extension NavigationLink: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let title = label.isEmpty ? qtTextLabel(from: labelView.wrapped) : label
        let box = Unmanaged.passRetained(QtClosureBox({})).toOpaque()
        let click: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtClosureBox>.fromOpaque(userData).takeUnretainedValue().closure()
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtClosureBox>.fromOpaque(userData).release()
        }
        return qtOpaque(quill_qt_bridge_button_create(title, click, box, destroy))
    }
}

extension TabView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let children = tabs.map { tab in qtRenderAnyView(tab.wrapped) }
        return qtRenderVerticalContainer(children, spacing: 0, alignment: .leading)
    }
}

extension Section: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        var children: [OpaquePointer] = []
        if let header, !header.isEmpty {
            children.append(qtRenderView(Text(header)))
        }
        children.append(qtRenderView(content))
        if let footer, !footer.isEmpty {
            children.append(qtRenderView(Text(footer)))
        }
        return qtRenderVerticalContainer(children, spacing: 4, alignment: .leading)
    }
}

// MARK: - Label

extension Label: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        var children: [OpaquePointer] = []
        if let iconName = systemImage {
            children.append(qtRenderView(Image(systemName: iconName)))
        } else if let path = imagePath {
            children.append(qtRenderView(Image(filePath: path)))
        }
        children.append(qtOpaque(quill_qt_bridge_label_create(title)))
        return qtRenderHorizontalContainer(children, spacing: 6, alignment: .center)
    }
}

// MARK: - Lazy stacks

extension LazyVStack: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let children = items.flatMap { item in qtRenderChildren(contentBuilder(item)) }
        return qtRenderVerticalContainer(
            children,
            spacing: resolveStackSpacing(spacing),
            alignment: alignment
        )
    }
}

extension LazyHStack: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let children = items.flatMap { item in qtRenderChildren(contentBuilder(item)) }
        return qtRenderHorizontalContainer(
            children,
            spacing: resolveStackSpacing(spacing),
            alignment: alignment
        )
    }
}

// MARK: - Async / geometry

extension GeometryReader: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderView(content(GeometryProxy(size: CGSize(width: 300, height: 300))))
    }
}

// MARK: - Lifecycle and event views

extension OnAppearView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        qtPostIdleAction(qtBindActionToCurrentEnvironment(action))
        return widget
    }
}

extension OnDisappearView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension TaskView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widget = qtRenderView(content)
        let boundAction = qtBindTaskActionToCurrentEnvironment(action)
        _ = Task(priority: priority) { await boundAction() }
        return widget
    }
}

extension TapGestureView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        // No Qt tap signal yet — pass content through in a wrapper container.
        qtRenderView(content)
    }
}

extension DisclosureGroup: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let labelWidget: OpaquePointer
        if !title.isEmpty {
            labelWidget = qtOpaque(quill_qt_bridge_label_create(title))
            quill_qt_bridge_widget_set_stylesheet(qtHandle(labelWidget), "font-weight: bold;")
        } else if let lv = labelView {
            labelWidget = qtRenderAnyView(lv)
        } else {
            labelWidget = qtOpaque(quill_qt_bridge_label_create(""))
        }
        return qtRenderVerticalContainer(
            [labelWidget, qtRenderView(content)], spacing: 4, alignment: .leading)
    }
}

// MARK: - Core container Qt extensions

// The placeholder SwiftUI substitutes for "the content being modified" inside a
// custom ViewModifier's body. It carries the original view in `wrapped`; render
// straight through to it (mirrors the GTK backend). Without this, every custom
// ViewModifier subtree (e.g. IceCubes' ThemeApplier) dead-ends as an empty
// placeholder.
extension _ViewModifierContent: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderAnyView(wrapped.wrapped)
    }
}

extension ButtonStyleModifier: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let prev = getCurrentEnvironment()
        var env = prev
        env.buttonStyle = style
        setCurrentEnvironment(env)
        let widget = qtRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension CustomButtonStyleModifier: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let prev = getCurrentEnvironment()
        var env = prev
        env.customButtonStyle = style
        setCurrentEnvironment(env)
        let widget = qtRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

// Qt stylesheets have no CSS-transition analogue; render the content and let
// state changes apply immediately (no animated tween).
extension AnimatedView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

// The destination factory is consumed by the navigation system; the modifier is
// transparent to layout, so render the source content straight through.
extension NavigationDestinationModifier: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension Group: QtRenderable where Content: View {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension TupleView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let widgets = children.map { qtRenderAnyView($0) }
        return qtRenderVerticalContainer(widgets, spacing: 0, alignment: .leading)
    }
}

extension Grid: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension GridRow: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension GridCellSpanView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension LazyHGrid: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let children = items.flatMap { item in qtRenderChildren(contentBuilder(item)) }
        return qtRenderHorizontalContainer(children, spacing: 0, alignment: .center)
    }
}

extension EnvironmentObjectModifierView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let prev = getCurrentEnvironment()
        var env = prev
        env.setObject(object)
        setCurrentEnvironment(env)
        let widget = qtRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension EnvironmentObservableModifierView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let prev = getCurrentEnvironment()
        var env = prev
        env.setObject(object)
        setCurrentEnvironment(env)
        let widget = qtRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

// MARK: - Misc modifier Qt extensions

extension BlurView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        if radius > 0 {
            quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "filter: blur(\(radius)px);")
        }
        return child
    }
}

extension ClippedView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "overflow: hidden;")
        return child
    }
}

extension ClipShapeView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "overflow: hidden;")
        return child
    }
}

extension PositionView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        let css = "position: absolute; left: \(Int(x))px; top: \(Int(y))px;"
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), css)
        return child
    }
}

extension LayoutPriorityView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension ToggleStyleModifier: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let prev = getCurrentEnvironment()
        var env = prev
        env.toggleStyle = style
        setCurrentEnvironment(env)
        let widget = qtRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension FocusedValueView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension DropDestinationView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension LongPressGestureView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension StrokedShape: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let r = Int(color.red * 255)
        let g = Int(color.green * 255)
        let b = Int(color.blue * 255)
        let a = String(format: "%.2f", color.alpha)
        let css = "border: 1px solid rgba(\(r),\(g),\(b),\(a));"
        return qtCreateStyledContainer(css)
    }
}

extension FullScreenCoverView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension Stepper: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let spinBox = qtOpaque(
            quill_qt_make_double_spin_box(
                range.lowerBound,
                range.upperBound,
                step
            )
        )
        quill_qt_double_spin_box_set_value(qtHandle(spinBox), value.wrappedValue)

        let binding = value
        let stepValue = step
        let box = Unmanaged.passRetained(QtDoubleClosureBox { newValue in
            if abs(newValue - binding.wrappedValue) > stepValue * 0.01 {
                binding.wrappedValue = newValue
            }
        }).toOpaque()

        let valueChanged: quill_qt_bridge_double_callback = { newValue, userData in
            guard let userData else { return }
            Unmanaged<QtDoubleClosureBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .closure(newValue)
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtDoubleClosureBox>.fromOpaque(userData).release()
        }
        quill_qt_double_spin_box_connect_value_changed(
            qtHandle(spinBox),
            valueChanged,
            box,
            destroy
        )

        guard !label.isEmpty else { return spinBox }
        return qtRenderHorizontalContainer(
            [qtOpaque(quill_qt_bridge_label_create(label)), spinBox],
            spacing: 8,
            alignment: .center
        )
    }
}

extension DatePicker: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let calendar = qtOpaque(quill_qt_make_calendar_widget())
        if let selection {
            let components = selection.wrappedValue
            quill_qt_calendar_select_ymd(
                qtHandle(calendar),
                Int32(components.year),
                Int32(components.month),
                Int32(components.day)
            )
        }

        let binding = selection
        let callback = onChange
        let box = Unmanaged.passRetained(QtDateClosureBox { components in
            if let binding, components != binding.wrappedValue {
                binding.wrappedValue = components
            }
            callback?(components)
        }).toOpaque()

        let selectionChanged: quill_qt_bridge_date_callback = { year, month, day, userData in
            guard let userData else { return }
            let components = SwiftOpenUI.DateComponents(
                year: Int(year),
                month: Int(month),
                day: Int(day)
            )
            Unmanaged<QtDateClosureBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .closure(components)
        }
        let destroy: quill_qt_bridge_click_callback = { userData in
            guard let userData else { return }
            Unmanaged<QtDateClosureBox>.fromOpaque(userData).release()
        }
        quill_qt_calendar_connect_selection_changed(
            qtHandle(calendar),
            selectionChanged,
            box,
            destroy
        )

        guard !title.isEmpty else { return calendar }
        return qtRenderVerticalContainer(
            [qtOpaque(quill_qt_bridge_label_create(title)), calendar],
            spacing: 4,
            alignment: .leading
        )
    }
}

// MARK: - Text modifier Qt extensions

extension FontWeightView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        let cssWeight: Int
        switch weight {
        case .ultraLight: cssWeight = 100
        case .thin:       cssWeight = 200
        case .light:      cssWeight = 300
        case .regular:    cssWeight = 400
        case .medium:     cssWeight = 500
        case .semibold:   cssWeight = 600
        case .bold:       cssWeight = 700
        case .heavy:      cssWeight = 800
        case .black:      cssWeight = 900
        case .none:       cssWeight = 400
        }
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "font-weight: \(cssWeight);")
        return child
    }
}

extension BoldView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "font-weight: bold;")
        return child
    }
}

extension ItalicView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "font-style: italic;")
        return child
    }
}

extension LineLimitView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_apply_line_limit_to_labels(
            qtHandle(child),
            Int32(lineLimit ?? -1)
        )
        return child
    }
}

extension TruncationModeView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        let qtMode: Int32
        switch mode {
        case .head:
            qtMode = 0
        case .tail:
            qtMode = 1
        case .middle:
            qtMode = 2
        }
        quill_qt_bridge_widget_apply_truncation_mode_to_labels(qtHandle(child), qtMode)
        return child
    }
}

extension LineSpacingView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "line-height: calc(1em + \(spacing)px);")
        return child
    }
}

extension MultilineTextAlignmentView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        let cssAlignment: String
        switch alignment {
        case .leading:  cssAlignment = "left"
        case .center:   cssAlignment = "center"
        case .trailing: cssAlignment = "right"
        }
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "text-align: \(cssAlignment);")
        return child
    }
}

extension UnderlineView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(
            qtHandle(child),
            "text-decoration-line: \(isActive ? "underline" : "none");")
        return child
    }
}

extension StrikethroughView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(
            qtHandle(child),
            "text-decoration-line: \(isActive ? "line-through" : "none");")
        return child
    }
}

extension TextCaseView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        let cssTransform: String
        switch textCase {
        case .uppercase?: cssTransform = "uppercase"
        case .lowercase?: cssTransform = "lowercase"
        case nil:         cssTransform = "none"
        }
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "text-transform: \(cssTransform);")
        return child
    }
}

// MARK: - Environment and toolbar Qt extensions

extension EnvironmentModifierView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let prev = getCurrentEnvironment()
        var env = prev
        env[keyPath: keyPath] = value
        setCurrentEnvironment(env)
        let widget = qtRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension ToolbarItem: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderView(content)
    }
}

extension ScrollViewReader: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        qtRenderView(content(ScrollViewProxy()))
    }
}

extension LabelsHiddenView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let prev = getCurrentEnvironment()
        var env = prev
        env.labelsHidden = true
        setCurrentEnvironment(env)
        let widget = qtRenderView(content)
        setCurrentEnvironment(prev)
        return widget
    }
}

extension TagView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension IdView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension ContextMenuView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension ConfirmationDialogView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension SearchableView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

// MARK: - Visual effects Qt extensions

extension RadialGradient: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let cx = Int(center.x * 100)
        let cy = Int(center.y * 100)
        let stops = qtGradientStopsCSS(gradient.stops)
        let css = "background: radial-gradient(circle at \(cx)% \(cy)%, \(stops)); min-height: 20px;"
        return qtCreateStyledContainer(css)
    }
}

extension ScaleEffectView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "transform: scale(\(scaleX), \(scaleY));")
        return child
    }
}

extension RotationView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "transform: rotate(\(angle)deg);")
        return child
    }
}

extension OffsetView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "transform: translate(\(Int(x))px, \(Int(y))px);")
        return child
    }
}

extension ShadowView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        let r = Int(color.red * 255)
        let g = Int(color.green * 255)
        let b = Int(color.blue * 255)
        let a = String(format: "%.2f", color.alpha)
        let css = "box-shadow: \(Int(x))px \(Int(y))px \(Int(radius))px rgba(\(r),\(g),\(b),\(a)); margin: \(Int(radius))px;"
        quill_qt_bridge_widget_set_stylesheet(qtHandle(child), css)
        return child
    }
}

extension AspectRatioView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        if let ratio {
            quill_qt_bridge_widget_set_stylesheet(qtHandle(child), "aspect-ratio: \(ratio);")
        }
        return child
    }
}

extension ViewThatFits: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        if children.isEmpty { return qtOpaque(quill_qt_bridge_container_create()) }
        return qtRenderAnyView(children[0])
    }
}

// MARK: - Modifier pass-throughs

extension TitledView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension ToolbarView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension ToolbarConfigurationView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension AlertModifierView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension BackgroundView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer { qtRenderView(content) }
}

extension PaddedView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let child = qtRenderView(content)
        var childW: Int32 = 0
        var childH: Int32 = 0
        quill_qt_bridge_widget_resolved_size(qtHandle(child), &childW, &childH)
        let container = qtOpaque(quill_qt_bridge_container_create())
        let w = max(0, Int(childW) + leading + trailing)
        let h = max(0, Int(childH) + top + bottom)
        quill_qt_bridge_widget_set_fixed_size(qtHandle(container), Int32(w), Int32(h))
        quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))
        quill_qt_bridge_widget_set_geometry(
            qtHandle(child), Int32(leading), Int32(top), childW, childH)
        return container
    }
}

extension OverlayView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        #if QUILLUI_QT_GENERIC
        return qtRenderOverlayContainer(
            [qtRenderView(content), qtRenderView(overlay)],
            alignment: alignment
        )
        #else
        return qtRenderView(content)
        #endif
    }
}

#endif
