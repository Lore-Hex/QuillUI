//
// SignalServiceKit ObjC base-model port for QuillOS (Track B).
//
// Faithful Swift port of Messages/Interactions/TSInteraction.{h,m} (ObjC,
// excluded on Linux) — the keystone of the model spine. ~70 Swift files
// subclass or reference it (TSMessage, TSCall, TSInfoMessage, ...). On Apple it
// is imported via the SignalServiceKit umbrella; on Linux it must exist as
// same-module Swift.
//
// Behaviour mirrors the original .m: the designated initializers (including the
// generated SDS init(grdbId:uniqueId:receivedAtTimestamp:sortId:timestamp:
// uniqueThreadId:) that TSInteraction+SDS.swift constructs), NSSecureCoding
// encode/decode with the legacy receivedAtTimestamp upgrade, the
// timestamp/sortId/threadId accessors, and the overridable interactionType /
// isDynamicInteraction hooks. Deep side effects are stubbed where the
// dependency is not yet ported.
//
// Divergences (Linux, noted): the `[[NSUUID sequential] UUIDString]` insert
// optimization falls back to a plain UUID; the TESTABLE_BUILD-only
// replaceTimestamp helpers are omitted (no callers, build has no TESTABLE_BUILD);
// receivedAtDate/timestampDate are computed directly from the ms timestamps.
//
import Foundation

// MARK: - OWSInteractionType  (declared in TSInteraction.h)

public enum OWSInteractionType: Int {
    case unknown = 0
    case incomingMessage = 1
    case outgoingMessage = 2
    case error = 3
    case call = 4
    case info = 5
    case typingIndicator = 6
    case threadDetails = 7
    case unreadIndicator = 8
    case dateHeader = 9
    case unknownThreadWarning = 10
    case defaultDisappearingMessageTimer = 11
    case collapseSet = 12
}

// MARK: - OWSPreviewText  (declared in TSInteraction.h)

public protocol OWSPreviewText: NSObjectProtocol {
    func previewText(transaction: DBReadTransaction) -> String
}

// MARK: - TSInteraction

open class TSInteraction: BaseModel, NSSecureCoding {

    public internal(set) var uniqueThreadId: String

    public internal(set) var sortId: UInt64

    /// A generic client-supplied "timestamp" for this interaction (ms since 1970).
    /// Almost always immutable; placeholder replacement is the one exception, so
    /// the setter is module-internal.
    public internal(set) var timestamp: UInt64

    /// An always locally-generated timestamp for when we "received" this
    /// interaction (ms since 1970).
    public internal(set) var receivedAtTimestamp: UInt64

    // MARK: Designated initializers

    public init(customUniqueId uniqueId: String,
                timestamp: UInt64,
                receivedAtTimestamp: UInt64,
                thread: TSThread) {
        self.sortId = 0
        self.timestamp = timestamp
        self.receivedAtTimestamp = receivedAtTimestamp
        self.uniqueThreadId = thread.uniqueId
        super.init(uniqueId: uniqueId)
    }

    public init(timestamp: UInt64,
                receivedAtTimestamp: UInt64,
                thread: TSThread) {
        self.sortId = 0
        self.timestamp = timestamp
        self.receivedAtTimestamp = receivedAtTimestamp
        self.uniqueThreadId = thread.uniqueId
        // Upstream uses a sequential (UUIDv7-style) id as an insert optimization;
        // that NSUUID category is ObjC-only, so fall back to a random UUID.
        super.init(uniqueId: UUID().uuidString)
    }

