import Foundation
import Testing

@Suite("Source hygiene")
struct SourceHygieneTests {
    @Test("Repository does not track local smoke-test artifacts")
    func repositoryDoesNotTrackLocalSmokeTestArtifacts() throws {
        let root = try packageRoot()
        // `-c safe.directory=…`: CI runs tests as a different user than the one
        // that owns the checkout (root-owned container vs the runner user), so a
        // bare `git` aborts with "detected dubious ownership" (exit 128). Scope
        // the exception to this invocation rather than mutating global git config
        // (and without touching linux-ci.yml, whose contents other tests assert on).
        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-c", "safe.directory=*", "-C", root.path, "ls-files"]
        )
        if result.status == 128 && result.output.contains("not a git repository") {
            return
        }
        #expect(result.status == 0, Comment(rawValue: result.output))

        let forbiddenSuffixes = [".bak", ".log", ".orig", ".tmp", "~"]
        let offenders = result.output
            .split(separator: "\n")
            .map(String.init)
            .filter { path in
                let fileName = path.split(separator: "/").last.map(String.init) ?? path
                return fileName == ".DS_Store"
                    || fileName.hasPrefix(".tmp-")
                    || fileName.hasPrefix("tmp-")
                    || forbiddenSuffixes.contains { fileName.hasSuffix($0) }
            }

        #expect(
            offenders.isEmpty,
            Comment(rawValue: "Tracked local artifacts:\n" + offenders.prefix(50).joined(separator: "\n"))
        )
    }

    @Test("Package manifest does not exclude moved QuillAppKit GTK sources")
    func packageManifestDoesNotExcludeMovedQuillAppKitGTKSources() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(!manifest.contains("exclude: [\"QuillAppKit+GTK.swift\"]"))
        #expect(manifest.contains("name: \"QuillAppKitGTK\""))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/QuillAppKitGTK/QuillAppKit+GTK.swift").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/QuillAppKit/QuillAppKit+GTK.swift").path
        ))
    }

    @Test("Package manifest can disable upstream app graphs without disabling vendored packages")
    func packageManifestCanDisableUpstreamAppGraphsWithoutDisablingVendoredPackages() throws {
        let manifest = try packageSource("Package.swift")
        let linuxCI = try packageSource(".github/workflows/linux-ci.yml")

        #expect(manifest.contains("QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS"))
        #expect(manifest.contains("func pathPresent(_ relativePath: String) -> Bool"))
        #expect(manifest.contains("func upstreamPresent(_ relativePath: String) -> Bool"))
        #expect(manifest.contains("guard !quillUIDisableUpstreamAppGraphs else"))
        #expect(manifest.contains("return pathPresent(relativePath)"))
        #expect(manifest.contains("if pathPresent(path)"))
        #expect(!manifest.contains("if upstreamPresent(path)"))
        #expect(manifest.contains("QUILLUI_CODEEDIT_UPSTREAM"))
        #expect(manifest.contains("let codeEditUpstreamEnabled: Bool = codeEditSourceUpstreamPresent"))
        #expect(manifest.contains("if codeEditUpstreamEnabled {"))

        #expect(linuxCI.contains("Swift tests\n        env:\n          QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS: \"1\""))
        #expect(linuxCI.contains("Build QuillUIGtk facade\n        env:\n          QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS: \"1\""))
        #expect(linuxCI.contains("Build QuillUIQt facade\n        env:\n          QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS: \"1\""))
        #expect(linuxCI.contains("GTK offscreen ImageRenderer smoke\n        timeout-minutes: 15\n        env:\n          QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS: \"1\"\n          QUILLUI_LINUX_BACKEND: \"gtk\"\n          TEST_RUN_TIMEOUT: \"180\""))
        #expect(linuxCI.contains("Generic SwiftUI to Qt backend smoke\n        env:\n          QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS: \"1\""))
    }

    @Test("Package manifest uses frontend-compatible default isolation flags")
    func packageManifestUsesFrontendCompatibleDefaultIsolationFlags() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(manifest.contains("#if compiler(>=6.2)"))
        #expect(manifest.contains("let quillMainActorDefaultIsolationSwiftSettings: [SwiftSetting] = ["))
        #expect(manifest.contains(".unsafeFlags([\"-Xfrontend\", \"-default-isolation\", \"-Xfrontend\", \"MainActor\"])"))
        #expect(manifest.contains("#else\nlet quillMainActorDefaultIsolationSwiftSettings: [SwiftSetting] = []\n#endif"))
        #expect(manifest.contains("let quillMinimalConcurrencyMainActorSwiftSettings: [SwiftSetting] = ["))
        #expect(!manifest.contains("\"-default-isolation\", \"MainActor\""))
    }

    @Test("GTK FrameView preserves minimum size for flexible content")
    func gtkFrameViewPreservesMinimumSizeForFlexibleContent() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")

        #expect(renderer.contains("let requestWidth = widthMayGrowWithParent"))
        #expect(renderer.contains("? minWidth.map(gtkPixelSize) ?? -1"))
        #expect(renderer.contains("let requestHeight = heightMayGrowWithParent"))
        #expect(renderer.contains("? minHeight.map(gtkPixelSize) ?? -1"))
    }

    @Test("Vendored LogStream C header is portable for Linux module builds")
    func vendoredLogStreamCHeaderIsPortableForLinuxModuleBuilds() throws {
        let header = try packageSource("third_party/LogStream/Sources/Headers/include/Header.h")

        #expect(header.contains("#include <stdbool.h>"))
        #expect(header.contains("#include <stddef.h>"))
        #expect(header.contains("#include <stdint.h>"))
        #expect(header.contains("#include <limits.h>"))
        #expect(header.contains("#include <sys/types.h>"))
        #expect(header.contains("typedef void *xpc_object_t;"))
        #expect(header.contains("#define __unsafe_unretained"))
        #expect(header.contains("#if defined(__APPLE__) && defined(__OBJC__)"))
    }

    @Test("Image click target helper detects adaptive action pixels")
    func imageClickTargetHelperDetectsAdaptiveActionPixels() throws {
        let root = try packageRoot()
        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/quillui-image-click-target.py").path,
                "--self-test",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
    }

    @Test("Local SwiftPM import discovery emits package and target deps")
    func localSwiftPMImportDiscoveryEmitsPackageAndTargetDeps() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-local-imports-\(UUID().uuidString)")
        let packageDir = sandbox.appendingPathComponent(".upstream/localsymbols")
        let collectionsPackageDir = sandbox.appendingPathComponent("third_party/LocalCollections")
        let grdbPackageDir = sandbox.appendingPathComponent("third_party/GRDB.swift")
        let trustedRouterPackageDir = sandbox.appendingPathComponent("third_party/trusted-router-swift")
        let swiftUIIntrospectPackageDir = sandbox.appendingPathComponent("third_party/SwiftUIIntrospect")
        let sourceDir = sandbox.appendingPathComponent("source")
        let packageDependencies = sandbox.appendingPathComponent("package-dependencies.swift")
        let targetDependencies = sandbox.appendingPathComponent("target-dependencies.txt")

        try fileManager.createDirectory(at: packageDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: collectionsPackageDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: grdbPackageDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trustedRouterPackageDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: swiftUIIntrospectPackageDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "LocalSymbols",
            products: [
                .library(name: "LocalSymbols", targets: ["LocalSymbols"])
            ],
            targets: [
                .target(name: "LocalSymbols")
            ]
        )
        """.write(to: packageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        enum LocalTargetKind { case exported }

        struct LocalTarget {
            let kind: LocalTargetKind
            let name: String

            static func target(kind: LocalTargetKind, name: String) -> LocalTarget {
                LocalTarget(kind: kind, name: name)
            }
        }

        let targets: [LocalTarget] = [
            .target(kind: .exported, name: "OrderedCollections")
        ]

        let package = Package(
            name: "LocalCollections",
            products: targets.map { .library(name: $0.name, targets: [$0.name]) },
            targets: [.target(name: "OrderedCollections")]
        )
        """.write(to: collectionsPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "GRDB",
            products: [.library(name: "GRDB", targets: ["GRDB"])],
            targets: [.target(name: "GRDB")]
        )
        """.write(to: grdbPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "TrustedRouter",
            products: [.library(name: "TrustedRouter", targets: ["TrustedRouter"])],
            targets: [.target(name: "TrustedRouter")]
        )
        """.write(to: trustedRouterPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "swiftui-introspect",
            products: [.library(name: "SwiftUIIntrospect", targets: ["SwiftUIIntrospect"])],
            targets: [.target(name: "SwiftUIIntrospect")]
        )
        """.write(to: swiftUIIntrospectPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import Foundation
        import GRDB
        import ExtensionFoundation
        import ExtensionKit
        import LocalSymbols
        import OrderedCollections
        import PDFKit.PDFView
        import QuickLookUI
        import SwiftUIIntrospect
        import TrustedRouter

        struct UsesLocalSymbols {}
        """.write(to: sourceDir.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/discover-local-swiftpm-import-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--source-dir", sourceDir.path,
                "--package-dependencies-out", packageDependencies.path,
                "--target-dependencies-out", targetDependencies.path,
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let packageOutput = try String(contentsOf: packageDependencies, encoding: .utf8)
        let targetOutput = try String(contentsOf: targetDependencies, encoding: .utf8)

        #expect(packageOutput.contains(".package(name: \"LocalSymbols\", path:"))
        #expect(packageOutput.contains(packageDir.path))
        #expect(packageOutput.contains(".package(name: \"LocalCollections\", path:"))
        #expect(packageOutput.contains(collectionsPackageDir.path))
        #expect(packageOutput.contains(".package(name: \"GRDB.swift\", path:"))
        #expect(packageOutput.contains(grdbPackageDir.path))
        #expect(packageOutput.contains(".package(name: \"trusted-router-swift\", path:"))
        #expect(packageOutput.contains(trustedRouterPackageDir.path))
        #expect(!packageOutput.contains("SwiftUIIntrospect"))
        #expect(targetOutput.contains("product:LocalSymbols:LocalSymbols"))
        #expect(targetOutput.contains("product:OrderedCollections:LocalCollections"))
        #expect(targetOutput.contains("product:GRDB:GRDB.swift"))
        #expect(targetOutput.contains("product:TrustedRouter:trusted-router-swift"))
        #expect(!targetOutput.contains("ExtensionFoundation"))
        #expect(!targetOutput.contains("ExtensionKit"))
        #expect(!targetOutput.contains("PDFKit"))
        #expect(!targetOutput.contains("QuickLookUI"))
        #expect(!targetOutput.contains("SwiftUIIntrospect"))
        #expect(!targetOutput.contains("Foundation"))
    }

    @Test("Local SwiftPM import discovery excludes copied app package root")
    func localSwiftPMImportDiscoveryExcludesCopiedAppPackageRoot() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-local-imports-exclude-app-\(UUID().uuidString)")
        let appPackageDir = sandbox.appendingPathComponent("vendor/apps/demo")
        let helperPackageDir = sandbox.appendingPathComponent("third_party/HelperPackage")
        let sourceDir = sandbox.appendingPathComponent("source")
        let packageDependencies = sandbox.appendingPathComponent("package-dependencies.swift")
        let targetDependencies = sandbox.appendingPathComponent("target-dependencies.txt")

        try fileManager.createDirectory(at: appPackageDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: helperPackageDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "DemoApp",
            products: [.library(name: "DemoCore", targets: ["DemoCore"])],
            targets: [.target(name: "DemoCore")]
        )
        """.write(to: appPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "HelperPackage",
            products: [.library(name: "HelperKit", targets: ["HelperKit"])],
            targets: [.target(name: "HelperKit")]
        )
        """.write(to: helperPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import DemoCore
        import HelperKit

        struct UsesGeneratedTargets {}
        """.write(to: sourceDir.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/discover-local-swiftpm-import-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--source-dir", sourceDir.path,
                "--exclude-package-root", appPackageDir.path,
                "--package-dependencies-out", packageDependencies.path,
                "--target-dependencies-out", targetDependencies.path,
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let packageOutput = try String(contentsOf: packageDependencies, encoding: .utf8)
        let targetOutput = try String(contentsOf: targetDependencies, encoding: .utf8)

        #expect(!packageOutput.contains("DemoApp"), Comment(rawValue: packageOutput))
        #expect(!targetOutput.contains("DemoCore"), Comment(rawValue: targetOutput))
        #expect(packageOutput.contains(".package(name: \"HelperPackage\", path:"))
        #expect(targetOutput.contains("product:HelperKit:HelperPackage"))
    }

    @Test("Generated app builder prepares SwiftUI-importing local package dependencies")
    func generatedAppBuilderPreparesSwiftUIImportingLocalPackageDependencies() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-local-package-prep-\(UUID().uuidString)")
        let packageDir = sandbox.appendingPathComponent(".upstream/localsymbols")
        let packageSources = packageDir.appendingPathComponent("Sources/LocalSymbols")
        let pureDependencyDir = sandbox.appendingPathComponent("third_party/PureDependency")
        let pureDependencySources = pureDependencyDir.appendingPathComponent("Sources/PureDependency")
        let logOnlyPackageDir = sandbox.appendingPathComponent("third_party/LogOnly")
        let logOnlyPackageSources = logOnlyPackageDir.appendingPathComponent("Sources/LogOnly")
        let inactiveImportPackageDir = sandbox.appendingPathComponent("third_party/InactiveImport")
        let inactiveImportPackageSources = inactiveImportPackageDir.appendingPathComponent("Sources/InactiveImport")
        let conditionalAppKitPackageDir = sandbox.appendingPathComponent("third_party/ConditionalAppKit")
        let conditionalAppKitPackageSources = conditionalAppKitPackageDir.appendingPathComponent("Sources/ConditionalAppKit")
        let conditionalAppKitHelperSources = conditionalAppKitPackageDir.appendingPathComponent("Sources/ConditionalAppKitHelper")
        let conditionalExcludedSources = conditionalAppKitPackageDir.appendingPathComponent("Sources/ConditionalExcluded")
        let workRoot = sandbox.appendingPathComponent("work")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: packageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pureDependencySources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logOnlyPackageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: inactiveImportPackageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: conditionalAppKitPackageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: conditionalAppKitHelperSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: conditionalExcludedSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "LocalSymbols",
            products: [
                .library(name: "LocalSymbols", targets: ["LocalSymbols"])
            ],
            dependencies: [
                .package(path: "\(pureDependencyDir.path)")
            ],
            targets: [
                .target(
                    name: "LocalSymbols",
                    dependencies: ["PureDependency"]
                )
            ]
        )
        """.write(to: packageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI
        import PureDependency

        public extension Image {
            static let localSymbol = Image(systemName: "star")
        }
        """.write(to: packageSources.appendingPathComponent("Symbols.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "PureDependency",
            products: [
                .library(name: "PureDependency", targets: ["PureDependency"])
            ],
            targets: [
                .target(name: "PureDependency")
            ]
        )
        """.write(to: pureDependencyDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public struct PureDependency {}
        """.write(to: pureDependencySources.appendingPathComponent("PureDependency.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "LogOnly",
            products: [
                .library(name: "LogOnly", targets: ["LogOnly"])
            ],
            targets: [
                .target(name: "LogOnly")
            ]
        )
        """.write(to: logOnlyPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        #if canImport(os)
        import os
        #endif

        public struct LogOnly {}
        """.write(to: logOnlyPackageSources.appendingPathComponent("LogOnly.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "InactiveImport",
            products: [
                .library(name: "InactiveImport", targets: ["InactiveImport"])
            ],
            targets: [
                .target(name: "InactiveImport")
            ]
        )
        """.write(to: inactiveImportPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        #if false
        import Combine
        #endif

        #if os(iOS)
        import UIKit
        #endif

        public struct InactiveImport {}
        """.write(to: inactiveImportPackageSources.appendingPathComponent("InactiveImport.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        var dependencies: [PackageDescription.Package.Dependency] = []

        let package = Package(
            name: "ConditionalAppKit",
            products: [
                .library(name: "ConditionalAppKit", targets: ["ConditionalAppKit", "ConditionalExcluded"])
            ],
            dependencies: dependencies,
            targets: [
                .target(name: "ConditionalAppKitHelper"),
                .target(name: "ConditionalExcluded", exclude: ["Ignored.swift"]),
                .target(
                    name: "ConditionalAppKit",
                    dependencies: [
                        "ConditionalAppKitHelper",
                        //.target(name: "CommentedDependency"),
                    ]
                )
            ]
        )
        """.write(to: conditionalAppKitPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public struct ConditionalAppKitHelper {}
        """.write(to: conditionalAppKitHelperSources.appendingPathComponent("ConditionalAppKitHelper.swift"), atomically: true, encoding: .utf8)
        try """
        #if os(macOS)
        import AppKit
        #endif

        public struct ConditionalExcluded {}
        """.write(to: conditionalExcludedSources.appendingPathComponent("ConditionalExcluded.swift"), atomically: true, encoding: .utf8)
        try """
        #if os(macOS)
        import AppKit
        #endif

        public struct ConditionalAppKit {}
        """.write(to: conditionalAppKitPackageSources.appendingPathComponent("ConditionalAppKit.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "LocalSymbols", path: "\(packageDir.path)")
        .package(name: "LogOnly", path: "\(logOnlyPackageDir.path)")
        .package(name: "InactiveImport", path: "\(inactiveImportPackageDir.path)")
        .package(name: "ConditionalAppKit", path: "\(conditionalAppKitPackageDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", root.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        let resolvedWorkRoot = workRoot.resolvingSymlinksInPath()
        let preparedManifest = try String(
            contentsOf: workRoot
                .appendingPathComponent("prepared-packages/LocalSymbols/Package.swift"),
            encoding: .utf8
        )
        let conditionalAppKitPreparedManifest = try String(
            contentsOf: workRoot
                .appendingPathComponent("prepared-packages/ConditionalAppKit/Package.swift"),
            encoding: .utf8
        )
        let originalManifest = try String(contentsOf: packageDir.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(rewrittenDependencies.contains(".package(name: \"LocalSymbols\", path:"))
        #expect(rewrittenDependencies.contains("prepared-packages/LocalSymbols"))
        #expect(rewrittenDependencies.contains(".package(name: \"LogOnly\", path: \"\(logOnlyPackageDir.path)\""))
        #expect(rewrittenDependencies.contains(".package(name: \"InactiveImport\", path: \"\(inactiveImportPackageDir.path)\""))
        #expect(rewrittenDependencies.contains("prepared-packages/ConditionalAppKit"))
        #expect(!rewrittenDependencies.contains("prepared-packages/LogOnly"))
        #expect(!rewrittenDependencies.contains("prepared-packages/InactiveImport"))
        #expect(preparedManifest.contains(".package(name: \"QuillUI\", path: \"\(root.path)\""))
        #expect(conditionalAppKitPreparedManifest.contains("dependencies.append(.package(name: \"QuillUI\", path: \"\(root.path)\""))
        #expect(conditionalAppKitPreparedManifest.contains(".product(name: \"AppKit\", package: \"QuillUI\")"))
        #expect(!conditionalAppKitPreparedManifest.contains("CommentedDependency\"),\n            ,"))
        #expect(!conditionalAppKitPreparedManifest.contains("],, exclude"))
        let pureDependencyPreparedPath = resolvedWorkRoot
            .appendingPathComponent("prepared-packages/PureDependency")
            .path
        #expect(
            preparedManifest.contains(".package(name: \"PureDependency\", path: \"\(pureDependencyPreparedPath)\"")
                || preparedManifest.contains(".package(name: \"PureDependency\", path: \"/private\(pureDependencyPreparedPath)\"")
        )
        #expect(preparedManifest.contains(".product(name: \"SwiftUI\", package: \"QuillUI\")"))
        #expect(preparedManifest.contains(".product(name: \"QuillShims\", package: \"QuillUI\")"))
        #expect(preparedManifest.contains(".swiftLanguageMode(.v5)"))
        #expect(!preparedManifest.contains(#".unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])"#))
        #expect(conditionalAppKitPreparedManifest.contains(".swiftLanguageMode(.v5)"))
        #expect(!conditionalAppKitPreparedManifest.contains(#".unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])"#))
        #expect(fileManager.fileExists(atPath: workRoot.appendingPathComponent("prepared-packages/PureDependency/Package.swift").path))
        #expect(fileManager.fileExists(atPath: workRoot.appendingPathComponent("prepared-packages/ConditionalAppKit/Package.swift").path))
        #expect(!fileManager.fileExists(atPath: workRoot.appendingPathComponent("prepared-packages/LogOnly").path))
        #expect(!fileManager.fileExists(atPath: workRoot.appendingPathComponent("prepared-packages/InactiveImport").path))
        #expect(!originalManifest.contains("QuillUI"))
    }

    @Test("Generated app builder prepares root-declared packages that import SwiftUI")
    func generatedAppBuilderPreparesRootDeclaredPackagesThatImportSwiftUI() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-root-declared-package-prep-\(UUID().uuidString)")
        let packageDir = sandbox.appendingPathComponent("third_party/RootDeclaredSwiftUI")
        let packageSources = packageDir.appendingPathComponent("Sources/RootDeclaredSwiftUI")
        let workRoot = sandbox.appendingPathComponent("work")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: packageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FakeRoot",
            dependencies: [
                .package(name: "RootDeclaredSwiftUI", path: "\(packageDir.path)")
            ],
            targets: []
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "RootDeclaredSwiftUI",
            products: [
                .library(name: "RootDeclaredSwiftUI", targets: ["RootDeclaredSwiftUI"])
            ],
            targets: [
                .target(name: "RootDeclaredSwiftUI")
            ]
        )
        """.write(to: packageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI

        public struct RootDeclaredLabel: View {
            public var body: some View {
                Text("Root declared")
            }
        }
        """.write(to: packageSources.appendingPathComponent("RootDeclaredLabel.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "RootDeclaredSwiftUI", path: "\(packageDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        let preparedManifest = try String(
            contentsOf: workRoot
                .appendingPathComponent("prepared-packages/RootDeclaredSwiftUI/Package.swift"),
            encoding: .utf8
        )

        #expect(rewrittenDependencies.contains("prepared-packages/RootDeclaredSwiftUI"))
        #expect(
            preparedManifest.contains(".package(name: \"QuillUI\", path: \"\(sandbox.path)\"")
                || preparedManifest.contains(".package(name: \"QuillUI\", path: \"/private\(sandbox.path)\"")
        )
        #expect(preparedManifest.contains(".product(name: \"SwiftUI\", package: \"QuillUI\")"))
        #expect(preparedManifest.contains(".product(name: \"QuillShims\", package: \"QuillUI\")"))
        #expect(preparedManifest.contains(".swiftLanguageMode(.v5)"))
        #expect(!preparedManifest.contains(#".unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])"#))
    }

    @Test("Generated app builder reuses Linux-ready vendored package dependencies")
    func generatedAppBuilderReusesLinuxReadyVendoredPackageDependencies() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-linux-ready-vendor-\(UUID().uuidString)")
        let packageDir = sandbox.appendingPathComponent("third_party/LinuxReadySDK")
        let packageSources = packageDir.appendingPathComponent("Sources/LinuxReadySDK")
        let workRoot = sandbox.appendingPathComponent("work")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: packageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "QuillUI",
            targets: [.target(name: "QuillUI")]
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try fileManager.createDirectory(
            at: sandbox.appendingPathComponent("Sources/QuillUI"),
            withIntermediateDirectories: true
        )
        try "public enum QuillUIRoot {}\n".write(
            to: sandbox.appendingPathComponent("Sources/QuillUI/QuillUIRoot.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "LinuxReadySDK",
            products: [.library(name: "LinuxReadySDK", targets: ["LinuxReadySDK"])],
            dependencies: [
                .package(name: "QuillUI", path: "\(sandbox.path)")
            ],
            targets: [
                .target(
                    name: "LinuxReadySDK",
                    dependencies: [
                        .product(name: "AuthenticationServices", package: "QuillUI"),
                        .product(name: "CryptoKit", package: "QuillUI"),
                        .product(name: "QuillShims", package: "QuillUI"),
                        .product(name: "Security", package: "QuillUI"),
                    ]
                )
            ]
        )
        """.write(to: packageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        #if canImport(AuthenticationServices)
        import AuthenticationServices
        #endif
        #if canImport(CryptoKit)
        import CryptoKit
        #endif
        #if canImport(Security)
        import Security
        #endif

        public struct LinuxReadySDKClient {}
        """.write(to: packageSources.appendingPathComponent("LinuxReadySDKClient.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "LinuxReadySDK", url: "https://example.com/LinuxReadySDK.git", from: "1.0.0")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--skip-source-lowering",
                "--require-vendored-sources",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        let resolvedPackagePath = packageDir.resolvingSymlinksInPath().path

        #expect(rewrittenDependencies.contains(".package(name: \"LinuxReadySDK\", path:"))
        #expect(
            rewrittenDependencies.contains(resolvedPackagePath)
                || rewrittenDependencies.contains("/private\(resolvedPackagePath)")
        )
        #expect(!rewrittenDependencies.contains("https://example.com/LinuxReadySDK.git"))
        #expect(!rewrittenDependencies.contains("prepared-packages/LinuxReadySDK"))
        #expect(!fileManager.fileExists(atPath: workRoot.appendingPathComponent("prepared-packages/LinuxReadySDK").path))
    }

    @Test("Generated app builder does not prepare the QuillUI root dependency")
    func generatedAppBuilderDoesNotPrepareTheQuillUIRootDependency() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-root-dependency-prep-\(UUID().uuidString)")
        let rendererDir = sandbox.appendingPathComponent("third_party/Renderer")
        let rendererSources = rendererDir.appendingPathComponent("Sources/Renderer")
        let workRoot = sandbox.appendingPathComponent("work")
        let cacheRoot = sandbox.appendingPathComponent("prepared-cache")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: rendererSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "QuillUI",
            targets: [.target(name: "QuillUI")]
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try fileManager.createDirectory(
            at: sandbox.appendingPathComponent("Sources/QuillUI"),
            withIntermediateDirectories: true
        )
        try "public enum QuillUIRoot {}\n".write(
            to: sandbox.appendingPathComponent("Sources/QuillUI/QuillUIRoot.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Renderer",
            products: [.library(name: "Renderer", targets: ["Renderer"])],
            dependencies: [
                .package(name: "QuillUI", path: "../..")
            ],
            targets: [
                .target(name: "Renderer")
            ]
        )
        """.write(to: rendererDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI

        public struct RendererView: View {
            public var body: some View { Text("renderer") }
        }
        """.write(to: rendererSources.appendingPathComponent("RendererView.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "Renderer", path: "\(rendererDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--prepared-cache-dir", cacheRoot.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let cacheEntries = try fileManager.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: nil
        )
        let preparedRenderer = try #require(cacheEntries.first { $0.lastPathComponent.hasPrefix("Renderer-") })
        let preparedManifest = try String(
            contentsOf: preparedRenderer.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let resolvedRoot = sandbox.resolvingSymlinksInPath().path

        #expect(preparedManifest.contains(".package(name: \"QuillUI\", path:"))
        #expect(preparedManifest.contains(resolvedRoot) || preparedManifest.contains("/private\(resolvedRoot)"))
        #expect(!preparedManifest.contains("prepared-cache/QuillUI-"))
        #expect(cacheEntries.allSatisfy { !$0.lastPathComponent.hasPrefix("QuillUI-") })
    }

    @Test("Generated app builder keeps prepared local dependency graphs internally consistent")
    func generatedAppBuilderKeepsPreparedLocalDependencyGraphsInternallyConsistent() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-prepared-graph-package-prep-\(UUID().uuidString)")
        let rendererDir = sandbox.appendingPathComponent("third_party/Renderer")
        let rendererSources = rendererDir.appendingPathComponent("Sources/Renderer")
        let modelDir = sandbox.appendingPathComponent("third_party/Model")
        let modelSources = modelDir.appendingPathComponent("Sources/Model")
        let utilityDir = sandbox.appendingPathComponent("third_party/Utility")
        let utilitySources = utilityDir.appendingPathComponent("Sources/Utility")
        let workRoot = sandbox.appendingPathComponent("work")
        let cacheRoot = sandbox.appendingPathComponent("prepared-cache")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: rendererSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: modelSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: utilitySources, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FixtureRoot",
            dependencies: [
                .package(path: "third_party/Renderer"),
                .package(path: "third_party/Model"),
                .package(path: "third_party/Utility"),
            ],
            targets: [.target(name: "FixtureRoot")]
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Renderer",
            products: [.library(name: "Renderer", targets: ["Renderer"])],
            dependencies: [
                .package(path: "../Model"),
                .package(path: "../Utility"),
            ],
            targets: [
                .target(name: "Renderer", dependencies: ["Model", "Utility"])
            ]
        )
        """.write(to: rendererDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI

        public struct RendererView: View {
            public var body: some View { Text("Renderer") }
        }
        """.write(to: rendererSources.appendingPathComponent("Renderer.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Model",
            products: [.library(name: "Model", targets: ["Model"])],
            dependencies: [
                .package(path: "../Utility"),
            ],
            targets: [
                .target(name: "Model", dependencies: ["Utility"])
            ]
        )
        """.write(to: modelDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public struct ModelValue {}
        """.write(to: modelSources.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Utility",
            products: [.library(name: "Utility", targets: ["Utility"])],
            targets: [.target(name: "Utility")]
        )
        """.write(to: utilityDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import Combine

        public final class UtilityObject: ObservableObject {}
        """.write(to: utilitySources.appendingPathComponent("Utility.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "Renderer", path: "\(rendererDir.path)")
        .package(name: "Model", path: "\(modelDir.path)")
        .package(name: "Utility", path: "\(utilityDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--prepared-cache-dir", cacheRoot.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        let cacheEntries = try fileManager.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: nil
        )
        func preparedCacheEntry(named name: String) throws -> URL {
            try #require(cacheEntries.first { $0.lastPathComponent.hasPrefix("\(name)-") })
        }
        let preparedRendererManifest = try String(
            contentsOf: try preparedCacheEntry(named: "Renderer").appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let preparedModelManifest = try String(
            contentsOf: try preparedCacheEntry(named: "Model").appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(rewrittenDependencies.contains("prepared-cache/Renderer-"))
        #expect(rewrittenDependencies.contains("prepared-cache/Model-"))
        #expect(rewrittenDependencies.contains("prepared-cache/Utility-"))
        #expect(preparedRendererManifest.contains(".package(name: \"Model\", path:"))
        #expect(preparedRendererManifest.contains(".package(name: \"Utility\", path:"))
        #expect(preparedRendererManifest.contains("prepared-cache/Model-"))
        #expect(preparedRendererManifest.contains("prepared-cache/Utility-"))
        #expect(preparedModelManifest.contains(".package(name: \"Utility\", path:"))
        #expect(preparedModelManifest.contains("prepared-cache/Utility-"))
        #expect(!preparedModelManifest.contains("../Utility"))
    }

    @Test("Generated app builder keeps root-declared pure vendored dependencies canonical")
    func generatedAppBuilderKeepsRootDeclaredPureVendoredDependenciesCanonical() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-prepared-root-pure-dep-\(UUID().uuidString)")
        let rendererDir = sandbox.appendingPathComponent("third_party/Renderer")
        let rendererSources = rendererDir.appendingPathComponent("Sources/Renderer")
        let rootPureDir = sandbox.appendingPathComponent("third_party/RootPure")
        let rootPureSources = rootPureDir.appendingPathComponent("Sources/RootPure")
        let workRoot = sandbox.appendingPathComponent("work")
        let cacheRoot = sandbox.appendingPathComponent("prepared-cache")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: rendererSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rootPureSources, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FixtureRoot",
            dependencies: [
                .package(path: "third_party/RootPure"),
            ],
            targets: [.target(name: "FixtureRoot")]
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Renderer",
            products: [.library(name: "Renderer", targets: ["Renderer"])],
            dependencies: [
                .package(path: "../RootPure"),
            ],
            targets: [
                .target(name: "Renderer", dependencies: ["RootPure"])
            ]
        )
        """.write(to: rendererDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI

        public struct RendererView: View {
            public var body: some View { Text(RootPureValue.text) }
        }
        """.write(to: rendererSources.appendingPathComponent("Renderer.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "RootPure",
            products: [.library(name: "RootPure", targets: ["RootPure"])],
            targets: [.target(name: "RootPure")]
        )
        """.write(to: rootPureDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public enum RootPureValue {
            public static let text = "root"
        }
        """.write(to: rootPureSources.appendingPathComponent("RootPure.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "Renderer", path: "\(rendererDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--prepared-cache-dir", cacheRoot.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let cacheEntries = try fileManager.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: nil
        )
        let preparedRenderer = try #require(cacheEntries.first { $0.lastPathComponent.hasPrefix("Renderer-") })
        let preparedManifest = try String(
            contentsOf: preparedRenderer.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(preparedManifest.contains(".package(name: \"RootPure\", path:"))
        #expect(
            preparedManifest.contains(rootPureDir.path)
                || preparedManifest.contains("/private\(rootPureDir.path)")
        )
        #expect(!preparedManifest.contains("prepared-cache/RootPure-"))
        #expect(cacheEntries.allSatisfy { !$0.lastPathComponent.hasPrefix("RootPure-") })
    }

    @Test("Generated app builder revisits earlier pure dependencies after later preparation")
    func generatedAppBuilderRevisitsEarlierPureDependenciesAfterLaterPreparation() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-prepared-fixed-point-\(UUID().uuidString)")
        let featureADir = sandbox.appendingPathComponent("third_party/FeatureA")
        let featureASources = featureADir.appendingPathComponent("Sources/FeatureA")
        let featureCDir = sandbox.appendingPathComponent("third_party/FeatureC")
        let featureCSources = featureCDir.appendingPathComponent("Sources/FeatureC")
        let sharedDir = sandbox.appendingPathComponent("third_party/SharedPure")
        let sharedSources = sharedDir.appendingPathComponent("Sources/SharedPure")
        let workRoot = sandbox.appendingPathComponent("work")
        let cacheRoot = sandbox.appendingPathComponent("prepared-cache")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: featureASources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: featureCSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sharedSources, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FixtureRoot",
            targets: [.target(name: "FixtureRoot")]
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        for (dir, name, importsSwiftUI) in [
            (featureADir, "FeatureA", false),
            (featureCDir, "FeatureC", true),
        ] {
            try """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(name)",
                products: [.library(name: "\(name)", targets: ["\(name)"])],
                dependencies: [
                    .package(path: "../SharedPure"),
                ],
                targets: [
                    .target(name: "\(name)", dependencies: ["SharedPure"])
                ]
            )
            """.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            let sourceDir = importsSwiftUI ? featureCSources : featureASources
            try """
            \(importsSwiftUI ? "import SwiftUI" : "import Foundation")

            public struct \(name)Value {
                public static let text = SharedPureValue.text
            }
            """.write(to: sourceDir.appendingPathComponent("\(name).swift"), atomically: true, encoding: .utf8)
        }
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "SharedPure",
            products: [.library(name: "SharedPure", targets: ["SharedPure"])],
            targets: [.target(name: "SharedPure")]
        )
        """.write(to: sharedDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public enum SharedPureValue {
            public static let text = "shared"
        }
        """.write(to: sharedSources.appendingPathComponent("SharedPure.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "FeatureA", path: "\(featureADir.path)")
        .package(name: "FeatureC", path: "\(featureCDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--prepared-cache-dir", cacheRoot.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        let cacheEntries = try fileManager.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: nil
        )
        let preparedFeatureA = try #require(cacheEntries.first { $0.lastPathComponent.hasPrefix("FeatureA-") })
        let preparedFeatureAManifest = try String(
            contentsOf: preparedFeatureA.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(rewrittenDependencies.contains("prepared-cache/FeatureA-"))
        #expect(rewrittenDependencies.contains("prepared-cache/FeatureC-"))
        #expect(preparedFeatureAManifest.contains("prepared-cache/SharedPure-"))
        #expect(!preparedFeatureAManifest.contains("../SharedPure"))
    }

    @Test("Generated app builder recovers prepared transitive dependencies from cache reuse")
    func generatedAppBuilderRecoversPreparedTransitiveDependenciesFromCacheReuse() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-prepared-cache-reuse-\(UUID().uuidString)")
        let featureADir = sandbox.appendingPathComponent("third_party/FeatureA")
        let featureASources = featureADir.appendingPathComponent("Sources/FeatureA")
        let featureCDir = sandbox.appendingPathComponent("third_party/FeatureC")
        let featureCSources = featureCDir.appendingPathComponent("Sources/FeatureC")
        let workRoot = sandbox.appendingPathComponent("work")
        let cacheRoot = sandbox.appendingPathComponent("prepared-cache")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: featureASources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: featureCSources, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FixtureRoot",
            targets: [.target(name: "FixtureRoot")]
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FeatureA",
            products: [.library(name: "FeatureA", targets: ["FeatureA"])],
            targets: [.target(name: "FeatureA")]
        )
        """.write(to: featureADir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import Foundation

        public enum FeatureAValue {
            public static let text = "a"
        }
        """.write(to: featureASources.appendingPathComponent("FeatureA.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FeatureC",
            products: [.library(name: "FeatureC", targets: ["FeatureC"])],
            dependencies: [
                .package(path: "../FeatureA"),
            ],
            targets: [
                .target(name: "FeatureC", dependencies: ["FeatureA"])
            ]
        )
        """.write(to: featureCDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI
        import FeatureA

        public struct FeatureCView: View {
            public var body: some View { Text(FeatureAValue.text) }
        }
        """.write(to: featureCSources.appendingPathComponent("FeatureC.swift"), atomically: true, encoding: .utf8)

        try """
        .package(name: "FeatureC", path: "\(featureCDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)
        var result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--prepared-cache-dir", cacheRoot.path,
                "--skip-source-lowering",
            ]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))

        try """
        .package(name: "FeatureA", path: "\(featureADir.path)")
        .package(name: "FeatureC", path: "\(featureCDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)
        result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--prepared-cache-dir", cacheRoot.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        #expect(rewrittenDependencies.contains("prepared-cache/FeatureA-"))
        #expect(rewrittenDependencies.contains("prepared-cache/FeatureC-"))
        #expect(!rewrittenDependencies.contains("path: \"\(featureADir.path)\""))
    }

    @Test("Generated app builder rewrites vendored transitive URL package dependencies")
    func generatedAppBuilderRewritesVendoredTransitiveURLPackageDependencies() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-transitive-url-package-prep-\(UUID().uuidString)")
        let packageDir = sandbox.appendingPathComponent("third_party/RootPackage")
        let packageSources = packageDir.appendingPathComponent("Sources/RootPackage")
        let supportPackageDir = sandbox.appendingPathComponent("third_party/remote-support-swift")
        let supportSources = supportPackageDir.appendingPathComponent("Sources/RemoteSupport")
        let workRoot = sandbox.appendingPathComponent("work")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: packageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: supportSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FakeRoot",
            targets: []
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "RootPackage",
            products: [
                .library(name: "RootPackage", targets: ["RootPackage"])
            ],
            dependencies: [
                .package(url: "https://github.com/example/remote-support-swift.git", from: "1.0.0")
            ],
            targets: [
                .target(
                    name: "RootPackage",
                    dependencies: [
                        .product(name: "RemoteSupport", package: "remote-support-swift")
                    ]
                )
            ]
        )
        """.write(to: packageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import RemoteSupport
        import SwiftUI

        public struct RootPackageLabel: View {
            public var body: some View {
                Text(RemoteSupport.value)
            }
        }
        """.write(to: packageSources.appendingPathComponent("RootPackageLabel.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "RemoteSupport",
            products: [
                .library(name: "RemoteSupport", targets: ["RemoteSupport"])
            ],
            targets: [
                .target(name: "RemoteSupport")
            ]
        )
        """.write(to: supportPackageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public enum RemoteSupport {
            public static let value = "vendored"
        }
        """.write(to: supportSources.appendingPathComponent("RemoteSupport.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "RootPackage", path: "\(packageDir.path)")
        .package(url: "https://github.com/example/remote-support-swift.git", from: "1.0.0")
        .package(name: "remote-support-swift", path: "\(supportPackageDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        let preparedManifest = try String(
            contentsOf: workRoot
                .appendingPathComponent("prepared-packages/RootPackage/Package.swift"),
            encoding: .utf8
        )
        let supportPreparedManifest = try String(
            contentsOf: workRoot
                .appendingPathComponent("prepared-packages/remote-support-swift/Package.swift"),
            encoding: .utf8
        )

        #expect(rewrittenDependencies.contains("prepared-packages/RootPackage"))
        #expect(preparedManifest.contains(".package(name: \"remote-support-swift\", path:"))
        #expect(preparedManifest.contains("prepared-packages/remote-support-swift"))
        #expect(!preparedManifest.contains("https://github.com/example/remote-support-swift.git"))
        #expect(preparedManifest.contains(#".product(name: "RemoteSupport", package: "remote-support-swift")"#))
        let remoteSupportDependencyLines = rewrittenDependencies
            .split(separator: "\n")
            .filter { $0.contains(#".package(name: "remote-support-swift", path:"#) }
        #expect(remoteSupportDependencyLines.count == 1, Comment(rawValue: rewrittenDependencies))
        #expect(preparedManifest.contains(".product(name: \"SwiftUI\", package: \"QuillUI\")"))
        #expect(preparedManifest.contains("// swift-tools-version: 6.0"))
        #expect(preparedManifest.contains(".swiftLanguageMode(.v5)"))
        #expect(!preparedManifest.contains(#".unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])"#))
        #expect(fileManager.fileExists(atPath: workRoot.appendingPathComponent("prepared-packages/remote-support-swift").path))
        #expect(!supportPreparedManifest.contains("QuillUI"))
    }

    @Test("Generated app builder resolves vendored URL aliases case-insensitively")
    func generatedAppBuilderResolvesVendoredURLAliasesCaseInsensitively() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-url-alias-package-prep-\(UUID().uuidString)")
        let packageDir = sandbox.appendingPathComponent("third_party/RootAliasPackage")
        let packageSources = packageDir.appendingPathComponent("Sources/RootAliasPackage")
        let asyncAlgorithmsDir = sandbox.appendingPathComponent("third_party/AsyncAlgorithms")
        let asyncAlgorithmsSources = asyncAlgorithmsDir.appendingPathComponent("Sources/AsyncAlgorithms")
        let workRoot = sandbox.appendingPathComponent("work")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: packageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: asyncAlgorithmsSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FakeRoot",
            targets: []
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "RootAliasPackage",
            products: [
                .library(name: "RootAliasPackage", targets: ["RootAliasPackage"])
            ],
            dependencies: [
                .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0")
            ],
            targets: [
                .target(
                    name: "RootAliasPackage",
                    dependencies: [
                        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
                    ]
                )
            ]
        )
        """.write(to: packageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI
        import AsyncAlgorithms

        public struct RootAliasLabel: View {
            public var body: some View {
                Text("vendored alias")
            }
        }
        """.write(to: packageSources.appendingPathComponent("RootAliasLabel.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "swift-async-algorithms",
            products: [
                .library(name: "AsyncAlgorithms", targets: ["AsyncAlgorithms"])
            ],
            targets: [
                .target(name: "AsyncAlgorithms")
            ]
        )
        """.write(to: asyncAlgorithmsDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public enum AsyncAlgorithmsShim {
            public static let value = "vendored"
        }
        """.write(to: asyncAlgorithmsSources.appendingPathComponent("AsyncAlgorithms.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "RootAliasPackage", path: "\(packageDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--skip-source-lowering",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let preparedManifest = try String(
            contentsOf: workRoot
                .appendingPathComponent("prepared-packages/RootAliasPackage/Package.swift"),
            encoding: .utf8
        )

        #expect(preparedManifest.contains(".package(name: \"swift-async-algorithms\", path:"))
        #expect(preparedManifest.contains("prepared-packages/swift-async-algorithms"))
        #expect(!preparedManifest.contains("https://github.com/apple/swift-async-algorithms.git"))
        #expect(fileManager.fileExists(
            atPath: workRoot.appendingPathComponent("prepared-packages/swift-async-algorithms/Package.swift").path
        ))
    }

    @Test("Generated app builder resolves vendored URLs from package manifest names")
    func generatedAppBuilderResolvesVendoredURLsFromPackageManifestNames() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-manifest-name-vendor-\(UUID().uuidString)")
        let packageDir = sandbox.appendingPathComponent("third_party/RenamedCheckout")
        let packageSources = packageDir.appendingPathComponent("Sources/RemoteSupportKit")
        let workRoot = sandbox.appendingPathComponent("work")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")

        try fileManager.createDirectory(at: packageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "FixtureRoot",
            targets: [.target(name: "FixtureRoot")]
        )
        """.write(to: sandbox.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "RemoteSupportKit",
            products: [
                .library(name: "RemoteSupportKit", targets: ["RemoteSupportKit"])
            ],
            targets: [
                .target(name: "RemoteSupportKit")
            ]
        )
        """.write(to: packageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        public enum RemoteSupportKit {
            public static let value = "vendored"
        }
        """.write(to: packageSources.appendingPathComponent("RemoteSupportKit.swift"), atomically: true, encoding: .utf8)
        try """
        .package(url: "https://example.com/remote-support-kit.git", from: "1.0.0")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
                "--root-dir", sandbox.path,
                "--work-root", workRoot.path,
                "--dependencies-in", dependenciesIn.path,
                "--dependencies-out", dependenciesOut.path,
                "--skip-source-lowering",
                "--require-vendored-sources",
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        let resolvedPackagePath = packageDir.resolvingSymlinksInPath().path

        #expect(rewrittenDependencies.contains(".package(name: \"remote-support-kit\", path:"))
        #expect(
            rewrittenDependencies.contains(resolvedPackagePath)
                || rewrittenDependencies.contains("/private\(resolvedPackagePath)")
        )
        #expect(!rewrittenDependencies.contains("https://example.com/remote-support-kit.git"))
    }

    @Test("Generated app dependency preparation can reuse a shared prepared package cache")
    func generatedAppDependencyPreparationCanReuseSharedPreparedPackageCache() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-prepared-cache-\(UUID().uuidString)")
        let packageDir = sandbox.appendingPathComponent("third_party/SharedWidget")
        let packageSources = packageDir.appendingPathComponent("Sources/SharedWidget")
        let workRoot = sandbox.appendingPathComponent("work")
        let cacheRoot = sandbox.appendingPathComponent("cache")
        let dependenciesIn = sandbox.appendingPathComponent("dependencies-in.swift")
        let dependenciesOut = sandbox.appendingPathComponent("dependencies-out.swift")
        let secondDependenciesOut = sandbox.appendingPathComponent("dependencies-out-second.swift")

        try fileManager.createDirectory(at: packageSources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "SharedWidget",
            products: [
                .library(name: "SharedWidget", targets: ["SharedWidget"])
            ],
            targets: [
                .target(name: "SharedWidget")
            ]
        )
        """.write(to: packageDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        import SwiftUI

        public struct SharedWidgetView: View {
            public var body: some View { Text("Cached") }
        }
        """.write(to: packageSources.appendingPathComponent("SharedWidget.swift"), atomically: true, encoding: .utf8)
        try """
        .package(name: "SharedWidget", path: "\(packageDir.path)")
        """.write(to: dependenciesIn, atomically: true, encoding: .utf8)

        let arguments = [
            "python3",
            root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py").path,
            "--root-dir", root.path,
            "--work-root", workRoot.path,
            "--dependencies-in", dependenciesIn.path,
            "--dependencies-out", dependenciesOut.path,
            "--prepared-cache-dir", cacheRoot.path,
            "--skip-source-lowering",
        ]

        let first = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: arguments
        )
        #expect(first.status == 0, Comment(rawValue: first.output))

        let rewrittenDependencies = try String(contentsOf: dependenciesOut, encoding: .utf8)
        let cacheEntries = try fileManager.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: nil
        )
        let preparedPackage = try #require(cacheEntries.first { $0.lastPathComponent.hasPrefix("SharedWidget-") })
        let preparedManifest = try String(
            contentsOf: preparedPackage.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(rewrittenDependencies.contains("quillui-prepared-cache"))
        #expect(rewrittenDependencies.contains("cache/SharedWidget-"))
        #expect(!rewrittenDependencies.contains("work/prepared-packages"))
        #expect(preparedManifest.contains(".package(name: \"QuillUI\", path:"))
        #expect(preparedManifest.contains(".product(name: \"SwiftUI\", package: \"QuillUI\")"))

        let futureDate = Date(timeIntervalSince1970: 2_000_000_000)
        try fileManager.setAttributes(
            [.modificationDate: futureDate],
            ofItemAtPath: packageDir.appendingPathComponent("Package.swift").path
        )
        try fileManager.setAttributes(
            [.modificationDate: futureDate],
            ofItemAtPath: packageSources.appendingPathComponent("SharedWidget.swift").path
        )

        var secondArguments = arguments
        if let outIndex = secondArguments.firstIndex(of: dependenciesOut.path) {
            secondArguments[outIndex] = secondDependenciesOut.path
        }
        let second = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: secondArguments
        )
        #expect(second.status == 0, Comment(rawValue: second.output))
        #expect(second.output.contains("reused prepared local SwiftPM dependency"))
    }

    @Test("Vendored app source helper materializes local source under upstream cache")
    func vendoredAppSourceHelperMaterializesLocalSourceUnderUpstreamCache() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-vendored-app-source-\(UUID().uuidString)")
        let sourceDir = sandbox.appendingPathComponent("vendor/apps/demo/App")
        let destination = sandbox.appendingPathComponent(".upstream/demo")

        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        public struct DemoAppSource {
            public static let value = "vendored"
        }
        """.write(to: sourceDir.appendingPathComponent("Demo.swift"), atomically: true, encoding: .utf8)
        try """
        quillui-app-source-vendor/v1
        app=demo
        source=git:1234567890abcdef
        """.write(
            to: sourceDir.deletingLastPathComponent().appendingPathComponent(".quillui-vendor-source-fingerprint"),
            atomically: true,
            encoding: .utf8
        )

        let resolveVendoredResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-lc",
                "source \"$0\"; quillui_resolve_app_source_dir \"$1\" demo App",
                root.appendingPathComponent("scripts/quillui-vendored-source.sh").path,
                sandbox.path,
            ]
        )
        #expect(resolveVendoredResult.status == 0, Comment(rawValue: resolveVendoredResult.output))
        #expect(
            resolveVendoredResult.output.trimmingCharacters(in: .whitespacesAndNewlines) == sourceDir.path,
            Comment(rawValue: resolveVendoredResult.output)
        )

        let summaryResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-lc",
                "source \"$0\"; quillui_print_vendored_app_source_summary \"$1\" demo",
                root.appendingPathComponent("scripts/quillui-vendored-source.sh").path,
                sandbox.path,
            ]
        )
        #expect(summaryResult.status == 0, Comment(rawValue: summaryResult.output))
        #expect(
            summaryResult.output.contains("vendored demo source snapshot: git:1234567890abcdef"),
            Comment(rawValue: summaryResult.output)
        )

        let materializeResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-lc",
                "source \"$0\"; quillui_materialize_vendored_app_source \"$1\" demo \"$2\"",
                root.appendingPathComponent("scripts/quillui-vendored-source.sh").path,
                sandbox.path,
                destination.path,
            ]
        )

        #expect(materializeResult.status == 0, Comment(rawValue: materializeResult.output))
        #expect(materializeResult.output.contains("vendored demo source"))
        #expect(materializeResult.output.contains("vendor/apps/demo"))
        #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("App/Demo.swift").path))
        #expect(fileManager.fileExists(atPath: destination.appendingPathComponent(".quillui-materialized-vendor-source-fingerprint").path))

        try """
        public struct DemoAppSource {
            public static let value = "patched"
        }
        """.write(to: destination.appendingPathComponent("App/Demo.swift"), atomically: true, encoding: .utf8)

        let reusedMaterializeResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-lc",
                "source \"$0\"; quillui_materialize_vendored_app_source \"$1\" demo \"$2\"",
                root.appendingPathComponent("scripts/quillui-vendored-source.sh").path,
                sandbox.path,
                destination.path,
            ]
        )
        #expect(reusedMaterializeResult.status == 0, Comment(rawValue: reusedMaterializeResult.output))
        #expect(reusedMaterializeResult.output.contains("reused materialized vendored demo source"))
        let reusedDestinationSource = try String(contentsOf: destination.appendingPathComponent("App/Demo.swift"), encoding: .utf8)
        #expect(reusedDestinationSource.contains("\"patched\""))

        try """
        public struct DemoAppSource {
            public static let value = "updated"
        }
        """.write(to: sourceDir.appendingPathComponent("Demo.swift"), atomically: true, encoding: .utf8)
        try """
        quillui-app-source-vendor/v1
        app=demo
        source=git:fedcba0987654321
        """.write(
            to: sourceDir.deletingLastPathComponent().appendingPathComponent(".quillui-vendor-source-fingerprint"),
            atomically: true,
            encoding: .utf8
        )

        let refreshedMaterializeResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-lc",
                "source \"$0\"; quillui_materialize_vendored_app_source \"$1\" demo \"$2\"",
                root.appendingPathComponent("scripts/quillui-vendored-source.sh").path,
                sandbox.path,
                destination.path,
            ]
        )
        #expect(refreshedMaterializeResult.status == 0, Comment(rawValue: refreshedMaterializeResult.output))
        #expect(refreshedMaterializeResult.output.contains("refreshing materialized vendored demo source"))
        #expect(refreshedMaterializeResult.output.contains("vendored demo source"))
        let refreshedDestinationSource = try String(contentsOf: destination.appendingPathComponent("App/Demo.swift"), encoding: .utf8)
        #expect(refreshedDestinationSource.contains("\"updated\""))

        let resolveRefreshResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-lc",
                "source \"$0\"; quillui_resolve_app_source_dir \"$1\" demo App",
                root.appendingPathComponent("scripts/quillui-vendored-source.sh").path,
                sandbox.path,
            ],
            environment: ["QUILLUI_REFRESH_VENDORED_SOURCE": "1"]
        )
        #expect(resolveRefreshResult.status == 0, Comment(rawValue: resolveRefreshResult.output))
        #expect(
            resolveRefreshResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                == destination.appendingPathComponent("App").path,
            Comment(rawValue: resolveRefreshResult.output)
        )

        let unsafeResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "bash",
                "-lc",
                "source \"$0\"; quillui_materialize_vendored_app_source \"$1\" demo \"$1/not-upstream/demo\"",
                root.appendingPathComponent("scripts/quillui-vendored-source.sh").path,
                sandbox.path,
            ]
        )

        #expect(unsafeResult.status == 2, Comment(rawValue: unsafeResult.output))
        #expect(unsafeResult.output.contains("refusing to materialize vendored demo outside .upstream"))
    }

    @Test("Lowered source cache key trusts vendored app source fingerprint")
    func loweredSourceCacheKeyTrustsVendoredAppSourceFingerprint() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-source-cache-key-\(UUID().uuidString)")
        let vendoredAppDir = sandbox.appendingPathComponent("vendor/apps/demo")
        let vendoredSourceDir = vendoredAppDir.appendingPathComponent("App")
        let vendoredSourceFile = vendoredSourceDir.appendingPathComponent("Demo.swift")
        let vendoredFingerprint = vendoredAppDir.appendingPathComponent(".quillui-vendor-source-fingerprint")
        let plainSourceDir = sandbox.appendingPathComponent("PlainApp")
        let plainSourceFile = plainSourceDir.appendingPathComponent("Plain.swift")

        try fileManager.createDirectory(at: vendoredSourceDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: plainSourceDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        public struct DemoAppSource {
            public static let value = "one"
        }
        """.write(to: vendoredSourceFile, atomically: true, encoding: .utf8)
        try """
        quillui-app-source-vendor/v1
        app=demo
        source=git:1111111111111111
        """.write(to: vendoredFingerprint, atomically: true, encoding: .utf8)
        try """
        public struct PlainAppSource {
            public static let value = "one"
        }
        """.write(to: plainSourceFile, atomically: true, encoding: .utf8)

        func cacheKey(sourceDir: URL) throws -> String {
            let result = try runSourceHygieneProcess(
                URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "python3",
                    root.appendingPathComponent("scripts/quillui-source-cache-key.py").path,
                    "--root-dir",
                    sandbox.path,
                    "--source-dir",
                    sourceDir.path,
                ]
            )
            #expect(result.status == 0, Comment(rawValue: result.output))
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let originalVendoredKey = try cacheKey(sourceDir: vendoredSourceDir)
        try """
        public struct DemoAppSource {
            public static let value = "locally-mutated"
        }
        """.write(to: vendoredSourceFile, atomically: true, encoding: .utf8)
        #expect(try cacheKey(sourceDir: vendoredSourceDir) == originalVendoredKey)

        try """
        quillui-app-source-vendor/v1
        app=demo
        source=git:2222222222222222
        """.write(to: vendoredFingerprint, atomically: true, encoding: .utf8)
        #expect(try cacheKey(sourceDir: vendoredSourceDir) != originalVendoredKey)

        let originalPlainKey = try cacheKey(sourceDir: plainSourceDir)
        try """
        public struct PlainAppSource {
            public static let value = "two"
        }
        """.write(to: plainSourceFile, atomically: true, encoding: .utf8)
        #expect(try cacheKey(sourceDir: plainSourceDir) != originalPlainKey)
    }

    @Test("Vendor app source script pins upstream checkout without git or build state")
    func vendorAppSourceScriptPinsUpstreamCheckoutWithoutGitOrBuildState() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-vendor-app-source-command-\(UUID().uuidString)")
        let scriptsDir = sandbox.appendingPathComponent("scripts")
        let upstreamDir = sandbox.appendingPathComponent(".upstream/demo")
        let vendorScript = scriptsDir.appendingPathComponent("vendor-app-source.sh")
        let vendoredDir = sandbox.appendingPathComponent("vendor/apps/demo")

        try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: upstreamDir.appendingPathComponent("App"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: upstreamDir.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: upstreamDir.appendingPathComponent(".swiftpm"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: upstreamDir.appendingPathComponent(".artifacts"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: upstreamDir.appendingPathComponent(".qa"), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: upstreamDir.appendingPathComponent("E2E/playwright/node_modules/pkg"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: upstreamDir.appendingPathComponent("E2E/playwright/test-results"),
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: sandbox) }

        try fileManager.copyItem(
            at: root.appendingPathComponent("scripts/vendor-app-source.sh"),
            to: vendorScript
        )
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vendorScript.path)
        try "public struct Demo {}\n".write(
            to: upstreamDir.appendingPathComponent("App/Demo.swift"),
            atomically: true,
            encoding: .utf8
        )
        let gitInit = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-C", upstreamDir.path, "init"]
        )
        #expect(gitInit.status == 0, Comment(rawValue: gitInit.output))
        let gitAdd = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-C", upstreamDir.path, "add", "App/Demo.swift"]
        )
        #expect(gitAdd.status == 0, Comment(rawValue: gitAdd.output))
        let gitCommit = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "git",
                "-C", upstreamDir.path,
                "-c", "user.name=QuillUI Test",
                "-c", "user.email=quillui@example.invalid",
                "commit",
                "-m", "Initial demo source"
            ]
        )
        #expect(gitCommit.status == 0, Comment(rawValue: gitCommit.output))
        try "build state\n".write(
            to: upstreamDir.appendingPathComponent(".build/state.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "swiftpm state\n".write(
            to: upstreamDir.appendingPathComponent(".swiftpm/config"),
            atomically: true,
            encoding: .utf8
        )
        try "artifact state\n".write(
            to: upstreamDir.appendingPathComponent(".artifacts/screenshot.png"),
            atomically: true,
            encoding: .utf8
        )
        try "qa state\n".write(
            to: upstreamDir.appendingPathComponent(".qa/render.log"),
            atomically: true,
            encoding: .utf8
        )
        try "node state\n".write(
            to: upstreamDir.appendingPathComponent("E2E/playwright/node_modules/pkg/index.js"),
            atomically: true,
            encoding: .utf8
        )
        try "playwright state\n".write(
            to: upstreamDir.appendingPathComponent("E2E/playwright/test-results/.last-run.json"),
            atomically: true,
            encoding: .utf8
        )

        let dryRun = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--dry-run", "demo"]
        )
        #expect(dryRun.status == 0, Comment(rawValue: dryRun.output))
        #expect(dryRun.output.contains("would vendor demo source"), Comment(rawValue: dryRun.output))
        #expect(!fileManager.fileExists(atPath: vendoredDir.path))

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "demo"]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("vendored demo source -> vendor/apps/demo"), Comment(rawValue: result.output))
        #expect(fileManager.fileExists(atPath: vendoredDir.appendingPathComponent("App/Demo.swift").path))
        #expect(!fileManager.fileExists(atPath: vendoredDir.appendingPathComponent(".git").path))
        #expect(!fileManager.fileExists(atPath: vendoredDir.appendingPathComponent(".build").path))
        #expect(!fileManager.fileExists(atPath: vendoredDir.appendingPathComponent(".swiftpm").path))
        #expect(!fileManager.fileExists(atPath: vendoredDir.appendingPathComponent(".artifacts").path))
        #expect(!fileManager.fileExists(atPath: vendoredDir.appendingPathComponent(".qa").path))
        #expect(!fileManager.fileExists(atPath: vendoredDir.appendingPathComponent("E2E/playwright/node_modules").path))
        #expect(!fileManager.fileExists(atPath: vendoredDir.appendingPathComponent("E2E/playwright/test-results").path))
        #expect(fileManager.fileExists(
            atPath: vendoredDir.appendingPathComponent(".quillui-vendor-source-fingerprint").path
        ))

        let vendorNote = try String(
            contentsOf: vendoredDir.appendingPathComponent("QUILLUI_VENDOR.md"),
            encoding: .utf8
        )
        #expect(vendorNote.contains("Vendored demo Source"))
        #expect(vendorNote.contains("Upstream: unknown"))
        #expect(vendorNote.contains("Keep the app source pristine"))

        try fileManager.createDirectory(
            at: vendoredDir.appendingPathComponent("E2E/playwright/node_modules/stale"),
            withIntermediateDirectories: true
        )
        try "stale\n".write(
            to: vendoredDir.appendingPathComponent("E2E/playwright/node_modules/stale/index.js"),
            atomically: true,
            encoding: .utf8
        )
        let forcedRefresh = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "demo"],
            environment: ["QUILLUI_VENDOR_FORCE": "1"]
        )
        #expect(forcedRefresh.status == 0, Comment(rawValue: forcedRefresh.output))
        #expect(!fileManager.fileExists(atPath: vendoredDir.appendingPathComponent("E2E/playwright/node_modules").path))

        let second = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "demo"]
        )
        #expect(second.status == 0, Comment(rawValue: second.output))
        #expect(
            second.output.contains("already vendored demo source -> vendor/apps/demo"),
            Comment(rawValue: second.output)
        )

        let plainUpstreamDir = sandbox.appendingPathComponent(".upstream/plain")
        let plainVendoredDir = sandbox.appendingPathComponent("vendor/apps/plain")
        try fileManager.createDirectory(
            at: plainUpstreamDir.appendingPathComponent("App"),
            withIntermediateDirectories: true
        )
        try "public struct Plain {}\n".write(
            to: plainUpstreamDir.appendingPathComponent("App/Plain.swift"),
            atomically: true,
            encoding: .utf8
        )
        let plainFirst = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "plain"]
        )
        #expect(plainFirst.status == 0, Comment(rawValue: plainFirst.output))
        #expect(fileManager.fileExists(
            atPath: plainVendoredDir.appendingPathComponent(".quillui-vendor-source-fingerprint").path
        ))
        let plainFingerprint = try String(
            contentsOf: plainVendoredDir.appendingPathComponent(".quillui-vendor-source-fingerprint"),
            encoding: .utf8
        )
        #expect(plainFingerprint.contains("source=tree:"), Comment(rawValue: plainFingerprint))

        let plainSecond = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "plain"]
        )
        #expect(plainSecond.status == 0, Comment(rawValue: plainSecond.output))
        #expect(
            plainSecond.output.contains("already vendored plain source -> vendor/apps/plain"),
            Comment(rawValue: plainSecond.output)
        )

        try "Custom provenance\n".write(
            to: plainVendoredDir.appendingPathComponent("QUILLUI_VENDOR.md"),
            atomically: true,
            encoding: .utf8
        )
        try "public struct Plain { public let value = 1 }\n".write(
            to: plainUpstreamDir.appendingPathComponent("App/Plain.swift"),
            atomically: true,
            encoding: .utf8
        )
        let plainRefresh = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "plain"]
        )
        #expect(plainRefresh.status == 0, Comment(rawValue: plainRefresh.output))
        #expect(plainRefresh.output.contains("vendored plain source -> vendor/apps/plain"))
        let preservedPlainNote = try String(
            contentsOf: plainVendoredDir.appendingPathComponent("QUILLUI_VENDOR.md"),
            encoding: .utf8
        )
        #expect(preservedPlainNote == "Custom provenance\n", Comment(rawValue: preservedPlainNote))
    }

    @Test("SwiftUI app vendor wrapper pins app source and SwiftPM pins")
    func swiftUIAppVendorWrapperPinsAppSourceAndSwiftPMPins() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-vendor-swiftui-app-source-\(UUID().uuidString)")
        let scriptsDir = sandbox.appendingPathComponent("scripts")
        let sourceDir = sandbox.appendingPathComponent("checkout/demo")
        let checkoutDir = sandbox.appendingPathComponent(".build/checkouts/trusted-router-swift")
        let vendoredAppDir = sandbox.appendingPathComponent("vendor/apps/demo")
        let vendoredPackageDir = sandbox.appendingPathComponent("third_party/trusted-router-swift")
        let wrapperScript = scriptsDir.appendingPathComponent("vendor-swiftui-app-source.sh")

        try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sourceDir.appendingPathComponent("Sources/Demo"), withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: checkoutDir.appendingPathComponent("Sources/TrustedRouter"),
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: sandbox) }

        for script in [
            "vendor-swiftui-app-source.sh",
            "vendor-app-source.sh",
            "vendor-swiftpm-sources.sh",
            "quillui-vendored-source.sh",
        ] {
            let destination = scriptsDir.appendingPathComponent(script)
            try fileManager.copyItem(
                at: root.appendingPathComponent("scripts/\(script)"),
                to: destination
            )
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Demo",
            dependencies: [
                .package(url: "https://github.com/jperla/trusted-router-swift.git", from: "0.4.1")
            ],
            targets: [
                .target(
                    name: "Demo",
                    dependencies: [.product(name: "TrustedRouter", package: "trusted-router-swift")]
                )
            ]
        )
        """.write(to: sourceDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try """
        {
          "pins" : [
            {
              "identity" : "trusted-router-swift",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/jperla/trusted-router-swift.git",
              "state" : {
                "revision" : "410cb034ce5a20b62f209d03d46a256cafe7b54f",
                "version" : "0.4.1"
              }
            }
          ],
          "version" : 3
        }
        """.write(to: sourceDir.appendingPathComponent("Package.resolved"), atomically: true, encoding: .utf8)
        try "import TrustedRouter\npublic struct DemoApp {}\n".write(
            to: sourceDir.appendingPathComponent("Sources/Demo/Demo.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "TrustedRouter",
            products: [.library(name: "TrustedRouter", targets: ["TrustedRouter"])],
            targets: [.target(name: "TrustedRouter")]
        )
        """.write(to: checkoutDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "public struct TrustedRouterClient {}\n".write(
            to: checkoutDir.appendingPathComponent("Sources/TrustedRouter/TrustedRouter.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                wrapperScript.path,
                "--source", sourceDir.path,
                "--scratch-path", sandbox.appendingPathComponent(".build").path,
                "demo",
            ]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("vendored demo source -> vendor/apps/demo"), Comment(rawValue: result.output))
        #expect(result.output.contains("vendored trusted-router-swift -> third_party/trusted-router-swift"), Comment(rawValue: result.output))
        #expect(fileManager.fileExists(atPath: vendoredAppDir.appendingPathComponent("Package.swift").path))
        #expect(fileManager.fileExists(atPath: vendoredAppDir.appendingPathComponent("Package.resolved").path))
        #expect(fileManager.fileExists(atPath: vendoredPackageDir.appendingPathComponent("Package.swift").path))
        #expect(fileManager.fileExists(
            atPath: vendoredPackageDir.appendingPathComponent("Sources/TrustedRouter/TrustedRouter.swift").path
        ))

        let dryRun = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                wrapperScript.path,
                "--dry-run",
                "--source", sourceDir.path,
                "--scratch-path", sandbox.appendingPathComponent(".build").path,
                "dry-demo",
            ]
        )
        #expect(dryRun.status == 0, Comment(rawValue: dryRun.output))
        #expect(dryRun.output.contains("would vendor dry-demo source"), Comment(rawValue: dryRun.output))
        #expect(dryRun.output.contains("would vendor trusted-router-swift -> third_party/trusted-router-swift"), Comment(rawValue: dryRun.output))
        #expect(!fileManager.fileExists(atPath: sandbox.appendingPathComponent("vendor/apps/dry-demo").path))
    }

    @Test("Linux lowering folds AppKit extension overrides into owning class")
    func linuxLoweringFoldsAppKitExtensionOverridesIntoOwningClass() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-extension-override-lowering-\(UUID().uuidString)")
        let sourceDir = sandbox.appendingPathComponent("Sources/Editor")
        let classFile = sourceDir.appendingPathComponent("EditorView.swift")
        let extensionFile = sourceDir.appendingPathComponent("EditorView+Input.swift")

        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        import AppKit

        open class EditorView: NSView {
            public func refreshEditor() {}
        }
        """.write(to: classFile, atomically: true, encoding: .utf8)

        try """
        import Foundation
        import QuillShims

        extension EditorView: NSTextInputClient {
            open override func keyDown(with event: NSEvent) {
                refreshEditor()
            }

            private func keepPrivateHelpersWithTheOverride() {}
        }
        """.write(to: extensionFile, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/lower-extension-overrides-for-linux.py").path,
                sourceDir.path,
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let loweredClass = try String(contentsOf: classFile, encoding: .utf8)
        let loweredExtension = try String(contentsOf: extensionFile, encoding: .utf8)

        #expect(loweredClass.contains("import Foundation"))
        #expect(loweredClass.contains("import QuillShims"))
        #expect(loweredClass.contains("open class EditorView: NSView, NSTextInputClient {"))
        #expect(loweredClass.contains("QuillUI folded extension: EditorView+Input.swift"))
        #expect(loweredClass.contains("open override func keyDown(with event: NSEvent)"))
        #expect(loweredClass.contains("private func keepPrivateHelpersWithTheOverride()"))
        #expect(!loweredExtension.contains("extension EditorView"))
    }

    @Test("Linux lowering removes impossible framework extension overrides")
    func linuxLoweringRemovesFrameworkExtensionOverrides() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-framework-extension-override-lowering-\(UUID().uuidString)")
        let sourceDir = sandbox.appendingPathComponent("Sources/Editor")
        let sourceFile = sourceDir.appendingPathComponent("NSTableView+Background.swift")

        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        import AppKit

        extension NSTableView {
            override open func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                backgroundColor = NSColor.clear
            }
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/lower-extension-overrides-for-linux.py").path,
                sourceDir.path,
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let lowered = try String(contentsOf: sourceFile, encoding: .utf8)
        #expect(lowered.contains("import AppKit"))
        #expect(!lowered.contains("extension NSTableView"))
        #expect(!lowered.contains("override open func viewDidMoveToWindow"))
    }

    @Test("Linux main-actor controller lowering wraps assignments but not comparisons")
    func linuxMainActorControllerLoweringSkipsComparisons() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-mainactor-assignment-lowering-\(UUID().uuidString)")
        let sourceDir = sandbox.appendingPathComponent("Sources/Editor")
        let sourceFile = sourceDir.appendingPathComponent("EditorController.swift")

        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try """
        import AppKit

        func configure(controller: NSViewController, configuration: AnyObject, model: AnyObject) -> Bool {
            controller.representedObject = model
            controller.items = children.map { child in
                Item(child: child)
            }
            controller.configuration == configuration &&
            controller.model === model
        }

        func install(child: Child) {
            item = NSSplitViewItem(viewController: NSHostingController(rootView: child))
        }

        func linesInRange(controller: EditorController) -> Int {
            guard let scrollView = controller.view as? NSScrollView else {
                return 0
            }
            return scrollView.hash
        }

        func setPosition(of index: Int, position: CGFloat) {
            viewController()?.splitView.setPosition(position, ofDividerAt: index)
        }

        func collapseView(with id: AnyHashable, _ enabled: Bool) {
            viewController()?.collapse(for: id, enabled: enabled)
        }

        func moveLines(controller: EditorController) {
            controller.moveLinesUp()
            controller.moveLinesDown()
        }

        func stopMonitoring(model: SettingsViewModel) {
            model.removeKeyDownMonitor()
            removeKeyDownMonitor()
        }

        func observe(workspace: Workspace, cancellables: inout Set<AnyCancellable>) {
            workspace.$highlightedFileItem
                .sink { [weak self] fileItem in
                    self?.controller?.reveal(fileItem)
                }
                .store(in: &cancellables)
            workspace.$searchResult
                .sink(receiveValue: { [weak self] results in
                    self?.controller?.updateNewSearchResults(results)
                })
        }

        func fileManagerUpdated(updatedItems: Set<FileItem>) {
            guard let outlineView = controller?.outlineView else { return }
            controller?.shouldReloadAfterDoneEditing = true
            controller?.shouldSendSelectionUpdate = false
            outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
            controller?.shouldSendSelectionUpdate = true
        }

        func updateToolbarItem() {
            if shouldShow {
                toolbar.insertItem(withItemIdentifier: .space, at: 1)
            } else {
                toolbar.removeItem(at: 1)
            }
        }

        @MainActor
        final class DesktopController {
            static let defaultDelay: UInt64 = 1_500_000_000

            private let presenter: any DesktopPresenter
            private let delay: UInt64
            private let optionalPresenter: (any DesktopPresenter)?

            init(
                presenter: any DesktopPresenter = DesktopPresenterImpl(),
                delay: UInt64 = Self.defaultDelay,
                optionalPresenter: (any DesktopPresenter)? = DesktopPresenterImpl()
            ) {
                self.presenter = presenter
                self.delay = delay
                self.optionalPresenter = optionalPresenter
            }
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/lower-mainactor-assignments-for-linux.py").path,
                sourceDir.path,
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))

        let lowered = try String(contentsOf: sourceFile, encoding: .utf8)
        #expect(lowered.contains("MainActor.assumeIsolated { [model] in\n        controller.representedObject = model\n    }"))
        #expect(lowered.contains("controller.items = children.map { child in\n        Item(child: child)\n    }"))
        #expect(!lowered.contains("MainActor.assumeIsolated {\n        controller.items = children.map { child in\n    }"))
        #expect(lowered.contains("controller.configuration == configuration &&"))
        #expect(lowered.contains("controller.model === model"))
        #expect(!lowered.contains("controller.configuration == configuration &&\n    }"))
        #expect(!lowered.contains("controller.model === model\n    }"))
        #expect(lowered.contains("NSSplitViewItem(viewController: MainActor.assumeIsolated { NSHostingController(rootView: child) })"))
        #expect(lowered.contains("let scrollView = MainActor.assumeIsolated { controller.view } as? NSScrollView"))
        #expect(lowered.contains("MainActor.assumeIsolated {\n        viewController()?.splitView.setPosition(position, ofDividerAt: index)\n    }"))
        #expect(lowered.contains("MainActor.assumeIsolated {\n        viewController()?.collapse(for: id, enabled: enabled)\n    }"))
        #expect(lowered.contains("MainActor.assumeIsolated {\n        controller.moveLinesUp()\n    }"))
        #expect(lowered.contains("MainActor.assumeIsolated {\n        controller.moveLinesDown()\n    }"))
        #expect(lowered.contains("MainActor.assumeIsolated {\n        model.removeKeyDownMonitor()\n    }"))
        #expect(lowered.contains("MainActor.assumeIsolated {\n        removeKeyDownMonitor()\n    }"))
        #expect(lowered.contains(".sink { [weak self] fileItem in\n            MainActor.assumeIsolated {\n                self?.controller?.reveal(fileItem)\n            }\n        }"))
        #expect(lowered.contains(".sink(receiveValue: { [weak self] results in\n            MainActor.assumeIsolated {\n                self?.controller?.updateNewSearchResults(results)\n            }\n        })"))
        #expect(lowered.contains("func fileManagerUpdated(updatedItems: Set<FileItem>) {\n    MainActor.assumeIsolated {\n        guard let outlineView = controller?.outlineView else { return }"))
        #expect(lowered.contains("func updateToolbarItem() {\n    MainActor.assumeIsolated {\n        if shouldShow {\n            toolbar.insertItem(withItemIdentifier: .space, at: 1)"))
        #expect(lowered.contains("@MainActor\n    init("))
        #expect(lowered.contains("presenter: (any DesktopPresenter)? = nil,"))
        #expect(lowered.contains("delay: UInt64? = nil,"))
        #expect(lowered.contains("optionalPresenter: (any DesktopPresenter)? = DesktopPresenterImpl()"))
        #expect(lowered.contains("let presenter = presenter ?? DesktopPresenterImpl()\n        let delay = delay ?? Self.defaultDelay\n        self.presenter = presenter"))

        let secondPass = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/lower-mainactor-assignments-for-linux.py").path,
                sourceDir.path,
            ]
        )
        #expect(secondPass.status == 0, Comment(rawValue: secondPass.output))
        let loweredAgain = try String(contentsOf: sourceFile, encoding: .utf8)
        #expect(loweredAgain == lowered)
    }

    @Test("Linux conditional lowering resolves platform-only branches")
    func linuxConditionalLoweringResolvesPlatformOnlyBranches() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-linux-conditions-\(UUID().uuidString)", isDirectory: true)
        let sourceDir = sandbox.appendingPathComponent("Sources", isDirectory: true)
        let sourceFile = sourceDir.appendingPathComponent("ConditionalView.swift")
        let inactiveIOSDir = sourceDir.appendingPathComponent("UI/iOS", isDirectory: true)
        let inactiveWatchDir = sourceDir.appendingPathComponent("UI/watchOS", isDirectory: true)
        let desktopDir = sourceDir.appendingPathComponent("UI/macOS", isDirectory: true)

        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: inactiveIOSDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: inactiveWatchDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: desktopDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try #"struct DeadIOSView {}"#.write(
            to: inactiveIOSDir.appendingPathComponent("DeadIOSView.swift"),
            atomically: true,
            encoding: .utf8
        )
        try #"struct DeadWatchView {}"#.write(
            to: inactiveWatchDir.appendingPathComponent("DeadWatchView.swift"),
            atomically: true,
            encoding: .utf8
        )
        try #"struct DesktopView {}"#.write(
            to: desktopDir.appendingPathComponent("DesktopView.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        import SwiftUI

        struct ConditionalView: View {
            var body: some View {
                Text("Hello")
                    .padding()
        #if os(iOS)
                    .showIf(false)
        #endif
            }

            var platform: String {
        #if os(iOS)
                "ios"
        #elseif os(macOS) || os(Linux)
                "linuxish"
        #else
                "other"
        #endif
            }

        #if canImport(UIKit)
            let unresolved = true
        #endif
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/lower-linux-conditional-compilation.py").path,
                sourceDir.path,
            ]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("Pruned 2 inactive platform source directories"))
        #expect(!fileManager.fileExists(atPath: inactiveIOSDir.path))
        #expect(!fileManager.fileExists(atPath: inactiveWatchDir.path))
        #expect(fileManager.fileExists(atPath: desktopDir.appendingPathComponent("DesktopView.swift").path))

        let lowered = try String(contentsOf: sourceFile, encoding: .utf8)
        #expect(lowered.contains("Text(\"Hello\")\n            .padding()"))
        #expect(!lowered.contains(".showIf(false)"))
        #expect(!lowered.contains("#if os(iOS)"))
        #expect(lowered.contains("\"linuxish\""))
        #expect(!lowered.contains("\"ios\""))
        #expect(!lowered.contains("\"other\""))
        #expect(lowered.contains("#if canImport(UIKit)"))

        let secondPass = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/lower-linux-conditional-compilation.py").path,
                sourceDir.path,
            ]
        )
        #expect(secondPass.status == 0, Comment(rawValue: secondPass.output))
        #expect(secondPass.output.contains("Pruned 0 inactive platform source directories"))
        let loweredAgain = try String(contentsOf: sourceFile, encoding: .utf8)
        #expect(loweredAgain == lowered)
    }

    @Test("MarkdownUI table rows render backend-stable full-width dividers")
    func markdownUITableRowsRenderBackendStableFullWidthDividers() throws {
        let root = try packageRoot()
        let markdownUI = try String(
            contentsOf: root.appendingPathComponent("Sources/MarkdownUI/MarkdownUI.swift"),
            encoding: .utf8
        )

        #expect(markdownUI.contains("private var tableDividerRule: some View"))
        #expect(markdownUI.contains("Color(red: 0.82, green: 0.82, blue: 0.82)"))
        #expect(markdownUI.contains(".frame(height: 1)\n            .frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(markdownUI.contains("tableDividerRule"))
    }

    @Test("WireGuard upstream fetch normalizes default isolation flags")
    func wireGuardUpstreamFetchNormalizesDefaultIsolationFlags() throws {
        let root = try packageRoot()
        let script = try String(
            contentsOf: root.appendingPathComponent("scripts/fetch-upstream.sh"),
            encoding: .utf8
        )

        #expect(script.contains("patching wireguard-apple Package.swift default-isolation flags"))
        #expect(script.contains("[\"-Xfrontend\", \"-default-isolation\", \"-Xfrontend\", \"MainActor\"]"))
        #expect(script.contains(#"r'\[\s*"-default-isolation"\s*,\s*"MainActor"\s*\]'"#))
    }

    @Test("Signal UIKit renderer maps editable UITextView through GTK entry bridge")
    func signalUIKitRendererMapsEditableTextViewThroughGtkEntryBridge() throws {
        let manifest = try packageSource("Package.swift")
        let renderer = try packageSource("Sources/SignalUIRenderCore/Renderer.swift")
        let host = try packageSource("Sources/SignalUIRender/main.swift")
        let mapper = try packageSource("Sources/SignalUIRenderCore/Mappers/LabelImageMappers.swift")
        let bridge = try packageSource("Sources/SignalUIRenderCore/Mappers/TextViewEntryBridge.swift")
        let gtkShim = try packageSource("Sources/CGtk4/shim.h")
        let captureScript = try packageSource("scripts/signal-render-capture.sh")
        let pendingSmokeScript = try packageSource("scripts/signal-render-pending-smoke.sh")
        let pendingContinueSmokeScript = try packageSource("scripts/signal-render-pending-continue-smoke.sh")
        let sendSmokeScript = try packageSource("scripts/signal-render-send-smoke.sh")
        let receiveSmokeScript = try packageSource("scripts/signal-render-receive-smoke.sh")
        let signalChatSmokeScript = try packageSource("scripts/signal-chat-stub-smoke.sh")
        let signalChatStub = try packageSource("scripts/signal-chat-stub-bridge.py")
        let screenshotVerifier = try packageSource("scripts/verify-backend-screenshot.py")
        let signalDockerfile = try packageSource("docker/quillui-signal-build.Dockerfile")

        #expect(manifest.contains("name: \"SignalUIRenderCore\""))
        #expect(manifest.contains("name: \"signal-ui-render-core-smoke\""))
        #expect(manifest.contains("name: \"SignalUIRenderCoreSmoke\""))
        #expect(manifest.contains("path: \"Sources/SignalUIRenderCore\""))
        #expect(manifest.contains("path: \"Sources/SignalUIRenderCoreSmoke\""))
        #expect(manifest.contains("\"QuillUIKit\", \"UIKit\", \"QuillFoundation\", \"QuartzCore\", \"CGtk4\""))
        #expect(manifest.contains("\"Fonts\",\n                \"Views/BodyRanges/SpoilerRendering/SpoilerParticleShader.metal\""))
        #expect(!renderer.contains("import SignalUI"))
        #expect(!renderer.contains("as? ColorOrGradientValue"))
        #expect(renderer.contains("ReflectedSignalColorOrGradient"))
        #expect(renderer.contains("String(describing: type(of: view)) == \"CVColorOrGradientView\""))
        #expect(mapper.contains("gtk_entry_new()!"))
        #expect(mapper.contains("placeholderText(for: textView) != nil"))
        #expect(mapper.contains("typeName.contains(\"LinkingTextView\")"))
        #expect(mapper.contains("quillSignalConnectTextViewEntrySignals"))
        #expect(bridge.contains("textView.quillReplaceCharacters("))
        #expect(bridge.contains("context.activateReturnKey()"))
        #expect(bridge.contains("quillSignalRenderSetFirstTextEntry"))
        #expect(bridge.contains("quillSignalRenderClickButton"))
        #expect(bridge.contains("labelText: String"))
        #expect(bridge.contains("quill_widget_is_label"))
        #expect(bridge.contains("quill_label_get_text"))
        #expect(bridge.contains("quill_widget_is_editable"))
        #expect(bridge.contains("quill_widget_is_button"))
        #expect(bridge.contains("quill_signal_emit_clicked"))
        #expect(bridge.contains("quill_editable_get_text"))
        #expect(bridge.contains("quill_entry_set_placeholder_text"))
        #expect(bridge.contains("notify::has-focus"))
        #expect(host.contains("SIGNAL_UI_RENDER_TYPE_TEXT"))
        #expect(host.contains("SIGNAL_UI_RENDER_CLICK_SEND"))
        #expect(host.contains("SIGNAL_UI_RENDER_CLICK_SEND_DELAY_MS"))
        #expect(host.contains("SIGNAL_UI_RENDER_LOG_INTERACTIONS"))
        #expect(host.contains("SIGNAL_UI_RENDER_DRAIN_SEND_QUEUE"))
        #expect(host.contains("SIGNAL_UI_RENDER_INJECT_INCOMING_TEXT"))
        #expect(host.contains("SIGNAL_UI_RENDER_CLICK_BUTTON_LABEL"))
        #expect(host.contains("SIGNAL_UI_RENDER_CLICK_BUTTON_LABEL_DELAY_MS"))
        #expect(host.contains("SIGNAL_UI_RENDER_RERENDER_DELAY_MS"))
        #expect(host.contains("pending request continuation settled"))
        #expect(host.contains("rerendered UIKit tree after"))
        #expect(host.contains("QuillSignalRealConversationProbe.injectAcceptedIncomingMessage"))
        #expect(host.contains("QuillSignalRealConversationProbe.settlePendingRequestContinuation"))
        #expect(host.contains("ThreadUtil.enqueueSendQueue.enqueue(operation: {})"))
        #expect(host.contains("runGtkMainLoopCooperatively()"))
        #expect(host.contains("while g_main_context_iteration(nil, 0) != 0 {}"))
        #expect(host.contains("g_timeout_add"))
        #expect(host.contains("scheduled send button click"))
        #expect(host.contains("quillSignalRenderSetFirstTextEntry"))
        #expect(host.contains("signal-uikit-button-send"))
        #expect(gtkShim.contains("static inline int quill_widget_is_editable"))
        #expect(gtkShim.contains("static inline int quill_widget_is_button"))
        #expect(gtkShim.contains("static inline int quill_widget_is_label"))
        #expect(gtkShim.contains("static inline const char *quill_label_get_text"))
        #expect(gtkShim.contains("static inline int quill_widget_has_css_class"))
        #expect(gtkShim.contains("static inline gulong quill_signal_connect_data"))
        #expect(captureScript.contains("conversation|real-conversation|real-conversation-accepted)"))
        #expect(captureScript.contains("swift build --show-bin-path"))
        #expect(!captureScript.contains(".build/aarch64-unknown-linux-gnu"))
        #expect(captureScript.contains("prepend_env_path QUILLUI_LOCALIZATION_DIRS \"$ROOT/.upstream/signal-ios/Signal\""))
        #expect(captureScript.contains("prepend_env_path QUILLUI_RESOURCE_DIRS \"$ROOT/.upstream/signal-ios/SignalUI\""))
        #expect(captureScript.contains("width=\"${SIGNAL_RENDER_CAPTURE_WIDTH:-$default_width}\""))
        #expect(captureScript.contains("GSK_RENDERER=\"${GSK_RENDERER:-cairo}\""))
        #expect(pendingSmokeScript.contains("swift build --show-bin-path"))
        #expect(pendingSmokeScript.contains("\"$ROOT/scripts/signal-render-capture.sh\" real-conversation"))
        #expect(pendingSmokeScript.contains("MessageRequestView"))
        #expect(pendingSmokeScript.contains("Name not verified"))
        #expect(pendingSmokeScript.contains("signal-real-conversation-pending"))
        #expect(pendingContinueSmokeScript.contains("SIGNAL_UI_RENDER_CLICK_BUTTON_LABEL=Continue"))
        #expect(pendingContinueSmokeScript.contains("SIGNAL_UI_RENDER_AUTO_CONFIRM_ACTION_SHEETS=1"))
        #expect(pendingContinueSmokeScript.contains("pending request continuation settled dbPending=false viewModelPending=false bottomViewType=inputToolbar hasInputToolbar=true"))
        #expect(pendingContinueSmokeScript.contains("systemRows=[info:acceptedMessageRequest:cell=543x80:collapse=false:button=184x31]"))
        #expect(pendingContinueSmokeScript.contains("ConversationInputToolbar"))
        #expect(pendingContinueSmokeScript.contains("You accepted Maya Rivera's message request."))
        #expect(pendingContinueSmokeScript.contains("CVCell frame=(0,444,760x80)"))
        #expect(pendingContinueSmokeScript.contains("UIButton frame=(152,37,184x31)"))
        #expect(pendingContinueSmokeScript.contains("require_log_absent_after_rerender \"acceptedMessageRequest\""))
        #expect(pendingContinueSmokeScript.contains("require_log_absent_after_rerender \"MessageRequestView\""))
        #expect(pendingContinueSmokeScript.contains("signal-real-conversation-accepted-request"))
        #expect(sendSmokeScript.contains("swift build --show-bin-path"))
        #expect(sendSmokeScript.contains("SIGNAL_UI_RENDER_DRAIN_SEND_QUEUE=1"))
        #expect(sendSmokeScript.contains(#"require_log_line 'signal-ui-render: after send click body=""'"#))
        #expect(sendSmokeScript.contains("signal-ui-render: after send click interactions send queue drained"))
        #expect(sendSmokeScript.contains("signal-ui-render: after send click interactions count=3 bodies="))
        #expect(sendSmokeScript.contains("verify-backend-screenshot.py"))
        #expect(sendSmokeScript.contains("signal-real-conversation-send"))
        #expect(receiveSmokeScript.contains("SIGNAL_UI_RENDER_INJECT_INCOMING_TEXT"))
        #expect(receiveSmokeScript.contains("signal-ui-render: scheduled incoming injection"))
        #expect(receiveSmokeScript.contains("signal-ui-render: injected incoming message summary count=3 bodies="))
        #expect(receiveSmokeScript.contains("verify-backend-screenshot.py"))
        #expect(receiveSmokeScript.contains("signal-real-conversation-receive"))
        #expect(signalChatSmokeScript.contains("swift build --disable-index-store"))
        #expect(signalChatSmokeScript.contains("--product signal-chat"))
        #expect(signalChatSmokeScript.contains("scripts/signal-chat-stub-bridge.py"))
        #expect(signalChatSmokeScript.contains("QSIGNAL_SOCK=\"$socket_path\""))
        #expect(signalChatSmokeScript.contains("verify-backend-screenshot.py"))
        #expect(signalChatSmokeScript.contains("signal-chat-stub"))
        #expect(signalChatStub.contains("just saw the window. this is the real deal"))
        #expect(!signalChatStub.contains("🔥"))
        #expect(signalDockerfile.contains("fonts-noto-color-emoji"))
        #expect(signalDockerfile.contains("libc++-dev"))
        #expect(signalDockerfile.contains("libc++abi-dev"))
        #expect(signalDockerfile.contains("--fix-missing"))
        #expect(signalDockerfile.contains("for i in 1 2 3 4 5; do"))
        #expect(!signalDockerfile.contains("\n        clang \\"))
        #expect(signalDockerfile.contains("Do not apt-install Ubuntu's clang"))
        #expect(signalDockerfile.contains("apt-get install -y --no-install-recommends --fix-broken || true"))
        #expect(signalDockerfile.contains("dpkg --configure -a || true"))
        #expect(screenshotVerifier.contains("def validate_signal_real_conversation"))
        #expect(screenshotVerifier.contains("def validate_signal_chat_stub"))
        #expect(screenshotVerifier.contains("signal-chat-stub"))
        #expect(screenshotVerifier.contains("signal-real-conversation-pending"))
        #expect(screenshotVerifier.contains("signal-real-conversation-accepted-request"))
        #expect(screenshotVerifier.contains("signal-real-conversation-send"))
        #expect(screenshotVerifier.contains("signal-real-conversation-receive"))
        #expect(screenshotVerifier.contains("request_warning_pixels >= 120"))
        #expect(screenshotVerifier.contains("request_action_pixels >= 80"))
        #expect(screenshotVerifier.contains("request_continue_pixels >= 120"))
        #expect(screenshotVerifier.contains("bottom_outgoing_pixels >= 2_500"))
        #expect(screenshotVerifier.contains("bottom_incoming_pixels >= 2_500"))
    }

    @Test("Signal upstream patches keep the real send pipeline database-backed")
    func signalUpstreamPatchesKeepRealSendPipelineDatabaseBacked() throws {
        let upstreamFetch = try packageSource("scripts/fetch-upstream.sh")
        let signalPortLink = try packageSource("scripts/quill-signal-link-ports.sh")
        let probe = try packageSource("Sources/SignalAppPort/QuillRealConversationProbe.swift")
        let infoMessagePort = try packageSource("Sources/SignalServiceKitObjCPort/QuillTSInfoMessage.swift")
        let summaryStart = try #require(probe.range(of: "acceptedInteractionDebugSummary()"))
        let summaryEnd = try #require(probe[summaryStart.upperBound...].range(of: "private static func makeViewController"))
        let summaryQuery = String(probe[summaryStart.lowerBound..<summaryEnd.lowerBound])

        #expect(upstreamFetch.contains("patching signal-ios SDSRecord.swift insert row-id propagation"))
        #expect(upstreamFetch.contains("delegate?.updateRowId(transaction.database.lastInsertedRowID)"))
        #expect(upstreamFetch.contains("SDSRecord.sdsInsert shape changed"))
        #expect(probe.contains("acceptedInteractionDebugSummary()"))
        #expect(probe.contains("injectAcceptedIncomingMessage"))
        #expect(probe.contains("profileManagerRef.localProfileKey(tx: tx) == nil"))
        #expect(probe.contains("setLocalProfileKey("))
        #expect(probe.contains("Aes256Key.keyByteLength"))
        #expect(probe.contains("settlePendingRequestContinuation"))
        #expect(probe.contains("pendingRequestDebugSummary"))
        #expect(probe.contains("systemMessageLayoutDebugSummary"))
        #expect(probe.contains("reloadConversationCollection(cvc)"))
        #expect(probe.contains("cvc.layout.invalidateLayout()"))
        #expect(probe.contains("cvc.collectionView.reloadData()"))
        #expect(probe.contains("SUIEnvironment.shared.quillInstallRenderLinkPreviewFetcher(QuillSignalRenderLinkPreviewFetcher())"))
        #expect(probe.contains("TSIncomingMessageBuilder.withDefaultValues"))
        #expect(probe.contains("CVScrollAction(action: .bottomForNewMessage, isAnimated: false)"))
        #expect(signalPortLink.contains("quillSignalCorelibsSafeAttributes"))
        #expect(signalPortLink.contains("SIGNAL_UI_RENDER_AUTO_CONFIRM_ACTION_SHEETS"))
        #expect(signalPortLink.contains("auto-confirmed action sheet"))
        #expect(infoMessagePort.contains("return _infoMessagePreviewText(tx: transaction)"))
        #expect(!infoMessagePort.contains("return String(describing: messageType)"))
        #expect(summaryQuery.contains("WHERE uniqueThreadId = ?"))
        #expect(!summaryQuery.contains("WHERE threadUniqueId = ?"))
        #expect(summaryQuery.contains("ORDER BY timestamp ASC, id ASC"))
    }

    @Test("Signal UIKit renderer maps UIButtons through GTK button actions")
    func signalUIKitRendererMapsButtonsThroughGtkButtonActions() throws {
        let renderer = try packageSource("Sources/SignalUIRenderCore/Renderer.swift")
        let controls = try packageSource("Sources/SignalUIRenderCore/Mappers/ControlMappers.swift")

        let buttonMapperIndex = try #require(renderer.range(of: "UIButtonGtkMapper.self"))
        let genericMapperIndex = try #require(renderer.range(of: "GenericViewGtkMapper.self"))
        #expect(buttonMapperIndex.lowerBound < genericMapperIndex.lowerBound)
        #expect(controls.contains("gtk_button_new()!"))
        #expect(controls.contains("gtk_button_set_child"))
        #expect(controls.contains("installButtonContentMutationBridge(on: widget, button: button, ctx: ctx)"))
        #expect(controls.contains("applyButtonRoleClasses(widget, button: button)"))
        #expect(controls.contains("applyConfigurationStyle(widget, button: button)"))
        #expect(controls.contains("button.configuration?.baseBackgroundColor ?? button.configuration?.background.backgroundColor"))
        #expect(controls.contains("button.configuration?.quillStyle == \"gray\""))
        #expect(controls.contains("button.layer.cornerRadius"))
        #expect(controls.contains("signal-uikit-button-\\(role)"))
        #expect(controls.contains("name.contains(\"arrow-up\") || name.contains(\"send\") || name.contains(\"paperplane\")"))
        #expect(controls.contains("button.quillSetSubviewMutationHandler(\"SignalUIRender.buttonContent\")"))
        #expect(controls.contains("gtk_button_set_child(buttonPointer(widget), child)"))
        #expect(controls.contains("gtk_widget_set_overflow(fixed, GTK_OVERFLOW_HIDDEN)"))
        #expect(controls.contains("clippedButtonChildFrame(subview.frame, in: button)"))
        #expect(controls.contains("sendActions(for: [.primaryActionTriggered, .touchUpInside])"))
        #expect(controls.contains("\"clicked\""))
        #expect(controls.contains("g_signal_connect_data("))
        #expect(controls.contains("UISwitchGTKActionContext"))
        #expect(controls.contains("\"notify::active\""))
        #expect(controls.contains("gtk_swift_switch_get_active"))
        #expect(controls.contains("uiSwitch.sendActions(for: .valueChanged)"))
        #expect(controls.contains("uiSwitch.quillSetViewMutationHandler(\"SignalUIRender.switchState\")"))
    }

    @Test("Signal UIKit renderer binds live UIKit mutations onto GTK widgets")
    func signalUIKitRendererBindsLiveViewMutationsOntoGtkWidgets() throws {
        let renderer = try packageSource("Sources/SignalUIRenderCore/Renderer.swift")
        let containers = try packageSource("Sources/SignalUIRenderCore/Mappers/ContainerMappers.swift")
        let collections = try packageSource("Sources/SignalUIRenderCore/Mappers/CollectionMappers.swift")
        let tables = try packageSource("Sources/SignalUIRenderCore/Mappers/TableMappers.swift")
        let labels = try packageSource("Sources/SignalUIRenderCore/Mappers/LabelImageMappers.swift")
        let textViewBridge = try packageSource("Sources/SignalUIRenderCore/Mappers/TextViewEntryBridge.swift")
        let quillUIKit = try packageSource("Sources/QuillUIKit/QuillUIKit.swift")
        let collectionExtras = try packageSource("Sources/QuillUIKit/UICollectionViewExtras.swift")
        let stackView = try packageSource("Sources/QuillUIKit/UIStackView.swift")
        let uiKitShim = try packageSource("Sources/UIKitShim/UIKit.swift")

        #expect(quillUIKit.contains("quillViewMutationHandler"))
        #expect(quillUIKit.contains("quillNotifyViewMutation()"))
        #expect(quillUIKit.contains("quillAppendViewMutationHandler"))
        #expect(quillUIKit.contains("quillSetViewMutationHandler"))
        #expect(quillUIKit.contains("quillSubviewMutationHandler"))
        #expect(quillUIKit.contains("quillNotifySubviewMutation()"))
        #expect(quillUIKit.contains("quillAppendSubviewMutationHandler"))
        #expect(quillUIKit.contains("quillSetSubviewMutationHandler"))
        #expect(quillUIKit.contains("quillNotifyTextMutation"))
        #expect(uiKitShim.contains("quillNotifyTextViewMutation"))
        #expect(quillUIKit.contains("quillHorizontalContentHuggingPriority"))
        #expect(quillUIKit.contains("contentCompressionResistancePriority(for axis: NSLayoutConstraint.Axis)"))
        #expect(quillUIKit.contains("oldSuperview?.quillNotifySubviewMutation()"))
        #expect(stackView.contains("quillNotifyStackConfigurationMutation"))
        #expect(stackView.contains("_arrangedSubviews.append(view)"))
        #expect(stackView.contains("quillNotifySubviewMutation()"))
        #expect(renderer.contains("installMutationBridge(widget, view)"))
        #expect(renderer.contains("signalColorOrGradientRules(for: view)"))
        #expect(renderer.contains("reflectedSignalColorOrGradientValue(from: view)"))
        #expect(renderer.contains("String(describing: type(of: view)) == \"CVColorOrGradientView\""))
        #expect(renderer.contains("case .solidColor(let color)"))
        #expect(renderer.contains("case .gradient(let color1, let color2, let angleRadians)"))
        #expect(renderer.contains("parseSignalColorOrGradientValue(child.value)"))
        #expect(renderer.contains("firstMirroredCGFloat(labeled: \"angleRadians\", in: caseChild.value)"))
        #expect(renderer.contains("view.quillSetViewMutationHandler(\"SignalUIRender.widgetState\")"))
        #expect(renderer.contains("gtk_widget_set_visible(widget, updatedView.isHidden ? 0 : 1)"))
        #expect(renderer.contains("gtk_widget_set_opacity(widget, gdouble(max(0, min(1, updatedView.alpha))))"))
        #expect(renderer.contains("updatedView.isUserInteractionEnabled && control.isEnabled"))
        #expect(renderer.contains("gtk_widget_set_size_request("))
        #expect(renderer.contains("static func gtkSizeRequestValue(_ value: CGFloat) -> gint"))
        #expect(renderer.contains("static func gtkCoordinateValue(_ value: CGFloat) -> gdouble"))
        #expect(renderer.contains("view.quillNotifyViewMutation()"))
        #expect(containers.contains("UIKitGtkRenderer.gtkCoordinateValue(frame.origin.x)"))
        #expect(containers.contains("UIKitGtkRenderer.gtkSizeRequestValue(frame.width)"))
        #expect(containers.contains("installStackMutationBridge(on: box, stack: stack, ctx: ctx)"))
        #expect(containers.contains("stack.quillSetSubviewMutationHandler(\"SignalUIRender.stackChildren\")"))
        #expect(containers.contains("shouldHonorArrangedSubviewFixedFrame(child)"))
        #expect(containers.contains("!crossFills"))
        #expect(containers.contains("child is UILabel"))
        #expect(containers.contains("shouldExpandAlongMainAxis(child, isVertical: isVertical)"))
        #expect(containers.contains("contentHuggingPriority(for: axis).rawValue"))
        #expect(containers.contains("shouldForceMainAxisExpansion(child)"))
        #expect(containers.contains("child.accessibilityIdentifier == \"qspacer\""))
        #expect(containers.contains("child.accessibilityIdentifier == \"qclass:qfield\""))
        #expect(containers.contains("gtk_widget_set_hexpand(childWidget, 0)"))
        #expect(containers.contains("shouldUseFixedLayout(for: view, subviews: subviews)"))
        #expect(containers.contains("parentHasExplicitSize"))
        #expect(containers.contains("installGenericFixedMutationBridge(on: fixed, view: view, ctx: ctx)"))
        #expect(containers.contains("view.quillSetSubviewMutationHandler(\"SignalUIRender.genericFixedChildren\")"))
        #expect(containers.contains("centeredBadgeChildFrame(child.frame, child: child, parent: view)"))
        #expect(containers.contains("parent.layer.cornerRadius > 0"))
        #expect(containers.contains("clearFixedChildren(fixed)"))
        #expect(containers.contains("gtk_fixed_remove(fixedPtr, child)"))
        #expect(containers.contains("installGenericBoxMutationBridge(on: box, view: view, isBadge: isBadge, ctx: ctx)"))
        #expect(containers.contains("view.quillSetSubviewMutationHandler(\"SignalUIRender.genericBoxChildren\")"))
        #expect(containers.contains("clearBoxChildren(box)"))
        #expect(collections.contains("installCollectionMutationBridge(on: stack, collectionView: collectionView, ctx: ctx)"))
        #expect(collectionExtras.contains("open func invalidateLayout()"))
        #expect(collectionExtras.contains("quillScheduleReloadAfterLayoutInvalidation()"))
        #expect(collectionExtras.contains("hasScheduledReloadAfterLayoutInvalidation"))
        #expect(collectionExtras.contains("Task { @MainActor [weak self] in"))
        #expect(collections.contains("UIKitGtkRenderer.gtkSizeRequestValue(frame.width)"))
        #expect(collections.contains("collectionView.quillSetSubviewMutationHandler(\"SignalUIRender.collectionChildren\")"))
        #expect(collections.contains("appendCollectionChildren(to: stack, collectionView: updatedCollectionView, ctx: ctx)"))
        #expect(collections.contains("clearCollectionBoxChildren(stack)"))
        #expect(collectionExtras.contains("func quillReloadDataAndNotify()"))
        #expect(collectionExtras.contains("QuillUIKitMutationNotifications.withoutNotifications"))
        #expect(collectionExtras.contains("quillNotifySubviewMutation()"))
        #expect(collectionExtras.contains("quillPrefetchedLayoutAttributesByIndexPath()"))
        #expect(collectionExtras.contains("layoutAttributesForElements(in: scanRect)"))
        #expect(collectionExtras.contains("prefetchedAttributes.isEmpty"))
        #expect(tables.contains("prepareCellGeometry(cell, in: tv, at: indexPath, width: rowContentWidth)"))
        #expect(tables.contains("cell.contentView.frame = cell.bounds"))
        #expect(tables.contains("delegate.tableView(tableView, heightForRowAt: indexPath)"))
        #expect(tables.contains("let cardInsets = CGFloat(cardHorizontalMargin * 2)"))
        #expect(labels.contains("installLabelMutationBridge(widget, label: label)"))
        #expect(labels.contains("UIKitGtkRenderer.gtkSizeRequestValue(size.width)"))
        #expect(labels.contains("gtk_label_set_single_line_mode(labelPtr, 1)"))
        #expect(labels.contains("gtk_label_set_ellipsize(labelPtr, PANGO_ELLIPSIZE_END)"))
        #expect(labels.contains("label.quillSetViewMutationHandler(\"SignalUIRender.labelContent\")"))
        #expect(labels.contains("installTextViewLabelMutationBridge(widget, textView: textView)"))
        #expect(labels.contains("installEditableTextViewMutationBridge(widget, textView: textView)"))
        #expect(labels.contains("textView.quillSetViewMutationHandler(\"SignalUIRender.textViewEntryContent\")"))
        #expect(textViewBridge.contains("quillSignalTextViewEntryGetText"))
    }

    @Test("Qt manifest avoids pkg-config prohibited flag warnings")
    func qtManifestAvoidsPkgConfigProhibitedFlagWarnings() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let qtCarrierHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/CQt6Widgets/shim.h"),
            encoding: .utf8
        )

        #expect(manifest.contains("func pkgConfigArguments("))
        #expect(manifest.contains("func pkgConfigIncludeFlags("))
        #expect(manifest.contains("func pkgConfigSwiftImporterFlags("))
        #expect(manifest.contains("func pkgConfigLinkerFlags("))
        #expect(manifest.contains("let qt6WidgetsIncludeFlags: [String] = pkgConfigIncludeFlags(\"Qt6Widgets\")"))
        #expect(manifest.contains("let qt6WidgetsLinkerFlags: [String] = pkgConfigLinkerFlags(\"Qt6Widgets\")"))
        #expect(manifest.contains("let qt6WidgetsCxxFlags: [String] = qt6WidgetsIncludeFlags + [\"-std=c++17\", \"-fPIC\", \"-Wno-deprecated-literal-operator\"]"))
        #expect(manifest.contains("name: \"CQt6Widgets\""))
        #expect(manifest.occurrences(of: "name: \"CQt6Widgets\"") == 1)
        #expect(manifest.occurrences(of: "name: \"CQuillQt6WidgetsShim\"") == 1)
        #expect(manifest.occurrences(of: "name: \"QuillWireGuardQtNativeRuntime\"") == 1)
        #expect(!manifest.contains("pkgConfig: \"Qt6Widgets\""))
        #expect(manifest.contains(".unsafeFlags(qt6WidgetsCxxFlags)"))
        #expect(manifest.contains(".unsafeFlags(qt6WidgetsLinkerFlags)"))
        #expect(manifest.contains("#if !os(Linux)\nproducts.append(.executable(name: \"quill-wireguard-qt\", targets: [\"QuillWireGuardQt\"]))"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .gtk {\n    products.append(.executable(name: \"quill-gtk-interaction-smoke\", targets: [\"QuillGtkInteractionSmoke\"]))"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .gtk && signalUpstreamPresent && libsignalUpstreamPresent {"))
        #expect(manifest.contains("products.append(.executable(name: \"signal-ui-render\", targets: [\"SignalUIRender\"]))"))
        #expect(manifest.contains("let quillLegacyMainActorConcurrencySettings: [SwiftSetting] =\n    quillMinimalConcurrencyMainActorSwiftSettings"))
        #expect(manifest.contains("let quillLegacyMainActorSwiftSettings: [SwiftSetting] = [\n    .swiftLanguageMode(.v5)\n] + quillLegacyMainActorConcurrencySettings"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .qt {"))
        #expect(manifest.contains("enum QuillCanonicalLinuxAppQtRuntime"))
        #expect(manifest.contains("struct QuillCanonicalLinuxAppSpec"))
        #expect(manifest.contains("let quillCanonicalLinuxApps: [QuillCanonicalLinuxAppSpec] = ["))
        #expect(manifest.contains("let quillCanonicalLinuxAppProducts: [Product] = quillCanonicalLinuxApps.map(\\.productDeclaration)"))
        #expect(manifest.contains("] + quillCanonicalLinuxAppProducts"))
        #expect(manifest.contains("products += ["))
        #expect(manifest.contains("products = quillCanonicalLinuxAppProducts + ["))
        #expect(manifest.contains(".library(name: \"UniformTypeIdentifiers\", targets: [\"UniformTypeIdentifiers\"]),\n            .library(name: \"CoreTransferable\", targets: [\"CoreTransferable\"]),"))
        #expect(manifest.contains(".library(name: \"QuillGenericQtNativeRuntime\", targets: [\"QuillGenericQtNativeRuntime\"])"))
        #expect(manifest.contains(".executable(name: \"quill-qt-interaction-smoke\", targets: [\"QuillQtInteractionSmoke\"])"))
        #expect(manifest.contains("func quillCanonicalLinuxAppQtTarget(_ app: QuillCanonicalLinuxAppSpec) -> Target"))
        #expect(manifest.contains("dependencies: [app.qtRuntime.targetDependency]"))
        #expect(manifest.contains("path: app.qtPath"))
        #expect(manifest.contains("let quillGenericQtSwiftSettings: [SwiftSetting] ="))
        #expect(manifest.contains(".define(\"QUILLUI_GENERIC_QT_NATIVE_BACKEND\")"))
        #expect(manifest.contains("swiftSettings = quillGenericQtSwiftSettings"))
        #expect(manifest.contains("] + quillCanonicalLinuxApps.map(quillCanonicalLinuxAppQtTarget)"))
        #expect(manifest.contains("qtRuntime: .genericQtNative"))
        #expect(manifest.contains("qtRuntime: .wireGuardQtNative"))
        // `var` (not `let`): SwiftProtobuf/swift-crypto are appended only when the
        // Signal upstream is present (Track B), so non-Signal builds don't get an
        // unused-dependency warning. See Package.swift `if signalUpstreamPresent`.
        #expect(manifest.contains("var quillDataPackageDependencies: [Package.Dependency] = ["))
        #expect(manifest.contains("cSQLiteTarget,\n        cCairoTarget,\n        quillDataMacroTarget,\n        quillDataTarget,"))
        #expect(manifest.contains("name: \"QuillFoundation\",\n            dependencies: quillFoundationDependencies,\n            path: \"Sources/QuillFoundation\",\n            swiftSettings: quillFoundationSwiftSettings"))
        #expect(manifest.contains("name: \"AppKit\",\n            dependencies: appKitShadowDependencies,\n            path: \"Sources/QuillAppKit\",\n            swiftSettings: [\n                .swiftLanguageMode(.v5),\n                .unsafeFlags([\"-strict-concurrency=minimal\"]),\n                .unsafeFlags(gdkPixbufSwiftImporterFlags)"))
        #expect(manifest.contains("name: \"UniformTypeIdentifiers\",\n            dependencies: [],\n            path: \"Sources/UniformTypeIdentifiersShim\""))
        #expect(manifest.contains("name: \"CoreTransferable\",\n            dependencies: [\"UniformTypeIdentifiers\"],\n            path: \"Sources/CoreTransferable\""))
        #expect(manifest.contains("name: \"QuillEnchantedShared\""))
        #expect(manifest.contains("path: \"Sources/QuillEnchantedShared\""))
        #expect(manifest.contains("quillEnchantedDataTarget,"))
        #expect(manifest.contains("name: \"QuillQtNativeRuntimeSupport\""))
        #expect(manifest.contains("path: \"Sources/QuillQtNativeRuntimeSupport\""))
        #expect(manifest.contains(".library(name: \"QuillGenericQtNativeRuntime\", targets: [\"QuillGenericQtNativeRuntime\"])"))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(manifest.contains("dependencies: [\"QuillWireGuardCore\", \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(manifest.contains("name: \"QuillGenericQtNativeRuntime\""))
        #expect(manifest.contains("path: \"Sources/QuillGenericQtNativeRuntime\""))
        #expect(manifest.contains("qtPath: \"Sources/QuillSignalQt\""))
        #expect(manifest.contains("qtPath: \"Sources/QuillWireGuardQt\""))
        #expect(manifest.contains("AppDelegate/Application remain intentionally deferred"))
        #expect(!manifest.contains("\"Sources/WireGuardApp/UI/macOS/AppDelegate.swift\""))
        #expect(!manifest.contains("\"Sources/WireGuardApp/UI/macOS/Application.swift\""))
        #expect(manifest.contains("let quillLinuxShimTestDependencies: [Target.Dependency] = ["))
        #expect(manifest.contains("let quillLinuxCompatibilityModuleTestDependencies: [Target.Dependency] = ["))
        #expect(manifest.contains("let testDeps: [Target.Dependency] = quillLinuxShimTestDependencies"))
        #expect(manifest.contains("name: \"QuillCompatibilityModuleTests\""))
        #expect(manifest.contains("dependencies: quillLinuxCompatibilityModuleTestDependencies"))
        #expect(!manifest.contains("products = [\n        .executable(name: \"quill-enchanted-qt\""))
        #expect(manifest.contains("allPackageDependencies = quillDataPackageDependencies"))
        #expect(manifest.contains("let packageTestTargets: [Target] = {"))
        #expect(manifest.contains("name: \"QuillQtBackendManifestTests\""))
        #expect(manifest.contains("targets: targets + packageTestTargets"))
        #expect(!manifest.contains("dependencies: quillQtInteractionSmokeDependencies"))
        #expect(qtCarrierHeader.contains("Linker carrier for Qt6 Widgets"))
        #expect(!qtCarrierHeader.contains("Pkg-config and linker carrier"))
    }

    @Test("SwiftUI Linux source lowering runs reusable Objective-C and shorthand cleanup")
    func swiftUILinuxSourceLoweringRunsReusableObjectiveCAndShorthandCleanup() throws {
        let manifest = try packageSource("Package.swift")
        let lowering = try packageSource("scripts/lower-swiftui-source-for-linux.sh")
        let objcLowering = try packageSource("scripts/lower-objc-interop-for-linux.sh")
        let preparedPackageDependencyScript = try packageSource("scripts/prepare-swiftui-linux-package-dependencies.py")
        let sourceLoweringRunner = try packageSource("scripts/run-quill-source-lower.sh")
        let swiftUILoweringRunner = try packageSource("scripts/run-quill-swiftui-lower.sh")
        let appKitLoweringRunner = try packageSource("scripts/run-quill-appkit-lower.sh")
        let mainActorAssignmentLowering = try packageSource("scripts/lower-mainactor-assignments-for-linux.py")
        let linuxConditionalLowering = try packageSource("scripts/lower-linux-conditional-compilation.py")
        let quillData = try packageSource("Sources/QuillData/QuillData.swift")
        let swiftUICompatibility = try packageSource("Sources/QuillSwiftUICompatibility/QuillSwiftUICompatibility.swift")
        let observation = try packageSource("Sources/Observation/Observation.swift")
        let foundationModels = try packageSource("Sources/FoundationModels/FoundationModels.swift")
        let mainActorAssignmentLoweringCall = "python3 \"$(dirname \"$0\")/lower-mainactor-assignments-for-linux.py\" \"$SOURCE_DIR\""
        let linuxConditionalLoweringCall = "python3 \"$(dirname \"$0\")/lower-linux-conditional-compilation.py\" \"$SOURCE_DIR\""
        let appKitLoweringCall = "\"$(dirname \"$0\")/run-quill-appkit-lower.sh\" \"$SOURCE_DIR\""
        let objcLoweringCall = "\"$(dirname \"$0\")/lower-objc-interop-for-linux.sh\" \"$SOURCE_DIR\""
        let signalUILowering = try packageSource("scripts/quill-signal-lower-ui.sh")
        let compatibilityModule = try packageSource("Sources/QuillSwiftUICompatibility/DesignSystemSurfaceCompat.swift")

        // No keyboardType(.URL) rewrite. The shim exposes a single canonical
        // keyboardType(_ type: UIKeyboardType), so upstream `.keyboardType(.URL)`
        // resolves to UIKeyboardType.URL by inference — the lowering must NOT
        // requalify it to the removed DSSC `KeyboardType.URL`. (textContentType,
        // whose TextContentType type still exists, is still rewritten below.)
        #expect(!lowering.contains(".keyboardType(KeyboardType.URL)"))
        #expect(manifest.contains("QUILLUI_RUNTIME_ONLY_MACROS"))
        #expect(manifest.contains("let quillDataMacroDependencies: [Target.Dependency] = quillUIRuntimeOnlyMacros ? [] : [\"QuillDataMacros\"]"))
        #expect(manifest.contains("let quillSwiftUICompatibilityMacroDependencies: [Target.Dependency] = quillUIRuntimeOnlyMacros ? [] : [\"QuillDataMacros\"]"))
        #expect(manifest.contains("let quillObservationMacroDependencies: [Target.Dependency] = quillUIRuntimeOnlyMacros ? [] : [\"QuillDataMacros\"]"))
        #expect(manifest.contains("let quillFoundationModelsMacroDependencies: [Target.Dependency] = quillUIRuntimeOnlyMacros ? [] : [\"QuillDataMacros\"]"))
        #expect(quillData.contains("#if !QUILLDATA_NO_MACROS"))
        #expect(swiftUICompatibility.contains("#if !QUILLUI_NO_COMPAT_MACROS"))
        #expect(observation.contains("#if !QUILLUI_NO_OBSERVATION_MACROS"))
        #expect(foundationModels.contains("#if !QUILLUI_NO_FOUNDATION_MODELS_MACROS"))
        #expect(lowering.contains("import[ \\t]+Carbon\\.[A-Za-z0-9_]+"))
        #expect(lowering.contains("@preconcurrency import $2"))
        #expect(lowering.contains("s/\\.textContentType\\([ \\t]*\\.URL[ \\t]*\\)/.textContentType(TextContentType.URL)/g;"))
        #expect(lowering.contains("NSMutableAttributedString(string: \"\")"))
        #expect(lowering.contains("NSAttributedString(string: \"\")"))
        #expect(lowering.contains("Corners\\.RawValue"))
        #expect(lowering.contains("s/\\.selectedRange\\(\\)/.selectedRange/g;"))
        #expect(lowering.contains("Swift.abs($1)"))
        #expect(lowering.contains("as\\?[ \\t]+NSURL"))
        #expect(lowering.contains("let $5 = $3.absoluteString"))
        #expect(lowering.contains("DispatchQueue\\.dispatchMainIfNot[ \\t]*\\{/Task { \\@MainActor in"))
        #expect(lowering.contains("Task { \\@MainActor in completion(.success(result)) }"))
        #expect(lowering.contains("CGFloat($2)"))
        #expect(lowering.contains("NSImage.SymbolConfiguration"))
        #expect(lowering.contains(#"(?:pointSize|weight|scale|textStyle|paletteColors)"#))
        #expect(!lowering.contains(#"s/(\.applying\(\s*)\.init\(/$1NSImage.SymbolConfiguration(/g;"#))
        #expect(lowering.contains("TextViewController\\b"))
        #expect(lowering.contains("@MainActor[ \\t]*\\n\\1\\@MainActor"))
        #expect(lowering.contains("*ViewModel[ \\t]*:[^\\n{]*\\bObservableObject\\b"))
        #expect(lowering.contains("@Sendable () -> Void"))
        #expect(lowering.contains("nonisolated(unsafe)"))
        #expect(!lowering.contains("(?!public[ \\t]+static[ \\t]+func[ \\t]+buildBlock\\b)"))
        #expect(lowering.contains("(class[[:space:]]+)?AppKit"))
        #expect(lowering.contains("NSTextStorage(?![A-Za-z0-9_])/AppKit.NSTextStorage"))
        #expect(lowering.contains("@Invalidating"))
        #expect(lowering.contains("SwiftTreeSitter.Node"))
        #expect(lowering.contains("(?=public[ \\t]+(?:protocol|class|struct|enum|actor|extension|func|var|let|typealias)\\b)"))
        #expect(lowering.contains("! -name 'Package.swift'"))
        #expect(lowering.contains(mainActorAssignmentLoweringCall))
        #expect(lowering.contains(linuxConditionalLoweringCall))
        #expect(mainActorAssignmentLowering.contains("MainActor.assumeIsolated"))
        #expect(linuxConditionalLowering.contains("evaluate_platform_expression"))
        #expect(linuxConditionalLowering.contains("match.group(1) == \"Linux\""))
        #expect(linuxConditionalLowering.contains("targetEnvironment"))
        #expect(mainActorAssignmentLowering.contains("NSWindowController"))
        #expect(mainActorAssignmentLowering.contains("controller."))
        #expect(lowering.contains(appKitLoweringCall))
        #expect(lowering.contains(objcLoweringCall))
        #expect((lowering.range(of: mainActorAssignmentLoweringCall)?.lowerBound ?? lowering.endIndex) < (lowering.range(of: appKitLoweringCall)?.lowerBound ?? lowering.startIndex))
        #expect((lowering.range(of: mainActorAssignmentLoweringCall)?.lowerBound ?? lowering.endIndex) < (lowering.range(of: linuxConditionalLoweringCall)?.lowerBound ?? lowering.startIndex))
        #expect((lowering.range(of: linuxConditionalLoweringCall)?.lowerBound ?? lowering.endIndex) < (lowering.range(of: appKitLoweringCall)?.lowerBound ?? lowering.startIndex))
        #expect((lowering.range(of: appKitLoweringCall)?.lowerBound ?? lowering.endIndex) < (lowering.range(of: objcLoweringCall)?.lowerBound ?? lowering.startIndex))
        #expect(objcLowering.contains("lower_foundation_bridge_casts"))
        #expect(objcLowering.contains("for cf_type in (\"CFDictionary\", \"CFString\", \"CFURL\", \"CFData\", \"CFMutableData\", \"CFArray\")"))
        #expect(objcLowering.contains("lowered = re.sub(rf\"\\bnil\\s+as\\s+{cf_type}\\?\", \"nil\", lowered)"))
        #expect(objcLowering.contains("lowered = lowered.replace(f\" as {cf_type}\", \"\")"))
        #expect(preparedPackageDependencyScript.contains("\"Cocoa\""))
        #expect(preparedPackageDependencyScript.contains("\"CoreSpotlight\""))
        #expect(preparedPackageDependencyScript.contains("\"ExtensionFoundation\""))
        #expect(preparedPackageDependencyScript.contains("\"ExtensionKit\""))
        #expect(preparedPackageDependencyScript.contains("\"AuthenticationServices\""))
        #expect(preparedPackageDependencyScript.contains("PREPARED_SWIFT_SETTINGS"))
        #expect(preparedPackageDependencyScript.contains("PREPARED_FINGERPRINT_FILE"))
        #expect(preparedPackageDependencyScript.contains("--prepared-cache-dir"))
        #expect(preparedPackageDependencyScript.contains("def prepared_package_directory("))
        #expect(preparedPackageDependencyScript.contains("reused prepared local SwiftPM dependency"))
        #expect(preparedPackageDependencyScript.contains("VENDORED_PACKAGE_ALIASES"))
        #expect(preparedPackageDependencyScript.contains("package_declares_quill_products_for_imports"))
        #expect(preparedPackageDependencyScript.contains("is_quillui_root_dependency"))
        #expect(preparedPackageDependencyScript.contains("update_digest_with_file_contents"))
        #expect(preparedPackageDependencyScript.contains("update_digest_with_tool_input"))
        #expect(preparedPackageDependencyScript.contains("read_bytes()"))
        #expect(preparedPackageDependencyScript.contains("update_digest_with_file_contents(digest, path, package_dir)"))
        #expect(!preparedPackageDependencyScript.contains("st_mtime_ns"))
        #expect(preparedPackageDependencyScript.contains("scripts/lower-observable-for-swiftopenui.py"))
        #expect(preparedPackageDependencyScript.contains("scripts/ensure-swift-imports.sh"))
        #expect(preparedPackageDependencyScript.contains("scripts/lower-mainactor-assignments-for-linux.py"))
        #expect(preparedPackageDependencyScript.contains("scripts/lower-linux-conditional-compilation.py"))
        #expect(preparedPackageDependencyScript.contains("scripts/lower-extension-overrides-for-linux.py"))
        #expect(preparedPackageDependencyScript.contains("Sources/QuillSourceLowering"))
        #expect(preparedPackageDependencyScript.contains(#""swift-async-algorithms": ["AsyncAlgorithms"]"#))
        #expect(preparedPackageDependencyScript.contains("normalized_package_component"))
        #expect(preparedPackageDependencyScript.contains(#".swiftLanguageMode(.v5)"#))
        #expect(preparedPackageDependencyScript.contains(#".unsafeFlags(["-strict-concurrency=minimal"])"#))
        #expect(!preparedPackageDependencyScript.contains(#".unsafeFlags(["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"])"#))
        #expect(preparedPackageDependencyScript.contains("SWIFT_TOOLS_VERSION_RE"))
        #expect(preparedPackageDependencyScript.contains("def patch_manifest_tools_version(manifest: str) -> str:"))
        #expect(preparedPackageDependencyScript.contains("manifest = patch_manifest_tools_version(manifest)"))
        #expect(preparedPackageDependencyScript.contains("patch_target_swift_settings"))
        #expect(signalUILowering.contains("Sources/SignalUIObjCPort"))
        #expect(signalUILowering.contains("QuillPort"))
        #expect(sourceLoweringRunner.contains("third_party/swift-syntax/Package.swift"))
        #expect(sourceLoweringRunner.contains(#".package(name: \"swift-syntax\", path: \"$ROOT_DIR/third_party/swift-syntax\")"#))
        #expect(swiftUILoweringRunner.contains("third_party/swift-syntax/Package.swift"))
        #expect(swiftUILoweringRunner.contains(#".package(name: \"swift-syntax\", path: \"$ROOT_DIR/third_party/swift-syntax\")"#))
        #expect(swiftUILoweringRunner.contains("TOOL_CACHE_KEY=\"$(printf '%s' \"$ROOT_DIR\" | cksum | awk '{print $1}')\""))
        #expect(swiftUILoweringRunner.contains(".build/quill-swiftui-lower-package-$TOOL_CACHE_KEY"))
        #expect(swiftUILoweringRunner.contains(".build/quill-swiftui-lower-tool-$TOOL_CACHE_KEY"))
        #expect(appKitLoweringRunner.contains("third_party/swift-syntax/Package.swift"))
        #expect(appKitLoweringRunner.contains(#".package(name: \"swift-syntax\", path: \"$ROOT_DIR/third_party/swift-syntax\")"#))
        #expect(appKitLoweringRunner.contains("TOOL_CACHE_KEY=\"$(printf '%s' \"$ROOT_DIR\" | cksum | awk '{print $1}')\""))
        #expect(appKitLoweringRunner.contains(".build/quill-appkit-lower-package-$TOOL_CACHE_KEY"))
        #expect(appKitLoweringRunner.contains(".build/quill-appkit-lower-tool-$TOOL_CACHE_KEY"))

        let viewBuilder = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/ViewBuilder.swift")
        #expect(viewBuilder.contains("public static func buildBlock<each Content: View>(_ content: repeat each Content) -> ViewList"))
        #expect(viewBuilder.contains("repeat children.append(contentsOf: childViews(from: each content))"))

        let viewThatFitsBuilder = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/ViewThatFits.swift")
        #expect(viewThatFitsBuilder.contains("public init<Content: View>(@ViewBuilder content: () -> Content)"))
        #expect(viewThatFitsBuilder.contains("Self.flatten(content()).map { AnyView(erasing: $0) }"))
        #expect(viewThatFitsBuilder.contains("public init(children: [AnyView])"))
        #expect(viewThatFitsBuilder.contains("if let multi = view as? any TransparentMultiChildView"))
        #expect(viewThatFitsBuilder.contains("New ViewThatFits call sites use standard ViewBuilder lowering."))
        #expect(viewThatFitsBuilder.contains("public static func buildPartialBlock(first component: [AnyView]) -> [AnyView]"))
        #expect(viewThatFitsBuilder.contains("public static func buildPartialBlock(accumulated: [AnyView], next: [AnyView]) -> [AnyView]"))

        let anyView = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/AnyView.swift")
        #expect(anyView.contains("public init(erasing view: any View)"))
        #expect(compatibilityModule.contains("self.init(children: content())"))

        let actionsBuilder = try packageSource("third_party/WelcomeWindow/Sources/WelcomeWindow/Model/ActionsBuilder.swift")
        #expect(actionsBuilder.contains("@MainActor public static func buildBlock<V1: View>(_ view1: V1) -> WelcomeActions"))
        #expect(actionsBuilder.contains("@MainActor public static func buildBlock<V1: View, V2: View>(_ view1: V1, _ view2: V2) -> WelcomeActions"))
        #expect(actionsBuilder.contains("@MainActor public static func buildBlock<V1: View, V2: View, V3: View>"))
    }

    @Test("Objective-C interop lowering removes CoreFoundation bridge casts without nil question marks")
    func objectiveCInteropLoweringRemovesCoreFoundationBridgeCastsWithoutNilQuestionMarks() throws {
        let root = try packageRoot()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillui-objc-lowering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("BridgeCasts.swift")
        try """
        import ImageIO

        let optionalOptions = nil as CFDictionary?
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 200,
        ] as [CFString: Any] as CFDictionary
        let metadataKeys: [CFString] = ["tiff:Orientation" as CFString]
        let source = CGImageSourceCreateWithData(Data() as CFData, nil)
        let destination = CGImageDestinationCreateWithData(NSMutableData() as CFMutableData, "public.png" as CFString, 1, nil)
        let urlSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: "/tmp/a.png") as CFURL, nil)
        let maybeName = "example" as CFString?
        let maybeNilName = nil as CFString?
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["bash", root.appendingPathComponent("scripts/lower-objc-interop-for-linux.sh").path, temporaryDirectory.path]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))

        let lowered = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(lowered.contains("let optionalOptions = nil"))
        #expect(lowered.contains("let options = [kCGImageSourceShouldCache: false]"))
        #expect(lowered.contains("] as [String: Any]"))
        #expect(lowered.contains("let metadataKeys: [String] = [\"tiff:Orientation\"]"))
        #expect(lowered.contains("CGImageSourceCreateWithData(Data(), nil)"))
        #expect(lowered.contains("CGImageDestinationCreateWithData(NSMutableData(), \"public.png\", 1, nil)"))
        #expect(lowered.contains("CGImageSourceCreateWithURL(URL(fileURLWithPath: \"/tmp/a.png\"), nil)"))
        #expect(lowered.contains("let maybeName = \"example\""))
        #expect(lowered.contains("let maybeNilName = nil"))
        #expect(!lowered.contains("nil?"))
    }

    @Test("GTK manifest filters pkg-config prohibited flag warnings")
    func gtkManifestFiltersPkgConfigProhibitedFlagWarnings() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let swiftOpenUIManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Package.swift"),
            encoding: .utf8
        )
        let swiftOpenUIPatcher = try String(
            contentsOf: root.appendingPathComponent("scripts/patch-swiftopenui-gtk-css.sh"),
            encoding: .utf8
        )
        let gtkModuleMap = try String(
            contentsOf: root.appendingPathComponent("Sources/CGtk4/module.modulemap"),
            encoding: .utf8
        )
        let gdkPixbufModuleMap = try String(
            contentsOf: root.appendingPathComponent("Sources/CGdkPixbuf/module.modulemap"),
            encoding: .utf8
        )

        #expect(manifest.contains("let gdkPixbufSwiftImporterFlags: [String] = pkgConfigSwiftImporterFlags(\"gdk-pixbuf-2.0\")"))
        #expect(manifest.contains("let gdkPixbufLinkerFlags: [String] = pkgConfigLinkerFlags(\"gdk-pixbuf-2.0\")"))
        #expect(manifest.contains("let gtk4SwiftImporterFlags: [String] = pkgConfigSwiftImporterFlags(\"gtk4\")"))
        #expect(manifest.contains("let gtk4LinkerFlags: [String] = pkgConfigLinkerFlags(\"gtk4\")"))
        #expect(manifest.contains("let quillUIGTKSwiftImporterSettings: [SwiftSetting] = quillUILinuxBuildBackend == .gtk ? ["))
        #expect(manifest.contains("let quillUIGTKLinkerSettings: [LinkerSetting] = quillUILinuxBuildBackend == .gtk ? ["))
        #expect(!manifest.contains("pkgConfig: \"gdk-pixbuf-2.0\""))
        #expect(!manifest.contains("pkgConfig: \"gtk4\""))
        #expect(manifest.contains("] + quillUIGTKSwiftImporterSettings"))
        #expect(manifest.contains("dependencies: quillUIDependencies,\n        swiftSettings: quillUIGTKSwiftImporterSettings,\n        linkerSettings: quillUIGTKLinkerSettings"))
        #expect(manifest.contains(".unsafeFlags(gtk4SwiftImporterFlags)"))
        #expect(manifest.contains(".unsafeFlags(gtk4LinkerFlags)"))
        #expect(swiftOpenUIManifest.contains("let swiftOpenUIGTKSwiftImporterFlags: [String] = swiftOpenUIPkgConfigSwiftImporterFlags(\"gtk4\")"))
        #expect(swiftOpenUIManifest.contains("let swiftOpenUIGTKLinkerFlags: [String] = swiftOpenUIPkgConfigLinkerFlags(\"gtk4\")"))
        #expect(swiftOpenUIManifest.contains(".unsafeFlags(swiftOpenUIGTKSwiftImporterFlags)"))
        #expect(swiftOpenUIManifest.contains(".unsafeFlags(swiftOpenUIGTKLinkerFlags)"))
        #expect(!swiftOpenUIManifest.contains("pkgConfig: \"gtk4\""))
        #expect(swiftOpenUIPatcher.contains("pkgConfig removal did not apply"))
        #expect(!swiftOpenUIPatcher.contains("pkgConfig patch did not apply"))
        #expect(gdkPixbufModuleMap.contains("module CGdkPixbuf [system]"))
        #expect(gtkModuleMap.contains("module CGtk4 [system]"))
    }

    @Test("IceCubes Env target keeps UIKit shim dependency")
    func iceCubesEnvTargetKeepsUIKitShimDependency() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(manifest.contains("Real Dimillian/IceCubesApp Env"))
        #expect(manifest.contains("Router → UIImage/UIApplication"))
        #expect(manifest.contains("""
                "KeychainSwift",
                "UIKit",
                "CryptoKit",
"""))
    }

    @Test("Linux SwiftUI compatibility exposes accessibility modifiers")
    func linuxSwiftUICompatibilityExposesAccessibilityModifiers() throws {
        let compatibility = try packageSource("Sources/QuillUI/UpstreamCompatibility.swift")
        let desktopInteraction = try packageSource("Sources/QuillSwiftUICompatibility/DesktopInteractionCompat.swift")
        let designSystemCompatibility = try packageSource("Sources/QuillSwiftUICompatibility/DesignSystemSurfaceCompat.swift")
        let compatibilityModifiers = try packageSource("Sources/QuillSwiftUICompatibility/IceCubesDesignSystemModifiers.swift")
        let gtkAccessibility = try packageSource("Sources/QuillUI/GTKAccessibilityModifiers.swift")
        let gtkHover = try packageSource("Sources/QuillUI/GTKHoverModifiers.swift")
        let gtkHitTesting = try packageSource("Sources/QuillUI/GTKHitTestingModifiers.swift")
        let gtkTextSelection = try packageSource("Sources/QuillUI/GTKTextSelectionModifiers.swift")
        let qtBackend = try packageSource("Sources/BackendQt/QtBackend.swift")
        let qtRenderer = try packageSource("Sources/BackendQt/QtRenderer.swift")
        let cqtHeader = try packageSource("Sources/CQtBridge/include/CQtBridge.h")
        let cqtBridge = try packageSource("Sources/CQtBridge/CQtBridge.cpp")
        let gtkPatchScript = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(!compatibility.contains("public struct AccessibilityChildBehavior: Hashable, Sendable"))
        #expect(designSystemCompatibility.contains("public struct AccessibilityChildBehavior: Hashable, Sendable"))
        #expect(designSystemCompatibility.contains("public static let combine = AccessibilityChildBehavior(\"combine\")"))
        #expect(desktopInteraction.contains("public struct AccessibilityLabelView<Content: View>: View"))
        #expect(desktopInteraction.contains("public struct AccessibilityValueView<Content: View>: View"))
        #expect(desktopInteraction.contains("public struct AccessibilityHintView<Content: View>: View"))
        #expect(desktopInteraction.contains("public struct AccessibilityElementView<Content: View>: View"))
        #expect(designSystemCompatibility.contains("func accessibilityLabel(_ label: String) -> AccessibilityLabelView<Self>"))
        #expect(designSystemCompatibility.contains("func accessibilityValue(_ value: String) -> AccessibilityValueView<Self>"))
        #expect(designSystemCompatibility.contains("func accessibilityHint(_ hint: String) -> AccessibilityHintView<Self>"))
        #expect(designSystemCompatibility.contains("func accessibilityElement(children: AccessibilityChildBehavior) -> AccessibilityElementView<Self>"))
        #expect(!designSystemCompatibility.contains("func accessibilityLabel(_ label: String) -> Self"))
        #expect(!designSystemCompatibility.contains("func accessibilityValue(_ value: String) -> Self"))
        #expect(!designSystemCompatibility.contains("func accessibilityHint(_ hint: String) -> Self"))
        #expect(compatibility.contains("func accessibilityLabel(_ label: String) -> AccessibilityLabelView<Self>"))
        #expect(compatibility.contains("func accessibilityValue(_ value: String) -> AccessibilityValueView<Self>"))
        #expect(compatibility.contains("func accessibilityHint(_ hint: String) -> AccessibilityHintView<Self>"))
        #expect(compatibility.contains("func accessibilityElement(children: AccessibilityChildBehavior) -> AccessibilityElementView<Self>"))
        #expect(compatibility.contains("\"accessibilityLabel\""))
        #expect(compatibility.contains("\"accessibilityValue\""))
        #expect(compatibility.contains("\"accessibilityHint\""))
        #expect(compatibility.contains("\"accessibilityElement(children:)\""))
        #expect(compatibilityModifiers.contains("public struct QuillCompatibilityOnHoverView<Content: View>: View"))
        #expect(compatibilityModifiers.contains("func onHover(perform action: @escaping (Bool) -> Void) -> QuillCompatibilityOnHoverView<Self>"))
        #expect(compatibilityModifiers.contains("public struct QuillCompatibilityAllowsHitTestingView<Content: View>: View"))
        #expect(compatibilityModifiers.contains("func allowsHitTesting(_ enabled: Bool) -> QuillCompatibilityAllowsHitTestingView<Self>"))
        #expect(compatibilityModifiers.contains("public struct QuillCompatibilityContentShapeView<Content: View, ShapeValue: Shape>: View"))
        #expect(compatibilityModifiers.contains("func contentShape<S: Shape>(_ shape: S) -> QuillCompatibilityContentShapeView<Self, S>"))
        #expect(compatibilityModifiers.contains("public struct QuillCompatibilityTextSelectionView<Content: View>: View"))
        #expect(compatibilityModifiers.contains("func textSelection(_ selectability: TextSelectability) -> QuillCompatibilityTextSelectionView<Self>"))
        #expect(!compatibility.contains("View accessibility labels are currently a source-compatibility fallback on Linux."))
        #expect(!compatibility.contains("View accessibility values are currently a source-compatibility fallback on Linux."))
        #expect(gtkAccessibility.contains("extension AccessibilityLabelView: GTKRenderable"))
        #expect(gtkAccessibility.contains("extension AccessibilityValueView: GTKRenderable"))
        #expect(gtkAccessibility.contains("extension AccessibilityHintView: GTKRenderable"))
        #expect(gtkAccessibility.contains("gtk_swift_accessible_update_label"))
        #expect(gtkAccessibility.contains("gtk_swift_accessible_update_description"))
        #expect(gtkAccessibility.contains("extension AccessibilityIdentifierView: GTKRenderable"))
        #expect(gtkAccessibility.contains("gtk_widget_set_name(widget, identifierPointer)"))
        #expect(gtkHover.contains("extension OnHoverView: GTKRenderable"))
        #expect(gtkHover.contains("extension QuillCompatibilityOnHoverView: GTKRenderable"))
        #expect(gtkHover.contains("private func quillGTKCreateHoverWidget<Content: View>"))
        #expect(gtkHover.contains("let container = gtk_overlay_new()!"))
        #expect(gtkHover.contains("gtk_widget_set_hexpand(container, 1)"))
        #expect(gtkHover.contains("gtk_widget_set_halign(container, GTK_ALIGN_FILL)"))
        #expect(gtkHover.contains("gtk_widget_set_hexpand(widget, 1)"))
        #expect(gtkHover.contains("gtk_overlay_set_child(OpaquePointer(container), widget)"))
        #expect(gtkHover.contains("gtk_event_controller_motion_new"))
        #expect(gtkHover.contains("gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE)"))
        #expect(gtkHover.contains("quillGTKInstallHoverControllers(on: container, retainedBox: retainedBox)"))
        #expect(gtkHover.contains("gtk_widget_get_first_child(widget)"))
        #expect(gtkHover.contains("gtk_widget_get_next_sibling(current)"))
        #expect(gtkHover.contains("\"enter\""))
        #expect(gtkHover.contains("\"leave\""))
        #expect(gtkHover.contains("gtk_widget_add_controller(widget, controller)"))
        #expect(gtkHitTesting.contains("extension AllowsHitTestingView: GTKRenderable"))
        #expect(gtkHitTesting.contains("extension QuillCompatibilityAllowsHitTestingView: GTKRenderable"))
        #expect(gtkHitTesting.contains("extension ContentShapeView: GTKRenderable"))
        #expect(gtkHitTesting.contains("extension QuillCompatibilityContentShapeView: GTKRenderable"))
        #expect(gtkHitTesting.contains("private func quillGTKCreateContentShapeWidget<Content: View>(content: Content) -> OpaquePointer"))
        #expect(gtkHitTesting.contains("let container = gtk_overlay_new()!"))
        #expect(gtkHitTesting.contains("gtk_widget_set_can_target(container, 1)"))
        #expect(gtkHitTesting.contains("gtk_overlay_set_child(OpaquePointer(container), widget)"))
        #expect(gtkHitTesting.contains("gtk_widget_set_can_target(widget, 0)"))
        #expect(gtkHitTesting.contains("gtk_widget_set_can_focus(widget, 0)"))
        #expect(gtkTextSelection.contains("extension TextSelectionView: GTKRenderable"))
        #expect(gtkTextSelection.contains("extension QuillCompatibilityTextSelectionView: GTKRenderable"))
        #expect(gtkTextSelection.contains("gtk_label_set_selectable"))
        #expect(gtkTextSelection.contains("quillGTKSetLabelsSelectable(in: current, selectable: selectable)"))
        #expect(qtRenderer.contains("extension QuillCompatibilityOnHoverView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_widget_install_hover_recursive(qtHandle(widget), callback, box, destroy)"))
        #expect(qtRenderer.contains("extension QuillCompatibilityAllowsHitTestingView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_widget_set_allows_hit_testing_recursive(qtHandle(widget), 0)"))
        #expect(qtRenderer.contains("extension QuillCompatibilityContentShapeView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_bridge_widget_set_fixed_size(qtHandle(container), naturalW, naturalH)"))
        #expect(qtRenderer.contains("quill_qt_bridge_widget_add_child(qtHandle(container), qtHandle(child))"))
        #expect(qtRenderer.contains("extension HelpView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_widget_set_tooltip_recursive(qtHandle(widget), text)"))
        #expect(qtRenderer.contains("extension DisabledView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_widget_set_enabled_recursive(qtHandle(widget), 0)"))
        #expect(qtRenderer.contains("extension FocusedView: QtRenderable"))
        #expect(qtRenderer.contains("extension FocusedEqualsView: QtRenderable"))
        #expect(qtRenderer.contains("state.storage.addPlatformFocusCallback(key: callbackKey)"))
        #expect(qtRenderer.contains("quill_qt_widget_request_focus_recursive(qtHandle(widget))"))
        #expect(qtRenderer.contains("quill_qt_widget_clear_focus_recursive(qtHandle(widget))"))
        #expect(qtRenderer.contains("state.storage.removePlatformFocusCallback(key: callbackKey)"))
        #expect(qtRenderer.contains("quill_qt_widget_install_focus_recursive(qtHandle(widget), focusChanged, box, destroy)"))
        #expect(qtRenderer.contains("extension AccessibilityIdentifierView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_bridge_widget_set_object_name(qtHandle(widget), identifier)"))
        #expect(qtRenderer.contains("extension AccessibilityLabelView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_widget_set_accessible_name_recursive(qtHandle(widget), label)"))
        #expect(qtRenderer.contains("extension AccessibilityValueView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_widget_set_accessible_description_recursive(qtHandle(widget), value)"))
        #expect(qtRenderer.contains("extension AccessibilityHintView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_widget_set_accessible_description_recursive(qtHandle(widget), hint)"))
        #expect(qtRenderer.contains("extension AccessibilityElementView: QtRenderable"))
        #expect(qtRenderer.contains("extension SheetModifierView: QtRenderable"))
        #expect(qtRenderer.contains("extension ItemSheetModifierView: QtRenderable"))
        #expect(qtRenderer.contains("extension PopoverView: QtRenderable"))
        #expect(qtRenderer.contains("private func qtRenderPresentedView<V: View>"))
        #expect(qtRenderer.contains("environment.dismiss = DismissAction(handler: dismiss)"))
        #expect(qtRenderer.contains("environment.isPresentedInSheet = true"))
        #expect(qtRenderer.contains("swiftOpenUIWithPresentationDismissAction(dismiss)"))
        #expect(qtRenderer.contains("private func qtRenderPresentationOverlay("))
        #expect(qtRenderer.contains("quill_qt_overlay_container_add_child("))
        #expect(qtRenderer.contains("extension QuillCompatibilityTextSelectionView: QtRenderable"))
        #expect(qtRenderer.contains("quill_qt_widget_set_text_selectable_recursive(qtHandle(widget), 1)"))
        #expect(qtRenderer.contains("extension OnSubmitView: QtRenderable"))
        #expect(qtRenderer.contains("environment.submitAction = SubmitAction(handler: action)"))
        #expect(qtRenderer.contains("if let submitAction = environment.submitAction"))
        #expect(qtRenderer.contains("quill_qt_line_edit_connect_return_pressed("))
        #expect(qtRenderer.contains("extension OnKeyPressView: QtRenderable"))
        #expect(qtRenderer.contains("environment.keyPressActions.append(KeyPressAction(key: key, handler: action))"))
        #expect(qtRenderer.contains("qtInstallKeyPressActions("))
        #expect(qtRenderer.contains("quill_qt_widget_install_key_press_recursive(qtHandle(widget), callback, box, destroy)"))
        #expect(qtRenderer.contains("QtKeyPressActionBox"))
        #expect(qtRenderer.contains("extension KeyboardShortcutView: QtRenderable"))
        #expect(qtRenderer.contains("environment.keyboardShortcut = shortcut"))
        #expect(qtRenderer.contains("QtShortcutDispatchBox"))
        #expect(qtRenderer.contains("KeyboardShortcutRegistry.shared.dispatch(shortcut, windowID: windowID)"))
        #expect(qtRenderer.contains("KeyboardShortcutRegistry.shared.register("))
        #expect(qtRenderer.contains("KeyboardShortcutRegistry.shared.unregister(id: registrationID)"))
        #expect(qtRenderer.contains("if let shortcut = environment.keyboardShortcut"))
        #expect(qtRenderer.contains("qtRegisterKeyboardShortcut("))
        #expect(qtRenderer.contains("quill_qt_widget_connect_destroyed(qtHandle(widget), destroyed, box, destroy)"))
        #expect(qtRenderer.contains("quill_qt_widget_install_shortcut_dispatcher(qtHandle(window), callback, box, destroy)"))
        #expect(qtBackend.contains("windowEnvironment.windowID = windowID"))
        #expect(qtBackend.contains("defer { setCurrentEnvironment(previousEnvironment) }"))
        #expect(qtBackend.contains("qtInstallKeyboardShortcutDispatcher(on: window, windowID: windowID)"))
        #expect(cqtHeader.contains("quill_qt_bridge_hover_callback"))
        #expect(cqtHeader.contains("quill_qt_bridge_focus_callback"))
        #expect(cqtHeader.contains("quill_qt_bridge_key_callback"))
        #expect(cqtHeader.contains("quill_qt_bridge_shortcut_callback"))
        #expect(cqtHeader.contains("quill_qt_widget_install_hover_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_install_focus_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_install_key_press_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_install_shortcut_dispatcher"))
        #expect(cqtHeader.contains("quill_qt_widget_connect_destroyed"))
        #expect(cqtHeader.contains("quill_qt_widget_request_focus_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_clear_focus_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_set_allows_hit_testing_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_set_enabled_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_set_tooltip_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_set_accessible_name_recursive"))
        #expect(cqtHeader.contains("quill_qt_widget_set_accessible_description_recursive"))
        #expect(cqtHeader.contains("quill_qt_line_edit_connect_return_pressed"))
        #expect(cqtBridge.contains("class QuillQtHoverFilter final : public QObject"))
        #expect(cqtBridge.contains("class QuillQtFocusFilter final : public QObject"))
        #expect(cqtBridge.contains("class QuillQtKeyPressFilter final : public QObject"))
        #expect(cqtBridge.contains("class QuillQtShortcutFilter final : public QObject"))
        #expect(cqtBridge.contains("target->installEventFilter(new QuillQtHoverFilter(state, target))"))
        #expect(cqtBridge.contains("target->installEventFilter(new QuillQtFocusFilter(state, target))"))
        #expect(cqtBridge.contains("target->installEventFilter(new QuillQtKeyPressFilter(state, target))"))
        #expect(cqtBridge.contains("qApp->installEventFilter(filter)"))
        #expect(cqtBridge.contains("qApp->removeEventFilter(this)"))
        #expect(cqtBridge.contains("widgetContains(window_, target)"))
        #expect(cqtBridge.contains("quillQtKeyEquivalent(QKeyEvent *event)"))
        #expect(cqtBridge.contains("quillQtEventModifiers(QKeyEvent *event)"))
        #expect(cqtBridge.contains("case Qt::Key_Return:"))
        #expect(cqtBridge.contains("case Qt::Key_Tab:"))
        #expect(cqtBridge.contains("case Qt::Key_Up:"))
        #expect(cqtBridge.contains("Qt::ControlModifier"))
        #expect(cqtBridge.contains("Qt::MetaModifier"))
        #expect(cqtBridge.contains("modifiers |= command"))
        #expect(cqtBridge.contains("focusable->setFocus(Qt::OtherFocusReason)"))
        #expect(cqtBridge.contains("QApplication::focusWidget()"))
        #expect(cqtBridge.contains("std::make_shared<QuillQtHoverState>(callback, user_data, destroy)"))
        #expect(cqtBridge.contains("std::make_shared<QuillQtFocusState>(callback, user_data, destroy)"))
        #expect(cqtBridge.contains("std::make_shared<QuillQtKeyPressState>(callback, user_data, destroy)"))
        #expect(cqtBridge.contains("std::make_shared<QuillQtShortcutState>(callback, user_data, destroy)"))
        #expect(cqtBridge.contains("Qt::WA_TransparentForMouseEvents"))
        #expect(cqtBridge.contains("target->setFocusPolicy(Qt::NoFocus)"))
        #expect(cqtBridge.contains("target->setEnabled(enabled != 0)"))
        #expect(cqtBridge.contains("target->setToolTip(tooltip)"))
        #expect(cqtBridge.contains("target->setAccessibleDescription(tooltip)"))
        #expect(cqtBridge.contains("target->setAccessibleName(name)"))
        #expect(cqtBridge.contains("target->setAccessibleDescription(description)"))
        #expect(cqtHeader.contains("quill_qt_widget_set_text_selectable_recursive"))
        #expect(cqtBridge.contains("QLabel *label = qobject_cast<QLabel *>(target)"))
        #expect(cqtBridge.contains("Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard"))
        #expect(cqtBridge.contains("QObject::connect(lineEdit, &QLineEdit::returnPressed"))
        #expect(gtkPatchScript.contains("gtk_swift_accessible_update_label"))
        #expect(gtkPatchScript.contains("GTK_ACCESSIBLE_PROPERTY_LABEL"))
        #expect(gtkPatchScript.contains("GTK_ACCESSIBLE_PROPERTY_DESCRIPTION"))
        #expect(gtkPatchScript.contains("gtk_widget_set_tooltip_text(widget, text)"))
        #expect(gtkPatchScript.contains("gtk_swift_accessible_update_description(widget, textPointer)"))
        #expect(gtkPatchScript.contains("helpStart = text.find(\"extension HelpView: GTKRenderable\")"))
        #expect(gtkPatchScript.contains("helpRenderer = text[helpStart:helpEnd]"))
        #expect(gtkPatchScript.contains("if \"gtk_swift_accessible_update_description(widget, textPointer)\" not in helpRenderer:"))
        #expect(gtkPatchScript.contains("helpRenderer = helpRenderer.replace(needle, replacement, 1)"))
        #expect(gtkPatchScript.contains("text = text[:helpStart] + helpRenderer + text[helpEnd:]"))
    }

    @Test("Linux build preparation is gated by the selected backend")
    func linuxBuildPreparationIsGatedBySelectedBackend() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let preparationScriptURL = root.appendingPathComponent("scripts/prepare-linux-build-backend.sh")
        let preserveScriptURL = root.appendingPathComponent("scripts/swiftpm-preserve-package-resolved.sh")
        let preparationScript = try String(contentsOf: preparationScriptURL, encoding: .utf8)
        let preserveScript = try String(contentsOf: preserveScriptURL, encoding: .utf8)
        let linuxSwiftTest = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-swift-test.sh"),
            encoding: .utf8
        )
        let quillFoundationRuntimeProbeURL = root
            .appendingPathComponent("scripts/linux-quillfoundation-runtime-probe.sh")
        let quillFoundationRuntimeProbe = try String(
            contentsOf: quillFoundationRuntimeProbeURL,
            encoding: .utf8
        )
        let gtkPatchScript = try String(
            contentsOf: root.appendingPathComponent("scripts/patch-swiftopenui-gtk-css.sh"),
            encoding: .utf8
        )
        let backendBuildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-linux-backend-products.sh"),
            encoding: .utf8
        )
        let smokeLib = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-linux-backend-smoke-lib.sh"),
            encoding: .utf8
        )

        #expect(fileManager.isExecutableFile(atPath: preparationScriptURL.path))
        #expect(fileManager.isExecutableFile(atPath: preserveScriptURL.path))
        #expect(fileManager.isExecutableFile(atPath: quillFoundationRuntimeProbeURL.path))
        #expect(preparationScript.contains("source \"$ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(preparationScript.contains("REQUESTED_BACKEND=\"${QUILLUI_LINUX_BACKEND:-gtk}\""))
        #expect(preparationScript.contains("REQUESTED_BACKEND=\"$(quillui_require_linux_build_backend_identifier \"${REQUESTED_BACKEND:-gtk}\")\""))
        #expect(preparationScript.contains("gtk)\n    \"$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh\" \"$SCRATCH_PATH\""))
        #expect(preparationScript.contains("qt)\n    ;;"))
        #expect(linuxSwiftTest.contains(": \"${QUILLUI_LINUX_BACKEND:=gtk}\""))
        #expect(linuxSwiftTest.contains("export QUILLUI_LINUX_BACKEND"))
        #expect(preserveScript.contains("PACKAGE_RESOLVED=\"$PACKAGE_DIR/Package.resolved\""))
        #expect(preserveScript.contains("cp -p \"$PACKAGE_RESOLVED\" \"$TEMP_RESOLVED\""))
        #expect(preserveScript.contains("restore_package_resolved"))
        #expect(preserveScript.contains("trap 'status=$?; restore_package_resolved; exit \"$status\"' EXIT"))
        #expect(preserveScript.contains("exit \"$status\""))

        #expect(linuxSwiftTest.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(linuxSwiftTest.contains("scripts/swiftpm-preserve-package-resolved.sh"))
        #expect(!linuxSwiftTest.contains("patch-swiftopenui-gtk-css.sh"))
        #expect(linuxSwiftTest.contains(": \"${QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS:=1}\""))
        #expect(linuxSwiftTest.contains("export QUILLUI_DISABLE_UPSTREAM_APP_GRAPHS"))
        #expect(linuxSwiftTest.contains("swift build --build-tests --scratch-path \"$SCRATCH_PATH\""))
        #expect(!linuxSwiftTest.contains("swift build --build-tests --disable-index-store"))
        #expect(linuxSwiftTest.contains("swift test --skip-build --disable-index-store --scratch-path \"$SCRATCH_PATH\""))
        #expect(quillFoundationRuntimeProbe.contains(".product(name: \"QuillFoundation\", package: \"$PACKAGE_IDENTITY\")"))
        #expect(quillFoundationRuntimeProbe.contains("class_getInstanceMethod(ObjCRuntimeProbe.self"))
        #expect(quillFoundationRuntimeProbe.contains("method_exchangeImplementations(original!, replacement!)"))
        #expect(quillFoundationRuntimeProbe.contains("objc-runtime-probe ok"))
        #expect(gtkPatchScript.contains("GRDB_SOURCE_DIR=\"$SCRATCH_PATH/checkouts/GRDB.swift/GRDB\""))
        #expect(gtkPatchScript.contains("VENDORED_GRDB_SOURCE_DIR=\"$PACKAGE_PATH/third_party/GRDB.swift/GRDB\""))
        #expect(gtkPatchScript.contains("for candidate_grdb_source_dir in \"$GRDB_SOURCE_DIR\" \"$VENDORED_GRDB_SOURCE_DIR\"; do"))
        #expect(gtkPatchScript.contains("new = disable_can_import(text, \"Combine\")"))
        #expect(gtkPatchScript.contains("QUILLUI_GRDB_SKIP_CGFLOAT_ON_LINUX"))
        #expect(gtkPatchScript.contains("missing required module 'COpenCombineHelpers'"))
        #expect(backendBuildScript.contains("quillui_prepare_backend_once()"))
        #expect(backendBuildScript.contains("PREPARED_BACKENDS=$'\\n'"))
        #expect(backendBuildScript.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(backendBuildScript.contains("scripts/swiftpm-preserve-package-resolved.sh"))
        #expect(backendBuildScript.contains("--backend \"$build_backend\""))
        #expect(!backendBuildScript.contains("if [[ \"$DRY_RUN\" != \"1\" ]]; then\n  \"$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh\""))
        #expect(smokeLib.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(smokeLib.contains("scripts/swiftpm-preserve-package-resolved.sh"))
        #expect(smokeLib.contains("--backend \"$linux_build_backend\""))
        #expect(!smokeLib.contains("scripts/patch-swiftopenui-gtk-css.sh"))
    }

    @Test("SwiftPM package sources can be vendored by path")
    func swiftPMPackageSourcesCanBeVendoredByPath() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let vendorScriptURL = root.appendingPathComponent("scripts/vendor-swiftpm-sources.sh")
        let vendorScript = try String(contentsOf: vendorScriptURL, encoding: .utf8)
        let hydrateScriptURL = root.appendingPathComponent("scripts/hydrate-swiftpm-checkouts-from-resolved.py")
        let hydrateScript = try String(contentsOf: hydrateScriptURL, encoding: .utf8)
        let linuxWorkflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"),
            encoding: .utf8
        )
        let macOSWorkflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/macos-ci.yml"),
            encoding: .utf8
        )
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let swiftOpenUIManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Package.swift"),
            encoding: .utf8
        )
        let openCombineURLSession = try String(
            contentsOf: root.appendingPathComponent("third_party/OpenCombine/Sources/OpenCombineFoundation/URLSession.swift"),
            encoding: .utf8
        )
        let grdbManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/GRDB.swift/Package.swift"),
            encoding: .utf8
        )
        let swiftCryptoManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/swift-crypto/Package.swift"),
            encoding: .utf8
        )
        let swiftTreeSitterManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftTreeSitter/Package.swift"),
            encoding: .utf8
        )
        let trustedRouterManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/trusted-router-swift/Package.swift"),
            encoding: .utf8
        )
        let ollamaKitManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/OllamaKit/Package.swift"),
            encoding: .utf8
        )
        let markdownUIManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/MarkdownUI/Package.swift"),
            encoding: .utf8
        )
        let magnetManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/Magnet/Package.swift"),
            encoding: .utf8
        )
        let asyncAlgorithmsManifest = try String(
            contentsOf: root.appendingPathComponent("third_party/AsyncAlgorithms/Package.swift"),
            encoding: .utf8
        )
        let zipFoundationLegacyManifests = try [
            "Package@swift-4.0.swift",
            "Package@swift-4.1.swift",
            "Package@swift-4.2.swift",
        ].map { manifestName in
            try String(
                contentsOf: root.appendingPathComponent("third_party/ZIPFoundation/\(manifestName)"),
                encoding: .utf8
            )
        }
        let dependencyPrepScript = try String(
            contentsOf: root.appendingPathComponent("scripts/prepare-swiftui-linux-package-dependencies.py"),
            encoding: .utf8
        )

        #expect(fileManager.isExecutableFile(atPath: vendorScriptURL.path))
        #expect(fileManager.fileExists(atPath: hydrateScriptURL.path))
        #expect(linuxWorkflow.contains("Audit vendored SwiftPM sources"))
        #expect(linuxWorkflow.contains("scripts/vendor-swiftpm-sources.sh --all-vendored-apps --no-resolve --check-vendored"))
        #expect(macOSWorkflow.contains("Audit vendored SwiftPM sources"))
        #expect(macOSWorkflow.contains("scripts/vendor-swiftpm-sources.sh --all-vendored-apps --no-resolve --check-vendored"))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/OpenCombine/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/OpenCombine/LICENSE").path))
        #expect(openCombineURLSession.contains("@unchecked Sendable"))
        #expect(openCombineURLSession.contains("let responseHandler: @Sendable (Data?, URLResponse?, Error?) -> Void"))
        #expect(openCombineURLSession.contains("completionHandler: responseHandler"))
        #expect(!openCombineURLSession.contains("completionHandler: handleResponse"))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/GRDB.swift/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/GRDB.swift/LICENSE").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-syntax/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-syntax/LICENSE.txt").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-crypto/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-crypto/LICENSE.txt").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-asn1/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-asn1/LICENSE.txt").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-protobuf/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-protobuf/LICENSE.txt").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/SwiftSoup/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/SwiftSoup/LICENSE").path))
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent("third_party/SwiftSoup/.git").path))
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent("third_party/SwiftSoup/Package.resolved").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/Alamofire/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/NetworkImage/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/SwiftCMark/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/Sauce/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/swift-collections/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/SwiftUIIntrospect/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/AsyncAlgorithms/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/SwiftTreeSitter/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/CodeEditLanguages/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/CodeEditTextView/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/trusted-router-swift/Package.swift").path))
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent("third_party/trusted-router-swift/README.md").path))
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent("third_party/trusted-router-swift/.git").path))
        // Vendored path packages keep the default graph offline; a root lockfile
        // full of remote pins makes SwiftPM hydrate repositories we do not use.
        #expect(!fileManager.fileExists(atPath: root.appendingPathComponent("Package.resolved").path))
        #expect(manifest.contains("func locatePackageRoot() -> String"))
        #expect(manifest.contains("URL(fileURLWithPath: #filePath, isDirectory: false)"))
        #expect(manifest.contains("fileManager.currentDirectoryPath"))
        #expect(manifest.contains("candidate.appendingPathComponent(\"Package.swift\")"))
        #expect(manifest.contains("candidate.appendingPathComponent(\"Sources\")"))
        #expect(manifest.contains("let packageRoot: String = locatePackageRoot()"))
        #expect(manifest.contains("func vendoredPackage("))
        #expect(manifest.contains("func vendoredExactPackage("))
        #expect(manifest.contains("func vendoredBranchPackage("))
        #expect(manifest.contains("return .package(name: name, path: path)"))
        #expect(manifest.contains("path: \"third_party/OpenCombine\""))
        #expect(manifest.contains("path: \"third_party/GRDB.swift\""))
        #expect(manifest.contains("path: \"third_party/swift-syntax\""))
        #expect(manifest.contains("path: \"third_party/swift-crypto\""))
        #expect(manifest.contains("path: \"third_party/swift-protobuf\""))
        #expect(manifest.contains("path: \"third_party/SwiftSoup\""))
        #expect(manifest.contains("path: \"third_party/CodeEditSourceEditor\""))
        #expect(manifest.contains("path: \"third_party/SwiftTerm\""))
        #expect(manifest.contains(".library(name: \"AuthenticationServices\", targets: [\"AuthenticationServices\"])"))
        #expect(manifest.contains("\"SwiftUIIntrospect\""))
        #expect(manifest.contains("\"AsyncAlgorithms\""))
        #expect(vendorScript.contains("trusted-router-swift"))
        #expect(vendorScript.contains("--app NAME"))
        #expect(vendorScript.contains("source \"$ROOT_DIR/scripts/quillui-vendored-source.sh\""))
        #expect(vendorScript.contains("quillui_resolve_app_checkout_dir \"$ROOT_DIR\" \"$app_name\""))
        #expect(vendorScript.contains("-name Package.resolved -type f -print"))
        #expect(vendorScript.contains("--all-vendored-apps"))
        #expect(vendorScript.contains("add_package_resolved_files_for_all_vendored_apps()"))
        #expect(vendorScript.contains("--package-resolved PATH"))
        #expect(vendorScript.contains("--hydrate-missing"))
        #expect(vendorScript.contains("--check-vendored"))
        #expect(vendorScript.contains("hydrate_missing_package_checkouts()"))
        #expect(vendorScript.contains("check_vendored_packages()"))
        #expect(vendorScript.contains("audit_vendored_package_manifests()"))
        #expect(vendorScript.contains("remote package dependency remains in"))
        #expect(vendorScript.contains("scripts/hydrate-swiftpm-checkouts-from-resolved.py"))
        #expect(vendorScript.contains("QUILLUI_VENDOR_INCLUDE_DEV_PACKAGES=1"))
        #expect(vendorScript.contains("dev_only = {"))
        #expect(vendorScript.contains("shim_only = {"))
        #expect(vendorScript.contains("\"sparkle\""))
        #expect(vendorScript.contains("\"swift-snapshot-testing\""))
        #expect(vendorScript.contains("\"swiftlintplugin\""))
        #expect(vendorScript.contains("read_package_resolved_names()"))
        #expect(vendorScript.contains("\"codeedittextview\": \"CodeEditTextView\""))
        #expect(vendorScript.contains("\"swift-markdown-ui\": \"MarkdownUI\""))
        #expect(swiftOpenUIManifest.contains("func swiftOpenUIVendoredPackage("))
        #expect(swiftOpenUIManifest.contains("URL(fileURLWithPath: #filePath, isDirectory: false)"))
        #expect(swiftOpenUIManifest.contains("fileManager.fileExists(atPath: localPackage)"))
        #expect(swiftOpenUIManifest.contains("fileManager.fileExists(atPath: nestedVendorPackage)"))
        #expect(swiftOpenUIManifest.contains("path: \"../OpenCombine\""))
        #expect(grdbManifest.contains("QuillUI vendors GRDB for offline Linux runtime builds"))
        #expect(!grdbManifest.contains("swift-docc-plugin"))
        #expect(swiftCryptoManifest.contains("// QuillUI vendors swift-crypto next to swift-asn1"))
        #expect(swiftCryptoManifest.contains(".package(path: \"../swift-asn1\")"))
        #expect(swiftTreeSitterManifest.contains(".package(name: \"TreeSitter\", path: \"../tree-sitter\")"))
        #expect(trustedRouterManifest.contains("// swift-tools-version: 6.0"))
        #expect(trustedRouterManifest.contains(".package(name: \"QuillUI\", path: \"../..\")"))
        #expect(trustedRouterManifest.contains(".product(name: \"AuthenticationServices\", package: \"QuillUI\")"))
        #expect(trustedRouterManifest.contains(".product(name: \"CryptoKit\", package: \"QuillUI\")"))
        #expect(trustedRouterManifest.contains(".product(name: \"QuillShims\", package: \"QuillUI\")"))
        #expect(trustedRouterManifest.contains(".product(name: \"Security\", package: \"QuillUI\")"))
        #expect(ollamaKitManifest.contains(".package(path: \"../Alamofire\")"))
        #expect(!ollamaKitManifest.contains("swift-docc-plugin"))
        #expect(!ollamaKitManifest.contains("OllamaKitTests"))
        #expect(markdownUIManifest.contains(".package(path: \"../NetworkImage\")"))
        #expect(markdownUIManifest.contains(".package(name: \"swift-cmark\", path: \"../SwiftCMark\")"))
        #expect(!markdownUIManifest.contains("swift-snapshot-testing"))
        #expect(!markdownUIManifest.contains("MarkdownUITests"))
        #expect(magnetManifest.contains(".package(path: \"../Sauce\")"))
        #expect(!magnetManifest.contains("MagnetTests"))
        #expect(vendorScript.contains("def patch_grdb(text: str) -> str:"))
        #expect(vendorScript.contains("patch_file(\"third_party/GRDB.swift/Package.swift\", patch_grdb)"))
        #expect(!vendorScript.contains("package == \"GRDB.swift\" and \"swift-docc-plugin\""))
        #expect(asyncAlgorithmsManifest.contains(".package(path: \"../swift-collections\")"))
        #expect(!asyncAlgorithmsManifest.contains("https://github.com/apple/swift-collections.git"))
        #expect(!asyncAlgorithmsManifest.contains("AsyncAlgorithmsTests"))
        #expect(!asyncAlgorithmsManifest.contains("AsyncStreamingTests"))
        #expect(vendorScript.contains("def patch_zipfoundation_legacy(text: str) -> str:"))
        #expect(vendorScript.contains("patch_file(manifest, patch_zipfoundation_legacy)"))
        for legacyManifest in zipFoundationLegacyManifests {
            #expect(legacyManifest.contains(".systemLibrary(name: \"CZLib\", pkgConfig: \"zlib\")"))
            #expect(legacyManifest.contains("targets: targets"))
            #expect(!legacyManifest.contains("IBM-Swift/CZlib"))
            #expect(!legacyManifest.contains(".package(url:"))
        }
        #expect(vendorScript.contains("Default package set: OpenCombine, GRDB.swift, swift-syntax, swift-crypto,"))
        #expect(vendorScript.contains("default_packages()"))
        #expect(vendorScript.contains("scripts/swiftpm-preserve-package-resolved.sh"))
        #expect(vendorScript.contains("already vendored $package -> third_party/$package"))
        #expect(vendorScript.contains("missing vendored $package -> third_party/$package"))
        #expect(vendorScript.contains("vendored SwiftPM package sources are present"))
        #expect(vendorScript.contains("QUILLUI_VENDOR_FORCE=1"))
        #expect(vendorScript.contains("git_source_identity()"))
        #expect(vendorScript.contains("git -C \"$source\" status --porcelain --untracked-files=no"))
        #expect(vendorScript.contains("vendored_source_metadata()"))
        #expect(vendorScript.contains("quillui-swiftpm-vendor/v1"))
        #expect(vendorScript.contains(".quillui-vendor-source-fingerprint"))
        #expect(vendorScript.contains("[[ \"$(cat \"$metadata_file\")\" == \"$metadata\" ]]"))
        #expect(vendorScript.contains("rsync -a --delete --delete-excluded"))
        #expect(vendorScript.contains("chmod -R u+w \"$destination\""))
        #expect(vendorScript.contains("--exclude '.git'"))
        #expect(vendorScript.contains("--exclude '.build'"))
        #expect(vendorScript.contains("--exclude '.build-*'"))
        #expect(vendorScript.contains("--exclude '.swiftpm'"))
        #expect(vendorScript.contains("--exclude 'Tests'"))
        #expect(vendorScript.contains("--exclude 'test'"))
        #expect(vendorScript.contains("--exclude '*.docc'"))
        #expect(vendorScript.contains("--exclude 'Assets'"))
        #expect(vendorScript.contains("--exclude 'Images'"))
        #expect(vendorScript.contains("--exclude '*Example*'"))
        #expect(vendorScript.contains("--exclude 'Demo'"))
        #expect(vendorScript.contains("--exclude 'Playground'"))
        #expect(vendorScript.contains("--exclude 'Sandbox'"))
        #expect(vendorScript.contains("--exclude '*Tests'"))
        #expect(vendorScript.contains("--exclude 'tools'"))
        #expect(vendorScript.contains("--exclude 'wrappers'"))
        #expect(vendorScript.contains("--exclude 'TestApplication'"))
        #expect(vendorScript.contains("--exclude 'TerminalApp'"))
        #expect(vendorScript.contains("--exclude '*.xcodeproj'"))
        #expect(vendorScript.contains("--exclude '*.xcworkspace'"))
        #expect(vendorScript.contains("--exclude 'Makefile'"))
        #expect(vendorScript.contains("--exclude 'Documentation'"))
        #expect(vendorScript.contains("--exclude 'Carthage'"))
        #expect(vendorScript.contains("--full"))
        #expect(vendorScript.contains("patch_swift_crypto_manifest()"))
        #expect(vendorScript.contains("patch_swift_tree_sitter_manifest()"))
        #expect(vendorScript.contains("patch_vendored_transitive_manifests()"))
        #expect(vendorScript.contains("def remove_named_call(text: str, call: str, name: str) -> str:"))
        #expect(vendorScript.contains("chmod u+w \"$manifest\""))
        #expect(vendorScript.contains(".package(path: \"../swift-asn1\")"))
        #expect(vendorScript.contains(".package(name: \"TreeSitter\", path: \"../tree-sitter\")"))
        #expect(vendorScript.contains(".package(path: \"../Alamofire\")"))
        #expect(vendorScript.contains(".package(name: \"swift-cmark\", path: \"../SwiftCMark\")"))
        #expect(vendorScript.contains(".package(path: \"../Sauce\")"))
        #expect(vendorScript.contains(".package(path: \"../swift-collections\")"))
        #expect(vendorScript.contains("OllamaKit Package.swift still contains remote docs or stale tests"))
        #expect(vendorScript.contains("MarkdownUI Package.swift still contains remote snapshot tests"))
        #expect(vendorScript.contains("Magnet Package.swift still contains stale tests"))
        #expect(vendorScript.contains("AsyncAlgorithms Package.swift still contains unbuildable slim-tree targets"))
        #expect(vendorScript.contains("GRDB.swift"))
        #expect(vendorScript.contains("SwiftSoup"))
        #expect(vendorScript.contains("JavaScriptKit"))
        #expect(hydrateScript.contains("CANONICAL_PACKAGE_NAMES"))
        #expect(hydrateScript.contains("\"activityindicatorview\": \"ActivityIndicatorView\""))
        #expect(hydrateScript.contains("\"swift-markdown-ui\": \"MarkdownUI\""))
        #expect(hydrateScript.contains("\"sparkle\""))
        #expect(hydrateScript.contains("Package.resolved pin lacks location or revision"))
        #expect(hydrateScript.contains("already vendored {pin.package} -> third_party/{pin.package}"))
        #expect(hydrateScript.contains("would hydrate {pin.package} from {pin.location} @ {pin.revision}"))
        #expect(hydrateScript.contains("[\"git\", \"clone\", \"--quiet\", pin.location"))
        #expect(hydrateScript.contains("[\"git\", \"checkout\", \"--quiet\", pin.revision]"))
        #expect(dependencyPrepScript.contains("def ensure_user_writable_tree(path: Path) -> None:"))
        #expect(dependencyPrepScript.contains("stat.S_IWUSR"))
        #expect(dependencyPrepScript.contains("ensure_user_writable_tree(prepared_dir)"))
        #expect(dependencyPrepScript.contains("PACKAGE_CALL_URL_RE"))
        #expect(dependencyPrepScript.contains("class LocalPackageDependency"))
        #expect(dependencyPrepScript.contains("def package_identity_from_url(url: str) -> str:"))
        #expect(dependencyPrepScript.contains("def dependency_package_name(parsed: PackageLine, package_dir: Path) -> str | None:"))
        #expect(dependencyPrepScript.contains("return identity"))
        #expect(dependencyPrepScript.contains("def local_package_dependencies(root_dir: Path, package_dir: Path)"))
        #expect(dependencyPrepScript.contains("url_package_name = package_name or package_identity_from_url(url)"))
        #expect(dependencyPrepScript.contains("dependency_dir = local_candidate_for_url(root_dir, url, url_package_name)"))
        #expect(dependencyPrepScript.contains("def rewrite_package_dependency_calls("))
        #expect(dependencyPrepScript.contains("url_replacements: dict[str, tuple[Path, str | None]]"))
        #expect(dependencyPrepScript.contains("dependency_line(package_name, replacement_path)"))
        #expect(dependencyPrepScript.contains("seen_output_lines: set[str] = set()"))
        #expect(dependencyPrepScript.contains("if rewritten in seen_output_lines:"))
        #expect(dependencyPrepScript.contains("if re.search(r\"\\bswiftSettings\\s*:\", block):"))
        #expect(dependencyPrepScript.contains("return block"))
    }

    @Test("SwiftPM package source vendoring discovers Package.resolved under vendored app source")
    func swiftPMPackageSourceVendoringDiscoversPackageResolvedUnderVendoredAppSource() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-vendor-app-package-resolved-\(UUID().uuidString)")
        let scriptsDir = sandbox.appendingPathComponent("scripts")
        let resolvedDir = sandbox
            .appendingPathComponent("vendor/apps/demo/Demo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm")
        let vendorScript = scriptsDir.appendingPathComponent("vendor-swiftpm-sources.sh")

        try fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resolvedDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        try fileManager.copyItem(
            at: root.appendingPathComponent("scripts/vendor-swiftpm-sources.sh"),
            to: vendorScript
        )
        try fileManager.copyItem(
            at: root.appendingPathComponent("scripts/quillui-vendored-source.sh"),
            to: scriptsDir.appendingPathComponent("quillui-vendored-source.sh")
        )
        try fileManager.copyItem(
            at: root.appendingPathComponent("scripts/hydrate-swiftpm-checkouts-from-resolved.py"),
            to: scriptsDir.appendingPathComponent("hydrate-swiftpm-checkouts-from-resolved.py")
        )
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: vendorScript.path)
        try """
        {
          "pins": [
            {
              "identity": "swift-async-algorithms",
              "kind": "remoteSourceControl",
              "location": "https://github.com/apple/swift-async-algorithms.git",
              "state": { "revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
            },
            {
              "identity": "swift-snapshot-testing",
              "kind": "remoteSourceControl",
              "location": "https://github.com/pointfreeco/swift-snapshot-testing.git",
              "state": { "revision": "cccccccccccccccccccccccccccccccccccccccc" }
            },
            {
              "identity": "swiftlintplugin",
              "kind": "remoteSourceControl",
              "location": "https://github.com/lukepistrol/SwiftLintPlugin",
              "state": { "revision": "dddddddddddddddddddddddddddddddddddddddd" }
            },
            {
              "identity": "codeedittextview",
              "kind": "remoteSourceControl",
              "location": "https://github.com/CodeEditApp/CodeEditTextView.git",
              "state": { "revision": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
            }
          ],
          "version": 2
        }
        """.write(
            to: resolvedDir.appendingPathComponent("Package.resolved"),
            atomically: true,
            encoding: .utf8
        )

        let missingVendoredCheck = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--check-vendored", "--app", "demo"]
        )

        #expect(missingVendoredCheck.status == 1, Comment(rawValue: missingVendoredCheck.output))
        #expect(
            missingVendoredCheck.output.contains("missing vendored AsyncAlgorithms -> third_party/AsyncAlgorithms"),
            Comment(rawValue: missingVendoredCheck.output)
        )
        #expect(
            missingVendoredCheck.output.contains("missing vendored CodeEditTextView -> third_party/CodeEditTextView"),
            Comment(rawValue: missingVendoredCheck.output)
        )

        let missingAllVendoredCheck = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--check-vendored", "--all-vendored-apps"]
        )

        #expect(missingAllVendoredCheck.status == 1, Comment(rawValue: missingAllVendoredCheck.output))
        #expect(
            missingAllVendoredCheck.output.contains("missing vendored AsyncAlgorithms -> third_party/AsyncAlgorithms"),
            Comment(rawValue: missingAllVendoredCheck.output)
        )
        #expect(
            missingAllVendoredCheck.output.contains("missing vendored CodeEditTextView -> third_party/CodeEditTextView"),
            Comment(rawValue: missingAllVendoredCheck.output)
        )

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--dry-run", "--app", "demo"]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("warning: no checkout found for AsyncAlgorithms"), Comment(rawValue: result.output))
        #expect(result.output.contains("warning: no checkout found for CodeEditTextView"), Comment(rawValue: result.output))
        #expect(!result.output.contains("SwiftSnapshotTesting"), Comment(rawValue: result.output))
        #expect(!result.output.contains("SwiftLintPlugin"), Comment(rawValue: result.output))

        let hydrateResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--dry-run", "--hydrate-missing", "--app", "demo"]
        )

        #expect(hydrateResult.status == 0, Comment(rawValue: hydrateResult.output))
        #expect(
            hydrateResult.output.contains("would hydrate AsyncAlgorithms from https://github.com/apple/swift-async-algorithms.git @ aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            Comment(rawValue: hydrateResult.output)
        )
        #expect(
            hydrateResult.output.contains("would hydrate CodeEditTextView from https://github.com/CodeEditApp/CodeEditTextView.git @ bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
            Comment(rawValue: hydrateResult.output)
        )
        #expect(!hydrateResult.output.contains("would hydrate SwiftSnapshotTesting"), Comment(rawValue: hydrateResult.output))
        #expect(!hydrateResult.output.contains("would hydrate SwiftLintPlugin"), Comment(rawValue: hydrateResult.output))

        let devResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "QUILLUI_VENDOR_INCLUDE_DEV_PACKAGES=1",
                vendorScript.path,
                "--no-resolve",
                "--dry-run",
                "--app",
                "demo",
            ]
        )

        #expect(devResult.status == 0, Comment(rawValue: devResult.output))
        #expect(
            devResult.output.contains("warning: no checkout found for SwiftSnapshotTesting"),
            Comment(rawValue: devResult.output)
        )
        #expect(
            devResult.output.contains("warning: no checkout found for SwiftLintPlugin"),
            Comment(rawValue: devResult.output)
        )

        let packageListResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--print-package-list", "--app", "demo"]
        )

        #expect(packageListResult.status == 0, Comment(rawValue: packageListResult.output))
        #expect(packageListResult.output.contains("AsyncAlgorithms"), Comment(rawValue: packageListResult.output))
        #expect(packageListResult.output.contains("CodeEditTextView"), Comment(rawValue: packageListResult.output))
        #expect(!packageListResult.output.contains("SwiftSnapshotTesting"), Comment(rawValue: packageListResult.output))
        #expect(!packageListResult.output.contains("SwiftLintPlugin"), Comment(rawValue: packageListResult.output))

        for package in ["AsyncAlgorithms", "CodeEditTextView"] {
            let packageDir = sandbox.appendingPathComponent("third_party/\(package)")
            try fileManager.createDirectory(at: packageDir, withIntermediateDirectories: true)
            try """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(name: "\(package)")
            """.write(
                to: packageDir.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
        }

        let presentVendoredCheck = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--check-vendored", "--app", "demo"]
        )

        #expect(presentVendoredCheck.status == 0, Comment(rawValue: presentVendoredCheck.output))
        #expect(
            presentVendoredCheck.output.contains("vendored SwiftPM package sources are present"),
            Comment(rawValue: presentVendoredCheck.output)
        )

        let presentAllVendoredCheck = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--check-vendored", "--all-vendored-apps"]
        )

        #expect(presentAllVendoredCheck.status == 0, Comment(rawValue: presentAllVendoredCheck.output))
        #expect(
            presentAllVendoredCheck.output.contains("vendored SwiftPM package sources are present"),
            Comment(rawValue: presentAllVendoredCheck.output)
        )

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "CodeEditTextView",
            dependencies: [
                .package(url: "https://github.com/example/not-vendored.git", from: "1.0.0")
            ]
        )
        """.write(
            to: sandbox.appendingPathComponent("third_party/CodeEditTextView/Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let remoteDependencyCheck = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--check-vendored", "--app", "demo"]
        )

        #expect(remoteDependencyCheck.status == 1, Comment(rawValue: remoteDependencyCheck.output))
        #expect(
            remoteDependencyCheck.output.contains("remote package dependency remains in third_party/CodeEditTextView/Package.swift"),
            Comment(rawValue: remoteDependencyCheck.output)
        )

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        // .package(url: "https://github.com/example/commented-example.git", from: "1.0.0")
        let package = Package(name: "CodeEditTextView")
        """.write(
            to: sandbox.appendingPathComponent("third_party/CodeEditTextView/Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let commentedRemoteCheck = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [vendorScript.path, "--no-resolve", "--check-vendored", "--app", "demo"]
        )

        #expect(commentedRemoteCheck.status == 0, Comment(rawValue: commentedRemoteCheck.output))
    }

    @Test("Heavy Linux backend runners are resource guarded")
    func heavyLinuxBackendRunnersAreResourceGuarded() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let guardURL = root.appendingPathComponent("scripts/quillui-resource-guard.sh")
        let guardSource = try String(contentsOf: guardURL, encoding: .utf8)

        #expect(fileManager.isExecutableFile(atPath: guardURL.path))
        #expect(guardSource.contains("QUILLUI_RESOURCE_GUARD_DISABLE"))
        #expect(guardSource.contains("QUILLUI_RESOURCE_GUARD_MIN_FREE_GIB"))
        #expect(guardSource.contains("QUILLUI_RESOURCE_GUARD_MAX_USED_PERCENT"))
        #expect(guardSource.contains("QUILLUI_RESOURCE_GUARD_MIN_AVAILABLE_MEMORY_MIB"))
        #expect(guardSource.contains("QUILLUI_RESOURCE_GUARD_WARN_AVAILABLE_MEMORY_MIB"))
        #expect(guardSource.contains("QUILLUI_RESOURCE_GUARD_MAX_CODEX_RSS_MIB"))
        #expect(guardSource.contains("QUILLUI_RESOURCE_GUARD_DIAGNOSTIC_PROCESS_LIMIT"))
        #expect(guardSource.contains("print_process_diagnostics"))
        #expect(guardSource.contains("print_process_group_diagnostics"))
        #expect(guardSource.contains("Codex RSS"))
        #expect(guardSource.contains("top RSS processes"))
        #expect(guardSource.contains("RSS by process group"))
        #expect(guardSource.contains("below warning threshold"))
        #expect(guardSource.contains("group = \"Codex\""))
        #expect(guardSource.contains("group = \"Linux VM\""))
        #expect(guardSource.contains("group = \"Swift toolchain\""))
        #expect(guardSource.contains("/proc/meminfo"))
        #expect(guardSource.contains("vm_stat"))
        #expect(guardSource.contains("/^Pages inactive:/"))

        let guardedScripts = [
            "scripts/linux-backend-check.sh",
            "scripts/linux-swift-test.sh",
            "scripts/build-linux-backend-products.sh",
            "scripts/build-swiftui-linux-app.sh",
            "scripts/generate-swiftui-linux-package.sh",
            "scripts/run-linux-backend-smoke-matrix.sh",
            "scripts/run-linux-backend-profile-csv.sh",
            "scripts/linux-backend-profile.sh",
            "scripts/linux-backend-visual-check.sh",
            "scripts/linux-backend-interaction-check.sh",
            "scripts/linux-solderscope-smoke-check.sh",
        ]

        for relativePath in guardedScripts {
            let source = try packageSource(relativePath)
            #expect(
                source.contains("scripts/quillui-resource-guard.sh"),
                "\(relativePath) should run the shared resource guard before heavy work"
            )
        }

        let legacyGtkShims = [
            ("scripts/linux-gtk-check.sh", "scripts/linux-backend-check.sh"),
            ("scripts/linux-gtk-visual-check.sh", "scripts/linux-backend-visual-check.sh"),
            ("scripts/linux-gtk-interaction-check.sh", "scripts/linux-backend-interaction-check.sh"),
            ("scripts/linux-gtk-profile.sh", "linux-backend-profile.sh"),
            ("scripts/run-linux-gtk-profile-csv.sh", "run-linux-backend-profile-csv.sh"),
            ("scripts/check-linux-gtk-profile-budget.sh", "check-linux-backend-profile-budget.sh"),
        ]

        for (relativePath, backendRunner) in legacyGtkShims {
            let source = try packageSource(relativePath)
            #expect(
                source.contains(backendRunner),
                "\(relativePath) should delegate to the backend-neutral runner"
            )
            #expect(
                !source.contains("swift build")
                    && !source.contains("swift test")
                    && !source.contains("xvfb-run")
                    && !source.contains("perf stat"),
                "\(relativePath) should stay a thin shim instead of starting heavy work directly"
            )
        }

        let backendBuildScript = try packageSource("scripts/build-linux-backend-products.sh")
        let smokeMatrixRunner = try packageSource("scripts/run-linux-backend-smoke-matrix.sh")
        #expect(backendBuildScript.contains("if [[ \"$DRY_RUN\" != \"1\" ]]; then\n  \"$ROOT_DIR/scripts/quillui-resource-guard.sh\""))
        #expect(smokeMatrixRunner.contains("if [[ \"$DRY_RUN\" != \"1\" ]]; then\n  \"$ROOT_DIR/scripts/quillui-resource-guard.sh\""))
    }

    @Test("Autonomous loop artifact pruning is scoped and dry-run first")
    func autonomousLoopArtifactPruningIsScopedAndDryRunFirst() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let pruneURL = root.appendingPathComponent("scripts/quillui-loop-prune.sh")
        let pruneSource = try String(contentsOf: pruneURL, encoding: .utf8)

        #expect(fileManager.isExecutableFile(atPath: pruneURL.path))
        #expect(pruneSource.contains("QUILLUI_LOOP_PRUNE_DRY_RUN"))
        #expect(pruneSource.contains("DRY_RUN=\"${QUILLUI_LOOP_PRUNE_DRY_RUN:-1}\""))
        #expect(pruneSource.contains("QUILLUI_LOOP_PRUNE_MAX_DAYS"))
        #expect(pruneSource.contains("QUILLUI_LOOP_PRUNE_INCLUDE_BUILD_CACHE"))
        #expect(pruneSource.contains("QUILLUI_LOOP_PRUNE_REPORT_USAGE"))
        #expect(pruneSource.contains("QUILLUI_LOOP_PRUNE_ROOT"))
        #expect(pruneSource.contains("quillui loop prune usage:"))
        #expect(pruneSource.contains("du -sh \"$path\""))
        #expect(pruneSource.contains("$ROOT_DIR/.qa"))
        #expect(pruneSource.contains("$ROOT_DIR/.build-codex-loop/artifacts"))
        #expect(pruneSource.contains("$ROOT_DIR/.build-linux-vm-loop/artifacts"))
        #expect(pruneSource.contains("$ROOT_DIR/.build-linux-qt/artifacts"))
        #expect(pruneSource.contains("$ROOT_DIR/.build/artifacts"))
        #expect(pruneSource.contains("$ROOT_DIR/.build-codex-loop"))
        #expect(pruneSource.contains("$ROOT_DIR/.build-linux-vm-loop"))
        #expect(pruneSource.contains("$ROOT_DIR/.build-linux-qt"))
        #expect(pruneSource.contains("-mtime"))
        #expect(pruneSource.contains("find \"$base\" -type f"))
        #expect(pruneSource.contains("refusing to prune outside a QuillUI checkout"))
        #expect(!pruneSource.contains("rm -rf"))
        #expect(!pruneSource.contains("\"$ROOT_DIR/.build\""))
    }

    @Test("SwiftPM resolver preservation restores Package.resolved")
    func swiftPMResolverPreservationRestoresPackageResolved() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let preserveScriptURL = root.appendingPathComponent("scripts/swiftpm-preserve-package-resolved.sh")
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("quillui-package-resolved-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let packageResolved = temporaryDirectory.appendingPathComponent("Package.resolved")
        let original = "original pins\n"
        try original.write(to: packageResolved, atomically: true, encoding: .utf8)

        let success = try runSourceHygieneProcess(
            preserveScriptURL,
            arguments: ["bash", "-c", "printf changed > \"$QUILLUI_SWIFTPM_PACKAGE_PATH/Package.resolved\""],
            environment: ["QUILLUI_SWIFTPM_PACKAGE_PATH": temporaryDirectory.path]
        )
        #expect(success.status == 0)
        #expect(try String(contentsOf: packageResolved, encoding: .utf8) == original)

        let failure = try runSourceHygieneProcess(
            preserveScriptURL,
            arguments: ["bash", "-c", "printf failed > \"$QUILLUI_SWIFTPM_PACKAGE_PATH/Package.resolved\"; exit 23"],
            environment: ["QUILLUI_SWIFTPM_PACKAGE_PATH": temporaryDirectory.path]
        )
        #expect(failure.status == 23)
        #expect(try String(contentsOf: packageResolved, encoding: .utf8) == original)

        try fileManager.removeItem(at: packageResolved)
        let missing = try runSourceHygieneProcess(
            preserveScriptURL,
            arguments: ["bash", "-c", "printf created > \"$QUILLUI_SWIFTPM_PACKAGE_PATH/Package.resolved\""],
            environment: ["QUILLUI_SWIFTPM_PACKAGE_PATH": temporaryDirectory.path]
        )
        #expect(missing.status == 0)
        #expect(!fileManager.fileExists(atPath: packageResolved.path))
    }

    @Test("macro expansion paths report diagnostics instead of crashing")
    func macroExpansionPathsAvoidFatalError() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let macros = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillDataMacros/QuillDataMacros.swift"),
            encoding: .utf8
        )

        #expect(manifest.contains("name: \"QuillDataTests\""))
        #expect(manifest.contains("dependencies: [\"QuillData\"]"))
        #expect(!manifest.contains(".product(name: \"SQLiteData\", package: \"sqlite-data\")"))
        #expect(!manifest.contains(".package(url: \"https://github.com/pointfreeco/sqlite-data\""))
        #expect(!macros.contains("fatalError("))
    }

    @Test("QuillChatKit stays reusable by native SwiftUI clients")
    func quillChatKitStaysNativeSwiftUIReusable() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillChatKit/QuillChatKit.swift"),
            encoding: .utf8
        )
        let iosCheck = try String(
            contentsOf: root.appendingPathComponent("scripts/check-quillchatkit-ios.sh"),
            encoding: .utf8
        )
        let macOSWorkflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/macos-ci.yml"),
            encoding: .utf8
        )
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)

        #expect(manifest.contains(".library(name: \"QuillChatKit\", targets: [\"QuillChatKit\"])"))
        #expect(manifest.contains("platforms: [.macOS(.v14), .iOS(.v14)]"))
        #expect(source.contains("import SwiftUI"))
        #expect(source.contains("public enum ChatInteractionProfile"))
        #expect(source.contains("public struct ChatAppearance"))
        #expect(source.contains("public static var platformDefault: ChatInteractionProfile"))
        #expect(source.contains("public static var platformDefault: ChatAppearance"))
        #expect(source.contains("#if os(iOS) || os(tvOS) || os(visionOS)"))
        #expect(source.contains("public static var touch: ChatAppearance"))
        #expect(source.contains("public struct ChatSidebar"))
        #expect(source.contains("public struct ChatSelectionPlaceholder"))
        #expect(source.contains("public struct ChatSplitShell"))
        #expect(source.contains("@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)"))
        #expect(source.contains("NavigationSplitView"))
        #expect(source.contains("public init<Thread: ChatThread>"))
        #expect(source.contains("private typealias ChatLayoutLength = Int"))
        #expect(source.contains("private typealias ChatLayoutLength = CGFloat"))
        #expect(!source.contains("import QuillUI"))
        #expect(!source.contains("import UIKit"))
        #expect(!source.contains("import AppKit"))
        #expect(iosCheck.contains("SDK_NAME=\"${QUILLCHATKIT_IOS_SDK:-iphonesimulator}\""))
        #expect(iosCheck.contains("TARGET_TRIPLE=\"${QUILLCHATKIT_IOS_TARGET_TRIPLE:-arm64-apple-ios14.0-simulator}\""))
        #expect(iosCheck.contains("swift build"))
        #expect(iosCheck.contains("--sdk \"$SDK_PATH\""))
        #expect(iosCheck.contains("--target QuillChatKit"))
        #expect(macOSWorkflow.contains("scripts/check-quillchatkit-ios.sh"))
        #expect(readme.contains("scripts/check-quillchatkit-ios.sh"))
        #expect(readme.contains("iOS simulator SDK"))
        #expect(readme.contains("ChatAppearance.touch"))
    }

    @Test("Linux UIKit shim covers dependency conformance symbols")
    func linuxUIKitShimCoversDependencyConformanceSymbols() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUIKit/QuillUIKit.swift"),
            encoding: .utf8
        )
        let pasteboardAdditions = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUIKit/QuillUIKitMissingMembers+Pasteboard.swift"),
            encoding: .utf8
        )
        let gestureRecognizers = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUIKit/UIGestureRecognizers.swift"),
            encoding: .utf8
        )
        let uiKitShim = try String(
            contentsOf: root.appendingPathComponent("Sources/UIKitShim/UIKit.swift"),
            encoding: .utf8
        )
        let swiftUICompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/DesignSystemSurfaceCompat.swift"),
            encoding: .utf8
        )
        let attributedStringSize = try String(
            contentsOf: root.appendingPathComponent("Sources/UIKitShim/NSAttributedStringSize.swift"),
            encoding: .utf8
        )
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(source.contains("public enum UIUserInterfaceStyle: Int"))
        #expect(manifest.contains("let quillUIKitDependencies: [Target.Dependency] = [\n    \"QuillFoundation\", \"QuillKit\", \"CoreGraphics\", \"QuartzCore\",\n    \"CoreTransferable\", \"UniformTypeIdentifiers\",\n]"))
        #expect(pasteboardAdditions.contains("import CoreGraphics"))
        #expect(uiKitShim.contains("public typealias UIEdgeInsets = QuillEdgeInsets"))
        #expect(uiKitShim.contains("public struct UIKitNSTextStorageEditActions: OptionSet, Sendable"))
        #expect(uiKitShim.contains("public typealias EditActions = UIKitNSTextStorageEditActions"))
        #expect(!uiKitShim.contains("public struct NSTextStorageEditActions: OptionSet"))
        #expect(uiKitShim.contains("public weak var layoutManager: NSLayoutManager?"))
        #expect(uiKitShim.contains("public init(start: UITextPosition, end: UITextPosition)"))
        #expect(!uiKitShim.contains("var safeAreaInsets: UIEdgeInsets { .zero }\n    @MainActor var windowScene"))
        #expect(uiKitShim.contains("open override func sizeThatFits(_ size: CGSize) -> CGSize"))
        #expect(uiKitShim.contains("public extension NSAttributedString {\n    func boundingRect(with size: CGSize,"))
        #expect(attributedStringSize.contains("func size() -> CGSize"))
        #expect(!attributedStringSize.contains("func boundingRect(with size: CGSize,"))
        #expect(source.contains("public typealias UserInterfaceStyle = UIUserInterfaceStyle"))
        #expect(source.contains("public struct AnimationOptions: OptionSet, Sendable"))
        #expect(source.contains("usingSpringWithDamping: CGFloat"))
        #expect(source.contains("public struct State: OptionSet, Sendable"))
        #expect(gestureRecognizers.contains("@MainActor open class UIGestureRecognizer: NSObject"))
        #expect(source.contains("public enum ContentInsetAdjustmentBehavior: Int"))
        #expect(source.contains("public enum DisplayModeButtonVisibility: Int"))
        #expect(source.contains("public enum SplitBehavior: Int"))
        #expect(source.contains("public enum Column: Int"))
        #expect(source.contains("public enum LayoutEnvironment: Int"))
        #expect(source.contains("case twoDisplaceSecondary"))
        #expect(source.contains("case inspector"))
        #expect(source.contains("@MainActor public class UIWindowScene: UIScene"))
        #expect(!uiKitShim.contains("@MainActor public class UIWindowScene: UIScene"))
        #expect(!uiKitShim.contains("@MainActor public protocol UINavigationControllerDelegate: AnyObject"))
        #expect(source.contains("@MainActor func textViewDidChange(_ textView: Any)"))
        #expect(uiKitShim.contains("@MainActor func textViewDidChange(_ textView: UITextView) {}"))
        #expect(!swiftUICompatibility.contains("func startAccessingSecurityScopedResource() -> Bool"))
        #expect(!swiftUICompatibility.contains("func stopAccessingSecurityScopedResource()"))
        #expect(source.contains("#if os(Linux)\n    open func forwardingTarget(for aSelector: Selector!) -> Any? { nil }\n    #else\n    open override func forwardingTarget(for aSelector: Selector!) -> Any? { nil }\n    #endif"))
        #expect(pasteboardAdditions.contains("#if os(Linux)\n    func responds(to selector: Selector?) -> Bool {\n        false\n    }\n    #endif"))
    }

    @Test("QuartzCore layer tests match CALayer main-actor isolation")
    func quartzCoreLayerTestsMatchCALayerMainActorIsolation() throws {
        let manifest = try packageSource("Package.swift")
        let modelTests = try packageSource("Tests/QuartzCoreTests/CALayerModelTests.swift")
        let timingTests = try packageSource("Tests/QuartzCoreTests/CAAnimationTimingTests.swift")

        #expect(manifest.contains("name: \"QuartzCoreTests\",\n        dependencies: [\"QuartzCore\"],\n        path: \"Tests/QuartzCoreTests\",\n        swiftSettings: [.swiftLanguageMode(.v5)]"))
        #expect(!modelTests.contains("@MainActor\nfinal class CALayerModelTests: XCTestCase"))
        #expect(!timingTests.contains("@MainActor\nfinal class CAAnimationTimingTests: XCTestCase"))
        #expect(modelTests.contains("@preconcurrency import QuartzCore"))
        #expect(timingTests.contains("@preconcurrency import QuartzCore"))
    }

    @Test("Semantic colors have a single platform-color owner")
    func semanticColorsHaveSinglePlatformColorOwner() throws {
        let foundation = try packageSource("Sources/QuillFoundation/QuillFoundation.swift")
        let uiKit = try packageSource("Sources/UIKitShim/UIKit.swift")

        for colorName in ["systemGray", "systemGray2", "systemBlue", "systemRed", "pink"] {
            #expect(foundation.contains("public static let \(colorName) = RSColor("))
            #expect(!uiKit.contains("static let \(colorName) = RSColor("))
        }

        #expect(foundation.contains("@_implementationOnly import CGdkPixbuf"))
        #expect(foundation.contains("public class RSColor: NSObject, NSSecureCoding"))
        #expect(foundation.contains("public static var supportsSecureCoding: Bool { true }"))
        #expect(uiKit.contains("static let placeholderText = RSColor("))
    }

    @Test("Text attachments have a single Linux compatibility owner")
    func textAttachmentsHaveSingleLinuxCompatibilityOwner() throws {
        let foundation = try packageSource("Sources/QuillFoundation/QuillFoundation.swift")
        let uiKit = try packageSource("Sources/UIKitShim/UIKit.swift")
        let appKit = try packageSource("Sources/QuillAppKit/QuillAppKit.swift")
        let textLayout = try packageSource("Sources/QuillFoundation/NSTextLayoutShared.swift")

        #expect(foundation.occurrences(of: "open class NSTextAttachment: NSObject") == 1)
        #expect(foundation.contains("public var image: RSImage?"))
        #expect(foundation.contains("convenience init(attachment: NSTextAttachment)"))
        #expect(!uiKit.contains("open class NSTextAttachment"))
        #expect(!appKit.contains("open class NSTextAttachment"))
        #expect(!uiKit.contains("convenience init(attachment: NSTextAttachment)"))
        #expect(!appKit.contains("convenience init(attachment: NSTextAttachment)"))
        #expect(textLayout.contains("NSTextAttachment also lives in QuillFoundation"))
    }

    @Test("Linux AppKit shims avoid Swift 6 warning traps")
    func linuxAppKitShimsAvoidSwift6WarningTraps() throws {
        let root = try packageRoot()
        let appKit = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKit/QuillAppKit.swift"),
            encoding: .utf8
        )
        let appKitBitmapEncode = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKit/QuillAppKitBitmapEncode.swift"),
            encoding: .utf8
        )
        let gtk = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKitGTK/QuillAppKit+GTK.swift"),
            encoding: .utf8
        )
        let gtkDrawingHost = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKitGTK/QuillNSViewDrawingHost.swift"),
            encoding: .utf8
        )
        let swiftUINSViewRepresentable = try String(
            contentsOf: root.appendingPathComponent("Sources/SwiftUIShim/NSViewRepresentable.swift"),
            encoding: .utf8
        )
        let appKitSmoke = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKitSmoke/Smoke.swift"),
            encoding: .utf8
        )
        let appKitSmokeRunner = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKitSmokeRunner/main.swift"),
            encoding: .utf8
        )
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(appKit.contains("@MainActor public protocol NSWindowDelegate"))
        #expect(appKit.contains("@MainActor open class NSViewController"))
        #expect(appKit.contains("public init(frame: NSRect)"))
        #expect(!appKit.contains("nonisolated public init(frame: NSRect)"))
        #expect(swiftUINSViewRepresentable.occurrences(of: "nonisolated(unsafe) let representable: R") == 3)
        #expect(swiftUINSViewRepresentable.occurrences(of: "nonisolated init(_ representable: R)") == 3)
        #expect(gtkDrawingHost.contains("public func quillGtkQueueDrawWidget(_ widget: OpaquePointer)"))
        #expect(gtkDrawingHost.contains("if Thread.isMainThread"))
        #expect(gtkDrawingHost.contains("g_idle_add_full(Int32(G_PRIORITY_DEFAULT)"))
        #expect(gtkDrawingHost.contains("g_object_ref(gpointer(widget))"))
        #expect(gtkDrawingHost.contains("g_object_unref(gpointer(queued.widget))"))
        #expect(gtkDrawingHost.contains("quillGtkQueueDrawWidget(live)"))
        #expect(swiftUINSViewRepresentable.occurrences(of: "nsView.needsDisplay = true") == 2)
        #expect(swiftUINSViewRepresentable.occurrences(of: "quillGtkQueueDrawWidget(") == 2)
        // SolderScope's @preconcurrency pivot (#548) made NSApplicationDelegate
        // @MainActor (its delegate methods are main-thread). `@preconcurrency`
        // downgrades the isolation check to Swift-5 mode, so a nonisolated
        // Telegram conformance is a warning rather than the hard error a bare
        // `@MainActor` protocol would cause — the protocol must carry BOTH
        // annotations and never appear as a bare (line-leading) `@MainActor`.
        #expect(appKit.contains("@preconcurrency @MainActor public protocol NSApplicationDelegate"))
        #expect(!appKit.contains("\n@MainActor public protocol NSApplicationDelegate"))
        #expect(appKit.contains("@MainActor public protocol NSToolbarDelegate"))
        #expect(appKit.contains("open var menu: NSMenu?"))
        #expect(appKit.contains("public func indexOfItem(withTitle title: String) -> Int"))
        #expect(appKitBitmapEncode.contains("@_implementationOnly import CGdkPixbuf"))
        #expect(appKit.contains("nonisolated(unsafe) public static var current: NSGraphicsContext?"))
        #expect(appKit.contains("public struct NSXPCServiceContinuation"))
        #expect(appKit.contains("func withService<Service, Result>"))
        #expect(appKit.contains("func withContinuation<Service, Result>"))
        #expect(appKit.contains("static let controlTextColor = NSColor()"))
        #expect(appKit.contains("func font(\n        withFamily family: String"))
        #expect(appKit.contains("open class NSPanGestureRecognizer"))
        #expect(appKit.contains("open func close() { window?.close() }"))
        #expect(appKit.contains("open class var isCompatibleWithOverlayScrollers"))
        #expect(appKit.contains("open func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool)"))
        #expect(appKit.contains("open func drawSelection(in dirtyRect: NSRect)"))
        #expect(appKit.contains("open class NSHostingView<Content>: NSView"))
        #expect(appKit.contains("public required init(rootView: Content)"))
        #expect(appKit.contains("open var currentPoint: NSPoint"))
        #expect(appKit.contains("public convenience init(rect: NSRect)"))
        #expect(appKit.contains("open func yank(_ sender: Any?)"))
        #expect(appKit.contains("open func textInputClientWillStartScrollingOrZooming()"))
        #expect(appKit.contains("open func textInputClientDidEndScrollingOrZooming()"))
        // The menu/table/outline delegate protocols must stay nonisolated:
        // @MainActor on a protocol infers @MainActor on conforming classes,
        // which breaks upstream Telegram TGUIKit types (TableView, ContextMenu)
        // that conform from nonisolated code. The shim bridges its delegate
        // call sites with MainActor.assumeIsolated instead.
        #expect(appKit.contains("public protocol NSMenuDelegate"))
        #expect(appKit.contains("public protocol NSTableViewDelegate"))
        #expect(appKit.contains("public protocol NSTableViewDataSource"))
        #expect(appKit.contains("public protocol NSOutlineViewDelegate"))
        #expect(appKit.contains("public protocol NSOutlineViewDataSource"))
        #expect(!appKit.contains("@MainActor public protocol NSMenuDelegate"))
        #expect(!appKit.contains("@MainActor public protocol NSTableViewDelegate"))
        #expect(appKit.contains("MainActor.assumeIsolated { delegate.menuWillOpen(self) }"))
        #expect(appKit.contains("public static let borderless: StyleMask = []"))
        #expect(appKit.contains("open class NSTextStorage: NSMutableAttributedString {"))
        #expect(appKit.contains("private func quillWireTextSystem()"))
        #expect(appKit.contains("open override func insertNewline(_ sender: Any?)"))
        #expect(appKit.contains("textStorage.addLayoutManager(layoutManager)"))
        #expect(appKit.contains("layoutManager.addTextContainer(textContainer)"))
        #expect(appKit.contains("public func removeTextContainer(at index: Int)"))
        #expect(appKit.contains("oldValue.removeTextContainer(at: oldIndex)"))
        #expect(appKitSmoke.contains("func smokeTextSystemWiring() -> Bool"))
        #expect(appKitSmoke.contains("replacementStorage.layoutManagers.contains { $0 === layoutManager }"))
        #expect(appKitSmoke.contains("replacementLayoutManager.textStorage === replacementStorage"))
        #expect(appKitSmoke.contains("replacementContainer.layoutManager === replacementLayoutManager"))
        #expect(appKitSmoke.contains("smokeTextSystemWiring() &&"))
        #expect(appKitSmokeRunner.contains("QuillAppKitSmoke.validate()"))
        #expect(manifest.contains(".executable(name: \"quill-appkit-smoke\", targets: [\"QuillAppKitSmokeRunner\"])"))
        #expect(appKit.contains("open func performKeyEquivalent(with event: NSEvent) -> Bool"))
        #expect(appKit.contains("open func standardWindowButton(_ button: WindowButton) -> NSButton?"))
        #expect(appKit.contains("open class NSRunningApplication: NSObject"))
        #expect(appKit.contains("public var runningApplications: [NSRunningApplication]"))
        #expect(appKit.contains("open var fittingSize: NSSize"))
        #expect(appKit.contains("open func updateConstraintsForSubtreeIfNeeded()"))
        #expect(appKit.contains("public var isExcludedFromWindowsMenu: Bool"))
        #expect(appKit.contains("public var hidesOnDeactivate: Bool"))
        #expect(appKit.contains("open func scroll(_ clipView: NSClipView, to point: NSPoint)"))
        #expect(appKit.contains("public convenience init(roundedRect rect: NSRect, xRadius: CGFloat, yRadius: CGFloat)"))
        #expect(appKit.contains("open func appendArc("))
        #expect(!appKit.contains("public static let borderless = StyleMask(rawValue: 0)"))
        #expect(!appKit.contains("open class NSTextStorage: NSMutableAttributedString, @unchecked Sendable"))
        #expect(!gtk.contains("let ctx = g_main_context_default()"))
    }

    @Test("GTK NSView drawing host forwards native input as AppKit events")
    func gtkNSViewDrawingHostForwardsNativeInputAsAppKitEvents() throws {
        let root = try packageRoot()
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let host = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKitGTK/QuillNSViewDrawingHost.swift"),
            encoding: .utf8
        )
        let shim = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/CGTK/shim.h"),
            encoding: .utf8
        )

        #expect(manifest.contains("name: \"QuillAppKitGTK\""))
        #expect(manifest.contains("\"AppKit\""))
        #expect(manifest.contains("\"CGtk4\""))
        #expect(manifest.contains("\"Observation\""))
        #expect(manifest.contains(".product(name: \"CGTK\", package: \"SwiftOpenUI\")"))
        #expect(manifest.contains(".product(name: \"SwiftOpenUI\", package: \"SwiftOpenUI\")"))
        #expect(host.contains("quillInstallGtkDrawHostInputControllers(on: area, host: box)"))
        #expect(host.contains("gtk_gesture_drag_new()"))
        #expect(host.contains("gtk_gesture_click_new()"))
        #expect(host.contains("gtk_swift_gesture_single_set_button(gesture, button.gtkButton)"))
        #expect(host.contains("gtk_swift_motion_capture_controller()"))
        #expect(host.contains("gtk_swift_scroll_capture_controller()"))
        #expect(!host.contains("gtk_event_controller_motion_new()"))
        #expect(!host.contains("gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)"))
        #expect(host.contains("gtk_gesture_zoom_new()"))
        #expect(host.contains("gtk_swift_add_capture_multitouch_gesture(widget, gesture)"))
        #expect(host.contains("event.magnification = magnification"))
        #expect(host.contains("context.host.beginMagnifyGesture()"))
        #expect(host.contains("dispatch(type: button.draggedEventType"))
        #expect(host.contains("clickCount: 2"))
        #expect(host.contains("lastPointerLocation ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)"))
        #expect(host.contains("updateCursor(at: location)"))
        #expect(host.contains("quillGTKCursorName(for: cursor)"))
        #expect(!host.contains("quillInstallNSViewCursorController"))
        #expect(host.contains("NSApplication.shared.sendEvent(event)"))
        #expect(host.contains("view.scrollWheel(with: event)"))
        #expect(shim.contains("gtk_swift_motion_capture_controller(void)"))
        #expect(shim.contains("gtk_swift_scroll_capture_controller(void)"))
        #expect(shim.contains("gtk_swift_add_capture_multitouch_gesture(GtkWidget *widget, GtkGesture *gesture)"))
    }

    @Test("Linux Apple compatibility shims avoid generated app warnings")
    func linuxAppleCompatibilityShimsAvoidGeneratedAppWarnings() throws {
        let root = try packageRoot()
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let appKit = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKit/QuillAppKit.swift"),
            encoding: .utf8
        )
        let avFoundation = try String(
            contentsOf: root.appendingPathComponent("Sources/AVFoundation/AVFoundation.swift"),
            encoding: .utf8
        )
        let avCaptureSurface = try String(
            contentsOf: root.appendingPathComponent("Sources/AVFoundation/AVCaptureSurface.swift"),
            encoding: .utf8
        )
        let avCaptureExtras = try String(
            contentsOf: root.appendingPathComponent("Sources/AVFoundation/AVCaptureExtras.swift"),
            encoding: .utf8
        )
        let syntheticCapture = try String(
            contentsOf: root.appendingPathComponent("Sources/AVFoundation/SyntheticCapture.swift"),
            encoding: .utf8
        )
        let captureTests = try String(
            contentsOf: root.appendingPathComponent("Tests/QuillCompatibilityModuleTests/AVCaptureSurfaceTests.swift"),
            encoding: .utf8
        )
        let osShim = try String(
            contentsOf: root.appendingPathComponent("Sources/osShim/os.swift"),
            encoding: .utf8
        )
        let attributedStringDocument = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillFoundation/NSAttributedStringDocument.swift"),
            encoding: .utf8
        )

        #expect(appKit.contains("@discardableResult\n    public func declareTypes(_ types: [PasteboardType], owner: Any?) -> Int"))
        #expect(avFoundation.contains("@discardableResult\n    public func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool"))
        #expect(avCaptureSurface.contains("var quillV4L2Bridge: AnyObject?"))
        #expect(avCaptureSurface.contains("public static let inputPriority = Preset(rawValue: \"AVCaptureSessionPresetInputPriority\")"))
        #expect(avCaptureSurface.occurrences(of: "public static let inputPriority = Preset(rawValue: \"AVCaptureSessionPresetInputPriority\")") == 1)
        #expect(avCaptureSurface.occurrences(of: "public enum InterruptionReason: Int, Sendable") == 1)
        #expect(avCaptureSurface.occurrences(of: "public var isMultitaskingCameraAccessSupported: Bool { false }") == 1)
        #expect(avCaptureSurface.occurrences(of: "public var isMultitaskingCameraAccessEnabled") == 1)
        #expect(avCaptureSurface.contains("public enum AVCaptureVideoStabilizationMode"))
        #expect(avCaptureSurface.contains("public var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off"))
        #expect(!avCaptureExtras.contains("public final class AVCaptureSession"))
        #expect(!avCaptureExtras.contains("open class AVCaptureInput"))
        #expect(!avCaptureExtras.contains("open class AVCaptureOutput"))
        #expect(!avCaptureExtras.contains("public final class AVCaptureDeviceInput"))
        #expect(!avCaptureExtras.contains("public final class AVCaptureVideoDataOutput"))
        #expect(!avCaptureExtras.contains("public protocol AVCaptureVideoDataOutputSampleBufferDelegate"))
        #expect(!avCaptureExtras.contains("public final class AVCaptureConnection"))
        #expect(!avCaptureExtras.contains("public enum AVAuthorizationStatus"))
        #expect(!avCaptureExtras.contains("public var deviceType: DeviceType"))
        #expect(!avCaptureExtras.contains("public func lockForConfiguration()"))
        #expect(avCaptureExtras.contains("open class AVCaptureVideoPreviewLayer"))
        // V4L2 (#515): the capture backend's CV4L2 system library joins the
        // dependency list Linux-only via quillV4L2Dependencies.
        #expect(manifest.contains(".target(name: \"AVFoundation\", dependencies: [\"QuillKit\", \"QuillFoundation\", \"QuartzCore\", \"AudioToolbox\", \"CoreMedia\", \"CoreVideo\", \"CoreImage\"] + quillV4L2Dependencies, path: \"Sources/AVFoundation\")"))
        #expect(manifest.contains("\"QuillFoundation\", \"QuillKit\", \"CoreGraphics\", \"QuartzCore\",\n    \"CoreTransferable\", \"UniformTypeIdentifiers\","))
        #expect(manifest.contains("[\"QuillFoundation\", \"QuillUIKit\", \"QuillKit\", \"CoreGraphics\", \"UserNotifications\", \"QuartzCore\", \"CoreTransferable\", \"CoreText\"]"))
        #expect(manifest.contains("name: \"QuillUIKit\",\n            dependencies: [\"QuillFoundation\", \"QuillKit\", \"CoreGraphics\", \"CoreTransferable\", \"UniformTypeIdentifiers\"],"))
        #expect(avCaptureSurface.contains("public class AVCaptureSession: @unchecked Sendable"))
        #expect(avCaptureSurface.contains("quillV4L2StartIfAvailable()"))
        #expect(!avCaptureExtras.contains("public final class AVCaptureSession"))
        #expect(!avCaptureExtras.contains("public protocol AVCaptureVideoDataOutputSampleBufferDelegate"))
        #expect(avFoundation.contains("self.devices = AVCaptureDevice.quillDiscoveredCaptureDevices()"))
        #expect(avCaptureSurface.contains("var quillSyntheticBridge: AnyObject?"))
        #expect(avCaptureSurface.contains("quillSyntheticStartIfAvailable()"))
        #expect(avCaptureSurface.contains("quillSyntheticStopIfAvailable()"))
        #expect(syntheticCapture.contains("QUILL_AVFOUNDATION_SYNTHETIC_CAMERA"))
        #expect(syntheticCapture.contains("static func quillDiscoveredCaptureDevices() -> [AVCaptureDevice]"))
        #expect(syntheticCapture.contains("static func deviceConfiguration(_ device: AVCaptureDevice)"))
        #expect(syntheticCapture.contains("let configuration = QuillSyntheticCaptureConfiguration.deviceConfiguration(syntheticDevice)"))
        #expect(syntheticCapture.contains("QuillSyntheticFrameFactory.makeFrame"))
        #expect(syntheticCapture.contains("captureOutput(box.output, didOutput: box.sampleBuffer, from: box.connection)"))
        #expect(captureTests.contains("syntheticCameraDiscoveryIsOptIn"))
        #expect(captureTests.contains("syntheticCaptureSessionDeliversFrames"))
        #expect(!osShim.contains("import os"))
        #expect(attributedStringDocument.contains("#if os(Linux)\n// NSAttributedString document-conversion surface"))
        #expect(attributedStringDocument.hasSuffix("#endif\n"))
        for product in ["WebKit", "CoreImage", "LinkPresentation", "AVKit", "QuickLook", "AppIntents"] {
            #expect(
                manifest.occurrences(of: ".library(name: \"\(product)\", targets: [\"\(product)\"])") == 1,
                Comment(rawValue: "Package.swift declares duplicate product \(product)")
            )
        }
    }

    @Test("Linux SwiftUI compatibility extensions have one canonical module")
    func linuxSwiftUICompatibilityExtensionsHaveOneCanonicalModule() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let quillUI = try String(contentsOf: root.appendingPathComponent("Sources/QuillUI/QuillUI.swift"), encoding: .utf8)
        let swiftUIShim = try String(contentsOf: root.appendingPathComponent("Sources/SwiftUIShim/SwiftUI.swift"), encoding: .utf8)
        let swiftUIPlatformSurface = try String(
            contentsOf: root.appendingPathComponent("Sources/SwiftUIShim/PlatformSurface.swift"),
            encoding: .utf8
        )
        let compatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/QuillSwiftUICompatibility.swift"),
            encoding: .utf8
        )
        let designCompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/DesignSystemSurfaceCompat.swift"),
            encoding: .utf8
        )
        let appStorageCompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/AppStorage.swift"),
            encoding: .utf8
        )
        let iceCubesViewModifiers = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/IceCubesViewModifiers.swift"),
            encoding: .utf8
        )
        let fileImporterCompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/QuillFileImporter.swift"),
            encoding: .utf8
        )
        let iceCubesShims = try String(
            contentsOf: root.appendingPathComponent("Sources/IceCubesShims/IceCubesShims.swift"),
            encoding: .utf8
        )
        let quillUpstreamCompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/UpstreamCompatibility.swift"),
            encoding: .utf8
        )
        let environmentModifiers = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/EnvironmentModifiers.swift"),
            encoding: .utf8
        )
        let gtkRenderer = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"),
            encoding: .utf8
        )
        let swiftOpenUIControlStyles = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/ControlStyleModifiers.swift"),
            encoding: .utf8
        )
        let swiftOpenUIColor = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/Color.swift"),
            encoding: .utf8
        )
        let swiftOpenUIFocusedValue = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/State/FocusedValue.swift"),
            encoding: .utf8
        )
        let swiftOpenUITextField = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/TextField.swift"),
            encoding: .utf8
        )

        #expect(manifest.contains("name: \"QuillSwiftUICompatibility\""))
        #expect(manifest.contains("\"QuillFoundation\",\n    \"QuillSwiftUICompatibility\","))
        // The SwiftUI shadow now mirrors Apple's macOS re-export topology
        // (AppKit + Combine) and carries the gtk-graph-only representable
        // mount via swiftUIShadowMountDependencies.
        #expect(manifest.contains("\"QuillSwiftUICompatibility\", \"AppKit\", \"UIKit\", \"CoreImage\", \"CoreTransferable\", \"Combine\","))
        #expect(manifest.contains("] + swiftUIShadowMountDependencies"))
        #expect(manifest.contains("\"Observation\",\n    .product(name: \"SwiftOpenUI\", package: \"SwiftOpenUI\"),\n    \"CGdkPixbuf\","))
        #expect(manifest.contains("let wrappingHStackDependencies: [Target.Dependency] =\n    quillUILinuxBuildBackend == .gtk"))
        #expect(manifest.contains(": [\"SwiftUI\", \"Observation\"]"))
        #expect(manifest.contains("let wrappingHStackSwiftSettings: [SwiftSetting] = quillUILinuxBuildBackend == .gtk"))
        #expect(manifest.contains("swiftSettings: wrappingHStackSwiftSettings,\n        linkerSettings: wrappingHStackLinkerSettings"))
        #expect(manifest.contains("? [\"QuillAppKitGTK\", \"Observation\", swiftUIShimBackendDependency]"))
        #expect(manifest.contains("quillUILinuxBuildBackend == .qt && quillUIQtGenericEnabled ? [\"QuillAppKitQt\", \"Observation\", swiftUIShimBackendDependency] : []"))
        #expect(manifest.contains(".product(name: \"SwiftOpenUISymbols\", package: \"SwiftOpenUI\"),\n                    \"QuillSwiftUICompatibility\",\n                    \"Observation\",\n                    \"CQtBridge\""))
        #expect(quillUI.contains("@_exported import QuillSwiftUICompatibility"))
        #expect(swiftUIShim.contains("@_exported import QuillSwiftUICompatibility"))
        #expect(compatibility.contains("typealias Weight = FontWeight"))
        #expect(compatibility.contains("static var firstTextBaseline: VerticalAlignment { .top }"))
        #expect(swiftOpenUIControlStyles.contains("public struct PlainButtonStyle: ButtonStyle"))
        #expect(swiftOpenUIControlStyles.contains("public final class ToggleStyleConfiguration"))
        #expect(swiftOpenUIControlStyles.contains("private let isOnBinding: Binding<Bool>"))
        #expect(swiftOpenUIControlStyles.contains("public var isOn: Bool"))
        #expect(swiftOpenUIControlStyles.contains("public protocol ToggleStyle"))
        #expect(swiftOpenUIControlStyles.contains("public protocol ControlGroupStyle"))
        #expect(swiftOpenUIControlStyles.contains("public var customToggleStyle: AnyToggleStyle?"))
        #expect(designCompatibility.contains("public struct RoundedBorderTextFieldStyle"))
        #expect(designCompatibility.contains("public struct KeyboardTypeView<Content: View, Keyboard>: View"))
        #expect(designCompatibility.contains("func scrollContentBackground(_ visibility: ScrollContentBackgroundVisibility) -> ScrollContentBackgroundView<Self>"))
        #expect(!designCompatibility.contains("func scrollContentBackground(_ visibility: ScrollContentBackgroundVisibility) -> Self"))
        #expect(swiftUIPlatformSurface.contains("func keyboardType(_ type: UIKeyboardType) -> KeyboardTypeView<Self, UIKeyboardType>"))
        #expect(fileImporterCompatibility.contains("func fileImporter("))
        #expect(fileImporterCompatibility.contains("QuillFileImporter.selectURLs("))
        #expect(!swiftUIPlatformSurface.contains("func fileImporter("))
        #expect(designCompatibility.contains("func formStyle(_ style: GroupedFormStyle) -> Self"))
        #expect(!iceCubesViewModifiers.contains("func formStyle(_ style: GroupedFormStyle) -> Self"))
        #expect(swiftOpenUITextField.contains("public init(_ title: String, text: Binding<String>, axis: Axis = .horizontal)"))
        #expect(!designCompatibility.contains("init(_ title: String, text: Binding<String>, axis: Axis)"))
        #expect(designCompatibility.contains("public static func offset(_ offset: CGSize) -> AnyTransition"))
        #expect(designCompatibility.contains("public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition"))
        #expect(designCompatibility.contains("@MainActor\n    static var circle: Circle { Circle() }"))
        #expect(designCompatibility.contains("FocusedKeyPathValuesStore.shared.resolve(keyPath)"))
        #expect(designCompatibility.contains("public var wrappedValue: Binding<Value>? { resolve() }"))
        #expect(quillUpstreamCompatibility.contains("OptionalFocusedValueView(content: self, keyPath: keyPath, value: value)"))
        #expect(!quillUpstreamCompatibility.contains("focusedSceneValue is currently a source-compatibility fallback on Linux."))
        #expect(swiftOpenUIFocusedValue.contains("public final class FocusedKeyPathValuesStore"))
        #expect(swiftOpenUIFocusedValue.contains("public init() {}"))
        #expect(swiftOpenUIFocusedValue.contains("valuesByWindow[windowID, default: [:]][keyPath] = value"))
        #expect(swiftOpenUIFocusedValue.contains("public struct OptionalFocusedValueView<Content: View, Value>: View"))
        #expect(swiftOpenUIFocusedValue.contains("public init(content: Content, keyPath: WritableKeyPath<FocusedValues, Value?>, value: Value?)"))
        #expect(swiftOpenUIFocusedValue.contains("FocusedKeyPathValuesStore.shared.publish(value, for: keyPath)"))
        #expect(swiftOpenUIFocusedValue.contains("FocusedKeyPathValuesStore.shared.clear(keyPath)"))
        #expect(designCompatibility.contains("@MainActor\n    public init<Content: View>(_ column: TableColumn<RowValue, Content>)"))
        #expect(designCompatibility.contains("public init<Value>(_ title: String, value: KeyPath<RowValue, Value>) where Content == Text"))
        #expect(designCompatibility.contains("private var isRowSelected: (@MainActor (RowValue) -> Bool)?"))
        #expect(designCompatibility.contains("let selection = selection"))
        #expect(designCompatibility.contains("selection.wrappedValue = [row.id]"))
        #expect(designCompatibility.contains("public func render(_ row: RowValue) -> Content"))
        #expect(designCompatibility.contains("public func cell(for row: RowValue) -> AnyView"))
        #expect(designCompatibility.contains("columns[columnIndex]\n                            .cell(for: rows[rowIndex])"))
        #expect(designCompatibility.contains(".onTapGesture {\n                    selectRow?(rows[rowIndex])"))
        #expect(designCompatibility.contains("@MainActor public static func buildExpression<Content: View>"))
        #expect(appStorageCompatibility.contains("public struct AppStorage<Value>: AnyStateStorageProvider"))
        #expect(!iceCubesShims.contains("public struct AppStorage<Value>"))
        #expect(appStorageCompatibility.contains("private enum QuillAppStorageEnvironment"))
        #expect(appStorageCompatibility.contains("QUILLUI_APP_STORAGE_\\(String(sanitized))"))
        #expect(appStorageCompatibility.contains("UserDefaults.standard.string(forKey: key)\n            ?? QuillAppStorageEnvironment.seed(forKey: key)"))
        #expect(appStorageCompatibility.contains("return QuillAppStorageEnvironment.seed(forKey: key).flatMap(Self.init(quillAppStorageSeed:))"))
        #expect(environmentModifiers.contains("public struct TransformEnvironmentModifierView"))
        #expect(environmentModifiers.contains("func transformEnvironment<V>("))
        #expect(gtkRenderer.contains("extension TransformEnvironmentModifierView: GTKRenderable"))
        #expect(gtkRenderer.contains("environment.customToggleStyle"))
        #expect(gtkRenderer.contains("extension CustomToggleStyleModifier: GTKRenderable"))
        #expect(gtkRenderer.contains("extension ControlGroupStyleModifier: GTKRenderable"))
        #expect(swiftOpenUIColor.contains("public static var tertiary: Color"))
        #expect(swiftOpenUIColor.contains("public static var quaternary: Color"))
        #expect(swiftUIPlatformSurface.contains("public extension Color"))
        #expect(swiftUIPlatformSurface.contains("init(_ color: NSColor)"))
        #expect(!quillUpstreamCompatibility.contains("public struct PlainButtonStyle"))
        #expect(!quillUpstreamCompatibility.contains("func formStyle(_ style: GroupedFormStyle)"))
        #expect(!designCompatibility.contains("public protocol ButtonStyle"))
        #expect(!designCompatibility.contains("public struct ButtonStyleConfiguration"))
        #expect(!designCompatibility.contains("public struct PlainButtonStyle: ButtonStyle"))
        #expect(!quillUpstreamCompatibility.contains("public struct RoundedBorderTextFieldStyle"))
        #expect(!quillUpstreamCompatibility.contains("public struct KeyboardTypeView<Content: View>"))
        #expect(!swiftUIShim.contains("static var firstTextBaseline"))
    }

    @Test("BackendQt text modifiers use native label traversal")
    func backendQtTextModifiersUseNativeLabelTraversal() throws {
        let renderer = try packageSource("Sources/BackendQt/QtRenderer.swift")
        let bridgeHeader = try packageSource("Sources/CQtBridge/include/CQtBridge.h")
        let bridgeImplementation = try packageSource("Sources/CQtBridge/CQtBridge.cpp")

        #expect(bridgeHeader.contains("quill_qt_bridge_widget_apply_line_limit_to_labels"))
        #expect(bridgeHeader.contains("quill_qt_bridge_widget_apply_truncation_mode_to_labels"))
        #expect(bridgeImplementation.contains("class QuillQtLabel final : public QLabel"))
        #expect(bridgeImplementation.contains("labelsInSubtree(asWidget(widget))"))
        #expect(bridgeImplementation.contains("fontMetrics().elidedText(fullText, elideMode, width())"))
        #expect(bridgeImplementation.contains("setMaximumHeight(lineHeight * effectiveLimit)"))
        #expect(renderer.contains("quill_qt_bridge_widget_apply_line_limit_to_labels"))
        #expect(renderer.contains("quill_qt_bridge_widget_apply_truncation_mode_to_labels"))
        #expect(renderer.contains("let text = title.isEmpty ? qtTextLabel(from: labelView.wrapped) : title"))
        #expect(renderer.contains("let children = items.flatMap { item in qtRenderChildren(contentBuilder(item)) }"))
        #expect(!renderer.contains("TODO: Qt label enumeration not yet implemented"))
        #expect(!renderer.contains("TODO: Qt truncation mode not yet implemented"))
        #expect(!renderer.contains("let text = label.isEmpty"))
    }

    @Test("BackendQt Stepper and DatePicker use native Qt controls")
    func backendQtStepperAndDatePickerUseNativeControls() throws {
        let renderer = try packageSource("Sources/BackendQt/QtRenderer.swift")
        let bridgeHeader = try packageSource("Sources/CQtBridge/include/CQtBridge.h")
        let bridgeImplementation = try packageSource("Sources/CQtBridge/CQtBridge.cpp")

        #expect(bridgeHeader.contains("quill_qt_make_double_spin_box"))
        #expect(bridgeHeader.contains("quill_qt_double_spin_box_connect_value_changed"))
        #expect(bridgeHeader.contains("quill_qt_make_calendar_widget"))
        #expect(bridgeHeader.contains("quill_qt_calendar_connect_selection_changed"))
        #expect(bridgeImplementation.contains("#include <QDoubleSpinBox>"))
        #expect(bridgeImplementation.contains("#include <QCalendarWidget>"))
        #expect(bridgeImplementation.contains("&QDoubleSpinBox::valueChanged"))
        #expect(bridgeImplementation.contains("&QCalendarWidget::selectionChanged"))
        #expect(renderer.contains("quill_qt_make_double_spin_box"))
        #expect(renderer.contains("quill_qt_make_calendar_widget"))
        #expect(renderer.contains("QtDoubleClosureBox"))
        #expect(renderer.contains("QtDateClosureBox"))
        #expect(!renderer.contains("extension Stepper: QtRenderable {\n    public func qtCreateWidget() -> OpaquePointer {\n        qtOpaque(quill_qt_bridge_label_create(label))"))
        #expect(!renderer.contains("extension DatePicker: QtRenderable {\n    public func qtCreateWidget() -> OpaquePointer {\n        qtOpaque(quill_qt_bridge_label_create(title))"))
    }

    @Test("ImageRenderer comments describe the current GTK offscreen path")
    func imageRendererCommentsDescribeCurrentOffscreenPath() throws {
        let root = try packageRoot()
        let rendererSource = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Rendering/ImageRenderer.swift"),
            encoding: .utf8
        )
        let compatibilitySource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/Compatibility.swift"),
            encoding: .utf8
        )
        let gtkSource = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4ImageRenderer.swift"),
            encoding: .utf8
        )

        #expect(rendererSource.contains("ImageRendererBackend.installViewRenderer"))
        #expect(compatibilitySource.contains("let renderer = SwiftOpenUI.OpenUIImageRenderer(content: self)"))
        #expect(compatibilitySource.contains("if let data = renderer.platformImage?.data"))
        #expect(compatibilitySource.contains("let image = QuillPlatformImage(data: data)"))
        #expect(!compatibilitySource.contains("if let image = renderer.platformImage {\n            return image"))
        #expect(gtkSource.contains("gtk_widget_snapshot_child"))
        #expect(gtkSource.contains("cairo_surface_write_to_png_stream"))
        #expect(!rendererSource.contains("not yet wired up; see the TODO on `ImageRenderer`"))
    }

    @Test("Enchanted image export rewrite rules stay removed")
    func enchantedImageExportRewriteRulesStayRemoved() throws {
        let root = try packageRoot()
        let rules = root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules")

        #expect(!FileManager.default.fileExists(
            atPath: rules.appendingPathComponent("Extensions/View+Extension.swift.pl").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: rules.appendingPathComponent("Services/Clipboard.swift.pl").path
        ))
    }

    @Test("Enchanted composer rewrite expands before drawing border")
    func enchantedComposerRewriteExpandsBeforeDrawingBorder() throws {
        let root = try packageRoot()
        let inputFieldsRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/macOS/Chat/Components/InputFields_macOS.swift.pl"),
            encoding: .utf8
        )
        let profileLowering = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/lower-profile-source.sh"),
            encoding: .utf8
        )
        let controls = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/Controls.swift"),
            encoding: .utf8
        )
        let inputFieldsTemplate = root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/macOS/Chat/Components/InputFields_macOS.swift")

        #expect(inputFieldsRule.contains("import QuillUI"))
        #expect(inputFieldsRule.contains("var body: AnyView"))
        #expect(inputFieldsRule.contains("QuillChatComposer("))
        #expect(inputFieldsRule.contains("selectedImage: \\$selectedImage"))
        #expect(inputFieldsRule.contains("onStop: { onStopGenerateTap() }"))
        #expect(inputFieldsRule.contains("onSend: { sendMessage() }"))
        #expect(!profileLowering.contains("QuillChatComposer("))
        #expect(controls.contains("public struct QuillChatComposer: View"))
        #expect(controls.contains("@Binding public var selectedImage: Image?"))
        #expect(controls.contains("selectedImage: Binding<Image?>"))
        #expect(controls.contains("usesBuiltInImageSelection = true"))
        #expect(controls.contains(".frame(maxWidth: .infinity)"))
        #expect(controls.contains("RoundedRectangle(cornerRadius: 28)"))
        #expect(controls.contains(".fileImporter("))
        #expect(controls.contains(".onDrop(of: [.image]"))
        #expect(controls.contains("QuillFileImporter.selectURL(allowedContentTypes: [.png, .jpeg, .tiff])"))
        #expect(controls.contains("importBuiltInImageSelectionIfAvailableForSend()"))
        #expect(controls.contains("QUILLUI_FILE_IMPORTER_AUTO_ATTACH"))
        #expect(controls.contains("handleImageImport"))
        #expect(controls.contains("handleImageDrop"))
        #expect(controls.contains("private var composerTextField: some View"))
        #expect(controls.contains("#if os(Linux)\n        TextField(\"Message\", text: $message)"))
        #expect(controls.contains("#else\n        TextField(\"Message\", text: $message, axis: .vertical)"))
        #expect(controls.contains(".onSubmit"))
        #expect(controls.contains("submitIfPossible()"))
        #expect(controls.contains(".keyboardShortcut(.return, modifiers: [])"))
        #expect(!FileManager.default.fileExists(atPath: inputFieldsTemplate.path))
    }

    @Test("Enchanted composer rewrite replaces post-lowering split body")
    func enchantedComposerRewriteReplacesPostLoweringSplitBody() throws {
        let root = try packageRoot()
        let rule = root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/macOS/Chat/Components/InputFields_macOS.swift.pl")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillui-input-fields-rule-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fixture = tempDir.appendingPathComponent("InputFields_macOS.swift")
        try """
        @preconcurrency import SwiftUI
        import QuillShims
        struct InputFieldsView: View {
            @Binding var message: String
            var conversationState: ConversationState
            var onStopGenerateTap: @MainActor () -> Void
            var selectedModel: LanguageModelSD?
            @Binding private var selectedImage: Image?

            var body: some View {
                HStack {
                    _quillSplitBody0Part0
                }
            }

            @ViewBuilder
            private var _quillSplitBody0Part0: some View {
                Text("old composer")
            }
        }

        """.write(to: fixture, atomically: true, encoding: .utf8)

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["perl", "-0pi", rule.path, fixture.path]
        )
        #expect(result.status == 0)

        let rewritten = try String(contentsOf: fixture, encoding: .utf8)
        #expect(rewritten.contains("import QuillShims\nimport QuillUI"))
        #expect(rewritten.contains("var body: AnyView"))
        #expect(rewritten.contains("QuillChatComposer("))
        #expect(rewritten.contains("selectedImage: $selectedImage"))
        #expect(!rewritten.contains("_quillSplitBody0Part0"))
        #expect(!rewritten.contains("old composer"))
    }

    @Test("Apple service aliases live in reusable compatibility modules")
    func appleServiceAliasesLiveInReusableCompatibilityModules() throws {
        let root = try packageRoot()
        let quillKit = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillKit/QuillKit.swift"),
            encoding: .utf8
        )
        let quillUIProfileCompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/ProfileCompatibility.swift"),
            encoding: .utf8
        )
        let quillShims = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillShims/QuillShims.swift"),
            encoding: .utf8
        )
        let securityShim = try String(
            contentsOf: root.appendingPathComponent("Sources/Security/Security.swift"),
            encoding: .utf8
        )
        #expect(quillKit.contains("ProcessInfo.processInfo.environment[\"QUILLUI_ACCESSIBILITY_TRUSTED\"]"))
        #expect(quillKit.contains("return [\"1\", \"true\", \"yes\", \"on\"].contains(override.lowercased())"))
        #expect(quillKit.contains("return false\n        #else\n        return true"))
        let swiftUILowering = try String(
            contentsOf: root.appendingPathComponent("scripts/lower-swiftui-source-for-linux.sh"),
            encoding: .utf8
        )
        let enchantedProfileLowering = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/lower-profile-source.sh"),
            encoding: .utf8
        )
        let enchantedSpeechRecognizerProfile = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/Shared/Chat/Components/Recorder/SpeechRecogniser.swift.pl"),
            encoding: .utf8
        )
        let coreGraphics = try String(
            contentsOf: root.appendingPathComponent("Sources/CoreGraphics/CoreGraphics.swift"),
            encoding: .utf8
        )
        let enchantedEmptyFiles = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/empty-files.txt"),
            encoding: .utf8
        )
        let profileAliasesPath = root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/QuillGeneratedProfileAliases.swift")
        let profileAliases = (try? String(contentsOf: profileAliasesPath, encoding: .utf8)) ?? ""

        for alias in [
            "public typealias Accessibility = QuillAccessibilityService",
            "public typealias Clipboard = QuillClipboard",
            "public typealias KeyBase = QuillKeyBase",
            "public typealias HotkeyCombination = QuillHotkeyCombination",
            "public typealias FloatingPanel = QuillFloatingPanel",
            "public typealias PanelManager = QuillPanelManager",
            "public typealias QuillUpdater = QuillUpdateService",
            "public typealias QuillUSBWatcher = QuillDeviceWatcher",
            "public typealias HotkeyService = QuillHotkeyService"
        ] {
            #expect(quillKit.contains(alias))
            #expect(!profileAliases.contains(alias.replacingOccurrences(of: "public ", with: "")))
        }
        #expect(quillShims.contains("@_exported import QuillKit"))
        #expect(quillShims.contains("@_exported import CoreGraphics"))
        #expect(quillShims.contains("@_exported import AppKit"))
        #expect(quillShims.contains("@_exported import Combine"))
        #expect(!securityShim.contains("@_exported import QuillKit"))
        #expect(securityShim.contains("@_exported import typealias QuillKit.CFString"))
        #expect(securityShim.contains("Unmanaged<CoreFoundation.CFError>"))
        #expect(securityShim.contains("kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256"))
        #expect(securityShim.contains("static var rsaSignatureMessagePKCS1v15SHA256"))
        #expect(securityShim.contains("importedKeyAttributes(from:"))
        #expect(securityShim.contains("secKeySupportsRSASignature"))
        #expect(swiftUILowering.contains("ensure-swift-imports.sh\" \"$SOURCE_DIR\" QuillShims"))
        #expect(swiftUILowering.contains("run-quill-appkit-lower.sh\" \"$SOURCE_DIR\""))
        #expect(!swiftUILowering.contains(#"s/Task \{[ \t]*\@MainActor[ \t]+in/Task {/g;"#))
        #expect(!swiftUILowering.contains(#"s/Task \{[ \t]*\@MainActor[ \t]+(\[[^\]]+\][ \t]+in)/Task { $1/g;"#))
        #expect(!swiftUILowering.contains(#"s/^[ \t]*\@MainActor[ \t]*\n//gm;"#))
        #expect(!enchantedProfileLowering.contains("ensure-swift-imports.sh\" \"$LOWERED_COPY\" AppKit"))
        #expect(!enchantedProfileLowering.contains("ensure-swift-imports.sh\" \"$LOWERED_COPY\" SwiftUI"))
        #expect(!enchantedSpeechRecognizerProfile.contains(#"Task \{[ \t]*\@MainActor"#))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/__all__.pl").path
        ))
        #expect(quillKit.contains("quill-pasteboard"))
        #expect(quillKit.contains("Apple.NSGeneralPboard"))
        #expect(quillKit.contains("writeFileBackedPasteboardString(string, forType: type)"))
        #expect(coreGraphics.contains("static let kVK_ANSI_V: CGKeyCode = 0x09"))
        #expect(!profileAliases.contains("typealias CGKeyCode = UInt16"))
        #expect(!profileAliases.contains("static let kVK_ANSI_V"))
        #expect(quillUIProfileCompatibility.contains("public typealias CheckForUpdatesMenuItem = QuillCheckForUpdatesMenuItem"))
        #expect(quillKit.contains("public enum QuillUSBLauncher"))
        #expect(quillKit.contains("QuillDeviceLauncher.install(label: label, subsystem: subsystem)"))
        #expect(!FileManager.default.fileExists(atPath: profileAliasesPath.path))
        #expect(!profileAliases.contains("typealias CheckForUpdatesMenuItem"))
        #expect(!profileAliases.contains("enum QuillUSBLauncher"))
        #expect(enchantedEmptyFiles.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!enchantedEmptyFiles.contains("Helpers/Accessibility.swift"))
        #expect(!enchantedEmptyFiles.contains("Helpers/HotKeys.swift"))
        #expect(!enchantedEmptyFiles.contains("Services/HotkeyService.swift"))
        #expect(!enchantedEmptyFiles.contains("UI/macOS/PromptPanel/FloatingPanel.swift"))
        #expect(!enchantedEmptyFiles.contains("UI/macOS/PromptPanel/PanelManager.swift"))
        #expect(!enchantedEmptyFiles.contains("Application/QuillUpdater.swift"))
        #expect(!enchantedEmptyFiles.contains("Application/QuillUSBWatcher.swift"))
        #expect(!enchantedEmptyFiles.contains("Application/QuillUSBLauncher.swift"))
    }

    @Test("CloudKit shim documents OpenCloudKit provider boundary")
    func cloudKitShimDocumentsOpenCloudKitProviderBoundary() throws {
        let manifest = try packageSource("Package.swift")
        let cloudKit = try packageSource("Sources/AppleFrameworkShims/CloudKit/CloudKit.swift")
        let apiMatrix = try packageSource("docs/api-coverage-matrix.md")
        let packageCoverage = try packageSource("docs/apple-package-function-coverage.md")
        let repositoryBoundaries = try packageSource("docs/repository-boundaries.md")
        let netNewsWireAudit = try packageSource("docs/netnewswire-audit.md")

        #expect(manifest.contains(".library(name: \"CloudKit\", targets: [\"CloudKit\"])"))
        #expect(manifest.contains("\"UserNotifications\", \"SystemConfiguration\", \"CloudKit\", \"StoreKit\", \"NaturalLanguage\""))
        #expect(manifest.contains(".target(name: \"CloudKit\", dependencies: [\"QuillFoundation\", \"QuillKit\"], path: \"Sources/AppleFrameworkShims/CloudKit\")"))
        #expect(cloudKit.contains("public enum QuillCloudKitCompatibility"))
        #expect(cloudKit.contains("https://github.com/cocologics/OpenCloudKit"))
        #expect(cloudKit.contains("public final class CKContainer"))
        #expect(cloudKit.contains("public final class CKDatabase"))
        #expect(cloudKit.contains("public final class CKRecord"))
        #expect(cloudKit.contains("QuillCompatibilityDiagnostics.shared.record"))
        #expect(apiMatrix.contains("OpenCloudKit"))
        #expect(packageCoverage.contains("OpenCloudKit"))
        #expect(repositoryBoundaries.contains("OpenCloudKit"))
        #expect(netNewsWireAudit.contains("OpenCloudKit"))
    }

    @Test("Linux controls read backend-scoped reference environment")
    func linuxControlsReadBackendScopedReferenceEnvironment() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/Controls.swift"),
            encoding: .utf8
        )

        #expect(source.contains("QuillBackendRegistry\n        .backendScopedEnvironmentValue("))
        #expect(source.contains("preferred: QuillBackendRuntimeContext.selectedBackend"))
        #expect(source.contains("gtkLegacy: \"QUILLUI_GTK_DEFAULT_WINDOW_WIDTH\""))
        #expect(source.contains("qtScoped: \"QUILLUI_QT_DEFAULT_WINDOW_WIDTH\""))
        #expect(source.contains("gtkLegacy: \"QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT\""))
        #expect(source.contains("qtScoped: \"QUILLUI_QT_DEFAULT_WINDOW_HEIGHT\""))
        #expect(!source.contains("legacy: \"QUILLUI_GTK_DEFAULT_WINDOW_WIDTH\""))
    }

    @Test("Public docs describe the backend-neutral app matrix")
    func publicDocsDescribeBackendNeutralAppMatrix() throws {
        let root = try packageRoot()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let appTargets = try String(contentsOf: root.appendingPathComponent("docs/app-targets.md"), encoding: .utf8)
        let uiTestPlan = try String(contentsOf: root.appendingPathComponent("docs/uitest-plan.md"), encoding: .utf8)
        let linuxBuildTooling = try String(
            contentsOf: root.appendingPathComponent("docs/linux-build-tooling.md"),
            encoding: .utf8
        )
        let profileBaseline = try String(
            contentsOf: root.appendingPathComponent("docs/profile-baseline.md"),
            encoding: .utf8
        )
        let offscreenRenderer = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/GtkOffscreenRender.swift"),
            encoding: .utf8
        )

        #expect(readme.contains("QuillUIGtk"))
        #expect(readme.contains("QuillUIQt"))
        #expect(readme.contains("QUILLUI_LINUX_BACKEND=qt swift run quill-wireguard"))
        #expect(readme.contains("QuillChatKit"))
        #expect(readme.contains("quill-wireguard"))
        #expect(readme.contains("scripts/quillui-backend-products.sh app-matrix"))
        #expect(readme.contains("interaction interaction-matrix"))
        #expect(readme.contains("scripts/linux-backend-check.sh"))
        #expect(!readme.contains("The first target app"))
        #expect(!readme.contains("scripts/linux-gtk-check.sh"))

        #expect(appTargets.contains("backend-renders end-to-end on Linux"))
        #expect(appTargets.contains("explicit Qt manifest graph"))
        #expect(appTargets.contains("dedicated Enchanted Qt native host"))
        #expect(!appTargets.contains("generic Qt native host while the full SwiftUI tree remains on the GTK path"))
        #expect(!appTargets.contains("GTK-renders end-to-end"))

        #expect(uiTestPlan.contains("Linux backend smoke"))
        #expect(uiTestPlan.contains("requested Linux backend matrix"))
        #expect(uiTestPlan.contains("backend-selected window"))
        #expect(uiTestPlan.contains("through the Linux backend matrix"))
        #expect(uiTestPlan.contains("canonical app product names"))
        #expect(uiTestPlan.contains("native Qt visual/selection smoke"))
        #expect(uiTestPlan.contains("first semantic native app interaction pair"))
        #expect(uiTestPlan.contains("GTK and Qt both have `import-paste` and `import-file`"))
        #expect(uiTestPlan.contains("GTK import modes assert the selected-row highlight moves"))
        #expect(uiTestPlan.contains("through the GTK fallback screenshot predicate"))
        #expect(!uiTestPlan.contains("Linux GTK smoke"))
        #expect(!uiTestPlan.contains("Screenshots the GTK window"))
        #expect(!uiTestPlan.contains("renders identically on Linux GTK"))

        #expect(linuxBuildTooling.contains("QUILLUI_BACKEND_LAYOUT_DEBUG"))
        #expect(linuxBuildTooling.contains("layout diagnostics behave the same across every runner"))
        #expect(linuxBuildTooling.contains("Canonical app products compile through the explicit backend selector"))
        #expect(linuxBuildTooling.contains("native-product-runtime-overrides"))
        #expect(linuxBuildTooling.contains("scripts/build-linux-backend-products.sh --scratch-path .build-linux backend-apps"))
        #expect(linuxBuildTooling.contains("scripts/build-linux-backend-products.sh --scratch-path .build-linux all-app-backends"))
        #expect(linuxBuildTooling.contains("--package-root"))
        #expect(linuxBuildTooling.contains("--entry-target"))
        #expect(linuxBuildTooling.contains("--target-layout-file"))
        #expect(linuxBuildTooling.contains("--extra-package-dependencies-file"))
        #expect(linuxBuildTooling.contains("scripts/swiftpm-package-layout-for-linux.py"))
        #expect(linuxBuildTooling.contains("derive the target"))
        #expect(linuxBuildTooling.contains("layout automatically from `Package.swift`"))
        #expect(linuxBuildTooling.contains("multi-target SwiftPM app trees"))
        #expect(linuxBuildTooling.contains("PRODUCT<TAB>BUILD_BACKEND"))
        #expect(linuxBuildTooling.contains("backend build stamps"))
        #expect(linuxBuildTooling.contains("stricter Linux build-backend normalizer"))
        #expect(linuxBuildTooling.contains("explicit positional backend argument"))
        #expect(linuxBuildTooling.contains("The GTK WireGuard host uses the same semantic modes"))
        #expect(linuxBuildTooling.contains("scripts/run-linux-backend-smoke-matrix.sh"))
        #expect(linuxBuildTooling.contains("--skip-repeated-products"))
        #expect(linuxBuildTooling.contains("generated-app-matrix"))
        #expect(linuxBuildTooling.contains("interaction-matrix"))
        #expect(linuxBuildTooling.contains("smoke-matrix"))
        #expect(linuxBuildTooling.contains("smoke-interaction-matrix"))
        #expect(linuxBuildTooling.contains("'.qa/{product}-generated-{backend}.png'"))
        #expect(linuxBuildTooling.contains("'.qa/{product}-{mode}-{backend}.png'"))
        #expect(linuxBuildTooling.contains("'.qa/{product}-{backend}.png'"))
        #expect(linuxBuildTooling.contains("'.qa/{product}-interaction-{backend}.png'"))
        #expect(linuxBuildTooling.contains("'.qa/{product}-toolbar-menu-{backend}.png'"))
        #expect(linuxBuildTooling.contains("`PRODUCT<TAB>BACKEND` rows"))
        #expect(linuxBuildTooling.contains("canonicalizes backend aliases"))
        #expect(!linuxBuildTooling.contains("QUILLUI_BACKEND=\"$backend\" scripts/linux-backend-visual-check.sh"))
        #expect(!linuxBuildTooling.contains("QUILLUI_BACKEND=\"$backend\" QUILLUI_BACKEND_SKIP_BUILD=1"))
        #expect(linuxBuildTooling.contains("backend-apps"))
        #expect(linuxBuildTooling.contains("all-app-backends"))

        #expect(profileBaseline.contains("`PRODUCT<TAB>BACKEND` rows"))
        #expect(profileBaseline.contains("canonicalized before launch"))
        #expect(profileBaseline.contains("`requested_backend`, `runtime_backend`, and"))
        #expect(profileBaseline.contains("`runtime_backend=qt`"))
        #expect(profileBaseline.contains("`runtime_mode=native`"))
        #expect(profileBaseline.contains("scripts/linux-backend-profile.sh <product> [settle] [steady] [backend]"))
        #expect(!profileBaseline.contains("scripts/linux-backend-profile.sh <product> [settle] [steady]`:"))
        #expect(linuxBuildTooling.contains("`runtime_mode` columns"))
        #expect(linuxBuildTooling.contains("shared generic Qt native rows"))
        #expect(!linuxBuildTooling.contains("generic Qt fallback rows"))

        #expect(offscreenRenderer.contains("scripts/linux-backend-check.sh"))
        #expect(!offscreenRenderer.contains("scripts/linux-gtk-check.sh"))
    }

    @Test("GitHub workflows avoid Node 20 action pins")
    func githubWorkflowsAvoidNode20ActionPins() throws {
        let root = try packageRoot()
        let workflowPaths = [
            ".github/workflows/linux-ci.yml",
            ".github/workflows/macos-ci.yml",
            ".github/workflows/enchanted-parity.yml",
            ".github/workflows/solderscope-ci.yml"
        ]

        let workflows = try workflowPaths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        let shellSyntaxCheck = try String(
            contentsOf: root.appendingPathComponent("scripts/check-shell-syntax.sh"),
            encoding: .utf8
        )
        let upstreamCacheAction = try String(
            contentsOf: root.appendingPathComponent(".github/actions/upstream-cache/action.yml"),
            encoding: .utf8
        )
        let loweredSourceCacheAction = try String(
            contentsOf: root.appendingPathComponent(".github/actions/lowered-source-cache/action.yml"),
            encoding: .utf8
        )
        let upstreamFetch = try String(
            contentsOf: root.appendingPathComponent("scripts/fetch-upstream.sh"),
            encoding: .utf8
        )

        #expect(workflows.contains("uses: actions/checkout@v5"))
        #expect(workflows.contains("uses: actions/upload-artifact@v6"))
        #expect(workflows.contains("uses: ./.github/actions/upstream-cache"))
        #expect(workflows.contains("uses: ./.github/actions/lowered-source-cache"))
        #expect(workflows.contains("QUILLUI_TRUST_UPSTREAM_CACHE: \"1\""))
        #expect(workflows.contains("scripts/check-shell-syntax.sh"))
        #expect(shellSyntaxCheck.contains("find scripts -type f -name '*.sh' | sort"))
        #expect(shellSyntaxCheck.contains("bash -n \"$script\""))
        #expect(upstreamCacheAction.contains("uses: actions/cache@v6"))
        #expect(upstreamCacheAction.contains("path: .upstream"))
        #expect(upstreamCacheAction.contains("scripts/fetch-upstream.sh"))
        #expect(upstreamCacheAction.contains("restore-keys:"))
        #expect(loweredSourceCacheAction.contains("uses: actions/cache@v6"))
        #expect(loweredSourceCacheAction.contains("path: .build/quillui-lowered-source-cache"))
        #expect(loweredSourceCacheAction.contains("source-app:"))
        #expect(loweredSourceCacheAction.contains("source_paths=(vendor/apps)"))
        #expect(loweredSourceCacheAction.contains("source_paths=(\"vendor/apps/$source_app\")"))
        #expect(loweredSourceCacheAction.contains("git -c 'safe.directory=*' ls-files -s"))
        #expect(loweredSourceCacheAction.contains("quillui-${{ runner.os }}-lowered-source-${{ inputs.cache-name }}-"))
        #expect(loweredSourceCacheAction.contains("scripts/quillui-source-cache-key.py"))
        #expect(loweredSourceCacheAction.contains("scripts/swiftpm-profile-lowered-source-cache.sh"))
        #expect(loweredSourceCacheAction.contains("Sources/QuillSourceLowering"))
        #expect(loweredSourceCacheAction.contains("vendor/apps"))
        #expect(loweredSourceCacheAction.contains("restore-keys:"))
        #expect(upstreamFetch.contains("QUILLUI_TRUST_UPSTREAM_CACHE=1"))
        #expect(upstreamFetch.contains("using cached $name"))
        #expect(upstreamFetch.contains("reset_repo_to_commit"))
        #expect(upstreamFetch.contains("want=(enchanted netnewswire wireguard icecubes solderscope)"))
        #expect(!workflows.contains("uses: actions/checkout@v4"))
        #expect(!workflows.contains("uses: actions/upload-artifact@v4"))
        #expect(!workflows.contains("uses: actions/upload-artifact@v5"))
        #expect(!workflows.contains("uses: actions/cache@v4"))
        #expect(!workflows.contains("uses: actions/cache@v5"))
    }

    @Test("App entry points use the shared Quill window scene")
    func appEntryPointsUseSharedQuillWindowScene() throws {
        let root = try packageRoot()
        let helperSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/QuillApp.swift"),
            encoding: .utf8
        )
        let backendSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/QuillBackend.swift"),
            encoding: .utf8
        )
        let wireGuardUISource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillWireGuardUI/QuillWireGuardUI.swift"),
            encoding: .utf8
        )
        let appEntryPointPaths = [
            "Sources/QuillSignal/main.swift",
            "Sources/QuillTelegram/main.swift",
            "Sources/QuillIINA/main.swift",
            "Sources/QuillCodeEdit/main.swift",
            "Sources/QuillNetNewsWire/main.swift",
            "Sources/QuillIceCubes/main.swift",
            "Sources/QuillWireGuard/main.swift"
        ]
        let appLauncherPaths = [
            "Sources/QuillSignal/main.swift": "QuillApp.run(QuillSignalApp.self)",
            "Sources/QuillTelegram/main.swift": "QuillApp.run(QuillTelegramApp.self)",
            "Sources/QuillIINA/main.swift": "QuillApp.run(QuillIINAApp.self)",
            "Sources/QuillCodeEdit/main.swift": "QuillApp.run(QuillCodeEditApp.self)",
            "Sources/QuillNetNewsWire/main.swift": "QuillApp.run(QuillNetNewsWireApp.self)",
            "Sources/QuillIceCubes/main.swift": "QuillApp.run(QuillIceCubesApp.self)",
            "Sources/QuillWireGuard/main.swift": "QuillApp.run(QuillWireGuardApp.self)"
        ]
        let qtAppLauncherPaths = [
            "Sources/QuillWireGuardQt/main.swift": "QuillQtApp.run(QuillWireGuardQtApp.self)"
        ]
        let sharedSceneEntryPoints = [
            "Sources/QuillWireGuard/main.swift": "QuillWireGuardScene.scene()",
            "Sources/QuillWireGuardQt/main.swift": "QuillWireGuardScene.scene()"
        ]
        let backendSmokeEntryPointPaths = [
            "Sources/QuillGtkInteractionSmoke/main.swift": "QuillBackendInteractionSmokeApp<QuillGtkBackend>",
            "Sources/QuillQtInteractionSmoke/main.swift": "QuillBackendInteractionSmokeApp<QuillQtBackend>"
        ]

        #expect(helperSource.contains("public enum QuillAppWindow"))
        #expect(helperSource.contains("public enum QuillAppDefaultSizePolicy"))
        #expect(helperSource.contains("case requested"))
        #expect(helperSource.contains("case linuxAppMinimum"))
        #expect(helperSource.contains("case linuxMinimum(width: Double, height: Double)"))
        #expect(helperSource.contains("public enum QuillBackendApp<Backend: QuillBackend>"))
        #expect(helperSource.contains("QuillBackendRegistry.launchPlan(preferred: preferredBackend)"))
        #expect(helperSource.contains("private struct QuillUncheckedSendableAppType<A: App>: @unchecked Sendable"))
        #expect(helperSource.contains("let appTypeBox = QuillUncheckedSendableAppType(appType: appType)"))
        #expect(helperSource.contains("QuillBackendRuntimeContext.install(launchPlan)"))
        #expect(helperSource.contains("struct QuillLinuxRuntimeHostDescriptor: Equatable, Sendable"))
        #expect(helperSource.contains("enum QuillLinuxRuntimeHost: CaseIterable"))
        #expect(helperSource.contains("case qt6"))
        #expect(helperSource.contains("static let linkedHosts: [QuillLinuxRuntimeHost] = [.gtk4]"))
        #expect(helperSource.contains("static var knownHosts: [QuillLinuxRuntimeHost]"))
        #expect(helperSource.contains("static var knownDescriptors: [QuillLinuxRuntimeHostDescriptor]"))
        #expect(helperSource.contains("static var linkedDescriptors: [QuillLinuxRuntimeHostDescriptor]"))
        #expect(helperSource.contains("static var descriptors: [QuillLinuxRuntimeHostDescriptor]"))
        #expect(helperSource.contains("static var supportedBackends: [QuillBackendIdentifier]"))
        #expect(helperSource.contains("linkedDescriptors.map(\\.backend)"))
        #expect(helperSource.contains("static var platformFallbackBackend: QuillBackendIdentifier"))
        #expect(helperSource.contains("static func descriptor("))
        #expect(helperSource.contains("static func knownDescriptor("))
        #expect(helperSource.contains("init(launchPlan: QuillBackendLaunchPlan)"))
        #expect(helperSource.contains("displayName: \"GTK4\""))
        #expect(helperSource.contains("displayName: \"Qt6\""))
        #expect(helperSource.contains("Native Qt6 Linux runtime host is declared but not linked."))
        #expect(helperSource.contains("No Linux runtime host is linked for"))
        #expect(helperSource.contains("QuillLinuxAppRuntime.run(appTypeBox.appType, launchPlan: launchPlan)"))
        #expect(helperSource.contains("QuillLinuxRuntimeHost(launchPlan: launchPlan).run(appType)"))
        #expect(helperSource.contains("QuillMainActorView.assumeIsolated"))
        #expect(helperSource.contains("defaultSizePolicy: QuillAppDefaultSizePolicy = .linuxAppMinimum"))
        #expect(helperSource.contains("policy: defaultSizePolicy"))
        #expect(helperSource.contains(".defaultSize(width: defaultSize.width, height: defaultSize.height)"))
        #expect(helperSource.contains("return (max(width, 900), max(height, 600))"))
        #expect(helperSource.contains("return (max(width, minimumWidth), max(height, minimumHeight))"))
        #expect(helperSource.contains("entry point"))
        #expect(helperSource.contains("launch-plan fallback"))
        #expect(!helperSource.contains("block six times"))
        #expect(backendSource.contains("return QuillLinuxRuntimeHost.supportedBackends"))
        #expect(backendSource.contains("return QuillLinuxRuntimeHost.platformFallbackBackend"))
        #expect(!backendSource.contains("return [.gtk]"))
        #expect(wireGuardUISource.contains("public enum QuillWireGuardScene"))
        #expect(wireGuardUISource.contains("QuillAppWindow.scene("))
        #expect(wireGuardUISource.contains("defaultSizePolicy: .linuxMinimum(width: minimumWidth, height: minimumHeight)"))

        for path in appEntryPointPaths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)

            if let sharedScene = sharedSceneEntryPoints[path] {
                #expect(source.contains(sharedScene), "\(path) should use the shared WireGuard scene")
            } else {
                #expect(source.contains("QuillAppWindow.scene("), "\(path) should use the shared scene helper")
            }
            #expect(!source.contains("WindowGroup("), "\(path) should not hand-roll WindowGroup setup")
            #expect(!source.contains(".defaultWindowSize("), "\(path) should not branch into Linux-only sizing")
            #expect(!source.contains(".defaultSize("), "\(path) should let QuillAppWindow own default sizing")
        }

        for (path, launcher) in appLauncherPaths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)

            #expect(source.contains(launcher), "\(path) should launch through QuillApp.run")
            #expect(!source.contains("GTK4Backend().run"), "\(path) should not call the GTK runtime directly")
            #expect(!source.contains("import BackendGTK4"), "\(path) should not import a backend implementation")
            #expect(!source.contains("import QuillUIGtk"), "\(path) should not import a backend facade")
            #expect(!source.contains("import QuillUIQt"), "\(path) should not import a backend facade")
        }

        for (path, launcher) in qtAppLauncherPaths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            let sharedScene = try #require(sharedSceneEntryPoints[path])

            #expect(source.contains(launcher), "\(path) should launch through QuillQtApp.run")
            #expect(source.contains("import QuillUIQt"), "\(path) should import the Qt backend facade")
            #expect(source.contains(sharedScene), "\(path) should reuse the shared WireGuard scene")
            #expect(!source.contains("WindowGroup("), "\(path) should not hand-roll WindowGroup setup")
            #expect(!source.contains(".defaultWindowSize("), "\(path) should not branch into Linux-only sizing")
            #expect(!source.contains(".defaultSize("), "\(path) should let QuillAppWindow own default sizing")
        }

        for (path, appType) in backendSmokeEntryPointPaths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)

            #expect(source.contains(appType), "\(path) should use the shared generic interaction smoke app")
            #expect(!source.contains("WindowGroup("), "\(path) should not hand-roll WindowGroup setup")
            #expect(!source.contains(".defaultWindowSize("), "\(path) should not branch into Linux-only sizing")
            #expect(!source.contains(".defaultSize("), "\(path) should let QuillInteractionSmokeScene own default sizing")
        }
    }

    @Test("Linux interaction smoke targets share one view surface")
    func linuxInteractionSmokeTargetsShareOneViewSurface() throws {
        let manifest = try packageSource("Package.swift")
        let gtkMain = try packageSource("Sources/QuillGtkInteractionSmoke/main.swift")
        let qtMain = try packageSource("Sources/QuillQtInteractionSmoke/main.swift")
        let sharedView = try packageSource("Sources/QuillInteractionSmokeSupport/QuillInteractionSmokeView.swift")
        let enchantedConversationStore = try packageSource("Sources/QuillEnchantedData/QuillDataConversationStore.swift")
        let wireGuardQtHost = try packageSource("Sources/CQuillQt6WidgetsShim/QuillWireGuardQt6Widgets.cpp")
        let qtRuntimeSupport = try packageSource("Sources/QuillQtNativeRuntimeSupport/QuillQtNativeRuntimeSupport.swift")
        let qtNativeSmokeHost = try packageSource("Sources/CQuillQt6WidgetsShim/QuillInteractionSmokeQt6Widgets.cpp")
        let qtNativeWidgetSupport = try packageSource("Sources/CQuillQt6WidgetsShim/QuillQtWidgetsSupport.hpp")

        #expect(manifest.contains(".library(name: \"QuillUIGtk\", targets: [\"QuillUIGtk\"])"))
        #expect(manifest.contains(".library(name: \"QuillUIQt\", targets: [\"QuillUIQt\"])"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .gtk {"))
        #expect(manifest.contains("products.append(.executable(name: \"quill-gtk-interaction-smoke\", targets: [\"QuillGtkInteractionSmoke\"]))"))
        #expect(manifest.contains(".executable(name: \"quill-qt-interaction-smoke\", targets: [\"QuillQtInteractionSmoke\"])"))
        #expect(manifest.contains("name: \"QuillInteractionSmokeSupport\""))
        #expect(manifest.contains("dependencies: [\"QuillUIGtk\", \"QuillInteractionSmokeSupport\"]"))
        #expect(manifest.contains("func quillLinuxBackendDependencies("))
        #expect(manifest.contains("name: \"QuillEnchantedData\""))
        #expect(manifest.contains("path: \"Sources/QuillEnchantedData\""))
        #expect(manifest.contains("dependencies: [\"QuillData\"]"))
        #expect(manifest.contains("dependencies: [\"QuillEnchantedData\", \"QuillFoundation\"]"))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(manifest.contains("nativeQt: [\"QuillWireGuardQtNativeRuntime\"]"))
        #expect(manifest.contains("dependencies: [\"CQuillQt6WidgetsShim\"]"))
        #expect(!manifest.contains("fallback: [\"QuillUIQt\", \"QuillInteractionSmokeSupport\"]"))
        #expect(!manifest.contains("dependencies: quillQtInteractionSmokeDependencies"))
        #expect(!manifest.contains("dependencies: [\"QuillUI\", \"QuillUIGtk\", \"QuillInteractionSmokeSupport\"]"))
        #expect(!manifest.contains("dependencies: [\"QuillUI\", \"QuillUIQt\", \"QuillInteractionSmokeSupport\"]"))
        #expect(sharedView.contains("import Foundation"))
        #expect(enchantedConversationStore.contains("let home = environment[\"QUILLDATA_HOME\"] ?? environment[\"HOME\"]"))
        #expect(enchantedConversationStore.contains("URL(fileURLWithPath: $0, isDirectory: true)"))

        #expect(gtkMain.contains("import QuillInteractionSmokeSupport"))
        #expect(gtkMain.contains("import QuillUIGtk"))
        #expect(!gtkMain.contains("import QuillUI\n"))
        #expect(gtkMain.contains("private typealias QuillGtkInteractionSmokeApp = QuillBackendInteractionSmokeApp<QuillGtkBackend>"))
        #expect(gtkMain.contains("QuillGtkApp.run(QuillGtkInteractionSmokeApp.self)"))
        #expect(!gtkMain.contains("QuillInteractionSmokeScene.scene(for: .gtk)"))
        #expect(!gtkMain.contains("Quill GTK Interaction"))
        #expect(!gtkMain.contains("Native GTK click target"))
        #expect(!gtkMain.contains("struct SmokeView"))

        #expect(qtMain.contains("import QuillInteractionSmokeSupport"))
        #expect(qtMain.contains("import QuillUIQt"))
        #expect(qtMain.contains("import CQuillQt6WidgetsShim"))
        #expect(qtMain.contains("quill_qt_run_interaction_smoke"))
        #expect(!qtMain.contains("import QuillUI\n"))
        #expect(qtMain.contains("private typealias QuillQtInteractionSmokeApp = QuillBackendInteractionSmokeApp<QuillQtBackend>"))
        #expect(qtMain.contains("QuillQtApp.run(QuillQtInteractionSmokeApp.self)"))
        #expect(!qtMain.contains("QuillInteractionSmokeScene.scene(for: .qt)"))
        #expect(!qtMain.contains("Quill Qt Interaction"))
        #expect(!qtMain.contains("Native Qt click target"))
        #expect(!qtMain.contains("struct SmokeView"))
        #expect(qtNativeSmokeHost.contains("int quill_qt_run_interaction_smoke"))
        #expect(qtNativeSmokeHost.contains("Native Qt opened this dialog from the backend interaction fixture."))
        #expect(wireGuardQtHost.contains("int quill_wireguard_qt_run_wireguard_json"))
        #expect(!wireGuardQtHost.contains("quill_qt_run_interaction_smoke"))
        #expect(!wireGuardQtHost.contains("interactionSmoke"))
        #expect(qtRuntimeSupport.contains("public static func boundedIndexOverride(environmentKey: String, count: Int) -> Int?"))
        #expect(qtRuntimeSupport.contains("public static func boundedIndexOverride(environmentKeys: [String], count: Int) -> Int?"))
        #expect(qtRuntimeSupport.contains("ProcessInfo.processInfo.environment[environmentKey]"))
        #expect(qtRuntimeSupport.contains("public static func boundedIndexOverride(_ value: String?, count: Int) -> Int?"))
        #expect(qtRuntimeSupport.contains("public static func executableName(arguments: [String] = CommandLine.arguments, fallback: String) -> String"))
        #expect(qtRuntimeSupport.contains("URL(fileURLWithPath: rawExecutablePath).lastPathComponent"))
        #expect(qtRuntimeSupport.contains("public static func encodedPayloadString<Payload: Encodable>"))
        #expect(qtRuntimeSupport.contains("public static func runEncodedPayload<Payload: Encodable>"))
        #expect(qtRuntimeSupport.contains("encoder.outputFormatting = [.sortedKeys]"))
        #expect(qtRuntimeSupport.contains("fputs(\"\\(executableName): failed to encode Qt payload: \\(error)\\n\", stderr)"))
        #expect(qtNativeWidgetSupport.contains("inline bool parseJsonObjectPayload("))
        #expect(qtNativeWidgetSupport.contains("inline bool jsonBoolValue("))
        #expect(qtNativeWidgetSupport.contains("inline QByteArray executableNameBytes("))
        #expect(qtNativeWidgetSupport.contains("QString::fromLocal8Bit(argv[0]).trimmed()"))
        #expect(qtNativeWidgetSupport.contains("inline QSize minimumWindowSize("))
        #expect(qtNativeWidgetSupport.contains("inline QSize defaultWindowSize("))
        #expect(qtNativeWidgetSupport.contains("%s: missing payload JSON\\n"))
        #expect(qtNativeWidgetSupport.contains("%s: invalid payload JSON at offset %lld: %s\\n"))
    }

    @Test("Enchanted Qt runtime mirrors the macOS payload contract")
    func enchantedQtRuntimeMirrorsMacOSPayloadContract() throws {
        let enchantedDataModels = try packageSource("Sources/QuillEnchantedData/Models.swift")
        let enchantedShared = try packageSource("Sources/QuillEnchantedShared/QuillEnchantedShared.swift")
        // Obsolete: QuillEnchantedQtNativeRuntime was deleted (reimpl retirement, epic
        // #188 #26). Removed in PR-C; skip here so PR-A is green.
        guard let enchantedQtRuntime = try? packageSource("Sources/QuillEnchantedQtNativeRuntime/QuillEnchantedQtNativeRuntime.swift") else { return }

        #expect(enchantedQtRuntime.contains("import QuillEnchantedData"))
        #expect(enchantedQtRuntime.contains("import QuillEnchantedShared"))
        #expect(enchantedQtRuntime.contains("import QuillQtNativeRuntimeSupport"))
        #expect(enchantedQtRuntime.contains("EnchantedModelContext.default()"))
        #expect(enchantedQtRuntime.contains("QuillEnchantedQtSnapshot.persisted("))
        #expect(enchantedQtRuntime.contains("quill_enchanted_qt_perform_action_json"))
        #expect(enchantedQtRuntime.contains("quill_enchanted_qt_free_string"))
        #expect(enchantedQtRuntime.contains("context.insert(ConversationDraft(title: EnchantedCopy.newConversationTitle))"))
        #expect(enchantedQtRuntime.contains("context.deleteConversation(id: conversationID)"))
        #expect(enchantedQtRuntime.contains("context.deleteAllConversations()"))
        #expect(enchantedQtRuntime.contains("var messageText: String?"))
        #expect(enchantedQtRuntime.contains("var endpoint: String?"))
        #expect(enchantedQtRuntime.contains("var selectedModel: String?"))
        #expect(enchantedQtRuntime.contains("var models: [String]?"))
        #expect(enchantedQtRuntime.contains("var attachmentPaths: [String]?"))
        #expect(enchantedQtRuntime.contains("var selectedModelSupportsImages: Bool"))
        #expect(enchantedQtRuntime.contains("selectedModelSupportsImages: EnchantedPreviewFixture.selectedModel.quillLikelySupportsImages"))
        #expect(enchantedQtRuntime.contains("snapshot.selectedModelSupportsImages = snapshot.models.contains(snapshot.selectedModel) && snapshot.selectedModel.quillLikelySupportsImages"))
        #expect(enchantedQtRuntime.contains("let selectedModelAllowsAttachments = models.contains(effectiveSelectedModel) && effectiveSelectedModel.quillLikelySupportsImages"))
        #expect(enchantedQtRuntime.contains("let attachments = selectedModelAllowsAttachments ? try imageAttachments(from: request.attachmentPaths ?? []) : []"))
        #expect(enchantedDataModels.contains("var quillLikelySupportsImages: Bool"))
        #expect(enchantedQtRuntime.contains("case \"sendMessage\":"))
        #expect(enchantedQtRuntime.contains("case \"refreshModels\", \"configureEndpoint\":"))
        #expect(enchantedQtRuntime.contains("case \"selectModel\":"))
        #expect(enchantedQtRuntime.contains("OllamaClient(baseURL: endpoint).fetchModels()"))
        #expect(enchantedQtRuntime.contains("context.updateConversationTitle(id: selectedConversationID, title: prompt.quillTitle())"))
        #expect(enchantedQtRuntime.contains("var selectedConversationID = try existingConversationID(request.conversationID, context: context)"))
        #expect(enchantedQtRuntime.occurrences(of: "existingConversationID(request.conversationID, context: context)") == 1)
        #expect(enchantedQtRuntime.contains("selectedConversationID: selectedConversationID,"))
        #expect(!enchantedQtRuntime.contains("selectedConversationID: existingConversationID(request.conversationID, context: context),"))
        #expect(enchantedQtRuntime.contains("let displayContent = PendingImageAttachment.displayContent(prompt: prompt, attachments: attachments)"))
        #expect(enchantedQtRuntime.contains("content: displayContent"))
        #expect(enchantedQtRuntime.contains("imagesForLastUserMessage: encodedImages"))
        #expect(enchantedQtRuntime.contains("private static func imageAttachments(from rawPaths: [String]) throws -> [PendingImageAttachment]"))
        #expect(enchantedQtRuntime.contains("sidebarSubtitle: EnchantedCopy.sidebarSubtitle"))
        #expect(enchantedQtRuntime.contains("noModelsTitle: EnchantedCopy.noModelsTitle"))
        #expect(enchantedQtRuntime.contains("newConversationButtonTitle: EnchantedCopy.newChatTitle"))
        #expect(!enchantedQtRuntime.contains("newChatTitle: EnchantedCopy.newChatTitle"))
        #expect(enchantedQtRuntime.contains("self.lastMessage = summary.lastMessage"))
        #expect(!enchantedQtRuntime.contains("noMessagesYet: EnchantedCopy.noMessagesYet"))
        #expect(!enchantedQtRuntime.contains("summary.lastMessage.isEmpty ? EnchantedCopy.noMessagesYet : summary.lastMessage"))
        #expect(enchantedQtRuntime.contains("attachTitle: EnchantedCopy.attachTitle"))
        #expect(enchantedQtRuntime.contains("clearAttachmentsTitle: EnchantedCopy.clearAttachmentsTitle"))
        #expect(enchantedQtRuntime.contains("attachmentsClearedStatus: EnchantedCopy.attachmentsClearedStatus"))
        #expect(enchantedQtRuntime.contains("attachmentRemovedEmptyStatus: EnchantedCopy.attachmentRemovedEmptyStatus"))
        #expect(!enchantedQtRuntime.contains("attachmentRemovedEmptyStatus: EnchantedCopy.readyStatus"))
        #expect(enchantedQtRuntime.contains("attachmentsTitle: EnchantedCopy.attachmentsTitle"))
        #expect(enchantedQtRuntime.contains("attachmentDefaultPrompt: EnchantedCopy.attachmentDefaultPrompt"))
        #expect(enchantedQtRuntime.contains("attachmentDefaultPromptPlural: EnchantedCopy.attachmentDefaultPromptPlural"))
        #expect(enchantedQtRuntime.contains("attachmentSummaryTitle: EnchantedCopy.attachmentSummaryTitle"))
        #expect(enchantedQtRuntime.contains("attachmentMaxByteCount: PendingImageAttachment.maxByteCount"))
        #expect(enchantedQtRuntime.contains("supportedAttachmentExtensions: PendingImageAttachment.supportedExtensions.sorted()"))
        #expect(enchantedQtRuntime.contains("unsupportedAttachmentSuffix: EnchantedCopy.unsupportedAttachmentSuffix"))
        #expect(enchantedQtRuntime.contains("unreadableAttachmentPrefix: EnchantedCopy.unreadableAttachmentPrefix"))
        #expect(enchantedQtRuntime.contains("unreadableAttachmentSuffix: EnchantedCopy.unreadableAttachmentSuffix"))
        #expect(enchantedQtRuntime.contains("oversizedAttachmentMiddle: EnchantedCopy.oversizedAttachmentMiddle"))
        #expect(enchantedQtRuntime.contains("oversizedAttachmentSuffix: EnchantedCopy.oversizedAttachmentSuffix"))
        #expect(enchantedQtRuntime.contains("sendTitle: EnchantedCopy.sendTitle"))
        #expect(enchantedQtRuntime.contains("stopTitle: EnchantedCopy.stopTitle"))
        #expect(enchantedQtRuntime.contains("stoppingStatus: EnchantedCopy.stoppingStatus"))
        #expect(enchantedQtRuntime.contains("isLoading: false"))
        #expect(enchantedQtRuntime.contains("emptyHistoryTitle: EnchantedCopy.emptyHistoryTitle"))
        #expect(enchantedQtRuntime.contains("emptyHistorySubtitle: EnchantedCopy.emptyHistorySubtitle"))
        #expect(enchantedQtRuntime.contains("emptyStateTitle: EnchantedCopy.emptyStateTitle"))
        #expect(enchantedQtRuntime.contains("emptyStateSubtitle: EnchantedCopy.emptyStateSubtitle"))
        #expect(enchantedShared.contains("public static let windowTitle = \"Enchanted\""))
        #expect(enchantedShared.contains("public static let sidebarSubtitle = \"Local AI conversations\""))
        #expect(enchantedShared.contains("public static let deleteDailyConversationsTitle = \"Delete daily conversations\""))
        #expect(enchantedShared.contains("public static let todayTitle = \"Today\""))
        #expect(enchantedShared.contains("public static let yesterdayTitle = \"Yesterday\""))
        #expect(enchantedShared.contains("public static let daysAgoSuffix = \"days ago\""))
        #expect(enchantedShared.contains("public struct EnchantedConversationDayGroup"))
        #expect(enchantedShared.contains("public enum EnchantedConversationHistory"))
        #expect(enchantedShared.contains("calendar.startOfDay(for: conversation.updatedAt)"))
        #expect(enchantedShared.contains(".sorted { $0.date > $1.date }"))
        #expect(enchantedShared.contains("public static let quillSectionTitle = \"Quill\""))
        #expect(enchantedShared.contains("public static let endpointLabel = \"Quill API endpoint\""))
        #expect(enchantedShared.contains("public static let systemPromptLabel = \"System prompt\""))
        #expect(enchantedShared.contains("public static let bearerTokenLabel = \"Bearer Token\""))
        #expect(enchantedShared.contains("public static let pingIntervalLabel = \"Ping Interval (seconds)\""))
        #expect(enchantedShared.contains("public static let appSectionTitle = \"APP\""))
        #expect(enchantedShared.contains("public static let appearanceLabel = \"Appearance\""))
        #expect(enchantedShared.contains("public static let appearanceSystemOption = \"System\""))
        #expect(enchantedShared.contains("public static let appearanceLightOption = \"Light\""))
        #expect(enchantedShared.contains("public static let appearanceDarkOption = \"Dark\""))
        #expect(enchantedShared.contains("public static let initialsLabel = \"Initials\""))
        #expect(enchantedShared.contains("public static let defaultUserInitials = \"Q\""))
        #expect(enchantedShared.contains("public enum EnchantedSettingsStorage"))
        #expect(enchantedShared.contains("public static let appearanceKey = \"quill.enchanted.colorScheme\""))
        #expect(enchantedShared.contains("public static let userInitialsKey = \"quill.enchanted.appUserInitials\""))
        #expect(enchantedShared.contains("public static let defaultAppearance = EnchantedAppearance.system"))
        #expect(enchantedShared.contains("public static let defaultUserInitials = EnchantedCopy.defaultUserInitials"))
        #expect(enchantedShared.contains("public enum EnchantedAppearance"))
        #expect(enchantedShared.contains("public enum EnchantedPingInterval"))
        #expect(!enchantedShared.contains("public static let endpointLabel = \"Ollama endpoint\""))
        #expect(!enchantedShared.contains("Quill Enchanted"))
        #expect(!enchantedShared.contains("QuillUI Linux preview"))
        #expect(enchantedShared.contains("public static let emptyStateTitle = appTitle"))
        #expect(enchantedShared.contains("public static let emptyStateSubtitle = \"\""))
        #expect(enchantedQtRuntime.contains("var systemImage: String"))
        #expect(enchantedQtRuntime.contains("self.systemImage = prompt.systemImage"))
        #expect(enchantedQtRuntime.contains("imagePreviewFallback: EnchantedIcon.imagePreviewFallback"))
        #expect(enchantedQtRuntime.contains("unavailableModel: EnchantedIcon.unavailableModel"))
        #expect(enchantedQtRuntime.contains("prompts: EnchantedPromptCatalog.visibleEmptyConversationPrompts.map(QuillEnchantedQtSnapshot.Prompt.init)"))
        let visiblePromptPositions = enchantedMacReferenceVisiblePromptTitles.compactMap { promptTitle in
            enchantedShared.range(of: "title: \"\(promptTitle)\"")?.lowerBound
        }
        #expect(visiblePromptPositions.count == enchantedMacReferenceVisiblePromptTitles.count)
        #expect(zip(visiblePromptPositions, visiblePromptPositions.dropFirst()).allSatisfy { pair in pair.0 < pair.1 })
        for promptTitle in enchantedNativeSamplePromptTitles {
            #expect(enchantedShared.contains("title: \"\(promptTitle)\""))
        }
        #expect(enchantedShared.contains("public enum EnchantedInitialSelection"))
        #expect(enchantedShared.contains("public static let selectedConversationIndexEnvironmentKeys = ["))
        #expect(enchantedShared.contains("QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START"))
        #expect(enchantedShared.contains("QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"))
        #expect(enchantedShared.contains("QuillInitialSelection.index("))
        #expect(enchantedShared.contains("QuillInitialSelection.selectedID("))
        #expect(enchantedQtRuntime.contains("EnchantedInitialSelection.selectedConversationIndex(count: count)"))
        #expect(!enchantedQtRuntime.contains("private static let selectedConversationIndexEnvironmentKeys = ["))
        #expect(enchantedQtRuntime.contains("var messages: [Message]? = nil"))
        #expect(enchantedShared.contains("public enum EnchantedPreviewFixture"))
        #expect(enchantedShared.contains("public static let launchConversationMessages"))
        #expect(enchantedShared.contains("public static let attachmentConversationMessages"))
        #expect(enchantedQtRuntime.contains("selectedModel: EnchantedPreviewFixture.selectedModel"))
        #expect(enchantedQtRuntime.contains("selectedConversationID: EnchantedPreviewFixture.selectedConversationID"))
        #expect(enchantedQtRuntime.contains("models: EnchantedPreviewFixture.models"))
        #expect(enchantedQtRuntime.contains("conversations: EnchantedPreviewFixture.conversations.map { Conversation($0) }"))
        #expect(enchantedQtRuntime.contains("messages: EnchantedPreviewFixture.messages.map { Message($0) }"))
        #expect(!enchantedQtRuntime.contains("private static let launchConversationMessages"))
        #expect(!enchantedQtRuntime.contains("messages: launchConversationMessages"))
        #expect(!enchantedQtRuntime.contains("messages: attachmentConversationMessages"))
        #expect(enchantedQtRuntime.contains("warningColor: EnchantedPalette.warningColor"))
        #expect(enchantedQtRuntime.contains("systemColor: EnchantedPalette.systemColor"))
        #expect(enchantedQtRuntime.contains("quoteRuleColor: EnchantedPalette.quoteRuleColor"))
        #expect(enchantedQtRuntime.contains("codeBlockColor: EnchantedPalette.codeBlockColor"))
        #expect(enchantedQtRuntime.contains("sidebarPadding: EnchantedVisualMetrics.sidebarPadding"))
        #expect(enchantedQtRuntime.contains("sidebarSpacing: EnchantedVisualMetrics.sidebarSpacing"))
        #expect(enchantedQtRuntime.contains("sidebarTitleSpacing: EnchantedVisualMetrics.sidebarTitleSpacing"))
        #expect(enchantedQtRuntime.contains("sidebarControlGroupSpacing: EnchantedVisualMetrics.sidebarControlGroupSpacing"))
        #expect(enchantedQtRuntime.contains("statusRowSpacing: EnchantedVisualMetrics.statusRowSpacing"))
        #expect(enchantedQtRuntime.contains("statusDotSize: EnchantedVisualMetrics.statusDotSize"))
        #expect(enchantedQtRuntime.contains("statusDotRadius: EnchantedVisualMetrics.statusDotRadius"))
        #expect(enchantedQtRuntime.contains("conversationListSpacing: EnchantedVisualMetrics.conversationListSpacing"))
        #expect(enchantedQtRuntime.contains("conversationRowPadding: EnchantedVisualMetrics.conversationRowPadding"))
        #expect(enchantedQtRuntime.contains("conversationRowSpacing: EnchantedVisualMetrics.conversationRowSpacing"))
        #expect(enchantedQtRuntime.contains("conversationRowRadius: EnchantedVisualMetrics.conversationRowRadius"))
        #expect(enchantedQtRuntime.contains("conversationListItemRadius: EnchantedVisualMetrics.conversationListItemRadius"))
        #expect(enchantedQtRuntime.contains("conversationListItemVerticalMargin: EnchantedVisualMetrics.conversationListItemVerticalMargin"))
        #expect(enchantedQtRuntime.contains("conversationListItemPadding: EnchantedVisualMetrics.conversationListItemPadding"))
        #expect(enchantedQtRuntime.contains("conversationActionsSpacing: EnchantedVisualMetrics.conversationActionsSpacing"))
        #expect(enchantedQtRuntime.contains("attachmentChipPadding: EnchantedVisualMetrics.attachmentChipPadding"))
        #expect(enchantedQtRuntime.contains("attachmentChipSpacing: EnchantedVisualMetrics.attachmentChipSpacing"))
        #expect(enchantedQtRuntime.contains("attachmentChipTextSpacing: EnchantedVisualMetrics.attachmentChipTextSpacing"))
        #expect(enchantedQtRuntime.contains("attachmentChipRadius: EnchantedVisualMetrics.attachmentChipRadius"))
        #expect(enchantedQtRuntime.contains("attachmentTraySpacing: EnchantedVisualMetrics.attachmentTraySpacing"))
        #expect(enchantedQtRuntime.contains("attachmentTrayChipSpacing: EnchantedVisualMetrics.attachmentTrayChipSpacing"))
        #expect(!enchantedQtRuntime.contains("attachmentInputHorizontalPadding: EnchantedVisualMetrics.attachmentInputHorizontalPadding"))
        #expect(!enchantedQtRuntime.contains("attachmentInputVerticalPadding: EnchantedVisualMetrics.attachmentInputVerticalPadding"))
        #expect(enchantedQtRuntime.contains("attachmentInputSpacing: EnchantedVisualMetrics.attachmentInputSpacing"))
        #expect(enchantedQtRuntime.contains("headerTitleWidth: EnchantedVisualMetrics.headerTitleWidth"))
        #expect(enchantedQtRuntime.contains("headerSpacing: EnchantedVisualMetrics.headerSpacing"))
        #expect(enchantedQtRuntime.contains("headerTitleSpacing: EnchantedVisualMetrics.headerTitleSpacing"))
        #expect(enchantedQtRuntime.contains("headerPadding: EnchantedVisualMetrics.headerPadding"))
        #expect(enchantedQtRuntime.contains("composerPadding: EnchantedVisualMetrics.composerPadding"))
        #expect(enchantedQtRuntime.contains("composerSpacing: EnchantedVisualMetrics.composerSpacing"))
        #expect(enchantedQtRuntime.contains("promptRowSpacing: EnchantedVisualMetrics.promptRowSpacing"))
        #expect(enchantedQtRuntime.contains("composerMinWidth: EnchantedVisualMetrics.composerMinWidth"))
        #expect(enchantedQtRuntime.contains("composerMaxWidth: EnchantedVisualMetrics.composerMaxWidth"))
        #expect(enchantedQtRuntime.contains("composerMinHeight: EnchantedVisualMetrics.composerMinHeight"))
        #expect(enchantedQtRuntime.contains("composerMaxHeight: EnchantedVisualMetrics.composerMaxHeight"))
        #expect(enchantedQtRuntime.contains("contentPadding: EnchantedVisualMetrics.contentPadding"))
        #expect(enchantedQtRuntime.contains("messageSpacing: EnchantedVisualMetrics.messageSpacing"))
        #expect(enchantedQtRuntime.contains("messageBubbleRowSpacing: EnchantedVisualMetrics.messageBubbleRowSpacing"))
        #expect(enchantedQtRuntime.contains("messageBubbleHorizontalPadding: EnchantedVisualMetrics.messageBubbleHorizontalPadding"))
        #expect(enchantedQtRuntime.contains("messageBubbleVerticalPadding: EnchantedVisualMetrics.messageBubbleVerticalPadding"))
        #expect(enchantedQtRuntime.contains("messageBubbleSpacing: EnchantedVisualMetrics.messageBubbleSpacing"))
        #expect(enchantedQtRuntime.contains("messageBubbleRadius: EnchantedVisualMetrics.messageBubbleRadius"))
        #expect(enchantedQtRuntime.contains("messageEditBorderWidth: EnchantedVisualMetrics.messageEditBorderWidth"))
        #expect(enchantedQtRuntime.contains("markdownBlockSpacing: EnchantedVisualMetrics.markdownBlockSpacing"))
        #expect(enchantedQtRuntime.contains("markdownListItemSpacing: EnchantedVisualMetrics.markdownListItemSpacing"))
        #expect(enchantedQtRuntime.contains("markdownNumberWidth: EnchantedVisualMetrics.markdownNumberWidth"))
        #expect(enchantedQtRuntime.contains("markdownQuoteSpacing: EnchantedVisualMetrics.markdownQuoteSpacing"))
        #expect(enchantedQtRuntime.contains("markdownQuoteRuleWidth: EnchantedVisualMetrics.markdownQuoteRuleWidth"))
        #expect(enchantedQtRuntime.contains("markdownQuoteRuleRadius: EnchantedVisualMetrics.markdownQuoteRuleRadius"))
        #expect(enchantedQtRuntime.contains("markdownQuoteVerticalPadding: EnchantedVisualMetrics.markdownQuoteVerticalPadding"))
        #expect(enchantedQtRuntime.contains("markdownCodeBlockSpacing: EnchantedVisualMetrics.markdownCodeBlockSpacing"))
        #expect(enchantedQtRuntime.contains("markdownCodeBlockPadding: EnchantedVisualMetrics.markdownCodeBlockPadding"))
        #expect(enchantedQtRuntime.contains("markdownCodeBlockRadius: EnchantedVisualMetrics.markdownCodeBlockRadius"))
        #expect(enchantedQtRuntime.contains("emptyHistoryPadding: EnchantedVisualMetrics.emptyHistoryPadding"))
        #expect(enchantedQtRuntime.contains("emptyHistorySpacing: EnchantedVisualMetrics.emptyHistorySpacing"))
        #expect(enchantedQtRuntime.contains("emptyHistoryRadius: EnchantedVisualMetrics.emptyHistoryRadius"))
        #expect(enchantedQtRuntime.contains("emptyStatePadding: EnchantedVisualMetrics.emptyStatePadding"))
        #expect(enchantedQtRuntime.contains("emptyStateSpacing: EnchantedVisualMetrics.emptyStateSpacing"))
        #expect(enchantedQtRuntime.contains("emptyStateMaxWidth: EnchantedVisualMetrics.emptyStateMaxWidth"))
        #expect(enchantedQtRuntime.contains("promptListSpacing: EnchantedVisualMetrics.promptListSpacing"))
        #expect(enchantedQtRuntime.contains("promptGridColumns: EnchantedVisualMetrics.promptGridColumns"))
        #expect(enchantedQtRuntime.contains("promptGridSpacing: EnchantedVisualMetrics.promptGridSpacing"))
        #expect(enchantedQtRuntime.contains("promptCardWidth: EnchantedVisualMetrics.promptCardWidth"))
        #expect(enchantedQtRuntime.contains("promptCardHeight: EnchantedVisualMetrics.promptCardHeight"))
        #expect(enchantedQtRuntime.contains("promptGridWidth: EnchantedVisualMetrics.promptGridWidth"))
        #expect(enchantedQtRuntime.contains("promptButtonMinHeight: EnchantedVisualMetrics.promptButtonMinHeight"))
        #expect(enchantedQtRuntime.contains("promptButtonWidth: EnchantedVisualMetrics.promptButtonWidth"))
        #expect(enchantedQtRuntime.contains("promptButtonPadding: EnchantedVisualMetrics.promptButtonPadding"))
        #expect(enchantedQtRuntime.contains("promptButtonRadius: EnchantedVisualMetrics.promptButtonRadius"))
        #expect(enchantedQtRuntime.contains("primaryButtonPadding: EnchantedVisualMetrics.primaryButtonPadding"))
        #expect(enchantedQtRuntime.contains("primaryButtonVerticalPadding: EnchantedVisualMetrics.primaryButtonVerticalPadding"))
        #expect(enchantedQtRuntime.contains("primaryButtonHorizontalPadding: EnchantedVisualMetrics.primaryButtonHorizontalPadding"))
        #expect(enchantedQtRuntime.contains("primaryButtonRadius: EnchantedVisualMetrics.primaryButtonRadius"))
        #expect(enchantedQtRuntime.contains("primaryButtonIconSpacing: EnchantedVisualMetrics.primaryButtonIconSpacing"))
        #expect(enchantedQtRuntime.contains("actionButtonIconSize: EnchantedVisualMetrics.actionButtonIconSize"))
        #expect(enchantedQtRuntime.contains("actionButtonIconSpacing: EnchantedVisualMetrics.actionButtonIconSpacing"))
        #expect(enchantedQtRuntime.contains("secondaryButtonVerticalPadding: EnchantedVisualMetrics.secondaryButtonVerticalPadding"))
        #expect(enchantedQtRuntime.contains("secondaryButtonHorizontalPadding: EnchantedVisualMetrics.secondaryButtonHorizontalPadding"))
        #expect(enchantedQtRuntime.contains("secondaryButtonRadius: EnchantedVisualMetrics.secondaryButtonRadius"))
        #expect(enchantedQtRuntime.contains("chipRemoveButtonVerticalPadding: EnchantedVisualMetrics.chipRemoveButtonVerticalPadding"))
        #expect(enchantedQtRuntime.contains("chipRemoveButtonHorizontalPadding: EnchantedVisualMetrics.chipRemoveButtonHorizontalPadding"))
        #expect(enchantedQtRuntime.contains("controlPadding: EnchantedVisualMetrics.controlPadding"))
        #expect(enchantedQtRuntime.contains("controlRadius: EnchantedVisualMetrics.controlRadius"))
        #expect(enchantedQtRuntime.contains("dropTargetPadding: EnchantedVisualMetrics.dropTargetPadding"))
        #expect(enchantedQtRuntime.contains("dropTargetRadius: EnchantedVisualMetrics.dropTargetRadius"))
        #expect(!enchantedQtRuntime.contains("QuillQtNativeRuntimeSupport.boundedIndexOverride("))
        #expect(!enchantedQtRuntime.contains("environmentKeys: selectedConversationIndexEnvironmentKeys"))
        #expect(!enchantedQtRuntime.contains("ProcessInfo.processInfo.environment["))
        #expect(enchantedQtRuntime.contains("snapshot.selectConversation(at: boundedIndex)"))
        #expect(enchantedQtRuntime.contains("QuillQtNativeRuntimeSupport.runEncodedPayload("))
        #expect(enchantedQtRuntime.contains("QuillQtNativeRuntimeSupport.encodedPayloadString(snapshot)"))
        #expect(enchantedQtRuntime.contains("executableName: QuillQtNativeRuntimeSupport.executableName(fallback: \"quill-enchanted-qt\")"))
    }

    @Test("Retired Enchanted Qt native runtime stays removed")
    func retiredEnchantedQtNativeRuntimeStaysRemoved() throws {
        let root = try packageRoot()
        let retiredRuntime = root.appendingPathComponent("Sources/QuillEnchantedQtNativeRuntime/QuillEnchantedQtNativeRuntime.swift")
        #expect(!FileManager.default.fileExists(atPath: retiredRuntime.path))
    }

    @Test("Generic Qt renderer reads SwiftUI bodies through MainActor isolation")
    func genericQtRendererReadsSwiftUIBodiesThroughMainActorIsolation() throws {
        let renderer = try packageSource("Sources/BackendQt/QtRenderer.swift")
        let smokeApp = try packageSource("Sources/BackendQt/QtSmokeApp.swift")
        let smokeScript = try packageSource("scripts/linux-qt-generic-smoke-check.sh")

        #expect(renderer.contains("MainActor.assumeIsolated {\n        rendered = qtRenderView(view.body)\n    }"))
        #expect(!renderer.contains("\n    return qtRenderView(view.body)\n    // Stateless composite view"))
        #expect(smokeApp.contains(".onKeyPress(.tab)"))
        #expect(smokeApp.contains("textFieldValue = \"Qt onKeyPress tab\""))
        #expect(smokeApp.contains(".keyboardShortcut(.defaultAction)"))
        #expect(smokeApp.contains("qtSmokeInteractionLog(\"keyboardShortcut default\")"))
        #expect(smokeApp.contains("textFieldValue = \"Qt keyboardShortcut default\""))
        #expect(smokeScript.contains("QUILLUI_QT_GENERIC_VERIFY_SHORTCUT"))
        #expect(smokeScript.contains("xdotool key --window \"$window_id\" --clearmodifiers Return"))
        #expect(smokeScript.contains("grep -q \"\\\\[qt-smoke\\\\] keyboardShortcut default\""))
        #expect(smokeScript.contains("Qt .keyboardShortcut(.defaultAction) did not reach the Swift action."))
    }

    @Test("Generic and WireGuard Qt hosts use shared native runtime contracts")
    func genericAndWireGuardQtHostsUseSharedNativeRuntimeContracts() throws {
        let root = try packageRoot()
        let enchantedShared = try packageSource("Sources/QuillEnchantedShared/QuillEnchantedShared.swift")
        let enchantedQtHost = try packageSource("Sources/CQuillQt6WidgetsShim/QuillEnchantedQt6Widgets.cpp")
        let genericQtRuntime = try packageSource("Sources/QuillGenericQtNativeRuntime/QuillGenericQtNativeRuntime.swift")
        let genericQtHost = try packageSource("Sources/CQuillQt6WidgetsShim/QuillGenericQt6Widgets.cpp")
        let genericQtHarness = try packageSource("scripts/generic-qt-enchanted-harness-check.sh")
        let wireGuardQtRuntime = try packageSource("Sources/QuillWireGuardQtNativeRuntime/QuillWireGuardQtNativeRuntime.swift")
        let wireGuardQtHost = try packageSource("Sources/CQuillQt6WidgetsShim/QuillWireGuardQt6Widgets.cpp")
        #expect(FileManager.default.isExecutableFile(
            atPath: root.appendingPathComponent("scripts/generic-qt-enchanted-harness-check.sh").path
        ))

        #expect(genericQtRuntime.contains("import QuillEnchantedShared"))
        #expect(genericQtRuntime.contains("import QuillQtNativeRuntimeSupport"))
        #expect(genericQtRuntime.contains("minimumWidth: EnchantedVisualMetrics.minimumWindowWidth"))
        #expect(genericQtRuntime.contains("minimumHeight: EnchantedVisualMetrics.minimumWindowHeight"))
        #expect(genericQtRuntime.contains("defaultWidth: EnchantedVisualMetrics.defaultWindowWidth"))
        #expect(genericQtRuntime.contains("defaultHeight: EnchantedVisualMetrics.defaultWindowHeight"))
        #expect(genericQtRuntime.contains("sidebarWidth: EnchantedVisualMetrics.sidebarWidth"))
        #expect(genericQtRuntime.contains("detailWidth: EnchantedVisualMetrics.detailWidth"))
        #expect(genericQtRuntime.contains("rootFontSize: EnchantedTypography.rootFontSize"))
        #expect(genericQtRuntime.contains("appTitleFontSize: EnchantedTypography.appTitleFontSize"))
        #expect(genericQtRuntime.contains("appTitleFontWeight: EnchantedTypography.appTitleFontWeight"))
        #expect(genericQtRuntime.contains("captionFontSize: EnchantedTypography.captionFontSize"))
        #expect(genericQtRuntime.contains("sectionTitleFontSize: EnchantedTypography.sectionTitleFontSize"))
        #expect(genericQtRuntime.contains("sectionTitleFontWeight: EnchantedTypography.sectionTitleFontWeight"))
        #expect(genericQtRuntime.contains("currentTitleFontSize: EnchantedTypography.currentTitleFontSize"))
        #expect(genericQtRuntime.contains("currentTitleFontWeight: EnchantedTypography.currentTitleFontWeight"))
        #expect(genericQtRuntime.contains("messageBodyFontSize: EnchantedTypography.messageBodyFontSize"))
        #expect(genericQtRuntime.contains("conversationTitleFontSize: EnchantedTypography.conversationTitleFontSize"))
        #expect(genericQtRuntime.contains("conversationTitleFontWeight: EnchantedTypography.conversationTitleFontWeight"))
        #expect(genericQtRuntime.contains("sidebarPadding: EnchantedVisualMetrics.sidebarPadding"))
        #expect(genericQtRuntime.contains("sidebarSpacing: EnchantedVisualMetrics.sidebarSpacing"))
        #expect(genericQtRuntime.contains("sidebarActionSpacing: EnchantedVisualMetrics.conversationActionsSpacing"))
        #expect(genericQtRuntime.contains("primaryButtonVerticalPadding: EnchantedVisualMetrics.primaryButtonVerticalPadding"))
        #expect(genericQtRuntime.contains("primaryButtonHorizontalPadding: EnchantedVisualMetrics.primaryButtonHorizontalPadding"))
        #expect(genericQtRuntime.contains("primaryButtonRadius: EnchantedVisualMetrics.primaryButtonRadius"))
        #expect(genericQtRuntime.contains("secondaryButtonRadius: EnchantedVisualMetrics.secondaryButtonRadius"))
        #expect(genericQtRuntime.contains("listSpacing: EnchantedVisualMetrics.conversationListSpacing"))
        #expect(genericQtRuntime.contains("listItemPadding: EnchantedVisualMetrics.conversationListItemPadding"))
        #expect(genericQtRuntime.contains("itemRowHorizontalPadding: EnchantedVisualMetrics.conversationRowPadding"))
        #expect(genericQtRuntime.contains("itemRowVerticalPadding: EnchantedVisualMetrics.conversationRowPadding"))
        #expect(genericQtRuntime.contains("itemRowSpacing: EnchantedVisualMetrics.conversationRowSpacing"))
        #expect(genericQtRuntime.contains("cardPaddingHorizontal: EnchantedVisualMetrics.emptyHistoryPadding"))
        #expect(genericQtRuntime.contains("messageCardPaddingHorizontal: EnchantedVisualMetrics.messageBubbleHorizontalPadding"))
        #expect(genericQtRuntime.contains("messageCardPaddingVertical: EnchantedVisualMetrics.messageBubbleVerticalPadding"))
        #expect(genericQtRuntime.contains("detailSpacing: EnchantedVisualMetrics.messageSpacing"))
        #expect(genericQtRuntime.contains("public static let genericSelectedIndexEnvironmentKey = \"QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START\""))
        #expect(genericQtRuntime.contains("public static let defaultSelectedIndexEnvironmentKeys = [genericSelectedIndexEnvironmentKey]"))
        #expect(genericQtRuntime.contains("public var selectedIndexEnvironmentKeys: [String]"))
        #expect(genericQtRuntime.contains("public var chatBehavior: ChatBehavior"))
        #expect(genericQtRuntime.contains("public struct ChatBehavior: Codable, Sendable"))
        #expect(genericQtRuntime.contains("public struct PromptResponse: Codable, Sendable"))
        #expect(genericQtRuntime.contains("chatBehavior: ChatBehavior = .init()"))
        #expect(genericQtRuntime.contains("chatBehavior: try container.decodeIfPresent(ChatBehavior.self, forKey: .chatBehavior) ?? .init()"))
        #expect(genericQtRuntime.contains("public var style: Style"))
        #expect(genericQtRuntime.contains("public struct Style: Codable, Sendable"))
        #expect(genericQtRuntime.contains("public static let desktop = Style("))
        #expect(genericQtRuntime.contains("public static let enchanted = Style("))
        #expect(genericQtRuntime.contains("canvasColor: EnchantedPalette.canvasColor"))
        #expect(genericQtRuntime.contains("activeCardColor: EnchantedPalette.sidebarSelectedColor"))
        #expect(genericQtRuntime.contains("primaryColor: EnchantedPalette.accentColor"))
        #expect(genericQtRuntime.contains("style: .enchanted"))
        #expect(genericQtRuntime.contains("style: Style = .desktop"))
        #expect(enchantedShared.contains("public static let cardQuietColor = \"#F1F1F5\""))
        #expect(genericQtRuntime.contains("static func appSpecific(_ environmentKeys: String...) -> [String]"))
        #expect(genericQtRuntime.contains("QuillGenericQtSelectionEnvironment.codeEdit"))
        #expect(genericQtRuntime.contains("QuillGenericQtSelectionEnvironment.iceCubes"))
        #expect(genericQtRuntime.contains("QuillGenericQtSelectionEnvironment.iina"))
        #expect(genericQtRuntime.contains("QuillGenericQtSelectionEnvironment.netNewsWire"))
        #expect(genericQtRuntime.contains("QuillGenericQtSelectionEnvironment.signal"))
        #expect(genericQtRuntime.contains("QuillGenericQtSelectionEnvironment.telegram"))
        #expect(genericQtRuntime.contains("QuillGenericQtSelectionEnvironment.chat"))
        #expect(genericQtRuntime.contains("public static func run(_ snapshot: QuillGenericQtAppSnapshot) -> Never"))
        #expect(genericQtRuntime.contains("QuillQtNativeRuntimeSupport.boundedIndexOverride("))
        #expect(genericQtRuntime.contains("environmentKeys: launchSnapshot.selectedIndexEnvironmentKeys"))
        #expect(genericQtRuntime.contains("QuillQtNativeRuntimeSupport.runEncodedPayload("))
        #expect(genericQtRuntime.contains("executableName: QuillQtNativeRuntimeSupport.executableName(fallback: \"quill-generic-qt\")"))
        #expect(genericQtRuntime.contains("Use **flexbox**: set `display` to `flex`"))
        #expect(genericQtRuntime.contains("justify-content: center;"))
        #expect(!genericQtRuntime.contains("executableName: String"))
        #expect(!genericQtRuntime.contains("executableName: executableName"))
        #expect(!genericQtRuntime.contains("ProcessInfo.processInfo.environment["))
        #expect(!genericQtRuntime.contains("private static func selectedIndexOverride"))
        #expect(genericQtHost.contains("QString chatMessagesPlainText(const QJsonArray &messages)"))
        #expect(genericQtHost.contains("QString chatMessagesJsonText(const QJsonArray &messages)"))
        #expect(genericQtHost.contains("bool writeFileBackedPasteboardText(const QString &text)"))
        #expect(genericQtHost.contains("QUILLUI_GTK_TOOLBAR_ACTION_COMMAND_DIR") == false)
        #expect(genericQtHost.contains("XDG_RUNTIME_DIR"))
        #expect(genericQtHost.contains("quill-pasteboard/Apple.NSGeneralPboard/types"))
        #expect(genericQtHost.contains("public.utf8-plain-text"))
        #expect(genericQtHost.contains("QStringLiteral(\"Copy Chat\")"))
        #expect(genericQtHost.contains("QStringLiteral(\"Copy Chat as JSON\")"))
        #expect(genericQtHost.contains("chatHeaderAction == QStringLiteral(\"copyMenu\")"))
        #expect(genericQtHost.contains("writeFileBackedPasteboardText(chatMessagesPlainText(selection.messages))"))
        #expect(genericQtHost.contains("writeFileBackedPasteboardText(chatMessagesJsonText(selection.messages))"))
        #expect(genericQtHarness.contains("QuillGenericQt6Widgets.cpp"))
        #expect(genericQtHarness.contains("quill_generic_qt_run_app_json(argc, argv, payload)"))
        #expect(genericQtHarness.contains("xvfb-run -a -s \"-screen 0 1180x760x24\""))
        #expect(genericQtHarness.contains("import -window root \"$output_path\""))
        #expect(genericQtHarness.contains("HARNESS_MODE=\"${QUILLUI_GENERIC_QT_HARNESS_MODE:-home}\""))
        #expect(genericQtHarness.contains("selected-chat|list-selection)"))
        #expect(genericQtHarness.contains("settings)"))
        #expect(genericQtHarness.contains("settings-click)"))
        #expect(genericQtHarness.contains("completions-click)"))
        #expect(genericQtHarness.contains("shortcuts-click)"))
        #expect(genericQtHarness.contains("VERIFY_PRODUCT=\"quill-enchanted-linux-qt-selected-chat\""))
        #expect(genericQtHarness.contains("VERIFY_PRODUCT=\"quill-enchanted-linux-qt-settings\""))
        #expect(genericQtHarness.contains("VERIFY_PRODUCT=\"quill-enchanted-linux-qt-utility\""))
        #expect(genericQtHarness.contains("ACTIVE_NAVIGATION=\"settings\""))
        #expect(genericQtHarness.contains("CLICK_NAVIGATION=\"settings\""))
        #expect(genericQtHarness.contains("CLICK_NAVIGATION=\"completions\""))
        #expect(genericQtHarness.contains("CLICK_NAVIGATION=\"shortcuts\""))
        #expect(genericQtHarness.contains("static const char selectedChatPayload[]"))
        #expect(genericQtHarness.contains("QUILLUI_GENERIC_QT_ACTIVE_NAVIGATION=\"$active_navigation\""))
        #expect(genericQtHarness.contains("QUILLUI_GENERIC_QT_AUTOMATION_CLICK_NAVIGATION=\"$click_navigation\""))
        #expect(genericQtHarness.contains("verify-backend-screenshot.py\" \"$output_path\" \"$verify_product\""))
        #expect(genericQtHarness.contains("\"selectedIndex\":-1"))
        #expect(genericQtHarness.contains("\"selectedIndex\":5"))
        #expect(genericQtHarness.contains("\"promptCardColor\":\"#F1F1F5\""))
        #expect(genericQtHost.contains("parseJsonObjectPayload("))
        #expect(genericQtHost.contains("QuillQtWidgets::executableNameBytes(argc, argv, \"quill-generic-qt\")"))
        #expect(genericQtHost.contains("QString genericStyleSheet(const QJsonObject &style)"))
        #expect(genericQtHost.contains("styleValue(style, \"canvasColor\", \"#F7F8F4\")"))
        #expect(genericQtHost.contains("const QString rootFontSize = cssPixels(style, \"rootFontSize\", 14)"))
        #expect(genericQtHost.contains("const QString appTitleFontSize = cssPixels(style, \"appTitleFontSize\", 26)"))
        #expect(genericQtHost.contains("const QString appTitleFontWeight = QString::number(intValue(style, \"appTitleFontWeight\", 700))"))
        #expect(genericQtHost.contains("const QString captionFontSize = cssPixels(style, \"captionFontSize\", 12)"))
        #expect(genericQtHost.contains("const QString sectionTitleFontSize = cssPixels(style, \"sectionTitleFontSize\", 15)"))
        #expect(genericQtHost.contains("const QString sectionTitleFontWeight = QString::number(intValue(style, \"sectionTitleFontWeight\", 700))"))
        #expect(genericQtHost.contains("const QString currentTitleFontSize = cssPixels(style, \"currentTitleFontSize\", 20)"))
        #expect(genericQtHost.contains("const QString currentTitleFontWeight = QString::number(intValue(style, \"currentTitleFontWeight\", 650))"))
        #expect(genericQtHost.contains("const QString messageBodyFontSize = cssPixels(style, \"messageBodyFontSize\", 14)"))
        #expect(genericQtHost.contains("const QString conversationTitleFontSize = cssPixels(style, \"conversationTitleFontSize\", 15)"))
        #expect(genericQtHost.contains("const QString conversationTitleFontWeight = QString::number(intValue(style, \"conversationTitleFontWeight\", 700))"))
        #expect(genericQtHost.contains("const QString cardRadius = cssPixels(style, \"cardRadius\", 8)"))
        #expect(genericQtHost.contains("const QString listItemRadius = cssPixels(style, \"listItemRadius\", 8)"))
        #expect(genericQtHost.contains("const QString primaryButtonRadius = cssPixels(style, \"primaryButtonRadius\", 8)"))
        #expect(genericQtHost.contains("const QString primaryButtonVerticalPadding = cssPixels(style, \"primaryButtonVerticalPadding\", 8)"))
        #expect(genericQtHost.contains("const QString secondaryButtonRadius = cssPixels(style, \"secondaryButtonRadius\", 7)"))
        #expect(genericQtHost.contains("QWidget#genericRoot { background: %1; color: %2; font-size: %3; }"))
        #expect(genericQtHost.contains("QLabel#appTitle { color: %1; font-size: %2; font-weight: %3; }"))
        #expect(genericQtHost.contains("QLabel#bodyText, QLabel#messageText { color: %1; font-size: %2; line-height: 140%; }"))
        #expect(!genericQtHost.contains("font-size: 14px;"))
        #expect(!genericQtHost.contains("font-size: 25px;"))
        #expect(!genericQtHost.contains("font-size: 22px;"))
        #expect(genericQtHost.contains("const QJsonObject style = jsonObjectValue(payload, \"style\");"))
        #expect(!genericQtHost.contains("root.setStyleSheet(genericStyleSheet());"))
        #expect(genericQtHost.contains("QuillQtWidgets::minimumWindowSize(payload, 900, 620)"))
        #expect(genericQtHost.contains("QuillQtWidgets::defaultWindowSize(payload, minimumSize)"))
        #expect(genericQtHost.contains("const int sidebarWidth = intValue(payload, \"sidebarWidth\", 320)"))
        #expect(genericQtHost.contains("sidebar->setMinimumWidth(sidebarWidth)"))
        #expect(genericQtHost.contains("sidebar->setMaximumWidth(sidebarWidth)"))
        #expect(genericQtHost.contains("list->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff)"))
        #expect(genericQtHost.contains("scroll->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff)"))
        #expect(genericQtHost.contains("const int sidebarPadding = intValue(style, \"sidebarPadding\", 18)"))
        #expect(genericQtHost.contains("layout->setContentsMargins(sidebarPadding, sidebarPadding, sidebarPadding, sidebarPadding)"))
        #expect(genericQtHost.contains("layout->setSpacing(intValue(style, \"sidebarSpacing\", 12))"))
        #expect(genericQtHost.contains("actions->setSpacing(intValue(style, \"sidebarActionSpacing\", 8))"))
        #expect(genericQtHost.contains("const int primaryButtonMinHeight = intValue(style, \"primaryButtonMinHeight\", 36)"))
        #expect(genericQtHost.contains("primary->setMinimumHeight(primaryButtonMinHeight)"))
        #expect(genericQtHost.contains("secondary->setMinimumHeight(primaryButtonMinHeight)"))
        #expect(genericQtHost.contains("list->setSpacing(intValue(style, \"listSpacing\", 4))"))
        #expect(genericQtHost.contains("layout->setSpacing(intValue(style, \"cardSpacing\", 7))"))
        #expect(genericQtHost.contains("layout->setSpacing(intValue(style, \"messageCardSpacing\", 6))"))
        #expect(genericQtHost.contains("layout->setSpacing(intValue(style, \"detailSpacing\", 14))"))
        #expect(genericQtHost.contains("contentLayout->setSpacing(intValue(style, \"detailContentSpacing\", 14))"))
        #expect(!genericQtHost.contains("primary->setMinimumHeight(36)"))
        #expect(!genericQtHost.contains("box->setContentsMargins(18, 18, 18, 18)"))
        #expect(!genericQtHost.contains("list->setSpacing(4)"))
        #expect(!genericQtHost.contains("rowLayout->setSpacing(4)"))
        #expect(genericQtHost.contains("primary->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Fixed)"))
        #expect(genericQtHost.contains("secondary->setSizePolicy(QSizePolicy::Fixed, QSizePolicy::Fixed)"))
        #expect(genericQtHost.contains("#include <QIcon>"))
        #expect(genericQtHost.contains("#include <QPainter>"))
        #expect(genericQtHost.contains("#include <QPixmap>"))
        #expect(genericQtHost.contains("#include <QStringList>"))
        #expect(genericQtHost.contains("#include <QTimer>"))
        #expect(genericQtHost.contains("QIcon symbolicIcon(const QString &kind)"))
        #expect(genericQtHost.contains("QPixmap pixmap(48, 48)"))
        #expect(genericQtHost.contains("painter.drawLine(QPointF(15, 20), QPointF(24, 29))"))
        #expect(genericQtHost.contains("painter.drawEllipse(QPointF(16, 24), 2.8, 2.8)"))
        #expect(genericQtHost.contains("painter.drawRoundedRect(QRectF(10, 13, 25, 25), 2.4, 2.4)"))
        #expect(genericQtHost.contains("kind == QStringLiteral(\"waveform\")"))
        #expect(genericQtHost.contains("painter.drawLine(QPointF(24, 12), QPointF(24, 36))"))
        #expect(genericQtHost.contains("normalized.contains(QStringLiteral(\"mic\"))"))
        #expect(genericQtHost.contains("class GradientWordmark final : public QWidget"))
        #expect(genericQtHost.contains("QLinearGradient gradient(path.boundingRect().topLeft(), path.boundingRect().topRight())"))
        #expect(genericQtHost.contains("GradientWordmark *title = new GradientWordmark(titleText, style)"))
        #expect(genericQtHost.contains("QStringLiteral(\"SF Pro Display\")"))
        #expect(genericQtHost.contains("QIcon systemImageIcon(const QString &systemImage)"))
        #expect(!genericQtHost.contains("QIcon::fromTheme"))
        #expect(!genericQtHost.contains("go-down-symbolic"))
        #expect(!genericQtHost.contains("view-more-symbolic"))
        #expect(!genericQtHost.contains("document-new-symbolic"))
        #expect(genericQtHost.contains("QPushButton#headerIconButton { background: transparent; border: 0; padding: %8; }"))
        #expect(genericQtHost.contains("QPushButton *headerIconButton(const QString &systemImage, const QString &title, const QJsonObject &style)"))
        #expect(genericQtHost.contains("const int iconSize = intValue(style, \"headerIconButtonIconSize\", 24)"))
        #expect(genericQtHost.contains("button->setIcon(systemImageIcon(systemImage))"))
        #expect(genericQtHost.contains("button->setIconSize(QSize(\n        iconSize,\n        iconSize"))
        #expect(genericQtHost.contains("button->setFlat(true)"))
        #expect(genericQtHost.contains("button->setFocusPolicy(Qt::NoFocus)"))
        #expect(genericQtHost.contains("QSplitter::handle:horizontal { width: 1px; }"))
        #expect(genericQtHost.contains("splitter->setHandleWidth(1)"))
        #expect(genericQtHost.contains("button->setIcon(systemImageIcon(stringValue(action, \"systemImage\")))"))
        #expect(genericQtHost.contains("button->setProperty(\"navigationAction\", navigationAction)"))
        #expect(genericQtHost.contains("button->setProperty(\"navigationTitle\", titleText)"))
        #expect(genericQtHost.contains("button->setProperty(\"navigationSubtitle\", stringValue(action, \"subtitle\"))"))
        #expect(genericQtHost.contains("QFrame#composerFrame { background: %4; border: 1px solid %6; border-radius: %7; }"))
        #expect(genericQtHost.contains("QWidget#detailBody, QWidget#conversationHost, QWidget#emptyState, QWidget#promptGridHost { background: %1; }"))
        #expect(genericQtHost.contains("notice->setMinimumHeight(intValue(style, \"noticeMinHeight\", 44))"))
        #expect(genericQtHost.contains("notice->setMaximumWidth(intValue(style, \"noticeMaxWidth\", 680))"))
        #expect(genericQtHost.contains("action->setProperty(\"navigationAction\", QStringLiteral(\"settings\"))"))
        #expect(genericQtHost.contains("bodyLayout->addWidget(notice, 0, Qt::AlignCenter)"))
        #expect(genericQtHost.contains("body->setObjectName(QStringLiteral(\"detailBody\"))"))
        #expect(genericQtHost.contains("conversationHost->setObjectName(QStringLiteral(\"conversationHost\"))"))
        #expect(genericQtHost.contains("emptyState->setObjectName(QStringLiteral(\"emptyState\"))"))
        #expect(genericQtHost.contains("gridHost->setObjectName(QStringLiteral(\"promptGridHost\"))"))
        #expect(genericQtHost.contains("#include <QStackedLayout>"))
        #expect(genericQtHost.contains("QWidget *settingsOverlayWidget(const QJsonObject &payload, const QJsonObject &style)"))
        #expect(genericQtHost.contains("host->setObjectName(QStringLiteral(\"panelOverlayHost\"))"))
        #expect(genericQtHost.contains("stack->setStackingMode(QStackedLayout::StackAll)"))
        #expect(genericQtHost.contains("emptyLayout->addWidget(emptyStateWidget(payload, style), 0, Qt::AlignCenter)"))
        #expect(genericQtHost.contains("Qt::Alignment panelAlignment"))
        #expect(genericQtHost.contains("panelLayout->addWidget(panel, 0, panelAlignment)"))
        #expect(genericQtHost.contains("settingsPaneWidget(payload, style), Qt::AlignCenter"))
        #expect(genericQtHost.contains("completionsPaneWidget(style, hostLayout, payload), Qt::AlignLeft"))
        #expect(genericQtHost.contains("layout->addWidget(settingsOverlayWidget(payload, style), 1)"))
        #expect(genericQtHost.contains("QFrame *completionsPaneWidget(\n    const QJsonObject &style"))
        #expect(genericQtHost.contains("QWidget *completionRowWidget("))
        #expect(genericQtHost.contains("panel->setMaximumWidth(intValue(style, \"completionsPanelMaxWidth\", 560))"))
        #expect(genericQtHost.contains("panel->setMinimumWidth(intValue(style, \"completionsPanelMinWidth\", 520))"))
        #expect(genericQtHost.contains("QLabel#completionTitle { color: #B06FD0;"))
        #expect(genericQtHost.contains("QFrame#completionDivider { background: %11; border: 0; min-height: 1px; max-height: 1px; }"))
        #expect(genericQtHost.contains("QPushButton#completionLinkButton { background: transparent; color: #0057FF;"))
        #expect(genericQtHost.contains("QPushButton#completionActionButton { background: transparent; color: %5;"))
        #expect(genericQtHost.contains("layout->addWidget(completionsOverlayWidget(payload, style, layout), 1)"))
        #expect(genericQtHost.contains("layout->addWidget(completionDividerWidget())"))
        #expect(genericQtHost.contains("QStringLiteral(\"New Completion\")"))
        #expect(genericQtHost.contains("QStringLiteral(\"Fix Grammar\")"))
        #expect(genericQtHost.contains("QStringLiteral(\"Politely Decline\")"))
        #expect(genericQtHost.contains("std::getenv(\"QUILLUI_BACKEND_SELECTED_MODEL_NAME\")"))
        #expect(genericQtHost.contains("QJsonObject chatBehaviorPayload(const QJsonObject &payload)"))
        #expect(genericQtHost.contains("QStringList modelMenuNames(const QJsonObject &payload)"))
        #expect(genericQtHost.contains("QString promptAssistantBody(const QString &promptTitle, const QJsonObject &payload)"))
        #expect(genericQtHost.contains("jsonArrayValue(chatBehaviorPayload(payload), \"modelMenuNames\")"))
        #expect(genericQtHost.contains("jsonArrayValue(chatBehaviorPayload(payload), \"promptResponses\")"))
        #expect(genericQtHost.contains("\"fallbackAssistantReply\""))
        #expect(genericQtHost.contains("initializeSelectedChatModelName(payload)"))
        #expect(genericQtHost.contains("showModelSelectionMenu(button, payload)"))
        #expect(genericQtHost.contains("editor->property(\"composerHandlerInstalled\").toBool()"))
        #expect(genericQtHost.contains("QObject::connect(editor, &QLineEdit::returnPressed"))
        #expect(genericQtHost.contains("persistPromptConversation(promptTitle, payload)"))
        #expect(genericQtHost.contains("populatePromptConversationContent(detailPane.contentLayout, promptTitle, style, payload)"))
        #expect(!genericQtHost.contains("Use **flexbox**: set display to flex"))
        #expect(genericQtHost.contains("QLineEdit#composerEditor { background: transparent; color: %5; border: 0; padding-left: 0; padding-right: 0; }"))
        #expect(genericQtHost.contains("QLabel#composerAccessoryIcon { background: transparent; border: 0; }"))
        #expect(genericQtHost.contains("QFrame *frame = QuillQtWidgets::frame(QStringLiteral(\"composerFrame\"))"))
        #expect(genericQtHost.contains("const int horizontalPadding = intValue(style, \"composerHorizontalPadding\", 14)"))
        #expect(genericQtHost.contains("frameLayout->setSpacing(intValue(style, \"composerAccessorySpacing\", 8))"))
        #expect(genericQtHost.contains("accessory->setObjectName(QStringLiteral(\"composerAccessoryIcon\"))"))
        #expect(genericQtHost.contains("const int accessorySize = intValue(style, \"composerAccessoryIconSize\", 24)"))
        #expect(genericQtHost.contains("systemImageIcon(QStringLiteral(\"waveform\")).pixmap(accessorySize, accessorySize)"))
        #expect(genericQtHost.contains("applyAccessibleText(accessory, QStringLiteral(\"Voice input\"), QStringLiteral(\"Voice input\"))"))
        #expect(genericQtHost.contains("#include <cstdlib>"))
        #expect(genericQtHost.contains("std::getenv(\"QUILLUI_GENERIC_QT_ACTIVE_NAVIGATION\")"))
        #expect(genericQtHost.contains("std::getenv(\"QUILLUI_GENERIC_QT_AUTOMATION_CLICK_NAVIGATION\")"))
        #expect(genericQtHost.contains("QString automationNavigationClickIdentifier()"))
        #expect(genericQtHost.contains("QString activeNavigationIdentifier(const QJsonObject &payload)"))
        #expect(genericQtHost.contains("QuillQtWidgets::environmentValue(\"QUILLUI_GENERIC_QT_METRIC_SCALE\")"))
        #expect(genericQtHost.contains("QuillQtWidgets::environmentFlag(\"QUILLUI_BACKEND_MAC_REFERENCE\")"))
        #expect(genericQtHost.contains("QuillQtWidgets::environmentFlag(\"QUILLUI_QT_MAC_REFERENCE\")"))
        #expect(genericQtHost.contains("bool macReferenceMode()"))
        #expect(genericQtHost.contains("return 2.0;"))
        #expect(genericQtHost.contains("QString::fromUtf8(key) == QStringLiteral(\"sidebarColor\")"))
        #expect(genericQtHost.contains("return QStringLiteral(\"#EEF2EA\")"))
        #expect(genericQtHost.contains("name != QStringLiteral(\"selectedindex\")"))
        #expect(genericQtHost.contains("name != QStringLiteral(\"headerheight\")"))
        #expect(genericQtHost.contains("name == QStringLiteral(\"settingspanelminwidth\")"))
        #expect(genericQtHost.contains("return 860;"))
        #expect(genericQtHost.contains("name == QStringLiteral(\"settingspanelmaxwidth\")"))
        #expect(genericQtHost.contains("return 900;"))
        #expect(genericQtHost.contains("name == QStringLiteral(\"settingspanelpadding\")"))
        #expect(genericQtHost.contains("name == QStringLiteral(\"settingspanelspacing\")"))
        #expect(genericQtHost.contains("name == QStringLiteral(\"settingsfieldspacing\")"))
        #expect(genericQtHost.contains("name == QStringLiteral(\"settingsfieldminheight\")"))
        #expect(genericQtHost.contains("!name.endsWith(QStringLiteral(\"weight\"))"))
        #expect(genericQtHost.contains("!name.endsWith(QStringLiteral(\"columns\"))"))
        #expect(genericQtHost.contains("std::lround(static_cast<double>(value) * scale)"))
        #expect(genericQtHost.contains("QFrame#settingsPanel { background: %1; border: 0; border-radius: %2; }"))
        #expect(genericQtHost.contains("QLineEdit#settingsField { background: white; color: %5; border: 1px solid %6; border-radius: %2; padding: %8; }"))
        #expect(genericQtHost.contains("QPushButton#settingsOptionButton { background: white; color: %5; border: 1px solid %6; border-radius: %2; padding: %8; }"))
        #expect(genericQtHost.contains("QPushButton#settingsPrimaryButton { background: %5; color: white; border: 0; border-radius: %2; padding: %8; font-weight: 650; }"))
        #expect(genericQtHost.contains("QFrame *settingsPaneWidget(const QJsonObject &payload, const QJsonObject &style)"))
        #expect(genericQtHost.contains("settingsValue(payload, \"endpointLabel\", QStringLiteral(\"Quill API endpoint\"))"))
        #expect(genericQtHost.contains("settingsValue(payload, \"systemPromptLabel\", QStringLiteral(\"System prompt\"))"))
        #expect(genericQtHost.contains("settingsValue(payload, \"bearerTokenLabel\", QStringLiteral(\"Bearer Token\"))"))
        #expect(genericQtHost.contains("settingsValue(payload, \"pingIntervalLabel\", QStringLiteral(\"Ping Interval (seconds)\"))"))
        #expect(genericQtHost.contains("settingsValue(payload, \"appearanceLabel\", QStringLiteral(\"Appearance\"))"))
        #expect(genericQtHost.contains("settingsValue(payload, \"initialsLabel\", QStringLiteral(\"Initials\"))"))
        #expect(genericQtHost.contains("void populateSettingsContent("))
        #expect(genericQtHost.contains("QFrame *utilityPaneWidget("))
        #expect(genericQtHost.contains("QString defaultNavigationSubtitle(const QString &navigationAction)"))
        #expect(genericQtHost.contains("Prompt completions use the shared Enchanted profile."))
        #expect(genericQtHost.contains("Keyboard shortcuts use the shared QuillKit shortcut surface."))
        #expect(genericQtHost.contains("No completions yet."))
        #expect(genericQtHost.contains("No shortcuts yet."))
        #expect(genericQtHost.contains("void populateUtilityContent("))
        #expect(genericQtHost.contains("void populateNavigationContent("))
        #expect(genericQtHost.contains("const QString activeNavigation = activeNavigationIdentifier(payload)"))
        #expect(genericQtHost.contains("if (chatMode && !activeNavigation.isEmpty())"))
        #expect(genericQtHost.contains("button->property(\"navigationAction\").toString()"))
        #expect(genericQtHost.contains("populateNavigationContent(\n                    detailPane.contentLayout"))
        #expect(genericQtHost.contains("button->property(\"navigationTitle\").toString()"))
        #expect(genericQtHost.contains("button->property(\"navigationSubtitle\").toString()"))
        #expect(genericQtHost.contains("QTimer::singleShot(250, &root"))
        #expect(genericQtHost.contains("button->click()"))
        #expect(genericQtHost.contains("headerIconButton(\n        QStringLiteral(\"chevron.down\")"))
        #expect(genericQtHost.contains("headerIconButton(\n        QStringLiteral(\"ellipsis\")"))
        #expect(genericQtHost.contains("headerIconButton(\n        QStringLiteral(\"square.and.pencil\")"))
        #expect(genericQtHost.contains("newChatButton->setProperty(\"chatHeaderAction\", QStringLiteral(\"newChat\"))"))
        #expect(genericQtHost.contains("const QString navigationAction = button->property(\"navigationAction\").toString()"))
        #expect(genericQtHost.contains("populateNavigationContent(\n                        detailPane.contentLayout"))
        #expect(genericQtHost.contains("chatHeaderAction == QStringLiteral(\"newChat\")"))
        #expect(genericQtHost.contains("itemList->clearSelection()"))
        #expect(genericQtHost.contains("itemList->setCurrentRow(-1)"))
        #expect(genericQtHost.contains("applySelection(detailPane, selectionForRow(payload, items, -1), payload, style, chatMode)"))
        #expect(!genericQtHost.contains("QLabel *toolbar = label(QStringLiteral(\"...\"), QStringLiteral(\"caption\"))"))
        #expect(!genericQtHost.contains("QSize minimumWindowSize(const QJsonObject &payload)"))
        #expect(!genericQtHost.contains("QSize defaultWindowSize(const QJsonObject &payload"))
        #expect(genericQtHost.contains("QString accessibilitySummary(const QString &title, const QString &detail)"))
        #expect(genericQtHost.contains("void applyAccessibleText(QWidget *widget, const QString &name, const QString &description = QString())"))
        #expect(genericQtHost.contains("widget->setAccessibleName(name.isEmpty() ? summary : name)"))
        #expect(genericQtHost.contains("widget->setAccessibleDescription(summary)"))
        #expect(genericQtHost.contains("widget->setToolTip(summary)"))
        #expect(genericQtHost.contains("widget->setStatusTip(summary)"))
        #expect(genericQtHost.contains("applyAccessibleText(row, titleText, rowSummary)"))
        #expect(genericQtHost.contains("applyAccessibleText(list, QStringLiteral(\"App items\"), QStringLiteral(\"App items\"))"))
        #expect(genericQtHost.contains("QString elidedChatSidebarText(const QString &text, const QJsonObject &style)"))
        #expect(genericQtHost.contains("intValue(style, \"chatSidebarTitleMaxWidth\", 180)"))
        #expect(genericQtHost.contains("QFontMetrics(probe.font()).elidedText(text, Qt::ElideRight, maximumWidth)"))
        #expect(genericQtHost.contains("applyAccessibleText(primary, primaryActionTitle, primaryActionTitle)"))
        #expect(genericQtHost.contains("applyAccessibleText(secondary, secondaryActionTitle, secondaryActionTitle)"))
        #expect(genericQtHost.contains("applyAccessibleText(card, titleText, cardSummary)"))
        #expect(genericQtHost.contains("applyAccessibleText(card, senderText, cardSummary)"))
        #expect(genericQtHost.contains("applyAccessibleText(detailPane.view, selection.detailTitle, detailSummary)"))
        #expect(genericQtHost.contains("applyAccessibleText(&root, windowTitle, windowTitle)"))
        #expect(wireGuardQtRuntime.contains("import QuillQtNativeRuntimeSupport"))
        #expect(wireGuardQtRuntime.contains("QuillQtNativeRuntimeSupport.runEncodedPayload("))
        #expect(wireGuardQtRuntime.contains("executableName: QuillQtNativeRuntimeSupport.executableName(fallback: \"quill-wireguard-qt\")"))
        #expect(wireGuardQtHost.contains("parseJsonObjectPayload("))
        #expect(wireGuardQtHost.contains("QuillQtWidgets::executableNameBytes(argc, argv, \"quill-wireguard-qt\")"))
        #expect(wireGuardQtHost.contains("QuillQtWidgets::minimumWindowSize(payload, 900, 600)"))
        #expect(wireGuardQtHost.contains("QuillQtWidgets::defaultWindowSize(payload, minimumWindowSize)"))
        #expect(!wireGuardQtHost.contains("QSize resolvedMinimumWindowSize"))
        #expect(!wireGuardQtHost.contains("QSize resolvedDefaultWindowSize"))
        #expect(!genericQtRuntime.contains("JSONEncoder()"))
        #expect(!wireGuardQtRuntime.contains("JSONEncoder()"))
        #expect(!enchantedQtHost.contains("missing payload JSON"))
        #expect(!enchantedQtHost.contains("invalid payload JSON at offset"))
        #expect(!genericQtHost.contains("missing payload JSON"))
        #expect(!genericQtHost.contains("invalid payload JSON at offset"))
        #expect(!wireGuardQtHost.contains("QJsonDocument document = QJsonDocument::fromJson(QByteArray(payload_json)"))
        #expect(enchantedQtHost.contains("QObject::connect(conversationList, &QListWidget::currentRowChanged"))
        #expect(genericQtHost.contains("QObject::connect(itemList, &QListWidget::currentRowChanged"))
        #expect(genericQtHost.contains("struct GenericSelection"))
        #expect(genericQtHost.contains("GenericSelection selectionForRow(const QJsonObject &payload, const QJsonArray &items, int row)"))
        #expect(genericQtHost.contains("bool hasSelection;"))
        #expect(genericQtHost.contains("bool preservesHeaderTitle;"))
        #expect(genericQtHost.contains("QFrame *chatSelectionDotWidget(const QJsonObject &style)"))
        #expect(genericQtHost.contains("const int dotSize = intValue(style, \"conversationSelectionDotSize\", 8)"))
        #expect(genericQtHost.contains("void updateChatSelectionDots(QListWidget *list)"))
        #expect(genericQtHost.contains("QFrame *dot = rowWidget->findChild<QFrame *>(QStringLiteral(\"chatSelectionDot\"))"))
        #expect(genericQtHost.contains("dot->setProperty(\"selected\", isSelected)"))
        #expect(genericQtHost.contains("refreshDynamicStyle(dot)"))
        #expect(genericQtHost.contains("updateChatSelectionDots(list)"))
        #expect(genericQtHost.contains("QString chatMessageRole(const QJsonObject &message)"))
        #expect(genericQtHost.contains("QString chatMessageBody(const QJsonObject &message)"))
        #expect(genericQtHost.contains("QWidget *chatMessageWidget(const QJsonObject &message, const QJsonObject &style)"))
        #expect(genericQtHost.contains("populateChatMessages(layout, selection.messages, style)"))
        #expect(genericQtHost.contains("void applySelection(\n    GenericDetailPane &detailPane"))
        #expect(genericQtHost.contains("populateEmptyStateContent(detailPane.contentLayout, payload, style)"))
        #expect(genericQtHost.contains("applySelection(detailPane, selectionForRow(payload, items, row), payload, style, chatMode)"))
        #expect(genericQtHost.contains("populateDetailContent(detailPane.contentLayout, selection, style, chatMode)"))
        #expect(genericQtHost.contains("selection.sections"))
        #expect(genericQtHost.contains("selection.messages"))
        #expect(genericQtHost.contains("boundedSelectedIndex("))
        #expect(genericQtHost.contains("const int selectedIndex = boundedSelectedIndex(items, rawSelectedIndex, chatMode)"))
        #expect(genericQtHost.contains("item.contains(QStringLiteral(\"sections\"))"))
        #expect(genericQtHost.contains("item.contains(QStringLiteral(\"messages\"))"))
        #expect(genericQtRuntime.contains("selectedIndex: -1,\n        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific("))
        #expect(genericQtRuntime.contains("public var sections: [Section]?"))
        #expect(genericQtRuntime.contains("public var messages: [Message]?"))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Open conversation with replies and boosts.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Weekend photo thread with media previews.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Desktop compatibility article selected for reading.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Project navigator source file selected.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Core engineering channel with the lower row selected.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Audio-only playlist item selected.\""))

        let qtVisiblePayloadSources = [
            ("Generic Qt runtime", genericQtRuntime)
        ]
        let internalVisibleCopyFragments = [
            "QUILLUI_LINUX_BACKEND",
            "SwiftPM",
            "Qt backend",
            "Qt graph",
            "GTK path",
            "GTK shell",
            "GTK preview",
            "screenshot smoke",
            "smoke target",
            "smoke capture",
            "fixture",
            "backend parity",
            "QuillUI is rendering",
            "Codable snapshot"
        ]
        for (sourceName, source) in qtVisiblePayloadSources {
            for fragment in internalVisibleCopyFragments {
                #expect(!source.contains(fragment), "\(sourceName) should not expose internal test/backend copy: \(fragment)")
            }
        }
    }

    @Test("Linux backend facades scripts and workflows stay backend neutral")
    func linuxBackendFacadesScriptsAndWorkflowsStayBackendNeutral() throws {
        let sharedView = try packageSource("Sources/QuillInteractionSmokeSupport/QuillInteractionSmokeView.swift")
        let backendCore = try packageSource("Sources/QuillUI/QuillBackend.swift")
        let appCore = try packageSource("Sources/QuillUI/QuillApp.swift")
        let gtkBackend = try packageSource("Sources/QuillUIGtk/QuillUIGtk.swift")
        let qtBackend = try packageSource("Sources/QuillUIQt/QuillUIQt.swift")
        let swiftOpenUICommands = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/App/Commands.swift")
        let swiftOpenUIButton = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/Button.swift")
        let swiftOpenUIGroup = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/Group.swift")
        let swiftOpenUIGTKBackend = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4Backend.swift")
        let quillUICompatibility = try packageSource("Sources/QuillUI/UpstreamCompatibility.swift")
        let backendScript = try packageSource("scripts/linux-backend-interaction-check.sh")
        let backendCheckScript = try packageSource("scripts/linux-backend-check.sh")
        let backendProfileScript = try packageSource("scripts/linux-backend-profile.sh")
        let backendVisualScript = try packageSource("scripts/linux-backend-visual-check.sh")
        let smokeLib = try packageSource("scripts/quillui-linux-backend-smoke-lib.sh")
        let backendProducts = try packageSource("scripts/quillui-backend-products.sh")
        let smokeMatrixRunner = try packageSource("scripts/run-linux-backend-smoke-matrix.sh")
        let profileMatrixRunner = try packageSource("scripts/run-linux-backend-profile-csv.sh")
        let interactionModeRunner = try packageSource("scripts/run-linux-backend-interaction-modes.sh")
        let functionalScript = try packageSource("scripts/quill-chat-functional-check.sh")
        let solderScopeSmoke = try packageSource("scripts/linux-solderscope-smoke-check.sh")
        let screenshotVerifier = try packageSource("scripts/verify-backend-screenshot.py")
        let legacyScreenshotVerifier = try packageSource("scripts/verify-gtk-screenshot.py")
        let legacyGtkScript = try packageSource("scripts/linux-gtk-interaction-check.sh")
        let fetchUpstream = try packageSource("scripts/fetch-upstream.sh")
        let workflow = try packageSource(".github/workflows/linux-ci.yml")
        let solderScopeWorkflow = try packageSource(".github/workflows/solderscope-ci.yml")
        let macOSWorkflow = try packageSource(".github/workflows/macos-ci.yml")

        #expect(sharedView.contains("public struct QuillInteractionSmokeConfiguration"))
        #expect(sharedView.contains("public struct QuillInteractionSmokeView"))
        #expect(sharedView.contains("public enum QuillInteractionSmokeScene"))
        #expect(sharedView.contains("public struct QuillBackendInteractionSmokeApp<Backend: QuillBackend>: App"))
        #expect(sharedView.contains("QuillInteractionSmokeScene.scene(for: Backend.identifier)"))
        #expect(sharedView.contains("defaultSizePolicy: .requested"))
        #expect(sharedView.contains("backendParitySurface"))
        #expect(sharedView.contains("QuillAppWindow.scene("))
        #expect(sharedView.contains("Quill Backend Interaction"))
        #expect(sharedView.contains("Native backend click target"))
        #expect(sharedView.contains("native backend button click"))
        #expect(sharedView.contains("private struct SmokeSheetContent"))
        #expect(sharedView.contains("SmokeSheetContent("))
        #expect(sharedView.contains("QuillSheetStatusBanner("))
        #expect(sharedView.contains("A Quill sheet status banner presented this sheet."))
        #expect(backendScript.contains("INTERACTION_ATTEMPT=\"${QUILLUI_BACKEND_INTERACTION_ATTEMPT:-1}\""))
        #expect(backendScript.contains("retry_backend_interaction_if_transient()"))
        #expect(backendScript.contains("if kill -0 \"${app_pid:-}\" 2>/dev/null; then"))
        #expect(backendScript.contains("exec \"$0\" \"$SCREENSHOT_PATH\" \"$PRODUCT\" \"$REQUESTED_BACKEND\""))
        #expect(backendScript.contains("&& \"$INTERACTION_MODE\" == \"settings-default-model-selected\""))
        #expect(backendScript.contains("INTERACTION_MAX_ATTEMPTS=4"))
        #expect(backendScript.contains("attempt $INTERACTION_ATTEMPT/$INTERACTION_MAX_ATTEMPTS); retrying"))
        #expect(!backendScript.contains("retrying once"))
        #expect(backendCore.contains("static var status: QuillBackendRuntimeStatus"))
        #expect(backendCore.contains("QuillBackendRegistry.runtimeStatus(preferred: identifier)"))
        #expect(backendCore.contains("public static func runtimeStatus("))
        #expect(backendCore.contains("public struct QuillBackendRuntimeAvailability"))
        #expect(backendCore.contains("public static var runtimeAvailabilities: [QuillBackendRuntimeAvailability]"))
        #expect(backendCore.contains("public static func runtimeAvailability("))
        #expect(appCore.contains("static func run<A: App>(_ appType: A.Type)"))
        #expect(appCore.contains("QuillBackendApp<Self>.run(appType)"))
        #expect(gtkBackend.contains("@_exported import QuillUI"))
        #expect(gtkBackend.contains("public enum QuillGtkBackend"))
        #expect(gtkBackend.contains("public typealias QuillGtkApp = QuillBackendApp<QuillGtkBackend>"))
        #expect(gtkBackend.contains("public typealias QuillGtkRuntimeAvailability = QuillBackendRuntimeAvailability"))
        #expect(gtkBackend.contains("public typealias QuillGtkBackendStatus = QuillBackendRuntimeStatus"))
        #expect(!gtkBackend.contains("public static var status"))
        #expect(!gtkBackend.contains("runtimeStatus"))
        #expect(!gtkBackend.contains("static func run<A: App>"))
        #expect(!gtkBackend.contains("QuillGtkBackend.run(appType)"))
        #expect(swiftOpenUICommands.contains("public static func buildBlock<C0: Commands, C1: Commands, C2: Commands>"))
        #expect(swiftOpenUICommands.contains("public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands>"))
        #expect(swiftOpenUICommands.contains("@_disfavoredOverload\n\tpublic static func buildBlock(_ components: any Commands...)"))
        #expect(swiftOpenUICommands.contains("public static func buildOptional<C: Commands>(_ component: C?) -> CommandCollection"))
        #expect(swiftOpenUICommands.contains("public static func buildEither<C: Commands>(first component: C) -> CommandCollection"))
        #expect(swiftOpenUICommands.contains("commandMenuItems(from: view)"))
        #expect(swiftOpenUICommands.contains("CommandMenuConditionalRepresentable"))
        #expect(swiftOpenUICommands.contains("CommandMenuOptionalRepresentable"))
        #expect(swiftOpenUICommands.contains("return commandMenuItems(from: conditional.commandMenuActiveContent)"))
        #expect(swiftOpenUICommands.contains("return commandMenuItems(from: content)"))
        #expect(swiftOpenUICommands.contains("commandsDebugLog(\"commands factory invoked type=\\(C.self) placements=\\(groups.count) items=\\(itemCount)\")"))
        #expect(swiftOpenUICommands.contains("extension Group: TupleCommandsProtocol where Content: Commands"))
        #expect(swiftOpenUICommands.contains("collectCommandGroups(content, into: &result)"))
        #expect(quillUICompatibility.contains("QuillConditionalViewRepresentable"))
        #expect(quillUICompatibility.contains("QuillOptionalViewRepresentable"))
        #expect(quillUICompatibility.contains("return quillCommandMenuItems(from: conditional.quillActiveContent)"))
        #expect(quillUICompatibility.contains("return quillCommandMenuItems(from: content)"))
        #expect(swiftOpenUIButton.contains("public init(_ title: String, systemImage: String, action: @escaping () -> Void)"))
        #expect(swiftOpenUIButton.contains("SwiftOpenUI.Label(title, systemImage: systemImage)"))
        #expect(swiftOpenUIGroup.contains("extension Group: Commands where Content: Commands"))
        #expect(swiftOpenUIGroup.contains("public init(@CommandsBuilder content: () -> Content)"))
        #expect(swiftOpenUIGTKBackend.contains("gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE)"))
        #expect(swiftOpenUIGTKBackend.contains("KeyboardShortcutRegistry.shared.dispatch(shortcut, windowID: windowID)"))
        #expect(qtBackend.contains("@_exported import QuillUI"))
        #expect(qtBackend.contains("public enum QuillQtBackend"))
        #expect(qtBackend.contains("public typealias QuillQtApp = QuillBackendApp<QuillQtBackend>"))
        #expect(qtBackend.contains("public typealias QuillQtRuntimeAvailability = QuillBackendRuntimeAvailability"))
        #expect(qtBackend.contains("public typealias QuillQtBackendStatus = QuillBackendRuntimeStatus"))
        #expect(!qtBackend.contains("public static var status"))
        #expect(!qtBackend.contains("runtimeStatus"))
        #expect(!qtBackend.contains("static func run<A: App>"))
        #expect(!qtBackend.contains("QuillQtBackend.run(appType)"))
        #expect(workflow.contains("swift build --scratch-path .build-linux --target QuillUIGtk"))
        #expect(workflow.contains("swift build --scratch-path .build-linux --target QuillUIQt"))
        #expect(macOSWorkflow.contains("swift build --target QuillUIGtk"))
        #expect(macOSWorkflow.contains("swift build --target QuillUIQt"))
        #expect(!macOSWorkflow.contains("swift build --target QuillGtkInteractionSmoke"))
        #expect(!macOSWorkflow.contains("swift build --target QuillQtInteractionSmoke"))

        #expect(backendScript.contains("REQUESTED_BACKEND=\"${3:-${QUILLUI_BACKEND:-}}\""))
        #expect(backendScript.contains("quillui_export_backend_argument \"$REQUESTED_BACKEND\" \"$PRODUCT\""))
        #expect(backendScript.contains("quillui_alias_backend_build_env"))
        #expect(backendScript.contains("quillui_alias_backend_interaction_env"))
        #expect(backendScript.contains("quill-backend-interaction-smoke-open.png"))
        #expect(backendScript.contains("/tmp/quillui-backend-interaction-app.log"))
        #expect(backendScript.contains("APP_LOG_PATH=\"${QUILLUI_BACKEND_INTERACTION_APP_LOG:-/tmp/quillui-backend-interaction-app.log}\""))
        #expect(backendScript.contains("quillui_print_backend_app_log_tail \"$APP_LOG_PATH\" \"${QUILLUI_BACKEND_INTERACTION_APP_LOG_LINES:-80}\""))
        #expect(backendScript.contains(">\"$APP_LOG_PATH\" 2>&1 &"))
        #expect(backendScript.contains("QUILLUI_GTK_DEBUG_ACTIONS=${QUILLUI_GTK_DEBUG_ACTIONS:-1}"))
        #expect(backendScript.contains("\"$INTERACTION_MODE\" == \"completions-new-sheet\""))
        #expect(!backendScript.contains("/tmp/quillui-gtk-interaction-app.log"))
        #expect(backendScript.contains("INTERACTION_MODE=\"$(quillui_backend_default_interaction_mode_for_product \"$PRODUCT\")\""))
        #expect(backendProducts.contains("quillui_backend_default_interaction_mode_for_product()"))
        #expect(backendProducts.contains("default-interaction-mode)"))
        #expect(backendProducts.contains("quillui_backend_visual_verify_product_for_product()"))
        #expect(backendProducts.contains("visual-verify-product)"))
        #expect(backendProducts.contains("quillui_is_quill_chat_mac_reference_product()"))
        #expect(backendProducts.contains("quillui_backend_app_interaction_verify_product_for_product()"))
        #expect(backendProducts.contains("quillui_backend_enchanted_linux_interaction_verify_product()"))
        #expect(backendProducts.contains("quillui_backend_quill_chat_interaction_verify_product()"))
        #expect(backendProducts.contains("quillui_backend_quill_chat_mac_reference_interaction_modes()"))
        #expect(backendProducts.contains("quill-chat-mac-reference-interaction-modes)"))
        #expect(backendProducts.contains("quillui_backend_wireguard_interaction_verify_product()"))
        #expect(backendProducts.contains("app-interaction-verify-product)"))
        #expect(backendProducts.contains("verify_product=\"quill-enchanted-linux-$selected_backend\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-toolbar-menu\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-toolbar-menu\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-composer-typed\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-settings-panel\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-settings-endpoint-typed\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-settings-bearer-token-typed\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-settings-ping-interval-typed\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-settings-default-model-selected\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-settings-delete-confirmation\""))
        #expect(backendProducts.contains("*:settings-delete-confirmed)"))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-completions-panel\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-completions-new-sheet\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-completions-saved\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-completions-edited\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-completions-deleted\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-history-selection\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-transcript-selection\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-markdown-transcript-selection\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-long-transcript-selection\""))
        #expect(backendProducts.contains("*:long-transcript-selection|*:long-transcript-auto-selection)"))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-prompt-send\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-composer-send\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-attachment-send\""))
        #expect(functionalScript.components(separatedBy: "def message_content_matches").count >= 4)
        #expect(functionalScript.components(separatedBy: "QUILLUI_FUNCTIONAL_MESSAGE_MIN_PREFIX").count >= 4)
        #expect(functionalScript.contains("expected.startswith(content)"))
        #expect(functionalScript.contains("Quill Chat functional relaunch:"))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-new-chat\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-copy-chat\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-copy-chat-json\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-toolbar-model-selected\""))
        #expect(backendProducts.contains("*:composer-send)"))
        #expect(backendProducts.contains("*:attachment-send|*:image-attachment-send)"))
        #expect(backendProducts.contains("*:new-chat)"))
        #expect(backendProducts.contains("*:copy-chat)"))
        #expect(backendProducts.contains("*:copy-chat-json)"))
        #expect(backendProducts.contains("*:toolbar-model-selected)"))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-qt-tunnel-selection\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-qt-name-edit\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-qt-import-paste\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-qt-import-file\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-qt-import-invalid-paste\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-qt-import-invalid-file\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-name-edit\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-import-paste\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-import-file\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-import-invalid-paste\""))
        #expect(backendProducts.contains("verify_product=\"quill-wireguard-import-invalid-file\""))
        #expect(backendScript.contains("[[ \"$PRODUCT\" == \"quill-wireguard\" && \"$SELECTED_BACKEND\" == \"gtk\" ]]"))
        #expect(backendScript.contains("[[ \"$PRODUCT\" == \"quill-wireguard\" && \"$SELECTED_BACKEND\" == \"qt\" ]]"))
        #expect(!backendScript.contains("quill-wireguard|quill-wireguard-qt)"))
        #expect(backendScript.contains("wireguard_import_configuration()"))
        #expect(backendScript.contains("wireguard_malformed_import_configuration()"))
        #expect(backendScript.contains("wireguard_malformed_import_configuration_file()"))
        #expect(backendScript.contains("wireguard_import_configuration_for_mode()"))
        #expect(backendScript.contains("wireguard_import_configuration_file_for_mode()"))
        #expect(backendScript.contains("QUILLUI_BACKEND_MALFORMED_IMPORT_CONFIGURATION"))
        #expect(backendScript.contains("QUILLUI_BACKEND_MALFORMED_IMPORT_CONFIGURATION_FILE"))
        #expect(backendScript.contains("QUILLUI_BACKEND_IMPORT_CONFIGURATION_FILE"))
        #expect(backendScript.contains("Tests/Fixtures/WireGuard/imported-edge.conf"))
        #expect(backendScript.contains("WireGuard import fixture is missing"))
        #expect(backendScript.contains("tunnel-name-edit|name-edit"))
        #expect(backendScript.contains("import-paste|paste-import"))
        #expect(backendScript.contains("import-invalid-paste|invalid-paste-import|import-malformed-paste|malformed-paste-import"))
        #expect(backendScript.contains("import-invalid-file|invalid-file-import|import-malformed-file|malformed-file-import"))
        #expect(backendScript.contains("import-file|file-import|import-invalid-file"))
        #expect(backendScript.contains("wireguard_import_configuration_file()"))
        #expect(backendScript.contains("wireguard_import_configuration_prefill_file_for_mode()"))
        #expect(backendScript.contains("QUILLUI_WIREGUARD_IMPORT_CONFIGURATION_FILE_ON_START=$import_file"))
        #expect(backendScript.contains("wireguard_gtk_import_uses_prefill=1"))
        #expect(backendScript.contains("QUILLUI_WIREGUARD_QT_IMPORT_CONFIGURATION_FILE_ON_START=$import_file"))
        #expect(backendScript.contains("QUILLUI_WIREGUARD_QT_IMPORT_DIALOG_ON_START=1"))
        #expect(backendScript.contains("QUILLUI_BACKEND_NAME_CLICK_X"))
        #expect(backendScript.contains("QUILLUI_BACKEND_IMPORT_EDITOR_X"))
        // The GTK paste import submits via Ctrl+Return (asserted below), not a
        // positional submit click — the Import button is occluded by the
        // expanding TextEditor, so no QUILLUI_BACKEND_IMPORT_SUBMIT_CLICK_* hook.
        #expect(!backendScript.contains("QUILLUI_BACKEND_IMPORT_SUBMIT_CLICK_X"))
        #expect(backendScript.contains("import_configuration=\"$(wireguard_import_configuration_for_mode \"$INTERACTION_MODE\")\" || exit $?"))
        #expect(backendScript.contains("xdotool key --clearmodifiers ctrl+a"))
        #expect(backendScript.contains("xdotool key --clearmodifiers ctrl+Return"))
        #expect(backendScript.contains("Unsupported WireGuard GTK interaction mode"))
        #expect(backendScript.contains("Unsupported WireGuard Qt interaction mode"))
        #expect(backendScript.contains("quillui_backend_reference_window_defaults"))
        #expect(!backendScript.contains("reference_window_width=\"${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}\""))
        #expect(backendScript.contains("quillui_backend_screen_size \"$PRODUCT\" \"${QUILLUI_BACKEND_INTERACTION_SCREEN_SIZE:-}\""))
        // Interaction clicks must wait for a mapped, plausibly-sized app
        // window (poll) rather than a one-shot pid lookup — the one-shot
        // raced slow app startup on CI and clicked screen-sized geometry.
        #expect(backendScript.contains("quillui_wait_for_app_window_for_pid \"$DISPLAY_ID\" \"$app_pid\""))
        #expect(backendScript.contains("QUILLUI_BACKEND_WINDOW_WAIT_SECONDS"))
        #expect(backendScript.contains("quillui_find_visible_window_by_name \"$DISPLAY_ID\" \".*\""))
        #expect(backendScript.contains("quillui_place_reference_window \"$DISPLAY_ID\" \"$window_id\""))
        #expect(backendScript.contains("quillui_append_backend_runtime_environment"))
        #expect(backendScript.contains("\"$REQUESTED_BACKEND\""))
        #expect(backendScript.contains("quillui_is_quill_chat_mac_reference_product \"$PRODUCT\""))
        #expect(!backendScript.contains("is_quill_chat_mac_reference()"))
        #expect(!backendScript.contains("${QUILLUI_GTK_INTERACTION_MODE:-}"))
        #expect(!backendScript.contains("${QUILLUI_GTK_CLICK_X:-"))
        #expect(!backendScript.contains("${QUILLUI_GTK_VERIFY_PRODUCT:-"))
        #expect(backendScript.contains("xdotool is required for backend interaction smoke tests"))
        #expect(backendScript.contains("quillui_is_backend_smoke_product \"$PRODUCT\""))
        #expect(backendScript.contains("quillui_normalize_backend_smoke_interaction_mode \"$INTERACTION_MODE\""))
        #expect(backendScript.contains("quillui_is_backend_smoke_sheet_interaction \"$INTERACTION_MODE\""))
        let sheetHelperDefinition = backendScript.range(of: "quillui_is_backend_smoke_sheet_interaction()")
        let sheetHelperFirstUse = backendScript.range(of: "if quillui_is_backend_smoke_sheet_interaction \"$INTERACTION_MODE\"")
        #expect(sheetHelperDefinition != nil)
        #expect(sheetHelperFirstUse != nil)
        if let sheetHelperDefinition, let sheetHelperFirstUse {
            #expect(sheetHelperDefinition.lowerBound < sheetHelperFirstUse.lowerBound)
        }
        #expect(backendScript.contains("QUILLUI_GTK_SHEET_PRESENTATION=${QUILLUI_GTK_SHEET_PRESENTATION:-window}"))
        #expect(backendScript.contains("refresh_capture_window_for_active_child_window"))
        #expect(backendScript.contains("refresh_capture_window_for_sheet_interaction"))
        // The child-window refresh must run for found-window captures too
        // (smoke sheets present as separate ~900px toplevels) — no
        // capture==root gate. IM-popup misfires are filtered by the
        // minimum-size candidate gate instead.
        #expect(!backendScript.contains("[[ \"$capture_window\" == \"root\" ]] || return 0"))
        #expect(!backendScript.contains("[[ \"$capture_window\" != \"root\" ]] || return 0"))
        #expect(backendScript.contains("quillui_window_is_plausible_capture_target \"$DISPLAY_ID\" \"$candidate_window\" \"$window_id\""))
        #expect(backendScript.contains("quillui_find_visible_window_for_pid_except \"$DISPLAY_ID\" \"$app_pid\" \"$window_id\""))
        #expect(!backendScript.contains("quill-gtk-interaction-smoke|quill-qt-interaction-smoke"))
        #expect(backendScript.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(backendScript.contains("verify-backend-screenshot.py"))
        #expect(backendScript.contains("quill_chat_composer_click_x()"))
        #expect(backendScript.contains("quill_chat_composer_click_y()"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPOSER_CLICK_Y"))
        #expect(backendScript.contains("window_height - 135"))
        #expect(backendScript.contains("window_height - 326"))
        #expect(backendScript.contains("window_height - 80"))
        #expect(!backendScript.contains("window_height - 115"))
        #expect(!backendScript.contains("window_height - 76"))
        #expect(backendScript.contains("quillui_backend_interaction_verify_product \"$PRODUCT\" \"$INTERACTION_MODE\" VERIFY_PRODUCT"))
        #expect(screenshotVerifier.contains("text_pixels >= 120"))
        #expect(!screenshotVerifier.contains("text_pixels >= 25,\n        f\"Mac-reference typed composer text was not detected"))
        #expect(backendScript.contains("quill_chat_completions_panel_probe_path=\"\""))
        #expect(backendScript.contains("quill_chat_completion_save_uses_seed_fixture()"))
        #expect(backendScript.contains("quill_chat_completion_delete_uses_seed_fixture()"))
        #expect(backendScript.contains("if ! quill_chat_completion_save_uses_seed_fixture && ! quill_chat_completion_delete_uses_seed_fixture; then"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETION_SAVE_DRIVER:-seed"))
        #expect(backendScript.contains("generated_name = \"Linux Edited Completion\" if interaction_mode == \"completions-delete\" else \"Linux Saved Completion\""))
        #expect(backendScript.contains("seed_quill_chat_saved_completion_fixture_if_needed"))
        #expect(backendScript.contains("_quilldata_json_GeneratedSwiftUILinuxApp_CompletionInstructionSD"))
        #expect(backendScript.contains("Linux Saved Completion"))
        #expect(backendScript.contains("\"Fix Grammar\""))
        #expect(backendScript.contains("\"Politely Decline\""))
        #expect(backendScript.contains("quill_chat_completion_database_path()"))
        #expect(backendScript.contains("quill_chat_completion_seed_records_deleted()"))
        #expect(backendScript.contains("verify_quill_chat_completion_deleted_if_needed()"))
        #expect(backendScript.contains("Linux Edited Completion"))
        #expect(backendScript.contains("No CompletionInstructionSD table was found"))
        #expect(backendScript.contains("Completions delete removed seeded completion records"))
        #expect(backendScript.contains("quill_chat_completion_interaction_needs_settled_capture()"))
        #expect(backendScript.contains("completions-save|completions-edit-save|completions-delete"))
        #expect(backendScript.contains("settle_quill_chat_completion_capture_if_verified()"))
        #expect(backendScript.contains("if quill_chat_completion_interaction_needs_settled_capture \\\n    && quillui_backend_interaction_verify_product \"$PRODUCT\" \"$INTERACTION_MODE\" verify_product"))
        #expect(backendScript.contains("\"$probe_path\" \\\n      \"$verify_product\""))
        #expect(backendScript.contains("quillui_backend_interaction_verify_product \"$PRODUCT\" \"$INTERACTION_MODE\" verify_product"))
        #expect(backendScript.contains("cp -f \"$quill_chat_completions_panel_probe_path\" \"$SCREENSHOT_PATH\""))
        #expect(backendScript.contains("settled_capture_taken=1"))
        #expect(screenshotVerifier.contains("minimum_row_dividers=2,\n        minimum_wordmark_pixels=350,\n        minimum_row_action_segments=1"))
        #expect(!backendScript.contains("settle_quill_chat_completion_capture_if_verified\n      return 0"))
        #expect(backendScript.contains("save_x=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + 1450))}\""))
        #expect(backendScript.contains("save_y=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 410))}\""))
        #expect(backendScript.contains("edit_x=\"${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_X:-$((window_x + 1475))}\""))
        #expect(backendScript.contains("edit_y=\"${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_Y:-$((window_y + 545))}\""))
        #expect(backendScript.contains("delete_x=\"${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X:-$((window_x + 1510))}\""))
        #expect(backendScript.contains("delete_y=\"${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_Y:-$((window_y + 545))}\""))
        #expect(!backendScript.contains("edit_x=\"${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_X:-$((window_x + 1510))}\""))
        #expect(!backendScript.contains("delete_x=\"${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X:-$((window_x + 1545))}\""))
        #expect(!backendScript.contains("save_x=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + 1522))}\""))
        #expect(!backendScript.contains("save_y=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 383))}\""))
        #expect(backendScript.contains("if quill_chat_completion_save_uses_seed_fixture; then\n    quill_chat_completions_panel_probe_path=\"\"\n    ensure_quill_chat_completions_panel_open\n    settle_quill_chat_completion_capture_if_verified\n    return\n  fi"))
        #expect(!backendScript.contains("delete_quill_chat_completion() {\n  local delete_x\n  local delete_y\n\n  open_quill_chat_completions_panel\n"))
        #expect(backendScript.contains("quill_chat_completions_panel_probe_path=\"\"\n  ensure_quill_chat_completions_panel_open\n  settle_quill_chat_completion_capture_if_verified"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_OPEN_ATTEMPTS:-3"))
        #expect(backendScript.contains("for ((attempt = 1; attempt <= max_attempts; attempt += 1)); do"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_OPEN_RETRY_SLEEP:-0.8"))
        #expect(backendScript.contains("quill_chat_mac_reference_new_completion_click_target()"))
        #expect(backendScript.contains("quill_chat_mac_reference_first_completion_delete_click_target()"))
        #expect(backendScript.contains("quillui-image-click-target.py"))
        #expect(backendScript.contains("quill-chat-first-completion-delete"))
        #expect(backendScript.contains("&& [[ \"$target\" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then"))
        #expect(backendScript.contains("quillui_append_backend_selection_start_environment"))
        #expect(!backendScript.contains("app_environment+=(\"QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"))
        #expect(!backendScript.contains("app_environment+=(\"QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_SLEEP:-0.6"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_ESCAPE_SLEEP:-0.3"))
        #expect(backendScript.contains("QUILLUI_ACCESSIBILITY_TRUSTED=${QUILLUI_ACCESSIBILITY_TRUSTED:-1}"))
        #expect(backendScript.contains("QUILLUI_CHAT_SHOW_COMPLETIONS_ON_START=${QUILLUI_CHAT_SHOW_COMPLETIONS_ON_START:-1}"))
        #expect(backendScript.contains("reset_cancel_x=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_X:-$((window_x + 610))}}\""))
        #expect(backendScript.contains("reset_cancel_y=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_Y:-$((window_y + 416))}}\""))
        #expect(!backendScript.contains("reset_cancel_x=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_X:-$((window_x + 570))}}\""))
        #expect(!backendScript.contains("reset_cancel_x=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_X:-$((window_x + 568))}}\""))
        #expect(!backendScript.contains("reset_cancel_x=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_X:-$((window_x + 455))}}\""))
        #expect(!backendScript.contains("reset_cancel_y=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_Y:-$((window_y + 390))}}\""))
        #expect(!backendScript.contains("reset_cancel_y=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_Y:-$((window_y + 382))}}\""))
        #expect(backendScript.contains("edit_quill_chat_existing_completion() {\n  local edit_x\n  local edit_y\n  local name_x\n  local name_y\n  local save_x\n  local save_y\n\n  if quillui_is_quill_chat_mac_reference_product \"$PRODUCT\"; then\n    quill_chat_completions_panel_probe_path=\"\"\n    ensure_quill_chat_completions_panel_open\n  else\n    open_quill_chat_completions_panel 1\n  fi"))
        #expect(backendScript.contains("delete_quill_chat_completion() {"))
        #expect(backendScript.contains("local database_path"))
        #expect(backendScript.contains("local delete_attempt"))
        #expect(backendScript.contains("local delete_attempts=\"${QUILLUI_BACKEND_COMPLETION_DELETE_ATTEMPTS:-3}\""))
        #expect(backendScript.contains("local target"))
        #expect(backendScript.contains("if quillui_is_quill_chat_mac_reference_product \"$PRODUCT\"; then\n    quill_chat_completions_panel_probe_path=\"\"\n    ensure_quill_chat_completions_panel_open\n  else\n    open_quill_chat_completions_panel\n  fi"))
        #expect(backendScript.contains("read -r delete_x delete_y <<< \"$target\""))
        #expect(backendScript.contains("database_path=\"$(quill_chat_completion_database_path)\""))
        #expect(backendScript.contains("for ((delete_attempt = 1; delete_attempt <= delete_attempts; delete_attempt += 1)); do"))
        #expect(backendScript.contains("quill_chat_completion_seed_records_deleted \"$database_path\""))
        #expect(backendScript.contains("Completion delete attempt $delete_attempt did not remove the seeded row; retrying target"))
        #expect(backendScript.contains("name_y=\"${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 462))}\""))
        #expect(backendScript.contains("delete_x=\"${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X:-$((window_x + 1510))}\""))
        #expect(backendScript.contains("delete_y=\"${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_Y:-$((window_y + 545))}\""))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_TEXT"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y"))
        #expect(backendScript.contains("instruction_x=\"${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X:-$((window_x + 720))}\""))
        #expect(backendScript.contains("instruction_y=\"${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y:-$((window_y + 548))}\""))
        #expect(backendScript.contains("Reply with a concise Linux validation response."))
        #expect(!backendScript.contains("name_y=\"${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 468))}\""))
        #expect(backendScript.contains("run_list_selection_or_header_interaction()"))
        #expect(backendScript.contains("unsupported_backend_interaction_mode()"))
        #expect(backendScript.contains("backend_label_for_message()"))
        #expect(backendScript.contains("echo \"Unsupported $label interaction mode: $INTERACTION_MODE\" >&2"))
        #expect(backendScript.contains("[[ \"$PRODUCT\" == \"quill-enchanted\" && ( \"$SELECTED_BACKEND\" == \"gtk\" || \"$SELECTED_BACKEND\" == \"qt\" ) ]]"))
        #expect(backendScript.contains("run_list_selection_or_header_interaction \"Enchanted $(backend_label_for_message \"$SELECTED_BACKEND\")\" click_enchanted_list_selection"))
        #expect(backendScript.contains("quillui_is_backend_chat_gtk_list_selection_app_product \"$PRODUCT\""))
        #expect(backendScript.contains("run_list_selection_or_header_interaction \"chat GTK\" click_chat_list_selection"))
        #expect(backendScript.contains("quillui_is_backend_generic_gtk_list_selection_app_product \"$PRODUCT\""))
        #expect(backendScript.contains("run_list_selection_or_header_interaction \"generic GTK\" click_generic_backend_list_selection"))
        #expect(backendScript.contains("quillui_is_backend_generic_qt_app_product \"$PRODUCT\""))
        #expect(backendScript.contains("run_list_selection_or_header_interaction \"generic Qt\" click_generic_backend_list_selection"))
        #expect(!backendScript.contains("xdotool is required for GTK interaction smoke tests"))
        #expect(!backendScript.contains("verify-gtk-screenshot.py"))
        #expect(backendVisualScript.contains("REQUESTED_BACKEND=\"${3:-${QUILLUI_BACKEND:-}}\""))
        #expect(backendVisualScript.contains("quillui_export_backend_argument \"$REQUESTED_BACKEND\" \"$PRODUCT\""))
        #expect(backendVisualScript.contains("quillui_alias_backend_build_env"))
        #expect(backendVisualScript.contains("quillui_alias_backend_visual_env"))
        #expect(backendVisualScript.contains("quill-enchanted-backend.png"))
        #expect(backendVisualScript.contains("/tmp/quillui-backend-app.log"))
        #expect(backendVisualScript.contains("APP_LOG_PATH=\"${QUILLUI_BACKEND_VISUAL_APP_LOG:-/tmp/quillui-backend-app.log}\""))
        #expect(backendVisualScript.contains(">\"$APP_LOG_PATH\" 2>&1 &"))
        #expect(backendVisualScript.contains("quillui_print_backend_app_log_tail \"$APP_LOG_PATH\" \"${QUILLUI_BACKEND_VISUAL_APP_LOG_LINES:-80}\""))
        #expect(!backendVisualScript.contains("quill-enchanted-gtk.png"))
        #expect(!backendVisualScript.contains("/tmp/quillui-gtk-app.log"))
        #expect(backendVisualScript.contains("quillui_backend_reference_window_defaults"))
        #expect(!backendVisualScript.contains("reference_window_width=\"${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}\""))
        #expect(backendVisualScript.contains("quillui_is_quill_chat_mac_reference_product \"$PRODUCT\""))
        #expect(backendVisualScript.contains("quillui_find_visible_window_for_pid \"$DISPLAY_ID\" \"$app_pid\""))
        #expect(backendVisualScript.contains("quillui_find_visible_window_by_name \"$DISPLAY_ID\" \".*\""))
        #expect(backendVisualScript.contains("quillui_move_window_to_origin \"$DISPLAY_ID\" \"$window_id\""))
        #expect(backendVisualScript.contains("quillui_find_quill_chat_reference_window \"$DISPLAY_ID\""))
        #expect(backendVisualScript.contains("quillui_place_reference_window \"$DISPLAY_ID\" \"$window_id\""))
        #expect(!backendVisualScript.contains("is_quill_chat_mac_reference()"))
        #expect(backendVisualScript.contains("DISPLAY_ID=\"$(quillui_normalize_x_display_id \"${QUILLUI_BACKEND_VISUAL_DISPLAY:-:94}\")\""))
        #expect(backendVisualScript.contains("quillui_start_xvfb \"$DISPLAY_ID\" \"$SCREEN_SIZE\" /tmp/quillui-xvfb.log xvfb_pid"))
        #expect(backendVisualScript.contains("quillui_stop_process_if_running \"${app_pid:-}\""))
        #expect(backendVisualScript.contains("quillui_stop_process_if_running \"$xvfb_pid\""))
        #expect(backendVisualScript.contains("quillui_append_backend_runtime_environment"))
        #expect(backendVisualScript.contains("\"$REQUESTED_BACKEND\""))
        #expect(backendProfileScript.contains("quillui_append_enchanted_profile_fixture_environment_if_needed"))
        #expect(!backendProfileScript.contains("quillui_append_quill_chat_profile_fixture_environment_if_needed"))
        #expect(backendVisualScript.contains("quillui_backend_visual_verify_product \"$PRODUCT\" VERIFY_PRODUCT"))
        #expect(!backendVisualScript.contains("${QUILLUI_GTK_MAC_REFERENCE:-0}"))
        #expect(!backendVisualScript.contains("${QUILLUI_GTK_VISUAL_DISPLAY:-"))
        #expect(!backendVisualScript.contains("${QUILLUI_GTK_SCREEN_SIZE:-"))
        #expect(!backendVisualScript.contains("${QUILLUI_GTK_VERIFY_PRODUCT:-"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_SNAPSHOT_ACTIVE_SHORTCUT_FALLBACK"))
        #expect(solderScopeSmoke.contains("shortcut $label active key s"))
        #expect(smokeLib.contains("source \"$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(smokeLib.contains("quillui_export_backend_argument()"))
        #expect(smokeLib.contains("requested_backend=\"$(quillui_require_requested_backend_for_product \"$product\")\""))
        #expect(smokeLib.contains("requested_backend=\"$(quillui_validate_requested_backend_for_product \"$product\" \"$requested_backend\")\""))
        #expect(smokeLib.contains("quillui_alias_backend_build_env()"))
        #expect(smokeLib.contains("quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE QUILLUI_QT_APP_EXECUTABLE"))
        #expect(smokeLib.contains("quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD QUILLUI_QT_SKIP_BUILD"))
        #expect(smokeLib.contains("qt6-base-dev"))
        #expect(smokeLib.contains("linux_build_backend=\"$(quillui_require_requested_backend_for_product \"$product\")\""))
        #expect(smokeLib.contains("QUILLUI_LINUX_BACKEND=\"$linux_build_backend\""))
        #expect(smokeLib.contains("quillui_assign_output()"))
        #expect(smokeLib.contains("printf -v \"$__quillui_output_var\" \"%s\" \"$__quillui_output_value\""))
        #expect(smokeLib.contains("quillui_start_xvfb()"))
        #expect(smokeLib.contains("/tmp/.X${display_number}-lock"))
        #expect(smokeLib.contains("/tmp/.X11-unix/X${display_number}"))
        #expect(smokeLib.contains("! -d \"/proc/$lock_pid\""))
        #expect(smokeLib.contains("quillui_assign_output \"$output_var\" \"$QUILLUI_BACKEND_APP_EXECUTABLE\""))
        #expect(smokeLib.contains("${QUILLUI_BACKEND_SKIP_BUILD:-0}"))
        #expect(smokeLib.contains("quillui_require_backend_product_build_stamp"))
        #expect(smokeLib.contains("quillui_record_backend_product_build"))
        #expect(!smokeLib.contains("quillui_assign_output \"$output_var\" \"$QUILLUI_GTK_APP_EXECUTABLE\""))
        #expect(!smokeLib.contains("${QUILLUI_GTK_SKIP_BUILD:-0}"))
        #expect(smokeLib.contains("quillui_linux_backend_apt_get()"))
        #expect(smokeLib.contains("ffmpeg"))
        #expect(smokeLib.contains("libc++-dev"))
        #expect(smokeLib.contains("libc++abi-dev"))
        #expect(smokeLib.contains("sudo apt-get \"${apt_options[@]}\" \"$@\""))
        #expect(smokeLib.contains("[[ \"$(id -u)\" == \"0\" ]]"))
        #expect(smokeLib.contains("apt-get \"${apt_options[@]}\" \"$@\""))
        #expect(smokeLib.contains("sudo or root access is required to install Linux backend smoke packages"))
        #expect(smokeLib.contains("quillui_install_linux_backend_smoke_packages()"))
        #expect(smokeLib.contains("quillui_linux_backend_apt_get update"))
        #expect(smokeLib.contains("quillui_linux_backend_apt_get install -y --fix-missing \"${missing[@]}\""))
        #expect(smokeLib.contains("quillui_normalize_x_display_id()"))
        #expect(smokeLib.contains("quillui_stop_process_if_running()"))
        #expect(!smokeLib.contains("quillui_is_quill_chat_mac_reference_product()"))
        #expect(smokeLib.contains("quillui_backend_reference_window_defaults()"))
        #expect(smokeLib.contains("quillui_find_visible_window_by_name()"))
        #expect(smokeLib.contains("quillui_find_visible_window_for_pid()"))
        #expect(smokeLib.contains("best_area=-1"))
        #expect(smokeLib.contains("xdotool getwindowgeometry --shell \"$candidate\""))
        #expect(smokeLib.contains("quillui_find_visible_window_for_pid_except()"))
        #expect(smokeLib.contains("quillui_find_any_visible_window()"))
        #expect(smokeLib.contains("quillui_find_quill_chat_reference_window()"))
        #expect(smokeLib.contains("quillui_place_reference_window()"))
        #expect(smokeLib.contains("quillui_print_backend_app_log_tail()"))
        #expect(smokeLib.contains("''|*[!0-9]*) line_count=80 ;;"))
        #expect(smokeLib.contains("echo \"Backend app log ($log_path):\" >&2"))
        #expect(smokeLib.contains("tail -n \"$line_count\" \"$log_path\" >&2 || true"))
        #expect(smokeLib.contains("quillui_backend_visual_verify_product()"))
        #expect(smokeLib.contains("verify_product=\"$(quillui_backend_visual_verify_product_for_product \"$product\" \"$selected_backend\")\""))
        #expect(smokeLib.contains("quillui_backend_interaction_verify_product()"))
        #expect(smokeLib.contains("local resolved_verify_product=\"$product\""))
        #expect(smokeLib.contains("quillui_assign_output \"$output_var\" \"$resolved_verify_product\""))
        #expect(!smokeLib.contains("local verify_product=\"$product\"\n  local app_verify_product"))
        #expect(smokeLib.contains("quillui_backend_list_selection_verify_product()"))
        #expect(smokeLib.contains("list_selection_verify_product=\"$(quillui_backend_list_selection_verify_product \"$product\" \"$selected_backend\")\""))
        #expect(smokeLib.contains("quillui_backend_app_interaction_verify_product_for_product \"$product\" \"$selected_backend\" \"$interaction_mode\""))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-composer-typed"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-toolbar-menu"))
        #expect(smokeLib.contains("quill-enchanted-list-selection"))
        #expect(smokeLib.contains("quill-enchanted-qt-list-selection"))
        #expect(smokeLib.contains("verify_product=\"$product-list-selection\""))
        #expect(smokeLib.contains("quillui_is_backend_chat_gtk_list_selection_app_product \"$product\""))
        #expect(smokeLib.contains("quillui_backend_chat_gtk_selection_environment_key()"))
        #expect(smokeLib.contains("quillui_backend_chat_gtk_selected_index_on_start()"))
        #expect(smokeLib.contains("quillui_backend_chat_shared_selection_environment_key()"))
        #expect(smokeLib.contains("verify_product=\"$product-gtk-list-selection\""))
        #expect(smokeLib.contains("quillui_is_backend_generic_gtk_list_selection_app_product \"$product\""))
        #expect(smokeLib.contains("verify_product=\"$product-qt-list-selection\""))
        #expect(smokeLib.contains("quillui_is_backend_generic_qt_app_product \"$product\""))
        #expect(smokeLib.contains("QUILLUI_GTK_MALFORMED_IMPORT_CONFIGURATION_FILE QUILLUI_QT_MALFORMED_IMPORT_CONFIGURATION_FILE"))
        #expect(smokeLib.contains("quillui_backend_smoke_interaction_verify_product \"$product\" \"$interaction_mode\""))
        #expect(smokeLib.contains("quillui_append_backend_launch_environment()"))
        #expect(smokeLib.contains("requested_backend=\"$(quillui_validate_requested_backend_for_product \"$product\" \"$requested_backend\")\""))
        #expect(smokeLib.contains("quillui_append_backend_layout_debug_environment()"))
        #expect(smokeLib.contains("quillui_append_backend_runtime_environment()"))
        #expect(smokeLib.contains("quillui_append_backend_launch_environment \"$output_array\" \"$product\" \"$display\" \"$requested_backend\""))
        #expect(smokeLib.contains("quillui_append_backend_layout_debug_environment \"$output_array\" \"${QUILLUI_BACKEND_LAYOUT_DEBUG:-}\""))
        #expect(smokeLib.contains("quillui_append_quill_chat_reference_environment_if_needed \\"))
        #expect(smokeLib.contains("quillui_append_backend_selection_start_environment()"))
        #expect(smokeLib.contains("quillui_backend_list_selection_start_environment_assignment()"))
        #expect(smokeLib.contains("selection_assignment=\"$(quillui_backend_list_selection_start_environment_assignment \"$product\" \"$selected_backend\")\""))
        #expect(smokeLib.contains("quillui_backend_generic_selection_environment_keys()"))
        #expect(smokeLib.contains("quillui_backend_selected_index_from_environment_keys()"))
        #expect(smokeLib.contains("quillui_backend_generic_selected_index_on_start()"))
        #expect(smokeLib.contains("quillui_backend_generic_qt_selected_index_on_start()"))
        #expect(smokeLib.contains("quillui_backend_generic_gtk_selection_environment_key()"))
        #expect(smokeLib.contains("QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=$selected_index"))
        #expect(smokeLib.contains("environment_key=\"$(quillui_backend_generic_gtk_selection_environment_key \"$product\")\""))
        #expect(smokeLib.contains("QUILLUI_GTK_CODEEDIT_SELECTED_FILE_INDEX_ON_START QUILLUI_QT_CODEEDIT_SELECTED_FILE_INDEX_ON_START"))
        #expect(smokeLib.contains("QUILLUI_GTK_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START QUILLUI_QT_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START"))
        #expect(smokeLib.contains("QUILLUI_GTK_IINA_SELECTED_PLAYLIST_INDEX_ON_START QUILLUI_QT_IINA_SELECTED_PLAYLIST_INDEX_ON_START"))
        #expect(smokeLib.contains("QUILLUI_GTK_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START QUILLUI_QT_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START"))
        #expect(smokeLib.contains("printf '%s\\n' QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START"))
        #expect(smokeLib.contains("printf '%s\\n' QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START"))
        #expect(smokeLib.contains("printf '%s\\n' QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START"))
        #expect(smokeLib.contains("printf '%s\\n' QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START"))
        #expect(smokeLib.contains("printf '%s\\n' QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START"))
        #expect(smokeLib.contains("printf '%s\\n' QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START"))
        #expect(smokeLib.contains("printf '%s\\n' QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START"))
        #expect(smokeLib.contains("quillui_backend_chat_shared_selection_environment_key"))
        #expect(smokeLib.contains("done < <(quillui_backend_generic_selection_environment_keys \"$product\")"))
        #expect(smokeLib.contains("[[ \"$environment_key\" == \"$shared_environment_key\" ]]"))
        #expect(smokeLib.contains("printf '%s\\n' \"${QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START:-0}\""))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=${QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START:-${QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START:-0}}"))
        #expect(smokeLib.contains("selected_index=\"$(quillui_backend_chat_gtk_selected_index_on_start \"$product\")\""))
        #expect(smokeLib.contains("environment_key=\"$(quillui_backend_chat_gtk_selection_environment_key \"$product\")\""))
        #expect(smokeLib.contains("printf '%s\\n' \"${!shared_environment_key:-1}\""))
        #expect(smokeLib.contains("quillui_seed_enchanted_reference_data()"))
        #expect(smokeLib.contains("seed-enchanted-reference-data.py"))
        #expect(smokeLib.contains("QUILLUI_BACKEND_LAYOUT_DEBUG=$layout_debug"))
        #expect(!smokeLib.contains("QUILLUI_GTK_LAYOUT_DEBUG=$layout_debug"))
        #expect(!smokeLib.contains("QUILLUI_QT_LAYOUT_DEBUG=$layout_debug"))
        #expect(smokeLib.contains("quillui_append_environment_assignment()"))
        #expect(smokeLib.contains("quillui_backend_scoped_app_environment_names()"))
        #expect(smokeLib.contains("quillui_unset_backend_scoped_app_environment()"))
        #expect(smokeLib.contains("quillui_unset_backend_scoped_app_environment"))
        #expect(smokeLib.contains("quillui_append_enchanted_fixture_data_environment()"))
        #expect(smokeLib.contains("quillui_append_enchanted_reference_mode_environment()"))
        #expect(smokeLib.contains("quillui_append_enchanted_profile_mode_environment()"))
        #expect(smokeLib.contains("quillui_append_enchanted_unreachable_environment()"))
        #expect(smokeLib.contains("quillui_is_generated_enchanted_linux_product()"))
        #expect(smokeLib.contains("quillui_append_enchanted_profile_fixture_environment_if_needed()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_fixture_data_environment()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_reference_environment()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_reference_environment_if_needed()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_profile_fixture_environment_if_needed()"))
        #expect(smokeLib.contains("Acquire::Retries=\"${QUILLUI_APT_RETRIES:-5}\""))
        #expect(smokeLib.contains("Acquire::http::Timeout=\"${QUILLUI_APT_HTTP_TIMEOUT:-30}\""))
        #expect(smokeLib.contains("install -y --fix-missing \"${missing[@]}\""))
        #expect(smokeLib.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(smokeLib.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=$reference_window_height"))
        #expect(smokeLib.contains("QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label"))
        #expect(!smokeLib.contains("QUILLUI_GTK_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(!smokeLib.contains("QUILLUI_QT_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(!smokeLib.contains("QUILLUI_QT_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label"))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_REFERENCE_MODE=1"))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_FORCE_UNREACHABLE=1"))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_PROFILE_MODE=1"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_REFERENCE_MODE=1"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_PROFILE_MODE=1"))
        #expect(smokeLib.contains("quillui_generated_app_backend_facade()"))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_BACKEND_FACADE"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_BACKEND_FACADE"))
        #expect(smokeLib.contains("quillui_generated_app_work_root()"))
        #expect(smokeLib.contains("default_work_root=\"$default_work_root-$backend_facade\""))
        #expect(smokeLib.contains("quillui_backend_generated_app_build_spec_for_product \"$product\""))
        #expect(smokeLib.contains("quillui_artifact_path_from_file()"))
        #expect(smokeLib.contains("artifact_path_file=\"${QUILLUI_BACKEND_APP_ARTIFACT_PATH_FILE:-$work_root/.quillui-artifact-path}\""))
        #expect(smokeLib.contains("QUILLUI_APP_ARTIFACT_PATH_FILE=\"$artifact_path_file\""))
        #expect(smokeLib.contains("Generated app build did not write a usable artifact path for $product: $artifact_path_file"))
        #expect(smokeLib.contains(".build/quillui-generated-app-build-cache"))
        #expect(smokeLib.contains("scripts/build-swiftui-linux-app.sh"))
        #expect(smokeLib.contains("\"${build_args[@]}\""))
        #expect(smokeLib.contains("generated_artifact_path"))
        #expect(smokeLib.contains("quillui_resolve_linux_backend_executable()"))
        #expect(backendCheckScript.contains("artifact_path_file=\"$generated_work_root/.quillui-artifact-path\""))
        #expect(backendCheckScript.contains("QUILLUI_APP_ARTIFACT_PATH_FILE=\"$artifact_path_file\""))
        #expect(backendCheckScript.contains("quillui_artifact_path_from_file \"$artifact_path_file\" ENCHANTED_ARTIFACT_PATH"))
        #expect(backendCheckScript.contains("run_executable_smoke \"$product\" \"$ENCHANTED_ARTIFACT_PATH\" \"$backend\""))
        #expect(!backendCheckScript.contains("ENCHANTED_BIN_DIR"))
        #expect(smokeLib.contains("quillui_seed_quill_chat_reference_data()"))
        #expect(backendScript.contains("quillui_resolve_linux_backend_executable \"$PRODUCT\" APP_EXECUTABLE"))
        #expect(backendScript.contains("quillui_append_backend_runtime_environment"))
        #expect(backendScript.contains("\"$PRODUCT\""))
        #expect(backendScript.contains("\"$DISPLAY_ID\""))
        #expect(backendScript.contains("quillui_start_xvfb \"$DISPLAY_ID\" \"$SCREEN_SIZE\" /tmp/quillui-xvfb-interaction.log xvfb_pid"))
        #expect(backendScript.contains("quillui_stop_process_if_running \"${app_pid:-}\""))
        #expect(backendScript.contains("quillui_stop_process_if_running \"$xvfb_pid\""))
        #expect(!backendScript.contains("install_packages()"))
        #expect(!backendScript.contains("build_and_resolve_executable()"))
        #expect(backendProducts.contains("quillui_gtk_app_products()"))
        #expect(backendProducts.contains("quillui_backend_app_products()"))
        #expect(backendProducts.contains("quillui_backend_generic_qt_app_products()"))
        #expect(backendProducts.contains("quillui_gtk_app_products() {\n  # Legacy GTK-named entry point"))
        #expect(backendProducts.contains("quillui_backend_app_products\n}"))
        #expect(backendProducts.contains("quillui_backend_app_backends()"))
        #expect(backendProducts.contains("quillui_backend_fixed_app_backend_overrides()"))
        #expect(backendProducts.contains("quillui_backend_fixed_backend_for_app_product()"))
        #expect(backendProducts.contains("quillui_backend_emit_matrix_for_product_rows()"))
        #expect(backendProducts.contains("quillui_backend_matrix_for_products()"))
        #expect(backendProducts.contains("quillui_backend_app_matrix()"))
        #expect(backendProducts.contains("product_rows=\"$(quillui_backend_app_products)\""))
        #expect(backendProducts.contains("quillui_normalize_backend_identifier()"))
        #expect(backendProducts.contains("quillui_require_backend_identifier()"))
        #expect(backendProducts.contains("quillui_record_backend_product_build()"))
        #expect(backendProducts.contains("quillui_require_backend_product_build_stamp()"))
        #expect(!backendProducts.contains("quillui_backend_identifier_or_raw()"))
        #expect(backendProducts.contains("quillui_backend_generated_app_products()"))
        #expect(backendProducts.contains("quillui_backend_generated_app_matrix()"))
        #expect(backendProducts.contains("product_rows=\"$(quillui_backend_generated_app_products)\""))
        #expect(backendProducts.contains("quillui_backend_smoke_products()"))
        #expect(backendProducts.contains("quillui_backend_smoke_matrix()"))
        #expect(backendProducts.contains("quillui_backend_profile_products()"))
        #expect(backendProducts.contains("done < <(quillui_backend_smoke_products)"))
        #expect(backendProducts.contains("quillui_backend_generated_app_products\n  quillui_backend_smoke_products"))
        #expect(backendProducts.contains("quillui_backend_profile_matrix()"))
        #expect(backendProducts.contains("quillui_backend_app_matrix\n  quillui_backend_generated_app_matrix\n  quillui_backend_smoke_matrix"))
        #expect(backendProducts.contains("quillui_backend_runtime_matrix_for_rows()"))
        #expect(backendProducts.contains("quillui_backend_app_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_interaction_app_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_generated_app_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_smoke_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_smoke_interaction_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_profile_runtime_matrix()"))
        #expect(backendProducts.contains("quillui_backend_product_list_contains()"))
        #expect(backendProducts.contains("quillui_backend_validate_runtime_product_reference()"))
        #expect(backendProducts.contains("quillui_backend_product_native_runtime_backends()"))
        #expect(backendProducts.contains("quillui_backend_product_has_native_runtime()"))
        #expect(backendProducts.contains("quillui_backend_validate_product_native_runtime_backends()"))
        #expect(backendProducts.contains("quillui_backend_app_backend_ids_for_awk()"))
        #expect(backendProducts.contains("quillui_backend_validate_backend_parity()"))
        #expect(backendProducts.contains("quillui_backend_validate_two_column_backend_parity()"))
        #expect(backendProducts.contains("quillui_backend_validate_mode_backend_parity()"))
        #expect(backendProducts.contains("quillui_backend_validate_two_column_backend_parity \"app-matrix\" quillui_backend_app_matrix"))
        #expect(backendProducts.contains("quillui_backend_validate_two_column_backend_parity \"interaction-matrix\" quillui_backend_interaction_app_matrix"))
        #expect(backendProducts.contains("quillui_backend_validate_two_column_backend_parity \"generated-app-matrix\" quillui_backend_generated_app_matrix"))
        #expect(backendProducts.contains("quillui_backend_validate_mode_backend_parity \"interaction-extra-mode-matrix\" quillui_backend_interaction_extra_mode_matrix"))
        #expect(backendProducts.contains("quillui_is_backend_smoke_product()"))
        #expect(backendProducts.contains("quillui_is_backend_generated_app_product()"))
        #expect(backendProducts.contains("quillui_is_backend_generic_qt_app_product()"))
        #expect(backendProducts.contains("quillui_backend_generic_gtk_list_selection_app_products()"))
        #expect(backendProducts.contains("quillui_is_backend_generic_gtk_list_selection_app_product()"))
        #expect(backendProducts.contains("done < <(quillui_backend_generic_gtk_list_selection_app_products)"))
        #expect(backendProducts.contains("quillui_backend_chat_gtk_list_selection_app_products()"))
        #expect(backendProducts.contains("quillui_is_backend_chat_gtk_list_selection_app_product()"))
        #expect(backendProducts.contains("done < <(quillui_backend_chat_gtk_list_selection_app_products)"))
        #expect(backendProducts.contains("generic-gtk-list-selection-apps)"))
        #expect(backendProducts.contains("chat-gtk-list-selection-apps)"))
        #expect(backendProducts.contains("is-generic-gtk-list-selection-app)"))
        #expect(backendProducts.contains("is-chat-gtk-list-selection-app)"))
        #expect(backendProducts.contains("done < <(quillui_backend_generic_qt_app_products)"))
        #expect(backendProducts.contains("quillui_alias_env()"))
        #expect(backendProducts.contains("backend_prefix=\"QUILLUI_QT_\""))
        #expect(backendProducts.contains("normalize-backend)"))
        #expect(backendProducts.contains("require-backend)"))
        #expect(backendProducts.contains("quillui_alias_backend_common_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_visual_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_interaction_env()"))
        #expect(backendProducts.contains("quillui_alias_backend_profile_env()"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_INTERACTION_MODE QUILLUI_GTK_INTERACTION_MODE QUILLUI_QT_INTERACTION_MODE"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_IMPORT_CONFIGURATION QUILLUI_GTK_IMPORT_CONFIGURATION QUILLUI_QT_IMPORT_CONFIGURATION"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_IMPORT_CONFIGURATION_FILE QUILLUI_GTK_IMPORT_CONFIGURATION_FILE QUILLUI_QT_IMPORT_CONFIGURATION_FILE"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START QUILLUI_GTK_GENERIC_SELECTED_INDEX_ON_START QUILLUI_QT_GENERIC_SELECTED_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START QUILLUI_GTK_CODEEDIT_SELECTED_FILE_INDEX_ON_START QUILLUI_QT_CODEEDIT_SELECTED_FILE_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_QT_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START QUILLUI_GTK_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START QUILLUI_QT_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START QUILLUI_GTK_IINA_SELECTED_PLAYLIST_INDEX_ON_START QUILLUI_QT_IINA_SELECTED_PLAYLIST_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START QUILLUI_GTK_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START QUILLUI_QT_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START QUILLUI_GTK_CHAT_SELECTED_THREAD_INDEX_ON_START QUILLUI_QT_CHAT_SELECTED_THREAD_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START QUILLUI_GTK_SIGNAL_SELECTED_THREAD_INDEX_ON_START QUILLUI_QT_SIGNAL_SELECTED_THREAD_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START QUILLUI_GTK_TELEGRAM_SELECTED_THREAD_INDEX_ON_START QUILLUI_QT_TELEGRAM_SELECTED_THREAD_INDEX_ON_START"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_PROFILE_COMMAND QUILLUI_GTK_PROFILE_COMMAND QUILLUI_QT_PROFILE_COMMAND"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE QUILLUI_GTK_PROFILE_SCREEN_SIZE QUILLUI_QT_PROFILE_SCREEN_SIZE"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_PROFILE_MAX_STARTUP_MS QUILLUI_GTK_PROFILE_MAX_STARTUP_MS QUILLUI_QT_PROFILE_MAX_STARTUP_MS\n  quillui_alias_backend_common_env"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_VERIFY_PRODUCT QUILLUI_GTK_VERIFY_PRODUCT QUILLUI_QT_VERIFY_PRODUCT"))
        #expect(backendProducts.contains("backend-apps)"))
        #expect(backendProducts.contains("app-backends)"))
        #expect(backendProducts.contains("app-matrix)"))
        #expect(backendProducts.contains("app-runtime-matrix)"))
        #expect(backendProducts.contains("interaction-runtime-matrix)"))
        #expect(backendProducts.contains("generated-apps)"))
        #expect(backendProducts.contains("generated-app-matrix)"))
        #expect(backendProducts.contains("generated-app-runtime-matrix)"))
        #expect(backendProducts.contains("gtk-apps)"))
        #expect(backendProducts.contains("fixed-app-backends)"))
        #expect(backendProducts.contains("native-product-runtime-backends)"))
        #expect(backendProducts.contains("native-product-runtime-overrides)"))
        #expect(backendProducts.contains("validate-integrity)"))
        #expect(backendProducts.contains("smoke-matrix)"))
        #expect(backendProducts.contains("smoke-runtime-matrix)"))
        #expect(backendProducts.contains("smoke-interaction-modes)"))
        #expect(backendProducts.contains("interaction-extra-mode-matrix)"))
        #expect(backendProducts.contains("interaction-extra-mode-runtime-matrix)"))
        #expect(backendProducts.contains("smoke-interaction-matrix)"))
        #expect(backendProducts.contains("smoke-interaction-runtime-matrix)"))
        #expect(backendProducts.contains("smoke-interaction-verify-matrix)"))
        #expect(backendProducts.contains("normalize-smoke-interaction-mode)"))
        #expect(backendProducts.contains("smoke-interaction-verify-product)"))
        #expect(backendProducts.contains("profile-products)"))
        #expect(backendProducts.contains("profile-matrix)"))
        #expect(backendProducts.contains("profile-runtime-matrix)"))
        #expect(backendProducts.contains("is-smoke-product)"))
        #expect(backendProducts.contains("is-generated-app)"))
        #expect(backendProducts.contains("backend-for-product)"))
        #expect(backendProducts.contains("quillui_backend_native_product_runtime_overrides()"))
        #expect(backendProducts.contains("quillui_backend_native_runtime_backend_for_product()"))
        #expect(backendProducts.contains("quillui_backend_validate_integrity()"))
        #expect(backendProducts.contains("quillui_alias_env QUILLUI_BACKEND_MALFORMED_IMPORT_CONFIGURATION_FILE"))
        #expect(backendProducts.contains("quill-qt-interaction-smoke)"))
        #expect(backendProducts.contains("echo \"qt\""))
        #expect(backendProducts.contains("quill-gtk-interaction-smoke|quill-enchanted-linux|quill-chat-linux"))
        #expect(backendProducts.contains("echo \"gtk\""))
        #expect(screenshotVerifier.contains("Quill backend interaction smoke"))
        #expect(screenshotVerifier.contains("mac_reference_sidebar_tint_pixel"))
        #expect(screenshotVerifier.contains("Mac-reference sidebar lost its green-tinted source-list material"))
        #expect(screenshotVerifier.contains("cool_wordmark_pixel"))
        #expect(screenshotVerifier.contains("warm_wordmark_pixel"))
        #expect(screenshotVerifier.contains("Mac-reference wordmark lost its blue-to-red color range"))
        #expect(screenshotVerifier.contains("validate_quill_backend_interaction_smoke"))
        #expect(screenshotVerifier.contains("validate_quill_solderscope_launch"))
        #expect(screenshotVerifier.contains("validate_quill_solderscope_interaction"))
        #expect(screenshotVerifier.contains("\"quill-solderscope-launch\""))
        #expect(screenshotVerifier.contains("quill-solderscope-interaction"))
        #expect(screenshotVerifier.contains("SolderScope dark toolbar pixels were not detected near the top"))
        #expect(screenshotVerifier.contains("canvas_dark_pixels >= 25_000"))
        #expect(screenshotVerifier.contains("frame_pixels >= 20_000"))
        #expect(screenshotVerifier.contains("SolderScope synthetic camera frame was not detected"))
        #expect(screenshotVerifier.contains("minimum_mean = 250 if solderscope_launch_product else 1000"))
        #expect(screenshotVerifier.contains("Quill Enchanted Qt native"))
        #expect(screenshotVerifier.contains("239 <= red <= 247 and 239 <= green <= 247 and 242 <= blue <= 250"))
        #expect(screenshotVerifier.contains("validate_quill_enchanted_qt_native"))
        #expect(screenshotVerifier.contains("product == \"quill-enchanted-qt\""))
        #expect(screenshotVerifier.contains("product == \"quill-enchanted-qt-list-selection\""))
        #expect(screenshotVerifier.contains("def generic_gtk_card_pixel"))
        #expect(screenshotVerifier.contains("return generic_qt_card_pixel(rgb) or prompt_card_pixel(rgb)"))
        #expect(screenshotVerifier.contains("ENCHANTED_LINUX_SNAPSHOT_VALIDATORS"))
        #expect(screenshotVerifier.contains("\"quill-enchanted-linux-qt\": validate_quill_enchanted_linux_qt_snapshot"))
        #expect(screenshotVerifier.contains("\"quill-enchanted-linux-qt-selected-chat\": validate_quill_enchanted_linux_qt_selected_chat"))
        #expect(screenshotVerifier.contains("\"quill-enchanted-linux-qt-settings\": validate_quill_enchanted_linux_qt_settings"))
        #expect(screenshotVerifier.contains("\"quill-enchanted-linux-qt-utility\": validate_quill_enchanted_linux_qt_utility"))
        #expect(screenshotVerifier.contains("\"quill-enchanted-linux-gtk\": validate_quill_enchanted_linux_gtk_snapshot"))
        #expect(screenshotVerifier.contains("empty_wordmark_pixels <= 3_000"))
        #expect(screenshotVerifier.contains("def validate_quill_enchanted_linux_qt_settings"))
        #expect(screenshotVerifier.contains("def validate_quill_enchanted_linux_qt_utility"))
        #expect(screenshotVerifier.contains("panel_pixels >= 80_000"))
        #expect(screenshotVerifier.contains("panel_pixels >= 35_000"))
        #expect(screenshotVerifier.contains("field_pixels >= 25_000"))
        #expect(screenshotVerifier.contains("field_pixels <= 15_000"))
        #expect(screenshotVerifier.contains("settings_text_pixels >= 1_200"))
        #expect(screenshotVerifier.contains("utility_text_pixels >= 500"))
        #expect(screenshotVerifier.contains("prompt_card_row=absent"))
        #expect(screenshotVerifier.contains("composer_accessory_pixels >= 20"))
        #expect(screenshotVerifier.contains("enchanted_user_bubble_pixel"))
        #expect(!screenshotVerifier.contains("product == \"quill-enchanted-linux-gtk\":\n        print(validate_quill_enchanted_qt_native(image))"))
        #expect(screenshotVerifier.contains("validate_quill_enchanted_linux_qt_snapshot"))
        #expect(screenshotVerifier.contains("validate_quill_enchanted_linux_gtk_snapshot"))
        #expect(screenshotVerifier.contains("Generated Enchanted GTK sidebar history was not detected"))
        #expect(screenshotVerifier.contains("sidebar_text_pixels={sidebar_text_pixels}"))
        #expect(screenshotVerifier.contains("product == \"quill-enchanted-list-selection\""))
        #expect(screenshotVerifier.contains("validate_quill_enchanted_gtk_list_selection"))
        #expect(screenshotVerifier.contains("load_generic_qt_app_products()"))
        #expect(screenshotVerifier.contains("load_generic_gtk_list_selection_app_products()"))
        #expect(screenshotVerifier.contains("load_chat_gtk_list_selection_app_products()"))
        #expect(screenshotVerifier.contains("Path(__file__).with_name(\"quillui-backend-products.sh\")"))
        #expect(screenshotVerifier.contains("\"generic-qt-apps\""))
        #expect(screenshotVerifier.contains("\"generic-gtk-list-selection-apps\""))
        #expect(screenshotVerifier.contains("\"chat-gtk-list-selection-apps\""))
        #expect(screenshotVerifier.contains("GENERIC_QT_APP_PRODUCTS"))
        #expect(screenshotVerifier.contains("GENERIC_QT_LIST_SELECTION_PRODUCTS"))
        #expect(screenshotVerifier.contains("GENERIC_GTK_LIST_SELECTION_PRODUCTS"))
        #expect(screenshotVerifier.contains("CHAT_GTK_LIST_SELECTION_PRODUCTS"))
        #expect(screenshotVerifier.contains("validate_quill_generic_gtk_list_selection"))
        #expect(screenshotVerifier.contains("validate_quill_generic_qt_list_selection"))
        #expect(screenshotVerifier.contains("product in GENERIC_GTK_LIST_SELECTION_PRODUCTS"))
        #expect(screenshotVerifier.contains("product in GENERIC_QT_LIST_SELECTION_PRODUCTS"))
        #expect(screenshotVerifier.contains("product in CHAT_GTK_LIST_SELECTION_PRODUCTS"))
        #expect(!screenshotVerifier.contains("fixture row"))
        #expect(screenshotVerifier.contains("Quill WireGuard Qt native"))
        #expect(screenshotVerifier.contains("validate_quill_wireguard_qt_native"))
        #expect(screenshotVerifier.contains("Quill WireGuard GTK {scenario}"))
        #expect(screenshotVerifier.contains("validate_quill_wireguard_gtk_native"))
        #expect(screenshotVerifier.contains("validate_quill_wireguard_gtk_import"))
        #expect(screenshotVerifier.contains("divider_min_x = left + int(app_width * 0.24)"))
        #expect(screenshotVerifier.contains("divider_max_x = left + int(app_width * 0.58)"))
        #expect(screenshotVerifier.contains("Quill WireGuard {backend.upper()} import error"))
        #expect(screenshotVerifier.contains("validate_quill_wireguard_import_error"))
        #expect(screenshotVerifier.contains("wireguard_error_text_pixel"))
        #expect(screenshotVerifier.contains("wireguard_selected_row_pixel"))
        #expect(screenshotVerifier.contains("minimum_selected_center_offset"))
        #expect(screenshotVerifier.contains("require_focused_title"))
        #expect(screenshotVerifier.contains("wireguard_qt_focused_title_border_pixel"))
        #expect(screenshotVerifier.contains("product == \"quill-wireguard-qt\""))
        #expect(screenshotVerifier.contains("quill-wireguard-qt-tunnel-selection"))
        #expect(screenshotVerifier.contains("quill-wireguard-qt-name-edit"))
        #expect(screenshotVerifier.contains("quill-wireguard-qt-import-paste"))
        #expect(screenshotVerifier.contains("quill-wireguard-qt-import-file"))
        #expect(screenshotVerifier.contains("quill-wireguard-qt-import-invalid-paste"))
        #expect(screenshotVerifier.contains("quill-wireguard-qt-import-invalid-file"))
        #expect(screenshotVerifier.contains("quill-wireguard-name-edit"))
        #expect(screenshotVerifier.contains("quill-wireguard-import-paste"))
        #expect(screenshotVerifier.contains("quill-wireguard-import-file"))
        #expect(screenshotVerifier.contains("quill-wireguard-import-invalid-paste"))
        #expect(screenshotVerifier.contains("quill-wireguard-import-invalid-file"))
        #expect(screenshotVerifier.contains("validate_quill_chatkit_gtk_list_selection"))
        #expect(screenshotVerifier.contains("CHAT_GTK_LIST_SELECTION_PRODUCTS"))
        #expect(screenshotVerifier.contains("Usage: verify-backend-screenshot.py SCREENSHOT_PATH PRODUCT"))
        #expect(!screenshotVerifier.contains("Quill GTK interaction smoke"))
        #expect(legacyScreenshotVerifier.contains("verify-backend-screenshot.py"))
        #expect(!legacyScreenshotVerifier.contains("validate_quill_backend_interaction_smoke"))
        #expect(legacyGtkScript.contains("linux-backend-interaction-check.sh"))
        #expect(smokeMatrixRunner.contains("source \"$ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(smokeMatrixRunner.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(smokeMatrixRunner.contains("app-matrix|interaction-matrix|interaction-extra-mode-matrix|generated-app-matrix|smoke-matrix|smoke-interaction-matrix"))
        #expect(smokeMatrixRunner.contains("quillui_smoke_runtime_matrix_command()"))
        #expect(smokeMatrixRunner.contains("RUNTIME_MATRIX_COMMAND=\"$(quillui_smoke_runtime_matrix_command \"$MATRIX_COMMAND\")\""))
        #expect(smokeMatrixRunner.contains("quillui_smoke_matrix_has_mode_column()"))
        #expect(smokeMatrixRunner.contains("CHECK_SCRIPT=\"$ROOT_DIR/scripts/linux-backend-visual-check.sh\""))
        #expect(smokeMatrixRunner.contains("CHECK_SCRIPT=\"$ROOT_DIR/scripts/linux-backend-interaction-check.sh\""))
        #expect(smokeMatrixRunner.contains("OUTPUT_TEMPLATE must include {product} and {backend}; mode matrices must also"))
        #expect(smokeMatrixRunner.contains("OUTPUT_TEMPLATE must include {mode} for $MATRIX_COMMAND"))
        #expect(smokeMatrixRunner.contains("Backend mode runtime matrix row has an empty mode"))
        #expect(smokeMatrixRunner.contains("Backend runtime matrix row has an unexpected mode column"))
        #expect(smokeMatrixRunner.contains("quillui_backend_validate_runtime_availability_for_product \"$product\" \"$backend\" \"$runtime_backend\" \"$runtime_mode\""))
        #expect(smokeMatrixRunner.contains("Backend runtime matrix row has invalid runtime availability"))
        #expect(smokeMatrixRunner.contains("quillui_smoke_build_cache_key()"))
        #expect(smokeMatrixRunner.contains("quillui_is_backend_generated_app_product \"$product\""))
        #expect(smokeMatrixRunner.contains("build_cache_key=\"$(quillui_smoke_build_cache_key \"$product\" \"$requested_backend\" \"$runtime_backend\")\""))
        #expect(smokeMatrixRunner.contains("printf '%s:%s\\n' \"$product\" \"$runtime_backend\""))
        #expect(smokeMatrixRunner.contains("quillui_smoke_visual_verify_product()"))
        #expect(smokeMatrixRunner.contains("quillui_runner_verify_product=\"\""))
        #expect(smokeMatrixRunner.contains("quillui_backend_visual_verify_product \"$product\" quillui_runner_verify_product"))
        #expect(smokeMatrixRunner.contains("quillui_smoke_interaction_verify_product()"))
        #expect(smokeMatrixRunner.contains("quillui_backend_interaction_verify_product \"$product\" \"$interaction_mode\" quillui_runner_verify_product"))
        #expect(smokeMatrixRunner.contains("verify_product=\"$(quillui_smoke_visual_verify_product \"$product\" \"$requested_backend\")\""))
        #expect(smokeMatrixRunner.contains("dry_run_fields+=(\"$verify_product\")"))
        #expect(smokeMatrixRunner.contains("generated_app_backend_facade=\"$runtime_backend\""))
        #expect(smokeMatrixRunner.contains("smoke_environment+=(\"QUILLUI_APP_BACKEND_FACADE=$generated_app_backend_facade\")"))
        #expect(smokeMatrixRunner.contains("QUILLUI_BACKEND_INTERACTION_MODE=$mode"))
        #expect(smokeMatrixRunner.contains("QUILLUI_BACKEND_SKIP_BUILD=1"))
        #expect(smokeMatrixRunner.contains("SMOKE_ROW_TIMEOUT=\"${QUILLUI_BACKEND_SMOKE_ROW_TIMEOUT:-10m}\""))
        #expect(smokeMatrixRunner.contains("SMOKE_ROW_KILL_AFTER=\"${QUILLUI_BACKEND_SMOKE_ROW_KILL_AFTER:-15s}\""))
        #expect(smokeMatrixRunner.contains("SMOKE_TIMEOUT_COMMAND=(\"$timeout_command\" \"--kill-after=$SMOKE_ROW_KILL_AFTER\" \"$SMOKE_ROW_TIMEOUT\")"))
        #expect(smokeMatrixRunner.contains("smoke_command=(env \"${smoke_environment[@]}\" \"$CHECK_SCRIPT\" \"$output_path\" \"$product\" \"$requested_backend\")"))
        #expect(smokeMatrixRunner.contains("\"${SMOKE_TIMEOUT_COMMAND[@]}\" \"${smoke_command[@]}\""))
        #expect(smokeMatrixRunner.contains("\"$ROOT_DIR/scripts/quillui-backend-products.sh\" \"$RUNTIME_MATRIX_COMMAND\""))
        #expect(profileMatrixRunner.contains("quillui_profile_build_cache_key()"))
        #expect(profileMatrixRunner.contains("build_cache_key=\"$(quillui_profile_build_cache_key \"$product\" \"$requested_backend\" \"$runtime_backend\")\""))
        #expect(profileMatrixRunner.contains("printf '%s:%s\\n' \"$product\" \"$runtime_backend\""))
        #expect(profileMatrixRunner.contains("profiler_environment+=(\"QUILLUI_APP_BACKEND_FACADE=$runtime_backend\")"))
        #expect(!profileMatrixRunner.contains("profiler_environment+=(\"QUILLUI_APP_BACKEND_FACADE=$requested_backend\")"))
        #expect(interactionModeRunner.contains("Usage: run-linux-backend-interaction-modes.sh OUTPUT_TEMPLATE PRODUCT BACKEND MODE..."))
        #expect(interactionModeRunner.contains("QUILLUI_BACKEND_INTERACTION_MODE_TIMEOUT"))
        #expect(interactionModeRunner.contains("timeout --kill-after=\"$MODE_KILL_AFTER\" \"$MODE_TIMEOUT\""))
        #expect(interactionModeRunner.contains("QUILLUI_BACKEND_INTERACTION_MODE=\"$mode\""))
        #expect(interactionModeRunner.contains("QUILLUI_BACKEND_INTERACTION_APP_LOG=\"$app_log_path\""))
        #expect(interactionModeRunner.contains("OUTPUT_TEMPLATE must include {mode}"))
        #expect(interactionModeRunner.contains("DEFAULT_APP_LOG_TEMPLATE='.qa/{product}-interaction-{mode}.log'"))
        #expect(interactionModeRunner.contains("APP_LOG_TEMPLATE=\"${QUILLUI_BACKEND_INTERACTION_APP_LOG_TEMPLATE:-$DEFAULT_APP_LOG_TEMPLATE}\""))
        #expect(!interactionModeRunner.contains("APP_LOG_TEMPLATE=\"${QUILLUI_BACKEND_INTERACTION_APP_LOG_TEMPLATE:-.qa/{product}-interaction-{mode}.log}\""))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products visual generated-app-matrix '.qa/{product}-generated-{backend}.png'"))
        #expect(workflow.contains("QUILLUI_BACKEND_SMOKE_ROW_TIMEOUT: \"25m\""))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh visual smoke-matrix '.qa/{product}-visual-{backend}.png'"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products interaction smoke-interaction-matrix '.qa/{product}-{mode}-{backend}.png'"))
        #expect(workflow.contains("QUILLUI_SOLDERSCOPE: \"1\""))
        #expect(workflow.contains("QUILLUI_SOLDERSCOPE_REQUIRED: \"1\""))
        #expect(workflow.contains("scripts/linux-solderscope-smoke-check.sh .qa/quill-solderscope-launch.png"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_REQUIRED"))
        #expect(solderScopeSmoke.contains("SolderScope smoke requires upstream source"))
        #expect(solderScopeSmoke.contains("Run scripts/fetch-upstream.sh solderscope before invoking this CI smoke."))
        #expect(solderScopeSmoke.contains("QUILL_AVFOUNDATION_SYNTHETIC_CAMERA=\"${QUILL_AVFOUNDATION_SYNTHETIC_CAMERA:-1}\""))
        #expect(solderScopeSmoke.contains("QUILL_AVFOUNDATION_SYNTHETIC_WIDTH=\"${QUILL_AVFOUNDATION_SYNTHETIC_WIDTH:-640}\""))
        #expect(solderScopeSmoke.contains("quillui_solderscope_resolve_desktop_dir()"))
        #expect(solderScopeSmoke.contains("FileManager.default.urls(for: .desktopDirectory"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_DRIVE_SNAPSHOT"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_safe_snapshot_desktop"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_click_toolbar_button()"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_DRIVE_RECORDING"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_DRIVER"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_START_DRIVER"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_STOP_DRIVER"))
        #expect(solderScopeSmoke.contains("local recording_driver=\"${QUILLUI_SOLDERSCOPE_RECORDING_DRIVER:-toolbar}\""))
        #expect(solderScopeSmoke.contains("local recording_start_driver=\"${QUILLUI_SOLDERSCOPE_RECORDING_START_DRIVER:-$recording_driver}\""))
        #expect(solderScopeSmoke.contains("local recording_stop_driver=\"${QUILLUI_SOLDERSCOPE_RECORDING_STOP_DRIVER:-toolbar}\""))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORD_BUTTON_RIGHT_OFFSET"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORD_TOOLBAR_Y_OFFSET"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORD_START_TOOLBAR_Y_OFFSET"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORD_STOP_TOOLBAR_Y_OFFSET"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_KEY_DRIVER:-active"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_POST_RECORDING_SETTLE_SECONDS"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_drive_recording_action()"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_recording_start_fallback_driver()"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_START_FALLBACK_DRIVER"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_START_FALLBACK_TICK:-12"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_START_FALLBACK_RETRY_INTERVAL_TICKS:-0"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_START_INDICATOR_PROBE_INTERVAL_TICKS:-4"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_recording_stop_fallback_driver()"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_STOP_FALLBACK_DRIVER"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_STOP_FALLBACK_TICK:-12"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_STOP_FALLBACK_RETRY_INTERVAL_TICKS:-0"))
        #expect(solderScopeSmoke.contains("recording_count > SOLDERSCOPE_RECORDING_BEFORE_COUNT"))
        #expect(solderScopeSmoke.contains("recording_stop_observed_idle == 1 && recording_count > SOLDERSCOPE_RECORDING_BEFORE_COUNT"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_START_RETRY_TICK"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_START_RETRY_INTERVAL_TICKS"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_START_RETRY_INTERVAL_TICKS:-0"))
        #expect(solderScopeSmoke.contains("for attempt in {1..80}"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_KEY_DRIVER:-window"))
        #expect(solderScopeSmoke.contains("xdotool key --clearmodifiers"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_STOP_RETRY_TICK"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_STOP_RETRY_TICK:-8"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_recording_indicator_visible()"))
        #expect(solderScopeSmoke.contains("local recording_stop_observed_idle=0"))
        #expect(solderScopeSmoke.contains("start retry skipped because recording indicator is visible"))
        #expect(solderScopeSmoke.contains("start fallback skipped because recording indicator is visible"))
        #expect(solderScopeSmoke.contains("start fallback retry skipped because recording indicator is visible"))
        #expect(solderScopeSmoke.contains("recording indicator is visible after start"))
        #expect(solderScopeSmoke.contains("recording UI is idle after stop"))
        #expect(solderScopeSmoke.contains("stop retry skipped because recording indicator is not visible"))
        #expect(solderScopeSmoke.contains("stop fallback skipped because recording UI was already observed idle"))
        #expect(solderScopeSmoke.contains("recording_stop_observed_idle=1"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FREEZE_DRIVER"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FREEZE_KEY_DRIVER:-window"))
        #expect(solderScopeSmoke.contains("local freeze_key_driver=\"${7:-${QUILLUI_SOLDERSCOPE_FREEZE_KEY_DRIVER:-window}}\""))
        #expect(solderScopeSmoke.contains("shortcut $label $freeze_key_driver key space"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_freeze_shortcut_handled_count()"))
        #expect(solderScopeSmoke.contains("key shortcut=none\\\\+space .* handled=true"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_try_freeze_driver()"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_try_freeze_toolbar_candidates()"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FREEZE_ALT_KEY_DRIVER:-active"))
        #expect(solderScopeSmoke.contains("shortcut $label did not reach GTK handler"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FREEZE_BUTTON_RIGHT_OFFSET"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FREEZE_BUTTON_RIGHT_OFFSET:-218"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FREEZE_TOOLBAR_RIGHT_OFFSETS"))
        #expect(solderScopeSmoke.contains("205 230 190 245"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FREEZE_TOOLBAR_Y_OFFSET"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_TOOLBAR_PRESS_SECONDS:-0.08"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_TOOLBAR_SETTLE_SECONDS"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_TOOLBAR_RETARGET_DELTA_Y"))
        #expect(solderScopeSmoke.contains("SOLDERSCOPE_FREEZE_DRIVER=\"${QUILLUI_SOLDERSCOPE_FREEZE_DRIVER:-shortcut}\""))
        #expect(solderScopeSmoke.contains("quill-solderscope-freeze-interaction"))
        #expect(solderScopeSmoke.contains("freeze skipped"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_SNAPSHOT_DRIVER"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_SNAPSHOT_BUTTON_RIGHT_OFFSET"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_SNAPSHOT_TOOLBAR_Y_OFFSET"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_SNAPSHOT_RETRY_TICK"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_SNAPSHOT_ATTEMPTS:-40"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_SNAPSHOT_TICK_SECONDS:-0.25"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key()"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_recording_started_log_count()"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_recording_saved_log_count()"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_snapshot_saved_log_count()"))
        #expect(solderScopeSmoke.contains("SOLDERSCOPE_SNAPSHOT_LOG_BEFORE_COUNT"))
        #expect(solderScopeSmoke.contains("snapshot_saved_log_count=\"$(quillui_solderscope_snapshot_saved_log_count)\""))
        #expect(solderScopeSmoke.contains("snapshot_count > SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT || snapshot_saved_log_count > SOLDERSCOPE_SNAPSHOT_LOG_BEFORE_COUNT"))
        #expect(solderScopeSmoke.contains("snapshot_count <= SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT && snapshot_saved_log_count <= SOLDERSCOPE_SNAPSHOT_LOG_BEFORE_COUNT"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_wait_for_visible_frame_with_retry()"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_nudge_frame_redraw()"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FRAME_WAIT_RETRIES:-1"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_FRAME_NUDGE_SETTLE_SECONDS:-0.2"))
        #expect(solderScopeSmoke.contains("xdotool windowsize --sync \"$window_id\" \"$nudge_width\" \"$nudge_height\""))
        #expect(solderScopeSmoke.contains("xdotool windowsize --sync \"$window_id\" \"$window_width\" \"$window_height\""))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" 0"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_wait_for_visible_frame_with_retry \\\n      \"after snapshot\" \"$settled_snapshot_screenshot\" \"$window_id\" \"$window_width\" \"$window_height\""))
        #expect(solderScopeSmoke.contains("quillui_solderscope_wait_for_recording_idle()"))
        #expect(solderScopeSmoke.contains("local label=\"${1:-before interaction}\""))
        #expect(solderScopeSmoke.contains("local settled_screenshot_path=\"${2:-}\""))
        #expect(solderScopeSmoke.contains("cp -f \"$frame_probe_path\" \"$settled_screenshot_path\""))
        #expect(solderScopeSmoke.contains("synthetic frame is visible $label"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_wait_for_visible_frame_with_retry \\\n      \"before freeze\" \"\" \"$window_id\" \"$window_width\" \"$window_height\""))
        #expect(solderScopeSmoke.contains("quillui_solderscope_recording_indicator_red_pixels()"))
        #expect(solderScopeSmoke.contains("indicator_pixels > 500"))
        #expect(solderScopeSmoke.contains("local settled_screenshot_path=\"${1:-}\""))
        #expect(solderScopeSmoke.contains("cp -f \"$idle_probe_path\" \"$settled_screenshot_path\""))
        #expect(solderScopeSmoke.contains("local settled_recording_screenshot=\"${SCREENSHOT_PATH%.png}-recording-idle.png\""))
        #expect(solderScopeSmoke.contains("local settled_snapshot_screenshot=\"${SCREENSHOT_PATH%.png}-snapshot-settled.png\""))
        #expect(solderScopeSmoke.contains("quillui_solderscope_wait_for_visible_frame_with_retry \\\n      \"after recording\" \"$settled_recording_screenshot\" \"$window_id\" \"$window_width\" \"$window_height\""))
        #expect(solderScopeSmoke.contains("cp -f \"${SCREENSHOT_PATH%.png}-recording-idle.png\" \"$SCREENSHOT_PATH\""))
        #expect(solderScopeSmoke.contains("cp -f \"${SCREENSHOT_PATH%.png}-snapshot-settled.png\" \"$SCREENSHOT_PATH\""))
        #expect(solderScopeSmoke.contains("rm -f \"${SCREENSHOT_PATH%.png}-recording-idle.png\""))
        #expect(solderScopeSmoke.contains("rm -f \"${SCREENSHOT_PATH%.png}-snapshot-settled.png\""))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_IDLE_WAIT_SECONDS:-8"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_IDLE_TICK_SECONDS:-0.5"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_count_recordings"))
        #expect(solderScopeSmoke.contains("SolderScope_*.mov"))
        #expect(solderScopeSmoke.contains("dd if=\"$movie_path\" bs=1 skip=4 count=4"))
        #expect(solderScopeSmoke.contains("[[ \"$SOLDERSCOPE_DRIVE_SNAPSHOT\" != \"1\" ]]"))
        #expect(solderScopeSmoke.contains("DISPLAY=\"$DISPLAY_ID\" xdotool click 4"))
        #expect(solderScopeSmoke.contains("xdotool mousedown 1 mousemove --sync \"$drag_end_x\" \"$drag_end_y\" mouseup 1"))
        #expect(solderScopeSmoke.contains("click --repeat 2 --delay 80 1"))
        #expect(solderScopeSmoke.contains("DISPLAY=\"$DISPLAY_ID\" xdotool key --window \"$window_id\" --clearmodifiers \"$key\""))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_SAVE_ATTEMPTS:-120"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_SAVE_TICK_SECONDS:-0.25"))
        #expect(solderScopeSmoke.contains("QUILLUI_SOLDERSCOPE_RECORDING_SECONDS:-4"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" i"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" h"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" v"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" bracketright"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" 0"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" b"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" space"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" Escape"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" r"))
        #expect(solderScopeSmoke.contains("quillui_solderscope_send_key \"$window_id\" s"))
        #expect(solderScopeSmoke.contains("record-start"))
        #expect(solderScopeSmoke.contains("record-start-retry"))
        #expect(solderScopeSmoke.contains("record-start-fallback"))
        #expect(solderScopeSmoke.contains("record-start-fallback-retry"))
        #expect(solderScopeSmoke.contains("record-stop"))
        #expect(solderScopeSmoke.contains("record-stop-retry"))
        #expect(solderScopeSmoke.contains("snapshot"))
        #expect(solderScopeSmoke.contains("snapshot-retry"))
        #expect(solderScopeSmoke.contains("SolderScope interaction smoke: recording saved"))
        #expect(solderScopeSmoke.contains("SolderScope interaction smoke: snapshot saved"))
        #expect(screenshotVerifier.contains("lower_left_recording_pixels <= 500"))
        #expect(screenshotVerifier.contains("rgb[0] >= 180"))
        #expect(screenshotVerifier.contains("rgb[0] - rgb[1] >= 90"))
        #expect(screenshotVerifier.contains("SolderScope recording indicator is still visible after the stop action"))
        #expect(screenshotVerifier.contains("validate_quill_solderscope_freeze_interaction"))
        #expect(screenshotVerifier.contains("frozen_badge_pixels >= 500"))
        #expect(screenshotVerifier.contains("SolderScope FROZEN indicator was not detected after the freeze shortcut"))
        #expect(solderScopeWorkflow.contains("name: SolderScope Linux CI"))
        #expect(solderScopeWorkflow.contains("QUILLUI_SOLDERSCOPE_REQUIRED: \"1\""))
        #expect(solderScopeWorkflow.contains("SolderScope API and fixture tests"))
        #expect(solderScopeWorkflow.contains("SolderScope GTK launch and interaction"))
        #expect(solderScopeWorkflow.contains("scripts/fetch-upstream.sh solderscope"))
        #expect(solderScopeWorkflow.contains("scripts/linux-swift-test.sh --scratch-path .build-solderscope-api --filter SolderScopeChromeConformanceTests"))
        #expect(solderScopeWorkflow.contains("scripts/linux-swift-test.sh --scratch-path .build-solderscope-api --filter AVCaptureSurfaceTests"))
        #expect(solderScopeWorkflow.contains("scripts/linux-swift-test.sh --scratch-path .build-solderscope-api --filter V4L2ConversionTests"))
        #expect(solderScopeWorkflow.contains("scripts/linux-swift-test.sh --scratch-path .build-solderscope-api --filter BitmapAndMovieEncodeTests"))
        #expect(!solderScopeWorkflow.contains(".build-solderscope-capture"))
        #expect(!solderScopeWorkflow.contains(".build-solderscope-v4l2"))
        #expect(!solderScopeWorkflow.contains(".build-solderscope-encode"))
        #expect(solderScopeWorkflow.contains("scripts/linux-solderscope-smoke-check.sh .qa/quill-solderscope-visual.png visual"))
        #expect(solderScopeWorkflow.contains("SolderScope GTK snapshot smoke"))
        #expect(solderScopeWorkflow.contains("QUILLUI_SOLDERSCOPE_DRIVE_RECORDING=0 QUILLUI_SOLDERSCOPE_FREEZE_DRIVER=none scripts/linux-solderscope-smoke-check.sh .qa/quill-solderscope-snapshot.png interaction"))
        #expect(solderScopeWorkflow.contains("SolderScope GTK freeze smoke"))
        #expect(solderScopeWorkflow.contains("SolderScope GTK recording smoke"))
        #expect(solderScopeWorkflow.contains("QUILLUI_SOLDERSCOPE_SKIP_BUILD=1 QUILLUI_SOLDERSCOPE_SCRATCH_PATH=.build-solderscope-gtk QUILLUI_SOLDERSCOPE_DRIVE_SNAPSHOT=0 QUILLUI_SOLDERSCOPE_DRIVE_RECORDING=0 QUILLUI_SOLDERSCOPE_FREEZE_DRIVER=shortcut QUILLUI_SOLDERSCOPE_FREEZE_KEY_DRIVER=window QUILLUI_GTK_DEBUG_ACTIONS=1 scripts/linux-solderscope-smoke-check.sh .qa/quill-solderscope-interaction.png interaction"))
        #expect(solderScopeWorkflow.contains("QUILLUI_SOLDERSCOPE_DRIVE_SNAPSHOT=0 QUILLUI_SOLDERSCOPE_DRIVE_RECORDING=1 QUILLUI_SOLDERSCOPE_FREEZE_DRIVER=none scripts/linux-solderscope-smoke-check.sh .qa/quill-solderscope-recording.png interaction"))
        #expect(!solderScopeWorkflow.contains("QUILLUI_SOLDERSCOPE_SNAPSHOT_DRIVER=toolbar"))
        #expect(!solderScopeWorkflow.contains("QUILLUI_SOLDERSCOPE_FREEZE_DRIVER=toolbar"))
        #expect(!solderScopeWorkflow.contains("QUILLUI_SOLDERSCOPE_RECORDING_DRIVER=toolbar"))
        #expect(solderScopeWorkflow.contains("uses: actions/upload-artifact@v6"))
        #expect(fetchUpstream.contains("solderscope)"))
        #expect(fetchUpstream.contains("fetch_repo solderscope https://github.com/rjwalters/SolderScope.git"))
        #expect(fetchUpstream.contains("patch_solderscope"))
        #expect(fetchUpstream.contains("frozenFrame = materializedFrame(from: currentFrame) ?? lastRenderedFrame"))
        #expect(fetchUpstream.contains("private var frozenFrame: QuillFoundation.CGImage?"))
        #expect(fetchUpstream.contains("private var lastRenderedFrame: QuillFoundation.CGImage?"))
        #expect(fetchUpstream.contains("lastRenderedFrame = renderedImage"))
        #expect(fetchUpstream.contains("let cgImage: QuillFoundation.CGImage"))
        #expect(fetchUpstream.contains("if all(marker in new for marker in patched_markers):"))
        #expect(workflow.contains("QUILLUI_BACKEND_SKIP_BUILD=1 scripts/run-linux-backend-smoke-matrix.sh interaction generated-app-matrix '.qa/{product}-toolbar-menu-{backend}.png'"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products visual app-matrix '.qa/{product}-{backend}.png'"))
        #expect(workflow.contains("QUILLUI_BACKEND_SKIP_BUILD=1 scripts/run-linux-backend-smoke-matrix.sh interaction interaction-matrix '.qa/{product}-interaction-{backend}.png'"))
        #expect(workflow.contains("QUILLUI_BACKEND_SKIP_BUILD=1 scripts/run-linux-backend-smoke-matrix.sh interaction interaction-extra-mode-matrix '.qa/{product}-{mode}-{backend}.png'"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh validate-integrity"))
        #expect(workflow.contains("Each canonical app product compiles through the requested"))
        #expect(workflow.contains("scripts/build-linux-backend-products.sh --scratch-path .build-linux backend-apps"))
        #expect(!workflow.contains("native Qt products such as quill-enchanted-qt"))
        #expect(!workflow.contains("Qt rows currently exercise the shared launch-plan fallback"))
        #expect(!workflow.contains("With no per-product branch in `verify-backend-screenshot.py`"))
        #expect(workflow.contains("scripts/run-linux-backend-profile-csv.sh --matrix profile-matrix"))
        #expect(workflow.contains("QUILLUI_BACKEND_PROFILE_SETTLE: \"1\""))
        #expect(workflow.contains("QUILLUI_BACKEND_PROFILE_STEADY: \"3\""))
        #expect(workflow.contains("QUILLUI_BACKEND_PROFILE_ROW_TIMEOUT: \"2m\""))
        #expect(workflow.contains("QUILLUI_BACKEND_PROFILE_ROW_KILL_AFTER: \"10s\""))
        #expect(!workflow.contains("scripts/quillui-backend-products.sh profile-matrix | scripts/run-linux-backend-profile-csv.sh"))
        #expect(workflow.contains("Backend launch target interaction smokes"))
        #expect(!workflow.contains("while IFS=\"$tab\" read -r product backend; do"))
        #expect(!workflow.contains("scripts/linux-backend-interaction-check.sh .qa/quill-gtk-interaction-smoke-open.png quill-gtk-interaction-smoke"))
        #expect(!workflow.contains("scripts/linux-backend-interaction-check.sh .qa/quill-qt-interaction-smoke-open.png quill-qt-interaction-smoke"))
    }

    @Test("Qt widget hosts share native style helpers")
    func qtWidgetHostsShareNativeStyleHelpers() throws {
        let root = try packageRoot()
        let support = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillQtWidgetsSupport.hpp"),
            encoding: .utf8
        )
        let enchantedHost = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillEnchantedQt6Widgets.cpp"),
            encoding: .utf8
        )
        let genericHost = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillGenericQt6Widgets.cpp"),
            encoding: .utf8
        )

        #expect(support.contains("inline QString cssPixels("))
        #expect(support.contains("inline void refreshStyle(QWidget *widget)"))
        #expect(support.contains("inline void scrollAreaToBottomLater(QScrollArea *scrollArea)"))
        #expect(support.contains("QTimer::singleShot(0, scrollArea"))
        #expect(support.contains("scrollBar->setValue(scrollBar->maximum())"))
        #expect(!enchantedHost.contains("using QuillQtWidgets::cssPixels;"))
        #expect(enchantedHost.contains("QString stylePixels(const QJsonObject &style, const char *key)"))
        #expect(enchantedHost.contains("int styleInt(const QJsonObject &style, const char *key)"))
        #expect(enchantedHost.contains("using QuillQtWidgets::refreshStyle;"))
        #expect(enchantedHost.contains("using QuillQtWidgets::scrollAreaToBottomLater;"))
        #expect(!enchantedHost.contains("QString cssPixels("))
        #expect(!enchantedHost.contains("void refreshStyle(QWidget *widget)"))
        #expect(!enchantedHost.contains("void scrollAreaToBottomLater(QScrollArea *scrollArea)"))
        #expect(genericHost.contains("using QuillQtWidgets::cssPixels;"))
        #expect(!genericHost.contains("QString cssPixels("))
    }

    @Test("Generated Linux app packages can launch through backend facades")
    func generatedLinuxAppPackagesCanLaunchThroughBackendFacades() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/generate-swiftui-linux-package.sh"),
            encoding: .utf8
        )
        let buildSource = try String(
            contentsOf: root.appendingPathComponent("scripts/build-swiftui-linux-app.sh"),
            encoding: .utf8
        )
        let packageSource = try String(
            contentsOf: root.appendingPathComponent("scripts/package-swiftui-linux-app.sh"),
            encoding: .utf8
        )
        let metadataCheckSource = try String(
            contentsOf: root.appendingPathComponent("scripts/check-linux-app-metadata.sh"),
            encoding: .utf8
        )
        let flatpakManifestSource = try String(
            contentsOf: root.appendingPathComponent("scripts/generate-flatpak-manifest.sh"),
            encoding: .utf8
        )
        let runtimeDepsSource = try String(
            contentsOf: root.appendingPathComponent("scripts/check-linux-app-runtime-deps.sh"),
            encoding: .utf8
        )
        let linuxBuildToolingSource = try String(
            contentsOf: root.appendingPathComponent("docs/linux-build-tooling.md"),
            encoding: .utf8
        )
        let legacyQuillChatBuildSource = try String(
            contentsOf: root.appendingPathComponent("scripts/build-quill-chat-linux.sh"),
            encoding: .utf8
        )
        let enchantedBuildSource = try String(
            contentsOf: root.appendingPathComponent("scripts/build-enchanted-linux.sh"),
            encoding: .utf8
        )
        let enchantedSourceResolver = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-enchanted-source.sh"),
            encoding: .utf8
        )
        let fetchUpstream = try String(
            contentsOf: root.appendingPathComponent("scripts/fetch-upstream.sh"),
            encoding: .utf8
        )
        let vendoredSource = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-vendored-source.sh"),
            encoding: .utf8
        )
        let solderScopeVendor = try String(
            contentsOf: root.appendingPathComponent("vendor/apps/solderscope/QUILLUI_VENDOR.md"),
            encoding: .utf8
        )
        let solderScopeLicense = try String(
            contentsOf: root.appendingPathComponent("vendor/apps/solderscope/LICENSE"),
            encoding: .utf8
        )
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"),
            encoding: .utf8
        )
        let enchantedWorkflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/enchanted-parity.yml"),
            encoding: .utf8
        )
        let generatedEnchantedChatSource = try String(
            contentsOf: root.appendingPathComponent("scripts/generated-enchanted-chat-components-check.sh"),
            encoding: .utf8
        )
        let generatedEnchantedMacOSChatSource = try String(
            contentsOf: root.appendingPathComponent("scripts/generated-enchanted-macos-chat-check.sh"),
            encoding: .utf8
        )
        let generatedEnchantedSource = try String(
            contentsOf: root.appendingPathComponent("scripts/generated-enchanted-full-source-check.sh"),
            encoding: .utf8
        )
        let genericProfileSource = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/generic-swiftui.sh"),
            encoding: .utf8
        )
        let genericLoweredSourceCacheSource = try String(
            contentsOf: root.appendingPathComponent("scripts/swiftpm-profile-lowered-source-cache.sh"),
            encoding: .utf8
        )
        let genericProfileRuntimeSource = genericProfileSource + "\n" + genericLoweredSourceCacheSource
        let sourceCacheKey = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-source-cache-key.py"),
            encoding: .utf8
        )
        let genericAutoLayoutSource = try String(
            contentsOf: root.appendingPathComponent("scripts/swiftpm-profile-auto-layout.sh"),
            encoding: .utf8
        )
        let genericLocalImportsSource = try String(
            contentsOf: root.appendingPathComponent("scripts/swiftpm-profile-local-imports.sh"),
            encoding: .utf8
        )
        let localImportDiscoverySource = try String(
            contentsOf: root.appendingPathComponent("scripts/discover-local-swiftpm-import-dependencies.py"),
            encoding: .utf8
        )
        let vendorAppSource = try String(
            contentsOf: root.appendingPathComponent("scripts/vendor-app-source.sh"),
            encoding: .utf8
        )
        let vendorSwiftUIAppSource = try String(
            contentsOf: root.appendingPathComponent("scripts/vendor-swiftui-app-source.sh"),
            encoding: .utf8
        )
        let vendoredSourceHelper = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-vendored-source.sh"),
            encoding: .utf8
        )
        let codeEditVendor = try String(
            contentsOf: root.appendingPathComponent("vendor/apps/codeedit/QUILLUI_VENDOR.md"),
            encoding: .utf8
        )
        let quillCodeVendor = try String(
            contentsOf: root.appendingPathComponent("vendor/apps/quillcode/QUILLUI_VENDOR.md"),
            encoding: .utf8
        )
        let quillCodeVendorFingerprint = try String(
            contentsOf: root.appendingPathComponent("vendor/apps/quillcode/.quillui-vendor-source-fingerprint"),
            encoding: .utf8
        )

        #expect(source.contains("QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY"))
        #expect(source.contains("QUILLUI_GENERATED_BACKEND_FACADE"))
        #expect(source.contains("source \"$ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(source.contains("quillui_alias_env QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY QUILLUI_GENERATED_INCLUDE_GTK_BACKEND QUILLUI_GENERATED_INCLUDE_QT_BACKEND"))
        #expect(source.contains("INCLUDE_BACKEND_ENTRY=\"${QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY:-0}\""))
        #expect(!source.contains("${QUILLUI_GENERATED_INCLUDE_GTK_BACKEND:-0}"))
        #expect(source.contains("backend entry generation is enabled"))
        #expect(source.contains("validate_boolean_flag \"$INCLUDE_BACKEND_ENTRY\""))
        #expect(source.contains("normalize_generated_backend_facade"))
        #expect(source.contains("requires QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY=1"))
        #expect(source.contains("backend_import=\"QuillUI\""))
        #expect(source.contains("backend_runner=\"QuillApp\""))
        #expect(source.contains("backend_import=\"QuillUIGtk\""))
        #expect(source.contains("backend_runner=\"QuillGtkApp\""))
        #expect(source.contains("QT_NATIVE_CATALOG_ENTRY=\"${QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY:-QuillGenericQtAppCatalog.enchantedUpstreamSlice}\""))
        #expect(source.contains("validate_swift_type \"$QT_NATIVE_CATALOG_ENTRY\""))
        #expect(source.contains("backend_import=\"QuillGenericQtNativeRuntime\""))
        #expect(source.contains("backend_launch_statement=\"QuillGenericQtNativeApp.run($QT_NATIVE_CATALOG_ENTRY)\""))
        #expect(source.contains("backend_launch_statement=\"${backend_runner}.run(${APP_ENTRY_TYPE}.self)\""))
        #expect(source.contains("copy_source_files=0"))
        #expect(source.contains("if [[ \"$copy_source_files\" == \"1\" ]]"))
        #expect(source.contains("REQUESTED_PACKAGE_DIR=\"$PACKAGE_DIR\""))
        #expect(source.contains("PACKAGE_STAGING_DIR=\"$PACKAGE_PARENT_DIR/."))
        #expect(source.contains("sync_generated_package()"))
        #expect(source.contains("diff -qr \"$staging_dir\" \"$destination_dir\""))
        #expect(source.contains("Reused unchanged generated package: $relative_destination"))
        #expect(source.contains("rsync -a --delete --checksum \"$staging_dir\"/ \"$destination_dir\"/"))
        #expect(source.contains("Updated generated package: $relative_destination"))
        #expect(source.contains("PACKAGE_DIR=\"$REQUESTED_PACKAGE_DIR\""))
        #expect(!genericProfileSource.contains("rm -rf \"$PACKAGE_DIR\""))
        #expect(source.contains("RESOURCE_DIR=\"$TARGET_DIR/Resources\""))
        #expect(source.contains("scripts/copy-swiftui-linux-resources.py"))
        #expect(source.contains("TARGET_LAYOUT_FILE=\"${QUILLUI_GENERATED_TARGET_LAYOUT_FILE:-}\""))
        #expect(source.contains("EXTRA_PACKAGE_DEPENDENCIES_FILE=\"${QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}\""))
        #expect(source.contains("EXTRA_TARGET_DEPENDENCIES_FILE=\"${QUILLUI_GENERATED_EXTRA_TARGET_DEPENDENCIES_FILE:-}\""))
        #expect(source.contains("PREPARED_PACKAGE_CACHE_DIR=\"${QUILLUI_GENERATED_PREPARED_PACKAGE_CACHE_DIR:-}\""))
        #expect(source.contains(".product(name: \"CoreSpotlight\", package: \"QuillUI\")"))
        #expect(source.contains("validate_relative_path"))
        #expect(source.contains("swift_dependency_entry()"))
        #expect(source.contains("product:*"))
        #expect(source.contains(".product(name: \"%s\", package: \"%s\")"))
        #expect(source.contains("PREPARED_PACKAGE_DEPENDENCIES_FILE=\"$WORK_ROOT/prepared-package-dependencies.swift\""))
        #expect(source.contains("scripts/prepare-swiftui-linux-package-dependencies.py"))
        #expect(source.contains("--dependencies-in \"$EXTRA_PACKAGE_DEPENDENCIES_FILE\""))
        #expect(source.contains("--dependencies-out \"$PREPARED_PACKAGE_DEPENDENCIES_FILE\""))
        #expect(source.contains("prepare_dependency_args+=(--prepared-cache-dir \"$PREPARED_PACKAGE_CACHE_DIR\")"))
        #expect(source.contains("done < \"$PREPARED_PACKAGE_DEPENDENCIES_FILE\""))
        #expect(!source.contains("vendored_extra_package_dependency()"))
        #expect(source.contains("copy_swift_sources()"))
        #expect(source.contains("copy_resources_line()"))
        #expect(source.contains("append_target_definition"))
        #expect(source.contains("Target layout must include QUILLUI_GENERATED_TARGET_NAME=$TARGET_NAME"))
        #expect(source.contains("generated_swift_count_dir=\"$PACKAGE_DIR/Sources\""))
        #expect(source.contains("extra_package_dependencies+="))
        #expect(source.contains("extra_target_dependencies"))
        #expect(source.contains("Extra target dependency file was not found"))
        #expect(source.contains("$target_resources"))
        #expect(source.contains("source_target_dependencies="))
        #expect(source.contains(".product(name: \"Network\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"CryptoKit\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"ExtensionFoundation\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"ExtensionKit\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"PDFKit\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"QuickLook\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"QuickLookUI\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"QuillUIGtk\", package: \"QuillUI\")' \"$target_dependency_entries\")"))
        #expect(source.contains("import QuillAppKitGTK"))
        #expect(source.contains("_ = QuillAppKitGTKAutoInstall.didInstall"))
        #expect(source.contains(".product(name: \"QuillAppKitGTK\", package: \"QuillUI\")' \"$target_dependency_entries\")"))
        #expect(source.contains("if [[ \"$BACKEND_FACADE\" != \"qt\" ]]"))
        #expect(source.contains("quillui_generated_source_requires_macro_plugin()"))
        #expect(source.contains("grep -R -E -q --include='*.swift'"))
        #expect(source.contains("generated source still contains Swift macro syntax; disabling runtime-only macro stubs"))
        #expect(source.contains("QUILLUI_RUNTIME_ONLY_MACROS=\"$quillui_runtime_only_macros\" QUILLUI_LINUX_BACKEND=qt \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(source.contains("QUILLUI_RUNTIME_ONLY_MACROS=\"$quillui_runtime_only_macros\" QUILLUI_LINUX_BACKEND=gtk \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(source.contains("import $backend_import"))
        #expect(source.contains("$backend_launch_statement"))
        #expect(source.contains(".product(name: \"QuillUIGtk\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"QuillGenericQtNativeRuntime\", package: \"QuillUI\")"))
        #expect(buildSource.contains("--backend-facade"))
        #expect(buildSource.contains("--source-app"))
        #expect(buildSource.contains("--source-subdir"))
        #expect(buildSource.contains("QUILLUI_APP_SOURCE_APP"))
        #expect(buildSource.contains("QUILLUI_APP_SOURCE_SUBDIR"))
        #expect(buildSource.contains("source \"$ROOT_DIR/scripts/quillui-vendored-source.sh\""))
        #expect(buildSource.contains("validate_source_app_name()"))
        #expect(buildSource.contains("validate_relative_source_path()"))
        #expect(buildSource.contains("quillui_resolve_app_checkout_dir \"$ROOT_DIR\" \"$SOURCE_APP\""))
        #expect(buildSource.contains("SOURCE_DIR=\"$SOURCE_CHECKOUT_DIR/$SOURCE_SUBDIR\""))
        #expect(buildSource.contains("PACKAGE_ROOT=\"$SOURCE_CHECKOUT_DIR\""))
        #expect(buildSource.contains("using vendored $SOURCE_APP source at vendor/apps/$SOURCE_APP"))
        #expect(buildSource.contains("quillui_print_vendored_app_source_summary \"$ROOT_DIR\" \"$SOURCE_APP\""))
        #expect(buildSource.contains("using upstream $SOURCE_APP source at .upstream/$SOURCE_APP"))
        #expect(buildSource.contains("--prepared-package-cache-dir"))
        #expect(buildSource.contains("QUILLUI_APP_PREPARED_PACKAGE_CACHE_DIR"))
        #expect(buildSource.contains(".build/quillui-prepared-packages-cache"))
        #expect(buildSource.contains("--build-scratch"))
        #expect(buildSource.contains("--build-scratch-cache-dir"))
        #expect(buildSource.contains("--no-reuse-build-scratch"))
        #expect(buildSource.contains("QUILLUI_APP_BUILD_SCRATCH"))
        #expect(buildSource.contains("QUILLUI_APP_BUILD_SCRATCH_CACHE_DIR"))
        #expect(buildSource.contains("QUILLUI_APP_REUSE_BUILD_SCRATCH=1"))
        #expect(buildSource.contains("generated_app_build_scratch_key()"))
        #expect(buildSource.contains("default_generated_build_scratch()"))
        #expect(buildSource.contains(".build/quillui-generated-app-build-cache"))
        #expect(buildSource.contains("quillui-generated-app-build-scratch/v1"))
        #expect(buildSource.contains("scripts/generate-swiftui-linux-package.sh"))
        #expect(buildSource.contains("Package.resolved"))
        #expect(buildSource.contains("QUILLUI_GENERATED_BUILD_SCRATCH=\"$BUILD_SCRATCH\""))
        #expect(buildSource.contains("--scratch-path \"$BUILD_SCRATCH\""))
        #expect(buildSource.contains("==> generated app SwiftPM scratch:"))
        #expect(buildSource.contains("--vendor-swiftpm-sources"))
        #expect(buildSource.contains("--no-vendor-swiftpm-sources"))
        #expect(buildSource.contains("QUILLUI_APP_VENDOR_SWIFTPM_SOURCES"))
        #expect(buildSource.contains("VENDOR_SWIFTPM_SOURCES=\"${QUILLUI_APP_VENDOR_SWIFTPM_SOURCES:-auto}\""))
        #expect(buildSource.contains("QUILLUI_APP_VENDOR_SWIFTPM_SOURCES=auto"))
        #expect(buildSource.contains("validate_vendor_swiftpm_sources_mode()"))
        #expect(buildSource.contains("vendor_swiftpm_sources_enabled()"))
        #expect(buildSource.contains("vendor_swiftpm_app_stamp_key()"))
        #expect(buildSource.contains("vendor_swiftpm_app_packages()"))
        #expect(buildSource.contains("run_vendor_swiftpm_sources_for_app()"))
        #expect(buildSource.contains("QUILLUI_APP_VENDOR_SWIFTPM_STAMP_DIR"))
        #expect(buildSource.contains(".build/quillui-vendored-swiftpm-source-stamps"))
        #expect(buildSource.contains("quillui-vendored-swiftpm-app/v1"))
        #expect(buildSource.contains("Reused vendored SwiftPM source scan"))
        #expect(buildSource.contains("quillui_vendored_swiftpm_app_stamp_is_valid \"$ROOT_DIR\" \"$stamp_file\""))
        #expect(buildSource.contains("quillui_write_vendored_swiftpm_app_stamp \"$ROOT_DIR\" \"$stamp_file\" \"$app_name\" \"$stamp_key\""))
        #expect(buildSource.contains("--check-vendored >/dev/null"))
        #expect(buildSource.contains("Vendored SwiftPM package sources already cover $app_name"))
        #expect(buildSource.contains("Vendored SwiftPM source scan stamp is stale; refreshing"))
        #expect(buildSource.contains("Vendored SwiftPM package sources are incomplete for $app_name."))
        #expect(buildSource.contains("scripts/vendor-swiftpm-sources.sh --app $app_name --hydrate-missing"))
        #expect(buildSource.contains("scripts/vendor-swiftpm-sources.sh\", \"scripts/quillui-vendored-source.sh"))
        #expect(buildSource.contains("for path in sorted(checkout.rglob(\"Package.resolved\"))"))
        #expect(buildSource.contains("run_vendor_swiftpm_sources_for_app \"$SOURCE_APP\" \"$SOURCE_CHECKOUT_DIR\""))
        #expect(buildSource.contains("auto|AUTO|Auto)"))
        #expect(buildSource.contains("QUILLUI_APP_VENDOR_SWIFTPM_RESOLVE"))
        #expect(buildSource.contains("--print-package-list"))
        #expect(buildSource.contains("local vendor_swiftpm_args=(\"$ROOT_DIR/scripts/vendor-swiftpm-sources.sh\" \"--app\" \"$app_name\")"))
        #expect(buildSource.contains("vendor_swiftpm_args+=(\"--no-resolve\")"))
        #expect(buildSource.contains("--vendor-swiftpm-sources requires --source-app"))
        #expect(buildSource.contains("QUILLUI_RUNTIME_ONLY_MACROS=0"))
        #expect(buildSource.contains("QUILLUI_RUNTIME_ONLY_MACROS=\"$quillui_runtime_only_macros\" QUILLUI_LINUX_BACKEND=qt"))
        #expect(buildSource.contains("QUILLUI_RUNTIME_ONLY_MACROS=\"$quillui_runtime_only_macros\" QUILLUI_LINUX_BACKEND=gtk"))
        #expect(buildSource.contains("QUILLUI_APP_BACKEND_FACADE"))
        #expect(buildSource.contains("NORMALIZED_BACKEND_FACADE"))
        #expect(buildSource.contains("QUILLUI_LINUX_BACKEND=qt \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(buildSource.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(buildSource.contains("QUILLUI_LINUX_BACKEND=gtk \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(buildSource.contains("quillui_normalize_backend_identifier \"${BACKEND_FACADE:-swiftui}\""))
        #expect(buildSource.contains("QUILLUI_GENERATED_BACKEND_FACADE=\"$NORMALIZED_BACKEND_FACADE\""))
        #expect(buildSource.contains("QUILLUI_GENERATED_PREPARED_PACKAGE_CACHE_DIR=\"$PREPARED_PACKAGE_CACHE_DIR\""))
        #expect(buildSource.contains("--package-root"))
        #expect(buildSource.contains("QUILLUI_APP_PACKAGE_ROOT"))
        #expect(buildSource.contains("--package-root does not contain Package.swift"))
        #expect(buildSource.contains("QUILLUI_PROFILE_PACKAGE_ROOT=\"$PACKAGE_ROOT\""))
        #expect(buildSource.contains("--entry-target"))
        #expect(buildSource.contains("QUILLUI_APP_ENTRY_TARGET"))
        #expect(buildSource.contains("QUILLUI_PROFILE_ENTRY_TARGET=\"$ENTRY_TARGET\""))
        #expect(buildSource.contains("--target-layout-file"))
        #expect(buildSource.contains("QUILLUI_APP_TARGET_LAYOUT_FILE"))
        #expect(buildSource.contains("QUILLUI_GENERATED_TARGET_LAYOUT_FILE=\"$TARGET_LAYOUT_FILE\""))
        #expect(buildSource.contains("--extra-package-dependencies-file"))
        #expect(buildSource.contains("QUILLUI_APP_EXTRA_PACKAGE_DEPENDENCIES_FILE"))
        #expect(buildSource.contains("QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE=\"$EXTRA_PACKAGE_DEPENDENCIES_FILE\""))
        #expect(buildSource.contains("--extra-target-dependencies-file"))
        #expect(buildSource.contains("QUILLUI_APP_EXTRA_TARGET_DEPENDENCIES_FILE"))
        #expect(buildSource.contains("QUILLUI_GENERATED_EXTRA_TARGET_DEPENDENCIES_FILE=\"$EXTRA_TARGET_DEPENDENCIES_FILE\""))
        #expect(buildSource.contains("QUILLUI_REQUIRE_VENDORED_SOURCES=0"))
        #expect(buildSource.contains("QUILLUI_REQUIRE_VENDORED_SOURCES=\"${QUILLUI_REQUIRE_VENDORED_SOURCES:-1}\""))
        #expect(buildSource.contains("GENERATED_APP_RESOURCES_DIR=\"$WORK_ROOT/package/Sources/GeneratedSwiftUILinuxApp/Resources\""))
        #expect(buildSource.contains("scripts/materialize-swiftui-linux-main-bundle-resources.py"))
        #expect(linuxBuildToolingSource.contains("--vendor-swiftpm-sources"))
        #expect(linuxBuildToolingSource.contains("vendor-swiftui-app-source.sh"))
        #expect(linuxBuildToolingSource.contains("QUILLUI_APP_VENDOR_SWIFTPM_RESOLVE=1"))
        #expect(linuxBuildToolingSource.contains(".build/quillui-lowered-source-cache"))
        #expect(linuxBuildToolingSource.contains("--build-scratch"))
        #expect(linuxBuildToolingSource.contains(".build/quillui-generated-app-build-cache"))
        #expect(linuxBuildToolingSource.contains("--no-reuse-build-scratch"))
        #expect(buildSource.contains("--artifact-path-file"))
        #expect(buildSource.contains("QUILLUI_APP_ARTIFACT_PATH_FILE"))
        #expect(buildSource.contains("printf '%s\\n' \"$ARTIFACT_PATH\" > \"$ARTIFACT_PATH_FILE\""))
        #expect(vendoredSourceHelper.contains("quillui_vendored_swiftpm_manifest_fingerprint()"))
        #expect(vendoredSourceHelper.contains("quillui_vendored_swiftpm_app_stamp_is_valid()"))
        #expect(vendoredSourceHelper.contains("quillui_write_vendored_swiftpm_app_stamp()"))
        #expect(vendoredSourceHelper.contains("quillui-vendored-swiftpm-manifests/v1"))
        #expect(vendoredSourceHelper.contains("swiftpmPackage=%s"))
        #expect(vendoredSourceHelper.contains("manifestFingerprint=%s"))
        #expect(genericProfileRuntimeSource.contains("scripts/run-quill-source-lower.sh"))
        #expect(genericProfileRuntimeSource.contains("scripts/lower-swiftui-source-for-linux.sh"))
        #expect(genericProfileRuntimeSource.contains("QUILLUI_PROFILE_LOWERED_SOURCE_CACHE_DIR"))
        #expect(genericProfileRuntimeSource.contains("QUILLUI_PROFILE_REUSE_LOWERED_SOURCE"))
        #expect(genericProfileRuntimeSource.contains("scripts/quillui-source-cache-key.py"))
        #expect(genericProfileRuntimeSource.contains(".build/quillui-lowered-source-cache"))
        #expect(genericProfileRuntimeSource.contains(".quillui-lowered-source-cache-key"))
        #expect(genericProfileRuntimeSource.contains("Reused cached generic SwiftUI lowered source"))
        #expect(sourceCacheKey.contains("quillui-lowered-source-cache-v2"))
        #expect(sourceCacheKey.contains("vendored_app_source_fingerprint"))
        #expect(sourceCacheKey.contains("source-vendored-app"))
        #expect(sourceCacheKey.contains("source-vendor-fingerprint"))
        #expect(sourceCacheKey.contains("\"vendor/apps\""))
        #expect(sourceCacheKey.contains(".quillui-vendor-source-fingerprint"))
        #expect(sourceCacheKey.contains("\"node_modules\""))
        #expect(genericProfileRuntimeSource.contains("mkdir -p \"$WORK_ROOT\""))
        #expect(!genericProfileSource.contains("rm -rf \"$PACKAGE_DIR\""))
        #expect(!genericProfileRuntimeSource.contains("rm -rf \"$WORK_ROOT\""))
        #expect(genericProfileRuntimeSource.contains("source \"$ROOT_DIR/scripts/swiftpm-profile-auto-layout.sh\""))
        #expect(genericProfileRuntimeSource.contains("source \"$ROOT_DIR/scripts/swiftpm-profile-local-imports.sh\""))
        #expect(genericProfileRuntimeSource.contains("source \"$ROOT_DIR/scripts/swiftpm-profile-lowered-source-cache.sh\""))
        #expect(genericProfileRuntimeSource.contains("PREPARED_PACKAGE_CACHE_DIR=\"${QUILLUI_PROFILE_PREPARED_PACKAGE_CACHE_DIR:-${QUILLUI_GENERATED_PREPARED_PACKAGE_CACHE_DIR:-$ROOT_DIR/.build/quillui-prepared-packages-cache}}\""))
        #expect(genericProfileRuntimeSource.contains("QUILLUI_GENERATED_PREPARED_PACKAGE_CACHE_DIR=\"$PREPARED_PACKAGE_CACHE_DIR\""))
        #expect(genericProfileRuntimeSource.contains("QUILLUI_REQUIRE_VENDORED_SOURCES=\"${QUILLUI_REQUIRE_VENDORED_SOURCES:-1}\""))
        #expect(genericProfileRuntimeSource.contains("quillui_profile_maybe_derive_swiftpm_layout"))
        #expect(genericProfileRuntimeSource.contains("quillui_profile_maybe_discover_local_import_dependencies"))
        #expect(genericAutoLayoutSource.contains("scripts/swiftpm-package-layout-for-linux.py"))
        #expect(genericAutoLayoutSource.contains("QUILLUI_PROFILE_PACKAGE_ROOT"))
        #expect(genericAutoLayoutSource.contains("QUILLUI_PROFILE_ENTRY_TARGET"))
        #expect(genericAutoLayoutSource.contains("QUILLUI_PROFILE_RESOLVED_PACKAGE_ROOT"))
        #expect(genericAutoLayoutSource.contains("QUILLUI_GENERATED_TARGET_LAYOUT_FILE=\"$auto_layout_file\""))
        #expect(genericAutoLayoutSource.contains("QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE=\"$auto_dependencies_file\""))
        #expect(genericLocalImportsSource.contains("scripts/discover-local-swiftpm-import-dependencies.py"))
        #expect(genericLocalImportsSource.contains("--exclude-package-root"))
        #expect(genericLocalImportsSource.contains("QUILLUI_PROFILE_RESOLVED_PACKAGE_ROOT"))
        #expect(genericLocalImportsSource.contains("QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE"))
        #expect(genericLocalImportsSource.contains("QUILLUI_GENERATED_EXTRA_TARGET_DEPENDENCIES_FILE"))
        #expect(localImportDiscoverySource.contains("IMPORT_RE"))
        #expect(localImportDiscoverySource.contains("--exclude-package-root"))
        #expect(localImportDiscoverySource.contains("\"third_party\", \".upstream\", \"vendor/apps\""))
        #expect(localImportDiscoverySource.contains("EXPORTED_CUSTOM_TARGET_RE"))
        #expect(localImportDiscoverySource.contains("QUILL_PROVIDED_IMPORTS"))
        #expect(localImportDiscoverySource.contains("\"Cocoa\""))
        #expect(localImportDiscoverySource.contains("\".\" in package_path.name or \"-\" in package_path.name"))
        #expect(localImportDiscoverySource.contains("product:{product.product_name}:{product.package_name}"))
        #expect(genericProfileRuntimeSource.contains("scripts/generate-swiftui-linux-package.sh"))
        #expect(genericProfileRuntimeSource.contains("QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY=1"))
        #expect(genericProfileRuntimeSource.contains("generic-swiftui qt facade requires QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY"))
        #expect(!genericProfileRuntimeSource.contains("Enchanted"))
        #expect(!genericProfileRuntimeSource.contains("QuillCode"))
        #expect(packageSource.contains("scripts/build-swiftui-linux-app.sh"))
        #expect(packageSource.contains("QUILLUI_APP_BACKEND_FACADE:-gtk"))
        #expect(packageSource.contains("QUILLUI_APP_ID"))
        #expect(packageSource.contains("validate_app_id \"$APP_ID\""))
        #expect(packageSource.contains("QUILLUI_APP_BUNDLE_SWIFT_RUNTIME"))
        #expect(packageSource.contains("--bundle-swift-runtime"))
        #expect(packageSource.contains("validate_boolean_flag \"$BUNDLE_SWIFT_RUNTIME\""))
        #expect(packageSource.contains("xml_escape()"))
        #expect(packageSource.contains("--artifact-path-file \"$ARTIFACT_PATH_FILE\""))
        #expect(packageSource.contains("\"$ARTIFACT_DIR/share/applications\""))
        #expect(packageSource.contains("\"$ARTIFACT_DIR/share/metainfo\""))
        #expect(packageSource.contains("cp \"$ARTIFACT_PATH\" \"$ARTIFACT_DIR/bin/$PRODUCT_NAME\""))
        #expect(packageSource.contains("ARTIFACT_BIN_DIR=\"$(dirname \"$ARTIFACT_PATH\")\""))
        #expect(packageSource.contains("find \"$ARTIFACT_BIN_DIR\" -maxdepth 1 -type d \\( -name '*.resources' -o -name '*.bundle' \\) -print0"))
        #expect(packageSource.contains("cp -R \"$resource_dir\" \"$ARTIFACT_DIR/bin/\""))
        #expect(packageSource.contains("SWIFT_RUNTIME_DIR=\"$ARTIFACT_DIR/lib/swift/linux\""))
        #expect(packageSource.contains("cp -L \"$runtime_library\" \"$SWIFT_RUNTIME_DIR/$(basename \"$runtime_library\")\""))
        #expect(packageSource.contains("cat > \"$ARTIFACT_DIR/share/applications/$APP_ID.desktop\""))
        #expect(packageSource.contains("Exec=$DESKTOP_EXEC"))
        #expect(packageSource.contains("Icon=$ICON_NAME"))
        #expect(packageSource.contains("cat > \"$ARTIFACT_DIR/share/metainfo/$APP_ID.metainfo.xml\""))
        #expect(packageSource.contains("<launchable type=\"desktop-id\">$APP_ID.desktop</launchable>"))
        #expect(packageSource.contains("export GTK_A11Y=\"\\${GTK_A11Y:-none}\""))
        #expect(packageSource.contains("export QUILLUI_BACKEND=\"\\${QUILLUI_BACKEND:-$NORMALIZED_BACKEND_FACADE}\""))
        #expect(packageSource.contains("export LD_LIBRARY_PATH=\"\\$DIR/lib/swift/linux\\${LD_LIBRARY_PATH:+:\\$LD_LIBRARY_PATH}\""))
        #expect(packageSource.contains("printf 'app_id=%s\\n' \"$APP_ID\""))
        #expect(packageSource.contains("printf 'swift_runtime_bundled=%s\\n' \"$BUNDLE_SWIFT_RUNTIME\""))
        #expect(packageSource.contains("printf 'swift_runtime_library_count=%s\\n' \"$SWIFT_RUNTIME_LIBRARY_COUNT\""))
        #expect(packageSource.contains("metadata/quillui-release.env"))
        #expect(packageSource.contains("tar -C \"$(dirname \"$ARTIFACT_DIR\")\" -czf \"$TARBALL_PATH\""))
        #expect(metadataCheckSource.contains("Usage: $(basename \"$0\") ARTIFACT_DIR APP_ID PRODUCT_NAME [DISPLAY_NAME]"))
        #expect(metadataCheckSource.contains("share/applications/$APP_ID.desktop"))
        #expect(metadataCheckSource.contains("share/metainfo/$APP_ID.metainfo.xml"))
        #expect(metadataCheckSource.contains("grep -Fx \"Exec=$PRODUCT_NAME\""))
        #expect(metadataCheckSource.contains("ET.parse(metainfo_path).getroot()"))
        #expect(metadataCheckSource.contains("Linux app metadata ok: %s"))
        #expect(flatpakManifestSource.contains("Usage: $(basename \"$0\") --artifact-dir PATH [--output PATH]"))
        #expect(flatpakManifestSource.contains("QUILLUI_FLATPAK_ARTIFACT_DIR"))
        #expect(flatpakManifestSource.contains("metadata_value app_id \"$METADATA_FILE\""))
        #expect(flatpakManifestSource.contains("\"app-id\": app_id"))
        #expect(flatpakManifestSource.contains("\"runtime\": os.environ[\"QUILLUI_FLATPAK_RUNTIME_ID\"]"))
        #expect(flatpakManifestSource.contains("\"command\": product_name"))
        #expect(flatpakManifestSource.contains("\"finish-args\": finish_args"))
        #expect(flatpakManifestSource.contains("if [ -d lib ]; then cp -a lib /app/lib/quillui-app/; fi"))
        #expect(flatpakManifestSource.contains("install -Dm644 share/applications/{app_id}.desktop"))
        #expect(flatpakManifestSource.contains("install -Dm644 share/metainfo/{app_id}.metainfo.xml"))
        #expect(flatpakManifestSource.contains("exec /app/lib/quillui-app/run \"$@\""))
        #expect(flatpakManifestSource.contains("Flatpak manifest written: %s"))
        #expect(runtimeDepsSource.contains("Usage: $(basename \"$0\") ARTIFACT_DIR PRODUCT_NAME [--report PATH]"))
        #expect(runtimeDepsSource.contains("--require-bundled-swift-runtime"))
        #expect(runtimeDepsSource.contains("ldd \"$BINARY_PATH\" > \"$LDD_OUTPUT\""))
        #expect(runtimeDepsSource.contains("LDD_LIBRARY_PATHS+=(\"$ARTIFACT_DIR/lib/swift/linux\")"))
        #expect(runtimeDepsSource.contains("LD_LIBRARY_PATH=\"$LDD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}\" ldd \"$BINARY_PATH\""))
        #expect(runtimeDepsSource.contains("library\\tkind\\tpath"))
        #expect(runtimeDepsSource.contains("swift-runtime"))
        #expect(runtimeDepsSource.contains("Swift runtime resolved from host:"))
        #expect(runtimeDepsSource.contains("artifact-bundled"))
        #expect(runtimeDepsSource.contains("Unresolved runtime dependencies:"))
        #expect(runtimeDepsSource.contains("Runtime dependency report written: %s"))
        #expect(legacyQuillChatBuildSource.contains("scripts/build-enchanted-linux.sh"))
        #expect(enchantedBuildSource.contains("--backend-facade"))
        #expect(enchantedBuildSource.contains("QUILLUI_ENCHANTED_BACKEND_FACADE"))
        #expect(enchantedBuildSource.contains("QUILLUI_QUILL_CHAT_BACKEND_FACADE"))
        #expect(enchantedBuildSource.contains("source \"$ROOT_DIR/scripts/quillui-enchanted-source.sh\""))
        #expect(enchantedBuildSource.contains("APP_DIR=\"$(quillui_resolve_enchanted_source_dir \"$ROOT_DIR\")\""))
        #expect(enchantedBuildSource.contains("BACKEND_FACADE_ARGS=(--backend-facade \"$BACKEND_FACADE\")"))
        #expect(enchantedSourceResolver.contains("quillui_resolve_enchanted_source_dir()"))
        #expect(enchantedSourceResolver.contains("QUILLUI_APP_SOURCE_DIR"))
        #expect(enchantedSourceResolver.contains("ENCHANTED_SOURCE_DIR"))
        #expect(enchantedSourceResolver.contains("quillui_resolve_enchanted_checkout_dir()"))
        #expect(enchantedSourceResolver.contains("vendor/apps/enchanted/Enchanted"))
        #expect(enchantedSourceResolver.contains("QUILL_CHAT_DIR/Enchanted"))
        #expect(enchantedSourceResolver.contains(".upstream/enchanted"))
        #expect(fetchUpstream.contains("source \"$ROOT_DIR/scripts/quillui-vendored-source.sh\""))
        #expect(fetchUpstream.contains("quillui_materialize_vendored_app_source \"$ROOT_DIR\" \"$name\" \"$dest\""))
        #expect(fetchUpstream.contains("fetch_repo enchanted https://github.com/gluonfield/enchanted.git"))
        #expect(fetchUpstream.contains("fetch_repo codeedit https://github.com/CodeEditApp/CodeEdit.git"))
        #expect(fetchUpstream.contains("fetch_repo solderscope https://github.com/rjwalters/SolderScope.git"))
        #expect(fetchUpstream.contains("logger=\"$dir/Utilities/Logger.swift\""))
        #expect(fetchUpstream.contains("patch_solderscope: lowered import os.log"))
        #expect(!fetchUpstream.contains("swift run quill-lower-appkit \"$dir\""))
        #expect(solderScopeVendor.contains("https://github.com/rjwalters/SolderScope"))
        #expect(solderScopeVendor.contains("54693b618ca11e86b005474246664fe1f5473449"))
        #expect(solderScopeVendor.contains("QUILLUI_REFRESH_VENDORED_SOURCE=1"))
        #expect(solderScopeLicense.contains("MIT License"))
        #expect(codeEditVendor.contains("https://github.com/CodeEditApp/CodeEdit.git"))
        #expect(codeEditVendor.contains("cec6287a49a0a460cd7cab17f254eebc3ada828e"))
        #expect(codeEditVendor.contains("License: MIT, preserved in `LICENSE.md`"))
        #expect(quillCodeVendor.contains("git@github.com:Lore-Hex/QuillCode.git"))
        #expect(quillCodeVendor.contains("af513673fa03476cc8cb17e2113dad75f2edb76e"))
        #expect(quillCodeVendor.contains("Keep the app source pristine"))
        #expect(quillCodeVendorFingerprint.contains("app=quillcode"))
        #expect(quillCodeVendorFingerprint.contains("source=git:af513673fa03476cc8cb17e2113dad75f2edb76e"))
        #expect(vendoredSource.contains("quillui_materialize_vendored_app_source()"))
        #expect(vendoredSource.contains("quillui_resolve_app_checkout_dir()"))
        #expect(vendoredSource.contains("quillui_resolve_app_source_dir()"))
        #expect(vendoredSource.contains("quillui_print_vendored_app_source_summary()"))
        #expect(vendoredSource.contains("vendored %s source snapshot"))
        #expect(vendoredSource.contains("quillui_upstream_app_source_dir()"))
        #expect(vendoredSource.contains("vendor/apps/$name"))
        #expect(vendoredSource.contains("QUILLUI_REFRESH_VENDORED_SOURCE"))
        #expect(vendoredSource.contains("refusing to materialize vendored $name outside .upstream"))
        #expect(vendoredSource.contains(".quillui-materialized-vendor-source-fingerprint"))
        #expect(vendoredSource.contains("cmp -s"))
        #expect(vendoredSource.contains("reused materialized vendored $name source"))
        #expect(vendoredSource.contains("refreshing materialized vendored $name source"))
        #expect(vendoredSource.contains("rsync -a --delete"))
        #expect(vendoredSource.contains("syncing vendored $name source"))
        #expect(vendorAppSource.contains("QUILLUI_VENDOR.md"))
        #expect(vendorAppSource.contains("QUILLUI_VENDOR_FORCE=1"))
        #expect(vendorAppSource.contains("git_source_identity()"))
        #expect(vendorAppSource.contains("rev-parse --show-toplevel"))
        #expect(vendorAppSource.contains("git -C \"$source\" status --porcelain --untracked-files=no"))
        #expect(vendorAppSource.contains("content_source_identity()"))
        #expect(vendorAppSource.contains("\".artifacts\""))
        #expect(vendorAppSource.contains("\".qa\""))
        #expect(vendorAppSource.contains("--exclude '.artifacts'"))
        #expect(vendorAppSource.contains("--exclude '.qa'"))
        #expect(vendorAppSource.contains("\"node_modules\""))
        #expect(vendorAppSource.contains("--exclude 'node_modules'"))
        #expect(vendorAppSource.contains("\"test-results\""))
        #expect(vendorAppSource.contains("--exclude 'test-results'"))
        #expect(vendorAppSource.contains("rsync -a --delete --delete-excluded"))
        #expect(vendorAppSource.contains("quillui-app-source-tree/v1"))
        #expect(vendorAppSource.contains("tree:\" + digest.hexdigest()"))
        #expect(vendorAppSource.contains("vendored_app_source_metadata()"))
        #expect(vendorAppSource.contains("quillui-app-source-vendor/v1"))
        #expect(vendorAppSource.contains(".quillui-vendor-source-fingerprint"))
        #expect(vendorAppSource.contains("PRESERVED_VENDOR_NOTE"))
        #expect(vendorAppSource.contains("cp \"$DEST_DIR/QUILLUI_VENDOR.md\" \"$PRESERVED_VENDOR_NOTE\""))
        #expect(vendorAppSource.contains("cp \"$PRESERVED_VENDOR_NOTE\" \"$DEST_DIR/QUILLUI_VENDOR.md\""))
        #expect(vendorAppSource.contains("already vendored $APP_NAME source -> vendor/apps/$APP_NAME"))
        #expect(vendorSwiftUIAppSource.contains("Pin a SwiftUI app checkout for fast QuillUI Linux builds"))
        #expect(vendorSwiftUIAppSource.contains("vendor-app-source.sh"))
        #expect(vendorSwiftUIAppSource.contains("vendor-swiftpm-sources.sh"))
        #expect(vendorSwiftUIAppSource.contains("--no-resolve"))
        #expect(vendorSwiftUIAppSource.contains("--hydrate-missing"))
        #expect(vendorSwiftUIAppSource.contains("HYDRATE_DEPENDENCIES=1"))
        #expect(vendorSwiftUIAppSource.contains("dependency_args+=(\"--hydrate-missing\")"))
        #expect(vendorSwiftUIAppSource.contains("append_package_resolved_files_from_source"))
        #expect(enchantedWorkflow.contains("--source-app enchanted"))
        #expect(enchantedWorkflow.contains("--source-subdir Enchanted"))
        #expect(enchantedWorkflow.contains("Confirm vendored Enchanted source"))
        #expect(enchantedWorkflow.contains("Audit vendored Enchanted SwiftPM sources"))
        #expect(enchantedWorkflow.contains("scripts/vendor-swiftpm-sources.sh --app enchanted --no-resolve --check-vendored"))
        #expect(enchantedWorkflow.contains("Restore lowered source cache"))
        #expect(enchantedWorkflow.contains("uses: ./.github/actions/lowered-source-cache"))
        #expect(enchantedWorkflow.contains("source-app: enchanted"))
        #expect(enchantedWorkflow.contains("scripts/audit-upstream-enchanted.sh >/tmp/quillui-enchanted-vendored-audit.md"))
        #expect(!enchantedWorkflow.contains("Restore upstream source cache"))
        #expect(!enchantedWorkflow.contains("scripts/fetch-upstream.sh enchanted"))
        #expect(!enchantedWorkflow.contains("ENCHANTED_APP_DIR=\"$(quillui_resolve_enchanted_source_dir \"$PWD\")\""))
        #expect(!enchantedWorkflow.contains("QUILL_CHAT_DIR: ${{ github.workspace }}/.upstream/enchanted"))
        #expect(!workflow.contains("QUILL_CHAT_DIR: ${{ github.workspace }}/.upstream/enchanted"))
        #expect(!source.contains("import BackendGTK4"))
        #expect(!source.contains("GTK4Backend().run($APP_ENTRY_TYPE.self)"))
        #expect(!source.contains("GTK backend generation is enabled"))
        #expect(generatedEnchantedChatSource.contains("source \"$ROOT_DIR/scripts/quillui-enchanted-source.sh\""))
        #expect(generatedEnchantedChatSource.contains("UPSTREAM_DIR=\"$(quillui_resolve_enchanted_source_dir \"$ROOT_DIR\")\""))
        #expect(generatedEnchantedMacOSChatSource.contains("source \"$ROOT_DIR/scripts/quillui-enchanted-source.sh\""))
        #expect(generatedEnchantedMacOSChatSource.contains("UPSTREAM_DIR=\"$(quillui_resolve_enchanted_source_dir \"$ROOT_DIR\")\""))
        #expect(generatedEnchantedSource.contains("source \"$ROOT_DIR/scripts/quillui-enchanted-source.sh\""))
        #expect(generatedEnchantedSource.contains("source \"$ROOT_DIR/scripts/swiftpm-profile-lowered-source-cache.sh\""))
        #expect(generatedEnchantedSource.contains("UPSTREAM_DIR=\"$(quillui_resolve_enchanted_source_dir \"$ROOT_DIR\")\""))
        #expect(generatedEnchantedSource.contains("LOWERED_SOURCE_CACHE_DIR=\"${QUILLUI_PROFILE_LOWERED_SOURCE_CACHE_DIR:-$ROOT_DIR/.build/quillui-lowered-source-cache}\""))
        #expect(generatedEnchantedSource.contains("REUSE_LOWERED_SOURCE=\"${QUILLUI_PROFILE_REUSE_LOWERED_SOURCE:-1}\""))
        #expect(generatedEnchantedSource.contains("quillui_profile_prepare_lowered_source"))
        #expect(generatedEnchantedSource.contains("SOURCE_COPY=\"$QUILLUI_PROFILE_SOURCE_COPY\""))
        #expect(generatedEnchantedSource.contains("LOWERED_COPY=\"$QUILLUI_PROFILE_LOWERED_COPY\""))
        #expect(generatedEnchantedSource.contains("rm -rf \"$PACKAGE_DIR\""))
        #expect(!generatedEnchantedSource.contains("rm -rf \"$WORK_ROOT\""))
        #expect(!generatedEnchantedSource.contains("cp -R \"$UPSTREAM_DIR\"/. \"$SOURCE_COPY\"/"))
        #expect(generatedEnchantedSource.contains("include_backend_entry=0"))
        #expect(generatedEnchantedSource.contains("QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY=\"$include_backend_entry\""))
        #expect(!generatedEnchantedSource.contains("include_gtk_backend"))
        #expect(!generatedEnchantedSource.contains("QUILLUI_GENERATED_INCLUDE_GTK_BACKEND"))
        #expect(!source.contains("package(url: \"https://github.com/codelynx/SwiftOpenUI\""))
        #expect(!source.contains(".product(name: \"BackendGTK4\", package: \"SwiftOpenUI\")"))
    }

    @Test("Telegram upstream source tooling is tracked")
    func telegramUpstreamSourceToolingIsTracked() throws {
        let root = try packageRoot()
        let fetchUpstream = try String(
            contentsOf: root.appendingPathComponent("scripts/fetch-upstream.sh"),
            encoding: .utf8
        )
        let telegramSourceResolver = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-telegram-source.sh"),
            encoding: .utf8
        )
        let telegramPackageCheck = try String(
            contentsOf: root.appendingPathComponent("scripts/generated-telegram-package-check.sh"),
            encoding: .utf8
        )
        let telegramManifestPatcher = try String(
            contentsOf: root.appendingPathComponent("scripts/patch-telegram-package-manifest.py"),
            encoding: .utf8
        )
        let telegramSourceLowerer = try String(
            contentsOf: root.appendingPathComponent("scripts/lower-telegram-linux-source.py"),
            encoding: .utf8
        )
        let telegramAudit = try String(
            contentsOf: root.appendingPathComponent("docs/upstream-telegram-audit.md"),
            encoding: .utf8
        )
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let objcFoundationHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/Foundation/Foundation.h"),
            encoding: .utf8
        )
        let objcCoreFoundationHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/CoreFoundation/CoreFoundation.h"),
            encoding: .utf8
        )
        let objcAppKitHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/AppKit/AppKit.h"),
            encoding: .utf8
        )
        let objcCoreGraphicsHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/CoreGraphics/CoreGraphics.h"),
            encoding: .utf8
        )
        let objcPreludeHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/QuillObjCCompatibility/Prelude.h"),
            encoding: .utf8
        )
        let quillFoundationLinuxClone = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillFoundation/FoundationLinuxClone.swift"),
            encoding: .utf8
        )
        let machHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/mach/mach.h"),
            encoding: .utf8
        )
        let accelerateHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/Accelerate/Accelerate.h"),
            encoding: .utf8
        )
        let audioToolboxHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/AudioToolbox/AudioToolbox.h"),
            encoding: .utf8
        )
        let carbonHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/Carbon/Carbon.h"),
            encoding: .utf8
        )
        let avFoundationHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/AVFoundation/AVFoundation.h"),
            encoding: .utf8
        )
        let ioHIDHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/IOKit/hidsystem/IOHIDLib.h"),
            encoding: .utf8
        )
        let securityHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/Security/Security.h"),
            encoding: .utf8
        )
        let commonCryptoHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/CommonCrypto/CommonCrypto.h"),
            encoding: .utf8
        )
        let coreTextHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/CoreText/CoreText.h"),
            encoding: .utf8
        )
        let quartzCoreHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/QuartzCore/QuartzCore.h"),
            encoding: .utf8
        )
        let objcModuleMap = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/module.modulemap"),
            encoding: .utf8
        )
        let objcRuntimeHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/objc/runtime.h"),
            encoding: .utf8
        )
        let apiCredentialsOverlay = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillTelegramBuildOverlays/ApiCredentials/Sources/ApiCredentials/QuillSecurityOverlay.swift"),
            encoding: .utf8
        )
        let stringsOverlay = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillTelegramBuildOverlays/Strings/Sources/Strings/QuillStringsLinuxOverlay.swift"),
            encoding: .utf8
        )
        let telegramSystemOverlay = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillTelegramBuildOverlays/TelegramSystem/Sources/TelegramSystem/QuillDarwinSysctlOverlay.swift"),
            encoding: .utf8
        )
        let objcUtilsOverlayPackage = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillTelegramBuildOverlays/ObjcUtils/Package.swift"),
            encoding: .utf8
        )
        let objcUtilsSwiftOverlay = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillTelegramBuildOverlays/ObjcUtils/Sources/ObjcUtilsSwift/ObjcUtils.swift"),
            encoding: .utf8
        )
        let coreVideoShim = try String(
            contentsOf: root.appendingPathComponent("Sources/AppleFrameworkShims/CoreVideo/CoreVideo.swift"),
            encoding: .utf8
        )
        let coreTextSwiftShim = try String(
            contentsOf: root.appendingPathComponent("Sources/AppleFrameworkShims/CoreText/CoreText.swift"),
            encoding: .utf8
        )
        let extensionFoundationShim = try String(
            contentsOf: root.appendingPathComponent("Sources/AppleFrameworkShims/ExtensionFoundation/ExtensionFoundation.swift"),
            encoding: .utf8
        )
        let extensionKitShim = try String(
            contentsOf: root.appendingPathComponent("Sources/AppleFrameworkShims/ExtensionKit/ExtensionKit.swift"),
            encoding: .utf8
        )
        let objcJavaScriptCoreHeader = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillObjCCompatibility/include/JavaScriptCore/JavaScriptCore.h"),
            encoding: .utf8
        )

        #expect(manifest.contains(".library(name: \"QuillObjCCompatibility\", targets: [\"QuillObjCCompatibility\"])"))
        #expect(manifest.contains(".library(name: \"COSUnfairLock\", targets: [\"COSUnfairLock\"])"))
        #expect(manifest.contains(".library(name: \"NaturalLanguage\", targets: [\"NaturalLanguage\"])"))
        #expect(manifest.contains(".library(name: \"ImageIO\", targets: [\"ImageIO\"])"))
        #expect(manifest.contains(".library(name: \"Accelerate\", targets: [\"Accelerate\"])"))
        #expect(manifest.contains(".library(name: \"CoreLocation\", targets: [\"CoreLocation\"])"))
        #expect(manifest.contains(".library(name: \"CoreVideo\", targets: [\"CoreVideo\"])"))
        #expect(manifest.contains(".library(name: \"Vision\", targets: [\"Vision\"])"))
        #expect(manifest.contains(".library(name: \"StoreKit\", targets: [\"StoreKit\"])"))
        #expect(manifest.contains(".library(name: \"ExtensionFoundation\", targets: [\"ExtensionFoundation\"])"))
        #expect(manifest.contains(".library(name: \"ExtensionKit\", targets: [\"ExtensionKit\"])"))
        #expect(manifest.contains("\"ExtensionFoundation\", \"ExtensionKit\""))
        #expect(extensionKitShim.contains("import AppKit"))
        #expect(extensionKitShim.contains("extension Array: AppExtensionScene where Element: AppExtensionScene"))
        #expect(extensionKitShim.contains("onConnection: (NSXPCConnection) -> Bool"))
        #expect(extensionFoundationShim.contains("public protocol AppExtensionConfiguration"))
        #expect(manifest.contains("\"AVFAudio\", \"CoreVideo\""))
        #expect(manifest.contains("name: \"QuillObjCCompatibility\""))
        #expect(fetchUpstream.contains("telegram)"))
        #expect(fetchUpstream.contains("fetch_repo telegram-swift https://github.com/overtake/TelegramSwift.git master"))
        #expect(telegramSourceResolver.contains("quillui_resolve_telegram_source_dir()"))
        #expect(telegramSourceResolver.contains("QUILLUI_APP_SOURCE_DIR"))
        #expect(telegramSourceResolver.contains("TELEGRAM_SWIFT_SOURCE_DIR"))
        #expect(telegramSourceResolver.contains("TELEGRAM_SOURCE_DIR"))
        #expect(telegramSourceResolver.contains(".upstream/telegram-swift"))
        #expect(telegramPackageCheck.contains("source \"$ROOT_DIR/scripts/quillui-telegram-source.sh\""))
        #expect(telegramPackageCheck.contains("UPSTREAM_DIR=\"$(quillui_resolve_telegram_source_dir \"$ROOT_DIR\")\""))
        #expect(telegramPackageCheck.contains("QUILLUI_TELEGRAM_PACKAGE_CHECK_PACKAGES"))
        #expect(telegramPackageCheck.contains("--jobs 1"))
        #expect(telegramPackageCheck.contains("--skip-update"))
        #expect(telegramPackageCheck.contains("ApiCredentials"))
        #expect(telegramPackageCheck.contains("CAPortal"))
        #expect(telegramPackageCheck.contains("CallVideoLayer"))
        #expect(telegramPackageCheck.contains("ColorPalette"))
        #expect(telegramPackageCheck.contains("Colors"))
        #expect(telegramPackageCheck.contains("CalendarUtils"))
        #expect(telegramPackageCheck.contains("CrashHandler"))
        #expect(telegramPackageCheck.contains("CurrencyFormat"))
        #expect(telegramPackageCheck.contains("DateUtils"))
        #expect(telegramPackageCheck.contains("DetectSpeech"))
        #expect(telegramPackageCheck.contains("Dock"))
        #expect(telegramPackageCheck.contains("DustLayer"))
        #expect(telegramPackageCheck.contains("EDSunriseSet"))
        #expect(telegramPackageCheck.contains("EmojiSuggestions"))
        #expect(telegramPackageCheck.contains("FastBlur"))
        #expect(telegramPackageCheck.contains("FetchManager"))
        #expect(telegramPackageCheck.contains("FoundationUtils"))
        #expect(telegramPackageCheck.contains("GZIP"))
        #expect(telegramPackageCheck.contains("GraphUI"))
        #expect(telegramPackageCheck.contains("HackUtils"))
        #expect(telegramPackageCheck.contains("HotKey"))
        #expect(telegramPackageCheck.contains("InAppPurchaseManager"))
        #expect(telegramPackageCheck.contains("InAppSettings"))
        #expect(telegramPackageCheck.contains("InAppVideoServices"))
        #expect(telegramPackageCheck.contains("InputView"))
        #expect(telegramPackageCheck.contains("KeyboardKey"))
        #expect(telegramPackageCheck.contains("Localization"))
        #expect(telegramPackageCheck.contains("MergeLists"))
        #expect(telegramPackageCheck.contains("NumberPluralization"))
        #expect(telegramPackageCheck.contains("OCR"))
        #expect(telegramPackageCheck.contains("ObjcUtils"))
        #expect(telegramPackageCheck.contains("PrivateCallScreen"))
        #expect(telegramPackageCheck.contains("Reactions"))
        #expect(telegramPackageCheck.contains("RingBuffer"))
        #expect(telegramPackageCheck.contains("Spotlight"))
        #expect(telegramPackageCheck.contains("Strings"))
        #expect(telegramPackageCheck.contains("Svg"))
        #expect(telegramPackageCheck.contains("TGCurrencyFormatter"))
        #expect(telegramPackageCheck.contains("TGGifConverter"))
        #expect(telegramPackageCheck.contains("TGModernGrowingTextView"))
        #expect(telegramPackageCheck.contains("TGPassportMRZ"))
        #expect(telegramPackageCheck.contains("TGUIKit"))
        #expect(telegramPackageCheck.contains("TGVideoCameraMovie"))
        #expect(telegramPackageCheck.contains("TelegramMedia"))
        #expect(telegramPackageCheck.contains("TelegramIconsTheme"))
        #expect(telegramPackageCheck.contains("TelegramSystem"))
        #expect(telegramPackageCheck.contains("TextRecognizing"))
        #expect(telegramPackageCheck.contains("ThemeSettings"))
        #expect(telegramPackageCheck.contains("Translate"))
        // telegram-ios submodule packages promoted into the default compile
        // set once the mirror + ObjC compatibility surface covered them.
        #expect(telegramPackageCheck.contains("MediaPlayer"))
        #expect(telegramPackageCheck.contains("TelegramAudio"))
        #expect(telegramPackageCheck.contains("YuvConversion"))
        #expect(telegramPackageCheck.contains("libphonenumber"))
        #expect(telegramPackageCheck.contains("QuillObjCCompatibility/include"))
        #expect(telegramPackageCheck.contains("QuillObjCCompatibility/Prelude.h"))
        #expect(telegramPackageCheck.contains("overlay_root=\"$ROOT_DIR/Sources/QuillTelegramBuildOverlays\""))
        #expect(telegramPackageCheck.contains("package_mirror_root=\"$WORK_ROOT/overlaid-packages\""))
        #expect(telegramPackageCheck.contains("submodule_mirror_root=\"$WORK_ROOT/submodules\""))
        #expect(telegramPackageCheck.contains("CACHE_HOME=\"${QUILLUI_GENERATED_TELEGRAM_PACKAGE_HOME"))
        #expect(telegramPackageCheck.contains("HOME=\"$CACHE_HOME\""))
        #expect(telegramPackageCheck.contains("find \"$UPSTREAM_DIR/packages\""))
        #expect(telegramPackageCheck.contains("lower-telegram-linux-source.py"))
        #expect(telegramPackageCheck.contains("patch-telegram-package-manifest.py"))
        #expect(telegramPackageCheck.contains("materialize_telegram_shared_headers \"$submodule_name\" \"$mirrored_submodule\"\n        python3 \"$ROOT_DIR/scripts/patch-telegram-package-manifest.py\" \"$mirrored_submodule\" \"$ROOT_DIR\""))
        #expect(telegramPackageCheck.contains("find \"$submodule_mirror_root\" -type f -name Package.swift -print | sort"))
        #expect(telegramPackageCheck.contains("cp -R \"$overlay_dir\"/. \"$mirror_package_dir\""))
        #expect(telegramPackageCheck.contains("cp -R \"$UPSTREAM_DIR/submodules/telegram-ios/submodules\" \"$submodule_mirror_root/telegram-ios/submodules\""))
        #expect(telegramPackageCheck.contains("ln -s \"$submodule_mirror_root\" \"$package_mirror_root/submodules\""))
        #expect(telegramPackageCheck.contains("-fobjc-runtime=gnustep-2.0"))
        #expect(telegramPackageCheck.contains("-fblocks"))
        #expect(telegramPackageCheck.contains("-fobjc-arc"))
        #expect(telegramPackageCheck.contains("deeper Foundation/AppKit runtime surface"))
        #expect(telegramPackageCheck.contains("Generic build overlays applied"))
        #expect(telegramAudit.contains("Telegram Swift is not a SwiftUI app"))
        #expect(telegramAudit.contains("scripts/fetch-upstream.sh telegram"))
        #expect(telegramAudit.contains("QuillObjCCompatibility"))
        #expect(telegramAudit.contains("QuillAppKit/QuillKit shims"))
        #expect(telegramAudit.contains("Sources/QuillTelegramBuildOverlays"))
        #expect(telegramAudit.contains("mirrored package tree"))
        #expect(telegramAudit.contains("local QuillUI Apple-module products"))
        #expect(telegramAudit.contains("transitive `Colors` package"))
        #expect(telegramManifestPatcher.contains("IMPORT_TO_PRODUCT"))
        #expect(telegramManifestPatcher.contains("search_roots = [sources_dir, package_dir] if sources_dir.exists() else [package_dir]"))
        #expect(telegramManifestPatcher.contains("relative_parts = swift_file.relative_to(package_dir).parts"))
        #expect(telegramManifestPatcher.contains("if any(part in {\".build\", \".git\", \".swiftpm\"} for part in relative_parts):"))
        #expect(telegramManifestPatcher.contains("\"AppKit\": \"AppKit\""))
        #expect(telegramManifestPatcher.contains("\"AVFoundation\": \"AVFoundation\""))
        #expect(telegramManifestPatcher.contains("\"Accelerate\": \"Accelerate\""))
        #expect(telegramManifestPatcher.contains("\"Cocoa\": \"Cocoa\""))
        #expect(telegramManifestPatcher.contains("\"CoreLocation\": \"CoreLocation\""))
        #expect(telegramManifestPatcher.contains("\"CoreVideo\": \"CoreVideo\""))
        #expect(telegramManifestPatcher.contains("\"COSUnfairLock\": \"COSUnfairLock\""))
        #expect(telegramManifestPatcher.contains("\"NaturalLanguage\": \"NaturalLanguage\""))
        #expect(telegramManifestPatcher.contains("\"ImageIO\": \"ImageIO\""))
        #expect(telegramManifestPatcher.contains("\"IOKit\": \"IOKit\""))
        #expect(telegramManifestPatcher.contains("\"StoreKit\": \"StoreKit\""))
        #expect(telegramManifestPatcher.contains("\"QuillFoundation\": \"QuillFoundation\""))
        #expect(telegramManifestPatcher.contains(".package(name: \"QuillUI\""))
        #expect(telegramManifestPatcher.contains(".product(name:"))
        #expect(telegramSourceLowerer.contains("THREAD_SELECTOR_RE"))
        #expect(telegramSourceLowerer.contains("insert_import(lowered, \"COSUnfairLock\")"))
        #expect(telegramSourceLowerer.contains("insert_import(lowered, \"QuillFoundation\")"))
        #expect(telegramSourceLowerer.contains("CFAbsoluteTimeGetCurrent"))
        #expect(telegramSourceLowerer.contains("threadPriority"))
        #expect(telegramSourceLowerer.contains("IOKit\\.ps"))
        #expect(telegramSourceLowerer.contains("os_unfair_lock"))
        #expect(telegramSourceLowerer.contains("__nonnull"))
        #expect(telegramSourceLowerer.contains("getxattr"))
        #expect(telegramSourceLowerer.contains("setxattr"))
        #expect(telegramSourceLowerer.contains("@objc"))
        #expect(telegramSourceLowerer.contains("#selector"))
        #expect(telegramSourceLowerer.contains("autoreleasepool"))
        #expect(quillFoundationLinuxClone.contains("typealias CFAbsoluteTime = Double"))
        #expect(quillFoundationLinuxClone.contains("func CFAbsoluteTimeGetCurrent()"))
        #expect(quillFoundationLinuxClone.contains("var threadPriority: Double"))
        #expect(quillFoundationLinuxClone.contains("static let quillByCaretPositionsRawValue"))
        #expect(quillFoundationLinuxClone.contains("static let byCaretPositions = NSString.quillByCaretPositionsOption"))
        #expect(quillFoundationLinuxClone.contains("public let KERN_SUCCESS: kern_return_t = 0"))
        #expect(quillFoundationLinuxClone.contains("func mach_timebase_info() -> mach_timebase_info_data_t"))
        #expect(quillFoundationLinuxClone.contains("func mach_absolute_time() -> UInt64"))
        #expect(quillFoundationLinuxClone.contains("class func unarchivedArrayOfObjects<DecodedObjectType>"))
        #expect(quillFoundationLinuxClone.contains("class func unarchivedDictionary<DecodedKeyType, DecodedObjectType>"))
        #expect(objcFoundationHeader.contains("@interface NSString : NSObject"))
        #expect(objcFoundationHeader.contains("@interface NSDateComponents : NSObject"))
        #expect(objcFoundationHeader.contains("@interface NSCalendar : NSObject"))
        #expect(objcFoundationHeader.contains("@interface NSCharacterSet : NSObject"))
        #expect(objcFoundationHeader.contains("@protocol NSXMLParserDelegate"))
        #expect(objcFoundationHeader.contains("@property (nonatomic, readonly) NSUInteger numberOfRanges;"))
        #expect(objcFoundationHeader.contains("#define DEPRECATED_MSG_ATTRIBUTE(msg) __attribute__((deprecated(msg)))"))
        #expect(objcFoundationHeader.contains("@interface NSOperation : NSObject"))
        #expect(objcFoundationHeader.contains("NSURLRequestUseProtocolCachePolicy = 0"))
        #expect(objcFoundationHeader.contains("+ (instancetype)ephemeralSessionConfiguration;"))
        #expect(objcFoundationHeader.contains("static NSString * const NSUnderlyingErrorKey"))
        #expect(objcFoundationHeader.contains("@property (nonatomic, readonly) NSString *debugDescription;"))
        #expect(objcFoundationHeader.contains("+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key;"))
        #expect(objcFoundationHeader.contains("- (NSString *)displayNameForKey:(id)key value:(id)value;"))
        #expect(objcFoundationHeader.contains("#define NSEC_PER_MSEC 1000000ull"))
        #expect(objcFoundationHeader.contains("@interface NSURLComponents : NSObject"))
        #expect(objcFoundationHeader.contains("+ (instancetype)URLQueryAllowedCharacterSet;"))
        #expect(objcFoundationHeader.contains("stringByAddingPercentEncodingWithAllowedCharacters"))
        #expect(objcFoundationHeader.contains("+ (instancetype)predicateWithBlock:"))
        #expect(objcFoundationHeader.contains("replaceMatchesInString:(NSMutableString *)string"))
        #expect(objcFoundationHeader.contains("@interface NSDateComponentsFormatter : NSObject"))
        #expect(objcFoundationHeader.contains("static NSString * const NSURLErrorKey"))
        #expect(objcFoundationHeader.contains("NSRegularExpressionDotMatchesLineSeparators"))
        #expect(objcFoundationHeader.contains("+ (instancetype)whitespaceAndNewlineCharacterSet;"))
        #expect(objcFoundationHeader.contains("+ (instancetype)decimalDigitCharacterSet;"))
        #expect(objcFoundationHeader.contains("- (BOOL)isSupersetOfSet:(NSCharacterSet *)other;"))
        #expect(objcFoundationHeader.contains("#define __nullable _Nullable"))
        #expect(objcFoundationHeader.contains("@interface NSOperationQueue : NSObject"))
        #expect(objcFoundationHeader.contains("NSQualityOfServiceUtility"))
        #expect(objcFoundationHeader.contains("@property NSQualityOfService qualityOfService;"))
        #expect(objcFoundationHeader.contains("@property (copy) void (^completionBlock)(void);"))
        #expect(objcFoundationHeader.contains("- (NSArray<NSString *> *)preferredLocalizations;"))
        #expect(objcFoundationHeader.contains("+ (NSString *)canonicalLanguageIdentifierFromString:(NSString *)string;"))
        #expect(objcFoundationHeader.contains("static NSString * const NSInvalidArgumentException"))
        #expect(objcFoundationHeader.contains("@protocol NSURLSessionDataDelegate"))
        #expect(objcFoundationHeader.contains("NSURLSessionResponseAllow = 1"))
        #expect(objcFoundationHeader.contains("+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration"))
        #expect(objcFoundationHeader.contains("- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url;"))
        #expect(objcFoundationHeader.contains("+ (NSString *)localizedStringForStatusCode:(NSInteger)statusCode;"))
        #expect(objcFoundationHeader.contains("static NSString * const NSURLErrorDomain"))
        #expect(objcFoundationHeader.contains("NSURLResponseUnknownLength"))
        #expect(objcFoundationHeader.contains("NSJSONReadingAllowFragments"))
        #expect(objcCoreFoundationHeader.contains("kCFStringEncodingInvalidId"))
        #expect(objcCoreFoundationHeader.contains("CFStringConvertIANACharSetNameToEncoding"))
        #expect(objcModuleMap.contains("module CoreGraphics"))
        #expect(objcCoreGraphicsHeader.contains("CGRectGetMinX"))
        #expect(objcCoreGraphicsHeader.contains("#include <AppKit/AppKit.h>"))
        #expect(objcAppKitHeader.contains("typedef const void CGImage;"))
        #expect(objcAppKitHeader.contains("CGImageCreateWithImageInRect"))
        #expect(objcAppKitHeader.contains("+ (instancetype)valueWithRect:(NSRect)rect;"))
        #expect(objcAppKitHeader.contains("- (CGRect)CGRectValue;"))
        #expect(objcModuleMap.contains("module JavaScriptCore"))
        #expect(objcJavaScriptCoreHeader.contains("@interface JSContext : NSObject"))
        #expect(objcJavaScriptCoreHeader.contains("@interface JSValue : NSObject"))
        #expect(objcJavaScriptCoreHeader.contains("valueWithObject:(id)value inContext:(JSContext *)context"))
        #expect(objcRuntimeHeader.contains("objc_lookUpClass"))
        #expect(objcRuntimeHeader.contains("protocol_getMethodDescription"))
        #expect(objcFoundationHeader.contains("@interface NSDataDetector : NSObject"))
        #expect(objcFoundationHeader.contains("@interface NSRegularExpression : NSObject"))
        #expect(objcFoundationHeader.contains("@interface NSFileManager : NSObject"))
        #expect(objcFoundationHeader.contains("@interface NSMutableAttributedString : NSAttributedString"))
        #expect(objcFoundationHeader.contains("NSHomeDirectory"))
        #expect(objcFoundationHeader.contains("arc4random"))
        #expect(objcFoundationHeader.contains("- (void)getBytes:(void *)buffer range:(NSRange)range"))
        #expect(objcFoundationHeader.contains("- (void)appendBytes:(const void *)bytes length:(NSUInteger)length"))
        #expect(objcFoundationHeader.contains("@protocol NSFastEnumeration"))
        #expect(objcFoundationHeader.contains("typedef uint32_t UInt32"))
        #expect(objcFoundationHeader.contains("clang assume_nonnull begin"))
        #expect(objcFoundationHeader.contains("typedef NS_ENUM(NSInteger, NSDateFormatterStyle)"))
        #expect(objcFoundationHeader.contains("typedef long dispatch_once_t"))
        #expect(objcCoreFoundationHeader.contains("CFStringGetBytes"))
        #expect(objcCoreFoundationHeader.contains("kCFStringEncodingUTF16LE"))
        #expect(objcAppKitHeader.contains("CGSizeMake"))
        #expect(objcAppKitHeader.contains("CGSizeEqualToSize"))
        #expect(objcAppKitHeader.contains("CGContextFillRect"))
        #expect(objcAppKitHeader.contains("@interface NSView : NSObject"))
        #expect(objcAppKitHeader.contains("@interface NSBitmapImageRep : NSObject"))
        #expect(objcAppKitHeader.contains("@interface NSGraphicsContext : NSObject"))
        #expect(objcAppKitHeader.contains("@interface NSOpenPanel : NSObject"))
        #expect(objcAppKitHeader.contains("@interface NSEvent : NSObject"))
        #expect(objcAppKitHeader.contains("CGImageRef"))
        #expect(objcAppKitHeader.contains("CGBitmapContextCreate"))
        #expect(objcAppKitHeader.contains("LSCopyApplicationURLsForURL"))
        #expect(objcAppKitHeader.contains("NSArray<NSView *> *subviews"))
        #expect(objcAppKitHeader.contains("NSString *className"))
        #expect(objcAppKitHeader.contains("NSEventModifierFlagCommand"))
        #expect(objcAppKitHeader.contains("@interface NSWorkspace : NSObject"))
        #expect(objcPreludeHeader.contains("#include <string.h>"))
        #expect(machHeader.contains("vm_allocate"))
        #expect(machHeader.contains("vm_remap"))
        #expect(accelerateHeader.contains("vImage_Buffer"))
        #expect(accelerateHeader.contains("vImageBoxConvolve_ARGB8888"))
        #expect(audioToolboxHeader.contains("AudioComponentDescription"))
        #expect(audioToolboxHeader.contains("AUVoiceIOMutedSpeechActivityEventListener"))
        #expect(carbonHeader.contains("kVK_Return"))
        #expect(carbonHeader.contains("UCKeyTranslate"))
        #expect(avFoundationHeader.contains("@interface AVURLAsset : NSObject"))
        #expect(avFoundationHeader.contains("CMSampleBufferRef"))
        #expect(avFoundationHeader.contains("@interface AVMutableMetadataItem : NSObject"))
        #expect(ioHIDHeader.contains("IOHIDRequestAccess"))
        #expect(ioHIDHeader.contains("IOServiceGetMatchingServices"))
        #expect(securityHeader.contains("import Security"))
        #expect(commonCryptoHeader.contains("import CommonCrypto"))
        #expect(commonCryptoHeader.contains("CC_MD5"))
        #expect(coreTextHeader.contains("CTLineGetGlyphCount"))
        #expect(quartzCoreHeader.contains("QuartzCore"))
        #expect(objcModuleMap.contains("module Foundation"))
        #expect(objcModuleMap.contains("module AppKit"))
        #expect(objcModuleMap.contains("module Cocoa"))
        #expect(objcModuleMap.contains("module Security"))
        #expect(objcModuleMap.contains("module CommonCrypto"))
        #expect(objcModuleMap.contains("module CoreText"))
        #expect(objcModuleMap.contains("module QuartzCore"))
        #expect(!objcModuleMap.contains("module CoreFoundation {"))
        #expect(objcPreludeHeader.contains("#include <string>"))
        #expect(objcPreludeHeader.contains("#include <pthread.h>"))
        #expect(apiCredentialsOverlay.contains("func SecStaticCodeCreateWithPath"))
        #expect(apiCredentialsOverlay.contains("func CC_SHA1"))
        #expect(apiCredentialsOverlay.contains("containerURL(forSecurityApplicationGroupIdentifier"))
        #expect(stringsOverlay.contains("static let byWords"))
        // Strings' CoreText glyph-count path resolves to the shared CoreText
        // shim product (added by the manifest patcher), not the overlay.
        #expect(coreTextSwiftShim.contains("func CTLineCreateWithAttributedString"))
        #expect(coreTextSwiftShim.contains("func CTLineGetGlyphCount"))
        #expect(coreTextSwiftShim.contains("func CTTypesetterCreateWithAttributedString(_ attributedString: NSAttributedString) -> CTTypesetter"))
        #expect(coreTextSwiftShim.contains("func CTTypesetterSuggestClusterBreak"))
        #expect(coreTextSwiftShim.contains("func CTTypesetterCreateLine(_ typesetter: CTTypesetter"))
        #expect(!coreTextSwiftShim.contains("public func CFRangeMake"))
        #expect(extensionFoundationShim.contains("public protocol AppExtensionConfiguration"))
        #expect(extensionFoundationShim.contains("func accept(connection: NSXPCConnection) -> Bool"))
        #expect(extensionKitShim.contains("public protocol AppExtensionScene"))
        #expect(extensionKitShim.contains("public struct PrimitiveAppExtensionScene"))
        #expect(extensionKitShim.contains("@resultBuilder"))
        #expect(stringsOverlay.contains("quillIsTelegramWordCharacter"))
        #expect(telegramSystemOverlay.contains("func sysctlbyname"))
        #expect(telegramSystemOverlay.contains("oldlenp?.pointee = 0"))
        #expect(objcUtilsOverlayPackage.contains(".library(name: \"ObjcUtils\", targets: [\"ObjcUtils\"])"))
        #expect(objcUtilsOverlayPackage.contains(".library(name: \"ObjcUtilsObjC\", targets: [\"ObjcUtilsObjC\"])"))
        #expect(objcUtilsOverlayPackage.contains("Sources/ObjcUtilsSwift"))
        #expect(objcUtilsOverlayPackage.contains("publicHeadersPath: \"Sources/ObjcUtils\""))
        #expect(objcUtilsSwiftOverlay.contains("public enum ObjcUtils"))
        #expect(objcUtilsSwiftOverlay.contains("windowResizeNorthWestSouthEastCursor"))
        #expect(objcUtilsSwiftOverlay.contains("windowResizeNorthEastSouthWestCursor"))
        #expect(objcUtilsSwiftOverlay.contains("NSCursor.resizeLeftRight"))
        #expect(coreVideoShim.contains("@_exported import QuillFoundation"))
        #expect(coreVideoShim.contains("public typealias CVPixelBuffer"))
        #expect(coreVideoShim.contains("CVDisplayLinkCreateWithCGDisplay"))
        #expect(coreVideoShim.contains("CVPixelBufferCreate"))
        #expect(coreVideoShim.contains("CVPixelBufferLockBaseAddress"))
        #expect(coreVideoShim.contains("kCVPixelBufferIOSurfacePropertiesKey"))
    }

    @Test("Generated resource copier flattens asset catalog images")
    func generatedResourceCopierFlattensAssetCatalogImages() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("QuillGeneratedResources-\(UUID().uuidString)", isDirectory: true)
        let source = temporaryDirectory.appendingPathComponent("Source", isDirectory: true)
        let output = temporaryDirectory.appendingPathComponent("Output", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let imageset = source
            .appendingPathComponent("Assets.xcassets", isDirectory: true)
            .appendingPathComponent("logo-nobg.imageset", isDirectory: true)
        try fileManager.createDirectory(at: imageset, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: source.appendingPathComponent("Shared", isDirectory: true),
            withIntermediateDirectories: true
        )

        try Data("one-x".utf8).write(to: imageset.appendingPathComponent("logo-1x.png"))
        try Data("two-x".utf8).write(to: imageset.appendingPathComponent("logo-2x.png"))
        try """
        {
          "images": [
            { "filename": "logo-1x.png", "idiom": "universal", "scale": "1x" },
            { "filename": "logo-2x.png", "idiom": "universal", "scale": "2x" }
          ],
          "info": { "author": "xcode", "version": 1 }
        }
        """.write(to: imageset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        try Data("{\"ok\":true}".utf8).write(to: source.appendingPathComponent("Shared/info.json"))
        try "struct Ignored {}".write(
            to: source.appendingPathComponent("Ignored.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/copy-swiftui-linux-resources.py").path,
                "--source-dir",
                source.path,
                "--output-dir",
                output.path
            ]
        )

        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("1 plain, 1 asset-catalog images"))
        #expect(try Data(contentsOf: output.appendingPathComponent("logo-nobg.png")) == Data("two-x".utf8))
        #expect(fileManager.fileExists(atPath: output.appendingPathComponent("Shared/info.json").path))
        #expect(!fileManager.fileExists(atPath: output.appendingPathComponent("Ignored.swift").path))
        #expect(!fileManager.fileExists(atPath: output.appendingPathComponent("Assets.xcassets").path))

        let bundle = temporaryDirectory.appendingPathComponent("Bundle", isDirectory: true)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)
        let otherResources = output.appendingPathComponent("Other", isDirectory: true)
        try fileManager.createDirectory(at: otherResources, withIntermediateDirectories: true)
        try Data("duplicate".utf8).write(to: otherResources.appendingPathComponent("info.json"))

        let materializeResult = try runSourceHygieneProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                root.appendingPathComponent("scripts/materialize-swiftui-linux-main-bundle-resources.py").path,
                "--resources-dir",
                output.path,
                "--bundle-dir",
                bundle.path
            ]
        )

        #expect(materializeResult.status == 0, Comment(rawValue: materializeResult.output))
        #expect(materializeResult.output.contains("root aliases"))
        #expect(fileManager.fileExists(atPath: bundle.appendingPathComponent("Shared/info.json").path))
        #expect(fileManager.fileExists(atPath: bundle.appendingPathComponent("Other/info.json").path))
        #expect(fileManager.fileExists(atPath: bundle.appendingPathComponent("logo-nobg.png").path))
        #expect(!fileManager.fileExists(atPath: bundle.appendingPathComponent("info.json").path))
    }

    @Test("QuillPromptGrid uses backend-stable prompt accessories on Linux")
    func quillPromptGridUsesBackendStablePromptAccessoriesOnLinux() throws {
        let controls = try packageSource("Sources/QuillUI/Controls.swift")
        guard let gridStart = controls.range(of: "public struct QuillPromptGrid: View"),
              let nextSection = controls.range(of: "public struct QuillConversationHistoryItem: Identifiable") else {
            Issue.record("Unable to locate QuillPromptGrid source")
            return
        }

        let promptGrid = String(controls[gridStart.lowerBound..<nextSection.lowerBound])
        #expect(controls.contains("public static func selectedPrompts<Item>("))
        #expect(controls.contains("let preferredItems = preferredTitles.compactMap { preferredTitle in"))
        #expect(controls.contains("source.first { title($0) == preferredTitle }"))
        #expect(controls.contains(": Array(source.prefix(max(0, fallbackCount)))"))
        #expect(controls.contains("public static func selectedModelSender<Model, Attachment, TrimmingID>("))
        #expect(controls.contains("guard let selectedModel else { return }"))
        #expect(controls.contains("onSend(prompt, selectedModel, attachment, trimmingID)"))
        #expect(controls.contains("public struct QuillPromptGridLayout: Equatable, Sendable"))
        #expect(controls.contains("public static let compactCards = QuillPromptGridLayout()"))
        #expect(controls.contains("public static let wideDesktopCards = QuillPromptGridLayout("))
        #expect(promptGrid.contains("layout: QuillPromptGridLayout"))
        #expect(promptGrid.contains("self.columns = layout.columns"))
        #expect(promptGrid.contains("self.init(\n            prompts: prompts,\n            layout: QuillPromptGridLayout("))
        #expect(promptGrid.contains("LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing)"))
        #expect(promptGrid.contains("GridItem(.adaptive(minimum: Double(max(80, cardWidth))), spacing: gridSpacing)"))
        #expect(promptGrid.contains("Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columns)"))
        #expect(promptGrid.contains("ForEach(prompts)"))
        #expect(promptGrid.contains("Image(systemName: QuillSystemSymbol.compatibleName(prompt.systemImage))"))
        #expect(promptGrid.contains("private var promptFontSize: CGFloat {\n        #if os(Linux)\n        cardHeight >= 220 ? 24 : 15"))
        #expect(promptGrid.contains("Color.clear\n                    .frame(height: promptCardContentHeight)"))
        #expect(promptGrid.contains("private var promptCardContentHeight: CGFloat"))
        #expect(promptGrid.contains("max(1, cardHeight - (promptCardPaddingWidth * 2))"))
        #expect(promptGrid.contains("QuillDesktopChromeStyle.promptCardBackground"))
        #expect(promptGrid.contains("QuillPromptLightbulbGlyph(color: Color(hex: \"#2E2E31\"))"))
        #expect(promptGrid.contains("private struct QuillPromptLightbulbGlyph: View"))
        #expect(!promptGrid.contains("Image(systemName: QuillSystemSymbol.compatibleName(\"lightbulb\"))"))
        #expect(!promptGrid.contains("prompt.systemImage.contains(\"lightbulb\") ? \"!\" : \"?\""))
        #expect(!promptGrid.contains("#if os(Linux)\n        ZStack"))
        #expect(!promptGrid.contains("Color(hex: \"#E8E8EE\")"))
    }

    @Test("QuillDesktopSplitLayout mirrors Mac reference titlebar chrome")
    func quillDesktopSplitLayoutMirrorsMacReferenceTitlebarChrome() throws {
        let controls = try packageSource("Sources/QuillUI/Controls.swift")

        #expect(controls.contains("private var sidebarToggleGlyph: some View"))
        #expect(controls.contains(".frame(width: 176, height: 24, alignment: .leading)"))
        #expect(controls.contains("Color.clear\n                .frame(width: 48, height: 1)"))
        #expect(controls.contains(".font(.system(size: 16, weight: .regular))"))
        #expect(controls.contains("public struct QuillDesktopChatScaffold<"))
        #expect(controls.contains("public struct QuillMessageList<"))
        #expect(controls.contains("public struct QuillEditableMessageList<"))
        #expect(controls.contains("@Binding public var editingMessage: Message?"))
        #expect(controls.contains("public var interactionAvailability: QuillMessageInteractionAvailability"))
        #expect(controls.contains("interactionAvailability: QuillMessageInteractionAvailability = .all"))
        #expect(controls.contains("interactionAvailability.contains(.selectText)"))
        #expect(controls.contains("interactionAvailability.contains(.readAloud)"))
        #expect(controls.contains("public struct QuillMessageInteractionAvailability: OptionSet"))
        #expect(controls.contains("public static var platformDefaults: QuillMessageInteractionAvailability"))
        #expect(controls.contains("QuillDesktopMessageHoverActionRow("))
        #expect(controls.contains("struct QuillDesktopMessageHoverActionRow<Content: View>: View"))
        #expect(controls.contains("VStack(alignment: .leading, spacing: 2)"))
        #expect(controls.contains("if isUserMessage {\n                    Spacer()\n                }\n                actionBar"))
        #expect(controls.contains("QuillMessageHoverActionBar(actions: visibleActions)"))
        #expect(controls.contains("Array(actions.filter { $0.kind == .item && !$0.isDisabled }.prefix(4))"))
        #expect(controls.contains("#elseif os(Linux)\n        return [.readAloud]"))

        let messageHoverActions = try packageSource("Sources/QuillUI/GTKMessageHoverActions.swift")
        #expect(messageHoverActions.contains("extension QuillDesktopMessageHoverActionRow: GTKRenderable"))
        #expect(messageHoverActions.contains("gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)"))
        #expect(messageHoverActions.contains("gtk_widget_set_hexpand(container, 1)"))
        #expect(messageHoverActions.contains("gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)"))
        #expect(messageHoverActions.contains("gtk_box_append(UnsafeMutableRawPointer(container).assumingMemoryBound(to: GtkBox.self), contentWidget)"))
        #expect(messageHoverActions.contains("gtk_box_append(UnsafeMutableRawPointer(container).assumingMemoryBound(to: GtkBox.self), actionWidget)"))
        #expect(messageHoverActions.contains("gtk_widget_set_opacity(actionWidget, 0.0001)"))
        #expect(messageHoverActions.contains("private final class QuillGTKMessageHoverActionState"))
        #expect(messageHoverActions.contains("g_object_set_data_full(object, \"quill-message-hover-action-state\", retainedState)"))
        #expect(messageHoverActions.contains("quillGTKInstallMessageHoverActionControllers("))
        #expect(messageHoverActions.contains("g_timeout_add(80, { userData -> gboolean in"))
        #expect(messageHoverActions.contains("gtk_widget_get_first_child(widget)"))
        #expect(messageHoverActions.contains("gtk_widget_get_next_sibling(current)"))
        #expect(controls.contains("public func contextMenuActions(for message: Message) -> [QuillMenuAction]"))
        #expect(controls.contains("messages.quillMessageListScrollToken(content: content)"))
        #expect(controls.contains("actions: contextMenuActions(for:)"))
        #expect(controls.contains("public var scrollToken: AnyHashable"))
        #expect(controls.contains("private static var bottomSentinelID: String"))
        #expect(controls.contains("Text(Self.bottomSentinelID)"))
        #expect(controls.contains(".foregroundColor(.clear)"))
        #expect(controls.contains("ScrollViewReader { scrollViewProxy in"))
        #expect(controls.contains(".id(scrollToken)"))
        #expect(controls.contains("ForEach(actions(message))"))
        #expect(controls.contains("contextMenuItem(for: action)"))
        #expect(controls.contains("QuillUncheckedSendableScrollViewProxy(proxy: scrollViewProxy)"))
        #expect(controls.contains("QuillUncheckedSendableScrollTarget(value: $0)"))
        #expect(controls.contains("deferredProxy.proxy.scrollTo(deferredLastMessage.value, anchor: .bottom)"))
        #expect(controls.contains("private struct QuillUncheckedSendableScrollViewProxy: @unchecked Sendable"))
        #expect(controls.contains("private struct QuillUncheckedSendableScrollTarget<Value>: @unchecked Sendable"))
        #expect(controls.contains("DispatchQueue.main.async"))
        #expect(controls.contains("for delayMilliseconds in [50, 150, 350, 750, 1_500, 3_000, 5_000, 8_000]"))
        #expect(controls.contains("DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMilliseconds))"))
        #expect(controls.contains("func quillMessageListScrollToken(content: (Element) -> String) -> AnyHashable"))
        #expect(controls.contains("let itemIDs = map { String(describing: $0.id) }.joined(separator: \"|\")"))
        #expect(controls.contains("let lastContent = last.map(content) ?? \"\""))
        #expect(controls.contains("public var composerMaxWidth: CGFloat"))
        #expect(controls.contains("public var composerHorizontalPadding: CGFloat"))
        #expect(controls.contains("public var composerVerticalPadding: CGFloat"))
        #expect(controls.contains("public var hasSelection: Bool"))
        #expect(controls.contains("public var showsStatus: Bool"))
        #expect(controls.contains("public struct QuillEditableDesktopChatScaffold<"))
        #expect(controls.contains("@State private var draft: String"))
        #expect(controls.contains("@State private var editMessage: EditMessage?"))
        #expect(controls.contains("@FocusState private var isFocusedInput: Bool"))
        #expect(controls.contains("selectedContent: { selectedContent($editMessage) }"))
        #expect(controls.contains("composer: { composerContent($draft, $editMessage) }"))
        #expect(controls.contains(".quillSyncEditableMessage($editMessage, draft: $draft, isFocused: $isFocusedInput, content: editContent)"))
        #expect(controls.contains("public struct QuillModelConversationChatScaffold<"))
        #expect(controls.contains("ModelID: Hashable"))
        #expect(controls.contains("public var selectedConversationID: String?"))
        #expect(controls.contains("public var statusMaxWidth: CGFloat"))
        #expect(controls.contains("hasSelection: hasSelection"))
        #expect(controls.contains("showsStatus: showsStatus"))
        #expect(controls.contains("modelActions: modelActions"))
        #expect(controls.contains("optionsActions: optionsActions"))
        #expect(controls.contains("QuillDesktopChatConversationSidebar(\n                conversations: conversations"))
        #expect(controls.contains("QuillSelectedPromptEmptyState(\n                brandTitle: brandTitle"))
        #expect(controls.contains("QuillChatUnreachableBanner(settings: settingsContent)"))
        #expect(controls.contains("public var modelActions: [QuillMenuAction]"))
        #expect(controls.contains("public var optionsActions: [QuillMenuAction]"))
        #expect(controls.contains("if hasSelection {\n                    selectedContent"))
        #expect(controls.contains("if showsStatus {\n                    statusContent"))
        #expect(controls.contains(".padding(.horizontal, composerHorizontalPadding)"))
        #expect(controls.contains(".padding(.vertical, composerVerticalPadding)"))
        #expect(controls.contains("composerContent\n                    .frame(maxWidth: .infinity)"))
        #expect(controls.contains(".frame(maxWidth: composerMaxWidth)"))
        #expect(controls.contains("public extension QuillDesktopChatScaffold where ToolbarContent == QuillDesktopChatToolbar"))
        #expect(controls.contains("modelActions: [QuillMenuAction]"))
        #expect(controls.contains("optionsActions: [QuillMenuAction]"))
        #expect(controls.contains("onNewConversation: @escaping () -> Void"))
        #expect(controls.contains("public struct QuillDesktopChatToolbar: View"))
        #expect(controls.contains("public var modelActions: [QuillMenuAction]"))
        #expect(controls.contains("public var optionsActions: [QuillMenuAction]"))
        #expect(controls.contains("QuillToolbarIconButton(systemImage: \"square.and.pencil\", action: onNewConversation)"))
        #expect(controls.contains("import QuillKit"))
        #expect(controls.contains("public static func copyText("))
        #expect(controls.contains("clipboard: QuillClipboard = .shared"))
        #expect(controls.contains("clipboard.setString(text)"))
        #expect(controls.contains("public static func edit("))
        #expect(controls.contains("public static func unselect("))
        #expect(controls.contains("public static func chatMessageActions("))
        #expect(controls.contains("var actions = [QuillMenuAction.copyText(content, clipboard: clipboard)]"))
        #expect(controls.contains("if let selectText {"))
        #expect(controls.contains("selection.pin.in.out"))
        #expect(controls.contains("if let readAloud {"))
        #expect(controls.contains("speaker.wave.3.fill"))
        #expect(controls.contains("actions.append(contentsOf: additionalActions)"))
        #expect(controls.contains("if isUserMessage {"))
        #expect(controls.contains("if isEditing {"))
        #expect(controls.contains("public static func copyChatActions(copy: @escaping (_ json: Bool) -> Void) -> [QuillMenuAction]"))
        #expect(controls.contains("public enum QuillChatCopy"))
        #expect(controls.contains("public static func rememberedVisibleMessageAction<Message>("))
        #expect(controls.contains("rememberVisibleMessages(key: key, messages, role: role, content: content)"))
        #expect(controls.contains("installRememberedCommandBridge(key: key, clipboard: clipboard)"))
        #expect(controls.contains("return { json in\n            rememberVisibleMessages(key: key, messages, role: role, content: content)"))
        #expect(controls.contains("guard !messages.isEmpty else {\n            return\n        }"))
        #expect(controls.contains("copyRememberedVisibleMessages(key: key, asJSON: json, fallback: fallback, clipboard: clipboard)"))
        #expect(controls.contains("copyRememberedVisibleMessagesIfAvailable("))
        #expect(controls.contains("ensureLinuxFileBackedClipboardContains("))
        #expect(controls.contains("appendingPathComponent(\"quill-pasteboard\")"))
        #expect(controls.contains("return copyRememberedVisibleMessagesIfAvailable(key: key, asJSON: false, clipboard: clipboard)"))
        #expect(controls.contains("return copyRememberedVisibleMessagesIfAvailable(key: key, asJSON: true, clipboard: clipboard)"))
        #expect(controls.contains("copyReferenceTranscriptIfRequested(asJSON: false, clipboard: clipboard, environment: environment)"))
        #expect(controls.contains("copyReferenceTranscriptIfRequested(asJSON: true, clipboard: clipboard, environment: environment)"))
        #expect(controls.contains("referenceTranscriptFallbackIsEnabled(environment: environment)"))
        #expect(controls.contains("return ensureLinuxFileBackedClipboardContains(referenceTranscriptPayload.plainText)"))
        #expect(controls.contains("return ensureLinuxFileBackedClipboardContains(text)"))
        #expect(controls.contains("\"QUILLUI_BACKEND_MAC_REFERENCE\", \"QUILLUI_QUILL_CHAT_REFERENCE_MODE\""))
        #expect(controls.contains("private static let referenceTranscriptPayload = RememberedPayload("))
        #expect(controls.contains("static func isRememberedCommandTitle(_ title: String) -> Bool"))
        #expect(!controls.contains("rememberedPayloads.removeValue(forKey: key)"))
        #expect(controls.contains("public struct QuillChatCopyRememberingView<Message, Content: View>: View"))
        #expect(controls.contains("func quillRememberVisibleMessages<Message>("))
        #expect(controls.contains("QuillChatCopy.rememberVisibleMessages(key: key, messages, role: role, content: messageContent)"))
        #expect(controls.contains("QuillChatCopy.installRememberedCommandBridge(key: key)"))
        #expect(controls.contains("public static func copyVisibleMessages<Message>("))
        #expect(controls.contains("static func installRememberedCommandBridge("))
        #expect(controls.contains("static func performRememberedCommand("))
        #expect(controls.contains("func perform(_ title: String) -> Bool"))
        #expect(controls.contains("return QuillChatCopy.performRememberedCommand(title, key: key, clipboard: snapshot.clipboard)"))
        #expect(controls.contains("case \"Copy Chat\":"))
        #expect(controls.contains("case \"Copy Chat as JSON\":"))
        #expect(controls.contains("private final class RememberedCommandBridge: @unchecked Sendable"))
        #expect(controls.contains("QUILLUI_GTK_TOOLBAR_ACTION_COMMAND_DIR"))
        #expect(controls.contains("private var isPolling = false"))
        #expect(controls.contains("Thread.detachNewThread { [weak self] in"))
        #expect(controls.contains("Thread.sleep(forTimeInterval: 0.1)"))
        #expect(controls.contains("fallback?(json)"))
        #expect(controls.contains("messages.map { \"\\(role($0).capitalized): \\(content($0))\" }.joined(separator: \"\\n\\n\")"))
        #expect(controls.contains("encoder.outputFormatting = [.withoutEscapingSlashes]"))
        #expect(controls.contains("private final class RememberedPayloadStore: @unchecked Sendable"))
        #expect(controls.contains("public static func selectableModels<Item, SelectionID: Hashable>"))
        #expect(controls.contains("return version.isEmpty ? name(model) : \"\\(name(model)) \\(version)\""))
        #expect(controls.contains("layout: QuillPromptGridLayout"))
        #expect(controls.contains("self.init(\n            brandTitle: brandTitle,\n            prompts: prompts,\n            layout: QuillPromptGridLayout("))
        #expect(controls.contains("public static let quillChatMacReferencePromptTitles = ["))
        #expect(controls.contains("public struct QuillSelectedPromptEmptyState<Item>: View"))
        #expect(controls.contains("preferredTitles: [String] = QuillPrompt.quillChatMacReferencePromptTitles"))
        #expect(controls.contains("QuillChatEmptyState(\n            brandTitle: brandTitle"))
        #expect(controls.contains("linuxCompactEmptyStateContent"))
        #expect(controls.contains(".padding(.top, linuxCompactTopPadding(totalHeight: Double(geometry.size.height)))"))
        #expect(controls.contains("private var linuxCompactEmptyStateVerticalSpacing: Int { 48 }"))
        #expect(controls.contains("Int(min(150, max(96, totalHeight * 0.18)).rounded())"))
        #expect(controls.contains("public static func selectedModelSender<Model, Attachment, TrimmingID>("))
        #expect(controls.contains("public static func selectableItems<Item, SelectionID: Hashable>"))
        #expect(controls.contains("return emptyTitle.map { [QuillMenuAction.disabled(title: $0)] } ?? []"))
        #expect(controls.contains("systemImage: selectedID == itemID ? selectedSystemImage : nil"))
        #expect(controls.contains("public static func desktopChatUtilityToggles("))
        #expect(controls.contains("showCompletions.wrappedValue = true"))
        #expect(controls.contains("showShortcuts.wrappedValue = true"))
        #expect(controls.contains("showSettings.wrappedValue = true"))
        #expect(controls.contains("showCompletions.wrappedValue = false"))
        #expect(controls.contains("showShortcuts.wrappedValue = false"))
        #expect(controls.contains("showSettings.wrappedValue = false"))
        #expect(controls.contains("enum QuillDesktopChatInitialUtilitySheet"))
        #expect(controls.contains("static let showCompletionsEnvironmentKeys = ["))
        #expect(controls.contains("\"QUILLUI_CHAT_SHOW_COMPLETIONS_ON_START\""))
        #expect(controls.contains("\"QUILLUI_QUILL_CHAT_SHOW_COMPLETIONS_ON_START\""))
        #expect(controls.contains("\"QUILLUI_ENCHANTED_SHOW_COMPLETIONS_ON_START\""))
        #expect(controls.contains("\"QUILLUI_GTK_ENCHANTED_SHOW_COMPLETIONS_ON_START\""))
        #expect(controls.contains("static func showCompletions(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool"))
        #expect(controls.contains("trimmingCharacters(in: .whitespacesAndNewlines).lowercased()"))
        #expect(controls.contains("return [\"1\", \"true\", \"yes\", \"on\"].contains(rawValue)"))
        #expect(controls.contains("func quillDesktopChatUtilitySheets<"))
        #expect(controls.contains("settingsFocusedValue: WritableKeyPath<FocusedValues, Binding<Bool>?>? = nil"))
        #expect(controls.contains(".focusedSceneValue(settingsFocusedValue, showSettings)"))
        #expect(controls.contains(".sheet(isPresented: showCompletions)"))
        #expect(controls.contains(".sheet(isPresented: showShortcuts)"))
        #expect(controls.contains("#if os(macOS) || os(iOS) || os(visionOS)\n    func quillSyncEditableMessage<Message: Equatable>("))
        #expect(controls.contains("func quillSyncEditableMessage<Message: Equatable>("))
        #expect(controls.contains("isFocused: FocusState<Bool>.Binding"))
        #expect(controls.contains("isFocused: FocusState<Bool>"))
        #expect(controls.contains("private func quillSyncEditableMessageBody<Message: Equatable>("))
        #expect(controls.contains("onChange(of: editMessage.wrappedValue, initial: false)"))
        #expect(controls.contains("draft.wrappedValue = content(newMessage)"))
        #expect(controls.contains("setFocused()"))
        #expect(controls.contains(".background(QuillDesktopChromeStyle.sidebarBackground)"))
        #expect(controls.contains(".background(QuillDesktopChromeStyle.detailBackground)"))
        #expect(controls.contains("public static var promptCardBackground: Color"))
        #expect(controls.contains("ForEach(Array(brandTitle.enumerated()), id: \\.offset)"))
        #expect(controls.contains(".foregroundColor(linuxWordmarkColor(at: index))"))
        #expect(controls.contains("private func linuxWordmarkColor(at index: Int) -> Color"))
        #expect(controls.contains("Color(hex: \"#657BE8\")"))
        #expect(controls.contains("Color(hex: \"#D96570\")"))
        #expect(!controls.contains(".background(Color(hex: \"#F5F5F7\"))"))
        #expect(!controls.contains(".foregroundColor(Color(hex: \"#9B72CB\"))"))
        #expect(!controls.contains(".fontWeight(.semibold)\n                            .foregroundColor(Color(hex: \"#444446\"))"))
    }

    @Test("GTK toolbar primitives use custom glyph children instead of text arrows")
    func gtkToolbarPrimitivesUseCustomGlyphChildrenInsteadOfTextArrows() throws {
        let controls = try packageSource("Sources/QuillUI/Controls.swift")
        let toolbar = try packageSource("Sources/QuillUI/GTKToolbarMenuButton.swift")
        let shim = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/CGTK/shim.h")

        #expect(controls.contains("#if os(Linux)\n        QuillGTKToolbarIconButton("))
        #expect(toolbar.contains("struct QuillGTKToolbarIconButton: View, PrimitiveView, GTKRenderable"))
        #expect(toolbar.contains("gtk_swift_menu_button_set_always_show_arrow(button, 0)"))
        #expect(toolbar.contains("gtk_swift_menu_button_set_child(button, makeToolbarGlyphChild("))
        #expect(toolbar.contains("gtk_swift_widget_insert_action_group(button, \"menu\", gpointer(actionGroup))"))
        #expect(toolbar.contains("gtk_swift_widget_insert_action_group(popover, \"menu\", gpointer(actionGroup))"))
        #expect(toolbar.contains("QUILLUI_GTK_TOOLBAR_ACTION_COMMAND_DIR"))
        #expect(toolbar.contains("actionsByTitle[action.title] = box"))
        #expect(toolbar.contains("g_timeout_add(100, { userData -> gboolean in"))
        #expect(toolbar.contains("String(contentsOf: commandURL, encoding: .utf8)"))
        #expect(toolbar.contains("if QuillChatCopy.performRememberedCommand(title)"))
        #expect(toolbar.contains("if QuillChatCopy.isRememberedCommandTitle(title),"))
        #expect(toolbar.contains("shouldDeferRememberedCommand(commandURL)"))
        #expect(toolbar.contains(".contentModificationDateKey"))
        #expect(toolbar.contains("gtk_box_append(toolbarBoxPointer(box), makeToolbarGlyphLabel(glyph))"))
        #expect(toolbar.contains("private func toolbarBoxPointer"))
        #expect(!toolbar.contains("boxPointer(box)"))
        #expect(toolbar.contains("materialName: \"more_horiz\""))
        #expect(toolbar.contains("materialName: \"expand_more\""))
        #expect(toolbar.contains("materialName: \"edit_square\""))
        #expect(toolbar.contains("materialName: \"library_books\""))
        #expect(toolbar.contains("materialName: \"auto_awesome\""))
        #expect(toolbar.contains("materialName: \"filter_list\""))
        #expect(!toolbar.contains("private var menuTitle"))
        #expect(!toolbar.contains("\"\u{2022}\u{2022}\u{2022}"))
        #expect(!toolbar.contains("\"\u{2304}\""))
        #expect(shim.contains("gtk_swift_menu_button_set_child(GtkWidget *button, GtkWidget *child)"))
        #expect(shim.contains("gtk_swift_menu_button_set_always_show_arrow(GtkWidget *button"))
    }

    @Test("QuillConversationHistoryList mirrors Enchanted row preview and accessibility")
    func quillConversationHistoryListMirrorsEnchantedRowPreviewAndAccessibility() throws {
        let controls = try packageSource("Sources/QuillUI/Controls.swift")
        guard let historyStart = controls.range(of: "public struct QuillConversationHistoryItem: Identifiable"),
              let nextSection = controls.range(of: "public struct QuillSidebarNavigationAction: Identifiable") else {
            Issue.record("Unable to locate QuillConversationHistoryList source")
            return
        }

        let historyList = String(controls[historyStart.lowerBound..<nextSection.lowerBound])
        #expect(historyList.contains("public var lastMessage: String"))
        #expect(historyList.contains("lastMessage: String = \"\""))
        #expect(historyList.contains("public var emptyTitle: String"))
        #expect(historyList.contains("public var emptySubtitle: String"))
        #expect(historyList.contains("emptyTitle: String = \"No saved chats yet\""))
        #expect(historyList.contains("emptySubtitle: String = \"Start a chat and it will be saved locally.\""))
        #expect(historyList.contains("private enum QuillConversationInitialSelection"))
        #expect(historyList.contains("\"QUILLUI_QUILL_HISTORY_SELECTED_INDEX_ON_START\""))
        #expect(historyList.contains("\"QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START\""))
        #expect(historyList.contains("\"QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START\""))
        #expect(historyList.contains("\"QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START\""))
        #expect(historyList.contains("@State private var didApplyInitialSelection = false"))
        #expect(historyList.contains(".onAppear { applyInitialSelectionIfNeeded() }"))
        #expect(historyList.contains(".onChange(of: sortedItems.map(\\.id)) { _, _ in applyInitialSelectionIfNeeded() }"))
        #expect(historyList.contains(".onChange(of: flattenedGroupedItems.map(\\.id)) { _, _ in applyInitialSelectionIfNeeded() }"))
        #expect(historyList.contains("QuillConversationInitialSelection.index(count: sortedItems.count)"))
        #expect(historyList.contains("QuillConversationInitialSelection.index(count: items.count)"))
        #expect(historyList.contains(".accessibilityElement(children: .combine)"))
        #expect(historyList.contains(".accessibilityLabel(item.title)"))
        #expect(historyList.contains(".accessibilityValue(item.lastMessage)"))
        #expect(historyList.contains(".help(accessibilitySummary(for: item))"))
        #expect(historyList.contains("""
                        .help(accessibilitySummary(for: item))
                        #if os(Linux)
                        .onTapGesture { onSelect(item) }
                        #endif
                        .onHover { hovering in
"""))
        #expect(historyList.contains("if sortedItems.isEmpty"))
        #expect(historyList.contains("private var emptyHistory: some View"))
        #expect(historyList.contains("Text(emptyTitle)"))
        #expect(historyList.contains("Text(emptySubtitle)"))
        #expect(historyList.contains(".font(.system(size: emptyTitleFontSize, weight: emptyTitleFontWeight))"))
        #expect(historyList.contains(".font(.system(size: emptySubtitleFontSize))"))
        #expect(historyList.contains(".padding(emptyHistoryPadding)"))
        #expect(historyList.contains(".background(rowBackgroundColor)"))
        #expect(historyList.contains(".cornerRadius(emptyHistoryCornerRadius)"))
        #expect(historyList.contains(".accessibilityLabel(emptyTitle)"))
        #expect(historyList.contains(".accessibilityValue(emptySubtitle)"))
        #expect(historyList.contains(".help(emptySubtitle)"))
        #expect(historyList.contains("let lastMessage = lastMessagePreview(for: item)"))
        #expect(historyList.contains("VStack(alignment: .leading, spacing: listSpacing)"))
        #expect(historyList.contains("ForEach(sortedItems) { item in"))
        #expect(historyList.contains("Button(action: { onSelect(item) })"))
        #expect(historyList.contains("VStack(alignment: .leading, spacing: rowTextSpacing)"))
        #expect(historyList.contains(".font(.system(size: rowFontSize))"))
        #expect(historyList.contains(".lineLimit(1)\n                                    .truncationMode(.tail)"))
        #expect(historyList.contains("Text(lastMessage)"))
        #expect(historyList.contains(".font(.system(size: rowPreviewFontSize))"))
        #expect(historyList.contains(".lineLimit(2)"))
        #expect(historyList.contains(".lineLimit(2)\n                                        .truncationMode(.tail)"))
        #expect(historyList.contains(".padding(rowPadding)"))
        #expect(historyList.contains("""
                            .padding(rowPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .quillHistoryRowBackground(rowBackgroundColor(for: rowState), cornerRadius: rowCornerRadius)
                        }
                        .contentShape(Rectangle())
"""))
        #expect(historyList.contains(".quillHistoryRowButtonStyle(isSelected: isSelected, drawsIdleBackground: true)"))
        #expect(historyList.contains("private var listSpacing: CGFloat { 8 }"))
        #expect(historyList.contains("private var rowFontSize: CGFloat { 15 }"))
        #expect(historyList.contains("private var rowPreviewFontSize: CGFloat { 12 }"))
        #expect(historyList.contains("private var rowPadding: CGFloat { 11 }"))
        #expect(historyList.contains("private var rowTextSpacing: CGFloat { 5 }"))
        #expect(historyList.contains("private var rowCornerRadius: CGFloat { CGFloat(MacMetrics.ListRow.cornerRadius) }"))
        #expect(historyList.contains("private var emptyTitleFontSize: CGFloat { 15 }"))
        #expect(historyList.contains("private var emptySubtitleFontSize: CGFloat { 12 }"))
        #expect(historyList.contains("private var emptyTitleFontWeight: Font.Weight { .bold }"))
        #expect(historyList.contains("private var emptyHistoryPadding: CGFloat { 12 }"))
        #expect(historyList.contains("private var emptyHistorySpacing: CGFloat { 8 }"))
        #expect(historyList.contains("private var emptyHistoryCornerRadius: CGFloat { 8 }"))
        #expect(historyList.contains("private var sortedItems: [QuillConversationHistoryItem]"))
        #expect(historyList.contains("items.sorted { $0.updatedAt > $1.updatedAt }"))
        #expect(historyList.contains("public struct QuillDateGroupedConversationHistoryList: View"))
        #expect(historyList.contains("public init<SourceItem>("))
        #expect(historyList.contains("var sourceItemsByID: [String: SourceItem] = [:]"))
        #expect(historyList.contains("lastMessage: @escaping (SourceItem) -> String = { _ in \"\" }"))
        #expect(historyList.contains("onSelect: { item in\n                if let sourceItem = sourceItemsByID[item.id]"))
        #expect(historyList.contains("onDelete: onDelete.map { delete in"))
        #expect(historyList.contains("public var dateTitle: (Date) -> String"))
        #expect(historyList.contains("public var onDeleteDay: ((Date) -> Void)?"))
        #expect(historyList.contains("Dictionary(grouping: items) { item in"))
        #expect(historyList.contains("Calendar.current.startOfDay(for: item.updatedAt)"))
        #expect(historyList.contains("QuillConversationHistoryDayGroup("))
        #expect(historyList.contains("ForEach(dayGroups) { group in"))
        #expect(historyList.contains("Text(dateTitle(group.date))"))
        #expect(historyList.contains("ForEach(group.items) { item in"))
        #expect(historyList.contains("private func groupedRow(for item: QuillConversationHistoryItem) -> some View"))
        #expect(historyList.contains("return Button(action: { onSelect(item) })"))
        #expect(historyList.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(historyList.contains(".lineLimit(1)\n                    .truncationMode(.tail)"))
        #expect(historyList.contains("""
            .padding(.vertical, groupedRowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: groupedRowMinHeight, alignment: .leading)
        }
        .contentShape(Rectangle())
"""))
        #expect(historyList.contains("""
        .help(item.title)
        #if os(Linux)
        .onTapGesture { onSelect(item) }
        #endif
        .onHover { hovering in
"""))
        #expect(historyList.contains("let textState = PaintControlState(isHovered: isHovered, isSelected: isSelected)"))
        #expect(historyList.contains("MacListRowPaint.primaryTextColor(for: textState)"))
        #expect(historyList.contains(".foregroundColor(Color(quillPaint: MacListRowPaint.primaryTextColor(for: textState)))"))
        #expect(historyList.contains(".quillHistoryRowButtonStyle(isSelected: isSelected, drawsIdleBackground: false)"))
        #expect(historyList.contains("Button(role: .destructive, action: { onDeleteDay(date) })"))
        #expect(historyList.contains("Button(role: .destructive, action: { onDelete(item) })"))
        #expect(historyList.contains("private var groupedSectionFontSize: CGFloat { 24 }"))
        #expect(historyList.contains("private var groupedRowFontSize: CGFloat { 23 }"))
        #expect(historyList.contains("private var groupedRowMinHeight: CGFloat { 48 }"))
        #expect(historyList.contains("private var groupedSelectionDotSize: CGFloat { 8 }"))
        #expect(!historyList.contains("No conversations yet"))
        #expect(!historyList.contains(".font(.caption)"))
        #expect(!historyList.contains(".padding(.top, 12)"))
        #expect(!historyList.contains("QuillConversationHistorySection"))
        #expect(!historyList.contains("ForEach(sections)"))
        #expect(!historyList.contains("Text(section.title)"))
        #expect(!historyList.contains("private static func sectionTitle"))
        #expect(!historyList.contains("selectionIndicatorTopPadding"))
        #expect(!historyList.contains("rowHorizontalPadding"))
        #expect(!historyList.contains("QuillDesktopChromeStyle.selectedRowCornerRadius"))
        #expect(historyList.contains("@State private var hoveredItemID: String?"))
        #expect(historyList.contains("let isHovered = hoveredItemID == item.id"))
        #expect(historyList.contains("let rowState = PaintControlState(isHovered: isHovered, isSelected: isSelected)"))
        #expect(historyList.contains("private var rowBackgroundColor: Color { Color(quillPaint: MacColors.controlBackground) }"))
        #expect(historyList.contains("private func rowBackgroundColor(for state: PaintControlState) -> Color"))
        #expect(historyList.contains("MacListRowPaint.effectiveFillColor(for: state)"))
        #expect(historyList.contains("MacListRowPaint.primaryTextColor(for: state)"))
        #expect(historyList.contains("MacListRowPaint.secondaryTextColor(for: state)"))
        #expect(historyList.contains(".foregroundColor(rowTitleColor(for: rowState))"))
        #expect(historyList.contains(".foregroundColor(rowPreviewColor(for: rowState))"))
        #expect(historyList.contains(".quillHistoryRowBackground(rowBackgroundColor(for: rowState), cornerRadius: rowCornerRadius)"))
        #expect(historyList.contains("func quillHistoryRowButtonStyle(isSelected: Bool, drawsIdleBackground: Bool) -> some View"))
        #expect(historyList.contains("ButtonStyleType.quillPaintMacListRow("))
        #expect(historyList.contains(".onHover { hovering in"))
        #expect(historyList.contains("hoveredItemID = hovering ? item.id : nil"))
        #expect(historyList.contains("private func lastMessagePreview(for item: QuillConversationHistoryItem) -> String"))
        #expect(historyList.contains("item.lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)"))
        #expect(historyList.contains("return \"\\(item.title)\\n\\(lastMessage)\""))
    }

    @Test("QuillSidebarNavigationButton uses native image symbols")
    func quillSidebarNavigationButtonUsesNativeImageSymbols() throws {
        let controls = try packageSource("Sources/QuillUI/Controls.swift")
        #expect(controls.contains("public struct QuillDesktopSidebar<Content: View>: View"))
        #expect(controls.contains("public var bottomActions: [QuillSidebarNavigationAction]"))
        #expect(controls.contains("QuillSidebarBottomNavigation(actions: bottomActions)"))
        #expect(controls.contains(".frame(height: 146)\n                .frame(maxWidth: .infinity, alignment: .topLeading)"))
        #expect(!controls.contains(".frame(maxWidth: .infinity, height: 146, alignment: .topLeading)"))
        #expect(!controls.contains(".frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)"))
        #expect(controls.contains("public struct QuillDesktopChatUtilitySidebar<"))
        #expect(controls.contains("@State private var showSettings = false"))
        #expect(controls.contains("@State private var showCompletions: Bool"))
        #expect(controls.contains("self._showCompletions = State(wrappedValue: QuillDesktopChatInitialUtilitySheet.showCompletions())"))
        #expect(controls.contains("@State private var showShortcuts = false"))
        #expect(controls.contains("QuillDesktopSidebar(bottomActions: bottomActions)"))
        #expect(controls.contains("settingsFocusedValue: settingsFocusedValue"))
        #expect(controls.contains("onSettings: onSettings"))
        #expect(controls.contains("public struct QuillDesktopChatConversationSidebar<"))
        #expect(controls.contains("public var conversations: [Conversation]"))
        #expect(controls.contains("private var conversationID: (Conversation) -> String"))
        #expect(controls.contains("QuillDateGroupedConversationHistoryList(\n                items: conversations"))
        #expect(controls.contains("id: conversationID"))
        #expect(controls.contains("title: conversationTitle"))
        #expect(controls.contains("updatedAt: conversationUpdatedAt"))
        #expect(controls.contains("public static func desktopChatUtilities("))
        #expect(controls.contains(".completions(action: onCompletions)"))
        #expect(controls.contains(".shortcuts(action: onShortcuts)"))
        #expect(controls.contains(".settings(action: onSettings)"))
        #expect(controls.contains(".padding(.horizontal, 18)"))
        #expect(controls.contains(".padding(.top, 88)"))
        #expect(controls.contains(".padding(.bottom, 18)"))
        #expect(controls.contains("public struct QuillSheetStatusBanner<SheetContent: View>: View"))
        #expect(controls.contains("@State private var isPresented = false"))
        #expect(controls.contains(".sheet(isPresented: $isPresented)"))
        #expect(controls.contains("private var resolvedHorizontalPadding: Int { Int(horizontalPadding.rounded()) }"))
        #expect(controls.contains("public struct QuillChatUnreachableBanner<SettingsContent: View>: View"))
        #expect(controls.contains("Quill is unreachable. Plug Quill back in if it's unplugged"))
        #expect(controls.contains("QuillSheetStatusBanner(\n            message: message"))

        let cairoPaintContext = try packageSource("Sources/QuillPaintCairo/CairoPaintContext.swift")
        #expect(cairoPaintContext.contains("import CCairo"))
        #expect(cairoPaintContext.contains("public convenience init(cr: OpaquePointer)"))
        #expect(cairoPaintContext.contains("MacFontResolution.resolve(font)"))
        #expect(cairoPaintContext.contains("cairo_select_font_face("))
        #expect(cairoPaintContext.contains("cairo_show_text(pointer, string)"))
        #expect(!cairoPaintContext.contains("drawText(_ string: String, at point: PaintPoint, font: PaintFont, color: PaintColor) {\n        // TODO"))

        guard let buttonStart = controls.range(of: "public struct QuillSidebarNavigationButton: View"),
              let nextSection = controls.range(of: "public struct QuillStatusBanner: View") else {
            Issue.record("Unable to locate QuillSidebarNavigationButton source")
            return
        }

        let sidebarButton = String(controls[buttonStart.lowerBound..<nextSection.lowerBound])
        #expect(sidebarButton.contains("Image(systemName: sidebarSystemImageName)"))
        #expect(sidebarButton.contains(".frame(width: 24, height: 24, alignment: .leading)"))
        #expect(sidebarButton.contains(".quillSidebarUtilityButtonStyle()"))
        #expect(!sidebarButton.contains(".buttonStyle(.plain)"))
        #expect(sidebarButton.contains("if systemImage == \"textformat.abc\""))
        #expect(sidebarButton.contains("Text(\"Abc\")"))
        #expect(sidebarButton.contains("QuillSidebarKeyboardGlyph(color: Color(hex: \"#3A3A3C\"))"))
        #expect(sidebarButton.contains("QuillSidebarGearGlyph(color: Color(hex: \"#3A3A3C\"))"))
        #expect(sidebarButton.contains("private struct QuillSidebarKeyboardGlyph: View"))
        #expect(sidebarButton.contains("private struct QuillSidebarGearGlyph: View"))
        #expect(sidebarButton.contains(".stroke(color, lineWidth: 1.3)"))
        #expect(sidebarButton.contains("ForEach(0..<8, id: \\.self)"))
        #expect(sidebarButton.contains(".rotationEffect(Angle.degrees(Double(index) * 45))"))
        #expect(sidebarButton.contains(".stroke(color, lineWidth: 1.7)"))
        #expect(sidebarButton.contains("\"textformat\", \"textformat.abc\""))
        #expect(sidebarButton.contains("\"keyboard\", \"keyboard.fill\""))
        #expect(sidebarButton.contains("\"gearshape\", \"gearshape.fill\", \"gear\""))
        #expect(!sidebarButton.contains("case \"keyboard\", \"keyboard.fill\":"))
        #expect(!sidebarButton.contains("case \"gearshape\", \"gearshape.fill\", \"gear\":"))
        #expect(controls.contains("func quillSidebarUtilityButtonStyle() -> some View"))
        #expect(controls.contains("self.buttonStyle(ButtonStyleType.quillPaintMacListRow(\n            isSelected: false,\n            drawsIdleBackground: false\n        ))"))
    }

    @Test("GTK QuillPaint hooks cover button and text input chrome")
    func gtkQuillPaintHooksCoverButtonAndTextInputChrome() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let textFieldPrimitive = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/TextField.swift")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")
        let smallPatcher = try packageSource("scripts/patch-swiftopenui-quillpaint.py")
        let gtkBackend = try packageSource("Sources/QuillUIGtk/QuillUIGtk.swift")
        let gtkButton = try packageSource("Sources/QuillUIGtk/QuillGtkButton.swift")
        let gtkTextField = try packageSource("Sources/QuillUIGtk/QuillGtkTextField.swift")
        let gtkToggle = try packageSource("Sources/QuillUIGtk/QuillGtkToggle.swift")
        let gtkListRow = try packageSource("Sources/QuillUIGtk/QuillGtkListRow.swift")

        for source in [renderer, patcher, smallPatcher] {
            #expect(source.contains("quill_gtk_button_paint_hook"))
            #expect(source.contains("quill_gtk_text_field_paint_hook"))
            #expect(source.contains("quill_gtk_text_editor_paint_hook"))
            #expect(source.contains("quill_gtk_toggle_paint_hook"))
            #expect(source.contains("quill_gtk_list_row_paint_hook"))
            #expect(source.contains("quillPaintMacListRow"))
            #expect(source.contains("var useQuillPaintTextField = false"))
            #expect(source.contains("textFieldStyleType == .roundedBorder"))
            #expect(source.contains("extension SecureField: GTKRenderable"))
            #expect(source.contains("quill_gtk_text_field_paint_hook?(OpaquePointer(entry), true)"))
            #expect(source.contains("extension TextEditor: GTKRenderable"))
            #expect(source.contains("extension Toggle: GTKRenderable"))
            #expect(source.contains("quill_gtk_toggle_paint_hook?("))
        }

        #expect(renderer.contains("private final class GTKTextBindingIdleUpdate"))
        #expect(renderer.contains("includeValueWhenUnidentified: Bool = false"))
        #expect(renderer.contains("configuration.maxColumns > 1 ? 160 : 0"))
        #expect(renderer.contains("let gtkSwiftFontMonospacedMarker = \"gtk-swift-font-monospaced\""))
        #expect(renderer.contains("private let gtkFontDescendantSelectors = ["))
        #expect(renderer.contains("\"textview text\""))
        #expect(renderer.contains("private func gtkFontCSS(_ font: Font)"))
        #expect(renderer.contains("case .custom(let size, let weight, let design):"))
        #expect(renderer.contains("appendWeight(weight)"))
        #expect(renderer.contains("appendDesign(design)"))
        #expect(renderer.contains("descendantSelectors: gtkFontDescendantSelectors"))
        #expect(renderer.contains("gtkScheduleTextBindingUpdate(binding, value: newText)"))
        #expect(renderer.contains("gtk_text_view_set_accepts_tab(textViewPtr, 1)"))
        #expect(textFieldPrimitive.contains("public let axis: Axis"))
        #expect(textFieldPrimitive.contains("public init(_ title: String, text: Binding<String>, axis: Axis = .horizontal)"))
        #expect(renderer.contains("props: .text(GTK4TextDescriptor(content: \"\\(content)|axis:\\(axis.rawValue)\"))"))
        #expect(renderer.contains("if axis.contains(.vertical) {\n            return gtkCreateMultilineTextField(title: title, text: text)\n        }"))
        #expect(renderer.contains("private final class GTKMultilineTextFieldBindingBox"))
        #expect(renderer.contains("private final class GTKTextInputFocusTarget"))
        #expect(renderer.contains("private func gtkInstallTextInputFocusGesture("))
        #expect(renderer.contains("gtkFocusTextInputWidget(target.widget)"))
        #expect(renderer.contains("private func gtkScheduleTextInputFocus("))
        #expect(renderer.contains("gtk_widget_set_can_focus(target.widget, 1)"))
        #expect(renderer.contains("gtk_widget_set_can_target(overlay, 1)"))
        #expect(renderer.contains("gtkInstallTextInputFocusGesture(on: renderedWidget, target: textView)"))
        #expect(renderer.contains("if styleContext != nil || !(label is Text) {\n                // Remove GTK default button border/padding so custom-styled"))
        #expect(renderer.contains("background: transparent;\n                    background-color: transparent;\n                    background-image: none;\n                    border: none;"))
        #expect(renderer.contains("border-radius: 0;\n                    box-shadow: none;\n                    outline: none;"))
        #expect(renderer.contains("min-width: 0;\n                    text-shadow: none;"))
        #expect(patcher.contains("if styleContext != nil || !(label is Text) {"))
        #expect(patcher.contains("background: transparent;\n                    background-color: transparent;\n                    background-image: none;\n                    border: none;"))
        #expect(patcher.contains("border-radius: 0;\n                    box-shadow: none;\n                    outline: none;"))
        #expect(patcher.contains("min-width: 0;\n                    text-shadow: none;"))
        #expect(renderer.contains("private let gtkPlainMultilineTextInputCSS"))
        #expect(renderer.contains("background-image: none;"))
        #expect(renderer.contains("private func gtkApplyPlainMultilineTextFieldChrome("))
        #expect(renderer.contains("descendantSelectors: gtkPlainMultilineScrolledDescendants"))
        #expect(renderer.contains("let textFieldStyleType = environment.textFieldStyle"))
        #expect(renderer.contains("gtk_widget_set_margin_start(placeholderLabel, textFieldStyleType == .plain ? 0 : 6)"))
        #expect(renderer.contains("var useQuillPaintTextEditor = false"))
        #expect(renderer.contains("case .plain:\n        gtkApplyPlainMultilineTextFieldChrome(scrolledWindow: scrolled, textView: textView)"))
        #expect(renderer.contains("case .automatic, .roundedBorder:\n        useQuillPaintTextEditor = true"))
        #expect(renderer.contains("if useQuillPaintTextEditor,\n       let paintedEditor = quill_gtk_text_editor_paint_hook?("))
        #expect(renderer.contains("gtk_text_view_set_accepts_tab(textViewPtr, 0)"))
        #expect(renderer.contains("gtkInstallTextInputKeyController(\n        on: textView,\n        submitAction: environment.submitAction,\n        keyPressActions: environment.keyPressActions\n    )"))
        #expect(renderer.contains("gtk_widget_set_hexpand(overlay, gtk_widget_get_hexpand(renderedWidget))"))
        #expect(renderer.contains("gtk_widget_set_vexpand(overlay, gtk_widget_get_vexpand(renderedWidget))"))
        #expect(renderer.contains("gtk_overlay_add_overlay(OpaquePointer(overlay), placeholderLabel)"))
        #expect(renderer.contains("gtkInstallTextInputFocusGesture(on: overlay, target: textView)"))
        #expect(renderer.contains("let buffer = gtk_text_view_get_buffer(textViewPtr)!\n        let box = Unmanaged.passRetained(StringClosureBox { newText in\n            gtkScheduleTextBindingUpdate(binding, value: newText)\n        }).toOpaque()"))
        #expect(renderer.contains("return {\n        gtkFlushPendingTextBindingUpdate()\n        let previousEnvironment = getCurrentEnvironment()"))
        #expect(renderer.contains("return { value in\n        gtkFlushPendingTextBindingUpdate()\n        let previousEnvironment = getCurrentEnvironment()"))
        #expect(renderer.contains("let changedBox = Unmanaged.passRetained(StringClosureBox"))
        #expect(renderer.contains("gtk_editable_get_text(OpaquePointer(editable))"))
        #expect(patcher.contains("SwiftOpenUI TextField changed-signal insert shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI TextField idle binding helper insertion marker was not recognized"))
        #expect(patcher.contains("SwiftOpenUI action binding flush insertion shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI value action binding flush insertion shape was not recognized"))
        #expect(patcher.contains("direct_text_editor_update = '''        let box = Unmanaged.passRetained(StringClosureBox { newText in"))
        #expect(patcher.contains("idle_text_editor_update = '''        let box = Unmanaged.passRetained(StringClosureBox { newText in"))
        #expect(patcher.contains("old_text_editor_options = '''        gtk_text_view_set_wrap_mode(textViewPtr, GTK_WRAP_WORD_CHAR)"))
        #expect(patcher.contains("gtk_text_view_set_accepts_tab(textViewPtr, 1)"))
        #expect(patcher.contains("private func gtkFontCSS(_ font: Font)"))
        #expect(patcher.contains("descendantSelectors: gtkFontDescendantSelectors"))
        #expect(smallPatcher.contains("private func gtkFontCSS(_ font: Font)"))
        #expect(smallPatcher.contains("SwiftOpenUI action binding flush insertion shape was not recognized"))
        #expect(smallPatcher.contains("SwiftOpenUI value action binding flush insertion shape was not recognized"))
        #expect(smallPatcher.contains("direct_text_editor_update = '''        let box = Unmanaged.passRetained(StringClosureBox { newText in"))
        #expect(smallPatcher.contains("old_text_editor_options = '''        gtk_text_view_set_wrap_mode(textViewPtr, GTK_WRAP_WORD_CHAR)"))
        #expect(smallPatcher.contains("gtk_text_view_set_accepts_tab(textViewPtr, 1)"))
        #expect(smallPatcher.contains("descendantSelectors: gtkFontDescendantSelectors"))
        #expect(patcher.contains("private final class GTKTextBindingIdleUpdate"))
        #expect(patcher.contains("includeValueWhenUnidentified: Bool = false"))
        #expect(patcher.contains("gtkScheduleTextBindingUpdate(binding, value: newText)"))
        #expect(patcher.contains("let changedBox = Unmanaged.passRetained(StringClosureBox"))
        #expect(patcher.contains("gtk_editable_get_text(OpaquePointer(editable))"))

        #expect(gtkBackend.contains("installQuillButtonHook()"))
        #expect(gtkBackend.contains("installQuillTextFieldHook()"))
        #expect(gtkBackend.contains("installQuillToggleHook()"))
        #expect(gtkBackend.contains("installQuillListRowHook()"))
        #expect(gtkButton.contains("setupQuillButtonChrome(button: button, label: label, isDefault: isDefault)"))
        #expect(gtkButton.contains("MacButtonPaint()"))
        #expect(gtkTextField.contains("setupQuillTextFieldChrome(entry: entry)"))
        #expect(gtkTextField.contains("setupQuillTextEditorChrome(scrolledWindow: scrolledWindow, textView: textView)"))
        #expect(gtkTextField.contains("MacTextFieldPaint()"))
        #expect(gtkTextField.contains("installQuillTextInputFocusGesture(on: overlay, focus: focusEntry)"))
        #expect(gtkTextField.contains("installQuillTextInputFocusGesture(on: entryWidget, focus: focusEntry)"))
        #expect(gtkTextField.contains("installQuillTextInputFocusGesture(on: scrolledWidget, focus: focusTextView)"))
        #expect(gtkTextField.contains("gtk_swift_add_capture_gesture(widget, gesture)"))
        #expect(gtkTextField.contains("\"pressed\""))
        #expect(gtkTextField.contains("gtk_editable_get_delegate(OpaquePointer(entry))"))
        #expect(gtkTextField.contains("quillTextFieldForceFocus(quillTextFieldGTKWidgetPointer(delegate))"))
        #expect(gtkTextField.contains("gtk_swift_root_grab_focus(widget)"))
        #expect(gtkTextField.contains("private final class QuillGTKTextInputFocusTarget"))
        #expect(gtkTextField.contains("quillTextFieldScheduleRootFocus(widget)"))
        #expect(gtkTextField.contains("g_object_ref(gpointer(widget))"))
        #expect(gtkTextField.contains("g_idle_add({ userData -> gboolean in"))
        #expect(gtkTextField.contains("g_object_unref(gpointer(target.widget))"))
        #expect(gtkTextField.contains("gtk_overlay_add_overlay(OpaquePointer(overlay), entryWidget)"))
        #expect(gtkTextField.contains("gtk_overlay_add_overlay(OpaquePointer(overlay), scrolledWidget)"))
        #expect(gtkTextField.contains("gtk_swift_drawing_area_set_draw_func("))
        #expect(gtkTextField.contains("CairoPaintContext(cr: cr)"))
        #expect(gtkTextField.contains(".quill-paint-text-field text placeholder"))
        #expect(gtkTextField.contains("textview.quill-paint-text-editor"))
        #expect(gtkTextField.contains("let editorBackgroundColor = quillTextFieldCSSRGBA(MacColors.controlBackground)"))
        #expect(gtkTextField.contains("background: \\(editorBackgroundColor);"))
        #expect(renderer.range(of: "if widthFree && !heightFree && childExpH") != nil)
        #expect(renderer.range(of: "if widthMayGrowWithParent || heightMayGrowWithParent") != nil)
        #expect(
            renderer.range(of: "if widthFree && !heightFree && childExpH")!.lowerBound
                < renderer.range(of: "if widthMayGrowWithParent || heightMayGrowWithParent")!.lowerBound
        )
        #expect(gtkToggle.contains("setupQuillToggleChrome(control: control, isSwitch: isSwitch, label: label)"))
        #expect(gtkToggle.contains("MacCheckboxPaint(value: chromeBox.isActive ? .on : .off)"))
        #expect(gtkToggle.contains("MacSwitchPaint(isOn: chromeBox.isActive)"))
        #expect(gtkToggle.contains("gtk_widget_set_opacity(control, 0.001)"))
        #expect(gtkToggle.contains("installQuillToggleLabelGesture"))
        #expect(gtkListRow.contains("setupQuillListRowChrome("))
        #expect(gtkListRow.contains("MacListRowPaint()"))
        #expect(gtkListRow.contains("drawsIdleBackground"))
        #expect(gtkListRow.contains("gtk_overlay_add_overlay(OpaquePointer(overlay), contentWidget)"))
        #expect(gtkListRow.contains("CairoPaintContext(cr: cr)"))
        #expect(gtkListRow.contains("quill-paint-list-row"))
    }

    @Test("SwiftUI onKeyPress is real GTK text input behavior, not an inert shim")
    func swiftUIOnKeyPressRendersThroughGTKTextInputs() throws {
        let compatibility = try packageSource("Sources/QuillSwiftUICompatibility/DesignSystemSurfaceCompat.swift")
        let primitive = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/OnKeyPressModifier.swift")
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")

        #expect(!compatibility.contains("func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPressResult) -> Self"))
        #expect(primitive.contains("public enum KeyPressResult"))
        #expect(primitive.contains("public struct OnKeyPressView<Content: View>: View, PrimitiveView"))
        #expect(primitive.contains("public func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPressResult) -> OnKeyPressView<Self>"))
        #expect(primitive.contains("public var keyPressActions: [KeyPressAction]"))
        #expect(renderer.contains("private func gtkKeyEquivalent(for keyval: guint) -> KeyEquivalent?"))
        #expect(renderer.contains("private final class GTKTextInputKeyControllerBox"))
        #expect(renderer.contains("for keyPressAction in keyPressActions.reversed() where keyPressAction.key == key"))
        #expect(renderer.contains("if keyPressAction.handler() == .handled"))
        #expect(renderer.contains("extension OnKeyPressView: GTKRenderable, GTKDescribable"))
        #expect(renderer.contains("env.keyPressActions.append(KeyPressAction(key: key, handler: action))"))
        #expect(renderer.contains("keyPressActions: environment.keyPressActions"))
        #expect(renderer.contains("keyPressActions: getCurrentEnvironment().keyPressActions"))
    }

    @Test("Enchanted SF Symbols map to bundled Material glyphs")
    func enchantedSFSymbolsMapToMaterialGlyphs() throws {
        let symbols = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/SFSymbolCompatibility.swift"
        )
        let codepoints = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/MaterialSymbolsCodepoints.swift"
        )
        let renderer = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
        )
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        let expectedMappings: [(sf: String, material: String)] = [
            ("at", "alternate_email"),
            ("bookmark.fill", "bookmark"),
            ("checkmark.seal", "verified"),
            ("checkmark.seal.fill", "verified"),
            ("checkmark.square.fill", "check_box"),
            ("captions.bubble", "subtitles"),
            ("chart.bar", "bar_chart"),
            ("curlybraces", "data_object"),
            ("hand.draw", "gesture"),
            ("internaldrive", "hard_drive"),
            ("keyboard.fill", "keyboard"),
            ("line.3.horizontal", "menu"),
            ("list.bullet.rectangle.portrait", "list_alt"),
            ("newspaper", "newspaper"),
            ("paperplane.fill", "send"),
            ("paintpalette", "palette"),
            ("person.badge.minus", "person_remove"),
            ("photo", "image"),
            ("photo.fill", "image"),
            ("rectangle.stack", "stacks"),
            ("pin", "push_pin"),
            ("pin.fill", "push_pin"),
            ("selection.pin.in.out", "select_all"),
            ("server.rack", "dns"),
            ("sidebar.left", "view_sidebar"),
            ("space", "space_bar"),
            ("speaker.slash.fill", "volume_off"),
            ("speaker.wave.2.fill", "volume_up"),
            ("speaker.wave.3.fill", "volume_up"),
            ("square", "check_box_outline_blank"),
            ("square.fill", "stop"),
            ("sun.max", "light_mode"),
            ("textformat.abc", "text_fields"),
            ("wand.and.stars", "magic_button"),
            ("water.waves", "water_drop"),
            ("waveform", "graphic_eq")
        ]

        for (sf, material) in expectedMappings {
            let mappingLineExists = symbols
                .split(separator: "\n")
                .contains { line in
                    line.contains("\"\(sf)\"") && line.contains("\"\(material)\"")
                }
            let codepointLineExists = codepoints
                .split(separator: "\n")
                .contains { line in
                    line.contains("\"\(material)\"")
                }

            #expect(
                mappingLineExists,
                "Expected SF Symbol \(sf) to map to Material glyph \(material)"
            )
            #expect(
                codepointLineExists,
                "Expected Material glyph \(material) to have a direct-render codepoint"
            )
        }

        let expectedMappedCodepoints = [
            "alternate_email",
            "bar_chart",
            "newspaper",
            "person_remove",
            "public",
            "repeat",
            "reply"
        ]
        for material in expectedMappedCodepoints {
            #expect(
                codepoints.split(separator: "\n").contains { $0.contains("\"\(material)\"") },
                "Expected IceCubes Material glyph \(material) to have a direct-render codepoint"
            )
        }

        #expect(renderer.contains("private func gtkMaterialNameForSystemImage(_ sfName: String) -> String"))
        #expect(renderer.contains("let materialName = gtkMaterialSymbolName(forSystemName: iconName)"))
        #expect(renderer.contains("gtkRenderMaterialSymbolLabel(materialName, scale: .small)"))
        #expect(renderer.contains("let materialName = gtkMaterialSymbolName(forSystemName: sfName)"))
        #expect(renderer.contains("MaterialSymbolsCodepoints.codepoint(for: name)"))
        #expect(renderer.contains("let glyphPointSize = gtkMaterialSymbolGlyphPointSize(for: scale)"))
        #expect(renderer.contains("case .medium, .large:"))
        #expect(renderer.contains("Double(scale.pointSize) * 0.8"))
        #expect(!renderer.contains("gtk_image_new_from_icon_name(iconName)"))
        #expect(patcher.contains("MaterialSymbolsCodepoints.codepoint(for: name)"))
        #expect(patcher.contains("let glyphPointSize = gtkMaterialSymbolGlyphPointSize(for: scale)"))
        #expect(patcher.contains("SwiftOpenUI Material Symbols GTK renderer shape was not recognized"))
    }

    @Test("UIKit UIViewRepresentable text bindings lower to SwiftOpenUI TextEditor")
    func uiViewRepresentableTextBindingsLowerToSwiftOpenUITextEditor() throws {
        let representable = try packageSource("Sources/SwiftUIShim/UIKitRepresentable.swift")

        #expect(representable.contains("public protocol UIViewRepresentable: View"))
        #expect(!representable.contains("public protocol UIViewRepresentable: View where Body == EmptyView"))
        #expect(representable.contains("public struct QuillUIViewRepresentableHostView"))
        #expect(representable.contains("public protocol UIViewControllerRepresentable: View"))
        #expect(!representable.contains("public protocol UIViewControllerRepresentable: View where Body == EmptyView"))
        #expect(representable.contains("public struct QuillUIViewControllerRepresentableHostView"))
        #expect(representable.contains("QuillUIFontPickerControllerHost(controller: fontPicker, coordinatorRetainer: coordinator)"))
        #expect(representable.contains("private let coordinatorRetainer: Any"))
        #expect(representable.contains("init(controller: UIFontPickerViewController, coordinatorRetainer: Any)"))
        #expect(representable.contains("controller.delegate?.fontPickerViewControllerDidPickFont(controller)"))
        #expect(representable.contains("QuillAttributedTextRepresentableEditor(text: attributedText)"))
        #expect(representable.contains("TextEditor(text: plainText)"))
        #expect(representable.contains("private protocol QuillHostedSwiftUIView"))
        #expect(representable.contains("private final class QuillUIHostingUIView"))
        #expect(representable.contains("self.view = QuillUIHostingUIView(rootView: rootView)"))
        #expect(representable.contains("private func quillHostedSwiftUIView<R: UIViewRepresentable>(from representable: R) -> AnyView?"))
        #expect(representable.contains("representable.makeUIView(context: context)"))
        #expect(representable.contains("representable.updateUIView(uiView, context: context)"))
        #expect(representable.contains("return quillFindHostedSwiftUIView(in: coordinator)"))
        #expect(representable.contains("for subview in uiView.subviews"))
        #expect(representable.contains("Binding<NSMutableAttributedString>"))
        #expect(representable.contains("TextEditor(text: Binding<String>("))
        #expect(representable.contains("NSMutableAttributedString(string: newValue)"))
        #expect(representable.contains("private func quillFindBinding<Value>"))
    }

    @Test("GTK NavigationStack preserves empty destination navigation titles")
    func gtkNavigationStackPreservesEmptyDestinationNavigationTitles() throws {
        let navigation = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKNavigation.swift"
        )
        let viewHost = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKViewHost.swift"
        )
        let renderer = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
        )
        let environment = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUI/Environment/Environment.swift"
        )
        let renderTests = try packageSource(
            "third_party/SwiftOpenUI/Tests/BackendTests/GTK4Tests/GTK4RenderTests.swift"
        )
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(navigation.contains("let title = resolved.title"))
        #expect(!navigation.contains("resolved.title.isEmpty ? String(describing: value.base) : resolved.title"))
        #expect(navigation.contains("let stateNamespace: String"))
        #expect(navigation.contains("let navigationStateNamespace = gtkClaimStateIdentityNamespace(\"NavigationStack\")"))
        #expect(navigation.contains("func navigationDestinationStateNamespace(for value: AnyHashable) -> String"))
        #expect(navigation.contains("stateNamespace: navigationDestinationStateNamespace(for: value)"))
        #expect(navigation.contains("context.navigationDestinationStateNamespace(for: value)"))
        #expect(navigation.contains("env.refreshInjectedObjectsFromRegistry()"))
        #expect(navigation.contains("gtkResumeViewHostLifecycleForVisibleSubtree(widget)"))
        #expect(navigation.contains("g_object_ref(gpointer(widget))\n        g_idle_add({ userData -> gboolean in"))
        #expect(navigation.contains("g_object_unref(gpointer(widgetRef.widget))"))
        #expect(navigation.contains("GTKNavigationContextEnvironmentKey"))
        #expect(navigation.contains("gtkEnvironmentWithNavigationContext"))
        #expect(navigation.contains("gtkEnvironmentWithNavigationDestinationDismiss"))
        #expect(navigation.contains("DismissAction(handler: { [weak context] in"))
        #expect(navigation.contains("debugName: \"gtk navigation destination\""))
        #expect(navigation.contains("getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]"))
        #expect(navigation.contains("context.flushPendingPresentedDestinations()"))
        #expect(navigation.contains("NavigationPresentedDestinationModifier: GTKDescribable"))
        #expect(navigation.contains("content: isPresented.wrappedValue ? \"presented\" : \"dismissed\""))
        #expect(renderer.contains("extension Picker: GTKRenderable, GTKDescribable"))
        #expect(renderer.contains("typeName: \"Picker\""))
        #expect(renderer.contains("bindActionToCurrentEnvironment(onChanged)"))
        #expect(renderer.contains("SegmentClosureBox(index: index, closure: boundOnChanged)"))
        #expect(viewHost.contains("func gtkResumeViewHostLifecycleForVisibleSubtree"))
        #expect(viewHost.contains("resumeLifecycleAfterProgrammaticVisibilityChange()"))
        #expect(renderer.contains("gtkMountTypeCounters[namespace] = [:]"))
        #expect(environment.contains("public mutating func refreshInjectedObjectsFromRegistry()"))
        #expect(renderTests.contains("testNavigationStackBoundPathDestinationStateSurvivesParentRebuild"))
        #expect(renderTests.contains("testNavigationStackProgrammaticTypedPathRunsDestinationOnAppear"))
        #expect(renderTests.contains("testNavigationDestinationIsPresentedPushesAfterStateMutationInChildHost"))
        #expect(renderTests.contains("testNavigationDestinationIsPresentedPushesAfterPickerSelectionMutation"))
        #expect(renderTests.contains("testNavigationDestinationIsPresentedDismissActionPopsRouteAndClearsBinding"))
        #expect(renderTests.contains("GTKBoundNavigationDestinationProbeView"))
        #expect(renderTests.contains("GTKBoundNavigationOnAppearProbeView"))
        #expect(renderTests.contains("GTKPresentedNavigationStateProbeView"))
        #expect(renderTests.contains("GTKPresentedNavigationPickerProbeView"))
        #expect(renderTests.contains("GTKPresentedNavigationDismissDestination"))
        #expect(patcher.contains("let title = resolved.title"))
        #expect(patcher.contains("String(describing: value.base)"))
        #expect(patcher.contains("navigationDestinationStateNamespace"))
        #expect(patcher.contains("gtkClaimStateIdentityNamespace(\\\"NavigationStack\\\")"))
        #expect(patcher.contains("refreshInjectedObjectsFromRegistry"))
        #expect(patcher.contains("gtkResumeViewHostLifecycleForVisibleSubtree"))
        #expect(patcher.contains("NavigationPresentedDestinationModifier"))
        #expect(patcher.contains("GTKNavigationContextEnvironmentKey"))
        #expect(patcher.contains("gtkEnvironmentWithNavigationContext"))
        #expect(patcher.contains("gtkEnvironmentWithNavigationDestinationDismiss"))
        #expect(patcher.contains("debugName: \"gtk navigation destination\""))
        #expect(patcher.contains("context.flushPendingPresentedDestinations()"))
        #expect(patcher.contains("NavigationPresentedDestinationModifier: GTKDescribable"))
        #expect(patcher.contains("extension Picker: GTKRenderable, GTKDescribable"))
        #expect(patcher.contains("typeName: \"Picker\""))
        #expect(patcher.contains("let boundOnChanged = bindActionToCurrentEnvironment(onChanged)"))
        #expect(patcher.contains("let boundOnChanged = onChanged.map { bindActionToCurrentEnvironment($0) }"))
    }

    @Test("GTK onChange values are scoped by state identity namespace")
    func gtkOnChangeValuesAreScopedByStateIdentityNamespace() throws {
        let modifier = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/OnChangeModifier.swift"
        )
        let renderer = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
        )
        let tests = try packageSource(
            "third_party/SwiftOpenUI/Tests/SwiftOpenUITests/ModifierTests/OnChangeTests.swift"
        )
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        for source in [modifier, patcher] {
            #expect(source.contains("private struct OnChangeStorageKey: Hashable"))
            #expect(source.contains("let namespace: String"))
            #expect(source.contains("let storageKey = OnChangeStorageKey(namespace: namespace, index: key)"))
            #expect(
                source.contains("namespace: String = \"default\"")
                    || source.contains("namespace: String = \\\"default\\\"")
            )
            #expect(source.contains("_onChangePreviousValues[storageKey]"))
        }

        for source in [renderer, patcher] {
            #expect(source.contains("onChangeCheckAndFire("))
            #expect(source.contains("onChangeCheckAndFireTwoArg("))
            #expect(source.contains("namespace: gtkStateIdentityNamespace()"))
        }

        #expect(tests.contains("testFirstRenderInDifferentNamespaceDoesNotFire"))
        #expect(tests.contains("testNamespacesTrackPreviousValuesIndependently"))
        #expect(patcher.contains("SwiftOpenUI GTK OnChange single-argument renderer shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI OnChange storage shape was not recognized"))
    }

    @Test("GTK text normalizes IceCubes separator glyph for Linux font fallback")
    func gtkTextNormalizesIceCubesSeparatorGlyphForLinuxFontFallback() throws {
        let renderer = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
        )
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(renderer.contains("private func gtkDisplayTextContent(_ text: String) -> String"))
        #expect(renderer.contains("text.replacingOccurrences(of: \"\\u{2E31}\", with: \"\\u{00B7}\")"))
        #expect(renderer.contains("let displayContent = gtkDisplayTextContent(content)"))
        #expect(renderer.contains("let label = gtk_label_new(displayContent)!"))
        #expect(renderer.contains("gtkPrepareRowTextLabel(label, text: displayContent)"))
        #expect(renderer.contains("return gtkPangoMarkup(for: run.text, foregroundColor: color)"))

        #expect(patcher.contains("private func gtkDisplayTextContent"))
        #expect(patcher.contains("SwiftOpenUI Text GTK display normalization shape was not recognized"))
        #expect(patcher.contains("let displayContent = gtkDisplayTextContent(content)"))
    }

    @Test("GTK TabView hides empty SwiftUI compatibility switcher")
    func gtkTabViewHidesEmptySwiftUICompatibilitySwitcher() throws {
        let renderer = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
        )
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(renderer.contains("extension TabView: GTKRenderable, GTKDescribable"))
        #expect(renderer.contains("public func gtkDescribeNode() -> GTK4DescriptorNode"))
        #expect(renderer.contains("gtkWithStateIdentityNamespaceComponent(\"Tab[\\(id)]\")"))
        #expect(renderer.contains("let lazilyRenderInactiveTabs = selectionHandler != nil"))
        #expect(renderer.contains("if lazilyRenderInactiveTabs, id != activeResolvedId"))
        #expect(renderer.contains("opaqueFromWidget(gtkCreateEmptyViewWidget())"))

        for source in [renderer, patcher] {
            #expect(source.contains("private func gtkTabViewShouldShowSwitcher(_ tabs: [AnyTab]) -> Bool"))
            #expect(source.contains("tabs.count > 1 && tabs.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }"))
            #expect(source.contains("if gtkTabViewShouldShowSwitcher(tabs) {"))
            #expect(source.contains("let switcher = gtk_stack_switcher_new()!"))
            #expect(source.contains("gtk_swift_stack_switcher_set_stack(switcher, stack)"))
            #expect(source.contains("gtk_box_append(boxPointer(vbox), switcher)"))
        }

        #expect(patcher.contains("SwiftOpenUI TabView GTK switcher shape was not recognized"))
        #expect(!renderer.contains("let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!\n        gtk_box_append(boxPointer(vbox), switcher)"))
    }

    @Test("GTK renderer skips nil SwiftUI layout children generically")
    func gtkRendererSkipsNilSwiftUILayoutChildrenGenerically() throws {
        let renderer = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
        )
        let descriptorTree = try packageSource(
            "third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4DescriptorTree.swift"
        )
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        for source in [renderer, patcher] {
            #expect(source.contains("private func gtkLayoutChildViews(from view: any View, depth: Int = 0) -> [any View]"))
            #expect(source.contains("if mirror.displayStyle == .optional"))
            #expect(source.contains("guard let child = mirror.children.first?.value as? any View else { return [] }"))
            #expect(source.contains("String(reflecting: Swift.type(of: view)).contains(\"_ConditionalView\")"))
            #expect(source.contains("if let transparent = view as? any TransparentMultiChildView"))
            #expect(source.contains("return transparent.children.flatMap { gtkLayoutChildViews(from: $0, depth: depth + 1) }"))
            #expect(source.contains("if Swift.type(of: view) is any PrimitiveView.Type"))
            #expect(source.contains("unsupported primitive view rendered as EmptyView"))
            #expect(source.contains("return opaqueFromWidget(gtkCreateEmptyViewWidget())"))
            #expect(source.contains("for child in multi.children.flatMap({ gtkLayoutChildViews(from: $0) })"))
            #expect(source.contains("return gtkLayoutChildViews(from: child).map { render($0) }"))
            #expect(source.contains("return gtkLayoutChildViews(from: view).map { gtkRenderAnyView($0) }"))
        }

        for source in [descriptorTree, patcher] {
            #expect(source.contains("private func gtkDescriptorChildViews(from view: any View, depth: Int = 0) -> [any View]"))
            #expect(source.contains("if mirror.displayStyle == .optional"))
            #expect(source.contains("guard let child = mirror.children.first?.value as? any View else { return [] }"))
            #expect(source.contains("String(reflecting: Swift.type(of: view)).contains(\"_ConditionalView\")"))
            #expect(source.contains("if let transparent = view as? any TransparentMultiChildView"))
            #expect(source.contains("return transparent.children.flatMap { gtkDescriptorChildViews(from: $0, depth: depth + 1) }"))
            #expect(source.contains("children: multi.children.flatMap { child in"))
            #expect(source.contains("gtkDescriptorChildViews(from: child).map(gtkDescribeAnyView)"))
        }

        #expect(patcher.contains("SwiftOpenUI gtkRenderChildren layout-child shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI descriptor multi-child shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI primitive render fallback insertion point was not recognized"))
    }

    @Test("QuillCode SF Symbols map to bundled Material glyphs")
    func quillCodeSFSymbolsMapToMaterialGlyphs() throws {
        let symbols = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/SFSymbolCompatibility.swift"
        )
        let codepoints = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/MaterialSymbolsCodepoints.swift"
        )

        let expectedMappings: [(sf: String, material: String)] = [
            ("arrow.up.right", "open_in_new"),
            ("arrow.down.doc", "download"),
            ("arrow.triangle.merge", "merge_type"),
            ("arrow.up.doc", "upload_file"),
            ("arrow.uturn.backward", "undo"),
            ("arrow.uturn.left.square", "undo"),
            ("brain.head.profile", "psychology"),
            ("camera.viewfinder", "photo_camera"),
            ("clear", "backspace"),
            ("clock.fill", "schedule"),
            ("clock.arrow.circlepath", "history"),
            ("command", "keyboard_command_key"),
            ("diamond", "diamond"),
            ("display", "desktop_windows"),
            ("doc.plaintext", "article"),
            ("doc.richtext", "article"),
            ("exclamationmark.circle.fill", "error"),
            ("hammer", "construction"),
            ("hand.raised.fill", "front_hand"),
            ("hand.thumbsdown", "thumb_down"),
            ("hand.thumbsup", "thumb_up"),
            ("list.bullet.rectangle", "list_alt"),
            ("minus.rectangle", "disabled_by_default"),
            ("network.slash", "wifi_off"),
            ("person.2.badge.gearshape", "manage_accounts"),
            ("person.crop.circle.badge.checkmark", "how_to_reg"),
            ("play.circle.fill", "play_circle"),
            ("point.3.connected.trianglepath.dotted", "account_tree"),
            ("plus.bubble", "add_comment"),
            ("plus.message", "add_comment"),
            ("plus.rectangle.on.folder", "create_new_folder"),
            ("plus.square.on.square", "add_box"),
            ("puzzlepiece.extension", "extension"),
            ("q.circle.fill", "code"),
            ("rectangle.on.rectangle", "content_copy"),
            ("rectangle.stack.badge.questionmark", "unknown_document"),
            ("slash.circle", "keyboard_command_key"),
            ("stop.circle", "stop_circle"),
            ("tablecells", "table"),
            ("terminal", "terminal"),
            ("text.bubble", "chat_bubble"),
            ("text.bubble.badge.exclamationmark", "error"),
            ("text.bubble.badge.plus", "add_comment"),
            ("text.cursor", "text_fields"),
            ("text.magnifyingglass", "find_in_page"),
            ("trash.slash", "delete_forever"),
            ("waveform.path.ecg", "ecg_heart"),
            ("wrench.and.screwdriver", "construction"),
            ("xmark.octagon", "dangerous"),
            ("xmark.octagon.fill", "dangerous")
        ]

        for (sf, material) in expectedMappings {
            let mappingLineExists = symbols
                .split(separator: "\n")
                .contains { line in
                    line.contains("\"\(sf)\"") && line.contains("\"\(material)\"")
                }
            let codepointLineExists = codepoints
                .split(separator: "\n")
                .contains { line in
                    line.contains("\"\(material)\"")
                }

            #expect(
                mappingLineExists,
                "Expected QuillCode SF Symbol \(sf) to map to Material glyph \(material)"
            )
            #expect(
                codepointLineExists,
                "Expected Material glyph \(material) to have a direct-render codepoint"
            )
        }
    }

    @Test("SF Symbol compatibility map is covered by direct-render codepoints")
    func sfSymbolCompatibilityMapIsCoveredByDirectRenderCodepoints() throws {
        let symbols = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/SFSymbolCompatibility.swift"
        )
        let codepoints = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/MaterialSymbolsCodepoints.swift"
        )

        let materialRegex = try NSRegularExpression(pattern: #""[^"]+"\s*:\s*"([^"]+)""#)
        let materialMatches = materialRegex.matches(
            in: symbols,
            range: NSRange(symbols.startIndex..., in: symbols)
        )
        let mappedMaterials = Set(materialMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: symbols) else { return nil }
            return String(symbols[range])
        })

        let codepointRegex = try NSRegularExpression(pattern: #""([^"]+)"\s*:"#)
        let codepointMatches = codepointRegex.matches(
            in: codepoints,
            range: NSRange(codepoints.startIndex..., in: codepoints)
        )
        let directRenderMaterials = Set(codepointMatches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: codepoints) else { return nil }
            return String(codepoints[range])
        })

        let missing = mappedMaterials.subtracting(directRenderMaterials).sorted()
        #expect(
            missing.isEmpty,
            Comment(rawValue: "Missing Material codepoints:\n" + missing.joined(separator: "\n"))
        )
    }

    @Test("Material Symbols codepoint table has unique keys")
    func materialSymbolsCodepointTableHasUniqueKeys() throws {
        let codepoints = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/MaterialSymbolsCodepoints.swift"
        )
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        let codepointRegex = try NSRegularExpression(pattern: #""([^"]+)"\s*:\s+0x[0-9A-Fa-f]+,"#)
        let codepointMatches = codepointRegex.matches(
            in: codepoints,
            range: NSRange(codepoints.startIndex..., in: codepoints)
        )
        var counts: [String: Int] = [:]
        for match in codepointMatches {
            guard let range = Range(match.range(at: 1), in: codepoints) else { continue }
            counts[String(codepoints[range]), default: 0] += 1
        }

        let duplicates = counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        #expect(
            duplicates.isEmpty,
            Comment(rawValue: "Duplicate Material codepoint keys:\n" + duplicates.joined(separator: "\n"))
        )
        #expect(patcher.contains("deduplicate_codepoint_entries"))
    }

    @Test("GTK installs OpenCombine main DispatchQueue bridge")
    func gtkInstallsOpenCombineMainDispatchQueueBridge() throws {
        let scheduler = try packageSource(
            "third_party/OpenCombine/Sources/OpenCombineDispatch/DispatchQueue+Scheduler.swift"
        )
        let gtkRuntime = try packageSource("Sources/QuillAppKitGTK/QuillAppKit+GTK.swift")
        let drawingHost = try packageSource("Sources/QuillAppKitGTK/QuillNSViewDrawingHost.swift")
        let manifest = try packageSource("Package.swift")

        #expect(scheduler.contains("openCombineDispatchInstallMainQueueScheduler"))
        #expect(scheduler.contains("openCombineDispatchIsMainQueue"))
        #expect(scheduler.contains("openCombineDispatchScheduleOnInstalledMainQueue"))
        #expect(scheduler.contains("queue.label == \"com.apple.main-thread\""))
        #expect(gtkRuntime.contains("openCombineDispatchInstallMainQueueScheduler"))
        #expect(gtkRuntime.contains("Preserve same-turn SwiftUI/Combine state ordering"))
        #expect(gtkRuntime.contains("if Thread.isMainThread"))
        #expect(gtkRuntime.contains("action()"))
        #expect(gtkRuntime.contains("QuillOpenCombineDispatchActionBox"))
        #expect(gtkRuntime.contains("g_idle_add_full(Int32(G_PRIORITY_DEFAULT)"))
        #expect(drawingHost.contains("if Thread.isMainThread"))
        #expect(drawingHost.contains("g_idle_add_full(Int32(G_PRIORITY_DEFAULT)"))
        #expect(manifest.contains(#".product(name: "OpenCombineDispatch", package: "OpenCombine")"#))
    }

    @Test("GTK labels use SF Symbol compatibility map")
    func gtkLabelsUseSFSymbolCompatibilityMap() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")

        #expect(renderer.contains("gtkMaterialSymbolName(forSystemName: iconName)"))
        #expect(renderer.contains("gtkRenderMaterialSymbolLabel(materialName, scale: .small)"))
        #expect(renderer.contains("gtkMaterialSymbolName(forSystemName: sfName)"))
        #expect(!renderer.contains("gtk_image_new_from_icon_name(iconName)"))
    }

    @Test("SwiftUI menu label builders preserve custom labels")
    func swiftUIMenuLabelBuildersPreserveCustomLabels() throws {
        let menu = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/Menu.swift")
        let compat = try packageSource("Sources/QuillSwiftUICompatibility/DesignSystemSurfaceCompat.swift")
        let gtkRenderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let qtRenderer = try packageSource("Sources/BackendQt/QtRenderer.swift")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(menu.contains("public let labelView: AnyView?"))
        #expect(menu.contains("labelView: AnyView? = nil"))
        #expect(menu.contains("self.init(title, elements: content())"))
        #expect(menu.contains("self.init(\"\", elements: content(), labelView: AnyView(label()), primaryAction: primaryAction)"))
        #expect(menu.contains("self.init(\"\", elements: content(), labelView: AnyView(label()))"))
        #expect(!compat.contains("self.init(\"\", content: content)"))

        for source in [gtkRenderer, patcher] {
            #expect(source.contains("private func gtkApplyPlainMenuButtonChrome"))
            #expect(
                source.contains("menubutton.\\(className) > button")
                    || source.contains("menubutton.\\\\(className) > button")
            )
            #expect(source.contains("if let labelView {"))
            #expect(source.contains("gtkDisableButtonChildTargeting(childWidget)"))
            #expect(source.contains("gtk_swift_menu_button_set_always_show_arrow(button, 0)"))
            #expect(source.contains("gtk_swift_menu_button_set_child(button, childWidget)"))
            #expect(source.contains("gtkApplyPlainMenuButtonChrome(to: button)"))
        }

        #expect(qtRenderer.contains("if let anyView = view as? AnyView"))
        #expect(qtRenderer.contains("if let labelView {"))
        #expect(qtRenderer.contains("let labelText = qtTextLabel(from: labelView.wrapped)"))
    }

    @Test("GTK plain button style suppresses platform chrome")
    func gtkPlainButtonStyleSuppressesPlatformChrome() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let shim = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/CGTK/shim.h")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        for source in [renderer, patcher] {
            #expect(source.contains("private func gtkDisableButtonChildTargeting"))
            #expect(source.contains("private func gtkDebugLog(_ message: String)"))
            #expect(source.contains("gtk_widget_set_can_target(widget, 0)"))
            #expect(source.contains("gtkDisableButtonChildTargeting(childWidget)"))
            #expect(source.contains("private final class GTKButtonActionBox"))
            #expect(source.contains("private func gtkScheduleButtonAction"))
            #expect(source.contains("private func gtkScheduleSheetDismissal"))
            #expect(source.contains("gtkScheduleSheetDismissal {"))
            #expect(source.contains("gtk_swift_gesture_single_set_button(gesture, 1)"))
            #expect(source.contains("gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource(\"gesture\", widget: context.widget)"))
            #expect(source.contains("gtk_swift_add_capture_gesture"))
            #expect(source.contains("gtk_swift_add_capture_gesture(button, gesture)"))
            #expect(source.contains("gtk_swift_legacy_capture_controller"))
            #expect(source.contains("gtk_swift_event_is_primary_button_press"))
            #expect(source.contains("gtkScheduleButtonAction(box, source: \"legacy\""))
            #expect(source.contains("GTKButtonRootEventContext"))
            #expect(source.contains("var gestureController: gpointer?"))
            #expect(source.contains("gtkInstallButtonRootEventFallback"))
            #expect(source.contains("context.gestureController = gpointer(gesture)"))
            #expect(source.contains("gtkDispatchButtonRootPress(context, root: root, x: x, y: y, source: \"root-legacy\")"))
            #expect(source.contains("gtkDispatchButtonRootPress(context, root: root, x: x, y: y, source: \"root-gesture\")"))
            #expect(source.contains("gtk_swift_add_capture_gesture(root, gesture)"))
            #expect(source.contains("private func gtkDispatchButtonRootPress"))
            #expect(
                source.contains("let resolvedSource = isTopmost ? source : \"\\(source)-visual\"")
                    || source.contains("let resolvedSource = isTopmost ? source : \"\\\\(source)-visual\"")
            )
            #expect(
                source.contains("gtkButtonDebugSource(\"\\(resolvedSource)@")
                    || source.contains("gtkButtonDebugSource(\"\\\\(resolvedSource)@")
            )
            #expect(source.contains("gtk_swift_widget_is_topmost_at_root_point"))
            #expect(source.contains("gtk_widget_add_css_class(button, \"flat\")"))
            #expect(source.contains("private let gtkButtonGlobalDispatcherDataKey"))
            #expect(source.contains("private final class GTKButtonGlobalRootDispatcher"))
            #expect(source.contains("gtkPreferredButtonActionAtRootPoint"))
            #expect(source.contains("button global root dispatcher installed"))
            #expect(source.contains("button global root-hit root@"))
            #expect(source.contains("gtkInstallGlobalButtonRootDispatcher(for: context.widget)"))
            #expect(source.contains("background: transparent;"))
            #expect(source.contains("background-color: transparent;"))
            #expect(source.contains("background-image: none;"))
            #expect(source.contains("border: none;"))
            #expect(source.contains("border-radius: 0;"))
            #expect(source.contains("box-shadow: none;"))
            #expect(source.contains("outline: none;"))
            #expect(source.contains("text-shadow: none;"))
            #expect(!source.contains("border: none; background: none; padding: 0;"))
        }
        for source in [shim, patcher] {
            #expect(source.contains("gtk_swift_flow_box_new"))
            #expect(source.contains("gtk_swift_flow_box_configure"))
            #expect(source.contains("gtk_swift_flow_box_insert"))
        }
        #expect(patcher.contains("gtk_swift_widget_contains_root_point"))
        #expect(!patcher.contains("guard gtk_swift_widget_contains_root_point(root, context.widget"))
        #expect(patcher.contains("GTK_PICK_NON_TARGETABLE"))
        #expect(patcher.contains("gtk_swift_widget_is_ancestor_or_self(picked, widget)"))
        #expect(shim.contains("GTK_PICK_NON_TARGETABLE"))
        #expect(shim.contains("gtk_swift_widget_is_ancestor_or_self(picked, widget)"))
        #expect(renderer.contains("gtk_swift_drop_down_new(stringList)!"))
        #expect(!renderer.contains("gtk_drop_down_new_from_strings(ptr)!"))
        #expect(renderer.contains("guard options.indices.contains(newIndex), newIndex != clampedSelection else"))
        #expect(renderer.contains("let boundOnChanged = bindActionToCurrentEnvironment(onChanged)"))
        #expect(renderer.contains("let boundOnChanged = onChanged.map { bindActionToCurrentEnvironment($0) }"))
        #expect(patcher.contains("gtk_swift_drop_down_new(stringList)!"))
        #expect(patcher.contains("guard options.indices.contains(newIndex), newIndex != clampedSelection else"))
        #expect(patcher.contains("gtk_swift_drop_down_new(gpointer model)"))
        #expect(shim.contains("gtk_swift_drop_down_new(gpointer model)"))
        #expect(shim.contains("gtk_drop_down_new(G_LIST_MODEL(model), NULL)"))
    }

    @Test("GTK backend launches through a plain GTK main loop")
    func gtkBackendLaunchesThroughPlainGTKMainLoop() throws {
        let backend = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4Backend.swift")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        for source in [backend, patcher] {
            #expect(source.contains("gtk_init_check()"))
            #expect(source.contains("factory(nil)"))
            #expect(source.contains("g_main_loop_new(nil, 0)"))
            #expect(source.contains("g_main_loop_run(loop)"))
            #expect(source.contains("extension Group: GTKWindowRenderable where Content: Scene"))
            #expect(source.contains("gtkRenderScene(content, app: app)"))
            #expect(!source.contains("g_application_run(applicationPointer(appPtr), 0, nil)"))
        }
        #expect(!backend.contains("g_application_run("))
    }

    @Test("GTK main-actor body rendering does not return raw pointers through assumeIsolated")
    func gtkMainActorBodyRenderingDoesNotReturnRawPointersThroughAssumeIsolated() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let navigation = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKNavigation.swift")

        #expect(renderer.contains("private final class GTKMainActorIsolatedResult<Value>: @unchecked Sendable"))
        #expect(renderer.contains("func gtkAssumeMainActorIsolated<Value>(_ body: @MainActor () -> Value) -> Value"))
        #expect(renderer.contains("MainActor.assumeIsolated {\n        result.value = body()\n    }"))
        #expect(renderer.contains("return gtkAssumeMainActorIsolated { renderable.gtkCreateWidget() }"))
        #expect(renderer.contains("return gtkAssumeMainActorIsolated { gtkRenderView(view.body) }"))
        #expect(renderer.contains("return gtkAssumeMainActorIsolated { multi.gtkRenderChildren() }"))
        #expect(renderer.contains("gtkAssumeMainActorIsolated { gtkRenderView(view.body) }"))
        #expect(navigation.contains("return gtkAssumeMainActorIsolated { gtkRenderToolbarWidgets(from: view.body) }"))

        #expect(!renderer.contains("return MainActor.assumeIsolated { renderable.gtkCreateWidget() }"))
        #expect(!renderer.contains("return MainActor.assumeIsolated { gtkRenderView(view.body) }"))
        #expect(!renderer.contains("return MainActor.assumeIsolated { multi.gtkRenderChildren() }"))
        #expect(!navigation.contains("return MainActor.assumeIsolated { gtkRenderToolbarWidgets(from: view.body) }"))
    }

    @Test("GTK patcher preserves fixed-frame and list viewport sizing contracts")
    func gtkPatcherPreservesFixedFrameAndListViewportSizingContracts() throws {
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let renderTests = try packageSource("third_party/SwiftOpenUI/Tests/BackendTests/GTK4Tests/GTK4RenderTests.swift")
        let navigation = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKNavigation.swift")
        let backend = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4Backend.swift")
        let environment = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Environment/Environment.swift")
        let compatibility = try packageSource("Sources/QuillUI/Compatibility.swift")

        #expect(patcher.contains("fixed_frame_child_sizing = \"SwiftUI proposes the clamped fixed-frame size to children\""))
        #expect(patcher.contains("gtkPixelSize(layout.childPlacement.size.width)"))
        #expect(patcher.contains("gtkPixelSize(layout.childPlacement.size.height)"))
        #expect(patcher.contains("fixed_frame_expanding_child_sizing = \"Expanding fixed-frame children receive the proposed frame size\""))
        #expect(patcher.contains("childExpH ? gtkPixelSize(layout.childPlacement.size.width) : -1"))
        #expect(patcher.contains("childExpV ? gtkPixelSize(layout.childPlacement.size.height) : -1"))
        #expect(patcher.contains("fixed_frame_box_clipping = \"Fixed-frame clipping uses a normal GtkBox allocation\""))
        #expect(patcher.contains("let slot: UnsafeMutablePointer<GtkWidget> = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!"))
        #expect(patcher.contains("gtk_box_append(boxPointer(slot), child)"))
        #expect(patcher.contains("fixed_frame_flexible_width_fixed_height_clip = \"gtkFrameFlexibleWidthFixedHeightClip\""))
        #expect(patcher.contains("if widthMayGrowWithParent && !heightMayGrowWithParent {"))
        #expect(patcher.contains("gtk_scrolled_window_set_max_content_height(scrolledOp, height)"))
        #expect(patcher.contains("fixed_width_flexible_height_clip = \"gtkFrameFixedWidthFlexibleHeightClip\""))
        #expect(renderer.contains("gtkFrameFixedWidthFlexibleHeightClip"))
        #expect(renderer.contains("gtk_scrolled_window_set_max_content_width(scrolledOp, width)"))
        #expect(renderer.contains("!widthMayGrowWithParent && heightMayGrowWithParent && childExpV"))
        #expect(patcher.contains("fixed_width_parent_flexible_guard = \"!widthMayGrowWithParent && heightMayGrowWithParent && childExpV\""))
        #expect(renderer.contains("gtkFrameFlexibleWidthFixedHeightClip"))
        #expect(renderer.contains("if widthMayGrowWithParent && !heightMayGrowWithParent {"))
        #expect(renderer.contains("gtk_widget_set_vexpand(child, heightMayGrowWithParent ? 1 : 0)"))
        #expect(renderer.contains("gtkSwiftVerticalFillIntentMarker"))
        #expect(renderer.contains("private func gtkMarkVerticalFillIntent"))
        #expect(renderer.contains("private func gtkHasVerticalFillIntent"))
        #expect(renderer.contains("gtkHasVerticalFillIntent(widget)"))
        #expect(renderer.contains("gtk_widget_set_vexpand(widget, 0)"))
        #expect(renderer.contains("gtkHasVerticalFillIntent(overlayWidget)"))
        #expect(renderer.contains("gtkMarkVerticalFillIntent(box)"))
        #expect(renderer.contains("gtk_widget_set_vexpand(widget, 1)\n            hasVerticalFillIntent = true"))
        #expect(renderer.contains("gtkMarkVerticalFillIntent(area)"))
        #expect(patcher.contains("gtkSwiftVerticalFillIntentMarker"))
        #expect(patcher.contains("let overlayWantsVerticalFill ="))
        #expect(patcher.contains("gtkHasVerticalFillIntent(overlayWidget)"))
        #expect(patcher.contains("gtkMarkVerticalFillIntent(box)"))
        #expect(patcher.contains("vstack_spacer_vertical_fill"))
        #expect(patcher.contains("hasVerticalFillIntent = true"))
        #expect(renderTests.contains("testZStackTopOverlayDoesNotFillHeightFromUnmarkedVExpand"))
        #expect(renderTests.contains("testZStackTopOverlayFillsHeightForExplicitFlexibleFrame"))
        #expect(renderTests.contains("GTKAccidentalVExpandOverlayProbe"))
        #expect(patcher.contains("padded_view_child_fill = \"PaddedView must let expanding content fill its margin wrapper\""))
        #expect(patcher.contains("gtk_widget_set_halign(child, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtk_widget_set_valign(child, GTK_ALIGN_FILL)"))
        #expect(renderer.contains("extension ClippedView: GTKRenderable"))
        #expect(renderer.contains("let wrapper = gtk_swift_width_clamp_new(inner)!"))
        #expect(patcher.contains("clipped_width_clamp = \"let wrapper = gtk_swift_width_clamp_new(inner)!\""))
        #expect(renderer.contains("gtk_widget_set_halign(inner, GTK_ALIGN_FILL)"))
        #expect(renderer.contains("gtk_widget_set_valign(inner, GTK_ALIGN_FILL)"))
        #expect(renderer.contains("gtk_widget_set_halign(baseWidget, GTK_ALIGN_FILL)"))
        #expect(renderer.contains("gtk_widget_set_valign(baseWidget, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)"))
        #expect(patcher.contains("gtk_widget_set_halign(row, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox, fillWidth: true, fillHeight: false)"))
        #expect(patcher.contains("private func gtkClampHiddenHorizontalScrollOffset"))
        #expect(patcher.contains("old_vertical_scroll_horizontal_guard"))
        #expect(patcher.contains("!isSwiftUIVerticalScrollView,"))
        #expect(navigation.contains("private func gtkCreateFixedSplitColumnContainer("))
        #expect(navigation.contains("gtk_scrolled_window_set_max_content_width(scrolledOp, pixelWidth)"))
        #expect(navigation.contains("gtkApplyFixedSplitColumnWidth(sidebar, width: sidebarW)"))
        #expect(navigation.contains("let sidebarWidget = gtkCreateFixedSplitColumnContainer("))
        #expect(navigation.contains("let contentWidget = gtkCreateFixedSplitColumnContainer("))
        #expect(patcher.contains("private func gtkCreateFixedSplitColumnContainer("))
        #expect(patcher.contains("gtk_scrolled_window_set_max_content_width(scrolledOp, pixelWidth)"))
        #expect(patcher.contains("gtkApplyFixedSplitColumnWidth(sidebar, width: sidebarW)"))
        #expect(patcher.contains("let sidebarWidget = gtkCreateFixedSplitColumnContainer("))
        #expect(patcher.contains("let contentWidget = gtkCreateFixedSplitColumnContainer("))
        #expect(patcher.contains("mapped_on_disappear_marker = \"GTK OnDisappear requires a prior map before firing\""))
        #expect(environment.contains("swiftOpenUIWithPresentationDismissAction"))
        #expect(environment.contains("swiftOpenUICurrentPresentationDismissAction"))
        #expect(compatibility.contains("if let contextualDismiss = swiftOpenUICurrentPresentationDismissAction()"))
        #expect(renderer.contains("let capturedPresentationDismissAction = swiftOpenUICurrentPresentationDismissAction()"))
        #expect(renderer.contains("swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction)"))
        #expect(patcher.contains("private final class GTKSheetLifecycleScope"))
        #expect(patcher.contains("swiftOpenUIWithPresentationDismissAction(dismissAction)"))
        #expect(patcher.contains("gtkWithSheetLifecycleScope(info.lifecycleScope) { info.render() }"))
        #expect(patcher.contains("gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetView) }"))
        #expect(patcher.contains("private var gtkRootSheetOverlayStack: [OpaquePointer] = []"))
        #expect(patcher.contains("private func gtkWithRootSheetOverlay<T>(_ rootOverlay: OpaquePointer, _ body: () -> T) -> T"))
        #expect(patcher.contains("private func gtkSheetRootOverlay(for anchor: UnsafeMutablePointer<GtkWidget>) -> OpaquePointer?"))
        #expect(renderer.contains("private final class GTKSheetPanelSizeContext"))
        #expect(renderer.contains("private let gtkSheetPanelSizeTickCallback"))
        #expect(renderer.contains("gtkClampedSheetPanelDimension("))
        #expect(renderer.contains("gtkInstallSheetPanelOverlaySizeClamp("))
        #expect(renderer.contains("margins: gtkSheetOverlayHorizontalMargins"))
        #expect(patcher.contains("private final class GTKSheetPanelSizeContext"))
        #expect(patcher.contains("private let gtkSheetPanelSizeTickCallback"))
        #expect(patcher.contains("gtkClampedSheetPanelDimension("))
        #expect(patcher.contains("gtkInstallSheetPanelOverlaySizeClamp("))
        #expect(patcher.contains("margins: gtkSheetOverlayHorizontalMargins"))
        #expect(patcher.contains("if let rootOverlay = gtkCurrentRootSheetOverlay()"))
        #expect(patcher.contains("if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(anchor))"))
        #expect(patcher.contains("var ancestor = gtk_widget_get_parent(anchor)"))
        #expect(patcher.contains("ancestor = gtk_widget_get_parent(current)"))
        #expect(patcher.contains("if let rootOverlay = gtkFallbackRootPresentationOverlay()"))
        #expect(patcher.occurrences(of: "let rootOverlay = gtkSheetRootOverlay(for: anchor)") == 2)
        #expect(patcher.occurrences(of: "gtkWithRootSheetOverlay(rootOverlay) {") == 2)
        #expect(patcher.contains("private func gtkCreateSheetOverlayLayer("))
        #expect(patcher.contains("applyCSSToWidget(backdrop, properties: \"background: #f8f8fb;\")"))
        #expect(patcher.occurrences(of: "gtkStoreRootPresentationOverlay(rootOverlay, on: layer)") == 2)
        #expect(patcher.occurrences(of: "gtkStoreRootPresentationOverlay(rootOverlay, on: panel)") == 2)
        #expect(patcher.occurrences(of: "gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)") == 2)
        #expect(patcher.contains("private func gtkAttachRootSheetOverlay("))
        #expect(patcher.contains("gtk_widget_insert_after(layer, overlayWidget, previousTop)"))
        #expect(patcher.occurrences(of: "gtkAttachRootSheetOverlay(layer, to: rootOverlay)") >= 2)
        #expect(patcher.contains("presentedLayer = layer"))
        #expect(patcher.contains("private var gtkRootPresentationOverlayFallback: OpaquePointer?"))
        #expect(patcher.contains("func gtkStoreRootPresentationOverlay("))
        #expect(patcher.contains("gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: widgetPointer(winPtr))"))
        #expect(patcher.contains("gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: contentWidget)"))
        #expect(patcher.contains("func gtkStoredRootPresentationOverlay(on widget: gpointer) -> OpaquePointer?"))
        #expect(patcher.contains("gtkStoredRootPresentationOverlay(on: root) ?? gtkRootPresentationOverlayFallback"))
        #expect(patcher.contains("func gtkFallbackRootPresentationOverlay() -> OpaquePointer?"))
        #expect(backend.contains("private func gtkShouldShowWindowMenuBar() -> Bool"))
        #expect(backend.contains("QUILLUI_BACKEND_SHOW_WINDOW_MENUBAR"))
        #expect(backend.contains("QUILLUI_GTK_SHOW_WINDOW_MENUBAR"))
        #expect(backend.contains("QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR"))
        #expect(backend.contains("QUILLUI_GTK_HIDE_WINDOW_MENUBAR"))
        #expect(backend.contains("gtkSetupCommandShortcutsIfNeeded(winPtr: winWidget, windowID: Int(bitPattern: winPtr))"))
        #expect(backend.contains("if !quillHidesTitleBar && gtkShouldShowWindowMenuBar()"))
        #expect(backend.occurrences(of: "if gtkShouldShowWindowMenuBar() {") == 1)
        #expect(patcher.contains("private func gtkShouldShowWindowMenuBar() -> Bool"))
        #expect(patcher.contains("QUILLUI_BACKEND_SHOW_WINDOW_MENUBAR"))
        #expect(patcher.contains("QUILLUI_GTK_SHOW_WINDOW_MENUBAR"))
        #expect(patcher.contains("QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR"))
        #expect(patcher.contains("QUILLUI_GTK_HIDE_WINDOW_MENUBAR"))
        #expect(patcher.contains("gtkSetupCommandShortcutsIfNeeded(winPtr: winWidget, windowID: Int(bitPattern: winPtr))"))
        #expect(patcher.contains("text.replace(root_content_menubar_setup, window_group_menubar_setup, 1)"))
        #expect(patcher.contains("text.replace(root_content_menubar_setup, window_menubar_setup, 1)"))
        #expect(!patcher.contains("text.replace(root_menubar_setup, root_menubar_setup_new)"))
        #expect(backend.contains("private let gtkRootPresentationOverlayKey"))
        #expect(backend.contains("func gtkCreateRootPresentationContainer("))
        #expect(backend.contains("gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: widgetPointer(winPtr))"))
        #expect(backend.contains("gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: contentWidget)"))
        #expect(backend.contains("func gtkStoredRootPresentationOverlay(on widget: gpointer) -> OpaquePointer?"))
        #expect(backend.contains("let rootContentWidget = gtkCreateRootPresentationContainer(winPtr: winPtr, contentWidget: contentWidget)"))
        #expect(backend.contains("gtk_window_set_child(winPtr, rootContentWidget)"))
        #expect(patcher.contains("sheet item root present activeKey="))
        #expect(patcher.contains("sheet item root unavailable activeKey="))
        #expect(patcher.contains("if gtkShouldRenderSheetInWindow() {\n            let sheetBuilder = sheetContent"))
        #expect(!patcher.contains("if gtkShouldRenderSheetInWindow() || gtkShouldRenderSheetInRootOverlay()"))
        #expect(patcher.occurrences(of: "env.dismiss = DismissAction(handler: dismissAction)") >= 4)
        #expect(patcher.occurrences(of: "gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetBuilder(currentItem)) }") == 2)
        #expect(patcher.contains("lifecycleScope.runDisappearActions()"))
        #expect(patcher.contains("sheetLifecycleScope.registerOnDisappear(boundAction)"))
        #expect(patcher.contains("gtkInstallSheetPanelFocusBridge(on: panel)"))
        #expect(patcher.contains("gtkScheduleFirstSheetEditableFocus(in: panel)"))
        #expect(patcher.contains("gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY)"))
        #expect(patcher.contains("gtkScheduleSheetEditableFocus(editable)"))
        #expect(patcher.contains("gtkFocusSheetEditableWidget(editable)"))
        #expect(patcher.contains("private final class GTKSheetEditableFocusTarget"))
        #expect(patcher.contains("private final class GTKSheetPanelFocusTarget"))
        #expect(patcher.contains("gtk_editable_get_delegate(OpaquePointer(widget))"))
        #expect(patcher.contains("gtkScheduleSheetEditableFocus(delegateWidget)"))
        #expect(patcher.contains("gtk_widget_set_can_target(widget, 1)\n    gtk_widget_set_can_focus(widget, 1)\n    gtk_widget_set_focusable(widget, 1)"))
        #expect(patcher.contains("gtk_widget_set_can_target(delegateWidget, 1)\n        gtk_widget_set_can_focus(delegateWidget, 1)\n        gtk_widget_set_focusable(delegateWidget, 1)"))
        #expect(patcher.contains("gtk_widget_set_can_target(target.widget, 1)\n        gtk_widget_set_can_focus(target.widget, 1)\n        gtk_widget_set_focusable(target.widget, 1)"))
        #expect(patcher.contains("gtkFindFirstSheetEditable(in: target.panel)"))
        #expect(patcher.contains("g_idle_add({ userData -> gboolean in"))
        #expect(patcher.contains("gtk_swift_widget_is_topmost_at_root_point(root, widget, rootX, rootY)"))
        #expect(patcher.contains("gtk_swift_widget_is_editable(widget)"))
        #expect(patcher.contains("gtk_swift_root_grab_focus(widget)"))
        #expect(patcher.contains("gtk_swift_root_grab_focus(delegateWidget)"))
        #expect(patcher.contains("var hasMapped: Bool = false"))
        #expect(patcher.contains("guard box.hasMapped else { return }"))
    }

    @Test("Completions screenshot verifier requires trailing controls")
    func completionsScreenshotVerifierRequiresTrailingControls() throws {
        let verifier = try packageSource("scripts/verify-backend-screenshot.py")

        #expect(verifier.contains("require_sidebar_footer_navigation: bool = True"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_new_chat"))
        #expect(verifier.contains("validate_quill_chat_mac_reference(image, require_sidebar_footer_navigation=False)"))
        #expect(verifier.contains("print(validate_quill_chat_mac_reference_new_chat(image))"))
        #expect(verifier.contains("def mac_reference_completion_action_pixel"))
        #expect(verifier.contains("def dark_row_segment_count"))
        #expect(verifier.contains("Mac-reference completions Close control was not detected"))
        #expect(verifier.contains("Mac-reference completions New Completion action was not detected"))
        #expect(verifier.contains("Mac-reference completions row edit/delete actions were not detected"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_panel_visible"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_panel_visible(image: Screenshot) -> str:\n    return validate_quill_chat_mac_reference_completions_panel(\n        image,\n        minimum_row_dividers=2,\n        minimum_wordmark_pixels=350,"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_new_sheet"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_saved"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_edited"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_edited(image: Screenshot) -> str:\n    panel_summary = validate_quill_chat_mac_reference_completions_panel(\n        image,\n        minimum_row_dividers=2,\n        minimum_wordmark_pixels=350,"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_deleted"))
        #expect(verifier.contains("Completions Upsert Cancel action was not detected"))
        #expect(verifier.contains("Completions Upsert Save action was not detected"))
        #expect(verifier.contains("Completions Upsert preview chip was not detected"))
        #expect(verifier.contains("Saved completion row was not detected"))
        #expect(verifier.contains("Edited completion row name was not detected above the stock row baseline"))
        #expect(verifier.contains("Completions sheet still appears to be visible after Delete"))
        #expect(verifier.contains("Stock completion rows were not restored after deleting the generated completion"))
        #expect(verifier.contains("Completions Upsert sheet still appears to be visible after Save"))
        #expect(verifier.contains("Completions edit sheet still appears to be visible after Save"))
        #expect(verifier.contains("close_pixels >= 60"))
        #expect(verifier.contains("new_completion_pixels >= 120"))
        #expect(verifier.contains("minimum_row_action_segments: int = 4"))
        #expect(verifier.contains("top + int(app_height * 0.345)"))
        #expect(verifier.contains("row_action_segments >= minimum_row_action_segments"))
        #expect(verifier.contains("minimum_wordmark_pixels: int = 650"))
        #expect(verifier.contains("wordmark_pixels >= minimum_wordmark_pixels"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-completions-panel-visible"))
        #expect(verifier.contains("panel_surface_pixels >= 32_000"))
        #expect(verifier.contains("minimum_row_dividers=0"))
        #expect(verifier.contains("minimum_row_action_segments=1"))
        #expect(verifier.contains("minimum_row_dividers=2"))
        #expect(verifier.contains("minimum_row_action_segments=4"))
        #expect(verifier.contains("minimum_wordmark_pixels=350"))
        #expect(verifier.contains("cancel_pixels >= 90"))
        #expect(verifier.contains("save_pixels >= 90"))
        #expect(verifier.contains("dismissed_sheet_field_pixels <= 12_000"))
        #expect(verifier.contains("root_title_pixels >= 400"))
        #expect(verifier.contains("saved_row_pixels >= 260"))
        #expect(verifier.contains("edited_row_name_pixels >= 240"))
        #expect(verifier.contains("top + int(app_height * 0.335)"))
        #expect(verifier.contains("top + int(app_height * 0.39)"))
        #expect(verifier.contains("top + int(app_height * 0.49)"))
        #expect(verifier.contains("top + int(app_height * 0.57)"))
        #expect(verifier.contains("deleted_row_action_segments = dark_row_segment_count"))
        #expect(verifier.contains("deleted_row_action_segments >= 4"))
        #expect(!verifier.contains("deleted_row_action_segments <= 3"))
    }

    @Test("Vendored GTK renderer preserves SwiftUI scroll row width contract")
    func vendoredGTKRendererPreservesSwiftUIScrollRowWidthContract() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let scrollView = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/ScrollView.swift")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(scrollView.contains("public let showsIndicators: Bool"))
        #expect(scrollView.contains("self.showsIndicators = true"))
        #expect(scrollView.contains("self.showsIndicators = showsIndicators"))
        #expect(renderer.contains("private final class GTKScrollViewCrossAxisContext"))
        #expect(renderer.contains("gtkScrollViewCrossAxisTickCallback"))
        #expect(renderer.contains("private func gtkClampHiddenHorizontalScrollOffset"))
        #expect(renderer.contains("if context.fillWidth {\n        gtkClampHiddenHorizontalScrollOffset(widget)\n    }"))
        #expect(renderer.contains("gtkInstallScrollViewCrossAxisFill("))
        #expect(renderer.contains("let horizontalMargins = gtk_widget_get_margin_start(context.child)"))
        #expect(renderer.contains("gtk_widget_get_margin_end(context.child)"))
        #expect(renderer.contains("gtk_widget_set_size_request(context.child, max(gint(1), width - horizontalMargins), -1)"))
        #expect(renderer.contains("let verticalMargins = gtk_widget_get_margin_top(context.child)"))
        #expect(renderer.contains("gtk_widget_get_margin_bottom(context.child)"))
        #expect(renderer.contains("gtk_widget_set_size_request(context.child, -1, max(gint(1), height - verticalMargins))"))
        #expect(renderer.contains("SwiftUI lays vertical ScrollView content out in the viewport"))
        #expect(renderer.contains("A horizontal-only SwiftUI ScrollView has the natural height of"))
        #expect(renderer.contains("let childWantsVerticalFill = gtkHasVerticalFillIntent(child)"))
        #expect(renderer.contains("gtk_widget_set_vexpand(child, childWantsVerticalFill ? 1 : 0)"))
        #expect(renderer.contains("gtk_widget_set_valign(child, childWantsVerticalFill ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER)"))
        #expect(renderer.contains("gtk_scrolled_window_set_min_content_width(scrolledOp, 1)"))
        #expect(renderer.contains("gtk_scrolled_window_set_min_content_height(scrolledOp, 1)"))
        #expect(patcher.contains("SwiftOpenUI ScrollView natural-size clamp shape was not recognized"))
        #expect(patcher.contains("gtk_scrolled_window_set_min_content_width(scrolledOp, 1)"))
        #expect(patcher.contains("gtk_scrolled_window_set_min_content_height(scrolledOp, 1)"))
        #expect(renderer.contains("private func gtkCompressibleHeightClamp"))
        #expect(renderer.contains("private func gtkCompressibleProposalClamp"))
        #expect(renderer.contains("gtk_swift_compressible_height_clamp_new(child)"))
        #expect(renderer.contains("for originalWidget in children {\n        var widget = originalWidget"))
        #expect(renderer.contains("widget = gtkCompressibleHeightClamp(widget)"))
        #expect(renderer.contains("return opaqueFromWidget(gtkCompressibleProposalClamp(box))"))
        #expect(patcher.contains("gtk_swift_compressible_height_clamp_new"))
        #expect(patcher.contains("SwiftOpenUI GTK compressible width clamp insertion point was not recognized"))
        #expect(patcher.contains("SwiftOpenUI VStack compressible-child loop shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI GeometryReader return shape was not recognized"))
        #expect(renderer.contains("let visibleScrollPolicy: GtkPolicyType = showsIndicators ? GTK_POLICY_AUTOMATIC : GTK_POLICY_EXTERNAL"))
        #expect(renderer.contains("fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal)"))
        #expect(renderer.contains("let scrollerWantsVerticalFill = axes.contains(.vertical)"))
        #expect(renderer.contains("gtk_widget_set_vexpand(scrolled, scrollerWantsVerticalFill ? 1 : 0)"))
        #expect(renderer.contains("gtkMarkVerticalFillIntent(scrolled)"))
        #expect(renderer.contains("GTK_POLICY_EXTERNAL,\n        GTK_POLICY_EXTERNAL"))
        #expect(renderer.contains("gtk_scrolled_window_set_has_frame(OpaquePointer(scrolled), 0)"))
        #expect(renderer.contains("private let gtkStaticLazyStackItemLimit = 64"))
        #expect(renderer.contains("private func gtkCreateStaticLazyStackWidget"))
        #expect(renderer.contains("items.count <= gtkStaticLazyStackItemLimit"))
        #expect(renderer.contains("orientation: GTK_ORIENTATION_HORIZONTAL"))
        #expect(renderer.contains("gtk_widget_set_vexpand(scrolled, orientation == GTK_ORIENTATION_VERTICAL ? 1 : 0)"))
        #expect(renderer.contains("gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)"))
        #expect(renderer.contains("SwiftUI lays repeated vertical rows against the parent's"))
        #expect(renderer.contains("gtk_widget_set_hexpand(widget, 1)"))
        #expect(renderer.contains("gtk_widget_set_halign(widget, GTK_ALIGN_FILL)"))
    }

    @Test("Vendored SwiftOpenUI localization handles IceCubes top-level plural catalogs")
    func vendoredSwiftOpenUILocalizationHandlesIceCubesTopLevelPluralCatalogs() throws {
        let localization = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Localization.swift")
        let localizationTests = try packageSource("third_party/SwiftOpenUI/Tests/SwiftOpenUITests/LocalizationTests.swift")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(localization.contains("let pluralName = \"__quill_plural\""))
        #expect(localization.contains("template = LocalizedTemplate(value: \"%#@\\(pluralName)@\")"))
        #expect(localization.contains("var argumentIndex: Int?"))
        #expect(localization.contains("pluralSubstitution.argumentIndex = substitutionArgumentIndex(substitution[\"argNum\"])"))
        #expect(localization.contains("private func substitutionArgumentIndex(_ value: Any?) -> Int?"))
        #expect(localization.contains("private func pluralSubstitution(in plural: [String: Any]) -> PluralSubstitution"))
        #expect(localization.contains("zero: pluralString(in: plural[\"zero\"])"))
        #expect(localization.contains("many: pluralString(in: plural[\"many\"])"))
        #expect(localization.contains("let argumentIndex = substitution.argumentIndex ?? 0"))
        #expect(localization.contains("replacement = substitution.zero ?? substitution.other ?? substitution.one"))
        #expect(localization.contains("replacement = substitution.other ?? substitution.many ?? substitution.few ?? substitution.one"))
        #expect(localization.contains("formatPluralReplacement(replacement, argument: argument, arguments: arguments)"))
        #expect(localization.contains("replacement.replacingOccurrences(of: \"%arg\", with: argument)"))

        #expect(localizationTests.contains("testTopLevelPluralVariationCatalogEntryFormatsFlattenedInterpolation"))
        #expect(localizationTests.contains("testPluralCatalogSubstitutionUsesArgNumAndArgToken"))
        #expect(localizationTests.contains("\"status.summary.n-favorites %lld\""))
        #expect(localizationTests.contains("\"design.tag.n-posts-from-n-participants %lld %lld\""))
        #expect(localizationTests.contains("Text(\"status.summary.n-favorites 42\").content"))
        #expect(localizationTests.contains("\"42 favorites\""))
        #expect(localizationTests.contains("\"146 posts from 45 participants\""))

        #expect(patcher.contains("LOCALIZATION=\"$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Localization.swift\""))
        #expect(patcher.contains("SwiftOpenUI localization plural substitution shape was not recognized"))
        #expect(patcher.contains("var argumentIndex: Int?"))
        #expect(patcher.contains("substitutionArgumentIndex(substitution[\"argNum\"])"))
        #expect(patcher.contains("private func formatPluralReplacement(_ replacement: String, argument: String, arguments: [String]) -> String"))
        #expect(patcher.contains("let pluralName = \"__quill_plural\""))
        #expect(patcher.contains("SwiftOpenUI plural category selection shape was not recognized"))
    }

    @Test("Vendored GTK renderer applies SwiftUI form row metadata")
    func vendoredGTKRendererAppliesSwiftUIFormRowMetadata() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let rowModifiers = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/ListRowModifiers.swift")
        let designCompat = try packageSource("Sources/QuillSwiftUICompatibility/IceCubesDesignSystemModifiers.swift")
        let quillCompat = try packageSource("Sources/QuillUI/UpstreamCompatibility.swift")

        #expect(rowModifiers.contains("public protocol ListRowInsetsProvider"))
        #expect(rowModifiers.contains("public protocol ListRowSeparatorProvider"))
        #expect(rowModifiers.contains("public struct ListRowInsetsView<Content: View>: View, ListRowInsetsProvider"))
        #expect(rowModifiers.contains("public struct ListRowSeparatorView<Content: View>: View, ListRowSeparatorProvider"))
        #expect(renderer.contains("private func gtkRowMetadata(from view: any View) -> GTKRowMetadata"))
        #expect(renderer.contains("private func gtkDirectChildViews<V: View>(of view: V, depth: Int = 0) -> [any View]"))
        #expect(renderer.contains("if mirror.displayStyle == .optional"))
        #expect(renderer.contains("String(reflecting: Swift.type(of: view)).contains(\"_ConditionalView\")"))
        #expect(renderer.contains("private func gtkFormChildViews<V: View>(of view: V, depth: Int = 0) -> [any View]"))
        #expect(renderer.contains("private func gtkFlattenSectionProducingTypedFormChild<V: View>(_ view: V, depth: Int) -> [any View]"))
        #expect(renderer.contains("if V.Body.self != Never.self, gtkViewTypeNameSuggestsFormSectionProducer(view)"))
        #expect(renderer.contains("if bodyChildren.contains(where: gtkIsSectionView)"))
        #expect(renderer.contains("private func gtkViewTypeNameSuggestsFormSectionProducer(_ view: any View) -> Bool"))
        #expect(renderer.contains("typeName.hasSuffix(\"Section\")"))
        #expect(renderer.contains("typeName.hasSuffix(\"Sections\")"))
        #expect(renderer.contains("if let insetsProvider = value as? any ListRowInsetsProvider"))
        #expect(renderer.contains("if let separatorProvider = value as? any ListRowSeparatorProvider"))
        #expect(renderer.contains("private func gtkRenderRowContent("))
        #expect(renderer.contains("private func gtkViewIsPlainTextRow"))
        #expect(renderer.contains("if mirror.displayStyle == .optional"))
        #expect(renderer.contains("if mirror.displayStyle == .enum"))
        #expect(renderer.contains("if value is any MultiChildView { return false }"))
        #expect(renderer.contains("gtkPrepareRowTextLabel(label, text: displayContent)"))
        #expect(renderer.contains("private let gtkRowLabelWrapThreshold = 40"))
        #expect(renderer.contains("private let gtkRowLabelMaxWidthChars: gint = 88"))
        #expect(renderer.contains("private var gtkRowTextRenderContextStack: [Bool] = []"))
        #expect(renderer.contains("private var gtkIsRenderingRowContent: Bool"))
        #expect(renderer.contains("if !gtkIsRenderingRowContent, gtkCanUseSharedVStackLayout(children)"))
        #expect(renderer.contains("if !gtkIsRenderingRowContent, gtkCanUseSharedHStackLayout(children)"))
        #expect(renderer.contains("if !gtkIsRenderingRowContent, gtkCanUseSharedZStackLayout(children)"))
        #expect(renderer.contains("private func gtkWithRowTextRenderContext"))
        #expect(renderer.contains("private func gtkPrepareRowTextLabel"))
        #expect(renderer.contains("guard let includeShortPlainText = gtkRowTextRenderContextStack.last else { return }"))
        #expect(renderer.contains("private func gtkConstrainRowTextLabels"))
        #expect(renderer.contains("if existingLines == 1"))
        #expect(renderer.contains("if !includeShortPlainText && text.count < gtkRowLabelWrapThreshold"))
        #expect(renderer.contains("gtk_label_set_width_chars(labelOp, gtkRowLabelMaxWidthChars)"))
        #expect(renderer.contains("gtk_label_set_max_width_chars(labelOp, gtkRowLabelMaxWidthChars)"))
        #expect(renderer.contains("let includeShortPlainText = gtkViewIsPlainTextRow(view)"))
        #expect(renderer.contains("let child = gtkWithRowTextRenderContext(includeShortPlainText: includeShortPlainText)"))
        #expect(renderer.contains("gtkConstrainRowTextLabels(child, includeShortPlainText: includeShortPlainText)"))
        #expect(renderer.contains("gtk_widget_set_vexpand(child, 0)"))
        #expect(renderer.contains("gtk_widget_set_valign(child, GTK_ALIGN_START)"))
        #expect(renderer.contains("private final class GTKRowWidthContext"))
        #expect(renderer.contains("gtkRowWidthTickCallback"))
        #expect(renderer.contains("private func gtkInstallRowWidthFill("))
        #expect(renderer.contains("gtk_widget_set_size_request(context.child, max(gint(1), width - horizontalMargins), -1)"))
        #expect(renderer.contains("gtk_widget_set_margin_start(child, gint(insets.leading))"))
        #expect(renderer.contains("gtk_widget_set_margin_end(child, gint(insets.trailing))"))
        #expect(renderer.contains("let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!"))
        #expect(renderer.contains("gtk_box_append(boxPointer(wrapper), child)"))
        #expect(renderer.contains("gtkInstallRowWidthFill(on: wrapper, child: child)"))
        #expect(renderer.contains("gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)"))
        #expect(renderer.contains("let clampedBox = gtk_swift_width_clamp_new(box)!"))
        #expect(renderer.contains("let viewport = gtk_swift_min_width_viewport_new(clampedBox)!"))
        #expect(renderer.contains("gtk_scrolled_window_set_child(scrolledOp, viewport)"))
        #expect(renderer.contains("gtkInstallScrollViewCrossAxisFill(on: scrolled, child: viewport, fillWidth: true, fillHeight: false)"))
        #expect(renderer.contains("gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)"))
        #expect(renderer.contains("gtk_widget_set_margin_start(scrolled, 16)"))
        #expect(renderer.contains("gtk_widget_set_margin_end(scrolled, 16)"))
        #expect(renderer.contains("gtkAppendRows(gtkDirectChildViews(of: content), to: rows)"))
        #expect(renderer.contains("for child in gtkFormChildViews(of: content)"))
        #expect(renderer.contains("if gtkIsSectionView(child)"))
        #expect(renderer.contains("reflectedTypeName.contains(\"SwiftOpenUI.Section<\")"))
        #expect(renderer.contains(".swiftopenui-list row.separator-hidden { border-bottom: none; }"))
        #expect(!designCompat.contains("func listRowInsets(_ insets: EdgeInsets?) -> Self"))
        #expect(!designCompat.contains("func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> Self"))
        #expect(quillCompat.contains("@_disfavoredOverload\n    func listRowInsets(_ insets: EdgeInsets?) -> SwiftOpenUI.ListRowInsetsView<Self>"))
        #expect(quillCompat.contains("@_disfavoredOverload\n    func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> SwiftOpenUI.ListRowSeparatorView<Self>"))
    }

    @Test("Upstream IceCubes visual smoke is a first-class Linux artifact")
    func upstreamIceCubesVisualSmokeIsFirstClassLinuxArtifact() throws {
        let script = try packageSource("scripts/icecubes-linux-visual-check.sh")
        let verifier = try packageSource("scripts/verify-backend-screenshot.py")
        let workflow = try packageSource(".github/workflows/linux-ci.yml")
        let parityLog = try packageSource("docs/icecubes-behavior-parity.md")
        let quillKit = try packageSource("Sources/QuillKit/QuillKit.swift")
        let package = try packageSource("Package.swift")
        let fetchUpstream = try packageSource("scripts/fetch-upstream.sh")
        let seedMain = try packageSource("Sources/IceCubesSeedAccount/main.swift")
        let designSystemCompat = try packageSource("Sources/QuillSwiftUICompatibility/DesignSystemSurfaceCompat.swift")
        let refreshModifier = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/RefreshableModifier.swift")
        let swiftOpenUILayout = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Layout/Layout.swift")
        let compatibilityModuleTests = try packageSource("Tests/QuillCompatibilityModuleTests/CompatibilityModuleTests.swift")
        let mastodonFixtures = try packageSource("Tests/Fixtures/IceCubes/mastodon-fixtures.json")
        let textLayoutCompat = try packageSource("Sources/QuillSwiftUICompatibility/TextLayoutCompat.swift")
        let toolbarModifier = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/ToolbarModifier.swift")
        let navigationStack = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Navigation/NavigationStack.swift")
        let asyncImage = try packageSource("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/AsyncImage.swift")
        let gtkNavigation = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKNavigation.swift")
        let gtkRenderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let gtkViewHost = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKViewHost.swift")
        let gtkDescriptorTree = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4DescriptorTree.swift")
        let gtkShim = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/CGTK/shim.h")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(script.contains("QUILLUI_ICECUBES=1"))
        #expect(script.contains("--product icecubes-linux-app"))
        #expect(script.contains("--product icecubes-seed-account"))
        #expect(script.contains("verify-backend-screenshot.py\" \"$SCREENSHOT_PATH\" \"$VERIFY_PRODUCT\""))
        #expect(script.contains("quillui_install_linux_backend_smoke_packages"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_SCROLL_CLICKS"))
        #expect(script.contains("xdotool mousemove \"$SCROLL_X\" \"$SCROLL_Y\" click 5"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_TYPE_INSTANCE_KEYS"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_TYPE_FOCUS_SETTLE_SECONDS"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_TYPE_KEY_DELAY_MS"))
        #expect(script.contains("xdotool key --delay \"$TYPE_KEY_DELAY_MS\" --clearmodifiers"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_INITIAL_SETTLE_SECONDS"))
        #expect(script.contains("WINDOW_TRACE=\"${QUILLUI_ICECUBES_VISUAL_TRACE_WINDOWS:-0}\""))
        #expect(script.contains("trace_visual_window \"final-capture\" \"$capture_window_id\""))
        #expect(script.contains("Fixture-backed URLProtocol tasks can trip a Linux FoundationNetworking"))
        #expect(script.contains("SETTLE_SECONDS=\"0\""))
        #expect(script.contains("timeout 10 import -window"))
        #expect(script.contains("IceCubes app exited before screenshot capture."))
        #expect(script.contains("Tests/Fixtures/IceCubes/mastodon-fixtures.json"))
        #expect(script.contains("QUILLUI_URLSESSION_FIXTURES_FILE=$DEFAULT_URLSESSION_FIXTURES_FILE"))
        #expect(script.contains("QUILLUI_URLSESSION_FIXTURES_DEBUG=1"))
        #expect(mastodonFixtures.contains("\"media-home-1003\""))
        #expect(mastodonFixtures.contains("\"https://files.mastodon.social/media_attachments/home-1003.png\""))
        #expect(mastodonFixtures.contains("\"pathPrefix\": \"/media_attachments/\""))
        #expect(!designSystemCompat.contains("public struct LayoutContainer"))
        #expect(swiftOpenUILayout.contains("public struct LayoutContainer"))
        #expect(swiftOpenUILayout.contains("layout.sizeThatFits("))
        #expect(swiftOpenUILayout.contains("LayoutSubviews([LayoutSubview(index: 0)])"))
        #expect(swiftOpenUILayout.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        #expect(swiftOpenUILayout.contains(".frame(width: size.width, height: size.height, alignment: .topLeading)"))
        #expect(compatibilityModuleTests.contains("swiftUICustomLayoutContainersApplyMeasuredSize"))
        #expect(compatibilityModuleTests.contains("compatibilityOptionalDoubleValue"))
        #expect(asyncImage.contains("let fileExtension = url.pathExtension"))
        #expect(asyncImage.contains("+ (fileExtension.isEmpty ? \"\" : \".\\(fileExtension)\")"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-add-account-instance\""))
        #expect(script.contains("sign-in-open)"))
        #expect(script.contains("QUILLUI_OPEN_URL_LOG_FILE=$OPEN_URL_LOG_PATH"))
        #expect(script.contains("QUILLUI_OPEN_URL_LOG_ASSUME_HANDLED=1"))
        #expect(script.contains("verify_oauth_open_url_log"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_SIGN_IN_OPEN_TIMEOUT_SECONDS"))
        #expect(script.contains("wait_for_oauth_open_url_log"))
        #expect(script.contains("redirect_uri\") == [\"icecubesapp://\"]"))
        #expect(script.contains("{\"read\", \"write\", \"follow\", \"push\"}.issubset(scope)"))
        #expect(script.contains("seeded-authenticated-shell)"))
        #expect(script.contains("QUILLUI_KEYCHAINSWIFT_STORE_PATH=\"$KEYCHAIN_STORE_PATH\""))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-shell\""))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_COMPOSER_SEND_X"))
        #expect(script.contains("seeded-authenticated-composer-submit)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-composer-submitted\""))
        #expect(script.contains("icecubes-linux-authenticated-composer\" 2>&1"))
        #expect(script.contains("wait_for_authenticated_composer_dismissal"))
        #expect(script.contains("wait_for_authenticated_route_visual \"$VERIFY_PRODUCT\" \"authenticated composer submitted shell\""))
        #expect(script.contains("authenticated composer status create"))
        #expect(script.contains("seeded-authenticated-trending)"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_TRENDING_X"))
        #expect(script.contains("AUTH_TRENDING_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_TRENDING_Y:-117}\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/trends/statuses\""))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-trending\""))
        #expect(script.contains("seeded-authenticated-local)"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_LOCAL_X"))
        #expect(script.contains("AUTH_LOCAL_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_LOCAL_Y:-156}\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/timelines/public?local=true&limit=50\""))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-local\""))
        #expect(script.contains("seeded-authenticated-federated)"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_FEDERATED_X"))
        #expect(script.contains("AUTH_FEDERATED_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_FEDERATED_Y:-195}\""))
        #expect(script.contains("AUTH_EXPLORE_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_Y:-273}\""))
        #expect(script.contains("AUTH_EXPLORE_LINKS_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_LINKS_X:-308}\""))
        #expect(script.contains("AUTH_EXPLORE_LINKS_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_LINKS_Y:-128}\""))
        #expect(script.contains("AUTH_EXPLORE_POSTS_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_POSTS_X:-406}\""))
        #expect(script.contains("AUTH_EXPLORE_POSTS_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_POSTS_Y:-128}\""))
        #expect(script.contains("AUTH_EXPLORE_SUGGESTED_USERS_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SUGGESTED_USERS_X:-545}\""))
        #expect(script.contains("AUTH_EXPLORE_SUGGESTED_USERS_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SUGGESTED_USERS_Y:-94}\""))
        #expect(script.contains("AUTH_EXPLORE_TAGS_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_TAGS_X:-682}\""))
        #expect(script.contains("AUTH_EXPLORE_TAGS_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_TAGS_Y:-94}\""))
        #expect(script.contains("AUTH_NOTIFICATIONS_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_NOTIFICATIONS_Y:-312}\""))
        #expect(script.contains("AUTH_PROFILE_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_PROFILE_Y:-430}\""))
        #expect(script.contains("AUTH_MESSAGES_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_Y:-390}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_SCROLL_CLICKS=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_SCROLL_CLICKS:-6}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_X:-405}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_Y:-365}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_FONT_SCALE_START_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_SCALE_START_X:-526}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_FONT_SCALE_END_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_SCALE_END_X:-620}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_FONT_SCALE_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_SCALE_Y:-592}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_X:-289}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_SYSTEM_COLOR_Y:-293}\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/timelines/public?local=false&limit=50\""))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-federated\""))
        #expect(script.contains("seeded-authenticated-explore)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-explore\""))
        #expect(script.contains("open_authenticated_explore_route()"))
        #expect(script.contains("wait_for_authenticated_home_row_visual"))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/suggestions\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/trends/tags\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/trends/links\""))
        #expect(script.contains("authenticated Explore trending posts"))
        #expect(script.contains("seeded-authenticated-explore-links)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-explore-links\""))
        #expect(script.contains("click_app_window_point \"$AUTH_EXPLORE_LINKS_X\" \"$AUTH_EXPLORE_LINKS_Y\""))
        #expect(script.contains("authenticated Explore Links quick-access route"))
        #expect(script.contains("seeded-authenticated-explore-posts)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-explore-posts\""))
        #expect(script.contains("click_app_window_point \"$AUTH_EXPLORE_POSTS_X\" \"$AUTH_EXPLORE_POSTS_Y\""))
        #expect(script.contains("authenticated Explore Trending Posts quick-access route"))
        #expect(script.contains("seeded-authenticated-explore-tags)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-explore-tags\""))
        #expect(script.contains("click_app_window_point \"$AUTH_EXPLORE_TAGS_X\" \"$AUTH_EXPLORE_TAGS_Y\""))
        #expect(script.contains("authenticated Explore Tags quick-access route"))
        #expect(script.contains("seeded-authenticated-explore-suggested-users)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-explore-suggested-users\""))
        #expect(script.contains("click_app_window_point \"$AUTH_EXPLORE_SUGGESTED_USERS_X\" \"$AUTH_EXPLORE_SUGGESTED_USERS_Y\""))
        #expect(script.contains("authenticated Explore Suggested Users relationships"))
        #expect(script.contains("authenticated Explore Suggested Users quick-access route"))
        #expect(script.contains("seeded-authenticated-explore-search)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-explore-search\""))
        #expect(script.contains("AUTH_EXPLORE_SEARCH_KEYS=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_KEYS:-q u i l l}\""))
        #expect(script.contains("AUTH_EXPLORE_SEARCH_FOCUS_SETTLE_SECONDS=\"${QUILLUI_ICECUBES_VISUAL_AUTH_EXPLORE_SEARCH_FOCUS_SETTLE_SECONDS:-0.6}\""))
        #expect(script.contains("type_authenticated_explore_search_text"))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v2/search?q=quill&resolve=true\""))
        #expect(script.contains("authenticated Explore search account relationships"))
        #expect(script.contains("seeded-authenticated-profile)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-profile\""))
        #expect(script.contains("wait_for_authenticated_route_visual \"$VERIFY_PRODUCT\" \"authenticated Profile route\""))
        #expect(script.contains("seeded-authenticated-messages)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-messages\""))
        #expect(script.contains("AUTH_MESSAGES_ENDPOINT=\"/api/v1/conversations\""))
        #expect(script.contains("AUTH_MESSAGES_CLICK_RETRIES=\"${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_CLICK_RETRIES:-5}\""))
        #expect(script.contains("AUTH_MESSAGES_CLICK_RETRY_SECONDS=\"${QUILLUI_ICECUBES_VISUAL_AUTH_MESSAGES_CLICK_RETRY_SECONDS:-0.75}\""))
        #expect(script.contains("open_authenticated_messages_route()"))
        #expect(script.contains("click_authenticated_messages_sidebar_row()"))
        #expect(script.contains("click_authenticated_messages_sidebar_row \"$expected_conversations_count\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"$AUTH_MESSAGES_ENDPOINT\" \"authenticated Messages sidebar navigation\""))
        #expect(script.contains("seeded-authenticated-messages-refresh)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-messages-refresh\""))
        #expect(script.contains("trigger_authenticated_refresh_shortcut \\\n      \"$AUTH_MESSAGES_ENDPOINT\""))
        #expect(script.contains("authenticated Messages sidebar navigation"))
        #expect(script.contains("AUTH_MESSAGES_DETAIL_READ_LOG=\"[QuillURLSessionFixtures] direct POST https://mastodon.social/api/v1/conversations/conversation-1001/read\""))
        #expect(script.contains("AUTH_MESSAGES_DETAIL_CONTEXT_LOG=\"[QuillURLSessionFixtures] direct GET https://mastodon.social/api/v1/statuses/conversation-status-1001/context\""))
        #expect(script.contains("open_authenticated_messages_detail_route()"))
        #expect(script.contains("seeded-authenticated-messages-detail)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-messages-detail\""))
        #expect(script.contains("authenticated Messages detail mark-read"))
        #expect(script.contains("authenticated Messages detail context fetch"))
        #expect(script.contains("AUTH_LIST_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_X:-32}\""))
        #expect(script.contains("AUTH_LIST_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_Y:-586}\""))
        #expect(script.contains("AUTH_LIST_REPAINT_SETTLE_SECONDS=\"${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_REPAINT_SETTLE_SECONDS:-8}\""))
        #expect(script.contains("AUTH_LIST_CLICK_RETRIES=\"${QUILLUI_ICECUBES_VISUAL_AUTH_LIST_CLICK_RETRIES:-5}\""))
        #expect(script.contains("AUTH_LIST_ENDPOINT=\"/api/v1/timelines/list/list-quill-core\""))
        #expect(script.contains("AUTH_LIST_PAGINATION_ENDPOINT=\"${AUTH_LIST_ENDPOINT}?max_id=list-9002\""))
        #expect(script.contains("click_authenticated_list_sidebar_row"))
        #expect(script.contains("open_authenticated_list_route()"))
        #expect(script.contains("seeded-authenticated-list)"))
        #expect(script.contains("seeded-authenticated-list-refresh)"))
        #expect(script.contains("seeded-authenticated-list-pagination)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-list\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/lists\" \"authenticated Lists bootstrap\" 1"))
        #expect(script.contains("wait_for_authenticated_api_activity \"$AUTH_LIST_ENDPOINT\" \"authenticated List sidebar navigation\""))
        #expect(script.contains("trigger_authenticated_refresh_shortcut \\\n      \"$AUTH_LIST_ENDPOINT\""))
        #expect(script.contains("authenticated List refresh"))
        #expect(script.contains("wait_for_authenticated_api_activity \"$AUTH_LIST_PAGINATION_ENDPOINT\" \"authenticated List timeline pagination\""))
        #expect(script.contains("open_authenticated_settings_route()"))
        #expect(script.contains("scroll_authenticated_settings_content()"))
        #expect(script.contains("open_authenticated_settings_display_route()"))
        #expect(script.contains("drag_authenticated_settings_display_font_scale()"))
        #expect(script.contains("select_authenticated_settings_display_font_picker()"))
        #expect(script.contains("toggle_authenticated_settings_display_system_color()"))
        #expect(script.contains("seeded-authenticated-settings-display)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-settings-display\""))
        #expect(script.contains("click_app_window_point \"$AUTH_SETTINGS_DISPLAY_X\" \"$AUTH_SETTINGS_DISPLAY_Y\""))
        #expect(script.contains("authenticated Settings Display route"))
        #expect(script.contains("seeded-authenticated-settings-display-font-scale)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-settings-display-font-scale\""))
        #expect(script.contains("authenticated Settings Display font-scale mutation"))
        #expect(script.contains("seeded-authenticated-settings-display-font-picker)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-settings-display-font-picker\""))
        #expect(script.contains("authenticated Settings Display font-picker route"))
        #expect(script.contains("seeded-authenticated-settings-display-font-picker-select)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-settings-display-font-picker-selected\""))
        #expect(script.contains("authenticated Settings Display font-picker selected dismissal"))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEYS=\"${QUILLUI_ICECUBES_VISUAL_AUTH_SETTINGS_DISPLAY_FONT_PICKER_KEYS:-End Return}\""))
        #expect(script.contains("AUTH_SETTINGS_DISPLAY_FONT_PICKER_INTER_X"))
        #expect(script.contains("seeded-authenticated-settings-display-system-color)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-settings-display-system-color\""))
        #expect(script.contains("authenticated Settings Display system-color mutation"))
        #expect(verifier.contains("def validate_icecubes_linux_add_account"))
        #expect(verifier.contains("def validate_icecubes_linux_add_account_instance"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_shell"))
        #expect(verifier.contains("icecubes_sign_in_button_pixel"))
        #expect(verifier.contains("neutral_placeholder"))
        #expect(verifier.contains("top_left_blank_artifact_pixels"))
        #expect(verifier.contains("IceCubes Add Account has a leaked blank top-left root-content artifact"))
        #expect(verifier.contains("ToolbarTitleMenu appears to leak menu contents into the main content area"))
        #expect(verifier.contains("left + int(app_width * 0.78)"))
        #expect(verifier.contains("left + int(app_width * 0.43)"))
        #expect(verifier.contains("add_account_title_pixels <= 260"))
        #expect(verifier.contains("product == \"icecubes-linux-add-account\""))
        #expect(verifier.contains("product == \"icecubes-linux-add-account-instance\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-shell\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-trending\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_trending"))
        #expect(verifier.contains("IceCubes authenticated Trending sidebar row was not selected"))
        #expect(verifier.contains("IceCubes authenticated Trending timeline rows were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-local\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_local"))
        #expect(verifier.contains("218 <= r <= 235 and 228 <= g <= 245 and 238 <= b <= 255 and b >= g >= r"))
        #expect(verifier.contains("top + 136"))
        #expect(verifier.contains("IceCubes authenticated Local sidebar row was not selected"))
        #expect(verifier.contains("IceCubes authenticated Local timeline rows were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-federated\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_federated"))
        #expect(verifier.contains("top + 176"))
        #expect(verifier.contains("top + 300"))
        #expect(verifier.contains("IceCubes authenticated Federated sidebar row was not selected"))
        #expect(verifier.contains("IceCubes authenticated Federated timeline rows were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-explore\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_explore"))
        #expect(verifier.contains("explore_selected_pixels"))
        #expect(verifier.contains("quick_access_pixels"))
        #expect(verifier.contains("trending_tags_pixels"))
        #expect(verifier.contains("suggested_accounts_pixels"))
        #expect(verifier.contains("IceCubes authenticated Explore quick-access buttons were not detected"))
        #expect(verifier.contains("IceCubes authenticated Explore trending tags section was not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-explore-links\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_explore_links"))
        #expect(verifier.contains("link_row_pixels"))
        #expect(verifier.contains("first_link_title_pixels"))
        #expect(verifier.contains("first_link_action_pixels"))
        #expect(verifier.contains("IceCubes authenticated Explore Links list rows were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-explore-posts\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_explore_posts"))
        #expect(verifier.contains("action_button_surface_pixels"))
        #expect(verifier.contains("IceCubes authenticated Explore Posts timeline rows were not detected"))
        #expect(verifier.contains("IceCubes authenticated Explore Posts action controls were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-explore-tags\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_explore_tags"))
        #expect(verifier.contains("back_button_surface_pixels"))
        #expect(verifier.contains("tag_row_pixels"))
        #expect(verifier.contains("IceCubes authenticated Explore Tags list rows were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-explore-suggested-users\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_explore_suggested_users"))
        #expect(verifier.contains("account_row_pixels"))
        #expect(verifier.contains("stale_placeholder_row_pixels"))
        #expect(verifier.contains("account_row_pixels <= 8_000"))
        #expect(verifier.contains("lower content should be blank after the two fixture accounts"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-settings-display\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-settings-display-font-scale\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-settings-display-font-picker\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-settings-display-font-picker-selected\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-settings-display-system-color\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_settings_display"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_settings_display_font_scale"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_settings_display_font_picker"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_settings_display_font_picker_selected"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_settings_display_system_color"))
        #expect(verifier.contains("display_control_text_pixels"))
        #expect(verifier.contains("preview_status_text_pixels"))
        #expect(verifier.contains("lower_display_control_pixels"))
        #expect(verifier.contains("slider_control_pixels"))
        #expect(verifier.contains("top_display_control_pixels >= 550"))
        #expect(verifier.contains("lower_display_control_pixels >= 900"))
        #expect(verifier.contains("slider_control_pixels >= 700"))
        #expect(verifier.contains("display_row_segments"))
        #expect(verifier.contains("display_row_segments >= 7"))
        #expect(verifier.contains("IceCubes authenticated Settings Display lower controls were not detected"))
        #expect(verifier.contains("IceCubes authenticated Settings Display font scaling control was not detected"))
        #expect(verifier.contains("IceCubes authenticated Settings Display row stack was not detected"))
        #expect(verifier.contains("slider_right_accent_pixels >= 180"))
        #expect(verifier.contains("IceCubes authenticated Settings Display font-scale slider did not move right"))
        #expect(verifier.contains("font_picker_surface_pixels >= 240_000"))
        #expect(verifier.contains("title_text_pixels >= 180"))
        #expect(verifier.contains("atkinson_button_pixels >= 220"))
        #expect(verifier.contains("stale_slider_accent_pixels <= 40"))
        #expect(verifier.contains("selected_font_text_pixels >= 120"))
        #expect(verifier.contains("system_label_signature_pixels <= 92"))
        #expect(verifier.contains("IceCubes authenticated Settings Display selected font row still looks like the default System label"))
        #expect(verifier.contains("toggle_accent_pixels <= 60"))
        #expect(verifier.contains("enabled_color_row_text_pixels >= 240"))
        #expect(verifier.contains("IceCubes authenticated Settings Display color rows did not become enabled after system-color toggle"))
        #expect(verifier.contains("stale_settings_root_visible_logout_pixels"))
        #expect(verifier.contains("stale_settings_root_visible_logout_pixels <= 80"))
        #expect(verifier.contains("stale_settings_root_display_highlight_pixels"))
        #expect(gtkNavigation.contains("private enum GTKNavigationPersistedRoute"))
        #expect(gtkNavigation.contains("private var gtkNavigationPersistedRoutesByNamespace"))
        #expect(gtkNavigation.contains("func restorePersistedRoutesIfNeeded()"))
        #expect(gtkNavigation.contains("pushDestinationRoute("))
        #expect(gtkNavigation.contains("shouldPersistUnboundValueRoutes"))
        #expect(gtkNavigation.contains("GTKDeferredNavigationDestination"))
        #expect(verifier.contains("IceCubes authenticated Explore Suggested Users account rows were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-explore-search\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_explore_search"))
        #expect(verifier.contains("search_entry_surface_pixels"))
        #expect(verifier.contains("IceCubes authenticated Explore search field does not appear to contain typed text"))
        #expect(verifier.contains("IceCubes authenticated Explore search results were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-notifications\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-composer-submitted\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_notifications"))
        #expect(verifier.contains("notifications_label_pixels"))
        #expect(verifier.contains("first_notification_header_pixels"))
        #expect(verifier.contains("first_notification_body_pixels"))
        #expect(verifier.contains("second_notification_action_pixels"))
        #expect(verifier.contains("IceCubes authenticated Notifications first row content did not look populated/compact"))
        #expect(!verifier.contains("IceCubes authenticated Notifications sidebar row was not selected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-profile\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_profile"))
        #expect(verifier.contains("profile_selected_pixels"))
        #expect(verifier.contains("account_header_pixels"))
        #expect(verifier.contains("IceCubes authenticated Profile account info/stats were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-messages\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-messages-refresh\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-messages-detail\""))
        #expect(verifier.contains("elif product == \"icecubes-linux-authenticated-messages-refresh\":\n        print(validate_icecubes_linux_authenticated_messages(image))"))
        #expect(verifier.contains("elif product == \"icecubes-linux-authenticated-messages-detail\":\n        print(validate_icecubes_linux_authenticated_messages_detail(image))"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_messages"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_messages_detail"))
        #expect(verifier.contains("def icecubes_authenticated_accent_pixel"))
        #expect(verifier.contains("messages_selected_pixels"))
        #expect(verifier.contains("conversation_header_pixels"))
        #expect(verifier.contains("conversation_body_pixels"))
        #expect(verifier.contains("back_button_pixels"))
        #expect(verifier.contains("composer_pixels"))
        #expect(verifier.contains("IceCubes authenticated Messages detail reply composer was not detected"))
        #expect(!verifier.contains("unread_marker_pixels"))
        #expect(!verifier.contains("IceCubes authenticated Messages unread fixture marker was not detected"))
        #expect(verifier.contains("IceCubes authenticated Messages conversation body was not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-list\""))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_list"))
        #expect(verifier.contains("list_selected_pixels"))
        #expect(verifier.contains("list_fixture_author_pixels"))
        #expect(verifier.contains("list_fixture_body_pixels"))
        #expect(verifier.contains("second_list_fixture_author_pixels"))
        #expect(verifier.contains("IceCubes authenticated List sidebar row was not selected"))
        #expect(verifier.contains("IceCubes authenticated List first fixture body was not detected"))
        #expect(verifier.contains("IceCubes authenticated List timeline rows were not detected"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-status-detail\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-status-detail-boost\""))
        #expect(verifier.contains("\"icecubes-linux-authenticated-status-detail-favorite\""))
        #expect(script.contains("AUTH_STATUS_DETAIL_REPLY_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_REPLY_X:-272}\""))
        #expect(script.contains("seeded-authenticated-status-detail-reply)"))
        #expect(script.contains("AUTH_STATUS_DETAIL_QUOTE_MENU_Y=\"${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_QUOTE_MENU_Y:-258}\""))
        #expect(script.contains("seeded-authenticated-status-detail-quote)"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_status_detail"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_status_detail_boost"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_status_detail_favorite"))
        #expect(verifier.contains("icecubes_authenticated_sidebar_surface_pixel"))
        #expect(verifier.contains("detail_header_pixels"))
        #expect(verifier.contains("detail_body_pixels"))
        #expect(verifier.contains("detail_upper_body_pixels"))
        #expect(verifier.contains("detail_lower_body_pixels"))
        #expect(verifier.contains("detail_media_pixels"))
        #expect(verifier.contains("detail_summary_pixels"))
        #expect(verifier.contains("detail_has_wide_media = app_width >= 900 and detail_media_pixels >= 100_000"))
        #expect(verifier.contains("detail_has_summary = detail_summary_pixels >= 350"))
        #expect(verifier.contains("detail_action_pixels"))
        #expect(verifier.contains("detail_top_action_pixels"))
        #expect(verifier.contains("detail_action_count_pixels"))
        #expect(verifier.contains("boost_accent_pixels"))
        #expect(verifier.contains("favorite_accent_pixels"))
        #expect(verifier.contains("IceCubes authenticated Status detail body text was not detected"))
        #expect(toolbarModifier.contains("case center"))
        #expect(textLayoutCompat.contains("static var principal: ToolbarItemPlacement { .center }"))
        #expect(designSystemCompat.contains("ToolbarTitleMenu"))
        #expect(designSystemCompat.contains("ToolbarItem(placement: .principal)"))
        #expect(navigationStack.contains("public let typedPathBinding: AnyNavigationPathBinding?"))
        #expect(navigationStack.contains("public struct AnyNavigationPathBinding"))
        #expect(navigationStack.contains("where Path.Element: Hashable"))
        #expect(gtkNavigation.contains("var typedPathBinding: AnyNavigationPathBinding?"))
        #expect(gtkNavigation.contains("typedPathBinding?.elements()"))
        #expect(gtkNavigation.contains("case .center:\n                gtk_header_bar_set_title_widget"))
        #expect(gtkNavigation.contains("item.placement == .center"))
        #expect(gtkNavigation.contains("toolbarItems where item.placement != .leading && item.placement != .center"))
        #expect(gtkRenderer.contains("gtkForcedStateIdentityNamespace\n        ?? GTKViewHost.getCurrentRebuilding()?.stateIdentityNamespace"))
        #expect(gtkRenderer.contains("private func gtkWithStateIdentityNamespaceComponent"))
        #expect(gtkRenderer.contains("private func gtkRestoreAndInstallInlineState"))
        #expect(gtkRenderer.contains("inline state install type="))
        #expect(gtkRenderer.contains("hasReactiveProperties(view), let host = GTKViewHost.getCurrentRebuilding()"))
        #expect(gtkRenderer.contains("gtkRestoreAndInstallInlineState(view, host: host)"))
        #expect(gtkRenderer.contains("gtkWithForcedStateIdentityNamespace(namespace)"))
        #expect(gtkRenderer.contains("gtkRestoreViewHostLifecycleIfAvailable(host)"))
        #expect(gtkViewHost.contains("private struct GTKViewHostLifecycleSnapshot"))
        #expect(gtkViewHost.contains("gtkBeginViewHostLifecycleRemountPass()"))
        #expect(gtkViewHost.contains("gtkEndViewHostLifecycleRemountPass()"))
        #expect(gtkViewHost.contains("gtkRestoreViewHostLifecycleIfAvailable"))
        #expect(gtkViewHost.contains("gtkStoreViewHostLifecycleSnapshot"))
        #expect(gtkViewHost.contains("gtkViewHostLifecycleRemountIsActive()"))
        #expect(gtkViewHost.contains("if var existing = gtkViewHostLifecycleRemountCache[namespace]"))
        #expect(gtkViewHost.contains("existing.appearedOnAppearIdentities.formUnion(snapshot.appearedOnAppearIdentities)"))
        #expect(gtkViewHost.contains("activeTasksByIdentity.removeAll()"))
        #expect(gtkViewHost.contains("gtkStoreViewHostLifecycleSnapshot(lifecycleSnapshot, for: stateIdentityNamespace)"))
        #expect(gtkDescriptorTree.contains("public let components: [String]"))
        #expect(gtkDescriptorTree.contains("lhs.components == rhs.components"))
        #expect(gtkDescriptorTree.contains("nodeComponents = components + [\"key:\\(semanticComponent)\"]"))
        #expect(gtkDescriptorTree.contains("nodeComponents = components + [\"#\\(localIndex)\"]"))
        #expect(gtkDescriptorTree.contains("descriptor.typeName.hasPrefix(\"IdView<\")"))
        #expect(gtkDescriptorTree.contains("descriptor.typeName.hasPrefix(\"GTKStateNamespaceView<\")"))
        #expect(gtkDescriptorTree.contains("if hasReactiveProperties(view)"))
        #expect(gtkDescriptorTree.contains("typeName: \"GTKStatefulHost<\\(String(describing: type(of: view)))>\""))
        #expect(gtkRenderer.contains("private struct GTKStateNamespaceView"))
        #expect(gtkRenderer.contains("private protocol GTKKeyedListRowProducer"))
        #expect(gtkRenderer.contains("extension ForEach: GTKKeyedListRowProducer"))
        #expect(gtkRenderer.contains("if let keyedRows = view as? GTKKeyedListRowProducer"))
        #expect(gtkRenderer.contains("return keyedRows.gtkKeyedListRows(depth: depth + 1).flatMap"))
        #expect(gtkRenderer.contains("return keyedRows.gtkKeyedListRows(depth: 0).flatMap"))
        #expect(gtkRenderer.contains("private func gtkSearchableKeepsChromeVisible(for placement: SearchFieldPlacement) -> Bool"))
        #expect(gtkRenderer.contains("case .navigationBarDrawer(let displayMode):\n        return displayMode == .always"))
        #expect(gtkRenderer.contains("!$0.wrappedValue && !gtkSearchableKeepsChromeVisible(for: placement)"))
        #expect(gtkRenderer.contains("gtk_widget_set_can_target(box, 1)"))
        #expect(gtkRenderer.contains("gtk_widget_set_focus_on_click(entry, 1)"))
        #expect(gtkRenderer.contains("gtk_widget_set_focus_on_click(delegateWidget, 1)"))
        #expect(gtkRenderer.contains("let focusGesture = gtk_gesture_click_new()!"))
        #expect(gtkRenderer.contains("gtk_swift_root_grab_focus(box.entry)"))
        #expect(gtkRenderer.contains("private let gtkSearchableFocusDataKey = \"gtk-swift-searchable-focus\""))
        #expect(gtkRenderer.contains("private let gtkSearchableTopSurfaceDataKey = \"gtk-swift-searchable-top-surface-focus\""))
        #expect(gtkRenderer.contains("private final class GTKSearchRootEventContext"))
        #expect(gtkRenderer.contains("gtkAttachSearchTopSurfaceData(to: box, box: searchFocusBox)"))
        #expect(gtkRenderer.contains("let entryContainer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!"))
        #expect(gtkRenderer.contains("gtk_box_append(boxPointer(entryContainer), entry)"))
        #expect(gtkRenderer.contains("gtk_widget_set_visible(entryContainer, 0)"))
        #expect(gtkRenderer.contains("private func gtkSearchEntryEstimatedChromeContainsRootPoint"))
        #expect(gtkRenderer.contains("guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: x, y: y)"))
        #expect(gtkRenderer.contains("private func gtkFocusSearchEntryAtRootPoint"))
        #expect(gtkRenderer.contains("source: \"tap-root-dispatch@\\(Int(rootX)),\\(Int(rootY))\""))
        #expect(gtkRenderer.contains("source: \"tap-root@\\(Int(x)),\\(Int(y))\""))
        #expect(gtkRenderer.contains("source: \"list-row-root-dispatch@\\(Int(rootX)),\\(Int(rootY))\""))
        #expect(gtkRenderer.contains("gtk_swift_search_entry_set_key_capture_widget(entry, box)"))
        #expect(gtkShim.contains("gtk_swift_search_entry_set_key_capture_widget"))
        #expect(gtkShim.contains("gtk_swift_search_entry_get_key_capture_widget"))
        #expect(gtkRenderer.contains("gtkScheduleTextBindingUpdate(box.binding, value: newValue)"))
        #expect(gtkRenderer.contains("let changedBox = Unmanaged.passRetained(StringClosureBox { newText in\n            gtkScheduleTextBindingUpdate(binding, value: newText)"))
        #expect(patcher.contains("SwiftOpenUI SearchableView GTK extension marker was not recognized"))
        #expect(patcher.contains("gtkSearchableKeepsChromeVisible(for: placement)"))
        #expect(patcher.contains("SwiftOpenUI SearchableView search wrapper creation was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView search entry creation was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView search focus marker was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView content append was not recognized"))
        #expect(patcher.contains("SwiftOpenUI GTK search-entry shim shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView visibility expression was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView search-changed binding update was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView token marker was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView root focus helper shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView entry container append was not recognized"))
        #expect(patcher.contains("SwiftOpenUI SearchableView entry container visibility was not recognized"))
        #expect(patcher.contains("SwiftOpenUI tap root dispatcher searchable guard shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI tap root fallback searchable guard shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI list row root dispatcher searchable guard shape was not recognized"))
        #expect(verifier.contains("search_entry_text_pixels = dark_pixel_count(\n        image,\n        left + 275"))
        #expect(workflow.contains("Upstream IceCubes GTK visual smoke"))
        #expect(workflow.contains("scripts/icecubes-linux-visual-check.sh .qa/icecubes-linux-add-account.png"))
        #expect(workflow.contains("Upstream IceCubes GTK Add Account interaction smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=type-instance"))
        #expect(workflow.contains("Upstream IceCubes GTK OAuth open smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=sign-in-open"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated shell smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-shell"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Trending smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-trending"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Local smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-local"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Federated smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-federated"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Explore smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-explore"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Explore Links quick-access smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-explore-links"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Explore Trending Posts quick-access smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-explore-posts"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Explore Tags quick-access smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-explore-tags"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Explore Suggested Users quick-access smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-explore-suggested-users"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Explore search smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-explore-search"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Notifications smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-notifications"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Notifications refresh smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-notifications-refresh"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Profile smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-profile"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Messages smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-messages"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Messages refresh smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-messages-refresh"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Messages detail smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-messages-detail"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated List smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-list"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated List refresh smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-list-refresh"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated List pagination smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-list-pagination"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Settings smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-settings"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Settings Display smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-settings-display"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Settings Display font-scale smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-settings-display-font-scale"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Settings Display font-picker smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-settings-display-font-picker"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Settings Display font-picker select smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-settings-display-font-picker-select"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Settings Display system-color smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-settings-display-system-color"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Composer smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-composer"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Composer text entry smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-composer-type"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Composer submit smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-composer-submit"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Status detail smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-status-detail"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Status detail refresh smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-status-detail-refresh"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Status detail boost smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-status-detail-boost"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Status detail quote composer smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-status-detail-quote"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Status detail favorite smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-status-detail-favorite"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Status detail bookmark smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-status-detail-bookmark"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Status detail reply composer smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-status-detail-reply"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated media viewer smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-media-viewer"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Home pagination smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-home-pagination"))
        #expect(workflow.contains("Upstream IceCubes GTK authenticated Home refresh smoke"))
        #expect(workflow.contains("QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-home-refresh"))
        #expect(workflow.contains("fonts-noto-cjk"))
        #expect(parityLog.contains("[x] Add CI launch smoke and screenshot artifacts for `IceCubesLinuxApp`."))
        #expect(parityLog.contains("QUILLUI_ICECUBES_VISUAL_SCROLL_CLICKS"))
        #expect(parityLog.contains("sign-in-open"))
        #expect(parityLog.contains("seeded-authenticated-shell"))
        #expect(parityLog.contains("seeded-authenticated-home-pagination"))
        #expect(parityLog.contains("seeded-authenticated-home-refresh"))
        #expect(parityLog.contains("seeded-authenticated-status-detail-refresh"))
        #expect(parityLog.contains("exact-matches fresh fixture log"))
        #expect(parityLog.contains("SwiftUI `.refreshable`"))
        #expect(parityLog.contains("seeded-authenticated-notifications-refresh"))
        #expect(parityLog.contains("route-agnostic refresh shortcut driver"))
        #expect(parityLog.contains("seeded-authenticated-trending"))
        #expect(parityLog.contains("seeded-authenticated-local"))
        #expect(parityLog.contains("seeded-authenticated-federated"))
        #expect(parityLog.contains("seeded-authenticated-explore"))
        #expect(parityLog.contains("seeded-authenticated-explore-links"))
        #expect(parityLog.contains("seeded-authenticated-explore-posts"))
        #expect(parityLog.contains("seeded-authenticated-explore-tags"))
        #expect(parityLog.contains("seeded-authenticated-explore-suggested-users"))
        #expect(parityLog.contains("seeded-authenticated-explore-search"))
        #expect(parityLog.contains("seeded-authenticated-notifications"))
        #expect(parityLog.contains("seeded-authenticated-profile"))
        #expect(parityLog.contains("seeded-authenticated-messages"))
        #expect(parityLog.contains("seeded-authenticated-messages-refresh"))
        #expect(parityLog.contains("seeded-authenticated-messages-detail"))
        #expect(parityLog.contains("seeded-authenticated-list"))
        #expect(parityLog.contains("seeded-authenticated-list-refresh"))
        #expect(parityLog.contains("seeded-authenticated-list-pagination"))
        #expect(parityLog.contains("seeded-authenticated-settings-display"))
        #expect(parityLog.contains("seeded-authenticated-settings-display-font-scale"))
        #expect(parityLog.contains("seeded-authenticated-settings-display-font-picker"))
        #expect(parityLog.contains("seeded-authenticated-settings-display-system-color"))
        #expect(parityLog.contains("stacked `.task` modifiers"))
        #expect(parityLog.contains("environment-injected observable object reads"))
        #expect(parityLog.contains("seeded-authenticated-composer-submit"))
        #expect(parityLog.contains("seeded-authenticated-status-detail"))
        #expect(parityLog.contains("seeded-authenticated-status-detail-boost"))
        #expect(parityLog.contains("seeded-authenticated-status-detail-quote"))
        #expect(parityLog.contains("seeded-authenticated-status-detail-favorite"))
        #expect(parityLog.contains("seeded-authenticated-status-detail-bookmark"))
        #expect(parityLog.contains("seeded-authenticated-status-detail-reply"))
        #expect(parityLog.contains("token exchange/credential verification still require"))
        #expect(parityLog.contains("direct async `QuillURLSessionFixtures.data(...)` transport"))
        #expect(fetchUpstream.contains("QuillURLSessionFixtures.data(for: request, fallbackSession: urlSession)"))
        #expect(fetchUpstream.contains("QuillURLSessionFixtures.data(for: request, fallbackSession: URLSession.shared)"))
        #expect(fetchUpstream.contains("import QuillKit"))
        #expect(quillKit.contains("public static let openURLLogFileEnvironmentKey = \"QUILLUI_OPEN_URL_LOG_FILE\""))
        #expect(quillKit.contains("public static let openURLLogAssumeHandledEnvironmentKey = \"QUILLUI_OPEN_URL_LOG_ASSUME_HANDLED\""))
        #expect(quillKit.contains("public static let responseDelayMillisecondsEnvironmentKey = \"QUILLUI_URLSESSION_FIXTURE_RESPONSE_DELAY_MS\""))
        #expect(quillKit.contains("public static func data("))
        #expect(quillKit.contains("fileprivate static func directResponse(for request: URLRequest)"))
        #expect(quillKit.contains("debugLog(\"direct \\(request.httpMethod ?? \"GET\")"))
        #expect(quillKit.contains("private static let deliveryQueue = DispatchQueue(label: \"co.lorehex.QuillURLSessionFixtures.delivery\")"))
        #expect(quillKit.contains("private func beginDelivery() -> Bool"))
        #expect(quillKit.contains("private static func logOpenURLIfConfigured"))
        #expect(quillKit.contains("recordOpen(url, didOpen: true, backendName: \"file-log\")"))
        #expect(package.contains("\"QuillKit\",\n                \"os\","))
        #expect(package.contains(".executable(name: \"icecubes-seed-account\", targets: [\"IceCubesSeedAccount\"])"))
        #expect(package.contains("name: \"IceCubesSeedAccount\""))
        #expect(seedMain.contains("try account.save()"))
        #expect(seedMain.contains("AppAccountsManager.latestCurrentAccountKey = account.id"))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/timelines/home\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/trends/statuses\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/suggestions\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/trends/tags\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/trends/links\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/lists\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/timelines/list/list-quill-core\""))
        #expect(mastodonFixtures.contains("\"query\": \"max_id=1001&limit=40\""))
        #expect(mastodonFixtures.contains("Pagination Fixture: IceCubes requested the next home timeline page"))
        #expect(mastodonFixtures.contains("Bottom Pagination Fixture: the appended page stayed visible"))
        #expect(mastodonFixtures.contains("\"query\": \"max_id=list-9002\""))
        #expect(mastodonFixtures.contains("Quill Core"))
        #expect(mastodonFixtures.contains("QuillUI Explore Fixture Link"))
        #expect(mastodonFixtures.contains("suggested-account-1"))
        #expect(mastodonFixtures.contains("Explore Fixture"))
        #expect(mastodonFixtures.contains("Swift Linux Fixture"))
        #expect(mastodonFixtures.contains("id%5B%5D=suggested-account-1&id%5B%5D=suggested-account-2"))
        #expect(mastodonFixtures.contains("QuillUI fixture trending status"))
        #expect(mastodonFixtures.contains("Trending Fixture"))
        #expect(mastodonFixtures.contains("QuillUI fixture local timeline"))
        #expect(mastodonFixtures.contains("Local Fixture"))
        #expect(mastodonFixtures.contains("\"query\": \"local=true&limit=50\""))
        #expect(mastodonFixtures.contains("\"query\": \"local=false&limit=50\""))
        #expect(mastodonFixtures.contains("QuillUI fixture federated timeline"))
        #expect(mastodonFixtures.contains("Federated Fixture"))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/notifications\""))
        #expect(mastodonFixtures.contains("\"query\": \"limit=30\""))
        #expect(mastodonFixtures.contains("\"query\": \"min_id=notification-1002&limit=30\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v2/notifications\""))
        #expect(mastodonFixtures.contains("\"query\": \"grouped_types%5B%5D=favourite&grouped_types%5B%5D=follow&grouped_types%5B%5D=reblog&expand_accounts=full\""))
        #expect(mastodonFixtures.contains("\"query\": \"since_id=1002&grouped_types%5B%5D=favourite&grouped_types%5B%5D=follow&grouped_types%5B%5D=reblog&expand_accounts=full\""))
        #expect(mastodonFixtures.contains("\"pathPrefix\": \"/avatars/\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/conversations\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/conversations/conversation-1001/read\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/statuses/conversation-status-1001/context\""))
        #expect(mastodonFixtures.contains("conversation-status-1001"))
        #expect(mastodonFixtures.contains("Conversation fixture: Alice sent a direct message"))
        #expect(mastodonFixtures.contains("notification-status-1002"))
        #expect(mastodonFixtures.contains("notification-status-1001"))
        #expect(mastodonFixtures.contains("Notification fixture: Alice favorited"))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/markers\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/statuses\""))
        #expect(mastodonFixtures.contains("posted-hello-from-linux"))
        #expect(mastodonFixtures.contains("\"pathPattern\": \"/api/v1/statuses/{id}\""))
        #expect(mastodonFixtures.contains("\"pathPattern\": \"/api/v1/statuses/{id}/context\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/statuses/1003/reblog\""))
        #expect(mastodonFixtures.contains("\"path\": \"/api/v1/statuses/1003/favourite\""))
        #expect(mastodonFixtures.contains("QuillUI fixture status detail"))
        #expect(script.contains("seeded-authenticated-notifications"))
        #expect(script.contains("seeded-authenticated-notifications-refresh"))
        #expect(script.contains("seeded-authenticated-messages-refresh"))
        #expect(script.contains("seeded-authenticated-messages-detail"))
        #expect(script.contains("seeded-authenticated-list-refresh"))
        #expect(script.contains("seeded-authenticated-list-pagination"))
        #expect(script.contains("authenticated Messages refresh"))
        #expect(script.contains("authenticated Messages detail context fetch"))
        #expect(script.contains("authenticated List refresh"))
        #expect(script.contains("authenticated List timeline pagination"))
        #expect(script.contains("AUTH_NOTIFICATIONS_INITIAL_ENDPOINT=\"/api/v2/notifications?grouped_types%5B%5D=favourite&grouped_types%5B%5D=follow&grouped_types%5B%5D=reblog&expand_accounts=full\""))
        #expect(script.contains("AUTH_NOTIFICATIONS_REFRESH_ENDPOINT=\"/api/v2/notifications?since_id=1002&grouped_types%5B%5D=favourite&grouped_types%5B%5D=follow&grouped_types%5B%5D=reblog&expand_accounts=full\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"$AUTH_NOTIFICATIONS_INITIAL_ENDPOINT\" \"authenticated Notifications sidebar navigation\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"$AUTH_NOTIFICATIONS_REFRESH_ENDPOINT\" \"authenticated Notifications display refresh\""))
        #expect(script.contains("authenticated Notifications display refresh"))
        #expect(script.contains("authenticated Notifications refresh"))
        #expect(script.contains("AUTH_NOTIFICATIONS_Y"))
        #expect(script.contains("seeded-authenticated-status-detail"))
        #expect(script.contains("seeded-authenticated-status-detail-boost"))
        #expect(script.contains("seeded-authenticated-status-detail-favorite"))
        #expect(script.contains("seeded-authenticated-media-viewer"))
        #expect(script.contains("seeded-authenticated-home-pagination"))
        #expect(script.contains("seeded-authenticated-home-refresh"))
        #expect(script.contains("AUTH_TIMELINE_PAGINATION_SCROLL_CLICKS"))
        #expect(script.contains("AUTH_REFRESH_KEY_SETTLE_SECONDS"))
        #expect(script.contains("trigger_authenticated_refresh_shortcut()"))
        #expect(script.contains("/api/v1/timelines/home?max_id=1001&limit=40"))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/timelines/home?max_id=1001&limit=40\" \"authenticated Home timeline pagination\""))
        #expect(script.contains("wait_for_authenticated_api_activity \"/api/v1/timelines/home?max_id=1001&limit=40\" \"authenticated Home timeline pagination\"\n    scroll_authenticated_timeline_for_pagination"))
        #expect(script.contains("trigger_authenticated_home_refresh()"))
        #expect(script.contains("xdotool key --clearmodifiers ctrl+r"))
        #expect(script.contains("\"/api/v1/timelines/home?limit=50\""))
        #expect(script.contains("\"authenticated Home refresh\""))
        #expect(script.contains("previous_refresh_trigger_count=\"$(count_app_log_occurrences \"[QuillUI GTK Refreshable] trigger source=keyboard\")\""))
        #expect(script.contains("wait_for_app_log_activity \"[QuillUI GTK Refreshable] trigger source=keyboard\" \"$label shortcut\" \"$((previous_refresh_trigger_count + 1))\""))
        #expect(script.contains("QUILLUI_GTK_DEBUG_REFRESHABLE=${QUILLUI_GTK_DEBUG_REFRESHABLE:-1}"))
        #expect(refreshModifier.contains("public struct RefreshableView<Content: View>: View"))
        #expect(refreshModifier.contains("public func refreshable(action: @escaping () async -> Void) -> RefreshableView<Self>"))
        #expect(refreshModifier.contains("private final class RefreshActionBox: @unchecked Sendable"))
        #expect(!designSystemCompat.contains("func refreshable(action: @escaping () async -> Void) -> Self"))
        #expect(gtkRenderer.contains("private final class GTKRefreshActionBox"))
        #expect(gtkRenderer.contains("KeyboardShortcut(KeyEquivalent(\"r\"), modifiers: .command)"))
        #expect(gtkRenderer.contains("gtkAttachRefreshOverscrollHandler(to: widget, actionBox: actionBox)"))
        #expect(gtkRenderer.contains("box.trigger(source: \"edge-overshot\")"))
        #expect(gtkRenderer.contains("gtkAttachRefreshAction(to: widget, action: action)"))
        #expect(gtkDescriptorTree.contains("case listRowLifecycleScope"))
        #expect(gtkDescriptorTree.contains("gtkWithSuppressedDescriptorLifecyclePayloads"))
        #expect(gtkDescriptorTree.contains("includingListRowScopes: Bool = true"))
        #expect(gtkDescriptorTree.contains("node.descriptor.kind == .listRowLifecycleScope, !includingListRowScopes"))
        #expect(gtkViewHost.contains("includingListRowScopes: false"))
        #expect(gtkRenderer.contains("private final class GTKListRowLifecycleBox"))
        #expect(gtkRenderer.contains("private final class GTKListViewportLifecycleController"))
        #expect(gtkRenderer.contains("gtkDescribeListRowLifecycleScope"))
        #expect(gtkRenderer.contains("gtkAttachListRowLifecycleData(to: row, view: child, source: rowSource)"))
        #expect(gtkRenderer.contains("gtkInstallListViewportLifecycleController(on: scrolled, listBox: listBox)"))
        #expect(gtkRenderer.contains("lifecycle.setVisible(gtkListRowIsVisible(current, in: scrolled))"))
        #expect(script.contains("AUTH_MEDIA_VIEWER_X=\"${QUILLUI_ICECUBES_VISUAL_AUTH_MEDIA_VIEWER_X:-520}\""))
        #expect(script.contains("wait_for_authenticated_media_viewer_visual"))
        #expect(verifier.contains("icecubes-linux-authenticated-home-pagination"))
        #expect(verifier.contains("def validate_icecubes_linux_authenticated_home_pagination"))
        #expect(verifier.contains("IceCubes authenticated Home pagination lower timeline rows were not detected"))
        #expect(verifier.contains("icecubes-linux-authenticated-home-refresh"))
        #expect(verifier.contains("elif product == \"icecubes-linux-authenticated-home-refresh\":\n        print(validate_icecubes_linux_authenticated_home_row_ready(image))"))
        #expect(verifier.contains("icecubes-linux-authenticated-notifications-refresh"))
        #expect(verifier.contains("elif product == \"icecubes-linux-authenticated-notifications-refresh\":\n        print(validate_icecubes_linux_authenticated_notifications(image))"))
        #expect(verifier.contains("\"icecubes-linux-authenticated-status-detail-refresh\""))
        #expect(verifier.contains("elif product == \"icecubes-linux-authenticated-status-detail-refresh\":\n        print(validate_icecubes_linux_authenticated_status_detail(image))"))
        #expect(verifier.contains("icecubes-linux-authenticated-media-viewer"))
        #expect(verifier.contains("IceCubes authenticated media viewer did not show a selected media surface larger than the timeline row"))
        #expect(verifier.contains("IceCubes authenticated media viewer capture still looks like the unchanged Timeline row"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_X"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_PRE_CLICK_DELAY_SECONDS"))
        #expect(script.contains("AUTH_STATUS_DETAIL_CLICK_RETRIES=\"${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_CLICK_RETRIES:-5}\""))
        #expect(script.contains("AUTH_STATUS_DETAIL_CLICK_RETRY_SECONDS=\"${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_CLICK_RETRY_SECONDS:-0.75}\""))
        #expect(script.contains("AUTH_STATUS_DETAIL_REFRESH_KEY_RETRIES=\"${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_REFRESH_KEY_RETRIES:-5}\""))
        #expect(script.contains("AUTH_STATUS_DETAIL_REFRESH_KEY_RETRY_SECONDS=\"${QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_REFRESH_KEY_RETRY_SECONDS:-0.75}\""))
        #expect(script.contains("AUTH_STATUS_DETAIL_GET_LOG=\"[QuillURLSessionFixtures] direct GET https://mastodon.social/api/v1/statuses/1003\""))
        #expect(script.contains("AUTH_STATUS_DETAIL_CONTEXT_GET_LOG=\"[QuillURLSessionFixtures] direct GET https://mastodon.social/api/v1/statuses/1003/context\""))
        #expect(script.contains("count_app_log_exact_occurrences()"))
        #expect(script.contains("wait_for_app_log_exact_activity()"))
        #expect(script.contains("click_authenticated_status_detail_row()"))
        #expect(script.contains("wait_for_status_detail_request_after_click()"))
        #expect(!script.contains("state install type=StatusKit.StatusDetailView"))
        #expect(script.contains("trigger_authenticated_status_detail_refresh()"))
        #expect(script.contains("for attempt in $(seq 1 \"$AUTH_STATUS_DETAIL_REFRESH_KEY_RETRIES\")"))
        #expect(script.contains("seeded-authenticated-status-detail-refresh)"))
        #expect(script.contains("VERIFY_PRODUCT=\"icecubes-linux-authenticated-status-detail-refresh\""))
        #expect(script.contains("count_app_log_exact_occurrences \"$AUTH_STATUS_DETAIL_GET_LOG\""))
        #expect(script.contains("count_app_log_exact_occurrences \"$AUTH_STATUS_DETAIL_CONTEXT_GET_LOG\""))
        #expect(script.contains("trigger_authenticated_status_detail_refresh \"$((previous_status_count + 1))\" \"$((previous_context_count + 1))\""))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_BOOST_X"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_BOOST_MENU_X"))
        #expect(script.contains("QUILLUI_ICECUBES_VISUAL_AUTH_STATUS_DETAIL_FAVORITE_X"))
        #expect(script.contains("if [[ \"$INTERACTION\" == \"seeded-authenticated-media-viewer\" ]]; then"))
        #expect(script.contains("QUILLUI_GTK_DEBUG_ACTIONS=${QUILLUI_GTK_DEBUG_ACTIONS:-1}"))
        #expect(!script.contains("wait_for_app_log_activity \"StatusKit.StatusRowView\""))
        #expect(!script.contains("wait_for_app_log_activity \"list row root fallback installed\""))
        #expect(script.contains("/api/v1/statuses/1003"))
        #expect(script.contains("/api/v1/statuses/1003/context"))
        #expect(script.contains("/api/v1/statuses/1003/reblog"))
        #expect(script.contains("/api/v1/statuses/1003/favourite"))
        #expect(script.contains("authenticated status detail navigation"))
        #expect(script.contains("authenticated status boost action"))
        #expect(script.contains("authenticated status favorite action"))
        #expect(designSystemCompat.contains("Menu(\"Timeline\") { box.value }"))
        #expect(designSystemCompat.contains("fileprivate protocol QuillTabCollectible"))
        #expect(designSystemCompat.contains("quillCollectTabs(fromAny:)"))
        #expect(designSystemCompat.contains("selectionValue: AnyHashable(value)"))
        #expect(gtkRenderer.contains("QUILLUI_GTK_DEBUG_TABS"))
        #expect(gtkRenderer.contains("gtk_swift_stack_get_visible_child_name"))
        #expect(gtkRenderer.contains("private func gtkActivateSidebarTab"))
        #expect(gtkRenderer.contains("private func gtkInstallSidebarTabActivationGesture"))
        #expect(gtkRenderer.contains("private func gtkInstallSidebarTabRootActivationFallback"))
        #expect(gtkRenderer.contains("private func gtkActivateSidebarTabAt"))
        #expect(gtkRenderer.contains("GTKSidebarTabFallbackContext"))
        #expect(gtkRenderer.contains("gtk_widget_translate_coordinates(source, context.sidebar"))
        #expect(gtkRenderer.contains("gtkInstallSidebarTabRootActivationFallback(on: root, sidebar: sidebar)"))
        #expect(gtkRenderer.contains("gtkSidebarTabActivationBoxDataKey"))
        #expect(gtkRenderer.contains("sidebar fallback requested="))
        #expect(gtkRenderer.contains("gtk_swift_add_capture_gesture(widget, gesture)"))
        #expect(gtkRenderer.contains("selectionHandler?(id)"))
        #expect(gtkRenderer.contains("private let gtkSidebarTabSelectedClass = \"swiftopenui-tab-selected\""))
        #expect(gtkRenderer.contains("gtk_widget_add_css_class(button, gtkSidebarTabSelectedClass)"))
        #expect(gtkRenderer.contains("gtk_widget_remove_css_class(current, gtkSidebarTabSelectedClass)"))
        #expect(gtkRenderer.contains("gtkWithStateIdentityNamespaceComponent(\"Tab[\\(id)]\")"))
        #expect(gtkRenderer.contains("gtk_widget_set_can_target(widget, 1)"))
        #expect(gtkRenderer.contains("gtkPropagateSingleChildLayoutMarkers(from: [contentWidget], to: widget)"))
        #expect(gtkRenderer.contains("private protocol GTKPrimaryTapActionProvider"))
        #expect(gtkRenderer.contains("private protocol GTKBackgroundActionProvider"))
        #expect(gtkRenderer.contains("gtkPrimaryActionBackground"))
        #expect(gtkRenderer.contains("list primary action background"))
        #expect(gtkRenderer.contains("private func gtkPrimaryTapAction(inAny view: any View"))
        #expect(gtkRenderer.contains("gtkInstallListRowTapFallback("))
        #expect(gtkRenderer.contains("gtkListRowTapActionDataKey"))
        #expect(gtkRenderer.contains("gtkInstallListBoxTapFallback(on: listBox)"))
        #expect(gtkRenderer.contains("list box tap fallback installed"))
        #expect(gtkRenderer.contains("listbox@\\(Int(x)),\\(Int(y))"))
        #expect(gtkRenderer.contains("private func gtkWidgetTreeContainsVisualTapActionAtRootPoint"))
        #expect(gtkRenderer.contains("private func gtkPreferredTapGestureActionBoxAtRootPoint"))
        #expect(gtkRenderer.contains("gtkPointPrefersDifferentTapGestureAction"))
        #expect(gtkRenderer.contains("gtkTapGestureBoxIsLayoutBackground"))
        #expect(gtkRenderer.contains("box.source == \"SwiftOpenUI.Color\""))
        #expect(gtkRenderer.contains("source: String(reflecting: Swift.type(of: content))"))
        #expect(gtkRenderer.contains("gtkTestWidgetTreeContainsVisualTapActionAtRootPoint"))
        #expect(gtkRenderer.contains("gtkTestPreferredTapActionMatchesWidgetTapData"))
        #expect(gtkRenderer.contains("tap gesture skipped deeper visual tap"))
        #expect(gtkRenderer.contains("list row global dispatch skipped visual tap"))
        #expect(gtkRenderer.contains("list row tap skipped visual tap listbox-root"))
        #expect(gtkRenderer.contains("list row tap skipped visual tap gesture"))
        #expect(gtkRenderer.contains("let rowSource = String(reflecting: Swift.type(of: child))"))
        #expect(gtkRenderer.contains("source: rowSource"))
        #expect(gtkRenderer.contains("list row tap fallback installed"))
        #expect(gtkRenderer.contains("gtkCSSFontSizePixels(forApplePointSize: size)"))
        #expect(gtkRenderer.contains("pointSize * 0.875"))
    }

    @Test("Vendored GTK ScrollViewReader uses deferred ID adjustment scrolling")
    func vendoredGTKScrollViewReaderUsesDeferredIDAdjustmentScrolling() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let viewHost = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKViewHost.swift")
        let descriptorTree = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4DescriptorTree.swift")
        let describeTests = try packageSource("Tests/QuillUITests/GTKDescribeCycleGuardTests.swift")

        #expect(renderer.contains("private var gtkScrollTargetRegistry: [AnyHashable: UnsafeMutablePointer<GtkWidget>]"))
        #expect(renderer.contains("private var gtkPendingScrollRequests: [AnyHashable: GTKPendingScrollRequest]"))
        #expect(renderer.contains("let gtkSwiftVerticalScrollViewMarker = \"gtk-swift-vertical-scroll-view\""))
        #expect(renderer.contains("private func gtkMarkSwiftUIScrollView"))
        #expect(renderer.contains("gtkMarkSwiftUIScrollView(scrolled, hasVerticalAxis: axes.contains(.vertical))"))
        #expect(renderer.contains("private func gtkRegisterScrollTarget(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>)"))
        #expect(renderer.contains("gtkResolvePendingScrollTo(id: id, widget: widget)"))
        #expect(renderer.contains("@discardableResult\nprivate func gtkApplyScrollTo"))
        #expect(renderer.contains("gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY)"))
        #expect(renderer.contains("gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled))"))
        #expect(renderer.contains("gtk_adjustment_set_value(vadjustment, maxValue)"))
        #expect(renderer.contains("!isSwiftUIVerticalScrollView,\n               let hadjustment = gtk_scrolled_window_get_hadjustment"))
        #expect(renderer.contains("gtkScheduleScrollTo(id: id, widget, anchor: anchor)"))
        #expect(renderer.contains("gtkPendingScrollRequests[anyID] = GTKPendingScrollRequest(anchor: anchor)"))
        #expect(renderer.contains("gtkRegisterScrollTarget(id: AnyHashable(id), widget: wrapper)"))
        #expect(renderer.contains("extension ScrollViewReader: GTKRenderable, GTKDescribable"))
        #expect(renderer.contains("typeName: \"ScrollViewReader\""))
        #expect(renderer.contains("children: [gtkDescribeView(content(proxy))]"))
        #expect(viewHost.contains("private struct GTKScrollAdjustmentSnapshot"))
        #expect(viewHost.contains("private func gtkCollectScrollAdjustmentSnapshots(in widget: UnsafeMutablePointer<GtkWidget>)"))
        #expect(viewHost.contains("let scrollSnapshots = gtkCollectScrollAdjustmentSnapshots(in: container)"))
        #expect(viewHost.contains("gtkRestoreScrollAdjustmentSnapshots(scrollSnapshots, in: newChild)"))
        #expect(viewHost.contains("gtkScheduleScrollAdjustmentSnapshotRestore(scrollSnapshots, in: newChild)"))
        #expect(viewHost.contains("snapshot.isAtEnd ? maxValue"))
        #expect(viewHost.contains("func describeBodyCapturingPayloads"))
        #expect(viewHost.contains("GTKViewHost.setCurrentRebuilding(self)"))
        #expect(viewHost.contains("gtkBeginStateIdentityPass()"))
        #expect(descriptorTree.contains("task payload identity mismatch identities=\\(identities.count) payloads=\\(payloads.count)"))
        #expect(describeTests.contains("exploreStyleModifierChainPreservesTaskPayloads"))
        #expect(describeTests.contains("ScrollViewReader { _ in"))
        #expect(describeTests.contains("captured.taskPayloads.count == 2"))
        #expect(!renderer.contains("gtk_widget_grab_focus(widget)"))
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
            domain: "SourceHygieneTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }

    private func packageSource(_ relativePath: String) throws -> String {
        let root = try packageRoot()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func runSourceHygieneProcess(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        process.standardOutput = pipe
        process.standardError = pipe

        // Drain the pipe CONCURRENTLY. Reading only after waitUntilExit()
        // deadlocks once the child's output exceeds the ~64 KB pipe buffer: the
        // child blocks on write while we block waiting for it to exit. On a full
        // CI checkout `git ls-files` emits far more than 64 KB, which wedged the
        // entire Linux test run until the 900 s timeout. (It never deadlocked
        // locally only because an unmounted .git made git fail fast with a tiny
        // error — the "git-128" artifact that masked this.) A readabilityHandler
        // keeps the buffer drained so the child runs to completion.
        let collector = QuillProcessOutputCollector()
        let readHandle = pipe.fileHandleForReading
        readHandle.readabilityHandler = { handle in
            collector.append(handle.availableData)
        }

        try process.run()
        process.waitUntilExit()

        readHandle.readabilityHandler = nil
        collector.append(readHandle.readDataToEndOfFile())
        return (process.terminationStatus, collector.string())
    }
}

/// Thread-safe accumulator for a subprocess's piped output, fed from the pipe's
/// readabilityHandler queue so a chatty child never blocks on a full pipe.
private final class QuillProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock(); data.append(chunk); lock.unlock()
    }
    func string() -> String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private let enchantedNativeSamplePromptTitles: [String] = [
    "Give me phrases to learn in a new language",
    "Act like Mowgli from The Jungle Book and answer questions",
    "How to center div in HTML?",
    "What's unique about Go programming language?",
    "Give 10 gift ideas for best friend",
    "Write a text message asking a friend to be my plus-one at a wedding",
    "Explain supercomputers like I'm five years old",
    "How to do personal taxes in USA?",
    "What are the largest cities in USA in population? Give a table",
    "Give me ideas about New Years resolutions",
    "What is bubble sort? Write example in python"
]

private let enchantedMacReferenceVisiblePromptTitles: [String] = [
    "How to center div in HTML?",
    "How to do personal taxes in USA?",
    "Explain supercomputers like I'm five years old",
    "Write a text message asking a friend to be my plus-one at a wedding"
]

private extension String {
    func occurrences(of needle: String) -> Int {
        guard !needle.isEmpty else {
            return 0
        }

        var count = 0
        var searchStartIndex = startIndex

        while let range = range(of: needle, range: searchStartIndex..<endIndex) {
            count += 1
            searchStartIndex = range.upperBound
        }

        return count
    }
}
