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
}

// MARK: - UINavigationItem extras (side table)

/// Per-item stored state for members the class body (QuillUIKit.swift, not
/// editable from this file) doesn't declare.
@MainActor private final class NavigationItemExtrasState {
    weak var owner: UINavigationItem?
    /// Strong, as on Apple — the navigation item owns its search controller.
    var searchController: UISearchController?
    var hidesSearchBarWhenScrolling = true

    init(owner: UINavigationItem) { self.owner = owner }
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

    public func setBackgroundImage(_ image: UIImage?, forToolbarPosition position: UIBarPosition, barMetrics: UIBarMetrics) {
        quillBackgroundImages["\(position.rawValue):\(barMetrics.rawValue)"] = image
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