    /// Generated SDS initializer — TSInteraction+SDS.swift constructs the model
    /// through this from an InteractionRecord row.
    public init(grdbId: Int64,
                uniqueId: String,
                receivedAtTimestamp: UInt64,
                sortId: UInt64,
                timestamp: UInt64,
                uniqueThreadId: String) {
        self.receivedAtTimestamp = receivedAtTimestamp
        self.sortId = sortId
        self.timestamp = timestamp
        self.uniqueThreadId = uniqueThreadId
        super.init(grdbId: grdbId, uniqueId: uniqueId)
    }

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSInteraction.")
    }

    // MARK: NSSecureCoding

    public class var supportsSecureCoding: Bool { true }

    public required init?(coder: NSCoder) {
        let decodedReceived = (coder.decodeObject(of: NSNumber.self, forKey: "receivedAtTimestamp"))?.uint64Value ?? 0
        let decodedTimestamp = (coder.decodeObject(of: NSNumber.self, forKey: "timestamp"))?.uint64Value ?? 0
        self.sortId = (coder.decodeObject(of: NSNumber.self, forKey: "sortId"))?.uint64Value ?? 0
        self.timestamp = decodedTimestamp
        self.uniqueThreadId = (coder.decodeObject(of: NSString.self, forKey: "uniqueThreadId") as String?) ?? ""

        // Previously receivedAtTimestamp lived on TSMessage; it moved up to
        // TSInteraction. Upgrade from the older receivedAtDate/receivedAt fields.
        var receivedFinal = decodedReceived
        if receivedFinal == 0 {
            var receivedAtDate = coder.decodeObject(of: NSDate.self, forKey: "receivedAtDate")
            if receivedAtDate == nil {
                receivedAtDate = coder.decodeObject(of: NSDate.self, forKey: "receivedAt")
            }
            if let receivedAtDate {
                receivedFinal = NSDate.ows_millisecondsSince1970(forDate: receivedAtDate)
            }
            // For non-message interactions, the timestamp *is* the receivedAtTimestamp.
            if receivedFinal == 0 {
                receivedFinal = decodedTimestamp
            }
        }
        self.receivedAtTimestamp = receivedFinal

        super.init(coder: coder)
    }

    open func encode(with coder: NSCoder) {
        encodeIds(with: coder)
        coder.encode(NSNumber(value: receivedAtTimestamp), forKey: "receivedAtTimestamp")
        coder.encode(NSNumber(value: sortId), forKey: "sortId")
        coder.encode(NSNumber(value: timestamp), forKey: "timestamp")
        coder.encode(uniqueThreadId, forKey: "uniqueThreadId")
    }

    // MARK: Equality

    open override var hash: Int {
        var result = super.hash
        result ^= Int(truncatingIfNeeded: receivedAtTimestamp)
        result ^= Int(truncatingIfNeeded: sortId)
        result ^= Int(truncatingIfNeeded: timestamp)
        result ^= uniqueThreadId.hashValue
        return result
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard super.isEqual(object), let other = object as? TSInteraction else {
            return false
        }
        return receivedAtTimestamp == other.receivedAtTimestamp
            && sortId == other.sortId
            && timestamp == other.timestamp
            && uniqueThreadId == other.uniqueThreadId
    }

    // MARK: Thread

    public func thread(tx: DBReadTransaction) -> TSThread? {
        // May be empty for a few legacy interactions enqueued in the message sender.
        if uniqueThreadId.isEmpty {
            return nil
        }
        // It's also possible that the thread doesn't exist.
        return TSThread.fetchViaCacheObjC(uniqueId: uniqueThreadId, transaction: tx)
    }

    // MARK: Date operations

    public var receivedAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(receivedAtTimestamp) / 1000)
    }

    public var timestampDate: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }

    // MARK: Type / dynamic

    open var interactionType: OWSInteractionType {
        owsFailDebug("unknown interaction type.")
        return .unknown
    }

    open override var description: String {
        "\(super.description) in thread: \(uniqueThreadId) timestamp: \(timestamp)"
    }

    /// "Dynamic" interactions are not messages or static events (info/error
    /// messages, etc.); they are created/updated/deleted by the views.
    open var isDynamicInteraction: Bool { false }

    // MARK: Sorting migration

    public func replaceSortId(_ sortId: UInt64) {
        self.sortId = sortId
    }
}
