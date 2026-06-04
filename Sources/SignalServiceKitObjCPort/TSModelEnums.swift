//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// These enums are declared in Objective-C headers in the upstream Signal-iOS
// SignalServiceKit (NS_ENUM / NS_CLOSED_ENUM). On Apple they are imported into
// Swift by the Clang importer; on Linux there is no ObjC importer, and the
// owning `.h`/`.m` files are excluded from the SwiftPM target, so the hundreds
// of Swift files that reference these types fail with "cannot find type".
//
// This file ports them to faithful Swift enums, preserving for each:
//   * the EXACT raw-value type the ObjC enum used (NSInteger -> Int,
//     NSUInteger -> UInt, int32_t -> Int32, uint64_t -> UInt64), because the
//     generated `*+SDS.swift` records and decoders construct them via
//     `Enum(rawValue: <column>)` and GRDB decodes the column to RawValue;
//   * the EXACT integer raw values from the ObjC headers (persisted on disk);
//   * the Swift-imported (prefix-stripped, lower-camel) CASE NAMES that the
//     existing Swift code already references (verified against call sites).
//
// Codable conformance is intentionally NOT declared here: the compiled file
// `Util/SDS+Enums.swift` already provides `extension <Enum>: Codable {}` for
// each of these (empty extensions that synthesize Codable on a raw-value enum).
// Declaring `: Codable` here too would be a redundant-conformance error.
//
// STRUCTURAL NOTE: this file is the committable source of truth. For the build
// it is overlaid SAME-MODULE into the SignalServiceKit target source tree (the
// Swift consumers reference these as same-module types, exactly as they would
// the ObjC-imported originals on Apple). The durable architecture overlays this
// into a generated source copy via the lowering pipeline.
//
import Foundation

// MARK: - TSOutgoingMessage.h : NS_CLOSED_ENUM(NSInteger, TSOutgoingMessageState)

public enum TSOutgoingMessageState: Int {
    case sending = 0
    case failed = 1
    // These two enum values have been combined into `.sent`.
    case sent_OBSOLETE = 2
    case delivered_OBSOLETE = 3
    case sent = 4
    case pending = 5
}

// MARK: - Security/OWSVerificationState.h : NS_CLOSED_ENUM(uint64_t, OWSVerificationState)

public enum OWSVerificationState: UInt64 {
    case `default` = 0
    case verified = 1
    case noLongerVerified = 2
    case defaultAcknowledged = 3
}

// MARK: - TSMessage.h : NS_CLOSED_ENUM(NSInteger, TSEditState)

public enum TSEditState: Int {
    case none = 0
    case latestRevisionRead = 1
    case pastRevision = 2
    case latestRevisionUnread = 3
}

// MARK: - TSInfoMessage.h : NS_CLOSED_ENUM(NSInteger, TSInfoMessageType)
// NOTE: mixed ObjC prefixes (`TSInfoMessageType*` and `TSInfoMessage*`) mean the
// Swift importer strips only the common prefix `TSInfoMessage`, so the
// `...Type...` cases keep a leading `type`.

public enum TSInfoMessageType: Int {
    case typeLocalUserEndedSession = 0
    case userNotRegistered = 1
    case typeUnsupportedMessage = 2
    case typeGroupUpdate = 3
    case typeGroupQuit = 4
    case typeDisappearingMessagesUpdate = 5
    case addToContactsOffer = 6
    case verificationStateChange = 7
    case addUserToProfileWhitelistOffer = 8
    case addGroupToProfileWhitelistOffer = 9
    case unknownProtocolVersion = 10
    case userJoinedSignal = 11
    case syncedThread = 12
    case profileUpdate = 13
    case phoneNumberChange = 14
    case recipientHidden = 15
    case paymentsActivationRequest = 16
    case paymentsActivated = 17
    case threadMerge = 18
    case sessionSwitchover = 19
    case reportedSpam = 20
    case learnedProfileName = 21
    case blockedOtherUser = 22
    case blockedGroup = 23
    case unblockedOtherUser = 24
    case unblockedGroup = 25
    case acceptedMessageRequest = 26
    case typeRemoteUserEndedSession = 27
    case typeEndPoll = 28
    case typePinnedMessage = 29
}

// MARK: - TSErrorMessage.h : NS_CLOSED_ENUM(int32_t, TSErrorMessageType)

public enum TSErrorMessageType: Int32 {
    case noSession = 0
    case wrongTrustedIdentityKey = 1
    case invalidKeyException = 2
    case missingKeyId = 3
    case invalidMessage = 4
    case duplicateMessage = 5
    case invalidVersion = 6
    case nonBlockingIdentityChange = 7
    case unknownContactBlockOffer = 8
    case groupCreationFailed = 9
    case sessionRefresh = 10
    case decryptionFailure = 11
}

// MARK: - TSCall.h : NS_ENUM(NSUInteger, RPRecentCallType)  (1-based)

public enum RPRecentCallType: UInt {
    case incoming = 1
    case outgoing = 2
    case incomingMissed = 3
    case outgoingIncomplete = 4
    case incomingIncomplete = 5
    case incomingMissedBecauseOfChangedIdentity = 6
    case incomingDeclined = 7
    case outgoingMissed = 8
    case incomingAnsweredElsewhere = 9
    case incomingDeclinedElsewhere = 10
    case incomingBusyElsewhere = 11
    case incomingMissedBecauseOfDoNotDisturb = 12
    case incomingMissedBecauseBlockedSystemContact = 13
}

// MARK: - TSCall.h : NS_CLOSED_ENUM(NSUInteger, TSRecentCallOfferType)

public enum TSRecentCallOfferType: UInt {
    case audio = 0
    case video = 1
}

// MARK: - TSPaymentModels.h : NS_ENUM(NSUInteger, TSPaymentCurrency)

public enum TSPaymentCurrency: UInt {
    case unknown = 0
    case mobileCoin = 1
}

// MARK: - TSPaymentModels.h : NS_ENUM(NSUInteger, TSPaymentType)

public enum TSPaymentType: UInt {
    case incomingPayment = 0
    case outgoingPayment = 1
    case outgoingPaymentNotFromLocalDevice = 2
    case incomingUnidentified = 3
    case outgoingUnidentified = 4
    case outgoingTransfer = 5
    case outgoingDefragmentation = 6
    case outgoingDefragmentationNotFromLocalDevice = 7
    case outgoingRestored = 8
    case incomingRestored = 9
}

// MARK: - TSPaymentModels.h : NS_ENUM(NSUInteger, TSPaymentState)

public enum TSPaymentState: UInt {
    case outgoingUnsubmitted = 0
    case outgoingUnverified = 1
    case outgoingVerified = 2
    case outgoingSending = 3
    case outgoingSent = 4
    case outgoingComplete = 5
    case outgoingFailed = 6
    case incomingUnverified = 7
    case incomingVerified = 8
    case incomingComplete = 9
    case incomingFailed = 10
}

// MARK: - TSPaymentModels.h : NS_ENUM(NSUInteger, TSPaymentFailure)

public enum TSPaymentFailure: UInt {
    case none = 0
    case unknown = 1
    case insufficientFunds = 2
    case validationFailed = 3
    case notificationSendFailed = 4
    case invalid = 5
    case expired = 6
}
