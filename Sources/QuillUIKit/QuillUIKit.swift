// QuillUIKit
// ==========
// UIKit (UI*) shadow types for platforms where Apple's UIKit isn't
// available (Linux, macOS without iOS support). On iOS this is empty —
// QuillFoundation already re-exports the real UIKit framework. On
// macOS we provide UIKit-shaped types so iOS-targeted upstream code
// (NetNewsWire iOS, Ice Cubes iOS, etc.) can compile under Mac Catalyst /
// macOS-as-iOS-host configurations.
//
// AuthenticationServices stubs live here too — they're small and the
// flow (presentation context, callback) belongs alongside UI plumbing.

import QuillFoundation
import QuillKit

#if os(Linux)
// CALayer for UIView.layer. On Apple platforms the real QuartzCore arrives
// transitively via AppKit/UIKit; on Linux it's the in-tree shim module.
import QuartzCore
#endif

#if os(iOS)
// On iOS the real UIKit / AuthenticationServices / WebKit are auto-imported.
import AuthenticationServices
public typealias ASPresentationAnchor = UIWindow
#elseif os(macOS)
import AppKit
import AuthenticationServices
public typealias ASPresentationAnchor = NSWindow
#else
public typealias ASPresentationAnchor = NSObject
#endif

#if !os(iOS)

// MARK: - UIResponder / UIView / UIViewController stubs

@MainActor open class UIResponder: NSObject, @preconcurrency QuillSelectorDispatching {
    /// Linux target-action dispatch base (no ObjC runtime). The source lowering
    /// (AppKitLowering) injects an `override` of this into every UIResponder
    /// subclass that declares `@objc` action methods; each override switches on
    /// `selector.name` and falls through to `super.quillPerform` for inherited
    /// selectors, terminating here in a no-op. CLASS-BODY (not an extension) so
    /// the overrides are reachable through a base-class-typed reference — see
    /// QuillSelectorDispatching (QuillFoundation) for the full rationale.
    ///
    /// `@preconcurrency`: the witness is `@MainActor` (this class is) but the
    /// protocol requirement is nonisolated so target-action can fire from
    /// nonisolated callers (Timer / CADisplayLink / UndoManager). On an
    /// explicitly-`@MainActor` class that mismatch is a hard error without
    /// `@preconcurrency`, which downgrades it to a runtime main-thread check —
    /// correct here since UI target-action always fires on the main thread.
    open func quillPerform(_ selector: Selector, with sender: Any?) {}

    open var next: UIResponder? { nil }

    /// Apple's default: no accessory view (ContactShareViewController
    /// overrides this with a super call).
    open var inputAccessoryView: UIView? { nil }

    open var keyCommands: [UIKeyCommand]? { nil }

    /// UIKit default: a responder refuses first-responder status unless a
    /// subclass opts in (text fields, SignalUI's ActionSheetController, …).
    open var canBecomeFirstResponder: Bool { false }
    open var isFirstResponder: Bool { false }

    @discardableResult
    open func becomeFirstResponder() -> Bool { true }

    @discardableResult
    open func resignFirstResponder() -> Bool { true }

    open func buildMenu(with builder: UIMenuBuilder) {
        _ = builder
    }

    // MARK: Touch dispatch
    //
    // CLASS-BODY, not extension: Signal subclasses override these (extensions
    // cannot be overridden without ObjC dynamism). The UIResponder variants
    // take an OPTIONAL event, unlike the UIGestureRecognizer hooks in
    // UIGestureRecognizers.swift (Apple's subclass contract there is
    // non-optional). Apple's defaults forward up the responder chain; there
    // is no chain wiring on Linux, so the defaults are no-ops — the future
    // event backend (compositor input → window dispatch) calls these, and
    // overrides run today when upstream code invokes them directly.
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = touches
        _ = event
    }
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = touches
        _ = event
    }
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = touches
        _ = event
    }
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = touches
        _ = event
    }
}

/// The layout attribute an anchor represents. QuillUIKit-local (the public
/// `NSLayoutConstraint.Attribute` enum lives in QuillAppKit, which depends on
/// this module). The native layout pass (e.g. QuillAppKitQt → QuillAutoLayout)
/// reads this to translate a constraint into the solver.
public enum QuillLayoutAttribute: Sendable {
    case left, right, top, bottom, leading, trailing
    case width, height, centerX, centerY, firstBaseline, lastBaseline
    case notAnAttribute
}

/// Non-generic read access to an anchor's binding, so a layout pass can inspect
/// heterogeneous anchors (X-axis / Y-axis / dimension) uniformly.
public protocol QuillLayoutAnchorReading: AnyObject {
    var quillItem: AnyObject? { get }
    var quillAttribute: QuillLayoutAttribute { get }
}

public class NSLayoutAnchor<AnchorType>: NSObject, QuillLayoutAnchorReading {
    /// The item (e.g. an NSView) this anchor belongs to. Weak: the constraint
    /// retains the anchor; the anchor must not retain the view.
    public internal(set) weak var quillItem: AnyObject?
    public internal(set) var quillAttribute: QuillLayoutAttribute

    public init(item: AnyObject?, attribute: QuillLayoutAttribute) {
        quillItem = item
        quillAttribute = attribute
        super.init()
    }
    public override init() {
        quillItem = nil
        quillAttribute = .notAnAttribute
        super.init()
    }
}

public class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {}
public class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {}

public class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    public func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .equal, second: nil, multiplier: 0, constant: c)
    }
    public func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .lessThanOrEqual, second: nil, multiplier: 0, constant: c)
    }
    public func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .greaterThanOrEqual, second: nil, multiplier: 0, constant: c)
    }
    public func constraint(equalTo other: NSLayoutDimension, multiplier m: CGFloat = 1, constant c: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .equal, second: other, multiplier: m, constant: c)
    }
    public func constraint(greaterThanOrEqualTo other: NSLayoutDimension, multiplier m: CGFloat = 1, constant c: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .greaterThanOrEqual, second: other, multiplier: m, constant: c)
    }
    public func constraint(lessThanOrEqualTo other: NSLayoutDimension, multiplier m: CGFloat = 1, constant c: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .lessThanOrEqual, second: other, multiplier: m, constant: c)
    }
}

public extension NSLayoutAnchor {
    func constraint(equalTo other: NSLayoutAnchor<AnchorType>, constant c: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .equal, second: other, multiplier: 1, constant: c)
    }
    func constraint(greaterThanOrEqualTo other: NSLayoutAnchor<AnchorType>, constant c: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .greaterThanOrEqual, second: other, multiplier: 1, constant: c)
    }
    func constraint(lessThanOrEqualTo other: NSLayoutAnchor<AnchorType>, constant c: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .lessThanOrEqual, second: other, multiplier: 1, constant: c)
    }
}

public class NSLayoutConstraint: NSObject {
    public enum QuillRelation: Sendable { case equal, lessThanOrEqual, greaterThanOrEqual }
    public typealias Relation = QuillRelation
    public enum Axis: Sendable { case horizontal, vertical }

    /// Constraint priority (NSLayoutConstraint.Priority): a Float wrapper with
    /// the standard named levels and +/- arithmetic (so `.defaultHigh + 1`
    /// works, as real AppKit code uses).
    public struct Priority: RawRepresentable, Sendable, Equatable {
        public var rawValue: Float
        public init(rawValue: Float) { self.rawValue = rawValue }
        public init(_ rawValue: Float) { self.rawValue = rawValue }
        public static let required = Priority(1000)
        public static let defaultHigh = Priority(750)
        public static let dragThatCanResizeWindow = Priority(510)
        public static let windowSizeStayPut = Priority(500)
        public static let dragThatCannotResizeWindow = Priority(490)
        public static let defaultLow = Priority(250)
        public static let fittingSizeCompression = Priority(50)
        /// UIKit's name for the fitting-size priority (AppKit spells it
        /// `fittingSizeCompression`); both are 50. SignalUI passes it to
        /// `systemLayoutSizeFitting(_:withHorizontalFittingPriority:…)`.
        public static let fittingSizeLevel = Priority(50)
        public static func + (lhs: Priority, rhs: Float) -> Priority { Priority(lhs.rawValue + rhs) }
        public static func - (lhs: Priority, rhs: Float) -> Priority { Priority(lhs.rawValue - rhs) }
    }

    /// Constraint priority. Captured for the native layout pass (which maps it
    /// to a solver strength); defaults to required.
    public var priority: Priority = .required

    /// Anchor bindings + parameters captured from the factory methods, read by
    /// the native layout pass. A nil second anchor ⇒ a constant dimension
    /// (first.attribute == multiplier·second.attribute + constant; with no
    /// second, first.attribute == constant).
    public let quillFirstAnchor: (any QuillLayoutAnchorReading)?
    public let quillSecondAnchor: (any QuillLayoutAnchorReading)?
    public let quillRelation: QuillRelation
    public let quillMultiplier: CGFloat
    public let quillConstant: CGFloat

    /// Globally-active constraints. The native layout pass filters these to the
    /// view subtree it lays out. (AppKit stores them per-view; a global list
    /// keeps the QuillUIKit↔QuillAppKit module split simple. Items are weak via
    /// the anchors, so the pass drops constraints whose views have gone away.)
    nonisolated(unsafe) public static var quillActive: [NSLayoutConstraint] = []

    public var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive {
                NSLayoutConstraint.quillActive.append(self)
            } else {
                NSLayoutConstraint.quillActive.removeAll { $0 === self }
            }
        }
    }

    init(first: (any QuillLayoutAnchorReading)?, relation: QuillRelation,
         second: (any QuillLayoutAnchorReading)?, multiplier: CGFloat, constant: CGFloat) {
        quillFirstAnchor = first
        quillSecondAnchor = second
        quillRelation = relation
        quillMultiplier = multiplier
        quillConstant = constant
        super.init()
    }
    public override init() {
        quillFirstAnchor = nil
        quillSecondAnchor = nil
        quillRelation = .equal
        quillMultiplier = 1
        quillConstant = 0
        super.init()
    }

    public static func activate(_ constraints: [NSLayoutConstraint]) {
        for c in constraints { c.isActive = true }
    }
    public static func deactivate(_ constraints: [NSLayoutConstraint]) {
        for c in constraints { c.isActive = false }
    }
}

