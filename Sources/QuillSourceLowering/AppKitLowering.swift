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
///   * `Timer(timeInterval:repeats:){…}` → `QuillTimer.make(timeInterval:repeats:){…}`.
///     swift-corelibs-Foundation's `Timer.init` block is hard `@Sendable`, so
///     verbatim pre-Concurrency closures that call `@MainActor` UI methods (the
///     norm in AppKit apps — `NSViewController` is `@MainActor`) fail to compile
///     on Linux ("call to main actor-isolated method in a synchronous nonisolated
///     context"). `QuillTimer.make` (QuillFoundation) takes a NON-`@Sendable`
///     block, so the closure inherits `@MainActor`. A distinct symbol avoids the
///     overload ambiguity a same-name `Timer` overload would cause (trailing
///     closures match the last parameter by position). Only the block /
///     trailing-closure init is rewritten — the target-action
///     `Timer(timeInterval:target:selector:…)` and `Timer.scheduledTimer` are
///     left alone.
///   * `extension <LocalClass> { override func/var … }` → the `override` members
///     are moved into the class body. Swift forbids overriding a non-`@objc`
///     method from an extension; on macOS AppKit methods are `@objc` so it's
///     allowed, but on Linux there's no `@objc`, so the override must live in the
///     class itself (e.g. WireGuard's `LogViewController.cancelOperation`). Only
///     extensions of classes defined in the same file are touched; non-`override`
///     members stay in the extension.
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
        // in QuillFoundation (declared next to `Selector`; QuillAppKit aliases
        // it). On a second pass the source has no `@objc` left, so the
        // collector finds nothing and nothing is appended — the pass stays
        // idempotent.
        let collector = ActionMethodCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        // Pass 1: the in-place rewrites (strip @objc, #selector→Selector,
        // Timer→QuillTimer.make, os.log import, os(macOS) widening).
        let pass1 = AppKitRewriter().rewrite(tree)
        // Pass 2: move `override` members declared in `extension <LocalClass> { … }`
        // into the class body. Swift forbids overriding a non-@objc method from an
        // extension; on macOS these methods are @objc so it's allowed, but on Linux
        // there is no @objc, so the override must live in the class itself. Run after
        // pass 1 so the moved members carry pass-1's transforms (e.g. #selector).
        // App-agnostic — keyed only off "extension of a class defined in this file".
        let mergeCollector = ExtensionOverrideCollector(viewMode: .sourceAccurate)
        mergeCollector.walk(pass1)
        let merged: Syntax = mergeCollector.overridesByClass.isEmpty
            ? pass1
            : ExtensionOverrideMerger(
                localClassNames: mergeCollector.localClassNames,
                overridesByClass: mergeCollector.overridesByClass
              ).rewrite(pass1)
        let rewritten = merged.description
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
    /// `extension Type: QuillActionDispatching { public func quillPerform(_:with:) }`
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
            // `public`: a witness must be at least as accessible as the
            // conformance, and lowered framework code (Signal-iOS's SignalUI)
            // has public/open conformers where an implicitly-internal witness
            // is rejected ("must be declared public because it matches a
            // requirement in public protocol"). `public` is legal and
            // warning-free on internal/private conformers too (verified).
            lines.append("    public func quillPerform(_ selector: Selector, with sender: Any?) {")
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
        let stripped = stripAttributes(super.visit(node).cast(FunctionDeclSyntax.self))
        return DeclSyntax(repairDispatchWitnessAccess(stripped))
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

    /// Repair pass: upgrade a previously generated dispatch witness to `public`.
    ///
    /// `generateDispatchConformances` emits `public func quillPerform(_:with:)`,
    /// but earlier versions of this tool emitted it without an access modifier.
    /// Those stale blocks persist in already-lowered vendored trees (e.g.
    /// Signal-iOS's SignalUI, lowered in place by quill-signal-lower-ui.sh):
    /// the conformance generator keys off `@objc`, which a lowered tree no
    /// longer contains, so a re-run appends nothing and cannot self-heal. On a
    /// public conformer the implicitly-internal witness is rejected ("method
    /// must be declared public because it matches a requirement in public
    /// protocol 'QuillSelectorDispatching'") — Swift access-checks the matched
    /// member even though the protocol has a default implementation, so the
    /// default never rescues an under-accessible witness. Fixing it here (the
    /// long-lived tool) instead of hand-editing vendored files means any
    /// re-run of the standard lowering scripts repairs the whole tree.
    ///
    /// `quillPerform` is a Quill-invented name that only this generator ever
    /// writes, so keying on the exact generated signature is safe. Skips decls
    /// that already carry any access modifier (idempotent) and bodyless decls
    /// (protocol requirements may not carry access modifiers).
    private func repairDispatchWitnessAccess(_ node: FunctionDeclSyntax) -> FunctionDeclSyntax {
        guard node.name.text == "quillPerform", node.body != nil else { return node }
        let params = Array(node.signature.parameterClause.parameters)
        guard params.count == 2,
              params[0].firstName.text == "_",
              params[0].secondName?.text == "selector",
              params[0].type.trimmedDescription == "Selector",
              params[1].firstName.text == "with",
              params[1].secondName?.text == "sender",
              params[1].type.trimmedDescription == "Any?" else { return node }
        let accessKeywords: Set<String> = [
            "public", "open", "package", "internal", "fileprivate", "private",
        ]
        guard !node.modifiers.contains(where: { accessKeywords.contains($0.name.text) }) else {
            return node
        }
        // Re-anchor the decl's leading trivia (newline + indent) onto `public`,
        // which becomes the decl's new first token (generated decls carry no
        // attributes and no other modifiers).
        var copy = node
        let savedLeading = copy.leadingTrivia
        copy.leadingTrivia = Trivia()
        copy.modifiers = DeclModifierListSyntax(
            Array(copy.modifiers) + [DeclModifierSyntax(name: .keyword(.public), trailingTrivia: .space)]
        )
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

    // Timer(timeInterval:repeats:block:) -> QuillTimer.make(timeInterval:repeats:block:).
    // corelibs-Foundation's Timer.init block is hard @Sendable, so verbatim
    // pre-Concurrency closures that call @MainActor UI methods fail to compile on
    // Linux. QuillTimer.make (QuillFoundation, #if os(Linux)) takes a NON-@Sendable
    // block so the closure inherits @MainActor; it's a distinct symbol (no overload
    // ambiguity) returning a real Timer. Idempotent: the rewritten callee is a
    // member access (QuillTimer.make), not the `Timer` identifier, so it won't
    // re-match.
    override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
        guard let call = recursed.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "Timer",
              Self.isTimerBlockInit(call) else {
            return recursed
        }
        var make = ExprSyntax("QuillTimer.make")
        make.leadingTrivia = call.calledExpression.leadingTrivia
        make.trailingTrivia = call.calledExpression.trailingTrivia
        var copy = call
        copy.calledExpression = make
        return ExprSyntax(copy)
    }

    /// True iff `call` is `Timer(timeInterval:repeats:block:)` — labels
    /// `timeInterval` + `repeats` with the block as a trailing closure, or those
    /// two labels plus an explicit `block:` argument. Other `Timer` inits (the
    /// target-action `timeInterval:target:selector:userInfo:repeats:`,
    /// `fire:interval:…`) and `Timer.scheduledTimer` don't match and are untouched.
    static func isTimerBlockInit(_ call: FunctionCallExprSyntax) -> Bool {
        let labels: [String?] = call.arguments.map { $0.label?.text }
        if call.trailingClosure != nil {
            return labels == ["timeInterval", "repeats"]
        }
        return labels == ["timeInterval", "repeats", "block"]
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

// MARK: - Extension-override merge (Pass 2)

/// `true` if a member declares `override` (func / var / subscript).
private func isOverrideMember(_ item: MemberBlockItemSyntax) -> Bool {
    func hasOverride(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "override" }
    }
    if let f = item.decl.as(FunctionDeclSyntax.self) { return hasOverride(f.modifiers) }
    if let v = item.decl.as(VariableDeclSyntax.self) { return hasOverride(v.modifiers) }
    if let s = item.decl.as(SubscriptDeclSyntax.self) { return hasOverride(s.modifiers) }
    return false
}

