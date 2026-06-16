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
        #expect(manifest.contains("if signalUpstreamPresent && libsignalUpstreamPresent {"))
        #expect(manifest.contains("products.append(.executable(name: \"signal-ui-render\", targets: [\"SignalUIRender\"]))"))
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
        let lowering = try packageSource("scripts/lower-swiftui-source-for-linux.sh")
        let objcLowering = try packageSource("scripts/lower-objc-interop-for-linux.sh")
        let appKitLoweringCall = "\"$(dirname \"$0\")/run-quill-appkit-lower.sh\" \"$SOURCE_DIR\""
        let objcLoweringCall = "\"$(dirname \"$0\")/lower-objc-interop-for-linux.sh\" \"$SOURCE_DIR\""
        let signalUILowering = try packageSource("scripts/quill-signal-lower-ui.sh")

        #expect(lowering.contains("s/\\.keyboardType\\([ \\t]*\\.URL[ \\t]*\\)/.keyboardType(KeyboardType.URL)/g;"))
        #expect(lowering.contains("s/\\.textContentType\\([ \\t]*\\.URL[ \\t]*\\)/.textContentType(TextContentType.URL)/g;"))
        #expect(lowering.contains(appKitLoweringCall))
        #expect(lowering.contains(objcLoweringCall))
        #expect((lowering.range(of: appKitLoweringCall)?.lowerBound ?? lowering.endIndex) < (lowering.range(of: objcLoweringCall)?.lowerBound ?? lowering.startIndex))
        #expect(objcLowering.contains("lower_foundation_bridge_casts"))
        #expect(objcLowering.contains("for cf_type in (\"CFDictionary\", \"CFString\", \"CFURL\", \"CFData\", \"CFMutableData\", \"CFArray\")"))
        #expect(objcLowering.contains("lowered = re.sub(rf\"\\bnil\\s+as\\s+{cf_type}\\?\", \"nil\", lowered)"))
        #expect(objcLowering.contains("lowered = lowered.replace(f\" as {cf_type}\", \"\")"))
        #expect(signalUILowering.contains("Sources/SignalUIObjCPort"))
        #expect(signalUILowering.contains("QuillPort"))
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
        #expect(gtkPatchScript.contains("GRDB_SOURCE_DIR=\"$SCRATCH_PATH/checkouts/GRDB.swift/GRDB\""))
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

        #expect(uiKit.contains("static let placeholderText = RSColor("))
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
        // SolderScope's @preconcurrency pivot (#548) made NSApplicationDelegate
        // @MainActor (its delegate methods are main-thread). `@preconcurrency`
        // downgrades the isolation check to Swift-5 mode, so a nonisolated
        // Telegram conformance is a warning rather than the hard error a bare
        // `@MainActor` protocol would cause — the protocol must carry BOTH
        // annotations and never appear as a bare (line-leading) `@MainActor`.
        #expect(appKit.contains("@preconcurrency @MainActor public protocol NSApplicationDelegate"))
        #expect(!appKit.contains("\n@MainActor public protocol NSApplicationDelegate"))
        #expect(appKit.contains("@MainActor public protocol NSToolbarDelegate"))
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
        #expect(appKit.contains("open func performKeyEquivalent(with event: NSEvent) -> Bool"))
        #expect(appKit.contains("open func standardWindowButton(_ button: WindowButton) -> NSButton?"))
        #expect(appKit.contains("open class NSRunningApplication: NSObject"))
        #expect(appKit.contains("public var runningApplications: [NSRunningApplication]"))
        #expect(appKit.contains("public var fittingSize: NSSize"))
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
        let avCaptureSurface = try String(
            contentsOf: root.appendingPathComponent("Sources/AVFoundation/AVCaptureSurface.swift"),
            encoding: .utf8
        )
        let avCaptureExtras = try String(
            contentsOf: root.appendingPathComponent("Sources/AVFoundation/AVCaptureExtras.swift"),
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
        #expect(!osShim.contains("import os"))
        #expect(attributedStringDocument.contains("#if os(Linux)\n// NSAttributedString document-conversion surface"))
        #expect(attributedStringDocument.hasSuffix("#endif\n"))
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
        let designCompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/DesignSystemSurfaceCompat.swift"),
            encoding: .utf8
        )
        let appStorageCompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/AppStorage.swift"),
            encoding: .utf8
        )
        let quillUpstreamCompatibility = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/UpstreamCompatibility.swift"),
            encoding: .utf8
        )
        let swiftOpenUIControlStyles = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/ControlStyleModifiers.swift"),
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
        #expect(manifest.contains("let wrappingHStackDependencies: [Target.Dependency] = [\n    \"SwiftUI\",\n    \"Observation\","))
        #expect(manifest.contains("? [\"QuillAppKitGTK\", \"Observation\", swiftUIShimBackendDependency]"))
        #expect(manifest.contains("quillUILinuxBuildBackend == .qt && quillUIQtGenericEnabled ? [\"QuillAppKitQt\", \"Observation\", swiftUIShimBackendDependency] : []"))
        #expect(manifest.contains(".product(name: \"SwiftOpenUISymbols\", package: \"SwiftOpenUI\"),\n                    \"Observation\",\n                    \"CQtBridge\""))
        #expect(quillUI.contains("@_exported import QuillSwiftUICompatibility"))
        #expect(swiftUIShim.contains("@_exported import QuillSwiftUICompatibility"))
        #expect(compatibility.contains("typealias Weight = FontWeight"))
        #expect(compatibility.contains("static var firstTextBaseline: VerticalAlignment { .top }"))
        #expect(swiftOpenUIControlStyles.contains("public struct PlainButtonStyle: ButtonStyle"))
        #expect(designCompatibility.contains("public struct RoundedBorderTextFieldStyle"))
        #expect(designCompatibility.contains("@MainActor\n    static var circle: Circle { Circle() }"))
        #expect(designCompatibility.contains("@MainActor\n    public init<Content: View>(_ column: TableColumn<RowValue, Content>)"))
        #expect(designCompatibility.contains("@MainActor public static func buildExpression<Content: View>"))
        #expect(appStorageCompatibility.contains("public struct AppStorage<Value>: AnyStateStorageProvider"))
        #expect(!quillUpstreamCompatibility.contains("public struct PlainButtonStyle"))
        #expect(!designCompatibility.contains("public protocol ButtonStyle"))
        #expect(!designCompatibility.contains("public struct ButtonStyleConfiguration"))
        #expect(!designCompatibility.contains("public struct PlainButtonStyle: ButtonStyle"))
        #expect(!quillUpstreamCompatibility.contains("public struct RoundedBorderTextFieldStyle"))
        #expect(!swiftUIShim.contains("static var firstTextBaseline"))
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
        let inputFieldsTemplate = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/macOS/Chat/Components/InputFields_macOS.swift"),
            encoding: .utf8
        )

        #expect(inputFieldsRule.contains("\\n$1.frame(maxWidth: .infinity)\\n$1.overlay("))
        #expect(inputFieldsRule.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(inputFieldsTemplate.contains("private var composerField: some View"))
        #expect(inputFieldsTemplate.contains("private var actionButtons: some View"))
        #expect(!inputFieldsTemplate.contains(".fileImporter("))
        #expect(!inputFieldsTemplate.contains(".onDrop("))
        #expect(!inputFieldsTemplate.contains(".addCustomHotkeys("))
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
        #expect(swiftUILowering.contains("ensure-swift-imports.sh\" \"$SOURCE_DIR\" QuillShims"))
        #expect(swiftUILowering.contains("run-quill-appkit-lower.sh\" \"$SOURCE_DIR\""))
        #expect(swiftUILowering.contains(#"s/Task \{[ \t]*\@MainActor[ \t]+in/Task {/g;"#))
        #expect(swiftUILowering.contains(#"s/Task \{[ \t]*\@MainActor[ \t]+(\[[^\]]+\][ \t]+in)/Task { $1/g;"#))
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
            ".github/workflows/macos-ci.yml",
            ".github/workflows/solderscope-ci.yml"
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
        let backendScript = try packageSource("scripts/linux-backend-interaction-check.sh")
        let backendProfileScript = try packageSource("scripts/linux-backend-profile.sh")
        let backendVisualScript = try packageSource("scripts/linux-backend-visual-check.sh")
        let smokeLib = try packageSource("scripts/quillui-linux-backend-smoke-lib.sh")
        let backendProducts = try packageSource("scripts/quillui-backend-products.sh")
        let smokeMatrixRunner = try packageSource("scripts/run-linux-backend-smoke-matrix.sh")
        let interactionModeRunner = try packageSource("scripts/run-linux-backend-interaction-modes.sh")
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
        #expect(backendScript.contains("quillui_backend_interaction_verify_product \"$PRODUCT\" \"$INTERACTION_MODE\" VERIFY_PRODUCT"))
        #expect(backendScript.contains("quill_chat_completions_panel_probe_path=\"\""))
        #expect(backendScript.contains("quill_chat_completion_interaction_needs_settled_capture()"))
        #expect(backendScript.contains("completions-save|completions-edit-save|completions-delete"))
        #expect(backendScript.contains("settle_quill_chat_completion_capture_if_verified()"))
        #expect(backendScript.contains("quillui_backend_interaction_verify_product \"$PRODUCT\" \"$INTERACTION_MODE\" verify_product"))
        #expect(backendScript.contains("cp -f \"$quill_chat_completions_panel_probe_path\" \"$SCREENSHOT_PATH\""))
        #expect(backendScript.contains("settled_capture_taken=1"))
        #expect(backendScript.contains("settle_quill_chat_completion_capture_if_verified\n      return 0"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_OPEN_ATTEMPTS:-3"))
        #expect(backendScript.contains("for ((attempt = 1; attempt <= max_attempts; attempt += 1)); do"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_OPEN_RETRY_SLEEP:-0.8"))
        #expect(backendScript.contains("quillui_append_backend_selection_start_environment"))
        #expect(!backendScript.contains("app_environment+=(\"QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"))
        #expect(!backendScript.contains("app_environment+=(\"QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_SLEEP:-0.6"))
        #expect(backendScript.contains("reset_cancel_x=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_X:-$((window_x + 570))}}\""))
        #expect(backendScript.contains("reset_cancel_y=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_Y:-$((window_y + 382))}}\""))
        #expect(backendScript.contains("name_y=\"${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 462))}\""))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_TEXT"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X"))
        #expect(backendScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y"))
        #expect(backendScript.contains("instruction_x=\"${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X:-$((window_x + 720))}\""))
        #expect(backendScript.contains("instruction_y=\"${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y:-$((window_y + 548))}\""))
        #expect(backendScript.contains("Reply with a concise Linux validation response."))
        #expect(backendScript.contains("save_x=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + 1448))}\""))
        #expect(backendScript.contains("save_y=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 407))}\""))
        #expect(!backendScript.contains("name_y=\"${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 468))}\""))
        #expect(!backendScript.contains("save_x=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + 1450))}\""))
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
        #expect(screenshotVerifier.contains("validate_quill_solderscope_launch"))
        #expect(screenshotVerifier.contains("\"quill-solderscope-launch\""))
        #expect(screenshotVerifier.contains("quill-solderscope-interaction"))
        #expect(screenshotVerifier.contains("SolderScope dark toolbar pixels were not detected near the top"))
        #expect(screenshotVerifier.contains("canvas_dark_pixels >= 25_000"))
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
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh visual smoke-matrix '.qa/{product}-visual-{backend}.png'"))
        #expect(workflow.contains("scripts/run-linux-backend-smoke-matrix.sh --skip-repeated-products interaction smoke-interaction-matrix '.qa/{product}-{mode}-{backend}.png'"))
        #expect(workflow.contains("scripts/linux-solderscope-smoke-check.sh .qa/quill-solderscope-launch.png"))
        #expect(solderScopeWorkflow.contains("name: SolderScope Linux CI"))
        #expect(solderScopeWorkflow.contains("SolderScope API and fixture tests"))
        #expect(solderScopeWorkflow.contains("SolderScope GTK launch and interaction"))
        #expect(solderScopeWorkflow.contains("scripts/fetch-upstream.sh solderscope"))
        #expect(solderScopeWorkflow.contains("scripts/linux-swift-test.sh --scratch-path .build-solderscope-api --filter SolderScopeChromeConformanceTests"))
        #expect(solderScopeWorkflow.contains("scripts/linux-swift-test.sh --scratch-path .build-solderscope-capture --filter AVCaptureSurfaceTests"))
        #expect(solderScopeWorkflow.contains("scripts/linux-swift-test.sh --scratch-path .build-solderscope-v4l2 --filter V4L2ConversionTests"))
        #expect(solderScopeWorkflow.contains("scripts/linux-swift-test.sh --scratch-path .build-solderscope-encode --filter BitmapAndMovieEncodeTests"))
        #expect(solderScopeWorkflow.contains("scripts/linux-solderscope-smoke-check.sh .qa/quill-solderscope-visual.png visual"))
        #expect(solderScopeWorkflow.contains("QUILLUI_SOLDERSCOPE_SKIP_BUILD=1 QUILLUI_SOLDERSCOPE_SCRATCH_PATH=.build-solderscope-gtk scripts/linux-solderscope-smoke-check.sh .qa/quill-solderscope-interaction.png interaction"))
        #expect(solderScopeWorkflow.contains("uses: actions/upload-artifact@v6"))
        #expect(fetchUpstream.contains("solderscope)"))
        #expect(fetchUpstream.contains("fetch_repo solderscope https://github.com/rjwalters/SolderScope.git"))
        #expect(fetchUpstream.contains("patch_solderscope"))
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
        #expect(source.contains("RESOURCE_DIR=\"$TARGET_DIR/Resources\""))
        #expect(source.contains("scripts/copy-swiftui-linux-resources.py"))
        #expect(source.contains("target_resources='            resources: [.copy(\"Resources\")],"))
        #expect(source.contains("$target_resources"))
        #expect(source.contains("source_target_dependencies="))
        #expect(source.contains("target_dependencies=\"$(printf '%s,\\n"))
        #expect(source.contains(".product(name: \"QuillUIGtk\", package: \"QuillUI\")' \"$source_target_dependencies\")\""))
        #expect(source.contains("if [[ \"$BACKEND_FACADE\" != \"qt\" ]]"))
        #expect(source.contains("QUILLUI_LINUX_BACKEND=qt \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(source.contains("QUILLUI_LINUX_BACKEND=gtk \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(source.contains("import $backend_import"))
        #expect(source.contains("$backend_launch_statement"))
        #expect(source.contains(".product(name: \"QuillUIGtk\", package: \"QuillUI\")"))
        #expect(source.contains(".product(name: \"QuillGenericQtNativeRuntime\", package: \"QuillUI\")"))
        #expect(buildSource.contains("--backend-facade"))
        #expect(buildSource.contains("QUILLUI_APP_BACKEND_FACADE"))
        #expect(buildSource.contains("NORMALIZED_BACKEND_FACADE"))
        #expect(buildSource.contains("QUILLUI_LINUX_BACKEND=qt \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
        #expect(buildSource.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(buildSource.contains("QUILLUI_LINUX_BACKEND=gtk \"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh\" swift build"))
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
        #expect(controls.contains("public static func selectableModels<Item, SelectionID: Hashable>"))
        #expect(controls.contains("return version.isEmpty ? name(model) : \"\\(name(model)) \\(version)\""))
        #expect(controls.contains("layout: QuillPromptGridLayout"))
        #expect(controls.contains("self.init(\n            brandTitle: brandTitle,\n            prompts: prompts,\n            layout: QuillPromptGridLayout("))
        #expect(controls.contains("public static let quillChatMacReferencePromptTitles = ["))
        #expect(controls.contains("public struct QuillSelectedPromptEmptyState<Item>: View"))
        #expect(controls.contains("preferredTitles: [String] = QuillPrompt.quillChatMacReferencePromptTitles"))
        #expect(controls.contains("QuillChatEmptyState(\n            brandTitle: brandTitle"))
        #expect(controls.contains("public static func selectedModelSender<Model, Attachment, TrimmingID>("))
        #expect(controls.contains("public static func selectableItems<Item, SelectionID: Hashable>"))
        #expect(controls.contains("return emptyTitle.map { [QuillMenuAction.disabled(title: $0)] } ?? []"))
        #expect(controls.contains("systemImage: selectedID == itemID ? selectedSystemImage : nil"))
        #expect(controls.contains("public static func desktopChatUtilityToggles("))
        #expect(controls.contains("showCompletions.wrappedValue.toggle()"))
        #expect(controls.contains("showShortcuts.wrappedValue.toggle()"))
        #expect(controls.contains("showSettings.wrappedValue.toggle()"))
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
        #expect(historyList.contains("@State private var didApplyInitialSelection = false"))
        #expect(historyList.contains(".onAppear { applyInitialSelectionIfNeeded() }"))
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
        #expect(historyList.contains("Text(lastMessage)"))
        #expect(historyList.contains(".font(.system(size: rowPreviewFontSize))"))
        #expect(historyList.contains(".lineLimit(2)"))
        #expect(historyList.contains(".padding(rowPadding)"))
        #expect(historyList.contains("""
                            .padding(rowPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(rowBackgroundColor(for: rowState))
                            .cornerRadius(rowCornerRadius)
                        }
                        .contentShape(Rectangle())
