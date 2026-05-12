import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuardCore fixture model")
struct QuillWireGuardCoreTests {

    @Test("Fixture tunnels are non-empty with unique ids")
    func fixtureTunnelsAreNonEmptyWithUniqueIDs() {
        let tunnels = QuillWireGuardFixtures.tunnels
        #expect(!tunnels.isEmpty)
        #expect(Set(tunnels.map(\.id)).count == tunnels.count)
        #expect(QuillWireGuardFixtures.defaultTunnelID == tunnels.first?.id)
    }

    @Test("Fixture tunnels carry render-facing interface and peer data")
    func fixtureTunnelsCarryRenderFacingData() {
        for tunnel in QuillWireGuardFixtures.tunnels {
            #expect(!tunnel.name.isEmpty)
            #expect(!tunnel.interface.privateKey.isEmpty)
            #expect(!tunnel.interface.publicKey.isEmpty)
            #expect(!tunnel.interface.addresses.isEmpty)
            #expect(!tunnel.peers.isEmpty)

            for peer in tunnel.peers {
                #expect(!peer.name.isEmpty)
                #expect(!peer.publicKey.isEmpty)
                #expect(!peer.allowedIPs.isEmpty)
            }
        }
    }

    @Test("wg-quick export contains interface and peer sections")
    func wgQuickExportContainsInterfaceAndPeerSections() {
        let tunnel = QuillWireGuardFixtures.tunnels[0]
        let config = tunnel.wgQuickConfig()

        #expect(config.contains("[Interface]"))
        #expect(config.contains("PrivateKey = \(tunnel.interface.privateKey)"))
        #expect(config.contains("Address = \(tunnel.interface.addresses.joined(separator: ", "))"))
        #expect(config.contains("[Peer]"))
        #expect(config.contains("# Name = \(tunnel.peers[0].name)"))
        #expect(config.contains("PublicKey = \(tunnel.peers[0].publicKey)"))
        #expect(config.contains("AllowedIPs = \(tunnel.peers[0].allowedIPs.joined(separator: ", "))"))
        #expect(!config.localizedCaseInsensitiveContains("placeholder"))
        #expect(!config.localizedCaseInsensitiveContains("stub"))
    }

    @Test("Backend availability is explicit per platform")
    func backendAvailabilityIsExplicitPerPlatform() {
        #if os(Linux)
        #expect(!QuillWireGuardBackend.isAvailable)
        #else
        #expect(QuillWireGuardBackend.isAvailable)
        #endif
        #expect(!QuillWireGuardBackend.statusText.isEmpty)
    }

    @Test("Fallback platforms share the fixture-backed configuration shell")
    func fallbackPlatformsShareFixtureBackedConfigurationShell() throws {
        let sourceURL = try packageRoot()
            .appendingPathComponent("Sources/QuillWireGuard/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("struct WireGuardFallbackConfigurationView"))
        #expect(source.contains("typealias ContentView = WireGuardFallbackConfigurationView"))
        #expect(source.contains("WireGuardFallbackConfigurationView()"))
        #expect(!source.contains("WireGuardKit not available"))
        #expect(!source.contains("Click + in the sidebar to generate a fresh\\nCurve25519 keypair via upstream WireGuardKit."))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()

        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }

        throw SourceHygieneError.packageRootNotFound
    }
}

private enum SourceHygieneError: Error {
    case packageRootNotFound
}
