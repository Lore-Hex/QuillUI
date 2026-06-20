@_exported import QuillFoundation
@_exported import QuillUIKit
@_exported import AppKit

@MainActor
public protocol SFSafariViewControllerDelegate: AnyObject {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController)
}

@MainActor
public class SFSafariViewController: UIViewController {
    public final class Configuration: @unchecked Sendable {
        public var entersReaderIfAvailable: Bool = false
        public init() {}
    }

    public weak var delegate: SFSafariViewControllerDelegate?
    public var preferredBarTintColor: UIColor?
    public var preferredControlTintColor: UIColor?
    public let url: URL
    public let configuration: Configuration

    public init(url: URL, configuration: Configuration = Configuration()) {
        self.url = url
        self.configuration = configuration
        // UIViewController's `init()` is convenience; super-call the designated init
        // (else "undefined symbol UIViewController.init()" at link time).
        super.init(nibName: nil, bundle: nil)
    }

    // QuillUIKit's UIViewController declares `required init?(coder:)`; once this
    // class adds its own designated init it must restate the required init.
    // No archive is decoded on Linux, so url falls back to a blank URL.
    public required init?(coder: NSCoder) {
        self.url = URL(string: "about:blank")!
        self.configuration = Configuration()
        super.init(coder: coder)
    }
}

@MainActor
open class SFSafariExtensionHandler: NSObject {
    public override init() {
        super.init()
    }

    open func messageReceived(withName messageName: String, from page: SFSafariPage, userInfo: [String: Any]?) {
        _ = (messageName, page, userInfo)
    }

    open func toolbarItemClicked(in window: SFSafariWindow) {
        _ = window
    }

    open func validateToolbarItem(in window: SFSafariWindow, validationHandler: @escaping (Bool, String) -> Void) {
        _ = window
        validationHandler(false, "")
    }
}

@MainActor
open class SFSafariExtensionViewController: NSViewController {}

@MainActor
open class SFSafariWindow: NSObject {
    public var activeTab: SFSafariTab?

    public init(activeTab: SFSafariTab? = nil) {
        self.activeTab = activeTab
        super.init()
    }

    open func getActiveTab(completionHandler: @escaping (SFSafariTab?) -> Void) {
        completionHandler(activeTab)
    }
}

@MainActor
open class SFSafariTab: NSObject {
    public var activePage: SFSafariPage?

    public init(activePage: SFSafariPage? = nil) {
        self.activePage = activePage
        super.init()
    }

    open func getActivePage(completionHandler: @escaping (SFSafariPage?) -> Void) {
        completionHandler(activePage)
    }
}

@MainActor
open class SFSafariPage: NSObject {
    public struct DispatchedMessage: Equatable, Sendable {
        public let name: String
        public let userInfo: [String: String]

        public init(name: String, userInfo: [String: Any]?) {
            self.name = name
            self.userInfo = userInfo?.compactMapValues { value in
                switch value {
                case let string as String:
                    return string
                case let bool as Bool:
                    return bool ? "true" : "false"
                case let number as NSNumber:
                    return number.stringValue
                default:
                    return nil
                }
            } ?? [:]
        }
    }

    public var properties: SFSafariPageProperties?
    public private(set) var dispatchedMessages: [DispatchedMessage] = []

    public init(properties: SFSafariPageProperties? = SFSafariPageProperties(isActive: true)) {
        self.properties = properties
        super.init()
    }

    open func dispatchMessageToScript(withName messageName: String, userInfo: [String: Any]?) {
        dispatchedMessages.append(DispatchedMessage(name: messageName, userInfo: userInfo))
    }

    open func getPropertiesWithCompletionHandler(_ completionHandler: @escaping (SFSafariPageProperties?) -> Void) {
        completionHandler(properties)
    }
}

public struct SFSafariPageProperties: Sendable {
    public var isActive: Bool?

    public init(isActive: Bool? = nil) {
        self.isActive = isActive
    }
}