public enum UIUserInterfaceStyle: Int {
    case unspecified
    case light
    case dark
}

/// Apple's UIUserInterfaceLevel (base vs. elevated window layers). Raw values
/// match UIKit's (.unspecified == -1).
public enum UIUserInterfaceLevel: Int {
    case unspecified = -1
    case base = 0
    case elevated = 1
}

/// Apple's UIAccessibilityContrast (the Increase Contrast accessibility
/// setting). Raw values match UIKit's (.unspecified == -1).
public enum UIAccessibilityContrast: Int {
    case unspecified = -1
    case normal = 0
    case high = 1
}

/// A rectangular region that participates in Auto Layout without a backing
/// view (safe area, layout margins, free-standing guides added through
/// UIView.addLayoutGuide). @MainActor to match UIKit's isolation (and because
/// guides hold references into the view tree).
@MainActor public class UILayoutGuide: NSObject {
    public internal(set) weak var owningView: UIView?
    public var identifier: String = ""

    /// View-created guides (safe area / layout margins) alias the owning view:
    /// Linux draws no status bar, notch, or home indicator, so the safe area
    /// IS the view's bounds, and pinning to the guide must solve exactly like
    /// pinning to the view. Free-standing guides bind anchors to the guide
    /// object itself; the native layout pass skips items it cannot resolve to
    /// a view, so their constraints are captured but inert.
    weak var quillAliasedView: UIView?
    private var quillAnchorItem: AnyObject { quillAliasedView ?? self }

    // Fresh bound anchor per access — same pattern as UIView's anchors and
    // QuillAppKit's NSLayoutGuide.
    public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: quillAnchorItem, attribute: .top) }
    public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: quillAnchorItem, attribute: .bottom) }
    public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: quillAnchorItem, attribute: .leading) }
    public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: quillAnchorItem, attribute: .trailing) }
    public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: quillAnchorItem, attribute: .left) }
    public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: quillAnchorItem, attribute: .right) }
    public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: quillAnchorItem, attribute: .centerX) }
    public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: quillAnchorItem, attribute: .centerY) }
    public var widthAnchor: NSLayoutDimension { NSLayoutDimension(item: quillAnchorItem, attribute: .width) }
    public var heightAnchor: NSLayoutDimension { NSLayoutDimension(item: quillAnchorItem, attribute: .height) }
}

#if !os(macOS)
// Linux-only: UIWindow shadow (macOS already has NSWindow typealiased
// to UIWindow in QuillFoundation).
@MainActor open class UIWindow: UIView {
    // CLASS-BODY designated inits, not extension: SignalUI's OWSWindow
    // overrides both `init(frame:)` and `init(windowScene:)`, and Swift
    // cannot override an initializer introduced in an extension. Declaring a
    // designated init here also disables auto-inheritance of UIView's
    // `init(frame:)`, so it is re-declared as an override to keep
    // `UIWindow(frame:)` callable. The scene is recorded (Apple ties the
    // window to its scene); nothing composites on Linux.
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }
    public init(windowScene: UIWindowScene) {
        super.init(frame: .zero)
        windowScene.windows.append(self)
    }
}
#endif

@MainActor open class UIView: UIResponder {
    public enum ContentMode: Sendable {
        case scaleToFill
        case scaleAspectFit
        case scaleAspectFill
        case redraw
        case center
        case top
        case bottom
        case left
        case right
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    public struct AutoresizingMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let flexibleLeftMargin = AutoresizingMask(rawValue: 1 << 0)
        public static let flexibleWidth = AutoresizingMask(rawValue: 1 << 1)
        public static let flexibleRightMargin = AutoresizingMask(rawValue: 1 << 2)
        public static let flexibleTopMargin = AutoresizingMask(rawValue: 1 << 3)
        public static let flexibleHeight = AutoresizingMask(rawValue: 1 << 4)
        public static let flexibleBottomMargin = AutoresizingMask(rawValue: 1 << 5)
    }

    // Apple's UIView has NO designated init() — only init(frame:). The old
    // `override init()` here was an invented designated init, which made
    // upstream subclasses' `public init()` declarations demand `override`.
    public convenience override init() { self.init(frame: .zero) }

