import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard wg-show status parser")
struct QuillWireGuardStatusParserTests {

    @Test("parses wg show dump into per-peer runtime stats")
    func parsesDumpIntoRuntimeStats() {
        let dump = [
            "device-private-key=\tdevice-public-key=\t51820\toff",
            "peer-one-public-key=\t(none)\t203.0.113.5:51820\t0.0.0.0/0, ::/0\t1717171717\t1024\t2048\t25",
            "peer-two-public-key=\t(none)\t(none)\t10.7.0.0/24\t0\t0\t0\toff",
        ].joined(separator: "\n")

        let status = QuillWireGuardStatusParser.parse(dump: dump)
        #expect(status?.interfacePublicKey == "device-public-key=")
        #expect(status?.listenPort == 51820)
        #expect(status?.peers.count == 2)
        #expect(status?.hasHandshake == true)

        let active = status?.peers[0]
        #expect(active?.publicKey == "peer-one-public-key=")
        #expect(active?.endpoint == "203.0.113.5:51820")
        #expect(active?.rxBytes == 1024)
        #expect(active?.txBytes == 2048)
        #expect(active?.persistentKeepAlive == 25)
        #expect(active?.latestHandshake == Date(timeIntervalSince1970: 1717171717))

        // Sentinels: (none) endpoint -> nil, 0 handshake -> nil, off keepalive -> nil.
        let idle = status?.peers[1]
        #expect(idle?.endpoint == nil)
        #expect(idle?.latestHandshake == nil)
        #expect(idle?.rxBytes == 0)
        #expect(idle?.persistentKeepAlive == nil)
    }

    @Test("returns nil when no interface line is present")
    func returnsNilForEmptyDump() {
        #expect(QuillWireGuardStatusParser.parse(dump: "") == nil)
        #expect(QuillWireGuardStatusParser.parse(dump: "\n  \n") == nil)
    }

    @Test("ignores malformed peer lines but keeps valid ones")
    func ignoresMalformedPeerLines() {
        let dump = [
            "priv=\tpub=\t51820\toff",
            "too\tfew\tfields",
            "good-peer=\t(none)\t(none)\t0.0.0.0/0\t0\t10\t20\toff",
        ].joined(separator: "\n")

        let status = QuillWireGuardStatusParser.parse(dump: dump)
        #expect(status?.peers.count == 1)
        #expect(status?.peers[0].publicKey == "good-peer=")
        #expect(status?.peers[0].txBytes == 20)
        #expect(status?.hasHandshake == false)
    }
}
