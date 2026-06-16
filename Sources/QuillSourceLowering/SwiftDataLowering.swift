import Foundation
import SwiftParser
import SwiftSyntax

/// Lowers SwiftData-only Swift syntax into QuillData-compatible Swift.
///
/// Mirrors the regex transformations in
/// `scripts/lower-swiftdata-for-quilldata.sh` but uses a structured
/// SwiftSyntax rewriter so multi-line declarations, attribute argument
/// lists, and conditional compilation blocks survive correctly. The
/// generated-source profiles now invoke the `quill-source-lower` CLI so this
/// Swift implementation is the long-lived ground truth.
///
/// Coverage of the three core transformations:
///   * `@Model` → `PersistentModel` inheritance
///   * `@Transient var X` → `var X`
///   * `#Predicate<T> { … }` → `#QuillPredicate<T> { … }`
///
/// Relationship properties also get a `didSet` hook that forwards to
/// `QuillRelationships`, plus generated inverse registration for
/// non-optional to-many relationships that declare an `inverse:` key path.
public struct SwiftDataLowering {
    public init() {}

    /// Lowers a single Swift source string in memory.
    public func lower(_ source: String) -> String {
        let registrations = SwiftDataRelationshipScanner.relationshipRegistrations(in: [source])
        return lower(source, registrations: registrations)
    }

