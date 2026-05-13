import Foundation
import Testing

@Suite("Linux GTK app matrix")
struct LinuxGTKAppMatrixTests {
    @Test("covers each user-facing app product once")
    func coversEachUserFacingAppProductOnce() throws {
        let root = try packageRoot()
        let matrixScript = root.appendingPathComponent("scripts/quillui-backend-products.sh")
        let legacyMatrixScript = root.appendingPathComponent("scripts/linux-gtk-app-products.sh")

        let result = try runScript(matrixScript, arguments: ["gtk-apps"])
        #expect(result.status == 0, Comment(rawValue: result.output))
        let legacyResult = try runScript(legacyMatrixScript)
        #expect(legacyResult.status == 0, Comment(rawValue: legacyResult.output))
        #expect(legacyResult.output == result.output)

        let products = result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let expected = [
            "quill-enchanted",
            "quill-enchanted-upstream-slice",
            "quill-icecubes",
            "quill-netnewswire",
            "quill-codeedit",
            "quill-signal",
            "quill-telegram",
            "quill-iina",
            "quill-wireguard"
        ]

        #expect(products == expected)
        #expect(Set(products).count == products.count)

        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        for product in products {
            #expect(manifest.contains(".executable(name: \"\(product)\""))
        }

        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"),
            encoding: .utf8
        )
        #expect(workflow.contains("scripts/quillui-backend-products.sh gtk-apps"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh smoke-products | while IFS= read -r product; do"))
        #expect(workflow.contains("scripts/linux-backend-visual-check.sh .qa/quill-chat-linux-generated-gtk.png quill-chat-linux"))
        #expect(workflow.contains("scripts/linux-backend-visual-check.sh \".qa/${product}-visual.png\" \"$product\""))
        #expect(workflow.contains("scripts/linux-backend-visual-check.sh \".qa/${product}-gtk.png\" \"$product\""))
        #expect(workflow.contains("scripts/quillui-backend-products.sh gtk-apps | scripts/run-linux-backend-profile-csv.sh /tmp/quillui-profile.csv"))
        #expect(workflow.contains("scripts/check-linux-backend-profile-budget.sh /tmp/quillui-profile.csv"))
        #expect(!workflow.contains("scripts/run-linux-gtk-profile-csv.sh /tmp/quillui-profile"))
        #expect(!workflow.contains("scripts/check-linux-gtk-profile-budget.sh /tmp/quillui-profile"))
        #expect(!workflow.contains("QuillSignal GTK visual smoke"))
        #expect(!workflow.contains("for product in quill-signal quill-telegram"))
        #expect(!workflow.contains("scripts/linux-gtk-visual-check.sh"))
        #expect(!workflow.contains("< <("))

