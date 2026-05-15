import Foundation
import Testing

@Suite("Linux backend app matrix", .serialized)
struct LinuxBackendAppMatrixTests {
    private struct AppTargetContract {
        var product: String
        var target: String
        var qtPath: String
        var qtRuntimeDependency: String
        var qtLauncherCall: String
    }

    private static let expectedAppContracts = [
        AppTargetContract(
            product: "quill-enchanted",
            target: "QuillEnchanted",
            qtPath: "Sources/QuillEnchantedQt",
            qtRuntimeDependency: "QuillEnchantedQtNativeRuntime",
            qtLauncherCall: "QuillEnchantedQtNativeApp.run()"
        ),
        AppTargetContract(
            product: "quill-enchanted-upstream-slice",
            target: "QuillEnchantedUpstreamSlice",
            qtPath: "Sources/QuillEnchantedUpstreamSliceQt",
            qtRuntimeDependency: "QuillGenericQtNativeRuntime",
            qtLauncherCall: "QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog.enchantedUpstreamSlice)"
        ),
        AppTargetContract(
            product: "quill-icecubes",
            target: "QuillIceCubes",
            qtPath: "Sources/QuillIceCubesQt",
            qtRuntimeDependency: "QuillGenericQtNativeRuntime",
            qtLauncherCall: "QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog.iceCubes)"
        ),
        AppTargetContract(
            product: "quill-netnewswire",
            target: "QuillNetNewsWire",
            qtPath: "Sources/QuillNetNewsWireQt",
            qtRuntimeDependency: "QuillGenericQtNativeRuntime",
            qtLauncherCall: "QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog.netNewsWire)"
        ),
        AppTargetContract(
            product: "quill-codeedit",
            target: "QuillCodeEdit",
            qtPath: "Sources/QuillCodeEditQt",
            qtRuntimeDependency: "QuillGenericQtNativeRuntime",
            qtLauncherCall: "QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog.codeEdit)"
        ),
        AppTargetContract(
            product: "quill-signal",
            target: "QuillSignal",
            qtPath: "Sources/QuillSignalQt",
            qtRuntimeDependency: "QuillGenericQtNativeRuntime",
            qtLauncherCall: "QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog.signal)"
        ),
        AppTargetContract(
            product: "quill-telegram",
            target: "QuillTelegram",
            qtPath: "Sources/QuillTelegramQt",
            qtRuntimeDependency: "QuillGenericQtNativeRuntime",
            qtLauncherCall: "QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog.telegram)"
        ),
        AppTargetContract(
            product: "quill-iina",
            target: "QuillIINA",
            qtPath: "Sources/QuillIINAQt",
            qtRuntimeDependency: "QuillGenericQtNativeRuntime",
            qtLauncherCall: "QuillGenericQtNativeApp.run(QuillGenericQtAppCatalog.iina)"
        ),
        AppTargetContract(
            product: "quill-wireguard",
            target: "QuillWireGuard",
            qtPath: "Sources/QuillWireGuardQt",
            qtRuntimeDependency: "QuillWireGuardQtNativeRuntime",
            qtLauncherCall: "QuillWireGuardQtNativeApp.run()"
        )
    ]

    private static var expectedAppProducts: [String] {
        expectedAppContracts.map(\.product)
    }

    private static var expectedGenericQtAppProducts: [String] {
        expectedAppContracts
            .filter { $0.qtRuntimeDependency == "QuillGenericQtNativeRuntime" }
            .map(\.product)
    }

    private static var expectedGenericGtkListSelectionAppProducts: [String] {
        expectedGenericQtAppProducts.filter { product in
            !["quill-signal", "quill-telegram"].contains(product)
        }
    }

    private static let expectedChatGtkListSelectionAppProducts = ["quill-signal", "quill-telegram"]

    private static let expectedBackends = ["gtk", "qt"]
    private static let expectedNativeRuntimeBackends = ["gtk"]
    private static let expectedGeneratedAppProducts = ["quill-chat-linux"]
    private static let expectedSmokeProducts = ["quill-gtk-interaction-smoke", "quill-qt-interaction-smoke"]
    private static let profileCSVHeader = "product,requested_backend,runtime_backend,runtime_mode,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"

    private static var expectedAppMatrixRows: [String] {
        expectedAppProducts.flatMap { product in
            expectedBackends.map { backend in "\(product)\t\(backend)" }
        }
    }

    private static var expectedGeneratedAppMatrixRows: [String] {
        expectedGeneratedAppProducts.flatMap { product in
            expectedBackends.map { backend in "\(product)\t\(backend)" }
        }
    }

    private static var expectedAppRuntimeRows: [String] {
        expectedAppMatrixRows.map { row in
            let fields = row.split(separator: "\t").map(String.init)
            return "\(fields[0])\t\(fields[1])\t\(fields[1])\tnative"
        }
    }

    private static var expectedProfileRuntimeRows: [String] {
        expectedAppRuntimeRows
            + expectedGeneratedAppRuntimeRows
            + [
                "quill-gtk-interaction-smoke\tgtk\tgtk\tnative",
                "quill-qt-interaction-smoke\tqt\tqt\tnative"
            ]
    }

    private static var expectedGeneratedAppRuntimeRows: [String] {
        expectedGeneratedAppProducts.flatMap { product in
            expectedBackends.map { backend in
                if backend == "qt" {
                    return "\(product)\tqt\tqt\tnative"
                }
                return "\(product)\tgtk\tgtk\tnative"
            }
        }
    }

    private static func expectedVisualVerifierProduct(product: String, backend: String) -> String {
        if backend == "qt" {
            switch product {
            case "quill-enchanted":
                return "quill-enchanted-qt"
            case "quill-wireguard":
                return "quill-wireguard-qt"
            default:
                break
            }
        }
        return product
    }

    private static func expectedVisualRow(product: String, backend: String) -> String {
        let verifyProduct = Self.expectedVisualVerifierProduct(product: product, backend: backend)
        return "visual\t\(product)\t\(backend)\t\(backend)\tnative\t.qa/\(product)-\(backend).png\t0\t\(verifyProduct)"
    }

    private static func expectedInteractionExtraModeRow(
        product: String,
        backend: String,
        mode: String,
        verifyProduct: String
    ) -> String {
        "interaction\t\(product)\t\(backend)\t\(backend)\tnative\t.qa/\(product)-\(mode)-\(backend).png\t0\t\(mode)\t\(verifyProduct)"
    }

