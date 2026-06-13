import Foundation
import Testing

@Suite("QuillData SwiftData source lowering")
struct QuillDataSourceLoweringTests {
    @Test("lowering script converts SwiftData-only model syntax")
    func loweringScriptConvertsModelSyntax() throws {
        let root = try packageRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillDataSourceLoweringTests-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("Source", isDirectory: true)
        let output = directory.appendingPathComponent("Output", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let modelSource = """
        import Foundation
        import SwiftData

        @Model
        final class ConversationSD: Identifiable {
            @Attribute(.unique) var id: UUID = UUID()
            @Relationship(deleteRule: .nullify) var model: LanguageModelSD?
            @Relationship(deleteRule: .cascade, inverse: \\MessageSD.conversation) var messages: [MessageSD] = []
            @Transient var title: String { model?.name ?? "" }

            init(model: LanguageModelSD? = nil) {
                self.model = model
            }
        }

        @Model
        final class MessageSD: Identifiable {
            @Attribute(.unique) var id: UUID = UUID()
            @Relationship var conversation: ConversationSD?

            init(content: String) {
                self.conversation = conversation
            }
        }

        func lookup(conversationId: UUID) {
            let predicate = #Predicate<ConversationSD>{ $0.id == conversationId }
            _ = FetchDescriptor<ConversationSD>(predicate: predicate)
        }
        """
        try modelSource.write(
            to: source.appendingPathComponent("ConversationSD.swift"),
            atomically: true,
            encoding: .utf8
        )

        let script = root.appendingPathComponent("scripts/lower-swiftdata-for-quilldata.sh")
        let scriptSource = try String(contentsOf: script, encoding: .utf8)
        #expect(scriptSource.contains("run-quill-source-lower.sh"))
        #expect(!scriptSource.contains("--package-path \"$ROOT_DIR\""))
        #expect(!scriptSource.contains("perl -0pi"))

        let lowererWrapper = try String(
            contentsOf: root.appendingPathComponent("scripts/run-quill-source-lower.sh"),
            encoding: .utf8
        )
        #expect(lowererWrapper.contains("QUILLUI_SOURCE_LOWER"))
        #expect(lowererWrapper.contains(".build/quill-source-lower-package"))
        #expect(lowererWrapper.contains("ln -s \"$ROOT_DIR/Sources/QuillSourceLowering\""))
        #expect(lowererWrapper.contains("--package-path \"$TOOL_PACKAGE_DIR\""))
        #expect(lowererWrapper.contains("--disable-index-store"))
        #expect(!lowererWrapper.contains("--package-path \"$ROOT_DIR\""))

        let result = try runScript(
            script,
            arguments: [source.path, output.path],
            environment: [
                "QUILLUI_SOURCE_LOWER_PACKAGE_DIR": directory
                    .appendingPathComponent("ToolPackage", isDirectory: true).path,
                "QUILLUI_SOURCE_LOWER_SCRATCH_PATH": directory
                    .appendingPathComponent("ToolScratch", isDirectory: true).path,
            ]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))

        let lowered = try String(
            contentsOf: output.appendingPathComponent("ConversationSD.swift"),
            encoding: .utf8
        )
        #expect(lowered.contains("final class ConversationSD: Identifiable, PersistentModel {"))
        #expect(lowered.contains("final class MessageSD: Identifiable, PersistentModel {"))
        #expect(lowered.contains("var title: String"))
        #expect(lowered.contains("#QuillPredicate<ConversationSD>"))
        #expect(lowered.contains("QuillRelationships.relationshipDidSet("))
        #expect(lowered.contains("_ = Self.__quillRelationshipsRegistered"))
        #expect(lowered.contains("QuillRelationships.registerInverse("))
        #expect(lowered.contains("toMany: \\ConversationSD.messages"))
        #expect(lowered.contains("toOne: \\MessageSD.conversation"))
        #expect(lowered.contains("self.model = model"))
        #expect(!lowered.contains("self.conversation = conversation"))
        #expect(!lowered.contains("@Model"))
        #expect(!lowered.contains("@Transient"))
        #expect(!lowered.contains("#Predicate"))
    }

    @Test("hashable identity shim generator emits reusable model extensions")
    func hashableIdentityShimGeneratorEmitsModelExtensions() throws {
        let root = try packageRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillHashableShimTests-\(UUID().uuidString)", isDirectory: true)
        let output = directory.appendingPathComponent("GeneratedModelHashing.swift")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let script = root.appendingPathComponent("scripts/generate-hashable-identity-shims.sh")
        let result = try runScript(
            script,
            arguments: [
                output.path,
                "LanguageModelSD:name:id:String",
                "ConversationSD:id"
            ]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))

