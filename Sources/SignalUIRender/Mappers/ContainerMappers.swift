// SignalUIRender · ContainerMappers
// =================================
// UIKit→GTK4 mappers for the two container shapes Signal-iOS leans on most:
//
//   • UIStackView  → GtkBox (vertical/horizontal), honoring axis, spacing,
//                    alignment (perpendicular axis) and distribution (main
//                    axis) via GtkWidget halign/valign + hexpand/vexpand —
//                    mirroring how SwiftOpenUI's VStack/HStack fallback maps
//                    SwiftUI alignment onto a GtkBox.
//   • UIView (any) → GtkFixed, placing each subview by its explicit frame.
//                    This is the coordinate-layout fallback used wherever a
//                    view positions children with frames rather than a stack.
//
// Both mappers are pure adapters over the FIXED CONTRACT (UIViewGtkMapper /
// UIKitGtkRenderContext / GtkWidgetPtr), which is declared elsewhere in this
// target — we use it here, never redefine it. Children are produced through
// `ctx.render`, never by re-entering UIKit directly, so the registry stays the
// single source of truth for view→widget dispatch.
//
// Registry ordering contract: UIStackViewGtkMapper is MORE specific than
// GenericViewGtkMapper and must be offered to the registry first; the generic
// mapper's `handles` returns `true` and is therefore the last-resort fallback.

import CGTK
import CGTKBridge   // boxPointer(_:): UnsafeMutablePointer<GtkWidget> -> UnsafeMutablePointer<GtkBox>
import Foundation
import QuillUIKit    // UIView, UIStackView, NSLayoutConstraint.Axis

// MARK: - UIStackView → GtkBox

/// Maps a UIStackView onto a GtkBox laid out along the stack's axis.
///
/// Most-specific container mapper: `handles` matches only genuine stack views,
/// so the registry must try this BEFORE the generic UIView fallback.
public enum UIStackViewGtkMapper: UIViewGtkMapper {

    public static func handles(_ view: UIView) -> Bool {
        view is UIStackView
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        // `handles` guarantees the cast; fall back to a fresh GtkBox defensively
        // rather than trapping if the registry ever mis-routes a plain UIView.
        guard let stack = view as? UIStackView else {
            return gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        }

        let isVertical = (stack.axis == .vertical)
        let orientation = isVertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
        let box = gtk_box_new(orientation, gint(stack.spacing))!

        // Distribution governs the MAIN axis (the axis the box stacks along):
        // the "fill" family stretches children to share the run; the spacing
        // families leave them at their natural size and only tune gaps.
        let mainAxisFills: Bool
        let mainAxisExpandsAllChildren: Bool
        switch stack.distribution {
        case .fill, .fillEqually, .fillProportionally:
            mainAxisFills = true
            mainAxisExpandsAllChildren = stack.distribution != .fill
        case .equalSpacing, .equalCentering:
            mainAxisFills = false
            mainAxisExpandsAllChildren = false
        }

        // Alignment governs the PERPENDICULAR axis (cross axis). Map UIKit's
        // members onto a GtkAlign; `.fill` additionally wants the child to
        // expand to fill the cross axis.
        let (crossAlign, crossFills) = crossAxisAlignment(stack.alignment)

        let boxWantsHExpand = appendArrangedSubviews(
            to: box,
            stack: stack,
            isVertical: isVertical,
            mainAxisFills: mainAxisFills,
            mainAxisExpandsAllChildren: mainAxisExpandsAllChildren,
            crossAlign: crossAlign,
            crossFills: crossFills,
            ctx: ctx
        )

        // Propagate only horizontal expansion up so an enclosing container hands
        // the box the window width to fill.
        if boxWantsHExpand { gtk_widget_set_hexpand(box, 1) }

        installStackMutationBridge(on: box, stack: stack, ctx: ctx)
        ctx.applyLayerStyle(box, view)
        return box
    }