    private static var expectedInteractionExtraModeRows: [String] {
        [
            Self.expectedInteractionExtraModeRow(
                product: "quill-wireguard",
                backend: "gtk",
                mode: "import-paste",
                verifyProduct: "quill-wireguard-import-paste"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-wireguard",
                backend: "gtk",
                mode: "import-file",
                verifyProduct: "quill-wireguard-import-file"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-wireguard",
                backend: "gtk",
                mode: "import-invalid-paste",
                verifyProduct: "quill-wireguard-import-invalid-paste"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-wireguard",
                backend: "gtk",
                mode: "import-invalid-file",
                verifyProduct: "quill-wireguard-import-invalid-file"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-wireguard",
                backend: "qt",
                mode: "import-paste",
                verifyProduct: "quill-wireguard-qt-import-paste"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-wireguard",
                backend: "qt",
                mode: "import-file",
                verifyProduct: "quill-wireguard-qt-import-file"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-wireguard",
                backend: "qt",
                mode: "import-invalid-paste",
                verifyProduct: "quill-wireguard-qt-import-invalid-paste"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-wireguard",
                backend: "qt",
                mode: "import-invalid-file",
                verifyProduct: "quill-wireguard-qt-import-invalid-file"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-enchanted",
                backend: "gtk",
                mode: "list-selection",
                verifyProduct: "quill-enchanted-list-selection"
            ),
            Self.expectedInteractionExtraModeRow(
                product: "quill-enchanted",
                backend: "qt",
                mode: "list-selection",
                verifyProduct: "quill-enchanted-qt-list-selection"
            ),
        ] + expectedChatGtkListSelectionAppProducts.map { product in
            Self.expectedInteractionExtraModeRow(
                product: product,
                backend: "gtk",
                mode: "list-selection",
                verifyProduct: "\(product)-list-selection"
            )
        } + expectedGenericGtkListSelectionAppProducts.map { product in
            Self.expectedInteractionExtraModeRow(
                product: product,
                backend: "gtk",
                mode: "list-selection",
                verifyProduct: "\(product)-gtk-list-selection"
            )
        } + expectedGenericQtAppProducts.map { product in
            Self.expectedInteractionExtraModeRow(
                product: product,
                backend: "qt",
                mode: "list-selection",
                verifyProduct: "\(product)-qt-list-selection"
            )
        }
    }

    private static func lines(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map(String.init)
    }

    @Test("canonical app products compile through explicit Linux backends")
    func canonicalAppProductsCompileThroughExplicitLinuxBackends() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        let buildScript = root.appendingPathComponent("scripts/build-linux-backend-products.sh")
        let legacyMatrixScript = root.appendingPathComponent("scripts/linux-gtk-app-products.sh")

        let appProducts = try runScript(script, arguments: ["backend-apps"])
        #expect(appProducts.status == 0, Comment(rawValue: appProducts.output))
        #expect(Self.lines(appProducts.output) == Self.expectedAppProducts)

        let gtkProducts = try runScript(script, arguments: ["gtk-apps"])
        #expect(gtkProducts.status == 0, Comment(rawValue: gtkProducts.output))
        #expect(gtkProducts.output == appProducts.output)

        let genericQtProducts = try runScript(script, arguments: ["generic-qt-apps"])
        #expect(genericQtProducts.status == 0, Comment(rawValue: genericQtProducts.output))
        #expect(Self.lines(genericQtProducts.output) == Self.expectedGenericQtAppProducts)
        #expect(Self.lines(genericQtProducts.output).allSatisfy { Self.expectedAppProducts.contains($0) })

        let genericGtkProducts = try runScript(script, arguments: ["generic-gtk-list-selection-apps"])
        #expect(genericGtkProducts.status == 0, Comment(rawValue: genericGtkProducts.output))
        #expect(Self.lines(genericGtkProducts.output) == Self.expectedGenericGtkListSelectionAppProducts)
        #expect(Self.lines(genericGtkProducts.output).allSatisfy { Self.expectedAppProducts.contains($0) })

        let chatGtkProducts = try runScript(script, arguments: ["chat-gtk-list-selection-apps"])
        #expect(chatGtkProducts.status == 0, Comment(rawValue: chatGtkProducts.output))
        #expect(Self.lines(chatGtkProducts.output) == Self.expectedChatGtkListSelectionAppProducts)
        #expect(Self.lines(chatGtkProducts.output).allSatisfy { Self.expectedAppProducts.contains($0) })

        let genericQtMembership = try runScript(script, arguments: ["is-generic-qt-app", "quill-signal"])
        #expect(genericQtMembership.status == 0, Comment(rawValue: genericQtMembership.output))

        let nativeQtMembership = try runScript(script, arguments: ["is-generic-qt-app", "quill-wireguard"])
        #expect(nativeQtMembership.status != 0)

        let genericGtkMembership = try runScript(script, arguments: ["is-generic-gtk-list-selection-app", "quill-codeedit"])
        #expect(genericGtkMembership.status == 0, Comment(rawValue: genericGtkMembership.output))

        let chatExcludedFromGenericGtkMembership = try runScript(script, arguments: ["is-generic-gtk-list-selection-app", "quill-signal"])
        #expect(chatExcludedFromGenericGtkMembership.status != 0)

        let chatGtkMembership = try runScript(script, arguments: ["is-chat-gtk-list-selection-app", "quill-signal"])
        #expect(chatGtkMembership.status == 0, Comment(rawValue: chatGtkMembership.output))

        let genericExcludedFromChatGtkMembership = try runScript(script, arguments: ["is-chat-gtk-list-selection-app", "quill-codeedit"])
        #expect(genericExcludedFromChatGtkMembership.status != 0)

        let legacyProducts = try runScript(legacyMatrixScript)
        #expect(legacyProducts.status == 0, Comment(rawValue: legacyProducts.output))
        #expect(legacyProducts.output == appProducts.output)

        let appBackends = try runScript(script, arguments: ["app-backends"])
        #expect(appBackends.status == 0, Comment(rawValue: appBackends.output))
        #expect(Self.lines(appBackends.output) == Self.expectedBackends)

