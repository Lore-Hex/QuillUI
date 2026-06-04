//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful pass-1 Swift port of Messages/Interactions/TSInfoMessage.m as
// open class TSInfoMessage: TSMessage, OWSReadTracking, plus the
// InfoMessageUserInfoKey NS_STRING_ENUM it declares.
//
// Pass-1 deferrals (noted): infoMessageUserInfoObjectClasses returns [] (the
// secure-unarchive allow-list is a runtime concern); markAsRead sets read
// directly; SDS-tabled so initWithCoder is unavailable.
//
import Foundation

// MARK: - InfoMessageUserInfoKey  (NS_STRING_ENUM in TSInfoMessage.h)

public struct InfoMessageUserInfoKey: RawRepresentable, Hashable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

extension InfoMessageUserInfoKey {
    public static let legacyGroupUpdateItems = InfoMessageUserInfoKey("InfoMessageUserInfoKeyUpdateMessages")
    public static let groupUpdateItems = InfoMessageUserInfoKey("InfoMessageUserInfoKeyUpdateMessagesV2")
    public static let oldGroupModel = InfoMessageUserInfoKey("InfoMessageUserInfoKeyOldGroupModel")
    public static let newGroupModel = InfoMessageUserInfoKey("InfoMessageUserInfoKeyNewGroupModel")
    public static let oldDisappearingMessageToken = InfoMessageUserInfoKey("InfoMessageUserInfoKeyOldDisappearingMessageToken")
    public static let newDisappearingMessageToken = InfoMessageUserInfoKey("InfoMessageUserInfoKeyNewDisappearingMessageToken")
    public static let groupUpdateSourceLegacyAddress = InfoMessageUserInfoKey("InfoMessageUserInfoKeyGroupUpdateSourceAddress")
    public static let legacyUpdaterKnownToBeLocalUser = InfoMessageUserInfoKey("InfoMessageUserInfoKeyUpdaterWasLocalUser")
    public static let profileChanges = InfoMessageUserInfoKey("InfoMessageUserInfoKeyProfileChanges")
    public static let changePhoneNumberAciString = InfoMessageUserInfoKey("InfoMessageUserInfoKeyChangePhoneNumberUuid")
    public static let changePhoneNumberOld = InfoMessageUserInfoKey("InfoMessageUserInfoKeyChangePhoneNumberOld")
    public static let changePhoneNumberNew = InfoMessageUserInfoKey("InfoMessageUserInfoKeyChangePhoneNumberNew")
    public static let paymentActivationRequestSenderAci = InfoMessageUserInfoKey("InfoMessageUserInfoKeyPaymentActivationRequestSenderAci")
    public static let paymentActivatedAci = InfoMessageUserInfoKey("InfoMessageUserInfoKeyPaymentActivatedAci")
    public static let threadMergePhoneNumber = InfoMessageUserInfoKey("InfoMessageUserInfoKeyThreadMergePhoneNumber")
    public static let sessionSwitchoverPhoneNumber = InfoMessageUserInfoKey("InfoMessageUserInfoKeySessionSwitchoverPhoneNumber")
    public static let phoneNumberDisplayNameBeforeLearningProfileName = InfoMessageUserInfoKey("InfoMessageUserInfoKeyPhoneNumberDisplayNameBeforeLearningProfileName")
    public static let usernameDisplayNameBeforeLearningProfileName = InfoMessageUserInfoKey("InfoMessageUserInfoKeyUsernameDisplayNameBeforeLearningProfileName")
    public static let endPoll = InfoMessageUserInfoKey("InfoMessageUserInfoKeyEndPoll")
    public static let pinnedMessage = InfoMessageUserInfoKey("InfoMessageUserInfoKeyPinnedMessage")
}

// MARK: - TSInfoMessage

open class TSInfoMessage: TSMessage, OWSReadTracking {

