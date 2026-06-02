import Foundation
import Testing
@testable import QuillWireGuardCore

/// End-to-end proof of the WireGuard connect path against a REAL tunnel. CI has no
/// `wg` / kernel module, so this is gated on `QUILLUI_WG_E2E=1` (skipped everywhere
/// except a privileged Linux host with wireguard-tools, e.g. `docker run --privileged`).
/// It compiles in CI (so it can't rot) but only runs when explicitly enabled.
///
/// Run it:
///   docker run --rm --privileged -v "$PWD:/src:ro" swift:6.2-noble sh -c '
///     apt-get update -qq && apt-get install -y -qq wireguard-tools iproute2
///     git clone -q /src /w && cd /w
///     QUILLUI_WG_E2E=1 swift test --filter QuillWireGuardEndToEndTests'
@Suite("QuillWireGuard end-to-end (real wg-quick)")
struct QuillWireGuardEndToEndTests {

    @Test(
        "key-gen -> activate -> live status sees it up -> deactivate -> down",
        .enabled(if: ProcessInfo.processInfo.environment["QUILLUI_WG_E2E"] == "1")
    )
    func connectPathAgainstRealTunnel() throws {
        let runner = QuillWireGuardProcessRunner()

        // 1. Real keypair via `wg genkey` / `wg pubkey` (exercises QuillWireGuardKeyService).
        let keys = try QuillWireGuardKeyService.generateKeyPair(runner: runner)
        #expect(!keys.privateKey.isEmpty)
        #expect(!keys.publicKey.isEmpty)

        let tunnel = QuillWireGuardTunnel(
            id: "e2e",
            name: "wge2e",
            status: .inactive,
            interface: QuillWireGuardInterface(
                privateKey: keys.privateKey,
                publicKey: keys.publicKey,
                addresses: ["10.99.0.1/24"],
                dnsServers: []
            ),
            peers: []
        )
        // No systemd in the container, so drive wg-quick directly.
        let controller = QuillWireGuardRuntimeController(runner: runner, useSystemd: false)
        let interface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: tunnel.name)
        try? controller.deactivate(interface: interface)  // clear any leftover
        defer { try? QuillWireGuardActivationService.deactivate(tunnelNamed: tunnel.name, controller: controller) }

        // 2. Activate: install the config + `wg-quick up` (the exact chain the connect button runs).
        try QuillWireGuardActivationService.activate(tunnel: tunnel, controller: controller)

        // 3. Live status must now report the interface up.
        let up = QuillWireGuardLiveStatusService.liveStatus(forTunnelNamed: tunnel.name, controller: controller, now: Date())
        #expect(up.isActive == true, "tunnel should be active after activate")

        // 4. Deactivate, then live status must report inactive.
        try QuillWireGuardActivationService.deactivate(tunnelNamed: tunnel.name, controller: controller)
        let down = QuillWireGuardLiveStatusService.liveStatus(forTunnelNamed: tunnel.name, controller: controller, now: Date())
        #expect(down == .inactive, "tunnel should be inactive after deactivate")
    }
}