        let generatedProducts = try runScript(script, arguments: ["generated-apps"])
        #expect(generatedProducts.status == 0, Comment(rawValue: generatedProducts.output))
        #expect(Self.lines(generatedProducts.output) == Self.expectedGeneratedAppProducts)

        let smokeProducts = try runScript(script, arguments: ["smoke-products"])
        #expect(smokeProducts.status == 0, Comment(rawValue: smokeProducts.output))
        #expect(Self.lines(smokeProducts.output) == Self.expectedSmokeProducts)

        let appProductSet = Set(Self.lines(appProducts.output))
        let generatedProductSet = Set(Self.lines(generatedProducts.output))
        let smokeProductSet = Set(Self.lines(smokeProducts.output))
        #expect(appProductSet.isDisjoint(with: generatedProductSet))
        #expect(appProductSet.isDisjoint(with: smokeProductSet))
        #expect(generatedProductSet.isDisjoint(with: smokeProductSet))

        let profileProducts = try runScript(script, arguments: ["profile-products"])
        #expect(profileProducts.status == 0, Comment(rawValue: profileProducts.output))
        #expect(Self.lines(profileProducts.output) == Self.expectedAppProducts + Self.expectedGeneratedAppProducts + Self.expectedSmokeProducts)
        #expect(Set(Self.lines(profileProducts.output)).count == Self.lines(profileProducts.output).count)

        for matrixCommand in ["app-matrix", "build-product-matrix"] {
            let result = matrixCommand == "build-product-matrix"
                ? try runScript(script, arguments: [matrixCommand, "backend-apps"])
                : try runScript(script, arguments: [matrixCommand])
            #expect(result.status == 0, Comment(rawValue: result.output))
            #expect(Self.lines(result.output) == Self.expectedAppMatrixRows)
        }

        let buildPlan = try runScript(buildScript, arguments: ["--dry-run", "backend-apps"])
        #expect(buildPlan.status == 0, Comment(rawValue: buildPlan.output))
        #expect(Self.lines(buildPlan.output) == Self.expectedAppMatrixRows)

        let fixedBackends = try runScript(script, arguments: ["fixed-app-backends"])
        #expect(fixedBackends.status == 0, Comment(rawValue: fixedBackends.output))
        #expect(fixedBackends.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let nativeRuntimes = try runScript(script, arguments: ["native-runtime-backends"])
        #expect(nativeRuntimes.status == 0, Comment(rawValue: nativeRuntimes.output))
        #expect(Self.lines(nativeRuntimes.output) == Self.expectedNativeRuntimeBackends)

        let nativeProductRuntimes = try runScript(script, arguments: ["native-product-runtime-backends"])
        #expect(nativeProductRuntimes.status == 0, Comment(rawValue: nativeProductRuntimes.output))
        #expect(Self.lines(nativeProductRuntimes.output) == Self.expectedBackends)

