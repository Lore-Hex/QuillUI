//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful pass-1 Swift port of Messages/Interactions/TSOutgoingMessage.m as
// open class TSOutgoingMessage: TSMessage, the largest interaction subclass.
//
// Pass-1 deferrals (noted, no compile-contract impact): the recipient-computing
// builder init (additionalRecipients/explicit/skipped/transaction) builds with an
// EMPTY recipientAddressStates instead of consulting thread state; `messageState`
// returns storedMessageState (the full messageStateForRecipientStates +
// legacy-state computation is deferred); wasSent/DeliveredToAnyRecipient are
// simplified; the send machinery (buildPlaintextData/contentBuilder/
// dataMessage/sync-transcript), the write-hook overrides, shouldStartExpireTimer
// override, and updateWith* are deferred to a later pass.
//
import Foundation

private let tsOutgoingMessageSchemaVersion: UInt = 1

open class TSOutgoingMessage: TSMessage {

    public internal(set) var customMessage: String?
    public internal(set) var groupMetaMessage: Int
    public internal(set) var hasLegacyMessageState: Bool
    public internal(set) var hasSyncedTranscript: Bool
    public internal(set) var isVoiceMessage: Bool
    public internal(set) var legacyMessageState: TSOutgoingMessageState
    public internal(set) var legacyWasDelivered: Bool
    public internal(set) var mostRecentFailureText: String?
    public internal(set) var recipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?
    public internal(set) var storedMessageState: TSOutgoingMessageState
    public internal(set) var wasNotCreatedLocally: Bool
    public internal(set) var changeActionsProtoData: Data?

    internal var outgoingMessageSchemaVersion: UInt

    // MARK: Computed

    /// PASS 1: returns storedMessageState; the recipient-state computation is deferred.
    public var messageState: TSOutgoingMessageState { storedMessageState }

    public var wasSentToAnyRecipient: Bool { messageState == .sent }

    public var wasDeliveredToAnyRecipient: Bool {
        hasLegacyMessageState && legacyWasDelivered && messageState == .sent
    }

    public var isOnline: Bool { false }
    public var isUrgent: Bool { true }

    public func updateStoredMessageState() {
        storedMessageState = messageState
    }