    /// Custom-drawing override point (CVTextLabel). Nothing rasterizes
    /// UIView.draw on Linux yet; subclass implementations run when a
    /// future compositor calls them.
    open func draw(_ rect: CGRect) { _ = rect }
    /// Trait-change override point (ContactCell etc.); never fired (traits
    /// are static on Linux).
    open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        _ = previousTraitCollection
    }
    // `open` (not just `public`): a designated init cannot be overridden
    // cross-module unless it is open, and Signal subclasses declare
    // `override init(frame:)` everywhere (ImageEditorSliderView's
    // BackgroundView, OWSLayerView, …).
    public init(frame: CGRect) {
        super.init()
        self.frame = frame
    }
    // `open` (not just `public`): Signal subclasses override frame/bounds with
    // didSet observers everywhere (CVImageView, ManualLayoutView, OWSLayerView,
    // …) and that requires the stored property itself to be overridable
    // cross-module.
    open var frame: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0) {
        didSet {
            #if os(Linux)
            _layer?.frame = frame
            #endif
        }
    }
    open var bounds: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0) {
        didSet {
            #if os(Linux)
            _layer?.bounds = bounds
            #endif
        }
    }

    /// The center of the view's frame, in the superview's coordinate system.
    /// Derived from `frame` both ways, exactly UIKit's geometry when no
    /// transform is set. APPROXIMATION: with a transform, real UIKit keeps
    /// `center` fixed (it is the layer position) while `frame` becomes the
    /// transformed bounding box; this shim's `frame` never re-derives from
    /// `transform`, so center and frame always agree here.
    open var center: CGPoint {
        get { CGPoint(x: frame.midX, y: frame.midY) }
        set {
            frame.origin = CGPoint(
                x: newValue.x - frame.size.width / 2,
                y: newValue.y - frame.size.height / 2
            )
        }
    }

    /// The view's affine transform. Stored faithfully and mirrored into the
    /// layer MODEL on Linux (CALayer.setAffineTransform), so animation/
    /// geometry code can read back what it set. MODEL HONESTY: nothing
    /// composites on Linux, so the transform does not move pixels, and —
    /// unlike real UIKit — `frame` is NOT recomputed as the transformed
    /// bounding box (see `center`).
    open var transform: CGAffineTransform = .identity {
        didSet {
            #if os(Linux)
            _layer?.setAffineTransform(transform)
            #endif
        }
    }

    /// How content is fitted into the bounds. CLASS-BODY `open` (UIImageView
    /// no longer redeclares it) so subclass overrides resolve cross-module.
    /// Faithful STATE with Apple's default; no renderer consumes it on Linux
    /// yet.
    open var contentMode: ContentMode = .scaleToFill

    public private(set) weak var superview: UIView?
    public var subviews: [UIView] = []
    open func removeFromSuperview() {
        superview?.subviews.removeAll { $0 === self }
        superview = nil
        #if os(Linux)
        _layer?.removeFromSuperlayer()
        #endif
    }
    public var backgroundColor: UIColor?
    open func addSubview(_ view: UIView) {
        view.willMove(toWindow: window)
        view.removeFromSuperview()
        subviews.append(view)
        view.superview = self
        view.window = window
        #if os(Linux)
        layer.addSublayer(view.layer)
        #endif
    }

    /// Inserts a subview at an explicit z-position (index 0 is backmost).
    /// Same installation sequence as addSubview. APPROXIMATION: Apple raises
    /// on an out-of-range index; the shim clamps — upstream callers compute
    /// indices from `subviews` they just read, so a clamp never actually
    /// engages, and clamping beats crashing on a model with no compositor.
    open func insertSubview(_ view: UIView, at index: Int) {
        view.willMove(toWindow: window)
        view.removeFromSuperview()
        let position = max(0, min(index, subviews.count))
        subviews.insert(view, at: position)
        view.superview = self
        view.window = window
        #if os(Linux)
        // Mirror z-order relative to the next view-backed sublayer (not the
        // raw index): stray non-view sublayers (shape/gradient layers added
        // directly to `layer`) keep their stacking instead of being displaced.
        if position + 1 < subviews.count {
            layer.insertSublayer(view.layer, below: subviews[position + 1].layer)
        } else {
            layer.addSublayer(view.layer)
        }
        #endif
    }

    /// Apple requires `siblingSubview` to already be a child (behavior is
    /// undefined otherwise); the shim's honest fallback for a non-child
    /// sibling is a plain append (frontmost), documented rather than trapped.
    open func insertSubview(_ view: UIView, aboveSubview siblingSubview: UIView) {
        if let index = subviews.firstIndex(where: { $0 === siblingSubview }) {
            insertSubview(view, at: index + 1)
        } else {
            addSubview(view)
        }
    }

    open func insertSubview(_ view: UIView, belowSubview siblingSubview: UIView) {
        if let index = subviews.firstIndex(where: { $0 === siblingSubview }) {
            insertSubview(view, at: index)
        } else {
            addSubview(view)
        }
    }

    open func willMove(toWindow newWindow: UIWindow?) {
        _ = newWindow
    }

    open func willMove(toSuperview newSuperview: UIView?) {
        _ = newSuperview
    }

    open func didMoveToSuperview() {}

    open func layoutMarginsDidChange() {}

    open func safeAreaInsetsDidChange() {}

    open func invalidateIntrinsicContentSize() {
        setNeedsLayout()
        superview?.setNeedsLayout()
    }

    // MARK: Hit testing
    //
    // CLASS-BODY, not extension: Signal subclasses override both hooks.
    // Geometry shares `convert`'s frame-chain approximations (see
    // UIViewGeometry.swift); transforms never bend the hit path because
    // `frame` is never re-derived from `transform` in this shim.

    /// Containment in the view's own bounds space. Raw origin/size math, the
    /// CALayer.hitTest convention (half-open on the max edges).
    open func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        _ = event
        return point.x >= bounds.origin.x
            && point.y >= bounds.origin.y
            && point.x < bounds.origin.x + bounds.size.width
            && point.y < bounds.origin.y + bounds.size.height
    }

    /// Apple's documented algorithm: ineligible views (hidden, interaction
    /// disabled, alpha < 0.01) swallow nothing; children are consulted
    /// front-to-back (later siblings are frontmost) with the point converted
    /// into each child's space; self answers when no child claims the point.
    open func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha >= 0.01,
              self.point(inside: point, with: event) else { return nil }
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(convert(point, to: subview), with: event) {
                return hit
            }
        }
        return self
    }

    #if os(Linux)
    // UIView.layer — Apple's view/layer pairing. Created lazily (first access)
    // via `layerClass` so subclasses that override `layerClass` (CAShapeLayer-
    // backed views etc.) get the right class; geometry writes mirror into it.
    // There is no compositor on Linux yet, so the layer is a faithful MODEL
    // (geometry, hierarchy, animation timing) — not pixels. Linux-only block:
    // on macOS this module builds against real AppKit and predates the shim.
    private var _layer: CALayer?
    open class var layerClass: AnyClass { CALayer.self }
    private func quillInstantiateLayer(_ layerClass: AnyClass) -> CALayer {
        switch layerClass {
        case _ where layerClass === CALayer.self:
            return CALayer()
        case _ where layerClass === CAShapeLayer.self:
            return CAShapeLayer()
        case _ where layerClass === CAGradientLayer.self:
            return CAGradientLayer()
        case _ where layerClass === CATextLayer.self:
            return CATextLayer()
        case _ where layerClass === CAEmitterLayer.self:
            return CAEmitterLayer()
        case _ where layerClass === CAReplicatorLayer.self:
            return CAReplicatorLayer()
        case _ where layerClass === CAScrollLayer.self:
            return CAScrollLayer()
        case _ where layerClass === CATransformLayer.self:
            return CATransformLayer()
        case _ where layerClass === CAMetalLayer.self:
            return CAMetalLayer()
        default:
            return CALayer()
        }
    }

    open var layer: CALayer {
        if let existing = _layer { return existing }
        let created = quillInstantiateLayer(type(of: self).layerClass)
        // Seed from BOTH stored geometry properties: a bounds set before the
        // first layer access must survive (frame alone would reset the
        // layer's bounds to the possibly-zero stored frame). frame first —
        // it derives position + bounds.size — then bounds wins where the
        // caller set it explicitly.
        created.frame = frame
        if bounds != .zero {
            created.bounds = bounds
        }
        if transform != .identity {
            created.setAffineTransform(transform)
        }
        _layer = created
        return created
    }
    #endif
    public var window: UIWindow?
    public typealias UserInterfaceStyle = UIUserInterfaceStyle
    public var overrideUserInterfaceStyle: UserInterfaceStyle = .unspecified
    public var isHidden: Bool = false
    public var isUserInteractionEnabled: Bool = true
    public var alpha: CGFloat = 1.0
    public var tintColor: UIColor?
    open func tintColorDidChange() {}

    /// View-owned layout guides. Linux draws no status bar, notch, or home
    /// indicator, so the safe area IS the view's bounds: both guides alias the
    /// view itself (see UILayoutGuide.quillAliasedView), making constraints
    /// against them solve exactly like constraints against the view's edges.
    /// MODEL HONESTY: layoutMargins are recorded (quillLayoutMargins below)
    /// but the native layout pass does not yet inset the margins guide.
    public private(set) lazy var safeAreaLayoutGuide: UILayoutGuide = self.quillMakeEdgeAliasedGuide(identifier: "UIViewSafeAreaLayoutGuide")
    public private(set) lazy var layoutMarginsGuide: UILayoutGuide = self.quillMakeEdgeAliasedGuide(identifier: "UIViewLayoutMarginsGuide")
    private func quillMakeEdgeAliasedGuide(identifier: String) -> UILayoutGuide {
        let guide = UILayoutGuide()
        guide.identifier = identifier
        guide.owningView = self
        guide.quillAliasedView = self
        return guide
    }

    /// Backing store for `layoutMargins`. The UIEdgeInsets-typed property
    /// cannot live here: UIEdgeInsets is declared in the UIKit shim module,
    /// which depends on this one, so the shim layers `layoutMargins` over this
    /// value. 8pt on every edge is UIKit's default.
    public var quillLayoutMargins = QuillEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

    /// Guides added via addLayoutGuide(_:). Free-standing guides keep their
    /// anchors bound to the guide object itself, which the native layout pass
    /// cannot (yet) resolve to a view — their constraints are captured but
    /// inert (see UILayoutGuide.quillAliasedView).
    public private(set) var layoutGuides: [UILayoutGuide] = []
    open func addLayoutGuide(_ layoutGuide: UILayoutGuide) {
        layoutGuide.owningView?.removeLayoutGuide(layoutGuide)
        layoutGuides.append(layoutGuide)
        layoutGuide.owningView = self
    }
    open func removeLayoutGuide(_ layoutGuide: UILayoutGuide) {
        layoutGuides.removeAll { $0 === layoutGuide }
        if layoutGuide.owningView === self { layoutGuide.owningView = nil }
    }

    // Computed so each anchor is bound to this view + its attribute (the
    // native layout pass reads that binding to translate the constraint into
    // the solver). Fresh per access — anchors are lightweight value-like
    // handles, matching QuillAppKit's NSView.
    public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .top) }
    public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .bottom) }
    public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .leading) }
    public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .trailing) }
    public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .left) }
    public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .right) }
    public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .centerX) }
    public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .centerY) }
    public var widthAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .width) }
    public var heightAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .height) }

    /// Layout dirtying. MODEL HONESTY: there is no compositor-driven layout
    /// pass on Linux — layoutIfNeeded() just gives layoutSubviews() overrides
    /// one chance to run per dirtying, so upstream code that does manual
    /// frame math there still executes.
    private var quillNeedsLayout = true
    open func setNeedsLayout() { quillNeedsLayout = true }
    public func setNeedsDisplay() {}
    open func layoutIfNeeded() {
        guard quillNeedsLayout else { return }
        quillNeedsLayout = false
        layoutSubviews()
    }
    open func layoutSubviews() {}

    // MARK: Constraint pass + measurement
    //
    // CLASS-BODY `open`: Signal overrides all three (CVLabel/CVButton/
    // CVImageView override updateConstraints; ManualLayoutView and friends
    // override sizeThatFits; ImageEditorSlider overrides intrinsicContentSize)
    // and overrides need class-body members. Constraints live in one global
    // list here (NSLayoutConstraint.quillActive), so there is no per-view
    // update pass to run — the hooks exist for overrides, and the bases are
    // honest no-ops.

    /// Apple's constraint-refresh override point (subclasses call super).
    open func updateConstraints() {}
    /// Recorded-intent no-op, same posture as setNeedsDisplay: nothing
    /// schedules a constraint pass on Linux.
    open func setNeedsUpdateConstraints() {}

    /// "Best fitting" size. Apple's UIView default returns the view's
    /// EXISTING size (the proposal is only consulted by overrides), and so
    /// does the shim.
    open func sizeThatFits(_ size: CGSize) -> CGSize {
        _ = size
        return bounds.size
    }

    /// No intrinsic size, exactly Apple's UIView default; content-bearing
    /// views override with real metrics.
    open var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
    /// Apple's sentinel for "no intrinsic metric on this axis" (-1).
    public static let noIntrinsicMetric: CGFloat = -1

    public static var areAnimationsEnabled: Bool = true
    public static var inheritedAnimationDuration: TimeInterval = 0

    public func setContentCompressionResistancePriority(_ priority: NSLayoutConstraint.Priority, for axis: NSLayoutConstraint.Axis) {
        _ = priority
        _ = axis
    }

    /// Sibling of setContentCompressionResistancePriority above, same
    /// posture: recorded-intent no-op — the native layout pass does not
    /// consume hugging/compression priorities yet. (SignalUI calls this
    /// bare from UIView subclass bodies — SelectionIndicatorView, the
    /// autoSetDimension helpers in UIView+AutoLayout — so it must be a
    /// class member, not a global.)
    public func setContentHuggingPriority(_ priority: NSLayoutConstraint.Priority, for axis: NSLayoutConstraint.Axis) {
        _ = priority
        _ = axis
    }

    public func contentHuggingPriority(for axis: NSLayoutConstraint.Axis) -> NSLayoutConstraint.Priority {
        _ = axis
        return .defaultLow
    }

    public struct AnimationOptions: OptionSet, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let layoutSubviews = AnimationOptions(rawValue: 1 << 0)
        public static let allowUserInteraction = AnimationOptions(rawValue: 1 << 1)
        public static let beginFromCurrentState = AnimationOptions(rawValue: 1 << 2)
        public static let `repeat` = AnimationOptions(rawValue: 1 << 3)
        public static let repeatAnimation = `repeat`
        public static let autoreverse = AnimationOptions(rawValue: 1 << 4)
        public static let overrideInheritedDuration = AnimationOptions(rawValue: 1 << 5)
        public static let overrideInheritedCurve = AnimationOptions(rawValue: 1 << 6)
        public static let allowAnimatedContent = AnimationOptions(rawValue: 1 << 7)
        public static let showHideTransitionViews = AnimationOptions(rawValue: 1 << 8)
        public static let overrideInheritedOptions = AnimationOptions(rawValue: 1 << 9)
        public static let curveEaseInOut: AnimationOptions = []
        public static let curveEaseIn = AnimationOptions(rawValue: 1 << 16)
        public static let curveEaseOut = AnimationOptions(rawValue: 2 << 16)
        public static let curveLinear = AnimationOptions(rawValue: 3 << 16)
        public static let transitionFlipFromLeft = AnimationOptions(rawValue: 1 << 20)
        public static let transitionFlipFromRight = AnimationOptions(rawValue: 2 << 20)
        public static let transitionCurlUp = AnimationOptions(rawValue: 3 << 20)
        public static let transitionCurlDown = AnimationOptions(rawValue: 4 << 20)
        public static let transitionCrossDissolve = AnimationOptions(rawValue: 5 << 20)
        public static let transitionFlipFromTop = AnimationOptions(rawValue: 6 << 20)
        public static let transitionFlipFromBottom = AnimationOptions(rawValue: 7 << 20)
        public static let preferredFramesPerSecondDefault: AnimationOptions = []
        public static let preferredFramesPerSecond60 = AnimationOptions(rawValue: 3 << 24)
        public static let preferredFramesPerSecond30 = AnimationOptions(rawValue: 7 << 24)
    }

    public static func animate(
        withDuration: TimeInterval,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        animations()
        completion?(true)
    }

    public static func performWithoutAnimation(_ actionsWithoutAnimation: () -> Void) {
        actionsWithoutAnimation()
    }

    public static func transition(
        with view: UIView,
        duration: TimeInterval,
        options: AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        _ = (view, duration, options)
        animations()
        completion?(true)
    }

    public static func animateKeyframes(
        withDuration duration: TimeInterval,
        delay: TimeInterval = 0,
        options: AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        _ = (duration, delay, options)
        animations()
        completion?(true)
    }

    public static func addKeyframe(
        withRelativeStartTime frameStartTime: Double,
        relativeDuration frameDuration: Double,
        animations: @escaping () -> Void
    ) {
        _ = (frameStartTime, frameDuration)
        animations()
    }

    public static func animate(
        withDuration: TimeInterval,
        delay: TimeInterval = 0,
        options: AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        animations()
        completion?(true)
    }

    public static func animate(
        withDuration: TimeInterval,
        delay: TimeInterval,
        usingSpringWithDamping: CGFloat,
        initialSpringVelocity: CGFloat,
        options: AnimationOptions,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        animations()
        completion?(true)
    }

    public var traitCollection = UITraitCollection()
    public var translatesAutoresizingMaskIntoConstraints: Bool = true
    public var autoresizingMask: AutoresizingMask = []
    public var clipsToBounds: Bool = true
    public var tag: Int = 0
    public var semanticContentAttribute: UISemanticContentAttribute = .unspecified

    /// Compositing hint ("my content fills my bounds — skip blending behind
    /// me"). Apple's UIView default is true. Faithful STATE only: there is
    /// no compositor on Linux, so nothing consumes it yet.
    public var isOpaque: Bool = true

    // MARK: Accessibility
    //
    // CLASS-BODY `open` STORED properties: Signal overrides these with
    // computed get/set pairs that call super (CVCapsuleLabel's label +
    // traits, AttachmentApproval's MediaQualitySelectionControl,
    // OWSFlatButton's identifier), and cross-module overrides need
    // overridable class-body members. On Apple most of these live on
    // NSObject's informal accessibility protocol; the shim hangs them on
    // UIView (+ UIBarButtonItem below), the only receivers upstream uses.
    // Faithful STATE only: no assistive technology reads them on Linux.
    open var isAccessibilityElement: Bool = false
    open var accessibilityIdentifier: String?
    open var accessibilityLabel: String?
    open var accessibilityValue: String?
    open var accessibilityHint: String?
    open var accessibilityTraits: UIAccessibilityTraits = .none
    /// Apple derives this from on-screen geometry (screen coordinates);
    /// the shim stores it (default .zero) and lets overrides compute their
    /// own (AttachmentApproval does, via UIAccessibility.convertToScreenCoordinates).
    open var accessibilityFrame: CGRect = .zero
    open var accessibilityElementsHidden: Bool = false

    // VoiceOver action hooks, Apple's defaults (unhandled / no-op).
    // Overridden by MediaQualitySelectionControl's adjustable control.
    open func accessibilityActivate() -> Bool { false }
    open func accessibilityIncrement() {}
    open func accessibilityDecrement() {}
}

