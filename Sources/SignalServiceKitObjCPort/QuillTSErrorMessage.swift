//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful pass-1 Swift port of Messages/Interactions/TSErrorMessage.m as
// open class TSErrorMessage: TSMessage, OWSReadTracking, OWSPreviewText.
//
// Pass-1 deferrals (noted): previewText returns a generic string (the upstream
// switch needs OWSLocalizedString + the safety-number-change description +
// the contact manager); markAsRead sets `read` directly (skips the
// anyUpdateErrorMessage DB write); error messages are SDS-tabled (not blob
// archived), so initWithCoder is unavailable upstream and not provided here.
//
import Foundation

open class TSErrorMessage: TSMessage, OWSReadTracking, OWSPreviewText {

    public internal(set) var errorType: TSErrorMessageType
    public internal(set) var read: Bool
    public internal(set) var recipientAddress: SignalServiceAddress?
    public internal(set) var sender: SignalServiceAddress?
    public internal(set) var wasIdentityVerified: Bool

    /// OWSReadTracking (ObjC property `read`, getter `wasRead`).
    public var wasRead: Bool { read }

    // MARK: Initializers

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSErrorMessage.")
    }

    @available(*, unavailable, message: "TSErrorMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for TSErrorMessage.")
    }

    public init(errorMessageWithBuilder errorMessageBuilder: TSErrorMessageBuilder) {
        self.errorType = errorMessageBuilder.errorType
        self.read = false
        self.recipientAddress = errorMessageBuilder.recipientAddress
        self.sender = errorMessageBuilder.senderAddress
        self.wasIdentityVerified = errorMessageBuilder.wasIdentityVerified
        super.init(messageWithBuilder: errorMessageBuilder)
        if isDynamicInteraction {
            self.read = true
        }
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
                wasIdentityVerified: Bool) {
        self.errorType = errorType
        self.read = read
        self.recipientAddress = recipientAddress
        self.sender = sender
        self.wasIdentityVerified = wasIdentityVerified
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

    open override var interactionType: OWSInteractionType { .error }

    public func previewText(transaction: DBReadTransaction) -> String {
        // PASS 1: localized per-errorType strings + safety-number description deferred.
        "Error"
    }

    // MARK: OWSReadTracking

    public func markAsRead(at readTimestamp: UInt64,
                           thread: TSThread,
                           circumstance: OWSReceiptCircumstance,
                           shouldClearNotifications: Bool,
                           transaction: DBWriteTransaction) {
        if read { return }
        // PASS 1: set directly; the anyUpdateErrorMessage DB write is deferred.
        // We never send read receipts for error messages, so circumstance is ignored.
        read = true
    }

    // MARK: Equality

    open override var hash: Int {
        var result = super.hash
        result ^= Int(truncatingIfNeeded: errorType.rawValue)
        result ^= read ? 1 : 0
        result ^= recipientAddress?.hash ?? 0
        result ^= sender?.hash ?? 0
        result ^= wasIdentityVerified ? 1 : 0
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let other = object as? TSErrorMessage else {
            return false
        }
        func objectsEqual(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
            if lhs == nil, rhs == nil { return true }
            return lhs?.isEqual(rhs) ?? false
        }
        return errorType == other.errorType
            && read == other.read
            && objectsEqual(recipientAddress, other.recipientAddress)
            && objectsEqual(sender, other.sender)
            && wasIdentityVerified == other.wasIdentityVerified
    }
}
