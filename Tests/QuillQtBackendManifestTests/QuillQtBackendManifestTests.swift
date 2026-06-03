import Foundation
import QuillEnchantedShared
import QuillGenericQtNativeRuntime
import QuillQtNativeRuntimeSupport
import Testing

@Suite("Qt backend manifest")
struct QuillQtBackendManifestTests {
    private struct QtAppSpec: Equatable {
        var product: String
        var target: String
        var qtPath: String
        var qtRuntime: String
    }

    private struct GenericQtCatalogExpectation {
        var catalogCase: String
        var selectedIndexEnvironmentKeys: [String]
        var snapshot: QuillGenericQtAppSnapshot
    }

    private static let expectedGenericQtCatalogProducts = [
        "quill-enchanted-upstream-slice",
        "quill-icecubes",
        "quill-netnewswire",
        "quill-codeedit",
        "quill-signal",
        "quill-telegram",
        "quill-iina"
    ]

    private static let expectedGenericQtCatalog: [String: GenericQtCatalogExpectation] = [
        "quill-enchanted-upstream-slice": .init(
            catalogCase: "enchantedUpstreamSlice",
            selectedIndexEnvironmentKeys: EnchantedInitialSelection.selectedConversationIndexEnvironmentKeys + [
                QuillGenericQtAppSnapshot.genericSelectedIndexEnvironmentKey
            ],
            snapshot: QuillGenericQtAppCatalog.enchantedUpstreamSlice
        ),
        "quill-icecubes": .init(
            catalogCase: "iceCubes",
            selectedIndexEnvironmentKeys: [
                "QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START",
                QuillGenericQtAppSnapshot.genericSelectedIndexEnvironmentKey
            ],
            snapshot: QuillGenericQtAppCatalog.iceCubes
        ),
        "quill-netnewswire": .init(
            catalogCase: "netNewsWire",
            selectedIndexEnvironmentKeys: [
                "QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START",
                QuillGenericQtAppSnapshot.genericSelectedIndexEnvironmentKey
            ],
            snapshot: QuillGenericQtAppCatalog.netNewsWire
        ),
        "quill-codeedit": .init(
            catalogCase: "codeEdit",
            selectedIndexEnvironmentKeys: [
                "QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START",
                QuillGenericQtAppSnapshot.genericSelectedIndexEnvironmentKey
            ],
            snapshot: QuillGenericQtAppCatalog.codeEdit
        ),
        "quill-signal": .init(
            catalogCase: "signal",
            selectedIndexEnvironmentKeys: [
                "QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START",
                "QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START",
                QuillGenericQtAppSnapshot.genericSelectedIndexEnvironmentKey
            ],
            snapshot: QuillGenericQtAppCatalog.signal
        ),
        "quill-telegram": .init(
            catalogCase: "telegram",
            selectedIndexEnvironmentKeys: [
                "QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START",
                "QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START",
                QuillGenericQtAppSnapshot.genericSelectedIndexEnvironmentKey
            ],
            snapshot: QuillGenericQtAppCatalog.telegram
        ),
        "quill-iina": .init(
            catalogCase: "iina",
            selectedIndexEnvironmentKeys: [
                "QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START",
                QuillGenericQtAppSnapshot.genericSelectedIndexEnvironmentKey
            ],
            snapshot: QuillGenericQtAppCatalog.iina
        )
    ]

