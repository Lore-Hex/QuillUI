//===----------------------------------------------------------------------===//
//
//  UIViewControllerSurface.swift
//  QuillUIKit — the UIViewController presentation/paging/search surface
//
//  Fills the controller-level API surface that SignalUI's view controllers
//  compile against, without touching the UIViewController base class in
//  QuillUIKit.swift (one name, one owner):
//
//    - UIStatusBarStyle (the enum only — see the status-bar note below)
//    - UIViewController extensions: `title`, `transitioningDelegate`,
//      `presentationController`, `setNeedsStatusBarAppearanceUpdate()`
//    - UIPresentationController + UIAdaptivePresentationControllerDelegate
//    - The custom-transition protocol family: UIViewControllerContext-
//      Transitioning (+ the from/to keys), UIViewControllerAnimated-
//      Transitioning, UIViewControllerInteractiveTransitioning,
//      UIViewControllerTransitioningDelegate
//    - UIPageViewController + its DataSource/Delegate protocols
//    - UISearchBar + UISearchBarDelegate, UISearchController +
//      UISearchResultsUpdating + UISearchControllerDelegate
//
//  Honest Linux semantics:
//    - Everything here is a faithful MODEL of UIKit's API contract:
//      configuration is stored with Apple's defaults and containment uses
//      the base class's willMove/didMove calling convention, but there is
//      no compositor, so nothing animates, no transition contexts are ever
//      vended, and no search presentation actually occurs.
//    - Stored state added to the existing UIViewController lives in a
//      side table keyed by ObjectIdentifier (the UIGestureRecognizers.swift
//      pattern): entries carry a weak backref to their owner, getters
//      filter on `owner === self` so a recycled heap address can never
//      inherit a dead controller's state, and dead entries are pruned on
//      each first-write.
//
//  STATUS-BAR NOTE (deliberate omission): `preferredStatusBarStyle`,
//  `prefersStatusBarHidden`, and `childForStatusBarStyle` are NOT declared
//  here. SignalUI *overrides* them, and Swift cannot override members
//  introduced in an extension (no @objc dynamism on Linux) — declaring them
//  here would also block the real fix by colliding with a later class-body
//  declaration. They must be added to the UIViewController class body in
//  QuillUIKit.swift, exactly like the `touchesBegan` family documented in
//  UIGestureRecognizers.swift. Only the UIStatusBarStyle type (which those
//  overrides name) and the non-overridable appearance-update no-op live here.
//
//===----------------------------------------------------------------------===//

import QuillFoundation

#if !os(iOS)

// MARK: - UIStatusBarStyle

/// Status-bar text/icon styling. Raw values mirror Apple's (the gap at 2 is
/// the deprecated `.blackOpaque`). There is no status bar on Linux; the value
/// is carried so upstream appearance plumbing type-checks.
public enum UIStatusBarStyle: Int, Sendable {
    case `default` = 0
    case lightContent = 1
    case darkContent = 3
}

// MARK: - UIViewController stored-state side table

/// Per-controller stored state for members the base class (QuillUIKit.swift,
/// not editable from this file) doesn't declare. See the file header for the
/// lifetime rules.
@MainActor private final class ControllerSurfaceState {
    /// Validity backref: a state object only speaks for a controller that is
    /// still alive AND identical to the keyed address.
    weak var owner: UIViewController?
    var title: String?
    /// Weak, as on Apple — Signal's ubiquitous `transitioningDelegate = self`
    /// must not immortalize the controller.
    weak var transitioningDelegate: (any UIViewControllerTransitioningDelegate)?
    /// Cached so repeated `presentationController` reads return one identity
    /// (delegates are attached to it). Holding it here is safe because the
    /// presentation controller's own controller refs are weak — the cache
    /// never keeps the owning controller alive.
    var presentationController: UIPresentationController?

    init(owner: UIViewController) { self.owner = owner }
}

@MainActor private var controllerSurfaceStates: [ObjectIdentifier: ControllerSurfaceState] = [:]

/// Drops entries whose controller has deallocated. Called on each state
/// creation so the table stays bounded by the number of live controllers
/// that ever used this surface.
@MainActor private func pruneDeadControllerStates() {
    controllerSurfaceStates = controllerSurfaceStates.filter { $0.value.owner != nil }
}

extension UIViewController {

    private var surfaceState: ControllerSurfaceState? {
        guard let state = controllerSurfaceStates[ObjectIdentifier(self)],
              state.owner === self else { return nil }
        return state
    }

