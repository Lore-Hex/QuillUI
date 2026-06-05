//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// The two ObjC TSInteraction subclasses under Calls/ that record call events in
// chat history: TSCall (1:1) and OWSGroupCallMessage (group). Their .m/.h are
// excluded (Calls/ is a mixed-language dir), but the Backups archivers and the
// interaction deserializers reference them, so they are ported here. Only the
// SDS designated initializers have Swift callers in the compiled set; the
// thread builders (used only by the still-excluded Calls Swift) are omitted.
//
import Foundation

// MARK: - NSStringFromCallType (TSCall.h free function)

public func NSStringFromCallType(_ callType: RPRecentCallType) -> String {
    "\(callType)"
}

// MARK: - TSCall

open class TSCall: TSInteraction, OWSPreviewText {

    public internal(set) var callType: RPRecentCallType
    public internal(set) var offerType: TSRecentCallOfferType
    public internal(set) var read: Bool

    public var wasRead: Bool { read }

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSCall.")
    }

    @available(*, unavailable, message: "TSCall is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for TSCall.")
    }

    public init(grdbId: Int64,
                uniqueId: String,
                receivedAtTimestamp: UInt64,
                sortId: UInt64,
                timestamp: UInt64,
                uniqueThreadId: String,
                callType: RPRecentCallType,
                offerType: TSRecentCallOfferType,
                read: Bool) {
        self.callType = callType
        self.offerType = offerType
        self.read = read
        super.init(grdbId: grdbId,
                   uniqueId: uniqueId,
                   receivedAtTimestamp: receivedAtTimestamp,
                   sortId: sortId,
                   timestamp: timestamp,
                   uniqueThreadId: uniqueThreadId)
    }

    // OWSPreviewText (localized per-callType text deferred).
    public func previewText(transaction: DBReadTransaction) -> String { "" }
}

// MARK: - OWSGroupCallMessage

open class OWSGroupCallMessage: TSInteraction {

    public internal(set) var creatorUuid: String?
    public internal(set) var joinedMemberUuids: [String]?
    public internal(set) var hasEnded: Bool
    public internal(set) var read: Bool
    public internal(set) var eraId: String?

    public var wasRead: Bool { read }

    /// Computed from creatorUuid / joinedMemberUuids on Apple. Parsing the ACI
    /// strings is deferred on Linux (returns nil / empty).
    public var creatorAci: AciObjC? { nil }
    public var joinedMemberAcis: [AciObjC] { [] }

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for OWSGroupCallMessage.")
    }

    @available(*, unavailable, message: "OWSGroupCallMessage is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for OWSGroupCallMessage.")
    }

    public init(grdbId: Int64,
                uniqueId: String,
                receivedAtTimestamp: UInt64,
                sortId: UInt64,
                timestamp: UInt64,
                uniqueThreadId: String,
                creatorUuid: String?,
                eraId: String?,
                hasEnded: Bool,
                joinedMemberUuids: [String]?,
                read: Bool) {
        self.creatorUuid = creatorUuid
        self.eraId = eraId
        self.hasEnded = hasEnded
        self.joinedMemberUuids = joinedMemberUuids
        self.read = read
        super.init(grdbId: grdbId,
                   uniqueId: uniqueId,
                   receivedAtTimestamp: receivedAtTimestamp,
                   sortId: sortId,
                   timestamp: timestamp,
                   uniqueThreadId: uniqueThreadId)
    }
}
