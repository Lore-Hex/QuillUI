import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard config round-trip fidelity")
struct QuillWireGuardConfigFidelityTests {

    private let config = """
    [Interface]
    PrivateKey = aabbccdd
    Address = 10.0.0.2/32
    Table = off
    PostUp = iptables -A FORWARD -i %i -j ACCEPT
    PostDown = iptables -D FORWARD -i %i -j ACCEPT
    FwMark = 0x1234

    [Peer]
    PublicKey = peerpubkey=
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    SomeFutureField = value123
    """

    @Test("unmodeled interface + peer fields are preserved, not dropped")
    func preservesUnknownFields() throws {
        let tunnel = try QuillWireGuardConfigParser.parse(config, id: "t", name: "t")
        #expect(tunnel.interface.extraConfigLines.contains("Table = off"))
        #expect(tunnel.interface.extraConfigLines.contains("PostUp = iptables -A FORWARD -i %i -j ACCEPT"))
        #expect(tunnel.interface.extraConfigLines.contains("PostDown = iptables -D FORWARD -i %i -j ACCEPT"))
        #expect(tunnel.interface.extraConfigLines.contains("FwMark = 0x1234"))
        // Known fields still parse into their typed slots.
        #expect(tunnel.interface.addresses == ["10.0.0.2/32"])
        #expect(tunnel.peers[0].extraConfigLines.contains("SomeFutureField = value123"))
        #expect(tunnel.peers[0].persistentKeepAlive == 25)
    }

    @Test("wgQuickConfig re-emits preserved fields, and re-parsing is idempotent")
    func roundTripsThroughGeneration() throws {
        let tunnel = try QuillWireGuardConfigParser.parse(config, id: "t", name: "t")
        let generated = tunnel.wgQuickConfig()
        for line in [
            "Table = off",
            "PostUp = iptables -A FORWARD -i %i -j ACCEPT",
            "PostDown = iptables -D FORWARD -i %i -j ACCEPT",
            "FwMark = 0x1234",
            "SomeFutureField = value123",
        ] {
            #expect(generated.contains(line), "round-trip dropped: \(line)")
        }
        let reparsed = try QuillWireGuardConfigParser.parse(generated, id: "t", name: "t")
        #expect(reparsed.interface.extraConfigLines.contains("PostUp = iptables -A FORWARD -i %i -j ACCEPT"))
        #expect(reparsed.peers[0].extraConfigLines.contains("SomeFutureField = value123"))
    }

    @Test("a fully-modeled config yields empty extraConfigLines")
    func noExtrasWhenAllModeled() throws {
        let plain = """
        [Interface]
        PrivateKey = key
        Address = 10.0.0.2/32

        [Peer]
        PublicKey = pub=
        AllowedIPs = 0.0.0.0/0
        """
        let tunnel = try QuillWireGuardConfigParser.parse(plain, id: "t", name: "t")
        #expect(tunnel.interface.extraConfigLines.isEmpty)
        #expect(tunnel.peers[0].extraConfigLines.isEmpty)
    }
}