        let runtimeAvailabilities = try runScript(script, arguments: ["runtime-availabilities"])
        #expect(runtimeAvailabilities.status == 0, Comment(rawValue: runtimeAvailabilities.output))
        #expect(Self.lines(runtimeAvailabilities.output) == [
            "gtk\tgtk\tnative",
            "qt\tgtk\tplatformFallback"
        ])

        let generatedAppRows = try runScript(script, arguments: ["generated-app-matrix"])
        #expect(generatedAppRows.status == 0, Comment(rawValue: generatedAppRows.output))
        #expect(Self.lines(generatedAppRows.output) == Self.expectedGeneratedAppMatrixRows)

        let generatedAppRuntimeRows = try runScript(script, arguments: ["generated-app-runtime-matrix"])
        #expect(generatedAppRuntimeRows.status == 0, Comment(rawValue: generatedAppRuntimeRows.output))
        #expect(Self.lines(generatedAppRuntimeRows.output) == Self.expectedGeneratedAppRuntimeRows)

        let nativeOverrides = try runScript(script, arguments: ["native-product-runtime-overrides"])
        #expect(nativeOverrides.status == 0, Comment(rawValue: nativeOverrides.output))
        #expect(Self.lines(nativeOverrides.output) == [
            "quill-chat-linux\tqt\tqt",
            "quill-qt-interaction-smoke\tqt\tqt"
        ])

        let integrity = try runScript(script, arguments: ["validate-integrity"])
        #expect(integrity.status == 0, Comment(rawValue: integrity.output))
        #expect(integrity.output.contains("backend product matrix ok"))

        let interactionExtraModes = try runScript(script, arguments: ["interaction-extra-mode-matrix"])
        #expect(interactionExtraModes.status == 0, Comment(rawValue: interactionExtraModes.output))
        let interactionExtraModeFields = Self.lines(interactionExtraModes.output)
            .map { row in row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        #expect(interactionExtraModeFields.allSatisfy { $0.count == 3 })
        let interactionExtraModeGroups = Dictionary(grouping: interactionExtraModeFields.filter { $0.count == 3 }) {
            "\($0[0])\t\($0[2])"
        }
        for (productAndMode, rows) in interactionExtraModeGroups {
            let backends = rows.map { $0[1] }.sorted()
            #expect(
                backends == Self.expectedBackends,
                Comment(rawValue: "interaction-extra-mode-matrix must mirror GTK/Qt for \(productAndMode): \(backends)")
            )
        }

        let defaultBackend = try runScript(script, arguments: ["backend-for-product", "quill-wireguard"])
        #expect(defaultBackend.status == 0, Comment(rawValue: defaultBackend.output))
        #expect(defaultBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let explicitBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-wireguard"],
            environment: ["QUILLUI_BACKEND": "Qt6"]
        )
        #expect(explicitBackend.status == 0, Comment(rawValue: explicitBackend.output))
        #expect(explicitBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let unsupportedProduct = try runScript(script, arguments: ["backend-for-product", "quill-wireguard-qt"])
        #expect(unsupportedProduct.status != 0)
        #expect(unsupportedProduct.output.contains("Unsupported QuillUI backend product: quill-wireguard-qt"))

        let unsupportedExplicitProduct = try runScript(
            script,
            arguments: ["requested-backend", "quill-wireguard-qt"],
            environment: ["QUILLUI_BACKEND": "qt"]
        )
        #expect(unsupportedExplicitProduct.status != 0)
        #expect(unsupportedExplicitProduct.output.contains("Unsupported QuillUI backend product: quill-wireguard-qt"))

        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        for contract in Self.expectedAppContracts {
            let qtRuntimeCase: String
            switch contract.qtRuntimeDependency {
            case "QuillEnchantedQtNativeRuntime":
                qtRuntimeCase = "enchantedQtNative"
            case "QuillGenericQtNativeRuntime":
                qtRuntimeCase = "genericQtNative"
            case "QuillWireGuardQtNativeRuntime":
                qtRuntimeCase = "wireGuardQtNative"
            default:
                qtRuntimeCase = ""
            }

            #expect(
                manifest.contains("product: \"\(contract.product)\", target: \"\(contract.target)\", qtPath: \"\(contract.qtPath)\", qtRuntime: .\(qtRuntimeCase)")
            )
            #expect(manifest.contains("return \"\(contract.qtRuntimeDependency)\""))

            let qtMain = root
                .appendingPathComponent(contract.qtPath)
                .appendingPathComponent("main.swift")
            #expect(
                FileManager.default.fileExists(atPath: qtMain.path),
                Comment(rawValue: "\(contract.product) must have an explicit Qt launcher")
            )

            let qtLauncher = try String(contentsOf: qtMain, encoding: .utf8)
            if contract.qtRuntimeDependency == "QuillGenericQtNativeRuntime" {
                #expect(qtLauncher.contains("#if QUILLUI_GENERIC_QT_NATIVE_BACKEND"))
            }
            #expect(qtLauncher.contains("import \(contract.qtRuntimeDependency)"))
            #expect(qtLauncher.contains(contract.qtLauncherCall))
        }
        #expect(manifest.contains("#if !os(Linux)\nproducts.append(.executable(name: \"quill-enchanted-qt\", targets: [\"QuillEnchantedQt\"]))\nproducts.append(.executable(name: \"quill-wireguard-qt\", targets: [\"QuillWireGuardQt\"]))"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .qt {"))
        #expect(manifest.contains("let quillCanonicalLinuxAppProducts: [Product] = quillCanonicalLinuxApps.map(\\.productDeclaration)"))
        #expect(manifest.contains("let quillGenericQtSwiftSettings: [SwiftSetting] ="))
        #expect(manifest.contains(".define(\"QUILLUI_GENERIC_QT_NATIVE_BACKEND\")"))
        #expect(manifest.contains("] + quillCanonicalLinuxApps.map(quillCanonicalLinuxAppQtTarget)"))
        #expect(manifest.contains(".library(name: \"QuillGenericQtNativeRuntime\", targets: [\"QuillGenericQtNativeRuntime\"])"))
        #expect(manifest.contains("name: \"QuillGenericQtNativeRuntime\""))
        #expect(manifest.contains("path: \"Sources/QuillGenericQtNativeRuntime\""))
        #expect(!manifest.contains("products = [\n        .executable(name: \"quill-enchanted-qt\""))
    }

    @Test("backend smoke matrix runner expands canonical rows")
    func backendSmokeMatrixRunnerExpandsCanonicalRows() throws {
        let root = try packageRoot()
        let runner = root.appendingPathComponent("scripts/run-linux-backend-smoke-matrix.sh")

        let visualRows = try runScript(
            runner,
            arguments: ["--dry-run", "visual", "app-matrix", ".qa/{product}-{backend}.png"]
        )
        #expect(visualRows.status == 0, Comment(rawValue: visualRows.output))
        #expect(Self.lines(visualRows.output) == Self.expectedAppMatrixRows.map { row in
            let fields = row.split(separator: "\t").map(String.init)
            return Self.expectedVisualRow(product: fields[0], backend: fields[1])
        })

        let interactionRows = try runScript(
            runner,
            arguments: ["--dry-run", "interaction", "interaction-extra-mode-matrix", ".qa/{product}-{mode}-{backend}.png"]
        )
        #expect(interactionRows.status == 0, Comment(rawValue: interactionRows.output))
        #expect(Self.lines(interactionRows.output) == Self.expectedInteractionExtraModeRows)
    }

    @Test("source contracts describe canonical backend selection")
    func sourceContractsDescribeCanonicalBackendSelection() throws {
        let root = try packageRoot()
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"), encoding: .utf8)
        let interactionScript = try String(contentsOf: root.appendingPathComponent("scripts/linux-backend-interaction-check.sh"), encoding: .utf8)
        let productsScript = try String(contentsOf: root.appendingPathComponent("scripts/quillui-backend-products.sh"), encoding: .utf8)
        let smokeLib = try String(contentsOf: root.appendingPathComponent("scripts/quillui-linux-backend-smoke-lib.sh"), encoding: .utf8)
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let appTargets = try String(contentsOf: root.appendingPathComponent("docs/app-targets.md"), encoding: .utf8)
        let tooling = try String(contentsOf: root.appendingPathComponent("docs/linux-build-tooling.md"), encoding: .utf8)
        let uiPlan = try String(contentsOf: root.appendingPathComponent("docs/uitest-plan.md"), encoding: .utf8)
        let profileBaseline = try String(contentsOf: root.appendingPathComponent("docs/profile-baseline.md"), encoding: .utf8)

        #expect(workflow.contains("Each canonical app product compiles through the requested"))
        #expect(workflow.contains("scripts/build-linux-backend-products.sh --scratch-path .build-linux backend-apps"))
        #expect(!workflow.contains("native Qt products such as quill-enchanted-qt"))

        #expect(interactionScript.contains("[[ \"$PRODUCT\" == \"quill-wireguard\" && \"$SELECTED_BACKEND\" == \"gtk\" ]]"))
        #expect(interactionScript.contains("[[ \"$PRODUCT\" == \"quill-wireguard\" && \"$SELECTED_BACKEND\" == \"qt\" ]]"))
        #expect(interactionScript.contains("run_list_selection_or_header_interaction()"))
        #expect(interactionScript.contains("unsupported_backend_interaction_mode()"))
        #expect(interactionScript.contains("backend_label_for_message()"))
        #expect(interactionScript.contains("[[ \"$PRODUCT\" == \"quill-enchanted\" && ( \"$SELECTED_BACKEND\" == \"gtk\" || \"$SELECTED_BACKEND\" == \"qt\" ) ]]"))
        #expect(interactionScript.contains("run_list_selection_or_header_interaction \"Enchanted $(backend_label_for_message \"$SELECTED_BACKEND\")\" click_enchanted_list_selection"))
        #expect(interactionScript.contains("run_list_selection_or_header_interaction \"chat GTK\" click_chat_list_selection"))
        #expect(interactionScript.contains("run_list_selection_or_header_interaction \"generic GTK\" click_generic_backend_list_selection"))
        #expect(interactionScript.contains("run_list_selection_or_header_interaction \"generic Qt\" click_generic_backend_list_selection"))
        #expect(interactionScript.contains("quillui_is_backend_chat_gtk_list_selection_app_product \"$PRODUCT\""))
        #expect(interactionScript.contains("INTERACTION_MODE=\"$(quillui_backend_default_interaction_mode_for_product \"$PRODUCT\")\""))
        #expect(!interactionScript.contains("quill-wireguard|quill-wireguard-qt)"))

        #expect(productsScript.contains("quillui_backend_default_interaction_mode_for_product()"))
        #expect(productsScript.contains("default-interaction-mode)"))

        #expect(smokeLib.contains("verify_product=\"quill-enchanted-qt\""))
        #expect(smokeLib.contains("verify_product=\"quill-wireguard-qt\""))
        #expect(smokeLib.contains("quillui_backend_interaction_verify_product()"))
        #expect(smokeLib.contains("quillui_backend_list_selection_verify_product()"))
        #expect(smokeLib.contains("list_selection_verify_product=\"$(quillui_backend_list_selection_verify_product \"$product\" \"$selected_backend\")\""))
        #expect(smokeLib.contains("quillui_backend_list_selection_start_environment_assignment()"))
        #expect(smokeLib.contains("selection_assignment=\"$(quillui_backend_list_selection_start_environment_assignment \"$product\" \"$selected_backend\")\""))
        #expect(smokeLib.contains("quill-enchanted-list-selection"))
        #expect(smokeLib.contains("verify_product=\"$product-list-selection\""))
        #expect(smokeLib.contains("quillui_is_backend_chat_gtk_list_selection_app_product \"$product\""))
        #expect(smokeLib.contains("verify_product=\"$product-qt-list-selection\""))

        for document in [readme, appTargets, tooling, uiPlan, profileBaseline] {
            #expect(document.contains("QUILLUI_LINUX_BACKEND=qt") || document.contains("runtime_backend=qt"))
            #expect(!document.contains("swift run quill-wireguard-qt"))
            #expect(!document.contains("native Qt rows such as `quill-wireguard-qt`"))
        }
        #expect(readme.contains("QUILLUI_LINUX_BACKEND=qt swift run quill-wireguard"))
        #expect(tooling.contains("scripts/build-linux-backend-products.sh --scratch-path .build-linux backend-apps"))
        #expect(uiPlan.contains("Canonical app products"))
        #expect(profileBaseline.contains("`runtime_backend=qt`"))
        #expect(profileBaseline.contains("`runtime_mode=native`"))
    }

    @Test("backend aliases and build stamps scope by selected backend")
    func backendAliasesAndBuildStampsScopeBySelectedBackend() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-backend-aliases-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let probe = temporaryDirectory.appendingPathComponent("probe.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        source "\(root.path)/scripts/quillui-backend-products.sh"
        source "\(root.path)/scripts/quillui-linux-backend-smoke-lib.sh"

        quillui_print_selection_env() {
          if (( ${#selection_env[@]} > 0 )); then
            printf '%s|' "${selection_env[@]}"
          fi
        }

        quillui_print_selection_keys() {
          local environment_key
          while IFS= read -r environment_key; do
            [[ -n "$environment_key" ]] || continue
            printf '%s|' "$environment_key"
          done < <(quillui_backend_generic_selection_environment_keys "$1")
        }

        unset QUILLUI_BACKEND QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_BACKEND_SKIP_BUILD
        export QUILLUI_GTK_APP_EXECUTABLE=/tmp/gtk-app
        export QUILLUI_QT_APP_EXECUTABLE=/tmp/qt-app
        export QUILLUI_GTK_SKIP_BUILD=0
        export QUILLUI_QT_SKIP_BUILD=1
        export QUILLUI_GTK_GENERIC_SELECTED_INDEX_ON_START=1
        export QUILLUI_QT_GENERIC_SELECTED_INDEX_ON_START=2
        export QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=3
        export QUILLUI_QT_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=4
        export QUILLUI_GTK_CHAT_SELECTED_THREAD_INDEX_ON_START=5
        export QUILLUI_QT_CHAT_SELECTED_THREAD_INDEX_ON_START=6
        export QUILLUI_GTK_SIGNAL_SELECTED_THREAD_INDEX_ON_START=7
        export QUILLUI_QT_SIGNAL_SELECTED_THREAD_INDEX_ON_START=8
        export QUILLUI_GTK_TELEGRAM_SELECTED_THREAD_INDEX_ON_START=9
        export QUILLUI_QT_TELEGRAM_SELECTED_THREAD_INDEX_ON_START=10
        export QUILLUI_GTK_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START=11
        export QUILLUI_QT_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START=12
        export QUILLUI_GTK_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START=13
        export QUILLUI_QT_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START=14
        export QUILLUI_GTK_CODEEDIT_SELECTED_FILE_INDEX_ON_START=15
        export QUILLUI_QT_CODEEDIT_SELECTED_FILE_INDEX_ON_START=16
        export QUILLUI_GTK_IINA_SELECTED_PLAYLIST_INDEX_ON_START=17
        export QUILLUI_QT_IINA_SELECTED_PLAYLIST_INDEX_ON_START=18

        quillui_export_backend_argument " Qt6 " quill-wireguard
        quillui_alias_backend_build_env
        quillui_alias_backend_interaction_env
        printf 'build-backend=%s\\n' "$QUILLUI_BACKEND"
        printf 'build-exe=%s\\n' "$QUILLUI_BACKEND_APP_EXECUTABLE"
        printf 'build-skip=%s\\n' "$QUILLUI_BACKEND_SKIP_BUILD"
        printf 'generic-selected-qt=%s\\n' "$QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START"
        printf 'enchanted-selected-qt=%s\\n' "$QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START"
        printf 'enchanted-selected-qt-legacy=%s\\n' "$QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"
        printf 'chat-selected-qt=%s\\n' "$QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START"
        printf 'signal-selected-qt=%s\\n' "$QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START"
        printf 'telegram-selected-qt=%s\\n' "$QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START"
        printf 'icecubes-selected-qt=%s\\n' "$QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START"
        printf 'netnewswire-selected-qt=%s\\n' "$QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START"
        printf 'codeedit-selected-qt=%s\\n' "$QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START"
        printf 'iina-selected-qt=%s\\n' "$QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START"

        unset QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START
        quillui_export_backend_argument gtk quill-wireguard
        quillui_alias_backend_interaction_env
        printf 'generic-selected-gtk=%s\\n' "$QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START"
        printf 'enchanted-selected-gtk=%s\\n' "$QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START"
        printf 'chat-selected-gtk=%s\\n' "$QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START"
        printf 'signal-selected-gtk=%s\\n' "$QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START"
        printf 'telegram-selected-gtk=%s\\n' "$QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START"
        printf 'icecubes-selected-gtk=%s\\n' "$QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START"
        printf 'netnewswire-selected-gtk=%s\\n' "$QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START"
        printf 'codeedit-selected-gtk=%s\\n' "$QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START"
        printf 'iina-selected-gtk=%s\\n' "$QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START"

        unset QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START
        printf 'signal-selection-keys=%s\\n' "$(quillui_print_selection_keys quill-signal)"
        printf 'telegram-selection-keys=%s\\n' "$(quillui_print_selection_keys quill-telegram)"
        printf 'enchanted-selection-keys=%s\\n' "$(quillui_print_selection_keys quill-enchanted-upstream-slice)"
        printf 'codeedit-gtk-selection-key=%s\\n' "$(quillui_backend_generic_gtk_selection_environment_key quill-codeedit)"
        printf 'signal-chat-gtk-selection-key=%s\\n' "$(quillui_backend_chat_gtk_selection_environment_key quill-signal)"
        printf 'telegram-chat-gtk-selection-key=%s\\n' "$(quillui_backend_chat_gtk_selection_environment_key quill-telegram)"
        if quillui_backend_generic_gtk_selection_environment_key quill-signal >/dev/null 2>&1; then
          echo unexpected-signal-gtk-key
          exit 1
        fi
        printf 'signal-gtk-selection-key=unsupported\\n'
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-signal qt list-selection
        printf 'generic-selection-env=%s\\n' "$(quillui_print_selection_env)"
        export QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START=4
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-signal qt list-selection
        printf 'signal-qt-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START
        export QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START=2
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-signal qt list-selection
        printf 'shared-chat-qt-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START
        export QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START=5
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-telegram qt list-selection
        printf 'telegram-qt-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START
        export QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START=2
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-icecubes qt list-selection
        printf 'icecubes-qt-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START
        export QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START=1
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-netnewswire qt list-selection
        printf 'netnewswire-qt-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START
        export QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START=2
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-codeedit qt list-selection
        printf 'codeedit-qt-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START
        export QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START=2
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-iina qt list-selection
        printf 'iina-qt-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START
        export QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START=3
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-icecubes gtk list-selection
        printf 'icecubes-gtk-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START
        export QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=4
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-netnewswire gtk list-selection
        printf 'netnewswire-gtk-generic-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START
        export QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START=1
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-codeedit gtk list-selection
        printf 'codeedit-gtk-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START
        export QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START=2
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-iina gtk list-selection
        printf 'iina-gtk-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START
        export QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=3
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-enchanted-upstream-slice gtk list-selection
        printf 'upstream-slice-gtk-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-enchanted qt list-selection "\(temporaryDirectory.path)/selection"
        printf 'enchanted-selection-env=%s\\n' "$(quillui_print_selection_env)"
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-enchanted gtk list-selection "\(temporaryDirectory.path)/selection"
        printf 'enchanted-gtk-selection-env=%s\\n' "$(quillui_print_selection_env)"
        test -f "\(temporaryDirectory.path)/selection/quill-enchanted-reference-home/.quillui/enchanted/enchanted-quilldata.sqlite"
        printf 'enchanted-gtk-fixture=ok\\n'
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-signal gtk list-selection
        printf 'gtk-selection-env=%s\\n' "$(quillui_print_selection_env)"
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-telegram gtk list-selection
        printf 'telegram-gtk-selection-env=%s\\n' "$(quillui_print_selection_env)"
        export QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START=2
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-signal gtk list-selection
        printf 'shared-chat-selection-env=%s\\n' "$(quillui_print_selection_env)"
        unset QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START
        selection_env=()
        quillui_append_backend_selection_start_environment selection_env quill-signal qt click
        printf 'click-selection-env=%s\\n' "$(quillui_print_selection_env)"

        quillui_unset_backend_scoped_app_environment
        printf 'scoped-generic-after-unset=%s/%s\\n' "${QUILLUI_GTK_GENERIC_SELECTED_INDEX_ON_START-unset}" "${QUILLUI_QT_GENERIC_SELECTED_INDEX_ON_START-unset}"
        printf 'scoped-icecubes-after-unset=%s/%s\\n' "${QUILLUI_GTK_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START-unset}" "${QUILLUI_QT_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START-unset}"
        printf 'scoped-netnewswire-after-unset=%s/%s\\n' "${QUILLUI_GTK_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START-unset}" "${QUILLUI_QT_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START-unset}"
        printf 'scoped-codeedit-after-unset=%s/%s\\n' "${QUILLUI_GTK_CODEEDIT_SELECTED_FILE_INDEX_ON_START-unset}" "${QUILLUI_QT_CODEEDIT_SELECTED_FILE_INDEX_ON_START-unset}"
        printf 'scoped-iina-after-unset=%s/%s\\n' "${QUILLUI_GTK_IINA_SELECTED_PLAYLIST_INDEX_ON_START-unset}" "${QUILLUI_QT_IINA_SELECTED_PLAYLIST_INDEX_ON_START-unset}"

        unset QUILLUI_BACKEND
        quillui_export_backend_argument "" quill-wireguard
        printf 'product-default=%s\\n' "$QUILLUI_BACKEND"
        quillui_export_backend_argument qt quill-wireguard
        printf 'product-explicit=%s\\n' "$QUILLUI_BACKEND"
        printf 'default-mode-signal=%s\\n' "$(quillui_backend_default_interaction_mode_for_product quill-signal)"
        printf 'default-mode-chat=%s\\n' "$(quillui_backend_default_interaction_mode_for_product quill-chat-linux)"
        printf 'default-mode-wireguard=%s\\n' "$(quillui_backend_default_interaction_mode_for_product quill-wireguard)"
        printf 'default-mode-smoke=%s\\n' "$(quillui_backend_default_interaction_mode_for_product quill-gtk-interaction-smoke)"

        launch_env=()
        quillui_append_backend_launch_environment launch_env quill-wireguard "" qt
        printf 'launch-env=%s\\n' "$(printf '%s|' "${launch_env[@]}")"

        runtime_env=()
        quillui_append_backend_runtime_environment runtime_env quill-icecubes "" "\(temporaryDirectory.path)/runtime" 900 620 0 gtk
        printf 'icecubes-runtime-env=%s\\n' "$(printf '%s|' "${runtime_env[@]}")"
        runtime_env=()
        quillui_append_backend_runtime_environment runtime_env quill-netnewswire "" "\(temporaryDirectory.path)/runtime" 900 620 0 gtk
        printf 'netnewswire-runtime-env=%s\\n' "$(printf '%s|' "${runtime_env[@]}")"

        if quillui_export_backend_argument qt quill-wireguard-qt 2>/dev/null; then
          echo unexpected-product
          exit 1
        fi
        printf 'missing-product=failed\\n'

        stamp_root="\(temporaryDirectory.path)/stamps"
        if quillui_require_backend_product_build_stamp "$stamp_root" quill-wireguard qt 2>/dev/null; then
          echo unexpected-stamp
          exit 1
        fi
        printf 'missing-stamp=failed\\n'
        quillui_record_backend_product_build "$stamp_root" quill-wireguard qt
        quillui_require_backend_product_build_stamp "$stamp_root" quill-wireguard qt
        printf 'qt-stamp=ok\\n'
        if quillui_require_backend_product_build_stamp "$stamp_root" quill-wireguard gtk 2>/dev/null; then
          echo unexpected-gtk-stamp
          exit 1
        fi
        printf 'gtk-stamp=missing\\n'

        """.write(to: probe, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: probe.path)

        let result = try runScript(probe)
        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("build-backend=qt"))
        #expect(result.output.contains("build-exe=/tmp/qt-app"))
        #expect(result.output.contains("build-skip=1"))
        #expect(result.output.contains("generic-selected-qt=2"))
        #expect(result.output.contains("enchanted-selected-qt=4"))
        #expect(result.output.contains("enchanted-selected-qt-legacy=4"))
        #expect(result.output.contains("chat-selected-qt=6"))
        #expect(result.output.contains("signal-selected-qt=8"))
        #expect(result.output.contains("telegram-selected-qt=10"))
        #expect(result.output.contains("icecubes-selected-qt=12"))
        #expect(result.output.contains("netnewswire-selected-qt=14"))
        #expect(result.output.contains("codeedit-selected-qt=16"))
        #expect(result.output.contains("iina-selected-qt=18"))
        #expect(result.output.contains("generic-selected-gtk=1"))
        #expect(result.output.contains("enchanted-selected-gtk=3"))
        #expect(result.output.contains("chat-selected-gtk=5"))
        #expect(result.output.contains("signal-selected-gtk=7"))
        #expect(result.output.contains("telegram-selected-gtk=9"))
        #expect(result.output.contains("icecubes-selected-gtk=11"))
        #expect(result.output.contains("netnewswire-selected-gtk=13"))
        #expect(result.output.contains("codeedit-selected-gtk=15"))
        #expect(result.output.contains("iina-selected-gtk=17"))
        #expect(result.output.contains("signal-selection-keys=QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START|QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START|"))
        #expect(result.output.contains("telegram-selection-keys=QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START|QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START|"))
        #expect(result.output.contains("enchanted-selection-keys=QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START|QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START|"))
        #expect(result.output.contains("codeedit-gtk-selection-key=QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START"))
        #expect(result.output.contains("signal-chat-gtk-selection-key=QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START"))
        #expect(result.output.contains("telegram-chat-gtk-selection-key=QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START"))
        #expect(result.output.contains("signal-gtk-selection-key=unsupported"))
        #expect(result.output.contains("generic-selection-env=QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=0|"))
        #expect(result.output.contains("signal-qt-selection-env=QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=4|"))
        #expect(result.output.contains("shared-chat-qt-selection-env=QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=2|"))
        #expect(result.output.contains("telegram-qt-selection-env=QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=5|"))
        #expect(result.output.contains("icecubes-qt-selection-env=QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=2|"))
        #expect(result.output.contains("netnewswire-qt-selection-env=QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=1|"))
        #expect(result.output.contains("codeedit-qt-selection-env=QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=2|"))
        #expect(result.output.contains("iina-qt-selection-env=QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=2|"))
        #expect(result.output.contains("icecubes-gtk-selection-env=QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START=3|"))
        #expect(result.output.contains("netnewswire-gtk-generic-selection-env=QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START=4|"))
        #expect(result.output.contains("codeedit-gtk-selection-env=QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START=1|"))
        #expect(result.output.contains("iina-gtk-selection-env=QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START=2|"))
        #expect(result.output.contains("upstream-slice-gtk-selection-env=QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=3|"))
        #expect(result.output.contains("enchanted-selection-env=QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=0|"))
        #expect(result.output.contains("enchanted-gtk-selection-env=HOME=\(temporaryDirectory.path)/selection/quill-enchanted-reference-home|QUILLDATA_HOME=\(temporaryDirectory.path)/selection/quill-enchanted-reference-home|QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=0|"))
        #expect(result.output.contains("enchanted-gtk-fixture=ok"))
        #expect(result.output.contains("gtk-selection-env=QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START=1|"))
        #expect(result.output.contains("telegram-gtk-selection-env=QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START=1|"))
        #expect(result.output.contains("shared-chat-selection-env=QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START=2|"))
        #expect(result.output.contains("click-selection-env=\n"))
        #expect(result.output.contains("scoped-generic-after-unset=unset/unset"))
        #expect(result.output.contains("scoped-icecubes-after-unset=unset/unset"))
        #expect(result.output.contains("scoped-netnewswire-after-unset=unset/unset"))
        #expect(result.output.contains("scoped-codeedit-after-unset=unset/unset"))
        #expect(result.output.contains("scoped-iina-after-unset=unset/unset"))
        #expect(result.output.contains("product-default=gtk"))
        #expect(result.output.contains("product-explicit=qt"))
        #expect(result.output.contains("launch-env=GTK_A11Y=none|QUILLUI_BACKEND=qt|"))
        #expect(result.output.contains("icecubes-runtime-env=GTK_A11Y=none|QUILLUI_BACKEND=gtk|QUILLUI_DISABLE_FETCH=1|"))
        #expect(result.output.contains("netnewswire-runtime-env=GTK_A11Y=none|QUILLUI_BACKEND=gtk|QUILLUI_DISABLE_FETCH=1|"))
        #expect(result.output.contains("default-mode-signal=click"))
        #expect(result.output.contains("default-mode-chat=toolbar-menu"))
        #expect(result.output.contains("default-mode-wireguard=tunnel-name-edit"))
        #expect(result.output.contains("default-mode-smoke=open-panel"))
        #expect(result.output.contains("missing-product=failed"))
        #expect(result.output.contains("missing-stamp=failed"))
        #expect(result.output.contains("qt-stamp=ok"))
        #expect(result.output.contains("gtk-stamp=missing"))
    }

    @Test("build preparation helper accepts only Linux build backends")
    func buildPreparationHelperAcceptsOnlyLinuxBuildBackends() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/prepare-linux-build-backend.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-backend-prepare-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let qt = try runScript(
            script,
            arguments: ["--backend", "Qt6", "--scratch-path", temporaryDirectory.path]
        )
        #expect(qt.status == 0, Comment(rawValue: qt.output))

        let environmentQt = try runScript(
            script,
            arguments: ["--scratch-path", temporaryDirectory.path],
            environment: ["QUILLUI_LINUX_BACKEND": " qt6 "]
        )
        #expect(environmentQt.status == 0, Comment(rawValue: environmentQt.output))

        let unsupported = try runScript(
            script,
            arguments: ["--backend", "swiftui", "--scratch-path", temporaryDirectory.path]
        )
        #expect(unsupported.status == 64)
        #expect(unsupported.output.contains("Unsupported QuillUI Linux build backend: swiftui; expected gtk or qt."))
    }

    @Test("profile budget rejects runtime drift")
    func profileBudgetRejectsRuntimeDrift() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/check-linux-backend-profile-budget.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-budget-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let goodCSV = temporaryDirectory.appendingPathComponent("good.csv")
        try """
        \(Self.profileCSVHeader)
        quill-netnewswire,qt,qt,native,1,2,3,0.1,0.1,ok
        quill-chat-linux,qt,qt,native,1,2,3,0.1,0.1,ok
        quill-qt-interaction-smoke,qt,qt,native,1,2,3,0.1,0.1,ok

        """.write(to: goodCSV, atomically: true, encoding: .utf8)

        let good = try runScript(
            script,
            arguments: [goodCSV.path, "--max-rss-kb", "400000", "--max-startup-ms", "10000", "--max-cpu-pct", "99"]
        )
        #expect(good.status == 0, Comment(rawValue: good.output))

        let badCSV = temporaryDirectory.appendingPathComponent("bad.csv")
        try """
        \(Self.profileCSVHeader)
        quill-netnewswire,qt,gtk,platformFallback,1,2,3,0.1,0.1,ok

        """.write(to: badCSV, atomically: true, encoding: .utf8)

        let bad = try runScript(
            script,
            arguments: [badCSV.path, "--max-rss-kb", "400000", "--max-startup-ms", "10000", "--max-cpu-pct", "99"]
        )
        #expect(bad.status != 0)
        #expect(bad.output.contains("runtime_backend=gtk does not match requested_backend=qt expected_runtime=qt"))

        let badGeneratedCSV = temporaryDirectory.appendingPathComponent("bad-generated.csv")
        try """
        \(Self.profileCSVHeader)
        quill-chat-linux,qt,gtk,platformFallback,1,2,3,0.1,0.1,ok

        """.write(to: badGeneratedCSV, atomically: true, encoding: .utf8)

        let badGenerated = try runScript(
            script,
            arguments: [badGeneratedCSV.path, "--max-rss-kb", "400000", "--max-startup-ms", "10000", "--max-cpu-pct", "99"]
        )
        #expect(badGenerated.status != 0)
        #expect(badGenerated.output.contains("runtime_backend=gtk does not match requested_backend=qt expected_runtime=qt"))
    }

    @Test("profile CSV runner expands canonical backend matrix")
    func profileCSVRunnerExpandsCanonicalBackendMatrix() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-canonical-matrix-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let csv = temporaryDirectory.appendingPathComponent("profile.csv")
        let fakeProfiler = temporaryDirectory.appendingPathComponent("matrix-profiler.sh")
        try """
        #!/usr/bin/env bash
        product="$1"
        backend="${4:-}"
        if [[ -z "$backend" ]]; then
          exit 43
        fi
        if [[ "$backend" != "${QUILLUI_BACKEND:-}" ]]; then
          exit 44
        fi
        echo "$product,1,2,3,4.0,5.0,ok"

        """.write(to: fakeProfiler, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProfiler.path)

        let result = try runScript(
            script,
            arguments: ["--matrix", "profile-matrix", csv.path],
            environment: ["QUILLUI_BACKEND_PROFILE_COMMAND": fakeProfiler.path]
        )

        let expected = """
        \(Self.profileCSVHeader)
        \(Self.expectedProfileRuntimeRows.map { row in
            let fields = row.split(separator: "\t").map(String.init)
            return "\(fields[0]),\(fields[1]),\(fields[2]),\(fields[3]),1,2,3,4.0,5.0,ok"
        }.joined(separator: "\n"))

        """

        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(result.output == expected)
        #expect(try String(contentsOf: csv, encoding: .utf8) == expected)
    }

    private func runScript(
        _ script: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        stdin: String? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        if let stdin {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            try process.run()
            inputPipe.fileHandleForWriting.write(Data(stdin.utf8))
            inputPipe.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }
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
            domain: "LinuxBackendAppMatrixTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }
}