    @Test("Qt backend registers a real Qt-mode test target")
    func qtBackendRegistersRealQtModeTestTarget() throws {
        let environmentBackend = ProcessInfo.processInfo.environment["QUILLUI_LINUX_BACKEND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        #expect(environmentBackend == "qt" || environmentBackend == "qt6")

        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(manifest.contains("if quillUILinuxBuildBackend == .qt {\n        return ["))
        #expect(manifest.contains("name: \"QuillQtBackendManifestTests\""))
        #expect(manifest.contains("products = quillCanonicalLinuxAppProducts + ["))
        #expect(manifest.contains(".executable(name: \"quill-qt-interaction-smoke\", targets: [\"QuillQtInteractionSmoke\"])"))
        #expect(manifest.contains("allPackageDependencies = quillDataPackageDependencies"))
        #expect(manifest.contains("let quillDataPackageDependencies: [Package.Dependency] = ["))
        #expect(manifest.contains("cSQLiteTarget,\n        quillDataMacroTarget,\n        quillDataTarget,"))
        #expect(manifest.contains("name: \"QuillEnchantedShared\""))
        #expect(manifest.contains("dependencies: [\"QuillEnchantedData\", \"QuillFoundation\"]"))
        #expect(manifest.contains("path: \"Sources/QuillEnchantedShared\""))
        #expect(manifest.contains("quillEnchantedDataTarget,"))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(!manifest.contains("if quillUILinuxBuildBackend == .qt {\n        return []"))
    }

    @Test("Canonical app specs resolve to explicit Qt launchers")
    func canonicalAppSpecsResolveToExplicitQtLaunchers() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let script = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        let appProducts = try runScript(script, arguments: ["backend-apps"])
        #expect(appProducts.status == 0, Comment(rawValue: appProducts.output))

        let expectedProducts = lines(appProducts.output)
        let specs = try canonicalAppSpecs(in: manifest)
        #expect(specs.map(\.product) == expectedProducts)
        #expect(
            specs
                .filter { $0.qtRuntime == "genericQtNative" }
                .map(\.product) == Self.expectedGenericQtCatalogProducts
        )

        for spec in specs {
            let mainURL = root.appendingPathComponent(spec.qtPath).appendingPathComponent("main.swift")
            #expect(
                FileManager.default.fileExists(atPath: mainURL.path),
                Comment(rawValue: "\(spec.product) must have a Qt launcher at \(spec.qtPath)/main.swift")
            )

