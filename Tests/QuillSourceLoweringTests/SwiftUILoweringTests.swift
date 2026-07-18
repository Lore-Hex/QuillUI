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

    @Test("@MainActor attribute is preserved on decls")
    func mainActorAttributePreserved() {
        let source = """
        @MainActor
        final class AppModel {
            var title = "Quill"
        }

        @MainActor func bootstrap() {}
        enum Helpers { @MainActor static func bootstrap() {} }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("@MainActor\nfinal class AppModel"))
        #expect(lowered.contains("@MainActor func bootstrap()"))
        #expect(lowered.contains("@MainActor static func bootstrap()"))
        #expect(lowered.contains("final class AppModel"))
    }

    @Test("@MainActor is preserved for explicit static result-builder buildBlock methods")
    func mainActorPreservedForStaticResultBuilderBuildBlock() {
        let source = """
        @resultBuilder
        public enum ActionsBuilder {
            @MainActor public static func buildBlock<V1: View>(_ view1: V1) -> WelcomeActions {
                .one(AnyView(view1))
            }

            @MainActor static func buildBlock() -> WelcomeActions {
                .none
            }
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("@MainActor public static func buildBlock<V1: View>(_ view1: V1) -> WelcomeActions"))
        #expect(lowered.contains("@MainActor static func buildBlock() -> WelcomeActions"))
        #expect(lowered.components(separatedBy: "@MainActor").count - 1 == 2)
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
        #expect(lowered.contains("}\n\n    @MainActor func togglePanel()"))
        #expect(lowered.contains("\n    @MainActor var allowPrinting = true"))
    }

    @Test("@MainActor is preserved in inline function type expressions")
    func mainActorInsideTypeExpression() {
        let source = """
        struct DesktopRoot {
            let action: (@MainActor () -> Void)?
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("let action: (@MainActor () -> Void)?"))
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
            var selected = false {
                didSet { selectionChanges += 1 }
            }
            private var selectionChanges = 0 {
                willSet { _ = newValue }
            }
            var computed: Int { 9 }
            var explicitComputed: Int {
                get { 10 }
                set { _ = newValue }
            }
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
        #expect(lowered.contains("@QuillPublished private var cached = 7"))
        #expect(lowered.contains("@QuillPublished private(set) var readOnly = 8"))
        #expect(lowered.contains("@QuillPublished var selected = false"))
        #expect(lowered.contains("@QuillPublished private var selectionChanges = 0"))
        #expect(lowered.contains("var computed: Int { 9 }"))
        #expect(lowered.contains("var explicitComputed: Int"))
        #expect(lowered.contains("@Published var alreadyPublished = 10"))
        #expect(lowered.contains("@QuillPublished var alreadyQuillPublished = 11"))
        #expect(!lowered.contains("@QuillPublished static var"))
        #expect(!lowered.contains("@QuillPublished class var"))
        #expect(!lowered.contains("@QuillPublished var computed"))
        #expect(!lowered.contains("@QuillPublished var explicitComputed"))
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
        #expect(lowered.contains("@MainActor"))
        #expect(!lowered.contains("@Observable"))
        #expect(lowered.contains("final class AppModel: QuillObservableObject"))
        #expect(lowered.contains("@QuillPublished var title = \"Quill\""))
        #expect(lowered.contains("@MainActor\nstruct Root: View {"))
        #expect(lowered.contains("let action: (@MainActor () -> Void)?"))
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
        #expect(first.contains("@MainActor"))
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

        @available(macOS 14.0, *)
        #Preview {
            Root()
        }

        #Preview("named") {
            Root()
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("#Preview"))
        #expect(!lowered.contains("@available(macOS 14.0, *)"))
        #expect(lowered.contains("struct Root: View"))
    }

    @Test("Top-level #Preview at end of file is removed")
    func previewBlockAtEndOfFileRemoved() {
        let source = """
        import SwiftUI

        struct SettingsPane: View {
            var body: some View { Text("Settings") }
        }

        #Preview {
            SettingsPane()
        }
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(!lowered.contains("#Preview"))
        #expect(lowered.contains("struct SettingsPane: View"))
    }

    @Test("Apple framework submodule imports lower to parent shim modules")
    func appleFrameworkSubmoduleImportsLowerToParentShimModules() {
        let source = """
        import Foundation.NSDate
        import PDFKit.PDFView
        @preconcurrency import UIKit.UIGestureRecognizerSubclass

        let date = NSDate()
        """
        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("import Foundation"))
        #expect(lowered.contains("import PDFKit"))
        #expect(lowered.contains("@preconcurrency import UIKit"))
        #expect(!lowered.contains("Foundation.NSDate"))
        #expect(!lowered.contains("PDFKit.PDFView"))
        #expect(!lowered.contains("UIKit.UIGestureRecognizerSubclass"))
    }

    @Test("URLRequest constructor calls qualify FoundationNetworking on Linux")
    func urlRequestConstructorCallsQualifyFoundationNetworking() {
        let source = """
        import Foundation

        enum GitRouter {
            func request(_ url: URL) -> URLRequest? {
                URLRequest(url: url)
            }

            func existing(_ url: URL) -> URLRequest {
                Foundation.URLRequest(url: url)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("import Foundation\nimport FoundationNetworking"))
        #expect(lowered.contains("FoundationNetworking.URLRequest(url: url)"))
        #expect(!lowered.contains("Foundation.URLRequest(url: url)"))
        #expect(!lowered.contains("FoundationNetworking.Foundation.URLRequest"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("FoundationNetworking async URLSession protocol requirements remain visible on Linux")
    func foundationNetworkingAsyncURLSessionRequirementsRemainVisible() {
        let source = """
        import Foundation
        #if canImport(FoundationNetworking)
        import FoundationNetworking
        #endif

        protocol GitURLSession {
        #if !canImport(FoundationNetworking)
            func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)

            func upload(
                for request: URLRequest,
                from bodyData: Data,
                delegate: URLSessionTaskDelegate?
            ) async throws -> (Data, URLResponse)
        #endif
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("#if true"))
        #expect(lowered.contains("func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)"))
        #expect(lowered.contains("func upload(\n        for request: URLRequest,"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("NSFontManager availableFontFamilies method calls lower to property access")
    func nsFontManagerAvailableFontFamiliesCallsLowerToPropertyAccess() {
        let source = """
        import AppKit

        func families() -> [String] {
            NSFontManager.shared.availableFontFamilies()
        }

        func monospaced() -> [String] {
            let availableFontFamilies = NSFontManager.shared.availableFontFamilies
            return availableFontFamilies.filter { $0.contains("Mono") }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("NSFontManager.shared.availableFontFamilies"))
        #expect(!lowered.contains("availableFontFamilies()"))
        #expect(lowered.contains("let availableFontFamilies: [String] = NSFontManager.shared.availableFontFamilies"))
        #expect(lowered.contains("return quillClosureFilter(availableFontFamilies) { $0.contains(\"Mono\") }"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("AttributedString foregroundColor dynamic member lowers to helper")
    func attributedStringForegroundColorDynamicMemberLowersToHelper() {
        let source = """
        import SwiftUI

        func info() -> AttributedString {
            var attrString = AttributedString("Mason Registry")
            if let linkRange = attrString.range(of: "Mason Registry") {
                attrString[linkRange].link = URL(string: "https://mason-registry.dev/")
                attrString[linkRange].foregroundColor = NSColor.linkColor
            }
            return attrString
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("quillSetAttributedStringForegroundColor(&attrString, range: linkRange, color: NSColor.linkColor)"))
        #expect(!lowered.contains("].foregroundColor ="))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("Projected collection isEmpty checks lower to wrapped collection checks")
    func projectedCollectionIsEmptyChecksLowerToWrappedCollectionChecks() {
        let source = """
        import SwiftUI

        struct AccountsSettingsView: View {
            @State var accounts: [String] = []

            var body: some View {
                if $accounts.isEmpty {
                    Text("No accounts")
                }
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("if accounts.isEmpty {"))
        #expect(!lowered.contains("$accounts.isEmpty"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("POSIX sysconf buffer sizes lower to Int for Glibc allocation APIs")
    func posixSysconfBufferSizesLowerToInt() {
        let source = """
        func loadUser() {
            let bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)
            let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: bufsize)
            _ = buffer
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("let bufsize = Int(sysconf(Int32(_SC_GETPW_R_SIZE_MAX)))"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("Axis and Edge tuple switches gain default case for OptionSet axis")
    func axisEdgeTupleSwitchesGainDefaultCase() {
        let source = """
        func split(_ direction: Edge) {
            switch (axis, direction) {
            case (.horizontal, .trailing), (.vertical, .bottom):
                insertAfter()
            case (.horizontal, .leading), (.vertical, .top):
                insertBefore()
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("default:\n            break"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("Axis initializer switches gain horizontal default for OptionSet exhaustiveness")
    func axisInitializerSwitchesGainHorizontalDefault() {
        let source = """
        enum SplitViewAxis {
            case vertical, horizontal

            init(_ swiftUI: Axis) {
                switch swiftUI {
                case .vertical: self = .vertical
                case .horizontal: self = .horizontal
                }
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("default:"))
        #expect(lowered.contains("self = .horizontal"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("XPC continuation data decoded by JSONDecoder is annotated as Data")
    func jsonDecoderContinuationDataIsAnnotated() {
        let source = """
        import Foundation

        enum ExtensionKind: Decodable {}

        struct ExtensionInfo {
            static func getAvailableFeatures(_ connection: NSXPCConnection) async throws -> [ExtensionKind] {
                let encodedAvailableFeatures = try await connection.withContinuation { (service: XPCWrappable, continuation) in
                    service.getExtensionKinds(reply: continuation.resumingHandler)
                }
                return try JSONDecoder().decode([ExtensionKind].self, from: encodedAvailableFeatures)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("let encodedAvailableFeatures: Data = try await connection.withContinuation"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("optional published MergeMany chains lower to named local publishers")
    func optionalPublishedMergeManyChainsLowerToNamedLocalPublishers() {
        let source = """
        import Combine

        extension WindowController {
            internal func listenToDocumentEdited(workspace: WorkspaceDocument) {
                workspace.editorManager?.$activeEditor
                    .flatMap({ editor in
                        editor.$tabs
                    })
                    .compactMap({ tab in
                        Publishers.MergeMany(tab.elements.compactMap({ $0.file.fileDocumentPublisher }))
                    })
                    .switchToLatest()
                    .compactMap({ fileDocument in
                        fileDocument?.isDocumentEditedPublisher
                    })
                    .flatMap({ $0 })
                    .sink { isDocumentEdited in
                        if isDocumentEdited {
                            self.setDocumentEdited(true)
                            return
                        }

                        self.updateDocumentEdited(workspace: workspace)
                    }
                    .store(in: &cancellables)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("if let _quillCombinePipeline0Source = workspace.editorManager?.$activeEditor {"))
        #expect(lowered.contains("let _quillCombinePipeline0Children = _quillCombinePipeline0Source"))
        #expect(lowered.contains("let _quillCombinePipeline0Documents = _quillCombinePipeline0Children"))
        #expect(lowered.contains("Publishers.MergeMany(tab.elements.compactMap { $0.file.fileDocumentPublisher })"))
        #expect(lowered.contains("let _quillCombinePipeline0Values = _quillCombinePipeline0Documents"))
        #expect(lowered.contains("_quillCombinePipeline0Values\n            .sink { isDocumentEdited in"))
        #expect(!lowered.contains("workspace.editorManager?.$activeEditor\n                    .flatMap({ editor in"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
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

    @Test("Large ViewBuilder content properties are split like body builders")
    func largeContentBuilderIsSplitIntoHelpers() {
        let rows = (0..<30).map { index in
            """
                        Text("Tab \(index)")
                            .font(.caption)
                            .padding(.horizontal, 8)
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct ComplexTab: View {
            @ViewBuilder var content: some View {
                HStack(alignment: .center, spacing: 3) {
                    // Tab content
        \(rows)
                }
                .frame(maxHeight: .infinity)
                .accessibilityLabel("Tab")
            }

            var body: some View {
                content
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("@ViewBuilder\n    private var _quillSplitBody0Part0: some View"))
        #expect(lowered.contains("EmptyView()"))
        #expect(lowered.contains("HStack(alignment: .center, spacing: 3) {"))
        #expect(lowered.contains(".accessibilityLabel(\"Tab\")"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("Large GeometryReader bodies are extracted into proxy helpers")
    func largeGeometryReaderBodyIsExtractedIntoProxyHelper() {
        let rows = (0..<34).map { index in
            """
                            Text("Crumb \(index)")
                                .font(.caption)
                                .frame(width: proxy.size.width)
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct JumpBar: View {
            var body: some View {
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
        \(rows)
                        }
                    }
                    .onAppear {
                        _ = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, _ in
                        _ = proxy.size.height
                    }
        #if compiler(>=6.2)
                    .background(Text("new compiler"))
        #else
                    .background(Text("old compiler"))
        #endif
                }
                .padding(.horizontal, 4)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("GeometryReader { proxy in\n            _quillSplitBody0Geometry(proxy)\n        }"))
        #expect(lowered.contains("@ViewBuilder\n    private func _quillSplitBody0Geometry(_ proxy: GeometryProxy) -> some View"))
        #expect(lowered.contains("ScrollView(.horizontal, showsIndicators: false)"))
        #expect(lowered.contains("#if compiler(>=6.2)"))
        #expect(lowered.contains(".padding(.horizontal, 4)"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("Generated GeometryReader helpers split root TrackableScrollView closures")
    func generatedGeometryReaderHelperSplitsTrackableScrollViewClosure() {
        let rows = (0..<30).map { index in
            """
                                Text("Tab \(index)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .padding(.horizontal, 8)
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct EditorTabs: View {
            var body: some View {
                GeometryReader { geometryProxy in
                    TrackableScrollView(.horizontal, showIndicators: false) {
                        ScrollViewReader { scrollReader in
                            HStack(alignment: .center, spacing: -1) {
        \(rows)
                            }
                            .onAppear {
                                scrollReader.scrollTo("selected")
                            }
                            .onChange(of: geometryProxy.size.width) { _, _ in
                                scrollReader.scrollTo("selected")
                            }
                            .frame(height: 28)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .overlay(alignment: .leading) {
                        Color.clear.opacity(0.5)
                    }
                    .overlay(alignment: .trailing) {
                        Color.clear.opacity(0.5)
                    }
                }
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("_quillSplitBody0Geometry(geometryProxy)"))
        #expect(lowered.contains("_quillSplitBody1TrackableContent(geometryProxy)"))
        #expect(lowered.contains("private func _quillSplitBody1TrackableContent(_ geometryProxy: GeometryProxy) -> some View"))
        #expect(lowered.contains("_quillSplitBody2ScrollReaderContent(scrollReader, geometryProxy)"))
        #expect(lowered.contains("private func _quillSplitBody2ScrollReaderContent(_ scrollReader: ScrollViewProxy, _ geometryProxy: GeometryProxy) -> some View"))
        #expect(lowered.contains("var view = AnyView("))
        #expect(lowered.contains("return view"))
        #expect(lowered.contains(".onChange(of: geometryProxy.size.width)"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("Generated helper splitting preserves renamed GeometryReader parameters")
    func generatedHelperSplittingPreservesRenamedGeometryReaderParameters() {
        let rows = (0..<30).map { index in
            """
                                Text("Tab \(index)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .padding(.horizontal, 8)
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct EditorTabs: View {
            var body: some View {
                GeometryReader { proxy in
                    TrackableScrollView(.horizontal, showIndicators: false) {
                        ScrollViewReader { scrollReader in
                            HStack(alignment: .center, spacing: -1) {
        \(rows)
                            }
                            .onAppear {
                                scrollReader.scrollTo("selected")
                            }
                            .onChange(of: proxy.size.width) { _, _ in
                                scrollReader.scrollTo("selected")
                            }
                            .frame(height: 28)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .overlay(alignment: .leading) {
                        Color.clear.opacity(0.5)
                    }
                }
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("_quillSplitBody0Geometry(proxy)"))
        #expect(lowered.contains("_quillSplitBody1TrackableContent(proxy)"))
        #expect(lowered.contains("private func _quillSplitBody1TrackableContent(_ proxy: GeometryProxy) -> some View"))
        #expect(lowered.contains("_quillSplitBody2ScrollReaderContent(scrollReader, proxy)"))
        #expect(lowered.contains("private func _quillSplitBody2ScrollReaderContent(_ scrollReader: ScrollViewProxy, _ proxy: GeometryProxy) -> some View"))
        #expect(lowered.contains(".onChange(of: proxy.size.width)"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("Large SwiftUI body splitting keeps multiline conditional expressions together")
    func largeBodySplitKeepsMultilineConditionalExpressionsTogether() {
        let rows = (0..<34).map { index in
            """
                    Text("Row \(index)")
                        .font(.caption)
                        .padding(.horizontal, 8)
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct WorkspacePanel: View {
            @EnvironmentObject private var model: WorkspaceModel

            var body: some View {
                VStack {
                    if model.hasLeadingSidebar
                        && (
                            model.navigatorVisibility != .hidden
                            || model.inspectorVisibility != .hidden
                        ) {
                        SidebarView()
                    }
        \(rows)
                }
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        let normalizedWhitespace = lowered.replacingOccurrences(
            of: #" +"#,
            with: " ",
            options: .regularExpression
        )
        #expect(lowered.contains("@ViewBuilder\n    private var _quillSplitBody0Part0: some View"))
        #expect(normalizedWhitespace.contains("if model.hasLeadingSidebar\n && ("))
        #expect(normalizedWhitespace.contains("model.navigatorVisibility != .hidden\n || model.inspectorVisibility != .hidden"))
        #expect(!lowered.contains("private var _quillSplitBody0Part1: some View {\n        &&"))
        #expect(!lowered.contains("if model.hasLeadingSidebar\n    }"))
        #expect(!lowered.contains("_quillSplitBody0Part34}"))
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

    @Test("simple ViewThatFits children lower to explicit AnyView array")
    func simpleViewThatFitsChildrenLowerToExplicitAnyViewArray() {
        let source = """
        import SwiftUI

        struct FindPanelView: View {
            @ObservedObject var viewModel: FindPanelViewModel
            @FocusState private var focus: FindPanelFocus?
            @State private var findModePickerWidth: CGFloat = 1.0

            var body: some View {
                ViewThatFits {
                    FindPanelContent(
                        viewModel: viewModel,
                        focus: $focus,
                        findModePickerWidth: $findModePickerWidth,
                        condensed: false
                    )
                    FindPanelContent(
                        viewModel: viewModel,
                        focus: $focus,
                        findModePickerWidth: $findModePickerWidth,
                        condensed: true
                    )
                }
                .padding(.horizontal, 5)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("ViewThatFits(children: ["))
        #expect(lowered.contains("AnyView(\n                FindPanelContent("))
        #expect(lowered.contains("condensed: false"))
        #expect(lowered.contains("condensed: true"))
        #expect(lowered.contains("])\n        .padding(.horizontal, 5)"))
        #expect(!lowered.contains("ViewThatFits {\n"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("large ViewThatFits modifier chains split the base view into a helper")
    func largeViewThatFitsModifierChainsSplitBaseViewIntoHelper() {
        let modifiers = (0..<8).map { index in
            """
                    .onChange(of: viewModel.value\(index)) { newValue in
                        viewModel.handle(newValue)
                    }
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct FindPanelView: View {
            @ObservedObject var viewModel: FindPanelViewModel

            var body: some View {
                ViewThatFits {
                    FindPanelContent(viewModel: viewModel, condensed: false)
                    FindPanelContent(viewModel: viewModel, condensed: true)
                }
                .padding(.horizontal, 5)
                .frame(height: viewModel.panelHeight)
                .background(.bar)
        \(modifiers)
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("@ViewBuilder\n    private var _quillSplitBody0Part0: some View"))
        #expect(lowered.contains("var body: some View {\n        var view = AnyView("))
        #expect(lowered.contains("            _quillSplitBody0Part0"))
        #expect(lowered.contains("        view = AnyView(view\n            .onChange(of: viewModel.value0)"))
        #expect(lowered.contains("        return view"))
        #expect(lowered.contains("ViewThatFits(children: ["))
        #expect(lowered.contains(".frame(height: viewModel.panelHeight)"))
        #expect(lowered.contains(".background(Material.bar)"))
        #expect(lowered.contains(".onChange(of: viewModel.value7)"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("large conditional SwiftUI bodies lower to explicit AnyView return flow")
    func largeConditionalBodyLowersToAnyViewReturnFlow() {
        let observers = (0..<4).map { index in
            """
                            .onChange(of: model.value\(index)) { _, newValue in
                                model.handle(newValue, manager: manager)
                            }
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct WorkspaceLikeView: View {
            @EnvironmentObject private var model: WorkspaceModel

            var body: some View {
                if model.fileManager != nil, let manager = model.manager {
                    VStack {
                        SplitViewReader { proxy in
                            SplitView(axis: .vertical) {
                                EditorAreaView()
                                UtilityAreaView()
                            }
                            .edgesIgnoringSafeArea(.top)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .top) {
                                StatusBarView(proxy: proxy)
                            }
        \(observers)
                            .task {
                                await manager.refresh()
                            }
                            .onReceive(NotificationCenter.default.publisher(for: Window.willCloseNotification)) { output in
                                model.persist(output)
                            }
                        }
                    }
                    .background(EffectView(.contentBackground))
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        model.handleDrop(providers)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("workspace area")
                }
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("guard model.fileManager != nil, let manager = model.manager else {"))
        #expect(lowered.contains("return AnyView(EmptyView())"))
        #expect(lowered.contains("var view = AnyView("))
        #expect(lowered.contains("view = AnyView(view\n            .background(EffectView(.contentBackground))"))
        #expect(lowered.contains("view = AnyView(view\n            .onDrop(of: [.fileURL], isTargeted: nil)"))
        #expect(lowered.contains("return view"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("large conditional builder items with observer chains move to local AnyView functions")
    func largeConditionalBuilderItemsWithObserverChainsMoveToLocalAnyViewFunctions() {
        let observers = (0..<4).map { index in
            """
                            .onChange(of: model.value\(index)) { _, newValue in
                                model.handle(newValue, manager: manager)
                            }
            """
        }.joined(separator: "\n")

        let source = """
        import SwiftUI

        struct WorkspaceLikeView: View {
            @EnvironmentObject private var model: WorkspaceModel

            var body: some View {
                if model.fileManager != nil, let manager = model.manager {
                    VStack {
                        EditorAreaView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .top) {
                                StatusBarView()
                            }
        \(observers)
                            .task {
                                await manager.refresh()
                            }
                    }
                    .background(EffectView(.contentBackground))
                }
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("func _quillSplitBody0Part0() -> AnyView"))
        #expect(lowered.contains("_quillSplitBody0Part0()"))
        #expect(lowered.contains("view = AnyView(view\n                .onChange(of: model.value0)"))
        #expect(lowered.contains("return view"))
        #expect(SwiftUILowering().lower(lowered) == lowered)
    }

    @Test("ViewThatFits with local declarations is left intact")
    func viewThatFitsWithLocalDeclarationsIsLeftIntact() {
        let source = """
        import SwiftUI

        struct Root: View {
            var body: some View {
                ViewThatFits {
                    let title = "Local"
                    Text(title)
                    Text("Fallback")
                }
            }
        }
        """

        let lowered = SwiftUILowering().lower(source)
        #expect(lowered.contains("ViewThatFits {"))
        #expect(!lowered.contains("ViewThatFits(children:"))
        #expect(lowered.contains("let title = \"Local\""))
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