    private func ensureSurfaceState() -> ControllerSurfaceState {
        if let state = surfaceState { return state }
        pruneDeadControllerStates()
        let state = ControllerSurfaceState(owner: self)
        controllerSurfaceStates[ObjectIdentifier(self)] = state
        return state
    }

    /// A localized title for the controller. As on Apple, setting it also
    /// feeds the navigation item (Apple couples the two unless the item's
    /// title was set independently; the shim always mirrors — the simpler
    /// rule covers upstream's usage, which sets one or the other, not both).
    /// (Apple declares this `open`; extension members can't be overridden,
    /// so subclass `override var title` sites need a class-body declaration.)
    public var title: String? {
        get { surfaceState?.title }
        set {
            ensureSurfaceState().title = newValue
            navigationItem.title = newValue
        }
    }

    /// The custom-transition vendor (weak, as on Apple). Stored faithfully so
    /// `presentationController` can consult it; no animator is ever invoked
    /// because no transitions run.
    public var transitioningDelegate: (any UIViewControllerTransitioningDelegate)? {
        get { surfaceState?.transitioningDelegate }
        set { ensureSurfaceState().transitioningDelegate = newValue }
    }

    /// The presentation controller managing this controller's presentation.
    /// Built lazily on first access — delegate-supplied when the
    /// transitioning delegate vends one (Apple's `.custom` path), otherwise a
    /// plain UIPresentationController — and cached for identity stability.
    public var presentationController: UIPresentationController? {
        let state = ensureSurfaceState()
        if let existing = state.presentationController { return existing }
        let created = transitioningDelegate?.presentationController(
            forPresented: self, presenting: presentingViewController, source: self)
            ?? UIPresentationController(presentedViewController: self, presenting: presentingViewController)
        state.presentationController = created
        return created
    }

    /// No-op: there is no status bar to restyle. Kept callable so upstream
    /// appearance-invalidation calls compile. (The overridable style hooks
    /// themselves are deliberately absent — see the file-header note.)
    public func setNeedsStatusBarAppearanceUpdate() {}
}

// MARK: - UIPresentationController

/// Coordinates a presented controller's chrome. On Apple this object owns the
/// container view and drives adaptivity; here it is an inert, subclassable
/// record of the (presented, presenting) pair — Signal's custom presentation
/// controllers override the open hooks below, which simply never fire.
@MainActor open class UIPresentationController: NSObject {

    // Weak backing refs break the retain cycle through the side-table cache
    // (table -> controller state -> presentation controller -> controller).
    // On Apple a presentation controller never outlives its presented
    // controller, so the non-optional accessor honors that same lifetime
    // contract; tearing it would trap here just as it would over there.
    private weak var _presentedViewController: UIViewController?
    private weak var _presentingViewController: UIViewController?

    /// The controller being presented. Non-optional, as on Apple.
    public var presentedViewController: UIViewController { _presentedViewController! }

    /// The presenting side. Apple resolves a nil `presenting:` argument to
    /// the actual presenter at presentation time; the shim's nearest honest
    /// equivalent is the presented controller's live `presentingViewController`,
    /// falling back to the presented controller itself (Apple never returns
    /// nil here).
    public var presentingViewController: UIViewController {
        _presentingViewController
            ?? presentedViewController.presentingViewController
            ?? presentedViewController
    }

    open weak var delegate: (any UIAdaptivePresentationControllerDelegate)?

    public init(presentedViewController: UIViewController, presenting presentingViewController: UIViewController?) {
        self._presentedViewController = presentedViewController
        self._presentingViewController = presentingViewController
        super.init()
    }

    /// Always nil: the container view is created by a live transition, and
    /// none ever runs. Subclass geometry that does `containerView!.bounds`
    /// compiles and simply must not execute (it wouldn't on Apple either,
    /// outside a presentation).
    public var containerView: UIView? { nil }

    /// The default is the presented controller's view, as on Apple.
    open var presentedView: UIView? { _presentedViewController?.view }

    open var frameOfPresentedViewInContainerView: CGRect { containerView?.bounds ?? .zero }

    open var shouldPresentInFullscreen: Bool { true }
    open var shouldRemovePresentersView: Bool { false }

    // Transition lifecycle hooks: overridden by upstream, invoked by nobody
    // until a presentation backend exists.
    open func presentationTransitionWillBegin() {}
    open func presentationTransitionDidEnd(_ completed: Bool) {}
    open func dismissalTransitionWillBegin() {}
    open func dismissalTransitionDidEnd(_ completed: Bool) {}
    open func containerViewWillLayoutSubviews() {}
    open func containerViewDidLayoutSubviews() {}

