//===----------------------------------------------------------------------===//
//
//  UINavigationExtras.swift
//  QuillUIKit — navigation chrome: bars, bar items, and the indicator control
//
//  Fills the bar-level API surface SignalUI compiles against, extending the
//  thin UINavigationBar/UINavigationItem/UIBarButtonItem declarations that
//  live in QuillUIKit.swift (another owner — extensions only here):
//
//    - UIBarStyle, UIBarPosition, UIBarPositioning(+Delegate)
//    - UINavigationBarDelegate (+ defaults) and UINavigationBar extras
//      (`barStyle`, `delegate`) via side table
//    - UINavigationItem extras (`searchController`,
//      `hidesSearchBarWhenScrolling`) via side table
//    - UINavigationController.Operation (named by the
//      UINavigationControllerDelegate animation hooks in UIKitShim)
//    - UIBarButtonItem.Style / .SystemItem + the Apple-typed convenience
//      inits layered over QuillUIKit.swift's Int-typed designated inits
//    - UIToolbar (+ UIToolbarDelegate)
//    - UIActivityIndicatorView
//
//  Honest Linux semantics: everything is a faithful MODEL of UIKit's API
//  contract — configuration is stored with Apple's defaults, but no bar is
//  composited, no bar button is hit-testable, and the activity indicator's
//  animation state is a flag (plus the hidesWhenStopped visibility rule),
//  not a spinner.
//
//  Stored state added to classes declared elsewhere uses the side-table
//  pattern from UIViewControllerSurface.swift / UIGestureRecognizers.swift:
//  entries carry a weak owner backref, getters filter on `owner === self` so
//  a recycled heap address can never inherit a dead object's state, and dead
//  entries are pruned on each first-write.
//
//===----------------------------------------------------------------------===//

import QuillFoundation

#if !os(iOS)

// MARK: - UIBarStyle

/// Bar chrome styling. Raw values mirror Apple's; `blackOpaque` is Apple's
/// deprecated alias for `.black` (same raw value over there, so it is a
/// static alias here — Swift enums cannot repeat raw values).
public enum UIBarStyle: Int, Sendable {
    case `default` = 0
    case black = 1
    /// Deprecated on Apple ("use .black with isTranslucent = true").
    case blackTranslucent = 2

    /// Deprecated on Apple ("use .black").
    public static var blackOpaque: UIBarStyle { .black }
}

// MARK: - UIBarPosition + UIBarPositioning

/// Where a bar sits relative to its containing view. Raw values mirror
/// Apple's.
public enum UIBarPosition: Int, Sendable {
    case any = 0
    case bottom = 1
    case top = 2
    case topAttached = 3
}

/// Adopted by bars that report a position. As on Apple.
@MainActor public protocol UIBarPositioning: AnyObject {
    var barPosition: UIBarPosition { get }
}

/// The positioning callback shared by the bar delegates. Optional on Apple,
/// defaulted here; `.any` mirrors Apple's "unimplemented" behavior (the bar
/// falls back to its own default position).
@MainActor public protocol UIBarPositioningDelegate: AnyObject {
    func position(for bar: any UIBarPositioning) -> UIBarPosition
}

extension UIBarPositioningDelegate {
    @MainActor public func position(for bar: any UIBarPositioning) -> UIBarPosition { .any }
}

// MARK: - UINavigationBarDelegate

/// Push/pop interception for a navigation bar's item stack. All methods are
/// optional on Apple; required-with-defaults here (the codebase convention —
/// conformer implementations win through the witness table). Nothing invokes
/// them yet: QuillUIKit's UINavigationBar has no item-stack machinery, so
/// upstream implementations (OWSNavigationController's back-button
/// interception) compile and simply never fire.
@MainActor public protocol UINavigationBarDelegate: UIBarPositioningDelegate {
    func navigationBar(_ navigationBar: UINavigationBar, shouldPush item: UINavigationItem) -> Bool
    func navigationBar(_ navigationBar: UINavigationBar, didPush item: UINavigationItem)
    func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool
    func navigationBar(_ navigationBar: UINavigationBar, didPop item: UINavigationItem)
}

extension UINavigationBarDelegate {
    @MainActor public func navigationBar(_ navigationBar: UINavigationBar, shouldPush item: UINavigationItem) -> Bool { true }
    @MainActor public func navigationBar(_ navigationBar: UINavigationBar, didPush item: UINavigationItem) {}
    @MainActor public func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool { true }
    @MainActor public func navigationBar(_ navigationBar: UINavigationBar, didPop item: UINavigationItem) {}
}

