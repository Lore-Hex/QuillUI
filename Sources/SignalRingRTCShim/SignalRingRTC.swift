//
// QuillUI Linux shim for SignalRingRTC (signalapp/ringrtc v2.69.1).
//
// RingRTC is Signal's voice/video calling stack: a Rust core plus a Swift layer
// that `import WebRTC` (the iOS WebRTC framework) and calls a generated Rust FFI.
// None of that exists on Linux, and building it would mean building all of
// WebRTC for aarch64. Voice/video calling is therefore DEFERRED.
//
// SignalServiceKit, however, references a small SignalRingRTC type surface from
// its *non-calling* paths (messaging, storage-service sync, call-link backup,
// log bridging). This shim provides exactly that surface, with type shapes
// copied faithfully from RingRTC's source so the real Signal Swift compiles
// unmodified. Method bodies that require the native lib are stubbed; nothing
// here is on a messaging/storage code path that needs real calling.
//
// Surface (from RingRTC `CallLinks.swift` / `Logging.swift`):
//   • CallLinkRootKey  — used by MessageReceiver, StorageServiceManager,
//     StorageServiceProto+Sync, AvatarDefaultColorManager, the call-link
//     backup archiver (construct from Data, read `.bytes`).
//   • RingRTCLogLevel + RingRTCLogger + setUpRingRTCLogging — DebugLogger's
//     RingRTC log bridge.
//
import Foundation

// MARK: - CallLinkRootKey  (RingRTC CallLinks.swift)

public struct CallLinkRootKey: CustomStringConvertible {
    public struct ValidationError: Error {
        public init() {}
    }

    public let bytes: Data

    /// Real RingRTC parses a base16 "xxxx-xxxx-…" key through the Rust FFI.
    /// Deferred on Linux — the non-calling SSK paths construct from `Data`.
    public init(_ string: String) throws {
        throw ValidationError()
    }

    /// Store the raw key bytes. Real RingRTC validates length/format via FFI;
    /// that validation is deferred so storage round-trips keys unchanged.
    public init(_ bytes: Data) throws {
        self.bytes = bytes
    }

    public static func generate() -> Self {
        var raw = Data(count: 16)
        for i in raw.indices { raw[i] = UInt8.random(in: .min ... .max) }
        return CallLinkRootKey(unchecked: raw)
    }

    public static func generateAdminPasskey() -> Data {
        var raw = Data(count: 16)
        for i in raw.indices { raw[i] = UInt8.random(in: .min ... .max) }
        return raw
    }

    /// Real derivation is an FFI HKDF over the root key. Deferred — not reached
    /// by the non-calling SSK paths compiled here.
    public func deriveRoomId() -> Data {
        return Data()
    }

    public var description: String {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private init(unchecked bytes: Data) {
        self.bytes = bytes
    }
}

// MARK: - Logging  (RingRTC Logging.swift)

public enum RingRTCLogLevel: UInt8, Comparable {
    case error = 1
    case warn = 2
    case info = 3
    case debug = 4
    case trace = 5