    /// UIContentContainer's resize/rotation hook. On Apple, UIKit routes
    /// size transitions through the presentation controller so its chrome
    /// can track the new container size; Signal's custom presentation
    /// controllers (ActionSheetPresentationController,
    /// InteractiveSheetAnimationController) override this with a super call.
    /// No resize pass invokes it on Linux, so the base is a no-op — same
    /// shape as UIViewController's hook in QuillUIKit.swift.
    open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {}
}

/// The navigation controller's delegate surface. Moved here from the UIKit
/// shim module (which depends on this one and re-exports it) so the
/// UINavigationController class body in QuillUIKit.swift can declare Apple's
/// `open weak var delegate`, which upstream (OWSNavigationController)
/// overrides. Empty, as it was in the shim: upstream's optional-requirement
/// calls on it are a separate (non-override) error family.
@MainActor public protocol UINavigationControllerDelegate: AnyObject {}

/// Adaptivity/dismissal notifications. All members are optional on Apple
/// (an @objc protocol); here they are defaulted instead. The
/// UIModalPresentationStyle-typed adaptivity methods are omitted because that
/// type isn't declared in the shims yet.
public protocol UIAdaptivePresentationControllerDelegate: AnyObject {
    @MainActor func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool
    @MainActor func presentationControllerWillDismiss(_ presentationController: UIPresentationController)
    @MainActor func presentationControllerDidDismiss(_ presentationController: UIPresentationController)
    @MainActor func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController)
}

extension UIAdaptivePresentationControllerDelegate {
    @MainActor public func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { true }
    @MainActor public func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {}
    @MainActor public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {}
    @MainActor public func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {}
}

// MARK: - Custom-transition protocol family

/// Keys for the controllers participating in a transition.
public struct UITransitionContextViewControllerKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let from = UITransitionContextViewControllerKey(rawValue: "UITransitionContextFromViewControllerKey")
    public static let to = UITransitionContextViewControllerKey(rawValue: "UITransitionContextToViewControllerKey")
}

/// Keys for the views participating in a transition.
public struct UITransitionContextViewKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let from = UITransitionContextViewKey(rawValue: "UITransitionContextFromViewKey")
    public static let to = UITransitionContextViewKey(rawValue: "UITransitionContextToViewKey")
}

/// The context UIKit hands an animator. The shims never vend one (animators
/// are only ever *consumers* of this protocol upstream); it exists so
/// animator signatures type-check. `presentationStyle` is omitted pending a
/// UIModalPresentationStyle declaration.
public protocol UIViewControllerContextTransitioning: AnyObject {
    @MainActor var containerView: UIView { get }
    @MainActor var isAnimated: Bool { get }
    @MainActor var isInteractive: Bool { get }
    @MainActor var transitionWasCancelled: Bool { get }
    @MainActor var targetTransform: CGAffineTransform { get }
    @MainActor func completeTransition(_ didComplete: Bool)
    @MainActor func updateInteractiveTransition(_ percentComplete: CGFloat)
    @MainActor func finishInteractiveTransition()
    @MainActor func cancelInteractiveTransition()
    @MainActor func pauseInteractiveTransition()
    @MainActor func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController?
    @MainActor func view(forKey key: UITransitionContextViewKey) -> UIView?
    @MainActor func initialFrame(for vc: UIViewController) -> CGRect
    @MainActor func finalFrame(for vc: UIViewController) -> CGRect
}

/// A fixed-duration transition animator. `animationEnded` is optional on
/// Apple, so it is defaulted here; the two core requirements are required
/// there and stay required here.
public protocol UIViewControllerAnimatedTransitioning: AnyObject {
    @MainActor func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval
    @MainActor func animateTransition(using transitionContext: any UIViewControllerContextTransitioning)
    @MainActor func animationEnded(_ transitionCompleted: Bool)
}

extension UIViewControllerAnimatedTransitioning {
    @MainActor public func animationEnded(_ transitionCompleted: Bool) {}
}

/// A driver for interactive transitions. Only `startInteractiveTransition`
/// is required on Apple; the properties are defaulted to Apple's defaults.
public protocol UIViewControllerInteractiveTransitioning: AnyObject {
    @MainActor func startInteractiveTransition(_ transitionContext: any UIViewControllerContextTransitioning)
    @MainActor var completionSpeed: CGFloat { get }
    @MainActor var wantsInteractiveStart: Bool { get }
}

