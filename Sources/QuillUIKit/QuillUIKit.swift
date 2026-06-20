// QuillUIKit
// ==========
// UIKit (UI*) shadow types for platforms where Apple's UIKit isn't
// available (Linux, macOS without iOS support). On iOS this is empty —
// QuillFoundation already re-exports the real UIKit framework. On
// macOS we provide UIKit-shaped types so iOS-targeted upstream code
// (NetNewsWire iOS, Ice Cubes iOS, etc.) can compile under Mac Catalyst /
// macOS-as-iOS-host configurations.
//
// AuthenticationServices stubs live in the `AuthenticationServices` shim target
// so AS* names do not collide with UIKit-shaped aliases.

import QuillFoundation
import QuillKit

#if os(Linux)
// CALayer for UIView.layer. On Apple platforms the real QuartzCore arrives
// transitively via AppKit/UIKit; on Linux it's the in-tree shim module.
import QuartzCore
#endif

#if os(iOS)
// On iOS the real UIKit / WebKit are auto-imported.
#elseif os(macOS)
import AppKit
#endif

#if !os(iOS)

// MARK: - UIResponder / UIView / UIViewController stubs

@MainActor open class UITextInputAssistantItem: NSObject {
    open var leadingBarButtonGroups: [UIBarButtonItemGroup] = []
    open var trailingBarButtonGroups: [UIBarButtonItemGroup] = []
}

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

    /// NSObject's ObjC message-forwarding hook. Declared `open` in the CLASS BODY
    /// (not an extension of corelibs `NSObject`, which can't be overridden) so
    /// BodyRangesTextView can `override` it and call `super.forwardingTarget(for:)`.
    /// The lowering adds the `override` keyword to such upstream declarations.
    /// MODEL HONESTY: no ObjC runtime on Linux, so nothing forwards — returns nil.
    #if os(Linux)
    open func forwardingTarget(for aSelector: Selector!) -> Any? { nil }
    #else
    open override func forwardingTarget(for aSelector: Selector!) -> Any? { nil }
    #endif

    open var next: UIResponder? { nil }

    /// Apple's default: no accessory view (ContactShareViewController
    /// overrides this with a super call).
    open var inputAccessoryView: UIView? { nil }

    /// The shortcut bar model exposed above the keyboard. Linux has no system
    /// keyboard UI yet; this records the same mutable groups upstream code
    /// saves/restores around text input mode changes.
    open var inputAssistantItem = UITextInputAssistantItem()

    /// Apple's responder-level undo manager. QuillFoundation supplies the
    /// Linux clone of Foundation.UndoManager, so text views can clear/register
    /// undo actions without depending on AppKit.
    open var undoManager: UndoManager? = UndoManager()

    /// Invalidates input views on Apple. There is no input-view host on Linux
    /// yet, so the call is a faithful no-op.
    open func reloadInputViews() {}

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

    // MARK: Edit menu / standard editing actions
    //
    // CLASS-BODY, not extension: Signal subclasses override these standard
    // editing-action methods AND call up through super (text views, message
    // cells, ActionSheet). On Apple these are part of UIResponderStandardEdit
    // Actions, implemented by UIResponder; there is no responder chain or edit
    // menu on Linux, so the bases are honest no-ops and canPerformAction
    // refuses everything (Apple's UIResponder default is also false — a
    // subclass opts in per action).
    open func cut(_ sender: Any?) { _ = sender }
    open func copy(_ sender: Any?) { _ = sender }
    open func paste(_ sender: Any?) { _ = sender }
    open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        _ = action
        _ = sender
        return false
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

public class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {
    public func constraint(equalToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        NSLayoutConstraint(first: self, relation: .equal, second: anchor, multiplier: multiplier, constant: 8 * multiplier)
    }
}
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

/// Apple's UIUserInterfaceIdiom. Declared here (not in the UIKit umbrella) so
/// `UITraitCollection.userInterfaceIdiom` below can be typed with it; the
/// umbrella re-exports it under the same name. Raw values match UIKit's
/// (.unspecified == -1).
public enum UIUserInterfaceIdiom: Int, Sendable {
    case unspecified = -1, phone = 0, pad = 1, tv = 2, carPlay = 3, mac = 5, vision = 6
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

    /// View-created guides keep their own identity so the layout pass can
    /// distinguish safe-area edges from layout-margin edges. Free-standing
    /// guides added with addLayoutGuide(_:) still alias the owning view's full
    /// bounds until Quill has a real guide solver.
    weak var quillAliasedView: UIView?
    private var quillAnchorItem: AnyObject { self }

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

    /// iOS 26 corner-adaptation hint for `Source.margins` — whether the guide
    /// should pull in to avoid rounded display corners / window controls along an
    /// axis. Recorded-intent only on Linux.
    public enum Adaptivity: Sendable {
        case automatic
        case none
        case horizontal
        case vertical
    }

    /// iOS 26 `UILayoutGuide.Source`, the argument to `UIView.layoutGuide(for:)`.
    public enum Source: Sendable {
        case margins(cornerAdaptation: Adaptivity)
        case safeArea
    }
}

#if !os(macOS)
public struct UIWindowLevel: RawRepresentable, Equatable, Comparable, Sendable {
    public var rawValue: CGFloat
    public init(rawValue: CGFloat) { self.rawValue = rawValue }

    public static let normal = UIWindowLevel(rawValue: 0)
    public static let _background = UIWindowLevel(rawValue: -1)

    public static func < (lhs: UIWindowLevel, rhs: UIWindowLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

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
    // UIView's required init?(coder:) is no longer inherited once this class
    // declares its own designated inits above; restate it (OWSWindow's faithful
    // override needs a base to override).
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    open var screen: UIScreen = .main
    open var windowLevel: UIWindowLevel = .normal
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
        public static let width = flexibleWidth
        public static let height = flexibleHeight
    }

    // Apple's UIView has NO designated init() — only init(frame:). The old
    // `override init()` here was an invented designated init, which made
    // upstream subclasses' `public init()` declarations demand `override`.
    public convenience override init() { self.init(frame: .zero) }

