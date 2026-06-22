import Foundation
import Testing

@Suite("SwiftPM package layout helper")
struct SwiftPMPackageLayoutTests {

    @Test("Manifest-derived layout preserves reachable targets and external products")
    func manifestDerivedLayoutPreservesReachableTargetsAndExternalProducts() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("QuillUISwiftPMPackageLayoutTests-\(UUID().uuidString)")
        let packageRoot = scratch.appendingPathComponent("SampleDesktop")
        let sources = packageRoot.appendingPathComponent("Sources")
        let output = scratch.appendingPathComponent("Output")
        defer { try? fileManager.removeItem(at: scratch) }

        try fileManager.createDirectory(
            at: sources.appendingPathComponent("SampleCore"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: sources.appendingPathComponent("SampleFeature"),
            withIntermediateDirectories: true
        )
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
                products: [
                    .library(name: "SampleFeature", targets: ["SampleFeature"]),
                    .executable(name: "sample-desktop", targets: ["sample-desktop"])
                ],
                dependencies: [
                    .package(url: "https://example.com/tools.git", exact: "1.2.3")
                ],
                targets: [
                    .target(name: "SampleCore"),
                    .target(
                        name: "SampleFeature",
                        dependencies: [
                            "SampleCore",
                            .product(name: "ExampleTools", package: "tools")
                        ]
                    ),
                    .executableTarget(
                        name: "sample-desktop",
                        dependencies: ["SampleFeature"]
                    )
                ]
            )
            """,
            to: packageRoot.appendingPathComponent("Package.swift")
        )
        try write("public struct SampleCore {}\n", to: sources.appendingPathComponent("SampleCore/Core.swift"))
        try write(
            "import SampleCore\npublic struct SampleFeature {}\n",
            to: sources.appendingPathComponent("SampleFeature/Feature.swift")
        )
        try write(
            """
            import SwiftUI

            @main
            struct SampleDesktopApp: App {
                var body: some Scene {
                    WindowGroup { Text("Hello") }
                }
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

        #expect(result.status == 0)
        #expect(try String(contentsOf: layout, encoding: .utf8) == """
        SampleCore\tSampleCore\t
        SampleFeature\tSampleFeature\tSampleCore,product:ExampleTools:tools
        GeneratedSwiftUILinuxApp\tsample-desktop\tSampleFeature

        """)
        #expect(try String(contentsOf: dependencies, encoding: .utf8) == """
        .package(url: "https://example.com/tools.git", exact: "1.2.3")

        """)
    }

    @Test("Explicit entry target bypasses app type source inference")
    func explicitEntryTargetBypassesAppTypeSourceInference() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("QuillUISwiftPMEntryTargetTests-\(UUID().uuidString)")
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
                targets: [.executableTarget(name: "sample-desktop")]
            )
            """,
            to: packageRoot.appendingPathComponent("Package.swift")
        )
        try write("print(\"no @main app type here\")\n", to: sources.appendingPathComponent("sample-desktop/main.swift"))

        let layout = output.appendingPathComponent("layout.tsv")
        let dependencies = output.appendingPathComponent("dependencies.swift")
        let result = try run(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/swiftpm-package-layout-for-linux.py").path,
                "--package-root", packageRoot.path,
                "--source-dir", sources.path,
                "--app-type", "MissingDesktopApp",
                "--entry-target", "sample-desktop",
                "--generated-target", "GeneratedSwiftUILinuxApp",
                "--layout-out", layout.path,
                "--dependencies-out", dependencies.path
            ]
        )

        #expect(result.status == 0)
        #expect(try String(contentsOf: layout, encoding: .utf8) == """
        GeneratedSwiftUILinuxApp\tsample-desktop\t

        """)
        #expect(try String(contentsOf: dependencies, encoding: .utf8).isEmpty)
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
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
            domain: "SwiftPMPackageLayoutTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
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

        let collector = SwiftPMPackageLayoutOutputCollector()
        let readHandle = pipe.fileHandleForReading
        readHandle.readabilityHandler = { handle in
            collector.append(handle.availableData)
        }

        try process.run()
        process.waitUntilExit()

        readHandle.readabilityHandler = nil
        collector.append(readHandle.readDataToEndOfFile())

        return (process.terminationStatus, collector.string)
    }
}

private final class SwiftPMPackageLayoutOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
}
