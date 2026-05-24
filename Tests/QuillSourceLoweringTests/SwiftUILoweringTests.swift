import Foundation
import Testing
@testable import QuillSourceLowering

@Suite("SwiftUI source lowering (SwiftSyntax)")
struct SwiftUILoweringTests {
    @Test("@main attribute is stripped from top-level decls")
    func mainAttributeStripped() {
        let source = """
        import SwiftUI

        @main
        struct MyApp: App {
            var body: some Scene { WindowGroup { Text("hi") } }
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("@main"))
        #expect(lowered.contains("struct MyApp: App"))
    }

    @Test("@MainActor attribute is stripped from decls")
    func mainActorAttributeStripped() {
        let source = """
        @MainActor
        final class AppModel {
            var title = "Quill"
        }

        @MainActor func bootstrap() {}
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("@MainActor"))
        #expect(lowered.contains("final class AppModel"))
        #expect(lowered.contains("func bootstrap()"))
    }

    @Test("@MainActor is stripped from inline function type expressions")
    func mainActorInsideTypeExpression() {
        let source = """
        struct DesktopRoot {
            let action: (@MainActor () -> Void)?
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("@MainActor"))
        #expect(lowered.contains("let action: (() -> Void)?"))
    }

    @Test("@Observable attribute is stripped from class decls")
    func observableAttributeStripped() {
        let source = """
        @Observable
        final class AppModel {
            var title = "Quill"
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("@Observable"))
        #expect(lowered.contains("final class AppModel"))
        #expect(lowered.contains("var title"))
    }

    @Test("Sendable is dropped from inheritance when View is present")
    func sendableDroppedFromViewInheritance() {
        let source = """
        struct DesktopRoot: View, Sendable {
            var body: some View { Text("hello") }
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("struct DesktopRoot: View {"))
        #expect(!lowered.contains("Sendable"))
    }

    @Test("Sendable is preserved when View is NOT in the inheritance list")
    func sendablePreservedWithoutView() {
        let source = """
        struct PlainModel: Equatable, Sendable {
            var value: Int = 0
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("Sendable"))
        #expect(lowered.contains("Equatable"))
    }

    @Test("Sendable in the middle of an inheritance list is removed cleanly")
    func sendableInMiddleOfInheritance() {
        let source = """
        struct Composite: View, Sendable, Equatable {
            var body: some View { Text("x") }
            static func == (lhs: Composite, rhs: Composite) -> Bool { true }
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("Sendable"))
        #expect(lowered.contains("View, Equatable"))
    }

    @Test("Multiple decls in a file each get lowered")
    func multipleDeclsLowered() {
        let source = """
        import SwiftUI

        @main
        @MainActor
        struct MyApp: App {
            var body: some Scene { WindowGroup { Root() } }
        }

        @Observable
        final class AppModel {
            var title = "Quill"
        }

        @MainActor
        struct Root: View, Sendable {
            let action: (@MainActor () -> Void)?
            var body: some View { Text("ok") }
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("@main"))
        #expect(!lowered.contains("@MainActor"))
        #expect(!lowered.contains("@Observable"))
        #expect(lowered.contains("struct Root: View {"))
        #expect(lowered.contains("let action: (() -> Void)?"))
    }

    @Test("Unrelated attributes are preserved")
    func unrelatedAttributesPreserved() {
        let source = """
        @propertyWrapper
        struct PassThrough<Value> {
            var wrappedValue: Value
        }

        struct Holder {
            @PassThrough var name: String = ""
            @available(macOS 12, *) var legacy: Int { 0 }
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("@propertyWrapper"))
        #expect(lowered.contains("@PassThrough"))
        #expect(lowered.contains("@available(macOS 12, *)"))
    }

    @Test("Idempotent across two passes")
    func idempotent() {
        let source = """
        @main
        struct MyApp: App {
            @MainActor var state = 0
            var body: some Scene { WindowGroup { Root() } }
        }

        struct Root: View, Sendable {
            let action: (@MainActor () -> Void)?
            var body: some View { Text("x") }
        }
        """
        let first = SwiftUILowering().lower(source)
        let second = SwiftUILowering().lower(first)
        #expect(first == second)
        #expect(!first.contains("@main"))
        #expect(!first.contains("@MainActor"))
        #expect(first.contains("struct Root: View {"))
    }

    @Test("lowerInPlace rewrites .swift files and leaves other files alone")
    func lowerInPlaceTouchesOnlySwift() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("SwiftUILoweringTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        let nested = scratch.appendingPathComponent("Nested", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)

        let swiftFile = nested.appendingPathComponent("App.swift")
        try """
        @main
        struct MyApp: App {
            var body: some Scene { WindowGroup { Text("hi") } }
        }
        """.write(to: swiftFile, atomically: true, encoding: .utf8)

        let textFile = scratch.appendingPathComponent("README.txt")
        let readmeContents = "Keep me as-is.\n"
        try readmeContents.write(to: textFile, atomically: true, encoding: .utf8)

        let visited = try SwiftUILowering().lowerInPlace(sourceDir: scratch)
        #expect(visited == 1)

        let loweredSwift = try String(contentsOf: swiftFile, encoding: .utf8)
        #expect(!loweredSwift.contains("@main"))
        #expect(loweredSwift.contains("struct MyApp: App"))

        let untouchedText = try String(contentsOf: textFile, encoding: .utf8)
        #expect(untouchedText == readmeContents)
    }
}
