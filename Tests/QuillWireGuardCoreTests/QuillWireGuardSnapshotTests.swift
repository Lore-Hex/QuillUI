import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard snapshot Qt-payload fields")
struct QuillWireGuardSnapshotTests {

    @Test("interface snapshot carries MTU text only when set")
    func interfaceSnapshotMTU() {
        let withMTU = QuillWireGuardInterface(
            privateKey: "k", publicKey: "p", addresses: ["10.0.0.2/32"], dnsServers: [],
            listenPort: 51820, mtu: 1380
        )
        #expect(QuillWireGuardInterfaceSnapshot(interface: withMTU).mtuText == "1380")

        let withoutMTU = QuillWireGuardInterface(
            privateKey: "k", publicKey: "p", addresses: ["10.0.0.2/32"], dnsServers: []
        )
        #expect(QuillWireGuardInterfaceSnapshot(interface: withoutMTU).mtuText == nil)
    }

    @Test("peer snapshot shows 'enabled' for a preshared key, nil otherwise")
    func peerSnapshotPresharedKey() {
        let withPSK = QuillWireGuardPeer(
            id: "t-1", name: "Peer", publicKey: "pk", allowedIPs: ["0.0.0.0/0"], preSharedKey: "secret="
        )
        #expect(QuillWireGuardPeerSnapshot(peer: withPSK).preSharedKeyText == "enabled")

        let withoutPSK = QuillWireGuardPeer(
            id: "t-1", name: "Peer", publicKey: "pk", allowedIPs: ["0.0.0.0/0"]
        )
        #expect(QuillWireGuardPeerSnapshot(peer: withoutPSK).preSharedKeyText == nil)
    }
}
