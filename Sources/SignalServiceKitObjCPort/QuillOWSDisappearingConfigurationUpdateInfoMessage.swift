//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// OWSDisappearingConfigurationUpdateInfoMessage.h -- a TSInfoMessage subclass
// inserted into a (historically contact) thread when the disappearing-messages
// timer is changed. It stores the new timer configuration so the conversation
// view can render "X set disappearing messages to N".
//
// Two initializers are used by the compiled SignalServiceKit Swift:
//  - the SDS designated init (grdbId:...), used by the interaction deserializers
//    -- it adds four columns to TSInfoMessage's init and forwards the rest;
//  - the contact-thread builder (used by ThreadUtil / GroupManager / Backups),
//    which creates a fresh `.typeDisappearingMessagesUpdate` info message.
//
import Foundation

open class OWSDisappearingConfigurationUpdateInfoMessage: TSInfoMessage {

    public internal(set) var configurationDurationSeconds: UInt32
    public internal(set) var configurationIsEnabled: Bool
    public internal(set) var createdByRemoteName: String?
    public internal(set) var createdInExistingGroup: Bool

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSDisappearingConfigurationUpdateInfoMessage.")
    }

    @available(*, unavailable, message: "OWSDisappearingConfigurationUpdateInfoMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for OWSDisappearingConfigurationUpdateInfoMessage.")
    }

    // MARK: Builder (contact thread)

    public init(contactThread: TSContactThread,
                timestamp: UInt64,
                isConfigurationEnabled: Bool,
                configurationDurationSeconds: UInt32,
                createdByRemoteName: String?) {
        self.configurationDurationSeconds = configurationDurationSeconds
        self.configurationIsEnabled = isConfigurationEnabled
        self.createdByRemoteName = createdByRemoteName
        self.createdInExistingGroup = false
        super.init(thread: contactThread,
                   timestamp: timestamp,
                   serverGuid: nil,
                   messageType: .typeDisappearingMessagesUpdate,
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
                configurationDurationSeconds: UInt32,
                configurationIsEnabled: Bool,
                createdByRemoteName: String?,
                createdInExistingGroup: Bool) {
        self.configurationDurationSeconds = configurationDurationSeconds
        self.configurationIsEnabled = configurationIsEnabled
        self.createdByRemoteName = createdByRemoteName
        self.createdInExistingGroup = createdInExistingGroup
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
