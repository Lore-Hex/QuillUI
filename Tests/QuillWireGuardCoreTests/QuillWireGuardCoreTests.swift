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
            .appendingPathComponent("Sources/QuillWireGuardUI/QuillWireGuardUI.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("public struct WireGuardFallbackConfigurationView"))
        #expect(source.contains("public typealias ContentView = WireGuardFallbackConfigurationView"))
        #expect(source.contains("WireGuardFallbackConfigurationView()"))
        #expect(!source.contains("WireGuardKit not available"))
        #expect(!source.contains("Click + in the sidebar to generate a fresh\\nCurve25519 keypair via upstream WireGuardKit."))
    }

    @Test("WireGuard app entry points share the UI scene helper")
    func wireGuardAppEntryPointsShareUISceneHelper() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillWireGuard/main.swift"),
            encoding: .utf8
        )
        let qtSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillWireGuardQt/main.swift"),
            encoding: .utf8
        )
        let uiSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillWireGuardUI/QuillWireGuardUI.swift"),
            encoding: .utf8
        )
        let helperSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/QuillApp.swift"),
            encoding: .utf8
        )
        let nativeRuntimeSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillWireGuardQtNativeRuntime/QuillWireGuardQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let nativeShimSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillWireGuardQt6Widgets.cpp"),
            encoding: .utf8
        )

        #expect(source.contains("QuillWireGuardScene.scene()"))
        #expect(source.contains("QuillApp.run(QuillWireGuardApp.self)"))
        #expect(qtSource.contains("#if canImport(QuillWireGuardQtNativeRuntime)"))
        #expect(qtSource.contains("QuillWireGuardQtNativeApp.run()"))
        #expect(qtSource.contains("import QuillUIQt"))
        #expect(qtSource.contains("QuillWireGuardScene.scene()"))
        #expect(qtSource.contains("QuillQtApp.run(QuillWireGuardQtApp.self)"))
        #expect(!uiSource.contains("@MainActor\npublic enum QuillWireGuardScene"))
        #expect(uiSource.contains("QuillAppWindow.scene("))
        #expect(uiSource.contains("defaultSizePolicy: .linuxMinimum(width: minimumWidth, height: minimumHeight)"))
        #expect(uiSource.contains("ContentView()"))
        #expect(helperSource.contains("QuillMainActorView.assumeIsolated"))
        #expect(nativeRuntimeSource.contains("QuillWireGuardAppSnapshot.configurationManager"))
        #expect(nativeRuntimeSource.contains("quill_wireguard_qt_run_wireguard_json"))
        #expect(nativeShimSource.contains("QApplication"))
        #expect(nativeShimSource.contains("QLineEdit"))
        #expect(nativeShimSource.contains("QListWidget"))
        #expect(nativeShimSource.contains("QPlainTextEdit"))
        #expect(nativeShimSource.contains("QWidget *tunnelRowWidget"))
        #expect(nativeShimSource.contains("void replaceTunnelName(QJsonArray *tunnels, int row, const QString &name)"))
        #expect(nativeShimSource.contains("void updateTunnelRowName(QListWidget *list, int row, const QString &name)"))
        #expect(nativeShimSource.contains("QObject::connect(name, &QLineEdit::textChanged"))
        #expect(nativeShimSource.contains("stringValue(interfaceObject, \"addressesText\")"))
        #expect(nativeShimSource.contains("QLabel#tunnelStatus, QLabel#tunnelSummary"))
        #expect(nativeShimSource.contains("QLineEdit#detailTitle"))
        #expect(nativeShimSource.contains("list->setItemWidget(item, tunnelRowWidget(tunnel))"))
        #expect(nativeShimSource.contains("const QJsonObject presentation = objectValue(payload, \"presentation\")"))
        #expect(nativeShimSource.contains("presentationValue(presentation, \"sidebarTitle\", \"Tunnels\")"))
        #expect(nativeShimSource.contains("presentationValue(presentation, \"interfaceSectionTitle\", \"Interface\")"))
        #expect(nativeShimSource.contains("presentationValue(presentation, \"tunnelNamePlaceholder\", \"Tunnel name\")"))
        #expect(nativeShimSource.contains("presentationValue(presentation, \"emptyStateTitle\", \"Quill WireGuard\")"))
        #expect(!nativeShimSource.contains("QStringList lines"))
        #expect(!nativeShimSource.contains("QLabel#detailTitle"))
        #expect(nativeShimSource.contains("QSize resolvedMinimumWindowSize"))
        #expect(nativeShimSource.contains("QSize resolvedDefaultWindowSize"))
        #expect(nativeShimSource.contains("intValue(payload, \"minimumWidth\", 900)"))
        #expect(nativeShimSource.contains("intValue(payload, \"minimumHeight\", 600)"))
        #expect(nativeShimSource.contains("std::max(intValue(payload, \"defaultWidth\", minimumSize.width()), minimumSize.width())"))
        #expect(nativeShimSource.contains("std::max(intValue(payload, \"defaultHeight\", minimumSize.height()), minimumSize.height())"))
        #expect(!nativeShimSource.contains("kMinimumAppWidth"))
        #expect(!nativeShimSource.contains("kMinimumAppHeight"))
        #expect(nativeShimSource.contains("window.setMinimumSize(minimumWindowSize)"))
        #expect(nativeShimSource.contains("window.resize(defaultWindowSize)"))
    }

    @Test("WireGuard snapshot preserves shared app presentation for native hosts")
    func wireGuardSnapshotPreservesSharedAppPresentationForNativeHosts() throws {
        let snapshot = QuillWireGuardAppSnapshot.configurationManager

        #expect(snapshot.title == QuillWireGuardAppMetadata.title)
        #expect(snapshot.defaultWidth == Int(QuillWireGuardAppMetadata.defaultWidth))
        #expect(snapshot.defaultHeight == Int(QuillWireGuardAppMetadata.defaultHeight))
        #expect(snapshot.minimumWidth == Int(QuillWireGuardAppMetadata.linuxMinimumWidth))
        #expect(snapshot.minimumHeight == Int(QuillWireGuardAppMetadata.linuxMinimumHeight))
        #expect(snapshot.presentation.sidebarTitle == QuillWireGuardPresentation.sidebarTitle)
        #expect(snapshot.presentation.backendTitle == QuillWireGuardPresentation.backendTitle)
        #expect(snapshot.presentation.interfaceSectionTitle == QuillWireGuardPresentation.interfaceSectionTitle)
        #expect(snapshot.presentation.exportSectionTitle == QuillWireGuardPresentation.exportSectionTitle)
        #expect(snapshot.presentation.noneText == QuillWireGuardPresentation.noneText)
        #expect(snapshot.selectedTunnelID == QuillWireGuardFixtures.defaultTunnelID)
        #expect(snapshot.tunnels.map(\.id) == QuillWireGuardFixtures.tunnels.map(\.id))
        #expect(snapshot.tunnels.first?.interface.addressesText == QuillWireGuardFixtures.tunnels.first?.interface.addresses.joined(separator: ", "))
        #expect(snapshot.tunnels.first?.peerSummary == QuillWireGuardFixtures.tunnels.first?.peerSummary)
        #expect(snapshot.tunnels.first?.wgQuickConfig == QuillWireGuardFixtures.tunnels.first?.wgQuickConfig())

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(QuillWireGuardAppSnapshot.self, from: encoded)
        #expect(decoded == snapshot)

        let legacyPayload = """
        {
          "title": "\(QuillWireGuardAppMetadata.title)",
          "defaultWidth": \(Int(QuillWireGuardAppMetadata.defaultWidth)),
          "defaultHeight": \(Int(QuillWireGuardAppMetadata.defaultHeight)),
          "minimumWidth": \(Int(QuillWireGuardAppMetadata.linuxMinimumWidth)),
          "minimumHeight": \(Int(QuillWireGuardAppMetadata.linuxMinimumHeight)),
          "backendStatusText": "Legacy backend status",
          "selectedTunnelID": null,
          "tunnels": []
        }
        """.data(using: .utf8)!
        let legacySnapshot = try JSONDecoder().decode(QuillWireGuardAppSnapshot.self, from: legacyPayload)
        #expect(legacySnapshot.presentation == QuillWireGuardPresentationSnapshot())
        #expect(legacySnapshot.tunnels.isEmpty)
    }

    @Test("Qt WireGuard manifest uses an explicit Linux backend graph selector")
    func qtWireGuardManifestUsesExplicitLinuxBackendGraphSelector() throws {
        let manifest = try String(
            contentsOf: try packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(manifest.contains("QUILLUI_LINUX_BACKEND"))
        #expect(manifest.contains("case \"qt\", \"qt6\""))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .qt && !qt6WidgetsPresent"))
        #expect(manifest.contains("let quillWireGuardQtDependencies: [Target.Dependency] = quillUILinuxBuildBackend == .qt"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .qt"))
        #expect(!manifest.contains("let quillWireGuardQtDependencies: [Target.Dependency] = qt6WidgetsPresent"))
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