@MainActor open class UIViewController: UIResponder {
    // Apple's designated initializer; without it NSObject's init() was
    // inherited as designated and upstream's `super.init(nibName:bundle:)`
    // and `public init()` overrides could not line up.
    public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init()
    }
    public convenience override init() { self.init(nibName: nil, bundle: nil) }

    public class func attemptRotationToDeviceOrientation() {}
    private var quillTitle: String?
    open var title: String? {
        get { quillTitle }
        set {
            quillTitle = newValue
            navigationItem.title = newValue
        }
    }

    open func viewIsAppearing(_ animated: Bool) { _ = animated }
    open var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        _ = previousTraitCollection
    }

    // View loading mirrors UIKit: the first access to `view` runs loadView()
    // and then viewDidLoad(), exactly once. There is no nib/storyboard system
    // here, so the default loadView() makes an empty UIView.
    private var _view: UIView?
    open var view: UIView! {
        get {
            if _view == nil {
                loadView()
                if _view == nil { _view = UIView() }
                viewDidLoad()
            }
            return _view
        }
        set { _view = newValue }
    }
    public var viewIfLoaded: UIView? { _view }
    public var isViewLoaded: Bool { _view != nil }
    open func loadView() { view = UIView() }
    public func loadViewIfNeeded() { _ = view }

    // Containment. Model-level bookkeeping with UIKit's calling convention:
    // addChild calls the child's willMove(toParent:), removeFromParent calls
    // didMove(toParent: nil); containers invoke the other half themselves.
    public var children: [UIViewController] = []
    public internal(set) weak var parent: UIViewController?
    open func addChild(_ childController: UIViewController) {
        childController.willMove(toParent: self)
        childController.parent?.children.removeAll { $0 === childController }
        children.append(childController)
        childController.parent = self
    }
    open func removeFromParent() {
        parent?.children.removeAll { $0 === self }
        parent = nil
        didMove(toParent: nil)
    }
    open func willMove(toParent parent: UIViewController?) {}
    open func didMove(toParent parent: UIViewController?) {}

    // Presentation. Model-level: tracks the presented/presenting relationship
    // and runs completions synchronously (there is no transition animation to
    // wait for); nothing reaches the screen until a native window layer
    // chooses to show the presented controller.
    open var definesPresentationContext: Bool = false
    open var providesPresentationContextTransitionStyle: Bool = false
    open var isModalInPresentation: Bool = false
    public internal(set) var presentedViewController: UIViewController?
    public internal(set) weak var presentingViewController: UIViewController?
    open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentedViewController = viewControllerToPresent
        viewControllerToPresent.presentingViewController = self
        completion?()
    }
    open func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if let presented = presentedViewController {
            presented.presentingViewController = nil
            presentedViewController = nil
        } else if let presenter = presentingViewController {
            presenter.presentedViewController = nil
            presentingViewController = nil
        }
        completion?()
    }
    /// Always nil — no interactive/animated transitions exist to coordinate.
    open var transitionCoordinator: UIViewControllerTransitionCoordinator? { nil }

    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewDidDisappear(_ animated: Bool) {}
    open func viewWillLayoutSubviews() {}
    open func viewDidLayoutSubviews() {}
    open func viewSafeAreaInsetsDidChange() {}
    open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {}

    // MARK: Status-bar appearance
    //
    // CLASS-BODY, not extension: SignalUI overrides all of these
    // (ImageEditorCropViewController & co.). Apple's defaults throughout.
    // There is no status bar on Linux, so nothing reads the values back yet;
    // UIViewControllerSurface.swift owns the matching no-op
    // setNeedsStatusBarAppearanceUpdate() and the UIStatusBarStyle enum.
    open var preferredStatusBarStyle: UIStatusBarStyle { .default }
    open var prefersStatusBarHidden: Bool { false }
    open var childForStatusBarStyle: UIViewController? { nil }
    open var childForStatusBarHidden: UIViewController? { nil }

    /// VoiceOver's "escape" (two-finger Z) hook — on Apple it's part of
    /// NSObject's accessibility protocol; class-body here so SignalUI's
    /// InteractiveSheetViewController can override it AND call up through
    /// super. Apple's default: unhandled (false). No assistive technology
    /// invokes it on Linux yet.
    open func accessibilityPerformEscape() -> Bool { false }

    public var traitCollection = UITraitCollection()
    public var navigationController: UINavigationController?
    public var splitViewController: UISplitViewController?
    public var navigationItem = UINavigationItem()
    public var preferredContentSize: CGSize = CGSize(width: 0, height: 0)

    // MARK: Presentation style
    //
    // CLASS-BODY, not extension: SignalUI's HeroSheetViewController overrides
    // `modalPresentationStyle` with a `willSet` observer, and Swift cannot
    // override a member introduced in an extension (no @objc dynamism on
    // Linux). Stored with Apple's iOS-13 default (`.automatic`); the
    // model-level present/dismiss does not consult it (nothing composites on
    // Linux yet). The UIModalPresentationStyle enum lives in
    // UIViewControllerSurface.swift.
    open var modalPresentationStyle: UIModalPresentationStyle = .automatic

    /// The popover-presentation controller, when this controller is (or will
    /// be) presented as a popover. nil by default — no popover presentation
    /// runs on Linux — but SignalUI reads it on UIActivityViewController and
    /// plain controllers (every use is `if let`/`?`), so it lives on the base
    /// class. Stored + `open` so a subclass could vend one; UIAlertController
    /// inherits this and no longer declares its own.
    open var popoverPresentationController: UIPopoverPresentationController?
}

@MainActor public class UISplitViewController: UIViewController {
    public enum DisplayMode: Int {
        case automatic
        case secondaryOnly
        case oneBesideSecondary
        case oneOverSecondary
        case twoBesideSecondary
        case twoOverSecondary
        case twoDisplaceSecondary
        case supplementary
    }

    public enum DisplayModeButtonVisibility: Int {
        case automatic
        case never
        case always
    }

