//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful Swift port of Messages/Interactions/TSMessage.{h,m} (ObjC, excluded
// on Linux) — the abstract message base. ~83 files descend from it
// (TSIncomingMessage / TSOutgoingMessage / TSInfoMessage / TSErrorMessage / ...);
// their generated `*+SDS.swift` deserializers call this class's 29-parameter SDS
// designated initializer via `super.init(grdbId:…)`, so it must exist same-module.
//
// PASS 1 scope (this file): the full stored-property surface, the three
// designated initializers (builder / SDS / NSCoding), encode/decode, exact-class
// hash + isEqual, and the expiration/story computed accessors. Deliberately
// deferred to a later pass (no compile impact — verified 0 Swift callers / not a
// contract requirement):
//   * the `anyWill/DidInsert/Update` overrides (mentions insert, expiration
//     start, story touch) — inherits TSInteraction's for now;
//   * the `updateWith…` mutators (0 Swift callers);
//   * `storyAuthorAci` returns nil (AciObjC has no string initializer in Swift;
//     parse via Aci in a later pass) — `isStoryReply` is unaffected;
//   * `body` is a plain stored value (the upstream getter applies
//     `filterStringForDisplay` unless `isPoll`) — restore the display filter later.
//
// Mid-cascade decouple: several stored-property types (OWSContact, OWSLinkPreview,
// MessageSticker, OWSGiftBadge, TSQuotedMessage) live in files that are themselves
// mid-cascade, so their NSObject/NSCoding conformance is not statically provable
// here. They are fine as property/parameter types, but decoded untyped and
// compared via dynamic NSObject casts.
//
import Foundation

private let owsMessageSchemaVersion: UInt = 4

open class TSMessage: TSInteraction {

    public internal(set) var body: String?
    public internal(set) var bodyRanges: MessageBodyRanges?
    public internal(set) var contactShare: OWSContact?
    public internal(set) var deprecated_attachmentIds: [String]?
    public internal(set) var editState: TSEditState
    public internal(set) var expireStartedAt: UInt64
    public internal(set) var expireTimerVersion: NSNumber?
    public internal(set) var expiresAt: UInt64
    public internal(set) var expiresInSeconds: UInt32
    public internal(set) var giftBadge: OWSGiftBadge?
    public internal(set) var isGroupStoryReply: Bool
    public internal(set) var isPoll: Bool
    public internal(set) var isSmsMessageRestoredFromBackup: Bool
    public internal(set) var isViewOnceComplete: Bool
    public internal(set) var isViewOnceMessage: Bool
    public internal(set) var linkPreview: OWSLinkPreview?
    public internal(set) var messageSticker: MessageSticker?
    public internal(set) var quotedMessage: TSQuotedMessage?
    public internal(set) var storedShouldStartExpireTimer: Bool
    public internal(set) var storyAuthorUuidString: String?
    public internal(set) var storyReactionEmoji: String?
    public internal(set) var storyTimestamp: NSNumber?
    public internal(set) var wasRemotelyDeleted: Bool

    /// Schema version last used to serialize this model (NSCoding migrations).
    internal var schemaVersion: UInt

    // MARK: Computed

    public var hasPerConversationExpiration: Bool { expiresInSeconds > 0 }

    public var hasPerConversationExpirationStarted: Bool {
        expireStartedAt > 0 && expiresInSeconds > 0
    }

    public func shouldStartExpireTimer() -> Bool {
        if hasPerConversationExpirationStarted { return true }
        return hasPerConversationExpiration
    }

    /// PASS 1: AciObjC has no string initializer in Swift; returns nil for now.
    public var storyAuthorAci: AciObjC? { nil }

    public var isStoryReply: Bool { storyAuthorUuidString != nil }

    private func updateExpiresAt() {
        if hasPerConversationExpirationStarted {
            expiresAt = expireStartedAt + UInt64(expiresInSeconds) * 1000
        } else {
            expiresAt = 0
        }
    }

