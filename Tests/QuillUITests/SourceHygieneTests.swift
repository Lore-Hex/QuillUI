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
        #expect(manifest.occurrences(of: "name: \"QuillEnchantedQtNativeRuntime\"") == 1)
        #expect(manifest.occurrences(of: "name: \"QuillWireGuardQtNativeRuntime\"") == 1)
        #expect(!manifest.contains("pkgConfig: \"Qt6Widgets\""))
        #expect(manifest.contains(".unsafeFlags(qt6WidgetsCxxFlags)"))
        #expect(manifest.contains(".unsafeFlags(qt6WidgetsLinkerFlags)"))
        #expect(manifest.contains("#if !os(Linux)\nproducts.append(.executable(name: \"quill-enchanted-qt\", targets: [\"QuillEnchantedQt\"]))\nproducts.append(.executable(name: \"quill-wireguard-qt\", targets: [\"QuillWireGuardQt\"]))"))
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
        #expect(manifest.contains("qtRuntime: .enchantedQtNative"))
        #expect(manifest.contains("qtRuntime: .genericQtNative"))
        #expect(manifest.contains("qtRuntime: .wireGuardQtNative"))
        #expect(manifest.contains("name: \"QuillQtNativeRuntimeSupport\""))
        #expect(manifest.contains("path: \"Sources/QuillQtNativeRuntimeSupport\""))
        #expect(manifest.contains(".library(name: \"QuillGenericQtNativeRuntime\", targets: [\"QuillGenericQtNativeRuntime\"])"))
        #expect(manifest.contains("dependencies: [\"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(manifest.contains("dependencies: [\"QuillWireGuardCore\", \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(manifest.contains("name: \"QuillGenericQtNativeRuntime\""))
        #expect(manifest.contains("path: \"Sources/QuillGenericQtNativeRuntime\""))
        #expect(manifest.contains("qtPath: \"Sources/QuillSignalQt\""))
        #expect(manifest.contains("qtPath: \"Sources/QuillWireGuardQt\""))
        #expect(!manifest.contains("products = [\n        .executable(name: \"quill-enchanted-qt\""))
        #expect(manifest.contains("allPackageDependencies = []"))
        #expect(manifest.contains("let packageTestTargets: [Target] = {"))
        #expect(manifest.contains("name: \"QuillQtBackendManifestTests\""))
        #expect(manifest.contains("name: \"QuillEnchantedTests\""))
        #expect(manifest.contains("dependencies: [\"QuillEnchantedCore\", \"QuillUI\"]"))
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

    @Test("Linux build preparation is gated by the selected backend")
    func linuxBuildPreparationIsGatedBySelectedBackend() throws {
        let root = try packageRoot()
        let fileManager = FileManager.default
        let preparationScriptURL = root.appendingPathComponent("scripts/prepare-linux-build-backend.sh")
        let preparationScript = try String(contentsOf: preparationScriptURL, encoding: .utf8)
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
        #expect(preparationScript.contains("source \"$ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(preparationScript.contains("REQUESTED_BACKEND=\"${QUILLUI_LINUX_BACKEND:-gtk}\""))
        #expect(preparationScript.contains("REQUESTED_BACKEND=\"$(quillui_require_linux_build_backend_identifier \"${REQUESTED_BACKEND:-gtk}\")\""))
        #expect(preparationScript.contains("gtk)\n    \"$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh\" \"$SCRATCH_PATH\""))
        #expect(preparationScript.contains("qt)\n    ;;"))

        #expect(linuxSwiftTest.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(!linuxSwiftTest.contains("patch-swiftopenui-gtk-css.sh"))
        #expect(backendBuildScript.contains("quillui_prepare_backend_once()"))
        #expect(backendBuildScript.contains("PREPARED_BACKENDS=$'\\n'"))
        #expect(backendBuildScript.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(backendBuildScript.contains("--backend \"$build_backend\""))
        #expect(!backendBuildScript.contains("if [[ \"$DRY_RUN\" != \"1\" ]]; then\n  \"$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh\""))
        #expect(smokeLib.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(smokeLib.contains("--backend \"$linux_build_backend\""))
        #expect(!smokeLib.contains("scripts/patch-swiftopenui-gtk-css.sh"))
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

    @Test("ImageRenderer comments describe the current GTK offscreen path")
    func imageRendererCommentsDescribeCurrentOffscreenPath() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/GdkPixbufTranscode.swift"),
            encoding: .utf8
        )

        #expect(source.contains("QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1"))
        #expect(!source.contains("not yet wired up; see the TODO on `ImageRenderer`"))
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
            "Sources/QuillWireGuard/main.swift",
            "Sources/QuillEnchantedCore/EnchantedApp.swift",
            "Sources/QuillEnchantedUpstreamSlice/main.swift"
        ]
        let appLauncherPaths = [
            "Sources/QuillSignal/main.swift": "QuillApp.run(QuillSignalApp.self)",
            "Sources/QuillTelegram/main.swift": "QuillApp.run(QuillTelegramApp.self)",
            "Sources/QuillIINA/main.swift": "QuillApp.run(QuillIINAApp.self)",
            "Sources/QuillCodeEdit/main.swift": "QuillApp.run(QuillCodeEditApp.self)",
            "Sources/QuillNetNewsWire/main.swift": "QuillApp.run(QuillNetNewsWireApp.self)",
            "Sources/QuillIceCubes/main.swift": "QuillApp.run(QuillIceCubesApp.self)",
            "Sources/QuillWireGuard/main.swift": "QuillApp.run(QuillWireGuardApp.self)",
            "Sources/QuillEnchanted/main.swift": "QuillApp.run(QuillEnchantedApp.self)",
            "Sources/QuillEnchantedUpstreamSlice/main.swift": "QuillApp.run(UpstreamSliceApp.self)"
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
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let gtkMain = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillGtkInteractionSmoke/main.swift"),
            encoding: .utf8
        )
        let qtMain = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillQtInteractionSmoke/main.swift"),
            encoding: .utf8
        )
        let sharedView = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillInteractionSmokeSupport/QuillInteractionSmokeView.swift"),
            encoding: .utf8
        )
        let enchantedConversationStore = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/QuillDataConversationStore.swift"),
            encoding: .utf8
        )
        let wireGuardQtHost = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillWireGuardQt6Widgets.cpp"),
            encoding: .utf8
        )
        let enchantedQtRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedQtNativeRuntime/QuillEnchantedQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let enchantedQtHost = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillEnchantedQt6Widgets.cpp"),
            encoding: .utf8
        )
        let genericQtHost = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillGenericQt6Widgets.cpp"),
            encoding: .utf8
        )
        let genericQtRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillGenericQtNativeRuntime/QuillGenericQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let qtRuntimeSupport = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillQtNativeRuntimeSupport/QuillQtNativeRuntimeSupport.swift"),
            encoding: .utf8
        )
        let wireGuardQtRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillWireGuardQtNativeRuntime/QuillWireGuardQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let qtNativeSmokeHost = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillInteractionSmokeQt6Widgets.cpp"),
            encoding: .utf8
        )
        let qtNativeWidgetSupport = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillQtWidgetsSupport.hpp"),
            encoding: .utf8
        )
        let backendCore = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/QuillBackend.swift"),
            encoding: .utf8
        )
        let appCore = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/QuillApp.swift"),
            encoding: .utf8
        )
        let gtkBackend = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUIGtk/QuillUIGtk.swift"),
            encoding: .utf8
        )
        let qtBackend = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUIQt/QuillUIQt.swift"),
            encoding: .utf8
        )
        let backendScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-interaction-check.sh"),
            encoding: .utf8
        )
        let backendProfileScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-profile.sh"),
            encoding: .utf8
        )
        let backendVisualScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-visual-check.sh"),
            encoding: .utf8
        )
        let smokeLib = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-linux-backend-smoke-lib.sh"),
            encoding: .utf8
        )
        let backendProducts = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-backend-products.sh"),
            encoding: .utf8
        )
        let smokeMatrixRunner = try String(
            contentsOf: root.appendingPathComponent("scripts/run-linux-backend-smoke-matrix.sh"),
            encoding: .utf8
        )
        let screenshotVerifier = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-backend-screenshot.py"),
            encoding: .utf8
        )
        let legacyScreenshotVerifier = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-gtk-screenshot.py"),
            encoding: .utf8
        )
        let legacyGtkScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-interaction-check.sh"),
            encoding: .utf8
        )
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"),
            encoding: .utf8
        )
        let macOSWorkflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/macos-ci.yml"),
            encoding: .utf8
        )

        #expect(manifest.contains(".library(name: \"QuillUIGtk\", targets: [\"QuillUIGtk\"])"))
        #expect(manifest.contains(".library(name: \"QuillUIQt\", targets: [\"QuillUIQt\"])"))
        #expect(manifest.contains("if quillUILinuxBuildBackend == .gtk {"))
        #expect(manifest.contains("products.append(.executable(name: \"quill-gtk-interaction-smoke\", targets: [\"QuillGtkInteractionSmoke\"]))"))
        #expect(manifest.contains(".executable(name: \"quill-qt-interaction-smoke\", targets: [\"QuillQtInteractionSmoke\"])"))
        #expect(manifest.contains("name: \"QuillInteractionSmokeSupport\""))
        #expect(manifest.contains("dependencies: [\"QuillUIGtk\", \"QuillInteractionSmokeSupport\"]"))
        #expect(manifest.contains("func quillLinuxBackendDependencies("))
        #expect(manifest.contains("nativeQt: [\"QuillEnchantedQtNativeRuntime\"]"))
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
        #expect(qtRuntimeSupport.contains("public static func runEncodedPayload<Payload: Encodable>"))
        #expect(qtRuntimeSupport.contains("encoder.outputFormatting = [.sortedKeys]"))
        #expect(qtRuntimeSupport.contains("fputs(\"\\(executableName): failed to encode Qt payload: \\(error)\\n\", stderr)"))
        #expect(qtNativeWidgetSupport.contains("inline bool parseJsonObjectPayload("))
        #expect(qtNativeWidgetSupport.contains("inline QByteArray executableNameBytes("))
        #expect(qtNativeWidgetSupport.contains("QString::fromLocal8Bit(argv[0]).trimmed()"))
        #expect(qtNativeWidgetSupport.contains("inline QSize minimumWindowSize("))
        #expect(qtNativeWidgetSupport.contains("inline QSize defaultWindowSize("))
        #expect(qtNativeWidgetSupport.contains("%s: missing payload JSON\\n"))
        #expect(qtNativeWidgetSupport.contains("%s: invalid payload JSON at offset %lld: %s\\n"))
        #expect(enchantedQtRuntime.contains("import QuillQtNativeRuntimeSupport"))
        #expect(enchantedQtRuntime.contains("QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START"))
        #expect(enchantedQtRuntime.contains("QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"))
        #expect(enchantedQtRuntime.contains("private static let selectedConversationIndexEnvironmentKeys = ["))
        #expect(enchantedQtRuntime.contains("var messages: [Message]? = nil"))
        #expect(enchantedQtRuntime.contains("messages: launchConversationMessages"))
        #expect(enchantedQtRuntime.contains("messages: attachmentConversationMessages"))
        #expect(enchantedQtRuntime.contains("QuillQtNativeRuntimeSupport.boundedIndexOverride("))
        #expect(enchantedQtRuntime.contains("environmentKeys: selectedConversationIndexEnvironmentKeys"))
        #expect(!enchantedQtRuntime.contains("ProcessInfo.processInfo.environment["))
        #expect(enchantedQtRuntime.contains("snapshot.selectedConversationID = snapshot.conversations[boundedIndex].id"))
        #expect(enchantedQtRuntime.contains("QuillQtNativeRuntimeSupport.runEncodedPayload("))
        #expect(enchantedQtRuntime.contains("executableName: QuillQtNativeRuntimeSupport.executableName(fallback: \"quill-enchanted-qt\")"))
        #expect(enchantedQtHost.contains("parseJsonObjectPayload("))
        #expect(enchantedQtHost.contains("QuillQtWidgets::executableNameBytes(argc, argv, \"quill-enchanted-qt\")"))
        #expect(enchantedQtHost.contains("executableName.constData()"))
        #expect(enchantedQtHost.contains("QuillQtWidgets::minimumWindowSize(payload, 980, 680)"))
        #expect(enchantedQtHost.contains("QuillQtWidgets::defaultWindowSize(payload, minimumWindowSize)"))
        #expect(!enchantedQtHost.contains("QSize resolvedMinimumWindowSize"))
        #expect(!enchantedQtHost.contains("QSize resolvedDefaultWindowSize"))
        #expect(enchantedQtHost.contains("selectedConversationMessages("))
        #expect(enchantedQtHost.contains("renderMessages(messageLayout, selectedMessages, prompts, style)"))
        #expect(genericQtRuntime.contains("import QuillQtNativeRuntimeSupport"))
        #expect(genericQtRuntime.contains("public static let genericSelectedIndexEnvironmentKey = \"QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START\""))
        #expect(genericQtRuntime.contains("public static let defaultSelectedIndexEnvironmentKeys = [genericSelectedIndexEnvironmentKey]"))
        #expect(genericQtRuntime.contains("public var selectedIndexEnvironmentKeys: [String]"))
        #expect(genericQtRuntime.contains("public var style: Style"))
        #expect(genericQtRuntime.contains("public struct Style: Codable, Sendable"))
        #expect(genericQtRuntime.contains("public static let desktop = Style("))
        #expect(genericQtRuntime.contains("style: Style = .desktop"))
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
        #expect(genericQtHost.contains("parseJsonObjectPayload("))
        #expect(genericQtHost.contains("QuillQtWidgets::executableNameBytes(argc, argv, \"quill-generic-qt\")"))
        #expect(genericQtHost.contains("QString genericStyleSheet(const QJsonObject &style)"))
        #expect(genericQtHost.contains("styleValue(style, \"canvasColor\", \"#F7F8F4\")"))
        #expect(genericQtHost.contains("const QJsonObject style = jsonObjectValue(payload, \"style\");"))
        #expect(!genericQtHost.contains("root.setStyleSheet(genericStyleSheet());"))
        #expect(genericQtHost.contains("QuillQtWidgets::minimumWindowSize(payload, 900, 620)"))
        #expect(genericQtHost.contains("QuillQtWidgets::defaultWindowSize(payload, minimumSize)"))
        #expect(!genericQtHost.contains("QSize minimumWindowSize(const QJsonObject &payload)"))
        #expect(!genericQtHost.contains("QSize defaultWindowSize(const QJsonObject &payload"))
        #expect(wireGuardQtRuntime.contains("import QuillQtNativeRuntimeSupport"))
        #expect(wireGuardQtRuntime.contains("QuillQtNativeRuntimeSupport.runEncodedPayload("))
        #expect(wireGuardQtRuntime.contains("executableName: QuillQtNativeRuntimeSupport.executableName(fallback: \"quill-wireguard-qt\")"))
        #expect(wireGuardQtHost.contains("parseJsonObjectPayload("))
        #expect(wireGuardQtHost.contains("QuillQtWidgets::executableNameBytes(argc, argv, \"quill-wireguard-qt\")"))
        #expect(wireGuardQtHost.contains("QuillQtWidgets::minimumWindowSize(payload, 900, 600)"))
        #expect(wireGuardQtHost.contains("QuillQtWidgets::defaultWindowSize(payload, minimumWindowSize)"))
        #expect(!wireGuardQtHost.contains("QSize resolvedMinimumWindowSize"))
        #expect(!wireGuardQtHost.contains("QSize resolvedDefaultWindowSize"))
        #expect(!enchantedQtRuntime.contains("JSONEncoder()"))
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
        #expect(genericQtHost.contains("void applySelection(GenericDetailPane &detailPane, const GenericSelection &selection)"))
        #expect(genericQtHost.contains("applySelection(detailPane, selectionForRow(payload, items, row))"))
        #expect(genericQtHost.contains("populateDetailContent(detailPane.contentLayout, selection)"))
        #expect(genericQtHost.contains("selection.sections"))
        #expect(genericQtHost.contains("selection.messages"))
        #expect(genericQtHost.contains("boundedSelectedIndex("))
        #expect(genericQtHost.contains("const int selectedIndex = boundedSelectedIndex(items, rawSelectedIndex)"))
        #expect(genericQtHost.contains("item.contains(QStringLiteral(\"sections\"))"))
        #expect(genericQtHost.contains("item.contains(QStringLiteral(\"messages\"))"))
        #expect(genericQtRuntime.contains("public var sections: [Section]?"))
        #expect(genericQtRuntime.contains("public var messages: [Message]?"))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Open conversation with replies and boosts.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Weekend photo thread with media previews.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Language practice with the lower row selected.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Desktop compatibility article selected for reading.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Project navigator source file selected.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Core engineering channel with the lower row selected.\""))
        #expect(genericQtRuntime.contains("detailSubtitle: \"Audio-only playlist item selected.\""))

        let qtVisiblePayloadSources = [
            ("Enchanted Qt runtime", enchantedQtRuntime),
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
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-completions-panel\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-history-selection\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-transcript-selection\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-markdown-transcript-selection\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-long-transcript-selection\""))
        #expect(backendProducts.contains("verify_product=\"quill-chat-linux-mac-reference-prompt-send\""))
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
        #expect(backendScript.contains("QUILLUI_BACKEND_IMPORT_SUBMIT_CLICK_X"))
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
        #expect(screenshotVerifier.contains("validate_quill_backend_interaction_smoke"))
        #expect(screenshotVerifier.contains("Quill Enchanted Qt native"))
        #expect(screenshotVerifier.contains("validate_quill_enchanted_qt_native"))
        #expect(screenshotVerifier.contains("product == \"quill-enchanted-qt\""))
        #expect(screenshotVerifier.contains("product == \"quill-enchanted-qt-list-selection\""))
        #expect(screenshotVerifier.contains("product == \"quill-enchanted-linux-qt\""))
        #expect(screenshotVerifier.contains("product == \"quill-enchanted-linux-gtk\""))
        #expect(screenshotVerifier.contains("validate_quill_enchanted_linux_qt_snapshot"))
        #expect(screenshotVerifier.contains("validate_quill_enchanted_linux_gtk_snapshot"))
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
        #expect(source.contains("QUILLUI_LINUX_BACKEND=qt swift build"))
        #expect(source.contains("import $backend_import"))
        #expect(source.contains("$backend_launch_statement"))
        #expect(source.contains(".product(name: \"QuillUIGtk\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"QuillGenericQtNativeRuntime\", package: \"QuillUI\")"))
        #expect(buildSource.contains("--backend-facade"))
        #expect(buildSource.contains("QUILLUI_APP_BACKEND_FACADE"))
        #expect(buildSource.contains("NORMALIZED_BACKEND_FACADE"))
        #expect(buildSource.contains("QUILLUI_LINUX_BACKEND=qt swift build"))
        #expect(buildSource.contains("quillui_normalize_backend_identifier \"${BACKEND_FACADE:-swiftui}\""))
        #expect(buildSource.contains("QUILLUI_GENERATED_BACKEND_FACADE=\"$NORMALIZED_BACKEND_FACADE\""))
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
}

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
