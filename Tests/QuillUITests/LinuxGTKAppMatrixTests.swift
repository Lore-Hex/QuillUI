import Foundation
import Testing

@Suite("Linux GTK app matrix")
struct LinuxGTKAppMatrixTests {
    @Test("covers each user-facing app product once")
    func coversEachUserFacingAppProductOnce() throws {
        let root = try packageRoot()
        let matrixScript = root.appendingPathComponent("scripts/linux-gtk-app-products.sh")

        let result = try runScript(matrixScript)
        #expect(result.status == 0, Comment(rawValue: result.output))

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
        #expect(workflow.contains("scripts/linux-gtk-app-products.sh"))
        #expect(workflow.contains("scripts/run-linux-gtk-profile-csv.sh /tmp/quillui-profile.csv"))
        #expect(workflow.contains("scripts/check-linux-gtk-profile-budget.sh /tmp/quillui-profile.csv"))
        #expect(!workflow.contains("QuillSignal GTK visual smoke"))
        #expect(!workflow.contains("for product in quill-signal quill-telegram"))
        #expect(!workflow.contains("< <("))
    }

    @Test("profile budget accepts current rows and rejects bad profile rows")
    func profileBudgetAcceptsCurrentRowsAndRejectsBadRows() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/check-linux-gtk-profile-budget.sh")
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
        let script = root.appendingPathComponent("scripts/run-linux-gtk-profile-csv.sh")
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
            environment: ["QUILLUI_GTK_PROFILE_COMMAND": fakeProfiler.path]
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