    @discardableResult
    private static func appendArrangedSubviews(
        to box: GtkWidgetPtr,
        stack: UIStackView,
        isVertical: Bool,
        mainAxisFills: Bool,
        mainAxisExpandsAllChildren: Bool,
        crossAlign: GtkAlign,
        crossFills: Bool,
        ctx: UIKitGtkRenderContext
    ) -> Bool {
        var boxWantsHExpand = false

        // The VERTICAL axis is unbounded in this renderer (content flows
        // top-to-bottom at natural height — there's no constraint solver to give
        // a stack a fixed height to distribute). So a stack NEVER propagates
        // vexpand: doing so let a cell's vertical label stack balloon its whole
        // section card. Only horizontal fill (the bounded window width) expands.
        for child in stack.arrangedSubviews {
            guard let childWidget = ctx.render(child) else { continue }

            // Honor an explicit fixed size on an arranged subview (e.g. a 56×56
            // avatar): pin the size and DON'T let the distribution stretch it
            // (otherwise a `.fill` row turns the circle into an ellipse). Auto
            // Layout views arrive at .zero and fall through to the expand logic.
            if child.frame.width > 0,
               child.frame.height > 0,
               shouldHonorArrangedSubviewFixedFrame(child) {
                gtk_widget_set_size_request(childWidget, gint(child.frame.width), gint(child.frame.height))
                gtk_widget_set_halign(childWidget, GTK_ALIGN_CENTER)
                gtk_widget_set_valign(childWidget, GTK_ALIGN_CENTER)
                gtk_box_append(boxPointer(box), childWidget)
                continue
            }

            if isVertical {
                // Vertical stack: main = vertical (natural height, top-packed),
                // cross = horizontal.
                gtk_widget_set_valign(childWidget, GTK_ALIGN_START)
                gtk_widget_set_halign(childWidget, crossAlign)
                if crossFills {
                    gtk_widget_set_hexpand(childWidget, 1)
                    boxWantsHExpand = true
                }
            } else {
                // Horizontal stack: main = horizontal (bounded → may fill),
                // cross = vertical (natural height, never vexpand).
                if mainAxisFills,
                   (mainAxisExpandsAllChildren || shouldExpandAlongMainAxis(child, isVertical: isVertical)) {
                    gtk_widget_set_hexpand(childWidget, 1)
                    gtk_widget_set_halign(childWidget, GTK_ALIGN_FILL)
                    boxWantsHExpand = true
                } else {
                    gtk_widget_set_halign(childWidget, GTK_ALIGN_START)
                }
                gtk_widget_set_valign(childWidget, crossFills ? GTK_ALIGN_FILL : crossAlign)
            }

            gtk_box_append(boxPointer(box), childWidget)
        }

        return boxWantsHExpand
    }

    private static func shouldExpandAlongMainAxis(_ child: UIView, isVertical: Bool) -> Bool {
        let axis: NSLayoutConstraint.Axis = isVertical ? .vertical : .horizontal
        return child.contentHuggingPriority(for: axis).rawValue <= NSLayoutConstraint.Priority.defaultLow.rawValue
    }

    private static func shouldHonorArrangedSubviewFixedFrame(_ child: UIView) -> Bool {
        // Signal's Auto Layout pass can measure table-row labels before GTK has
        // allocated the final row width. Keep labels flexible inside stacks so
        // they can consume the remaining horizontal space beside fixed controls.
        if child is UILabel {
            return false
        }
        return true
    }

    private static func installStackMutationBridge(
        on box: GtkWidgetPtr,
        stack: UIStackView,
        ctx: UIKitGtkRenderContext
    ) {
        stack.quillSetSubviewMutationHandler("SignalUIRender.stackChildren") { updatedView in
            guard let updatedStack = updatedView as? UIStackView else { return }
            clearBoxChildren(box)
            let isVertical = (updatedStack.axis == .vertical)
            let mainAxisFills: Bool
            let mainAxisExpandsAllChildren: Bool
            switch updatedStack.distribution {
            case .fill, .fillEqually, .fillProportionally:
                mainAxisFills = true
                mainAxisExpandsAllChildren = updatedStack.distribution != .fill
            case .equalSpacing, .equalCentering:
                mainAxisFills = false
                mainAxisExpandsAllChildren = false
            }
            let (crossAlign, crossFills) = crossAxisAlignment(updatedStack.alignment)
            let boxWantsHExpand = appendArrangedSubviews(
                to: box,
                stack: updatedStack,
                isVertical: isVertical,
                mainAxisFills: mainAxisFills,
                mainAxisExpandsAllChildren: mainAxisExpandsAllChildren,
                crossAlign: crossAlign,
                crossFills: crossFills,
                ctx: ctx
            )
            gtk_widget_set_hexpand(box, boxWantsHExpand ? 1 : 0)
            gtk_widget_queue_resize(box)
        }
    }

