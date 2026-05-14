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

    @Test("wg-quick import round-trips exported fixture configuration")
    func wgQuickImportRoundTripsExportedFixtureConfiguration() throws {
        let fixture = QuillWireGuardFixtures.tunnels[0]
        let parsed = try QuillWireGuardConfigParser.parse(
            fixture.wgQuickConfig(),
            id: fixture.id,
            name: fixture.name,
            status: fixture.status,
            interfacePublicKey: fixture.interface.publicKey
        )

        #expect(parsed.id == fixture.id)
        #expect(parsed.name == fixture.name)
        #expect(parsed.status == fixture.status)
        #expect(parsed.interface == fixture.interface)
        #expect(parsed.peers.map(\.name) == fixture.peers.map(\.name))
        #expect(parsed.peers.map(\.publicKey) == fixture.peers.map(\.publicKey))
        #expect(parsed.peers.map(\.allowedIPs) == fixture.peers.map(\.allowedIPs))
        #expect(parsed.peers.map(\.endpoint) == fixture.peers.map(\.endpoint))
        #expect(parsed.peers.map(\.persistentKeepAlive) == fixture.peers.map(\.persistentKeepAlive))
        #expect(parsed.wgQuickConfig() == fixture.wgQuickConfig())
    }

    @Test("wg-quick import handles comments and comma-separated values")
    func wgQuickImportHandlesCommentsAndCommaSeparatedValues() throws {
        let parsed = try QuillWireGuardConfigParser.parse(
            try sharedImportSmokeConfiguration(),
            id: "imported-home",
            name: "Imported Home",
            status: .needsBackend
        )

        #expect(parsed.id == "imported-home")
        #expect(parsed.name == "Imported Home")
        #expect(parsed.status == .needsBackend)
        #expect(parsed.interface.privateKey == "imported-private-key=")
        #expect(parsed.interface.publicKey == "imported-public-key=")
        #expect(parsed.interface.addresses == ["10.44.0.2/32", "fd44::2/128"])
        #expect(parsed.interface.dnsServers == ["1.1.1.1", "2606:4700:4700::1111"])
        #expect(parsed.interface.listenPort == 51820)
        #expect(parsed.peers.count == 1)
        #expect(parsed.peers[0].id == "imported-home-peer-1")
        #expect(parsed.peers[0].name == "Imported Edge")
        #expect(parsed.peers[0].publicKey == "imported-peer-public-key=")
        #expect(parsed.peers[0].allowedIPs == ["0.0.0.0/0", "::/0"])
        #expect(parsed.peers[0].endpoint == "vpn.example.com:51820")
        #expect(parsed.peers[0].persistentKeepAlive == 25)
    }

    @Test("wg-quick import reports structural errors")
    func wgQuickImportReportsStructuralErrors() throws {
        var error = parseError(for: "[Peer]\nPublicKey = peer")
        #expect(error == .missingInterface)

        error = parseError(for: "[Interface]\nAddress = 10.0.0.2/32")
        #expect(error == .missingInterfacePrivateKey)

        error = parseError(for: "[Interface]\nPrivateKey = key\n\n[Peer]\nAllowedIPs = 0.0.0.0/0")
        #expect(error == .missingPeerPublicKey(index: 1))

        error = parseError(for: "[Interface]\nPrivateKey = key\nListenPort = 999999")
        #expect(error == .invalidInteger(field: "ListenPort", value: "999999", line: 3))

        error = parseError(for: "PrivateKey = key\n[Interface]")
        #expect(error == .keyValueOutsideSection(line: 1, key: "PrivateKey"))
    }

    @Test("Import service returns render-ready snapshots and parse errors")
    func importServiceReturnsRenderReadySnapshotsAndParseErrors() throws {
        let fixture = QuillWireGuardFixtures.tunnels[0]
        let imported = QuillWireGuardImportService.importConfiguration(
            fixture.wgQuickConfig(),
            id: QuillWireGuardImportService.tunnelID(existingTunnelCount: 2),
            name: QuillWireGuardImportService.tunnelName(existingTunnelCount: 2)
        )

        #expect(imported.errorText == nil)
        #expect(imported.tunnel?.id == "imported-tunnel-3")
        #expect(imported.tunnel?.name == "Imported Tunnel 3")
        #expect(imported.tunnel?.statusText == QuillWireGuardTunnelStatus.needsBackend.rawValue)
        #expect(imported.tunnel?.interface.addressesText == fixture.interface.addresses.joined(separator: ", "))
        #expect(imported.tunnel?.peers.first?.publicKey == fixture.peers.first?.publicKey)
        #expect(imported.tunnel?.wgQuickConfig.contains("[Interface]") == true)

        let importedTunnel = try QuillWireGuardImportService.importTunnel(
            fixture.wgQuickConfig(),
            id: "gtk-import",
            name: "GTK Import"
        )
        #expect(importedTunnel.id == "gtk-import")
        #expect(importedTunnel.name == "GTK Import")
        #expect(importedTunnel.interface.privateKey == fixture.interface.privateKey)

        #expect(throws: QuillWireGuardImportError.emptyConfiguration) {
            try QuillWireGuardImportService.importTunnel(
                "  \n\t",
                id: "empty-import",
                name: "Empty Import"
            )
        }

        let failed = QuillWireGuardImportService.importConfiguration(
            "[Peer]\nPublicKey = peer",
            id: "bad-import",
            name: "Bad Import"
        )

        #expect(failed.tunnel == nil)
        #expect(failed.errorText == QuillWireGuardConfigParseError.missingInterface.description)
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
        #expect(source.contains("TextEditor(text: $importConfigurationText)"))
        #expect(source.contains("QuillFileImporter.selectURL(allowedContentTypes: [])"))
        #expect(source.contains("QuillWireGuardImportService.importTunnel"))
        #expect(source.contains("QuillWireGuardPresentation.importButtonLabel"))
        #expect(source.contains("importErrorText"))
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
        let nativeShimHeaderSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/include/CQuillQt6WidgetsShim.h"),
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
        #expect(nativeRuntimeSource.contains("@_cdecl(\"quill_wireguard_qt_import_config_json\")"))
        #expect(nativeRuntimeSource.contains("QuillWireGuardImportService.importConfiguration"))
        #expect(nativeRuntimeSource.contains("quill_wireguard_qt_free_string"))
        #expect(nativeRuntimeSource.contains("QuillWireGuardPresentation.importMissingConfigurationError"))
        #expect(nativeShimHeaderSource.contains("quill_wireguard_qt_import_config_callback"))
        #expect(nativeShimHeaderSource.contains("quill_wireguard_qt_free_string_callback"))
        #expect(nativeShimSource.contains("QApplication"))
        #expect(nativeShimSource.contains("QLineEdit"))
        #expect(nativeShimSource.contains("QListWidget"))
        #expect(nativeShimSource.contains("QPlainTextEdit"))
        #expect(nativeShimSource.contains("QPushButton"))
        #expect(nativeShimSource.contains("QFileDialog"))
        #expect(nativeShimSource.contains("QShortcut"))
        #expect(nativeShimSource.contains("QWidget *tunnelRowWidget"))
        #expect(nativeShimSource.contains("void addTunnelRow(QListWidget *list, const QJsonObject &tunnel)"))
        #expect(nativeShimSource.contains("void replaceTunnelName(QJsonArray *tunnels, int row, const QString &name)"))
        #expect(nativeShimSource.contains("void updateTunnelRowName(QListWidget *list, int row, const QString &name)"))
        #expect(nativeShimSource.contains("QObject::connect(name, &QLineEdit::textChanged"))
        #expect(nativeShimSource.contains("void showImportDialog("))
        #expect(nativeShimSource.contains("bool importConfigurationIntoList("))
        #expect(nativeShimSource.contains("quill_wireguard_qt_import_config_callback import_config"))
        #expect(nativeShimSource.contains("auto attemptImport = [&]"))
        #expect(nativeShimSource.contains("readImportConfigurationFile("))
        #expect(nativeShimSource.contains("startupImportConfigurationFile()"))
        #expect(nativeShimSource.contains("QUILLUI_WIREGUARD_QT_IMPORT_CONFIGURATION_FILE_ON_START"))
        #expect(nativeShimSource.contains("QTimer::singleShot"))
        #expect(nativeShimSource.contains("confirm->setDefault(true)"))
        #expect(nativeShimSource.contains("QKeySequence(QStringLiteral(\"Ctrl+Return\"))"))
        #expect(nativeShimSource.contains("QPushButton#importButton"))
        #expect(nativeShimSource.contains("importChooseFileButton"))
        #expect(nativeShimSource.contains("QFileDialog::getOpenFileName"))
        #expect(nativeShimSource.contains("attemptImport(configuration)"))
        #expect(nativeShimSource.contains("appendImportedTunnel(tunnels, list, countLabel, tunnel)"))
        #expect(nativeShimSource.contains("stringValue(interfaceObject, \"addressesText\")"))
        #expect(nativeShimSource.contains("QLabel#tunnelStatus, QLabel#tunnelSummary"))
        #expect(nativeShimSource.contains("QLineEdit#detailTitle"))
        #expect(nativeShimSource.contains("list->setItemWidget(item, tunnelRowWidget(tunnel))"))
        #expect(nativeShimSource.contains("const QJsonObject presentation = objectValue(payload, \"presentation\")"))
        #expect(nativeShimSource.contains("presentationValue(presentation, \"sidebarTitle\", \"Tunnels\")"))
        #expect(nativeShimSource.contains("presentationValue(presentation, \"interfaceSectionTitle\", \"Interface\")"))
        #expect(nativeShimSource.contains("presentationValue(presentation, \"tunnelNamePlaceholder\", \"Tunnel name\")"))
        #expect(nativeShimSource.contains("presentationValue(presentation, \"emptyStateTitle\", \"Quill WireGuard\")"))
        #expect(nativeShimSource.contains("\"importButtonLabel\""))
        #expect(nativeShimSource.contains("\"importButtonTooltip\""))
        #expect(nativeShimSource.contains("\"Import WireGuard configuration\""))
        #expect(nativeShimSource.contains("\"importFileActionLabel\""))
        #expect(nativeShimSource.contains("\"importDialogTitle\""))
        #expect(nativeShimSource.contains("\"importPlaceholder\""))
        #expect(nativeShimSource.contains("\"importEmptyConfigurationError\""))
        #expect(nativeShimSource.contains("\"importUnavailableError\""))
        #expect(nativeShimSource.contains("\"importNoResponseError\""))
        #expect(nativeShimSource.contains("\"importInvalidResponseError\""))
        #expect(nativeShimSource.contains("\"importMissingTunnelError\""))
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
        #expect(snapshot.presentation.importButtonLabel == QuillWireGuardPresentation.importButtonLabel)
        #expect(snapshot.presentation.importActionLabel == QuillWireGuardPresentation.importActionLabel)
        #expect(snapshot.presentation.importFileActionLabel == QuillWireGuardPresentation.importFileActionLabel)
        #expect(snapshot.presentation.importEmptyConfigurationError == QuillWireGuardPresentation.importEmptyConfigurationError)
        #expect(snapshot.presentation.importMissingTunnelError == QuillWireGuardPresentation.importMissingTunnelError)
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

        let legacyPresentationPayload = """
        {
          "sidebarTitle": "Legacy Tunnels",
          "backendTitle": "Legacy Backend",
          "noneText": "Nothing"
        }
        """.data(using: .utf8)!
        let legacyPresentation = try JSONDecoder().decode(
            QuillWireGuardPresentationSnapshot.self,
            from: legacyPresentationPayload
        )
        #expect(legacyPresentation.sidebarTitle == "Legacy Tunnels")
        #expect(legacyPresentation.backendTitle == "Legacy Backend")
        #expect(legacyPresentation.noneText == "Nothing")
        #expect(legacyPresentation.importActionLabel == QuillWireGuardPresentation.importActionLabel)
    }

    @Test("Native Qt host covers every shared WireGuard presentation key")
    func nativeQtHostCoversEverySharedWireGuardPresentationKey() throws {
        let presentationKeys = wireGuardPresentationPropertyNames()
        #expect(!presentationKeys.isEmpty)

        let encodedPresentation = try JSONDecoder().decode(
            [String: String].self,
            from: JSONEncoder().encode(QuillWireGuardPresentationSnapshot())
        )
        #expect(Set(encodedPresentation.keys) == Set(presentationKeys))

        let root = try packageRoot()
        let nativeRuntimeSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillWireGuardQtNativeRuntime/QuillWireGuardQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let nativeShimSource = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillWireGuardQt6Widgets.cpp"),
            encoding: .utf8
        )

        for key in presentationKeys {
            #expect(
                nativeShimSource.contains("\"\(key)\"")
                    || nativeRuntimeSource.contains("QuillWireGuardPresentation.\(key)")
            )
        }
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

    private func sharedImportSmokeConfiguration() throws -> String {
        let fixtureURL = try packageRoot()
            .appendingPathComponent("Tests/Fixtures/WireGuard/imported-edge.conf")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private func wireGuardPresentationPropertyNames() -> [String] {
        Mirror(reflecting: QuillWireGuardPresentationSnapshot()).children.compactMap { $0.label }
    }

    private func parseError(for configuration: String) -> QuillWireGuardConfigParseError? {
        do {
            _ = try QuillWireGuardConfigParser.parse(configuration)
            return nil
        } catch let parseError as QuillWireGuardConfigParseError {
            return parseError
        } catch {
            return nil
        }
    }
}

private enum SourceHygieneError: Error {
    case packageRootNotFound
}
