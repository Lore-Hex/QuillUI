//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful pass-1 Swift port of Messages/Interactions/TSIncomingMessage.m as
// open class TSIncomingMessage: TSMessage, OWSReadTracking.
//
// Pass-1 deferrals (noted): markAsRead/markAsViewed set the flags (and the
// read-edit-state transition) directly but skip the anyUpdateIncomingMessage DB
// write, expiration start, receipt-manager and notification side effects; error
// messages are SDS-tabled so initWithCoder is unavailable.
//
import Foundation

open class TSIncomingMessage: TSMessage, OWSReadTracking {

    public internal(set) var authorPhoneNumber: String?
    public internal(set) var authorUUID: String?

    /// DO NOT USE — kept only for SDS table backwards compatibility.
    public internal(set) var deprecated_sourceDeviceId: NSNumber?

    public internal(set) var read: Bool
    public internal(set) var viewed: Bool
    public internal(set) var serverTimestamp: NSNumber?
    public internal(set) var serverDeliveryTimestamp: UInt64
    public internal(set) var serverGuid: String?
    public internal(set) var wasReceivedByUD: Bool

    // MARK: Computed

    public var authorAddress: SignalServiceAddress {
        SignalServiceAddress.legacyAddress(serviceIdString: authorUUID, phoneNumber: authorPhoneNumber)
    }

    /// OWSReadTracking (ObjC property `read`, getter `wasRead`).
    public var wasRead: Bool { read }
    /// ObjC property `viewed`, getter `wasViewed`.
    public var wasViewed: Bool { viewed }

    // MARK: Initializers

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSIncomingMessage.")
    }

    @available(*, unavailable, message: "TSIncomingMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for TSIncomingMessage.")
    }

    public init(incomingMessageWithBuilder incomingMessageBuilder: TSIncomingMessageBuilder) {
        self.authorUUID = incomingMessageBuilder.authorAciObjC?.serviceIdUppercaseString
        self.authorPhoneNumber = incomingMessageBuilder.authorE164ObjC?.stringValue
        self.deprecated_sourceDeviceId = nil
        self.read = incomingMessageBuilder.read
        self.viewed = false
        let serverTimestamp = incomingMessageBuilder.serverTimestamp
        self.serverTimestamp = serverTimestamp > 0 ? NSNumber(value: serverTimestamp) : nil
        self.serverDeliveryTimestamp = incomingMessageBuilder.serverDeliveryTimestamp
        self.serverGuid = incomingMessageBuilder.serverGuid
        self.wasReceivedByUD = incomingMessageBuilder.wasReceivedByUD
        super.init(messageWithBuilder: incomingMessageBuilder)
    }

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
                wasRemotelyDeleted: Bool,
                authorPhoneNumber: String?,
                authorUUID: String?,
                deprecated_sourceDeviceId: NSNumber?,
                read: Bool,
                serverDeliveryTimestamp: UInt64,
                serverGuid: String?,
                serverTimestamp: NSNumber?,
                viewed: Bool,
                wasReceivedByUD: Bool) {
        self.authorPhoneNumber = authorPhoneNumber
        self.authorUUID = authorUUID
        self.deprecated_sourceDeviceId = deprecated_sourceDeviceId
        self.read = read
        self.viewed = viewed
        self.serverTimestamp = serverTimestamp
        self.serverDeliveryTimestamp = serverDeliveryTimestamp
        self.serverGuid = serverGuid
        self.wasReceivedByUD = wasReceivedByUD
        super.init(grdbId: grdbId,
                   uniqueId: uniqueId,
                   receivedAtTimestamp: receivedAtTimestamp,
                   sortId: sortId,
                   timestamp: timestamp,
                   uniqueThreadId: uniqueThreadId,
                   body: body,
                   bodyRanges: bodyRanges,
                   contactShare: contactShare,
                   deprecated_attachmentIds: deprecated_attachmentIds,
                   editState: editState,
                   expireStartedAt: expireStartedAt,
                   expireTimerVersion: expireTimerVersion,
                   expiresAt: expiresAt,
                   expiresInSeconds: expiresInSeconds,
                   giftBadge: giftBadge,
                   isGroupStoryReply: isGroupStoryReply,
                   isPoll: isPoll,
                   isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup,
                   isViewOnceComplete: isViewOnceComplete,
                   isViewOnceMessage: isViewOnceMessage,
                   linkPreview: linkPreview,
                   messageSticker: messageSticker,
                   quotedMessage: quotedMessage,
                   storedShouldStartExpireTimer: storedShouldStartExpireTimer,
                   storyAuthorUuidString: storyAuthorUuidString,
                   storyReactionEmoji: storyReactionEmoji,
                   storyTimestamp: storyTimestamp,
                   wasRemotelyDeleted: wasRemotelyDeleted)
    }

    // MARK: Overrides

    open override var interactionType: OWSInteractionType { .incomingMessage }

    // MARK: OWSReadTracking

    public func markAsRead(atTimestamp readTimestamp: UInt64,
                           thread: TSThread,
                           circumstance: OWSReceiptCircumstance,
                           shouldClearNotifications: Bool,
                           transaction: DBWriteTransaction) {
        if read { return }
        // PASS 1: set directly; DB write / expiration / receipts / notifications deferred.
        read = true
        if editState == .latestRevisionUnread {
            editState = .latestRevisionRead
        }
    }

    public func markAsViewed(at viewedTimestamp: UInt64,
                             thread: TSThread,
                             circumstance: OWSReceiptCircumstance,
                             transaction: DBWriteTransaction) {
        if viewed { return }
        // PASS 1: set directly; DB write / receipt side effects deferred.
        viewed = true
    }

    // MARK: Equality

    open override var hash: Int {
        var result = super.hash
        result ^= (authorPhoneNumber as NSString?)?.hash ?? 0
        result ^= (authorUUID as NSString?)?.hash ?? 0
        result ^= deprecated_sourceDeviceId?.hash ?? 0
        result ^= read ? 1 : 0
        result ^= Int(truncatingIfNeeded: serverDeliveryTimestamp)
        result ^= (serverGuid as NSString?)?.hash ?? 0
        result ^= serverTimestamp?.hash ?? 0
        result ^= viewed ? 1 : 0
        result ^= wasReceivedByUD ? 1 : 0
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let other = object as? TSIncomingMessage else {
            return false
        }
        func objectsEqual(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
            if lhs == nil, rhs == nil { return true }
            return lhs?.isEqual(rhs) ?? false
        }
        return objectsEqual(authorPhoneNumber as NSString?, other.authorPhoneNumber as NSString?)
            && objectsEqual(authorUUID as NSString?, other.authorUUID as NSString?)
            && objectsEqual(deprecated_sourceDeviceId, other.deprecated_sourceDeviceId)
            && read == other.read
            && serverDeliveryTimestamp == other.serverDeliveryTimestamp
            && objectsEqual(serverGuid as NSString?, other.serverGuid as NSString?)
            && objectsEqual(serverTimestamp, other.serverTimestamp)
            && viewed == other.viewed
            && wasReceivedByUD == other.wasReceivedByUD
    }
}