extension UIViewControllerInteractiveTransitioning {
    @MainActor public var completionSpeed: CGFloat { 1 }
    @MainActor public var wantsInteractiveStart: Bool { true }
}

/// The transition vendor consulted by `present(_:animated:)` for `.custom`
/// presentations. Every member is optional on Apple; all are defaulted to
/// nil here, so conformances that only implement a subset compile unchanged.
public protocol UIViewControllerTransitioningDelegate: AnyObject {
    @MainActor func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)?
    @MainActor func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)?
    @MainActor func interactionControllerForPresentation(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)?
    @MainActor func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)?
    @MainActor func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController?
}

extension UIViewControllerTransitioningDelegate {
    @MainActor public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { nil }
    @MainActor public func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { nil }
    @MainActor public func interactionControllerForPresentation(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? { nil }
    @MainActor public func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? { nil }
    @MainActor public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? { nil }
}

// MARK: - UIPageViewController

/// A paging container. Faithful model: configuration and the visible-page
/// set are real (with the base class's containment calling convention), but
/// there is no swipe machinery — the data source is stored, never queried,
/// and the delegate never hears a transition.
@MainActor open class UIPageViewController: UIViewController {

    public enum TransitionStyle: Int, Sendable {
        case pageCurl = 0
        case scroll = 1
    }

    public enum NavigationOrientation: Int, Sendable {
        case horizontal = 0
        case vertical = 1
    }

    public enum NavigationDirection: Int, Sendable {
        case forward = 0
        case reverse = 1
    }

    public enum SpineLocation: Int, Sendable {
        case none = 0
        case min = 1
        case mid = 2
        case max = 3
    }

    public struct OptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let spineLocation = OptionsKey(rawValue: "UIPageViewControllerOptionSpineLocationKey")
        public static let interPageSpacing = OptionsKey(rawValue: "UIPageViewControllerOptionInterPageSpacingKey")
    }

    public let transitionStyle: TransitionStyle
    public let navigationOrientation: NavigationOrientation
    /// From the init options where given, else Apple's per-style default
    /// (`.min` for page-curl, `.none` for scroll).
    public private(set) var spineLocation: SpineLocation

    open weak var delegate: (any UIPageViewControllerDelegate)?
    open weak var dataSource: (any UIPageViewControllerDataSource)?

    /// The currently visible page(s), as last set via `setViewControllers`.
    public private(set) var viewControllers: [UIViewController]?

    public var isDoubleSided: Bool = false

    /// The page-turn recognizers. Always empty: recognizers exist in the
    /// shims, but this container has no event backend to feed them.
    open var gestureRecognizers: [UIGestureRecognizer] { [] }

    public init(
        transitionStyle style: TransitionStyle = .pageCurl,
        navigationOrientation: NavigationOrientation = .horizontal,
        options: [OptionsKey: Any]? = nil
    ) {
        self.transitionStyle = style
        self.navigationOrientation = navigationOrientation
        // interPageSpacing is accepted (upstream passes it) and dropped:
        // spacing is a property of the scrolling layout that doesn't exist.
        self.spineLocation = (options?[.spineLocation] as? Int)
            .flatMap(SpineLocation.init(rawValue:))
            ?? (style == .pageCurl ? .min : .none)
        super.init()
    }

    /// Replaces the visible page set. Containment is real (old pages are
    /// removed with the willMove/removeFromParent convention, new ones added
    /// with addChild/didMove and their views installed); `direction` and
    /// `animated` are accepted and ignored — there is nothing to animate —
    /// and the completion runs synchronously with `true`, the same
    /// convention as the base class's present/dismiss.
    open func setViewControllers(
        _ viewControllers: [UIViewController]?,
        direction: NavigationDirection,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        for child in children {
            child.willMove(toParent: nil)
            child.viewIfLoaded?.removeFromSuperview()
            child.removeFromParent()
        }
        self.viewControllers = viewControllers
        for pageController in viewControllers ?? [] {
            addChild(pageController)
            view.addSubview(pageController.view)
            pageController.didMove(toParent: self)
        }
        completion?(true)
    }
}

/// Neighbor-page vendor. The two neighbor requirements are required on
/// Apple and stay required; the page-indicator pair is optional there and
/// defaulted here.
public protocol UIPageViewControllerDataSource: AnyObject {
    @MainActor func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController?
    @MainActor func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController?
    @MainActor func presentationCount(for pageViewController: UIPageViewController) -> Int
    @MainActor func presentationIndex(for pageViewController: UIPageViewController) -> Int
}

