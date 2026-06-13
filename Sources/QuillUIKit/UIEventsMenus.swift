//===----------------------------------------------------------------------===//
//
//  UIEventsMenus.swift
//  QuillUIKit — UIKit-shaped event, touch, and menu types for Linux
//
//  The input-event model (UITouch / UIEvent), the modern menu-element
//  hierarchy (UIMenuElement / UIMenu / UIAction), the legacy edit-menu
//  controller (UIMenuController / UIMenuItem), the context-menu surface
//  (UIContextMenuConfiguration / UIContextMenuInteraction(+Delegate) /
//  UITargetedPreview family), and UITextItemInteraction.
//
//  Honest Linux semantics (the UIGestureRecognizers.swift contract):
//    - There is no event backend yet. UITouch and UIEvent are faithful
//      MODELS: every property Apple exposes read-only is stored here with
//      Apple's defaults and is plainly settable, so the future backend
//      (compositor input → window dispatch) can populate instances and
//      feed them through the UIGestureRecognizer touches hooks. Nothing
//      constructs or delivers them on its own today.
//    - Menus are pure data. UIMenu/UIAction faithfully record their
//      children, attributes, and handlers (reachable for a future
//      presenter via `quillHandler`), but nothing presents them.
//      UIMenuController tracks visibility state and posts its will/did
//      notifications — Signal observes those to reconcile selection UI —
//      without putting anything on screen.
//    - Context-menu interactions store their delegate and configuration
//      faithfully; with no long-press dispatch, the delegate is never
//      consulted. UIPreviewParameters carries `quill*PathStorage` slots
//      (the UILabel.quillFontStorage pattern) because UIBezierPath lives
//      in the UIKitShim layer above this module; the shim layers the
//      typed `visiblePath`/`shadowPath` accessors over those slots.
//
//===----------------------------------------------------------------------===//

import QuillFoundation

#if !os(iOS)

// MARK: - UITouch

/// A single finger (or pointer) on the screen. With no event backend the
/// type is inert: the future backend creates instances, fills the stored
/// properties (including the `quill*Location` slots the geometry accessors
/// read), and delivers them via UIEvent / the gesture-recognizer hooks.
@MainActor open class UITouch: NSObject {

    /// The phase of a touch within its event stream.
    public enum Phase: Int, Sendable {
        case began
        case moved
        case stationary
        case ended
        case cancelled
        case regionEntered
        case regionMoved
        case regionExited
    }

    /// What kind of input produced the touch.
    public enum TouchType: Int, Sendable {
        case direct
        case indirect
        case pencil
        case indirectPointer
    }

    /// Read-only on Apple; plainly settable here so the future event
    /// backend can drive the lifecycle (the UIGestureRecognizer.state
    /// precedent).
    open var phase: UITouch.Phase = .began

    /// Taps registered for this touch. Apple reports 1 for a first tap.
    open var tapCount: Int = 1

    /// Seconds since system startup when the touch occurred or last moved.
    open var timestamp: TimeInterval = 0

    open var type: UITouch.TouchType = .direct

    /// Force properties: meaningful only on 3D-Touch/pencil hardware; 0
    /// everywhere here, as on non-force-capable Apple devices.
    open var force: CGFloat = 0
    open var maximumPossibleForce: CGFloat = 0
    open var majorRadius: CGFloat = 0

    /// The view/window the touch landed in. Weak, as on Apple (the touch
    /// must not keep dying view hierarchies alive between events).
    open weak var view: UIView?
    open weak var window: UIWindow?

    /// The recognizers currently receiving this touch.
    open var gestureRecognizers: [UIGestureRecognizer]? = nil

    /// Backend storage for the geometry accessors below. There is no live
    /// coordinate conversion yet, so locations are tracked in a single
    /// coordinate space — the `in view:` parameters are accepted for API
    /// fidelity only (the UIPanGestureRecognizer.translation(in:) contract).
    public var quillLocation: CGPoint = .zero
    public var quillPreviousLocation: CGPoint = .zero

    /// The touch's location in `view`'s coordinate system.
    open func location(in view: UIView?) -> CGPoint {
        _ = view
        return quillLocation
    }

    /// The touch's location at the previous event delivery.
    open func previousLocation(in view: UIView?) -> CGPoint {
        _ = view
        return quillPreviousLocation
    }
}