    public enum SplitBehavior: Int {
        case automatic
        case tile
        case overlay
        case displace
    }

    public enum Column: Int {
        case primary
        case supplementary
        case secondary
        case compact
        #if compiler(>=6.2)
        case inspector
        #endif
    }

    public enum Style: Int {
        case unspecified
        case doubleColumn
        case tripleColumn
    }

    public enum PrimaryEdge: Int {
        case leading
        case trailing
    }

    public enum BackgroundStyle: Int {
        case none
        case sidebar
    }

    public enum LayoutEnvironment: Int {
        case none
        case expanded
        case collapsed
    }

    public func show(_: DisplayMode) {}
    public func show(_: Column) {}
    public var preferredDisplayMode: DisplayMode = .automatic
    public var displayModeButtonVisibility: DisplayModeButtonVisibility = .automatic
    public var preferredSplitBehavior: SplitBehavior = .automatic
    public var preferredPrimaryColumnWidthFraction: CGFloat = 0
    public var primaryEdge: PrimaryEdge = .leading
    public var style: Style = .unspecified
}

@MainActor open class UINavigationController: UIViewController {
    public var navigationBar = UINavigationBar()
    open weak var delegate: (any UINavigationControllerDelegate)?
    public var interactivePopGestureRecognizer: UIGestureRecognizer? = UIGestureRecognizer()
    public var interactiveContentPopGestureRecognizer: UIGestureRecognizer? = UIGestureRecognizer()
    public private(set) var isNavigationBarHidden = false
    public var viewControllers: [UIViewController] {
        get { topViewController.map { [$0] } ?? [] }
        set { topViewController = newValue.last }
    }
    open func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        isNavigationBarHidden = hidden
    }
    /// Replaces the controller stack. `animated` is accepted and ignored —
    /// there is no push/pop transition to run. Model-level only: the stack is
    /// flattened to `topViewController` (the last entry), matching how
    /// `viewControllers` is modeled above.
    open func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        self.viewControllers = viewControllers
    }
    public init(rootViewController: UIViewController) {
        super.init(nibName: nil, bundle: nil)
        topViewController = rootViewController
    }
    public init(navigationBarClass: AnyClass?, toolbarClass: AnyClass?) {
        super.init(nibName: nil, bundle: nil)
    }
    public convenience init() { self.init(navigationBarClass: nil, toolbarClass: nil) }
    public func pushViewController(_: UIViewController, animated: Bool) {}
    public func popViewController(animated: Bool) -> UIViewController? { nil }
    public var topViewController: UIViewController?
    public var visibleViewController: UIViewController? { topViewController }
    // modalPresentationStyle: the enum-typed UIViewController extension
    // member (UIViewControllerSurface.swift) is the one owner; an Int-typed
    // shadow here broke enum assignments through nav-typed receivers.

}

@MainActor public class UITabBarController: UIViewController {
    public var selectedViewController: UIViewController?
    public var viewControllers: [UIViewController]?
}

@MainActor open class UINavigationBar: UIView, UIBarPositioning {
    private static let appearanceProxy = UINavigationBar()
    public var topItem: UINavigationItem?
    public var isTranslucent: Bool = false
    public var barTintColor: UIColor?
    public var titleTextAttributes: [NSAttributedString.Key: Any]?
    public var largeTitleTextAttributes: [NSAttributedString.Key: Any]?
    open var barPosition: UIBarPosition { .top }

    public static func appearance() -> UINavigationBar {
        appearanceProxy
    }
}

@MainActor public class UINavigationItem: NSObject {
    public var rightBarButtonItem: UIBarButtonItem?
    public var rightBarButtonItems: [UIBarButtonItem]?
    public var leftBarButtonItem: UIBarButtonItem?
    public var title: String?
}

/// `open` + @MainActor, like UIKit's: SignalUI subclasses it cross-module
/// (ClosureBarButtonItem in UIButton+SignalUI.swift keeps a closure handler
/// alive as the target) and layers convenience inits over these (every one
/// delegates to a real initializer here, then sets accessibilityIdentifier).
/// The old stubs took `style: Int`/`barButtonSystemItem: Int`, which could
/// never match upstream's `UIBarButtonItem.Style`/`.SystemItem` arguments.
@MainActor open class UIBarButtonItem: NSObject, @preconcurrency QuillSelectorDispatching {
    /// Linux target-action dispatch base (no ObjC runtime); roots the override
    /// chain for `@objc`-action UIBarButtonItem subclasses. Class-body, not an
    /// extension. `@preconcurrency`: nonisolated requirement, @MainActor witness
    /// — see UIResponder. See QuillSelectorDispatching (QuillFoundation).
    open func quillPerform(_ selector: Selector, with sender: Any?) {}

    public enum Style: Int, Sendable {
        case plain = 0
        case bordered = 1
        case done = 2
    }

    /// Apple's raw values, kept exactly so compared/persisted values stay
    /// stable.
    public enum SystemItem: Int, Sendable {
        case done = 0, cancel, edit, save, add, flexibleSpace, fixedSpace,
             compose, reply, action, organize, bookmarks, search, refresh,
             stop, camera, trash, play, pause, rewind, fastForward, undo,
             redo, pageCurl, close
    }

    // UIBarItem surface (the shim flattens UIBarItem into this class — no
    // other UIBarItem subtype is ported).
    open var title: String?
    open var image: UIImage?
    open var landscapeImagePhone: UIImage?
    open var isEnabled = true

    open var style: Style = .plain
    open var customView: UIView?
    /// Weak, like UIKit's target-action convention; ClosureBarButtonItem
    /// retains its handler itself. No event backend fires the action on
    /// Linux yet — a native toolbar/navigation renderer will.
    open weak var target: AnyObject?
    open var action: Selector?
    /// Which system item this button was created from. Apple keeps this
    /// private; recorded (quill-prefixed) for the future native renderer.
    public private(set) var quillSystemItem: SystemItem?

    public override init() { super.init() }

    public convenience init(image: UIImage?, style: Style, target: Any?, action: Selector?) {
        self.init()
        self.image = image
        self.style = style
        self.target = target as AnyObject?
        self.action = action
    }

    public convenience init(image: UIImage?, landscapeImagePhone: UIImage?, style: Style, target: Any?, action: Selector?) {
        self.init(image: image, style: style, target: target, action: action)
        self.landscapeImagePhone = landscapeImagePhone
    }

    public convenience init(title: String?, style: Style, target: Any?, action: Selector?) {
        self.init()
        self.title = title
        self.style = style
        self.target = target as AnyObject?
        self.action = action
    }

    public convenience init(barButtonSystemItem systemItem: SystemItem, target: Any?, action: Selector?) {
        self.init()
        self.quillSystemItem = systemItem
        self.target = target as AnyObject?
        self.action = action
    }

    public convenience init(image: UIImage?, menu: UIMenu) {
        self.init(image: image, style: .plain, target: nil, action: nil)
        self.menu = menu
    }

    public convenience init(customView: UIView) {
        self.init()
        self.customView = customView
    }

    open var menu: UIMenu?

    // MARK: Accessibility
    // Same posture as UIView's block above: stored, overridable, read by
    // no assistive technology on Linux. SignalUI's convenience inits set
    // accessibilityIdentifier from every call site.
    open var isAccessibilityElement: Bool = false
    open var accessibilityIdentifier: String?
    open var accessibilityLabel: String?
    open var accessibilityValue: String?
    open var accessibilityHint: String?
    open var accessibilityTraits: UIAccessibilityTraits = .none
}

// UITableView/UICollectionView families: open + UIScrollView-rooted (Apple's
// hierarchy; Signal subclasses both and reads scroll geometry through them).
// The wider member surface lives in UITableViewExtras.swift /
// UICollectionViewExtras.swift; only what MUST be class-body (subclass
// override points, designated inits, stored enum cases) sits here.
@MainActor open class UITableView: UIScrollView {
    /// Apple's default is automaticDimension (-1), not 0. (The static lives
    /// in UITableViewExtras.swift; same-module visibility.)
    public var rowHeight: CGFloat = UITableView.automaticDimension
    public var sectionIndexColor: UIColor?
    // init(frame:style:), style, reloadData and the rest of the member
    // surface live in UITableViewExtras.swift.
}

@MainActor open class UITableViewCell: UIView {
    private static let appearanceProxy = UITableViewCell(style: .default, reuseIdentifier: nil)
    public static func appearance() -> UITableViewCell { appearanceProxy }

    public enum CellStyle: Int { case `default`, value1, value2, subtitle }
    public private(set) var reuseIdentifier: String?
    public required init(style: CellStyle, reuseIdentifier: String?) {
        super.init(frame: .zero)
        self.reuseIdentifier = reuseIdentifier
    }
    public convenience init() { self.init(style: .default, reuseIdentifier: nil) }
    public var textLabel: UILabel?
    public var detailTextLabel: UILabel?
    public var imageView: UIImageView?

    /// A custom trailing accessory view (wins over `accessoryType` on Apple).
    /// CLASS-BODY `open`, not extension: SignalUI's ContactTableViewCell
    /// overrides it with a `didSet`, which an extension member cannot satisfy.
    /// Pure storage — no layout pass places it yet. (`accessoryType` and the
    /// rest of the cell surface live in UITableViewExtras.swift.)
    open var accessoryView: UIView?

    // Subclass override points (upstream overrides them with super calls).
    // isSelected/isHighlighted are the side-table accessors in
    // UITableViewExtras.swift; same-module assignment works from here.
    open func setSelected(_ selected: Bool, animated: Bool) { isSelected = selected }
    open func setHighlighted(_ highlighted: Bool, animated: Bool) { isHighlighted = highlighted }
    open func prepareForReuse() {}
}

@MainActor open class UICollectionView: UIScrollView {
    public init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame)
        self.collectionViewLayout = layout
    }
    public func cellForItem(at: IndexPath) -> UICollectionViewCell? { nil }
    open func reloadData() {}
}

