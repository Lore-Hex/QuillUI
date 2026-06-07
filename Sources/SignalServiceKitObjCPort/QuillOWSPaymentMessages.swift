//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// The OWSPaymentMessage chain (Messages/Payments/, excluded ObjC):
//   OWSPaymentMessage                  (protocol: paymentNotification)
//   OWSOutgoingPaymentMessage          (TSOutgoingMessage subclass)
//   OWSIncomingPaymentMessage          (TSIncomingMessage subclass)
//   OWSIncomingArchivedPaymentMessage  (TSIncomingMessage subclass)
//
// Only the SDS designated initializers have Swift callers (the deserializers).
// TSPaymentNotification / TSArchivedPaymentInfo / the OWSArchivedPaymentMessage
// protocol are ported elsewhere (QuillTSPaymentModels.swift /
// QuillOWSOutgoingArchivedPaymentMessage.swift).
//
import Foundation

// MARK: - OWSPaymentMessage (protocol)

public protocol OWSPaymentMessage {
    var paymentNotification: TSPaymentNotification? { get }
}

// MARK: - OWSOutgoingPaymentMessage

open class OWSOutgoingPaymentMessage: TSOutgoingMessage, OWSPaymentMessage {

    public internal(set) var paymentCancellation: Data?
    public internal(set) var paymentNotification: TSPaymentNotification?
    public internal(set) var paymentRequest: Data?

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSOutgoingPaymentMessage.")
    }

    public required init?(coder: NSCoder) {
        self.paymentCancellation = coder.decodeObject(forKey: "paymentCancellation") as? Data
        self.paymentNotification = coder.decodeObject(forKey: "paymentNotification") as? TSPaymentNotification
        self.paymentRequest = coder.decodeObject(forKey: "paymentRequest") as? Data
        super.init(coder: coder)
    }

    public init(grdbId: Int64, uniqueId: String, receivedAtTimestamp: UInt64, sortId: UInt64,
                timestamp: UInt64, uniqueThreadId: String, body: String?, bodyRanges: MessageBodyRanges?,
                contactShare: OWSContact?, deprecated_attachmentIds: [String]?, editState: TSEditState,
                expireStartedAt: UInt64, expireTimerVersion: NSNumber?, expiresAt: UInt64,
                expiresInSeconds: UInt32, giftBadge: OWSGiftBadge?, isGroupStoryReply: Bool, isPoll: Bool,
                isSmsMessageRestoredFromBackup: Bool, isViewOnceComplete: Bool, isViewOnceMessage: Bool,
                linkPreview: OWSLinkPreview?, messageSticker: MessageSticker?, quotedMessage: TSQuotedMessage?,
                storedShouldStartExpireTimer: Bool, storyAuthorUuidString: String?, storyReactionEmoji: String?,
                storyTimestamp: NSNumber?, wasRemotelyDeleted: Bool, customMessage: String?, groupMetaMessage: Int,
                hasLegacyMessageState: Bool, hasSyncedTranscript: Bool, isVoiceMessage: Bool,
                legacyMessageState: TSOutgoingMessageState, legacyWasDelivered: Bool, mostRecentFailureText: String?,
                recipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?,
                storedMessageState: TSOutgoingMessageState, wasNotCreatedLocally: Bool,
                paymentCancellation: Data?, paymentNotification: TSPaymentNotification?, paymentRequest: Data?) {
        self.paymentCancellation = paymentCancellation
        self.paymentNotification = paymentNotification
        self.paymentRequest = paymentRequest
        super.init(grdbId: grdbId, uniqueId: uniqueId, receivedAtTimestamp: receivedAtTimestamp, sortId: sortId,
                   timestamp: timestamp, uniqueThreadId: uniqueThreadId, body: body, bodyRanges: bodyRanges,
                   contactShare: contactShare, deprecated_attachmentIds: deprecated_attachmentIds, editState: editState,
                   expireStartedAt: expireStartedAt, expireTimerVersion: expireTimerVersion, expiresAt: expiresAt,
                   expiresInSeconds: expiresInSeconds, giftBadge: giftBadge, isGroupStoryReply: isGroupStoryReply, isPoll: isPoll,
                   isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup, isViewOnceComplete: isViewOnceComplete, isViewOnceMessage: isViewOnceMessage,
                   linkPreview: linkPreview, messageSticker: messageSticker, quotedMessage: quotedMessage,
                   storedShouldStartExpireTimer: storedShouldStartExpireTimer, storyAuthorUuidString: storyAuthorUuidString, storyReactionEmoji: storyReactionEmoji,
                   storyTimestamp: storyTimestamp, wasRemotelyDeleted: wasRemotelyDeleted, customMessage: customMessage, groupMetaMessage: groupMetaMessage,
                   hasLegacyMessageState: hasLegacyMessageState, hasSyncedTranscript: hasSyncedTranscript, isVoiceMessage: isVoiceMessage,
                   legacyMessageState: legacyMessageState, legacyWasDelivered: legacyWasDelivered, mostRecentFailureText: mostRecentFailureText,
                   recipientAddressStates: recipientAddressStates, storedMessageState: storedMessageState, wasNotCreatedLocally: wasNotCreatedLocally)
    }

    // Builder initializer (OWSOutgoingPaymentMessage.m
    // initWithBuilder:paymentNotification:transaction:): the convenience init in
    // OWSOutgoingPaymentMessage.swift delegates here. Forwards to TSOutgoingMessage's
    // builder init with empty recipient sets (as in the original) and stores the
    // payment notification.
    public init(builder messageBuilder: TSOutgoingMessageBuilder,
                paymentNotification: TSPaymentNotification,
                transaction: DBReadTransaction) {
        self.paymentCancellation = nil
        self.paymentNotification = paymentNotification
        self.paymentRequest = nil
        super.init(outgoingMessageWith: messageBuilder,
                   additionalRecipients: [],
                   explicitRecipients: [],
                   skippedRecipients: [],
                   transaction: transaction)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let paymentCancellation { coder.encode(paymentCancellation, forKey: "paymentCancellation") }
        if let paymentNotification { coder.encode(paymentNotification, forKey: "paymentNotification") }
        if let paymentRequest { coder.encode(paymentRequest, forKey: "paymentRequest") }
    }
}

