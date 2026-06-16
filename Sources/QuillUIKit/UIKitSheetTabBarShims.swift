import Foundation
import CoreGraphics
import QuillFoundation

// MARK: - UISheetPresentationController

@MainActor
open class UISheetPresentationController: NSObject {

    public struct Detent: Equatable, Sendable {
        public struct Identifier: RawRepresentable, Equatable, Hashable, Sendable {
            public let rawValue: String
            public init(rawValue: String) { self.rawValue = rawValue }

            public static let medium = Identifier(rawValue: "com.apple.UIKit.medium")
            public static let large = Identifier(rawValue: "com.apple.UIKit.large")
        }

        public let identifier: Identifier

        public init(identifier: Identifier) {
            self.identifier = identifier
        }

        public static func medium() -> Detent { Detent(identifier: .medium) }
        public static func large() -> Detent { Detent(identifier: .large) }
    }

    open var detents: [Detent] = [.large()]
    open var selectedDetentIdentifier: Detent.Identifier?
    open var prefersGrabberVisible: Bool = false
    open var preferredCornerRadius: CGFloat?
    open var largestUndimmedDetentIdentifier: Detent.Identifier?
    open weak var delegate: (any UISheetPresentationControllerDelegate)?

    public override init() {
        super.init()
    }

    open func animateChanges(_ changes: () -> Void) {
        changes()
    }
}

// MARK: - UISheetPresentationControllerDelegate

@MainActor
public protocol UISheetPresentationControllerDelegate: AnyObject {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ c: UISheetPresentationController)
}

public extension UISheetPresentationControllerDelegate {
    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ c: UISheetPresentationController) {}
}

// MARK: - UITabBar

@MainActor
open class UITabBar: UIView {

    open var items: [UITabBarItem]?
    open var selectedItem: UITabBarItem?
    open var barTintColor: UIColor?

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    open func setItems(_ items: [UITabBarItem]?, animated: Bool) {
        self.items = items
    }
}

// MARK: - UITabBarItem

@MainActor
open class UITabBarItem: NSObject {

    open var title: String?
    open var image: UIImage?
    open var badgeValue: String?
    open var tag: Int = 0

    public override init() {
        super.init()
    }

    public init(title: String?, image: UIImage?, tag: Int) {
        self.title = title
        self.image = image
        self.tag = tag
        super.init()
    }
}

// MARK: - UITabBarControllerDelegate

@MainActor
public protocol UITabBarControllerDelegate: AnyObject {}

// MARK: - UITab

@MainActor
open class UITab: NSObject {

    open var title: String
    open var identifier: String
    open var image: UIImage?

    public init(title: String, image: UIImage?, identifier: String) {
        self.title = title
        self.image = image
        self.identifier = identifier
        super.init()
    }
}

// MARK: - UIStatusBarAnimation

public enum UIStatusBarAnimation: Int {
    case none
    case fade
    case slide
}