    /// Custom-drawing override point (CVTextLabel). Nothing rasterizes
    /// UIView.draw on Linux yet; subclass implementations run when a
    /// future compositor calls them.
    open func draw(_ rect: CGRect) { _ = rect }
    /// Optional renderer metadata for custom-drawn text views. Some upstream
    /// UIKit components draw text from `draw(_:)` instead of using `UILabel`;
    /// render backends can consume these fields without knowing app-private
    /// view subclasses.
    public var quillRenderedText: String?
    public var quillRenderedTextColor: UIColor?
    public var quillRenderedTextPointSize: CGFloat = 17
    public var quillRenderedTextAlignment: QuillFoundation.NSTextAlignment = .natural
    public var quillRenderedTextNumberOfLines: Int = 0
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
        self.bounds = CGRect(origin: .zero, size: frame.size)
    }

    // Apple's UIView declares `public required init?(coder:)`. It must live on
    // the base for two reasons that together drive ~hundreds of lowered errors:
    //   1. Signal's faithful subclasses declare `required init?(coder:)` (the
    //      `fatalError("init(coder:) has not been implemented")` boilerplate
    //      Xcode generates). Without a `required init?(coder:)` here, those are
    //      "initializer does not override a designated initializer," and a
    //      subclass that adds its own designated init hits "initializer
    //      'init(coder:)' must be provided by subclass."
    //   2. `required` (not plain) is what lets a subclass that adds NO new init
    //      INHERIT it instead of being forced to restate it.
    // No NSCoder archive is ever decoded on Linux; this builds an empty view.
    public required init?(coder: NSCoder) {
        super.init()
        _ = coder
    }

    // `open` (not just `public`): Signal subclasses override frame/bounds with
    // didSet observers everywhere (CVImageView, ManualLayoutView, OWSLayerView,
    // …) and that requires the stored property itself to be overridable
    // cross-module.
    open var frame: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0) {
        didSet {
            if bounds.size != frame.size {
                bounds.size = frame.size
            }
            if oldValue.size != frame.size {
                setNeedsLayout()
            }
            if oldValue != frame {
                quillNotifyViewMutation()
                superview?.quillNotifySubviewMutation()
            }
            #if os(Linux)
            _layer?.frame = frame
            #endif
        }
    }
    open var bounds: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0) {
        didSet {
            if oldValue.size != bounds.size {
                setNeedsLayout()
            }
            if oldValue != bounds {
                quillNotifyViewMutation()
                superview?.quillNotifySubviewMutation()
            }
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

    /// Whether subviews are resized when this view's bounds change. Apple's
    /// default is true. Faithful STATE: there is no autoresizing pass on Linux
    /// (Auto Layout drives all measured ports), so nothing reads it back yet —
    /// but it is `open` + stored so the rare subclass that overrides it
    /// resolves cross-module.
    open var autoresizesSubviews: Bool = true

    open func removeFromSuperview() {
        let oldSuperview = superview
        // Apple notifies the (old) superview before the subview leaves, so the
        // hook still sees `self` in `subviews`.
        oldSuperview?.willRemoveSubview(self)
        oldSuperview?.subviews.removeAll { $0 === self }
        superview = nil
        #if os(Linux)
        _layer?.removeFromSuperlayer()
        #endif
        oldSuperview?.setNeedsLayout()
        oldSuperview?.quillNotifySubviewMutation()
    }
    // `open` (not just `public`): a classic overridable Apple UIView property
    // — Signal subclasses override backgroundColor with didSet observers.
    open var backgroundColor: UIColor?
    open func addSubview(_ view: UIView) {
        view.willMove(toWindow: window)
        view.removeFromSuperview()
        subviews.append(view)
        view.superview = self
        view.window = window
        #if os(Linux)
        layer.addSublayer(view.layer)
        #endif
        // Apple calls didAddSubview on the receiver after the subview is in
        // place (so overrides can observe the new child).
        didAddSubview(view)
        setNeedsLayout()
        quillNotifySubviewMutation()
    }

    // MARK: Subview observation hooks
    //
    // CLASS-BODY, not extension: subclasses override these and call super.
    // Apple's defaults are empty; the install/remove paths above fire them at
    // the documented moments.
    open func didAddSubview(_ subview: UIView) { _ = subview }
    open func willRemoveSubview(_ subview: UIView) { _ = subview }
    #if os(Linux)
    open func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        _ = (keyPath, object, change, context)
    }
    #else
    open override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        _ = (keyPath, object, change, context)
    }
    #endif

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
        // Apple fires didAddSubview for every insertion path.
        didAddSubview(view)
        setNeedsLayout()
        quillNotifySubviewMutation()
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
    // `open` (not just `public`): these are the well-known overridable Apple
    // UIView properties — Signal subclasses override them (often with didSet
    // observers) and that requires the stored property itself to be
    // overridable cross-module.
    public var quillViewMutationHandler: ((UIView) -> Void)?
    private var quillViewMutationHandlers: [String: (UIView) -> Void] = [:]
    public func quillNotifyViewMutation() {
        quillViewMutationHandler?(self)
        for key in quillViewMutationHandlers.keys.sorted() {
            quillViewMutationHandlers[key]?(self)
        }
    }
    public func quillAppendViewMutationHandler(_ handler: @escaping (UIView) -> Void) {
        let previous = quillViewMutationHandler
        quillViewMutationHandler = { view in
            previous?(view)
            handler(view)
        }
    }
    public func quillSetViewMutationHandler(
        _ key: String,
        _ handler: @escaping (UIView) -> Void
    ) {
        quillViewMutationHandlers[key] = handler
    }
    public var quillSubviewMutationHandler: ((UIView) -> Void)?
    private var quillSubviewMutationHandlers: [String: (UIView) -> Void] = [:]
    public func quillNotifySubviewMutation() {
        quillSubviewMutationHandler?(self)
        for key in quillSubviewMutationHandlers.keys.sorted() {
            quillSubviewMutationHandlers[key]?(self)
        }
    }
    public func quillAppendSubviewMutationHandler(_ handler: @escaping (UIView) -> Void) {
        let previous = quillSubviewMutationHandler
        quillSubviewMutationHandler = { view in
            previous?(view)
            handler(view)
        }
    }
    public func quillSetSubviewMutationHandler(
        _ key: String,
        _ handler: @escaping (UIView) -> Void
    ) {
        quillSubviewMutationHandlers[key] = handler
    }

    open var isHidden: Bool = false {
        didSet {
            if oldValue != isHidden {
                quillNotifyViewMutation()
                superview?.quillNotifySubviewMutation()
            }
        }
    }
    open var isUserInteractionEnabled: Bool = true {
        didSet {
            if oldValue != isUserInteractionEnabled { quillNotifyViewMutation() }
        }
    }
    open var alpha: CGFloat = 1.0 {
        didSet {
            if oldValue != alpha { quillNotifyViewMutation() }
        }
    }
    open var tintColor: UIColor?
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

    /// iOS 26 `UIView.layoutGuide(for:)`: resolves a layout guide from a
    /// `UILayoutGuide.Source` (e.g. `.margins(cornerAdaptation:)`). On Linux the
    /// margins source aliases the layout-margins guide; the corner-adaptation
    /// hint (for avoiding window controls) has no compositor to honor it.
    public func layoutGuide(for source: UILayoutGuide.Source) -> UILayoutGuide {
        switch source {
        case .margins:
            return layoutMarginsGuide
        case .safeArea:
            return safeAreaLayoutGuide
        }
    }

    /// Backing store for `layoutMargins`. The UIEdgeInsets-typed property
    /// cannot live here: UIEdgeInsets is declared in the UIKit shim module,
    /// which depends on this one, so the shim layers `layoutMargins` over this
    /// value. 8pt on every edge is UIKit's default.
    public var quillLayoutMargins = QuillEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

    /// Guides added via addLayoutGuide(_:). Until Quill has a full guide solver,
    /// view-owned guides alias the owning view so constraints through common
    /// content guides still produce usable frames instead of inert zero rects.
    public private(set) var layoutGuides: [UILayoutGuide] = []
    open func addLayoutGuide(_ layoutGuide: UILayoutGuide) {
        layoutGuide.owningView?.removeLayoutGuide(layoutGuide)
        layoutGuides.append(layoutGuide)
        layoutGuide.owningView = self
        layoutGuide.quillAliasedView = self
    }
    open func removeLayoutGuide(_ layoutGuide: UILayoutGuide) {
        layoutGuides.removeAll { $0 === layoutGuide }
        if layoutGuide.owningView === self {
            layoutGuide.owningView = nil
            layoutGuide.quillAliasedView = nil
        }
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
    /// one chance to run per dirtying, applies the common direct-subview
    /// equality constraints that PureLayout emits, then walks into children so
    /// upstream manual frame math still executes.
    private var quillNeedsLayout = true
    open func setNeedsLayout() { quillNeedsLayout = true }
    public func setNeedsDisplay() {}
    open func layoutIfNeeded() {
        quillApplyDirectSubviewConstraints()
        if quillNeedsLayout {
            quillNeedsLayout = false
            layoutSubviews()
            quillApplyDirectSubviewConstraints()
        }
        for subview in subviews {
            subview.layoutIfNeeded()
        }
    }
    open func layoutSubviews() {}

    private struct QuillConstraintFrame {
        var left: CGFloat?
        var right: CGFloat?
        var top: CGFloat?
        var bottom: CGFloat?
        var width: CGFloat?
        var height: CGFloat?
        var centerX: CGFloat?
        var centerY: CGFloat?
    }

    private func quillApplyDirectSubviewConstraints() {
        guard !subviews.isEmpty else { return }
        quillInferOwnSizeFromEdgePinnedSubviewIfNeeded()
        for subview in subviews {
            let resolved = quillResolvedConstraintFrame(for: subview)
            var nextFrame = subview.frame

            if let width = resolved.width {
                nextFrame.size.width = max(0, width)
            }
            if let height = resolved.height {
                nextFrame.size.height = max(0, height)
            }

            if resolved.width == nil, !(resolved.left != nil && resolved.right != nil), nextFrame.width == 0 {
                let fitted = subview.quillImplicitLayoutSize(
                    proposed: CGSize(
                        width: CGFloat.greatestFiniteMagnitude,
                        height: nextFrame.height > 0 ? nextFrame.height : CGFloat.greatestFiniteMagnitude
                    )
                )
                if fitted.width > 0, fitted.width.isFinite {
                    nextFrame.size.width = fitted.width
                }
            }
            if resolved.height == nil, !(resolved.top != nil && resolved.bottom != nil), nextFrame.height == 0 {
                let fitted = subview.quillImplicitLayoutSize(
                    proposed: CGSize(
                        width: nextFrame.width > 0 ? nextFrame.width : CGFloat.greatestFiniteMagnitude,
                        height: CGFloat.greatestFiniteMagnitude
                    )
                )
                if fitted.height > 0, fitted.height.isFinite {
                    nextFrame.size.height = fitted.height
                }
            }

            if let left = resolved.left, let right = resolved.right {
                nextFrame.origin.x = left
                nextFrame.size.width = max(0, right - left)
            } else if let left = resolved.left {
                nextFrame.origin.x = left
            } else if let right = resolved.right {
                nextFrame.origin.x = right - nextFrame.size.width
            } else if let centerX = resolved.centerX {
                nextFrame.origin.x = centerX - nextFrame.size.width / 2
            }

            if let top = resolved.top, let bottom = resolved.bottom {
                nextFrame.origin.y = top
                nextFrame.size.height = max(0, bottom - top)
            } else if let top = resolved.top {
                nextFrame.origin.y = top
            } else if let bottom = resolved.bottom {
                nextFrame.origin.y = bottom - nextFrame.size.height
            } else if let centerY = resolved.centerY {
                nextFrame.origin.y = centerY - nextFrame.size.height / 2
            }

            if subview.frame != nextFrame {
                subview.frame = nextFrame
            }
        }
    }

    private func quillInferOwnSizeFromEdgePinnedSubviewIfNeeded() {
        guard bounds.width == 0 || bounds.height == 0 else { return }
        guard let subview = subviews.first(where: { !$0.isHidden }) else { return }

        let resolved = quillResolvedConstraintFrame(for: subview)
        var nextFrame = frame
        var changed = false

        if bounds.width == 0, resolved.left != nil, resolved.right != nil {
            let fitted = subview.quillEstimatedFittingSize(
                proposed: CGSize(width: CGFloat.greatestFiniteMagnitude, height: max(bounds.height, 1))
            )
            let pinnedSize = quillSizeContributionFromEdgePinnedChild(subview, childSize: fitted)
            let width = pinnedSize.width > 0 ? pinnedSize.width : fitted.width
            if width > 0, width.isFinite {
                nextFrame.size.width = width
                if let trailing = quillResolvedOwnConstraintValue(for: .trailing) ?? quillResolvedOwnConstraintValue(for: .right) {
                    nextFrame.origin.x = trailing - width
                }
                changed = true
            }
        }

        if bounds.height == 0, resolved.top != nil, resolved.bottom != nil {
            let proposedWidth = nextFrame.size.width > 0 ? nextFrame.size.width : max(bounds.width, 1)
            let fitted = subview.quillEstimatedFittingSize(
                proposed: CGSize(width: proposedWidth, height: CGFloat.greatestFiniteMagnitude)
            )
            let pinnedSize = quillSizeContributionFromEdgePinnedChild(subview, childSize: fitted)
            let height = pinnedSize.height > 0 ? pinnedSize.height : fitted.height
            if height > 0, height.isFinite {
                nextFrame.size.height = height
                if let bottom = quillResolvedOwnConstraintValue(for: .bottom) {
                    nextFrame.origin.y = bottom - height
                }
                changed = true
            }
        }

        if changed, frame != nextFrame {
            frame = nextFrame
        }
    }

    func quillEstimatedFittingSize(proposed: CGSize) -> CGSize {
        var measured = sizeThatFits(proposed)
        let dimensionBounds = quillDimensionBoundsFromConstraints()
        measured.width = quillApplyDimensionBounds(measured.width, bounds: dimensionBounds.width)
        measured.height = quillApplyDimensionBounds(measured.height, bounds: dimensionBounds.height)

        guard !subviews.isEmpty else { return measured }

        var union = CGRect.null
        for subview in subviews where !subview.isHidden {
            let resolved = quillResolvedConstraintFrame(for: subview)
            var childFrame = subview.frame
            if let left = resolved.left {
                childFrame.origin.x = left
            }
            if let top = resolved.top {
                childFrame.origin.y = top
            }
            if let width = resolved.width {
                childFrame.size.width = width
            }
            if let height = resolved.height {
                childFrame.size.height = height
            }

            let childSize = subview.quillEstimatedFittingSize(proposed: CGSize(
                width: childFrame.width > 0 ? childFrame.width : proposed.width,
                height: childFrame.height > 0 ? childFrame.height : proposed.height
            ))
            if childFrame.width == 0 {
                childFrame.size.width = childSize.width
            }
            if childFrame.height == 0 {
                childFrame.size.height = childSize.height
            }

            let pinnedSize = quillSizeContributionFromEdgePinnedChild(subview, childSize: childSize)
            if pinnedSize.width > 0, pinnedSize.width.isFinite {
                measured.width = max(measured.width, pinnedSize.width)
            }
            if pinnedSize.height > 0, pinnedSize.height.isFinite {
                measured.height = max(measured.height, pinnedSize.height)
            }

            guard childFrame.width > 0 || childFrame.height > 0 else { continue }
            union = union.union(childFrame)
        }

        if !union.isNull {
            measured.width = max(measured.width, union.maxX)
            measured.height = max(measured.height, union.maxY)
        }
        measured.width = quillApplyDimensionBounds(measured.width, bounds: dimensionBounds.width)
        measured.height = quillApplyDimensionBounds(measured.height, bounds: dimensionBounds.height)
        return measured
    }

    private func quillImplicitLayoutSize(proposed: CGSize) -> CGSize {
        let intrinsic = intrinsicContentSize
        var size = CGSize.zero

        if intrinsic.width != UIView.noIntrinsicMetric, intrinsic.width > 0, intrinsic.width.isFinite {
            size.width = intrinsic.width
        }
        if intrinsic.height != UIView.noIntrinsicMetric, intrinsic.height > 0, intrinsic.height.isFinite {
            size.height = intrinsic.height
        }

        if size.width == 0 || size.height == 0 {
            let fitted = sizeThatFits(proposed)
            if size.width == 0, fitted.width > 0, fitted.width.isFinite {
                size.width = fitted.width
            }
            if size.height == 0, fitted.height > 0, fitted.height.isFinite {
                size.height = fitted.height
            }
        }

        return size
    }

    private func quillResolvedConstraintFrame(for subview: UIView) -> QuillConstraintFrame {
        var resolved = QuillConstraintFrame()
        for constraint in NSLayoutConstraint.quillActive where constraint.quillRelation == .equal {
            guard let first = constraint.quillFirstAnchor, first.quillItem === subview else {
                continue
            }
            guard let value = quillResolvedConstraintValue(for: constraint) else {
                continue
            }
            switch first.quillAttribute {
            case .left, .leading:
                resolved.left = value
            case .right, .trailing:
                resolved.right = value
            case .top:
                resolved.top = value
            case .bottom:
                resolved.bottom = value
            case .width:
                resolved.width = value
            case .height:
                resolved.height = value
            case .centerX:
                resolved.centerX = value
            case .centerY:
                resolved.centerY = value
            case .firstBaseline, .lastBaseline, .notAnAttribute:
                break
            }
        }
        return resolved
    }

    private struct QuillDimensionBounds {
        var width = QuillSingleDimensionBounds()
        var height = QuillSingleDimensionBounds()
    }

    private struct QuillSingleDimensionBounds {
        var minimum: CGFloat = 0
        var maximum: CGFloat?
    }

    private func quillDimensionBoundsFromConstraints() -> QuillDimensionBounds {
        var bounds = QuillDimensionBounds()
        for constraint in NSLayoutConstraint.quillActive {
            guard let first = constraint.quillFirstAnchor,
                  first.quillItem === self,
                  constraint.quillSecondAnchor == nil,
                  first.quillAttribute == .width || first.quillAttribute == .height else {
                continue
            }

            var dimension = first.quillAttribute == .width ? bounds.width : bounds.height
            switch constraint.quillRelation {
            case .equal:
                dimension.minimum = max(dimension.minimum, constraint.constant)
                dimension.maximum = min(dimension.maximum ?? constraint.constant, constraint.constant)
            case .greaterThanOrEqual:
                dimension.minimum = max(dimension.minimum, constraint.constant)
            case .lessThanOrEqual:
                dimension.maximum = min(dimension.maximum ?? constraint.constant, constraint.constant)
            }

            if first.quillAttribute == .width {
                bounds.width = dimension
            } else {
                bounds.height = dimension
            }
        }
        return bounds
    }

    private func quillApplyDimensionBounds(_ value: CGFloat, bounds: QuillSingleDimensionBounds) -> CGFloat {
        var result = value.isFinite && value > 0 ? value : 0
        result = max(result, bounds.minimum)
        if let maximum = bounds.maximum {
            result = min(result, maximum)
        }
        return result
    }

    private func quillSizeContributionFromEdgePinnedChild(_ child: UIView, childSize: CGSize) -> CGSize {
        var leftInset: CGFloat?
        var rightInset: CGFloat?
        var topInset: CGFloat?
        var bottomInset: CGFloat?

        for constraint in NSLayoutConstraint.quillActive where constraint.quillRelation == .equal {
            guard let first = constraint.quillFirstAnchor,
                  first.quillItem === child,
                  let second = constraint.quillSecondAnchor,
                  let edge = quillEdgeConstraintContribution(
                    first: first.quillAttribute,
                    second: second,
                    constant: constraint.constant
                  ) else {
                continue
            }

            switch edge {
            case .left(let inset):
                leftInset = inset
            case .right(let inset):
                rightInset = inset
            case .top(let inset):
                topInset = inset
            case .bottom(let inset):
                bottomInset = inset
            }
        }

        return CGSize(
            width: (leftInset != nil && rightInset != nil) ? (leftInset! + childSize.width + rightInset!) : 0,
            height: (topInset != nil && bottomInset != nil) ? (topInset! + childSize.height + bottomInset!) : 0
        )
    }

    private enum QuillEdgeContribution {
        case left(CGFloat)
        case right(CGFloat)
        case top(CGFloat)
        case bottom(CGFloat)
    }

    private func quillEdgeConstraintContribution(
        first: QuillLayoutAttribute,
        second: any QuillLayoutAnchorReading,
        constant: CGFloat
    ) -> QuillEdgeContribution? {
        let secondAttribute = second.quillAttribute
        if let guide = second.quillItem as? UILayoutGuide,
           let owner = guide.quillAliasedView ?? guide.owningView,
           owner === self,
           (guide === layoutMarginsGuide || guide.identifier == "UIViewLayoutMarginsGuide") {
            switch (first, secondAttribute) {
            case (.left, .left), (.leading, .leading):
                return .left(max(0, quillLayoutMargins.left + constant))
            case (.right, .right), (.trailing, .trailing):
                return .right(max(0, quillLayoutMargins.right - constant))
            case (.top, .top):
                return .top(max(0, quillLayoutMargins.top + constant))
            case (.bottom, .bottom):
                return .bottom(max(0, quillLayoutMargins.bottom - constant))
            default:
                break
            }
        }

        let guideFrame = (second.quillItem as? UILayoutGuide).flatMap { quillLayoutFrame(for: $0) }
        let isSelfEdge = second.quillItem === self

        switch (first, secondAttribute) {
        case (.left, .left), (.leading, .leading):
            if isSelfEdge {
                return .left(max(0, constant))
            }
            if let guideFrame {
                return .left(max(0, guideFrame.minX + constant))
            }
        case (.right, .right), (.trailing, .trailing):
            if isSelfEdge {
                return .right(max(0, -constant))
            }
            if let guideFrame {
                return .right(max(0, bounds.width - (guideFrame.maxX + constant)))
            }
        case (.top, .top):
            if isSelfEdge {
                return .top(max(0, constant))
            }
            if let guideFrame {
                return .top(max(0, guideFrame.minY + constant))
            }
        case (.bottom, .bottom):
            if isSelfEdge {
                return .bottom(max(0, -constant))
            }
            if let guideFrame {
                return .bottom(max(0, bounds.height - (guideFrame.maxY + constant)))
            }
        default:
            break
        }
        return nil
    }

    private func quillResolvedOwnConstraintValue(for attribute: QuillLayoutAttribute) -> CGFloat? {
        guard let superview else { return nil }
        for constraint in NSLayoutConstraint.quillActive where constraint.quillRelation == .equal {
            guard let first = constraint.quillFirstAnchor,
                  first.quillItem === self,
                  first.quillAttribute == attribute else {
                continue
            }
            guard let second = constraint.quillSecondAnchor,
                  let secondView = second.quillItem as? UIView,
                  secondView === superview else {
                continue
            }
            guard let value = superview.quillLayoutValue(for: second) else {
                continue
            }
            return value * constraint.quillMultiplier + constraint.constant
        }
        return nil
    }

    private func quillResolvedConstraintValue(for constraint: NSLayoutConstraint) -> CGFloat? {
        let constant = constraint.constant
        guard let second = constraint.quillSecondAnchor else {
            return constant
        }
        guard let secondValue = quillLayoutValue(for: second) else {
            return nil
        }
        return secondValue * constraint.quillMultiplier + constant
    }

    private func quillLayoutValue(for anchor: any QuillLayoutAnchorReading) -> CGFloat? {
        let frame: CGRect
        if let guide = anchor.quillItem as? UILayoutGuide {
            guard let guideFrame = quillLayoutFrame(for: guide) else {
                return nil
            }
            frame = guideFrame
        } else if let view = anchor.quillItem as? UIView {
            if view === self {
                frame = CGRect(origin: .zero, size: bounds.size)
            } else if view.superview === self {
                frame = view.frame
            } else if quillIsDescendant(of: view) {
                let ancestorOrigin = view.quillAbsoluteOrigin()
                let ownOrigin = quillAbsoluteOrigin()
                frame = CGRect(
                    x: ancestorOrigin.x - ownOrigin.x,
                    y: ancestorOrigin.y - ownOrigin.y,
                    width: view.bounds.width,
                    height: view.bounds.height
                )
            } else {
                return nil
            }
        } else {
            return nil
        }

        switch anchor.quillAttribute {
        case .left, .leading:
            return frame.minX
        case .right, .trailing:
            return frame.maxX
        case .top:
            return frame.minY
        case .bottom:
            return frame.maxY
        case .width:
            return frame.width
        case .height:
            return frame.height
        case .centerX:
            return frame.midX
        case .centerY:
            return frame.midY
        case .firstBaseline, .lastBaseline, .notAnAttribute:
            return nil
        }
    }

    private func quillLayoutFrame(for guide: UILayoutGuide) -> CGRect? {
        guard let owner = guide.quillAliasedView ?? guide.owningView else {
            return nil
        }

        let ownerFrame: CGRect
        if owner === self {
            ownerFrame = CGRect(origin: .zero, size: owner.bounds.size)
        } else if owner.superview === self {
            ownerFrame = owner.frame
        } else if quillIsDescendant(of: owner) {
            let ancestorOrigin = owner.quillAbsoluteOrigin()
            let ownOrigin = quillAbsoluteOrigin()
            ownerFrame = CGRect(
                x: ancestorOrigin.x - ownOrigin.x,
                y: ancestorOrigin.y - ownOrigin.y,
                width: owner.bounds.width,
                height: owner.bounds.height
            )
        } else {
            return nil
        }

        if guide === owner.layoutMarginsGuide || guide.identifier == "UIViewLayoutMarginsGuide" {
            return CGRect(
                x: ownerFrame.minX + owner.quillLayoutMargins.left,
                y: ownerFrame.minY + owner.quillLayoutMargins.top,
                width: max(0, ownerFrame.width - owner.quillLayoutMargins.left - owner.quillLayoutMargins.right),
                height: max(0, ownerFrame.height - owner.quillLayoutMargins.top - owner.quillLayoutMargins.bottom)
            )
        }

        return ownerFrame
    }

    private func quillIsDescendant(of ancestor: UIView) -> Bool {
        var current = superview
        while let view = current {
            if view === ancestor { return true }
            current = view.superview
        }
        return false
    }

    private func quillAbsoluteOrigin() -> CGPoint {
        var origin = frame.origin
        var current = superview
        while let view = current {
            origin.x += view.frame.origin.x
            origin.y += view.frame.origin.y
            current = view.superview
        }
        return origin
    }

    /// Apple's UIView is its own layer's delegate and implements
    /// `CALayerDelegate.action(for:forKey:)`. CLASS-BODY `open`: BezierPathView
    /// and OWSBubbleShapeView override it to return `nil` / `NSNull()` and disable
    /// implicit CALayer animations. No implicit-animation engine runs on Linux, so
    /// the default returns `nil` (no action).
    open func action(for layer: CALayer, forKey event: String) -> CAAction? {
        _ = (layer, event)
        return nil
    }

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

    /// APPROXIMATION: on Apple this runs the constraint solver for the
    /// smallest satisfying size. There is no solver behind the shim, so per
    /// axis the view's intrinsic metric wins when it has one and the target's
    /// axis is echoed otherwise.
    open func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        let intrinsic = intrinsicContentSize
        return CGSize(
            width: intrinsic.width >= 0 ? intrinsic.width : targetSize.width,
            height: intrinsic.height >= 0 ? intrinsic.height : targetSize.height
        )
    }

    open func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        _ = horizontalFittingPriority
        _ = verticalFittingPriority
        return systemLayoutSizeFitting(targetSize)
    }

    /// No intrinsic size, exactly Apple's UIView default; content-bearing
    /// views override with real metrics.
    open var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
    /// Apple's sentinel for "no intrinsic metric on this axis" (-1).
    public static let noIntrinsicMetric: CGFloat = -1

    /// Apple's UIView class property; custom-layout views (VideoTimelineView,
    /// LineWrappingStackView) override it to return `true`. `open` class var so
    /// those overrides are valid cross-module. Apple's default is `false`.
    open class var requiresConstraintBasedLayout: Bool { false }

    /// Window-membership override point (BezierPathView / OWSBubbleShapeView
    /// react to entering a window). No window graph drives it on Linux, but the
    /// `open` declaration makes the subclass overrides valid.
    open func didMoveToWindow() {}

    /// `nonisolated(unsafe)`: OWSNavigationController reads this in a nonisolated
    /// default-argument context. It is a plain Bool (no UI state behind it on
    /// Linux), so reading it across actors is safe — Apple likewise lets
    /// `UIView.areAnimationsEnabled` be queried from any thread.
    nonisolated(unsafe) public static var areAnimationsEnabled: Bool = true
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

    // @MainActor closures (Apple's UIView.animate IS @MainActor): SignalUI calls
    // these from Timer / completion closures, and an @MainActor parameter type makes
    // the passed closure literal infer @MainActor — so `self.someMainActorMember`
    // inside resolves without "call in a synchronous nonisolated context".
    public static func animate(
        withDuration: TimeInterval,
        animations: @MainActor @escaping () -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        animations()
        completion?(true)
    }

    public static func performWithoutAnimation(_ actionsWithoutAnimation: @MainActor () -> Void) {
        actionsWithoutAnimation()
    }

    public static func transition(
        with view: UIView,
        duration: TimeInterval,
        options: AnimationOptions = [],
        animations: @MainActor @escaping () -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        _ = (view, duration, options)
        animations()
        completion?(true)
    }

    public static func animateKeyframes(
        withDuration duration: TimeInterval,
        delay: TimeInterval = 0,
        options: AnimationOptions = [],
        animations: @MainActor @escaping () -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        _ = (duration, delay, options)
        animations()
        completion?(true)
    }

    public static func addKeyframe(
        withRelativeStartTime frameStartTime: Double,
        relativeDuration frameDuration: Double,
        animations: @MainActor @escaping () -> Void
    ) {
        _ = (frameStartTime, frameDuration)
        animations()
    }

    public static func animate(
        withDuration: TimeInterval,
        delay: TimeInterval = 0,
        options: AnimationOptions = [],
        animations: @MainActor @escaping () -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        animations()
        completion?(true)
    }

    public static func animate(
        withDuration: TimeInterval,
        delay: TimeInterval,
        usingSpringWithDamping: CGFloat,
        initialSpringVelocity: CGFloat,
        options: AnimationOptions = [],
        animations: @MainActor @escaping () -> Void,
        completion: (@MainActor (Bool) -> Void)? = nil
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
    public var effectiveUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection {
        switch semanticContentAttribute {
        case .forceRightToLeft:
            return .rightToLeft
        case .forceLeftToRight:
            return .leftToRight
        default:
            return traitCollection.layoutDirection
        }
    }

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
    open var accessibilityCustomActions: [UIAccessibilityCustomAction]?
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

    // Apple's UIViewController declares `public required init?(coder:)`. Same
    // rationale as UIView's: lowered Signal subclasses ship the faithful
    // `required init?(coder:)` boilerplate and need a base to override; marking
    // it `required` lets init-free subclasses inherit it. No nib/storyboard is
    // ever decoded on Linux.
    public required init?(coder: NSCoder) {
        super.init()
        _ = coder
    }

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

    // MARK: Transition-state flags
    //
    // On Apple these read true only during the narrow window of an
    // appearance/containment transition. There are no animated transitions on
    // Linux (present/dismiss and addChild/removeFromParent complete
    // synchronously), so the window is always empty and all four read false —
    // the faithful steady-state value. Class-body so SignalUI controllers that
    // branch on them resolve through base-typed references.
    open var isBeingPresented: Bool { false }
    open var isBeingDismissed: Bool { false }
    open var isMovingToParent: Bool { false }
    open var isMovingFromParent: Bool { false }

    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewDidDisappear(_ animated: Bool) {}
    open func viewWillLayoutSubviews() {}
    open func viewDidLayoutSubviews() {}
    open func viewSafeAreaInsetsDidChange() {}
    open func viewLayoutMarginsDidChange() {}
    open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {}
    open var hidesBottomBarWhenPushed: Bool = false
    open var shouldAutorotate: Bool { true }

    // MARK: Status-bar appearance
    //
    // CLASS-BODY, not extension: SignalUI overrides all of these
    // (ImageEditorCropViewController & co.). Apple's defaults throughout.
    // There is no status bar on Linux, so nothing reads the values back yet;
    // UIViewControllerSurface.swift owns the matching no-op
    // setNeedsStatusBarAppearanceUpdate() and the UIStatusBarStyle enum.
    open var preferredStatusBarStyle: UIStatusBarStyle { .default }
    open var prefersStatusBarHidden: Bool { false }
    open var modalPresentationCapturesStatusBarAppearance: Bool = false
    open var childForStatusBarStyle: UIViewController? { nil }
    open var childForStatusBarHidden: UIViewController? { nil }

    /// Whether this controller wants the home indicator hidden. Apple's
    /// default: false. CLASS-BODY `open` so SignalUI controllers (media
    /// viewers, call screens) override it and call super; there is no home
    /// indicator on Linux, so nothing reads it back yet.
    open var prefersHomeIndicatorAutoHidden: Bool { false }

    // MARK: Editing mode
    //
    // CLASS-BODY, not extension: SignalUI controllers (list/settings screens)
    // override setEditing(_:animated:) and call super, and read/observe
    // isEditing. Apple's UIViewController stores the editing flag and the
    // default setEditing just records it; there is no Edit button bar item to
    // toggle on Linux, but the state is faithful so view code that branches on
    // it behaves.
    private var quillIsEditing: Bool = false
    open var isEditing: Bool {
        get { quillIsEditing }
        set { quillIsEditing = newValue }
    }
    open func setEditing(_ editing: Bool, animated: Bool) {
        _ = animated
        quillIsEditing = editing
    }

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

@MainActor open class UISplitViewController: UIViewController {
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
    /// UIKit's documented bar show/hide animation duration. There is no bar
    /// animation on Linux, but SignalUI reads this constant to time its own
    /// coordinated animations, so it carries Apple's exact value.
    public static let hideShowBarDuration: CGFloat = 0.33

    public var navigationBar = UINavigationBar()
    open weak var delegate: (any UINavigationControllerDelegate)?
    public var interactivePopGestureRecognizer: UIGestureRecognizer? = UIGestureRecognizer()
    public var interactiveContentPopGestureRecognizer: UIGestureRecognizer? = UIGestureRecognizer()
    public private(set) var isNavigationBarHidden = false
    private var quillViewControllers: [UIViewController] = []
    public var viewControllers: [UIViewController] {
        get { quillViewControllers }
        set {
            let previous = quillViewControllers
            for controller in previous where !newValue.contains(where: { $0 === controller }) {
                if controller.navigationController === self {
                    controller.navigationController = nil
                }
            }
            quillViewControllers = newValue
            for controller in newValue {
                controller.navigationController = self
            }
        }
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
    // Apple's UINavigationController inherits `init(nibName:bundle:)` from
    // UIViewController as its designated initializer; `init(rootViewController:)`
    // and `init(navigationBarClass:toolbarClass:)` are CONVENIENCE inits that
    // chain through it. OWSNavigationController overrides `init(nibName:bundle:)`
    // and calls `super.init(nibName:bundle:)`, so that designated init must be
    // exposed here (a subclass with its own designated inits does not inherit
    // it). Restate it as the designated init and make the others convenience.
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    // DESIGNATED (not convenience): upstream subclasses (FingerprintViewController)
    // call `super.init(rootViewController:)` from their own designated init — only
    // legal against a superclass DESIGNATED init — and OWSNavigationController
    // declares `override convenience init(rootViewController:)`, which requires the
    // base to be an overridable designated init. (Apple makes it convenience, but
    // ObjC relaxes the rules there; on Linux Swift's strict init model needs this.)
    public init(rootViewController: UIViewController) {
        super.init(nibName: nil, bundle: nil)
        viewControllers = [rootViewController]
    }
    public convenience init(navigationBarClass: AnyClass?, toolbarClass: AnyClass?) {
        self.init(nibName: nil, bundle: nil)
    }
    public convenience init() { self.init(navigationBarClass: nil, toolbarClass: nil) }
    // Own designated init suppresses inheritance of UIViewController's
    // required init?(coder:); restate it.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    open func pushViewController(_ viewController: UIViewController, animated: Bool) {
        _ = animated
        viewControllers.append(viewController)
    }
    open func popViewController(animated: Bool) -> UIViewController? {
        _ = animated
        guard viewControllers.count > 1 else { return nil }
        let removed = viewControllers.removeLast()
        if removed.navigationController === self {
            removed.navigationController = nil
        }
        return removed
    }
    @discardableResult
    open func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        _ = animated
        guard let index = viewControllers.firstIndex(where: { $0 === viewController }) else {
            return nil
        }
        let removed = Array(viewControllers.suffix(from: index + 1))
        viewControllers = Array(viewControllers.prefix(index + 1))
        return removed
    }
    @discardableResult
    open func popToRootViewController(animated: Bool) -> [UIViewController]? {
        _ = animated
        guard let root = viewControllers.first else { return nil }
        return popToViewController(root, animated: false)
    }
    public var topViewController: UIViewController? {
        get { viewControllers.last }
        set { viewControllers = newValue.map { [$0] } ?? [] }
    }
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

    open func sizeToFit() {}
}