// MARK: - UIEvent

/// An input event: a bag of touches plus classification. Like UITouch,
/// a faithful settable model awaiting an event backend.
@MainActor open class UIEvent: NSObject {

    public enum EventType: Int, Sendable {
        case touches = 0
        case motion = 1
        case remoteControl = 2
        case presses = 3
        case scroll = 10
        case hover = 11
        case transform = 14
    }

    public enum EventSubtype: Int, Sendable {
        case none = 0
        case motionShake = 1
        case remoteControlPlay = 100
        case remoteControlPause = 101
        case remoteControlStop = 102
        case remoteControlTogglePlayPause = 103
        case remoteControlNextTrack = 104
        case remoteControlPreviousTrack = 105
        case remoteControlBeginSeekingBackward = 106
        case remoteControlEndSeekingBackward = 107
        case remoteControlBeginSeekingForward = 108
        case remoteControlEndSeekingForward = 109
    }

    open var type: UIEvent.EventType = .touches
    open var subtype: UIEvent.EventSubtype = .none

    /// Seconds since system startup when the event occurred.
    open var timestamp: TimeInterval = 0

    /// Hardware-keyboard modifiers held when the event was generated.
    open var modifierFlags: UIKeyModifierFlags = []

    /// Every touch belonging to the event. Settable for the future
    /// backend; nil until one exists, as for an event with no touches.
    open var allTouches: Set<UITouch>? = nil

    /// The event's touches that belong to `view`.
    open func touches(for view: UIView) -> Set<UITouch>? {
        guard let allTouches else { return nil }
        let matching = allTouches.filter { $0.view === view }
        return matching.isEmpty ? nil : matching
    }

    /// The event's touches being delivered to `gesture`.
    open func touches(for gesture: UIGestureRecognizer) -> Set<UITouch>? {
        guard let allTouches else { return nil }
        let matching = allTouches.filter { touch in
            touch.gestureRecognizers?.contains { $0 === gesture } ?? false
        }
        return matching.isEmpty ? nil : matching
    }
}

// MARK: - UIMenuElement

/// The abstract base of the modern menu hierarchy (UIMenu / UIAction).
/// As on Apple, clients never instantiate it directly — the initializer
/// is internal; only this module's subclasses chain to it.
open class UIMenuElement: NSObject {

    /// Display attributes for an element.
    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let disabled = Attributes(rawValue: 1 << 0)
        public static let destructive = Attributes(rawValue: 1 << 1)
        public static let hidden = Attributes(rawValue: 1 << 2)
        public static let keepsMenuPresented = Attributes(rawValue: 1 << 3)
    }

    /// The selection state of an element.
    public enum State: Int, Sendable {
        case off
        case on
        case mixed
    }

    /// Read-only on Apple's UIMenuElement (UIAction re-exposes them
    /// settable); plainly settable here, which covers both.
    open var title: String
    open var subtitle: String?
    open var image: UIImage?

    init(title: String, subtitle: String? = nil, image: UIImage? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
        super.init()
    }
}

// MARK: - UIMenu

/// A grouping of menu elements: pure data on Linux, faithfully recording
/// children/options until a presenter exists.
public class UIMenu: UIMenuElement {

    public struct Identifier: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }

    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /// Show children inline in the parent, rather than as a submenu.
        public static let displayInline = Options(rawValue: 1 << 0)
        /// Style as destructive.
        public static let destructive = Options(rawValue: 1 << 1)
        public static let singleSelection = Options(rawValue: 1 << 5)
        public static let displayAsPalette = Options(rawValue: 1 << 7)
    }

    public let identifier: UIMenu.Identifier
    public let options: UIMenu.Options
    public private(set) var children: [UIMenuElement]

    public init(
        title: String = "",
        subtitle: String? = nil,
        image: UIImage? = nil,
        identifier: UIMenu.Identifier? = nil,
        options: UIMenu.Options = [],
        children: [UIMenuElement] = []
    ) {
        // Apple synthesizes a unique identifier when none is supplied.
        self.identifier = identifier ?? Identifier(rawValue: "com.quillui.menu.\(UUID().uuidString)")
        self.options = options
        self.children = children
        super.init(title: title, subtitle: subtitle, image: image)
    }

    /// A copy of the menu with different children (same identity/options).
    public func replacingChildren(_ newChildren: [UIMenuElement]) -> UIMenu {
        UIMenu(
            title: title,
            subtitle: subtitle,
            image: image,
            identifier: identifier,
            options: options,
            children: newChildren
        )
    }
}

