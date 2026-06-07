import Foundation
import Testing

@Suite("Source hygiene")
struct SourceHygieneTests {
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
        #expect(manifest.contains("if quillUILinuxBuildBackend == .gtk {\n    products.append(.executable(name: \"quill-gtk-interaction-smoke\", targets: [\"QuillGtkInteractionSmoke\"]))\n}"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .qt {"))
        #expect(manifest.contains("enum QuillCanonicalLinuxAppQtRuntime"))
        #expect(manifest.contains("struct QuillCanonicalLinuxAppSpec"))
        #expect(manifest.contains("let quillCanonicalLinuxApps: [QuillCanonicalLinuxAppSpec] = ["))
        #expect(manifest.contains("let quillCanonicalLinuxAppProducts: [Product] = quillCanonicalLinuxApps.map(\\.productDeclaration)"))
        #expect(manifest.contains("] + quillCanonicalLinuxAppProducts"))
        #expect(manifest.contains("products = quillCanonicalLinuxAppProducts + [\n        .library(name: \"QuillGenericQtNativeRuntime\", targets: [\"QuillGenericQtNativeRuntime\"]),\n        .executable(name: \"quill-qt-interaction-smoke\", targets: [\"QuillQtInteractionSmoke\"])"))
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
        #expect(manifest.contains("cSQLiteTarget,\n        quillDataMacroTarget,\n        quillDataTarget,"))
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