            let launcher = try String(contentsOf: mainURL, encoding: .utf8)
            switch spec.qtRuntime {
            case "genericQtNative":
                guard let expectation = Self.expectedGenericQtCatalog[spec.product] else {
                    Issue.record("Missing generic Qt catalog expectation for \(spec.product)")
                    continue
                }

                #expect(launcher.contains("#if QUILLUI_GENERIC_QT_NATIVE_BACKEND"))
                #expect(launcher.contains("import QuillGenericQtNativeRuntime"))
                #expect(launcher.contains("QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog.\(expectation.catalogCase))"))
                #expect(!launcher.contains("#else"))
                #expect(!launcher.contains("executableName:"))
                #expect(!launcher.contains("QuillQtApp.run"))
                #expect(!launcher.contains("import QuillUIQt"))
            case "wireGuardQtNative":
                #expect(launcher.contains("#if QUILLUI_WIREGUARD_QT_NATIVE_BACKEND"))
                #expect(launcher.contains("import QuillWireGuardQtNativeRuntime"))
                #expect(launcher.contains("QuillWireGuardQtNativeApp.run()"))
                #expect(launcher.contains("#else"))
            default:
                Issue.record("Unknown Qt runtime case \(spec.qtRuntime) for \(spec.product)")
            }
        }
    }

    @Test("Generic Qt app catalog snapshots match the product roster")
    func genericQtAppCatalogSnapshotsMatchProductRoster() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        let smokeLib = root.appendingPathComponent("scripts/quillui-linux-backend-smoke-lib.sh")
        let genericProducts = try runScript(script, arguments: ["generic-qt-apps"])
        #expect(genericProducts.status == 0, Comment(rawValue: genericProducts.output))
        #expect(lines(genericProducts.output) == Self.expectedGenericQtCatalogProducts)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for product in Self.expectedGenericQtCatalogProducts {
            guard let expectation = Self.expectedGenericQtCatalog[product] else {
                Issue.record("Missing generic Qt catalog expectation for \(product)")
                continue
            }

            assertGenericQtSnapshot(expectation.snapshot, product: product, expectation: expectation)
            if product == "quill-enchanted-upstream-slice" {
                assertEnchantedSliceUsesSharedMetrics(expectation.snapshot)
            }

            let sharedSelectionKeys = try genericSelectionEnvironmentKeys(product: product, smokeLib: smokeLib)
            #expect(
                sharedSelectionKeys + QuillGenericQtAppSnapshot.defaultSelectedIndexEnvironmentKeys
                    == expectation.selectedIndexEnvironmentKeys
            )

            let encodedSnapshot = try encoder.encode(expectation.snapshot)
            let decodedSnapshot = try JSONDecoder().decode(QuillGenericQtAppSnapshot.self, from: encodedSnapshot)

            assertGenericQtSnapshot(decodedSnapshot, product: product, expectation: expectation)
            if product == "quill-enchanted-upstream-slice" {
                assertEnchantedSliceUsesSharedMetrics(decodedSnapshot)
            }

            #expect(decodedSnapshot.windowTitle == expectation.snapshot.windowTitle)
            #expect(decodedSnapshot.selectedIndex == expectation.snapshot.selectedIndex)
            #expect(decodedSnapshot.items.count == expectation.snapshot.items.count)
            #expect(decodedSnapshot.sections.count == expectation.snapshot.sections.count)
            #expect(decodedSnapshot.messages.count == expectation.snapshot.messages.count)
        }
    }

    @Test("Qt native runtime support clamps selection overrides")
    func qtNativeRuntimeSupportClampsSelectionOverrides() {
        #expect(QuillQtNativeRuntimeSupport.boundedIndexOverride(" 2 ", count: 3) == 2)
        #expect(QuillQtNativeRuntimeSupport.boundedIndexOverride("-4", count: 3) == 0)
        #expect(QuillQtNativeRuntimeSupport.boundedIndexOverride("9", count: 3) == 2)
        #expect(QuillQtNativeRuntimeSupport.boundedIndexOverride("abc", count: 3) == nil)
        #expect(QuillQtNativeRuntimeSupport.boundedIndexOverride("1", count: 0) == nil)
        #expect(QuillQtNativeRuntimeSupport.boundedIndexOverride(nil, count: 3) == nil)
    }

    @Test("Generic Qt snapshots decode legacy payload defaults")
    func genericQtSnapshotsDecodeLegacyPayloadDefaults() throws {
        let payload = """
        {
          "windowTitle": "Legacy Generic Qt",
          "sidebarTitle": "Inbox",
          "sidebarSubtitle": "Legacy payload",
          "listTitle": "Items",
          "status": "Qt native runtime",
          "detailTitle": "Detail",
          "detailSubtitle": "Legacy snapshot without style",
          "items": [
            {
              "title": "First",
              "subtitle": "Missing optional render fields"
            }
          ],
          "sections": [
            {
              "title": "Summary",
              "body": "Snapshot omits fields that host and Swift defaults should fill."
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(QuillGenericQtAppSnapshot.self, from: payload)

        #expect(snapshot.minimumWidth == 900)
        #expect(snapshot.minimumHeight == 620)
        #expect(snapshot.defaultWidth == 1040)
        #expect(snapshot.defaultHeight == 700)
        #expect(snapshot.sidebarWidth == 320)
        #expect(snapshot.detailWidth == 720)
        #expect(snapshot.primaryActionTitle == "New")
        #expect(snapshot.secondaryActionTitle == "Refresh")
        #expect(snapshot.selectedIndex == 0)
        #expect(snapshot.selectedIndexEnvironmentKeys == QuillGenericQtAppSnapshot.defaultSelectedIndexEnvironmentKeys)
        #expect(snapshot.messagesTitle == "Activity")
        #expect(snapshot.messages.isEmpty)
        #expect(snapshot.items[0].badge == "")
        #expect(snapshot.items[0].height == 76)
        #expect(snapshot.style.canvasColor == QuillGenericQtAppSnapshot.Style.desktop.canvasColor)
        #expect(snapshot.style.controlBorderColor == QuillGenericQtAppSnapshot.Style.desktop.controlBorderColor)
        #expect(snapshot.style.sidebarSpacing == QuillGenericQtAppSnapshot.Style.desktop.sidebarSpacing)
        #expect(snapshot.style.primaryButtonVerticalPadding == QuillGenericQtAppSnapshot.Style.desktop.primaryButtonVerticalPadding)
        #expect(snapshot.style.listSpacing == QuillGenericQtAppSnapshot.Style.desktop.listSpacing)
        #expect(snapshot.style.messageCardRadius == QuillGenericQtAppSnapshot.Style.desktop.messageCardRadius)
        #expect(snapshot.style.detailContentSpacing == QuillGenericQtAppSnapshot.Style.desktop.detailContentSpacing)
    }

    @Test("Generic Qt style decoding defaults missing fields")
    func genericQtStyleDecodingDefaultsMissingFields() throws {
        let payload = """
        {
          "canvasColor": "#101010",
          "primaryColor": "#202020"
        }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(QuillGenericQtAppSnapshot.Style.self, from: payload)

        #expect(style.canvasColor == "#101010")
        #expect(style.primaryColor == "#202020")
        #expect(style.sidebarColor == QuillGenericQtAppSnapshot.Style.desktop.sidebarColor)
        #expect(style.cardColor == QuillGenericQtAppSnapshot.Style.desktop.cardColor)
        #expect(style.controlBorderColor == QuillGenericQtAppSnapshot.Style.desktop.controlBorderColor)
        #expect(style.sidebarSpacing == QuillGenericQtAppSnapshot.Style.desktop.sidebarSpacing)
        #expect(style.primaryButtonVerticalPadding == QuillGenericQtAppSnapshot.Style.desktop.primaryButtonVerticalPadding)
        #expect(style.listSpacing == QuillGenericQtAppSnapshot.Style.desktop.listSpacing)
        #expect(style.messageCardRadius == QuillGenericQtAppSnapshot.Style.desktop.messageCardRadius)
        #expect(style.detailContentSpacing == QuillGenericQtAppSnapshot.Style.desktop.detailContentSpacing)
    }

    private func assertGenericQtSnapshot(
        _ snapshot: QuillGenericQtAppSnapshot,
        product: String,
        expectation: GenericQtCatalogExpectation
    ) {
        #expect(!snapshot.windowTitle.isEmpty, Comment(rawValue: "\(product) must provide a window title"))
        #expect(snapshot.minimumWidth > 0, Comment(rawValue: "\(product) must provide a positive minimum width"))
        #expect(snapshot.minimumHeight > 0, Comment(rawValue: "\(product) must provide a positive minimum height"))
        #expect(snapshot.defaultWidth >= snapshot.minimumWidth)
        #expect(snapshot.defaultHeight >= snapshot.minimumHeight)
        #expect(snapshot.sidebarWidth > 0)
        #expect(snapshot.detailWidth > 0)
        #expect(!snapshot.sidebarTitle.isEmpty)
        #expect(!snapshot.sidebarSubtitle.isEmpty)
        #expect(!snapshot.primaryActionTitle.isEmpty)
        #expect(!snapshot.secondaryActionTitle.isEmpty)
        #expect(!snapshot.listTitle.isEmpty)
        #expect(!snapshot.status.isEmpty)
        #expect(!snapshot.detailTitle.isEmpty)
        #expect(!snapshot.detailSubtitle.isEmpty)
        #expect(!snapshot.messagesTitle.isEmpty)
        #expect(!snapshot.items.isEmpty, Comment(rawValue: "\(product) must provide selectable rows"))
        #expect(!snapshot.sections.isEmpty, Comment(rawValue: "\(product) must provide detail sections"))
        #expect(snapshot.selectedIndexEnvironmentKeys == expectation.selectedIndexEnvironmentKeys)
        #expect(Set(snapshot.selectedIndexEnvironmentKeys).count == snapshot.selectedIndexEnvironmentKeys.count)

        if snapshot.items.isEmpty {
            Issue.record("\(product) must provide at least one item before selectedIndex can be validated")
        } else {
            #expect(snapshot.selectedIndex >= 0)
            #expect(snapshot.selectedIndex < snapshot.items.count)
        }

        for item in snapshot.items {
            #expect(!item.title.isEmpty, Comment(rawValue: "\(product) items must provide titles"))
            #expect(!item.subtitle.isEmpty, Comment(rawValue: "\(product) items must provide subtitles"))
            #expect(item.height > 0, Comment(rawValue: "\(product) items must provide positive row heights"))

            if let sections = item.sections {
                #expect(!sections.isEmpty, Comment(rawValue: "\(product) item sections must not be empty"))
                for section in sections {
                    #expect(!section.title.isEmpty)
                    #expect(!section.body.isEmpty)
                }
            }

            if let messages = item.messages {
                for message in messages {
                    #expect(!message.sender.isEmpty)
                    #expect(!message.body.isEmpty)
                }
            }
        }

        for section in snapshot.sections {
            #expect(!section.title.isEmpty)
            #expect(!section.body.isEmpty)
        }

        for message in snapshot.messages {
            #expect(!message.sender.isEmpty)
            #expect(!message.body.isEmpty)
        }
    }

    private func assertEnchantedSliceUsesSharedMetrics(_ snapshot: QuillGenericQtAppSnapshot) {
        #expect(snapshot.minimumWidth == EnchantedVisualMetrics.minimumWindowWidth)
        #expect(snapshot.minimumHeight == EnchantedVisualMetrics.minimumWindowHeight)
        #expect(snapshot.defaultWidth == EnchantedVisualMetrics.defaultWindowWidth)
        #expect(snapshot.defaultHeight == EnchantedVisualMetrics.defaultWindowHeight)
        #expect(snapshot.sidebarWidth == EnchantedVisualMetrics.sidebarWidth)
        #expect(snapshot.detailWidth == EnchantedVisualMetrics.detailWidth)
        #expect(snapshot.style.canvasColor == EnchantedPalette.canvasColor)
        #expect(snapshot.style.sidebarColor == EnchantedPalette.sidebarColor)
        #expect(snapshot.style.cardColor == EnchantedPalette.cardColor)
        #expect(snapshot.style.activeCardColor == EnchantedPalette.sidebarSelectedColor)
        #expect(snapshot.style.primaryColor == EnchantedPalette.accentColor)
        #expect(snapshot.style.inkColor == EnchantedPalette.textColor)
        #expect(snapshot.style.mutedColor == EnchantedPalette.secondaryTextColor)
        #expect(snapshot.style.badgeColor == EnchantedPalette.accentColor)
        #expect(snapshot.style.selectedMutedColor == EnchantedPalette.sidebarSelectedColor)
        #expect(snapshot.style.borderColor == EnchantedPalette.hairlineColor)
        #expect(snapshot.style.selectedBorderColor == EnchantedPalette.controlBorderColor)
        #expect(snapshot.style.dividerColor == EnchantedPalette.hairlineColor)
        #expect(snapshot.style.controlBorderColor == EnchantedPalette.controlBorderColor)
        #expect(snapshot.style.sidebarPadding == EnchantedVisualMetrics.sidebarPadding)
        #expect(snapshot.style.sidebarSpacing == EnchantedVisualMetrics.sidebarSpacing)
        #expect(snapshot.style.sidebarActionSpacing == EnchantedVisualMetrics.conversationActionsSpacing)
        #expect(
            snapshot.style.primaryButtonMinHeight
                == EnchantedVisualMetrics.primaryButtonVerticalPadding * 2 + EnchantedTypography.rootFontSize
        )
        #expect(snapshot.style.primaryButtonVerticalPadding == EnchantedVisualMetrics.primaryButtonVerticalPadding)
        #expect(snapshot.style.primaryButtonHorizontalPadding == EnchantedVisualMetrics.primaryButtonHorizontalPadding)
        #expect(snapshot.style.primaryButtonRadius == EnchantedVisualMetrics.primaryButtonRadius)
        #expect(snapshot.style.secondaryButtonVerticalPadding == EnchantedVisualMetrics.secondaryButtonVerticalPadding)
        #expect(snapshot.style.secondaryButtonHorizontalPadding == EnchantedVisualMetrics.secondaryButtonHorizontalPadding)
        #expect(snapshot.style.secondaryButtonRadius == EnchantedVisualMetrics.secondaryButtonRadius)
        #expect(snapshot.style.listSpacing == EnchantedVisualMetrics.conversationListSpacing)
        #expect(snapshot.style.listItemRadius == EnchantedVisualMetrics.conversationListItemRadius)
        #expect(snapshot.style.listItemVerticalMargin == EnchantedVisualMetrics.conversationListItemVerticalMargin)
        #expect(snapshot.style.listItemPadding == EnchantedVisualMetrics.conversationListItemPadding)
        #expect(snapshot.style.itemRowHorizontalPadding == EnchantedVisualMetrics.conversationRowPadding)
        #expect(snapshot.style.itemRowVerticalPadding == EnchantedVisualMetrics.conversationRowPadding)
        #expect(snapshot.style.itemRowSpacing == EnchantedVisualMetrics.conversationRowSpacing)
        #expect(snapshot.style.cardRadius == EnchantedVisualMetrics.emptyHistoryRadius)
        #expect(snapshot.style.cardPaddingHorizontal == EnchantedVisualMetrics.emptyHistoryPadding)
        #expect(snapshot.style.cardPaddingVertical == EnchantedVisualMetrics.emptyHistoryPadding)
        #expect(snapshot.style.cardSpacing == EnchantedVisualMetrics.emptyHistorySpacing)
        #expect(snapshot.style.activeCardRadius == EnchantedVisualMetrics.conversationRowRadius)
        #expect(snapshot.style.messageCardRadius == EnchantedVisualMetrics.messageBubbleRadius)
        #expect(snapshot.style.messageCardPaddingHorizontal == EnchantedVisualMetrics.messageBubbleHorizontalPadding)
        #expect(snapshot.style.messageCardPaddingVertical == EnchantedVisualMetrics.messageBubbleVerticalPadding)
        #expect(snapshot.style.messageCardSpacing == EnchantedVisualMetrics.messageBubbleSpacing)
        #expect(snapshot.style.detailPaddingHorizontal == EnchantedVisualMetrics.contentPadding)
        #expect(snapshot.style.detailPaddingVertical == EnchantedVisualMetrics.contentPadding)
        #expect(snapshot.style.detailSpacing == EnchantedVisualMetrics.messageSpacing)
        #expect(snapshot.style.detailContentSpacing == EnchantedVisualMetrics.messageSpacing)
    }

    private func canonicalAppSpecs(in manifest: String) throws -> [QtAppSpec] {
        let regex = try NSRegularExpression(
            pattern: #"\.init\(product: "([^"]+)", target: "([^"]+)", qtPath: "([^"]+)", qtRuntime: \.([A-Za-z0-9_]+)\)"#
        )
        let nsRange = NSRange(manifest.startIndex..<manifest.endIndex, in: manifest)
        return regex.matches(in: manifest, range: nsRange).compactMap { match in
            guard
                let productRange = Range(match.range(at: 1), in: manifest),
                let targetRange = Range(match.range(at: 2), in: manifest),
                let qtPathRange = Range(match.range(at: 3), in: manifest),
                let runtimeRange = Range(match.range(at: 4), in: manifest)
            else {
                return nil
            }

            return QtAppSpec(
                product: String(manifest[productRange]),
                target: String(manifest[targetRange]),
                qtPath: String(manifest[qtPathRange]),
                qtRuntime: String(manifest[runtimeRange])
            )
        }
    }

    private func lines(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func runScript(
        _ script: URL,
        arguments: [String] = []
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = script
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private func genericSelectionEnvironmentKeys(product: String, smokeLib: URL) throws -> [String] {
        let result = try runBash(
            """
            set -euo pipefail
            source "$1"
            quillui_backend_generic_selection_environment_keys "$2"
            """,
            arguments: [smokeLib.path, product]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))
        return lines(result.output)
    }

    private func runBash(
        _ command: String,
        arguments: [String] = []
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command, "quillui-test-bash"] + arguments
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private func packageRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while directory.path != "/" {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "QuillQtBackendManifestTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }
}