// MARK: - UIAction

/// The handler invoked when an action is selected.
public typealias UIActionHandler = (UIAction) -> Void

/// A leaf menu element with a closure handler. (Declared here, with the
/// rest of the menu hierarchy, replacing the earlier loosely-typed stub
/// in QuillUIKit.swift — it must subclass UIMenuElement so upstream
/// `UIMenu(children: [UIAction...])` arrays upcast.)
public class UIAction: UIMenuElement {

    public struct Identifier: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }

    public let identifier: UIAction.Identifier
    public var discoverabilityTitle: String?
    public var attributes: UIMenuElement.Attributes
    public var state: UIMenuElement.State
    public var sender: Any?

    /// The selection handler. Apple keeps this private; it is exposed
    /// `quill`-prefixed so a future menu presenter (or a test) can invoke
    /// the recorded action, in the quillTargetActions tradition.
    public let quillHandler: UIActionHandler

    public init(
        title: String = "",
        subtitle: String? = nil,
        image: UIImage? = nil,
        identifier: UIAction.Identifier? = nil,
        discoverabilityTitle: String? = nil,
        attributes: UIMenuElement.Attributes = [],
        state: UIMenuElement.State = .off,
        handler: @escaping UIActionHandler
    ) {
        self.identifier = identifier ?? Identifier(rawValue: "com.quillui.action.\(UUID().uuidString)")
        self.discoverabilityTitle = discoverabilityTitle
        self.attributes = attributes
        self.state = state
        self.quillHandler = handler
        super.init(title: title, subtitle: subtitle, image: image)
    }
}

@MainActor public protocol UIInteraction: AnyObject {
    var view: UIView? { get set }
}

@MainActor public protocol UIEditMenuInteractionDelegate: AnyObject {}

@MainActor public final class UIEditMenuInteraction: NSObject, UIInteraction {
    public weak var view: UIView?
    public weak var delegate: UIEditMenuInteractionDelegate?

    public init(delegate: UIEditMenuInteractionDelegate?) {
        self.delegate = delegate
        super.init()
    }
}

@MainActor private var quillViewInteractions: [ObjectIdentifier: [any UIInteraction]] = [:]

public extension UIView {
    var interactions: [any UIInteraction] {
        quillViewInteractions[ObjectIdentifier(self)] ?? []
    }

    func addInteraction(_ interaction: any UIInteraction) {
        let key = ObjectIdentifier(self)
        var entries = quillViewInteractions[key, default: []]
        if !entries.contains(where: { $0 === interaction }) {
            entries.append(interaction)
        }
        interaction.view = self
        quillViewInteractions[key] = entries
    }

    func removeInteraction(_ interaction: any UIInteraction) {
        let key = ObjectIdentifier(self)
        guard var entries = quillViewInteractions[key] else { return }
        entries.removeAll { $0 === interaction }
        if interaction.view === self {
            interaction.view = nil
        }
        quillViewInteractions[key] = entries.isEmpty ? nil : entries
    }
}

@MainActor public final class UIScrollEdgeElementContainerInteraction: NSObject, UIInteraction {
    public enum Edge: Int, Sendable {
        case top
        case left
        case bottom
        case right
        case leading
        case trailing
    }

    public weak var view: UIView?
    public var edge: Edge = .bottom
    public weak var scrollView: UIScrollView?
}

// MARK: - UIMenuController / UIMenuItem

/// One custom item in the legacy edit menu.
public class UIMenuItem: NSObject {
    public var title: String
    public var action: Selector

    public init(title: String, action: Selector) {
        self.title = title
        self.action = action
        super.init()
    }
}

/// The legacy singleton edit-menu (cut/copy/paste bubble) controller.
/// On Linux nothing is presented, but the visibility state machine is
/// real and the will/did notifications fire, so upstream observers that
/// reconcile selection state against menu dismissal keep working.
@MainActor public class UIMenuController: NSObject {

    public static let shared = UIMenuController()