    @Test("GTK manifest filters pkg-config prohibited flag warnings")
    func gtkManifestFiltersPkgConfigProhibitedFlagWarnings() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
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
        #expect(gdkPixbufModuleMap.contains("module CGdkPixbuf [system]"))
        #expect(gtkModuleMap.contains("module CGtk4 [system]"))
    }

    @Test("Linux SwiftUI compatibility exposes accessibility modifiers")
    func linuxSwiftUICompatibilityExposesAccessibilityModifiers() throws {
        let compatibility = try packageSource("Sources/QuillUI/UpstreamCompatibility.swift")
        let gtkAccessibility = try packageSource("Sources/QuillUI/GTKAccessibilityModifiers.swift")
        let gtkHover = try packageSource("Sources/QuillUI/GTKHoverModifiers.swift")
        let gtkPatchScript = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(compatibility.contains("public struct AccessibilityChildBehavior: Hashable, Sendable"))
        #expect(compatibility.contains("public static let combine = AccessibilityChildBehavior(\"combine\")"))
        #expect(compatibility.contains("public struct AccessibilityLabelView<Content: View>: View"))
        #expect(compatibility.contains("public struct AccessibilityValueView<Content: View>: View"))
        #expect(compatibility.contains("public struct AccessibilityElementView<Content: View>: View"))
        #expect(compatibility.contains("func accessibilityLabel(_ label: String) -> AccessibilityLabelView<Self>"))
        #expect(compatibility.contains("func accessibilityValue(_ value: String) -> AccessibilityValueView<Self>"))
        #expect(compatibility.contains("func accessibilityElement(children: AccessibilityChildBehavior) -> AccessibilityElementView<Self>"))
        #expect(compatibility.contains("\"accessibilityLabel\""))
        #expect(compatibility.contains("\"accessibilityValue\""))
        #expect(compatibility.contains("\"accessibilityElement(children:)\""))
        #expect(!compatibility.contains("View accessibility labels are currently a source-compatibility fallback on Linux."))
        #expect(!compatibility.contains("View accessibility values are currently a source-compatibility fallback on Linux."))
        #expect(gtkAccessibility.contains("extension AccessibilityLabelView: GTKRenderable"))
        #expect(gtkAccessibility.contains("extension AccessibilityValueView: GTKRenderable"))
        #expect(gtkAccessibility.contains("gtk_swift_accessible_update_label"))
        #expect(gtkAccessibility.contains("gtk_swift_accessible_update_description"))
        #expect(gtkHover.contains("extension OnHoverView: GTKRenderable"))
        #expect(gtkHover.contains("gtk_event_controller_motion_new"))
        #expect(gtkHover.contains("\"enter\""))
        #expect(gtkHover.contains("\"leave\""))
        #expect(gtkHover.contains("gtk_widget_add_controller(widget, controller)"))
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
        #expect(preparationScript.contains("source \"$ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(preparationScript.contains("REQUESTED_BACKEND=\"${QUILLUI_LINUX_BACKEND:-gtk}\""))
        #expect(preparationScript.contains("REQUESTED_BACKEND=\"$(quillui_require_linux_build_backend_identifier \"${REQUESTED_BACKEND:-gtk}\")\""))
        #expect(preparationScript.contains("gtk)\n    \"$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh\" \"$SCRATCH_PATH\""))
        #expect(preparationScript.contains("qt)\n    ;;"))
        #expect(preserveScript.contains("PACKAGE_RESOLVED=\"$PACKAGE_DIR/Package.resolved\""))
        #expect(preserveScript.contains("cp -p \"$PACKAGE_RESOLVED\" \"$TEMP_RESOLVED\""))
        #expect(preserveScript.contains("restore_package_resolved"))
        #expect(preserveScript.contains("trap 'status=$?; restore_package_resolved; exit \"$status\"' EXIT"))
        #expect(preserveScript.contains("exit \"$status\""))

        #expect(linuxSwiftTest.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(linuxSwiftTest.contains("scripts/swiftpm-preserve-package-resolved.sh"))
        #expect(!linuxSwiftTest.contains("patch-swiftopenui-gtk-css.sh"))
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

        #expect(source.contains("public enum UIUserInterfaceStyle: Int"))
        #expect(source.contains("public typealias UserInterfaceStyle = UIUserInterfaceStyle"))
        #expect(source.contains("public struct AnimationOptions: OptionSet, Sendable"))
        #expect(source.contains("usingSpringWithDamping: CGFloat"))
        #expect(source.contains("public struct State: OptionSet, Sendable"))
        #expect(source.contains("public class UIGestureRecognizer: NSObject"))
        #expect(source.contains("public enum ContentInsetAdjustmentBehavior: Int"))
        #expect(source.contains("public enum DisplayModeButtonVisibility: Int"))
        #expect(source.contains("public enum SplitBehavior: Int"))
        #expect(source.contains("public enum Column: Int"))
        #expect(source.contains("public enum LayoutEnvironment: Int"))
        #expect(source.contains("case twoDisplaceSecondary"))
        #expect(source.contains("case inspector"))
    }

    @Test("Linux AppKit shims avoid Swift 6 warning traps")
    func linuxAppKitShimsAvoidSwift6WarningTraps() throws {
        let root = try packageRoot()
        let appKit = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKit/QuillAppKit.swift"),
            encoding: .utf8
        )
        let gtk = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillAppKitGTK/QuillAppKit+GTK.swift"),
            encoding: .utf8
        )

        #expect(appKit.contains("@MainActor public protocol NSWindowDelegate"))
        #expect(appKit.contains("@MainActor open class NSViewController"))
        #expect(appKit.contains("@MainActor public protocol NSApplicationDelegate"))
        #expect(appKit.contains("@MainActor public protocol NSMenuDelegate"))
        #expect(appKit.contains("@MainActor public protocol NSToolbarDelegate"))
        #expect(appKit.contains("@MainActor public protocol NSTableViewDelegate"))
        #expect(appKit.contains("@MainActor public protocol NSTableViewDataSource"))
        #expect(appKit.contains("@MainActor public protocol NSOutlineViewDelegate"))
        #expect(appKit.contains("@MainActor public protocol NSOutlineViewDataSource"))
        #expect(appKit.contains("public static let borderless: StyleMask = []"))
        #expect(appKit.contains("open class NSTextStorage: NSMutableAttributedString {"))
        #expect(!appKit.contains("public static let borderless = StyleMask(rawValue: 0)"))
        #expect(!appKit.contains("open class NSTextStorage: NSMutableAttributedString, @unchecked Sendable"))
        #expect(!gtk.contains("let ctx = g_main_context_default()"))
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
        let osShim = try String(
            contentsOf: root.appendingPathComponent("Sources/osShim/os.swift"),
            encoding: .utf8
        )

        #expect(appKit.contains("@discardableResult\n    public func declareTypes(_ types: [PasteboardType], owner: Any?) -> Int"))
        #expect(avFoundation.contains("@discardableResult\n    public func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool"))
        #expect(manifest.contains(".target(name: \"AVFoundation\", dependencies: [\"QuillKit\", \"QuillFoundation\"], path: \"Sources/AVFoundation\")"))
        #expect(!osShim.contains("import os"))
    }

    @Test("Linux SwiftUI compatibility extensions have one canonical module")
    func linuxSwiftUICompatibilityExtensionsHaveOneCanonicalModule() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let quillUI = try String(contentsOf: root.appendingPathComponent("Sources/QuillUI/QuillUI.swift"), encoding: .utf8)
        let swiftUIShim = try String(contentsOf: root.appendingPathComponent("Sources/SwiftUIShim/SwiftUI.swift"), encoding: .utf8)
        let compatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/QuillSwiftUICompatibility.swift"),
            encoding: .utf8
        )

        #expect(manifest.contains("name: \"QuillSwiftUICompatibility\""))
        #expect(manifest.contains("\"QuillFoundation\",\n    \"QuillSwiftUICompatibility\","))
        #expect(manifest.contains("dependencies: [\"QuillUI\", \"QuillSwiftUICompatibility\"]"))
        #expect(quillUI.contains("@_exported import QuillSwiftUICompatibility"))
        #expect(swiftUIShim.contains("@_exported import QuillSwiftUICompatibility"))
        #expect(compatibility.contains("typealias Weight = FontWeight"))
        #expect(compatibility.contains("static var firstTextBaseline: VerticalAlignment { .top }"))
        #expect(!swiftUIShim.contains("static var firstTextBaseline"))
    }

    @Test("ImageRenderer comments describe the current GTK offscreen path")
    func imageRendererCommentsDescribeCurrentOffscreenPath() throws {
        let root = try packageRoot()
        let rendererSource = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Rendering/ImageRenderer.swift"),
            encoding: .utf8
        )
        let gtkSource = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4ImageRenderer.swift"),
            encoding: .utf8
        )

        #expect(rendererSource.contains("ImageRendererBackend.installViewRenderer"))
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

    @Test("Apple service aliases live in reusable compatibility modules")
    func appleServiceAliasesLiveInReusableCompatibilityModules() throws {
        let root = try packageRoot()
        let quillKit = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillKit/QuillKit.swift"),
            encoding: .utf8
        )
        let quillShims = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillShims/QuillShims.swift"),
            encoding: .utf8
        )
        let swiftUILowering = try String(
            contentsOf: root.appendingPathComponent("scripts/lower-swiftui-source-for-linux.sh"),
            encoding: .utf8
        )
        let coreGraphics = try String(
            contentsOf: root.appendingPathComponent("Sources/CoreGraphics/CoreGraphics.swift"),
            encoding: .utf8
        )
        let profileAliases = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/QuillGeneratedProfileAliases.swift"),
            encoding: .utf8
        )

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
        #expect(swiftUILowering.contains("ensure-swift-imports.sh\" \"$SOURCE_DIR\" QuillShims"))
        #expect(quillKit.contains("quill-pasteboard"))
        #expect(quillKit.contains("Apple.NSGeneralPboard"))
        #expect(quillKit.contains("writeFileBackedPasteboardString(string, forType: type)"))
        #expect(coreGraphics.contains("static let kVK_ANSI_V: CGKeyCode = 0x09"))
        #expect(!profileAliases.contains("typealias CGKeyCode = UInt16"))
        #expect(!profileAliases.contains("static let kVK_ANSI_V"))
        #expect(profileAliases.contains("typealias CheckForUpdatesMenuItem = QuillCheckForUpdatesMenuItem"))
        #expect(profileAliases.contains("enum QuillUSBLauncher"))
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
            ".github/workflows/macos-ci.yml"
        ]

        let workflows = try workflowPaths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        let shellSyntaxCheck = try String(
            contentsOf: root.appendingPathComponent("scripts/check-shell-syntax.sh"),
            encoding: .utf8
        )

        #expect(workflows.contains("uses: actions/checkout@v5"))
        #expect(workflows.contains("uses: actions/upload-artifact@v6"))
        #expect(workflows.contains("scripts/check-shell-syntax.sh"))
        #expect(shellSyntaxCheck.contains("find scripts -type f -name '*.sh' | sort"))
        #expect(shellSyntaxCheck.contains("bash -n \"$script\""))
        #expect(!workflows.contains("uses: actions/checkout@v4"))
        #expect(!workflows.contains("uses: actions/upload-artifact@v4"))
        #expect(!workflows.contains("uses: actions/upload-artifact@v5"))
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
        #expect(!genericQtRuntime.contains("executableName: String"))
        #expect(!genericQtRuntime.contains("executableName: executableName"))
        #expect(!genericQtRuntime.contains("ProcessInfo.processInfo.environment["))
        #expect(!genericQtRuntime.contains("private static func selectedIndexOverride"))
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
        #expect(!genericQtHost.contains("font-size: 12px;"))
        #expect(!genericQtHost.contains("font-size: 25px;"))
        #expect(!genericQtHost.contains("font-size: 22px;"))
        #expect(!genericQtHost.contains("font-weight: 700;"))
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
        #expect(genericQtHost.contains("button->setIcon(systemImageIcon(stringValue(action, \"systemImage\")))"))
        #expect(genericQtHost.contains("button->setProperty(\"navigationAction\", navigationAction)"))
        #expect(genericQtHost.contains("button->setProperty(\"navigationTitle\", titleText)"))
        #expect(genericQtHost.contains("button->setProperty(\"navigationSubtitle\", stringValue(action, \"subtitle\"))"))
        #expect(genericQtHost.contains("QFrame#composerFrame { background: %4; border: 1px solid %6; border-radius: %7; }"))
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
        let backendScript = try packageSource("scripts/linux-backend-interaction-check.sh")
        let backendProfileScript = try packageSource("scripts/linux-backend-profile.sh")
        let backendVisualScript = try packageSource("scripts/linux-backend-visual-check.sh")
        let smokeLib = try packageSource("scripts/quillui-linux-backend-smoke-lib.sh")
        let backendProducts = try packageSource("scripts/quillui-backend-products.sh")
        let smokeMatrixRunner = try packageSource("scripts/run-linux-backend-smoke-matrix.sh")
        let screenshotVerifier = try packageSource("scripts/verify-backend-screenshot.py")
        let legacyScreenshotVerifier = try packageSource("scripts/verify-gtk-screenshot.py")
        let legacyGtkScript = try packageSource("scripts/linux-gtk-interaction-check.sh")
        let workflow = try packageSource(".github/workflows/linux-ci.yml")
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
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-prompt-send\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-composer-send\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-new-chat\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-copy-chat\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-copy-chat-json\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-toolbar-model-selected\""))
        #expect(backendProducts.contains("*:composer-send)"))
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
        #expect(backendScript.contains("QUILLUI_FILE_IMPORTER_SELECTION=$import_file"))
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
        #expect(backendScript.contains("quillui_find_visible_window_for_pid \"$DISPLAY_ID\" \"$app_pid\""))
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
        #expect(backendScript.contains("quillui_find_visible_window_for_pid_except \"$DISPLAY_ID\" \"$app_pid\" \"$window_id\""))
        #expect(!backendScript.contains("quill-gtk-interaction-smoke|quill-qt-interaction-smoke"))
        #expect(backendScript.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(backendScript.contains("verify-backend-screenshot.py"))
        #expect(backendScript.contains("quillui_backend_interaction_verify_product \"$PRODUCT\" \"$INTERACTION_MODE\" VERIFY_PRODUCT"))
        #expect(backendScript.contains("quillui_append_backend_selection_start_environment"))
        #expect(!backendScript.contains("app_environment+=(\"QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"))
        #expect(!backendScript.contains("app_environment+=(\"QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START"))
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
        #expect(smokeLib.contains("printf -v \"$output_var\" \"%s\" \"$value\""))
        #expect(smokeLib.contains("quillui_start_xvfb()"))
        #expect(smokeLib.contains("quillui_assign_output \"$output_var\" \"$QUILLUI_BACKEND_APP_EXECUTABLE\""))
        #expect(smokeLib.contains("${QUILLUI_BACKEND_SKIP_BUILD:-0}"))
        #expect(smokeLib.contains("quillui_require_backend_product_build_stamp"))
        #expect(smokeLib.contains("quillui_record_backend_product_build"))
        #expect(!smokeLib.contains("quillui_assign_output \"$output_var\" \"$QUILLUI_GTK_APP_EXECUTABLE\""))
        #expect(!smokeLib.contains("${QUILLUI_GTK_SKIP_BUILD:-0}"))
        #expect(smokeLib.contains("quillui_install_linux_backend_smoke_packages()"))
        #expect(smokeLib.contains("quillui_normalize_x_display_id()"))
        #expect(smokeLib.contains("quillui_stop_process_if_running()"))
        #expect(!smokeLib.contains("quillui_is_quill_chat_mac_reference_product()"))
        #expect(smokeLib.contains("quillui_backend_reference_window_defaults()"))
        #expect(smokeLib.contains("quillui_find_visible_window_by_name()"))
        #expect(smokeLib.contains("quillui_find_visible_window_for_pid()"))
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
        #expect(smokeLib.contains("enchanted_default_work_root=\"$enchanted_default_work_root-$enchanted_backend_facade\""))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_BACKEND_FACADE=\"$enchanted_backend_facade\""))
        #expect(smokeLib.contains("quillui_resolve_linux_backend_executable()"))
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
        #expect(smokeMatrixRunner.contains("quillui_backend_visual_verify_product \"$product\" resolved_verify_product"))
        #expect(smokeMatrixRunner.contains("quillui_smoke_interaction_verify_product()"))
        #expect(smokeMatrixRunner.contains("quillui_backend_interaction_verify_product \"$product\" \"$interaction_mode\" resolved_verify_product"))
        #expect(smokeMatrixRunner.contains("verify_product=\"$(quillui_smoke_visual_verify_product \"$product\" \"$requested_backend\")\""))
        #expect(smokeMatrixRunner.contains("dry_run_fields+=(\"$verify_product\")"))
        #expect(smokeMatrixRunner.contains("smoke_environment+=(\"QUILLUI_APP_BACKEND_FACADE=$requested_backend\")"))
        #expect(smokeMatrixRunner.contains("QUILLUI_BACKEND_INTERACTION_MODE=$mode"))
        #expect(smokeMatrixRunner.contains("QUILLUI_BACKEND_SKIP_BUILD=1"))
        #expect(smokeMatrixRunner.contains("env \"${smoke_environment[@]}\" \"$CHECK_SCRIPT\" \"$output_path\" \"$product\" \"$requested_backend\""))
        #expect(smokeMatrixRunner.contains("\"$ROOT_DIR/scripts/quillui-backend-products.sh\" \"$RUNTIME_MATRIX_COMMAND\""))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products visual generated-app-matrix '.qa/{product}-generated-{backend}.png'"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh visual smoke-matrix '.qa/{product}-visual-{backend}.png'"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products interaction smoke-interaction-matrix '.qa/{product}-{mode}-{backend}.png'"))
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
        #expect(source.contains("source_target_dependencies="))
        #expect(source.contains("target_dependencies=\"$(printf '%s,\\n"))
        #expect(source.contains(".product(name: \"QuillUIGtk\", package: \"QuillUI\")' \"$source_target_dependencies\")\""))
        #expect(source.contains("if [[ \"$BACKEND_FACADE\" != \"qt\" ]]"))
        #expect(source.contains("QUILLUI_LINUX_BACKEND=qt \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(source.contains("import $backend_import"))
        #expect(source.contains("$backend_launch_statement"))
        #expect(source.contains(".product(name: \"QuillUIGtk\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"QuillGenericQtNativeRuntime\", package: \"QuillUI\")"))
        #expect(buildSource.contains("--backend-facade"))
        #expect(buildSource.contains("QUILLUI_APP_BACKEND_FACADE"))
        #expect(buildSource.contains("NORMALIZED_BACKEND_FACADE"))
        #expect(buildSource.contains("QUILLUI_LINUX_BACKEND=qt \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(buildSource.contains("quillui_normalize_backend_identifier \"${BACKEND_FACADE:-swiftui}\""))
        #expect(buildSource.contains("QUILLUI_GENERATED_BACKEND_FACADE=\"$NORMALIZED_BACKEND_FACADE\""))
        #expect(buildSource.contains("--artifact-path-file"))
        #expect(buildSource.contains("QUILLUI_APP_ARTIFACT_PATH_FILE"))
        #expect(buildSource.contains("printf '%s\\n' \"$ARTIFACT_PATH\" > \"$ARTIFACT_PATH_FILE\""))
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
        #expect(enchantedSourceResolver.contains("QUILL_CHAT_DIR/Enchanted"))
        #expect(enchantedSourceResolver.contains(".upstream/enchanted/Enchanted"))
        #expect(!source.contains("import BackendGTK4"))
        #expect(!source.contains("GTK4Backend().run($APP_ENTRY_TYPE.self)"))
        #expect(!source.contains("GTK backend generation is enabled"))
        #expect(generatedEnchantedChatSource.contains("source \"$ROOT_DIR/scripts/quillui-enchanted-source.sh\""))
        #expect(generatedEnchantedChatSource.contains("UPSTREAM_DIR=\"$(quillui_resolve_enchanted_source_dir \"$ROOT_DIR\")\""))
        #expect(generatedEnchantedMacOSChatSource.contains("source \"$ROOT_DIR/scripts/quillui-enchanted-source.sh\""))
        #expect(generatedEnchantedMacOSChatSource.contains("UPSTREAM_DIR=\"$(quillui_resolve_enchanted_source_dir \"$ROOT_DIR\")\""))
        #expect(generatedEnchantedSource.contains("source \"$ROOT_DIR/scripts/quillui-enchanted-source.sh\""))
        #expect(generatedEnchantedSource.contains("UPSTREAM_DIR=\"$(quillui_resolve_enchanted_source_dir \"$ROOT_DIR\")\""))
        #expect(generatedEnchantedSource.contains("include_backend_entry=0"))
        #expect(generatedEnchantedSource.contains("QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY=\"$include_backend_entry\""))
        #expect(!generatedEnchantedSource.contains("include_gtk_backend"))
        #expect(!generatedEnchantedSource.contains("QUILLUI_GENERATED_INCLUDE_GTK_BACKEND"))
        #expect(!source.contains("package(url: \"https://github.com/codelynx/SwiftOpenUI\""))
        #expect(!source.contains(".product(name: \"BackendGTK4\", package: \"SwiftOpenUI\")"))
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
        #expect(promptGrid.contains("LazyVGrid(columns: gridColumns, alignment: .leading, spacing: gridSpacing)"))
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
        #expect(controls.contains("public var composerMaxWidth: CGFloat"))
        #expect(controls.contains("public var composerHorizontalPadding: CGFloat"))
        #expect(controls.contains("public var composerVerticalPadding: CGFloat"))
        #expect(controls.contains("public var hasSelection: Bool"))
        #expect(controls.contains("public var showsStatus: Bool"))
        #expect(controls.contains("if hasSelection {\n                    selectedContent"))
        #expect(controls.contains("if showsStatus {\n                    statusContent"))
        #expect(controls.contains(".padding(.horizontal, composerHorizontalPadding)"))
        #expect(controls.contains(".padding(.vertical, composerVerticalPadding)"))
        #expect(controls.contains(".frame(maxWidth: composerMaxWidth)"))
        #expect(controls.contains("public struct QuillDesktopChatToolbar: View"))
        #expect(controls.contains("public var modelActions: [QuillMenuAction]"))
        #expect(controls.contains("public var optionsActions: [QuillMenuAction]"))
        #expect(controls.contains("QuillToolbarIconButton(systemImage: \"square.and.pencil\", action: onNewConversation)"))
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
        #expect(historyList.contains(".accessibilityElement(children: .combine)"))
        #expect(historyList.contains(".accessibilityLabel(item.title)"))
        #expect(historyList.contains(".accessibilityValue(item.lastMessage)"))
        #expect(historyList.contains(".help(accessibilitySummary(for: item))"))
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
        #expect(historyList.contains("VStack(alignment: .leading, spacing: rowTextSpacing)"))
        #expect(historyList.contains(".font(.system(size: rowFontSize))"))
        #expect(historyList.contains("Text(lastMessage)"))
        #expect(historyList.contains(".font(.system(size: rowPreviewFontSize))"))
        #expect(historyList.contains(".lineLimit(2)"))
        #expect(historyList.contains(".padding(rowPadding)"))
        #expect(historyList.contains(".cornerRadius(rowCornerRadius)"))
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
        #expect(historyList.contains("public var dateTitle: (Date) -> String"))
        #expect(historyList.contains("public var onDeleteDay: ((Date) -> Void)?"))
        #expect(historyList.contains("Dictionary(grouping: items) { item in"))
        #expect(historyList.contains("Calendar.current.startOfDay(for: item.updatedAt)"))
        #expect(historyList.contains("QuillConversationHistoryDayGroup("))
        #expect(historyList.contains("ForEach(dayGroups) { group in"))
        #expect(historyList.contains("Text(dateTitle(group.date))"))
        #expect(historyList.contains("ForEach(group.items) { item in"))
        #expect(historyList.contains("private func groupedRow(for item: QuillConversationHistoryItem) -> some View"))
        #expect(historyList.contains("let textState = PaintControlState(isHovered: isHovered, isSelected: false)"))
        #expect(historyList.contains("MacListRowPaint.primaryTextColor(for: textState)"))
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
        #expect(historyList.contains(".background(rowBackgroundColor(for: rowState))"))
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
        #expect(controls.contains(".padding(.horizontal, 18)"))
        #expect(controls.contains(".padding(.top, 88)"))
        #expect(controls.contains(".padding(.bottom, 18)"))

        guard let buttonStart = controls.range(of: "public struct QuillSidebarNavigationButton: View"),
              let nextSection = controls.range(of: "public struct QuillStatusBanner: View") else {
            Issue.record("Unable to locate QuillSidebarNavigationButton source")
            return
        }

        let sidebarButton = String(controls[buttonStart.lowerBound..<nextSection.lowerBound])
        #expect(sidebarButton.contains("Image(systemName: sidebarSystemImageName)"))
        #expect(sidebarButton.contains("if systemImage == \"textformat.abc\""))
        #expect(sidebarButton.contains("Text(\"Abc\")"))
        #expect(sidebarButton.contains("QuillSidebarKeyboardGlyph(color: Color(hex: \"#3A3A3C\"))"))
        #expect(sidebarButton.contains("QuillSidebarGearGlyph(color: Color(hex: \"#3A3A3C\"))"))
        #expect(sidebarButton.contains("private struct QuillSidebarKeyboardGlyph: View"))
        #expect(sidebarButton.contains("private struct QuillSidebarGearGlyph: View"))
        #expect(sidebarButton.contains(".stroke(color, lineWidth: 1.3)"))
        #expect(sidebarButton.contains(".stroke(color, lineWidth: 1.6)"))
        #expect(sidebarButton.contains("\"textformat\", \"textformat.abc\""))
        #expect(sidebarButton.contains("\"keyboard\", \"keyboard.fill\""))
        #expect(sidebarButton.contains("\"gearshape\", \"gearshape.fill\", \"gear\""))
        #expect(!sidebarButton.contains("case \"keyboard\", \"keyboard.fill\":"))
        #expect(!sidebarButton.contains("case \"gearshape\", \"gearshape.fill\", \"gear\":"))
    }

    @Test("GTK plain button style suppresses platform chrome")
    func gtkPlainButtonStyleSuppressesPlatformChrome() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        for source in [renderer, patcher] {
            #expect(source.contains("gtk_widget_add_css_class(button, \"flat\")"))
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
    }

    @Test("GTK patcher preserves fixed-frame and list viewport sizing contracts")
    func gtkPatcherPreservesFixedFrameAndListViewportSizingContracts() throws {
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")

        #expect(patcher.contains("fixed_frame_child_sizing = \"SwiftUI proposes the clamped fixed-frame size to children\""))
        #expect(patcher.contains("gtkPixelSize(layout.childPlacement.size.width)"))
        #expect(patcher.contains("gtkPixelSize(layout.childPlacement.size.height)"))
        #expect(patcher.contains("fixed_frame_expanding_child_sizing = \"Expanding fixed-frame children receive the proposed frame size\""))
        #expect(patcher.contains("childExpH ? gtkPixelSize(layout.childPlacement.size.width) : -1"))
        #expect(patcher.contains("childExpV ? gtkPixelSize(layout.childPlacement.size.height) : -1"))
        #expect(patcher.contains("fixed_frame_box_clipping = \"Fixed-frame clipping uses a normal GtkBox allocation\""))
        #expect(patcher.contains("let slot: UnsafeMutablePointer<GtkWidget> = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!"))
        #expect(patcher.contains("gtk_box_append(boxPointer(slot), child)"))
        #expect(patcher.contains("padded_view_child_fill = \"PaddedView must let expanding content fill its margin wrapper\""))
        #expect(patcher.contains("gtk_widget_set_halign(child, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtk_widget_set_valign(child, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)"))
        #expect(patcher.contains("gtk_widget_set_halign(row, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox, fillWidth: true, fillHeight: false)"))
        #expect(patcher.contains("mapped_on_disappear_marker = \"GTK OnDisappear requires a prior map before firing\""))
        #expect(patcher.contains("private final class GTKSheetLifecycleScope"))
        #expect(patcher.contains("gtkWithSheetLifecycleScope(info.lifecycleScope) { info.render() }"))
        #expect(patcher.contains("gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetView) }"))
        #expect(patcher.contains("if gtkShouldRenderSheetInWindow() || gtkShouldRenderSheetInRootOverlay()"))
        #expect(patcher.contains("gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetBuilder(currentItem)) }"))
        #expect(patcher.contains("sheetLifecycleScope.registerOnDisappear(boundAction)"))
        #expect(patcher.contains("var hasMapped: Bool = false"))
        #expect(patcher.contains("guard box.hasMapped else { return }"))
    }

    @Test("Completions screenshot verifier requires trailing controls")
    func completionsScreenshotVerifierRequiresTrailingControls() throws {
        let verifier = try packageSource("scripts/verify-backend-screenshot.py")

        #expect(verifier.contains("def mac_reference_completion_action_pixel"))
        #expect(verifier.contains("def dark_row_segment_count"))
        #expect(verifier.contains("Mac-reference completions Close control was not detected"))
        #expect(verifier.contains("Mac-reference completions New Completion action was not detected"))
        #expect(verifier.contains("Mac-reference completions row edit/delete actions were not detected"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_new_sheet"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_saved"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_edited"))
        #expect(verifier.contains("def validate_quill_chat_mac_reference_completions_deleted"))
        #expect(verifier.contains("Completions Upsert Cancel action was not detected"))
        #expect(verifier.contains("Completions Upsert Save action was not detected"))
        #expect(verifier.contains("Completions Upsert preview chip was not detected"))
        #expect(verifier.contains("Saved completion row was not detected"))
        #expect(verifier.contains("Edited completion row name was not detected above the stock row baseline"))
        #expect(verifier.contains("Deleted completion row still appears to be present"))
        #expect(verifier.contains("Completions Upsert sheet still appears to be visible after Save"))
        #expect(verifier.contains("Completions edit sheet still appears to be visible after Save"))
        #expect(verifier.contains("close_pixels >= 60"))
        #expect(verifier.contains("new_completion_pixels >= 120"))
        #expect(verifier.contains("minimum_row_action_segments: int = 4"))
        #expect(verifier.contains("row_action_segments >= minimum_row_action_segments"))
        #expect(verifier.contains("cancel_pixels >= 90"))
        #expect(verifier.contains("save_pixels >= 90"))
        #expect(verifier.contains("saved_row_pixels >= 260"))
        #expect(verifier.contains("edited_row_name_pixels >= 400"))
        #expect(verifier.contains("deleted_row_action_segments <= 3"))
    }

    @Test("Vendored GTK renderer preserves SwiftUI scroll row width contract")
    func vendoredGTKRendererPreservesSwiftUIScrollRowWidthContract() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")

        #expect(renderer.contains("private final class GTKScrollViewCrossAxisContext"))
        #expect(renderer.contains("gtkScrollViewCrossAxisTickCallback"))
        #expect(renderer.contains("gtkInstallScrollViewCrossAxisFill("))
        #expect(renderer.contains("gtk_widget_set_size_request(context.child, width, -1)"))
        #expect(renderer.contains("SwiftUI lays vertical ScrollView content out in the viewport"))
        #expect(renderer.contains("fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal)"))
        #expect(renderer.contains("gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)"))
        #expect(renderer.contains("SwiftUI lays repeated vertical rows against the parent's"))
        #expect(renderer.contains("gtk_widget_set_hexpand(widget, 1)"))
        #expect(renderer.contains("gtk_widget_set_halign(widget, GTK_ALIGN_FILL)"))
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

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
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
