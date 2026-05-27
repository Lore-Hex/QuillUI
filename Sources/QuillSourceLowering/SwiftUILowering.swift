import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Lowers SwiftUI-only Swift syntax into Linux-compatible Swift.
///
/// Mirrors most of the regex transformations in
/// `scripts/lower-swiftui-source-for-linux.sh`. Currently covers:
///
///   * `@main` attribute removal from any declaration
///   * `@MainActor` attribute removal from any declaration
///   * `@MainActor` removal from inline function type expressions
///     (e.g. `let action: (@MainActor () -> Void)?` → `let action: (() -> Void)?`)
///   * `@Observable` class lowering to `QuillObservableObject` inheritance
///     with `@QuillPublished` wrapping for eligible stored properties
///   * `Sendable` removal from inheritance lists whenever `View` is also
///     present (so `struct Foo: View, Sendable` → `struct Foo: View`)
///   * `#Preview { … }` top-level declaration deletion (any `#Preview` macro
///     expansion at file scope is removed entirely)
///   * `os(macOS)` widening to `(os(macOS) || os(Linux))` inside `#if`
///     condition expression trees, with carve-outs for negated forms (`!os(macOS)`)
///     and already-widened forms (`os(macOS) || os(Linux)`)
///
/// Out of scope for this implementation (still handled by the shell script):
///   * `#Preview` blocks wrapped in `#if … #endif` whose `#endif` is the
///     end-of-file marker. Top-level `#Preview` is deleted but the `#if`
///     wrapper is not collapsed.
public struct SwiftUILowering {
    public init() {}

    /// Lowers a single Swift source string in memory.
    public func lower(_ source: String) -> String {
        let tree = Parser.parse(source: source)
        let rewriter = SwiftUIRewriter()
        let rewritten = rewriter.rewrite(tree)
        return rewritten.description
    }

    /// Lowers every `.swift` file under `sourceDir` *in place*. Files whose
    /// lowered content equals the input are not rewritten, so file mtimes
    /// don't churn when a pass is a no-op. Returns the number of `.swift`
    /// files visited (whether or not they were rewritten).
    @discardableResult
    public func lowerInPlace(
        sourceDir: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        let normalizedSource = sourceDir.resolvingSymlinksInPath()

        guard let enumerator = fileManager.enumerator(
            at: normalizedSource,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            let resolved = fileURL.resolvingSymlinksInPath()
            let resourceValues = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            guard resolved.pathExtension == "swift" else { continue }

            let original = try String(contentsOf: resolved, encoding: .utf8)
            let lowered = lower(original)
            if lowered != original {
                try lowered.write(to: resolved, atomically: true, encoding: .utf8)
            }
            count += 1
        }
        return count
    }
}

// MARK: - Rewriter

private final class SwiftUIRewriter: SyntaxRewriter {
    /// Attribute names removed wholesale whether they appear on a declaration
    /// or wrapped around an inline type expression.
    private static let strippedAttributeNames: Set<String> = ["main", "MainActor", "Observable"]

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        // Check the input node before recursion: the AttributeListSyntax
        // override strips @Observable from the recursed class declaration.
        let isObservableClass = node.attributes.contains { Self.isAttribute($0, named: "Observable") }

        let recursed: ClassDeclSyntax
        if let visited = super.visit(node).as(ClassDeclSyntax.self) {
            recursed = visited
        } else {
            recursed = node
        }

        guard isObservableClass else {
            return DeclSyntax(recursed)
        }

