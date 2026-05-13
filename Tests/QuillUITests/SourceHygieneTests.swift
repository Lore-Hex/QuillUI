import Foundation
import Testing

@Suite("Source hygiene")
struct SourceHygieneTests {
    @Test("macro expansion paths report diagnostics instead of crashing")
    func macroExpansionPathsAvoidFatalError() throws {
        let root = try packageRoot()
        let macros = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillDataMacros/QuillDataMacros.swift"),
            encoding: .utf8
        )

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

        #expect(manifest.contains(".library(name: \"QuillChatKit\", targets: [\"QuillChatKit\"])"))
        #expect(manifest.contains("platforms: [.macOS(.v14), .iOS(.v14)]"))
        #expect(source.contains("import SwiftUI"))
        #expect(source.contains("public struct ChatAppearance"))
        #expect(source.contains("private typealias ChatLayoutLength = Int"))
        #expect(source.contains("private typealias ChatLayoutLength = CGFloat"))
        #expect(!source.contains("import QuillUI"))
        #expect(!source.contains("import UIKit"))
        #expect(!source.contains("import AppKit"))
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

        #expect(workflows.contains("uses: actions/checkout@v5"))
        #expect(workflows.contains("uses: actions/upload-artifact@v6"))
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
        let backendSmokeEntryPointPaths = [
            "Sources/QuillGtkInteractionSmoke/main.swift": "QuillInteractionSmokeScene.scene(for: .gtk)",
            "Sources/QuillQtInteractionSmoke/main.swift": "QuillInteractionSmokeScene.scene(for: .qt)"
        ]

        #expect(helperSource.contains("public enum QuillAppWindow"))
        #expect(helperSource.contains("QuillBackendRegistry.launchPlan(preferred: preferredBackend)"))
        #expect(helperSource.contains("private enum QuillLinuxRuntimeHost"))
        #expect(helperSource.contains("QuillLinuxRuntimeHost(runtimeBackend: launchPlan.runtime).run(appType)"))
        #expect(helperSource.contains("QuillMainActorView.assumeIsolated"))
        #expect(helperSource.contains(".defaultSize(width: width, height: height)"))

