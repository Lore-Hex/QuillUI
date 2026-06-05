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
        #expect(!lowererWrapper.contains("--package-path \"$ROOT_DIR\""))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, source.path, output.path]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "QUILLUI_SOURCE_LOWER_PACKAGE_DIR": directory
                    .appendingPathComponent("ToolPackage", isDirectory: true).path,
                "QUILLUI_SOURCE_LOWER_SCRATCH_PATH": directory
                    .appendingPathComponent("ToolScratch", isDirectory: true).path,
            ]
        ) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, Comment(rawValue: log))

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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            script.path,
            output.path,
            "LanguageModelSD:name:id:String",
            "ConversationSD:id"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, Comment(rawValue: log))

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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [
                script.path,
                source.path,
                "AppKit",
                "NeedsImport.swift",
                "AlreadyImported.swift",
                "NoImport.swift",
                "MissingOptional.swift"
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()

            let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            #expect(process.terminationStatus == 0, Comment(rawValue: log))
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, templates.path, output.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, Comment(rawValue: log))

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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, source.path, rules.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, Comment(rawValue: log))

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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, source.path, list.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, Comment(rawValue: log))

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

        let failing = try runScript(script, arguments: ["--profile", "enchanted-full-source", "--max-shell-lines", "1"])
        #expect(failing.status != 0, Comment(rawValue: failing.output))
        #expect(failing.output.contains("profile budget failed"))
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
        #expect(manifest.contains(".target(name: \"UIKit\", dependencies: [\"QuillFoundation\", \"QuillUIKit\", \"QuillKit\"], path: \"Sources/UIKitShim\")"))
        #expect(manifest.contains(".target(\n        name: \"QuillUIKit\",\n        dependencies: [\"QuillFoundation\"],\n        path: \"Sources/QuillUIKit\"\n    )"))
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
        #expect(verifier.contains("Mac-reference sidebar region rendered no content"))
        #expect(verifier.contains("Mac-reference window controls were not detected"))
        #expect(verifier.contains("Mac-reference alert is too short"))
        #expect(verifier.contains("Quill Chat Mac-reference landmarks"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_composer_typed"))
        #expect(verifier.contains("Mac-reference typed composer text was not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_settings_panel"))
        #expect(verifier.contains("Mac-reference typed settings endpoint was not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_completions_panel"))
        #expect(verifier.contains("Mac-reference completions list dividers were not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_history_selection"))
        #expect(verifier.contains("Mac-reference selected history marker was not detected"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-transcript-selection"))
        #expect(verifier.contains("Mac-reference selected transcript assistant message was not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_markdown_transcript_selection"))
        #expect(verifier.contains("Mac-reference markdown transcript code panel was not detected"))
        #expect(verifier.contains("Mac-reference markdown transcript table panel was not detected"))
        #expect(verifier.contains("Mac-reference markdown transcript table dividers were not detected"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-markdown-transcript-selection"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_long_transcript_selection"))
        #expect(verifier.contains("Mac-reference long transcript did not scroll to the dense bottom marker"))
        #expect(verifier.contains("quill-chat-linux-mac-reference-long-transcript-selection"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_prompt_send"))
        #expect(verifier.contains("Mac-reference prompt-send message content was not detected"))
        #expect(verifier.contains("validate_quill_chat_mac_reference_composer_send"))
        #expect(verifier.contains("Mac-reference composer-send message content was not detected"))
        #expect(verifier.contains("validate_quill_chat_functional_transcript"))
        #expect(verifier.contains("Functional transcript assistant reply was not detected"))
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
        #expect(interactionScript.contains("settings-endpoint-typed"))
        #expect(interactionScript.contains("click_x=\"${QUILLUI_BACKEND_CLICK_X:-52}\""))
        #expect(interactionScript.contains("click_y=\"${QUILLUI_BACKEND_CLICK_Y:-1366}\""))
        #expect(interactionScript.contains("settings_x=\"${QUILLUI_BACKEND_SETTINGS_CLICK_X:-52}\""))
        #expect(interactionScript.contains("settings_y=\"${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-1366}\""))
        #expect(interactionScript.contains("window_x + 52"))
        #expect(interactionScript.contains("window_height - 14"))
        #expect(interactionScript.contains("completions-panel"))
        #expect(interactionScript.contains("click_x=\"${QUILLUI_BACKEND_CLICK_X:-90}\""))
        #expect(interactionScript.contains("click_y=\"${QUILLUI_BACKEND_CLICK_Y:-1244}\""))
        #expect(interactionScript.contains("window_x + 90"))
        #expect(interactionScript.contains("window_height - 136"))
        #expect(interactionScript.contains("history-selection"))
        #expect(interactionScript.contains("transcript-selection"))
        #expect(interactionScript.contains("markdown-transcript-selection"))
        #expect(interactionScript.contains("long-transcript-selection"))
        #expect(interactionScript.contains("prompt-send"))
        #expect(interactionScript.contains("composer-send"))
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
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-completions-panel"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-history-selection"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-transcript-selection"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-markdown-transcript-selection"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-long-transcript-selection"))
        #expect(!smokeLib.contains("quill-chat-linux-mac-reference-prompt-send"))
        #expect(backendProducts.contains("quillui_backend_quill_chat_interaction_verify_product()"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-composer-typed"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-settings-panel"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-settings-endpoint-typed"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-completions-panel"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-history-selection"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-transcript-selection"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-markdown-transcript-selection"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-long-transcript-selection"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-prompt-send"))
        #expect(backendProducts.contains("quill-chat-linux-mac-reference-composer-send"))
        #expect(backendProducts.contains("*:composer-send)"))

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
        #expect(functionalScript.contains("QUILLDATA_HOME=$RUN_HOME"))
        #expect(functionalScript.contains("mock Ollama did not start"))
        #expect(functionalScript.contains("quillui_functional_xdotool()"))
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

        let emptyConversationRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/Shared/Chat/Components/EmptyConversaitonView.swift.pl"),
            encoding: .utf8
        )
        #expect(emptyConversationRule.contains("Text(\"Quill\")"))
        #expect(emptyConversationRule.contains("brandTitle: \"Quill\""))

        let sidebarTemplate = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/Shared/Sidebar/SidebarView.swift"),
            encoding: .utf8
        )
        #expect(sidebarTemplate.contains("ConversationHistoryList("))
        #expect(sidebarTemplate.contains(".padding(.top, 88)"))
        #expect(!sidebarTemplate.contains("Text(\"New chat\")"))
        #expect(!sidebarTemplate.contains("Color(red: 0.259, green: 0.522, blue: 0.957)"))

        let historyTemplate = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/templates/UI/Shared/Sidebar/Components/ConversationHistoryListView.swift"),
            encoding: .utf8
        )
        #expect(historyTemplate.contains("struct ConversationGroup: Hashable"))
        #expect(historyTemplate.contains("conversationGroup.date.daysAgoString()"))
        #expect(historyTemplate.contains("Circle()"))
        #expect(historyTemplate.contains("if selectedConversation == dailyConversation"))
        #expect(!historyTemplate.contains(".showIf("))
        #expect(historyTemplate.contains(".frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)"))
        #expect(historyTemplate.contains(".contentShape(Rectangle())"))
        #expect(historyTemplate.contains(".onTapGesture { onTap(dailyConversation) }"))
        #expect(!historyTemplate.contains("QuillConversationHistoryList("))

        let unreachableRule = try String(
            contentsOf: root.appendingPathComponent("scripts/profiles/enchanted-full-source/rewrite-rules/UI/Shared/Chat/Components/UnreachableAPIView.swift.pl"),
            encoding: .utf8
        )
        #expect(unreachableRule.contains("Quill is unreachable"))
        #expect(unreachableRule.contains("update your Quill API endpoint"))

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

            var body: some View {
        #if os(macOS) && canImport(AppKit)
                Text("desktop")
        #elseif !os(macOS) && canImport(UIKit)
                Text("touch")
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
        #expect(lowered.contains("#if (os(macOS) || os(Linux)) && canImport(AppKit)"))
        #expect(lowered.contains("#elseif !os(macOS) && canImport(UIKit)"))
        #expect(lowered.contains("#if os(macOS) || os(Linux)"))
        #expect(lowered.contains("let action: (() -> Void)?"))
        #expect(lowered.contains("final class AppModel: QuillObservableObject"))
        #expect(lowered.contains("@QuillPublished var title = \"Quill\""))
        #expect(lowered.contains("private var cachedTitle = \"\""))
        #expect(lowered.contains("static var sharedTitle = \"Shared\""))
        #expect(lowered.contains("struct DesktopRoot: View {"))
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
                applyCSSToWidget(entry, properties: "border: none; outline: none; box-shadow: none;")
                return opaqueFromWidget(entry)
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

        let patchedSwiftOpenUIManifest = try String(contentsOf: swiftOpenUIManifest, encoding: .utf8)
        #expect(patchedSwiftOpenUIManifest.contains("import Foundation"))
        #expect(patchedSwiftOpenUIManifest.contains("func swiftOpenUIPkgConfigArguments("))
        #expect(patchedSwiftOpenUIManifest.contains("func swiftOpenUIPkgConfigSwiftImporterFlags("))
        #expect(patchedSwiftOpenUIManifest.contains("let swiftOpenUIGTKSwiftImporterFlags: [String] = swiftOpenUIPkgConfigSwiftImporterFlags(\"gtk4\")"))
        #expect(patchedSwiftOpenUIManifest.contains("let swiftOpenUIGTKLinkerFlags: [String] = swiftOpenUIPkgConfigLinkerFlags(\"gtk4\")"))
        #expect(patchedSwiftOpenUIManifest.contains(".unsafeFlags(swiftOpenUIGTKSwiftImporterFlags)"))
        #expect(patchedSwiftOpenUIManifest.contains(".unsafeFlags(swiftOpenUIGTKLinkerFlags)"))
        #expect(!patchedSwiftOpenUIManifest.contains("pkgConfig: \"gtk4\""))

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
        #expect(patchedRenderer.contains("background: transparent; background-color: transparent; border: none"))
        #expect(patchedRenderer.contains("SwiftUI lays vertical ScrollView content out in the viewport"))
        #expect(patchedRenderer.contains("gtk_widget_set_halign(child, GTK_ALIGN_FILL)"))
        #expect(patchedRenderer.contains("gtk_widget_set_valign(child, GTK_ALIGN_FILL)"))
        #expect(patchedRenderer.contains("var buttonWantsHExpand = false"))
        #expect(patchedRenderer.contains("if gtk_widget_get_hexpand(childWidget) != 0"))
        #expect(patchedRenderer.contains("gtk_widget_set_hexpand(button, buttonWantsHExpand ? 1 : 0)"))
        #expect(patchedRenderer.contains("gtk_widget_set_halign(button, buttonWantsHExpand ? GTK_ALIGN_FILL : GTK_ALIGN_START)"))
        #expect(patchedRenderer.contains("expandsToFillWidth: childExpH || (width == nil && maxWidth != nil && maxWidth != .infinity)"))
        #expect(patchedRenderer.contains("expandsToFillHeight: childExpV || (height == nil && maxHeight != nil && maxHeight != .infinity)"))
        #expect(patchedRenderer.contains("expandsToFillHeight: gtk_widget_get_vexpand(child) != 0 || (height == nil && maxHeight != nil && maxHeight != .infinity)"))
        #expect(patchedRenderer.contains("retainedBox = Unmanaged<ClosureBox>.fromOpaque(userData).retain().toOpaque()"))
        #expect(patchedRenderer.contains("private var gtkStateCache: [String: [AnyStateStorage]] = [:]"))
        #expect(patchedRenderer.contains("private var gtkStateTypeCounters: [String: [String: Int]] = [:]"))
        #expect(patchedRenderer.contains("private func gtkStateIdentityNamespace() -> String"))
        #expect(patchedRenderer.contains("GTKViewHost.getCurrentRebuilding()?.stateIdentityNamespace ?? \"root\""))
        #expect(patchedRenderer.contains("func gtkBeginStateIdentityPass()"))
        #expect(patchedRenderer.contains("gtkStateTypeCounters[gtkStateIdentityNamespace()] = [:]"))
        #expect(patchedRenderer.contains("return \"\\(namespace)::\\(typeName)#\\(index)\""))
        #expect(patchedRenderer.contains("host.stateIdentityNamespace = key"))
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
        #expect(patchedRenderer.contains("private var gtkPendingScrollRequests"))
        #expect(patchedRenderer.contains("gtk_widget_translate_coordinates(target, scrolled"))
        #expect(patchedRenderer.contains("gtk_scrolled_window_get_vadjustment"))
        #expect(patchedRenderer.contains("let request = GTKPendingScrollRequest(anchor: anchor)"))
        #expect(patchedRenderer.contains("gtkPendingScrollRequests[id] = request"))
        #expect(patchedRenderer.contains("gtkScheduleScrollTo(widget, anchor: anchor)"))
        #expect(patchedRenderer.contains("gtkScheduleIdleScrollTo(_ target"))
        #expect(patchedRenderer.contains("g_object_ref(gpointer(target))"))
        #expect(patchedRenderer.contains("defer { g_object_unref(gpointer(context.target)) }"))
        #expect(patchedRenderer.contains("g_idle_add({ userData -> gboolean in"))
        #expect(patchedRenderer.contains("gtkScheduleIdleScrollTo(widget, anchor: request.anchor)"))
        #expect(patchedRenderer.contains("gtkResolveOrQueueScrollTo(id: anyID, anchor: anchor)"))
        #expect(patchedRenderer.contains("gtkResolvePendingScrollTo(id: AnyHashable(id), widget: widget)"))
        #expect(patchedRenderer.contains("context.remainingTicks -= 1"))
        #expect(patchedRenderer.contains("gtkScheduleOnAppear(_ action"))
        #expect(patchedRenderer.contains("gtkScheduleOnAppear(boundAction, on: widget)"))
        #expect(!patchedRenderer.contains("gtk_widget_grab_focus(widget)"))
        #expect(patchedRenderer.contains("private protocol GTKDecorativeOverlay"))
        #expect(patchedRenderer.contains("extension StrokedShape: GTKDecorativeOverlay"))
        #expect(patchedRenderer.contains("gtk_widget_set_can_target(overlayWidget, 0)"))

        let patchedDescriptorTree = try String(contentsOf: descriptorTree, encoding: .utf8)
        #expect(patchedDescriptorTree.contains("GTK Button action closures capture the view state storage"))
        #expect(patchedDescriptorTree.contains("if plan.newDescriptor.kind == .button"))

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

        let patchedToolbar = try String(contentsOf: toolbar, encoding: .utf8)
        #expect(patchedToolbar.contains("public let renderedViews: [any View]"))
        #expect(patchedToolbar.contains("item.content.body as? MultiChildView"))

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

    @Test("vendored SwiftOpenUI starts GTK task modifiers after map")
    func vendoredSwiftOpenUIStartsGTKTasksAfterMap() throws {
        let root = try packageRoot()
        let viewHost = root
            .appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKViewHost.swift")
        let renderer = root
            .appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift")
        let viewHostSource = try String(contentsOf: viewHost, encoding: .utf8)
        let rendererSource = try String(contentsOf: renderer, encoding: .utf8)

        #expect(viewHostSource.contains("private var taskLifecycleSuspended = true"))
        #expect(viewHostSource.contains("host.resumeTasksAfterAppear()"))
        #expect(viewHostSource.contains("if !taskLifecycleSuspended {"))
        #expect(viewHostSource.contains("for (identity, payload) in taskPayloadsByIdentity where activeTasksByIdentity[identity] == nil"))
        #expect(rendererSource.contains("extension TaskView: GTKRenderable, GTKDescribable"))
        #expect(rendererSource.contains("gtkAttachStandaloneTaskLifecycle("))
        #expect(rendererSource.contains("action: bindTaskActionToCurrentEnvironment(action)"))
        #expect(!rendererSource.contains("if GTKViewHost.getCurrentRebuilding() == nil {\n            gtkAttachStandaloneTaskLifecycle("))
        #expect(!rendererSource.contains("gtkCollectTaskPayload(GTK4TaskPayload(\n            priority: priority"))
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
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
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
