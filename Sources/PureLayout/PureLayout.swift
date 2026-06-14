// PureLayout -- Linux shim for compiling Signal-iOS SignalUI against QuillUI (QuillOS).
// Symbols are added on demand as the SignalUI compile reports missing API.
//
// Faithful Swift surface of PureLayout v3 (Signal builds against the signalapp
// fork, which adds `autoPinEdge(toSuperviewMargin:withInset:)` and
// `autoPinEdgesToSuperviewMargins(with:)` on top of upstream). Signatures and
// semantics mirror the real library: every `auto*` method sets
// `translatesAutoresizingMaskIntoConstraints = false` on the receiver, builds a
// REAL `NSLayoutConstraint` through QuillUIKit's anchor factories, installs it
// (`isActive = true`, honoring `NSLayoutConstraint.autoSetPriority` scopes) and
// returns it. Bottom/right/trailing insets and inequality relations are
// inverted exactly like PureLayout's `autoPinEdgeToSuperviewEdge:withInset:
// relation:`, so a positive inset always moves the view INTO its superview.
//
// SignalUI's own UIView+AutoLayout.swift layers Signal-specific helpers
// (autoPinWidthToSuperview, autoHCenterInSuperview, ...) on top of these
// primitives -- those are intentionally NOT defined here.
import Foundation
import UIKit

// MARK: - ALEdge / ALAxis / ALDimension / ALAttribute

/// PureLayout's edge enum (raw ObjC values track NSLayoutAttribute; SignalUI
/// only ever uses the cases by name, so no raw values are modeled).
public enum ALEdge: Sendable {
    case left, right, top, bottom, leading, trailing
}

/// PureLayout's axis enum. NOTE the inherited UIKit vocabulary: `.vertical` is
/// the vertical center LINE (centerX attribute) and `.horizontal` the
/// horizontal one (centerY attribute).
public enum ALAxis: Sendable {
    case vertical, horizontal, baseline, firstBaseline

    /// PureLayout aliases ALAxisLastBaseline == ALAxisBaseline.
    public static var lastBaseline: ALAxis { .baseline }
}

public enum ALDimension: Sendable {
    case width, height
}

/// PureLayout's combined attribute enum (edges + axes + dimensions), used by
/// `autoConstrainAttribute(_:to:of:...)`. Margin attributes are omitted until
/// a call site needs them (QuillUIKit does not model layoutMargins yet).
public enum ALAttribute: Sendable {
    case left, right, top, bottom, leading, trailing
    case width, height
    case vertical, horizontal, baseline, firstBaseline

    /// PureLayout aliases ALAttributeLastBaseline == ALAttributeBaseline.
    public static var lastBaseline: ALAttribute { .baseline }
}

// MARK: - Attribute -> QuillUIKit anchor mapping

/// Which anchor family an attribute belongs to. Apple encodes this in the
/// `NSLayoutAnchor` phantom type; PureLayout (and this shim) perform the
/// classification at runtime instead.
private enum QuillALAttributeKind {
    case xPosition, yPosition, dimension
}