        let gtkCheck = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-check.sh"),
            encoding: .utf8
        )
        #expect(gtkCheck.contains("scripts/quillui-backend-products.sh gtk-apps"))
        #expect(gtkCheck.contains("for product in \"${APP_PRODUCTS[@]}\""))
        #expect(gtkCheck.contains("swift build --scratch-path .build-linux --product \"$product\""))
        #expect(gtkCheck.contains("run_smoke \"$product\""))
        #expect(!gtkCheck.contains("run_smoke quill-enchanted"))
        #expect(!gtkCheck.contains("run_smoke quill-enchanted-upstream-slice"))

        let profileScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-profile.sh"),
            encoding: .utf8
        )
        let legacyProfileScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-profile.sh"),
            encoding: .utf8
        )
        let visualScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-visual-check.sh"),
            encoding: .utf8
        )
        let smokeLib = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-linux-backend-smoke-lib.sh"),
            encoding: .utf8
        )
        let legacyVisualScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-visual-check.sh"),
            encoding: .utf8
        )
        let csvRunner = try String(
            contentsOf: root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh"),
            encoding: .utf8
        )
        let legacyCSVRunner = try String(
            contentsOf: root.appendingPathComponent("scripts/run-linux-gtk-profile-csv.sh"),
            encoding: .utf8
        )
        let budgetScript = try String(
            contentsOf: root.appendingPathComponent("scripts/check-linux-backend-profile-budget.sh"),
            encoding: .utf8
        )
        let legacyBudgetScript = try String(
            contentsOf: root.appendingPathComponent("scripts/check-linux-gtk-profile-budget.sh"),
            encoding: .utf8
        )
        let backendProducts = try String(contentsOf: matrixScript, encoding: .utf8)
        #expect(backendProducts.contains("quillui_alias_env()"))
        #expect(profileScript.contains("source \"$ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(legacyProfileScript.contains("linux-backend-profile.sh"))
        #expect(visualScript.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(smokeLib.contains("source \"$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(smokeLib.contains("quillui_install_linux_backend_smoke_packages()"))
        #expect(smokeLib.contains("quillui_resolve_linux_backend_executable()"))
        #expect(smokeLib.contains("quillui_seed_quill_chat_reference_data()"))
        #expect(legacyVisualScript.contains("scripts/linux-backend-visual-check.sh"))
        #expect(!legacyVisualScript.contains("quillui_alias_env"))
        #expect(profileScript.contains("quillui_requested_backend_for_product \"$PRODUCT\""))
        #expect(profileScript.contains("app_environment+=(QUILLUI_BACKEND=\"$requested_backend\")"))
        #expect(profileScript.contains("QUILLUI_BACKEND_PROFILE_DISPLAY"))
        #expect(visualScript.contains("quillui_alias_env QUILLUI_BACKEND_VISUAL_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE"))
        #expect(visualScript.contains("quillui_alias_env QUILLUI_BACKEND_VERIFY_PRODUCT QUILLUI_GTK_VERIFY_PRODUCT"))
        #expect(visualScript.contains("quillui_resolve_linux_backend_executable \"$PRODUCT\" APP_EXECUTABLE"))
        #expect(visualScript.contains("quillui_requested_backend_for_product \"$PRODUCT\""))
        #expect(visualScript.contains("app_environment+=(QUILLUI_BACKEND=\"$requested_backend\")"))
        #expect(visualScript.contains("verify-backend-screenshot.py"))
        #expect(!visualScript.contains("verify-gtk-screenshot.py"))
        #expect(!visualScript.contains("install_packages()"))
        #expect(!visualScript.contains("build_and_resolve_executable()"))
        #expect(csvRunner.contains("QUILLUI_BACKEND_PROFILE_COMMAND"))
        #expect(csvRunner.contains("$ROOT_DIR/scripts/linux-backend-profile.sh"))
        #expect(csvRunner.contains("QUILLUI_BACKEND_PROFILE_SETTLE"))
        #expect(legacyCSVRunner.contains("run-linux-backend-profile-csv.sh"))
        #expect(budgetScript.contains("QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT"))
        #expect(legacyBudgetScript.contains("check-linux-backend-profile-budget.sh"))
    }

    @Test("backend product helper maps GTK and Qt defaults")
    func backendProductHelperMapsDefaults() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/quillui-backend-products.sh")

        let smokeProducts = try runScript(script, arguments: ["smoke-products"])
        #expect(smokeProducts.status == 0, Comment(rawValue: smokeProducts.output))
        #expect(smokeProducts.output.split(whereSeparator: \.isNewline).map(String.init) == [
            "quill-gtk-interaction-smoke",
            "quill-qt-interaction-smoke"
        ])

        let qtBackend = try runScript(script, arguments: ["backend-for-product", "quill-qt-interaction-smoke"])
        #expect(qtBackend.status == 0, Comment(rawValue: qtBackend.output))
        #expect(qtBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")

        let gtkBackend = try runScript(script, arguments: ["backend-for-product", "quill-icecubes"])
        #expect(gtkBackend.status == 0, Comment(rawValue: gtkBackend.output))
        #expect(gtkBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "gtk")

        let overrideBackend = try runScript(
            script,
            arguments: ["requested-backend", "quill-icecubes"],
            environment: ["QUILLUI_BACKEND": "qt"]
        )
        #expect(overrideBackend.status == 0, Comment(rawValue: overrideBackend.output))
        #expect(overrideBackend.output.trimmingCharacters(in: .whitespacesAndNewlines) == "qt")
    }

    @Test("profile budget accepts current rows and rejects bad profile rows")
    func profileBudgetAcceptsCurrentRowsAndRejectsBadRows() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/check-linux-backend-profile-budget.sh")
        let fileManager = FileManager.default
        let csv = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-\(UUID().uuidString).csv")
        defer { try? fileManager.removeItem(at: csv) }

        try """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        quill-icecubes,13148,6,236156,3.0,2.8,ok
        quill-netnewswire,13105,6,235852,5.8,5.6,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let passing = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(passing.status == 0, Comment(rawValue: passing.output))
        #expect(passing.output.contains("profile budget ok: quill-icecubes"))
        #expect(passing.output.contains("profile budget ok: quill-netnewswire"))

        try """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        quill-icecubes,13148,6,236156,3.0,135.2,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let failing = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(failing.status != 0)
        #expect(failing.output.contains("cpu_pct_steady=135.2"))

        try """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        quill-icecubes,13148,nope,236156,3.0,2.8,ok

        """.write(to: csv, atomically: true, encoding: .utf8)

        let malformed = try runScript(script, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(malformed.status != 0)
        #expect(malformed.output.contains("startup_ms=nope is not a non-negative integer"))
    }

    @Test("profile CSV runner shares header and failure-tolerant product loop")
    func profileCSVRunnerSharesHeaderAndFailureTolerantProductLoop() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-runner-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let csv = temporaryDirectory.appendingPathComponent("profile.csv")
        let fakeProfiler = temporaryDirectory.appendingPathComponent("fake-profiler.sh")
        try """
        #!/usr/bin/env bash
        product="$1"
        echo "$product,1,2,3,4.0,5.0,ok"
        if [[ "$product" == "second-product" ]]; then
          exit 7
        fi

        """.write(to: fakeProfiler, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProfiler.path)

        let result = try runScript(
            script,
            arguments: [csv.path, "first-product", "second-product"],
            environment: ["QUILLUI_BACKEND_PROFILE_COMMAND": fakeProfiler.path]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        let expected = """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        first-product,1,2,3,4.0,5.0,ok
        second-product,1,2,3,4.0,5.0,ok

        """
        #expect(result.output == expected)
        let writtenCSV = try String(contentsOf: csv, encoding: .utf8)
        #expect(writtenCSV == expected)
    }

    @Test("profile CSV runner records profilers that fail before emitting rows")
    func profileCSVRunnerRecordsSilentProfilerFailures() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/run-linux-backend-profile-csv.sh")
        let budgetScript = root.appendingPathComponent("scripts/check-linux-backend-profile-budget.sh")
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-profile-silent-failure-\(UUID().uuidString)")
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let csv = temporaryDirectory.appendingPathComponent("profile.csv")
        let fakeProfiler = temporaryDirectory.appendingPathComponent("silent-profiler.sh")
        try """
        #!/usr/bin/env bash
        exit 42

        """.write(to: fakeProfiler, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeProfiler.path)

        let result = try runScript(
            script,
            arguments: [csv.path, "silent-product"],
            environment: ["QUILLUI_GTK_PROFILE_COMMAND": fakeProfiler.path]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        let expected = """
        product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status
        silent-product,0,0,0,0.0,0.0,profiler-exit-42

        """
        #expect(result.output == expected)
        #expect(try String(contentsOf: csv, encoding: .utf8) == expected)

        let budget = try runScript(budgetScript, arguments: [csv.path, "--max-cpu-pct", "25"])
        #expect(budget.status != 0)
        #expect(budget.output.contains("silent-product exit_status=profiler-exit-42"))
    }

    private func runScript(
        _ script: URL,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }

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
            domain: "LinuxGTKAppMatrixTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }
}
