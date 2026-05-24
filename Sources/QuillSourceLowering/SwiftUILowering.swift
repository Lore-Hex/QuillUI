import Foundation
import SwiftParser
import SwiftSyntax

/// Lowers SwiftUI-only Swift syntax into Linux-compatible Swift.
///
/// Mirrors a *subset* of the regex transformations in
/// `scripts/lower-swiftui-source-for-linux.sh`. The first SwiftSyntax slice
/// covers cleanly-structural attribute and inheritance rewrites:
///
///   * `@main` attribute removal from any declaration
///   * `@MainActor` attribute removal from any declaration
///   * `@MainActor` removal from inline function type expressions
///     (e.g. `let action: (@MainActor () -> Void)?` → `let action: (() -> Void)?`)
///   * `@Observable` attribute removal from any declaration (note: this is
///     the lightweight removal pass; the full `@Observable` → `QuillObservableObject`
///     class transformation with `@QuillPublished` stored-property wrapping is
///     still handled by the shell script's Python helper)
///   * `Sendable` removal from inheritance lists whenever `View` is also
///     present (so `struct Foo: View, Sendable` → `struct Foo: View`)
///
/// Out of scope for this slice (still handled by the shell script):
///   * `@Observable` → `QuillObservableObject` rewrite with `@QuillPublished`
///     wrapping of stored properties
///   * `#Preview` block deletion, including the special case where the block
///     is wrapped in a `#if … #endif` extending to EOF
///   * `os(macOS)` widening to `(os(macOS) || os(Linux))` in compilation
///     conditions, with carve-outs for negated and already-widened forms
///
/// Until the SwiftSyntax implementation catches up to the above, the shell
/// script remains the canonical entry point for generated-source profiles.
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
}
