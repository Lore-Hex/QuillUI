// UIAutoLayout.swift
// ==================
// Auto Layout runtime surface layered over the core types in
// QuillUIKit.swift (NSLayoutConstraint, the anchor family, UILayoutGuide).
// Everything here is API that upstream UIKit code (SignalUI and its
// PureLayout fork) touches at runtime on constraints and guides:
//
//   - NSLayoutConstraint.constant (settable) / .identifier / .multiplier
//   - UILayoutPriority (UIKit's name for NSLayoutConstraint.Priority)
//   - NSLayoutConstraint.Axis: RawRepresentable (UIKit's enum is Int-raw)
//   - UILayoutGuide.layoutFrame
//   - UIView.keyboardLayoutGuide (+ the UIKeyboardLayoutGuide class)
//   - UIScrollView.contentLayoutGuide / .frameLayoutGuide
//
// Storage rules: the classes these members belong to are declared in
// QuillUIKit.swift (one name, one owner), so members that need state use
// side tables keyed by ObjectIdentifier — the established pattern (see
// viewGestureRecognizers in UIGestureRecognizers.swift). Entries are never
// evicted; acceptable for the shim's lifetime, same posture as the gesture
// table.

import QuillFoundation
import QuillKit

#if !os(iOS)

// MARK: - NSLayoutConstraint runtime members

/// Side tables for NSLayoutConstraint's mutable surface. The constraint's
/// captured parameters (quillConstant & co.) are immutable `let`s read by the
/// native layout pass; UIKit's `constant` is settable after creation, so the
/// override lives here. `nonisolated(unsafe)` matches the posture of
/// `NSLayoutConstraint.quillActive`: Auto Layout traffic is main-thread in
/// practice.
nonisolated(unsafe) private var constraintConstantOverrides: [ObjectIdentifier: CGFloat] = [:]
nonisolated(unsafe) private var constraintIdentifiers: [ObjectIdentifier: String] = [:]

extension NSLayoutConstraint {
    /// `constant` — settable, like UIKit. Reads fall back to the value the
    /// constraint was created with (`quillConstant`).
    ///
    /// MODEL HONESTY: the Qt layout pass currently feeds `quillConstant`
    /// (the creation-time value) to the solver, so runtime mutations are
    /// captured here but not yet re-solved. Migrating the pass to read
    /// `constant` instead is a one-line follow-up in
    /// QuillAppKitQt/QuillAppKit+Qt+Layout.swift.
    public var constant: CGFloat {
        get { constraintConstantOverrides[ObjectIdentifier(self)] ?? quillConstant }
        set { constraintConstantOverrides[ObjectIdentifier(self)] = newValue }
    }

    /// Debugging label, `String?` exactly like Apple's.
    public var identifier: String? {
        get { constraintIdentifiers[ObjectIdentifier(self)] }
        set { constraintIdentifiers[ObjectIdentifier(self)] = newValue }
    }

    /// Read-only in UIKit (callers re-create the constraint to change it —
    /// SignalUI's ImageEditorCropViewController documents exactly that).
    public var multiplier: CGFloat { quillMultiplier }
}

/// UIKit's name for the layout-priority type. AppKit spells it
/// `NSLayoutConstraint.Priority`; the underlying struct (Float raw value,
/// `.required` / `.defaultHigh` / `.defaultLow`, +/- arithmetic) is the same.
public typealias UILayoutPriority = NSLayoutConstraint.Priority

// MARK: - NSLayoutConstraint.Axis raw values

/// UIKit's `NSLayoutConstraint.Axis` is an Int-raw enum
/// (UILayoutConstraintAxis: horizontal = 0, vertical = 1). The shim enum in
/// QuillUIKit.swift carries no raw type, so the conformance is layered here —
/// upstream code switches on it with `@unknown default` and logs
/// `self.rawValue` (OWSStackView).
extension NSLayoutConstraint.Axis: RawRepresentable {
    public typealias RawValue = Int

    public init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .horizontal
        case 1: self = .vertical
        default: return nil
        }
    }

    public var rawValue: Int {
        switch self {
        case .horizontal: return 0
        case .vertical: return 1
        }
    }
}

// MARK: - UILayoutGuide.layoutFrame

extension UILayoutGuide {
    /// The guide's frame in its owning view's coordinate system.
    ///
    /// MODEL HONESTY: there is no constraint solve to read back on Linux, so
    /// this is computed from the guide's binding instead:
    ///   - keyboard guides report a zero-height strip at the view's bottom
    ///     (no on-screen keyboard on QuillOS — "keyboard hidden", which makes
    ///     upstream visibility checks like Toast's height comparison correct);
    ///   - view-aliased guides (safe area / layout margins / scroll-view
    ///     guides) ARE the view on Linux, so they report its bounds;
    ///   - free-standing guides approximate with the owning view's bounds
    ///     (their constraints are captured but not solved — see
    ///     UILayoutGuide.quillAliasedView).
    public var layoutFrame: CGRect {
        if let keyboardGuide = self as? UIKeyboardLayoutGuide {
            return keyboardGuide.quillKeyboardLayoutFrame
        }
        if let aliased = quillAliasedView {
            return aliased.bounds
        }
        return owningView?.bounds ?? .zero
    }
}

// MARK: - UIKeyboardLayoutGuide / UIView.keyboardLayoutGuide

