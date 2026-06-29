#if os(Linux)

import Foundation
import QuillFoundation

public let CSSearchableItemActionType = "com.apple.corespotlightitem"
public let CSSearchableItemActivityIdentifier = "kCSSearchableItemActivityIdentifier"

public extension String {
    static let content = "public.content"
}

open class CSSearchableItemAttributeSet: NSObject, @unchecked Sendable {
    public let itemContentType: String

    public var title: String?
    public var displayName: String?
    public var contentDescription: String?
    public var thumbnailData: Data?
    public var creator: String?
    public var kind: String?
    public var keywords: [String]?
    public var phoneNumbers: [String]?
    public var emailAddresses: [String]?
    public var supportsPhoneCall: NSNumber?
    public var supportsNavigation: NSNumber?
    public var relatedUniqueIdentifier: String?

    public init(itemContentType: String) {
        self.itemContentType = itemContentType
        super.init()
    }

    public convenience init(contentType: String) {
        self.init(itemContentType: contentType)
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
