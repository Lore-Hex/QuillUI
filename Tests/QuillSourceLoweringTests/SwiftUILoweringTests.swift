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

    @Test("stripped declaration attributes preserve member boundaries")
    func strippedAttributesPreserveMemberBoundaries() {
        let source = """
        class PanelManager {
            func handleNewMessages() {
                if true {}
            }

            @MainActor
            @objc func togglePanel() {}

            @MainActor var allowPrinting = true
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("}func"))
        #expect(!lowered.contains("}var"))
        #expect(lowered.contains("}\n\n    func togglePanel()"))
        #expect(lowered.contains("\n    var allowPrinting = true"))
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

    @Test("@Observable classes gain QuillObservableObject and publish stored vars")
    func observableClassLowered() {
        let source = """
        @Observable
        final class AppModel {
            var title = "Quill"
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("@Observable"))
        #expect(lowered.contains("final class AppModel: QuillObservableObject {"))
        #expect(lowered.contains("@QuillPublished var title = \"Quill\""))
    }

    @Test("@Observable inheritance prepends QuillObservableObject")
    func observableInheritancePrepended() {
        let source = """
        @Observable
        final class Store: Identifiable {}
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("final class Store: QuillObservableObject, Identifiable {}"))
    }

    @Test("@Observable classes already conforming to ObservableObject are not double-added")
    func observableExistingObservableObjectIsIdempotent() {
        let source = """
        @Observable
        final class Store: ObservableObject {
            var value = 1
        }

        @Observable
        final class OtherStore: QuillObservableObject {
            var value = 2
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("final class Store: ObservableObject {"))
        #expect(lowered.contains("final class OtherStore: QuillObservableObject {"))
        #expect(!lowered.contains("QuillObservableObject, ObservableObject"))
        #expect(!lowered.contains("QuillObservableObject, QuillObservableObject"))
    }

    @Test("@Observable stored var allowlist matches SwiftOpenUI helper")
    func observableStoredVarAllowlist() {
        let source = """
        @Observable
        final class Store {
            var stored = 1
            public var publicValue = 2
            internal var internalValue = 3
            fileprivate var fileValue = 4
            static var shared = 5
            class var subclassValue: Int { 6 }
            private var cached = 7
            private(set) var readOnly = 8
            var computed: Int { 9 }
            @Published var alreadyPublished = 10
            @QuillPublished var alreadyQuillPublished = 11
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("@QuillPublished var stored = 1"))
        #expect(lowered.contains("@QuillPublished public var publicValue = 2"))
        #expect(lowered.contains("@QuillPublished internal var internalValue = 3"))
        #expect(lowered.contains("@QuillPublished fileprivate var fileValue = 4"))
        #expect(lowered.contains("static var shared = 5"))
        #expect(lowered.contains("class var subclassValue: Int { 6 }"))
        #expect(lowered.contains("private var cached = 7"))
        #expect(lowered.contains("private(set) var readOnly = 8"))
        #expect(lowered.contains("var computed: Int { 9 }"))
        #expect(lowered.contains("@Published var alreadyPublished = 10"))
        #expect(lowered.contains("@QuillPublished var alreadyQuillPublished = 11"))
        #expect(!lowered.contains("@QuillPublished static var"))
        #expect(!lowered.contains("@QuillPublished class var"))
        #expect(!lowered.contains("@QuillPublished private var"))
        #expect(!lowered.contains("@QuillPublished private(set)"))
        #expect(!lowered.contains("@QuillPublished var computed"))
        #expect(!lowered.contains("@QuillPublished @Published"))
        #expect(!lowered.contains("@QuillPublished @QuillPublished"))
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

    @Test("Identifiable ForEach collection gains explicit id key path")
    func identifiableForEachCollectionGainsExplicitID() {
        let source = """
        struct SuggestionsView: View {
            var suggestions: [Suggestion]
            var body: some View {
                ForEach(suggestions) { suggestion in
                    Text(suggestion.title)
                }
            }
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains(#"ForEach(suggestions, id: \.id) { suggestion in"#))
    }

    @Test("ForEach ranges and explicit ids are preserved")
    func forEachRangesAndExplicitIDsPreserved() {
        let source = """
        struct RangeView: View {
            var items: [Item]
            var body: some View {
                VStack {
                    ForEach(0..<items.count) { index in
                        Text("\\(index)")
                    }
                    ForEach(items.indices) { index in
                        Text("\\(index)")
                    }
                    ForEach(items, id: \\.name) { item in
                        Text(item.name)
                    }
                }
            }
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("ForEach(0..<items.count)"))
        #expect(lowered.contains("ForEach(items.indices)"))
        #expect(lowered.contains(#"ForEach(items, id: \.name)"#))
        #expect(!lowered.contains(#"0..<items.count, id: \.id"#))
        #expect(!lowered.contains(#"items.indices, id: \.id"#))
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
        #expect(lowered.contains("final class AppModel: QuillObservableObject"))
        #expect(lowered.contains("@QuillPublished var title = \"Quill\""))
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
        @Observable
        final class AppModel {
            var count = 0
        }

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
        #expect(!first.contains("@Observable"))
        #expect(first.contains("final class AppModel: QuillObservableObject {"))
        #expect(first.contains("@QuillPublished var count = 0"))
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

    @Test("Large SwiftUI body builders are split into private ViewBuilder parts")
    func largeBodyBuilderIsSplitIntoHelpers() {
        let rows = (0..<36).map { index in
            """
                        Text("Row \(index)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 8)
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct ComplexRoot: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
        \(rows)
                }
                .padding(12)
                .background(Color.white)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("@ViewBuilder\n    private var _quillSplitBody0Part0: some View"))
        #expect(lowered.contains("_quillSplitBody0Part35"))
        #expect(lowered.contains("VStack(alignment: .leading, spacing: 8) {"))
        #expect(lowered.contains("            _quillSplitBody0Part0"))
        #expect(lowered.contains(".background(Color.white)"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("Large SwiftUI bodies with local declarations are left intact")
    func largeBodyWithLocalDeclarationsIsNotSplit() {
        let rows = (0..<28).map { index in
            """
                        Text("\\(title)-\(index)")
                            .font(.caption)
                            .padding(.horizontal, 8)
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct ComplexRoot: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    let title = "Local"
        \(rows)
                }
                .padding(12)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("_quillSplitBody"))
        #expect(lowered.contains("let title = \"Local\""))
    }

    @Test("Large SwiftUI bodies with conditional compilation are left intact")
    func largeBodyWithCompileConditionsIsNotSplit() {
        let rows = (0..<28).map { index in
            """
                        Text("Row \(index)")
                            .font(.caption)
                            .padding(.horizontal, 8)
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct ConditionalRoot: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
        \(rows)
                    TextEditor(text: .constant("body"))
                        .focusable()
                    #if os(visionOS)
                        .frame(width: 600, height: 600)
                    #endif
                }
                .padding(12)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("_quillSplitBody"))
        #expect(lowered.contains("#if os(visionOS)"))
        #expect(lowered.contains(".frame(width: 600, height: 600)"))
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
