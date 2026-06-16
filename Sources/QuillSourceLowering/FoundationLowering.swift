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
        return FoundationRewriter().rewrite(tree).description
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
    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
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

    override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
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

    private static func baseLooksLikeSortDescriptor(_ base: ExprSyntax) -> Bool {
        base.trimmedDescription.lowercased().contains("sortdescriptor")
    }
}