extension ALEdge {
    fileprivate var quillAttribute: QuillLayoutAttribute {
        switch self {
        case .left: return .left
        case .right: return .right
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    fileprivate var quillKind: QuillALAttributeKind {
        switch self {
        case .top, .bottom: return .yPosition
        case .left, .right, .leading, .trailing: return .xPosition
        }
    }

    /// PureLayout inverts the inset (and any inequality relation) for these
    /// edges so positive insets are always inward.
    fileprivate var quillInsetIsInverted: Bool {
        switch self {
        case .bottom, .right, .trailing: return true
        case .top, .left, .leading: return false
        }
    }
}

extension ALAxis {
    fileprivate var quillAttribute: QuillLayoutAttribute {
        switch self {
        case .vertical: return .centerX
        case .horizontal: return .centerY
        case .baseline: return .lastBaseline
        case .firstBaseline: return .firstBaseline
        }
    }

    fileprivate var quillKind: QuillALAttributeKind {
        switch self {
        case .vertical: return .xPosition
        case .horizontal, .baseline, .firstBaseline: return .yPosition
        }
    }
}

extension ALDimension {
    fileprivate var quillAttribute: QuillLayoutAttribute {
        switch self {
        case .width: return .width
        case .height: return .height
        }
    }
}

extension ALAttribute {
    fileprivate var quillAttribute: QuillLayoutAttribute {
        switch self {
        case .left: return .left
        case .right: return .right
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        case .width: return .width
        case .height: return .height
        case .vertical: return .centerX
        case .horizontal: return .centerY
        case .baseline: return .lastBaseline
        case .firstBaseline: return .firstBaseline
        }
    }

    fileprivate var quillKind: QuillALAttributeKind {
        switch self {
        case .left, .right, .leading, .trailing, .vertical: return .xPosition
        case .top, .bottom, .horizontal, .baseline, .firstBaseline: return .yPosition
        case .width, .height: return .dimension
        }
    }
}

extension NSLayoutConstraint.Relation {
    fileprivate var quillInverse: NSLayoutConstraint.Relation {
        switch self {
        case .equal: return .equal
        case .lessThanOrEqual: return .greaterThanOrEqual
        case .greaterThanOrEqual: return .lessThanOrEqual
        }
    }
}

// MARK: - Constraint builders

/// Builds `first <relation> second + constant` through QuillUIKit's public
/// anchor factories (multiplier is fixed at 1, matching Apple's x/y-anchor API).
private func quillRelate<AnchorType>(
    _ first: NSLayoutAnchor<AnchorType>,
    _ relation: NSLayoutConstraint.Relation,
    _ second: NSLayoutAnchor<AnchorType>,
    constant: CGFloat
) -> NSLayoutConstraint {
    switch relation {
    case .equal:
        return first.constraint(equalTo: second, constant: constant)
    case .greaterThanOrEqual:
        return first.constraint(greaterThanOrEqualTo: second, constant: constant)
    case .lessThanOrEqual:
        return first.constraint(lessThanOrEqualTo: second, constant: constant)
    }
}

/// Position (edge/axis) constraint between two views. Anchors are created here
/// with the precise item+attribute binding the native layout pass reads; the
/// concrete X/Y anchor subclass is chosen from the attribute kind (Apple's
/// phantom-typed anchors enforce this at compile time, PureLayout at runtime).
private func quillPositionConstraint(
    from item: AnyObject,
    attribute: QuillLayoutAttribute,
    kind: QuillALAttributeKind,
    relation: NSLayoutConstraint.Relation,
    to otherItem: AnyObject,
    otherAttribute: QuillLayoutAttribute,
    constant: CGFloat
) -> NSLayoutConstraint {
    switch kind {
    case .xPosition:
        return quillRelate(
            NSLayoutXAxisAnchor(item: item, attribute: attribute),
            relation,
            NSLayoutXAxisAnchor(item: otherItem, attribute: otherAttribute),
            constant: constant
        )
    case .yPosition:
        return quillRelate(
            NSLayoutYAxisAnchor(item: item, attribute: attribute),
            relation,
            NSLayoutYAxisAnchor(item: otherItem, attribute: otherAttribute),
            constant: constant
        )
    case .dimension:
        return quillRelate(
            NSLayoutDimension(item: item, attribute: attribute),
            relation,
            NSLayoutDimension(item: otherItem, attribute: otherAttribute),
            constant: constant
        )
    }
}

// MARK: - NSLayoutConstraint + PureLayout

extension NSLayoutConstraint {
    /// PureLayout's global priority scope. Constraints INSTALLED while a
    /// `autoSetPriority(_:forConstraints:)` block is running pick up the scoped
    /// priority (the real library applies its global state in `-autoInstall`).
    /// `nonisolated(unsafe)` matches `quillActive`'s posture in QuillUIKit:
    /// Auto Layout traffic is main-thread in practice.
    nonisolated(unsafe) fileprivate static var quillAutoPriorityStack: [NSLayoutConstraint.Priority] = []

    /// `+[NSLayoutConstraint autoSetPriority:forConstraints:]`. All PureLayout
    /// constraints created inside `block` get `priority`.
    public static func autoSetPriority(_ priority: NSLayoutConstraint.Priority, forConstraints block: () -> Void) {
        quillAutoPriorityStack.append(priority)
        defer { quillAutoPriorityStack.removeLast() }
        block()
    }

    /// `-[NSLayoutConstraint autoInstall]`: applies any scoped priority, then
    /// activates the constraint.
    public func autoInstall() {
        if let scopedPriority = NSLayoutConstraint.quillAutoPriorityStack.last {
            priority = scopedPriority
        }
        isActive = true
    }

    /// `-[NSLayoutConstraint autoRemove]`: deactivates the constraint.
    public func autoRemove() {
        isActive = false
    }
}

// MARK: - UIView + PureLayout

extension UIView {

    /// PureLayout NSAsserts a non-nil superview before pinning to it; mirror
    /// that contract instead of silently returning a dummy constraint.
    private var quillALSuperview: UIView {
        guard let superview = superview else {
            preconditionFailure("PureLayout: view's superview must not be nil when pinning to it")
        }
        return superview
    }

    // MARK: Superview edges

    @discardableResult
    public func autoPinEdgesToSuperviewEdges(with insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        return [
            autoPinEdge(toSuperviewEdge: .top, withInset: insets.top),
            autoPinEdge(toSuperviewEdge: .leading, withInset: insets.left),
            autoPinEdge(toSuperviewEdge: .bottom, withInset: insets.bottom),
            autoPinEdge(toSuperviewEdge: .trailing, withInset: insets.right),
        ]
    }

    /// Signal call sites pass a bare `CGFloat` inset (a uniform inset on all
    /// four edges); PureLayout itself only takes `UIEdgeInsets`, so add the
    /// convenience overload that wraps the scalar in a uniform inset.
    @discardableResult
    public func autoPinEdgesToSuperviewEdges(withInset inset: CGFloat) -> [NSLayoutConstraint] {
        return autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset))
    }

