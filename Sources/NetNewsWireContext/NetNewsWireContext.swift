@_exported import Foundation

#if os(macOS) || os(iOS)
@_exported import CoreGraphics
#else
public typealias CGFloat = Double
public struct CGPoint: Sendable {
    public var x, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
public struct CGSize: Sendable {
    public var width, height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}
public struct CGRect: Sendable {
    public var origin: CGPoint
    public var size: CGSize
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = CGPoint(x: x, y: y)
        self.size = CGSize(width: width, height: height)
    }
}
#endif

@MainActor public var appDelegate: AppDelegateShim!

@MainActor public class AppDelegateShim: NSObject {
    public var unreadCount = 0
}

public class AppDefaults: @unchecked Sendable {
    public static let shared = AppDefaults()
    public var unreadCount = 0
    public var lastImageCacheFlushDate: Date?
    public var isArticleContentJavascriptEnabled = true
    public var articleTextSize = ArticleTextSize.medium
    public var timelineIconSize = 40
    public var timelineNumberOfLines = 2
    public var hideReadFeeds = false
    public var expandedContainers = Set<String>()
    public var selectedSidebarItem: String?
    public var smartFeedsHidingReadArticles = Set<String>()
    public var splitViewPreferredDisplayMode = 0
    public var defaultBrowserID: String?
    public var openInBrowserInBackground = true
    public var addFeedAccountID: String?
    public var addFeedFolderName: String?
}

public enum ArticleTextSize: Int {
    case small, medium, large, extraLarge
    public var cssClass: String { "medium" }
}