        let generated = try String(contentsOf: output, encoding: .utf8)
        #expect(generated.contains("extension LanguageModelSD: Hashable"))
        #expect(generated.contains("var id: String { name }"))
        #expect(generated.contains("lhs.name == rhs.name"))
        #expect(generated.contains("hasher.combine(name)"))
        #expect(generated.contains("extension ConversationSD: Hashable"))
        #expect(generated.contains("lhs.id == rhs.id"))
        #expect(generated.contains("hasher.combine(id)"))
    }

    @Test("Swift import helper inserts missing imports idempotently")
    func swiftImportHelperInsertsMissingImportsIdempotently() throws {
        let root = try packageRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillSwiftImportTests-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("Source", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let needsImport = source.appendingPathComponent("NeedsImport.swift")
        try """
        //
        // NeedsImport.swift
        //

        import Foundation

        struct NeedsImport {}
        """.write(to: needsImport, atomically: true, encoding: .utf8)

        let alreadyImported = source.appendingPathComponent("AlreadyImported.swift")
        try """
        import Foundation
        import AppKit

        struct AlreadyImported {}
        """.write(to: alreadyImported, atomically: true, encoding: .utf8)

        let noImport = source.appendingPathComponent("NoImport.swift")
        try "struct NoImport {}\n".write(to: noImport, atomically: true, encoding: .utf8)

        let script = root.appendingPathComponent("scripts/ensure-swift-imports.sh")
        for _ in 0..<2 {
            let result = try runScript(
                script,
                arguments: [
                    source.path,
                    "AppKit",
                    "NeedsImport.swift",
                    "AlreadyImported.swift",
                    "NoImport.swift",
                    "MissingOptional.swift"
                ]
            )
            #expect(result.status == 0, Comment(rawValue: result.output))
        }

        let lowered = try String(contentsOf: needsImport, encoding: .utf8)
        #expect(lowered.contains("import Foundation\nimport AppKit\n\nstruct NeedsImport"))

        let existing = try String(contentsOf: alreadyImported, encoding: .utf8)
        #expect(existing.components(separatedBy: "import AppKit").count == 2)

        let prepended = try String(contentsOf: noImport, encoding: .utf8)
        #expect(prepended.hasPrefix("import AppKit\nstruct NoImport"))
    }

    @Test("profile template installer copies nested replacement files")
    func profileTemplateInstallerCopiesNestedReplacementFiles() throws {
        let root = try packageRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillProfileTemplateTests-\(UUID().uuidString)", isDirectory: true)
        let templates = directory.appendingPathComponent("Templates", isDirectory: true)
        let output = directory.appendingPathComponent("Output", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let nestedTemplate = templates.appendingPathComponent("UI/Chat/Replacement.swift")
        try FileManager.default.createDirectory(
            at: nestedTemplate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "struct Replacement {}\n".write(to: nestedTemplate, atomically: true, encoding: .utf8)

        let topLevelTemplate = templates.appendingPathComponent("GeneratedAliases.swift")
        try "typealias Example = Int\n".write(to: topLevelTemplate, atomically: true, encoding: .utf8)

        let staleOutput = output.appendingPathComponent("UI/Chat/Replacement.swift")
        try FileManager.default.createDirectory(
            at: staleOutput.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "stale\n".write(to: staleOutput, atomically: true, encoding: .utf8)

        let script = root.appendingPathComponent("scripts/install-profile-templates.sh")
        let result = try runScript(script, arguments: [templates.path, output.path])
        #expect(result.status == 0, Comment(rawValue: result.output))

        let copiedNested = try String(contentsOf: staleOutput, encoding: .utf8)
        #expect(copiedNested == "struct Replacement {}\n")

        let copiedTopLevel = try String(
            contentsOf: output.appendingPathComponent("GeneratedAliases.swift"),
            encoding: .utf8
        )
        #expect(copiedTopLevel == "typealias Example = Int\n")
    }

    @Test("profile rewrite helper applies global and file-specific rules")
    func profileRewriteHelperAppliesGlobalAndFileSpecificRules() throws {
        let root = try packageRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillProfileRewriteTests-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("Source", isDirectory: true)
        let rules = directory.appendingPathComponent("Rules", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let nestedSource = source.appendingPathComponent("Nested/Target.swift")
        try FileManager.default.createDirectory(
            at: nestedSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        func target() async {
            await Example.shared.run()
            Value.old()
        }
        """.write(to: nestedSource, atomically: true, encoding: .utf8)

        let otherSource = source.appendingPathComponent("Other.swift")
        try """
        func other() async {
            await Example.shared.run()
            Value.old()
        }
        """.write(to: otherSource, atomically: true, encoding: .utf8)

        let nestedRule = rules.appendingPathComponent("Nested/Target.swift.pl")
        try FileManager.default.createDirectory(
            at: nestedRule.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "s/Value\\.old\\(\\)/Value.new()/g;\n".write(to: nestedRule, atomically: true, encoding: .utf8)
        try "s/await Example\\.shared\\.run\\(\\)/Example.shared.run()/g;\n".write(
            to: rules.appendingPathComponent("__all__.pl"),
            atomically: true,
            encoding: .utf8
        )

        let script = root.appendingPathComponent("scripts/apply-profile-rewrites.sh")
        let result = try runScript(script, arguments: [source.path, rules.path])
        #expect(result.status == 0, Comment(rawValue: result.output))

        let rewrittenNested = try String(contentsOf: nestedSource, encoding: .utf8)
        #expect(rewrittenNested.contains("Example.shared.run()"))
        #expect(rewrittenNested.contains("Value.new()"))

        let rewrittenOther = try String(contentsOf: otherSource, encoding: .utf8)
        #expect(rewrittenOther.contains("Example.shared.run()"))
        #expect(rewrittenOther.contains("Value.old()"))
    }

    @Test("profile truncate helper empties listed optional files")
    func profileTruncateHelperEmptiesListedOptionalFiles() throws {
        let root = try packageRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillProfileTruncateTests-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("Source", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existing = source.appendingPathComponent("Services/Legacy.swift")
        let nested = source.appendingPathComponent("UI/macOS/Panel.swift")
        let unlisted = source.appendingPathComponent("Keep.swift")
        for file in [existing, nested, unlisted] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "keep me\n".write(to: file, atomically: true, encoding: .utf8)
        }

        let list = directory.appendingPathComponent("empty-files.txt")
        try """
        # optional generated stubs
          Services/Legacy.swift
        UI/macOS/Panel.swift # inline comments are ignored
        Missing.swift

        """.write(to: list, atomically: true, encoding: .utf8)

        let script = root.appendingPathComponent("scripts/truncate-profile-files.sh")
        let result = try runScript(script, arguments: [source.path, list.path])
        #expect(result.status == 0, Comment(rawValue: result.output))

        #expect(try String(contentsOf: existing, encoding: .utf8).isEmpty)
        #expect(try String(contentsOf: nested, encoding: .utf8).isEmpty)
        #expect(try String(contentsOf: unlisted, encoding: .utf8) == "keep me\n")
    }

    @Test("profile budget audit enforces small shell glue")
    func profileBudgetAuditEnforcesSmallShellGlue() throws {
        let root = try packageRoot()
        let script = root.appendingPathComponent("scripts/audit-profile-budget.sh")

        let passing = try runScript(script, arguments: ["--max-shell-lines", "50"])
        #expect(passing.status == 0, Comment(rawValue: passing.output))
        #expect(passing.output.contains("scripts/profiles/enchanted-full-source/lower-profile-source.sh"))
        #expect(passing.output.contains("profile template budget report: scripts/profiles/enchanted-full-source/templates has"))

        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"),
            encoding: .utf8
        )
        #expect(workflow.contains("scripts/audit-profile-budget.sh --max-shell-lines 50 --max-template-lines 140"))

        let failing = try runScript(script, arguments: ["--profile", "enchanted-full-source", "--max-shell-lines", "1"])
        #expect(failing.status != 0, Comment(rawValue: failing.output))
        #expect(failing.output.contains("profile budget failed"))

        let templateFailing = try runScript(script, arguments: [
            "--profile", "enchanted-full-source",
            "--max-template-lines", "1"
        ])
        #expect(templateFailing.status != 0, Comment(rawValue: templateFailing.output))
        #expect(templateFailing.output.contains("profile template budget failed"))
    }

    @Test("Linux Swift test wrapper applies checkout patches before testing")
    func linuxSwiftTestWrapperAppliesCheckoutPatches() throws {
        let root = try packageRoot()
        let wrapper = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-swift-test.sh"),
            encoding: .utf8
        )
        #expect(wrapper.contains("SCRATCH_PATH=\".build-linux\""))
        #expect(wrapper.contains("--scratch-path=*"))
        #expect(wrapper.contains("scripts/prepare-linux-build-backend.sh"))
        #expect(!wrapper.contains("scripts/patch-swiftopenui-gtk-css.sh"))
        #expect(wrapper.contains("swift test --scratch-path \"$SCRATCH_PATH\""))

        let preparationScript = try String(
            contentsOf: root.appendingPathComponent("scripts/prepare-linux-build-backend.sh"),
            encoding: .utf8
        )
        #expect(preparationScript.contains("gtk)\n    \"$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh\" \"$SCRATCH_PATH\""))
        #expect(preparationScript.contains("qt)\n    ;;"))

        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/linux-ci.yml"),
            encoding: .utf8
        )
        #expect(workflow.contains("scripts/linux-swift-test.sh --scratch-path .build-linux"))
        #expect(workflow.contains("scripts/linux-swift-test.sh --scratch-path .build-linux-offscreen"))
    }

    @Test("Package exports generated app compatibility products")
    func packageExportsGeneratedAppCompatibilityProducts() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        #expect(manifest.contains("\"IOKit\""))
        #expect(manifest.contains(".target(\n        name: \"IOKit\""))
        #expect(manifest.contains("path: \"Sources/IOKit\""))
        #expect(manifest.contains("publicHeadersPath: \".\""))
        // UserNotifications and CoreTransferable are @_exported by the UIKit
        // shim so UIKit-only app files resolve notification and share/transfer
        // APIs without source edits.
        // Both targets take their dependencies from #if os(Linux)-swapped lists:
        // on Linux they add the QuartzCore shim (UIView.layer; UIKit re-exports
        // QuartzCore exactly like iOS), on Apple platforms the real QuartzCore
        // exists and the shim target doesn't. QuillKit rides in both arms: the
        // canonical UIApplication opens URLs / registers notifications through
        // QuillWorkspace + QuillNotificationService.
        #expect(manifest.contains(".target(name: \"UIKit\", dependencies: uiKitShimDependencies, path: \"Sources/UIKitShim\")"))
        #expect(manifest.contains("let uiKitShimDependencies: [Target.Dependency] ="))
        #expect(manifest.contains("[\"QuillFoundation\", \"QuillUIKit\", \"QuillKit\", \"UserNotifications\", \"QuartzCore\", \"CoreTransferable\"]"))
        #expect(manifest.contains(".target(\n        name: \"QuillUIKit\",\n        dependencies: quillUIKitDependencies,\n        path: \"Sources/QuillUIKit\"\n    )"))
        #expect(manifest.contains("let quillUIKitDependencies: [Target.Dependency] = [\"QuillFoundation\", \"QuillKit\", \"QuartzCore\"]"))
        #expect(manifest.contains("var productDeclaration: Product {\n        .executable(name: product, targets: [target])\n    }"))
        #expect(manifest.contains(".init(product: \"quill-wireguard\", target: \"QuillWireGuard\", qtPath: \"Sources/QuillWireGuardQt\", qtRuntime: .wireGuardQtNative)"))
        #expect(manifest.contains("] + quillCanonicalLinuxAppProducts"))
        #expect(manifest.contains("path: \"Sources/QuillWireGuardQt\""))
        #expect(manifest.contains(".library(name: \"QuillGenericQtNativeRuntime\", targets: [\"QuillGenericQtNativeRuntime\"])"))
        #expect(manifest.contains("name: \"QuillGenericQtNativeRuntime\""))
        #expect(manifest.contains("path: \"Sources/QuillGenericQtNativeRuntime\""))
        #expect(manifest.contains("var quillWireGuardCoreDependencies: [Target.Dependency] = []"))
        // QuillWireGuardCore picks up the real upstream WireGuardKit wherever it's vendored.
        #expect(manifest.contains("quillWireGuardCoreDependencies.append(\"WireGuardKit\")"))
        #expect(manifest.contains("var quillWireGuardUIDependencies: [Target.Dependency] = [\"QuillWireGuardCore\", \"QuillUI\"]"))
        #expect(manifest.contains("quillWireGuardUIDependencies.append(\"WireGuardKit\")"))
        #expect(manifest.contains("quillWireGuardUIDependencies.append(\"SwiftUI\")"))
        #expect(manifest.contains("dependencies: quillWireGuardCoreDependencies"))
        #expect(manifest.contains("dependencies: quillWireGuardUIDependencies"))
        #expect(manifest.contains("dependencies: quillWireGuardQtDependencies"))
    }

    @Test("visual smoke exposes opt-in Mac reference landmarks")
    func visualSmokeExposesOptInMacReferenceLandmarks() throws {
        let root = try packageRoot()
        let visualScript = try String(
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
        let legacyVisualScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-visual-check.sh"),
            encoding: .utf8
        )
        #expect(legacyVisualScript.contains("scripts/linux-backend-visual-check.sh"))
        #expect(backendProducts.contains("QUILLUI_BACKEND_MAC_REFERENCE"))
        #expect(smokeLib.contains("${reference_window_width}x${reference_window_height}x24"))
        #expect(visualScript.contains("quillui_backend_reference_window_defaults"))
        #expect(visualScript.contains("quillui_backend_screen_size"))
        #expect(!visualScript.contains("reference_window_width=\"${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}\""))
        #expect(visualScript.contains("quillui_append_backend_runtime_environment"))
        #expect(smokeLib.contains("quillui_backend_reference_window_defaults()"))
        #expect(smokeLib.contains("quillui_append_quill_chat_reference_environment_if_needed()"))
        #expect(smokeLib.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(smokeLib.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=$reference_window_height"))
        #expect(smokeLib.contains("QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label"))
        #expect(!smokeLib.contains("QUILLUI_GTK_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(!smokeLib.contains("QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label"))
        #expect(visualScript.contains("DISPLAY_ID=\"$(quillui_normalize_x_display_id \"${QUILLUI_BACKEND_VISUAL_DISPLAY:-:94}\")\""))
        #expect(visualScript.contains("quillui_backend_visual_verify_product \"$PRODUCT\" VERIFY_PRODUCT"))
        #expect(!visualScript.contains("${QUILLUI_GTK_MAC_REFERENCE:-0}"))
        #expect(!visualScript.contains("${QUILLUI_GTK_DEFAULT_WINDOW_WIDTH:-2048}"))
        #expect(!visualScript.contains("${QUILLUI_GTK_VISUAL_DISPLAY:-"))
        #expect(!visualScript.contains("${QUILLUI_GTK_SCREEN_SIZE:-"))
        #expect(!visualScript.contains("${QUILLUI_GTK_VERIFY_PRODUCT:-"))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_REFERENCE_MODE=1"))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_FORCE_UNREACHABLE=1"))
        #expect(smokeLib.contains("QUILLUI_ENCHANTED_PROFILE_MODE=1"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_REFERENCE_MODE=1"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_PROFILE_MODE=1"))
        #expect(smokeLib.contains("seed-quill-chat-reference-data.py"))
        #expect(visualScript.contains("quillui_find_quill_chat_reference_window \"$DISPLAY_ID\""))
        #expect(smokeLib.contains("quillui_find_quill_chat_reference_window()"))
        #expect(smokeLib.contains("quillui_place_reference_window()"))
        #expect(smokeLib.contains("openbox"))
        #expect(visualScript.contains("capture_window=\"$window_id\""))
        #expect(smokeLib.contains("quillui_backend_visual_verify_product()"))
        #expect(smokeLib.contains("quill-chat-linux-mac-reference"))

        let verifier = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-backend-screenshot.py"),
            encoding: .utf8
        )
        #expect(verifier.contains("validate_quill_chat_mac_reference"))
        #expect(verifier.contains("Mac-reference prompt card row was not detected"))
        #expect(verifier.contains("prompt_card_fill_height"))
        #expect(verifier.contains("Mac-reference prompt cards are too short"))
        #expect(verifier.contains("card_height={prompt_card_height}px"))
        #expect(verifier.contains("Mac-reference sidebar region rendered no content"))
        #expect(verifier.contains("mac_reference_sidebar_tint_pixel"))
        #expect(verifier.contains("Mac-reference sidebar lost its green-tinted source-list material"))
        #expect(verifier.contains("Mac-reference window controls were not detected"))
        #expect(verifier.contains("cool_wordmark_pixel"))
        #expect(verifier.contains("warm_wordmark_pixel"))
        #expect(verifier.contains("Mac-reference wordmark lost its blue-to-red color range"))
        #expect(verifier.contains("Mac-reference alert is too short"))
        #expect(verifier.contains("Quill Chat Mac-reference landmarks"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_composer_typed"))
        #expect(verifier.contains("Mac-reference typed composer text was not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_settings_panel"))
        #expect(verifier.contains("panel_kind = \"root-overlay\""))
        #expect(verifier.contains("top + int(app_height * 0.18)"))
        #expect(verifier.contains("abs(panel_segment.center - detail_center)"))
        #expect(verifier.contains("Mac-reference root-overlay settings panel is misplaced or too narrow"))
        #expect(verifier.contains("panel={panel_segment.width}px@{panel_y} ({panel_kind})"))
        #expect(verifier.contains("Mac-reference typed settings endpoint was not detected"))
        #expect(verifier.contains("endpoint_text_pixels >= 300"))
        #expect(verifier.contains("Mac-reference typed settings bearer token was not detected"))
        #expect(verifier.contains("root_overlay_field_text_pixels(2)"))
        #expect(verifier.contains("Mac-reference typed settings ping interval was not detected"))
        #expect(verifier.contains("root_overlay_field_text_pixels(3)"))
        #expect(verifier.contains("for y in range(panel_y + 32"))
        #expect(verifier.contains("ping_text_pixels >= 90"))
        #expect(verifier.contains("if not require_selected_default_model:"))
        #expect(verifier.contains("Mac-reference selected default model was not detected"))
        #expect(verifier.contains("model_x0 = panel_segment.start + 20"))
        #expect(verifier.contains("model_y0 = panel_y + 340"))
        #expect(verifier.contains("model_text_pixels >= 200"))
        #expect(verifier.contains("selected_model_pixels={model_text_pixels}"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_completions_panel"))
        #expect(verifier.contains("sheet_top = max(top, sheet_top - 64)"))
        #expect(verifier.contains("sheet_segment.start - 26"))
        #expect(verifier.contains("name_field_pixels >= 14_000"))
        #expect(verifier.contains("root_title_pixels = pixel_count"))
        #expect(verifier.contains("divider_threshold = 700"))
        #expect(verifier.contains("panel={panel_kind}"))
        #expect(verifier.contains("Mac-reference completions list dividers were not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_history_selection"))
        #expect(verifier.contains("Mac-reference selected history marker was not detected"))
        #expect(verifier.contains("top + int(app_height * 0.12)"))
        #expect(verifier.contains("left + 120"))
        #expect(verifier.contains("def selected_history_marker_pixel"))
        #expect(verifier.contains("selected_history_marker_pixel"))
        #expect(verifier.contains("top + int(app_height * 0.86)"))
        #expect(verifier.contains("marker_y, marker_peak_pixels = max("))
        #expect(verifier.contains("selected_row_text_y0 = max(marker_y - int(app_height * 0.025), top)"))
        #expect(verifier.contains("selected_row_pixels >= 180"))
        #expect(verifier.contains("selected_marker_peak={marker_peak_pixels}@{marker_y}"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-transcript-selection"))
        #expect(verifier.contains("Mac-reference selected transcript assistant message was not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_markdown_transcript_selection"))
        #expect(verifier.contains("Mac-reference markdown transcript code panel was not detected"))
        #expect(verifier.contains("Mac-reference markdown transcript table panel was not detected"))
        #expect(verifier.contains("Mac-reference markdown transcript table dividers were not detected"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-markdown-transcript-selection"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_message_hover_actions"))
        #expect(verifier.contains("Mac-reference message hover action icons were not detected"))
        #expect(verifier.contains("detail_left + int(detail_width * 0.78)"))
        #expect(verifier.contains("top + int(app_height * 0.11)"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-message-hover-actions"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_long_transcript_selection"))
        #expect(verifier.contains("Mac-reference long transcript did not scroll to the dense bottom marker"))
        #expect(verifier.contains("bottom_transcript_pixels >= 2_000"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-long-transcript-selection"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_prompt_send"))
        #expect(verifier.contains("Mac-reference {label} message content was not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_composer_send"))
        #expect(verifier.contains("message_y0 = top + int(app_height * 0.05)"))
        #expect(verifier.contains("message_y1 = top + int(app_height * 0.70)"))
        #expect(verifier.contains("selected_message_y0 = top + int(app_height * 0.05)"))
        #expect(verifier.contains("selected_message_y1 = top + int(app_height * 0.70)"))
        #expect(verifier.contains("detail_left + int(detail_width * 0.52),\n            selected_message_y1"))
        #expect(verifier.contains("Mac-reference {label} message did not align to the trailing edge"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_toolbar_model_selected"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-toolbar-model-selected"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-new-chat"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-copy-chat"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-copy-chat-json"))
        #expect(verifier.contains("validate_quill_chat_functional_transcript"))
        #expect(verifier.contains("Functional transcript assistant reply was not detected"))
        #expect(verifier.contains("transcript_message_y0 = top + int(app_height * 0.05)"))
        #expect(verifier.contains("transcript_message_y1 = top + int(app_height * 0.70)"))
        #expect(verifier.contains("quill-chat-linux-functional-transcript"))

        let interactionScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-backend-interaction-check.sh"),
            encoding: .utf8
        )
        let legacyInteractionScript = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-gtk-interaction-check.sh"),
            encoding: .utf8
        )
        #expect(legacyInteractionScript.contains("linux-backend-interaction-check.sh"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_INTERACTION_MODE"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_FOCUS_PRIME"))
        #expect(smokeLib.contains("QUILLUI_BACKEND_VERIFY_PRODUCT"))
        #expect(interactionScript.contains("quillui_backend_reference_window_defaults"))
        #expect(!interactionScript.contains("reference_window_width=\"${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}\""))
        #expect(interactionScript.contains("quillui_append_backend_runtime_environment"))
        #expect(!smokeLib.contains("QUILLUI_GTK_DEFAULT_WINDOW_WIDTH=$reference_window_width"))
        #expect(!interactionScript.contains("${QUILLUI_GTK_INTERACTION_MODE:-}"))
        #expect(!interactionScript.contains("${QUILLUI_GTK_FOCUS_PRIME"))
        #expect(!interactionScript.contains("${QUILLUI_GTK_CLICK_X:-"))
        #expect(!interactionScript.contains("${QUILLUI_GTK_VERIFY_PRODUCT:-"))
        #expect(interactionScript.contains("composer-typed"))
        #expect(interactionScript.contains("settings-panel"))
        #expect(interactionScript.contains("alert-settings-panel"))
        #expect(interactionScript.contains("click_x=\"${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 98))}\""))
        #expect(interactionScript.contains("click_y=\"${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 205))}\""))
        #expect(interactionScript.contains("settings-endpoint-typed"))
        #expect(interactionScript.contains("settings-bearer-token-typed"))
        #expect(interactionScript.contains("settings-ping-interval-typed"))
        #expect(interactionScript.contains("settings-default-model-selected"))
        #expect(interactionScript.contains("&& \"$INTERACTION_MODE\" == \"settings-default-model-selected\""))
        #expect(interactionScript.contains("INTERACTION_MAX_ATTEMPTS=4"))
        #expect(interactionScript.contains("attempt $INTERACTION_ATTEMPT/$INTERACTION_MAX_ATTEMPTS); retrying"))
        #expect(!interactionScript.contains("retrying once"))
        #expect(interactionScript.contains("settings-delete-confirmation"))
        #expect(interactionScript.contains("settings-delete-confirmed"))
        #expect(interactionScript.contains("confirm_quill_chat_settings_delete()"))
        #expect(interactionScript.contains("verify_quill_chat_delete_confirmed_if_needed()"))
        #expect(interactionScript.contains("Settings delete confirmed cleared conversation data"))
        #expect(interactionScript.contains("quill_chat_settings_click_x()"))
        #expect(interactionScript.contains("quill_chat_settings_click_y()"))
        #expect(interactionScript.contains("printf '%s\\n' \"${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 80))}\""))
        #expect(interactionScript.contains("printf '%s\\n' \"${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 60))}\""))
        #expect(interactionScript.contains("printf '%s\\n' \"${QUILLUI_BACKEND_SETTINGS_CLICK_X:-52}\""))
        #expect(interactionScript.contains("printf '%s\\n' \"${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-1366}\""))
        #expect(interactionScript.contains("click_x=\"${QUILLUI_BACKEND_CLICK_X:-$(quill_chat_settings_click_x)}\""))
        #expect(interactionScript.contains("click_y=\"${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_settings_click_y)}\""))
        #expect(interactionScript.contains("endpoint_x=\"${QUILLUI_BACKEND_ENDPOINT_CLICK_X:-650}\""))
        #expect(interactionScript.contains("token_x=\"${QUILLUI_BACKEND_TOKEN_CLICK_X:-1000}\""))
        #expect(interactionScript.contains("token_y=\"${QUILLUI_BACKEND_TOKEN_CLICK_Y:-831}\""))
        #expect(interactionScript.contains("ping_x=\"${QUILLUI_BACKEND_PING_CLICK_X:-1000}\""))
        #expect(interactionScript.contains("ping_y=\"${QUILLUI_BACKEND_PING_CLICK_Y:-853}\""))
        #expect(interactionScript.contains("model_x=\"${QUILLUI_BACKEND_MODEL_PICKER_CLICK_X:-770}\""))
        #expect(interactionScript.contains("model_y=\"${QUILLUI_BACKEND_MODEL_PICKER_CLICK_Y:-763}\""))
        #expect(interactionScript.contains("QUILLUI_BACKEND_MODEL_PICKER_OPEN_SLEEP"))
        #expect(interactionScript.contains("xdotool key --clearmodifiers Down Return"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_SELECTED_MODEL_NAME=${QUILLUI_BACKEND_SELECTED_MODEL_NAME:-mistral-7b-reference-linux-picker:latest}"))
        #expect(interactionScript.contains("xdotool key --clearmodifiers Escape"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_MODEL_PICKER_SETTLE_SLEEP"))
        #expect(interactionScript.contains("clear_x=\"${QUILLUI_BACKEND_CLEAR_ALL_CLICK_X:-1024}\""))
        #expect(interactionScript.contains("clear_y=\"${QUILLUI_BACKEND_CLEAR_ALL_CLICK_Y:-1000}\""))
        #expect(interactionScript.contains("refresh_capture_window_for_active_child_window"))
        // No capture==root gate on the child-window refresh (smoke sheets
        // present as separate toplevels); IM popups are filtered by the
        // minimum-size candidate gate.
        #expect(!interactionScript.contains("[[ \"$capture_window\" == \"root\" ]] || return 0"))
        #expect(!interactionScript.contains("[[ \"$capture_window\" != \"root\" ]] || return 0"))
        #expect(interactionScript.contains("quillui_window_is_plausible_capture_target \"$DISPLAY_ID\" \"$candidate_window\" \"$window_id\""))
        #expect(interactionScript.contains("xdotool key --clearmodifiers ctrl+a"))
        #expect(interactionScript.contains("token_y=\"${QUILLUI_BACKEND_TOKEN_CLICK_Y:-$((window_y + 222))}\""))
        #expect(interactionScript.contains("window_x + 52"))
        #expect(interactionScript.contains("window_height - 14"))
        #expect(interactionScript.contains("completions-panel"))
        #expect(interactionScript.contains("local reset_before_open=\"${1:-0}\""))
        #expect(interactionScript.contains("if [[ \"$reset_before_open\" == \"1\" ]]; then"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CLICK_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CLICK_Y"))
        #expect(interactionScript.contains("reset_x=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CLICK_X:-$(quill_chat_settings_click_x)}\""))
        #expect(interactionScript.contains("reset_y=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CLICK_Y:-$(quill_chat_settings_click_y)}\""))
        #expect(!interactionScript.contains("reset_y=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CLICK_Y:-$(quill_chat_mac_reference_history_row_y recent-transcript)}\""))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_SLEEP:-0.6"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_SLEEP:-0.6"))
        #expect(interactionScript.contains("reset_cancel_x=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_X:-$((window_x + 570))}}\""))
        #expect(interactionScript.contains("reset_cancel_y=\"${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_Y:-$((window_y + 382))}}\""))
        #expect(interactionScript.contains("quill_chat_completions_click_x()"))
        #expect(interactionScript.contains("quill_chat_completions_click_y()"))
        #expect(interactionScript.contains("printf '%s\\n' \"${QUILLUI_BACKEND_COMPLETIONS_CLICK_X:-$((window_x + 80))}\""))
        #expect(interactionScript.contains("printf '%s\\n' \"${QUILLUI_BACKEND_COMPLETIONS_CLICK_Y:-$((window_y + window_height - 188))}\""))
        #expect(interactionScript.contains("printf '%s\\n' \"${QUILLUI_BACKEND_COMPLETIONS_CLICK_Y:-$((window_y + 1244))}\""))
        #expect(interactionScript.contains("click_x=\"${QUILLUI_BACKEND_CLICK_X:-$(quill_chat_completions_click_x)}\""))
        #expect(interactionScript.contains("click_y=\"${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_completions_click_y)}\""))
        #expect(interactionScript.contains("open_quill_chat_completions_panel 1\n  if quillui_is_quill_chat_mac_reference_product \"$PRODUCT\"; then\n    edit_x="))
        #expect(!interactionScript.contains("open_quill_chat_new_completion_sheet() {\n  local new_x\n  local new_y\n\n  open_quill_chat_completions_panel 1"))
        #expect(interactionScript.contains("window_x + 90"))
        #expect(interactionScript.contains("window_height - 136"))
        #expect(interactionScript.contains("completions-new-sheet"))
        #expect(interactionScript.contains("completions-save"))
        #expect(interactionScript.contains("completions-edit-save"))
        #expect(interactionScript.contains("completions-delete"))
        #expect(interactionScript.contains("save_quill_chat_new_completion()"))
        #expect(interactionScript.contains("edit_quill_chat_existing_completion()"))
        #expect(interactionScript.contains("delete_quill_chat_completion()"))
        #expect(interactionScript.contains("quill_chat_mac_reference_completions_panel_visible()"))
        #expect(interactionScript.contains("ensure_quill_chat_completions_panel_open()"))
        #expect(interactionScript.contains("python3 \"$ROOT_DIR/scripts/verify-backend-screenshot.py\""))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETION_NAME_TEXT"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_TEXT"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETION_EDITED_NAME_TEXT"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X"))
        #expect(interactionScript.contains("name_y=\"${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 462))}\""))
        #expect(interactionScript.contains("instruction_x=\"${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X:-$((window_x + 720))}\""))
        #expect(interactionScript.contains("instruction_y=\"${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y:-$((window_y + 548))}\""))
        #expect(interactionScript.contains("Reply with a concise Linux validation response."))
        #expect(interactionScript.contains("save_x=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + 1448))}\""))
        #expect(interactionScript.contains("save_y=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 407))}\""))
        #expect(!interactionScript.contains("name_y=\"${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 468))}\""))
        #expect(!interactionScript.contains("save_x=\"${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + 1450))}\""))
        #expect(interactionScript.contains("history-selection"))
        #expect(interactionScript.contains("transcript-selection"))
        #expect(interactionScript.contains("markdown-transcript-selection"))
        #expect(interactionScript.contains("message-hover-actions"))
        #expect(interactionScript.contains("hover_quill_chat_message_actions()"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_MESSAGE_HOVER_X"))
        #expect(interactionScript.contains("hover_x=\"${QUILLUI_BACKEND_MESSAGE_HOVER_X:-1900}\""))
        #expect(interactionScript.contains("hover_y=\"${QUILLUI_BACKEND_MESSAGE_HOVER_Y:-124}\""))
        #expect(interactionScript.contains("refocus_capture_window()"))
        #expect(interactionScript.contains("move_pointer_to()"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_MESSAGE_HOVER_RESET_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_MESSAGE_HOVER_ENTRY_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_MESSAGE_HOVER_NUDGE_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_MESSAGE_HOVER_SETTLE_SLEEP"))
        #expect(interactionScript.contains("sleep \"${QUILLUI_BACKEND_MESSAGE_HOVER_SLEEP:-2}\""))
        #expect(interactionScript.contains("long-transcript-selection"))
        #expect(interactionScript.contains("long-transcript-selection|long-transcript-auto-selection)"))
        #expect(interactionScript.contains("quill_chat_mac_reference_history_row_y()"))
        #expect(interactionScript.contains("recent-transcript)"))
        #expect(interactionScript.contains("window_y + 540"))
        #expect(interactionScript.contains("markdown-transcript)"))
        #expect(interactionScript.contains("window_y + 1058"))
        #expect(interactionScript.contains("window_y + 590"))
        #expect(interactionScript.contains("long-transcript)"))
        #expect(interactionScript.contains("window_y + 638"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_SCROLL_CLICKS"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_SCROLL_CLICK_DELAY"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_SCROLL_KEY_REPEATS"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_SCROLL_KEY_DELAY"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_SCROLL_SETTLE_SLEEP"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_SCROLL_AFTER_SLEEP"))
        #expect(interactionScript.contains("click_at \"$scroll_x\" \"$scroll_y\""))
        #expect(interactionScript.contains("if [[ \"$INTERACTION_MODE\" == \"long-transcript-auto-selection\" ]]"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_AUTOSCROLL_AFTER_SLEEP"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_AUTOSCROLL_AFTER_SLEEP:-9"))
        #expect(interactionScript.contains("QuillMessageList retries Linux ScrollViewReader bottom-scroll at 5s"))
        #expect(interactionScript.contains("xdotool key --clearmodifiers End"))
        #expect(interactionScript.contains("scroll_clicks=\"${QUILLUI_BACKEND_SCROLL_CLICKS:-4800}\""))
        #expect(interactionScript.contains("scroll_click_delay=\"${QUILLUI_BACKEND_SCROLL_CLICK_DELAY:-5}\""))
        #expect(interactionScript.contains("xdotool click --repeat \"$scroll_clicks\" --delay \"$scroll_click_delay\" 5"))
        #expect(interactionScript.contains("xdotool click --repeat"))
        #expect(interactionScript.contains("prompt-send"))
        #expect(interactionScript.contains("composer-send"))
        #expect(interactionScript.contains("toolbar-model-selected"))
        #expect(interactionScript.contains("select_quill_chat_toolbar_model_and_send_prompt()"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_MODEL_MENU_CLICK_X"))
        #expect(interactionScript.contains("mistral-7b-reference-linux-picker:latest"))
        #expect(interactionScript.contains("quill_chat_latest_conversation_uses_model()"))
        #expect(interactionScript.contains("new-chat"))
        #expect(interactionScript.contains("open_quill_chat_new_chat()"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_NEW_CHAT_CLICK_X"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_HISTORY_CLICK_X"))
        #expect(interactionScript.contains("if [[ \"$SELECTED_BACKEND\" == \"qt\" ]]; then"))
        #expect(interactionScript.contains("new_chat_x=\"${QUILLUI_BACKEND_NEW_CHAT_CLICK_X:-$((window_x + window_width - 70))}\""))
        #expect(interactionScript.contains("new_chat_y=\"${QUILLUI_BACKEND_NEW_CHAT_CLICK_Y:-$((window_y + 57))}\""))
        #expect(interactionScript.contains("copy-chat"))
        #expect(interactionScript.contains("copy-chat-json"))
        #expect(interactionScript.contains("copy_quill_chat_transcript()"))
        #expect(interactionScript.contains("select_quill_chat_markdown_transcript()"))
        #expect(interactionScript.contains("menu_x=\"${QUILLUI_BACKEND_MENU_CLICK_X:-$((window_x + window_width - 170))}\""))
        #expect(interactionScript.contains("QUILLUI_BACKEND_CLIPBOARD_RUNTIME_DIR"))
        #expect(interactionScript.contains("QUILLUI_GTK_TOOLBAR_ACTION_COMMAND_DIR=$quill_gtk_toolbar_action_command_dir"))
        #expect(interactionScript.contains("! -s \"$clipboard_file\""))
        #expect(interactionScript.contains("printf '%s\\n' \"$action_title\" > \"$quill_gtk_toolbar_action_command_dir/command-$(date +%s%N)-$$\""))
        #expect(interactionScript.contains("QUILLUI_BACKEND_COPY_CHAT_JSON_CLICK_Y"))
        #expect(interactionScript.contains("copy_y=\"${QUILLUI_BACKEND_COPY_CHAT_JSON_CLICK_Y:-126}\""))
        #expect(interactionScript.contains("Copy Chat pasteboard text verified"))
        #expect(interactionScript.contains("Copy Chat as JSON pasteboard text verified"))
        #expect(interactionScript.contains("json.load(stream)"))
        #expect(interactionScript.contains("Toolbar model selection verified through QuillData"))
        #expect(smokeLib.contains("QUILLUI_QUILL_CHAT_REFERENCE_MODE=1"))
        #expect(interactionScript.contains("QUILLUI_BACKEND_TYPE_TEXT"))
        #expect(interactionScript.contains("generic_backend_list_selection_y()"))
        #expect(interactionScript.contains("click_generic_backend_list_selection()"))
        #expect(interactionScript.contains("enchanted_list_selection_y()"))
        #expect(interactionScript.contains("click_enchanted_list_selection()"))
        #expect(interactionScript.contains("click_chat_list_selection()"))
        #expect(interactionScript.contains("click_backend_header_action()"))
        #expect(interactionScript.contains("quillui_backend_interaction_verify_product \"$PRODUCT\" \"$INTERACTION_MODE\" VERIFY_PRODUCT"))
        #expect(smokeLib.contains("quillui_backend_interaction_verify_product()"))
        #expect(smokeLib.contains("quillui_backend_app_interaction_verify_product_for_product \"$product\" \"$selected_backend\" \"$interaction_mode\""))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-composer-typed"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-settings-panel"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-settings-endpoint-typed"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-settings-bearer-token-typed"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-settings-ping-interval-typed"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-settings-default-model-selected"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-settings-delete-confirmation"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-completions-panel"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-completions-new-sheet"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-completions-saved"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-completions-edited"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-completions-deleted"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-history-selection"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-transcript-selection"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-markdown-transcript-selection"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-long-transcript-selection"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-prompt-send"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-new-chat"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-copy-chat"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-copy-chat-json"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-toolbar-model-selected"))
        #expect(backendProducts.contains("quillui_backend_quill_chat_interaction_verify_product()"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-composer-typed"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-settings-panel"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-settings-endpoint-typed"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-settings-bearer-token-typed"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-settings-ping-interval-typed"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-settings-default-model-selected"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-settings-delete-confirmation"))
        #expect(backendProducts.contains("*:settings-delete-confirmed)"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-completions-panel"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-completions-new-sheet"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-completions-saved"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-completions-edited"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-completions-deleted"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-history-selection"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-transcript-selection"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-markdown-transcript-selection"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-message-hover-actions"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-long-transcript-selection"))
        #expect(backendProducts.contains("*:long-transcript-selection|*:long-transcript-auto-selection)"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-prompt-send"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-composer-send"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-new-chat"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-copy-chat"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-copy-chat-json"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-toolbar-model-selected"))
        #expect(backendProducts.contains("*:composer-send)"))
        #expect(backendProducts.contains("*:new-chat)"))
        #expect(backendProducts.contains("*:copy-chat)"))
        #expect(backendProducts.contains("*:copy-chat-json)"))
        #expect(backendProducts.contains("*:toolbar-model-selected)"))

        let functionalScript = try String(
            contentsOf: root.appendingPathComponent("scripts/quill-chat-functional-check.sh"),
            encoding: .utf8
        )
        let mockOllama = try String(
            contentsOf: root.appendingPathComponent("scripts/mock-ollama.py"),
            encoding: .utf8
        )
        #expect(functionalScript.contains("scripts/mock-ollama.py"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_MESSAGE"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_REPLY"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_VERIFY_RELAUNCH"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_RELAUNCH_SCREENSHOT"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_XVFB_LOG"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_OPENBOX_LOG"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_MOCK_START_DEADLINE"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_SEND_DEADLINE"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_RELAUNCH_DEADLINE"))
        #expect(functionalScript.contains("QUILLDATA_HOME=$RUN_HOME"))
        #expect(functionalScript.contains("mock Ollama did not start"))
        #expect(functionalScript.contains("quillui_functional_xdotool()"))
        #expect(functionalScript.contains("quillui_functional_default_display()"))
        #expect(functionalScript.contains("for candidate in :96 :97 :98 :99"))
        #expect(functionalScript.contains("QUILLUI_FUNCTIONAL_XDOTOOL_TIMEOUT"))
        #expect(functionalScript.contains("launch_app_instance()"))
        #expect(functionalScript.contains("resolve_app_window_geometry()"))
        #expect(functionalScript.contains("payload.get(\"path\") == \"/api/chat\""))
        #expect(functionalScript.contains("home / \".quilldata\" / \"default.sqlite\""))
        #expect(functionalScript.contains("row[0].endswith(\"_MessageSD\")"))
        #expect(functionalScript.contains("len(matching_request_users) == 1"))
        #expect(functionalScript.contains("request_ok and user_persisted and assistant_persisted"))
        #expect(functionalScript.contains("baseline_chat_requests"))
        #expect(functionalScript.contains("last_request_count == baseline_chat_requests"))
        #expect(functionalScript.contains("quill-chat-linux-functional-transcript"))
        #expect(functionalScript.contains("Functional relaunch screenshot"))
        #expect(functionalScript.contains("Functional failure screenshot"))
        #expect(functionalScript.contains("quillui_print_backend_app_log_tail"))
        #expect(functionalScript.contains("Mock Ollama log"))
        #expect(functionalScript.contains("window_height - 190"))
        #expect(functionalScript.contains("window_x + 110"))
        #expect(functionalScript.contains("window_y + 172"))
        #expect(functionalScript.contains("Click the row band rather than the header"))
        #expect(!functionalScript.contains("QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1"))
        #expect(!functionalScript.contains("QUILLUI_ENCHANTED_FORCE_UNREACHABLE=1"))
        #expect(mockOllama.contains("class MockOllamaHandler"))
        #expect(mockOllama.contains("\"method\": \"GET\""))
        #expect(mockOllama.contains("\"method\": \"POST\""))
        #expect(mockOllama.contains("self.path == \"/api/tags\""))
        #expect(mockOllama.contains("self.path != \"/api/chat\""))
        #expect(mockOllama.contains("application/x-ndjson"))

        let parityWorkflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/enchanted-parity.yml"),
            encoding: .utf8
        )
        #expect(parityWorkflow.contains("openbox"))
        #expect(parityWorkflow.contains("QUILLUI_BACKEND_SKIP_BUILD: \"1\""))
        #expect(parityWorkflow.contains("Run packaged release artifact interaction verifiers"))
        #expect(parityWorkflow.contains("quill_chat_modes=\"$(scripts/quillui-backend-products.sh quill-chat-mac-reference-interaction-modes)\""))
        #expect(parityWorkflow.contains("$quill_chat_modes"))
        #expect(backendProducts.contains("quillui_backend_quill_chat_mac_reference_interaction_modes()"))
        #expect(backendProducts.contains("quill-chat-mac-reference-interaction-modes)"))
        #expect(backendProducts.contains("settings-panel"))
        #expect(backendProducts.contains("alert-settings-panel"))
        #expect(backendProducts.contains("settings-endpoint-typed"))
        #expect(backendProducts.contains("settings-bearer-token-typed"))
        #expect(backendProducts.contains("settings-ping-interval-typed"))
        #expect(backendProducts.contains("settings-default-model-selected"))
        #expect(backendProducts.contains("settings-delete-confirmation"))
        #expect(backendProducts.contains("settings-delete-confirmed"))
        #expect(backendProducts.contains("completions-panel"))
        #expect(backendProducts.contains("completions-new-sheet"))
        #expect(backendProducts.contains("completions-save"))
        #expect(backendProducts.contains("completions-edit-save"))
        #expect(backendProducts.contains("completions-delete"))
        #expect(backendProducts.contains("new-chat"))
        #expect(backendProducts.contains("toolbar-model-selected"))
        #expect(backendProducts.contains("prompt-send"))
        #expect(backendProducts.contains("copy-chat"))
        #expect(backendProducts.contains("copy-chat-json"))
        #expect(backendProducts.contains("history-selection"))
        #expect(backendProducts.contains("transcript-selection"))
        #expect(backendProducts.contains("markdown-transcript-selection"))
        #expect(backendProducts.contains("message-hover-actions"))
        #expect(backendProducts.contains("long-transcript-selection"))
        #expect(backendProducts.contains("long-transcript-auto-selection"))
        #expect(!backendProducts.contains("message-hover-actions \\\n    long-transcript-selection \\"))
        #expect(parityWorkflow.contains(".qa/quill-chat-linux-release-artifact-{mode}-gtk.png"))
        #expect(parityWorkflow.contains("Package real-source GTK release artifact"))
        #expect(parityWorkflow.contains("scripts/package-swiftui-linux-app.sh"))
        #expect(parityWorkflow.contains("--artifact-dir .build/releases/quill-chat-linux-gtk"))
        #expect(parityWorkflow.contains("--tarball .qa/quill-chat-linux-gtk-release.tar.gz"))
        #expect(parityWorkflow.contains("--app-id io.lorehex.QuillChat"))
        #expect(parityWorkflow.contains("--summary \"Quill Chat is an Apple Swift chat app packaged for Linux through QuillUI.\""))
        #expect(parityWorkflow.contains("--categories \"Utility;Network;\""))
        #expect(parityWorkflow.contains("--bundle-swift-runtime"))
        #expect(parityWorkflow.contains("scripts/check-linux-app-metadata.sh"))
        #expect(parityWorkflow.contains("io.lorehex.QuillChat"))
        #expect(parityWorkflow.contains("scripts/generate-flatpak-manifest.sh"))
        #expect(parityWorkflow.contains("--output .qa/io.lorehex.QuillChat.flatpak.json"))
        #expect(parityWorkflow.contains("python3 -m json.tool .qa/io.lorehex.QuillChat.flatpak.json >/dev/null"))
        #expect(parityWorkflow.contains("scripts/check-linux-app-runtime-deps.sh"))
        #expect(parityWorkflow.contains("--require-bundled-swift-runtime"))
        #expect(parityWorkflow.contains("--report .qa/quill-chat-linux-runtime-deps.tsv"))
        #expect(parityWorkflow.contains("Run packaged release artifact visual verifier"))
        #expect(parityWorkflow.contains("echo \"QUILLUI_BACKEND_APP_EXECUTABLE=$PWD/.build/releases/quill-chat-linux-gtk/run\" >> \"$GITHUB_ENV\""))
        #expect(parityWorkflow.contains(".qa/quill-chat-linux-release-artifact-gtk.png"))
        #expect(parityWorkflow.contains("scripts/run-linux-backend-interaction-modes.sh"))
        #expect(parityWorkflow.contains("QUILLUI_BACKEND_INTERACTION_APP_LOG_TEMPLATE: \".qa/quill-chat-linux-release-artifact-{mode}.log\""))
        #expect(parityWorkflow.contains("QUILLUI_BACKEND_INTERACTION_MODE_TIMEOUT: \"120s\""))
        #expect(!parityWorkflow.contains(".qa/quill-chat-linux-release-artifact-new-chat-gtk.png"))
        #expect(!parityWorkflow.contains(".qa/quill-chat-linux-mac-reference-{mode}-gtk.png"))
        #expect(!parityWorkflow.contains("for mode in \\"))
        #expect(parityWorkflow.contains("Run live composer-send and relaunch functional verifier"))
        #expect(parityWorkflow.contains("scripts/quill-chat-functional-check.sh"))
        #expect(parityWorkflow.contains(".qa/quill-chat-linux-functional-composer-send-gtk.png"))
        #expect(parityWorkflow.contains("timeout --kill-after=15s 180s"))
        #expect(parityWorkflow.contains("QUILLUI_FUNCTIONAL_VERIFY_RELAUNCH: \"1\""))
        #expect(parityWorkflow.contains("QUILLUI_FUNCTIONAL_COMPOSER_X: \"700\""))
        #expect(parityWorkflow.contains("QUILLUI_FUNCTIONAL_COMPOSER_Y: \"1190\""))

        let seedScript = try String(
            contentsOf: root.appendingPathComponent("scripts/seed-quill-chat-reference-data.py"),
            encoding: .utf8
        )
        #expect(seedScript.contains("\"GeneratedSwiftUILinuxApp.MessageSD\""))
        #expect(seedScript.contains("Use **flexbox**: set `display` to `flex`"))
        #expect(seedScript.contains("[MDN flexbox](https://developer.mozilla.org/docs/Web/CSS/CSS_flexible_box_layout)"))
        #expect(seedScript.contains("```css"))
        #expect(seedScript.contains("justify-content: center"))
        #expect(seedScript.contains("| Property | Value |"))
        #expect(seedScript.contains("| display | `flex` |"))
        #expect(seedScript.contains("Long transcript scroll test"))
        #expect(seedScript.contains("bottom scroll target is visible near the composer"))
        #expect(seedScript.contains("\"conversation\": transcript_conversation_payload"))

        let enchantedSeedScript = try String(
            contentsOf: root.appendingPathComponent("scripts/seed-enchanted-reference-data.py"),
            encoding: .utf8
        )
        #expect(enchantedSeedScript.contains("home / \".quilldata\" / \"default.sqlite\""))
        #expect(enchantedSeedScript.contains("_quilldata_json_GeneratedSwiftUILinuxApp_ConversationSD"))
        #expect(enchantedSeedScript.contains("_quilldata_json_GeneratedSwiftUILinuxApp_MessageSD"))
        #expect(enchantedSeedScript.contains("_quilldata_json_GeneratedSwiftUILinuxApp_LanguageModelSD"))
        #expect(enchantedSeedScript.contains("quill_chat_reference_items(now)"))
        #expect(enchantedSeedScript.contains("dt.datetime.now(dt.timezone.utc).replace(microsecond=0)"))
        #expect(enchantedSeedScript.contains("mistral-7b-reference-linux-picker:latest"))
        #expect(enchantedSeedScript.contains("image_support=False"))
        #expect(enchantedSeedScript.contains("Auto-config test: reply with one short phrase"))
        #expect(enchantedSeedScript.contains("Write a text message asking a friend"))
        #expect(enchantedSeedScript.contains("How to center div in HTML?"))
        #expect(enchantedSeedScript.contains("Long transcript scroll test"))
        #expect(enchantedSeedScript.contains("Use **flexbox**: set `display` to `flex`"))
        #expect(enchantedSeedScript.contains("Final answer: bottom scroll target is visible near the composer"))
        #expect(enchantedSeedScript.contains("\"name\": name"))
        #expect(enchantedSeedScript.contains("\"conversation\": conversation_payload"))
        #expect(enchantedSeedScript.contains("\"modelProvider\": {\"ollama\": {}}"))
        #expect(enchantedSeedScript.contains("home / \".quillui\" / \"enchanted\" / \"enchanted-quilldata.sqlite\""))

        let controls = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/Controls.swift"),
            encoding: .utf8
        )
        #expect(controls.contains("#if os(Linux)"))
        #expect(controls.contains("promptCard(prompt)"))
        #expect(controls.contains("Button(action: { action(prompt) })"))
        #expect(controls.contains("public struct QuillSidebarNavigationButton"))
        #expect(controls.contains("Button(action: action)"))
        #expect(controls.contains("Button(action: {\n                    action?()"))
        #expect(controls.contains(".buttonStyle(.plain)"))
        #expect(controls.contains("quillBackendReferenceWindowWidth"))
        #expect(controls.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH"))
        #expect(controls.contains("QuillBackendRegistry\n        .backendScopedEnvironmentValue("))
        #expect(controls.contains("preferred: QuillBackendRuntimeContext.selectedBackend"))
        #expect(controls.contains("gtkLegacy: \"QUILLUI_GTK_DEFAULT_WINDOW_WIDTH\""))
        #expect(controls.contains("qtScoped: \"QUILLUI_QT_DEFAULT_WINDOW_WIDTH\""))
        #expect(controls.contains("gtkLegacy: \"QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT\""))
        #expect(controls.contains("qtScoped: \"QUILLUI_QT_DEFAULT_WINDOW_HEIGHT\""))
        #expect(!controls.contains("quillGTKReferenceWindowWidth"))

        let modelStoreRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/Stores/LanguageModelStore.swift.pl"),
            encoding: .utf8
        )
        #expect(modelStoreRule.contains("QUILLUI_ENCHANTED_REFERENCE_MODE"))
        #expect(modelStoreRule.contains("QUILLUI_QUILL_CHAT_REFERENCE_MODE"))
        #expect(modelStoreRule.contains("llava:latest"))
        #expect(modelStoreRule.contains("self.selectedModel = fallbackModel"))
        #expect(modelStoreRule.contains("self.selectedModel = fallbackModels.first"))
        #expect(modelStoreRule.contains("let availableModels = storedModels.filter"))
        #expect(modelStoreRule.contains("self.selectedModel = availableModels.first"))
        #expect(modelStoreRule.contains("self.supportsImages = self.selectedModel?.supportsImages ?? availableModels.first?.supportsImages ?? false"))

        let applicationEntryPointRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/Application/EnchantedApp.swift.pl"),
            encoding: .utf8
        )
        #expect(applicationEntryPointRule.contains("WindowGroup(\"Quill Chat\")"))

        let chatViewRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/macOS/Chat/ChatView_macOS.swift.pl"),
            encoding: .utf8
        )
        #expect(chatViewRule.contains("Text(\"Quill Chat\")"))
        #expect(chatViewRule.contains("title: \"Quill Chat\""))
        #expect(chatViewRule.contains("(?:maxWidth|width): 800"))

        let chatViewTemplate = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/macOS/Chat/ChatView_macOS.swift"),
            encoding: .utf8
        )
        #expect(chatViewTemplate.contains("QuillModelConversationChatScaffold("))
        #expect(chatViewTemplate.contains("selectedConversationID: selectedConversation?.id.uuidString"))
        #expect(chatViewTemplate.contains("models: modelsList"))
        #expect(chatViewTemplate.contains("selectedModelID: selectedModel?.name"))
        #expect(chatViewTemplate.contains("reachable: reachable"))
        #expect(chatViewTemplate.contains("onNewConversation: onNewConversationTap"))
        #expect(chatViewTemplate.contains("editContent: \\.content"))
        #expect(!chatViewTemplate.contains("QuillEditableDesktopChatScaffold("))
        #expect(!chatViewTemplate.contains("QuillDesktopChatScaffold("))
        #expect(!chatViewTemplate.contains("QuillDesktopChatConversationSidebar("))
        #expect(chatViewTemplate.contains("conversations: conversations"))
        #expect(chatViewTemplate.contains("settingsFocusedValue: \\.showSettings"))
        #expect(chatViewTemplate.contains("conversationID: { $0.id.uuidString }"))
        #expect(chatViewTemplate.contains("conversationTitle: \\.name"))
        #expect(chatViewTemplate.contains("conversationUpdatedAt: \\.updatedAt"))
        #expect(chatViewTemplate.contains("conversationDateTitle: { $0.daysAgoString() }"))
        #expect(chatViewTemplate.contains("onSettings: { Task { Haptics.shared.mediumTap() } }"))
        #expect(chatViewTemplate.contains("onSelectConversation: onConversationTap"))
        #expect(chatViewTemplate.contains("onDeleteConversation: onConversationDelete"))
        #expect(chatViewTemplate.contains("onDeleteDailyConversations: onDeleteDailyConversations"))
        #expect(!chatViewTemplate.contains("SidebarView("))
        #expect(!chatViewTemplate.contains("QuillMenuAction.selectableModels("))
        #expect(chatViewTemplate.contains("modelID: \\.name"))
        #expect(chatViewTemplate.contains("modelName: \\.prettyName"))
        #expect(chatViewTemplate.contains("modelVersion: \\.prettyVersion"))
        #expect(chatViewTemplate.contains("onSelectModel: { onSelectModel($0) }"))
        #expect(!chatViewTemplate.contains("QuillMenuAction.copyChatActions(copy: copyChat)"))
        #expect(chatViewTemplate.contains("composer: { message, editMessage in"))
        #expect(chatViewTemplate.contains("message: message"))
        #expect(chatViewTemplate.contains("editMessage: editMessage"))
        #expect(!chatViewTemplate.contains("@State private var message"))
        #expect(!chatViewTemplate.contains("@State private var editMessage"))
        #expect(!chatViewTemplate.contains("@FocusState private var isFocusedInput"))
        #expect(!chatViewTemplate.contains(".quillSyncEditableMessage($editMessage, draft: $message, isFocused: $isFocusedInput, content: \\.content)"))
        #expect(!chatViewTemplate.contains("QuillSelectedPromptEmptyState("))
        #expect(chatViewTemplate.contains("promptSource: SamplePrompts.samples"))
        #expect(chatViewTemplate.contains("promptID: \\.id"))
        #expect(chatViewTemplate.contains("promptTitle: \\.prompt"))
        #expect(chatViewTemplate.contains("promptSystemImage: { $0.type.icon }"))
        #expect(chatViewTemplate.contains("sendPrompt: QuillPrompt.selectedModelSender("))
        #expect(chatViewTemplate.contains("selectedModel: selectedModel"))
        #expect(chatViewTemplate.contains("onSend: onSendMessageTap"))
        #expect(!chatViewTemplate.contains("EmptyConversaitonView("))
        #expect(!chatViewTemplate.contains("QuillChatUnreachableBanner {"))
        #expect(!chatViewTemplate.contains(".frame(maxWidth: 1524)"))
        #expect(!chatViewTemplate.contains("UnreachableAPIView()"))
        #expect(!chatViewTemplate.contains("private func sendPrompt(_ selectedMessage: String)"))
        #expect(!chatViewTemplate.contains("QuillMenuAction.selectableItems("))
        #expect(!chatViewTemplate.contains("emptyTitle: \"No models available\""))
        #expect(!chatViewTemplate.contains("QuillMenuAction(title: \"Copy Chat\""))
        #expect(!chatViewTemplate.contains("QuillMenuAction(title: \"Copy Chat as JSON\""))
        #expect(!chatViewTemplate.contains("} toolbar: {"))
        #expect(!chatViewTemplate.contains("QuillDesktopChatToolbar("))
        #expect(!chatViewTemplate.contains(".onChange(of: editMessage, initial: false)"))
        #expect(!chatViewTemplate.contains("message = newMessage.content"))
        #expect(!chatViewTemplate.contains("isFocusedInput = true"))
        #expect(!chatViewTemplate.contains("modelsList.map { model in"))
        #expect(!chatViewTemplate.contains("QuillDesktopSplitLayout("))
        #expect(!chatViewTemplate.contains("VStack(alignment: .center, spacing: 0)"))
        #expect(!chatViewTemplate.contains(".frame(width: 800)"))
        #expect(!chatViewTemplate.contains("composerWidth:"))

        let emptyFiles = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/empty-files.txt"),
            encoding: .utf8
        )
        #expect(emptyFiles.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!emptyFiles.contains("UI/Shared/Chat/Components/EmptyConversaitonView.swift"))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/Shared/Chat/Components/EmptyConversaitonView.swift").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/Shared/Chat/Components/EmptyConversaitonView.swift.pl").path
        ))

        let optionalEmptyFiles = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/empty-files.txt"),
            encoding: .utf8
        )
        #expect(optionalEmptyFiles.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!optionalEmptyFiles.contains("UI/Shared/Sidebar/SidebarView.swift"))
        #expect(!optionalEmptyFiles.contains("UI/Shared/Sidebar/Components/ConversationHistoryListView.swift"))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/Shared/Sidebar/SidebarView.swift").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/Shared/Sidebar/Components/ConversationHistoryListView.swift").path
        ))

        let messageListTemplate = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/Shared/Chat/Components/MessageListVIew.swift"),
            encoding: .utf8
        )
        #expect(messageListTemplate.contains("QuillEditableMessageList("))
        #expect(messageListTemplate.contains("editingMessage: $editMessage"))
        #expect(messageListTemplate.contains("content: \\.content"))
        #expect(messageListTemplate.contains("isUserMessage: { $0.role == \"user\" }"))
        #expect(messageListTemplate.contains("interactionAvailability: .platformDefaults"))
        #expect(messageListTemplate.contains("selectText: { messageSelected = $0 }"))
        #expect(messageListTemplate.contains("readAloud: { onReadAloud($0.content) }"))
        #expect(!messageListTemplate.contains("QuillMessageList("))
        #expect(!messageListTemplate.contains("scrollToken: messages.quillMessageListScrollToken(content: \\.content)"))
        #expect(!messageListTemplate.contains("actions: contextMenuActions"))
        #expect(!messageListTemplate.contains("scrollToken: scrollToken"))
        #expect(!messageListTemplate.contains("private var scrollToken: AnyHashable"))
        #expect(!messageListTemplate.contains("messages.map(\\.id).map(\\.uuidString).joined(separator: \"|\")"))
        #expect(!messageListTemplate.contains("private func contextMenuActions(for message: MessageSD) -> [QuillMenuAction]"))
        #expect(!messageListTemplate.contains("QuillMenuAction.chatMessageActions("))
        #expect(!messageListTemplate.contains("content: message.content"))
        #expect(!messageListTemplate.contains("isUserMessage: message.role == \"user\""))
        #expect(!messageListTemplate.contains("isEditing: editMessage?.id == message.id"))
        #expect(!messageListTemplate.contains("private var selectTextAction: ((MessageSD) -> Void)?"))
        #expect(!messageListTemplate.contains("selectTextAction"))
        #expect(!messageListTemplate.contains("private var readAloudAction: ((MessageSD) -> Void)?"))
        #expect(!messageListTemplate.contains("readAloudAction"))
        #expect(!messageListTemplate.contains("isEditing: editMessage?.id == message.id,\n#if"))
        #expect(!messageListTemplate.contains("additionalActions: platformContextMenuActions(for: message)"))
        #expect(!messageListTemplate.contains("private func platformContextMenuActions(for message: MessageSD) -> [QuillMenuAction]"))
        #expect(!messageListTemplate.contains("QuillMenuAction.copyText(message.content)"))
        #expect(!messageListTemplate.contains("actions.append(.edit {"))
        #expect(!messageListTemplate.contains("actions.append(.unselect {"))
        #expect(!messageListTemplate.contains("Clipboard.shared.setString(message.content)"))
        #expect(!messageListTemplate.contains("QuillMenuAction(title: \"Copy\", systemImage: \"doc.on.doc\")"))
        #expect(!messageListTemplate.contains("private let quillMessageListBottomID"))
        #expect(!messageListTemplate.contains("ScrollViewReader"))
        #expect(!messageListTemplate.contains("DispatchQueue.main.async"))
        #expect(!messageListTemplate.contains(".onChange(of: messages.map(\\.id))"))

        let fullSourceCheck = try String(
            contentsOf: root.appendingPathComponent("scripts/generated-enchanted-full-source-check.sh"),
            encoding: .utf8
        )
        #expect(!fullSourceCheck.contains("import QuillUI"))
        #expect(fullSourceCheck.contains("import QuillShims"))
        #expect(!fullSourceCheck.contains("_ = QuillChatUnreachableBanner {"))
        #expect(!fullSourceCheck.contains("QuillDesktopChatConversationSidebar("))
        #expect(fullSourceCheck.contains("Settings()\n        }"))

        let unreachableEmptyFiles = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/empty-files.txt"),
            encoding: .utf8
        )
        #expect(unreachableEmptyFiles.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!unreachableEmptyFiles.contains("UI/Shared/Chat/Components/UnreachableAPIView.swift"))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/Shared/Chat/Components/UnreachableAPIView.swift").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/Shared/Chat/Components/UnreachableAPIView.swift.pl").path
        ))

        let conversationStoreRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/Stores/ConversationStore.swift.pl"),
            encoding: .utf8
        )
        #expect(conversationStoreRule.contains("if !currentMessageBuffer.isEmpty"))
        #expect(conversationStoreRule.contains("lastMesasge.content.append(currentMessageBuffer)"))
        #expect(conversationStoreRule.contains("var pendingMessages = conversation.messages.sorted"))
        #expect(conversationStoreRule.contains("pendingMessages.append(userMessage)"))
        #expect(conversationStoreRule.contains("pendingMessages.append(assistantMessage)"))
        #expect(conversationStoreRule.contains("self.messages = pendingMessages.sorted"))
        #expect(conversationStoreRule.contains("self.selectedConversation = conversation"))
        #expect(conversationStoreRule.contains("let currentUserRequestMessage = OKChatRequestData.Message"))
        #expect(conversationStoreRule.contains("!messageHistory.contains(where: { \\$0.role == .user && \\$0.content == userPrompt })"))
        #expect(conversationStoreRule.contains("messageHistory.append(currentUserRequestMessage)"))
        #expect(conversationStoreRule.contains("Task { try? await self.loadConversations() }"))
        #expect(!conversationStoreRule.contains("conversation.messages + [userMessage]"))

        let appStoreRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/Stores/AppStore.swift.pl"),
            encoding: .utf8
        )
        #expect(appStoreRule.contains("QUILLUI_ENCHANTED_FORCE_UNREACHABLE"))
        #expect(appStoreRule.contains("QUILLUI_ENCHANTED_PROFILE_MODE"))
        #expect(appStoreRule.contains("QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE"))
        #expect(appStoreRule.contains("QUILLUI_QUILL_CHAT_PROFILE_MODE"))
        #expect(appStoreRule.contains("startCheckingReachability(interval: pingInterval)"))

        let applicationEntryRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/Shared/ApplicationEntry.swift.pl"),
            encoding: .utf8
        )
        #expect(applicationEntryRule.contains("QUILLUI_ENCHANTED_PROFILE_MODE"))
        #expect(applicationEntryRule.contains("QUILLUI_QUILL_CHAT_PROFILE_MODE"))
        #expect(applicationEntryRule.contains("Task.detached"))
    }

    @Test("generic SwiftUI lowering widens positive macOS gates")
    func genericSwiftUILoweringWidensPositiveMacOSGates() throws {
        let root = try packageRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillSwiftUILoweringTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = directory.appendingPathComponent("App.swift")
        try """
        import SwiftUI

        @main
        @Observable
        final class AppModel {
            var title = "Quill"
            private var cachedTitle = ""
            static var sharedTitle = "Shared"
        }

        @MainActor
        struct DesktopRoot: View, Sendable {
            let action: (@MainActor () -> Void)?

            func schedule(action: (() -> Void)?) {
                Task { @MainActor in
                    action?()
                }
                Task { @MainActor [action] in
                    action?()
                }
            }

            var body: some View {
        #if os(macOS) && canImport(AppKit)
                Text("desktop")
        #elseif !os(macOS) && canImport(UIKit)
                TextField("URL", text: .constant(""))
                    .keyboardType(.URL)
                    .textContentType(.URL)
        #endif
            }
        }

        #if os(macOS) || os(Linux)
        let alreadyDesktop = true
        #endif

        #Preview {
            DesktopRoot(action: nil)
        }
        """.write(to: source, atomically: true, encoding: .utf8)

        let script = root.appendingPathComponent("scripts/lower-swiftui-source-for-linux.sh")
        for _ in 0..<2 {
            let result = try runScript(script, arguments: [directory.path])
            #expect(result.status == 0, Comment(rawValue: result.output))
        }

        let lowered = try String(contentsOf: source, encoding: .utf8)
        #expect(lowered.contains("import QuillShims"))
        #expect(lowered.components(separatedBy: "import QuillShims").count == 2)
        #expect(lowered.contains("#if (os(macOS) || os(Linux)) && canImport(AppKit)"))
        #expect(lowered.contains("#elseif !os(macOS) && canImport(UIKit)"))
        #expect(lowered.contains("#if os(macOS) || os(Linux)"))
        #expect(lowered.contains("let action: (() -> Void)?"))
        #expect(lowered.contains("""
        Task {
            action?()
        }
"""))
        #expect(lowered.contains("""
        Task { [action] in
            action?()
        }
"""))
        #expect(lowered.contains("final class AppModel: QuillObservableObject"))
        #expect(lowered.contains("@QuillPublished var title = \"Quill\""))
        #expect(lowered.contains("private var cachedTitle = \"\""))
        #expect(lowered.contains("static var sharedTitle = \"Shared\""))
        #expect(lowered.contains("struct DesktopRoot: View {"))
        #expect(lowered.contains(".keyboardType(KeyboardType.URL)"))
        #expect(lowered.contains(".textContentType(TextContentType.URL)"))
        #expect(!lowered.contains("@main"))
        #expect(!lowered.contains("@Observable"))
        #expect(!lowered.contains("@MainActor"))
        #expect(!lowered.contains("#Preview"))
    }

    @Test("SwiftOpenUI GTK patch keeps Enchanted fixes generic")
    func swiftOpenUIGTKPatchKeepsEnchantedFixesGeneric() throws {
        let root = try packageRoot()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillSwiftOpenUIPatchTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let renderer = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
        )
        let swiftOpenUIManifest = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Package.swift"
        )
        let descriptorTree = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4DescriptorTree.swift"
        )
        let backend = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4Backend.swift"
        )
        let viewHost = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKViewHost.swift"
        )
        let navigation = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKNavigation.swift"
        )
        let shim = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/Backend/GTK4/CGTK/shim.h"
        )
        let toolbar = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/SwiftOpenUI/Modifiers/ToolbarModifier.swift"
        )
        let layout = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/SwiftOpenUI/Layout/Layout.swift"
        )
        let symbols = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/SwiftOpenUISymbols/SFSymbolCompatibility.swift"
        )
        let scrollViewReader = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/SwiftOpenUI/Views/ScrollViewReader.swift"
        )
        let state = directory.appendingPathComponent(
            "checkouts/SwiftOpenUI/Sources/SwiftOpenUI/State/State.swift"
        )
        let issueReporter = directory.appendingPathComponent(
            "checkouts/xctest-dynamic-overlay/Sources/IssueReporting/IssueReporters/DefaultReporter.swift"
        )
        let sharedBinding = directory.appendingPathComponent(
            "checkouts/swift-sharing/Sources/Sharing/SharedBinding.swift"
        )
        for file in [swiftOpenUIManifest, renderer, descriptorTree, backend, viewHost, navigation, shim, toolbar, layout, symbols, scrollViewReader, state, issueReporter, sharedBinding] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        try """
        // swift-tools-version: 5.10

        import PackageDescription

        var targets: [Target] = [
            .systemLibrary(
                name: "CGTK",
                path: "Sources/Backend/GTK4/CGTK",
                pkgConfig: "gtk4",
                providers: [.apt(["libgtk-4-dev"])]
            ),
            .target(
                name: "CGTKBridge",
                dependencies: ["CGTK"],
                path: "Sources/Backend/GTK4/CGTKBridge"
            ),
            .target(
                name: "BackendGTK4",
                dependencies: ["SwiftOpenUI", "CGTK", "CGTKBridge", "SwiftOpenUISymbols"],
                path: "Sources/Backend/GTK4/Rendering",
                linkerSettings: [
                    .linkedLibrary("fontconfig"),
                ]
            ),
            .testTarget(
                name: "GTK4RenderTests",
                dependencies: ["SwiftOpenUI", "BackendGTK4", "CGTK", "CGTKBridge"],
                path: "Tests/BackendTests/GTK4Tests"
            ),
            .testTarget(
                name: "GTKLayoutParityTests",
                dependencies: ["SwiftOpenUI", "BackendGTK4", "CGTK", "CGTKBridge", "LayoutParityShared"],
                path: "Tests/LayoutParityTests/GTKComparison"
            ),
        ]
        """.write(to: swiftOpenUIManifest, atomically: true, encoding: .utf8)

        try """
        let gtkSwiftSpacerMarker = "gtk-swift-spacer"
        let gtkSwiftDividerMarker = "gtk-swift-divider"

        private func gtkPixelSize(_ value: Double) -> gint {
            return gint(value)
        }

        private func gtkVStackSpacing(_ spacing: Int) -> Int {
            return spacing
        }

        // MARK: - Rendering dispatch

        public func gtkRenderView<V: View>(_ view: V) -> OpaquePointer {
            let host = AnyViewHost()
            installState(view, host: host)
            if let multi = view as? MultiChildView {
                let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                for child in multi.children {
                    let widget = widgetFromOpaque(gtkRenderAnyView(child))
                    gtk_box_append(boxPointer(box), widget)
                }
                return opaqueFromWidget(box)
            }
            return gtkRenderView(view.body)
        }

        // MARK: - GeometryReader GTK extension

        private class GeometryReaderContext {
            let renderContent: (GeometryProxy) -> OpaquePointer
            let box: UnsafeMutablePointer<GtkWidget>

            init<Content: View>(content: @escaping (GeometryProxy) -> Content,
                                box: UnsafeMutablePointer<GtkWidget>) {
                self.box = box
                self.renderContent = { proxy in
                    gtkRenderView(content(proxy))
                }
            }
        }

        // MARK: - GTK rendering protocol

        extension Group: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                for child in gtkRenderChildren(content) {
                    gtk_box_append(boxPointer(box), widgetFromOpaque(child))
                }
                return opaqueFromWidget(box)
            }
        }

        extension ForEach: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                for item in data {
                    let childView = content(item)
                    let widget = widgetFromOpaque(gtkRenderView(childView))
                    gtk_box_append(boxPointer(box), widget)
                }
                return opaqueFromWidget(box)
            }
        }

        extension ScrollView: GTKRenderable, GTKDescribable {
            public func gtkCreateWidget() -> OpaquePointer {
                let scrolled = gtk_scrolled_window_new()!
                let scrolledOp = OpaquePointer(scrolled)
                let child = widgetFromOpaque(gtkRenderView(content))
                if axes.contains(.vertical) {
                    gtk_widget_set_vexpand(child, 0)
                }
                if axes.contains(.horizontal) {
                    gtk_widget_set_hexpand(child, 0)
                }
                gtk_scrolled_window_set_child(scrolledOp, child)
                gtk_widget_set_vexpand(scrolled, 1)
                gtk_widget_set_hexpand(scrolled, 1)
                return opaqueFromWidget(scrolled)
            }
        }

        extension Button: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let button: UnsafeMutablePointer<GtkWidget>

                if let textLabel = label as? Text {
                    button = gtk_button_new_with_label(textLabel.content)!
                } else {
                    button = gtk_button_new()!
                    let childWidget = widgetFromOpaque(gtkRenderView(label))
                    let btnPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
                    gtk_button_set_child(btnPtr, childWidget)
                    // Remove GTK default button border/padding so custom-styled
                    // labels (with .background/.frame) render cleanly.
                    applyCSSToWidget(button, properties: "border: none;")
                }

                gtk_widget_set_hexpand(button, 0)
                gtk_widget_set_halign(button, GTK_ALIGN_START)
                let boundAction = bindActionToCurrentEnvironment(action)
                let box = Unmanaged.passRetained(ClosureBox(boundAction)).toOpaque()
                g_signal_connect_data(
                    gpointer(button),
                    "clicked",
                    unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                        let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                        box.closure()
                    } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                    box,
                    { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                        Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                    },
                    GConnectFlags(rawValue: 0)
                )
                return opaqueFromWidget(button)
            }
        }

        extension TextField: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let entry = gtk_entry_new()!
                // Apply text field style from environment
                let textFieldStyleType = getCurrentEnvironment().textFieldStyle
                switch textFieldStyleType {
                case .plain:
                    applyCSSToWidget(entry, properties: "border: none; outline: none; box-shadow: none;")
                case .automatic, .roundedBorder:
                    break // default GTK entry styling
                }

                gtkApplyEnabledState(to: entry)
                return opaqueFromWidget(entry)
            }
        }

        extension SecureField: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let entry = gtk_password_entry_new()!

                gtkApplyEnabledState(to: entry)
                return opaqueFromWidget(entry)
            }
        }

        extension TextEditor: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let textView = gtk_text_view_new()!
                let scrolled = gtk_scrolled_window_new()!
                gtk_scrolled_window_set_child(OpaquePointer(scrolled), textView)
                gtk_widget_set_vexpand(scrolled, 1)
                gtk_widget_set_hexpand(scrolled, 1)

                gtkApplyEnabledState(to: textView)
                return opaqueFromWidget(scrolled)
            }
        }

        extension Toggle: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let toggleStyleType = getCurrentEnvironment().toggleStyle

                if toggleStyleType == .switch {
                    return gtkCreateSwitchWidget()
                }
                return gtkCreateCheckButtonWidget()
            }

            private func gtkCreateCheckButtonWidget() -> OpaquePointer {
                let check = label.isEmpty
                    ? gtk_check_button_new()!
                    : gtk_check_button_new_with_label(label)!
                gtkApplyEnabledState(to: check)
                return opaqueFromWidget(check)
            }

            private func gtkCreateSwitchWidget() -> OpaquePointer {
                let sw = gtk_swift_switch_new()!

                if label.isEmpty {
                    gtkApplyEnabledState(to: sw)
                    return opaqueFromWidget(sw)
                }

                let hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!
                gtkApplyEnabledState(to: hbox)
                return opaqueFromWidget(hbox)
            }
        }

        extension FrameView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let child = widgetFromOpaque(gtkRenderView(content))
                let childExpH = gtk_widget_get_hexpand(child) != 0
                let childExpV = gtk_widget_get_vexpand(child) != 0
                let wrapper = gtk_swift_fixed_new()!
                let naturalSize = gtkMeasureWidgetNaturalSize(child)
                let layout = computeFrameLayout(
                    childNaturalSize: naturalSize,
                    width: width,
                    height: height,
                    minWidth: minWidth,
                    minHeight: minHeight,
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                    alignment: alignment,
                    expandsToFillWidth: childExpH,
                    expandsToFillHeight: childExpV
                )
                gtk_widget_set_size_request(
                    wrapper,
                    gtkPixelSize(layout.containerSize.width),
                    gtkPixelSize(layout.containerSize.height)
                )
                if let xw = maxWidth, xw == .infinity {
                    gtk_widget_set_hexpand(wrapper, 1)
                }
                if let xh = maxHeight, xh == .infinity {
                    gtk_widget_set_vexpand(wrapper, 1)
                }
                return opaqueFromWidget(wrapper)
            }

            private func gtkFrameFlexibleAxis(
                child: UnsafeMutablePointer<GtkWidget>,
                childExpH: Bool
            ) -> OpaquePointer {
                let naturalSize = gtkMeasureWidgetNaturalSize(child)
                let layout = computeFrameLayout(
                    childNaturalSize: naturalSize,
                    width: width,
                    height: height,
                    minWidth: minWidth,
                    minHeight: minHeight,
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                    alignment: alignment,
                    expandsToFillWidth: childExpH,
                    expandsToFillHeight: gtk_widget_get_vexpand(child) != 0
                )
                gtk_widget_set_size_request(child, gtkPixelSize(layout.containerSize.width), -1)
                return opaqueFromWidget(child)
            }
        }

        private class SheetInfo {
            let anchor: UnsafeMutablePointer<GtkWidget>
            let render: () -> OpaquePointer
            let onDismiss: () -> Void
            /// Dismissal config from sheet content, used to present confirmation dialog on intercept.
            let dismissalConfig: DismissalConfirmationConfiguration?

            init(anchor: UnsafeMutablePointer<GtkWidget>,
                 render: @escaping () -> OpaquePointer,
                 onDismiss: @escaping () -> Void,
                 dismissalConfig: DismissalConfirmationConfiguration? = nil) {
                self.anchor = anchor
                self.render = render
                self.onDismiss = onDismiss
                self.dismissalConfig = dismissalConfig
            }
        }

        extension SheetModifierView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let widget = widgetFromOpaque(gtkRenderView(content))
                let anchor: UnsafeMutablePointer<GtkWidget>
                if let host = GTKViewHost.getCurrentRebuilding() {
                    anchor = host.container
                } else {
                    anchor = widget
                }
                let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

                if !isPresented.wrappedValue {
                    if let dialogPtr = g_object_get_data(gobject, "swift-sheet-window") {
                        let dialog = dialogPtr.assumingMemoryBound(to: GtkWindow.self)
                        g_object_set_data(gobject, "swift-sheet-active", nil)
                        g_object_set_data(gobject, "swift-sheet-window", nil)
                        gtk_window_destroy(dialog)
                        onDismiss?()
                    }
                    return opaqueFromWidget(widget)
                }

                // Guard against duplicate presentation on rebuild
                guard g_object_get_data(gobject, "swift-sheet-active") == nil else {
                    return opaqueFromWidget(widget)
                }
                g_object_set_data(gobject, "swift-sheet-active", gpointer(bitPattern: 1))
                g_object_ref(gpointer(anchor))

                let sheetView = sheetContent
                let binding = isPresented
                let userOnDismiss = onDismiss
                let dismissalConfig = gtkExtractDismissalConfig(from: sheetView)
                let info = Unmanaged.passRetained(SheetInfo(
                    anchor: anchor,
                    render: { gtkRenderView(sheetView) },
                    onDismiss: {
                        let obj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
                        guard g_object_get_data(obj, "swift-sheet-active") != nil else { return }
                        g_object_set_data(obj, "swift-sheet-active", nil)
                        g_object_set_data(obj, "swift-sheet-window", nil)
                        binding.wrappedValue = false
                        userOnDismiss?()
                    },
                    dismissalConfig: dismissalConfig
                )).toOpaque()

                g_idle_add({ userData -> gboolean in
                    let info = Unmanaged<SheetInfo>.fromOpaque(userData!).takeRetainedValue()
                    guard let root = gtk_widget_get_root(info.anchor) else {
                        info.onDismiss()
                        g_object_unref(gpointer(info.anchor))
                        return 0
                    }
                    let dialog = gtk_window_new()!
                    let dialogWin = windowPointer(dialog)
                    gtk_window_set_default_size(dialogWin, 400, 300)
                    gtk_window_set_transient_for(
                        dialogWin,
                        UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
                    )
                    let anchorObj = UnsafeMutableRawPointer(info.anchor).assumingMemoryBound(to: GObject.self)
                    g_object_set_data(anchorObj, "swift-sheet-window", gpointer(dialogWin))
                    gtk_window_present(dialogWin)
                    g_object_unref(gpointer(info.anchor))
                    return 0
                }, info)

                return opaqueFromWidget(widget)
            }
        }

        extension ItemSheetModifierView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let widget = widgetFromOpaque(gtkRenderView(content))
                let anchor: UnsafeMutablePointer<GtkWidget>
                if let host = GTKViewHost.getCurrentRebuilding() {
                    anchor = host.container
                } else {
                    anchor = widget
                }
                let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

                guard let currentItem = item.wrappedValue else {
                    if let dialogPtr = g_object_get_data(gobject, "swift-sheet-window") {
                        let dialog = dialogPtr.assumingMemoryBound(to: GtkWindow.self)
                        g_object_set_data(gobject, "swift-sheet-active", nil)
                        g_object_set_data(gobject, "swift-sheet-window", nil)
                        g_object_set_data(gobject, "swift-sheet-item-id", nil)
                        gtk_window_destroy(dialog)
                        onDismiss?()
                    }
                    return opaqueFromWidget(widget)
                }

                // Check if the item identity changed while a sheet is already active
                let currentIdHash = currentItem.id.hashValue
                if g_object_get_data(gobject, "swift-sheet-active") != nil {
                    let storedHash = Int(bitPattern: g_object_get_data(gobject, "swift-sheet-item-id"))
                    if storedHash == currentIdHash {
                        return opaqueFromWidget(widget)
                    }
                    if let dialogPtr = g_object_get_data(gobject, "swift-sheet-window") {
                        let dialog = dialogPtr.assumingMemoryBound(to: GtkWindow.self)
                        g_object_set_data(gobject, "swift-sheet-active", nil)
                        g_object_set_data(gobject, "swift-sheet-window", nil)
                        g_object_set_data(gobject, "swift-sheet-item-id", nil)
                        gtk_window_destroy(dialog)
                        onDismiss?()
                    }
                }
                g_object_set_data(gobject, "swift-sheet-active", gpointer(bitPattern: 1))
                g_object_set_data(gobject, "swift-sheet-item-id", gpointer(bitPattern: currentIdHash))
                g_object_ref(gpointer(anchor))

                let sheetBuilder = sheetContent
                let itemBinding = item
                let userOnDismiss = onDismiss
                let itemDismissalConfig = gtkExtractDismissalConfig(from: sheetBuilder(currentItem))
                let info = Unmanaged.passRetained(SheetInfo(
                    anchor: anchor,
                    render: { gtkRenderView(sheetBuilder(currentItem)) },
                    onDismiss: {
                        let obj = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
                        guard g_object_get_data(obj, "swift-sheet-active") != nil else { return }
                        g_object_set_data(obj, "swift-sheet-active", nil)
                        g_object_set_data(obj, "swift-sheet-window", nil)
                        g_object_set_data(obj, "swift-sheet-item-id", nil)
                        itemBinding.wrappedValue = nil
                        userOnDismiss?()
                    },
                    dismissalConfig: itemDismissalConfig
                )).toOpaque()

                g_idle_add({ userData -> gboolean in
                    let info = Unmanaged<SheetInfo>.fromOpaque(userData!).takeRetainedValue()
                    guard let root = gtk_widget_get_root(info.anchor) else {
                        info.onDismiss()
                        g_object_unref(gpointer(info.anchor))
                        return 0
                    }
                    let dialog = gtk_window_new()!
                    let dialogWin = windowPointer(dialog)
                    gtk_window_set_default_size(dialogWin, 400, 300)
                    gtk_window_set_transient_for(
                        dialogWin,
                        UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self)
                    )
                    let anchorObj = UnsafeMutableRawPointer(info.anchor).assumingMemoryBound(to: GObject.self)
                    g_object_set_data(anchorObj, "swift-sheet-window", gpointer(dialogWin))
                    gtk_window_present(dialogWin)
                    g_object_unref(gpointer(info.anchor))
                    return 0
                }, info)

                return opaqueFromWidget(widget)
            }
        }

        // MARK: - Help / tooltip modifier

        extension HelpView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let widget = widgetFromOpaque(gtkRenderView(content))
                gtk_widget_set_tooltip_text(widget, text)
                return opaqueFromWidget(widget)
            }
        }

        // MARK: - Clip Shape GTK extensions

        // MARK: - ScrollViewReader + ID GTK extensions

        extension IdView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let widget = widgetFromOpaque(gtkRenderView(content))
                registerViewID(id, element: widget)
                return opaqueFromWidget(widget)
            }
        }

        extension ScrollViewReader: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                var proxy = ScrollViewProxy()
                proxy.scrollToAction = { anyID, anchor in
                    guard let widget = lookupViewID(anyID) as? UnsafeMutablePointer<GtkWidget> else { return }
                    // Verify the widget is still alive before operating on it
                    guard gtk_swift_is_widget(widget) != 0 else { return }
                    // Find the enclosing GtkScrolledWindow and scroll to the widget.
                    var parent = gtk_widget_get_parent(widget)
                    while let p = parent {
                        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(p)))
                        if typeName == "GtkScrolledWindow" {
                            // Temporarily make the widget focusable so grab_focus
                            // triggers GTK4 auto-scroll. Restore after.
                            let wasFocusable = gtk_widget_get_focusable(widget)
                            gtk_widget_set_focusable(widget, 1)
                            gtk_widget_grab_focus(widget)
                            gtk_widget_set_focusable(widget, wasFocusable)
                            break
                        }
                        parent = gtk_widget_get_parent(p)
                    }
                }
                return gtkRenderView(content(proxy))
            }
        }

        // MARK: - Gesture GTK extensions

        extension TapGestureView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let widget = widgetFromOpaque(gtkRenderView(content))
                let gesture = gtk_gesture_click_new()!
                gtk_swift_add_gesture(widget, gesture)
                return opaqueFromWidget(widget)
            }
        }

        extension LongPressGestureView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let widget = widgetFromOpaque(gtkRenderView(content))
                let gesture = gtk_gesture_long_press_new()!
                gtk_swift_add_gesture(widget, gesture)
                return opaqueFromWidget(widget)
            }
        }

        // MARK: - OnAppear / OnDisappear GTK extensions

        extension OnAppearView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let widget = widgetFromOpaque(gtkRenderView(content))

                let isRebuild: Bool
                if let host = GTKViewHost.getCurrentRebuilding() {
                    isRebuild = gtk_widget_get_mapped(host.container) != 0
                } else {
                    isRebuild = false
                }

                if !isRebuild {
                    let boundAction = bindActionToCurrentEnvironment(action)
                    let box = Unmanaged.passRetained(ClosureBox(boundAction)).toOpaque()
                    g_signal_connect_data(
                        gpointer(widget),
                        "map",
                        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                            let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                            box.closure()
                        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                        box,
                        { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                            Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                        },
                        GConnectFlags(rawValue: 0)
                    )
                }

                return opaqueFromWidget(widget)
            }
        }

        // MARK: - Overlay GTK extension

        extension OverlayView: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                let container = gtk_overlay_new()!

                let baseWidget = widgetFromOpaque(gtkRenderView(content))
                gtk_overlay_set_child(OpaquePointer(container), baseWidget)

                let overlayWidget = widgetFromOpaque(gtkRenderView(overlay))
                let (hAlign, vAlign) = gtkAlignFromAlignment(alignment)
                let overlayWantsHExpand = gtk_widget_get_hexpand(overlayWidget) != 0
                let overlayWantsVExpand = gtk_widget_get_vexpand(overlayWidget) != 0
                gtk_widget_set_halign(overlayWidget, overlayWantsHExpand ? GTK_ALIGN_FILL : hAlign)
                gtk_widget_set_valign(overlayWidget, overlayWantsVExpand ? GTK_ALIGN_FILL : vAlign)
                gtk_overlay_add_overlay(OpaquePointer(container), overlayWidget)

                return opaqueFromWidget(container)
            }
        }

        extension Picker: GTKRenderable {
            public func gtkCreateWidget() -> OpaquePointer {
                gtkCreateDropdownWidget()
            }

            private func gtkCreateDropdownWidget() -> OpaquePointer {
                let cStrings: [UnsafeMutablePointer<CChar>?] = options.map { strdup($0) } + [nil]

                let dropdown = cStrings.withUnsafeBufferPointer { buf -> UnsafeMutablePointer<GtkWidget> in
                    buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { ptr in
                        gtk_drop_down_new_from_strings(ptr)!
                    }
                }

                for cStr in cStrings { cStr.map { free($0) } }

                let dropdownOp = OpaquePointer(dropdown)
                gtk_drop_down_set_selected(dropdownOp, guint(selected))
                if let onChanged = onChanged {
                    let box = Unmanaged.passRetained(IntClosureBox(onChanged)).toOpaque()
                    g_signal_connect_data(
                        gpointer(dropdown),
                        "notify::selected",
                        unsafeBitCast({ (widget: gpointer?, _: gpointer?, userData: gpointer?) in
                            let box = Unmanaged<IntClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                            let sel = Int(gtk_drop_down_get_selected(OpaquePointer(widget!)))
                            box.closure(sel)
                        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
                        box,
                        { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                            Unmanaged<IntClosureBox>.fromOpaque(userData!).release()
                        },
                        GConnectFlags(rawValue: 0)
                    )
                }
                return opaqueFromWidget(dropdown)
            }
        }

        final class LazyGridContext {
            init<Data, Content: View>(items: [Data], contentBuilder: @escaping (Data) -> Content,
                                      cellMinWidth: Int) {
                self.itemCount = items.count
                self.cellMinWidth = cellMinWidth
                self.renderItem = { index in
                    widgetFromOpaque(gtkRenderView(contentBuilder(items[index])))
                }
            }
        }

        private func gtkCreateLazyGridWidget<Data, Content: View>(
            items: [Data],
            contentBuilder: @escaping (Data) -> Content,
            gridItems: [GridItem],
            orientation: GtkOrientation
        ) -> OpaquePointer {
            let stringList = gtk_swift_string_list_new()!
            for i in 0..<items.count {
                gtk_swift_string_list_append(stringList, "\\(i)")
            }
            let configuration = computeLazyGridConfiguration(gridItems: gridItems)
            let cellMinWidth = configuration.adaptiveMinimum
            let context = LazyGridContext(items: items, contentBuilder: contentBuilder,
                                          cellMinWidth: cellMinWidth)
            return opaqueFromWidget(gridView)
        }
        """.write(to: renderer, atomically: true, encoding: .utf8)

        try """
        public enum GTK4DescriptorKind {
            case button
            case color
            case composite
            case text
        }

        public enum GTK4DescriptorPlanKind {
            case create
            case replace
            case reuse
            case update
        }

        public enum GTK4DescriptorUpdateIntent {
            case canvasContent
            case colorFill
            case paddingLayout
            case sliderValue
            case textContent
        }

        public struct GTK4DescriptorNode {
            public let kind: GTK4DescriptorKind
        }

        public struct GTK4DescriptorPlan {
            public let kind: GTK4DescriptorPlanKind
            public let newDescriptor: GTK4DescriptorNode
            public let updateIntent: GTK4DescriptorUpdateIntent
            public let children: [GTK4DescriptorPlan]
        }

        public func gtkCanApplyTextColorHostMutation(plan: GTK4DescriptorPlan) -> Bool {
            switch plan.kind {
            case .create, .replace:
                return false
            case .reuse:
                if plan.newDescriptor.kind == .composite && plan.children.isEmpty {
                    return false
                }
                return plan.children.allSatisfy(gtkCanApplyTextColorHostMutation)
            case .update:
                guard plan.updateIntent == .textContent || plan.updateIntent == .colorFill
                        || plan.updateIntent == .canvasContent
                        || plan.updateIntent == .sliderValue
                        || plan.updateIntent == .paddingLayout else {
                    return false
                }
                return plan.children.allSatisfy(gtkCanApplyTextColorHostMutation)
            }
        }
        """.write(to: descriptorTree, atomically: true, encoding: .utf8)

        try """
        import Foundation

        // MARK: - View Identity

        public struct IdView<Content: View, ID: Hashable>: View, PrimitiveView {
            public typealias Body = Never
            public let content: Content
            public let id: ID
        }

        public func registerViewID<ID: Hashable>(_ id: ID, element: Any) {}
        public func lookupViewID<ID: Hashable>(_ id: ID) -> Any? { nil }

        public struct ScrollViewProxy {
            public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
                scrollToAction?(AnyHashable(id), anchor)
            }

            public var scrollToAction: ((AnyHashable, UnitPoint?) -> Void)?
            public init() {}
        }
        """.write(to: scrollViewReader, atomically: true, encoding: .utf8)

        try """
        #include <gtk/gtk.h>
        #include <fontconfig/fontconfig.h>

        void
        gtk_swift_add_gesture(GtkWidget *widget, GtkGesture *gesture) {
            gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(gesture));
        }
        """.write(to: shim, atomically: true, encoding: .utf8)

        try """
        import Foundation

        public protocol AnyStateStorageProvider {
            var anyStorage: AnyStateStorage { get }
        }

        public protocol AnyStateStorage: AnyObject {
            var host: AnyViewHost? { get set }
            func restoreValue(from other: AnyStateStorage)
        }

        @propertyWrapper
        public struct State<Value>: AnyStateStorageProvider {
            public let storage: StateStorage<Value>

            public init(wrappedValue: Value) {
                storage = StateStorage(wrappedValue)
            }

            public var wrappedValue: Value {
                get { storage.value }
                nonmutating set { storage.setValue(newValue) }
            }

            public var projectedValue: Binding<Value> {
                Binding(get: { self.storage.value }, set: { self.storage.setValue($0) })
            }

            public var anyStorage: AnyStateStorage { storage }
        }

        public class StateStorage<Value>: AnyStateStorage, GenerationTracked {
            private let lock = NSLock()
            var _value: Value  // internal for restoreValue cross-storage access
            public weak var host: AnyViewHost?
            public private(set) var generation: UInt64 = 0

            public init(_ value: Value) {
                _value = value
            }

            public var value: Value {
                lock.lock()
                defer { lock.unlock() }
                recordDependencyRead(self)
                return _value
            }

            public func setValue(_ newValue: Value) {
                lock.lock()
                _value = newValue
                generation += 1
                lock.unlock()
                host?.scheduleRebuild()
            }

            public func restoreValue(from other: AnyStateStorage) {
                if let typed = other as? StateStorage<Value> {
                    _value = typed._value
                }
            }
        }
        """.write(to: state, atomically: true, encoding: .utf8)

        try """
        #if canImport(os)
          import os
        #endif

        extension IssueReporter where Self == _DefaultReporter {
          #if canImport(Darwin)
            @_transparent
          #endif
          public static var `default`: Self { Self() }
        }

        public struct _DefaultReporter {}
        """.write(to: issueReporter, atomically: true, encoding: .utf8)

        try """
        #if canImport(SwiftUI)
          import SwiftUI
        #endif

        #if canImport(SwiftUI) && !os(Linux)
          let swiftUIBindingBridge = true
        #endif
        """.write(to: sharedBinding, atomically: true, encoding: .utf8)

        try """
        import Foundation

        func gtkConfigureRootContentToFillWindow(_ contentWidget: UnsafeMutablePointer<GtkWidget>) {
            gtk_widget_set_hexpand(contentWidget, 1)
            gtk_widget_set_vexpand(contentWidget, 1)
        }

        extension WindowGroup {
            func gtkResolvedDefaultWindowSize() -> (width: Double, height: Double)? {
                switch windowSizing ?? .automatic {
                case .automatic:
                    return (
                        defaultWindowWidth ?? defaultAutomaticWindowWidth,
                        defaultWindowHeight ?? defaultAutomaticWindowHeight
                    )
                case .content:
                    return nil
                }
            }

            func gtkRender(winPtr: UnsafeMutablePointer<GtkWindow>, contentWidget: UnsafeMutablePointer<GtkWidget>) {
                if let defaultSize = gtkResolvedDefaultWindowSize() {
                    gtk_window_set_default_size(
                        winPtr,
                        gint(defaultSize.width),
                        gint(defaultSize.height)
                    )
                }

                gtkConfigureRootContentToFillWindow(contentWidget)

                gtk_window_set_child(winPtr, contentWidget)
                let winWidget = widgetPointer(winPtr)
                gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: contentWidget, windowID: Int(bitPattern: winPtr))
            }

            func gtkInstallDefaultMenu(menuModel: OpaquePointer, fileMenu: OpaquePointer) {
                gtk_swift_menu_append_submenu(menuModel, "File", fileMenu)
            }
        }
        """.write(to: backend, atomically: true, encoding: .utf8)

        try """
        final class GTKViewHost {
            let container: UnsafeMutablePointer<GtkWidget>
            let buildBody: () -> OpaquePointer
            private var observationDidFire = false
            var capturedEnvironment: EnvironmentValues

            init(buildBody: @escaping () -> OpaquePointer) {
                self.container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                self.buildBody = buildBody
                self.capturedEnvironment = getCurrentEnvironment()
            }

            func buildBodyWithTracking() -> OpaquePointer {
                if #available(macOS 14.0, iOS 17.0, *) {
                    var result: OpaquePointer!
                    withObservationTracking {
                        result = buildBody()
                    } onChange: { [weak self] in
                        _ = self
                    }
                    return result
                }

                let result = buildBody()
                return result
            }

            func rebuild() {
                g_object_ref(gpointer(container))
                defer { g_object_unref(gpointer(container)) }
                _ = buildBodyWithTracking()
            }
        }
        """.write(to: viewHost, atomically: true, encoding: .utf8)

        try """
        extension NavigationSplitView {
            private func gtkCreateTwoColumnWidget() -> OpaquePointer {
                let paned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL)!
                let sidebarW = gtkExtractColumnWidth(from: sidebar) ?? Double(sidebarWidth)
                let sidebarWidget = widgetFromOpaque(gtkRenderView(sidebar))
                let detailWidget = widgetFromOpaque(gtkRenderView(detail))
                gtk_swift_paned_set_position(paned, gint(sidebarW))
                if let provider = gtkExtractColumnWidthProvider(from: sidebar),
                   let minW = provider.columnMinWidth {
                    gtk_widget_set_size_request(sidebarWidget, gint(minW), -1)
                }
                return opaqueFromWidget(paned)
            }

            private func gtkCreateThreeColumnWidget() -> OpaquePointer {
                let outerPaned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL)!
                let innerPaned = gtk_paned_new(GTK_ORIENTATION_HORIZONTAL)!
                let sidebarWidget = widgetFromOpaque(gtkRenderView(sidebar))
                let contentWidget = widgetFromOpaque(gtkRenderView(content))
                let detailWidget = widgetFromOpaque(gtkRenderView(detail))
                let sidebarW = gtkExtractColumnWidth(from: sidebar) ?? Double(sidebarWidth)
                let contentW = gtkExtractColumnWidth(from: content) ?? 250.0
                gtk_swift_paned_set_position(innerPaned, gint(sidebarW))
                gtk_swift_paned_set_position(outerPaned, gint(sidebarW + contentW))
                return opaqueFromWidget(outerPaned)
            }
        }

        extension NavigationSplitViewColumnWidthView: GTKRenderable {}

        private func gtkInstallToolbar<V: View>(from view: V, on widget: UnsafeMutablePointer<GtkWidget>) {
            for item in toolbarItems {
                let itemWidget = widgetFromOpaque(gtkRenderAnyView(item.wrapped))
                switch item.placement {
                case .leading:
                    gtk_header_bar_pack_start(headerBarOp, itemWidget)
                case .primaryAction, .trailing:
                    gtk_header_bar_pack_end(headerBarOp, itemWidget)
                }
            }
        }
        """.write(to: navigation, atomically: true, encoding: .utf8)

        try """
        public struct AnyToolbarItem {
            public let placement: ToolbarItemPlacement
            public let wrapped: any View

            public init<Content: View>(_ item: ToolbarItem<Content>) {
                self.placement = item.placement
                self.wrapped = item.content
            }
        }

        /// Protocol for views that carry toolbar items.
        public protocol ToolbarProvider {}
        """.write(to: toolbar, atomically: true, encoding: .utf8)

        try """
        public func computeFrameLayout(
            childNaturalSize: ViewSize,
            width: Double? = nil,
            height: Double? = nil,
            minWidth: Double? = nil,
            minHeight: Double? = nil,
            maxWidth: Double? = nil,
            maxHeight: Double? = nil,
            alignment: Alignment = .center,
            expandsToFillWidth: Bool = false,
            expandsToFillHeight: Bool = false
        ) -> FrameLayoutResult {
            var containerWidth = childNaturalSize.width
            var containerHeight = childNaturalSize.height
            if let width { containerWidth = width }
            if let height { containerHeight = height }
            if let minWidth { containerWidth = max(containerWidth, minWidth) }
            if let minHeight { containerHeight = max(containerHeight, minHeight) }
            if let maxWidth, maxWidth != .infinity { containerWidth = min(containerWidth, maxWidth) }
            if let maxHeight, maxHeight != .infinity { containerHeight = min(containerHeight, maxHeight) }
            return FrameLayoutResult(containerSize: ViewSize(width: containerWidth, height: containerHeight), childPlacement: .zero)
        }
        """.write(to: layout, atomically: true, encoding: .utf8)

        try """
        let map = [
                "calendar":              "calendar_today",
                "pencil":                "edit",
                "plus.circle.fill":      "add_circle",
                "square.and.arrow.up":   "share",
                "square.and.pencil":     "edit",
                "tag.fill":              "label",
                "xmark.circle.fill":     "cancel",
        ]
        """.write(to: symbols, atomically: true, encoding: .utf8)

        let script = root.appendingPathComponent("scripts/patch-swiftopenui-gtk-css.sh")
        let result = try runScript(
            script,
            arguments: [directory.path],
            environment: [
                "QUILLUI_SWIFT_PACKAGE_PATH": root.path,
                "QUILLUI_SWIFTOPENUI_ROOT": directory.appendingPathComponent("checkouts/SwiftOpenUI").path,
                // Hermetic test: stub checkouts are pre-seeded above; there is no
                // real package to `swift package resolve`, so opt out of the
                // unconditional resolve the patcher does in the real build.
                "QUILLUI_SKIP_PACKAGE_RESOLVE": "1",
            ]
        )
        #expect(result.status == 0, Comment(rawValue: result.output))

        let patchScript = try String(contentsOf: script, encoding: .utf8)
        #expect(patchScript.contains("text.replace(\"remainingTicks: Int = 4\", \"remainingTicks: Int = 180\")"))
        #expect(patchScript.contains("SwiftOpenUI ScrollViewReader scroll-range upgrade shape was not recognized"))
        #expect(patchScript.contains("SwiftOpenUI ScrollViewReader bottom-anchor scroll shape was not recognized"))
        #expect(patchScript.contains("SwiftOpenUI ScrollViewReader axis-specific success shape was not recognized"))
        #expect(patchScript.contains("SwiftOpenUI ScrollViewReader scroll-view marker install shape was not recognized"))
        #expect(patchScript.contains("SwiftOpenUI ScrollViewReader fallback scroll return shape was not recognized"))
        #expect(patchScript.contains("SwiftOpenUI OnAppear lifecycle rebuild shape was not recognized"))
        #expect(patchScript.contains("SwiftOpenUI TextField changed-signal insert shape was not recognized"))
        #expect(patchScript.contains("SwiftOpenUI TextField idle binding helper insertion marker was not recognized"))
        #expect(patchScript.contains("private final class GTKTextBindingIdleUpdate"))
        #expect(patchScript.contains("includeValueWhenUnidentified: Bool = false"))
        #expect(patchScript.contains("gtkScheduleTextBindingUpdate(binding, value: newText)"))
        #expect(patchScript.contains("let changedBox = Unmanaged.passRetained(StringClosureBox"))
        #expect(patchScript.contains("gtk_editable_get_text(OpaquePointer(editable))"))

        let patchedSwiftOpenUIManifest = try String(contentsOf: swiftOpenUIManifest, encoding: .utf8)
        #expect(patchedSwiftOpenUIManifest.contains("import Foundation"))
        #expect(patchedSwiftOpenUIManifest.contains("func swiftOpenUIPkgConfigArguments("))
        #expect(patchedSwiftOpenUIManifest.contains("func swiftOpenUIPkgConfigSwiftImporterFlags("))
        #expect(patchedSwiftOpenUIManifest.contains("let swiftOpenUIGTKSwiftImporterFlags: [String] = swiftOpenUIPkgConfigSwiftImporterFlags(\"gtk4\")"))
        #expect(patchedSwiftOpenUIManifest.contains("let swiftOpenUIGTKLinkerFlags: [String] = swiftOpenUIPkgConfigLinkerFlags(\"gtk4\")"))
        #expect(patchedSwiftOpenUIManifest.contains(".unsafeFlags(swiftOpenUIGTKSwiftImporterFlags)"))
        #expect(patchedSwiftOpenUIManifest.contains(".unsafeFlags(swiftOpenUIGTKLinkerFlags)"))
        #expect(patchedSwiftOpenUIManifest.contains("pkgConfig: \"gtk4\""))

        let patchedRenderer = try String(contentsOf: renderer, encoding: .utf8)
        #expect(patchedRenderer.contains("init(views: [any View], cellMinWidth: Int)"))
        #expect(patchedRenderer.contains("let itemCount = expandedChildren?.count ?? items.count"))
        #expect(patchedRenderer.contains("configuration.maxColumns > 1 ? 160 : 0"))
        #expect(patchedRenderer.contains("gtkCreateStaticLazyGridWidget("))
        #expect(patchedRenderer.contains("views.count <= 64"))
        #expect(patchedRenderer.contains("gtk_swift_grid_attach("))
        #expect(patchedRenderer.contains("gint(index % columns)"))
        #expect(patchedRenderer.contains("gint(index / columns)"))
        #expect(patchedRenderer.contains("let staticGrid = gtkCreateStaticLazyGridWidget"))
        #expect(patchedRenderer.contains("for child in multi.children"))
        #expect(patchedRenderer.contains("gtkPropagateSingleChildLayoutMarkers("))
        #expect(patchedRenderer.contains("gtkHasLayoutMarker(child, key: gtkSwiftSpacerMarker)"))
        #expect(patchedRenderer.contains("gtkSetLayoutMarker(wrapper, key: gtkSwiftSpacerMarker)"))
        #expect(patchedRenderer.contains("var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []"))
        #expect(patchedRenderer.contains("renderedChildren.append(widget)"))
        #expect(patchedRenderer.contains("gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)"))
        #expect(patchedRenderer.contains("if needsHExpand { gtk_widget_set_hexpand(box, 1) }"))
        #expect(patchedRenderer.contains("if needsVExpand { gtk_widget_set_vexpand(box, 1) }"))
        #expect(patchedRenderer.contains("SwiftUI lays repeated vertical rows against the parent's"))
        #expect(patchedRenderer.contains("gtk_widget_set_hexpand(widget, 1)"))
        #expect(patchedRenderer.contains("gtk_widget_add_css_class(button, \"flat\")"))
        #expect(patchedRenderer.contains("background: transparent;"))
        #expect(patchedRenderer.contains("background-color: transparent;"))
        #expect(patchedRenderer.contains("background-image: none;"))
        #expect(patchedRenderer.contains("border-radius: 0;"))
        #expect(patchedRenderer.contains("box-shadow: none;"))
        #expect(patchedRenderer.contains("text-shadow: none;"))
        #expect(patchedRenderer.contains("SwiftUI lays vertical ScrollView content out in the viewport"))
        #expect(patchedRenderer.contains("gtk_widget_set_halign(child, GTK_ALIGN_FILL)"))
        #expect(patchedRenderer.contains("gtk_widget_set_valign(child, GTK_ALIGN_FILL)"))
        #expect(patchedRenderer.contains("var buttonWantsHExpand = false"))
        #expect(patchedRenderer.contains("if gtk_widget_get_hexpand(childWidget) != 0"))
        #expect(patchedRenderer.contains("gtk_widget_set_hexpand(button, buttonWantsHExpand ? 1 : 0)"))
        #expect(patchedRenderer.contains("gtk_widget_set_halign(button, buttonWantsHExpand ? GTK_ALIGN_FILL : GTK_ALIGN_START)"))
        #expect(patchedRenderer.contains("public var quill_gtk_text_field_paint_hook: ((OpaquePointer, Bool) -> OpaquePointer?)? = nil"))
        #expect(patchedRenderer.contains("public var quill_gtk_text_editor_paint_hook: ((OpaquePointer, OpaquePointer) -> OpaquePointer?)? = nil"))
        #expect(patchedRenderer.contains("public var quill_gtk_toggle_paint_hook: ((OpaquePointer, Bool, Bool, String) -> OpaquePointer?)? = nil"))
        #expect(patchedRenderer.contains("var useQuillPaintTextField = false"))
        #expect(patchedRenderer.contains("quill_gtk_text_field_paint_hook?("))
        #expect(patchedRenderer.contains("extension SecureField: GTKRenderable"))
        #expect(patchedRenderer.contains("quill_gtk_text_field_paint_hook?(OpaquePointer(entry), true)"))
        #expect(patchedRenderer.contains("quill_gtk_text_editor_paint_hook?("))
        #expect(patchedRenderer.contains("let check = label.isEmpty || quill_gtk_toggle_paint_hook != nil"))
        #expect(patchedRenderer.contains("quill_gtk_toggle_paint_hook?("))
        #expect(patchedRenderer.contains("false,\n            label"))
        #expect(patchedRenderer.contains("true,\n            label"))
        #expect(patchedRenderer.contains("if maxWidth != nil {"))
        #expect(patchedRenderer.contains("if maxHeight != nil {"))
        #expect(!patchedRenderer.contains("if let xw = maxWidth, xw != nil"))
        #expect(!patchedRenderer.contains("if let xh = maxHeight, xh != nil"))
        #expect(patchedRenderer.contains("expandsToFillWidth: childExpH || (width == nil && maxWidth != nil && maxWidth != .infinity)"))
        #expect(patchedRenderer.contains("expandsToFillHeight: childExpV || (height == nil && maxHeight != nil && maxHeight != .infinity)"))
        #expect(patchedRenderer.contains("expandsToFillHeight: gtk_widget_get_vexpand(child) != 0 || (height == nil && maxHeight != nil && maxHeight != .infinity)"))
        #expect(patchedRenderer.contains("let buttonActionBox = Unmanaged.passRetained(GTKButtonActionBox(boundAction)).toOpaque()"))
        #expect(patchedRenderer.contains("let context = Unmanaged.passRetained(GTKButtonIdleActionContext(box: box, source: source)).toOpaque()"))
        #expect(patchedRenderer.contains("private var gtkStateCache: [String: [AnyStateStorage]] = [:]"))
        #expect(patchedRenderer.contains("private var gtkStateTypeCounters: [String: [String: Int]] = [:]"))
        #expect(patchedRenderer.contains("private func gtkStateIdentityNamespace() -> String"))
        // Deferred renders (GeometryReader callbacks) have no rebuilding host;
        // the forced-namespace fallback keeps their subtree off the shared
        // never-reset "root" counter pool so @State survives geometry passes.
        #expect(patchedRenderer.contains("?? gtkForcedStateIdentityNamespace"))
        #expect(patchedRenderer.contains("private var gtkForcedStateIdentityNamespace: String?"))
        #expect(patchedRenderer.contains("func gtkClaimStateIdentityNamespace(_ kind: String) -> String"))
        #expect(patchedRenderer.contains("func gtkWithForcedStateIdentityNamespace<T>(_ namespace: String, _ body: () -> T) -> T"))
        #expect(patchedRenderer.contains("gtkClaimStateIdentityNamespace(\"GeometryReader\")"))
        #expect(patchedRenderer.contains("gtkWithForcedStateIdentityNamespace(stateNamespace) {"))
        #expect(patchedRenderer.contains("func gtkBeginStateIdentityPass()"))
        #expect(patchedRenderer.contains("gtkStateTypeCounters[gtkStateIdentityNamespace()] = [:]"))
        #expect(patchedRenderer.contains("return \"\\(namespace)::\\(typeName)#\\(index)\""))
        #expect(patchedRenderer.contains("host.stateIdentityNamespace = key"))
        // Stateless wrappers must also consume a key slot and namespace their
        // children; the namespace assignment precedes the provider guard.
        #expect(patchedRenderer.contains("host.stateIdentityNamespace = key\n    let mirror = Mirror(reflecting: view)"))
        #expect(patchedRenderer.contains("old.forwardMutations(to: provider.anyStorage)"))
        #expect(patchedRenderer.contains("gtkRestoreAndInstallState(view, host: host)"))
        #expect(patchedRenderer.contains("let transientRoot: gpointer?"))
        #expect(patchedRenderer.contains("let liveRoot = gtk_widget_get_root(info.anchor).map { gpointer($0) }"))
        #expect(patchedRenderer.contains("guard let root = liveRoot ?? info.transientRoot else"))
        #expect(patchedRenderer.contains("gtkSheetDataKey(\"active\", modifierType: type(of: self))"))
        #expect(patchedRenderer.contains("?? GTKViewHost.getCurrentRebuilding()?.rebuildPresentationRoot"))
        #expect(patchedRenderer.contains("private func gtkSheetDefaultWidth() -> gint"))
        #expect(patchedRenderer.contains("gtk_window_set_default_size(dialogWin, gtkSheetDefaultWidth(), gtkSheetDefaultHeight())"))
        #expect(patchedRenderer.contains("g_object_get_data(gobject, activeKey)"))
        #expect(patchedRenderer.contains("g_object_set_data(anchorObj, info.windowKey, gpointer(dialogWin))"))
        #expect(patchedRenderer.contains("g_object_set_data(gobject, itemIDKey, gpointer(bitPattern: currentIdHash))"))
        #expect(patchedRenderer.contains("private final class GTKScrollViewCrossAxisContext"))
        #expect(patchedRenderer.contains("gtkScrollViewCrossAxisTickCallback"))
        #expect(patchedRenderer.contains("gtkInstallScrollViewCrossAxisFill("))
        #expect(patchedRenderer.contains("gtk_widget_set_size_request(context.child, width, -1)"))
        #expect(patchedRenderer.contains("private final class GTKScrollToContext"))
        #expect(patchedRenderer.contains("let targetID: AnyHashable?"))
        #expect(patchedRenderer.contains("var remainingTotalTicks: Int"))
        #expect(patchedRenderer.contains("targetID: AnyHashable? = nil, anchor: UnitPoint?, remainingTicks: Int = 180, remainingTotalTicks: Int = 600"))
        #expect(patchedRenderer.contains("private var gtkScrollTargetRegistry"))
        #expect(patchedRenderer.contains("private func gtkRegisterScrollTarget(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>)"))
        #expect(patchedRenderer.contains("g_object_ref(gpointer(widget))"))
        #expect(patchedRenderer.contains("gtkScrollTargetRegistry.updateValue(widget, forKey: id)"))
        #expect(patchedRenderer.contains("g_object_unref(gpointer(previous))"))
        #expect(patchedRenderer.contains("private var gtkPendingScrollRequests"))
        #expect(patchedRenderer.contains("let gtkSwiftScrollViewMarker = \"gtk-swift-scroll-view\""))
        #expect(patchedRenderer.contains("let gtkSwiftVerticalScrollViewMarker = \"gtk-swift-vertical-scroll-view\""))
        #expect(patchedRenderer.contains("private func gtkMarkSwiftUIScrollView("))
        #expect(patchedRenderer.contains("private func gtkIsSwiftUIVerticalScrollView(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool"))
        #expect(patchedRenderer.contains("gtkMarkSwiftUIScrollView(scrolled, hasVerticalAxis: axes.contains(.vertical))"))
        #expect(patchedRenderer.contains("gtk_widget_translate_coordinates(target, scrolled"))
        #expect(patchedRenderer.contains("gtk_scrolled_window_get_vadjustment"))
        #expect(patchedRenderer.contains("let requiresVerticalAnchor = anchorPoint.y > 0.0"))
        #expect(patchedRenderer.contains("let isSwiftUIVerticalScrollView = gtkIsSwiftUIVerticalScrollView(scrolled)"))
        #expect(patchedRenderer.contains("let hasTargetCoordinates = gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY) != 0"))
        #expect(patchedRenderer.contains("if !hasTargetCoordinates && anchorPoint.y < 1.0"))
        #expect(patchedRenderer.contains("if hasTargetCoordinates, let hadjustment"))
        #expect(patchedRenderer.contains("var verticalApplied = false"))
        #expect(patchedRenderer.contains("var horizontalApplied = false"))
        #expect(patchedRenderer.contains("if upper - lower > pageSize + 1.0"))
        #expect(patchedRenderer.contains("if anchorPoint.y >= 1.0"))
        #expect(patchedRenderer.contains("gtk_adjustment_set_value(vadjustment, maxValue)"))
        #expect(patchedRenderer.contains("parent = gtk_widget_get_parent(scrolled)\n                continue"))
        #expect(patchedRenderer.contains("@discardableResult\nprivate func gtkApplyScrollTo"))
        #expect(patchedRenderer.contains("if verticalApplied && isSwiftUIVerticalScrollView { return true }"))
        #expect(patchedRenderer.contains("if verticalApplied { fallbackVerticalApplied = true }"))
        #expect(patchedRenderer.contains("return fallbackVerticalApplied"))
        #expect(patchedRenderer.contains("let target = context.targetID.flatMap { gtkScrollTargetRegistry[$0] } ?? context.target"))
        #expect(patchedRenderer.contains("let applied = gtkApplyScrollTo(target, anchor: context.anchor)"))
        #expect(patchedRenderer.contains("if applied {\n            context.remainingTicks -= 1\n        }"))
        #expect(patchedRenderer.contains("context.remainingTotalTicks -= 1"))
        #expect(patchedRenderer.contains("context.remainingTicks > 0 && context.remainingTotalTicks > 0"))
        #expect(patchedRenderer.contains("let request = GTKPendingScrollRequest(anchor: anchor)"))
        #expect(patchedRenderer.contains("gtkPendingScrollRequests[id] = request"))
        #expect(patchedRenderer.contains("guard let widget = gtkScrollTargetRegistry[id] else { return }"))
        #expect(patchedRenderer.contains("gtkResolvePendingScrollTo(id: id, widget: widget)"))
        #expect(patchedRenderer.contains("gtkScheduleScrollTo(id: id, widget, anchor: anchor)"))
        #expect(patchedRenderer.contains("gtkScheduleIdleScrollTo(id: AnyHashable? = nil, _ target"))
        #expect(patchedRenderer.contains("gtkScheduleIdleScrollTo(id: id, widget, anchor: request.anchor)"))
        #expect(patchedRenderer.contains("g_object_ref(gpointer(target))"))
        #expect(patchedRenderer.contains("g_timeout_add(16, { userData -> gboolean in"))
        #expect(patchedRenderer.contains("let unmanaged = Unmanaged<GTKScrollToContext>.fromOpaque(userData)"))
        #expect(patchedRenderer.contains("unmanaged.release()"))
        #expect(patchedRenderer.contains("defer { g_object_unref(gpointer(context.target)) }"))
        #expect(patchedRenderer.contains("g_idle_add({ userData -> gboolean in"))
        #expect(patchedRenderer.contains("gtkResolveOrQueueScrollTo(id: anyID, anchor: anchor)"))
        #expect(patchedRenderer.contains("let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!"))
        #expect(patchedRenderer.contains("gtk_box_append(boxPointer(wrapper), widget)"))
        #expect(patchedRenderer.contains("gtkPropagateSingleChildLayoutMarkers(from: [widget], to: wrapper)"))
        #expect(patchedRenderer.contains("gtkRegisterScrollTarget(id: AnyHashable(id), widget: wrapper)"))
        #expect(!patchedRenderer.contains("lookupViewID(id) as? UnsafeMutablePointer<GtkWidget>"))
        #expect(patchedRenderer.contains("private func gtkSheetPresentationMode() -> String"))
        #expect(patchedRenderer.contains("QUILLUI_BACKEND_SHEET_PRESENTATION"))
        #expect(patchedRenderer.contains("private func gtkShouldRenderSheetInRootOverlay() -> Bool"))
        #expect(patchedRenderer.contains("return mode.isEmpty || mode == \"root\" || mode == \"root-overlay\" || mode == \"window-overlay\""))
        #expect(patchedRenderer.contains("private func gtkShouldRenderSheetInWindow() -> Bool"))
        #expect(patchedRenderer.contains("QUILLUI_GTK_SHEET_PRESENTATION"))
        #expect(patchedRenderer.contains("return mode == \"overlay\" || mode == \"in-window\" || mode == \"inline\""))
        #expect(patchedRenderer.contains("private func gtkRemoveSheetRootOverlay("))
        #expect(patchedRenderer.contains("gtkRemoveSheetRootOverlay(\n                anchor: anchor,\n                overlayKey: overlayKey,\n                activeKey: activeKey"))
        // Presented panels live in a global registry keyed by the type-derived
        // activeKey: anchors are recreated per parent render, so per-anchor
        // g_object data would orphan the panel after the first rebuild.
        #expect(patchedRenderer.contains("private var gtkRootSheetPanels: [String: UnsafeMutablePointer<GtkWidget>] = [:]"))
        #expect(patchedRenderer.contains("private var gtkRootSheetItemIDs: [String: Int] = [:]"))
        #expect(patchedRenderer.contains("guard let panel = gtkRootSheetPanels.removeValue(forKey: activeKey) else"))
        #expect(patchedRenderer.contains("guard gtkRootSheetPanels[activeKey] == nil else"))
        #expect(patchedRenderer.components(separatedBy: "gtkRootSheetPanels[activeKey] = panel").count == 3)
        #expect(!patchedRenderer.contains("g_object_set_data(gobject, overlayKey, gpointer(panel))"))
        // Debounced entry->binding writes: typing must not schedule a rebuild
        // per keystroke, and button actions flush eagerly so Save reads the
        // typed text from the model.
        #expect(patchedRenderer.contains("func gtkFlushPendingTextBindingUpdate()"))
        #expect(patchedRenderer.contains("gtkPendingTextBindingSourceID = g_timeout_add(250"))
        #expect(patchedRenderer.contains("gtkFlushPendingTextBindingUpdate()\n    let now = Date().timeIntervalSinceReferenceDate"))
        // Sheet auto-focus retries until the panel is allocated; a one-shot
        // grab on an unallocated panel fails silently and keyboard focus falls
        // to the sheet's first button.
        #expect(patchedRenderer.contains("if gtk_widget_get_width(target.panel) <= 1"))
        #expect(patchedRenderer.contains("private func gtkScheduleSheetDismissal(_ action"))
        #expect(patchedRenderer.contains("gtkScheduleSheetDismissal {\n                        binding.wrappedValue = false"))
        #expect(patchedRenderer.contains("gtkScheduleSheetDismissal {\n                        itemBinding.wrappedValue = nil"))
        #expect(patchedRenderer.contains("let dismissAction: () -> Void"))
        #expect(patchedRenderer.contains("env.dismiss = DismissAction(handler: dismissAction)"))
        #expect(patchedRenderer.contains("swiftOpenUIWithPresentationDismissAction(dismissAction)"))
        #expect(!patchedRenderer.contains("gtkScheduleSheetDismissal {\n                        gtkRemoveSheetRootOverlay(anchor: anchor, overlayKey: overlayKey, activeKey: activeKey)"))
        #expect(!patchedRenderer.contains("gtkScheduleSheetDismissal {\n                        gtkRemoveSheetRootOverlay(\n                            anchor: anchor"))
        #expect(patchedRenderer.contains("private func gtkCreateSheetOverlayPanel("))
        #expect(patchedRenderer.contains("gtkInstallSheetPanelFocusBridge(on: panel)"))
        #expect(patchedRenderer.contains("gtkScheduleFirstSheetEditableFocus(in: panel)"))
        #expect(patchedRenderer.contains("gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY)"))
        #expect(patchedRenderer.contains("gtk_swift_widget_is_topmost_at_root_point(root, widget, rootX, rootY)"))
        #expect(patchedRenderer.contains("gtkScheduleSheetEditableFocus(editable)"))
        #expect(patchedRenderer.contains("gtkFocusSheetEditableWidget(editable)"))
        #expect(patchedRenderer.contains("private final class GTKSheetEditableFocusTarget"))
        #expect(patchedRenderer.contains("private final class GTKSheetPanelFocusTarget"))
        #expect(patchedRenderer.contains("gtk_editable_get_delegate(OpaquePointer(widget))"))
        #expect(patchedRenderer.contains("gtkScheduleSheetEditableFocus(delegateWidget)"))
        #expect(patchedRenderer.contains("gtkFindFirstSheetEditable(in: target.panel)"))
        #expect(patchedRenderer.contains("g_idle_add({ userData -> gboolean in"))
        #expect(patchedRenderer.contains("gtk_swift_root_grab_focus(widget)"))
        #expect(patchedRenderer.contains("gtk_swift_root_grab_focus(delegateWidget)"))
        #expect(patchedRenderer.contains("private func gtkCreateSheetOverlay("))
        #expect(patchedRenderer.contains("gtk_widget_set_halign(panel, GTK_ALIGN_CENTER)"))
        #expect(patchedRenderer.contains("gtkRootPresentationOverlay(for: root)"))
        #expect(patchedRenderer.contains("private var gtkRootSheetOverlayStack: [OpaquePointer] = []"))
        #expect(patchedRenderer.contains("private func gtkWithRootSheetOverlay<T>(_ rootOverlay: OpaquePointer, _ body: () -> T) -> T"))
        #expect(patchedRenderer.contains("private func gtkSheetRootOverlay(for anchor: UnsafeMutablePointer<GtkWidget>) -> OpaquePointer?"))
        #expect(patchedRenderer.contains("if let rootOverlay = gtkCurrentRootSheetOverlay()"))
        #expect(patchedRenderer.contains("if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(anchor))"))
        #expect(patchedRenderer.contains("var ancestor = gtk_widget_get_parent(anchor)"))
        #expect(patchedRenderer.contains("ancestor = gtk_widget_get_parent(current)"))
        #expect(patchedRenderer.contains("if let rootOverlay = gtkFallbackRootPresentationOverlay()"))
        #expect(patchedRenderer.components(separatedBy: "let rootOverlay = gtkSheetRootOverlay(for: anchor)").count == 3)
        #expect(patchedRenderer.components(separatedBy: "gtkWithRootSheetOverlay(rootOverlay) {").count == 3)
        #expect(patchedRenderer.components(separatedBy: "gtkStoreRootPresentationOverlay(rootOverlay, on: panel)").count == 3)
        #expect(patchedRenderer.components(separatedBy: "gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)").count == 3)
        #expect(patchedRenderer.contains("let stringList = gtk_swift_string_list_new()!"))
        #expect(patchedRenderer.contains("gtk_swift_drop_down_new(stringList)!"))
        #expect(!patchedRenderer.contains("gtk_drop_down_new_from_strings(ptr)!"))
        #expect(patchedRenderer.contains("guard options.indices.contains(newIndex), newIndex != clampedSelection else"))
        #expect(patchedRenderer.contains("private func gtkAttachRootSheetOverlay("))
        #expect(patchedRenderer.contains("let previousTop = gtk_widget_get_last_child(overlayWidget)"))
        #expect(patchedRenderer.contains("gtk_widget_insert_after(panel, overlayWidget, previousTop)"))
        #expect(patchedRenderer.components(separatedBy: "gtkAttachRootSheetOverlay(panel, to: rootOverlay)").count == 3)
        #expect(patchedRenderer.contains("sheet item root present activeKey="))
        #expect(patchedRenderer.contains("sheet item root unavailable activeKey="))
        #expect(patchedRenderer.contains("gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget)"))
        #expect(patchedRenderer.contains("if gtkShouldRenderSheetInWindow() {\n            let sheetBuilder = sheetContent"))
        #expect(!patchedRenderer.contains("if gtkShouldRenderSheetInWindow() || gtkShouldRenderSheetInRootOverlay()"))
        #expect(patchedRenderer.components(separatedBy: "gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetBuilder(currentItem)) }").count == 3)
        #expect(patchedRenderer.contains("remainingTicks: Int = 180"))
        #expect(!patchedRenderer.contains("remainingTicks: Int = 4"))
        #expect(patchedRenderer.contains("context.remainingTicks -= 1"))
        #expect(patchedRenderer.contains("gtkScheduleOnAppear(_ action"))
        #expect(patchedRenderer.contains("gtkScheduleOnAppear(boundAction, on: widget)"))
        #expect(!patchedRenderer.contains("gtk_widget_grab_focus(widget)"))
        #expect(patchedRenderer.contains("private func gtkDisableButtonChildTargeting"))
        #expect(patchedRenderer.contains("gtkDisableButtonChildTargeting(childWidget)"))
        #expect(patchedRenderer.contains("private final class GTKButtonActionBox"))
        #expect(patchedRenderer.contains("private func gtkScheduleButtonAction"))
        #expect(patchedRenderer.contains("gtk_swift_gesture_single_set_button(gesture, 1)"))
        #expect(patchedRenderer.contains("gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource(\"gesture\", widget: context.widget))"))
        #expect(patchedRenderer.contains("gtk_swift_add_capture_gesture(button, gesture)"))
        #expect(patchedRenderer.contains("let legacyController = gtk_swift_legacy_capture_controller()!"))
        #expect(patchedRenderer.contains("gtk_swift_event_is_primary_button_press(event)"))
        #expect(patchedRenderer.contains("gtkScheduleButtonAction(box, source: \"legacy\")"))
        #expect(patchedRenderer.contains("private final class GTKButtonRootEventContext"))
        #expect(patchedRenderer.contains("gtkInstallButtonRootEventFallback(context)"))
        #expect(patchedRenderer.contains("gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource(\"root-legacy@"))
        #expect(patchedRenderer.contains("private func gtkButtonDebugSource(_ source: String, widget: UnsafeMutablePointer<GtkWidget>) -> String"))
        #expect(patchedRenderer.contains("gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y)"))
        #expect(!patchedRenderer.contains("guard gtk_swift_widget_contains_root_point(root, context.widget"))
        #expect(patchedRenderer.contains("context.removeController()"))
        #expect(patchedRenderer.contains("gtk_swift_add_event_controller(button, legacyController)"))
        #expect(patchedRenderer.contains("gtk_swift_add_capture_gesture(widget, gesture)"))
        #expect(patchedRenderer.contains("private protocol GTKDecorativeOverlay"))
        #expect(patchedRenderer.contains("extension StrokedShape: GTKDecorativeOverlay"))
        #expect(patchedRenderer.contains("gtk_widget_set_can_target(overlayWidget, 0)"))

        let patchedDescriptorTree = try String(contentsOf: descriptorTree, encoding: .utf8)
        #expect(patchedDescriptorTree.contains("GTK Button action closures capture the view state storage"))
        #expect(patchedDescriptorTree.contains("if plan.newDescriptor.kind == .button"))
        // Props-bearing childless composites (TextField & co.) compare
        // meaningfully and stay narrow-eligible on reuse.
        #expect(patchedDescriptorTree.contains("if case .none = plan.newDescriptor.props {"))

        let patchedViewHost = try String(contentsOf: viewHost, encoding: .utf8)
        #expect(patchedViewHost.contains("gtkBeginStateIdentityPass()"))
        #expect(patchedViewHost.contains("gtkBeginStateIdentityPass()\n                result = buildBody()"))
        #expect(patchedViewHost.contains("var rebuildPresentationRoot: gpointer?"))
        #expect(patchedViewHost.contains("var stateIdentityNamespace = \"root\""))
        #expect(patchedViewHost.contains("let presentationRoot = gtk_widget_get_root(container).map { gpointer($0) }"))

        let patchedScrollViewReader = try String(contentsOf: scrollViewReader, encoding: .utf8)
        #expect(patchedScrollViewReader.contains("fileprivate protocol _SwiftOpenUIOptionalHashableID"))
        #expect(patchedScrollViewReader.contains("extension Optional: _SwiftOpenUIOptionalHashableID where Wrapped: Hashable"))
        #expect(patchedScrollViewReader.contains("fileprivate func swiftOpenUIHashableScrollID<ID: Hashable>(_ id: ID) -> AnyHashable?"))
        #expect(patchedScrollViewReader.contains("guard let resolvedID = swiftOpenUIHashableScrollID(id) else { return }"))
        #expect(patchedScrollViewReader.contains("scrollToAction?(resolvedID, anchor)"))
        #expect(!patchedScrollViewReader.contains("scrollToAction?(AnyHashable(id), anchor)"))

        let patchedShim = try String(contentsOf: shim, encoding: .utf8)
        #expect(patchedShim.contains("gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(gesture), GTK_PHASE_BUBBLE)"))
        #expect(patchedShim.contains("gtk_swift_flow_box_new(void)"))
        #expect(patchedShim.contains("gtk_swift_flow_box_configure(GtkWidget *flow, guint spacing)"))
        #expect(patchedShim.contains("gtk_swift_flow_box_insert(GtkWidget *flow, GtkWidget *child)"))
        #expect(patchedShim.contains("gtk_swift_add_capture_gesture(GtkWidget *widget, GtkGesture *gesture)"))
        #expect(patchedShim.contains("gtk_swift_root_grab_focus(GtkWidget *widget)"))
        #expect(patchedShim.contains("gtk_swift_drop_down_new(gpointer model)"))
        #expect(patchedShim.contains("gtk_drop_down_new(G_LIST_MODEL(model), NULL)"))
        #expect(patchedShim.contains("gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(gesture), GTK_PHASE_CAPTURE)"))
        #expect(patchedShim.contains("gtk_swift_legacy_capture_controller(void)"))
        #expect(patchedShim.contains("gtk_swift_add_event_controller(GtkWidget *widget, gpointer controller)"))
        #expect(patchedShim.contains("gtk_swift_remove_event_controller(GtkWidget *widget, gpointer controller)"))
        #expect(patchedShim.contains("gtk_swift_event_is_primary_button_press(gpointer event)"))
        #expect(patchedShim.contains("gtk_swift_event_get_position(gpointer event, double *x, double *y)"))
        #expect(patchedShim.contains("gtk_swift_widget_root_widget(GtkWidget *widget)"))
        #expect(patchedShim.contains("gtk_swift_widget_contains_root_point(GtkWidget *root, GtkWidget *widget, double x, double y)"))
        #expect(patchedShim.contains("gtk_swift_widget_is_topmost_at_root_point(GtkWidget *root, GtkWidget *widget, double x, double y)"))
        #expect(patchedShim.contains("GTK_PICK_NON_TARGETABLE"))
        #expect(patchedShim.contains("gtk_swift_widget_is_ancestor_or_self(picked, widget)"))
        #expect(patchedShim.contains("gdk_button_event_get_button(gdk_event) == GDK_BUTTON_PRIMARY"))
        #expect(patchedShim.contains("gtk_gesture_single_set_exclusive(GTK_GESTURE_SINGLE(gesture), FALSE)"))

        let patchedState = try String(contentsOf: state, encoding: .utf8)
        #expect(patchedState.contains("func forwardMutations(to other: AnyStateStorage)"))
        #expect(patchedState.contains("private var forwardedStorage: StateStorage<Value>?"))
        #expect(patchedState.contains("let forwarded = forwardedStorage"))
        #expect(patchedState.contains("forwarded.setValue(newValue)"))
        #expect(patchedState.contains("typed !== self"))
        #expect(patchedState.contains("wireObservableObjectStateValueIfNeeded"))

        let patchedIssueReporter = try String(contentsOf: issueReporter, encoding: .utf8)
        #expect(!patchedIssueReporter.contains("canImport(os)"))
        #expect(!patchedIssueReporter.contains("canImport(Darwin)"))
        #expect(patchedIssueReporter.contains("#if false"))

        let patchedSharedBinding = try String(contentsOf: sharedBinding, encoding: .utf8)
        #expect(!patchedSharedBinding.contains("canImport(SwiftUI)"))
        #expect(patchedSharedBinding.contains("#if false"))

        let patchedBackend = try String(contentsOf: backend, encoding: .utf8)
        #expect(patchedBackend.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH"))
        #expect(patchedBackend.contains("QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"))
        #expect(patchedBackend.contains("QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL"))
        #expect(patchedBackend.contains("QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL"))
        #expect(patchedBackend.contains("requestedWidth ?? defaultWindowWidth ?? defaultAutomaticWindowWidth"))
        #expect(patchedBackend.contains("gtk_widget_set_size_request(\n                contentWidget"))
        #expect(patchedBackend.contains("private let gtkRootPresentationOverlayKey"))
        #expect(patchedBackend.contains("func gtkCreateRootPresentationContainer("))
        #expect(patchedBackend.contains("gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: widgetPointer(winPtr))"))
        #expect(patchedBackend.contains("gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: contentWidget)"))
        #expect(patchedBackend.contains("func gtkStoreRootPresentationOverlay("))
        #expect(patchedBackend.contains("func gtkStoredRootPresentationOverlay(on widget: gpointer) -> OpaquePointer?"))
        #expect(patchedBackend.contains("g_object_set_data(gobject, gtkRootPresentationOverlayKey, UnsafeMutableRawPointer(rootOverlay))"))
        #expect(patchedBackend.contains("gtkStoredRootPresentationOverlay(on: root) ?? gtkRootPresentationOverlayFallback"))
        #expect(patchedBackend.contains("func gtkFallbackRootPresentationOverlay() -> OpaquePointer?"))
        #expect(patchedBackend.contains("func gtkRootPresentationOverlay(for root: gpointer) -> OpaquePointer?"))
        #expect(patchedBackend.contains("let rootContentWidget = gtkCreateRootPresentationContainer(winPtr: winPtr, contentWidget: contentWidget)"))
        #expect(patchedBackend.contains("gtk_window_set_child(winPtr, rootContentWidget)"))
        #expect(patchedBackend.contains("gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: rootContentWidget"))

        let patchedToolbar = try String(contentsOf: toolbar, encoding: .utf8)
        #expect(patchedToolbar.contains("public let renderedViews: [any View]"))
        // Body access hops via assumeIsolated since View.body went @MainActor
        // (#513); the MultiChildView fan-out happens on the hopped value.
        #expect(patchedToolbar.contains("MainActor.assumeIsolated { item.content.body }"))
        #expect(patchedToolbar.contains("body as? MultiChildView"))

        let patchedLayout = try String(contentsOf: layout, encoding: .utf8)
        #expect(patchedLayout.contains("expandsToFillWidth && width == nil ? maxWidth"))
        #expect(patchedLayout.contains("expandsToFillHeight && height == nil ? maxHeight"))

        let patchedNavigation = try String(contentsOf: navigation, encoding: .utf8)
        #expect(patchedNavigation.contains("gtkBackendEnvironmentValue(_ canonical"))
        #expect(patchedNavigation.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT"))
        #expect(patchedNavigation.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH"))
        #expect(patchedNavigation.contains("QUILLUI_BACKEND_LAYOUT_DEBUG"))
        #expect(patchedNavigation.contains("gtkRenderToolbarItemWidgets(_ item: AnyToolbarItem)"))
        #expect(patchedNavigation.contains("gtkRequestedDefaultWindowHeight()"))
        #expect(patchedNavigation.contains("max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))"))
        #expect(patchedNavigation.contains("width * 0.27"))
        #expect(patchedNavigation.contains("gtkProportionalSidebarMapCallback"))
        #expect(patchedNavigation.contains("gtkProportionalSidebarTickCallback"))
        #expect(patchedNavigation.contains("gtkCreateTwoColumnSplitBox("))
        #expect(patchedNavigation.contains("gtkConfigureFixedSplitColumn(sidebarWidget, width: sidebarWidth)"))
        #expect(patchedNavigation.contains("gtkConfigureFillingSplitColumn(detailWidget)"))
        #expect(patchedNavigation.contains("gtkFixedSplitSidebarTickCallback"))
        #expect(patchedNavigation.contains("gtkInstallProportionalFixedSidebar(on: splitBox, sidebarWidget: sidebarWidget)"))
        #expect(patchedNavigation.contains("gtkApplyFixedSplitVisibility(visibility.wrappedValue"))
        #expect(patchedNavigation.contains("gtk_widget_set_margin_start(trailingCluster, 620)"))
        #expect(patchedNavigation.contains("gtkWrapWithToolbarRow(widgetFromOpaque(gtkRenderView(detail)), toolbarSource: detail)"))
        #expect(patchedNavigation.contains("let sidebarContentWidget = widgetFromOpaque(gtkRenderView(sidebar))"))
        #expect(patchedNavigation.contains("gtk_box_append(boxPointer(sidebarWidget), sidebarContentWidget)"))
        #expect(patchedNavigation.contains("gtk_widget_set_hexpand(widget, 0)"))
        #expect(patchedNavigation.contains("gtk_box_append(boxPointer(splitBox), gtkCreateSplitDivider())"))
        #expect(patchedNavigation.contains("background: #e8e9e6;"))
        #expect(patchedNavigation.contains("gtk_widget_set_vexpand(widget, 1)"))
        #expect(patchedNavigation.contains("gtk_widget_set_size_request(widget, gint(width), gtkRequestedDefaultWindowHeight())"))
        #expect(patchedNavigation.contains("let resolvedSidebarW = max(sidebarMinW, sidebarW)"))
        #expect(!patchedNavigation.contains("ProcessInfo.processInfo.environment[\"QUILLUI_GTK_LAYOUT_DEBUG\"] == \"1\""))
        #expect(!patchedNavigation.contains("gtkInstallToolbar(from: detail, on: paned)"))

        let patchedSymbols = try String(contentsOf: symbols, encoding: .utf8)
        let expectedGTKSymbols = [
            "\"arrow.clockwise\"",
            "\"arrow.forward.circle.fill\"",
            "\"checkmark.seal.fill\"",
            "\"chevron.down\"",
            "\"curlybraces\"",
            "\"doc.on.doc\"",
            "\"doc.text\"",
            "\"ellipsis.circle\"",
            "\"folder\"",
            "\"folder.badge.plus\"",
            "\"folder.fill\"",
            "\"gearshape\"",
            "\"gearshape.fill\"",
            "\"info.circle\"",
            "\"keyboard.fill\"",
            "\"lock.shield\"",
            "\"paperclip\"",
            "\"paperplane.fill\"",
            "\"pause.fill\"",
            "\"play.fill\"",
            "\"questionmark.circle\"",
            "\"shield.lefthalf.filled\"",
            "\"square.fill\"",
            "\"textformat.abc\"",
            "\"trash\"",
            "\"waveform\"",
            "\"xmark\"",
        ]
        for symbol in expectedGTKSymbols {
            #expect(patchedSymbols.contains(symbol), Comment(rawValue: symbol))
        }
        let patchedSymbolPairs = patchedSymbols.split(separator: "\n").compactMap { line -> (String, String)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let quotedParts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
            guard quotedParts.count >= 4 else { return nil }
            return (String(quotedParts[1]), String(quotedParts[3]))
        }
        var patchedSymbolValues = [String: String]()
        for (key, value) in patchedSymbolPairs {
            #expect(patchedSymbolValues[key] == nil, Comment(rawValue: key))
            patchedSymbolValues[key] = value
        }
        #expect(patchedSymbolValues["xmark"] == "close")
        #expect(patchedSymbolValues["curlybraces"] == "code")
        #expect(patchedSymbolValues["doc.text"] == "description")
        #expect(patchedSymbolValues["pause.fill"] == "pause")
        #expect(patchedSymbolValues["play.fill"] == "play_arrow")
    }

    @Test("vendored SwiftOpenUI restores GTK input focus by stable identity before DFS fallback")
    func vendoredSwiftOpenUIRestoresGTKInputFocusByStableIdentity() throws {
        let root = try packageRoot()
        let viewHost = root
            .appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKViewHost.swift")
        let source = try String(contentsOf: viewHost, encoding: .utf8)

        #expect(source.contains("let descriptorIdentity: GTK4DescriptorIdentity?"))
        #expect(source.contains("let stableFocusKey: String?"))
        #expect(source.contains("private let focusIdentityKey = \"gtk-swift-focus-identity\""))
        #expect(source.contains("gtkTagFocusableInputIdentities("))
        #expect(source.contains("stableFocusKey(from: node.descriptor)"))
        #expect(source.contains("target = findUniqueEditable(in: widget, stableFocusKey: stableFocusKey)"))
        #expect(source.contains("target = findEditable(in: widget, descriptorIdentity: descriptorIdentity)"))
        #expect(source.contains("target = findNthEditable(in: widget, targetIndex: info.editableIndex"))

        let stableKeyIndex = source.range(
            of: "target = findUniqueEditable(in: widget, stableFocusKey: stableFocusKey)"
        )?.lowerBound
        let descriptorIndex = source.range(
            of: "target = findEditable(in: widget, descriptorIdentity: descriptorIdentity)"
        )?.lowerBound
        let fallbackIndex = source.range(
            of: "target = findNthEditable(in: widget, targetIndex: info.editableIndex"
        )?.lowerBound

        #expect(stableKeyIndex != nil)
        #expect(descriptorIndex != nil)
        #expect(fallbackIndex != nil)
        if let stableKeyIndex, let descriptorIndex, let fallbackIndex {
            #expect(stableKeyIndex < descriptorIndex)
            #expect(descriptorIndex < fallbackIndex)
        }
    }

    @Test("vendored SwiftOpenUI starts GTK lifecycle modifiers after map")
    func vendoredSwiftOpenUIStartsGTKLifecycleAfterMap() throws {
        let root = try packageRoot()
        let viewHost = root
            .appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKViewHost.swift")
        let descriptorTree = root
            .appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4DescriptorTree.swift")
        let renderer = root
            .appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let viewHostSource = try String(contentsOf: viewHost, encoding: .utf8)
        let descriptorTreeSource = try String(contentsOf: descriptorTree, encoding: .utf8)
        let rendererSource = try String(contentsOf: renderer, encoding: .utf8)

        #expect(viewHostSource.contains("private var taskLifecycleSuspended = true"))
        #expect(viewHostSource.contains("private var onAppearPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4OnAppearPayload]"))
        #expect(viewHostSource.contains("private var appearedOnAppearIdentities: Set<GTK4DescriptorIdentity>"))
        #expect(viewHostSource.contains("\"realize\""))
        #expect(viewHostSource.contains("host.resumeTasksAfterAppear()"))
        #expect(viewHostSource.contains("private func resumeTasksIfAlreadyMapped()"))
        #expect(viewHostSource.contains("guard gtk_widget_get_mapped(container) != 0 else { return }"))
        #expect(viewHostSource.contains("if !taskLifecycleSuspended {"))
        #expect(viewHostSource.contains("appearedOnAppearIdentities = appearedOnAppearIdentities.intersection(liveIdentities)"))
        #expect(viewHostSource.contains("for (identity, payload) in taskPayloadsByIdentity where activeTasksByIdentity[identity] == nil"))
        #expect(descriptorTreeSource.contains("case onAppear"))
        #expect(descriptorTreeSource.contains("case .onAppear:      return .none"))
        #expect(rendererSource.contains("extension TaskView: GTKRenderable, GTKDescribable"))
        #expect(rendererSource.contains("extension OnAppearView: GTKRenderable, GTKDescribable"))
        #expect(rendererSource.contains("gtkAttachStandaloneTaskLifecycle("))
        #expect(rendererSource.contains("gtkCollectTaskPayload("))
        #expect(rendererSource.contains("GTK4TaskPayload("))
        #expect(rendererSource.contains("gtkCollectOnAppearPayload("))
        #expect(rendererSource.contains("action: bindTaskActionToCurrentEnvironment(action)"))
        #expect(rendererSource.contains("if GTKViewHost.getCurrentRebuilding() == nil {\n            gtkAttachStandaloneTaskLifecycle("))
        #expect(rendererSource.contains("let boundAction = bindActionToCurrentEnvironment(action)"))
        #expect(rendererSource.contains("} else {\n            gtkScheduleOnAppear(boundAction, on: widget)\n        }"))
    }

    private func runScript(
        _ script: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let pipe = Pipe()
        let output = ProcessOutputCollector()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            output.append(handle.availableData)
        }
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        output.append(pipe.fileHandleForReading.readDataToEndOfFile())

        return (process.terminationStatus, output.string())
    }

    private func packageRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let script = directory.appendingPathComponent("scripts/lower-swiftdata-for-quilldata.sh")
            if FileManager.default.fileExists(atPath: script.path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw SourceLoweringTestError.packageRootNotFound
    }

}

private enum SourceLoweringTestError: Error {
    case packageRootNotFound
}

private final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        let output = String(data: data, encoding: .utf8) ?? ""
        lock.unlock()
        return output
    }
}