@MainActor public class UINavigationItem: NSObject {
    public var rightBarButtonItem: UIBarButtonItem?
    public var rightBarButtonItems: [UIBarButtonItem]?
    public var leftBarButtonItem: UIBarButtonItem?
    /// The bar button item shown as the back button on the NEXT view controller
    /// pushed on top of one owning this item (OWSTableViewController2 sets a
    /// blank-title back button to hide the previous title). Faithful storage; no
    /// navigation bar renders it on Linux yet.
    public var backBarButtonItem: UIBarButtonItem?
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
        case prominent = 3
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

    /// The action invoked when the item is tapped (iOS 14+). Recorded; no
    /// native toolbar fires it on Linux yet, mirroring `target`/`action`.
    open var primaryAction: UIAction? {
        didSet {
            if let primaryAction {
                if title == nil, !primaryAction.title.isEmpty { title = primaryAction.title }
                if image == nil { image = primaryAction.image }
            }
        }
    }

    /// `UIBarButtonItem(primaryAction:)` (iOS 14+).
    public convenience init(primaryAction: UIAction?) {
        self.init()
        self.primaryAction = primaryAction
    }

    /// `UIBarButtonItem(image:primaryAction:)` (iOS 14+).
    public convenience init(image: UIImage?, primaryAction: UIAction?) {
        self.init()
        self.image = image
        self.primaryAction = primaryAction
    }