/// `UIView.keyboardLayoutGuide`'s class. On QuillOS there is no on-screen
/// keyboard, so the guide models the keyboard permanently hidden: a
/// zero-height, full-width strip sitting on the owning view's bottom edge.
/// Pinning content above `keyboardLayoutGuide.topAnchor` (the dominant
/// upstream pattern) therefore pins it to the view's bottom — exactly where
/// it belongs with no keyboard up.
///
/// X-axis and width anchors come from the view alias (full width); the
/// Y-axis anchors are overridden to the BOTTOM edge.
@MainActor public class UIKeyboardLayoutGuide: UILayoutGuide {
    /// iOS 15: whether the guide tracks an undocked/floating keyboard.
    /// Stored faithfully; nothing floats on QuillOS.
    public var followsUndockedKeyboard: Bool = false

    /// iOS 17: whether the guide's hidden-keyboard position respects the
    /// bottom safe area. The safe area IS the view's bounds on Linux, so
    /// both settings resolve to the same geometry; stored faithfully.
    public var usesBottomSafeArea: Bool = true

    private var quillBottomEdgeItem: AnyObject { owningView ?? self }

    public override var topAnchor: NSLayoutYAxisAnchor {
        NSLayoutYAxisAnchor(item: quillBottomEdgeItem, attribute: .bottom)
    }
    public override var bottomAnchor: NSLayoutYAxisAnchor {
        NSLayoutYAxisAnchor(item: quillBottomEdgeItem, attribute: .bottom)
    }
    public override var centerYAnchor: NSLayoutYAxisAnchor {
        NSLayoutYAxisAnchor(item: quillBottomEdgeItem, attribute: .bottom)
    }
    /// Bound to the guide itself, NOT the aliased view: the guide's height is
    /// zero (keyboard hidden), and the inherited alias would report the
    /// view's full height. Constraints against it are captured but inert
    /// (the layout pass skips items it cannot resolve to a view).
    public override var heightAnchor: NSLayoutDimension {
        NSLayoutDimension(item: self, attribute: .height)
    }

    /// Zero-height strip on the owning view's bottom edge ("keyboard
    /// hidden"), read by UILayoutGuide.layoutFrame.
    fileprivate var quillKeyboardLayoutFrame: CGRect {
        guard let view = owningView else { return .zero }
        let bounds = view.bounds
        return CGRect(x: bounds.minX, y: bounds.maxY, width: bounds.width, height: 0)
    }
}

/// Side table: view → its lazily-created keyboard guide (UIView's stored
/// properties live in QuillUIKit.swift, which this file must not touch).
@MainActor private var viewKeyboardLayoutGuides: [ObjectIdentifier: UIKeyboardLayoutGuide] = [:]

extension UIView {
    /// Lazily created per view, stable identity across accesses (upstream
    /// stores constraints against it). Aliased to the view the same way the
    /// safe-area and margins guides are (see quillMakeEdgeAliasedGuide), with
    /// the Y-axis behavior provided by UIKeyboardLayoutGuide's overrides.
    public var keyboardLayoutGuide: UIKeyboardLayoutGuide {
        if let existing = viewKeyboardLayoutGuides[ObjectIdentifier(self)] {
            return existing
        }
        let guide = UIKeyboardLayoutGuide()
        guide.identifier = "UIViewKeyboardLayoutGuide"
        guide.owningView = self
        guide.quillAliasedView = self
        viewKeyboardLayoutGuides[ObjectIdentifier(self)] = guide
        return guide
    }
}

// MARK: - UIScrollView layout guides

/// Side tables: scroll view → its lazily-created guides (UIScrollView is
/// declared in QuillUIKit.swift; same storage rule as above).
@MainActor private var scrollViewContentLayoutGuides: [ObjectIdentifier: UILayoutGuide] = [:]
@MainActor private var scrollViewFrameLayoutGuides: [ObjectIdentifier: UILayoutGuide] = [:]

extension UIScrollView {
    /// MODEL HONESTY: QuillUIKit's UIScrollView does not model a scrollable
    /// content region (no compositor scrolls anything yet), so BOTH guides
    /// alias the scroll view itself — content area == viewport. Constraints
    /// pinning content to `contentLayoutGuide` and sizing it against
    /// `frameLayoutGuide` (the canonical UIKit idiom) stay solvable and make
    /// the content fill the visible rect. Stable identity per scroll view,
    /// like UIKit.

    /// The content area. Apple's identifier string is kept verbatim.
    public var contentLayoutGuide: UILayoutGuide {
        if let existing = scrollViewContentLayoutGuides[ObjectIdentifier(self)] {
            return existing
        }
        let guide = quillMakeScrollGuide(identifier: "UIScrollView-contentLayoutGuide")
        scrollViewContentLayoutGuides[ObjectIdentifier(self)] = guide
        return guide
    }

    /// The untransformed frame rect. Apple's identifier string is kept
    /// verbatim.
    public var frameLayoutGuide: UILayoutGuide {
        if let existing = scrollViewFrameLayoutGuides[ObjectIdentifier(self)] {
            return existing
        }
        let guide = quillMakeScrollGuide(identifier: "UIScrollView-frameLayoutGuide")
        scrollViewFrameLayoutGuides[ObjectIdentifier(self)] = guide
        return guide
    }

    private func quillMakeScrollGuide(identifier: String) -> UILayoutGuide {
        let guide = UILayoutGuide()
        guide.identifier = identifier
        guide.owningView = self
        guide.quillAliasedView = self
        return guide
    }
}

#endif // !os(iOS)
