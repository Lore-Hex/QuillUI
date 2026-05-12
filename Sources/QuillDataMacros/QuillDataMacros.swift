import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private enum QuillPredicateMacroError: Error, CustomStringConvertible {
    case missingClosure

    var description: String {
        switch self {
        case .missingClosure:
            return "#QuillPredicate requires a closure argument"
        }
    }
}

public struct QuillModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else { return [] }
        let className = classDecl.name.text
        let tableName = "_\(className)s"
        let access = classDecl.modifiers.map({ "\($0) " }).joined()
        let isPublic = access.contains("public ")
        let visibility = isPublic ? "public " : ""

        let storedProperties = classDecl.memberBlock.members.compactMap { member -> VariableDeclSyntax? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return nil }
            for binding in varDecl.bindings { if binding.accessorBlock != nil { return nil } }
            return varDecl
        }

        let structProperties = storedProperties.map { varDecl -> String in
            varDecl.bindings.map { binding -> String in
                "\(visibility)var \(binding.pattern.description): \(binding.typeAnnotation?.type.description ?? "Any")"
            }.joined(separator: "\n    ")
        }.joined(separator: "\n    ")

        let mappingInitParams = storedProperties.flatMap { varDecl in
            varDecl.bindings.map { "\(($0.pattern.description)): \(($0.pattern.description))" }
        }.joined(separator: ", ")

        let fromTableParams = storedProperties.flatMap { varDecl in
            varDecl.bindings.map { "\(($0.pattern.description)): tableStruct.\($0.pattern.description)" }
        }.joined(separator: ", ")

        let updateBody = storedProperties.flatMap { varDecl in
            varDecl.bindings.map { "self.\($0.pattern.description) = tableStruct.\($0.pattern.description)" }
        }.joined(separator: "\n        ")

        let sqlProperties = storedProperties.flatMap { varDecl in
            varDecl.bindings.map { binding in
                let name = binding.pattern.description
                let type = binding.typeAnnotation?.type.description ?? "TEXT"
                let sqlType: String
                switch type {
                case "Int", "Int64": sqlType = "INTEGER"
                case "Double", "Float": sqlType = "REAL"
                case "Bool": sqlType = "INTEGER"
                case "Date": sqlType = "DATETIME"
                case "Data": sqlType = "BLOB"
                case "UUID": sqlType = "TEXT"
                default: sqlType = "TEXT"
                }
                let pk = name == "id" ? " PRIMARY KEY ON CONFLICT REPLACE" : " NOT NULL"
                return "\\\"\(name)\\\" \(sqlType)\(pk)"
            }
        }.joined(separator: ",\\n    ")

        let fullSQL = "CREATE TABLE IF NOT EXISTS \\\"\(tableName)\\\" (\\n    \(sqlProperties)\\n)"

        return [
            "\(raw: visibility)typealias TableStruct = _\(raw: className)",
            "\(raw: visibility)static let createTableSQL = \(raw: #"""#)\(raw: fullSQL)\(raw: #"""#)",
            "\(raw: visibility)static let tableName = \"\(raw: tableName)\"",
            "\(raw: visibility)struct _\(raw: className): Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord { \(raw: structProperties); \(raw: visibility)static let databaseTableName = \"\(raw: tableName)\" }",
            "\(raw: visibility)func toTableStruct() -> _\(raw: className) { _\(raw: className)(\(raw: mappingInitParams)) }",
            "\(raw: visibility)func update(from tableStruct: _\(raw: className)) { \(raw: updateBody) }",
            "\(raw: visibility)static func fromTableStruct(_ tableStruct: _\(raw: className)) -> \(raw: className) { \(raw: className)(\(raw: fromTableParams)) }"
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        [
            DeclSyntax("extension \(type.trimmed): PersistentModel {}").as(ExtensionDeclSyntax.self)!,
            DeclSyntax("extension \(type.trimmed): QuillTableMappable {}").as(ExtensionDeclSyntax.self)!
        ]
    }
}

public struct QuillPredicateMacro: ExpressionMacro {
    public static func expansion(of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext) throws -> ExprSyntax {
        guard let closure = node.trailingClosure ?? node.arguments.first?.expression.as(ClosureExprSyntax.self) else {
            throw QuillPredicateMacroError.missingClosure
        }
        let sql = translateToSQL(closure: closure) ?? "1=1"
        return "Predicate(sqlFilter: \"\(raw: sql)\") \(raw: closure.description)"
    }