    /// `UIBarButtonItem(title:image:primaryAction:menu:)` (iOS 14+).
    public convenience init(title: String?, image: UIImage?, primaryAction: UIAction?, menu: UIMenu?) {
        self.init()
        self.title = title
        self.image = image
        self.primaryAction = primaryAction
        self.menu = menu
    }

    /// `UIBarButtonItem(title:image:target:action:menu:)` (iOS 14+).
    public convenience init(title: String?, image: UIImage?, target: Any?, action: Selector?, menu: UIMenu?) {
        self.init()
        self.title = title
        self.image = image
        self.target = target as AnyObject?
        self.action = action
        self.menu = menu
    }

    /// `UIBarButtonItem(systemItem:primaryAction:menu:)` (iOS 14+).
    public convenience init(systemItem: SystemItem, primaryAction: UIAction? = nil, menu: UIMenu? = nil) {
        self.init()
        self.quillSystemItem = systemItem
        self.primaryAction = primaryAction
        self.menu = menu
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

    public init() {
        super.init(frame: .zero)
        quillSetTableStyle(.plain)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        quillSetTableStyle(.plain)
    }

    public init(frame: CGRect, style: Style) {
        super.init(frame: frame)
        quillSetTableStyle(style)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // style, reloadData and the rest of the member
    // surface live in UITableViewExtras.swift.
}

// The configuration-driven cell content surface (iOS 14+). On Apple a cell's
// `contentConfiguration` drives its content view; concrete configurations include
// UIListContentConfiguration and SwiftUI's UIHostingConfiguration (which lives in
// the SwiftUI shim and conforms to this protocol). Linux is inert: assigning a
// configuration stores it but renders nothing.
@MainActor public protocol UIContentConfiguration {}

@MainActor open class UITableViewCell: UIView {
    private static let appearanceProxy = UITableViewCell(style: .default, reuseIdentifier: nil)
    public static func appearance() -> UITableViewCell { appearanceProxy }

    public enum CellStyle: Int { case `default`, value1, value2, subtitle }
    public private(set) var reuseIdentifier: String?
    private let quillTextLabel = UILabel()
    private let quillDetailTextLabel = UILabel()
    private let quillImageView = UIImageView(image: nil)
    // Apple's `UITableViewCell.init(style:reuseIdentifier:)` is the DESIGNATED
    // initializer and is NOT `required` -- only `init?(coder:)` is (from
    // NSCoding). The earlier `required` here drove the lowered cells into two
    // contradictory errors:
    //   * subclasses that only OVERRIDE it (ContactCell, ContactTableViewCell,
    //     NonContactTableViewCell, MentionPicker, SafetyNumberConfirmationSheet)
    //     hit "use the 'required' modifier to override a required initializer"
    //     -- Apple subclasses write plain `override init(style:)`, no `required`.
    //   * subclasses that add their OWN designated init (ContactShareViewController,
    //     ContactReminderTableViewCell, GroupTableViewCell, OWSTableItem's cell)
    //     hit "'required' initializer 'init(style:reuseIdentifier:)' must be
    //     provided by subclass" -- a `required` base forces every such subclass
    //     to restate it, which faithful Apple code does not do.
    // Making it a plain designated init (required ONLY on init?(coder:), exactly
    // like Apple) resolves both families at once.
    public init(style: CellStyle, reuseIdentifier: String?) {
        super.init(frame: .zero)
        self.reuseIdentifier = reuseIdentifier
    }
    public convenience init() { self.init(style: .default, reuseIdentifier: nil) }
    // Own designated init above suppresses inheritance of UIView's
    // required init?(coder:); restate it so SignalUI cell subclasses' faithful
    // `required init?(coder:)` overrides resolve.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    open var textLabel: UILabel? { quillTextLabel }
    open var detailTextLabel: UILabel? { quillDetailTextLabel }
    open var imageView: UIImageView? { quillImageView }
    // Inert on Linux: stored but never applied to a content view. SignalUI's
    // RecipientPickerViewController assigns a UIHostingConfiguration here.
    public var contentConfiguration: UIContentConfiguration?

    /// Configuration-based background (iOS 14+). `Any?` to match the upstream
    /// assignment of `UIBackgroundConfiguration.listGroupedCell()` etc.
    /// (MentionPicker's cell sets it). Nothing composites it on Linux yet.
    public var backgroundConfiguration: Any?

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

    /// Apple's configuration-based cell-update hook (iOS 14+). CLASS-BODY `open`:
    /// MentionPicker's MentionableUserCell overrides it to recolor its background
    /// for the selected/highlighted state. Nothing drives the update pass on Linux
    /// yet, so the base is a no-op.
    open func updateConfiguration(using state: UICellConfigurationState) {
        _ = state
    }
}

@MainActor open class UICollectionView: UIScrollView {
    public init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame)
        self.collectionViewLayout = layout
    }
    // Own designated init suppresses inheritance of UIView's
    // required init?(coder:); restate it.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    public func cellForItem(at indexPath: IndexPath) -> UICollectionViewCell? {
        quillCellForItem(at: indexPath)
    }

    open func reloadData() {
        quillReloadData()
    }
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
    open override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
        contentView.layoutIfNeeded()
    }
    open func prepareForReuse() {}
    open func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        frame = layoutAttributes.frame
        alpha = layoutAttributes.alpha
        isHidden = layoutAttributes.isHidden
        contentView.frame = bounds
        contentView.layoutIfNeeded()
    }
}

