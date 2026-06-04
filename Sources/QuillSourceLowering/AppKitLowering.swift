import Foundation
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Lowers AppKit / Objective-C target-action syntax into Linux-buildable Swift,
/// so unmodified macOS app source recompiles against the QuillAppKit shadow
/// stack (which has no Objective-C runtime). Companion to `SwiftUILowering` —
/// same shape, same in-place file walk.
///
/// This is **automatic and app-agnostic**: it rewrites the stereotyped
/// target-action wiring every AppKit app uses, nothing app-specific. Currently
/// covers:
///
///   * `@objc` (and `@objcMembers` / `@IBAction` / `@IBOutlet` / `@IBInspectable`
///     / `@IBDesignable` / `@NSManaged` / `@GKInspectable` / `@NSApplicationMain`)
///     attribute removal from any declaration. The QuillAppKit shadow needs no
///     ObjC exposure; the methods stay as plain Swift methods. Leading trivia is
///     preserved so a line-leading `@objc` doesn't merge its decl onto the
///     previous line (a "consecutive statements" error when that line isn't
///     brace-terminated).
///   * `#selector(x)` → `Selector("x")`. On Linux `#selector` can't compile
///     (there is no `ObjectiveC` module), but `QuillFoundation.Selector` is a
///     plain `struct { let name: String }`. We key the `Selector` off the
///     **source text** of the reference: there is no real ObjC runtime, so the
///     string only has to be consistent between the value and our dispatch — it
///     need not match Apple's selector mangling. The leading **type qualifier is
///     stripped** (`TunnelsListTableViewController.handleRemoveTunnelAction` →
///     `handleRemoveTunnelAction`, `NSWindow.toggleFullScreen(_:)` →
///     `toggleFullScreen(_:)`) so a qualified `#selector` compares equal to the
///     unqualified `#selector` that set the action — menu validation
///     (`menuItem.action == #selector(Type.foo)`) relies on this.
///
/// Runtime dispatch (a generated per-class `quillPerform(_:)` the Qt control
/// backing invokes on click) layers on separately; this pass produces source
/// that *compiles* against the shadow, which is conformance milestone #1.
public struct AppKitLowering {
    public init() {}

    /// Lowers a single Swift source string in memory.
    public func lower(_ source: String) -> String {
        let tree = Parser.parse(source: source)
        let rewriter = AppKitRewriter()
        return rewriter.rewrite(tree).description
    }

    /// Lowers every `.swift` file under `sourceDir` *in place*. Mirrors
    /// `SwiftUILowering.lowerInPlace`: files unchanged by the pass aren't
    /// rewritten (no mtime churn). Returns the number of `.swift` files visited.
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

private final class AppKitRewriter: SyntaxRewriter {
    /// Attributes removed wholesale — the ObjC-exposure markers the shadow
    /// doesn't need (and that don't compile without an ObjC runtime).
    static let strippedAttributeNames: Set<String> = [
        "objc", "objcMembers",
        "IBAction", "IBOutlet", "IBInspectable", "IBDesignable",
        "NSManaged", "GKInspectable", "NSApplicationMain",
    ]

    // Strip ObjC attributes per decl kind that can carry them. Doing it at the
    // decl level (rather than in `visit(AttributeListSyntax)`) lets us re-anchor
    // the decl's leading trivia onto the surviving first token, so removing a
    // line-leading `@objc` keeps the decl on its own line.
    override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
        DeclSyntax(stripAttributes(super.visit(node).cast(FunctionDeclSyntax.self)))
    }
    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        DeclSyntax(stripAttributes(super.visit(node).cast(VariableDeclSyntax.self)))
    }
    override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax {
        DeclSyntax(stripAttributes(super.visit(node).cast(InitializerDeclSyntax.self)))
    }
    override func visit(_ node: SubscriptDeclSyntax) -> DeclSyntax {
        DeclSyntax(stripAttributes(super.visit(node).cast(SubscriptDeclSyntax.self)))
    }
    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        DeclSyntax(stripAttributes(super.visit(node).cast(ClassDeclSyntax.self)))
    }
    override func visit(_ node: ProtocolDeclSyntax) -> DeclSyntax {
        DeclSyntax(stripAttributes(super.visit(node).cast(ProtocolDeclSyntax.self)))
    }
    override func visit(_ node: EnumDeclSyntax) -> DeclSyntax {
        DeclSyntax(stripAttributes(super.visit(node).cast(EnumDeclSyntax.self)))
    }
    override func visit(_ node: ExtensionDeclSyntax) -> DeclSyntax {
        DeclSyntax(stripAttributes(super.visit(node).cast(ExtensionDeclSyntax.self)))
    }

    private func stripAttributes<S: SyntaxProtocol & WithAttributesSyntax>(_ node: S) -> S {
        let kept = node.attributes.filter { element -> Bool in
            guard case .attribute(let attr) = element else { return true }
            return !Self.strippedAttributeNames.contains(attr.attributeName.trimmedDescription)
        }
        guard kept.count != node.attributes.count else { return node }
        // `node.leadingTrivia` is the leading trivia of the decl's first token —
        // the removed `@` when `@objc` leads. Re-anchor it onto whatever token
        // is first after stripping (a surviving attribute, a modifier, or the
        // keyword) so the newline+indent before the decl survives.
        let savedLeading = node.leadingTrivia
        var copy = node
        copy.attributes = kept
        copy.leadingTrivia = savedLeading
        return copy
    }

    // #selector(x) -> Selector("x")
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

    /// Normalize a `#selector` reference into a stable key: drop the leading type
    /// qualifier (everything up to and including the final `.` that precedes the
    /// method name, considering only dots *before* any `(` so argument labels are
    /// untouched). `Type.method` and bare `method` thus map to the same key.
    static func selectorKey(from arguments: String) -> String {
        let t = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualifierPath = t.prefix { $0 != "(" }
        guard let lastDot = qualifierPath.range(of: ".", options: .backwards) else {
            return t
        }
        return String(t[t.index(after: lastDot.lowerBound)...])
    }
}
