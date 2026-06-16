//===----------------------------------------------------------------------===//
//
//  UIScrollViewExtras.swift
//  QuillUIKit — the UIScrollView scrolling surface for Linux
//
//  The bulk of UIScrollView's API beyond the zoom members declared in the
//  class body (QuillUIKit.swift): content geometry (contentOffset /
//  contentSize), scrolling configuration flags, deceleration / keyboard /
//  indicator option types, the scroll-driving gesture recognizers, and the
//  remaining UIScrollViewDelegate callbacks.
//
//  Honest Linux semantics (same MODEL-not-engine rules as the rest of the
//  module):
//    - There is no event backend, so nothing ever scrolls on its own.
//      `isTracking` / `isDragging` / `isDecelerating` are honestly `false`;
//      configuration flags are faithfully stored Apple defaults that a
//      future compositor can consume.
//    - `contentOffset` IS `bounds.origin`, exactly as on Apple (UIScrollView
//      scrolls by translating its own bounds). Programmatic offset changes
//      are therefore real model mutations, visible to any geometry code,
//      and they notify `scrollViewDidScroll`, as Apple's setter does.
//    - Animated variants complete instantly (no animation backend);
//      `scrollViewDidEndScrollingAnimation` fires synchronously so upstream
//      continuation logic still runs.
//
//  Storage: the class body lives in QuillUIKit.swift (another owner), and
//  extensions cannot add stored properties, so per-instance state lives in a
//  file-scope side table — the UIView.gestureRecognizers pattern. A weak
//  `owner` backref guards every read against ObjectIdentifier address reuse,
//  and dead entries are swept on write.
//
//  Insets: contentInset / scrollIndicatorInsets / adjustedContentInset are
//  UIEdgeInsets-typed and `open` (subclasses override them), so they live in
//  the UIScrollView CLASS BODY (QuillUIKit.swift), typed `QuillEdgeInsets`.
//  This is possible because `UIEdgeInsets` is a typealias to `QuillEdgeInsets`
//  (declared in this module) — the UIKit shim re-exports it under the Apple
//  name. They are NOT in this extension (extension members cannot be
//  overridden, which made every upstream override ambiguous).
//
//  NOT here on purpose: `contentLayoutGuide` / `frameLayoutGuide` (the Auto
//  Layout surface owns those).
//
//===----------------------------------------------------------------------===//

import QuillFoundation

#if !os(iOS)

// MARK: - Per-instance state side table

/// Everything UIScrollView needs to remember per instance, with Apple's
/// documented defaults. (`contentOffset` is absent: it lives in
/// `bounds.origin`, see the accessor.)
private struct QuillScrollViewState {
    /// Address-reuse guard: a side-table entry is only valid while the view
    /// that wrote it is still alive AND is the view reading it. See
    /// UIGestureRecognizers.swift for the rationale.
    weak var owner: UIScrollView?

    var isScrollEnabled = true
    var isPagingEnabled = false
    var isDirectionalLockEnabled = false
    var bounces = true
    var alwaysBounceVertical = false
    var alwaysBounceHorizontal = false
    var canCancelContentTouches = true
    var delaysContentTouches = true
    var automaticallyAdjustsScrollIndicatorInsets = true
    var decelerationRate = UIScrollView.DecelerationRate.normal
    var keyboardDismissMode = UIScrollView.KeyboardDismissMode.none
    var indicatorStyle = UIScrollView.IndicatorStyle.default

    // contentInset / verticalScrollIndicatorInsets / horizontalScrollIndicatorInsets
    // are NO LONGER stored here. They are `open` stored properties on the
    // UIScrollView class body (QuillUIKit.swift) now that UIEdgeInsets is a
    // typealias to QuillEdgeInsets (this module's type) — so subclasses can
    // override them. The side table only holds state that has no class-body home.

    /// Lazily-created scroll-driving recognizers. Strong, like the view's
    /// hold on any attached recognizer; the recognizers' weak `view`
    /// backrefs point back at `owner` once attached.
    var panGestureRecognizer: UIPanGestureRecognizer?
    var pinchGestureRecognizer: UIPinchGestureRecognizer?
}

@MainActor private var quillScrollViewStates: [ObjectIdentifier: QuillScrollViewState] = [:]

extension UIScrollView {