@MainActor public class UIAlertController: UIViewController {
    /// Apple's UIAlertController.Style (action sheet vs. alert). Raw values
    /// match UIKit's (actionSheet == 0, alert == 1). The old `preferredStyle:
    /// Int` parameter could never accept upstream's `.alert` / `.actionSheet`
    /// arguments.
    public enum Style: Int, Sendable {
        case actionSheet = 0
        case alert = 1
    }

    // `title` is inherited from UIViewController (open var title: String?).
    public var message: String?
    public private(set) var preferredStyle: Style = .alert
    /// The actions added via `addAction(_:)`, in insertion order, as on Apple.
    public private(set) var actions: [UIAlertAction] = []
    public var preferredAction: UIAlertAction?

    public init(title: String?, message: String?, preferredStyle: Style) {
        self.message = message
        self.preferredStyle = preferredStyle
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }
    // Own designated init suppresses inheritance of UIViewController's
    // required init?(coder:); restate it.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public func addAction(_ action: UIAlertAction) {
        actions.append(action)
    }
    // popoverPresentationController is inherited from UIViewController.
    // (UITextField-based addTextField(configurationHandler:) belongs in the
    // UIKitShim layer — UITextField is declared in that dependent module.)
}

public class UIAlertAction: NSObject {
    /// Apple's UIAlertAction.Style. Raw values match UIKit's (default == 0,
    /// cancel == 1, destructive == 2). The old `style: Int` parameter could
    /// never accept upstream's `.default` / `.cancel` / `.destructive`.
    public enum Style: Int, Sendable {
        case `default` = 0
        case cancel = 1
        case destructive = 2
    }

