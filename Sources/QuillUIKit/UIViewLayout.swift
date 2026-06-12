// UIViewLayout.swift
// ==================
// UIView Auto Layout surface that needs no stored properties on the class
// body: constraint installation conveniences and the QuillEdgeInsets value
// type backing UIView.layoutMargins. Same shadow-type rules as
// QuillUIKit.swift: UIKit-shaped API, model-level honesty comments where
// Linux has no compositor to consume the values.

import QuillFoundation

#if !os(iOS)

/// Four-edge inset value backing `UIView.layoutMargins` (stored as
/// `UIView.quillLayoutMargins`). QuillUIKit-local on purpose: the public
/// `UIEdgeInsets` is declared in the UIKit shim module, which DEPENDS on this
/// one, so the UIEdgeInsets-typed `layoutMargins` accessor is layered there
/// over this storage. The native layout pass can read margins from here
/// without importing the UIKit shim.
public struct QuillEdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
    public static let zero = QuillEdgeInsets()
}

public extension UIView {
    /// Constraint installation. UIKit tracks constraints per view; this module
    /// keeps one global active list (NSLayoutConstraint.quillActive — see the
    /// rationale on that property), so installing simply means activating.
    func addConstraint(_ constraint: NSLayoutConstraint) {
        constraint.isActive = true
    }

    func addConstraints(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints { constraint.isActive = true }
    }

    func removeConstraint(_ constraint: NSLayoutConstraint) {
        constraint.isActive = false
    }

    func removeConstraints(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints { constraint.isActive = false }
    }

    /// The active constraints anchored on this view (either end), computed
    /// from the global list — which is what callers use the property for
    /// (inspection and selective deactivation).
    var constraints: [NSLayoutConstraint] {
        NSLayoutConstraint.quillActive.filter {
            $0.quillFirstAnchor?.quillItem === self || $0.quillSecondAnchor?.quillItem === self
        }
    }
}

#endif // !os(iOS)