        var updated = recursed
        Self.prependQuillObservableObject(to: &updated)
        Self.wrapEligibleStoredVars(in: &updated)
        return DeclSyntax(updated)
    }

    /// Overriding `visit(_ node: AttributeListSyntax)` catches every place
    /// SwiftSyntax models an attribute list — decl-level (`@MainActor func`),
    /// type-level (`(@MainActor () -> Void)?`), and accessor-level — without
    /// per-decl-type boilerplate.
    override func visit(_ node: AttributeListSyntax) -> AttributeListSyntax {
        let recursed = super.visit(node)
        let filtered = AttributeListSyntax(recursed.filter { element in
            guard case .attribute(let attr) = element else { return true }
            return !Self.strippedAttributeNames.contains(attr.attributeName.trimmedDescription)
        })
        guard filtered.count != recursed.count else { return recursed }
        return filtered
    }

    /// Drop `Sendable` from any inheritance list that also names `View`. This
    /// matches the regex `: View, Sendable` → `: View` but works regardless of
    /// `Sendable`'s position in the list, and works for structs, classes,
    /// actors, and enums.
    override func visit(_ node: InheritanceClauseSyntax) -> InheritanceClauseSyntax {
        let recursed = super.visit(node)
        let hasView = recursed.inheritedTypes.contains { $0.type.trimmedDescription == "View" }
        guard hasView else { return recursed }

        let types = recursed.inheritedTypes
        guard let sendableIdx = types.firstIndex(where: { $0.type.trimmedDescription == "Sendable" }) else {
            return recursed
        }

        let removedEntry = types[sendableIdx]
        var newTypes = types
        newTypes.remove(at: sendableIdx)

        // Ensure the new last entry has no trailing comma and that any whitespace
        // that lived on the removed `Sendable` entry's trailing trivia (typically
        // the space before `{`) is carried forward so the brace doesn't fuse.
        if !newTypes.isEmpty {
            let lastIdx = newTypes.index(before: newTypes.endIndex)
            var last = newTypes[lastIdx]
            last.trailingComma = nil

            let removedTrailing = removedEntry.type.trailingTrivia
            if !removedTrailing.isEmpty {
                last.type = last.type.with(\.trailingTrivia, last.type.trailingTrivia + removedTrailing)
            }
            newTypes[lastIdx] = last
        }

        var updated = recursed
        updated.inheritedTypes = newTypes
        return updated
    }

    /// Drop top-level `#Preview` macro expansions. These have no Linux
    /// equivalent and exist only for Xcode preview rendering. The Swift
    /// parser sometimes models the freestanding `#Preview` as a
    /// `MacroExpansionDeclSyntax` and sometimes as a
    /// `MacroExpansionExprSyntax` depending on parse ambiguity — handle both.
    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        let recursed = super.visit(node)
        let filtered = recursed.filter { item in
            if let macroDecl = item.item.as(MacroExpansionDeclSyntax.self),
               macroDecl.macroName.text == "Preview" {
                return false
            }
            if let macroExpr = item.item.as(MacroExpansionExprSyntax.self),
               macroExpr.macroName.text == "Preview" {
                return false
            }
            return true
        }
        if filtered.count == recursed.count { return recursed }
        return filtered
    }

    /// Widen `os(macOS)` to `(os(macOS) || os(Linux))` inside `#if` condition
    /// expression trees. The rewrite only fires inside compile-config
    /// conditions, never in regular code, so we run a nested rewriter
    /// scoped to `IfConfigClauseSyntax.condition`.
    override func visit(_ node: IfConfigClauseSyntax) -> IfConfigClauseSyntax {
        let recursed = super.visit(node)
        guard let condition = recursed.condition else { return recursed }

        // Two-pass: first scan the condition tree for `os(macOS)` calls that
        // should be skipped (negated form or already-widened form), then rewrite.
        let scanner = OSMacOSSkipScanner(viewMode: .sourceAccurate)
        scanner.walk(condition)
        let widener = OSMacOSWidener(skipIDs: scanner.skipIDs)
        let rewritten = widener.rewrite(Syntax(condition))
        guard let newCondition = rewritten.as(ExprSyntax.self) else { return recursed }
        var updated = recursed
        updated.condition = newCondition
        return updated
    }

    // MARK: Observable lowering helpers

    private static func prependQuillObservableObject(to classDecl: inout ClassDeclSyntax) {
        if var clause = classDecl.inheritanceClause {
            let alreadyHasObservableObject = clause.inheritedTypes.contains { entry in
                let type = entry.type.trimmedDescription
                return type == "ObservableObject" || type == "QuillObservableObject"
            }
            if alreadyHasObservableObject { return }

            var types = clause.inheritedTypes
            let entry = InheritedTypeSyntax(
                type: TypeSyntax(
                    IdentifierTypeSyntax(
                        name: .identifier("QuillObservableObject")
                    )
                ),
                trailingComma: .commaToken(trailingTrivia: .space)
            )
            types.insert(entry, at: types.startIndex)
            clause.inheritedTypes = types
            classDecl.inheritanceClause = clause
            return
        }

        // No existing inheritance clause — create one. Normalize surrounding
        // trivia so the inserted conformance separates cleanly from both the
        // class name and opening brace.
        let nameTrailing = classDecl.name.trailingTrivia
        classDecl.name = classDecl.name.with(\.trailingTrivia, [])

        var memberBlock = classDecl.memberBlock
        let braceLeading = memberBlock.leftBrace.leadingTrivia
        memberBlock.leftBrace = memberBlock.leftBrace.with(\.leadingTrivia, [])
        classDecl.memberBlock = memberBlock

        let combinedTail = nameTrailing + braceLeading
        let trailingForObservableObject: Trivia = combinedTail.containsNewlineOrSpace
            ? combinedTail
            : .space

        let entry = InheritedTypeSyntax(
            type: TypeSyntax(
                IdentifierTypeSyntax(
                    name: .identifier("QuillObservableObject", trailingTrivia: trailingForObservableObject)
                )
            )
        )

        classDecl.inheritanceClause = InheritanceClauseSyntax(
            colon: .colonToken(trailingTrivia: .space),
            inheritedTypes: InheritedTypeListSyntax([entry])
        )
    }

    private static func wrapEligibleStoredVars(in classDecl: inout ClassDeclSyntax) {
        var members = classDecl.memberBlock.members
        for index in members.indices {
            var member = members[index]
            guard var variable = member.decl.as(VariableDeclSyntax.self),
                  isEligibleStoredObservableVar(variable) else {
                continue
            }

            variable = prependQuillPublished(to: variable)
            member.decl = DeclSyntax(variable)
            members[index] = member
        }

        var memberBlock = classDecl.memberBlock
        memberBlock.members = members
        classDecl.memberBlock = memberBlock
    }

    private static func isEligibleStoredObservableVar(_ variable: VariableDeclSyntax) -> Bool {
        guard variable.bindingSpecifier.text == "var" else { return false }

        let alreadyPublished = variable.attributes.contains {
            isAttribute($0, named: "Published") || isAttribute($0, named: "QuillPublished")
        }
        if alreadyPublished {
            return false
        }

        if variable.modifiers.contains(where: { modifier in
            let name = modifier.name.text
            return name == "static" || name == "class" || name == "private"
        }) {
            return false
        }

        if variable.bindings.contains(where: { $0.accessorBlock != nil }) {
            return false
        }

        return true
    }

    private static func prependQuillPublished(to variable: VariableDeclSyntax) -> VariableDeclSyntax {
        let leadingTrivia = variable.leadingTrivia
        var updated = variable.with(\.leadingTrivia, [])
        let publishedAttribute = AttributeSyntax(
            leadingTrivia: leadingTrivia,
            attributeName: IdentifierTypeSyntax(
                name: .identifier("QuillPublished", trailingTrivia: .space)
            )
        )
        let attributes = [AttributeListSyntax.Element.attribute(publishedAttribute)] + Array(updated.attributes)
        updated.attributes = AttributeListSyntax(attributes)
        return updated
    }

    private static func isAttribute(_ element: AttributeListSyntax.Element, named name: String) -> Bool {
        guard case let .attribute(attribute) = element else { return false }
        return attribute.attributeName.trimmedDescription == name
    }
}