// MARK: - TSIncomingMessage payment subclasses

open class OWSIncomingPaymentMessage: TSIncomingMessage, OWSPaymentMessage {

    public internal(set) var paymentCancellation: Data?
    public internal(set) var paymentNotification: TSPaymentNotification?
    public internal(set) var paymentRequest: Data?

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSIncomingPaymentMessage.")
    }

    @available(*, unavailable, message: "OWSIncomingPaymentMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for OWSIncomingPaymentMessage.")
    }

    public init(grdbId: Int64, uniqueId: String, receivedAtTimestamp: UInt64, sortId: UInt64,
                timestamp: UInt64, uniqueThreadId: String, body: String?, bodyRanges: MessageBodyRanges?,
                contactShare: OWSContact?, deprecated_attachmentIds: [String]?, editState: TSEditState,
                expireStartedAt: UInt64, expireTimerVersion: NSNumber?, expiresAt: UInt64,
                expiresInSeconds: UInt32, giftBadge: OWSGiftBadge?, isGroupStoryReply: Bool, isPoll: Bool,
                isSmsMessageRestoredFromBackup: Bool, isViewOnceComplete: Bool, isViewOnceMessage: Bool,
                linkPreview: OWSLinkPreview?, messageSticker: MessageSticker?, quotedMessage: TSQuotedMessage?,
                storedShouldStartExpireTimer: Bool, storyAuthorUuidString: String?, storyReactionEmoji: String?,
                storyTimestamp: NSNumber?, wasRemotelyDeleted: Bool, authorPhoneNumber: String?, authorUUID: String?,
                deprecated_sourceDeviceId: NSNumber?, read: Bool, serverDeliveryTimestamp: UInt64, serverGuid: String?,
                serverTimestamp: NSNumber?, viewed: Bool, wasReceivedByUD: Bool,
                paymentCancellation: Data?, paymentNotification: TSPaymentNotification?, paymentRequest: Data?) {
        self.paymentCancellation = paymentCancellation
        self.paymentNotification = paymentNotification
        self.paymentRequest = paymentRequest
        super.init(grdbId: grdbId, uniqueId: uniqueId, receivedAtTimestamp: receivedAtTimestamp, sortId: sortId,
                   timestamp: timestamp, uniqueThreadId: uniqueThreadId, body: body, bodyRanges: bodyRanges,
                   contactShare: contactShare, deprecated_attachmentIds: deprecated_attachmentIds, editState: editState,
                   expireStartedAt: expireStartedAt, expireTimerVersion: expireTimerVersion, expiresAt: expiresAt,
                   expiresInSeconds: expiresInSeconds, giftBadge: giftBadge, isGroupStoryReply: isGroupStoryReply, isPoll: isPoll,
                   isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup, isViewOnceComplete: isViewOnceComplete, isViewOnceMessage: isViewOnceMessage,
                   linkPreview: linkPreview, messageSticker: messageSticker, quotedMessage: quotedMessage,
                   storedShouldStartExpireTimer: storedShouldStartExpireTimer, storyAuthorUuidString: storyAuthorUuidString, storyReactionEmoji: storyReactionEmoji,
                   storyTimestamp: storyTimestamp, wasRemotelyDeleted: wasRemotelyDeleted, authorPhoneNumber: authorPhoneNumber, authorUUID: authorUUID,
                   deprecated_sourceDeviceId: deprecated_sourceDeviceId, read: read, serverDeliveryTimestamp: serverDeliveryTimestamp, serverGuid: serverGuid,
                   serverTimestamp: serverTimestamp, viewed: viewed, wasReceivedByUD: wasReceivedByUD)
    }

    // Builder initializer (OWSIncomingPaymentMessage.m
    // initIncomingMessageWithBuilder:paymentNotification:): TSIncomingMessageBuilder
    // .build() returns this when a paymentNotification is present. Forwards to
    // TSIncomingMessage's builder init and stores the payment notification.
    public init(initIncomingMessageWithBuilder messageBuilder: TSIncomingMessageBuilder,
                paymentNotification: TSPaymentNotification) {
        self.paymentCancellation = nil
        self.paymentNotification = paymentNotification
        self.paymentRequest = nil
        super.init(incomingMessageWithBuilder: messageBuilder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let paymentCancellation { coder.encode(paymentCancellation, forKey: "paymentCancellation") }
        if let paymentNotification { coder.encode(paymentNotification, forKey: "paymentNotification") }
        if let paymentRequest { coder.encode(paymentRequest, forKey: "paymentRequest") }
    }
}

