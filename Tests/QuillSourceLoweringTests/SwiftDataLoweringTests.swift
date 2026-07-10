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

    @Test("@Attribute is stripped from stored properties")
    func attributeStripped() {
        let source = """
        @Model
        final class ConversationSD: Identifiable {
            @Attribute(.unique) var id: UUID = UUID()
            @Attribute(.externalStorage) var image: Data?
        }
        """
        let lowered = SwiftDataLowering().lower(source)
        #expect(!lowered.contains("@Attribute"))
        #expect(lowered.contains("var id: UUID = UUID()"))
        #expect(lowered.contains("var image: Data?"))
    }

    @Test("@Relationship properties gain inverse-maintenance observers and registration")
    func relationshipObserversAndRegistration() {
        let source = """
        @Model
        final class ConversationSD: Identifiable {
            @Relationship(deleteRule: .cascade, inverse: \\MessageSD.conversation)
            var messages: [MessageSD] = []
        }

        @Model
        final class MessageSD: Identifiable {
            @Relationship var conversation: ConversationSD?

            init(content: String) {
                self.conversation = conversation
            }
        }
        """

        let lowered = SwiftDataLowering().lower(source)

        #expect(lowered.contains("var messages: [MessageSD] = [] {"))
        #expect(lowered.contains("var conversation: ConversationSD? {"))
        #expect(lowered.contains("_ = Self.__quillRelationshipsRegistered"))
        #expect(lowered.contains("QuillRelationships.relationshipDidSet("))
        #expect(lowered.contains("ObjectIdentifier(Self.self)"))
        #expect(lowered.contains("\"messages\""))
        #expect(lowered.contains("newValue: messages"))
        #expect(lowered.contains("\"conversation\""))
        #expect(lowered.contains("newValue: conversation"))
        #expect(lowered.contains("private static let __quillRelationshipsRegistered: Void = {"))
        #expect(lowered.contains("parentType: ConversationSD.self"))
        #expect(lowered.contains("toManyProperty: \"messages\""))
        #expect(lowered.contains("toMany: \\ConversationSD.messages"))
        #expect(lowered.contains("childType: MessageSD.self"))
        #expect(lowered.contains("toOneProperty: \"conversation\""))
        #expect(lowered.contains("toOne: \\MessageSD.conversation"))
        #expect(!lowered.contains("@Relationship"))
        #expect(!lowered.contains("self.conversation = conversation"))
    }

    @Test("optional to-many relationships are not registered until the runtime supports optional arrays")
    func optionalToManyRelationshipRegistrationSkipped() {
        let source = """
        @Model
        final class LanguageModelSD: Identifiable {
            @Relationship(deleteRule: .cascade, inverse: \\ConversationSD.model)
            var conversations: [ConversationSD]? = []
        }

        @Model
        final class ConversationSD: Identifiable {
            @Relationship(deleteRule: .nullify)
            var model: LanguageModelSD?
        }
        """

        let lowered = SwiftDataLowering().lower(source)

        #expect(lowered.contains("var conversations: [ConversationSD]? = [] {"))
        #expect(lowered.contains("var model: LanguageModelSD? {"))
        #expect(!lowered.contains("__quillRelationshipsRegistered"))
        #expect(!lowered.contains("toMany: \\LanguageModelSD.conversations"))
        #expect(!lowered.contains("@Relationship"))
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

    @Test("lowerDirectory discovers relationship inverses across separate files")
    func lowerDirectoryDiscoversRelationshipInversesAcrossFiles() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("SwiftDataRelationshipLoweringTests-\(UUID().uuidString)", isDirectory: true)
        let source = scratch.appendingPathComponent("Source", isDirectory: true)
        let output = scratch.appendingPathComponent("Output", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        try fm.createDirectory(at: source, withIntermediateDirectories: true)

        try """
        @Model
        final class ConversationSD: Identifiable {
            @Relationship(deleteRule: .cascade, inverse: \\MessageSD.conversation)
            var messages: [MessageSD] = []
        }
        """.write(to: source.appendingPathComponent("ConversationSD.swift"), atomically: true, encoding: .utf8)

        try """
        @Model
        final class MessageSD: Identifiable {
            @Relationship var conversation: ConversationSD?

            init(content: String) {
                self.conversation = conversation
            }
        }
        """.write(to: source.appendingPathComponent("MessageSD.swift"), atomically: true, encoding: .utf8)

        try SwiftDataLowering().lowerDirectory(sourceDir: source, outputDir: output)

        let loweredConversation = try String(
            contentsOf: output.appendingPathComponent("ConversationSD.swift"),
            encoding: .utf8
        )
        let loweredMessage = try String(
            contentsOf: output.appendingPathComponent("MessageSD.swift"),
            encoding: .utf8
        )

        for lowered in [loweredConversation, loweredMessage] {
            #expect(lowered.contains("_ = Self.__quillRelationshipsRegistered"))
            #expect(lowered.contains("QuillRelationships.registerInverse("))
            #expect(lowered.contains("toMany: \\ConversationSD.messages"))
            #expect(lowered.contains("toOne: \\MessageSD.conversation"))
            #expect(!lowered.contains("@Relationship"))
        }
        #expect(loweredMessage.contains("var conversation: ConversationSD? {"))
        #expect(!loweredMessage.contains("self.conversation = conversation"))
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