    /// Translate a UIStackView.Alignment into a cross-axis GtkAlign plus a flag
    /// for whether the child should expand to fill the cross axis (`.fill`).
    /// Baseline alignments have no GtkBox analogue; approximate first→start and
    /// last→end so text rows still land sensibly.
    private static func crossAxisAlignment(
        _ alignment: UIStackView.Alignment
    ) -> (GtkAlign, Bool) {
        switch alignment {
        case .fill:
            return (GTK_ALIGN_FILL, true)
        case .leading:                 // == .top (shared raw value)
            return (GTK_ALIGN_START, false)
        case .center:
            return (GTK_ALIGN_CENTER, false)
        case .trailing:                // == .bottom (shared raw value)
            return (GTK_ALIGN_END, false)
        case .firstBaseline:
            return (GTK_ALIGN_START, false)
        case .lastBaseline:
            return (GTK_ALIGN_END, false)
        }
    }
}

// MARK: - Generic UIView → GtkFixed

/// Last-resort mapper for any UIView. Lays subviews out by their explicit
/// frames inside a GtkFixed, the GTK widget purpose-built for absolute
/// coordinate placement.
///
/// `handles` returns `true`, so the registry must offer this mapper LAST —
/// after every more-specific mapper (including UIStackViewGtkMapper) has had
/// its chance.
public enum GenericViewGtkMapper: UIViewGtkMapper {

    public static func handles(_ view: UIView) -> Bool {
        true
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        let subviews = view.subviews

        // Auto Layout isn't solved in this renderer (verdict approach A: sidestep
        // the constraint solver). So most views arrive with `.zero` frames. Only
        // use absolute GtkFixed positioning when SOME subview actually carries a
        // real frame; otherwise frame-positioning would collapse everything to
        // (0,0)×0 (invisible). With no usable frames, fall back to a vertical
        // GtkBox so children stack at their natural size and are visible — this is
        // what makes Signal's constraint-built screens (e.g. the table filling its
        // controller view, a cell's label/icon row) actually render.
        let hasRealFrames = subviews.contains { $0.frame.width > 0 && $0.frame.height > 0 }

        if hasRealFrames {
            let fixed = gtk_fixed_new()!
            applyViewSize(to: fixed, from: view)
            appendFixedSubviews(to: fixed, view: view, ctx: ctx)
            installGenericFixedMutationBridge(on: fixed, view: view, ctx: ctx)
            ctx.applyLayerStyle(fixed, view)
            return fixed
        }

        // No-frame fallback: vertical GtkBox. Children fill horizontally and keep
        // their natural height; a scroll/table child is given room to expand.
        // A rounded badge (cornerRadius > 0, e.g. an avatar circle) centers its
        // single content (the initials) instead of top-left filling.
        let isBadge = view.layer.cornerRadius > 0
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        applyViewSize(to: box, from: view)
        for child in subviews {
            guard let childWidget = ctx.render(child) else { continue }
            configureGenericBoxChild(childWidget, for: child, isBadge: isBadge)
            gtk_box_append(boxPointer(box), childWidget)
        }
        installGenericBoxMutationBridge(on: box, view: view, isBadge: isBadge, ctx: ctx)
        ctx.applyLayerStyle(box, view)
        return box
    }

    private static func appendFixedSubviews(
        to fixed: GtkWidgetPtr,
        view: UIView,
        ctx: UIKitGtkRenderContext
    ) {
        let fixedPtr = UnsafeMutableRawPointer(fixed).assumingMemoryBound(to: GtkFixed.self)
        for child in subviewsInLayerOrder(view.subviews) {
            guard let childWidget = ctx.render(child) else { continue }
            let frame = centeredBadgeChildFrame(child.frame, child: child, parent: view)
            gtk_fixed_put(fixedPtr, childWidget, gdouble(frame.origin.x), gdouble(frame.origin.y))
            if frame.width > 0 || frame.height > 0 {
                gtk_widget_set_size_request(
                    childWidget,
                    frame.width > 0 ? gint(frame.width) : -1,
                    frame.height > 0 ? gint(frame.height) : -1
                )
            }
        }
    }