"""))
        #expect(historyList.contains(".cornerRadius(rowCornerRadius)"))
        #expect(historyList.contains(".buttonStyle(.plain)"))
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
        #expect(controls.contains("public struct QuillDesktopChatUtilitySidebar<"))
        #expect(controls.contains("@State private var showSettings = false"))
        #expect(controls.contains("@State private var showCompletions = false"))
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
    }

    @Test("GTK QuillPaint hooks cover button and text input chrome")
    func gtkQuillPaintHooksCoverButtonAndTextInputChrome() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")
        let smallPatcher = try packageSource("scripts/patch-swiftopenui-quillpaint.py")
        let gtkBackend = try packageSource("Sources/QuillUIGtk/QuillUIGtk.swift")
        let gtkButton = try packageSource("Sources/QuillUIGtk/QuillGtkButton.swift")
        let gtkTextField = try packageSource("Sources/QuillUIGtk/QuillGtkTextField.swift")
        let gtkToggle = try packageSource("Sources/QuillUIGtk/QuillGtkToggle.swift")

        for source in [renderer, patcher, smallPatcher] {
            #expect(source.contains("quill_gtk_button_paint_hook"))
            #expect(source.contains("quill_gtk_text_field_paint_hook"))
            #expect(source.contains("quill_gtk_text_editor_paint_hook"))
            #expect(source.contains("quill_gtk_toggle_paint_hook"))
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
        #expect(renderer.contains("gtkScheduleTextBindingUpdate(binding, value: newText)"))
        #expect(renderer.contains("let changedBox = Unmanaged.passRetained(StringClosureBox"))
        #expect(renderer.contains("gtk_editable_get_text(OpaquePointer(editable))"))
        #expect(patcher.contains("SwiftOpenUI TextField changed-signal insert shape was not recognized"))
        #expect(patcher.contains("SwiftOpenUI TextField idle binding helper insertion marker was not recognized"))
        #expect(patcher.contains("private final class GTKTextBindingIdleUpdate"))
        #expect(patcher.contains("includeValueWhenUnidentified: Bool = false"))
        #expect(patcher.contains("gtkScheduleTextBindingUpdate(binding, value: newText)"))
        #expect(patcher.contains("let changedBox = Unmanaged.passRetained(StringClosureBox"))
        #expect(patcher.contains("gtk_editable_get_text(OpaquePointer(editable))"))

        #expect(gtkBackend.contains("installQuillButtonHook()"))
        #expect(gtkBackend.contains("installQuillTextFieldHook()"))
        #expect(gtkBackend.contains("installQuillToggleHook()"))
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
        #expect(gtkToggle.contains("setupQuillToggleChrome(control: control, isSwitch: isSwitch, label: label)"))
        #expect(gtkToggle.contains("MacCheckboxPaint(value: chromeBox.isActive ? .on : .off)"))
        #expect(gtkToggle.contains("MacSwitchPaint(isOn: chromeBox.isActive)"))
        #expect(gtkToggle.contains("gtk_widget_set_opacity(control, 0.001)"))
        #expect(gtkToggle.contains("installQuillToggleLabelGesture"))
    }

    @Test("Enchanted SF Symbols map to bundled Material glyphs")
    func enchantedSFSymbolsMapToMaterialGlyphs() throws {
        let symbols = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/SFSymbolCompatibility.swift"
        )
        let codepoints = try packageSource(
            "third_party/SwiftOpenUI/Sources/SwiftOpenUISymbols/MaterialSymbolsCodepoints.swift"
        )

        let expectedMappings: [(sf: String, material: String)] = [
            ("checkmark.seal", "verified"),
            ("checkmark.seal.fill", "verified"),
            ("checkmark.square.fill", "check_box"),
            ("curlybraces", "data_object"),
            ("keyboard.fill", "keyboard"),
            ("line.3.horizontal", "menu"),
            ("paperplane.fill", "send"),
            ("photo", "image"),
            ("photo.fill", "image"),
            ("selection.pin.in.out", "select_all"),
            ("sidebar.left", "view_sidebar"),
            ("space", "space_bar"),
            ("speaker.slash.fill", "volume_off"),
            ("speaker.wave.2.fill", "volume_up"),
            ("speaker.wave.3.fill", "volume_up"),
            ("square", "check_box_outline_blank"),
            ("square.fill", "stop"),
            ("sun.max", "light_mode"),
            ("textformat.abc", "text_fields"),
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
            #expect(source.contains("gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource(\"gesture\", widget: context.widget))"))
            #expect(source.contains("gtk_swift_add_capture_gesture"))
            #expect(source.contains("gtk_swift_add_capture_gesture(button, gesture)"))
            #expect(source.contains("gtk_swift_legacy_capture_controller"))
            #expect(source.contains("gtk_swift_event_is_primary_button_press"))
            #expect(source.contains("gtkScheduleButtonAction(box, source: \"legacy\")"))
            #expect(source.contains("GTKButtonRootEventContext"))
            #expect(source.contains("gtkInstallButtonRootEventFallback"))
            #expect(source.contains("gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource(\"root-legacy@"))
            #expect(source.contains("gtk_swift_widget_is_topmost_at_root_point"))
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
            #expect(!source.contains("g_application_run(applicationPointer(appPtr), 0, nil)"))
        }
        #expect(!backend.contains("g_application_run("))
    }

    @Test("GTK patcher preserves fixed-frame and list viewport sizing contracts")
    func gtkPatcherPreservesFixedFrameAndListViewportSizingContracts() throws {
        let patcher = try packageSource("scripts/patch-swiftopenui-gtk-css.sh")
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
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
        #expect(patcher.contains("gtk_scrolled_window_set_max_content_height(scrolledOp, height)"))
        #expect(renderer.contains("gtkFrameFlexibleWidthFixedHeightClip"))
        #expect(renderer.contains("gtk_widget_set_vexpand(child, heightMayGrowWithParent ? 1 : 0)"))
        #expect(patcher.contains("padded_view_child_fill = \"PaddedView must let expanding content fill its margin wrapper\""))
        #expect(patcher.contains("gtk_widget_set_halign(child, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtk_widget_set_valign(child, GTK_ALIGN_FILL)"))
        #expect(renderer.contains("extension ClippedView: GTKRenderable"))
        #expect(renderer.contains("gtk_widget_set_halign(inner, GTK_ALIGN_FILL)"))
        #expect(renderer.contains("gtk_widget_set_valign(inner, GTK_ALIGN_FILL)"))
        #expect(renderer.contains("gtk_widget_set_halign(baseWidget, GTK_ALIGN_FILL)"))
        #expect(renderer.contains("gtk_widget_set_valign(baseWidget, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)"))
        #expect(patcher.contains("gtk_widget_set_halign(row, GTK_ALIGN_FILL)"))
        #expect(patcher.contains("gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox, fillWidth: true, fillHeight: false)"))
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
        #expect(patcher.contains("if let rootOverlay = gtkCurrentRootSheetOverlay()"))
        #expect(patcher.contains("if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(anchor))"))
        #expect(patcher.contains("var ancestor = gtk_widget_get_parent(anchor)"))
        #expect(patcher.contains("ancestor = gtk_widget_get_parent(current)"))
        #expect(patcher.contains("if let rootOverlay = gtkFallbackRootPresentationOverlay()"))
        #expect(patcher.occurrences(of: "let rootOverlay = gtkSheetRootOverlay(for: anchor)") == 2)
        #expect(patcher.occurrences(of: "gtkWithRootSheetOverlay(rootOverlay) {") == 2)
        #expect(patcher.occurrences(of: "gtkStoreRootPresentationOverlay(rootOverlay, on: panel)") == 2)
        #expect(patcher.occurrences(of: "gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)") == 2)
        #expect(patcher.contains("private func gtkAttachRootSheetOverlay("))
        #expect(patcher.contains("gtk_widget_insert_after(panel, overlayWidget, previousTop)"))
        #expect(patcher.occurrences(of: "gtkAttachRootSheetOverlay(panel, to: rootOverlay)") == 2)
        #expect(patcher.contains("private var gtkRootPresentationOverlayFallback: OpaquePointer?"))
        #expect(patcher.contains("func gtkStoreRootPresentationOverlay("))
        #expect(patcher.contains("gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: widgetPointer(winPtr))"))
        #expect(patcher.contains("gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: contentWidget)"))
        #expect(patcher.contains("func gtkStoredRootPresentationOverlay(on widget: gpointer) -> OpaquePointer?"))
        #expect(patcher.contains("gtkStoredRootPresentationOverlay(on: root) ?? gtkRootPresentationOverlayFallback"))
        #expect(patcher.contains("func gtkFallbackRootPresentationOverlay() -> OpaquePointer?"))
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
        #expect(verifier.contains("top + int(app_height * 0.345)"))
        #expect(verifier.contains("row_action_segments >= minimum_row_action_segments"))
        #expect(verifier.contains("minimum_wordmark_pixels: int = 650"))
        #expect(verifier.contains("wordmark_pixels >= minimum_wordmark_pixels"))
        #expect(verifier.contains("panel_surface_pixels >= 32_000"))
        #expect(verifier.contains("minimum_row_dividers=2"))
        #expect(verifier.contains("minimum_row_action_segments=3"))
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

    @Test("Vendored GTK ScrollViewReader uses deferred ID adjustment scrolling")
    func vendoredGTKScrollViewReaderUsesDeferredIDAdjustmentScrolling() throws {
        let renderer = try packageSource("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")

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
        #expect(renderer.contains("gtkScheduleScrollTo(id: id, widget, anchor: anchor)"))
        #expect(renderer.contains("gtkPendingScrollRequests[anyID] = GTKPendingScrollRequest(anchor: anchor)"))
        #expect(renderer.contains("gtkRegisterScrollTarget(id: AnyHashable(id), widget: wrapper)"))
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
