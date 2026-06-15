import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Opt-in lowering that removes Swift actor-isolation concurrency for headless
/// builds that run on a single thread with no structured-concurrency runtime
/// (e.g. the generic GTK backend used by the Enchanted / Quill Chat profile).
///
/// This is the first-class, registerable replacement for the per-app Perl
/// rewrite rules that used to live in
/// `scripts/profiles/enchanted-full-source/rewrite-rules/...` (notably
/// `Recorder/SpeechRecogniser.swift.pl`, `Recorder/RecordingView.swift.pl`,
/// and `Chat/Components/ModelSelectorView.swift.pl`). It performs exactly the
/// transformations those rules performed:
///
///   * `actor Name { … }`            -> `final class Name { … }`
///   * `nonisolated` declaration       modifier removal
///   * `await <intra-type call>`     -> `<intra-type call>` (the `await`
///     keyword is dropped). An *intra-type call* is a call whose receiver root
///     is `self` or a lower-cased identifier (i.e. a local value / instance of
///     a now-de-actored type), with **no** trailing closure. Calls whose
///     receiver root is a capitalized identifier (a type, e.g.
///     `SFSpeechRecognizer.hasAuthorizationToRecognize()`) and calls that carry
///     a trailing closure (e.g. `withCheckedContinuation { … }`) keep their
///     `await`, matching the original Perl rules byte-for-byte.
///
/// `@MainActor` removal is intentionally **not** done here — that strip is
/// already always-on in ``SwiftUILowering`` and applies to apps that keep real
/// async, so it must not be gated behind this opt-in rule.
///
/// This rule is **off by default**. Apps with genuine concurrency (Signal /
/// Telegram) must never enable it; only profiles that compile against the
/// headless single-threaded backend should opt in (see
/// ``SwiftUILoweringOptions/stripActorIsolation``).
public struct ActorIsolationLowering {
    public init() {}

    /// Lowers a single Swift source string in memory.
    public func lower(_ source: String) -> String {
        let tree = Parser.parse(source: source)
        return ActorIsolationRewriter().rewrite(tree).description
    }

    /// Lowers every `.swift` file under `sourceDir` *in place*. Files whose
    /// lowered content equals the input are not rewritten, so file mtimes don't
    /// churn on a no-op pass. Returns the number of `.swift` files visited.
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

private final class ActorIsolationRewriter: SyntaxRewriter {
    /// `actor Name { … }` -> `final class Name { … }`.
    ///
    /// SwiftSyntax models an actor with its own `ActorDeclSyntax`, so we rebuild
    /// the equivalent `ClassDeclSyntax` token-for-token, prepend a `final`
    /// modifier, and carry every piece of trivia (including the comment trivia
    /// attached to the leading attributes / modifiers) forward unchanged.
    override func visit(_ node: ActorDeclSyntax) -> DeclSyntax {
        let recursedSyntax = super.visit(node)
        guard let actor = recursedSyntax.as(ActorDeclSyntax.self) else {
            return recursedSyntax
        }

        // `final` carries the actor keyword's leading trivia so leading comments
        // / blank lines stay attached to the head of the declaration. The actor
        // keyword itself becomes the `class` keyword with a single leading space.
        let finalKeyword = TokenSyntax.keyword(
            .final,
            leadingTrivia: actor.actorKeyword.leadingTrivia,
            trailingTrivia: .space
        )
        let finalModifier = DeclModifierSyntax(name: finalKeyword)

        var modifiers = actor.modifiers
        modifiers = DeclModifierListSyntax([finalModifier] + Array(modifiers))

        let classKeyword = TokenSyntax.keyword(
            .class,
            leadingTrivia: [],
            trailingTrivia: actor.actorKeyword.trailingTrivia
        )

        let classDecl = ClassDeclSyntax(
            leadingTrivia: actor.leadingTrivia,
            attributes: actor.attributes,
            modifiers: modifiers,
            classKeyword: classKeyword,
            name: actor.name,
            genericParameterClause: actor.genericParameterClause,
            inheritanceClause: actor.inheritanceClause,
            genericWhereClause: actor.genericWhereClause,
            memberBlock: actor.memberBlock,
            trailingTrivia: actor.trailingTrivia
        )
        return DeclSyntax(classDecl)
    }

