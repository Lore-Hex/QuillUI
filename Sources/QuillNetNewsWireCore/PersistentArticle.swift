import Foundation
import QuillData
import QuillArticles

/// QuillData-backed persistence row for articles. Bridges the
/// upstream `Article` value (final class, not Codable) to a
/// PersistentModel value type that fits QuillData's Schema /
/// ModelContext storage path.
///
/// Per docs/quilldata.md, this is the SwiftData-shaped backend
/// for Linux + macOS, so the rest of the model can read +
/// write per-feed article state without going through a
/// homegrown SQLite wrapper. Eventually replaces the JSON
/// per-Set files in PersistenceStore once the model rewire
/// lands.
///
/// Field shape mirrors upstream `Article` minus the
/// non-persistable bits (Authors set, status object). Read +
/// starred state get inlined as flat Bools so a single fetch
/// can compute filtered timelines without joining a status
/// table — much simpler than upstream's ArticlesDatabase
/// row structure, which we don't need until cross-account sync
/// arrives.
public struct PersistentArticle: PersistentModel {
    /// Unique row key: matches `Article.articleID` (md5 hash of
    /// accountID+feedID+uniqueID via QuillRSCoreShim).
    public let id: String
    public var accountID: String
    public var feedID: String
    public var uniqueID: String
    public var title: String?
    public var contentHTML: String?
    public var contentText: String?
    public var url: String?
    public var externalURL: String?
    public var summary: String?
    public var imageURL: String?
    public var datePublished: Date?
    public var dateModified: Date?
    public var dateArrived: Date
    public var isRead: Bool
    public var isStarred: Bool

    public init(
        id: String,
        accountID: String,
        feedID: String,
        uniqueID: String,
        title: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        url: String? = nil,
        externalURL: String? = nil,
        summary: String? = nil,
        imageURL: String? = nil,
        datePublished: Date? = nil,
        dateModified: Date? = nil,
        dateArrived: Date = Date(),
        isRead: Bool = false,
        isStarred: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.feedID = feedID
        self.uniqueID = uniqueID
        self.title = title
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.url = url
        self.externalURL = externalURL
        self.summary = summary
        self.imageURL = imageURL
        self.datePublished = datePublished
        self.dateModified = dateModified
        self.dateArrived = dateArrived
        self.isRead = isRead
        self.isStarred = isStarred
    }
}

public extension PersistentArticle {
    /// Translate an upstream `Article` into the persistence row.
    /// Used at fetch-time after parseUpstreamArticles produces
    /// the in-memory shape; the result is what the QuillData
    /// ModelContext stores.
    init(_ article: Article, isRead: Bool = false, isStarred: Bool = false) {
        self.init(
            id: article.articleID,
            accountID: article.accountID,
            feedID: article.feedID,
            uniqueID: article.uniqueID,
            title: article.title,
            contentHTML: article.contentHTML,
            contentText: article.contentText,
            url: article.rawLink,
            externalURL: article.rawExternalLink,
            summary: article.summary,
            imageURL: article.rawImageLink,
            datePublished: article.datePublished,
            dateModified: article.dateModified,
            dateArrived: article.status.dateArrived,
            isRead: isRead,
            isStarred: isStarred
        )
    }
}