    public let title: String?
    public let style: Style
    public var isEnabled: Bool = true
    /// The handler invoked when the action is selected. No event backend fires
    /// it on Linux; recorded so a future native alert renderer can.
    public let quillHandler: ((UIAlertAction) -> Void)?

    public init(title: String?, style: Style, handler: ((UIAlertAction) -> Void)? = nil) {
        self.title = title
        self.style = style
        self.quillHandler = handler
        super.init()
    }
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
    public weak var delegate: (any UIPopoverPresentationControllerDelegate)?
    /// Views outside the popover that still receive touches while it is up.
    /// Recorded faithfully; no popover dimming view composites on Linux yet,
    /// so nothing reads it back. nil by default, matching UIKit.
    public var passthroughViews: [UIView]?
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
    // Own designated inits suppress inheritance of UIViewController's
    // required init?(coder:); restate it.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    /// Activity types to omit from the share sheet. Recorded faithfully; no
    /// share sheet composites on Linux yet, so nothing reads it back. nil by
    /// default, matching UIKit.
    public var excludedActivityTypes: [UIActivity.ActivityType]?
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

    open var isEnabled = true {
        didSet {
            if oldValue != isEnabled { quillNotifyViewMutation() }
        }
    }
    open var isSelected = false
    open var isHighlighted = false
    open var state: State = .normal

    /// Whether the control is currently tracking a touch. On Apple this is a
    /// READ-ONLY computed property (`open var isTracking: Bool { get }`) driven
    /// by the touch-tracking machinery (beginTracking…endTracking); there is no
    /// live touch tracking on Linux, so it is honestly `false`.
    ///
    /// It MUST be read-only (computed `{ get }`), not a stored `var = false`:
    /// upstream subclasses override it read-only (e.g. ImageEditor's
    /// RotationControl: `override var isTracking { scrollView.isTracking }`).
    /// A stored mutable `var` cannot be overridden by a read-only computed one
    /// ("cannot override mutable property with read-only property"), and that
    /// failed override then becomes a SECOND `isTracking` declaration on the
    /// subclass → "ambiguous use of 'isTracking'". Read-only here lets the
    /// override resolve as a true override, one owner per type.
    open var isTracking: Bool { false }
}

