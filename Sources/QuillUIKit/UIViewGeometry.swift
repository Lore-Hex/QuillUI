// UIViewGeometry.swift
// ====================
// Non-overridable UIView geometry helpers: coordinate conversion, system
// layout fitting, and subview z-reordering. Apple declares these on the
// class, but no upstream subclass overrides them, so they live in an
// extension per the module's storage rules (class bodies in QuillUIKit.swift
// — one name, one owner — hold only the members subclasses override or that
// need stored state).
//
// COORDINATE-CONVERSION APPROXIMATIONS (shared by hitTest in
// QuillUIKit.swift, documented once here):
//   * Geometry walks the superview frame chain. A point in a view's own
//     space maps into its superview's space as
//         p + frame.origin − bounds.origin
//     — the bounds term keeps scrolled content (UIScrollView contentOffset
//     expressed through bounds.origin) honest.
//   * `transform` is IGNORED. In this shim `frame` is never re-derived from
//     `transform` (see the property's note in QuillUIKit.swift), so the
//     frame chain is the whole geometric truth; on Apple a transformed
//     ancestor would bend the mapping.
//   * Views in different windows/trees: UIKit routes through the window and
//     screen; the shim treats each tree's root as a shared origin. Exact
//     whenever both views live under one root (every upstream call site);
//     best-effort otherwise.
//   * A nil view argument means "the window/screen" on Apple; here it means
//     root coordinates, which is the same thing for a rooted tree.

import QuillFoundation

#if !os(iOS)

public extension UIView {

    // MARK: - Coordinate conversion

    /// The translation that maps this view's coordinate space into its root
    /// ancestor's space (see the file header for what is and isn't modeled).
    private var quillOffsetFromRoot: CGPoint {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var current: UIView = self
        while let superview = current.superview {
            dx += current.frame.origin.x - current.bounds.origin.x
            dy += current.frame.origin.y - current.bounds.origin.y
            current = superview
        }
        return CGPoint(x: dx, y: dy)
    }

    func convert(_ point: CGPoint, to view: UIView?) -> CGPoint {
        let mine = quillOffsetFromRoot
        let theirs = view?.quillOffsetFromRoot ?? CGPoint(x: 0, y: 0)
        return CGPoint(
            x: point.x + mine.x - theirs.x,
            y: point.y + mine.y - theirs.y
        )
    }

    func convert(_ point: CGPoint, from view: UIView?) -> CGPoint {
        let mine = quillOffsetFromRoot
        let theirs = view?.quillOffsetFromRoot ?? CGPoint(x: 0, y: 0)
        return CGPoint(
            x: point.x + theirs.x - mine.x,
            y: point.y + theirs.y - mine.y
        )
    }

    /// Rect conversion translates the origin and keeps the size: with
    /// transforms out of the model (file header) no conversion can scale or
    /// rotate, so this is exact for everything the shim represents.
    func convert(_ rect: CGRect, to view: UIView?) -> CGRect {
        let origin = convert(rect.origin, to: view)
        return CGRect(x: origin.x, y: origin.y, width: rect.size.width, height: rect.size.height)
    }

    func convert(_ rect: CGRect, from view: UIView?) -> CGRect {
        let origin = convert(rect.origin, from: view)
        return CGRect(x: origin.x, y: origin.y, width: rect.size.width, height: rect.size.height)
    }

    // MARK: - System layout fitting

    /// Apple's "smallest possible size" fitting target (0 × 0).
    static let layoutFittingCompressedSize = CGSize(width: 0, height: 0)
    /// Apple's "largest possible size" fitting target (10000 × 10000).
    static let layoutFittingExpandedSize = CGSize(width: 10_000, height: 10_000)

    // MARK: - Subview z-reordering

    /// Moves an existing subview to the front (end of `subviews`). Not a
    /// child ⇒ no-op, as on Apple.
    func bringSubviewToFront(_ view: UIView) {
        guard let index = subviews.firstIndex(where: { $0 === view }) else { return }
        subviews.remove(at: index)
        subviews.append(view)
        #if os(Linux)
        // Re-adding an attached sublayer moves it to the top (CALayer's
        // addSublayer detaches first).
        layer.addSublayer(view.layer)
        #endif
        quillNotifySubviewMutation()
    }

    /// Moves an existing subview to the back (front of `subviews`). Not a
    /// child ⇒ no-op, as on Apple.
    func sendSubviewToBack(_ view: UIView) {
        guard let index = subviews.firstIndex(where: { $0 === view }) else { return }
        subviews.remove(at: index)
        subviews.insert(view, at: 0)
        #if os(Linux)
        // Order relative to the next view-backed sublayer; stray non-view
        // sublayers keep their stacking (same rationale as insertSubview).
        if let nextViewLayer = subviews.dropFirst().first?.layer {
            layer.insertSublayer(view.layer, below: nextViewLayer)
        }
        #endif
        quillNotifySubviewMutation()
    }
}

#endif // !os(iOS)
