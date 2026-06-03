import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard app snapshot live builder")
struct QuillWireGuardAppSnapshotLiveTests {

    final class StubRunner: QuillWireGuardCommandRunner, @unchecked Sendable {
        let output: String
        init(output: String) { self.output = output }
        func run(_ command: QuillWireGuardCommand) throws -> String { output }
    }

    @Test("configurationManager carries no live stats (static config view)")
    func staticHasNoLiveStats() {
        for tunnel in QuillWireGuardAppSnapshot.configurationManager.tunnels {
            for peer in tunnel.peers {
                #expect(peer.transferRxText == nil)
                #expect(peer.latestHandshakeText == nil)
            }
        }
    }

    @Test("liveConfigurationManager degrades to no live stats when tunnels are down")
    func liveDownHasNoStats() {
        let controller = QuillWireGuardRuntimeController(runner: StubRunner(output: ""))
        let snap = QuillWireGuardAppSnapshot.liveConfigurationManager(controller: controller, now: Date())
        #expect(snap.tunnels.count == QuillWireGuardAppSnapshot.configurationManager.tunnels.count)
        for tunnel in snap.tunnels {
            for peer in tunnel.peers { #expect(peer.transferRxText == nil) }
        }
    }

    @Test("liveConfigurationManager attaches live stats to a matching fixture peer")
    func liveAttachesToMatchingPeer() {
        guard let fixture = QuillWireGuardFixtures.tunnels.first(where: { !$0.peers.isEmpty }) else {
            Issue.record("expected a fixture tunnel with at least one peer")
            return
        }
        let peerKey = fixture.peers[0].publicKey
        // A wg dump whose single peer line carries the fixture peer's public key, so
        // the live stats attach to that exact peer in the resulting snapshot.
        let dump = "priv=\tpub=\t51820\toff\n\(peerKey)\t(none)\t1.2.3.4:51820\t0.0.0.0/0\t1700000000\t2048\t4096\t25"
        let controller = QuillWireGuardRuntimeController(runner: StubRunner(output: dump))
        let snap = QuillWireGuardAppSnapshot.liveConfigurationManager(
            controller: controller, now: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let peerSnap = snap.tunnels
            .first(where: { $0.name == fixture.name })?
            .peers.first(where: { $0.publicKey == peerKey })
        #expect(peerSnap?.transferRxText != nil)
        #expect(peerSnap?.transferTxText != nil)
        #expect(peerSnap?.latestHandshakeText != nil)
    }
}