@MainActor open class UIButton: UIControl {
    public var imageView: UIImageView?
    // (accessibilityLabel moved up to the UIView class body — one
    // declaration, overridable — matching Apple, where UIButton inherits it.)
    // setTitle(_:for:) — and the rest of the per-state content surface
    // (setImage / setTitleColor / setAttributedTitle / titleLabel) — lives in
    // UIButtonExtras.swift with Apple's exact `for state: UIControl.State`
    // signature. The old class-body `setTitle(_:for: Any)` here was a wrong-
    // typed duplicate: `Any` collided with the correct State-typed overload,
    // making every `button.setTitle(_, for: .normal)` call ambiguous.
    open var menu: UIMenu?
    open var showsMenuAsPrimaryAction: Bool = false
    open var contentHorizontalAlignment: UIControl.ContentHorizontalAlignment = .center
    open func sizeToFit() {
        frame.size = sizeThatFits(CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let metrics = quillButtonContentMetrics(constrainedTo: size)
        let insets = quillMeasuredContentInsets
        return CGSize(
            width: metrics.contentSize.width + insets.left + insets.right,
            height: metrics.contentSize.height + insets.top + insets.bottom
        )
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let metrics = quillButtonContentMetrics(constrainedTo: bounds.size)
        let insets = quillMeasuredContentInsets
        let availableWidth = max(0, bounds.width - insets.left - insets.right)
        let availableHeight = max(0, bounds.height - insets.top - insets.bottom)
        let contentWidth = min(metrics.contentSize.width, availableWidth)

        let startX: CGFloat
        switch contentHorizontalAlignment {
        case .left, .leading:
            startX = insets.left
        case .right, .trailing:
            startX = bounds.width - insets.right - contentWidth
        case .fill:
            startX = insets.left
        case .center:
            startX = insets.left + max(0, (availableWidth - contentWidth) / 2)
        }

        var x = startX
        if let imageView = metrics.imageView, metrics.imageSize.width > 0, metrics.imageSize.height > 0 {
            imageView.frame = CGRect(
                x: x,
                y: insets.top + max(0, (availableHeight - metrics.imageSize.height) / 2),
                width: metrics.imageSize.width,
                height: metrics.imageSize.height
            )
            x += metrics.imageSize.width
            if metrics.titleSize.width > 0 {
                x += metrics.imageTitleSpacing
            }
        }

        if let titleLabel = metrics.titleLabel, metrics.titleSize.width > 0, metrics.titleSize.height > 0 {
            titleLabel.frame = CGRect(
                x: x,
                y: insets.top + max(0, (availableHeight - metrics.titleSize.height) / 2),
                width: min(metrics.titleSize.width, max(0, bounds.width - insets.right - x)),
                height: metrics.titleSize.height
            )
        }
    }

    private func quillButtonContentMetrics(
        constrainedTo size: CGSize
    ) -> (
        titleLabel: UILabel?,
        titleSize: CGSize,
        imageView: UIImageView?,
        imageSize: CGSize,
        imageTitleSpacing: CGFloat,
        contentSize: CGSize
    ) {
        let insets = quillMeasuredContentInsets
        let proposedWidth = size.width.isFinite && size.width > 0
            ? max(0, size.width - insets.left - insets.right)
            : CGFloat.greatestFiniteMagnitude
        let proposedHeight = size.height.isFinite && size.height > 0
            ? max(0, size.height - insets.top - insets.bottom)
            : CGFloat.greatestFiniteMagnitude

        let storedLabel = quillButtonState.titleLabel
        let titleText = storedLabel?.attributedText?.string
            ?? storedLabel?.text
            ?? currentAttributedTitle?.string
            ?? currentTitle
            ?? ""
        let measuredLabel = titleText.isEmpty ? nil : (storedLabel ?? titleLabel)
        let titleSize = measuredLabel?.sizeThatFits(CGSize(width: proposedWidth, height: proposedHeight)) ?? .zero

        let imageView = self.imageView
        let imageSize = imageView?.image?.size ?? currentImage?.size ?? .zero
        let spacing = imageSize.width > 0 && titleSize.width > 0 ? quillMeasuredImagePadding : 0
        let contentSize = CGSize(
            width: imageSize.width + spacing + titleSize.width,
            height: max(imageSize.height, titleSize.height)
        )
        return (measuredLabel, titleSize, imageView, imageSize, spacing, contentSize)
    }

    // `setImage(_:for:)` lives in the CLASS BODY (not the UIButtonExtras
    // extension) and is `open` because AvatarImageView OVERRIDES it — an
    // extension method cannot be overridden cross-module. The backing state
    // accessors (`quillButtonState`, `quillRefreshContent`) are `internal` in
    // UIButtonExtras.swift so this reaches them.
    open func setImage(_ image: UIImage?, for state: UIControl.State) {
        if let image {
            quillButtonState.images[state.rawValue] = image
        } else {
            quillButtonState.images.removeValue(forKey: state.rawValue)
        }
        quillRefreshContent()
    }
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
    // Own designated inits suppress inheritance of UIView's
    // required init?(coder:); restate it.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    public var image: UIImage? {
        didSet {
            quillNotifyViewMutation()
            superview?.quillNotifySubviewMutation()
        }
    }
    public var highlightedImage: UIImage? {
        didSet { quillNotifyViewMutation() }
    }
    /// Apple's `UIImageView.isHighlighted` toggles between `image` and
    /// `highlightedImage`. CLASS-BODY `open`: VideoTimelineView's TrimHandleView
    /// overrides it with a `willSet` observer to lazily build the highlighted
    /// image. Pure storage — no renderer swaps the displayed image on Linux yet.
    open var isHighlighted: Bool = false
}

@MainActor open class UILabel: UIView {
    public var text: String? {
        didSet { quillNotifyTextMutation(oldValue != text) }
    }
    /// MODEL HONESTY: stored independently of `text` (real UIKit derives the
    /// plain string from it); no text engine consumes either on Linux yet.
    public var attributedText: NSAttributedString? {
        didSet { quillNotifyTextMutation(oldValue?.string != attributedText?.string) }
    }
    // Platform-gated: on macOS UIColor aliases real NSColor, which spells
    // this semantic color `labelColor`; only the Linux RSColor has `label`.
    #if os(macOS)
    public var textColor: UIColor! = .labelColor {
        didSet { quillNotifyTextMutation(true) }
    }
    #else
    public var textColor: UIColor! = .label {
        didSet { quillNotifyTextMutation(true) }
    }
    #endif
    public var numberOfLines: Int = 1 {
        didSet { quillNotifyTextMutation(oldValue != numberOfLines) }
    }
    // Module-qualified: on macOS this file imports real AppKit alongside
    // QuillFoundation, and the shared text-layout enums (NSTextLayoutShared.swift)
    // would tie with AppKit's under unqualified lookup. No-op on Linux.
    public var lineBreakMode: QuillFoundation.NSLineBreakMode = .byTruncatingTail {
        didSet { quillNotifyTextMutation(oldValue != lineBreakMode) }
    }
    public var textAlignment: QuillFoundation.NSTextAlignment = .natural {
        didSet { quillNotifyTextMutation(oldValue != textAlignment) }
    }
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
    public var preferredMaxLayoutWidth: CGFloat = 0 {
        didSet { quillNotifyTextMutation(oldValue != preferredMaxLayoutWidth) }
    }
    /// Backing store for `font`. The UIFont-typed accessor cannot live here:
    /// UIFont is declared in the UIKit shim module, which depends on this one,
    /// so the shim layers `font: UIFont!` over this slot (UIFontExtras.swift).
    public var quillFontStorage: AnyObject?
    public var quillFontPointSize: CGFloat = 17

    public func quillNotifyTextMutation(_ changed: Bool) {
        guard changed else { return }
        invalidateIntrinsicContentSize()
        quillNotifyViewMutation()
        superview?.quillNotifySubviewMutation()
    }

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

