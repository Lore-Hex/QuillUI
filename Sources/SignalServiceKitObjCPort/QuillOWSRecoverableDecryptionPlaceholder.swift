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

    // Builder initializer (OWSRecoverableDecryptionPlaceholder.m
    // initWithFailedEnvelopeTimestamp:sourceAci:untrustedGroupId:transaction:):
    // OWSMessageDecrypter inserts a placeholder for a resendable decryption
    // failure. A designated init? (this subclass declares its own designated init,
    // so it cannot delegate via self.init) that forwards to TSErrorMessage's
    // designated builder init.
    //
    // Divergence (Linux): the original prefers the GROUP thread when the sender is
    // a confirmed full member of untrustedGroupId, else falls back to the contact
    // thread. TSGroupThread.fetchWithGroupId has no Swift surface here yet, so this
    // port uses the contact-thread fallback unconditionally -- the placeholder is
    // still inserted (and is replaced by the recovered message later); group-thread
    // routing of the placeholder is deferred.
    public init?(
        failedEnvelopeTimestamp timestamp: UInt64,
        sourceAci: AciObjC,
        untrustedGroupId: Data?,
        transaction writeTx: DBWriteTransaction
    ) {
        _ = untrustedGroupId
        let sender = SignalServiceAddress(serviceIdObjC: sourceAci)
        guard let thread = TSContactThread.getWithContactAddress(sender, transaction: writeTx) else {
            return nil
        }
        let builder = TSErrorMessageBuilder(thread: thread, errorType: .decryptionFailure)
        builder.timestamp = timestamp
        builder.senderAddress = sender
        super.init(errorMessageWithBuilder: builder)
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
