import Foundation

/// Display-ready live stats for one peer (formatted strings, ready for the detail UI
/// or the Qt payload). Built from `QuillWireGuardPeerRuntime` via
/// `QuillWireGuardRuntimeFormatter`.
public struct QuillWireGuardLivePeerStats: Equatable, Sendable {
    public let publicKey: String
    public let transferRxText: String
    public let transferTxText: String
    public let latestHandshakeText: String

    public init(publicKey: String, transferRxText: String, transferTxText: String, latestHandshakeText: String) {
        self.publicKey = publicKey
        self.transferRxText = transferRxText
        self.transferTxText = transferTxText
        self.latestHandshakeText = latestHandshakeText
    }
}

/// Display-ready live status for a tunnel: whether it's up + per-peer stats.
public struct QuillWireGuardLiveStatus: Equatable, Sendable {
    public let isActive: Bool
    public let peers: [QuillWireGuardLivePeerStats]

    public init(isActive: Bool, peers: [QuillWireGuardLivePeerStats]) {
        self.isActive = isActive
        self.peers = peers
    }

    /// A tunnel that is down / has no live status.
    public static let inactive = QuillWireGuardLiveStatus(isActive: false, peers: [])
}

/// Bridges the merged runtime (controller -> parser) to the display layer: maps a
/// tunnel's name to a wg interface, fetches its live status, and formats it. This is
/// the data-flow seam the live UI (and a headless caller) consume. Pure given a
/// runner, so it is unit-testable with a stub and VM-demonstrable with the real
/// `QuillWireGuardProcessRunner` against an up tunnel.
public enum QuillWireGuardLiveStatusService {

    /// Derive a valid wg interface name from a tunnel's display name: lowercase, keep
    /// only kernel/wg-quick-legal chars, cap at 15, falling back to "wg0". The result
    /// always satisfies `QuillWireGuardLinuxAdapter.isValidInterfaceName`.
    public static func interfaceName(forTunnelNamed name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_=+.-")
        let filtered = String(name.lowercased().filter { allowed.contains($0) }.prefix(15))
        if filtered.isEmpty || filtered == "." || filtered == ".." {
            return "wg0"
        }
        return filtered
    }

    /// Fetch + format the live status for the named tunnel via the controller.
    /// Returns `.inactive` when the tunnel is down or `wg show` fails (e.g. not up).
    public static func liveStatus<Runner: QuillWireGuardCommandRunner>(
        forTunnelNamed name: String,
        controller: QuillWireGuardRuntimeController<Runner>,
        now: Date
    ) -> QuillWireGuardLiveStatus {
        let interface = interfaceName(forTunnelNamed: name)
        // `try?` flattens the throwing call + the optional return: nil means the
        // command failed OR the tunnel is down; non-nil is the live status.
        guard let status = try? controller.currentStatus(interface: interface) else {
            return .inactive
        }
        let peers = status.peers.map { peer in
            QuillWireGuardLivePeerStats(
                publicKey: peer.publicKey,
                transferRxText: QuillWireGuardRuntimeFormatter.transferText(peer.rxBytes),
                transferTxText: QuillWireGuardRuntimeFormatter.transferText(peer.txBytes),
                latestHandshakeText: QuillWireGuardRuntimeFormatter.handshakeText(peer.latestHandshake, now: now)
            )
        }
        return QuillWireGuardLiveStatus(isActive: true, peers: peers)
    }
}