@MainActor open class UICollectionViewCell: UIView {
    public var contentView = UIView()
    public var backgroundConfiguration: Any?
    open var isHighlighted: Bool = false
    open var isSelected: Bool = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(contentView)
    }
    public convenience init() { self.init(frame: .zero) }
    public required init?(coder: NSCoder) {
        super.init(frame: .zero)
        addSubview(contentView)
    }
    open func prepareForReuse() {}
}

@MainActor public class UIAlertController: UIViewController {
    public init(title: String?, message: String?, preferredStyle: Int) {
        super.init(nibName: nil, bundle: nil)
    }
    public func addAction(_: Any) {}
    // popoverPresentationController is inherited from UIViewController.
}

public class UIAlertAction: NSObject {
    public init(title: String?, style: Int, handler: ((UIAlertAction) -> Void)? = nil) {}
}

// UIAction lives in UIEventsMenus.swift with the rest of the menu-element
// hierarchy (it subclasses UIMenuElement, so upstream
// `UIMenu(children: [UIAction...])` arrays upcast). The loosely-typed stub
// that sat here was removed in its favor.

@MainActor public class UIPopoverPresentationController: NSObject {
    public var barButtonItem: UIBarButtonItem?
    public var sourceView: UIView?
    public var sourceRect: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
    public var permittedArrowDirections: UIPopoverArrowDirection = .any
}

public struct UIPopoverArrowDirection: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let up = UIPopoverArrowDirection(rawValue: 1 << 0)
    public static let down = UIPopoverArrowDirection(rawValue: 1 << 1)
    public static let left = UIPopoverArrowDirection(rawValue: 1 << 2)
    public static let right = UIPopoverArrowDirection(rawValue: 1 << 3)
    public static let any: UIPopoverArrowDirection = [.up, .down, .left, .right]
    public static let unknown = UIPopoverArrowDirection(rawValue: 1 << 4)
}

@MainActor public protocol UIPopoverPresentationControllerDelegate: AnyObject {}

@MainActor public class UIActivityViewController: UIViewController {
    public init(url: URL, title: String?, applicationActivities: [Any]?) {
        super.init(nibName: nil, bundle: nil)
    }
    public init(activityItems: [Any], applicationActivities: [Any]?) {
        super.init(nibName: nil, bundle: nil)
    }
}

public class UIPasteboard: NSObject {
    @MainActor public static let general = UIPasteboard()
    public var url: URL?
    public var string: String?
    public var image: UIImage?
}

@MainActor public class SLComposeServiceViewController: UIViewController {
    public var placeholder: String?
    public func configurationItems() -> [Any]! { nil }
}

public class SLComposeSheetConfigurationItem: NSObject {
    public override init() { super.init() }
    public var title: String?
    public var value: String?
    public var tapHandler: (() -> Void)?
}

// `open` (not just `public`) so framework shims can subclass it cross-module —
// e.g. UIKitShim's `UISwitch: UIControl`. UIView is already open; UIControl is
// open on iOS too.
@MainActor open class UIControl: UIView {
    public enum ContentHorizontalAlignment: Int, Sendable {
        case center
        case left
        case right
        case fill
        case leading
        case trailing
    }

    public struct State: OptionSet, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let normal: State = []
        public static let highlighted = State(rawValue: 1 << 0)
        public static let disabled = State(rawValue: 1 << 1)
        public static let selected = State(rawValue: 1 << 2)
        public static let focused = State(rawValue: 1 << 3)
        public static let application = State(rawValue: 0x00FF_0000)
        public static let reserved = State(rawValue: 0xFF00_0000)
    }

    open var isEnabled = true
    open var isSelected = false
    open var isHighlighted = false
    open var state: State = .normal
}

@MainActor open class UIButton: UIControl {
    public var imageView: UIImageView?
    // (accessibilityLabel moved up to the UIView class body — one
    // declaration, overridable — matching Apple, where UIButton inherits it.)
    public func setTitle(_: String?, for: Any) {}
    open var menu: UIMenu?
    open var showsMenuAsPrimaryAction: Bool = false
    open var contentHorizontalAlignment: UIControl.ContentHorizontalAlignment = .center
    open func sizeToFit() {}
}

@MainActor open class UIImageView: UIView {
    // (contentMode moved up to the UIView class body — one declaration,
    // overridable — matching Apple, where UIImageView inherits it.)
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public convenience init() {
        self.init(frame: .zero)
    }

    public init(image: UIImage?) {
        super.init(frame: .zero)
        self.image = image
    }
    public var image: UIImage?
    public var highlightedImage: UIImage?
}

@MainActor open class UILabel: UIView {
    public var text: String?
    /// MODEL HONESTY: stored independently of `text` (real UIKit derives the
    /// plain string from it); no text engine consumes either on Linux yet.
    public var attributedText: NSAttributedString?
    // Platform-gated: on macOS UIColor aliases real NSColor, which spells
    // this semantic color `labelColor`; only the Linux RSColor has `label`.
    #if os(macOS)
    public var textColor: UIColor! = .labelColor
    #else
    public var textColor: UIColor! = .label
    #endif
    public var numberOfLines: Int = 1
    // Module-qualified: on macOS this file imports real AppKit alongside
    // QuillFoundation, and the shared text-layout enums (NSTextLayoutShared.swift)
    // would tie with AppKit's under unqualified lookup. No-op on Linux.
    public var lineBreakMode: QuillFoundation.NSLineBreakMode = .byTruncatingTail
    public var textAlignment: QuillFoundation.NSTextAlignment = .natural
    /// Recorded but inert: nothing measures or shrinks text on Linux yet.
    public var adjustsFontSizeToFitWidth = false
    public var minimumScaleFactor: CGFloat = 0
    /// Dynamic Type opt-in (UIContentSizeCategoryAdjusting). Faithful STATE:
    /// recorded, but UIFontMetrics is identity on Linux so nothing rescales.
    public var adjustsFontForContentSizeCategory = false
    /// Recorded but inert, like adjustsFontSizeToFitWidth.
    public var allowsDefaultTighteningForTruncation = false
    /// Recorded for layout code that reads it back; no intrinsic-size pass
    /// consumes it on Linux yet.
    public var preferredMaxLayoutWidth: CGFloat = 0
    /// Backing store for `font`. The UIFont-typed accessor cannot live here:
    /// UIFont is declared in the UIKit shim module, which depends on this one,
    /// so the shim layers `font: UIFont!` over this slot (UIFontExtras.swift).
    public var quillFontStorage: AnyObject?

    /// UILabel's text-drawing override point. Signal subclasses (CVCapsuleLabel)
    /// override this and call super; there is no text renderer on Linux, so the
    /// base implementation is a no-op.
    open func drawText(in rect: CGRect) {
        _ = rect
    }

    /// The rect the label's text would occupy. MODEL HONESTY: with no text
    /// engine to measure glyphs, this returns the proposed bounds unchanged.
    open func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        _ = numberOfLines
        return bounds
    }
}

// UIVisualEffectView lives in UIEffects.swift with the UIVisualEffect family.

public struct UIKeyModifierFlags: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alphaShift = UIKeyModifierFlags(rawValue: 1 << 16)
    public static let shift = UIKeyModifierFlags(rawValue: 1 << 17)
    public static let control = UIKeyModifierFlags(rawValue: 1 << 18)
    public static let alternate = UIKeyModifierFlags(rawValue: 1 << 19)
    public static let command = UIKeyModifierFlags(rawValue: 1 << 20)
    public static let numericPad = UIKeyModifierFlags(rawValue: 1 << 21)
}

public class UIKeyCommand: NSObject {
    public static let inputEscape = "\u{1B}"
    public let input: String
    public let modifierFlags: UIKeyModifierFlags
    public let action: Selector

    public init(input: String, modifierFlags: UIKeyModifierFlags, action: Selector) {
        self.input = input
        self.modifierFlags = modifierFlags
        self.action = action
        super.init()
    }

    public init(title: String, image: Any?, action: Selector, input: String, modifierFlags: UIKeyModifierFlags, propertyList: Any? = nil) {
        _ = title
        _ = image
        _ = propertyList
        self.input = input
        self.modifierFlags = modifierFlags
        self.action = action
        super.init()
    }
}

public protocol UIViewControllerTransitionCoordinatorContext: AnyObject {
    var isCancelled: Bool { get }
}

public final class QuillUIViewControllerTransitionCoordinatorContext: UIViewControllerTransitionCoordinatorContext {
    public let isCancelled: Bool
    public init(isCancelled: Bool = false) {
        self.isCancelled = isCancelled
    }
}

public protocol UIViewControllerTransitionCoordinator: AnyObject {
    @MainActor func animate(
        alongsideTransition: ((UIViewControllerTransitionCoordinatorContext) -> Void)?,
        completion: ((UIViewControllerTransitionCoordinatorContext) -> Void)?
    )
}

@MainActor public protocol UIActivityItemSource: AnyObject {
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any?
}

public extension UIActivityItemSource {
    @MainActor func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> Any? {
        _ = activityViewController
        return nil
    }
}

open class UIActivity: NSObject {
    public override init() {}
    open var activityTitle: String? { nil }
    open var activityImage: UIImage? { nil }

    public struct ActivityType: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }
    open var activityType: ActivityType? { nil }

    public enum Category: Int { case action, share }
    open class var activityCategory: Category { .action }
    open func canPerform(withActivityItems: [Any]) -> Bool { true }
    open func prepare(withActivityItems: [Any]) {}
    open func perform() {}
    public func activityDidFinish(_: Bool) {}
}

