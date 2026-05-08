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
            @Transient var title: String { model?.name ?? "" }
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, source.path, output.path]
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
        #expect(lowered.contains("var title: String"))
        #expect(lowered.contains("QuillPredicate<ConversationSD> { $0.id == conversationId }"))
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
