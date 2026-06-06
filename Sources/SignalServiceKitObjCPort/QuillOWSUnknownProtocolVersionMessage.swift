//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// OWSUnknownProtocolVersionMessage.h -- a TSInfoMessage subclass inserted when a
// received message requires a newer protocol version than this client supports,
// so the conversation view can prompt the user to upgrade.
//
// Both initializers are used by the compiled SignalServiceKit Swift: the SDS
// designated init (interaction deserializers) and the thread builder.
//
import Foundation

open class OWSUnknownProtocolVersionMessage: TSInfoMessage {

    public internal(set) var protocolVersion: UInt
    /// If nil, the invalid message was sent by a linked device.
    public internal(set) var sender: SignalServiceAddress?

    /// Whether the required protocol version is still beyond what this client
    /// understands (the user may have upgraded since this message was inserted).
    public var isProtocolVersionUnknown: Bool {
        protocolVersion > UInt(SSKProtos.currentProtocolVersion)
    }

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSUnknownProtocolVersionMessage.")
    }

    @available(*, unavailable, message: "OWSUnknownProtocolVersionMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for OWSUnknownProtocolVersionMessage.")
    }

    // MARK: Builder (thread)

    public init(thread: TSThread,
                timestamp: UInt64,
                sender: SignalServiceAddress?,
                protocolVersion: UInt) {
        self.protocolVersion = protocolVersion
        self.sender = sender
        super.init(thread: thread,
                   timestamp: timestamp,
                   serverGuid: nil,
                   messageType: .unknownProtocolVersion,
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
                infoMessageUserInfo: [InfoMessageUserInfoKey: Any]?,
                messageType: TSInfoMessageType,
                read: Bool,
                serverGuid: String?,
                unregisteredAddress: SignalServiceAddress?,
                protocolVersion: UInt,
                sender: SignalServiceAddress?) {
        self.protocolVersion = protocolVersion
        self.sender = sender
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