// THE canonical UIApplication (the UIKit shim re-exports this module; a twin
// declaration there made `UIApplication.shared` ambiguous once SwiftUI began
// re-exporting AppKit, whose QuillUIKit re-export exposes this copy).
public class UIApplication: NSObject, @unchecked Sendable {
    @MainActor public static let shared = UIApplication()
    @MainActor @discardableResult public func open(
        _ url: URL,
        options: [AnyHashable: Any] = [:],
        completionHandler: ((Bool) -> Void)? = nil
    ) -> Bool {
        #if canImport(AppKit) && !os(Linux)
        let didOpen = NSWorkspace.shared.open(url)
        completionHandler?(didOpen)
        return didOpen
        #elseif os(Linux)
        let didOpen = QuillWorkspace.open(url)
        completionHandler?(didOpen)
        return didOpen
        #else
        completionHandler?(false)
        return false
        #endif
    }
    @MainActor public func canOpenURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        return ["http", "https", "mailto", "tel"].contains(scheme) || scheme.contains(".")
    }
    // Async form used by SwiftUI/UIKit real source (`await UIApplication.shared.open(url)`).
    // Disambiguate to the completion-handler overload to avoid recursing into itself.
    @MainActor @discardableResult public func open(_ url: URL) async -> Bool {
        open(url, options: [:], completionHandler: nil)
    }
    @MainActor public func registerForRemoteNotifications() {
        QuillNotificationService.shared.registerForRemoteNotifications()
    }
    @MainActor public func unregisterForRemoteNotifications() {
        QuillNotificationService.shared.unregisterForRemoteNotifications()
    }
    @MainActor public var isRegisteredForRemoteNotifications: Bool {
        QuillNotificationService.shared.remoteNotificationsRegistered
    }
    public enum LaunchOptionsKey: Hashable { case remoteNotification }
    @MainActor public var connectedScenes: Set<UIScene> = []
    @MainActor public var applicationState: UIApplicationState { .active }

    @MainActor @discardableResult public func sendAction(
        _ action: Selector,
        to target: Any?,
        from sender: Any?,
        for event: UIEvent?
    ) -> Bool {
        _ = event
        (target as? QuillSelectorDispatching)?.quillPerform(action, with: sender)
        return target is QuillSelectorDispatching
    }

    /// UIKit (and SignalServiceKit's AppContext) name the application-state enum
    /// `UIApplication.State`; `UIApplicationState` is its top-level alias on iOS.
    public typealias State = UIApplicationState

    // App-lifecycle notification names. Real UIKit members; SignalServiceKit's
    // lifecycle observers subscribe to these. No source posts them on Linux yet.
    public static let didBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
    public static let willResignActiveNotification = Notification.Name("UIApplicationWillResignActiveNotification")
    public static let didEnterBackgroundNotification = Notification.Name("UIApplicationDidEnterBackgroundNotification")
    public static let willEnterForegroundNotification = Notification.Name("UIApplicationWillEnterForegroundNotification")
    public static let willTerminateNotification = Notification.Name("UIApplicationWillTerminateNotification")
    public static let didReceiveMemoryWarningNotification = Notification.Name("UIApplicationDidReceiveMemoryWarningNotification")
    public static let significantTimeChangeNotification = Notification.Name("UIApplicationSignificantTimeChangeNotification")
    public static let openSettingsURLString = "app-settings:"

    @MainActor public func setAlternateIconName(_ name: String?, completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }
    @MainActor public var alternateIconName: String? { nil }
}

public enum UIApplicationState: Int { case active, inactive, background }

public enum UIBackgroundFetchResult: Int, Sendable {
    case newData
    case noData
    case failed
}

public class UIMenuBuilder: NSObject {
    public struct Identifier: RawRepresentable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let document = Identifier(rawValue: "document")
        public static let toolbar = Identifier(rawValue: "toolbar")
    }

    public func remove(menu: Identifier) {
        _ = menu
    }
}

open class UIScene: NSObject {
    @MainActor public var delegate: Any?
}

// UIWindowScene + UIStatusBarManager live here (not in the UIKit shim) so the
// UIWindow class body can declare an `open` designated `init(windowScene:)`
// that SignalUI's OWSWindow overrides — an extension initializer in the shim
// cannot be overridden cross-module. Faithful MODEL: a window remembers the
// scene that vended it; nothing composites.

@MainActor public protocol UIWindowSceneDelegate: AnyObject {}

@MainActor public class UIWindowScene: UIScene {
    public var windows: [UIWindow] = []
    public var keyWindow: UIWindow? { windows.first }
    public var interfaceOrientation: UIInterfaceOrientation = .portrait
    public var statusBarManager: UIStatusBarManager? = UIStatusBarManager()
}

@MainActor public final class UIStatusBarManager: NSObject {
    public var statusBarFrame: CGRect = .zero
}

public class UITraitCollection: NSObject {
    public var userInterfaceStyle: UIUserInterfaceStyle = .unspecified
    public var userInterfaceIdiom: Int = 0
    public var userInterfaceLevel: UIUserInterfaceLevel = .unspecified
    public var accessibilityContrast: UIAccessibilityContrast = .unspecified
    public var layoutDirection: UIUserInterfaceLayoutDirection = .leftToRight
    /// UIKit's default Dynamic Type category is .large.
    public var preferredContentSizeCategory: UIContentSizeCategory = .large

    public convenience init(preferredContentSizeCategory: UIContentSizeCategory) {
        self.init()
        self.preferredContentSizeCategory = preferredContentSizeCategory
    }

    public convenience init(userInterfaceStyle: UIUserInterfaceStyle) {
        self.init()
        self.userInterfaceStyle = userInterfaceStyle
    }

    public convenience init(userInterfaceLevel: UIUserInterfaceLevel) {
        self.init()
        self.userInterfaceLevel = userInterfaceLevel
    }

    public convenience init(accessibilityContrast: UIAccessibilityContrast) {
        self.init()
        self.accessibilityContrast = accessibilityContrast
    }

    /// Apple's UITraitCollection(traitsFrom:) merge: later collections override
    /// earlier ones for every trait they actually specify. (Theme.swift builds
    /// its elevated light/dark trait collections this way.)
    public convenience init(traitsFrom traitCollections: [UITraitCollection]) {
        self.init()
        for traits in traitCollections {
            if traits.userInterfaceStyle != .unspecified {
                userInterfaceStyle = traits.userInterfaceStyle
            }
            if traits.userInterfaceIdiom != 0 {
                userInterfaceIdiom = traits.userInterfaceIdiom
            }
            if traits.userInterfaceLevel != .unspecified {
                userInterfaceLevel = traits.userInterfaceLevel
            }
            if traits.accessibilityContrast != .unspecified {
                accessibilityContrast = traits.accessibilityContrast
            }
            layoutDirection = traits.layoutDirection
            preferredContentSizeCategory = traits.preferredContentSizeCategory
        }
    }

    /// UIKit's thread-local "current" traits. Computed (a fresh default-trait
    /// instance per access, like the layout anchors) so there is no shared
    /// mutable static; Linux has a single default trait environment anyway.
    public static var current: UITraitCollection { UITraitCollection() }
}

// MARK: - UITrait + registerForTraitChanges (iOS 17)
//
// The iOS-17 trait-observation API. SignalUI passes trait *types*
// (`UITraitUserInterfaceStyle.self`, …) to `registerForTraitChanges` on its
// views and reacts in a handler — the modern replacement for
// `traitCollectionDidChange`. Faithful MODEL: the trait types are real marker
// types and the registration is recorded, but no trait ever changes on Linux,
// so the handlers never fire (exactly as `traitCollectionDidChange` never
// fires here). The registration object Apple returns is unused upstream, so a
// lightweight token stands in.

/// A bindable trait, identified by its type. Adopted by the marker trait
/// types below; `registerForTraitChanges` takes an array of these
/// metatypes.
public protocol UITrait {}

/// Light/dark interface style. (A marker type — the live value is read off
/// `traitCollection.userInterfaceStyle`, as upstream does inside the
/// handler.)
public enum UITraitUserInterfaceStyle: UITrait {}

/// Dynamic Type size category. Marker type.
public enum UITraitPreferredContentSizeCategory: UITrait {}

/// Vertical size class (compact/regular). Marker type.
public enum UITraitVerticalSizeClass: UITrait {}

/// Horizontal size class (compact/regular). Marker type.
public enum UITraitHorizontalSizeClass: UITrait {}

/// The opaque handle Apple returns from `registerForTraitChanges`. Inert
/// here (no registry to deregister from); upstream never inspects it.
public struct UITraitChangeRegistration: Hashable, Sendable {
    public init() {}
}

extension UIView {
    /// Registers a handler for changes to the given traits (iOS 17). The
    /// handler's first parameter is the observing object; its concrete type
    /// is inferred from the closure (`UILabel`, `Self`, a custom view, …).
    /// No trait ever changes on Linux, so the handler is stored-and-dropped;
    /// the returned token is inert. Trailing-closure form.
    @discardableResult
    public func registerForTraitChanges<T>(
        _ traits: [any UITrait.Type],
        handler: @escaping (T, UITraitCollection) -> Void
    ) -> UITraitChangeRegistration {
        UITraitChangeRegistration()
    }

    /// Target/action form (iOS 17). The selector is accepted and never
    /// invoked (no trait changes on Linux).
    @discardableResult
    public func registerForTraitChanges(
        _ traits: [any UITrait.Type],
        target: Any,
        action: Selector
    ) -> UITraitChangeRegistration {
        UITraitChangeRegistration()
    }

    /// No-op: there is no registry to remove from.
    public func unregisterForTraitChanges(_ registration: UITraitChangeRegistration) {}
}

public enum UIUserInterfaceLayoutDirection: Int, Sendable {
    case leftToRight = 0
    case rightToLeft = 1
}

public enum UISemanticContentAttribute: Int, Sendable {
    case unspecified = 0
    case playback = 1
    case spatial = 2
    case forceLeftToRight = 3
    case forceRightToLeft = 4
}

public final class UILocalizedIndexedCollation: NSObject {
    public static func current() -> UILocalizedIndexedCollation {
        UILocalizedIndexedCollation()
    }

    public var sectionTitles: [String] { [] }
    public var sectionIndexTitles: [String] { sectionTitles }

    public func section(forSectionIndexTitle titleIndex: Int) -> Int {
        titleIndex
    }