    private func lower(_ source: String, registrations: Set<RelationshipRegistration>) -> String {
        let tree = Parser.parse(source: source)
        let rewriter = SwiftDataRewriter(knownRegistrations: registrations)
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

        var files: [(source: URL, destination: URL)] = []
        for case let fileURL as URL in enumerator {
            let resolved = fileURL.resolvingSymlinksInPath()
            let resourceValues = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            guard resolved.path.hasPrefix(sourcePathWithSlash) else { continue }
            let relativePath = String(resolved.path.dropFirst(sourcePathWithSlash.count))
            let destination = normalizedOutput.appendingPathComponent(relativePath)
            files.append((resolved, destination))
        }

        let swiftSources = try files.compactMap { file -> String? in
            guard file.source.pathExtension == "swift" else { return nil }
            return try String(contentsOf: file.source, encoding: .utf8)
        }
        let registrations = SwiftDataRelationshipScanner.relationshipRegistrations(in: swiftSources)

        for file in files {
            let resolved = file.source
            let destination = file.destination
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if resolved.pathExtension == "swift" {
                let source = try String(contentsOf: resolved, encoding: .utf8)
                let lowered = lower(source, registrations: registrations)
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

// MARK: - Relationship analysis

private struct RelationshipRegistration: Hashable {
    let parentType: String
    let toManyProperty: String
    let childType: String
    let toOneProperty: String
}

private struct RelationshipProperty: Hashable {
    let className: String
    let name: String
    let valueKind: RelationshipValueKind
    let inverse: RelationshipInverse?
}

private struct RelationshipInverse: Hashable {
    let rootType: String
    let property: String
}

private enum RelationshipValueKind: Hashable {
    case toMany(elementType: String, isOptional: Bool)
    case toOne(type: String, isOptional: Bool)
    case unsupported
}

private final class SwiftDataRelationshipScanner: SyntaxVisitor {
    private var properties: [RelationshipProperty] = []

    static func relationshipRegistrations(in sources: [String]) -> Set<RelationshipRegistration> {
        let scanner = SwiftDataRelationshipScanner(viewMode: .sourceAccurate)
        for source in sources {
            scanner.walk(Parser.parse(source: source))
        }
        return registrations(from: scanner.properties)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        properties.append(contentsOf: Self.relationshipProperties(in: node))
        return .visitChildren
    }

    static func relationshipProperties(in classDecl: ClassDeclSyntax) -> [RelationshipProperty] {
        let className = classDecl.name.text
        var properties: [RelationshipProperty] = []

        for member in classDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  let relationshipAttribute = relationshipAttribute(in: variable.attributes)
            else {
                continue
            }

            let inverse = relationshipInverse(from: relationshipAttribute)
            for binding in variable.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                properties.append(
                    RelationshipProperty(
                        className: className,
                        name: identifier.identifier.text,
                        valueKind: relationshipValueKind(from: binding.typeAnnotation?.type),
                        inverse: inverse
                    )
                )
            }
        }

        return properties
    }

    private static func registrations(from properties: [RelationshipProperty]) -> Set<RelationshipRegistration> {
        var registrations = Set<RelationshipRegistration>()
        let byQualifiedName = Dictionary(
            properties.map { ("\($0.className).\($0.name)", $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for property in properties {
            guard let inverse = property.inverse else { continue }

            switch property.valueKind {
            case .toMany(let childType, false):
                registrations.insert(
                    RelationshipRegistration(
                        parentType: property.className,
                        toManyProperty: property.name,
                        childType: inverse.rootType.isEmpty ? childType : inverse.rootType,
                        toOneProperty: inverse.property
                    )
                )

            case .toOne:
                guard let inverseProperty = byQualifiedName["\(inverse.rootType).\(inverse.property)"],
                      case .toMany(let childType, false) = inverseProperty.valueKind,
                      childType == property.className
                else {
                    continue
                }
                registrations.insert(
                    RelationshipRegistration(
                        parentType: inverse.rootType,
                        toManyProperty: inverse.property,
                        childType: property.className,
                        toOneProperty: property.name
                    )
                )

            case .toMany, .unsupported:
                continue
            }
        }

        return registrations
    }

    static func relationshipAttribute(in attributes: AttributeListSyntax) -> AttributeSyntax? {
        attributes.compactMap { element -> AttributeSyntax? in
            guard case .attribute(let attribute) = element,
                  attribute.attributeName.trimmedDescription == "Relationship"
            else {
                return nil
            }
            return attribute
        }.first
    }

    private static func relationshipInverse(from attribute: AttributeSyntax) -> RelationshipInverse? {
        guard case .argumentList(let arguments) = attribute.arguments else {
            return nil
        }

        for argument in arguments where argument.label?.text == "inverse" {
            guard let keyPath = argument.expression.as(KeyPathExprSyntax.self),
                  let propertyComponent = keyPath.components.compactMap({ component -> KeyPathPropertyComponentSyntax? in
                      guard case .property(let property) = component.component else { return nil }
                      return property
                  }).first
            else {
                return nil
            }

            return RelationshipInverse(
                rootType: keyPath.root?.trimmedDescription ?? "",
                property: propertyComponent.declName.baseName.text
            )
        }

        return nil
    }

    private static func relationshipValueKind(from type: TypeSyntax?) -> RelationshipValueKind {
        guard let type else { return .unsupported }
        return relationshipValueKind(fromTypeText: type.trimmedDescription)
    }

    private static func relationshipValueKind(fromTypeText rawText: String) -> RelationshipValueKind {
        let text = rawText.filter { !$0.isWhitespace }
        return relationshipValueKind(fromNormalizedTypeText: text, isOptional: false)
    }

    private static func relationshipValueKind(
        fromNormalizedTypeText text: String,
        isOptional: Bool
    ) -> RelationshipValueKind {
        if text.hasSuffix("?") || text.hasSuffix("!") {
            return relationshipValueKind(
                fromNormalizedTypeText: String(text.dropLast()),
                isOptional: true
            )
        }

        if text.hasPrefix("Optional<"), text.hasSuffix(">") {
            let inner = String(text.dropFirst("Optional<".count).dropLast())
            return relationshipValueKind(fromNormalizedTypeText: inner, isOptional: true)
        }

        if text.hasPrefix("["), text.hasSuffix("]") {
            let element = String(text.dropFirst().dropLast())
            return .toMany(elementType: element, isOptional: isOptional)
        }

        if text.hasPrefix("Array<"), text.hasSuffix(">") {
            let element = String(text.dropFirst("Array<".count).dropLast())
            return .toMany(elementType: element, isOptional: isOptional)
        }

        return text.isEmpty ? .unsupported : .toOne(type: text, isOptional: isOptional)
    }
}

// MARK: - Rewriter

private final class SwiftDataRewriter: SyntaxRewriter {
    private let knownRegistrations: Set<RelationshipRegistration>
    private var classStack: [ClassRelationshipContext] = []

    init(knownRegistrations: Set<RelationshipRegistration>) {
        self.knownRegistrations = knownRegistrations
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        let className = node.name.text
        let relationships = SwiftDataRelationshipScanner.relationshipProperties(in: node)
        let registrations = knownRegistrations.filter {
            $0.parentType == className || $0.childType == className
        }.sorted {
            ($0.parentType, $0.toManyProperty, $0.childType, $0.toOneProperty)
                < ($1.parentType, $1.toManyProperty, $1.childType, $1.toOneProperty)
        }
        classStack.append(
            ClassRelationshipContext(
                className: className,
                relationships: relationships,
                registrations: registrations
            )
        )
        defer { classStack.removeLast() }

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
        Self.addRelationshipRegistrationMemberIfNeeded(to: &updated, registrations: registrations)
        return DeclSyntax(updated)
    }

    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        let recursed: VariableDeclSyntax
        if let visited = super.visit(node).as(VariableDeclSyntax.self) {
            recursed = visited
        } else {
            recursed = node
        }

        var updated = recursed
        if let transientAttribute = recursed.attributes.first(where: { Self.isAttribute($0, named: "Transient") }) {
            updated.attributes = recursed.attributes.filter { !Self.isAttribute($0, named: "Transient") }

            if updated.attributes.isEmpty {
                updated = Self.setLeadingTrivia(transientAttribute.leadingTrivia, onVariable: updated)
            }
        }

        return DeclSyntax(addRelationshipObserversIfNeeded(to: updated))
    }

    override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(InitializerDeclSyntax.self)
        guard let context = classStack.last,
              !context.relationships.isEmpty,
              var body = recursed.body
        else {
            return DeclSyntax(recursed)
        }

        let parameterNames = Set(recursed.signature.parameterClause.parameters.compactMap(Self.localParameterName))
        let relationshipNamesWithoutParameters = Set(
            context.relationships
                .map(\.name)
                .filter { !parameterNames.contains($0) }
        )
        guard !relationshipNamesWithoutParameters.isEmpty else {
            return DeclSyntax(recursed)
        }

        let filteredStatements = body.statements.filter { item in
            !relationshipNamesWithoutParameters.contains { relationshipName in
                Self.isSelfAssignment(item, toPropertyNamed: relationshipName)
            }
        }
        guard filteredStatements.count != body.statements.count else {
            return DeclSyntax(recursed)
        }

        var updated = recursed
        body.statements = filteredStatements
        body.rightBrace = body.rightBrace.with(\.trailingTrivia, .newlines(1))
        updated.body = body
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

    private struct ClassRelationshipContext {
        let className: String
        let relationships: [RelationshipProperty]
        let registrations: [RelationshipRegistration]

        var hasRegistrationMember: Bool { !registrations.isEmpty }
    }

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

    private func addRelationshipObserversIfNeeded(to variable: VariableDeclSyntax) -> VariableDeclSyntax {
        guard let context = classStack.last,
              SwiftDataRelationshipScanner.relationshipAttribute(in: variable.attributes) != nil,
              variable.bindingSpecifier.tokenKind == .keyword(.var)
        else {
            return variable
        }

        var updated = variable
        var bindings = updated.bindings
        var changed = false

        for index in bindings.indices {
            var binding = bindings[index]
            guard binding.accessorBlock == nil,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self)
            else {
                continue
            }

            let propertyName = identifier.identifier.text
            guard let observer = Self.relationshipObserverBlock(
                propertyName: propertyName,
                ensuresRegistration: context.hasRegistrationMember
            ) else {
                continue
            }

            binding.accessorBlock = observer
                .with(\.leadingTrivia, .space)
                .with(\.trailingTrivia, .newlines(1))
            bindings[index] = binding
            changed = true
        }

        if changed {
            updated.bindings = bindings
        }
        return updated
    }

    private static func relationshipObserverBlock(
        propertyName: String,
        ensuresRegistration: Bool
    ) -> AccessorBlockSyntax? {
        let registrationLine = ensuresRegistration
            ? "            _ = Self.__quillRelationshipsRegistered\n"
            : ""
        let source = """
        var __quillRelationshipScratch: Any {
                didSet {
        \(registrationLine)            QuillRelationships.relationshipDidSet(
                        self,
                        ObjectIdentifier(Self.self),
                        "\(propertyName)",
                        oldValue: oldValue,
                        newValue: \(propertyName)
                    )
                }
            }
        """
        return DeclSyntax(stringLiteral: source)
            .as(VariableDeclSyntax.self)?
            .bindings
            .first?
            .accessorBlock
    }

    private static func addRelationshipRegistrationMemberIfNeeded(
        to classDecl: inout ClassDeclSyntax,
        registrations: [RelationshipRegistration]
    ) {
        guard !registrations.isEmpty,
              !hasRelationshipRegistrationMember(in: classDecl)
        else {
            return
        }

        let calls = registrations.map { registration in
            """
                    QuillRelationships.registerInverse(
                        parentType: \(registration.parentType).self,
                        toManyProperty: "\(registration.toManyProperty)",
                        toMany: \\\(registration.parentType).\(registration.toManyProperty),
                        childType: \(registration.childType).self,
                        toOneProperty: "\(registration.toOneProperty)",
                        toOne: \\\(registration.childType).\(registration.toOneProperty)
                    )
            """
        }.joined(separator: "\n")

        let memberSource = """
            private static let __quillRelationshipsRegistered: Void = {
        \(calls)
            }()
        """

        guard var registrationDecl = DeclSyntax(stringLiteral: memberSource).as(VariableDeclSyntax.self) else {
            return
        }
        registrationDecl = registrationDecl.with(\.leadingTrivia, .newlines(1) + .spaces(4))

        var memberBlock = classDecl.memberBlock
        var members = Array(memberBlock.members)
        members.append(MemberBlockItemSyntax(decl: DeclSyntax(registrationDecl)))
        memberBlock.members = MemberBlockItemListSyntax(members)
        classDecl.memberBlock = memberBlock
    }

    private static func hasRelationshipRegistrationMember(in classDecl: ClassDeclSyntax) -> Bool {
        classDecl.memberBlock.members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return false }
            return variable.bindings.contains { binding in
                binding.pattern.trimmedDescription == "__quillRelationshipsRegistered"
            }
        }
    }

    private static func localParameterName(_ parameter: FunctionParameterSyntax) -> String? {
        if let secondName = parameter.secondName, secondName.text != "_" {
            return secondName.text
        }
        let firstName = parameter.firstName.text
        return firstName == "_" ? nil : firstName
    }

    private static func isSelfAssignment(
        _ item: CodeBlockItemSyntax,
        toPropertyNamed propertyName: String
    ) -> Bool {
        let stripped = item.trimmedDescription
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
        return stripped == "self.\(propertyName)=\(propertyName)"
            || stripped == "self.\(propertyName)=\(propertyName);"
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
