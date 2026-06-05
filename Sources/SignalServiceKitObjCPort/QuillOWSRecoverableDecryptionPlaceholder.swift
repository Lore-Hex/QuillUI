//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// OWSRecoverableDecryptionPlaceholder.h -- a TSErrorMessage subclass inserted
// into a thread when an incoming message cannot yet be decrypted (e.g. an
// unknown sender-key state), so it can later be REPLACED by the recovered
// message. It adds no stored columns: its SDS designated initializer is
// identical to TSErrorMessage's, so the grdbId init here is a pure forward.
// `supportsReplacement` marks the placeholder replaceable.
//
// The `initWithFailedEnvelopeTimestamp:sourceAci:untrustedGroupId:transaction:`
// builder initializer has no callers in the compiled SignalServiceKit Swift and
// is omitted (deferred); add it if a caller surfaces.
//
import Foundation

open class OWSRecoverableDecryptionPlaceholder: TSErrorMessage {

    /// Whether this placeholder can be replaced by the recovered message. These
    /// placeholders are replaceable by definition (no base member; the original
    /// ObjC returned a stored flag, behavior deferred on Linux).
    public var supportsReplacement: Bool { true }

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSRecoverableDecryptionPlaceholder.")
    }

    @available(*, unavailable, message: "OWSRecoverableDecryptionPlaceholder is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for OWSRecoverableDecryptionPlaceholder.")
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