    @discardableResult
    public func autoPinEdgesToSuperviewEdges(with insets: UIEdgeInsets, excludingEdge edge: ALEdge) -> [NSLayoutConstraint] {
        var constraints: [NSLayoutConstraint] = []
        if edge != .top {
            constraints.append(autoPinEdge(toSuperviewEdge: .top, withInset: insets.top))
        }
        if edge != .leading && edge != .left {
            constraints.append(autoPinEdge(toSuperviewEdge: .leading, withInset: insets.left))
        }
        if edge != .bottom {
            constraints.append(autoPinEdge(toSuperviewEdge: .bottom, withInset: insets.bottom))
        }
        if edge != .trailing && edge != .right {
            constraints.append(autoPinEdge(toSuperviewEdge: .trailing, withInset: insets.right))
        }
        return constraints
    }

    @discardableResult
    public func autoPinEdge(toSuperviewEdge edge: ALEdge, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewEdge: edge, withInset: inset, relation: .equal)
    }

    @discardableResult
    public func autoPinEdge(toSuperviewEdge edge: ALEdge, withInset inset: CGFloat, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        // Bottom/right/trailing insets (and inequality relations) are inverted
        // to become offsets -- verbatim PureLayout behavior.
        var offset = inset
        var relation = relation
        if edge.quillInsetIsInverted {
            offset = -inset
            relation = relation.quillInverse
        }
        return autoPinEdge(edge, to: edge, of: quillALSuperview, withOffset: offset, relation: relation)
    }

    // MARK: Superview margins / safe area
    //
    // MODEL HONESTY: QuillUIKit's UIView does not model layoutMargins or
    // safeAreaInsets yet -- on QuillOS windows are plain rectangles (no notch,
    // no home indicator) and margin insets default to zero. Margin- and
    // safe-area-pinning therefore resolve to the superview's EDGES, keeping
    // PureLayout's constraint shape (inset/relation inversion, return types)
    // so upstream call sites compile and the layout stays solvable.

    /// The `with:` variant matches Signal's PureLayout fork; upstream
    /// PureLayout only has the parameterless form.
    @discardableResult
    public func autoPinEdgesToSuperviewMargins(with insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        return [
            autoPinEdge(toSuperviewMargin: .top, withInset: insets.top),
            autoPinEdge(toSuperviewMargin: .leading, withInset: insets.left),
            autoPinEdge(toSuperviewMargin: .bottom, withInset: insets.bottom),
            autoPinEdge(toSuperviewMargin: .trailing, withInset: insets.right),
        ]
    }

    @discardableResult
    public func autoPinEdgesToSuperviewMargins(excludingEdge edge: ALEdge) -> [NSLayoutConstraint] {
        var constraints: [NSLayoutConstraint] = []
        if edge != .top {
            constraints.append(autoPinEdge(toSuperviewMargin: .top))
        }
        if edge != .leading && edge != .left {
            constraints.append(autoPinEdge(toSuperviewMargin: .leading))
        }
        if edge != .bottom {
            constraints.append(autoPinEdge(toSuperviewMargin: .bottom))
        }
        if edge != .trailing && edge != .right {
            constraints.append(autoPinEdge(toSuperviewMargin: .trailing))
        }
        return constraints
    }

    /// The `withInset:` parameter matches Signal's PureLayout fork (upstream
    /// has only the bare and `relation:` forms).
    @discardableResult
    public func autoPinEdge(toSuperviewMargin edge: ALEdge, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewEdge: edge, withInset: inset)
    }

    @discardableResult
    public func autoPinEdge(toSuperviewMargin edge: ALEdge, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewEdge: edge, withInset: 0, relation: relation)
    }

    /// Signal's PureLayout fork exposes the inset+relation margin form too.
    /// With zero-modeled layout margins this resolves to the superview edge,
    /// preserving inset/relation-inversion semantics.
    @discardableResult
    public func autoPinEdge(toSuperviewMargin edge: ALEdge, withInset inset: CGFloat, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewEdge: edge, withInset: inset, relation: relation)
    }

    @discardableResult
    public func autoPinEdgesToSuperviewMargins(with insets: UIEdgeInsets, excludingEdge edge: ALEdge) -> [NSLayoutConstraint] {
        var constraints: [NSLayoutConstraint] = []
        if edge != .top {
            constraints.append(autoPinEdge(toSuperviewMargin: .top, withInset: insets.top))
        }
        if edge != .leading && edge != .left {
            constraints.append(autoPinEdge(toSuperviewMargin: .leading, withInset: insets.left))
        }
        if edge != .bottom {
            constraints.append(autoPinEdge(toSuperviewMargin: .bottom, withInset: insets.bottom))
        }
        if edge != .trailing && edge != .right {
            constraints.append(autoPinEdge(toSuperviewMargin: .trailing, withInset: insets.right))
        }
        return constraints
    }

    @discardableResult
    public func autoPinEdgesToSuperviewSafeArea(with insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        return autoPinEdgesToSuperviewEdges(with: insets)
    }

    @discardableResult
    public func autoPinEdgesToSuperviewSafeArea(with insets: UIEdgeInsets, excludingEdge edge: ALEdge) -> [NSLayoutConstraint] {
        return autoPinEdgesToSuperviewEdges(with: insets, excludingEdge: edge)
    }

    @discardableResult
    public func autoPinEdge(toSuperviewSafeArea edge: ALEdge, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewEdge: edge, withInset: inset)
    }

    @discardableResult
    public func autoPinEdge(toSuperviewSafeArea edge: ALEdge, withInset inset: CGFloat, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        return autoPinEdge(toSuperviewEdge: edge, withInset: inset, relation: relation)
    }

    // MARK: Edge to edge of another view

    @discardableResult
    public func autoPinEdge(_ edge: ALEdge, to toEdge: ALEdge, of otherView: UIView, withOffset offset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(edge, to: toEdge, of: otherView, withOffset: offset, relation: .equal)
    }

    @discardableResult
    public func autoPinEdge(_ edge: ALEdge, to toEdge: ALEdge, of otherView: UIView, withOffset offset: CGFloat, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        guard edge.quillKind == toEdge.quillKind else {
            preconditionFailure("PureLayout: cannot constrain \(edge) to \(toEdge) (mismatched axes)")
        }
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = quillPositionConstraint(
            from: self,
            attribute: edge.quillAttribute,
            kind: edge.quillKind,
            relation: relation,
            to: otherView,
            otherAttribute: toEdge.quillAttribute,
            constant: offset
        )
        constraint.autoInstall()
        return constraint
    }

    // MARK: All edges to another view
    //
    // PureLayout's `autoPinEdgesToSuperviewEdges` has a non-superview sibling
    // that pins all four edges to an arbitrary view; Signal call sites spell it
    // `autoPinEdges(toEdgesOf:)`. The bottom/trailing edges invert their inset
    // so a positive inset shrinks `self` inside `otherView`, matching the
    // superview-edges behavior above.

    @discardableResult
    public func autoPinEdges(toEdgesOf otherView: UIView, with insets: UIEdgeInsets = .zero) -> [NSLayoutConstraint] {
        return [
            autoPinEdge(.top, to: .top, of: otherView, withOffset: insets.top),
            autoPinEdge(.leading, to: .leading, of: otherView, withOffset: insets.left),
            autoPinEdge(.bottom, to: .bottom, of: otherView, withOffset: -insets.bottom),
            autoPinEdge(.trailing, to: .trailing, of: otherView, withOffset: -insets.right),
        ]
    }

    // MARK: Axis alignment / centering

    @discardableResult
    public func autoAlignAxis(toSuperviewAxis axis: ALAxis) -> NSLayoutConstraint {
        return autoAlignAxis(axis, toSameAxisOf: quillALSuperview)
    }

    @discardableResult
    public func autoAlignAxis(_ axis: ALAxis, toSameAxisOf otherView: UIView, withOffset offset: CGFloat = 0) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = quillPositionConstraint(
            from: self,
            attribute: axis.quillAttribute,
            kind: axis.quillKind,
            relation: .equal,
            to: otherView,
            otherAttribute: axis.quillAttribute,
            constant: offset
        )
        constraint.autoInstall()
        return constraint
    }

    @discardableResult
    public func autoCenterInSuperview() -> [NSLayoutConstraint] {
        // PureLayout's order: horizontal axis (centerY) first, then vertical.
        return [
            autoAlignAxis(toSuperviewAxis: .horizontal),
            autoAlignAxis(toSuperviewAxis: .vertical),
        ]
    }

    /// Margin-relative centering. With zero-modeled layout margins (see the
    /// margins note above) this is identical to `autoCenterInSuperview()`.
    @discardableResult
    public func autoCenterInSuperviewMargins() -> [NSLayoutConstraint] {
        return autoCenterInSuperview()
    }

    // MARK: Dimensions

    @discardableResult
    public func autoSetDimension(_ dimension: ALDimension, toSize size: CGFloat, relation: NSLayoutConstraint.Relation = .equal) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let anchor = NSLayoutDimension(item: self, attribute: dimension.quillAttribute)
        let constraint: NSLayoutConstraint
        switch relation {
        case .equal:
            constraint = anchor.constraint(equalToConstant: size)
        case .greaterThanOrEqual:
            constraint = anchor.constraint(greaterThanOrEqualToConstant: size)
        case .lessThanOrEqual:
            constraint = anchor.constraint(lessThanOrEqualToConstant: size)
        }
        constraint.autoInstall()
        return constraint
    }

    @discardableResult
    public func autoSetDimensions(to size: CGSize) -> [NSLayoutConstraint] {
        return [
            autoSetDimension(.width, toSize: size.width),
            autoSetDimension(.height, toSize: size.height),
        ]
    }

    // MARK: Matching dimensions

    @discardableResult
    public func autoMatch(_ dimension: ALDimension, to toDimension: ALDimension, of otherView: UIView, withOffset offset: CGFloat = 0) -> NSLayoutConstraint {
        return autoMatch(dimension, to: toDimension, of: otherView, withOffset: offset, relation: .equal)
    }

    @discardableResult
    public func autoMatch(_ dimension: ALDimension, to toDimension: ALDimension, of otherView: UIView, withOffset offset: CGFloat, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = quillRelate(
            NSLayoutDimension(item: self, attribute: dimension.quillAttribute),
            relation,
            NSLayoutDimension(item: otherView, attribute: toDimension.quillAttribute),
            constant: offset
        )
        constraint.autoInstall()
        return constraint
    }

    @discardableResult
    public func autoMatch(_ dimension: ALDimension, to toDimension: ALDimension, of otherView: UIView, withMultiplier multiplier: CGFloat) -> NSLayoutConstraint {
        return autoMatch(dimension, to: toDimension, of: otherView, withMultiplier: multiplier, relation: .equal)
    }

    @discardableResult
    public func autoMatch(_ dimension: ALDimension, to toDimension: ALDimension, of otherView: UIView, withMultiplier multiplier: CGFloat, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let first = NSLayoutDimension(item: self, attribute: dimension.quillAttribute)
        let second = NSLayoutDimension(item: otherView, attribute: toDimension.quillAttribute)
        let constraint: NSLayoutConstraint
        switch relation {
        case .equal:
            constraint = first.constraint(equalTo: second, multiplier: multiplier)
        case .greaterThanOrEqual:
            constraint = first.constraint(greaterThanOrEqualTo: second, multiplier: multiplier)
        case .lessThanOrEqual:
            constraint = first.constraint(lessThanOrEqualTo: second, multiplier: multiplier)
        }
        constraint.autoInstall()
        return constraint
    }

    // MARK: Generic attribute constraints

    @discardableResult
    public func autoConstrainAttribute(_ attribute: ALAttribute, to toAttribute: ALAttribute, of otherView: UIView, withOffset offset: CGFloat = 0) -> NSLayoutConstraint {
        return autoConstrainAttribute(attribute, to: toAttribute, of: otherView, withOffset: offset, relation: .equal)
    }

    @discardableResult
    public func autoConstrainAttribute(_ attribute: ALAttribute, to toAttribute: ALAttribute, of otherView: UIView, withOffset offset: CGFloat, relation: NSLayoutConstraint.Relation) -> NSLayoutConstraint {
        guard attribute.quillKind == toAttribute.quillKind else {
            preconditionFailure("PureLayout: cannot constrain \(attribute) to \(toAttribute) (mismatched attribute kinds)")
        }
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = quillPositionConstraint(
            from: self,
            attribute: attribute.quillAttribute,
            kind: attribute.quillKind,
            relation: relation,
            to: otherView,
            otherAttribute: toAttribute.quillAttribute,
            constant: offset
        )
        constraint.autoInstall()
        return constraint
    }

    // MARK: Top / bottom layout guides
    //
    // Signal's PureLayout fork adds helpers that pin a view to a view
    // controller's `topLayoutGuide` / `bottomLayoutGuide`. Those legacy guides
    // (deprecated by Apple in favor of `safeAreaLayoutGuide`) coincide with the
    // controller view's top/bottom edge once status-bar / nav-bar overlap is
    // accounted for. QuillOS models neither a status bar nor safe-area insets
    // (see the margins note above), so the guides resolve to the controller
    // view's edges; the `withInset:` offset is applied verbatim, inverted on
    // the bottom guide so a positive inset moves `self` up inside the view.

    @discardableResult
    public func autoPin(toTopLayoutGuideOf viewController: UIViewController, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(.top, to: .top, of: viewController.view, withOffset: inset)
    }

    @discardableResult
    public func autoPin(toBottomLayoutGuideOf viewController: UIViewController, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        return autoPinEdge(.bottom, to: .bottom, of: viewController.view, withOffset: -inset)
    }
}
