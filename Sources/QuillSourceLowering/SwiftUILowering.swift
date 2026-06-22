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
///   * Objective-C-only attribute removal (`@objc`, `@IBAction`, etc.)
///   * `#selector(x)` → `Selector("x")` for Linux builds without ObjC interop
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
        let foundational = FoundationLowering().lower(rewritten.description)
        return SwiftUIBodyComplexityLowering().lower(foundational)
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

// MARK: - SwiftUI body complexity lowering

/// Splits very large SwiftUI `body` builders into private `@ViewBuilder`
/// properties. This is a compile-time compatibility pass for real apps whose
/// macOS SwiftUI bodies type-check under Apple's toolchain but time out under
/// the Linux compatibility graph.
private struct SwiftUIBodyComplexityLowering {
    private static let marker = "_quillSplitBody"
    private static let bodyPattern = #"(?m)\bvar\s+body\s*:\s*some\s+View\s*\{"#
    private static let stackNames: Set<String> = [
        "Group",
        "HStack",
        "LazyHGrid",
        "LazyHStack",
        "LazyVGrid",
        "LazyVStack",
        "ScrollView",
        "VStack",
        "ZStack",
    ]

    func lower(_ source: String) -> String {
        guard !source.contains(Self.marker) else { return source }
        guard let bodyRegex = try? NSRegularExpression(pattern: Self.bodyPattern) else {
            return source
        }

        var lowered = source
        var searchLocation = 0
        var bodyID = 0

        while searchLocation < lowered.utf16.count {
            let searchRange = NSRange(location: searchLocation, length: lowered.utf16.count - searchLocation)
            guard let match = bodyRegex.firstMatch(in: lowered, range: searchRange),
                  let matchRange = Range(match.range, in: lowered) else {
                break
            }

            let openBrace = lowered.index(before: matchRange.upperBound)
            guard let closeBrace = Self.matchingDelimiter(
                in: lowered,
                open: openBrace,
                opening: "{",
                closing: "}"
            ) else {
                break
            }

            let bodyInnerStart = lowered.index(after: openBrace)
            let bodyInner = String(lowered[bodyInnerStart..<closeBrace])
            let memberIndent = Self.lineIndent(in: lowered, at: matchRange.lowerBound)

            if let split = Self.splitBody(bodyInner, bodyID: bodyID, memberIndent: memberIndent) {
                let bodyIndent = memberIndent + "    "
                let replacement = "{\n\(bodyIndent)\(split.rewrittenBody.trimmingCharacters(in: .whitespacesAndNewlines))\n\(memberIndent)}\n\n\(split.helpers)"
                let replacementStartUTF16 = lowered.utf16.distance(from: lowered.utf16.startIndex, to: openBrace.samePosition(in: lowered.utf16) ?? lowered.utf16.endIndex)
                lowered.replaceSubrange(openBrace...closeBrace, with: replacement)
                bodyID += 1
                searchLocation = replacementStartUTF16 + replacement.utf16.count
            } else {
                let nextIndex = lowered.index(after: closeBrace)
                searchLocation = lowered.utf16.distance(from: lowered.utf16.startIndex, to: nextIndex.samePosition(in: lowered.utf16) ?? lowered.utf16.endIndex)
            }
        }

        return lowered
    }

    private struct SplitBody {
        var rewrittenBody: String
        var helpers: String
    }

    private struct ItemRange {
        var range: Range<String.Index>
        var text: String
        var leadingIndent: String
    }