    // MARK: Initializers

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSMessage.")
    }

    public init(messageWithBuilder messageBuilder: TSMessageBuilder) {
        self.schemaVersion = owsMessageSchemaVersion
        if let messageBody = messageBuilder.messageBody, !messageBody.isEmpty {
            self.body = messageBody
            self.bodyRanges = messageBuilder.bodyRanges
        } else {
            self.body = nil
            self.bodyRanges = nil
        }
        self.deprecated_attachmentIds = nil
        self.editState = messageBuilder.editState
        self.expiresInSeconds = messageBuilder.expiresInSeconds
        self.expireStartedAt = messageBuilder.expireStartedAt
        self.expireTimerVersion = messageBuilder.expireTimerVersion
        self.expiresAt = 0
        self.isSmsMessageRestoredFromBackup = messageBuilder.isSmsMessageRestoredFromBackup
        self.isViewOnceMessage = messageBuilder.isViewOnceMessage
        self.isViewOnceComplete = messageBuilder.isViewOnceComplete
        self.wasRemotelyDeleted = messageBuilder.wasRemotelyDeleted
        self.storyTimestamp = messageBuilder.storyTimestamp
        self.storyAuthorUuidString = messageBuilder.storyAuthorAci?.serviceIdUppercaseString
        self.storyReactionEmoji = messageBuilder.storyReactionEmoji
        self.isGroupStoryReply = messageBuilder.isGroupStoryReply
        self.quotedMessage = messageBuilder.quotedMessage
        self.contactShare = messageBuilder.contactShare
        self.linkPreview = messageBuilder.linkPreview
        self.messageSticker = messageBuilder.messageSticker
        self.giftBadge = messageBuilder.giftBadge
        self.isPoll = messageBuilder.isPoll
        self.storedShouldStartExpireTimer = false
        super.init(timestamp: messageBuilder.timestamp,
                   receivedAtTimestamp: messageBuilder.receivedAtTimestamp,
                   thread: messageBuilder.thread)
        updateExpiresAt()
    }

    // MARK: Generated SDS initializer

    public init(grdbId: Int64,
                uniqueId: String,
                receivedAtTimestamp: UInt64,
                sortId: UInt64,
                timestamp: UInt64,
                uniqueThreadId: String,
                body: String?,
                bodyRanges: MessageBodyRanges?,
                contactShare: OWSContact?,
                deprecated_attachmentIds: [String]?,
                editState: TSEditState,
                expireStartedAt: UInt64,
                expireTimerVersion: NSNumber?,
                expiresAt: UInt64,
                expiresInSeconds: UInt32,
                giftBadge: OWSGiftBadge?,
                isGroupStoryReply: Bool,
                isPoll: Bool,
                isSmsMessageRestoredFromBackup: Bool,
                isViewOnceComplete: Bool,
                isViewOnceMessage: Bool,
                linkPreview: OWSLinkPreview?,
                messageSticker: MessageSticker?,
                quotedMessage: TSQuotedMessage?,
                storedShouldStartExpireTimer: Bool,
                storyAuthorUuidString: String?,
                storyReactionEmoji: String?,
                storyTimestamp: NSNumber?,
                wasRemotelyDeleted: Bool) {
        self.schemaVersion = owsMessageSchemaVersion
        self.body = body
        self.bodyRanges = bodyRanges
        self.contactShare = contactShare
        self.deprecated_attachmentIds = deprecated_attachmentIds
        self.editState = editState
        self.expireStartedAt = expireStartedAt
        self.expireTimerVersion = expireTimerVersion
        self.expiresAt = expiresAt
        self.expiresInSeconds = expiresInSeconds
        self.giftBadge = giftBadge
        self.isGroupStoryReply = isGroupStoryReply
        self.isPoll = isPoll
        self.isSmsMessageRestoredFromBackup = isSmsMessageRestoredFromBackup
        self.isViewOnceComplete = isViewOnceComplete
        self.isViewOnceMessage = isViewOnceMessage
        self.linkPreview = linkPreview
        self.messageSticker = messageSticker
        self.quotedMessage = quotedMessage
        self.storedShouldStartExpireTimer = storedShouldStartExpireTimer
        self.storyAuthorUuidString = storyAuthorUuidString
        self.storyReactionEmoji = storyReactionEmoji
        self.storyTimestamp = storyTimestamp
        self.wasRemotelyDeleted = wasRemotelyDeleted
        super.init(grdbId: grdbId,
                   uniqueId: uniqueId,
                   receivedAtTimestamp: receivedAtTimestamp,
                   sortId: sortId,
                   timestamp: timestamp,
                   uniqueThreadId: uniqueThreadId)
        updateExpiresAt()
    }

    // MARK: NSCoding

    public required init?(coder: NSCoder) {
        self.body = coder.decodeObject(forKey: "body") as? String
        self.bodyRanges = coder.decodeObject(forKey: "bodyRanges") as? MessageBodyRanges
        self.contactShare = coder.decodeObject(forKey: "contactShare") as? OWSContact
        self.deprecated_attachmentIds = coder.decodeObject(forKey: "deprecated_attachmentIds") as? [String]
        self.editState = TSEditState(rawValue: (coder.decodeObject(of: NSNumber.self, forKey: "editState"))?.intValue ?? 0) ?? .none
        self.expireStartedAt = (coder.decodeObject(of: NSNumber.self, forKey: "expireStartedAt"))?.uint64Value ?? 0
        self.expireTimerVersion = coder.decodeObject(of: NSNumber.self, forKey: "expireTimerVersion")
        self.expiresAt = (coder.decodeObject(of: NSNumber.self, forKey: "expiresAt"))?.uint64Value ?? 0
        self.expiresInSeconds = (coder.decodeObject(of: NSNumber.self, forKey: "expiresInSeconds"))?.uint32Value ?? 0
        self.giftBadge = coder.decodeObject(forKey: "giftBadge") as? OWSGiftBadge
        self.isGroupStoryReply = (coder.decodeObject(of: NSNumber.self, forKey: "isGroupStoryReply"))?.boolValue ?? false
        self.isPoll = (coder.decodeObject(of: NSNumber.self, forKey: "isPoll"))?.boolValue ?? false
        self.isSmsMessageRestoredFromBackup = (coder.decodeObject(of: NSNumber.self, forKey: "isSmsMessageRestoredFromBackup"))?.boolValue ?? false
        self.isViewOnceComplete = (coder.decodeObject(of: NSNumber.self, forKey: "isViewOnceComplete"))?.boolValue ?? false
        self.isViewOnceMessage = (coder.decodeObject(of: NSNumber.self, forKey: "isViewOnceMessage"))?.boolValue ?? false
        self.linkPreview = coder.decodeObject(forKey: "linkPreview") as? OWSLinkPreview
        self.messageSticker = coder.decodeObject(forKey: "messageSticker") as? MessageSticker
        self.quotedMessage = coder.decodeObject(forKey: "quotedMessage") as? TSQuotedMessage
        let decodedSchemaVersion = (coder.decodeObject(of: NSNumber.self, forKey: "schemaVersion"))?.uintValue ?? 0
        self.schemaVersion = decodedSchemaVersion
        self.storedShouldStartExpireTimer = (coder.decodeObject(of: NSNumber.self, forKey: "storedShouldStartExpireTimer"))?.boolValue ?? false
        self.storyAuthorUuidString = coder.decodeObject(of: NSString.self, forKey: "storyAuthorUuidString") as String?
        self.storyReactionEmoji = coder.decodeObject(of: NSString.self, forKey: "storyReactionEmoji") as String?
        self.storyTimestamp = coder.decodeObject(of: NSNumber.self, forKey: "storyTimestamp")
        self.wasRemotelyDeleted = (coder.decodeObject(of: NSNumber.self, forKey: "wasRemotelyDeleted"))?.boolValue ?? false

        // Schema migrations (legacy "attachments"-array branch dropped on Linux).
        if decodedSchemaVersion < 3 {
            self.expiresInSeconds = 0
            self.expireStartedAt = 0
            self.expiresAt = 0
        }
        if decodedSchemaVersion < 4, (deprecated_attachmentIds?.count ?? 0) > 0 {
            self.body = nil
        }
        self.schemaVersion = owsMessageSchemaVersion

        // Upgrade legacy per-message expiration into view-once.
        if let perMessageDuration = coder.decodeObject(of: NSNumber.self, forKey: "perMessageExpirationDurationSeconds"),
           perMessageDuration.uintValue > 0 {
            self.isViewOnceMessage = true
        }
        if let perMessageExpired = coder.decodeObject(of: NSNumber.self, forKey: "perMessageExpirationHasExpired"),
           perMessageExpired.boolValue {
            self.isViewOnceComplete = true
        }

        super.init(coder: coder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let body { coder.encode(body, forKey: "body") }
        if let bodyRanges { coder.encode(bodyRanges, forKey: "bodyRanges") }
        if let contactShare { coder.encode(contactShare, forKey: "contactShare") }
        if let deprecated_attachmentIds { coder.encode(deprecated_attachmentIds, forKey: "deprecated_attachmentIds") }
        coder.encode(NSNumber(value: editState.rawValue), forKey: "editState")
        coder.encode(NSNumber(value: expireStartedAt), forKey: "expireStartedAt")
        if let expireTimerVersion { coder.encode(expireTimerVersion, forKey: "expireTimerVersion") }
        coder.encode(NSNumber(value: expiresAt), forKey: "expiresAt")
        coder.encode(NSNumber(value: expiresInSeconds), forKey: "expiresInSeconds")
        if let giftBadge { coder.encode(giftBadge, forKey: "giftBadge") }
        coder.encode(NSNumber(value: isGroupStoryReply), forKey: "isGroupStoryReply")
        coder.encode(NSNumber(value: isPoll), forKey: "isPoll")
        coder.encode(NSNumber(value: isSmsMessageRestoredFromBackup), forKey: "isSmsMessageRestoredFromBackup")
        coder.encode(NSNumber(value: isViewOnceComplete), forKey: "isViewOnceComplete")
        coder.encode(NSNumber(value: isViewOnceMessage), forKey: "isViewOnceMessage")
        if let linkPreview { coder.encode(linkPreview, forKey: "linkPreview") }
        if let messageSticker { coder.encode(messageSticker, forKey: "messageSticker") }
        if let quotedMessage { coder.encode(quotedMessage, forKey: "quotedMessage") }
        coder.encode(NSNumber(value: schemaVersion), forKey: "schemaVersion")
        coder.encode(NSNumber(value: storedShouldStartExpireTimer), forKey: "storedShouldStartExpireTimer")
        if let storyAuthorUuidString { coder.encode(storyAuthorUuidString, forKey: "storyAuthorUuidString") }
        if let storyReactionEmoji { coder.encode(storyReactionEmoji, forKey: "storyReactionEmoji") }
        if let storyTimestamp { coder.encode(storyTimestamp, forKey: "storyTimestamp") }
        coder.encode(NSNumber(value: wasRemotelyDeleted), forKey: "wasRemotelyDeleted")
    }

    // MARK: Equality

    open override var hash: Int {
        var result = super.hash
        result ^= (body as NSString?)?.hash ?? 0
        result ^= (bodyRanges as? NSObject)?.hash ?? 0
        result ^= (contactShare as? NSObject)?.hash ?? 0
        result ^= (deprecated_attachmentIds as NSArray?)?.hash ?? 0
        result ^= Int(truncatingIfNeeded: editState.rawValue)
        result ^= Int(truncatingIfNeeded: expireStartedAt)
        result ^= expireTimerVersion?.hash ?? 0
        result ^= Int(truncatingIfNeeded: expiresAt)
        result ^= Int(truncatingIfNeeded: expiresInSeconds)
        result ^= (giftBadge as? NSObject)?.hash ?? 0
        result ^= isGroupStoryReply ? 1 : 0
        result ^= isPoll ? 1 : 0
        result ^= isSmsMessageRestoredFromBackup ? 1 : 0
        result ^= isViewOnceComplete ? 1 : 0
        result ^= isViewOnceMessage ? 1 : 0
        result ^= (linkPreview as? NSObject)?.hash ?? 0
        result ^= (messageSticker as? NSObject)?.hash ?? 0
        result ^= (quotedMessage as? NSObject)?.hash ?? 0
        result ^= Int(truncatingIfNeeded: schemaVersion)
        result ^= storedShouldStartExpireTimer ? 1 : 0
        result ^= (storyAuthorUuidString as NSString?)?.hash ?? 0
        result ^= (storyReactionEmoji as NSString?)?.hash ?? 0
        result ^= storyTimestamp?.hash ?? 0
        result ^= wasRemotelyDeleted ? 1 : 0
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let other = object as? TSMessage else {
            return false
        }
        func objectsEqual(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
            if lhs == nil, rhs == nil { return true }
            return lhs?.isEqual(rhs) ?? false
        }
        return body == other.body
            && objectsEqual(bodyRanges as? NSObject, other.bodyRanges as? NSObject)
            && objectsEqual(contactShare as? NSObject, other.contactShare as? NSObject)
            && (deprecated_attachmentIds ?? []) == (other.deprecated_attachmentIds ?? [])
            && editState == other.editState
            && expireStartedAt == other.expireStartedAt
            && objectsEqual(expireTimerVersion, other.expireTimerVersion)
            && expiresAt == other.expiresAt
            && expiresInSeconds == other.expiresInSeconds
            && objectsEqual(giftBadge as? NSObject, other.giftBadge as? NSObject)
            && isGroupStoryReply == other.isGroupStoryReply
            && isPoll == other.isPoll
            && isSmsMessageRestoredFromBackup == other.isSmsMessageRestoredFromBackup
            && isViewOnceComplete == other.isViewOnceComplete
            && isViewOnceMessage == other.isViewOnceMessage
            && objectsEqual(linkPreview as? NSObject, other.linkPreview as? NSObject)
            && objectsEqual(messageSticker as? NSObject, other.messageSticker as? NSObject)
            && objectsEqual(quotedMessage as? NSObject, other.quotedMessage as? NSObject)
            && storedShouldStartExpireTimer == other.storedShouldStartExpireTimer
            && storyAuthorUuidString == other.storyAuthorUuidString
            && storyReactionEmoji == other.storyReactionEmoji
            && objectsEqual(storyTimestamp, other.storyTimestamp)
            && wasRemotelyDeleted == other.wasRemotelyDeleted
    }

    // MARK: Attachment-update overloads (TSMessage.m, called during outgoing
    // prep + edit-revision attachment swaps)
    //
    // Upstream each anyUpdate-wraps the matching setter; on Linux these run at
    // message-prep time (pre-insert), so we set the stored prop directly. The
    // three `update(with:transaction:)` overloads resolve by argument type.

    open func update(with linkPreview: OWSLinkPreview, transaction: DBWriteTransaction) {
        self.linkPreview = linkPreview
    }

    open func update(with quotedMessage: TSQuotedMessage, transaction: DBWriteTransaction) {
        self.quotedMessage = quotedMessage
    }

    open func update(with messageSticker: MessageSticker, transaction: DBWriteTransaction) {
        self.messageSticker = messageSticker
    }

    open func update(withContactShare contactShare: OWSContact, transaction: DBWriteTransaction) {
        self.contactShare = contactShare
    }

    open func update(withIsPoll isPoll: Bool, transaction: DBWriteTransaction) {
        self.isPoll = isPoll
    }
}