    /// UIKit exposes `sizeToFit` on UIView; Quill keeps it on the concrete
    /// classes that need override points. UILabel callers use it to ask for an
    /// intrinsic-content-size pass, which is inert until a text renderer lands.
    open func sizeToFit() {
        frame.size = sizeThatFits(CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let string = attributedText?.string ?? text ?? ""
        guard !string.isEmpty else {
            return .zero
        }
        let pointSize = quillFontPointSize > 0 && quillFontPointSize.isFinite ? quillFontPointSize : 17
        let lineHeight = ceil(pointSize * 1.25)
        let charWidth = pointSize * 0.56
        let singleLineWidth = ceil(CGFloat(string.count) * charWidth)
        let proposedWidth = size.width.isFinite && size.width > 0 ? size.width : singleLineWidth
        let lineLimit = numberOfLines > 0 ? numberOfLines : Int.max
        let measuredLines = max(1, Int(ceil(singleLineWidth / max(proposedWidth, 1))))
        let lines = min(measuredLines, lineLimit)
        return CGSize(
            width: min(singleLineWidth, proposedWidth),
            height: CGFloat(lines) * lineHeight
        )
    }

    open override var intrinsicContentSize: CGSize {
        sizeThatFits(CGSize(
            width: preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
    }

    public static func titleLabelForRegistration(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
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
    // Apple's hardware-key input sentinels (UIKeyCommand exposes these as the
    // strings passed for `input:`). Values mirror the documented constants:
    // arrows are the UIKit private-use escape strings, escape is ESC.
    public static let inputUpArrow = "UIKeyInputUpArrow"
    public static let inputDownArrow = "UIKeyInputDownArrow"
    public static let inputLeftArrow = "UIKeyInputLeftArrow"
    public static let inputRightArrow = "UIKeyInputRightArrow"
    public static let inputEscape = "\u{1B}"
    public static let inputPageUp = "UIKeyInputPageUp"
    public static let inputPageDown = "UIKeyInputPageDown"
    public static let inputHome = "UIKeyInputHome"
    public static let inputEnd = "UIKeyInputEnd"

    public let input: String
    public let modifierFlags: UIKeyModifierFlags
    public let action: Selector
    /// Title shown in the iPad discoverability HUD / keyboard-shortcut list.
    public var discoverabilityTitle: String?

    public init(input: String, modifierFlags: UIKeyModifierFlags, action: Selector, discoverabilityTitle: String? = nil) {
        self.input = input
        self.modifierFlags = modifierFlags
        self.action = action
        self.discoverabilityTitle = discoverabilityTitle
        super.init()
    }

    /// Apple's older `UIKeyCommand` convenience initializer puts `action:`
    /// first (`init(action:input:modifierFlags:discoverabilityTitle:)`).
    /// MediaTextView uses this argument order, so expose it alongside the
    /// `input:`-first form above.
    public convenience init(action: Selector, input: String, modifierFlags: UIKeyModifierFlags, discoverabilityTitle: String? = nil) {
        self.init(input: input, modifierFlags: modifierFlags, action: action, discoverabilityTitle: discoverabilityTitle)
    }

    public init(title: String, image: Any?, action: Selector, input: String, modifierFlags: UIKeyModifierFlags, propertyList: Any? = nil, alternates: [UIKeyCommand] = [], discoverabilityTitle: String? = nil, attributes: UIMenuElement.Attributes = [], state: UIMenuElement.State = .off) {
        _ = title
        _ = image
        _ = propertyList
        _ = alternates
        _ = attributes
        _ = state
        self.input = input
        self.modifierFlags = modifierFlags
        self.action = action
        self.discoverabilityTitle = discoverabilityTitle ?? title
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

public extension UIViewControllerTransitionCoordinator {
    /// Apple defaults `completion:` to `nil`, so the common call site passes only
    /// the `alongsideTransition` block (often as a trailing closure). The protocol
    /// requirement can't carry a default argument, so forward through this overload.
    @MainActor func animate(
        alongsideTransition: ((UIViewControllerTransitionCoordinatorContext) -> Void)?
    ) {
        animate(alongsideTransition: alongsideTransition, completion: nil)
    }
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

// UIActivity is @MainActor on Apple platforms. The upstream Signal subclasses
// (CompareSafetyNumbersActivity) override these members under default actor
// isolation (@MainActor); a nonisolated base produced "different actor isolation
// from nonisolated overridden declaration" errors. Marking the class @MainActor
// matches UIKit and silences those overrides.
@MainActor open class UIActivity: NSObject {
    public override init() {}
    open var activityTitle: String? { nil }
    open var activityImage: UIImage? { nil }

    public struct ActivityType: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }

        // Apple's system activity-type constants (UIActivity.ActivityType.*),
        // carried so SignalUI's excludedActivityTypes lists resolve. The
        // rawValues match UIKit's `com.apple.UIKit.activity.*` identifiers.
        public static let postToFacebook = ActivityType("com.apple.UIKit.activity.PostToFacebook")
        public static let postToTwitter = ActivityType("com.apple.UIKit.activity.PostToTwitter")
        public static let postToWeibo = ActivityType("com.apple.UIKit.activity.PostToWeibo")
        public static let message = ActivityType("com.apple.UIKit.activity.Message")
        public static let mail = ActivityType("com.apple.UIKit.activity.Mail")
        public static let print = ActivityType("com.apple.UIKit.activity.Print")
        public static let copyToPasteboard = ActivityType("com.apple.UIKit.activity.CopyToPasteboard")
        public static let assignToContact = ActivityType("com.apple.UIKit.activity.AssignToContact")
        public static let saveToCameraRoll = ActivityType("com.apple.UIKit.activity.SaveToCameraRoll")
        public static let addToReadingList = ActivityType("com.apple.UIKit.activity.AddToReadingList")
        public static let postToFlickr = ActivityType("com.apple.UIKit.activity.PostToFlickr")
        public static let postToVimeo = ActivityType("com.apple.UIKit.activity.PostToVimeo")
        public static let postToTencentWeibo = ActivityType("com.apple.UIKit.activity.PostToTencentWeibo")
        public static let airDrop = ActivityType("com.apple.UIKit.activity.AirDrop")
        public static let openInIBooks = ActivityType("com.apple.UIKit.activity.OpenInIBooks")
        public static let markupAsPDF = ActivityType("com.apple.UIKit.activity.MarkupAsPDF")
        public static let sharePlay = ActivityType("com.apple.UIKit.activity.SharePlay")
        public static let collaborationInviteWithLink = ActivityType("com.apple.UIKit.activity.CollaborationInviteWithLink")
        public static let collaborationCopyLink = ActivityType("com.apple.UIKit.activity.CollaborationCopyLink")
        public static let addToHomeScreen = ActivityType("com.apple.UIKit.activity.AddToHomeScreen")
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
    @MainActor private var quillNextBackgroundTaskIdentifier: UIBackgroundTaskIdentifier = 1

    @MainActor @discardableResult public func beginBackgroundTask(
        expirationHandler handler: (() -> Void)? = nil
    ) -> UIBackgroundTaskIdentifier {
        _ = handler
        let identifier = quillNextBackgroundTaskIdentifier
        quillNextBackgroundTaskIdentifier += 1
        return identifier
    }

    @MainActor @discardableResult public func beginBackgroundTask(
        withName taskName: String?,
        expirationHandler handler: (() -> Void)? = nil
    ) -> UIBackgroundTaskIdentifier {
        _ = taskName
        return beginBackgroundTask(expirationHandler: handler)
    }

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
    public var userInterfaceIdiom: UIUserInterfaceIdiom = .unspecified
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
            if traits.userInterfaceIdiom != .unspecified {
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

    /// Whether color-rendering traits (interface style, contrast, display
    /// gamut) differ between the two collections — UIKit uses it to decide
    /// when CGColor-backed content needs re-resolving. There is a single
    /// default color environment on Linux, so this returns false; SignalUI
    /// calls it from traitCollectionDidChange and only needs the answer not
    /// to over-trigger redraws.
    public func hasDifferentColorAppearance(comparedTo traitCollection: UITraitCollection?) -> Bool {
        _ = traitCollection
        return false
    }
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

    // MARK: - Insets (overridable: class body, not an extension)
    //
    // contentInset / scrollIndicatorInsets are `open var` on Apple and upstream
    // scroll-view subclasses override them (StickerPackCollectionView overrides
    // `contentInset` with a `didSet`; others observe it). They were extension
    // accessors in UIKitShim/UIScrollViewInsets.swift because they are
    // UIEdgeInsets-typed and UIEdgeInsets used to be declared only in the UIKit
    // shim (which DEPENDS on this module) — but an extension member "cannot be
    // overridden", so every subclass override became a second declaration →
    // "ambiguous use of 'contentInset'" (198 errors). The fix: UIEdgeInsets is
    // now `typealias UIEdgeInsets = QuillEdgeInsets`, and QuillEdgeInsets lives
    // HERE, so these can be `open` class-body members typed by it — visible to
    // QuillUIKit, and the same type the shim re-exports as UIEdgeInsets, so the
    // upstream overrides resolve as true overrides. (UITableView inherits
    // these; it no longer needs a separate inset backing.)

    /// Extra padding around the content. A genuine change notifies
    /// `scrollViewDidChangeAdjustedContentInset` (the adjusted inset tracks
    /// this one, since Linux safe areas are zero), as Apple's setter does.
    open var contentInset: QuillEdgeInsets = .zero {
        didSet {
            guard contentInset != oldValue else { return }
            delegate?.scrollViewDidChangeAdjustedContentInset(self)
        }
    }

    /// The content inset after safe-area/keyboard adjustment — read-only, as
    /// on Apple. MODEL HONESTY: Linux has no safe areas or keyboard avoidance
    /// (`UIView.safeAreaInsets` is `.zero`), so the adjustment is always zero
    /// and this equals `contentInset`.
    open var adjustedContentInset: QuillEdgeInsets { contentInset }

    /// Insets for the vertical scroll indicator. Stored configuration —
    /// nothing draws indicators on Linux.
    open var verticalScrollIndicatorInsets: QuillEdgeInsets = .zero

    /// Insets for the horizontal scroll indicator.
    open var horizontalScrollIndicatorInsets: QuillEdgeInsets = .zero

    /// The legacy unified indicator inset: Apple documents setting it as
    /// setting both per-axis values and reading it as reading the vertical
    /// one — mirrored exactly.
    open var scrollIndicatorInsets: QuillEdgeInsets {
        get { verticalScrollIndicatorInsets }
        set {
            verticalScrollIndicatorInsets = newValue
            horizontalScrollIndicatorInsets = newValue
        }
    }

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

public extension UIApplicationDelegate {
    static func main() {}
}

public typealias UIBackgroundTaskIdentifier = Int
public extension UIBackgroundTaskIdentifier {
    static let invalid = 0
}

public class UIBackgroundConfiguration: NSObject {
    public static func listGroupedCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public static func listSidebarCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public var visualEffect: UIVisualEffect?
    public var shadowProperties = UIShadowProperties()
}

public class UIShadowProperties: NSObject {
    public var offset: CGSize = .zero
    public var color: UIColor?
    public var radius: CGFloat = 0
    public var opacity: CGFloat = 0
}

public class UIStoryboard: NSObject {
    public let name: String?
    public let bundle: Bundle?

    public override init() {
        self.name = nil
        self.bundle = nil
        super.init()
    }

    public init(name: String, bundle storyboardBundleOrNil: Bundle?) {
        self.name = name
        self.bundle = storyboardBundleOrNil
        super.init()
    }

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
    var row: Int {
        get { count >= 2 ? self[1] : 0 }
        set { self = IndexPath(indexes: [section, newValue]) }
    }
    var section: Int {
        get { count >= 1 ? self[0] : 0 }
        set { self = IndexPath(indexes: [newValue, row]) }
    }
}

public class NonIntrinsicImageView: UIImageView {}

#endif // !os(iOS)

// MARK: - AuthenticationServices
// (The ASWebAuthentication* stubs that used to live here moved to the dedicated
// `AuthenticationServices` shim — Sources/AppleFrameworkShims/AuthenticationServices.
// Keeping a duplicate here caused an ambiguous-type-lookup error once a module
// re-exported both QuillUIKit and AuthenticationServices, e.g. SignalServiceKit
// re-exporting UIKit while its PayPal flow does `import AuthenticationServices`.)
