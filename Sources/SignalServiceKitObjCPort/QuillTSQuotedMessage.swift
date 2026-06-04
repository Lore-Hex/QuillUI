//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful Swift port of Messages/Interactions/Quotes/TSQuotedMessage.{h,m}
// (ObjC, excluded on Linux). A standalone `NSObject <NSSecureCoding, NSCopying>`
// archived into the owning message's `quotedMessage` column (no SDS table), so
// the contract is the NSCoding keys + the two construction initializers, not a
// GRDB record. It is a stored-property type of TSMessage, hence a prerequisite
// for the TSMessage port.
//
// Divergence (Linux, noted): the ancient `quotedAttachments` (plural array)
// legacy-archive fallback in initWithCoder used `decodeObjectOfClasses:` and is
// dropped — only the single `quotedAttachment` key is decoded. RUNTIME archiver
// class-name aliasing is tracked separately (the NSKeyedArchiver wall).
//
import Foundation

// MARK: - TSQuotedMessageContentSource (declared in TSQuotedMessage.h)

public enum TSQuotedMessageContentSource: UInt {
    case unknown = 0
    case local = 1
    case remote = 2
    case story = 3
}

// MARK: - TSQuotedMessage

public class TSQuotedMessage: NSObject, NSSecureCoding, NSCopying {

    /// Raw ms timestamp of the quoted message; exposed publicly only as the
    /// nullable `timestampValue` (0 == "no timestamp").
    internal var timestamp: UInt64

    public internal(set) var authorAddress: SignalServiceAddress
    public internal(set) var bodySource: TSQuotedMessageContentSource

    /// Set IFF quoting a text message or attachment with caption.
    public internal(set) var body: String?
    public internal(set) var bodyRanges: MessageBodyRanges?

    public internal(set) var isGiftBadge: Bool
    public internal(set) var isTargetMessageViewOnce: Bool
    public internal(set) var isPoll: Bool

    /// Exposed via `attachmentInfo()`.
    internal var quotedAttachment: OWSAttachmentInfo?

    public var timestampValue: NSNumber? {
        timestamp == 0 ? nil : NSNumber(value: timestamp)
    }

    // MARK: Initializers

    /// Used when receiving quoted messages. Do not call directly outside AttachmentManager.
    public init(timestamp: UInt64,
                authorAddress: SignalServiceAddress,
                body: String?,
                bodyRanges: MessageBodyRanges?,
                bodySource: TSQuotedMessageContentSource,
                receivedQuotedAttachmentInfo attachmentInfo: OWSAttachmentInfo?,
                isGiftBadge: Bool,
                isTargetMessageViewOnce: Bool,
                isPoll: Bool) {
        owsAssertDebug(authorAddress.isValid)
        self.timestamp = timestamp
        self.authorAddress = authorAddress
        self.body = body
        self.bodyRanges = bodyRanges
        self.bodySource = bodySource
        self.quotedAttachment = attachmentInfo
        self.isGiftBadge = isGiftBadge
        self.isTargetMessageViewOnce = isTargetMessageViewOnce
        self.isPoll = isPoll
        super.init()
    }

    /// Used when sending quoted messages.
    public init(timestamp: NSNumber?,
                authorAddress: SignalServiceAddress,
                body: String?,
                bodyRanges: MessageBodyRanges?,
                quotedAttachmentForSending attachmentInfo: OWSAttachmentInfo?,
                isGiftBadge: Bool,
                isTargetMessageViewOnce: Bool,
                isPoll: Bool) {
        owsAssertDebug(authorAddress.isValid)
        self.timestamp = timestamp?.uint64Value ?? 0
        self.authorAddress = authorAddress
        self.body = body
        self.bodyRanges = bodyRanges
        self.bodySource = .local
        self.quotedAttachment = attachmentInfo
        self.isGiftBadge = isGiftBadge
        self.isTargetMessageViewOnce = isTargetMessageViewOnce
        self.isPoll = isPoll
        super.init()
    }

    /// Used when restoring quoted messages from backups.
    public class func quotedMessageFromBackup(
        targetMessageTimestamp timestamp: NSNumber?,
        authorAddress: SignalServiceAddress,
        body: String?,
        bodyRanges: MessageBodyRanges?,
        bodySource: TSQuotedMessageContentSource,
        quotedAttachmentInfo attachmentInfo: OWSAttachmentInfo?,
        isGiftBadge: Bool,
        isTargetMessageViewOnce: Bool,
        isPoll: Bool
    ) -> TSQuotedMessage {
        owsAssertDebug(authorAddress.isValid)
        return TSQuotedMessage(
            timestamp: timestamp?.uint64Value ?? 0,
            authorAddress: authorAddress,
            body: body,
            bodyRanges: bodyRanges,
            bodySource: bodySource,
            receivedQuotedAttachmentInfo: attachmentInfo,
            isGiftBadge: isGiftBadge,
            isTargetMessageViewOnce: isTargetMessageViewOnce,
            isPoll: isPoll
        )
    }

