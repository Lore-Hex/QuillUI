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
        // Collect target-action methods per type BEFORE @objc is stripped, so we
        // can synthesize the `QuillActionDispatching` conformance that the
        // runtime (`NSControl.sendAction`) invokes. See QuillActionDispatching
        // in QuillAppKit. On a second pass the source has no `@objc` left, so the
        // collector finds nothing and nothing is appended — the pass stays
        // idempotent.
        let collector = ActionMethodCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        let rewritten = AppKitRewriter().rewrite(tree).description
        let conformances = Self.generateDispatchConformances(
            orderedTypes: collector.orderedTypes,
            byType: collector.byType
        )
        return conformances.isEmpty ? rewritten : rewritten + conformances
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

    // MARK: - Dispatch-conformance generation

    /// Emit, per type that declares `@objc` target-action methods, an
    /// `extension Type: QuillActionDispatching { func quillPerform(_:with:) }`
    /// that switches over the selector name and calls the method. This is the
    /// runtime half of the lowering: `#selector(x)` became `Selector("x")`, and
    /// this turns that token back into a real call without an ObjC runtime.
    /// General + automatic — generated from the app's own `@objc` methods.
    static func generateDispatchConformances(
        orderedTypes: [String],
        byType: [String: [ActionMethod]]
    ) -> String {
        var out = ""
        for typeName in orderedTypes {
            guard let methods = byType[typeName] else { continue }
            // AppKit actions take 0 or 1 (sender) param; anything else isn't a
            // target-action, so we don't synthesize a call for it.
            let emittable = methods.filter { $0.params.count <= 1 }
            guard !emittable.isEmpty else { continue }

            var lines: [String] = []
            lines.append("")
            lines.append("// Auto-generated by AppKitLowering: target-action dispatch")
            lines.append("// (turns Selector(\"…\") back into a real call — no ObjC runtime).")
            lines.append("extension \(typeName): QuillActionDispatching {")
            lines.append("    func quillPerform(_ selector: Selector, with sender: Any?) {")
            lines.append("        switch selector.name {")
            for m in emittable {
                lines.append("        case \"\(selectorKeyForDecl(m))\": \(callExpression(m))")
            }
            lines.append("        default: break")
            lines.append("        }")
            lines.append("    }")
            lines.append("}")
            out += "\n" + lines.joined(separator: "\n") + "\n"
        }
        return out
    }

    /// The selector key a `#selector` reference to this method lowers to (must
    /// match `AppKitRewriter.selectorKey`): bare name for no-arg, `name(label:)`
    /// for args (external label; `_` for a wildcard label).
    static func selectorKeyForDecl(_ m: ActionMethod) -> String {
        guard !m.params.isEmpty else { return m.name }
        let labels = m.params.map { ($0.label.isEmpty ? "_" : $0.label) + ":" }.joined()
        return "\(m.name)(\(labels))"
    }

    /// The call expression for a dispatch case (0- or 1-arg action only).
    static func callExpression(_ m: ActionMethod) -> String {
        guard let p = m.params.first else { return "\(m.name)()" }
        let label = (p.label == "_" || p.label.isEmpty) ? "" : "\(p.label): "
        return "\(m.name)(\(label)\(castSenderExpression(toType: p.type)))"
    }

    /// Cast the dispatch `sender: Any?` to a 1-arg action's declared param type.
    static func castSenderExpression(toType type: String) -> String {
        let t = type.trimmingCharacters(in: .whitespaces)
        if t == "Any?" { return "sender" }
        if t.hasSuffix("?") { return "sender as? \(String(t.dropLast()))" }
        return "sender as! \(t)"
    }
}

// MARK: - Action-method collector

/// A target-action method found on a type: base name + parameters (external
/// label, declared type). AppKit actions have 0 or 1 (sender) param.
struct ActionMethod {
    let name: String
    let params: [(label: String, type: String)]
}

/// Walks a parsed file and records, per type (qualified name, source order), the
/// `@objc` methods — the target-action handlers AppKitLowering synthesizes a
/// `QuillActionDispatching` conformance for. Methods inside protocols are skipped
/// (a protocol requirement is not a dispatchable implementation).
private final class ActionMethodCollector: SyntaxVisitor {
    private(set) var orderedTypes: [String] = []
    private(set) var byType: [String: [ActionMethod]] = [:]
    private var typeStack: [String] = []
    private var protocolDepth = 0

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocolDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { protocolDepth -= 1 }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard protocolDepth == 0, !typeStack.isEmpty else { return .visitChildren }
        let isObjc = node.attributes.contains { element in
            if case .attribute(let attr) = element {
                return attr.attributeName.trimmedDescription == "objc"
            }
            return false
        }
        guard isObjc else { return .visitChildren }
        let params = node.signature.parameterClause.parameters.map { p in
            (label: p.firstName.text, type: p.type.trimmedDescription)
        }
        let typeName = typeStack.joined(separator: ".")
        if byType[typeName] == nil {
            byType[typeName] = []
            orderedTypes.append(typeName)
        }
        byType[typeName]?.append(ActionMethod(name: node.name.text, params: params))
        return .visitChildren
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

    // `import os.log` -> `import os`. Linux has no `os.log` submodule; the `os`
    // shadow (Sources/osShim) provides Logger / os_log. Preserves leading trivia.
    override func visit(_ node: ImportDeclSyntax) -> DeclSyntax {
        guard node.path.trimmedDescription == "os.log" else { return DeclSyntax(node) }
        var copy = node
        copy.path = ImportPathComponentListSyntax([
            ImportPathComponentSyntax(name: .identifier("os"))
        ])
        return DeclSyntax(copy)
    }

    // Widen `#if os(macOS)` / `#elseif os(macOS)` to `(os(macOS) || os(Linux))`
    // so desktop app source that branches macOS-vs-iOS compiles on Linux (Linux
    // takes the macOS branch instead of falling to an `#else #error`). Exact
    // match only — idempotent (the widened form won't re-match) and conservative
    // (compound / negated conditions are left untouched).
    override func visit(_ node: IfConfigClauseSyntax) -> IfConfigClauseSyntax {
        let recursed = super.visit(node)
        guard let condition = recursed.condition,
              condition.trimmedDescription == "os(macOS)" else {
            return recursed
        }
        var widened = ExprSyntax("os(macOS) || os(Linux)")
        widened.leadingTrivia = condition.leadingTrivia
        widened.trailingTrivia = condition.trailingTrivia
        var copy = recursed
        copy.condition = widened
        return copy
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