// MARK: - os(macOS) widening (nested rewriter, scoped to #if conditions)

/// Pre-scan pass that records the `os(macOS)` call IDs to leave alone:
/// those that are immediately negated (`!os(macOS)`) or already part of an
/// `os(macOS) || os(Linux)` pair. Doing this in a separate pass means the
/// rewriter doesn't have to rely on parent traversal mid-rewrite, which
/// `SyntaxRewriter` doesn't reliably support.
private final class OSMacOSSkipScanner: SyntaxVisitor {
    var skipIDs: Set<SyntaxIdentifier> = []

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.text == "!",
           let call = node.expression.as(FunctionCallExprSyntax.self),
           OSMacOSWidener.isOSMacOSCall(call) {
            skipIDs.insert(Syntax(call).id)
        }
        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if let op = node.operator.as(BinaryOperatorExprSyntax.self),
           op.operator.text == "||",
           let left = node.leftOperand.as(FunctionCallExprSyntax.self),
           OSMacOSWidener.isOSMacOSCall(left),
           let right = node.rightOperand.as(FunctionCallExprSyntax.self),
           OSMacOSWidener.isOSCall(right, argument: "Linux") {
            skipIDs.insert(Syntax(left).id)
        }
        return .visitChildren
    }

    /// Compile-config conditions like `#if os(macOS) || os(Linux)` typically
    /// parse as `SequenceExprSyntax` (an unfolded chain of operands and
    /// operator tokens) rather than `InfixOperatorExprSyntax`. Scan the
    /// sequence for the `os(macOS) || os(Linux)` triple and skip the
    /// left-hand call so the widening pass doesn't re-wrap it.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count >= 3 else { return .visitChildren }
        for i in 0...(elements.count - 3) {
            if let left = elements[i].as(FunctionCallExprSyntax.self),
               OSMacOSWidener.isOSMacOSCall(left),
               let op = elements[i + 1].as(BinaryOperatorExprSyntax.self),
               op.operator.text == "||",
               let right = elements[i + 2].as(FunctionCallExprSyntax.self),
               OSMacOSWidener.isOSCall(right, argument: "Linux") {
                skipIDs.insert(Syntax(left).id)
            }
        }
        return .visitChildren
    }
}

