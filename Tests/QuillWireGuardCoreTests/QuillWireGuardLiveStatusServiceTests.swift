import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard live status service")
struct QuillWireGuardLiveStatusServiceTests {

    final class StubRunner: QuillWireGuardCommandRunner, @unchecked Sendable {
        let output: String
        init(output: String) { self.output = output }
        func run(_ command: QuillWireGuardCommand) throws -> String { output }
    }

    @Test("derives a valid wg interface name from a tunnel display name")
    func interfaceNames() {
        #expect(QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: "Home Lab") == "homelab")
        #expect(QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: "wgtest") == "wgtest")
        #expect(QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: "A/B C!") == "abc")
        #expect(QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: "") == "wg0")
        #expect(QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: String(repeating: "x", count: 30)).count == 15)
        // Whatever the input, the result is always a legal wg interface name.
        for name in ["Home Lab", "", "A/B C!", "\u{043a}\u{043e}\u{0440}\u{043f}", "....", "WG-0"] {
            let iface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: name)
            #expect(QuillWireGuardLinuxAdapter.isValidInterfaceName(iface), "invalid iface '\(iface)' from '\(name)'")
        }
    }

    @Test("formats live status fetched via the controller")
    func liveStatusFromDump() {
        let dump = "priv=\tpub=\t51820\toff\npeerpub=\t(none)\t1.2.3.4:51820\t0.0.0.0/0\t0\t1536\t1048576\t25"
        let controller = QuillWireGuardRuntimeController(runner: StubRunner(output: dump))
        let status = QuillWireGuardLiveStatusService.liveStatus(
            forTunnelNamed: "wgtest", controller: controller, now: Date(timeIntervalSince1970: 2_000_000_000)
        )
        #expect(status.isActive == true)
        #expect(status.peers.count == 1)
        #expect(status.peers[0].transferRxText == "1.50 KiB")  // 1536 bytes
        #expect(status.peers[0].transferTxText == "1.00 MiB")  // 1048576 bytes
        #expect(status.peers[0].latestHandshakeText == "Never") // handshake "0"
    }

    @Test("inactive when the tunnel is down")
    func inactiveWhenDown() {
        let controller = QuillWireGuardRuntimeController(runner: StubRunner(output: ""))
        let status = QuillWireGuardLiveStatusService.liveStatus(forTunnelNamed: "wgtest", controller: controller, now: Date())
        #expect(status == .inactive)
    }
}