    /// Drop the `nonisolated` modifier from any declaration's modifier list.
    /// `nonisolated private func foo()` -> `private func foo()`.
    override func visit(_ node: DeclModifierListSyntax) -> DeclModifierListSyntax {
        let recursed = super.visit(node)
        guard recursed.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) }) else {
            return recursed
        }

        var kept: [DeclModifierSyntax] = []
        var carriedLeadingTrivia: Trivia = []
        for modifier in recursed {
            if modifier.name.tokenKind == .keyword(.nonisolated) {
                // Preserve any leading trivia (comments / blank lines) that lived
                // in front of `nonisolated` so it lands on whatever comes next.
                carriedLeadingTrivia = carriedLeadingTrivia + modifier.name.leadingTrivia
                continue
            }
            var updated = modifier
            if !carriedLeadingTrivia.isEmpty {
                updated.leadingTrivia = carriedLeadingTrivia + updated.leadingTrivia
                carriedLeadingTrivia = []
            }
            kept.append(updated)
        }
        // If `nonisolated` was the last/only modifier, its leading trivia is
        // re-attached by the parent (the declaration keyword keeps its own
        // leading trivia); an empty modifier list cleanly collapses.
        return DeclModifierListSyntax(kept)
    }

    /// Drop the `await` keyword from intra-type call expressions. See the type
    /// doc comment for the precise definition of an *intra-type call* and the
    /// carve-outs (capitalized type receivers, trailing-closure calls) that keep
    /// their `await`.
    override func visit(_ node: AwaitExprSyntax) -> ExprSyntax {
        let recursedSyntax = super.visit(node)
        guard let awaitExpr = recursedSyntax.as(AwaitExprSyntax.self) else {
            return recursedSyntax
        }
        guard Self.shouldStripAwait(from: awaitExpr.expression) else {
            return recursedSyntax
        }

        // Unwrap: replace the `await <expr>` with `<expr>`, moving the `await`
        // keyword's leading trivia onto the unwrapped expression so indentation
        // and any preceding comments survive.
        var inner = awaitExpr.expression
        inner.leadingTrivia = awaitExpr.awaitKeyword.leadingTrivia + inner.leadingTrivia
        return inner
    }

    /// An expression is a strippable intra-type call when:
    ///   * it is a function call,
    ///   * it has no trailing closure (so `withCheckedContinuation { … }` is
    ///     left awaited), and
    ///   * its callee's *receiver root* is `self` or a lower-cased identifier
    ///     (an instance / local value), never a capitalized identifier (a type).
    private static func shouldStripAwait(from expression: ExprSyntax) -> Bool {
        guard let call = expression.as(FunctionCallExprSyntax.self) else {
            return false
        }
        // Trailing-closure calls (e.g. `withCheckedContinuation { … }`) keep
        // their `await`; the original Perl rules never touched them.
        guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else {
            return false
        }
        return calleeRootIsInstance(call.calledExpression)
    }

    /// Walks to the root of a (possibly optional-chained / member-access) callee
    /// expression and decides whether that root is an instance (`self` or a
    /// lower-cased identifier) rather than a capitalized type name.
    private static func calleeRootIsInstance(_ expression: ExprSyntax) -> Bool {
        var current = expression
        while true {
            if let member = current.as(MemberAccessExprSyntax.self), let base = member.base {
                current = base
                continue
            }
            if let optional = current.as(OptionalChainingExprSyntax.self) {
                current = optional.expression
                continue
            }
            if let forced = current.as(ForceUnwrapExprSyntax.self) {
                current = forced.expression
                continue
            }
            break
        }

        if current.is(SuperExprSyntax.self) {
            return true
        }
        guard let ref = current.as(DeclReferenceExprSyntax.self) else {
            // Unknown root shape (subscripts, literals, etc.) — be conservative
            // and keep the `await`.
            return false
        }
        let name = ref.baseName.text
        if name == "self" {
            return true
        }
        // A leading upper-case letter marks a type (`SFSpeechRecognizer`,
        // `AVAudioSession`); keep its `await`. A lower-cased root is an instance
        // / local value of a de-actored type; strip its `await`.
        guard let first = name.first else { return false }
        return first.isLowercase
    }
}
