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

    // Stateless composite view — recurse through body.
    return qtRenderView(view.body)
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
    if let transparent = view as? TransparentMultiChildView {
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
        if let transparent = child as? TransparentMultiChildView {
            return qtRenderExpandedChildren(transparent.children)
        }
        return [qtRenderAnyView(child)]
    }
}

/// Wrap a reactive composite view in a QtViewHost and return its container.
func qtRenderStatefulView<V: View>(_ view: V) -> OpaquePointer {
    let host = QtViewHost { qtRenderView(view.body) }
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
        quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))
        quill_qt_bridge_widget_set_geometry(
            qtHandle(child),
            Int32(placement.origin.x),
            Int32(placement.origin.y),
            Int32(placement.size.width),
            Int32(placement.size.height)
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
        quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))
        quill_qt_bridge_widget_set_geometry(
            qtHandle(child),
            Int32(placement.origin.x),
            Int32(placement.origin.y),
            Int32(placement.size.width),
            Int32(placement.size.height)
        )
    }
    return container
}

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

extension Button: QtRenderable {
    public func qtCreateWidget() -> OpaquePointer {
        // Slice #1 supports the common Button(_:action:) shape (Text label).
        // Custom label views render through the generic path in a later slice.
        let title: String
        if let text = label as? Text {
            title = text.content
        } else {
            title = ""
        }

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

        return qtOpaque(quill_qt_bridge_button_create(title, click, box, destroy))
    }
}

#if QUILLUI_QT_GENERIC
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