    public enum ArrowDirection: Int, Sendable {
        case `default`
        case up
        case down
        case left
        case right
    }

    /// Custom items appended after the system items. Stored faithfully.
    public var menuItems: [UIMenuItem]?

    public var arrowDirection: ArrowDirection = .default

    public private(set) var isMenuVisible = false

    /// The menu bubble's frame. Nothing is on screen, so `.zero`.
    public var menuFrame: CGRect { .zero }

    /// The target rect recorded by show/setTargetRect, for the future
    /// presenter (and introspection).
    public private(set) var quillTargetRect: CGRect = .zero
    public private(set) weak var quillTargetView: UIView?

    // MARK: Presentation

    public func showMenu(from targetView: UIView, rect targetRect: CGRect) {
        quillTargetView = targetView
        quillTargetRect = targetRect
        setVisible(true)
    }

    public func hideMenu(from targetView: UIView) {
        _ = targetView
        setVisible(false)
    }

    public func hideMenu() {
        setVisible(false)
    }

    /// Deprecated-era API still used by upstream; same state machine.
    public func setMenuVisible(_ menuVisible: Bool, animated: Bool) {
        _ = animated
        setVisible(menuVisible)
    }

    public func setTargetRect(_ targetRect: CGRect, in targetView: UIView) {
        quillTargetRect = targetRect
        quillTargetView = targetView
    }

    /// Re-validates the menu against the first responder on Apple; with
    /// no menu UI there is nothing to revalidate.
    public func update() {}

    private func setVisible(_ visible: Bool) {
        guard visible != isMenuVisible else { return }
        let center = NotificationCenter.default
        if visible {
            center.post(name: Self.willShowMenuNotification, object: self)
            isMenuVisible = true
            center.post(name: Self.didShowMenuNotification, object: self)
        } else {
            center.post(name: Self.willHideMenuNotification, object: self)
            isMenuVisible = false
            center.post(name: Self.didHideMenuNotification, object: self)
        }
    }

    // MARK: Notifications

    public static let willShowMenuNotification = Notification.Name("UIMenuControllerWillShowMenuNotification")
    public static let didShowMenuNotification = Notification.Name("UIMenuControllerDidShowMenuNotification")
    public static let willHideMenuNotification = Notification.Name("UIMenuControllerWillHideMenuNotification")
    public static let didHideMenuNotification = Notification.Name("UIMenuControllerDidHideMenuNotification")
    public static let menuFrameDidChangeNotification = Notification.Name("UIMenuControllerMenuFrameDidChangeNotification")
}

// MARK: - UITextItemInteraction

/// What the user is doing with a text item (link/attachment) in a text
/// view; the third parameter of UITextViewDelegate's shouldInteractWith
/// methods (Signal's LinkingTextView).
public enum UITextItemInteraction: Int, Sendable {
    case invokeDefaultAction
    case presentActions
    case preview
}

// MARK: - Context menus: configuration

/// Builds the preview controller shown above a context menu.
public typealias UIContextMenuContentPreviewProvider = () -> UIViewController?

/// Builds the menu from the app's suggested elements.
public typealias UIContextMenuActionProvider = ([UIMenuElement]) -> UIMenu?

/// The recipe for one context-menu presentation: identity plus the two
/// deferred providers. Pure data; the providers are stored (reachable
/// via the `quill`-prefixed accessors for a future presenter) and never
/// invoked on Linux today.
public class UIContextMenuConfiguration: NSObject {

    public let identifier: NSCopying

    public let quillPreviewProvider: UIContextMenuContentPreviewProvider?
    public let quillActionProvider: UIContextMenuActionProvider?

    public init(
        identifier: NSCopying? = nil,
        previewProvider: UIContextMenuContentPreviewProvider? = nil,
        actionProvider: UIContextMenuActionProvider? = nil
    ) {
        // Apple substitutes a fresh NSUUID when no identifier is given.
        self.identifier = identifier ?? NSUUID()
        self.quillPreviewProvider = previewProvider
        self.quillActionProvider = actionProvider
        super.init()
    }
}

// MARK: - Context menus: interaction

/// How a context-menu preview commit animates.
public enum UIContextMenuInteractionCommitStyle: Int, Sendable {
    case dismiss
    case pop
}