    // MARK: Initializers

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSOutgoingMessage.")
    }

    public init(outgoingMessageWith outgoingMessageBuilder: TSOutgoingMessageBuilder,
                recipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]) {
        self.customMessage = nil
        self.groupMetaMessage = 0
        self.hasLegacyMessageState = false
        self.hasSyncedTranscript = false
        self.isVoiceMessage = outgoingMessageBuilder.isVoiceMessage
        self.legacyMessageState = .sending
        self.legacyWasDelivered = false
        self.mostRecentFailureText = nil
        self.recipientAddressStates = recipientAddressStates
        self.storedMessageState = .sending
        self.wasNotCreatedLocally = outgoingMessageBuilder.wasNotCreatedLocally
        self.changeActionsProtoData = outgoingMessageBuilder.groupChangeProtoData
        self.outgoingMessageSchemaVersion = tsOutgoingMessageSchemaVersion
        super.init(messageWithBuilder: outgoingMessageBuilder)
    }

    /// PASS 1: recipient determination from thread state is deferred — builds with
    /// an empty recipientAddressStates.
    public init(outgoingMessageWith outgoingMessageBuilder: TSOutgoingMessageBuilder,
                additionalRecipients: [ServiceIdObjC],
                explicitRecipients: [AciObjC],
                skippedRecipients: [ServiceIdObjC],
                transaction: DBReadTransaction) {
        self.customMessage = nil
        self.groupMetaMessage = 0
        self.hasLegacyMessageState = false
        self.hasSyncedTranscript = false
        self.isVoiceMessage = outgoingMessageBuilder.isVoiceMessage
        self.legacyMessageState = .sending
        self.legacyWasDelivered = false
        self.mostRecentFailureText = nil
        self.recipientAddressStates = [:]
        self.storedMessageState = .sending
        self.wasNotCreatedLocally = outgoingMessageBuilder.wasNotCreatedLocally
        self.changeActionsProtoData = outgoingMessageBuilder.groupChangeProtoData
        self.outgoingMessageSchemaVersion = tsOutgoingMessageSchemaVersion
        super.init(messageWithBuilder: outgoingMessageBuilder)
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
                wasNotCreatedLocally: Bool) {
        self.customMessage = customMessage
        self.groupMetaMessage = groupMetaMessage
        self.hasLegacyMessageState = hasLegacyMessageState
        self.hasSyncedTranscript = hasSyncedTranscript
        self.isVoiceMessage = isVoiceMessage
        self.legacyMessageState = legacyMessageState
        self.legacyWasDelivered = legacyWasDelivered
        self.mostRecentFailureText = mostRecentFailureText
        self.recipientAddressStates = recipientAddressStates
        self.storedMessageState = storedMessageState
        self.wasNotCreatedLocally = wasNotCreatedLocally
        self.changeActionsProtoData = nil
        self.outgoingMessageSchemaVersion = tsOutgoingMessageSchemaVersion
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

    // MARK: NSSecureCoding

    public required init?(coder: NSCoder) {
        self.changeActionsProtoData = coder.decodeObject(of: NSData.self, forKey: "changeActionsProtoData") as Data?
        self.customMessage = coder.decodeObject(of: NSString.self, forKey: "customMessage") as String?
        self.groupMetaMessage = (coder.decodeObject(of: NSNumber.self, forKey: "groupMetaMessage"))?.intValue ?? 0
        self.hasLegacyMessageState = (coder.decodeObject(of: NSNumber.self, forKey: "hasLegacyMessageState"))?.boolValue ?? false
        self.hasSyncedTranscript = (coder.decodeObject(of: NSNumber.self, forKey: "hasSyncedTranscript"))?.boolValue ?? false
        self.isVoiceMessage = (coder.decodeObject(of: NSNumber.self, forKey: "isVoiceMessage"))?.boolValue ?? false
        self.legacyMessageState = TSOutgoingMessageState(rawValue: (coder.decodeObject(of: NSNumber.self, forKey: "legacyMessageState"))?.intValue ?? 0) ?? .sending
        self.legacyWasDelivered = (coder.decodeObject(of: NSNumber.self, forKey: "legacyWasDelivered"))?.boolValue ?? false
        self.mostRecentFailureText = coder.decodeObject(of: NSString.self, forKey: "mostRecentFailureText") as String?
        self.outgoingMessageSchemaVersion = (coder.decodeObject(of: NSNumber.self, forKey: "outgoingMessageSchemaVersion"))?.uintValue ?? 0
        self.recipientAddressStates = coder.decodeObject(forKey: "recipientAddressStates") as? [SignalServiceAddress: TSOutgoingMessageRecipientState]
        self.storedMessageState = TSOutgoingMessageState(rawValue: (coder.decodeObject(of: NSNumber.self, forKey: "storedMessageState"))?.intValue ?? 0) ?? .sending
        self.wasNotCreatedLocally = (coder.decodeObject(of: NSNumber.self, forKey: "wasNotCreatedLocally"))?.boolValue ?? false
        super.init(coder: coder)
        self.outgoingMessageSchemaVersion = tsOutgoingMessageSchemaVersion
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let changeActionsProtoData { coder.encode(changeActionsProtoData, forKey: "changeActionsProtoData") }
        if let customMessage { coder.encode(customMessage, forKey: "customMessage") }
        coder.encode(NSNumber(value: groupMetaMessage), forKey: "groupMetaMessage")
        coder.encode(NSNumber(value: hasLegacyMessageState), forKey: "hasLegacyMessageState")
        coder.encode(NSNumber(value: hasSyncedTranscript), forKey: "hasSyncedTranscript")
        coder.encode(NSNumber(value: isVoiceMessage), forKey: "isVoiceMessage")
        coder.encode(NSNumber(value: legacyMessageState.rawValue), forKey: "legacyMessageState")
        coder.encode(NSNumber(value: legacyWasDelivered), forKey: "legacyWasDelivered")
        if let mostRecentFailureText { coder.encode(mostRecentFailureText, forKey: "mostRecentFailureText") }
        coder.encode(NSNumber(value: outgoingMessageSchemaVersion), forKey: "outgoingMessageSchemaVersion")
        if let recipientAddressStates { coder.encode(recipientAddressStates, forKey: "recipientAddressStates") }
        coder.encode(NSNumber(value: storedMessageState.rawValue), forKey: "storedMessageState")
        coder.encode(NSNumber(value: wasNotCreatedLocally), forKey: "wasNotCreatedLocally")
    }

    // MARK: Overrides

    open override var interactionType: OWSInteractionType { .outgoingMessage }

    // MARK: Equality

    open override var hash: Int {
        var result = super.hash
        result ^= (changeActionsProtoData as NSData?)?.hash ?? 0
        result ^= (customMessage as NSString?)?.hash ?? 0
        result ^= Int(truncatingIfNeeded: groupMetaMessage)
        result ^= hasLegacyMessageState ? 1 : 0
        result ^= hasSyncedTranscript ? 1 : 0
        result ^= isVoiceMessage ? 1 : 0
        result ^= Int(truncatingIfNeeded: legacyMessageState.rawValue)
        result ^= legacyWasDelivered ? 1 : 0
        result ^= (mostRecentFailureText as NSString?)?.hash ?? 0
        result ^= Int(truncatingIfNeeded: outgoingMessageSchemaVersion)
        result ^= (recipientAddressStates.map { $0 as NSDictionary })?.hash ?? 0
        result ^= Int(truncatingIfNeeded: storedMessageState.rawValue)
        result ^= wasNotCreatedLocally ? 1 : 0
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let other = object as? TSOutgoingMessage else {
            return false
        }
        func objectsEqual(_ lhs: NSObject?, _ rhs: NSObject?) -> Bool {
            if lhs == nil, rhs == nil { return true }
            return lhs?.isEqual(rhs) ?? false
        }
        return objectsEqual(changeActionsProtoData as NSData?, other.changeActionsProtoData as NSData?)
            && objectsEqual(customMessage as NSString?, other.customMessage as NSString?)
            && groupMetaMessage == other.groupMetaMessage
            && hasLegacyMessageState == other.hasLegacyMessageState
            && hasSyncedTranscript == other.hasSyncedTranscript
            && isVoiceMessage == other.isVoiceMessage
            && legacyMessageState == other.legacyMessageState
            && legacyWasDelivered == other.legacyWasDelivered
            && objectsEqual(mostRecentFailureText as NSString?, other.mostRecentFailureText as NSString?)
            && outgoingMessageSchemaVersion == other.outgoingMessageSchemaVersion
            && objectsEqual(recipientAddressStates.map { $0 as NSDictionary },
                            other.recipientAddressStates.map { $0 as NSDictionary })
            && storedMessageState == other.storedMessageState
            && wasNotCreatedLocally == other.wasNotCreatedLocally
    }
}
