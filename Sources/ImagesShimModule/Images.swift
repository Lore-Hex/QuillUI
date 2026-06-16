import Foundation
import Articles
import NNWAccount  // NNW's Account target (bare "Account" is the IceCubes lane)
import RSCore

extension RSImage {
    public static let maxIconPixelSize = Int(ceil(48.0 * RSScreen.maxScreenScale))
}

public final class IconImage: @unchecked Sendable {
    public let image: RSImage
    public let isSymbol: Bool
    public let isBackgroundSuppressed: Bool
    public let preferredColor: CGColor?

    public var isDark: Bool { false }
    public var isBright: Bool { false }

    public init(
        _ image: RSImage,
        isSymbol: Bool = false,
        isBackgroundSuppressed: Bool = false,
        preferredColor: CGColor? = nil
    ) {
        self.image = image
        self.isSymbol = isSymbol
        self.isBackgroundSuppressed = isBackgroundSuppressed
        self.preferredColor = preferredColor
    }
}

extension IconImage {
    public static var nnwFeedIcon: IconImage {
        IconImage(RSImage(named: "nnwFeedIcon") ?? RSImage(), isBackgroundSuppressed: true)
    }
}

public enum IconSize: Int, CaseIterable, Sendable {
    case small = 1
    case medium = 2
    case large = 3

    public var size: CGSize {
        switch self {
        case .small:
            return CGSize(width: 24, height: 24)
        case .medium:
            return CGSize(width: 36, height: 36)
        case .large:
            return CGSize(width: 48, height: 48)
        }
    }
}

@MainActor public final class FaviconDownloader {
    public static let shared = FaviconDownloader()

    private var iconsByFaviconURL = [String: IconImage]()
    private var iconsByFeedID = [SidebarItemIdentifier: IconImage]()

    public struct UserInfoKey {
        public static let faviconURL = "faviconURL"
    }

    public init() {}

    public func favicon(for feed: Feed) -> IconImage? {
        if let cached = cachedFaviconAsIcon(for: feed) {
            return cached
        }
        guard let faviconURL = feed.faviconURL else {
            return nil
        }
        return favicon(with: faviconURL, homePageURL: feed.homePageURL)
    }

    public func faviconAsIcon(for feed: Feed) -> IconImage? {
        favicon(for: feed)
    }

    public func cachedFaviconAsIcon(for feed: Feed) -> IconImage? {
        if let sidebarItemID = feed.sidebarItemID, let cached = iconsByFeedID[sidebarItemID] {
            return cached
        }
        guard let faviconURL = feed.faviconURL else {
            return nil
        }
        return iconsByFaviconURL[faviconURL]
    }

    public func favicon(with faviconURL: String, homePageURL: String?) -> IconImage? {
        _ = homePageURL
        guard faviconURL.hasPrefix("http://") || faviconURL.hasPrefix("https://") else {
            return nil
        }
        return iconsByFaviconURL[faviconURL]
    }

    public func favicon(withHomePageURL homePageURL: String) -> IconImage? {
        _ = homePageURL
        return nil
    }

    public func cache(_ iconImage: IconImage, forFaviconURL faviconURL: String) {
        iconsByFaviconURL[faviconURL] = iconImage
    }

    public func cache(_ iconImage: IconImage, for feed: Feed) {
        if let sidebarItemID = feed.sidebarItemID {
            iconsByFeedID[sidebarItemID] = iconImage
        }
        if let faviconURL = feed.faviconURL {
            iconsByFaviconURL[faviconURL] = iconImage
        }
    }

    public func emptyCache() {
        iconsByFaviconURL.removeAll()
        iconsByFeedID.removeAll()
    }
}

@MainActor public final class FaviconGenerator {
    public static let shared = FaviconGenerator()
    public static var templateImage: RSImage?

    private var cache = [String: IconImage]()

    public init() {}

    public func favicon(_ feed: Feed) -> IconImage {
        if let cached = cache[feed.url] {
            return cached
        }

        let template = Self.templateImage ?? RSImage(named: "faviconTemplateImage") ?? RSImage(systemName: "globe") ?? RSImage()
        let image = template.maskWithColor(color: UIColor.systemGray.cgColor) ?? template
        let iconImage = IconImage(image, isBackgroundSuppressed: true)
        cache[feed.url] = iconImage
        return iconImage
    }

    public func emptyCache() {
        cache.removeAll()
    }
}

@MainActor public final class FeedIconDownloader {
    public static let shared = FeedIconDownloader()

    private var iconsByFeedID = [SidebarItemIdentifier: IconImage]()

    public init() {}

    public func icon(for feed: Feed) -> IconImage? {
        cachedIcon(for: feed)
    }

    public func cachedIcon(for feed: Feed) -> IconImage? {
        guard let sidebarItemID = feed.sidebarItemID else {
            return nil
        }
        return iconsByFeedID[sidebarItemID]
    }

    public func cache(_ iconImage: IconImage, for feed: Feed) {
        if let sidebarItemID = feed.sidebarItemID {
            iconsByFeedID[sidebarItemID] = iconImage
        }
    }

    public func emptyCache() {
        iconsByFeedID.removeAll()
    }
}

@MainActor public final class AuthorAvatarDownloader {
    public static let shared = AuthorAvatarDownloader()

    private var iconsByAuthor = [Author: IconImage]()

    public init() {}

    public func image(for author: Author) -> IconImage? {
        cachedImage(for: author)
    }

    public func cachedImage(for author: Author) -> IconImage? {
        iconsByAuthor[author]
    }

    public func cache(_ iconImage: IconImage, for author: Author) {
        iconsByAuthor[author] = iconImage
    }

    public func emptyCache() {
        iconsByAuthor.removeAll()
    }
}
