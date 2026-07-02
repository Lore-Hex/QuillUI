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
        #expect(source.contains("Audit vendored Enchanted SwiftPM sources"))
        #expect(source.contains("scripts/vendor-swiftpm-sources.sh --app enchanted --no-resolve --check-vendored"))
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

    @Test("Enchanted SwiftPM dependency sources are vendored for offline app builds")
    func enchantedSwiftPMDependencySourcesAreVendoredForOfflineAppBuilds() throws {
        let root = try packageRoot()
        let trackedFiles = try gitTrackedFiles(in: root)
        guard !trackedFiles.isEmpty else {
            return
        }

        for path in [
            "third_party/ActivityIndicatorView/Package.swift",
            "third_party/Alamofire/Package.swift",
            "third_party/KeyboardShortcuts/Package.swift",
            "third_party/Magnet/Package.swift",
            "third_party/MarkdownUI/Package.swift",
            "third_party/NetworkImage/Package.swift",
            "third_party/OllamaKit/Package.swift",
            "third_party/Sauce/Package.swift",
            "third_party/Splash/Package.swift",
            "third_party/SwiftCMark/Package.swift",
            "third_party/Vortex/Package.swift",
            "third_party/WrappingHStack/Package.swift"
        ] {
            #expect(trackedFiles.contains(path), Comment(rawValue: "Missing Enchanted vendored source: \(path)"))
        }

        for path in trackedFiles {
            guard path.hasPrefix("third_party/ActivityIndicatorView/")
                || path.hasPrefix("third_party/Alamofire/")
                || path.hasPrefix("third_party/KeyboardShortcuts/")
                || path.hasPrefix("third_party/Magnet/")
                || path.hasPrefix("third_party/MarkdownUI/")
                || path.hasPrefix("third_party/NetworkImage/")
                || path.hasPrefix("third_party/OllamaKit/")
                || path.hasPrefix("third_party/Sauce/")
                || path.hasPrefix("third_party/Splash/")
                || path.hasPrefix("third_party/SwiftCMark/")
                || path.hasPrefix("third_party/Vortex/")
                || path.hasPrefix("third_party/WrappingHStack/")
            else {
                continue
            }

            #expect(!path.contains("/.git/"))
            #expect(!path.contains("/Tests/"))
            #expect(!path.contains("/test/"))
            #expect(!path.contains("/Demo/"))
            #expect(!path.contains("/Playground/"))
            #expect(!path.contains("/Sandbox/"))
            #expect(!path.contains(" Example/"))
            #expect(!path.contains("/.github/"))
            #expect(!path.contains("/docs/"))
            #expect(!path.contains("/Documentation/"))
            #expect(!path.contains(".docc/"))
            #expect(!path.contains("/Examples/"))
            #expect(!path.contains("/Assets/"))
            #expect(!path.contains("/Images/"))
            #expect(!path.contains("/tools/"))
            #expect(!path.contains("/wrappers/"))
            #expect(!path.contains("/Carthage/"))
            #expect(!path.contains(".xcodeproj/"))
            #expect(!path.contains(".xcworkspace/"))
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

    @Test("SwiftPM source vendoring accepts lockfile-discovered packages")
    func swiftPMSourceVendoringAcceptsLockfileDiscoveredPackages() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("QuillUIVendorUnknownPackage-\(UUID().uuidString)")
        let scripts = scratch.appendingPathComponent("scripts")
        let checkout = scratch
            .appendingPathComponent(".build")
            .appendingPathComponent("checkouts")
            .appendingPathComponent("CustomWidgets")
        let checkoutSources = checkout.appendingPathComponent("Sources/CustomWidgets")
        let resolved = scratch.appendingPathComponent("Package.resolved")
        defer { try? fileManager.removeItem(at: scratch) }

        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: checkoutSources, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: root.appendingPathComponent("scripts/vendor-swiftpm-sources.sh"),
            to: scripts.appendingPathComponent("vendor-swiftpm-sources.sh")
        )
        try fileManager.copyItem(
            at: root.appendingPathComponent("scripts/quillui-vendored-source.sh"),
            to: scripts.appendingPathComponent("quillui-vendored-source.sh")
        )
        try write(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "CustomWidgets",
                products: [.library(name: "CustomWidgets", targets: ["CustomWidgets"])],
                targets: [.target(name: "CustomWidgets")]
            )
            """,
            to: checkout.appendingPathComponent("Package.swift")
        )
        try write(
            "public enum CustomWidgets {}\n",
            to: checkoutSources.appendingPathComponent("CustomWidgets.swift")
        )
        try write(
            """
            {
              "pins": [
                {
                  "identity": "custom-widgets",
                  "kind": "remoteSourceControl",
                  "location": "https://example.com/CustomWidgets.git",
                  "state": {
                    "revision": "0123456789abcdef0123456789abcdef01234567",
                    "version": "1.0.0"
                  }
                }
              ],
              "version": 2
            }
            """,
            to: resolved
        )

        let lockfileResult = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                scripts.appendingPathComponent("vendor-swiftpm-sources.sh").path,
                "--package-resolved", resolved.path,
                "--scratch-path", scratch.appendingPathComponent(".build").path,
                "--no-resolve",
            ]
        )
        #expect(lockfileResult.status == 0, Comment(rawValue: lockfileResult.output))
        #expect(fileManager.fileExists(atPath: scratch.appendingPathComponent("third_party/CustomWidgets/Package.swift").path))
        #expect(lockfileResult.output.contains("vendored CustomWidgets -> third_party/CustomWidgets"))

        let explicitUnknownResult = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                scripts.appendingPathComponent("vendor-swiftpm-sources.sh").path,
                "--scratch-path", scratch.appendingPathComponent(".build").path,
                "--no-resolve",
                "DefinitelyNotKnown",
            ]
        )
        #expect(explicitUnknownResult.status == 64, Comment(rawValue: explicitUnknownResult.output))
        #expect(explicitUnknownResult.output.contains("unknown SwiftPM package 'DefinitelyNotKnown'"))
    }

    @Test("Vendored SwiftPM app scan stamps track selected manifest fingerprints")
    func vendoredSwiftPMAppScanStampsTrackSelectedManifestFingerprints() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("QuillUIVendoredStamp-\(UUID().uuidString)")
        let manifest = scratch.appendingPathComponent("third_party/ExampleWidgets/Package.swift")
        let unrelatedManifest = scratch.appendingPathComponent("third_party/UnrelatedWidgets/Package.swift")
        let stamp = scratch.appendingPathComponent(".build/vendor-stamps/example.stamp")
        defer { try? fileManager.removeItem(at: scratch) }

        try fileManager.createDirectory(
            at: manifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: unrelatedManifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try write(
            """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "ExampleWidgets")
            """,
            to: manifest
        )
        try write(
            """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "UnrelatedWidgets")
            """,
            to: unrelatedManifest
        )

        let helper = root.appendingPathComponent("scripts/quillui-vendored-source.sh")
        let writeResult = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-c",
                """
                source "$1"
                quillui_write_vendored_swiftpm_app_stamp "$2" "$3" example abc123 ExampleWidgets
                quillui_vendored_swiftpm_app_stamp_is_valid "$2" "$3"
                """,
                "bash",
                helper.path,
                scratch.path,
                stamp.path
            ]
        )
        #expect(writeResult.status == 0, Comment(rawValue: writeResult.output))
        let stamped = try String(contentsOf: stamp, encoding: .utf8)
        #expect(stamped.contains("app=example"))
        #expect(stamped.contains("key=abc123"))
        #expect(stamped.contains("swiftpmPackage=ExampleWidgets"))
        #expect(stamped.contains("manifestFingerprint="))

        try write(
            """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "UnrelatedWidgets", targets: [.target(name: "UnrelatedWidgets")])
            """,
            to: unrelatedManifest
        )

        let unrelatedResult = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-c",
                """
                source "$1"
                quillui_vendored_swiftpm_app_stamp_is_valid "$2" "$3"
                """,
                "bash",
                helper.path,
                scratch.path,
                stamp.path
            ]
        )
        #expect(unrelatedResult.status == 0, Comment(rawValue: unrelatedResult.output))

        try write(
            """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "ExampleWidgets", targets: [.target(name: "ExampleWidgets")])
            """,
            to: manifest
        )

        let staleResult = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-c",
                """
                source "$1"
                quillui_vendored_swiftpm_app_stamp_is_valid "$2" "$3"
                """,
                "bash",
                helper.path,
                scratch.path,
                stamp.path
            ]
        )
        #expect(staleResult.status != 0, Comment(rawValue: staleResult.output))
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