/// Walks a (pass-1) tree and records: the names of classes defined in the file,
/// and — keyed by extended-type name — the `override` members declared inside
/// `extension <Type> { … }`. The merger only acts on extensions whose type is one
/// of the local classes.
private final class ExtensionOverrideCollector: SyntaxVisitor {
    private(set) var localClassNames: Set<String> = []
    private(set) var overridesByClass: [String: [MemberBlockItemSyntax]] = [:]

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        localClassNames.insert(node.name.text)
        return .visitChildren
    }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let overrides = node.memberBlock.members.filter(isOverrideMember)
        if !overrides.isEmpty {
            overridesByClass[node.extendedType.trimmedDescription, default: []].append(contentsOf: overrides)
        }
        return .visitChildren
    }
}

/// Moves the collected `override` members out of each `extension <LocalClass>`
/// and appends them to that class's body, where Swift permits the override
/// without an Objective-C runtime. The emptied extension is left in place (an
/// empty extension is harmless and keeps any conformance clause). Idempotent: a
/// second run finds no override-in-extension, so nothing moves.
private final class ExtensionOverrideMerger: SyntaxRewriter {
    private let localClassNames: Set<String>
    private let overridesByClass: [String: [MemberBlockItemSyntax]]

    init(localClassNames: Set<String>, overridesByClass: [String: [MemberBlockItemSyntax]]) {
        self.localClassNames = localClassNames
        self.overridesByClass = overridesByClass
        super.init()
    }

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(ClassDeclSyntax.self)
        guard localClassNames.contains(recursed.name.text),
              let moved = overridesByClass[recursed.name.text], !moved.isEmpty else {
            return DeclSyntax(recursed)
        }
        var copy = recursed
        var members = copy.memberBlock.members
        for item in moved { members.append(item) }
        copy.memberBlock.members = members
        return DeclSyntax(copy)
    }

    override func visit(_ node: ExtensionDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(ExtensionDeclSyntax.self)
        let typeName = recursed.extendedType.trimmedDescription
        guard localClassNames.contains(typeName), overridesByClass[typeName] != nil else {
            return DeclSyntax(recursed)
        }
        let kept = recursed.memberBlock.members.filter { !isOverrideMember($0) }
        guard kept.count != recursed.memberBlock.members.count else { return DeclSyntax(recursed) }
        var copy = recursed
        copy.memberBlock.members = MemberBlockItemListSyntax(kept)
        return DeclSyntax(copy)
    }
}
