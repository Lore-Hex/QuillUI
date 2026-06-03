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