    public static func < (lhs: RingRTCLogLevel, rhs: RingRTCLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public protocol RingRTCLogger: Sendable {
    /// Output a log message at the given level. May be called on any thread.
    func log(level: RingRTCLogLevel, file: String, function: String, line: UInt32, message: String)

    /// Flush the log. May be called before a fatal error.
    func flush()
}

extension RingRTCLogger {
    /// Real RingRTC wires `rtc_log_init` to forward the Rust core's logs into
    /// this logger. Deferred on Linux (no RingRTC native lib) — a no-op until
    /// calling support lands. Signal's DebugLogger calls this at startup.
    public func setUpRingRTCLogging(maxLogLevel: RingRTCLogLevel = .info) {
        // Native RingRTC logging deferred.
    }
}

// MARK: - Group-call peek + ring surface  (RingRTC GroupCall.swift / SFU.swift)
//
// SignalServiceKit's *non-calling* group-call bookkeeping (GroupCallManager,
// GroupCallPeekClient, the CallRecord ring-update handler, CallHTTPClient)
// references the SFU peek client, the ring-update enum, call identifiers, and the
// RingRTC HTTP bridge — even though it never starts an actual call on these code
// paths. All INERT on Linux: peek returns an empty PeekInfo (no call in
// progress), the HTTP client never forwards anything. Real calling needs the
// RingRTC native lib + WebRTC (deferred). HONEST STATUS: group-call peeks always
// report "no active call"; voice/video calling does not work.

// MARK: HTTP bridge (RingRTC HTTPClient.swift)

public enum HTTPMethod: Sendable {
    case get, post, put, delete
}

public final class HTTPRequest: @unchecked Sendable {
    public let method: HTTPMethod
    public let url: String
    public let headers: [String: String]
    public let body: Data?
    public init(method: HTTPMethod, url: String, headers: [String: String], body: Data?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public final class HTTPResponse: @unchecked Sendable {
    public let statusCode: UInt16
    public let body: Data?
    public init(statusCode: UInt16, body: Data?) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol HTTPDelegate: AnyObject {
    func sendRequest(requestId: UInt32, request: HTTPRequest)
}

public final class HTTPClient: @unchecked Sendable {
    public weak var delegate: HTTPDelegate?
    public init() {}
    /// Inert: nothing is ever requested on Linux, so no responses arrive.
    public func receivedResponse(requestId: UInt32, response: HTTPResponse) {}
    public func httpRequestFailed(requestId: UInt32) {}
}

// MARK: Call identifiers (RingRTC)

public struct CallId: Equatable, Hashable, CustomStringConvertible, Sendable {
    public let rawValue: UInt64
    public init(_ rawValue: UInt64) { self.rawValue = rawValue }
    public init(eraId: String) { self.rawValue = callIdFromEra(eraId) }
    public var description: String { String(rawValue) }
}

/// FNV-1a fold of the era string — deterministic + stable within a run (the real
/// RingRTC derivation is an FFI hash; exact value is irrelevant to the
/// non-calling bookkeeping that only compares/logs call ids).
public func callIdFromEra(_ era: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in era.utf8 {
        hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    return hash
}

public func callIdFromRingId(_ ringId: Int64) -> UInt64 {
    UInt64(bitPattern: ringId)
}

// MARK: Ring updates (RingRTC)
//
// EXACTLY the seven cases SSK's GroupCallRecordRingUpdateHandler switches over
// (its switches are exhaustive with no default, so the case set must match).
public enum RingUpdate: Int32, Sendable {
    case requested
    case expiredRing
    case acceptedOnAnotherDevice
    case declinedOnAnotherDevice
    case busyLocally
    case busyOnAnotherDevice
    case cancelledByRinger
}

// MARK: SFU peek (RingRTC SFU.swift)

public struct GroupMemberInfo: Sendable {
    public let userId: UUID
    public let userIdCipherText: Data
    public init(userId: UUID, userIdCipherText: Data) {
        self.userId = userId
        self.userIdCipherText = userIdCipherText
    }
}

/// NOTE: no `callId` member — SSK declares `var callId: CallId?` in its own
/// `private extension PeekInfo` (derived from `eraId`), so a stored one here
/// would collide with that extension.
public struct PeekInfo: Sendable {
    public let joinedMembers: [UUID]
    public let creator: UUID?
    public let eraId: String?
    public let maxDevices: UInt32?
    public let deviceCountIncludingPendingDevices: UInt32
    public let deviceCountExcludingPendingDevices: UInt32
    public let pendingUsers: [UUID]
    public init(
        joinedMembers: [UUID] = [],
        creator: UUID? = nil,
        eraId: String? = nil,
        maxDevices: UInt32? = nil,
        deviceCountIncludingPendingDevices: UInt32 = 0,
        deviceCountExcludingPendingDevices: UInt32 = 0,
        pendingUsers: [UUID] = []
    ) {
        self.joinedMembers = joinedMembers
        self.creator = creator
        self.eraId = eraId
        self.maxDevices = maxDevices
        self.deviceCountIncludingPendingDevices = deviceCountIncludingPendingDevices
        self.deviceCountExcludingPendingDevices = deviceCountExcludingPendingDevices
        self.pendingUsers = pendingUsers
    }
}

public struct PeekRequest: Sendable {
    public let sfuURL: String
    public let membershipProof: Data
    public let groupMembers: [GroupMemberInfo]
    public init(sfuURL: String, membershipProof: Data, groupMembers: [GroupMemberInfo]) {
        self.sfuURL = sfuURL
        self.membershipProof = membershipProof
        self.groupMembers = groupMembers
    }
}

public struct PeekResponse: Sendable {
    public let errorStatusCode: UInt16?
    public let peekInfo: PeekInfo
    public init(errorStatusCode: UInt16? = nil, peekInfo: PeekInfo = PeekInfo()) {
        self.errorStatusCode = errorStatusCode
        self.peekInfo = peekInfo
    }
}

public final class SFUClient: @unchecked Sendable {
    public init(httpClient: HTTPClient) {}
    /// Inert: there is no SFU on Linux, so every peek reports an empty call (no
    /// error, no members) -- callers see "no active group call".
    public func peek(request: PeekRequest) async -> PeekResponse {
        PeekResponse(errorStatusCode: nil, peekInfo: PeekInfo())
    }
}

// MARK: - CallLinkState  (RingRTC CallLinks.swift)
//
// SSK's Calls/CallLinkState.swift wraps this RingRTC type: it reads
// name/restrictions/revoked/expiration/rootKey and maps Restrictions to its own
// Int enum (CallLinkRecord.Restrictions). The real value is produced by the
// RingRTC FFI on the calling paths (deferred on Linux); SSK's non-calling
// call-link backup/storage paths only read these fields. Faithful shape so the
// upstream compiles. Restrictions has EXACTLY the three cases SSK's mapping
// switches over (none/adminApproval/unknown -- exhaustive, no default), so the
// set must match. A memberwise init is provided for completeness, though no
// Linux-compiled path constructs one.
public struct CallLinkState {
    public enum Restrictions {
        case none
        case adminApproval
        case unknown
    }

    public let name: String
    public let restrictions: Restrictions
    public let revoked: Bool
    public let expiration: Date
    public let rootKey: CallLinkRootKey

    public init(
        name: String,
        restrictions: Restrictions,
        revoked: Bool,
        expiration: Date,
        rootKey: CallLinkRootKey
    ) {
        self.name = name
        self.restrictions = restrictions
        self.revoked = revoked
        self.expiration = expiration
        self.rootKey = rootKey
    }
}
