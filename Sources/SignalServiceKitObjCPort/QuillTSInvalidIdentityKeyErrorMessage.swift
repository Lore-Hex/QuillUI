//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// The TSInvalidIdentityKey* error-message hierarchy (Messages/InvalidKeyMessages):
//   TSInvalidIdentityKeyErrorMessage : TSErrorMessage          (abstract base)
//     TSInvalidIdentityKeySendingErrorMessage   (DEPRECATED mid-2017)
//     TSInvalidIdentityKeyReceivingErrorMessage (DEPRECATED mid-2017)
//
// New instances are no longer created, but historical rows still deserialize, so
// the classes must exist. Each is only constructed by the SDS deserializers via
// its grdbId designated initializer. The base adds no columns (its init is
// identical to TSErrorMessage's and overrides it); the two subclasses add a
// couple of legacy columns.
//
import Foundation

// MARK: - TSInvalidIdentityKeyErrorMessage (base)

open class TSInvalidIdentityKeyErrorMessage: TSErrorMessage {

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSInvalidIdentityKeyErrorMessage.")
    }

    @available(*, unavailable, message: "TSInvalidIdentityKeyErrorMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for TSInvalidIdentityKeyErrorMessage.")
    }

    // Identical signature to TSErrorMessage's SDS initializer, so it overrides.
    public override init(grdbId: Int64,
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
                         errorType: TSErrorMessageType,
                         read: Bool,
                         recipientAddress: SignalServiceAddress?,
                         sender: SignalServiceAddress?,
                         wasIdentityVerified: Bool) {
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
                   wasRemotelyDeleted: wasRemotelyDeleted,
                   errorType: errorType,
                   read: read,
                   recipientAddress: recipientAddress,
                   sender: sender,
                   wasIdentityVerified: wasIdentityVerified)
    }
}

// MARK: - TSInvalidIdentityKeySendingErrorMessage (DEPRECATED)

open class TSInvalidIdentityKeySendingErrorMessage: TSInvalidIdentityKeyErrorMessage {

    public internal(set) var messageId: String
    public internal(set) var preKeyBundle: Data

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSInvalidIdentityKeySendingErrorMessage.")
    }

    @available(*, unavailable, message: "TSInvalidIdentityKeySendingErrorMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for TSInvalidIdentityKeySendingErrorMessage.")
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
                errorType: TSErrorMessageType,
                read: Bool,
                recipientAddress: SignalServiceAddress?,
                sender: SignalServiceAddress?,
                wasIdentityVerified: Bool,
                messageId: String,
                preKeyBundle: Data) {
        self.messageId = messageId
        self.preKeyBundle = preKeyBundle
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
                   wasRemotelyDeleted: wasRemotelyDeleted,
                   errorType: errorType,
                   read: read,
                   recipientAddress: recipientAddress,
                   sender: sender,
                   wasIdentityVerified: wasIdentityVerified)
    }
}

// MARK: - TSInvalidIdentityKeyReceivingErrorMessage (DEPRECATED)

open class TSInvalidIdentityKeyReceivingErrorMessage: TSInvalidIdentityKeyErrorMessage {

    public internal(set) var authorId: String
    public internal(set) var envelopeData: Data?

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSInvalidIdentityKeyReceivingErrorMessage.")
    }

    @available(*, unavailable, message: "TSInvalidIdentityKeyReceivingErrorMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for TSInvalidIdentityKeyReceivingErrorMessage.")
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
                errorType: TSErrorMessageType,
                read: Bool,
                recipientAddress: SignalServiceAddress?,
                sender: SignalServiceAddress?,
                wasIdentityVerified: Bool,
                authorId: String,
                envelopeData: Data?) {
        self.authorId = authorId
        self.envelopeData = envelopeData
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
                   wasRemotelyDeleted: wasRemotelyDeleted,
                   errorType: errorType,
                   read: read,
                   recipientAddress: recipientAddress,
                   sender: sender,
                   wasIdentityVerified: wasIdentityVerified)
    }
}