// MARK: - UINavigationBar extras (side table)

/// Per-bar stored state for members the class body (QuillUIKit.swift, not
/// editable from this file) doesn't declare.
@MainActor private final class NavigationBarExtrasState {
    weak var owner: UINavigationBar?
    var barStyle: UIBarStyle = .default
    /// Weak, as on Apple (a navigation controller sets itself as its bar's
    /// delegate; the bar must not immortalize it).
    weak var delegate: (any UINavigationBarDelegate)?

    /// The iOS-13 scrollable appearances. Stored faithfully (strong, as on
    /// Apple — the bar owns them); installed by SignalUI's OWSNavigationBar
    /// but never composited.
    var standardAppearance: UINavigationBarAppearance?
    var scrollEdgeAppearance: UINavigationBarAppearance?
    var compactAppearance: UINavigationBarAppearance?
    var compactScrollEdgeAppearance: UINavigationBarAppearance?

    init(owner: UINavigationBar) { self.owner = owner }
}

@MainActor private var navigationBarExtrasStates: [ObjectIdentifier: NavigationBarExtrasState] = [:]

extension UINavigationBar {

    private var extrasState: NavigationBarExtrasState? {
        guard let state = navigationBarExtrasStates[ObjectIdentifier(self)],
              state.owner === self else { return nil }
        return state
    }

    private func ensureExtrasState() -> NavigationBarExtrasState {
        if let state = extrasState { return state }
        navigationBarExtrasStates = navigationBarExtrasStates.filter { $0.value.owner != nil }
        let state = NavigationBarExtrasState(owner: self)
        navigationBarExtrasStates[ObjectIdentifier(self)] = state
        return state
    }

    /// Stored faithfully (Apple's default); nothing draws bar chrome yet.
    public var barStyle: UIBarStyle {
        get { extrasState?.barStyle ?? .default }
        set { ensureExtrasState().barStyle = newValue }
    }

    /// Stored weakly, as on Apple; never called (no item-stack machinery).
    public var delegate: (any UINavigationBarDelegate)? {
        get { extrasState?.delegate }
        set { ensureExtrasState().delegate = newValue }
    }

    /// The appearance used in the bar's standard (non-scrolled) state.
    /// Stored faithfully; nothing draws bar chrome on Linux.
    public var standardAppearance: UINavigationBarAppearance {
        get { extrasState?.standardAppearance ?? UINavigationBarAppearance() }
        set { ensureExtrasState().standardAppearance = newValue }
    }

    /// The appearance used when scrolled to the top edge. Nil means "fall
    /// back to standardAppearance", as on Apple.
    public var scrollEdgeAppearance: UINavigationBarAppearance? {
        get { extrasState?.scrollEdgeAppearance }
        set { ensureExtrasState().scrollEdgeAppearance = newValue }
    }

    /// The appearance used in a compact (landscape-phone) bar. Nil means
    /// "fall back to standardAppearance", as on Apple.
    public var compactAppearance: UINavigationBarAppearance? {
        get { extrasState?.compactAppearance }
        set { ensureExtrasState().compactAppearance = newValue }
    }

    /// The appearance used in a compact bar scrolled to the top edge.
    public var compactScrollEdgeAppearance: UINavigationBarAppearance? {
        get { extrasState?.compactScrollEdgeAppearance }
        set { ensureExtrasState().compactScrollEdgeAppearance = newValue }
    }
}

// MARK: - UINavigationItem extras (side table)

/// Per-item stored state for members the class body (QuillUIKit.swift, not
/// editable from this file) doesn't declare.
@MainActor private final class NavigationItemExtrasState {
    weak var owner: UINavigationItem?
    /// Strong, as on Apple — the navigation item owns its search controller.
    var searchController: UISearchController?
    var hidesSearchBarWhenScrolling = true
    var preferredSearchBarPlacement: UINavigationItem.SearchBarPlacement = .automatic

    init(owner: UINavigationItem) { self.owner = owner }
}

extension UINavigationItem {
    /// Where the integrated search bar sits relative to the title. Raw values
    /// mirror Apple's (iOS 16+).
    public enum SearchBarPlacement: Int, Sendable {
        case automatic = 0
        case inline = 1
        case stacked = 2
    }
}

@MainActor private var navigationItemExtrasStates: [ObjectIdentifier: NavigationItemExtrasState] = [:]

extension UINavigationItem {

    private var extrasState: NavigationItemExtrasState? {
        guard let state = navigationItemExtrasStates[ObjectIdentifier(self)],
              state.owner === self else { return nil }
        return state
    }

