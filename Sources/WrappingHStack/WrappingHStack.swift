import SwiftUI
#if os(Linux) && canImport(BackendGTK4) && canImport(CGTK) && canImport(CGTKBridge)
import BackendGTK4
import CGTK
import CGTKBridge
#endif

@_spi(QuillTesting) public enum QuillWrappingHStackAlignment: Equatable {
    case leading
    case center
    case trailing
}

public struct WrappingHStack<Content: View>: View, MultiChildView {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    // Convenience initializer mirroring the upstream WrappingHStack signature
    // that takes `Int?` for spacing — keep source compat for callers using
    // either Int or CGFloat literal arguments.
    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int?,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing.map { CGFloat($0) }
        self.content = content()
    }

    public var body: some View {
        // SwiftOpenUI's `HStack(spacing:)` takes `Int?` on Linux
        // while real SwiftUI takes `CGFloat?`. Coerce to keep the
        // public `spacing: CGFloat?` API stable for both backends.
        #if os(Linux)
        let resolvedSpacing: Int = spacing.map { Int($0) } ?? 8
        #else
        let resolvedSpacing: CGFloat = spacing ?? 8
        #endif
        return HStack(alignment: .center, spacing: resolvedSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }

    // nonisolated: MultiChildView's requirement is nonisolated and this is a
    // pure stored-data traversal; keeps the conformance non-crossing now that
    // View conformers are type-isolated (whole-protocol isolation).
    nonisolated public var children: [any View] {
        if let multi = content as? MultiChildView {
            return multi.children
        }
        return [content]
    }

    @_spi(QuillTesting) public var quillResolvedSpacing: Int {
        spacing.map { max(0, Int($0.rounded())) } ?? 8
    }

    @_spi(QuillTesting) public var quillResolvedAlignment: QuillWrappingHStackAlignment {
        switch alignment {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        default:
            return .center
        }
    }
}

#if os(Linux) && canImport(BackendGTK4) && canImport(CGTK) && canImport(CGTKBridge)
extension WrappingHStack: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "WrappingHStack",
            children: children.map(gtkDescribeAnyView)
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let flow = gtk_swift_flow_box_new()!
        let resolvedSpacing = quillResolvedSpacing

        gtk_swift_flow_box_configure(flow, guint(resolvedSpacing))

        switch quillResolvedAlignment {
        case .leading:
            gtk_widget_set_halign(flow, GTK_ALIGN_START)
        case .center:
            gtk_widget_set_halign(flow, GTK_ALIGN_CENTER)
        case .trailing:
            gtk_widget_set_halign(flow, GTK_ALIGN_END)
        }
        gtk_widget_set_valign(flow, GTK_ALIGN_START)
        gtk_widget_set_hexpand(flow, 1)

        for child in children {
            let widget = widgetFromOpaque(gtkRenderAnyView(child))
            gtk_widget_set_hexpand(widget, 0)
            gtk_widget_set_halign(widget, GTK_ALIGN_START)
            gtk_widget_set_valign(widget, GTK_ALIGN_START)
            gtk_swift_flow_box_insert(flow, widget)
        }

        return opaqueFromWidget(flow)
    }
}
#endif
