//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// Faithful pass-1 Swift port of Messages/Payments/OWSOutgoingArchivedPaymentMessage.m
// (a TSOutgoingMessage subclass), plus the two small types it depends on that live
// in the excluded ObjC headers: TSArchivedPaymentInfo (TSPaymentModels.h) and the
// OWSArchivedPaymentMessage protocol (OWSArchivedPaymentMessage.h).
//
import Foundation

// MARK: - TSArchivedPaymentInfo (TSPaymentModels.h)

public class TSArchivedPaymentInfo: NSObject, NSSecureCoding, NSCopying {
    public internal(set) var amount: String?
    public internal(set) var fee: String?
    public internal(set) var note: String?

    public init(amount: String?, fee: String?, note: String?) {
        self.amount = amount
        self.fee = fee
        self.note = note
        super.init()
    }

    public class var supportsSecureCoding: Bool { true }

    public required init?(coder: NSCoder) {
        self.amount = coder.decodeObject(of: NSString.self, forKey: "amount") as String?
        self.fee = coder.decodeObject(of: NSString.self, forKey: "fee") as String?
        self.note = coder.decodeObject(of: NSString.self, forKey: "note") as String?
        super.init()
    }

    public func encode(with coder: NSCoder) {
        if let amount { coder.encode(amount, forKey: "amount") }
        if let fee { coder.encode(fee, forKey: "fee") }
        if let note { coder.encode(note, forKey: "note") }
    }

    public override var hash: Int {
        var result = 0
        result ^= (amount as NSString?)?.hash ?? 0
        result ^= (fee as NSString?)?.hash ?? 0
        result ^= (note as NSString?)?.hash ?? 0
        return result
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TSArchivedPaymentInfo, type(of: other) == type(of: self) else {
            return false
        }
        return amount == other.amount && fee == other.fee && note == other.note
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        TSArchivedPaymentInfo(amount: amount, fee: fee, note: note)
    }
}

// MARK: - OWSArchivedPaymentMessage (OWSArchivedPaymentMessage.h)

public protocol OWSArchivedPaymentMessage {
    var archivedPaymentInfo: TSArchivedPaymentInfo { get }
}

// MARK: - OWSOutgoingArchivedPaymentMessage

open class OWSOutgoingArchivedPaymentMessage: TSOutgoingMessage, OWSArchivedPaymentMessage {

    public internal(set) var archivedPaymentInfo: TSArchivedPaymentInfo

    // MARK: Initializers

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSOutgoingArchivedPaymentMessage.")
    }

    public init(outgoingArchivedPaymentMessageWith messageBuilder: TSOutgoingMessageBuilder,
                amount: String?,
                fee: String?,
                note: String?,
                transaction: DBReadTransaction) {
        self.archivedPaymentInfo = TSArchivedPaymentInfo(amount: amount, fee: fee, note: note)
        super.init(outgoingMessageWith: messageBuilder,
                   additionalRecipients: [],
                   explicitRecipients: [],
                   skippedRecipients: [],
                   transaction: transaction)
    }

    public init(outgoingArchivedPaymentMessageWith messageBuilder: TSOutgoingMessageBuilder,
                amount: String?,
                fee: String?,
                note: String?,
                recipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]) {
        self.archivedPaymentInfo = TSArchivedPaymentInfo(amount: amount, fee: fee, note: note)
        super.init(outgoingMessageWith: messageBuilder, recipientAddressStates: recipientAddressStates)
    }

    public required init?(coder: NSCoder) {
        self.archivedPaymentInfo = (coder.decodeObject(forKey: "archivedPaymentInfo") as? TSArchivedPaymentInfo)
            ?? TSArchivedPaymentInfo(amount: nil, fee: nil, note: nil)
        super.init(coder: coder)
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
                groupMetaMessage: Int,
                hasLegacyMessageState: Bool,
                hasSyncedTranscript: Bool,
                isVoiceMessage: Bool,
                legacyMessageState: TSOutgoingMessageState,
                legacyWasDelivered: Bool,
                mostRecentFailureText: String?,
                recipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?,
                storedMessageState: TSOutgoingMessageState,
                wasNotCreatedLocally: Bool,
                archivedPaymentInfo: TSArchivedPaymentInfo) {
        self.archivedPaymentInfo = archivedPaymentInfo
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
                   groupMetaMessage: groupMetaMessage,
                   hasLegacyMessageState: hasLegacyMessageState,
                   hasSyncedTranscript: hasSyncedTranscript,
                   isVoiceMessage: isVoiceMessage,
                   legacyMessageState: legacyMessageState,
                   legacyWasDelivered: legacyWasDelivered,
                   mostRecentFailureText: mostRecentFailureText,
                   recipientAddressStates: recipientAddressStates,
                   storedMessageState: storedMessageState,
                   wasNotCreatedLocally: wasNotCreatedLocally)
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(archivedPaymentInfo, forKey: "archivedPaymentInfo")
    }

    open override var hash: Int {
        var result = super.hash
        result ^= archivedPaymentInfo.hash
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let other = object as? OWSOutgoingArchivedPaymentMessage else {
            return false
        }
        return archivedPaymentInfo.isEqual(other.archivedPaymentInfo)
    }
}