    private static func centeredBadgeChildFrame(_ frame: CGRect, child: UIView, parent: UIView) -> CGRect {
        guard parent.layer.cornerRadius > 0,
              parent.subviews.count == 1,
              child === parent.subviews.first,
              frame.origin == .zero,
              frame.width > 0,
              frame.height > 0 else {
            return frame
        }

        let parentSize = parent.bounds.size != .zero ? parent.bounds.size : parent.frame.size
        guard parentSize.width > 0, parentSize.height > 0 else {
            return frame
        }

        return CGRect(
            x: max(0, (parentSize.width - frame.width) / 2),
            y: max(0, (parentSize.height - frame.height) / 2),
            width: frame.width,
            height: frame.height
        )
    }

    private static func installGenericFixedMutationBridge(
        on fixed: GtkWidgetPtr,
        view: UIView,
        ctx: UIKitGtkRenderContext
    ) {
        view.quillSetSubviewMutationHandler("SignalUIRender.genericFixedChildren") { updatedView in
            clearFixedChildren(fixed)
            appendFixedSubviews(to: fixed, view: updatedView, ctx: ctx)
            gtk_widget_queue_resize(fixed)
        }
    }

    private static func applyViewSize(to widget: GtkWidgetPtr, from view: UIView) {
        let size = view.bounds.size != .zero ? view.bounds.size : view.frame.size
        guard size.width > 0 || size.height > 0 else { return }
        gtk_widget_set_size_request(
            widget,
            size.width > 0 ? gint(size.width) : -1,
            size.height > 0 ? gint(size.height) : -1
        )
        if size.width > 0 {
            gtk_widget_set_hexpand(widget, 1)
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        }
        if size.height > 0 {
            gtk_widget_set_vexpand(widget, 1)
            gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
        }
    }

    private static func subviewsInLayerOrder(_ subviews: [UIView]) -> [UIView] {
        subviews
            .enumerated()
            .sorted { lhs, rhs in
                let lhsZ = lhs.element.layer.zPosition
                let rhsZ = rhs.element.layer.zPosition
                if lhsZ == rhsZ {
                    return lhs.offset < rhs.offset
                }
                return lhsZ < rhsZ
            }
            .map(\.element)
    }

    private static func configureGenericBoxChild(
        _ childWidget: GtkWidgetPtr,
        for child: UIView,
        isBadge: Bool
    ) {
        if isBadge {
            gtk_widget_set_hexpand(childWidget, 1)
            gtk_widget_set_vexpand(childWidget, 1)
            gtk_widget_set_halign(childWidget, GTK_ALIGN_CENTER)
            gtk_widget_set_valign(childWidget, GTK_ALIGN_CENTER)
        } else {
            gtk_widget_set_hexpand(childWidget, 1)
            gtk_widget_set_halign(childWidget, GTK_ALIGN_FILL)
            // Scroll views / tables grow to fill remaining vertical space;
            // plain content keeps its natural height and stacks from the top.
            if child is UIScrollView {
                gtk_widget_set_vexpand(childWidget, 1)
                gtk_widget_set_valign(childWidget, GTK_ALIGN_FILL)
            } else {
                gtk_widget_set_valign(childWidget, GTK_ALIGN_START)
            }
        }
    }

    private static func installGenericBoxMutationBridge(
        on box: GtkWidgetPtr,
        view: UIView,
        isBadge: Bool,
        ctx: UIKitGtkRenderContext
    ) {
        view.quillSetSubviewMutationHandler("SignalUIRender.genericBoxChildren") { updatedView in
            clearBoxChildren(box)
            for child in updatedView.subviews {
                guard let childWidget = ctx.render(child) else { continue }
                configureGenericBoxChild(childWidget, for: child, isBadge: isBadge)
                gtk_box_append(boxPointer(box), childWidget)
            }
            gtk_widget_queue_resize(box)
        }
    }
}

private func clearBoxChildren(_ box: GtkWidgetPtr) {
    while let child = gtk_widget_get_first_child(box) {
        gtk_box_remove(boxPointer(box), child)
    }
}

private func clearFixedChildren(_ fixed: GtkWidgetPtr) {
    let fixedPtr = UnsafeMutableRawPointer(fixed).assumingMemoryBound(to: GtkFixed.self)
    while let child = gtk_widget_get_first_child(fixed) {
        gtk_fixed_remove(fixedPtr, child)
    }
}