open class OWSIncomingArchivedPaymentMessage: TSIncomingMessage, OWSArchivedPaymentMessage {

    public internal(set) var archivedPaymentInfo: TSArchivedPaymentInfo

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSIncomingArchivedPaymentMessage.")
    }

    @available(*, unavailable, message: "OWSIncomingArchivedPaymentMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for OWSIncomingArchivedPaymentMessage.")
    }

    public init(grdbId: Int64, uniqueId: String, receivedAtTimestamp: UInt64, sortId: UInt64,
                timestamp: UInt64, uniqueThreadId: String, body: String?, bodyRanges: MessageBodyRanges?,
                contactShare: OWSContact?, deprecated_attachmentIds: [String]?, editState: TSEditState,
                expireStartedAt: UInt64, expireTimerVersion: NSNumber?, expiresAt: UInt64,
                expiresInSeconds: UInt32, giftBadge: OWSGiftBadge?, isGroupStoryReply: Bool, isPoll: Bool,
                isSmsMessageRestoredFromBackup: Bool, isViewOnceComplete: Bool, isViewOnceMessage: Bool,
                linkPreview: OWSLinkPreview?, messageSticker: MessageSticker?, quotedMessage: TSQuotedMessage?,
                storedShouldStartExpireTimer: Bool, storyAuthorUuidString: String?, storyReactionEmoji: String?,
                storyTimestamp: NSNumber?, wasRemotelyDeleted: Bool, authorPhoneNumber: String?, authorUUID: String?,
                deprecated_sourceDeviceId: NSNumber?, read: Bool, serverDeliveryTimestamp: UInt64, serverGuid: String?,
                serverTimestamp: NSNumber?, viewed: Bool, wasReceivedByUD: Bool,
                archivedPaymentInfo: TSArchivedPaymentInfo) {
        self.archivedPaymentInfo = archivedPaymentInfo
        super.init(grdbId: grdbId, uniqueId: uniqueId, receivedAtTimestamp: receivedAtTimestamp, sortId: sortId,
                   timestamp: timestamp, uniqueThreadId: uniqueThreadId, body: body, bodyRanges: bodyRanges,
                   contactShare: contactShare, deprecated_attachmentIds: deprecated_attachmentIds, editState: editState,
                   expireStartedAt: expireStartedAt, expireTimerVersion: expireTimerVersion, expiresAt: expiresAt,
                   expiresInSeconds: expiresInSeconds, giftBadge: giftBadge, isGroupStoryReply: isGroupStoryReply, isPoll: isPoll,
                   isSmsMessageRestoredFromBackup: isSmsMessageRestoredFromBackup, isViewOnceComplete: isViewOnceComplete, isViewOnceMessage: isViewOnceMessage,
                   linkPreview: linkPreview, messageSticker: messageSticker, quotedMessage: quotedMessage,
                   storedShouldStartExpireTimer: storedShouldStartExpireTimer, storyAuthorUuidString: storyAuthorUuidString, storyReactionEmoji: storyReactionEmoji,
                   storyTimestamp: storyTimestamp, wasRemotelyDeleted: wasRemotelyDeleted, authorPhoneNumber: authorPhoneNumber, authorUUID: authorUUID,
                   deprecated_sourceDeviceId: deprecated_sourceDeviceId, read: read, serverDeliveryTimestamp: serverDeliveryTimestamp, serverGuid: serverGuid,
                   serverTimestamp: serverTimestamp, viewed: viewed, wasReceivedByUD: wasReceivedByUD)
    }

    // Builder initializer (OWSIncomingArchivedPaymentMessage.m
    // initIncomingMessageWith:amount:fee:note:): the backup restore path
    // (BackupArchiveTSIncomingMessageArchiver) builds an archived-payment message.
    // Designated init building TSArchivedPaymentInfo from amount/fee/note and
    // forwarding to TSIncomingMessage's builder init (mirrors the Outgoing variant).
    public init(incomingMessageWith messageBuilder: TSIncomingMessageBuilder,
                amount: String?,
                fee: String?,
                note: String?) {
        self.archivedPaymentInfo = TSArchivedPaymentInfo(amount: amount, fee: fee, note: note)
        super.init(incomingMessageWithBuilder: messageBuilder)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(archivedPaymentInfo, forKey: "archivedPaymentInfo")
    }
}
