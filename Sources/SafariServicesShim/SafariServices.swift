@_exported import QuillFoundation
@_exported import QuillUIKit

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