    public internal(set) var messageType: TSInfoMessageType
    public internal(set) var customMessage: String?
    public internal(set) var unregisteredAddress: SignalServiceAddress?
    public internal(set) var serverGuid: String?
    public internal(set) var read: Bool
    public var infoMessageUserInfo: [InfoMessageUserInfoKey: Any]?

    /// OWSReadTracking (ObjC property `read`, getter `wasRead`).
    public var wasRead: Bool { read }

    public class func infoMessageUserInfoObjectClasses() -> [AnyClass] {
        // PASS 1: the secure-unarchive allow-list is deferred (runtime concern).
        []
    }

    // MARK: Initializers

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSInfoMessage.")
    }

    @available(*, unavailable, message: "TSInfoMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for TSInfoMessage.")
    }

    public init(thread: TSThread,
                timestamp: UInt64,
                serverGuid: String?,
                messageType: TSInfoMessageType,
                expireTimerVersion: NSNumber?,
                expiresInSeconds: UInt32,
                infoMessageUserInfo: [InfoMessageUserInfoKey: Any]?) {
        self.serverGuid = serverGuid
        self.messageType = messageType
        self.infoMessageUserInfo = infoMessageUserInfo
        self.customMessage = nil
        self.unregisteredAddress = nil
        self.read = false
        let builder: TSMessageBuilder = timestamp > 0
            ? TSMessageBuilder.messageBuilder(thread: thread, timestamp: timestamp)
            : TSMessageBuilder.messageBuilder(thread: thread)
        if expiresInSeconds > 0, expireTimerVersion != nil {
            builder.expiresInSeconds = expiresInSeconds
            builder.expireTimerVersion = expireTimerVersion
        }
        super.init(messageWithBuilder: builder)
        if isDynamicInteraction {
            self.read = true
        }
        if messageType == .typeGroupQuit {
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
                customMessage: String?,
                infoMessageUserInfo: [InfoMessageUserInfoKey: AnyObject]?,
                messageType: TSInfoMessageType,
                read: Bool,
                serverGuid: String?,
                unregisteredAddress: SignalServiceAddress?) {
        self.customMessage = customMessage
        self.infoMessageUserInfo = infoMessageUserInfo.map { $0 as [InfoMessageUserInfoKey: Any] }
        self.messageType = messageType
        self.read = read
        self.serverGuid = serverGuid
        self.unregisteredAddress = unregisteredAddress
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

    open override var interactionType: OWSInteractionType { .info }

    // MARK: OWSReadTracking

    public func markAsRead(at readTimestamp: UInt64,
                           thread: TSThread,
                           circumstance: OWSReceiptCircumstance,
                           shouldClearNotifications: Bool,
                           transaction: DBWriteTransaction) {
        if read { return }
        // PASS 1: set directly; the anyUpdateInfoMessage DB write + receipts deferred.
        read = true
    }

    // MARK: Equality

    open override var hash: Int {
        var result = super.hash
        result ^= (customMessage as NSString?)?.hash ?? 0
        result ^= (infoMessageUserInfo.map { $0 as NSDictionary })?.hash ?? 0
        result ^= Int(truncatingIfNeeded: messageType.rawValue)
        result ^= read ? 1 : 0
        result ^= (serverGuid as NSString?)?.hash ?? 0
        result ^= unregisteredAddress?.hash ?? 0
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let other = object as? TSInfoMessage else {
            return false
        }
        func objectsEqual(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
            if lhs == nil, rhs == nil { return true }
            return lhs?.isEqual(rhs) ?? false
        }
        return objectsEqual(customMessage as NSString?, other.customMessage as NSString?)
            && objectsEqual(infoMessageUserInfo.map { $0 as NSDictionary },
                            other.infoMessageUserInfo.map { $0 as NSDictionary })
            && messageType == other.messageType
            && read == other.read
            && objectsEqual(serverGuid as NSString?, other.serverGuid as NSString?)
            && objectsEqual(unregisteredAddress, other.unregisteredAddress)
    }
}