    /// The instance's state, validated against address reuse on read and
    /// re-stamped with `owner` on write. Mutating a property through this
    /// accessor (`quillScrollState.bounces = …`) is a read-modify-write.
    private var quillScrollState: QuillScrollViewState {
        get {
            if let state = quillScrollViewStates[ObjectIdentifier(self)], state.owner === self {
                return state
            }
            return QuillScrollViewState(owner: self)
        }
        set {
            // First write from this instance: sweep entries whose owner has
            // deallocated so the table stays bounded by live scroll views.
            if quillScrollViewStates[ObjectIdentifier(self)]?.owner !== self {
                quillScrollViewStates = quillScrollViewStates.filter { $0.value.owner != nil }
            }
            var state = newValue
            state.owner = self
            quillScrollViewStates[ObjectIdentifier(self)] = state
        }
    }

    // MARK: - Option types

    /// The rate at which scrolling decelerates after a drag. Apple models
    /// this as a CGFloat wrapper with two blessed values; upstream reads
    /// `.rawValue` for custom curves, so the raw values match Apple's.
    public struct DecelerationRate: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        /// Apple's default rate (0.998).
        public static let normal = DecelerationRate(rawValue: 0.998)
        /// Apple's fast rate (0.99), used for paging-like feels.
        public static let fast = DecelerationRate(rawValue: 0.99)
    }

    /// How dragging the scroll view dismisses the keyboard. Stored
    /// configuration: with no event backend there is no drag (and no
    /// keyboard) to act on yet.
    public enum KeyboardDismissMode: Int, Sendable {
        case none
        case onDrag
        case interactive
        case onDragWithAccessory
        case interactiveWithAccessory
    }

    /// The scroll-indicator color style. Stored configuration only — no
    /// compositor draws indicators on Linux.
    public enum IndicatorStyle: Int, Sendable {
        case `default`
        case black
        case white
    }

    // MARK: - Content geometry
    //
    // contentOffset / setContentOffset(_:animated:) / contentSize /
    // scrollRectToVisible / scrollsToTop moved to the UIScrollView CLASS BODY
    // (QuillUIKit.swift): Apple declares them `open` and upstream subclasses
    // override them, but extension members "cannot be overridden". (The members
    // that REMAIN below are `open var` on Apple too, but nothing overrides them,
    // so they stay extension members — `public`, since extensions can't be
    // `open`.)

    // MARK: - Scrolling configuration (stored Apple defaults)

    /// Whether user-initiated scrolling is allowed. Apple's default: true.
    public var isScrollEnabled: Bool {
        get { quillScrollState.isScrollEnabled }
        set { quillScrollState.isScrollEnabled = newValue }
    }

    /// Whether scrolling snaps to viewport-sized pages. Apple's default: false.
    public var isPagingEnabled: Bool {
        get { quillScrollState.isPagingEnabled }
        set { quillScrollState.isPagingEnabled = newValue }
    }

    /// Whether dragging locks to a single axis. Apple's default: false.
    public var isDirectionalLockEnabled: Bool {
        get { quillScrollState.isDirectionalLockEnabled }
        set { quillScrollState.isDirectionalLockEnabled = newValue }
    }

    /// Whether the content bounces past its edges. Apple's default: true.
    public var bounces: Bool {
        get { quillScrollState.bounces }
        set { quillScrollState.bounces = newValue }
    }

    /// Whether vertical bouncing happens even when content fits. Apple's
    /// default: false.
    public var alwaysBounceVertical: Bool {
        get { quillScrollState.alwaysBounceVertical }
        set { quillScrollState.alwaysBounceVertical = newValue }
    }

    /// Whether horizontal bouncing happens even when content fits. Apple's
    /// default: false.
    public var alwaysBounceHorizontal: Bool {
        get { quillScrollState.alwaysBounceHorizontal }
        set { quillScrollState.alwaysBounceHorizontal = newValue }
    }

    /// Whether touches already delivered to content can be canceled to
    /// start a scroll. Apple's default: true.
    public var canCancelContentTouches: Bool {
        get { quillScrollState.canCancelContentTouches }
        set { quillScrollState.canCancelContentTouches = newValue }
    }

    /// Whether touch-down delivery to content is briefly delayed. Apple's
    /// default: true.
    public var delaysContentTouches: Bool {
        get { quillScrollState.delaysContentTouches }
        set { quillScrollState.delaysContentTouches = newValue }
    }

    /// The post-drag deceleration rate. Apple's default: `.normal`.
    public var decelerationRate: DecelerationRate {
        get { quillScrollState.decelerationRate }
        set { quillScrollState.decelerationRate = newValue }
    }

    /// Keyboard dismissal on drag. Apple's default: `.none`.
    public var keyboardDismissMode: KeyboardDismissMode {
        get { quillScrollState.keyboardDismissMode }
        set { quillScrollState.keyboardDismissMode = newValue }
    }

    /// Indicator color style. Apple's default: `.default`.
    public var indicatorStyle: IndicatorStyle {
        get { quillScrollState.indicatorStyle }
        set { quillScrollState.indicatorStyle = newValue }
    }

    /// Whether indicator insets track the safe area. Apple's default: true.
    /// Inert configuration on Linux (safe areas are zero).
    public var automaticallyAdjustsScrollIndicatorInsets: Bool {
        get { quillScrollState.automaticallyAdjustsScrollIndicatorInsets }
        set { quillScrollState.automaticallyAdjustsScrollIndicatorInsets = newValue }
    }

    /// Briefly flashes the scroll indicators on Apple. MODEL HONESTY:
    /// nothing draws indicators on Linux, so this is a no-op.
    public func flashScrollIndicators() {}

    // MARK: - Live-interaction state (read-only on Apple)

    /// Whether a touch is currently down in the content. No event backend,
    /// so honestly `false`.
    public var isTracking: Bool { false }

    /// Whether the user is actively dragging. Always `false` (see above).
    public var isDragging: Bool { false }

    /// Whether the view is decelerating after a drag. Always `false`.
    public var isDecelerating: Bool { false }

    /// Whether a zoom gesture is in progress. Always `false`.
    public var isZooming: Bool { false }

    /// Whether the zoom is bouncing past its scale limits. Always `false`.
    public var isZoomBouncing: Bool { false }

    // MARK: - Gesture recognizers

    /// The pan recognizer driving scrolling. Created lazily and attached to
    /// the view (which then owns it), as on Apple — upstream disables it,
    /// reads its state, or wires failure requirements against it. Inert
    /// until an event backend exists, like every recognizer in this module.
    public var panGestureRecognizer: UIPanGestureRecognizer {
        if let existing = quillScrollState.panGestureRecognizer, existing.view === self {
            return existing
        }
        let recognizer = UIPanGestureRecognizer(target: nil, action: nil)
        addGestureRecognizer(recognizer)
        quillScrollState.panGestureRecognizer = recognizer
        return recognizer
    }

    /// The pinch recognizer driving zooming. Apple returns nil when zooming
    /// is impossible (the scale range is empty) — mirrored here, so the
    /// recognizer only materializes for zoomable scroll views.
    public var pinchGestureRecognizer: UIPinchGestureRecognizer? {
        guard minimumZoomScale != maximumZoomScale else { return nil }
        if let existing = quillScrollState.pinchGestureRecognizer, existing.view === self {
            return existing
        }
        let recognizer = UIPinchGestureRecognizer(target: nil, action: nil)
        addGestureRecognizer(recognizer)
        quillScrollState.pinchGestureRecognizer = recognizer
        return recognizer
    }

    // Inset accessors (contentInset / scrollIndicatorInsets &c.) moved to the
    // UIScrollView CLASS BODY (QuillUIKit.swift): they are `open` and upstream
    // subclasses override them, which an extension member cannot allow. They
    // are typed `QuillEdgeInsets` (== UIEdgeInsets via the UIKit-shim typealias).
}

// MARK: - UIScrollViewDelegate defaults

/// The rest of the delegate surface. The protocol's body (QuillUIKit.swift)
/// declares `scrollViewDidScroll` as a requirement and defaults
/// `viewForZooming(in:)` / `scrollViewDidEndZooming` in its own extension;
/// these are the remaining callbacks, defaulted with Apple's no-op (or
/// documented-default) answers so conformers keep implementing only what
/// they care about.
///
/// NOTE: these are extension members, not protocol requirements (the
/// protocol body has a different owner), so a call through the existential
/// reaches THESE implementations, not a conformer's. That costs nothing
/// today — the only caller is this file's instant-completion notifications —
/// and the methods can graduate to defaulted requirements when an event
/// backend starts driving them.
public extension UIScrollViewDelegate {
    @MainActor func scrollViewDidZoom(_ scrollView: UIScrollView) {}
    @MainActor func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {}
    @MainActor func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {}
    @MainActor func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {}
    @MainActor func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {}
    @MainActor func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {}
    @MainActor func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {}
    @MainActor func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {}
    @MainActor func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { true }
    @MainActor func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {}
    @MainActor func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {}
}

#endif // !os(iOS)