    private static func translateToSQL(closure: ClosureExprSyntax) -> String? {
        guard let body = closure.statements.first?.item.as(ExprSyntax.self) else { return nil }
        return translateExpression(body)
    }

    private static func translateExpression(_ expr: ExprSyntax) -> String? {
        if let infix = expr.as(InfixOperatorExprSyntax.self) {
            let left = translateExpression(infix.leftOperand), right = translateExpression(infix.rightOperand), op = infix.operator.description.trimmingCharacters(in: .whitespaces)
            guard let left, let right else { return nil }
            if op == "??" { return "COALESCE(\(left), \(right))" }
            let sqlOp = (op == "==" && (right == "NULL" || right == "nil" || right == "'nil'")) ? "IS" : (op == "!=" && (right == "NULL" || right == "nil" || right == "'nil'")) ? "IS NOT" : (op == "==") ? "=" : (op == "&&") ? "AND" : (op == "||") ? "OR" : op
            return "(\(left) \(sqlOp) \(right))"
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!" { return "NOT (\(translateExpression(prefix.expression) ?? ""))" }
        if let seq = expr.as(SequenceExprSyntax.self) {
             let els = Array(seq.elements)
             if els.count == 1 { return translateExpression(els[0]) }
             if els.count >= 3 {
                 var result: String? = translateExpression(els[0])
                 var i = 1
                 while i < els.count - 1 {
                     let op = els[i].description.trimmingCharacters(in: .whitespaces)
                     let right = translateExpression(els[i+1])
                     if let r = right, let l = result {
                         if op == "??" { result = "COALESCE(\(l), \(r))" }
                         else {
                             let sqlOp = (op == "==" && (r == "NULL" || r == "nil" || r == "'nil'")) ? "IS" : (op == "!=" && (r == "NULL" || r == "nil" || r == "'nil'")) ? "IS NOT" : (op == "==") ? "=" : (op == "&&") ? "AND" : (op == "||") ? "OR" : op
                             result = "(\(l) \(sqlOp) \(r))"
                         }
                     } else { return nil }
                     i += 2
                 }
                 return result
             }
        }
        if let tuple = expr.as(TupleExprSyntax.self) { return tuple.elements.first.flatMap { translateExpression($0.expression) } }
        if let opt = expr.as(OptionalChainingExprSyntax.self) { return translateExpression(opt.expression) }
        if let forced = expr.as(ForceUnwrapExprSyntax.self) { return translateExpression(forced.expression) }
        if let mem = expr.as(MemberAccessExprSyntax.self) {
            let name = mem.declName.baseName.text
            if let base = mem.base.map({ translateExpression($0) }), let b = base {
                if b == "$0" { return name == "isEmpty" ? "(LENGTH(\(name)) = 0)" : name }
                return name == "isEmpty" ? "(LENGTH(\(b)) = 0)" : "\(b)_\(name)"
            }
            return name
        }
        if let call = expr.as(FunctionCallExprSyntax.self), let mem = call.calledExpression.as(MemberAccessExprSyntax.self), let b = mem.base.map({ translateExpression($0) }), let base = b {
            let method = mem.declName.baseName.text, arg = call.arguments.first.flatMap({ translateExpression($0.expression) }) ?? ""
            if method == "contains" { return "(\(base) LIKE '%' || \(arg) || '%')" }
            if method == "hasPrefix" { return "(\(base) LIKE \(arg) || '%')" }
            if method == "hasSuffix" { return "(\(base) LIKE '%' || \(arg))" }
        }
        if let lit = expr.as(StringLiteralExprSyntax.self) {
            let text = lit.segments.description
            return text == "nil" ? "NULL" : "'\(text)'"
        }
        if let lit = expr.as(IntegerLiteralExprSyntax.self) { return lit.literal.text }
        if let lit = expr.as(BooleanLiteralExprSyntax.self) { return lit.literal.text == "true" ? "1" : "0" }
        if expr.is(NilLiteralExprSyntax.self) { return "NULL" }
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            return name == "$0" ? "$0" : name
        }
        return nil
    }
}

public struct QuillAttributeMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

public struct QuillRelationshipMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}

@main struct QuillDataMacrosPlugin: CompilerPlugin { let providingMacros: [Macro.Type] = [QuillModelMacro.self, QuillPredicateMacro.self, QuillAttributeMacro.self, QuillRelationshipMacro.self] }
