import Foundation
import Testing

@Suite("Vendored source pipeline")
struct VendoredSourcePipelineTests {
    @Test("Release packager preserves app source identity for vendored builds")
    func releasePackagerPreservesAppSourceIdentity() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/package-swiftui-linux-app.sh"),
            encoding: .utf8
        )

        #expect(source.contains("SOURCE_APP=\"${QUILLUI_APP_SOURCE_APP:-}\""))
        #expect(source.contains("--source-app NAME"))
        #expect(source.contains("--source-subdir PATH"))
        #expect(source.contains("--source-dir and --source-app are mutually exclusive"))
        #expect(source.contains("BUILD_SOURCE_ARGS=(--source-app \"$SOURCE_APP\")"))
        #expect(source.contains("BUILD_SOURCE_ARGS+=(--source-subdir \"$SOURCE_SUBDIR\")"))
        #expect(source.contains("BUILD_SOURCE_ARGS=(--source-dir \"$SOURCE_DIR\")"))
        #expect(source.contains("\"${BUILD_SOURCE_ARGS[@]}\""))
    }

    @Test("Enchanted wrapper defaults to vendored source app builds")
    func enchantedWrapperDefaultsToVendoredSourceAppBuilds() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/build-enchanted-linux.sh"),
            encoding: .utf8
        )

        #expect(source.contains("SOURCE_ARGS=(--source-app enchanted --source-subdir Enchanted)"))
        #expect(source.contains("SOURCE_ARGS=(--source-dir \"$APP_DIR\")"))
        #expect(source.contains("\"${SOURCE_ARGS[@]}\""))
    }

    @Test("Enchanted parity release packaging uses source app identity")
    func enchantedParityReleasePackagingUsesSourceAppIdentity() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/enchanted-parity.yml"),
            encoding: .utf8
        )

        #expect(source.contains("scripts/package-swiftui-linux-app.sh"))
        #expect(source.contains("--source-app enchanted"))
        #expect(source.contains("--source-subdir Enchanted"))
        #expect(!source.contains("ENCHANTED_APP_DIR=\"$(quillui_resolve_enchanted_source_dir \"$PWD\")\""))
    }

    @Test("QuillCode SwiftPM dependency sources are vendored without bulky artifacts")
    func quillCodeSwiftPMDependencySourcesAreVendoredWithoutBulkyArtifacts() throws {
        let root = try packageRoot()
        let trackedFiles = try gitTrackedFiles(in: root)
        guard !trackedFiles.isEmpty else {
            return
        }

        for path in [
            "third_party/CodeEditSourceEditor/Package.swift",
            "third_party/CodeEditTextView/Package.swift",
            "third_party/CodeEditLanguages/Package.swift",
            "third_party/SwiftTreeSitter/Package.swift",
            "third_party/tree-sitter/Package.swift",
            "third_party/swift-collections/Package.swift",
            "third_party/LanguageClient/Package.swift",
            "third_party/AnyCodable/Package.swift",
            "third_party/SwiftUIIntrospect/Package.swift",
            "third_party/AsyncAlgorithms/Package.swift"
        ] {
            #expect(trackedFiles.contains(path), Comment(rawValue: "Missing vendored package source: \(path)"))
        }

        for path in trackedFiles {
            #expect(!path.hasPrefix("third_party/CodeEditLanguages/.github/"))
            #expect(!path.hasPrefix("third_party/CodeEditLanguages/Tests/"))
            #expect(!path.hasPrefix("third_party/tree-sitter/cli/"))
            #expect(!path.hasPrefix("third_party/tree-sitter/test/"))
            #expect(!path.hasPrefix("third_party/tree-sitter/docs/"))
            #expect(!path.hasPrefix("third_party/Sparkle/"))
            #expect(!path.contains("/TerminalApp/"))
            #expect(path != "third_party/SwiftTerm/Makefile")
            #expect(!path.hasSuffix(".xcframework.zip"))
        }
    }

    @Test("Generated package layout omits QuillUI-provided compatibility packages")
    func generatedPackageLayoutOmitsQuillUIProvidedCompatibilityPackages() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("QuillUIVendoredSourcePipeline-\(UUID().uuidString)")
        let packageRoot = scratch.appendingPathComponent("SampleDesktop")
        let sources = packageRoot.appendingPathComponent("Sources")
        let output = scratch.appendingPathComponent("Output")
        defer { try? fileManager.removeItem(at: scratch) }

        try fileManager.createDirectory(
            at: sources.appendingPathComponent("sample-desktop"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

        try write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "SampleDesktop",
                products: [.executable(name: "sample-desktop", targets: ["sample-desktop"])],
                dependencies: [
                    .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.3"),
                    .package(url: "https://example.com/tools.git", exact: "1.2.3")
                ],
                targets: [
                    .executableTarget(
                        name: "sample-desktop",
                        dependencies: [
                            .product(name: "Sparkle", package: "Sparkle"),
                            .product(name: "ExampleTools", package: "tools")
                        ]
                    )
                ]
            )
            """,
            to: packageRoot.appendingPathComponent("Package.swift")
        )
        try write(
            """
            import SwiftUI
            import Sparkle

            @main
            struct SampleDesktopApp: App {
                var body: some Scene { WindowGroup { Text("Hello") } }
            }
            """,
            to: sources.appendingPathComponent("sample-desktop/main.swift")
        )

        let layout = output.appendingPathComponent("layout.tsv")
        let dependencies = output.appendingPathComponent("dependencies.swift")
        let result = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/swiftpm-package-layout-for-linux.py").path,
                "--package-root", packageRoot.path,
                "--source-dir", sources.path,
                "--app-type", "SampleDesktopApp",
                "--generated-target", "GeneratedSwiftUILinuxApp",
                "--layout-out", layout.path,
                "--dependencies-out", dependencies.path
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(try String(contentsOf: layout, encoding: .utf8) == """
        GeneratedSwiftUILinuxApp\tsample-desktop\tproduct:ExampleTools:tools

        """)
        #expect(try String(contentsOf: dependencies, encoding: .utf8) == """
        .package(url: "https://example.com/tools.git", exact: "1.2.3")

        """)
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func gitTrackedFiles(in root: URL) throws -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root.path, "ls-files"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return []
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        return Set(text.split(separator: "\n").map(String.init))
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func run(
        _ executable: URL,
        arguments: [String]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
