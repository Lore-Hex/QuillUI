#if os(Linux)

import Foundation
import QuillFoundation

public let CSSearchableItemActionType = "com.apple.corespotlightitem"
public let CSSearchableItemActivityIdentifier = "kCSSearchableItemActivityIdentifier"

open class CSSearchableItemAttributeSet: NSObject, @unchecked Sendable {
    public let itemContentType: String

    public var title: String?
    public var displayName: String?
    public var contentDescription: String?
    public var relatedUniqueIdentifier = ""
    public var thumbnailData: Data?
    public var creator: String?
    public var kind: String?
    public var keywords: [String]?
    public var phoneNumbers: [String]?
    public var emailAddresses: [String]?
    public var supportsPhoneCall: NSNumber?
    public var supportsNavigation: NSNumber?

    public init(itemContentType: String) {
        self.itemContentType = itemContentType
        super.init()
    }

    public convenience init(contentType: Any) {
        if let identifierProvider = contentType as? (any CoreSpotlightIdentifierProviding) {
            self.init(itemContentType: identifierProvider.coreSpotlightIdentifier)
        } else {
            self.init(itemContentType: String(describing: contentType))
        }
    }
}

public protocol CoreSpotlightIdentifierProviding {
    var coreSpotlightIdentifier: String { get }
}

open class NSUserActivity: NSObject, @unchecked Sendable {
    public let activityType: String
    public var title: String?
    public var keywords = Set<String>()
    public var isEligibleForSearch = false
    public var isEligibleForHandoff = false
    public var isEligibleForPublicIndexing = false
    public var isEligibleForPrediction = false
    public var persistentIdentifier: String?
    public var suggestedInvocationPhrase: String?
    public var webpageURL: URL?
    public var userInfo: [AnyHashable: Any]?
    public var requiredUserInfoKeys = Set<String>()
    public var contentAttributeSet: CSSearchableItemAttributeSet?
    public var needsSave = false
    public private(set) var isCurrent = false
    public private(set) var isInvalidated = false

    public init(activityType: String) {
        self.activityType = activityType
        super.init()
    }

    open func becomeCurrent() {
        isCurrent = true
        isInvalidated = false
    }

    open func resignCurrent() {
        isCurrent = false
    }

    open func invalidate() {
        isCurrent = false
        isInvalidated = true
    }

    open func addUserInfoEntries(from otherDictionary: [AnyHashable: Any]) {
        var next = userInfo ?? [:]
        for (key, value) in otherDictionary {
            next[key] = value
        }
        userInfo = next
    }
}

open class CSSearchableItem: NSObject, @unchecked Sendable {
    public let uniqueIdentifier: String
    public let domainIdentifier: String?
    public let attributeSet: CSSearchableItemAttributeSet
    public var expirationDate: Date?

    public init(uniqueIdentifier: String, domainIdentifier: String?, attributeSet: CSSearchableItemAttributeSet) {
        self.uniqueIdentifier = uniqueIdentifier
        self.domainIdentifier = domainIdentifier
        self.attributeSet = attributeSet
        super.init()
    }
}

open class CSSearchableIndex: NSObject, @unchecked Sendable {
    public static func `default`() -> CSSearchableIndex {
        CSSearchableIndex()
    }

    open func indexSearchableItems(_ items: [CSSearchableItem], completionHandler: ((Error?) -> Void)? = nil) {
        _ = items
        completionHandler?(nil)
    }

    open func deleteSearchableItems(withIdentifiers identifiers: [String], completionHandler: ((Error?) -> Void)? = nil) {
        _ = identifiers
        completionHandler?(nil)
    }

    open func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String], completionHandler: ((Error?) -> Void)? = nil) {
        _ = domainIdentifiers
        completionHandler?(nil)
    }

    open func deleteAllSearchableItems(completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }
}

#endif
