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

final class QtMoveCommandActionBox {
    let environment: EnvironmentValues
    let action: (MoveCommandDirection) -> Void

    init(environment: EnvironmentValues, action: @escaping (MoveCommandDirection) -> Void) {
        self.environment = environment
        self.action = action
    }

    func handle(keyCode: Int32) -> Bool {
        guard let direction = qtMoveCommandDirection(for: keyCode) else { return false }
        let previous = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previous) }
        action(direction)
        return true
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

func qtKeyEquivalent(for keyCode: Int32) -> KeyEquivalent? {
    guard let scalar = UnicodeScalar(UInt32(bitPattern: keyCode)) else { return nil }
    return KeyEquivalent(Character(scalar))
}

func qtMoveCommandDirection(for keyCode: Int32) -> MoveCommandDirection? {
    switch qtKeyEquivalent(for: keyCode) {
    case .upArrow:
        return .up
    case .downArrow:
        return .down
    case .leftArrow:
        return .left
    case .rightArrow:
        return .right
    default:
        return nil
    }
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

func qtInstallMoveCommandAction(
    on widget: OpaquePointer,
    environment: EnvironmentValues,
    action: @escaping (MoveCommandDirection) -> Void
) {
    let box = Unmanaged.passRetained(QtMoveCommandActionBox(
        environment: environment,
        action: action
    )).toOpaque()
    let callback: quill_qt_bridge_key_callback = { key, userData in
        guard let userData else { return 0 }
        return Unmanaged<QtMoveCommandActionBox>
            .fromOpaque(userData)
            .takeUnretainedValue()
            .handle(keyCode: key) ? 1 : 0
    }
    let destroy: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QtMoveCommandActionBox>.fromOpaque(userData).release()
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

extension MoveCommandView: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        let environment = getCurrentEnvironment()
        let widget = qtRenderView(content)
        qtInstallMoveCommandAction(on: widget, environment: environment, action: action)
        return widget
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

#endif
