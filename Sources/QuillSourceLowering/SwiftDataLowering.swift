import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Lowers SwiftData-only Swift syntax into QuillData-compatible Swift.
///
/// Mirrors the regex transformations in
/// `scripts/lower-swiftdata-for-quilldata.sh` but uses a structured
/// SwiftSyntax rewriter so multi-line declarations, attribute argument
/// lists, and conditional compilation blocks survive correctly. The
/// shell script remains the integration entry point used by existing
/// generated-source profiles; this Swift implementation is the
/// long-lived ground truth that the script and the upcoming
/// `quill-source-lower` CLI both delegate to.
///
/// Coverage of the three core transformations:
///   * `@Model` → `PersistentModel` inheritance
///   * `@Transient var X` → `var X`
///   * `#Predicate<T> { … }` → `#QuillPredicate<T> { … }`
///
/// The fourth transformation in the shell script — pruning
/// `self.relationship = relationship` from `init` bodies when the
/// relationship is not actually an init parameter — is intentionally
/// out of scope for this first SwiftSyntax slice and is tracked as a
/// follow-up. The shell script remains the source of truth for that
/// rewrite until the SwiftSyntax implementation catches up.
public struct SwiftDataLowering {
    public init() {}

    /// Lowers a single Swift source string in memory.
    public func lower(_ source: String) -> String {
        let tree = Parser.parse(source: source)
        let rewriter = SwiftDataRewriter()
        let rewritten = rewriter.rewrite(tree)
        return rewritten.description
    }

    /// Lowers every `.swift` file under `sourceDir` into `outputDir`,
    /// mirroring directory layout. Non-Swift files are copied verbatim.
    public func lowerDirectory(
        sourceDir: URL,
        outputDir: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: outputDir.path) {
            throw LoweringError.outputAlreadyExists(outputDir)
        }
        try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Resolve symlinks so prefix-stripping works on macOS where the
        // FileManager.enumerator can return `/private/var/...` paths while
        // a caller-supplied URL still says `/var/...`.
        let normalizedSource = sourceDir.resolvingSymlinksInPath()
        let normalizedOutput = outputDir.resolvingSymlinksInPath()

        guard let enumerator = fileManager.enumerator(
            at: normalizedSource,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let sourcePathWithSlash = normalizedSource.path.hasSuffix("/")
            ? normalizedSource.path
            : normalizedSource.path + "/"

        for case let fileURL as URL in enumerator {
            let resolved = fileURL.resolvingSymlinksInPath()
            let resourceValues = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            guard resolved.path.hasPrefix(sourcePathWithSlash) else { continue }
            let relativePath = String(resolved.path.dropFirst(sourcePathWithSlash.count))
            let destination = normalizedOutput.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if resolved.pathExtension == "swift" {
                let source = try String(contentsOf: resolved, encoding: .utf8)
                let lowered = lower(source)
                try lowered.write(to: destination, atomically: true, encoding: .utf8)
            } else {
                try fileManager.copyItem(at: resolved, to: destination)
            }
        }
    }

    public enum LoweringError: Error, CustomStringConvertible {
        case outputAlreadyExists(URL)

        public var description: String {
            switch self {
            case .outputAlreadyExists(let url):
                return "Output directory already exists: \(url.path)"
            }
        }
    }
}

// MARK: - Rewriter

final class SwiftDataRewriter: SyntaxRewriter {
    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        // Recurse first so any nested @Transient / #Predicate are already lowered
        // by the time we look at the class-level @Model attribute.
        let recursed: ClassDeclSyntax
        if let visited = super.visit(node).as(ClassDeclSyntax.self) {
            recursed = visited
        } else {
            recursed = node
        }

        guard let modelAttribute = recursed.attributes.first(where: { Self.isAttribute($0, named: "Model") }) else {
            return DeclSyntax(recursed)
        }

        var updated = recursed
        updated.attributes = recursed.attributes.filter { !Self.isAttribute($0, named: "Model") }

        // Replace (don't prepend) the next token's leading trivia with whatever
        // led the removed attribute. The next token already carries the trivia
        // between @Model and itself; replacing avoids stacking blank lines.
        if updated.attributes.isEmpty {
            updated = Self.setLeadingTrivia(modelAttribute.leadingTrivia, on: updated)
        }

