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

    @Test("os(macOS) in #if conditions is widened to (os(macOS) || os(Linux))")
    func osMacOSWidenedInIfConfig() {
        let source = """
        #if os(macOS) && canImport(AppKit)
        import AppKit
        #endif
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("#if (os(macOS) || os(Linux)) && canImport(AppKit)"))
    }

    @Test("Negated os(macOS) is left alone")
    func negatedOSMacOSPreserved() {
        let source = """
        #if !os(macOS)
        let mobile = true
        #endif
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("#if !os(macOS)"))
        #expect(!lowered.contains("(os(macOS) || os(Linux))"))
    }

    @Test("Already-widened os(macOS) || os(Linux) is idempotent")
    func alreadyWidenedIsIdempotent() {
        let source = """
        #if os(macOS) || os(Linux)
        let desktop = true
        #endif
        """
        let lowered = SwiftUILowering().lower(source)
        // The inner os(macOS) should NOT get re-wrapped.
        #expect(lowered.contains("#if os(macOS) || os(Linux)"))
        #expect(!lowered.contains("(os(macOS) || os(Linux)) || os(Linux)"))
    }

    @Test("Paren-wrapped negation widens (matches bash regex behavior)")
    func parenWrappedNegationWidens() {
        let source = """
        #if !(os(macOS))
        let weirdNeg = false
        #endif
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("(os(macOS) || os(Linux))"))
    }

    @Test("Top-level #Preview blocks are removed")
    func previewBlockRemoved() {
        let source = """
        import SwiftUI

        struct Root: View {
            var body: some View { Text("hi") }
        }

        #Preview {
            Root()
        }

        #Preview("named") {
            Root()
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("#Preview"))
        #expect(lowered.contains("struct Root: View"))
    }

    @Test("os(macOS) widening only affects #if conditions, not regular code")
    func osMacOSNotWidenedOutsideIfConfig() {
        // A bare `os(macOS)` reference in regular code is unusual but possible
        // (e.g. inside a string or as part of an unrelated function named `os`).
        // The widening must only fire inside #if conditions.
        let source = """
        func describePlatform() -> String {
            return "os(macOS)"
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("\"os(macOS)\""))
        #expect(!lowered.contains("|| os(Linux)"))
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
