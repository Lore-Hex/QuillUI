//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// OWSVerificationStateChangeMessage.h -- a TSInfoMessage subclass inserted when
// a contact's safety-number verification state changes (verified / no longer
// verified), so the conversation view can render "You marked X as verified".
//
// Both initializers are used by the compiled SignalServiceKit Swift: the SDS
// designated init (interaction deserializers) and the thread builder.
//
import Foundation

open class OWSVerificationStateChangeMessage: TSInfoMessage {

    public internal(set) var recipientAddress: SignalServiceAddress
    public internal(set) var verificationState: OWSVerificationState
    public internal(set) var isLocalChange: Bool

    /// Whether this message reports the user as verified.
    public func isVerified() -> Bool {
        verificationState == .verified
    }

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSVerificationStateChangeMessage.")
    }

    @available(*, unavailable, message: "OWSVerificationStateChangeMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for OWSVerificationStateChangeMessage.")
    }

    // MARK: Builder (thread)

    public init(thread: TSThread,
                timestamp: UInt64,
                recipientAddress: SignalServiceAddress,
                verificationState: OWSVerificationState,
                isLocalChange: Bool) {
        self.recipientAddress = recipientAddress
        self.verificationState = verificationState
        self.isLocalChange = isLocalChange
        super.init(thread: thread,
                   timestamp: timestamp,
                   serverGuid: nil,
                   messageType: .verificationStateChange,
                   expireTimerVersion: nil,
                   expiresInSeconds: 0,
                   infoMessageUserInfo: nil)
    }

    // MARK: SDS designated initializer

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
                customMessage: String?,
                infoMessageUserInfo: [InfoMessageUserInfoKey: AnyObject]?,
                messageType: TSInfoMessageType,
                read: Bool,
                serverGuid: String?,
                unregisteredAddress: SignalServiceAddress?,
                isLocalChange: Bool,
                recipientAddress: SignalServiceAddress,
                verificationState: OWSVerificationState) {
        self.recipientAddress = recipientAddress
        self.verificationState = verificationState
        self.isLocalChange = isLocalChange
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
                   customMessage: customMessage,
                   infoMessageUserInfo: infoMessageUserInfo,
                   messageType: messageType,
                   read: read,
                   serverGuid: serverGuid,
                   unregisteredAddress: unregisteredAddress)
    }
}
