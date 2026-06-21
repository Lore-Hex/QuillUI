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

@MainActor public var appDelegate: AppDelegate! = AppDelegate()

@MainActor public func appDelegateUnreadCount() -> Int {
    appDelegate?.unreadCount ?? 0
}

public final class AppDelegate {
    public struct AddFeedRequest {
        public let urlString: String?
        public let name: String?
        public let account: AnyObject?
        public let folder: AnyObject?

        public init(urlString: String?, name: String?, account: AnyObject?, folder: AnyObject?) {
            self.urlString = urlString
            self.name = name
            self.account = account
            self.folder = folder
        }
    }

    public var unreadCount = 0
    public private(set) var addFeedRequests = [AddFeedRequest]()
    public private(set) var removedMainWindows = [AnyObject]()
    public var lastAddFeedRequest: AddFeedRequest? { addFeedRequests.last }

    public init() {}

    public func addFeed(_ urlString: String?, name: String? = nil, account: AnyObject? = nil, folder: AnyObject? = nil) {
        addFeedRequests.append(AddFeedRequest(urlString: urlString, name: name, account: account, folder: folder))
    }

    public func resetAddFeedRequests() {
        addFeedRequests.removeAll()
    }

    public func removeMainWindow(_ windowController: AnyObject) {
        removedMainWindows.append(windowController)
    }
}

public class AppDefaults: @unchecked Sendable {
    public static let shared = AppDefaults()
    public static let defaultThemeName = "Default"
    public var unreadCount = 0
    public var lastImageCacheFlushDate: Date?
    public var isArticleContentJavascriptEnabled = true
    public var articleTextSize = AppDefaultsArticleTextSize.medium
    public var currentThemeName: String?
    public var refreshInterval = AppDefaultsRefreshInterval.every30Minutes
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

public enum AppDefaultsArticleTextSize: Int, Sendable {
    case small = 1
    case medium = 2
    case large = 3
    case xlarge = 4
    case xxlarge = 5

    public var cssClass: String {
        switch self {
        case .small: return "smallText"
        case .medium: return "mediumText"
        case .large: return "largeText"
        case .xlarge: return "xLargeText"
        case .xxlarge: return "xxLargeText"
        }
    }
}

public enum AppDefaultsRefreshInterval: Int, Sendable {
    case manually = 1
    case every30Minutes = 2
    case everyHour = 3
    case every2Hours = 4
    case every4Hours = 5
    case every8Hours = 6

    public func inSeconds() -> TimeInterval {
        switch self {
        case .manually: return 0
        case .every30Minutes: return 30 * 60
        case .everyHour: return 60 * 60
        case .every2Hours: return 2 * 60 * 60
        case .every4Hours: return 4 * 60 * 60
        case .every8Hours: return 8 * 60 * 60
        }
    }
}
