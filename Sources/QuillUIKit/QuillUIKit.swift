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

@MainActor open class UIResponder: NSObject {}

public class NSLayoutAnchor<AnchorType>: NSObject {}
public class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {}
public class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {}

public class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    public func constraint(equalToConstant: CGFloat) -> NSLayoutConstraint { NSLayoutConstraint() }
}

public extension NSLayoutAnchor {
    func constraint(equalTo: NSLayoutAnchor<AnchorType>, constant: CGFloat = 0) -> NSLayoutConstraint { NSLayoutConstraint() }
}

public class NSLayoutConstraint: NSObject {
    public var isActive: Bool = true
    public static func activate(_: [NSLayoutConstraint]) {}
}

public enum UIUserInterfaceStyle: Int {
    case unspecified
    case light
    case dark
}

public class UILayoutGuide: NSObject {
    public var topAnchor = NSLayoutYAxisAnchor()
    public var bottomAnchor = NSLayoutYAxisAnchor()
    public var leadingAnchor = NSLayoutXAxisAnchor()
    public var trailingAnchor = NSLayoutXAxisAnchor()
}

#if !os(macOS)
// Linux-only: UIWindow shadow (macOS already has NSWindow typealiased
// to UIWindow in QuillFoundation).
public class UIWindow: UIView {}
#endif

@MainActor open class UIView: UIResponder {
    public override init() { super.init() }
    public init(frame: CGRect) { super.init() }
    public var frame: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
    public var bounds: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
    public var subviews: [UIView] = []
    public func removeFromSuperview() {}
    public var backgroundColor: UIColor?
    public func addSubview(_: UIView) {}
    public var window: UIWindow?
    public typealias UserInterfaceStyle = UIUserInterfaceStyle
    public var overrideUserInterfaceStyle: UserInterfaceStyle = .unspecified
    public var isHidden: Bool = false
    public var alpha: CGFloat = 1.0
    public var tintColor: UIColor?

    public var safeAreaLayoutGuide = UILayoutGuide()
    public var topAnchor = NSLayoutYAxisAnchor()
    public var bottomAnchor = NSLayoutYAxisAnchor()
    public var leadingAnchor = NSLayoutXAxisAnchor()
    public var trailingAnchor = NSLayoutXAxisAnchor()
    public var widthAnchor = NSLayoutDimension()
    public var heightAnchor = NSLayoutDimension()

    public func setNeedsLayout() {}
    public func layoutIfNeeded() {}

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
}

@MainActor open class UIViewController: UIResponder {
    public var view: UIView!
    public var children: [UIViewController] = []
    public func present(_: Any, animated: Bool) {}
    public func dismiss(animated: Bool, completion: (() -> Void)? = nil) {}
    open func viewDidLoad() {}
    open func viewWillAppear(_: Bool) {}
    open func viewDidAppear(_: Bool) {}
    open func viewWillDisappear(_: Bool) {}
    open func viewDidDisappear(_: Bool) {}
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
    public var modalPresentationStyle: Int = 0
}

@MainActor public class UINavigationBar: UIView {
    public var topItem: UINavigationItem?
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

public class UIAction: NSObject {
    public init(title: String, image: Any?, identifier: Any? = nil, discoverabilityTitle: String? = nil, attributes: Any? = nil, state: Any? = nil, handler: @escaping (Any) -> Void) {}
}

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

@MainActor public class UIControl: UIView {
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
    public var contentMode: Int = 0
    public var image: UIImage?
}

@MainActor public class UILabel: UIView {
    public var text: String?
}

@MainActor public class UIVisualEffectView: UIView {}

public class UIKeyCommand: NSObject {
    public init(title: String, image: Any?, action: Selector, input: String, modifierFlags: Any?, propertyList: Any? = nil) {}
}

public protocol UIViewControllerTransitionCoordinator: AnyObject {
    @MainActor func animate(alongsideTransition: ((Any) -> Void)?, completion: ((Any) -> Void)?)
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

public class UIApplication: NSObject {
    @MainActor public static let shared = UIApplication()
    @MainActor public func open(_: URL, options: [AnyHashable: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {}
    @MainActor public func registerForRemoteNotifications() {}
    public enum LaunchOptionsKey: Hashable { case remoteNotification }
    @MainActor public var connectedScenes: Set<UIScene> = []
}

public class UIScene: NSObject {
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
}

public protocol UIScrollViewDelegate: AnyObject {
    @MainActor func scrollViewDidScroll(_: UIScrollView)
}

public class UIGestureRecognizer: NSObject {
    public enum State: Int {
        case possible
        case began
        case changed
        case ended
        case cancelled
        case failed
    }

    public var state: State = .possible
}

public class UIApplicationShortcutItem: NSObject {
    public var type: String = ""
}

public class UNUserNotificationCenter: NSObject {
    public static func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }
    public func requestAuthorization(options: Any, completionHandler: @escaping (Bool, Error?) -> Void) {}
    @MainActor public weak var delegate: UNUserNotificationCenterDelegate?
}

public protocol UNUserNotificationCenterDelegate: AnyObject {}

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

// MARK: - AuthenticationServices stubs (Linux)

#if !os(iOS) && !os(macOS)
public protocol ASWebAuthenticationPresentationContextProviding: AnyObject {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
}

public class ASWebAuthenticationSession: NSObject {
    public init(url: URL, callbackURLScheme: String?, completionHandler: @escaping (URL?, Error?) -> Void) {}
    public var presentationContextProvider: ASWebAuthenticationPresentationContextProviding?
    public func start() -> Bool { true }
    public func cancel() {}
}

public enum ASWebAuthenticationSessionError: Error {
    case canceledLogin
}
#endif
