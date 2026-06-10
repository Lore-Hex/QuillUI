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
        super.init()
    }
}
