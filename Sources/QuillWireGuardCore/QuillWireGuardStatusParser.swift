import Foundation

/// Live runtime stats for a single peer, parsed from `wg show <iface> dump`.
/// Mirrors the runtime fields upstream WireGuardKit exposes on `PeerConfiguration`
/// (`rxBytes` / `txBytes` / `lastHandshakeTime`), which QuillWireGuard's static
/// config model intentionally omits.
public struct QuillWireGuardPeerRuntime: Codable, Hashable, Sendable {
    public let publicKey: String
    public var endpoint: String?
    public var latestHandshake: Date?
    public var rxBytes: UInt64
    public var txBytes: UInt64
    public var persistentKeepAlive: UInt16?

    public init(
        publicKey: String,
        endpoint: String? = nil,
        latestHandshake: Date? = nil,
        rxBytes: UInt64 = 0,
        txBytes: UInt64 = 0,
        persistentKeepAlive: UInt16? = nil
    ) {
        self.publicKey = publicKey
        self.endpoint = endpoint
        self.latestHandshake = latestHandshake
        self.rxBytes = rxBytes
        self.txBytes = txBytes
        self.persistentKeepAlive = persistentKeepAlive
    }
}

/// Live runtime status for an interface, parsed from `wg show <iface> dump`.
/// The presence of an interface line means the tunnel is up.
public struct QuillWireGuardRuntimeStatus: Codable, Hashable, Sendable {
    public let interfacePublicKey: String
    public var listenPort: UInt16?
    public var peers: [QuillWireGuardPeerRuntime]

    public init(
        interfacePublicKey: String,
        listenPort: UInt16? = nil,
        peers: [QuillWireGuardPeerRuntime] = []
    ) {
        self.interfacePublicKey = interfacePublicKey
        self.listenPort = listenPort
        self.peers = peers
    }

    /// True once at least one peer has a recorded handshake (i.e. traffic has flowed).
    public var hasHandshake: Bool {
        peers.contains { $0.latestHandshake != nil }
    }
}

/// Parses `wg show <interface> dump` — the stable, script-friendly status format.
///
/// Tab-separated. The first line describes the interface:
///   `private-key  public-key  listen-port  fwmark`
/// Each subsequent line describes a peer:
///   `public-key  preshared-key  endpoint  allowed-ips  latest-handshake  rx  tx  keepalive`
/// Sentinels `(none)` / `off` / `0` map to nil / 0. Returns nil when there is no
/// interface line (the tunnel is down / `wg show` produced nothing).
///
/// This is pure text parsing — no privileges or kernel module required — so it is
/// fully unit-testable. Acquiring the dump (running `wg`) is a later runtime slice.
public enum QuillWireGuardStatusParser {
    public static func parse(dump: String) -> QuillWireGuardRuntimeStatus? {
        let lines = dump
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let interfaceLine = lines.first else { return nil }

        let interfaceFields = interfaceLine.components(separatedBy: "\t")
        guard interfaceFields.count >= 2, !interfaceFields[1].isEmpty else { return nil }

        return QuillWireGuardRuntimeStatus(
            interfacePublicKey: interfaceFields[1],
            listenPort: interfaceFields.count >= 3 ? UInt16(interfaceFields[2]) : nil,
            peers: lines.dropFirst().compactMap(parsePeerLine)
        )
    }

    private static func parsePeerLine(_ line: String) -> QuillWireGuardPeerRuntime? {
        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 8, !fields[0].isEmpty else { return nil }
        return QuillWireGuardPeerRuntime(
            publicKey: fields[0],
            endpoint: sentinelOrValue(fields[2]),
            latestHandshake: handshakeDate(fields[4]),
            rxBytes: UInt64(fields[5]) ?? 0,
            txBytes: UInt64(fields[6]) ?? 0,
            persistentKeepAlive: fields[7] == "off" ? nil : UInt16(fields[7])
        )
    }

    private static func sentinelOrValue(_ value: String) -> String? {
        (value.isEmpty || value == "(none)") ? nil : value
    }

    private static func handshakeDate(_ value: String) -> Date? {
        guard let seconds = TimeInterval(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