    private static func splitBody(_ body: String, bodyID: Int, memberIndent: String) -> SplitBody? {
        guard body.count >= 1_000 else { return nil }
        guard let call = firstStackCall(in: body),
              let closureRange = call.trailingClosureRange else {
            return nil
        }

        let closureContent = String(body[closureRange])
        let items = topLevelItems(in: closureContent)
        guard items.count >= 2, items.allSatisfy({ isExtractableBuilderItem($0.text) }) else {
            return nil
        }

        var rewrittenClosure = closureContent
        var helpers: [String] = []
        for (index, item) in items.enumerated().reversed() {
            let helperName = "\(marker)\(bodyID)Part\(index)"
            let replacement = "\(item.leadingIndent)\(helperName)"
            rewrittenClosure.replaceSubrange(item.range, with: replacement)
        }

        for (index, item) in items.enumerated() {
            let helperName = "\(marker)\(bodyID)Part\(index)"
            helpers.append(helper(name: helperName, item: item.text, memberIndent: memberIndent))
        }

        var rewrittenBody = body
        rewrittenBody.replaceSubrange(closureRange, with: rewrittenClosure)
        return SplitBody(rewrittenBody: rewrittenBody, helpers: helpers.joined(separator: "\n\n"))
    }

    private struct StackCall {
        var trailingClosureRange: Range<String.Index>?
    }

    private static func firstStackCall(in body: String) -> StackCall? {
        var cursor = body.startIndex
        while cursor < body.endIndex, body[cursor].isWhitespace {
            cursor = body.index(after: cursor)
        }

        let nameStart = cursor
        while cursor < body.endIndex, body[cursor].isLetter {
            cursor = body.index(after: cursor)
        }

        guard nameStart < cursor else { return nil }
        let name = String(body[nameStart..<cursor])
        guard stackNames.contains(name) else { return nil }

        while cursor < body.endIndex, body[cursor].isWhitespace {
            cursor = body.index(after: cursor)
        }

        if cursor < body.endIndex, body[cursor] == "(" {
            guard let closeParen = matchingDelimiter(
                in: body,
                open: cursor,
                opening: "(",
                closing: ")"
            ) else {
                return nil
            }
            cursor = body.index(after: closeParen)
            while cursor < body.endIndex, body[cursor].isWhitespace {
                cursor = body.index(after: cursor)
            }
        }

        guard cursor < body.endIndex, body[cursor] == "{" else { return nil }
        guard let closeBrace = matchingDelimiter(
            in: body,
            open: cursor,
            opening: "{",
            closing: "}"
        ) else {
            return nil
        }
        return StackCall(trailingClosureRange: body.index(after: cursor)..<closeBrace)
    }

    private static func topLevelItems(in closureContent: String) -> [ItemRange] {
        var items: [ItemRange] = []
        guard var itemStart = firstNonWhitespaceIndex(in: closureContent, from: closureContent.startIndex) else {
            return []
        }
        var cursor = itemStart
        var state = LexState()

        while cursor < closureContent.endIndex {
            let character = closureContent[cursor]
            state.consume(character, in: closureContent, at: cursor)

            if character == "\n",
               state.isTopLevel,
               let next = firstNonWhitespaceIndex(in: closureContent, from: closureContent.index(after: cursor)),
               shouldStartNewItem(afterNewlineAt: next, in: closureContent) {
                let itemRange = itemStart..<cursor
                appendItem(itemRange, from: closureContent, to: &items)
                itemStart = next
                cursor = next
                continue
            }

            cursor = closureContent.index(after: cursor)
        }

        appendItem(itemStart..<closureContent.endIndex, from: closureContent, to: &items)
        return items
    }

    private static func appendItem(
        _ range: Range<String.Index>,
        from source: String,
        to items: inout [ItemRange]
    ) {
        let text = String(source[range])
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.append(ItemRange(range: range, text: text, leadingIndent: leadingIndent(of: text)))
    }

    private static func shouldStartNewItem(afterNewlineAt index: String.Index, in source: String) -> Bool {
        guard index < source.endIndex else { return false }
        if source[index] == "." || source[index] == ")" || source[index] == "]" || source[index] == "}" {
            return false
        }

        let suffix = source[index...]
        for continuation in ["else", "catch", "while"] {
            if suffix.hasPrefix(continuation) {
                let end = source.index(index, offsetBy: continuation.count, limitedBy: source.endIndex) ?? source.endIndex
                if end == source.endIndex || !source[end].isIdentifierContinuation {
                    return false
                }
            }
        }
        return true
    }

