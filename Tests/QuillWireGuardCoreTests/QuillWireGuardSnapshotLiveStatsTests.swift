import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard tunnel snapshot live stats")
struct QuillWireGuardSnapshotLiveStatsTests {

    private func tunnel(peerPublicKey: String) -> QuillWireGuardTunnel {
        QuillWireGuardTunnel(
            id: "t1", name: "Home", status: .active,
            interface: QuillWireGuardInterface(privateKey: "k", publicKey: "ip", addresses: ["10.0.0.2/32"], dnsServers: []),
            peers: [QuillWireGuardPeer(id: "t1-p1", name: "Edge", publicKey: peerPublicKey, allowedIPs: ["0.0.0.0/0"])]
        )
    }

    @Test("snapshot carries live stats matched by peer public key")
    func snapshotCarriesLiveStats() {
        let live = QuillWireGuardLiveStatus(isActive: true, peers: [
            QuillWireGuardLivePeerStats(publicKey: "peerpub=", transferRxText: "1.50 KiB", transferTxText: "1.00 MiB", latestHandshakeText: "2 minutes ago")
        ])
        let snapshot = QuillWireGuardTunnelSnapshot(tunnel: tunnel(peerPublicKey: "peerpub="), liveStatus: live)
        #expect(snapshot.peers[0].transferRxText == "1.50 KiB")
        #expect(snapshot.peers[0].transferTxText == "1.00 MiB")
        #expect(snapshot.peers[0].latestHandshakeText == "2 minutes ago")
    }

    @Test("snapshot has no live stats without a live status (static config view)")
    func snapshotNoLiveStatsByDefault() {
        let snapshot = QuillWireGuardTunnelSnapshot(tunnel: tunnel(peerPublicKey: "peerpub="))
        #expect(snapshot.peers[0].transferRxText == nil)
        #expect(snapshot.peers[0].transferTxText == nil)
        #expect(snapshot.peers[0].latestHandshakeText == nil)
    }

    @Test("a live peer that doesn't match a config peer leaves it without live stats")
    func unmatchedLivePeer() {
        let live = QuillWireGuardLiveStatus(isActive: true, peers: [
            QuillWireGuardLivePeerStats(publicKey: "OTHER=", transferRxText: "1 B", transferTxText: "2 B", latestHandshakeText: "Never")
        ])
        let snapshot = QuillWireGuardTunnelSnapshot(tunnel: tunnel(peerPublicKey: "configpub="), liveStatus: live)
        #expect(snapshot.peers[0].transferRxText == nil)
    }
}