    // MARK: NSSecureCoding

    public class var supportsSecureCoding: Bool { true }

    public required init?(coder: NSCoder) {
        var decodedAddress = coder.decodeObject(of: SignalServiceAddress.self, forKey: "authorAddress")
        if decodedAddress == nil {
            let phoneNumber = coder.decodeObject(of: NSString.self, forKey: "authorId") as String?
            decodedAddress = SignalServiceAddress.legacyAddress(serviceIdString: nil, phoneNumber: phoneNumber)
        }
        guard let authorAddress = decodedAddress else { return nil }
        self.authorAddress = authorAddress
        self.body = coder.decodeObject(of: NSString.self, forKey: "body") as String?
        self.bodyRanges = coder.decodeObject(of: MessageBodyRanges.self, forKey: "bodyRanges")
        self.bodySource = TSQuotedMessageContentSource(
            rawValue: (coder.decodeObject(of: NSNumber.self, forKey: "bodySource"))?.uintValue ?? 0
        ) ?? .unknown
        self.isGiftBadge = (coder.decodeObject(of: NSNumber.self, forKey: "isGiftBadge"))?.boolValue ?? false
        self.isPoll = (coder.decodeObject(of: NSNumber.self, forKey: "isPoll"))?.boolValue ?? false
        self.isTargetMessageViewOnce = (coder.decodeObject(of: NSNumber.self, forKey: "isTargetMessageViewOnce"))?.boolValue ?? false
        // OWSAttachmentInfo's NSObject/NSCoding conformance is not statically
        // provable in this file while its defining file is mid-cascade, so decode
        // untyped and cast dynamically (still correct once that file compiles).
        self.quotedAttachment = coder.decodeObject(forKey: "quotedAttachment") as? OWSAttachmentInfo
        self.timestamp = (coder.decodeObject(of: NSNumber.self, forKey: "timestamp"))?.uint64Value ?? 0
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(authorAddress, forKey: "authorAddress")
        if let body { coder.encode(body, forKey: "body") }
        if let bodyRanges { coder.encode(bodyRanges, forKey: "bodyRanges") }
        coder.encode(NSNumber(value: bodySource.rawValue), forKey: "bodySource")
        coder.encode(NSNumber(value: isGiftBadge), forKey: "isGiftBadge")
        coder.encode(NSNumber(value: isPoll), forKey: "isPoll")
        coder.encode(NSNumber(value: isTargetMessageViewOnce), forKey: "isTargetMessageViewOnce")
        if let quotedAttachment { coder.encode(quotedAttachment, forKey: "quotedAttachment") }
        coder.encode(NSNumber(value: timestamp), forKey: "timestamp")
    }

    // MARK: Equality

    public override var hash: Int {
        var result = 0
        result ^= authorAddress.hash
        result ^= (body as NSString?)?.hash ?? 0
        result ^= bodyRanges?.hash ?? 0
        result ^= Int(truncatingIfNeeded: bodySource.rawValue)
        result ^= isGiftBadge ? 1 : 0
        result ^= isPoll ? 1 : 0
        result ^= isTargetMessageViewOnce ? 1 : 0
        result ^= (quotedAttachment as? NSObject)?.hash ?? 0
        result ^= Int(truncatingIfNeeded: timestamp)
        return result
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TSQuotedMessage, type(of: other) == type(of: self) else {
            return false
        }
        func objectsEqual(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
            if lhs == nil, rhs == nil { return true }
            return lhs?.isEqual(rhs) ?? false
        }
        return objectsEqual(authorAddress, other.authorAddress)
            && body == other.body
            && objectsEqual(bodyRanges, other.bodyRanges)
            && bodySource == other.bodySource
            && isGiftBadge == other.isGiftBadge
            && isPoll == other.isPoll
            && isTargetMessageViewOnce == other.isTargetMessageViewOnce
            && objectsEqual(quotedAttachment as? NSObject, other.quotedAttachment as? NSObject)
            && timestamp == other.timestamp
    }

    // MARK: NSCopying

    public func copy(with zone: NSZone? = nil) -> Any {
        TSQuotedMessage(
            timestamp: timestamp,
            authorAddress: authorAddress,
            body: body,
            bodyRanges: bodyRanges,
            bodySource: bodySource,
            receivedQuotedAttachmentInfo: quotedAttachment,
            isGiftBadge: isGiftBadge,
            isTargetMessageViewOnce: isTargetMessageViewOnce,
            isPoll: isPoll
        )
    }

    // MARK: Attachments

    public func attachmentInfo() -> OWSAttachmentInfo? {
        quotedAttachment
    }
}