    private func ensureExtrasState() -> NavigationItemExtrasState {
        if let state = extrasState { return state }
        navigationItemExtrasStates = navigationItemExtrasStates.filter { $0.value.owner != nil }
        let state = NavigationItemExtrasState(owner: self)
        navigationItemExtrasStates[ObjectIdentifier(self)] = state
        return state
    }

    /// The search controller to integrate into the navigation interface.
    /// Stored (strongly, as on Apple) and never presented — there is no
    /// navigation-bar compositor; the controller's own surface lives in
    /// UIViewControllerSurface.swift.
    public var searchController: UISearchController? {
        get { extrasState?.searchController }
        set { ensureExtrasState().searchController = newValue }
    }

    /// Stored faithfully (Apple's default is true); nothing scrolls a bar.
    public var hidesSearchBarWhenScrolling: Bool {
        get { extrasState?.hidesSearchBarWhenScrolling ?? true }
        set { ensureExtrasState().hidesSearchBarWhenScrolling = newValue }
    }

    /// The preferred placement of the integrated search bar. Stored faithfully
    /// (Apple's default is `.automatic`); no navigation bar lays it out.
    public var preferredSearchBarPlacement: SearchBarPlacement {
        get { extrasState?.preferredSearchBarPlacement ?? .automatic }
        set { ensureExtrasState().preferredSearchBarPlacement = newValue }
    }
}

// MARK: - UINavigationController.Operation

extension UINavigationController {
    /// The transition kind handed to UINavigationControllerDelegate's
    /// animation hooks (declared in UIKitShim/UIKit.swift, which names this
    /// type). Raw values mirror Apple's.
    public enum Operation: Int, Sendable {
        case none = 0
        case push = 1
        case pop = 2
    }
}

// MARK: - UINavigationController toolbar plumbing (side table)

/// Per-controller stored state for the toolbar members the class body
/// (QuillUIKit.swift, not editable from this file) doesn't declare.
@MainActor private final class NavigationControllerExtrasState {
    weak var owner: UINavigationController?
    /// Created on first `toolbar` access, then identity-stable (Apple vends
    /// one toolbar per navigation controller).
    var toolbar: UIToolbar?
    /// Apple's default: hidden until something shows it.
    var isToolbarHidden = true

    init(owner: UINavigationController) { self.owner = owner }
}

@MainActor private var navigationControllerExtrasStates: [ObjectIdentifier: NavigationControllerExtrasState] = [:]

extension UINavigationController {

    private var extrasState: NavigationControllerExtrasState? {
        guard let state = navigationControllerExtrasStates[ObjectIdentifier(self)],
              state.owner === self else { return nil }
        return state
    }

    private func ensureExtrasState() -> NavigationControllerExtrasState {
        if let state = extrasState { return state }
        navigationControllerExtrasStates = navigationControllerExtrasStates.filter { $0.value.owner != nil }
        let state = NavigationControllerExtrasState(owner: self)
        navigationControllerExtrasStates[ObjectIdentifier(self)] = state
        return state
    }

    /// The controller's toolbar, built lazily and identity-stable, as on
    /// Apple. Never composited; items flow in via the visible controller's
    /// `toolbarItems` on Apple, and here only by direct assignment.
    public var toolbar: UIToolbar! {
        let state = ensureExtrasState()
        if let existing = state.toolbar { return existing }
        let created = UIToolbar()
        state.toolbar = created
        return created
    }

    /// Stored faithfully (Apple defaults to hidden); nothing shows or hides.
    public var isToolbarHidden: Bool {
        get { extrasState?.isToolbarHidden ?? true }
        set { ensureExtrasState().isToolbarHidden = newValue }
    }

    /// `animated` is accepted and ignored — there is nothing to animate.
    public func setToolbarHidden(_ hidden: Bool, animated: Bool) {
        isToolbarHidden = hidden
    }
}

// MARK: - UIBarButtonItem spacer factories
//
// The Style/SystemItem enums and Apple-typed convenience inits that sat
// here moved INTO the UIBarButtonItem class body (QuillUIKit.swift) when
// the accessibility wave rebuilt it — same-wave twin resolved in favor of
// the class-body version (stored title/image/style, designated init()).
// Only the iOS-14 spacer factories remain here.
extension UIBarButtonItem {

    /// Apple's iOS 14 spacer factories. (Apple returns `Self`; that needs a
    /// required initializer, which the class body — another owner — doesn't
    /// declare, so these return the base type. Call sites are unaffected.)
    @MainActor public static func flexibleSpace() -> UIBarButtonItem {
        UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
    }