/// The animation hooks handed to delegate will-display/will-end methods.
/// Only the system creates conformers on Apple; here the protocols exist
/// so upstream delegate implementations type-check.
@MainActor public protocol UIContextMenuInteractionAnimating: AnyObject {
    var previewViewController: UIViewController? { get }
    func addAnimations(_ animations: @escaping () -> Void)
    func addCompletion(_ completion: @escaping () -> Void)
}

@MainActor public protocol UIContextMenuInteractionCommitAnimating: UIContextMenuInteractionAnimating {
    var preferredCommitStyle: UIContextMenuInteractionCommitStyle { get set }
}

/// The long-press-driven context-menu interaction. Faithful storage of
/// delegate and (via UIView.addInteraction, when the interaction plumbing
/// lands) attachment; with no event backend the delegate is never asked
/// for a configuration.
@MainActor public class UIContextMenuInteraction: NSObject {

    /// Weak and get-only, as on Apple.
    public private(set) weak var delegate: UIContextMenuInteractionDelegate?

    /// The view the interaction is attached to. Nothing sets this until
    /// the interaction-attachment plumbing exists.
    public private(set) weak var view: UIView?

    public init(delegate: UIContextMenuInteractionDelegate) {
        self.delegate = delegate
        super.init()
    }

    /// The interaction's location in `view`'s coordinates. No live
    /// touches, so `.zero` (the UIGestureRecognizer.location(in:) contract).
    public func location(in view: UIView?) -> CGPoint {
        _ = view
        return .zero
    }

    /// Dismisses the presented menu; nothing is ever presented.
    public func dismissMenu() {}

    /// Rebuilds the visible menu in place; never visible, so never called.
    public func updateVisibleMenu(_ block: (UIMenu) -> UIMenu) {
        _ = block
    }
}

/// All members are "optional" in the Apple sense except
/// `configurationForMenuAtLocation`, which Apple requires; the rest are
/// defaulted below with Apple's default answers (the
/// UIGestureRecognizerDelegate pattern).
public protocol UIContextMenuInteractionDelegate: AnyObject {
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration?
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating)
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?)
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?)
}

public extension UIContextMenuInteractionDelegate {
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? { nil }
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? { nil }
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {}
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {}
    @MainActor func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {}
}

// MARK: - Targeted previews

/// Where a preview animates from/to: a container view plus a center
/// point in the container's coordinates.
@MainActor public class UIPreviewTarget: NSObject {
    public let container: UIView
    public let center: CGPoint
    public let transform: CGAffineTransform

    public init(container: UIView, center: CGPoint, transform: CGAffineTransform) {
        self.container = container
        self.center = center
        self.transform = transform
        super.init()
    }

    public convenience init(container: UIView, center: CGPoint) {
        self.init(container: container, center: center, transform: .identity)
    }
}

/// Appearance overrides for a preview.
@MainActor public class UIPreviewParameters: NSObject {
    public var backgroundColor: UIColor?

    /// Backing stores for `visiblePath` / `shadowPath`. The
    /// UIBezierPath-typed accessors cannot live here: UIBezierPath is
    /// declared in the UIKit shim module, which depends on this one, so
    /// the shim layers the typed properties over these slots (the
    /// UILabel.quillFontStorage pattern).
    public var quillVisiblePathStorage: AnyObject?
    public var quillShadowPathStorage: AnyObject?
}

/// A view to feature during context-menu (and drag) transitions.
@MainActor public class UITargetedPreview: NSObject {
    public let view: UIView
    public let parameters: UIPreviewParameters
    public let target: UIPreviewTarget

    public var size: CGSize { view.bounds.size }

    public init(view: UIView, parameters: UIPreviewParameters, target: UIPreviewTarget) {
        self.view = view
        self.parameters = parameters
        self.target = target
        super.init()
    }

    /// Apple targets the view's current position in its superview; with
    /// no live geometry the frame midpoint is the faithful equivalent.
    public convenience init(view: UIView, parameters: UIPreviewParameters) {
        let target = UIPreviewTarget(
            container: view.superview ?? view,
            center: CGPoint(x: view.frame.midX, y: view.frame.midY)
        )
        self.init(view: view, parameters: parameters, target: target)
    }

    public convenience init(view: UIView) {
        self.init(view: view, parameters: UIPreviewParameters())
    }
}

#endif // !os(iOS)