        for path in appEntryPointPaths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)

            #expect(source.contains("QuillAppWindow.scene("), "\(path) should use the shared scene helper")
            #expect(!source.contains("WindowGroup("), "\(path) should not hand-roll WindowGroup setup")
            #expect(!source.contains(".defaultWindowSize("), "\(path) should not branch into Linux-only sizing")
            #expect(!source.contains(".defaultSize("), "\(path) should let QuillAppWindow own default sizing")
        }

        for (path, sceneCall) in backendSmokeEntryPointPaths {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)

            #expect(source.contains(sceneCall), "\(path) should use the shared interaction smoke scene")
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
        let smokeLib = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-linux-backend-smoke-lib.sh"),
            encoding: .utf8
        )
        let backendProducts = try String(
            contentsOf: root.appendingPathComponent("scripts/quillui-backend-products.sh"),
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

        #expect(manifest.contains(".library(name: \"QuillUIGtk\", targets: [\"QuillUIGtk\"])"))
        #expect(manifest.contains(".library(name: \"QuillUIQt\", targets: [\"QuillUIQt\"])"))
        #expect(manifest.contains(".executable(name: \"quill-gtk-interaction-smoke\", targets: [\"QuillGtkInteractionSmoke\"])"))
        #expect(manifest.contains(".executable(name: \"quill-qt-interaction-smoke\", targets: [\"QuillQtInteractionSmoke\"])"))
        #expect(manifest.contains("name: \"QuillInteractionSmokeSupport\""))
        #expect(manifest.contains("dependencies: [\"QuillUI\", \"QuillUIGtk\", \"QuillInteractionSmokeSupport\"]"))
        #expect(manifest.contains("dependencies: [\"QuillUI\", \"QuillUIQt\", \"QuillInteractionSmokeSupport\"]"))

        #expect(gtkMain.contains("import QuillInteractionSmokeSupport"))
        #expect(gtkMain.contains("import QuillUIGtk"))
        #expect(gtkMain.contains("QuillInteractionSmokeScene.scene(for: .gtk)"))
        #expect(gtkMain.contains("QuillGtkApp.run(QuillGtkInteractionSmokeApp.self)"))
        #expect(!gtkMain.contains("Quill GTK Interaction"))
        #expect(!gtkMain.contains("Native GTK click target"))
        #expect(!gtkMain.contains("struct SmokeView"))

        #expect(qtMain.contains("import QuillInteractionSmokeSupport"))
        #expect(qtMain.contains("import QuillUIQt"))
        #expect(qtMain.contains("QuillInteractionSmokeScene.scene(for: .qt)"))
        #expect(qtMain.contains("QuillQtApp.run(QuillQtInteractionSmokeApp.self)"))
        #expect(!qtMain.contains("Quill Qt Interaction"))
        #expect(!qtMain.contains("Native Qt click target"))
        #expect(!qtMain.contains("struct SmokeView"))

        #expect(sharedView.contains("public struct QuillInteractionSmokeConfiguration"))
        #expect(sharedView.contains("public struct QuillInteractionSmokeView"))
        #expect(sharedView.contains("public enum QuillInteractionSmokeScene"))
        #expect(sharedView.contains("backendParitySurface"))
        #expect(sharedView.contains("QuillAppWindow.scene("))
        #expect(sharedView.contains("Quill Backend Interaction"))
        #expect(sharedView.contains("Native backend click target"))
        #expect(sharedView.contains("native backend button click"))
        #expect(gtkBackend.contains("public enum QuillGtkBackend"))
        #expect(gtkBackend.contains("public enum QuillGtkApp"))
        #expect(gtkBackend.contains("public typealias QuillGtkBackendStatus = QuillBackendRuntimeStatus"))
        #expect(gtkBackend.contains("public static var status: QuillGtkBackendStatus"))
        #expect(gtkBackend.contains("runtimeStatus"))
        #expect(gtkBackend.contains("QuillApp.run(appType, preferredBackend: QuillGtkBackend.identifier)"))
        #expect(qtBackend.contains("public enum QuillQtBackend"))
        #expect(qtBackend.contains("public enum QuillQtApp"))
        #expect(qtBackend.contains("public typealias QuillQtBackendStatus = QuillBackendRuntimeStatus"))
        #expect(qtBackend.contains("public static var status: QuillQtBackendStatus"))
        #expect(qtBackend.contains("runtimeStatus"))
        #expect(qtBackend.contains("QuillApp.run(appType, preferredBackend: QuillQtBackend.identifier)"))

        #expect(backendScript.contains("QUILLUI_BACKEND_INTERACTION_MODE"))
        #expect(backendScript.contains("QUILLUI_BACKEND_VERIFY_PRODUCT"))
        #expect(backendScript.contains("quillui_alias_env QUILLUI_BACKEND_MAC_REFERENCE QUILLUI_GTK_MAC_REFERENCE"))
        #expect(backendScript.contains("quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_INTERACTION_SCREEN_SIZE"))
        #expect(backendScript.contains("reference_window_width=\"${QUILLUI_GTK_DEFAULT_WINDOW_WIDTH:-2048}\""))
        #expect(backendScript.contains("xdotool is required for backend interaction smoke tests"))
        #expect(backendScript.contains("quillui_is_backend_smoke_product \"$PRODUCT\""))
        #expect(!backendScript.contains("quill-gtk-interaction-smoke|quill-qt-interaction-smoke"))
        #expect(backendScript.contains("source \"$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh\""))
        #expect(backendScript.contains("verify-backend-screenshot.py"))
        #expect(!backendScript.contains("xdotool is required for GTK interaction smoke tests"))
        #expect(!backendScript.contains("verify-gtk-screenshot.py"))
        #expect(smokeLib.contains("source \"$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh\""))
        #expect(smokeLib.contains("quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE"))
        #expect(smokeLib.contains("quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD"))
        #expect(smokeLib.contains("quillui_install_linux_backend_smoke_packages()"))
        #expect(smokeLib.contains("quillui_resolve_linux_backend_executable()"))
        #expect(smokeLib.contains("quillui_seed_quill_chat_reference_data()"))
        #expect(backendScript.contains("quillui_resolve_linux_backend_executable \"$PRODUCT\" APP_EXECUTABLE"))
        #expect(backendScript.contains("quillui_requested_backend_for_product \"$PRODUCT\""))
        #expect(backendScript.contains("app_environment+=(QUILLUI_BACKEND=\"$REQUESTED_BACKEND\")"))
        #expect(!backendScript.contains("install_packages()"))
        #expect(!backendScript.contains("build_and_resolve_executable()"))
        #expect(backendProducts.contains("quillui_gtk_app_products()"))
        #expect(backendProducts.contains("quillui_backend_app_products()"))
        #expect(backendProducts.contains("quillui_backend_app_backends()"))
        #expect(backendProducts.contains("quillui_backend_app_matrix()"))
        #expect(backendProducts.contains("quillui_backend_smoke_products()"))
        #expect(backendProducts.contains("quillui_backend_profile_products()"))
        #expect(backendProducts.contains("quillui_backend_profile_matrix()"))
        #expect(backendProducts.contains("quillui_is_backend_smoke_product()"))
        #expect(backendProducts.contains("quillui_alias_env()"))
        #expect(backendProducts.contains("backend-apps)"))
        #expect(backendProducts.contains("app-backends)"))
        #expect(backendProducts.contains("app-matrix)"))
        #expect(backendProducts.contains("gtk-apps)"))
        #expect(backendProducts.contains("profile-products)"))
        #expect(backendProducts.contains("profile-matrix)"))
        #expect(backendProducts.contains("is-smoke-product)"))
        #expect(backendProducts.contains("backend-for-product)"))
        #expect(backendProducts.contains("quill-qt-interaction-smoke)"))
        #expect(backendProducts.contains("echo \"qt\""))
        #expect(backendProducts.contains("quill-gtk-interaction-smoke|quill-chat-linux"))
        #expect(backendProducts.contains("echo \"gtk\""))
        #expect(screenshotVerifier.contains("Quill backend interaction smoke"))
        #expect(screenshotVerifier.contains("validate_quill_backend_interaction_smoke"))
        #expect(screenshotVerifier.contains("Usage: verify-backend-screenshot.py SCREENSHOT_PATH PRODUCT"))
        #expect(!screenshotVerifier.contains("Quill GTK interaction smoke"))
        #expect(legacyScreenshotVerifier.contains("verify-backend-screenshot.py"))
        #expect(!legacyScreenshotVerifier.contains("validate_quill_backend_interaction_smoke"))
        #expect(legacyGtkScript.contains("linux-backend-interaction-check.sh"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh smoke-products"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh app-matrix"))
        #expect(workflow.contains("scripts/quillui-backend-products.sh profile-matrix"))
        #expect(workflow.contains("scripts/linux-backend-visual-check.sh \".qa/${product}-visual.png\" \"$product\""))
        #expect(workflow.contains("QUILLUI_BACKEND=\"$backend\" scripts/linux-backend-visual-check.sh \".qa/${product}-${backend}.png\" \"$product\""))
        #expect(workflow.contains("scripts/linux-backend-interaction-check.sh .qa/quill-gtk-interaction-smoke-open.png quill-gtk-interaction-smoke"))
        #expect(workflow.contains("scripts/linux-backend-interaction-check.sh .qa/quill-qt-interaction-smoke-open.png quill-qt-interaction-smoke"))
    }

    @Test("Generated Linux app packages launch through QuillApp")
    func generatedLinuxAppPackagesLaunchThroughQuillApp() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/generate-swiftui-linux-package.sh"),
            encoding: .utf8
        )

        #expect(source.contains("import QuillUI"))
        #expect(source.contains("QuillApp.run($APP_ENTRY_TYPE.self)"))
        #expect(!source.contains("import BackendGTK4"))
        #expect(!source.contains("GTK4Backend().run($APP_ENTRY_TYPE.self)"))
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