    /// The width is accepted and dropped (no `width` storage on the class
    /// body, and no bar lays items out).
    @MainActor public static func fixedSpace(_ width: CGFloat) -> UIBarButtonItem {
        UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
    }
}

// MARK: - UIToolbar

/// The bottom-bar delegate. Empty beyond positioning, as on Apple.
@MainActor public protocol UIToolbarDelegate: UIBarPositioningDelegate {}

/// A bar of UIBarButtonItems. Faithful model: the items array and chrome
/// knobs are stored with Apple's defaults; nothing is laid out or drawn, and
/// `setItems(_:animated:)` is the plain assignment (there is no animation).
@MainActor open class UIToolbar: UIView, UIBarPositioning {
    private static let appearanceProxy = UIToolbar()
    public static func appearance() -> UIToolbar { appearanceProxy }

    open var items: [UIBarButtonItem]?

    open func setItems(_ items: [UIBarButtonItem]?, animated: Bool) {
        self.items = items
    }

    public var barStyle: UIBarStyle = .default
    public var isTranslucent: Bool = true
    public var barTintColor: UIColor?
    open weak var delegate: (any UIToolbarDelegate)?
    open var quillBackgroundImages: [String: UIImage] = [:]
    open var quillShadowImages: [String: UIImage] = [:]

    public func setBackgroundImage(_ image: UIImage?, forToolbarPosition position: UIBarPosition, barMetrics: UIBarMetrics) {
        quillBackgroundImages["\(position.rawValue):\(barMetrics.rawValue)"] = image
    }

    public func setShadowImage(_ image: UIImage?, forToolbarPosition position: UIBarPosition, barMetrics: UIBarMetrics) {
        quillShadowImages["\(position.rawValue):\(barMetrics.rawValue)"] = image
    }

    /// A toolbar sits at the bottom, as on Apple.
    public var barPosition: UIBarPosition { .bottom }
}

public enum UIBarMetrics: Int, Sendable {
    case `default` = 0
    case compact = 1
    case defaultPrompt = 101
    case compactPrompt = 102
}

// MARK: - UIBarAppearance family
//
// The iOS-13 scrollable-appearance objects (UIBarAppearance and its
// per-bar subclasses). SignalUI's OWSNavigationBar builds a
// UINavigationBarAppearance, fills in background/title/shadow fields, and
// installs it on the bar's standard/scrollEdge/compact slots. Faithful
// MODEL: every field is stored with Apple's default; nothing draws bar
// chrome on Linux, so the installed appearance is inert state. The
// `configureWith*Background()` helpers reset the background fields exactly
// as Apple documents (opaque/default leave a system fill; transparent
// clears it).

/// The shared base for the per-bar appearance objects. Background, shadow,
/// and idiom configuration, as on Apple.
@MainActor open class UIBarAppearance: NSObject {

    /// Which idiom this appearance was created for. Apple defaults to the
    /// current device idiom; there is one idiom on Linux, so `.unspecified`.
    public enum Idiom: Int, Sendable {
        case unspecified = -1
        case phone = 0
        case pad = 1
        case tv = 2
        case carPlay = 3
        case mac = 5
        case vision = 6
    }

    /// The bar's background fill. Nil means "use the effect / system
    /// default", as on Apple.
    open var backgroundColor: UIColor?

    /// The blur/vibrancy applied behind the bar.
    open var backgroundEffect: UIBlurEffect?

    /// A background image drawn behind the bar (wins over the color/effect
    /// on Apple).
    open var backgroundImage: UIImage?

    /// How the background image is tiled/stretched. Raw value mirrors
    /// Apple's `UIView.ContentMode`-shaped default (`.scaleToFill`).
    open var backgroundImageContentMode: UIView.ContentMode = .scaleToFill

    /// The hairline separator color below the bar. Nil clears it (SignalUI
    /// sets `shadowColor = nil` to suppress the default).
    open var shadowColor: UIColor?

    /// A custom separator image below the bar.
    open var shadowImage: UIImage?

    public override init() {
        super.init()
    }

    /// Apple's idiom-typed initializer; the idiom is accepted and dropped
    /// (one idiom on Linux).
    public init(idiom: Idiom) {
        super.init()
    }