private final class OSMacOSWidener: SyntaxRewriter {
    private let skipIDs: Set<SyntaxIdentifier>

    init(skipIDs: Set<SyntaxIdentifier>) {
        self.skipIDs = skipIDs
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        guard Self.isOSMacOSCall(node) else { return ExprSyntax(super.visit(node)) }
        if skipIDs.contains(Syntax(node).id) {
            return ExprSyntax(node)
        }
        // Widen. Preserve trivia so surrounding spaces and newlines survive.
        let replacement: ExprSyntax = "(os(macOS) || os(Linux))"
        return ExprSyntax(
            replacement
                .with(\.leadingTrivia, node.leadingTrivia)
                .with(\.trailingTrivia, node.trailingTrivia)
        )
    }

    fileprivate static func isOSMacOSCall(_ call: FunctionCallExprSyntax) -> Bool {
        isOSCall(call, argument: "macOS")
    }

    fileprivate static func isOSCall(_ call: FunctionCallExprSyntax, argument expected: String) -> Bool {
        guard let calledName = call.calledExpression.as(DeclReferenceExprSyntax.self),
              calledName.baseName.text == "os" else {
            return false
        }
        guard call.arguments.count == 1, let onlyArgument = call.arguments.first else {
            return false
        }
        if let identifier = onlyArgument.expression.as(DeclReferenceExprSyntax.self),
           identifier.baseName.text == expected {
            return true
        }
        return false
    }
}
