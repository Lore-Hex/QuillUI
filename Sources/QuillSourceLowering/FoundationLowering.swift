import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Lowers Foundation API shapes that exist on Apple platforms but are absent
/// or runtime-trapping in swift-corelibs-foundation.
public struct FoundationLowering {
    public init() {}

    public func lower(_ source: String) -> String {
        let tree = Parser.parse(source: source)
        let checkingTypeVariables = NSTextCheckingTypeVariableScanner.variableNames(in: tree)
        let lowered = FoundationRewriter(checkingTypeVariables: checkingTypeVariables)
            .rewrite(tree)
            .description
        return Self.lowerLinuxFoundationCompatibility(Self.removeUnavailableFormatterOverrides(lowered))
    }

    private static func lowerLinuxFoundationCompatibility(_ source: String) -> String {
        var lowered = source
            .replacingOccurrences(of: "Unmanaged<CFURL>", with: "Unmanaged<NSURL>")
            .replacingOccurrences(of: "Foundation.URLRequest", with: "URLRequest")
            .replacingOccurrences(of: "Foundation.URLSession", with: "URLSession")
            .replacingOccurrences(of: "Foundation.URLSessionConfiguration", with: "URLSessionConfiguration")
            .replacingOccurrences(of: "Foundation.HTTPURLResponse", with: "HTTPURLResponse")
            .replacingOccurrences(of: "Foundation.URLResponse", with: "URLResponse")

        if lowered.contains("Process.ExecutionParameters"),
           !lowered.contains("import ProcessEnv"),
           let regex = try? NSRegularExpression(pattern: #"(?m)^((?:@preconcurrency[ \t]+)?import[ \t]+Foundation\b.*)$"#) {
            let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
            if let match = regex.firstMatch(in: lowered, range: range),
               let lineRange = Range(match.range(at: 1), in: lowered) {
                lowered.replaceSubrange(lineRange, with: "\(lowered[lineRange])\nimport ProcessEnv")
            } else {
                lowered = "import ProcessEnv\n" + lowered
            }
        }

        return lowered
    }

    private static func removeUnavailableFormatterOverrides(_ source: String) -> String {
        let pattern = #"(?m)^([ \t]*)override[ \t]+((?:(?:open|public|internal|fileprivate|private)[ \t]+)?)func[ \t]+(getObjectValue|isPartialStringValid)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: "$1$2func $3"
        )
    }

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

private final class FoundationRewriter: SyntaxRewriter {
    private let checkingTypeVariables: Set<String>

    init(checkingTypeVariables: Set<String>) {
        self.checkingTypeVariables = checkingTypeVariables
    }

    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
        if let loweredCheckingTypeInsert = lowerCheckingTypeInsert(recursed) {
            return loweredCheckingTypeInsert
        }

        if let loweredNSError = lowerNSErrorEmptyInitializer(recursed) {
            return loweredNSError
        }

        guard let call = recursed.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "NSSortDescriptor",
              call.arguments.map({ $0.label?.text }) == ["key", "ascending"],
              let firstArgument = call.arguments.first else {
            return recursed
        }

        var arguments = call.arguments
        var first = firstArgument
        first.label = nil
        first.colon = nil
        arguments[arguments.startIndex] = first

        var quillKey = ExprSyntax("NSSortDescriptor.quillKey")
        quillKey.leadingTrivia = call.calledExpression.leadingTrivia
        quillKey.trailingTrivia = call.calledExpression.trailingTrivia

        var copy = call
        copy.calledExpression = quillKey
        copy.arguments = arguments
        return ExprSyntax(copy)
    }

    private func lowerNSErrorEmptyInitializer(_ recursed: ExprSyntax) -> ExprSyntax? {
        guard let call = recursed.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "NSError",
              call.arguments.isEmpty else {
            return nil
        }

        var replacement = ExprSyntax("NSError(domain: \"QuillFoundation.NSError\", code: 0, userInfo: nil)")
        replacement.leadingTrivia = call.leadingTrivia
        replacement.trailingTrivia = call.trailingTrivia
        return replacement
    }

    override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
        if let loweredCheckingType = lowerCheckingTypeMemberAccess(recursed) {
            return loweredCheckingType
        }

        guard var access = recursed.as(MemberAccessExprSyntax.self),
              access.declName.baseName.text == "key",
              let base = access.base,
              Self.baseLooksLikeSortDescriptor(base) else {
            return recursed
        }

        var declName = access.declName
        declName.baseName = .identifier(
            "quillKey",
            leadingTrivia: declName.baseName.leadingTrivia,
            trailingTrivia: declName.baseName.trailingTrivia
        )
        access.declName = declName
        return ExprSyntax(access)
    }

    private func lowerCheckingTypeInsert(_ recursed: ExprSyntax) -> ExprSyntax? {
        guard var call = recursed.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
              callee.declName.baseName.text == "insert",
              let base = callee.base?.as(DeclReferenceExprSyntax.self),
              checkingTypeVariables.contains(base.baseName.text),
              call.arguments.count == 1,
              let firstArgument = call.arguments.first,
              let member = firstArgument.expression.as(MemberAccessExprSyntax.self),
              member.base == nil,
              let rawValue = Self.checkingTypeRawValue(named: member.declName.baseName.text) else {
            return nil
        }

        var arguments = call.arguments
        var first = firstArgument
        first.expression = Self.checkingTypeExpression(rawValue: rawValue, matchingTriviaOf: member)
        arguments[arguments.startIndex] = first
        call.arguments = arguments
        return ExprSyntax(call)
    }

    private func lowerCheckingTypeMemberAccess(_ recursed: ExprSyntax) -> ExprSyntax? {
        guard let access = recursed.as(MemberAccessExprSyntax.self),
              let rawValue = Self.checkingTypeRawValue(named: access.declName.baseName.text),
              access.base?.trimmedDescription == "NSTextCheckingResult.CheckingType" else {
            return nil
        }

        return Self.checkingTypeExpression(rawValue: rawValue, matchingTriviaOf: access)
    }

    private static func checkingTypeExpression(
        rawValue: Int,
        matchingTriviaOf source: some SyntaxProtocol
    ) -> ExprSyntax {
        var expression = ExprSyntax("NSTextCheckingResult.CheckingType(rawValue: \(raw: rawValue))")
        expression.leadingTrivia = source.leadingTrivia
        expression.trailingTrivia = source.trailingTrivia
        return expression
    }

    private static func checkingTypeRawValue(named name: String) -> Int? {
        switch name {
        case "date": return 1 << 3
        case "address": return 1 << 4
        case "link": return 1 << 5
        case "phoneNumber": return 1 << 11
        case "transitInformation": return 1 << 12
        default: return nil
        }
    }

    private static func baseLooksLikeSortDescriptor(_ base: ExprSyntax) -> Bool {
        base.trimmedDescription.lowercased().contains("sortdescriptor")
    }
}

private final class NSTextCheckingTypeVariableScanner: SyntaxVisitor {
    private var names: Set<String> = []

    static func variableNames(in tree: SourceFileSyntax) -> Set<String> {
        let scanner = NSTextCheckingTypeVariableScanner(viewMode: .sourceAccurate)
        scanner.walk(tree)
        return scanner.names
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        guard node.initializer?.value.trimmedDescription == "NSTextCheckingResult.CheckingType()",
              let identifier = node.pattern.as(IdentifierPatternSyntax.self) else {
            return .visitChildren
        }

        names.insert(identifier.identifier.text)
        return .visitChildren
    }
}