    private static func isExtractableBuilderItem(_ item: String) -> Bool {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for forbidden in ["let ", "var ", "return ", "guard ", "throw ", "defer "] {
            if trimmed.hasPrefix(forbidden) { return false }
        }
        return true
    }

    private static func helper(name: String, item: String, memberIndent: String) -> String {
        let bodyIndent = memberIndent + "    "
        let normalized = stripCommonIndent(item.trimmingCharacters(in: .whitespacesAndNewlines))
        let indented = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "\(bodyIndent)\($0)" }
            .joined(separator: "\n")

        return """
        \(memberIndent)@ViewBuilder
        \(memberIndent)private var \(name): some View {
        \(indented)
        \(memberIndent)}
        """
    }

    private static func stripCommonIndent(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let nonEmptyIndents = lines.compactMap { line -> Int? in
            guard line.contains(where: { !$0.isWhitespace }) else { return nil }
            return line.prefix { $0 == " " || $0 == "\t" }.count
        }
        guard let common = nonEmptyIndents.min(), common > 0 else { return text }
        return lines
            .map { line in
                guard line.count >= common else { return line }
                let cutoff = line.index(line.startIndex, offsetBy: common)
                return String(line[cutoff...])
            }
            .joined(separator: "\n")
    }

    private static func firstNonWhitespaceIndex(
        in source: String,
        from start: String.Index
    ) -> String.Index? {
        var index = start
        while index < source.endIndex {
            if !source[index].isWhitespace { return index }
            index = source.index(after: index)
        }
        return nil
    }

    private static func leadingIndent(of text: String) -> String {
        guard let newline = text.lastIndex(of: "\n") else {
            return String(text.prefix { $0 == " " || $0 == "\t" })
        }
        let afterNewline = text.index(after: newline)
        return String(text[afterNewline...].prefix { $0 == " " || $0 == "\t" })
    }

    private static func lineIndent(in source: String, at index: String.Index) -> String {
        let lineStart = source[..<index].lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
        return String(source[lineStart..<index].prefix { $0 == " " || $0 == "\t" })
    }

    private static func matchingDelimiter(
        in source: String,
        open: String.Index,
        opening: Character,
        closing: Character
    ) -> String.Index? {
        var state = LexState()
        var depth = 0
        var cursor = open

        while cursor < source.endIndex {
            let character = source[cursor]
            if state.isCode {
                if character == opening {
                    depth += 1
                } else if character == closing {
                    depth -= 1
                    if depth == 0 { return cursor }
                }
            }
            state.consume(character, in: source, at: cursor)
            cursor = source.index(after: cursor)
        }

        return nil
    }

    private struct LexState {
        var parenDepth = 0
        var braceDepth = 0
        var bracketDepth = 0
        var isInLineComment = false
        var isInBlockComment = false
        var isInString = false
        var isEscaped = false

        var isTopLevel: Bool {
            isCode && parenDepth == 0 && braceDepth == 0 && bracketDepth == 0
        }

        var isCode: Bool {
            !isInLineComment && !isInBlockComment && !isInString
        }

        mutating func consume(_ character: Character, in source: String, at index: String.Index) {
            if isInLineComment {
                if character == "\n" { isInLineComment = false }
                return
            }

            if isInBlockComment {
                if character == "/", previousCharacter(in: source, at: index) == "*" {
                    isInBlockComment = false
                }
                return
            }

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                return
            }

            if character == "/", nextCharacter(in: source, at: index) == "/" {
                isInLineComment = true
                return
            }

            if character == "/", nextCharacter(in: source, at: index) == "*" {
                isInBlockComment = true
                return
            }

            if character == "\"" {
                isInString = true
                return
            }

            switch character {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            default:
                break
            }
        }

        private func previousCharacter(in source: String, at index: String.Index) -> Character? {
            guard index > source.startIndex else { return nil }
            return source[source.index(before: index)]
        }

        private func nextCharacter(in source: String, at index: String.Index) -> Character? {
            let next = source.index(after: index)
            guard next < source.endIndex else { return nil }
            return source[next]
        }
    }
}