extension UIPageViewControllerDataSource {
    @MainActor public func presentationCount(for pageViewController: UIPageViewController) -> Int { 0 }
    @MainActor public func presentationIndex(for pageViewController: UIPageViewController) -> Int { 0 }
}

/// Transition notifications. All optional on Apple, all defaulted here. The
/// spine/orientation members are omitted: they name UIInterfaceOrientation
/// types the shims don't declare yet.
public protocol UIPageViewControllerDelegate: AnyObject {
    @MainActor func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController])
    @MainActor func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool)
}

extension UIPageViewControllerDelegate {
    @MainActor public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {}
    @MainActor public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {}
}

// MARK: - UISearchBar

/// The search input control. A stored-property model (text, placeholder,
/// chrome flags); no text field is composed underneath because UITextField
/// lives downstream of this module (Sources/UIKitShim), so `searchTextField`
/// is deliberately absent until it can be declared with the right type.
@MainActor open class UISearchBar: UIView {
    open var text: String?
    open var placeholder: String?
    open weak var delegate: (any UISearchBarDelegate)?
    public var barTintColor: UIColor?
    public var showsCancelButton: Bool = false

    public func setShowsCancelButton(_ showsCancelButton: Bool, animated: Bool) {
        self.showsCancelButton = showsCancelButton
    }
}

/// Editing/button callbacks. All optional on Apple, all defaulted here;
/// nothing fires them without an input backend.
public protocol UISearchBarDelegate: AnyObject {
    @MainActor func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String)
    @MainActor func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
    @MainActor func searchBarTextDidBeginEditing(_ searchBar: UISearchBar)
    @MainActor func searchBarTextDidEndEditing(_ searchBar: UISearchBar)
    @MainActor func searchBarSearchButtonClicked(_ searchBar: UISearchBar)
    @MainActor func searchBarCancelButtonClicked(_ searchBar: UISearchBar)
}

extension UISearchBarDelegate {
    @MainActor public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {}
    @MainActor public func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool { true }
    @MainActor public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {}
    @MainActor public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {}
    @MainActor public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {}
    @MainActor public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {}
}

// MARK: - UISearchController

/// Manages search presentation around a results controller. Inert model:
/// configuration and the owned search bar are real; `isActive` is a plain
/// stored flag (setting it presents nothing), and the updater/delegate are
/// stored weakly and never called.
@MainActor open class UISearchController: UIViewController {

    /// The controller that displays results, as passed at init (nil means
    /// "show results in the searched controller itself", as on Apple).
    public let searchResultsController: UIViewController?

    open weak var searchResultsUpdater: (any UISearchResultsUpdating)?
    open weak var delegate: (any UISearchControllerDelegate)?

    private let _searchBar = UISearchBar()
    open var searchBar: UISearchBar { _searchBar }

    open var isActive: Bool = false

    // Presentation knobs, stored with Apple's defaults.
    public var obscuresBackgroundDuringPresentation: Bool = true
    public var dimsBackgroundDuringPresentation: Bool = true
    public var hidesNavigationBarDuringPresentation: Bool = true
    public var automaticallyShowsCancelButton: Bool = true

    public init(searchResultsController: UIViewController?) {
        self.searchResultsController = searchResultsController
        super.init()
    }

    public convenience override init() {
        self.init(searchResultsController: nil)
    }
}

/// Required on Apple, required here: the one callback search text flows
/// through.
public protocol UISearchResultsUpdating: AnyObject {
    @MainActor func updateSearchResults(for searchController: UISearchController)
}

/// Presentation lifecycle notifications. All optional on Apple, all
/// defaulted here.
public protocol UISearchControllerDelegate: AnyObject {
    @MainActor func willPresentSearchController(_ searchController: UISearchController)
    @MainActor func didPresentSearchController(_ searchController: UISearchController)
    @MainActor func willDismissSearchController(_ searchController: UISearchController)
    @MainActor func didDismissSearchController(_ searchController: UISearchController)
}

extension UISearchControllerDelegate {
    @MainActor public func willPresentSearchController(_ searchController: UISearchController) {}
    @MainActor public func didPresentSearchController(_ searchController: UISearchController) {}
    @MainActor public func willDismissSearchController(_ searchController: UISearchController) {}
    @MainActor public func didDismissSearchController(_ searchController: UISearchController) {}
}

#endif // !os(iOS)