    public func section(for object: Any, collationStringSelector selector: Selector) -> Int {
        _ = (object, selector)
        return 0
    }

    public func sortedArray(from array: [Any], collationStringSelector selector: Selector) -> [Any] {
        _ = selector
        return array
    }
}

// MARK: - UIColor dynamic colors (trait-resolved)

#if os(Linux)
// Linux-only: UIColor is RSColor (QuillFoundation) with public RGBA storage;
// on macOS UIColor aliases real NSColor, which has no UITraitCollection-based
// dynamic-color surface. Lives here (not QuillFoundation) because the
// signatures need UITraitCollection — same placement precedent as
// UIColor.accessibilityName in UIAccessibilityExtras.swift.
public extension UIColor {
    /// Apple's UIColor(dynamicProvider:). RSColor stores one immutable RGBA
    /// value and no provider, so the closure is evaluated ONCE, against
    /// UITraitCollection.current (the single default/light trait environment
    /// on Linux), and that resolved color's components are copied.
    /// MODEL HONESTY: the color never re-resolves when traits change — dark
    /// variants supplied by the provider are not produced on Linux.
    convenience init(dynamicProvider: @escaping (UITraitCollection) -> UIColor) {
        let resolved = dynamicProvider(UITraitCollection.current)
        self.init(red: resolved._red, green: resolved._green, blue: resolved._blue, alpha: resolved._alpha)
    }

    /// Apple's UIColor.resolvedColor(with:) — resolves a dynamic color against
    /// specific traits. MODEL HONESTY: RSColor keeps no per-trait variants
    /// (any dynamicProvider was already folded at init), so this returns self
    /// regardless of the requested traits; Theme's dark-trait resolutions get
    /// the light value on Linux.
    func resolvedColor(with traitCollection: UITraitCollection) -> UIColor {
        _ = traitCollection
        return self
    }
}
#endif

/// Dynamic Type content size categories. Raw values match UIKit's so any
/// compared/persisted values stay stable. Faithful STATE only: UIFontMetrics
/// is identity on Linux, so no font actually rescales per category yet.
public struct UIContentSizeCategory: RawRepresentable, Equatable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let unspecified = UIContentSizeCategory(rawValue: "_UICTContentSizeCategoryUnspecified")
    public static let extraSmall = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXS")
    public static let small = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryS")
    public static let medium = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryM")
    public static let large = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryL")
    public static let extraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXL")
    public static let extraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXXL")
    public static let extraExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryXXXL")
    public static let accessibilityMedium = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityM")
    public static let accessibilityLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityL")
    public static let accessibilityExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXL")
    public static let accessibilityExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXXL")
    public static let accessibilityExtraExtraExtraLarge = UIContentSizeCategory(rawValue: "UICTContentSizeCategoryAccessibilityXXXL")

    public var isAccessibilityCategory: Bool {
        rawValue.hasPrefix("UICTContentSizeCategoryAccessibility")
    }

    /// Posted by UIKit when the user changes the preferred category; nothing
    /// posts it on Linux yet, but observers (OWSViewController) can subscribe.
    public static let didChangeNotification = Notification.Name("UIContentSizeCategoryDidChangeNotification")
}

@MainActor open class UIScrollView: UIView {
    public enum ContentInsetAdjustmentBehavior: Int {
        case automatic
        case scrollableAxes
        case never
        case always
    }

    public weak var delegate: UIScrollViewDelegate?
    open var contentInsetAdjustmentBehavior: ContentInsetAdjustmentBehavior = .automatic
    public var maximumZoomScale: CGFloat = 1
    public var minimumZoomScale: CGFloat = 1
    public var zoomScale: CGFloat = 1
    public var bouncesZoom: Bool = false
    public var showsHorizontalScrollIndicator: Bool = true
    public var showsVerticalScrollIndicator: Bool = true

    // MARK: - Content geometry (overridable: class body, not an extension)
    //
    // These were extension members (UIScrollViewExtras.swift). Apple declares
    // them `open`, and upstream subclasses across the scroll-view family override
    // them — but extension members "cannot be overridden", which produced the
    // bulk of the contentSize / scrollsToTop errors in the sig6 histogram. They
    // live in the class body now; their CGSize/CGPoint/Bool types are visible in
    // QuillUIKit, so there is no module-layering issue (unlike the
    // UIEdgeInsets-typed contentInset, which can't live here — UIEdgeInsets is
    // declared in the UIKit shim that DEPENDS on this module — and so stays an
    // extension accessor in UIScrollViewInsets.swift; UITextView, which DOES
    // override the insets, carries its own UIEdgeInsets-typed class-body copies
    // there). The remaining scroll surface (configuration flags, gesture
    // recognizers, live-interaction state) stays in UIScrollViewExtras.swift;
    // nothing overrides it.

    /// The origin of the visible content region. On Apple a scroll view scrolls
    /// by translating its own bounds, and `contentOffset` is that translation —
    /// modeled identically here (`bounds.origin`), so any geometry code sees
    /// programmatic scrolls. Setting a new value notifies `scrollViewDidScroll`,
    /// as Apple's setter does.
    open var contentOffset: CGPoint {
        get { bounds.origin }
        set {
            guard bounds.origin != newValue else { return }
            bounds.origin = newValue
            delegate?.scrollViewDidScroll(self)
        }
    }

    /// Scrolls to the given offset. MODEL HONESTY: there is no animation backend,
    /// so `animated: true` completes instantly — `scrollViewDidScroll` fires from
    /// the offset change and `scrollViewDidEndScrollingAnimation` fires
    /// synchronously (Apple fires it only for animated changes that actually
    /// animate, so a same-offset call stays silent, as on Apple).
    open func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        guard self.contentOffset != contentOffset else { return }
        self.contentOffset = contentOffset
        if animated {
            delegate?.scrollViewDidEndScrollingAnimation(self)
        }
    }

    /// The size of the scrollable content. Faithful storage; nothing on Linux
    /// derives it from subview layout yet.
    open var contentSize: CGSize = .zero

    /// Whether a status-bar tap scrolls to the top. Apple's default: true.
    open var scrollsToTop: Bool = true

    /// Scrolls the minimum distance needed to bring `rect` (content coordinates)
    /// into the visible region, clamped to the content bounds — Apple's
    /// documented behavior, computed from the live model geometry. A rect already
    /// visible (or a degenerate viewport) scrolls nothing.
    open func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        var offset = contentOffset
        if bounds.width > 0 {
            if rect.maxX > offset.x + bounds.width { offset.x = rect.maxX - bounds.width }
            if rect.minX < offset.x { offset.x = rect.minX }
            offset.x = min(max(0, offset.x), max(0, contentSize.width - bounds.width))
        }
        if bounds.height > 0 {
            if rect.maxY > offset.y + bounds.height { offset.y = rect.maxY - bounds.height }
            if rect.minY < offset.y { offset.y = rect.minY }
            offset.y = min(max(0, offset.y), max(0, contentSize.height - bounds.height))
        }
        setContentOffset(offset, animated: animated)
    }

    public func setZoomScale(_ scale: CGFloat, animated: Bool) {
        _ = animated
        zoomScale = min(max(scale, minimumZoomScale), maximumZoomScale)
    }

    public func zoom(to rect: CGRect, animated: Bool) {
        _ = rect
        setZoomScale(maximumZoomScale, animated: animated)
    }
}

public protocol UIScrollViewDelegate: AnyObject {
    @MainActor func scrollViewDidScroll(_: UIScrollView)
}

public extension UIScrollViewDelegate {
    @MainActor func scrollViewDidScroll(_: UIScrollView) {}
    @MainActor func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
    @MainActor func scrollViewDidEndZooming(_: UIScrollView, with view: UIView?, atScale scale: CGFloat) {}
}

// UIGestureRecognizer (base + tap/long-press/pan/pinch recognizers, the
// delegate protocol, and the UIView add/removeGestureRecognizer extension)
// lives in UIGestureRecognizers.swift.

public class UIApplicationShortcutItem: NSObject {
    public var type: String = ""
}

// UNUserNotificationCenter / UNUserNotificationCenterDelegate moved to the
// dedicated `UserNotifications` shim (Sources/AppleFrameworkShims/UserNotifications),
// which the `UIKit` shim re-exports — so `import UIKit` still resolves them while
// SignalServiceKit's `import UserNotifications` no longer collides with a second
// declaration here (the ambiguity that blocked the notifications presenter).

@MainActor public protocol UIApplicationDelegate: AnyObject {}

public typealias UIBackgroundTaskIdentifier = Int
public extension UIBackgroundTaskIdentifier {
    static let invalid = 0
}

public class UIBackgroundConfiguration: NSObject {
    public static func listGroupedCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public static func listSidebarCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public var visualEffect: UIVisualEffect?
}

public class UIStoryboard: NSObject {
    @MainActor public static let settings = UIStoryboard()
    @MainActor public static let add = UIStoryboard()
    @MainActor public func instantiateInitialViewController() -> UIViewController? { nil }
    @MainActor public func instantiateViewController(withIdentifier: String) -> UIViewController? { nil }
}

public extension IndexPath {
    // Real reads over Foundation.IndexPath's [section, row] ordering (UIKit's
    // outer/inner convention — matches the inits in UICollectionViewExtras
    // and the SSK port). The old hardcoded zeros silently misrouted every
    // multi-section table.
    var row: Int { count >= 2 ? self[1] : 0 }
    var section: Int { count >= 1 ? self[0] : 0 }
}

public class NonIntrinsicImageView: UIImageView {}

#endif // !os(iOS)

// MARK: - AuthenticationServices
// (The ASWebAuthentication* stubs that used to live here moved to the dedicated
// `AuthenticationServices` shim — Sources/AppleFrameworkShims/AuthenticationServices.
// Keeping a duplicate here caused an ambiguous-type-lookup error once a module
// re-exported both QuillUIKit and AuthenticationServices, e.g. SignalServiceKit
// re-exporting UIKit while its PayPal flow does `import AuthenticationServices`.)