    /// Copy initializer, as on Apple (OWSNavigationBar never uses it, but
    /// upstream appearance plumbing relies on it existing).
    public init(barAppearance: UIBarAppearance) {
        self.backgroundColor = barAppearance.backgroundColor
        self.backgroundEffect = barAppearance.backgroundEffect
        self.backgroundImage = barAppearance.backgroundImage
        self.backgroundImageContentMode = barAppearance.backgroundImageContentMode
        self.shadowColor = barAppearance.shadowColor
        self.shadowImage = barAppearance.shadowImage
        super.init()
    }

    /// Resets to an opaque system background (Apple drops any custom
    /// image/effect and restores the default fill + shadow).
    open func configureWithOpaqueBackground() {
        backgroundColor = nil
        backgroundImage = nil
        backgroundEffect = nil
    }

    /// Resets to the default translucent system background.
    open func configureWithDefaultBackground() {
        backgroundColor = nil
        backgroundImage = nil
        backgroundEffect = nil
    }

    /// Clears the background and the shadow (Apple's transparent preset).
    open func configureWithTransparentBackground() {
        backgroundColor = nil
        backgroundImage = nil
        backgroundEffect = nil
        shadowColor = nil
        shadowImage = nil
    }
}

/// Text/tint styling for a UIBarButtonItem within a bar appearance.
/// Faithful container of the per-state text attributes; nothing renders it.
@MainActor open class UIBarButtonItemAppearance: NSObject {

    public enum Style: Int, Sendable {
        case plain = 0
        case done = 1
    }

    /// The styling for a single control state. (Apple calls this
    /// UIBarButtonItemStateAppearance; the only members SignalUI-class code
    /// touches are the text attributes.)
    @MainActor public final class StateAppearance: NSObject {
        public var titleTextAttributes: [NSAttributedString.Key: Any] = [:]
    }

    public let normal = StateAppearance()
    public let highlighted = StateAppearance()
    public let disabled = StateAppearance()
    public let focused = StateAppearance()

    public override init() { super.init() }

    public init(style: Style) { super.init() }
}

/// The navigation-bar specialization. Adds the title/large-title text
/// attributes and the per-position bar-button appearances, as on Apple.
@MainActor open class UINavigationBarAppearance: UIBarAppearance {

    /// Styling for the (centered) title. SignalUI assigns this directly.
    open var titleTextAttributes: [NSAttributedString.Key: Any] = [:]

    /// Styling for the large title.
    open var largeTitleTextAttributes: [NSAttributedString.Key: Any] = [:]

    /// Appearance for regular bar-button items.
    open var buttonAppearance = UIBarButtonItemAppearance()
    /// Appearance for "Done"-style bar-button items.
    open var doneButtonAppearance = UIBarButtonItemAppearance()
    /// Appearance for the back button.
    open var backButtonAppearance = UIBarButtonItemAppearance()

    public override init() { super.init() }
    public override init(idiom: Idiom) { super.init(idiom: idiom) }
    public override init(barAppearance: UIBarAppearance) { super.init(barAppearance: barAppearance) }
}

// (UIToolbarAppearance / UITabBarAppearance are the other UIBarAppearance
// subclasses on Apple, but SignalUI never builds them, so they are omitted —
// add them if a future file references them.)

// MARK: - UIActivityIndicatorView

/// The spinner. Faithful model: animation state is a stored flag coupled to
/// visibility exactly as Apple couples it (start unhides; stop hides when
/// `hidesWhenStopped`), but nothing spins — there is no compositor.
@MainActor open class UIActivityIndicatorView: UIView {

    /// Raw values mirror Apple's (`.whiteLarge`/`.white`/`.gray` are the
    /// deprecated pre-iOS 13 cases; `.medium`/`.large` are current).
    public enum Style: Int, Sendable {
        /// Deprecated on Apple ("use .large").
        case whiteLarge = 0
        /// Deprecated on Apple ("use .medium").
        case white = 1
        /// Deprecated on Apple ("use .medium").
        case gray = 2
        case medium = 100
        case large = 101
    }

    open var style: Style = .medium

    /// Apple's default. Visibility is updated on stop (and start), not on
    /// flag flips, matching Apple.
    open var hidesWhenStopped: Bool = true

    /// The spinner tint. Nil means the system default over there; nothing
    /// reads it back here until something draws.
    open var color: UIColor!

    public private(set) var isAnimating: Bool = false

    public convenience init(style: Style) {
        self.init(frame: .zero)
        self.style = style
    }

    open func startAnimating() {
        isAnimating = true
        isHidden = false
    }

    open func stopAnimating() {
        isAnimating = false
        if hidesWhenStopped {
            isHidden = true
        }
    }
}

#endif // !os(iOS)
