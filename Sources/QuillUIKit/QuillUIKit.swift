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

@MainActor open class UIResponder: NSObject {
    open var keyCommands: [UIKeyCommand]? { nil }

    /// UIKit default: a responder refuses first-responder status unless a
    /// subclass opts in (text fields, SignalUI's ActionSheetController, …).
    open var canBecomeFirstResponder: Bool { false }

    @discardableResult
    open func becomeFirstResponder() -> Bool { true }

    @discardableResult
    open func resignFirstResponder() -> Bool { true }

    open func buildMenu(with builder: UIMenuBuilder) {
        _ = builder
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
public class UIWindow: UIView {}
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

    public override init() { super.init() }
    public init(frame: CGRect) {
        super.init()
        self.frame = frame
    }
    public var frame: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0) {
        didSet {
            #if os(Linux)
            _layer?.frame = frame
            #endif
        }
    }
    public var bounds: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0) {
        didSet {
            #if os(Linux)
            _layer?.bounds = bounds
            #endif
        }
    }
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

    open func willMove(toWindow newWindow: UIWindow?) {
        _ = newWindow
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
    open var layer: CALayer {
        if let existing = _layer { return existing }
        let cls = type(of: self).layerClass as? CALayer.Type ?? CALayer.self
        let created = cls.init()
        // Seed from BOTH stored geometry properties: a bounds set before the
        // first layer access must survive (frame alone would reset the
        // layer's bounds to the possibly-zero stored frame). frame first —
        // it derives position + bounds.size — then bounds wins where the
        // caller set it explicitly.
        created.frame = frame
        if bounds != .zero {
            created.bounds = bounds
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
    public func setContentCompressionResistancePriority(_ priority: NSLayoutConstraint.Priority, for axis: NSLayoutConstraint.Axis) {
        _ = priority
        _ = axis
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

    public static func animate(withDuration: TimeInterval, animations: @escaping () -> Void) { animations() }
    public static func animate(
        withDuration: TimeInterval,
        delay: TimeInterval,
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
    public func didMoveToSuperview() {}
    public var translatesAutoresizingMaskIntoConstraints: Bool = true
    public var autoresizingMask: AutoresizingMask = []
    public var clipsToBounds: Bool = true
}

@MainActor open class UIViewController: UIResponder {
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
    public var traitCollection = UITraitCollection()
    public var navigationController: UINavigationController?
    public var splitViewController: UISplitViewController?
    public var navigationItem = UINavigationItem()
    public var preferredContentSize: CGSize = CGSize(width: 0, height: 0)
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

@MainActor public class UINavigationController: UIViewController {
    public var navigationBar = UINavigationBar()
    public func pushViewController(_: UIViewController, animated: Bool) {}
    public func popViewController(animated: Bool) -> UIViewController? { nil }
    public var topViewController: UIViewController?
    public var visibleViewController: UIViewController? { topViewController }
    public var modalPresentationStyle: Int = 0

    /// Inert: UIDevice+FeatureSupport.ows_setOrientation calls this to nudge the
    /// rotation delegate chain after a programmatic orientation change. On QuillOS
    /// the GTK/Qt window manager owns orientation, so there is nothing to rotate;
    /// this no-op stand-in lets SSK's orientation hack compile.
    public static func attemptRotationToDeviceOrientation() {}
}

@MainActor public class UITabBarController: UIViewController {
    public var selectedViewController: UIViewController?
    public var viewControllers: [UIViewController]?
}

@MainActor public class UINavigationBar: UIView {
    private static let appearanceProxy = UINavigationBar()
    public var topItem: UINavigationItem?
    public var isTranslucent: Bool = false
    public var barTintColor: UIColor?

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

public class UIBarButtonItem: NSObject {
    @MainActor public init(image: UIImage?, style: Int, target: Any?, action: Selector?) {}
    @MainActor public init(title: String?, style: Int, target: Any?, action: Selector?) {}
    @MainActor public init(barButtonSystemItem: Int, target: Any?, action: Selector?) {}
    @MainActor public init(customView: UIView) {}
    public var title: String?
    public var isEnabled = true
    public var image: UIImage?
}

@MainActor public class UITableView: UIView {
    public var rowHeight: CGFloat = 0
}

@MainActor public class UITableViewCell: UIView {
    public enum CellStyle: Int { case `default` }
    public init(style: CellStyle, reuseIdentifier: String?) { super.init() }
    public var textLabel: UILabel?
    public var detailTextLabel: UILabel?
    public var imageView: UIImageView?
}

@MainActor public class UICollectionView: UIView {
    public func cellForItem(at: IndexPath) -> UICollectionViewCell? { nil }
}

@MainActor public class UICollectionViewCell: UIView {
    public var contentView = UIView()
    public var backgroundConfiguration: Any?
    public var isHighlighted: Bool = false
    public var isSelected: Bool = false
}

@MainActor public class UIAlertController: UIViewController {
    public init(title: String?, message: String?, preferredStyle: Int) {}
    public func addAction(_: Any) {}
    public var popoverPresentationController: UIPopoverPresentationController?
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
}

@MainActor public class UIActivityViewController: UIViewController {
    public init(url: URL, title: String?, applicationActivities: [Any]?) {}
    public init(activityItems: [Any], applicationActivities: [Any]?) {}
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

    public var isEnabled = true
    public var isSelected = false
    public var isHighlighted = false
    public var state: State = .normal
}

@MainActor public class UIButton: UIControl {
    public var imageView: UIImageView?
    public var accessibilityLabel: String?
    public func setTitle(_: String?, for: Any) {}
}

@MainActor open class UIImageView: UIView {
    public init(image: UIImage?) { super.init() }
    public var contentMode: UIView.ContentMode = .scaleToFill
    public var image: UIImage?
}

@MainActor open class UILabel: UIView {
    public var text: String?
    /// MODEL HONESTY: stored independently of `text` (real UIKit derives the
    /// plain string from it); no text engine consumes either on Linux yet.
    public var attributedText: NSAttributedString?
    public var textColor: UIColor! = .label
    public var numberOfLines: Int = 1
    // Module-qualified: on macOS this file imports real AppKit alongside
    // QuillFoundation, and the shared text-layout enums (NSTextLayoutShared.swift)
    // would tie with AppKit's under unqualified lookup. No-op on Linux.
    public var lineBreakMode: QuillFoundation.NSLineBreakMode = .byTruncatingTail
    public var textAlignment: QuillFoundation.NSTextAlignment = .natural
    /// Recorded but inert: nothing measures or shrinks text on Linux yet.
    public var adjustsFontSizeToFitWidth = false
    public var minimumScaleFactor: CGFloat = 0
    /// Backing store for `font`. The UIFont-typed accessor cannot live here:
    /// UIFont is declared in the UIKit shim module, which depends on this one,
    /// so the shim layers `font: UIFont!` over this slot.
    public var quillFontStorage: AnyObject?
}

@MainActor public class UIVisualEffectView: UIView {}

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

public protocol UIViewControllerTransitionCoordinator: AnyObject {
    @MainActor func animate(alongsideTransition: ((Any) -> Void)?, completion: ((Any) -> Void)?)
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

public class UITraitCollection: NSObject {
    public var userInterfaceStyle: UIUserInterfaceStyle = .unspecified
    public var userInterfaceIdiom: Int = 0
}

@MainActor public class UIScrollView: UIView {
    public enum ContentInsetAdjustmentBehavior: Int {
        case automatic
        case scrollableAxes
        case never
        case always
    }

    public weak var delegate: UIScrollViewDelegate?
    public var contentInsetAdjustmentBehavior: ContentInsetAdjustmentBehavior = .automatic
    public var maximumZoomScale: CGFloat = 1
    public var minimumZoomScale: CGFloat = 1
    public var zoomScale: CGFloat = 1
    public var bouncesZoom: Bool = false
    public var showsHorizontalScrollIndicator: Bool = true
    public var showsVerticalScrollIndicator: Bool = true

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
}

public class UIStoryboard: NSObject {
    @MainActor public static let settings = UIStoryboard()
    @MainActor public static let add = UIStoryboard()
    @MainActor public func instantiateInitialViewController() -> UIViewController? { nil }
    @MainActor public func instantiateViewController(withIdentifier: String) -> UIViewController? { nil }
}

public extension IndexPath {
    var row: Int { return 0 }
    var section: Int { return 0 }
}

public extension UIColor {
    static let label = RSColor()
    static let secondaryLabel = RSColor()
    static let tertiaryLabel = RSColor()
    static let systemBackground = RSColor()
    static let secondarySystemBackground = RSColor()
}

public class NonIntrinsicImageView: UIImageView {}

#endif // !os(iOS)

// MARK: - AuthenticationServices
// (The ASWebAuthentication* stubs that used to live here moved to the dedicated
// `AuthenticationServices` shim — Sources/AppleFrameworkShims/AuthenticationServices.
// Keeping a duplicate here caused an ambiguous-type-lookup error once a module
// re-exported both QuillUIKit and AuthenticationServices, e.g. SignalServiceKit
// re-exporting UIKit while its PayPal flow does `import AuthenticationServices`.)
