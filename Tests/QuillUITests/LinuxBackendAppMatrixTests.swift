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

    private static let expectedBackends = ["gtk", "qt"]
    private static let expectedGeneratedAppProducts = ["quill-chat-linux"]
    private static let expectedSmokeProducts = ["quill-gtk-interaction-smoke", "quill-qt-interaction-smoke"]
    private static let profileCSVHeader = "product,requested_backend,runtime_backend,runtime_mode,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"

    private static var expectedAppMatrixRows: [String] {
        expectedAppProducts.flatMap { product in
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
            + expectedGeneratedAppProducts.flatMap { product in
                expectedBackends.map { backend in "\(product)\t\(backend)\t\(backend)\tnative" }
            }
            + [
                "quill-gtk-interaction-smoke\tgtk\tgtk\tnative",
                "quill-qt-interaction-smoke\tqt\tqt\tnative"
            ]
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

        let legacyProducts = try runScript(legacyMatrixScript)
        #expect(legacyProducts.status == 0, Comment(rawValue: legacyProducts.output))
        #expect(legacyProducts.output == appProducts.output)

        let appBackends = try runScript(script, arguments: ["app-backends"])
        #expect(appBackends.status == 0, Comment(rawValue: appBackends.output))
        #expect(Self.lines(appBackends.output) == Self.expectedBackends)

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
        #expect(Self.lines(nativeRuntimes.output) == Self.expectedBackends)

        let runtimeAvailabilities = try runScript(script, arguments: ["runtime-availabilities"])
        #expect(runtimeAvailabilities.status == 0, Comment(rawValue: runtimeAvailabilities.output))
        #expect(Self.lines(runtimeAvailabilities.output) == [
            "gtk\tgtk\tnative",
            "qt\tqt\tnative"
        ])

        let nativeOverrides = try runScript(script, arguments: ["native-product-runtime-overrides"])
        #expect(nativeOverrides.status == 0, Comment(rawValue: nativeOverrides.output))
        #expect(Self.lines(nativeOverrides.output) == ["quill-qt-interaction-smoke\tqt\tqt"])

        let integrity = try runScript(script, arguments: ["validate-integrity"])
        #expect(integrity.status == 0, Comment(rawValue: integrity.output))
        #expect(integrity.output.contains("backend product matrix ok"))

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
            #expect(manifest.contains(".executable(name: \"\(contract.product)\", targets: [\"\(contract.target)\"])"))
            #expect(manifest.contains("name: \"\(contract.target)\""))
            #expect(manifest.contains("dependencies: [\"\(contract.qtRuntimeDependency)\"]"))
            #expect(manifest.contains("path: \"\(contract.qtPath)\""))

            let qtMain = root
                .appendingPathComponent(contract.qtPath)
                .appendingPathComponent("main.swift")
            #expect(
                FileManager.default.fileExists(atPath: qtMain.path),
                Comment(rawValue: "\(contract.product) must have an explicit Qt launcher")
            )

            let qtLauncher = try String(contentsOf: qtMain, encoding: .utf8)
            #expect(qtLauncher.contains("import \(contract.qtRuntimeDependency)"))
            #expect(qtLauncher.contains(contract.qtLauncherCall))
        }
        #expect(manifest.contains("#if !os(Linux)\nproducts.append(.executable(name: \"quill-enchanted-qt\", targets: [\"QuillEnchantedQt\"]))\nproducts.append(.executable(name: \"quill-wireguard-qt\", targets: [\"QuillWireGuardQt\"]))"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .qt {"))
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
            return "visual\t\(fields[0])\t\(fields[1])\t\(fields[1])\tnative\t.qa/\(fields[0])-\(fields[1]).png\t0"
        })

        let interactionRows = try runScript(
            runner,
            arguments: ["--dry-run", "interaction", "interaction-extra-mode-matrix", ".qa/{product}-{mode}-{backend}.png"]
        )
        #expect(interactionRows.status == 0, Comment(rawValue: interactionRows.output))
        #expect(Self.lines(interactionRows.output) == [
            "interaction\tquill-wireguard\tgtk\tgtk\tnative\t.qa/quill-wireguard-import-paste-gtk.png\t0\timport-paste",
            "interaction\tquill-wireguard\tgtk\tgtk\tnative\t.qa/quill-wireguard-import-file-gtk.png\t0\timport-file",
            "interaction\tquill-wireguard\tgtk\tgtk\tnative\t.qa/quill-wireguard-import-invalid-paste-gtk.png\t0\timport-invalid-paste",
            "interaction\tquill-wireguard\tgtk\tgtk\tnative\t.qa/quill-wireguard-import-invalid-file-gtk.png\t0\timport-invalid-file",
            "interaction\tquill-wireguard\tqt\tqt\tnative\t.qa/quill-wireguard-import-paste-qt.png\t0\timport-paste",
            "interaction\tquill-wireguard\tqt\tqt\tnative\t.qa/quill-wireguard-import-file-qt.png\t0\timport-file",
            "interaction\tquill-wireguard\tqt\tqt\tnative\t.qa/quill-wireguard-import-invalid-paste-qt.png\t0\timport-invalid-paste",
            "interaction\tquill-wireguard\tqt\tqt\tnative\t.qa/quill-wireguard-import-invalid-file-qt.png\t0\timport-invalid-file"
        ])
    }

    @Test("source contracts describe canonical backend selection")
    func sourceContractsDescribeCanonicalBackendSelection() throws {
        let root = try packageRoot()
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"), encoding: .utf8)
        let interactionScript = try String(contentsOf: root.appendingPathComponent("scripts/linux-backend-interaction-check.sh"), encoding: .utf8)
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
        #expect(!interactionScript.contains("quill-wireguard|quill-wireguard-qt)"))

        #expect(smokeLib.contains("verify_product=\"quill-enchanted-qt\""))
        #expect(smokeLib.contains("verify_product=\"quill-wireguard-qt\""))

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

        unset QUILLUI_BACKEND QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_BACKEND_SKIP_BUILD
        export QUILLUI_GTK_APP_EXECUTABLE=/tmp/gtk-app
        export QUILLUI_QT_APP_EXECUTABLE=/tmp/qt-app
        export QUILLUI_GTK_SKIP_BUILD=0
        export QUILLUI_QT_SKIP_BUILD=1

        quillui_export_backend_argument " Qt6 " quill-wireguard
        quillui_alias_backend_build_env
        printf 'build-backend=%s\\n' "$QUILLUI_BACKEND"
        printf 'build-exe=%s\\n' "$QUILLUI_BACKEND_APP_EXECUTABLE"
        printf 'build-skip=%s\\n' "$QUILLUI_BACKEND_SKIP_BUILD"

        unset QUILLUI_BACKEND
        quillui_export_backend_argument "" quill-wireguard
        printf 'product-default=%s\\n' "$QUILLUI_BACKEND"
        quillui_export_backend_argument qt quill-wireguard
        printf 'product-explicit=%s\\n' "$QUILLUI_BACKEND"

        launch_env=()
        quillui_append_backend_launch_environment launch_env quill-wireguard "" qt
        printf 'launch-env=%s\\n' "$(printf '%s|' "${launch_env[@]}")"

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
        #expect(result.output.contains("product-default=gtk"))
        #expect(result.output.contains("product-explicit=qt"))
        #expect(result.output.contains("launch-env=GTK_A11Y=none|QUILLUI_BACKEND=qt|"))
        #expect(result.output.contains("missing-product=failed"))
        #expect(result.output.contains("missing-stamp=failed"))
        #expect(result.output.contains("qt-stamp=ok"))
        #expect(result.output.contains("gtk-stamp=missing"))
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