// MARK: - Rewriter

private final class SwiftUIRewriter: SyntaxRewriter {
    /// Attribute names removed wholesale whether they appear on a declaration
    /// or wrapped around an inline type expression.
    private static let strippedAttributeNames: Set<String> = [
        "main", "MainActor", "Observable",
        "objc", "objcMembers",
        "IBAction", "IBOutlet", "IBInspectable", "IBDesignable",
        "NSManaged", "GKInspectable", "NSApplicationMain",
    ]

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
        let filtered: AttributeListSyntax = recursed.filter { element in
            guard case .attribute(let attr) = element else { return true }
            return !Self.strippedAttributeNames.contains(attr.attributeName.trimmedDescription)
        }
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

    /// Rewrite `#selector(x)` into QuillFoundation's plain selector token.
    /// Swift on Linux has no Objective-C selector expression support, but the
    /// source only needs a stable opaque value that the shim APIs can accept.
    override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
        guard let macro = recursed.as(MacroExpansionExprSyntax.self),
              macro.macroName.text == "selector" else {
            return recursed
        }
        let key = Self.selectorKey(from: macro.arguments.trimmedDescription)
        let escaped = key
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        var replacement = ExprSyntax("Selector(\"\(raw: escaped)\")")
        replacement.leadingTrivia = node.leadingTrivia
        replacement.trailingTrivia = node.trailingTrivia
        return replacement
    }

    /// Make identifiable collection `ForEach` calls explicit for the Linux
    /// compatibility toolchain. Apple's SwiftUI reliably infers
    /// `ForEach(collection)` when elements are `Identifiable`; the shim stack can
    /// lose that overload in large lowered builders and fall back to the
    /// `Range<Int>` initializer. `id: \.id` is source-equivalent for valid
    /// SwiftUI identifiable collections and keeps range forms untouched.
    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
        guard let call = recursed.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "ForEach",
              call.arguments.count == 1,
              let firstArgument = call.arguments.first,
              firstArgument.label == nil,
              call.trailingClosure != nil else {
            return recursed
        }

        let dataExpression = firstArgument.expression.trimmedDescription
        guard Self.shouldLowerIdentifiableForEachDataExpression(dataExpression) else {
            return recursed
        }

        let trailingClosure = call.trailingClosure?.description ?? ""
        let trailingClosureSeparator = trailingClosure.first?.isWhitespace == true ? "" : " "
        let additionalTrailingClosures = call.additionalTrailingClosures.description
        var replacement = ExprSyntax(
            "\(raw: call.calledExpression.trimmedDescription)(\(raw: dataExpression), id: \\.id)\(raw: trailingClosureSeparator)\(raw: trailingClosure)\(raw: additionalTrailingClosures)"
        )
        replacement.leadingTrivia = node.leadingTrivia
        replacement.trailingTrivia = node.trailingTrivia
        return replacement
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

    /// Normalize a selector expression into a stable key by dropping any leading
    /// type qualifier (`Type.method(_:)` and `method(_:)` become the same key).
    private static func selectorKey(from arguments: String) -> String {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualifierPath = trimmed.prefix { $0 != "(" }
        guard let lastDot = qualifierPath.range(of: ".", options: .backwards) else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: lastDot.lowerBound)...])
    }

    private static func shouldLowerIdentifiableForEachDataExpression(_ expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("..<") || trimmed.contains("...") { return false }
        if trimmed.hasSuffix(".indices") { return false }
        if trimmed.first?.isNumber == true { return false }
        return true
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

private extension Character {
    var isIdentifierContinuation: Bool {
        self == "_" || isLetter || isNumber
    }
}
