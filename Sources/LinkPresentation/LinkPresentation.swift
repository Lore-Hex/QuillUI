import UIKit

public final class LPLinkMetadata: @unchecked Sendable {
    public var title: String?
    public var imageProvider: NSItemProvider?

    public init() {}
}

@MainActor
public protocol UIActivityItemSource: AnyObject {
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any
    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any?
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata?
}
