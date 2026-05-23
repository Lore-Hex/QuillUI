import Foundation
import Testing
@testable import QuillSourceLowering

@Suite("SwiftData source lowering (SwiftSyntax)")
struct SwiftDataLoweringTests {
    @Test("@Model class without inheritance gains PersistentModel")
    func modelClassWithoutInheritance() {
        let source = """
        import Foundation

        @Model
        final class Bare {
            var name: String = ""
        }
        """
        let lowered = SwiftDataLowering().lower(source)
        #expect(lowered.contains("final class Bare: PersistentModel"))
        #expect(!lowered.contains("@Model"))
        #expect(lowered.contains("var name: String"))
    }

    @Test("@Model class with existing inheritance appends PersistentModel")
    func modelClassWithInheritance() {
        let source = """
        @Model
        final class Convo: Identifiable {
            var id: UUID = UUID()
        }
        """
        let lowered = SwiftDataLowering().lower(source)
        #expect(lowered.contains("final class Convo: Identifiable, PersistentModel"))
        #expect(!lowered.contains("@Model"))
    }

    @Test("PersistentModel is not duplicated when already present")
    func idempotentInheritance() {
        let source = """
        @Model
        final class Convo: Identifiable, PersistentModel {
            var id: UUID = UUID()
        }
        """
        let lowered = SwiftDataLowering().lower(source)
        let occurrences = lowered.components(separatedBy: "PersistentModel").count - 1
        #expect(occurrences == 1)
        #expect(!lowered.contains("@Model"))
    }

    @Test("@Transient is stripped from var declarations")
    func transientStripped() {
        let source = """
        @Model
        final class Convo {
            @Transient var displayName: String { name }
            var name: String = ""
        }
        """
        let lowered = SwiftDataLowering().lower(source)
        #expect(!lowered.contains("@Transient"))
        #expect(lowered.contains("var displayName: String"))
        #expect(lowered.contains("var name: String"))
    }

    @Test("#Predicate becomes #QuillPredicate")
    func predicateRenamed() {
        let source = """
        func lookup(id: UUID) {
            let predicate = #Predicate<Convo> { $0.id == id }
            _ = predicate
        }
        """
        let lowered = SwiftDataLowering().lower(source)
        #expect(lowered.contains("#QuillPredicate<Convo>"))
        #expect(!lowered.contains("#Predicate"))
    }

    @Test("Non-@Model classes are left alone")
    func unrelatedClassUntouched() {
        let source = """
        final class Regular: Equatable {
            var name: String = ""
            static func == (lhs: Regular, rhs: Regular) -> Bool { lhs.name == rhs.name }
        }
        """
        let lowered = SwiftDataLowering().lower(source)
        #expect(lowered.contains("final class Regular: Equatable"))
        #expect(!lowered.contains("PersistentModel"))
    }

    @Test("Lowering is idempotent across two passes")
    func idempotent() {
        let source = """
        @Model
        final class Convo: Identifiable {
            @Transient var displayName: String { name }
            var name: String = ""
        }

        let predicate = #Predicate<Convo> { $0.name == "x" }
        """
        let first = SwiftDataLowering().lower(source)
        let second = SwiftDataLowering().lower(first)
        #expect(first == second)
        #expect(first.contains("final class Convo: Identifiable, PersistentModel"))
        #expect(first.contains("#QuillPredicate<Convo>"))
        #expect(!first.contains("@Model"))
        #expect(!first.contains("@Transient"))
    }

    @Test("lowerDirectory mirrors layout and copies non-Swift files")
    func lowerDirectoryMirrorsLayout() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("SwiftDataLoweringTests-\(UUID().uuidString)", isDirectory: true)
        let source = scratch.appendingPathComponent("Source", isDirectory: true)
        let output = scratch.appendingPathComponent("Output", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }

        let nested = source.appendingPathComponent("Nested", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)

        try """
        @Model
        final class Convo: Identifiable {
            @Transient var displayName: String { name }
            var name: String = ""
        }
        """.write(to: nested.appendingPathComponent("Convo.swift"), atomically: true, encoding: .utf8)

        try "raw text\n".write(
            to: source.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        try SwiftDataLowering().lowerDirectory(sourceDir: source, outputDir: output)

        let loweredSwift = try String(
            contentsOf: output.appendingPathComponent("Nested/Convo.swift"),
            encoding: .utf8
        )
        #expect(loweredSwift.contains("final class Convo: Identifiable, PersistentModel"))
        #expect(!loweredSwift.contains("@Model"))
        #expect(!loweredSwift.contains("@Transient"))

        let copiedText = try String(
            contentsOf: output.appendingPathComponent("README.txt"),
            encoding: .utf8
        )
        #expect(copiedText == "raw text\n")
    }

    @Test("lowerDirectory refuses to overwrite an existing output path")
    func lowerDirectoryRefusesExistingOutput() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("SwiftDataLoweringTests-\(UUID().uuidString)", isDirectory: true)
        let source = scratch.appendingPathComponent("Source", isDirectory: true)
        let output = scratch.appendingPathComponent("Output", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)

        #expect(throws: SwiftDataLowering.LoweringError.self) {
            try SwiftDataLowering().lowerDirectory(sourceDir: source, outputDir: output)
        }
    }
}