        Self.addPersistentModel(to: &updated)
        Self.injectRelationshipMaintenance(into: &updated)
        return DeclSyntax(updated)
    }

    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        let recursed: VariableDeclSyntax
        if let visited = super.visit(node).as(VariableDeclSyntax.self) {
            recursed = visited
        } else {
            recursed = node
        }

        guard let transientAttribute = recursed.attributes.first(where: { Self.isAttribute($0, named: "Transient") }) else {
            return DeclSyntax(recursed)
        }

        var updated = recursed
        updated.attributes = recursed.attributes.filter { !Self.isAttribute($0, named: "Transient") }

        if updated.attributes.isEmpty {
            updated = Self.setLeadingTrivia(transientAttribute.leadingTrivia, onVariable: updated)
        }

        return DeclSyntax(updated)
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        let recursed: MacroExpansionExprSyntax
        if let visited = super.visit(node).as(MacroExpansionExprSyntax.self) {
            recursed = visited
        } else {
            recursed = node
        }

        guard recursed.macroName.text == "Predicate" else {
            return ExprSyntax(recursed)
        }

        var updated = recursed
        let originalToken = recursed.macroName
        updated.macroName = .identifier(
            "QuillPredicate",
            leadingTrivia: originalToken.leadingTrivia,
            trailingTrivia: originalToken.trailingTrivia
        )
        return ExprSyntax(updated)
    }

    // MARK: helpers

    private static func isAttribute(_ element: AttributeListSyntax.Element, named name: String) -> Bool {
        guard case let .attribute(attribute) = element else { return false }
        let typed = attribute.attributeName.trimmedDescription
        return typed == name
    }

    private static func addPersistentModel(to classDecl: inout ClassDeclSyntax) {
        if var clause = classDecl.inheritanceClause {
            let alreadyHas = clause.inheritedTypes.contains { entry in
                entry.type.trimmedDescription == "PersistentModel"
            }
            if alreadyHas { return }

            // Append `, PersistentModel` to the existing list. Strip stale
            // trailing trivia from the last type so the comma attaches tightly.
            // Combine any whitespace that was floating between the last type
            // and the brace onto PersistentModel's trailing trivia so we don't
            // end up with `PersistentModel{` when the brace's leading trivia
            // was empty.
            var types = clause.inheritedTypes
            var carriedTrailing: Trivia = []
            if let lastIndex = types.indices.last {
                var last = types[lastIndex]
                carriedTrailing = last.type.trailingTrivia
                last.type = last.type.with(\.trailingTrivia, [])
                last.trailingComma = .commaToken(trailingTrivia: .space)
                types[lastIndex] = last
            }

            var memberBlock = classDecl.memberBlock
            let braceLeading = memberBlock.leftBrace.leadingTrivia
            memberBlock.leftBrace = memberBlock.leftBrace.with(\.leadingTrivia, [])
            classDecl.memberBlock = memberBlock

            let combinedTail = carriedTrailing + braceLeading
            let trailingForPersistentModel: Trivia = combinedTail.containsNewlineOrSpace
                ? combinedTail
                : .space

            let persistentModelEntry = InheritedTypeSyntax(
                type: TypeSyntax(
                    IdentifierTypeSyntax(
                        name: .identifier("PersistentModel", trailingTrivia: trailingForPersistentModel)
                    )
                )
            )
            types.append(persistentModelEntry)
            clause.inheritedTypes = types
            classDecl.inheritanceClause = clause
            return
        }

        // No existing inheritance clause — create one. Normalize surrounding
        // trivia so we don't end up with `Foo : PersistentModel{` (extra space
        // before colon, missing space before brace) or `Foo:PersistentModel`.
        let nameTrailing = classDecl.name.trailingTrivia
        classDecl.name = classDecl.name.with(\.trailingTrivia, [])

        var memberBlock = classDecl.memberBlock
        let braceLeading = memberBlock.leftBrace.leadingTrivia
        memberBlock.leftBrace = memberBlock.leftBrace.with(\.leadingTrivia, [])
        classDecl.memberBlock = memberBlock

        // Build PersistentModel with an explicit trailing space so the brace
        // separates cleanly. Preserve any newline that was on the original
        // class-name trailing or brace leading trivia so multi-line layouts
        // survive. (Common case: both were just a single space — output is one
        // space between PersistentModel and `{`.)
        let combinedTail = nameTrailing + braceLeading
        let trailingForPersistentModel: Trivia
        if combinedTail.containsNewlineOrSpace {
            trailingForPersistentModel = combinedTail
        } else {
            trailingForPersistentModel = .space
        }

        let entry = InheritedTypeSyntax(
            type: TypeSyntax(
                IdentifierTypeSyntax(
                    name: .identifier("PersistentModel", trailingTrivia: trailingForPersistentModel)
                )
            )
        )

        classDecl.inheritanceClause = InheritanceClauseSyntax(
            colon: .colonToken(trailingTrivia: .space),
            inheritedTypes: InheritedTypeListSyntax([entry])
        )
    }

    private static func injectRelationshipMaintenance(into classDecl: inout ClassDeclSyntax) {
        var members = classDecl.memberBlock.members
        var relationships: [RelationshipProperty] = []

        for index in members.indices {
            var member = members[index]
            guard var variable = member.decl.as(VariableDeclSyntax.self),
                  let relationship = relationshipProperty(
                    in: variable,
                    enclosingClass: classDecl.name.text,
                    memberIndentation: indentation(from: member.decl.leadingTrivia)
                  ) else {
                continue
            }

            relationships.append(relationship)
            variable = addRelationshipObserver(to: variable, for: relationship)
            member.decl = DeclSyntax(variable)
            members[index] = member
        }

        guard !relationships.isEmpty,
              !hasQuillRelationshipRegistration(in: members) else {
            var memberBlock = classDecl.memberBlock
            memberBlock.members = members
            classDecl.memberBlock = memberBlock
            return
        }

        let classIndentation = relationships.first?.memberIndentation
            ?? indentation(from: members.first?.decl.leadingTrivia ?? classDecl.memberBlock.leftBrace.trailingTrivia)
        let registration = registrationMember(
            for: classDecl.name.text,
            relationships: relationships,
            memberIndentation: classIndentation
        )
        members.append(registration)

        var memberBlock = classDecl.memberBlock
        memberBlock.members = members
        classDecl.memberBlock = memberBlock
    }

    private static func relationshipProperty(
        in variable: VariableDeclSyntax,
        enclosingClass: String,
        memberIndentation: String
    ) -> RelationshipProperty? {
        guard variable.bindingSpecifier.text == "var",
              !variable.modifiers.contains(where: { modifier in
                  let name = modifier.name.text
                  return name == "static" || name == "class"
              }),
              let relationshipAttribute = variable.attributes.first(where: { isAttribute($0, named: "Relationship") }),
              variable.bindings.count == 1,
              let binding = variable.bindings.first,
              binding.accessorBlock == nil,
              let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type,
              let element = relationshipElementType(from: type) else {
            return nil
        }

        return RelationshipProperty(
            enclosingClass: enclosingClass,
            propertyName: identifierPattern.identifier.text,
            relatedType: element.typeName,
            isOptionalToOne: element.isOptionalToOne,
            isToMany: element.isToMany,
            hasInitializer: binding.initializer != nil,
            inverse: inverseKeyPath(from: relationshipAttribute),
            memberIndentation: memberIndentation
        )
    }

    private static func addRelationshipObserver(
        to variable: VariableDeclSyntax,
        for relationship: RelationshipProperty
    ) -> VariableDeclSyntax {
        var updated = variable
        guard let bindingIndex = updated.bindings.indices.first else { return updated }

        var binding = updated.bindings[bindingIndex]
        if relationship.isOptionalToOne && !relationship.hasInitializer {
            binding.initializer = nilInitializerClause()
        }
        binding.accessorBlock = relationshipObserverBlock(for: relationship)
        updated.bindings[bindingIndex] = binding
        return updated
    }

    private static func relationshipElementType(from type: TypeSyntax) -> RelationshipElementType? {
        let description = type.trimmedDescription

        if description.hasPrefix("["),
           description.hasSuffix("]") {
            let element = String(description.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !element.isEmpty else { return nil }
            return RelationshipElementType(typeName: element, isOptionalToOne: false, isToMany: true)
        }

        if description.hasPrefix("Array<"),
           description.hasSuffix(">") {
            let element = String(description.dropFirst("Array<".count).dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !element.isEmpty else { return nil }
            return RelationshipElementType(typeName: element, isOptionalToOne: false, isToMany: true)
        }

        if description.hasPrefix("Optional<"),
           description.hasSuffix(">") {
            let element = String(description.dropFirst("Optional<".count).dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !element.isEmpty else { return nil }
            return RelationshipElementType(typeName: element, isOptionalToOne: true, isToMany: false)
        }

        if description.hasSuffix("?") || description.hasSuffix("!") {
            let element = String(description.dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !element.isEmpty else { return nil }
            return RelationshipElementType(typeName: element, isOptionalToOne: true, isToMany: false)
        }

        return RelationshipElementType(typeName: description, isOptionalToOne: false, isToMany: false)
    }

    private static func inverseKeyPath(from element: AttributeListSyntax.Element) -> InverseKeyPath? {
        guard case let .attribute(attribute) = element else { return nil }
        return inverseKeyPath(from: attribute)
    }

    private static func inverseKeyPath(from attribute: AttributeSyntax) -> InverseKeyPath? {
        let source = attribute.description
        guard let inverseRange = source.range(of: "inverse:") else { return nil }

        let tail = source[inverseRange.upperBound...]
        var keyPath = ""
        var nestingDepth = 0
        for character in tail {
            switch character {
            case "(", "[", "<":
                nestingDepth += 1
                keyPath.append(character)
            case ")", "]", ">":
                if nestingDepth == 0 {
                    return parseInverseKeyPath(keyPath)
                }
                nestingDepth -= 1
                keyPath.append(character)
            case "," where nestingDepth == 0:
                return parseInverseKeyPath(keyPath)
            default:
                keyPath.append(character)
            }
        }

        return parseInverseKeyPath(keyPath)
    }

    private static func parseInverseKeyPath(_ rawKeyPath: String) -> InverseKeyPath? {
        let keyPath = rawKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyPath.hasPrefix("\\") else { return nil }

        let body = keyPath.dropFirst()
        guard let dotIndex = body.lastIndex(of: ".") else { return nil }

        let typeName = body[..<dotIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let propertyName = body[body.index(after: dotIndex)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !typeName.isEmpty, !propertyName.isEmpty else { return nil }
        return InverseKeyPath(typeName: String(typeName), propertyName: String(propertyName), keyPath: keyPath)
    }

    private static func relationshipObserverBlock(for relationship: RelationshipProperty) -> AccessorBlockSyntax {
        let indentation = relationship.memberIndentation
        let source = """
        var __quillRelationshipObserver: Any {
        \(indentation)    didSet {
        \(indentation)        _ = \(relationship.enclosingClass).__quillRelationshipsRegistered
        \(indentation)        _ = \(relationship.relatedType).__quillRelationshipsRegistered
        \(indentation)        QuillRelationships.relationshipDidSet(self, ObjectIdentifier(\(relationship.enclosingClass).self), "\(relationship.propertyName)", oldValue: oldValue as Any?, newValue: \(relationship.propertyName) as Any?)
        \(indentation)    }
        \(indentation)}
        """
        guard var accessorBlock = parseVariableDecl(source).bindings.first?.accessorBlock else {
            preconditionFailure("Failed to parse relationship observer accessor")
        }
        accessorBlock.leftBrace = accessorBlock.leftBrace.with(\.leadingTrivia, .space)
        return accessorBlock
    }

    private static func nilInitializerClause() -> InitializerClauseSyntax {
        let source = "var __quillRelationshipNilDefault: Any? = nil"
        guard var initializer = parseVariableDecl(source).bindings.first?.initializer else {
            preconditionFailure("Failed to parse relationship nil initializer")
        }
        initializer.equal = initializer.equal
            .with(\.leadingTrivia, .space)
            .with(\.trailingTrivia, .space)
        return initializer
    }

    private static func registrationMember(
        for className: String,
        relationships: [RelationshipProperty],
        memberIndentation: String
    ) -> MemberBlockItemSyntax {
        let registerCalls = relationships
            .filter { $0.isToMany }
            .compactMap { relationship -> String? in
                guard let inverse = relationship.inverse else { return nil }
                return """
                \(memberIndentation)    QuillRelationships.registerInverse(
                \(memberIndentation)        parentType: \(className).self, toManyProperty: "\(relationship.propertyName)", toMany: \\\(className).\(relationship.propertyName),
                \(memberIndentation)        childType: \(inverse.typeName).self, toOneProperty: "\(inverse.propertyName)", toOne: \(inverse.keyPath)
                \(memberIndentation)    )
                """
            }
            .joined(separator: "\n")

        let body = registerCalls.isEmpty ? "" : "\(registerCalls)\n"
        let source = """
        static let __quillRelationshipsRegistered: Void = {
        \(body)\(memberIndentation)}()
        """
        var declaration = parseVariableDecl(source)
        declaration = declaration.with(\.leadingTrivia, trivia(newlines: 2, indentation: memberIndentation))
        declaration = declaration.with(\.trailingTrivia, .newline)
        return MemberBlockItemSyntax(decl: DeclSyntax(declaration))
    }

    private static func hasQuillRelationshipRegistration(in members: MemberBlockItemListSyntax) -> Bool {
        members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return false }
            return variable.bindings.contains { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "__quillRelationshipsRegistered"
            }
        }
    }

    private static func parseVariableDecl(_ source: String) -> VariableDeclSyntax {
        guard let variable = DeclSyntax(stringLiteral: source).as(VariableDeclSyntax.self) else {
            preconditionFailure("Failed to parse variable declaration: \(source)")
        }
        return variable
    }

    private static func indentation(from trivia: Trivia) -> String {
        var indentation = ""
        var sawNewline = false

        for piece in trivia {
            switch piece {
            case .newlines, .carriageReturns, .carriageReturnLineFeeds:
                sawNewline = true
                indentation = ""
            case .spaces(let count) where sawNewline:
                indentation += String(repeating: " ", count: count)
            case .tabs(let count) where sawNewline:
                indentation += String(repeating: "\t", count: count)
            default:
                break
            }
        }

        return indentation.isEmpty ? "    " : indentation
    }

    private static func trivia(newlines: Int, indentation: String) -> Trivia {
        var pieces: [TriviaPiece] = [.newlines(newlines)]
        var spaceCount = 0
        var tabCount = 0

        func flushSpaces() {
            if spaceCount > 0 {
                pieces.append(.spaces(spaceCount))
                spaceCount = 0
            }
        }

        func flushTabs() {
            if tabCount > 0 {
                pieces.append(.tabs(tabCount))
                tabCount = 0
            }
        }

        for character in indentation {
            if character == "\t" {
                flushSpaces()
                tabCount += 1
            } else {
                flushTabs()
                spaceCount += 1
            }
        }
        flushSpaces()
        flushTabs()

        return Trivia(pieces: pieces)
    }

    private static func setLeadingTrivia(_ trivia: Trivia, on classDecl: ClassDeclSyntax) -> ClassDeclSyntax {
        var copy = classDecl
        if let firstModifier = copy.modifiers.first {
            var modifiers = copy.modifiers
            modifiers[modifiers.startIndex] = firstModifier.with(\.leadingTrivia, trivia)
            copy.modifiers = modifiers
        } else {
            copy.classKeyword = copy.classKeyword.with(\.leadingTrivia, trivia)
        }
        return copy
    }

    private static func setLeadingTrivia(_ trivia: Trivia, onVariable varDecl: VariableDeclSyntax) -> VariableDeclSyntax {
        var copy = varDecl
        if let firstModifier = copy.modifiers.first {
            var modifiers = copy.modifiers
            modifiers[modifiers.startIndex] = firstModifier.with(\.leadingTrivia, trivia)
            copy.modifiers = modifiers
        } else {
            copy.bindingSpecifier = copy.bindingSpecifier.with(\.leadingTrivia, trivia)
        }
        return copy
    }
}

private struct RelationshipElementType {
    let typeName: String
    let isOptionalToOne: Bool
    let isToMany: Bool
}

private struct InverseKeyPath {
    let typeName: String
    let propertyName: String
    let keyPath: String
}

private struct RelationshipProperty {
    let enclosingClass: String
    let propertyName: String
    let relatedType: String
    let isOptionalToOne: Bool
    let isToMany: Bool
    let hasInitializer: Bool
    let inverse: InverseKeyPath?
    let memberIndentation: String
}

extension Trivia {
    var containsNewlineOrSpace: Bool {
        contains { piece in
            switch piece {
            case .spaces, .tabs, .newlines, .carriageReturns, .carriageReturnLineFeeds:
                return true
            default:
                return false
            }
        }
    }
}
