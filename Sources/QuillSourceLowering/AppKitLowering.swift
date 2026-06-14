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
/// Runtime dispatch is wired by injecting a `quillPerform(_:with:)` method into
/// the CLASS BODY of every class that declared `@objc` actions (Pass 3 below);
/// the Qt/GTK control backing invokes it on click via QuillSelectorDispatching.
/// A class-body method is overridable, so subclass chains resolve dynamically;
/// see DispatchOverrideInjector and QuillSelectorDispatching (QuillFoundation).
public struct AppKitLowering {
    public init() {}

    /// Lowers a single Swift source string in memory.
    public func lower(_ source: String) -> String {
        let tree = Parser.parse(source: source)
        // Collect target-action methods (and each class's immediate superclass)
        // BEFORE @objc is stripped, so we can inject the `quillPerform` dispatch
        // the runtime (UIControl.sendActions / NSControl.sendAction / Timer /
        // CADisplayLink / UndoManager) invokes via `QuillSelectorDispatching`.
        // On a second pass the source has no `@objc` left, so the collector finds
        // nothing and nothing is injected — and the injector itself detects an
        // existing `quillPerform` and skips it, so the pass stays idempotent.
        let collector = ActionMethodCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        // Pass 1: the in-place rewrites (strip @objc, #selector→Selector,
        // Timer→QuillTimer.make, os.log import, os(macOS) widening).
        let pass1 = AppKitRewriter(
            dispatchReachabilityClassNames: Self.dispatchReachabilityClassNames(for: collector.orderedTypes)
        ).rewrite(tree)
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
        // Pass 3: inject the `quillPerform(_:with:)` target-action dispatch into
        // the CLASS BODY of every class that declared @objc actions. A class-body
        // method (vs. the old `extension X: QuillActionDispatching { … }`) is
        // overridable, so the per-class override chain resolves dynamically; see
        // DispatchOverrideInjector and QuillSelectorDispatching (QuillFoundation).
        let withDispatch: Syntax = collector.byType.isEmpty
            ? merged
            : DispatchOverrideInjector(
                byType: collector.byType,
                superclassByType: collector.superclassByType
              ).rewrite(merged)
        // Pass 4: prepend `nonisolated` to overrides of genuinely-nonisolated
        // NSObject members (init/description/isEqual/hash/debugDescription) so
        // they don't inherit SignalUI's `-default-isolation MainActor` and clash
        // with the nonisolated overridden declaration. See NonisolatedNSObjectMemberRewriter.
        return NonisolatedNSObjectMemberRewriter().rewrite(withDispatch).description
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

    // MARK: - Dispatch-override generation

    /// Render the `quillPerform(_:with:)` target-action dispatch method that the
    /// injector drops into a class body. `#selector(x)` became `Selector("x")`;
    /// this turns that token back into a real call without an ObjC runtime.
    /// General + automatic — built from the class's own `@objc` methods.
    ///
    /// `asOverride` selects the shape (see DispatchOverrideInjector for which is
    /// chosen per class):
    ///   * `true`  — `public override func quillPerform { switch …; default:
    ///     super.quillPerform(selector, with: sender) }`. The class inherits a
    ///     `quillPerform` (from a Quill shim root such as UIResponder, or another
    ///     lowered class through any number of transparent intermediates), so it
    ///     overrides it and falls through to `super` for inherited selectors.
    ///   * `false` — `public func quillPerform { switch …; default: break }`,
    ///     emitted alongside a `: QuillSelectorDispatching` conformance clause on
    ///     the class. The class's immediate superclass is `NSObject` (a chain
    ///     root that does not itself dispatch), so it newly conforms; `break`
    ///     terminates the chain (NSObject has no `quillPerform` to call).
    ///
    /// `indent` is the class-body member indentation (4 spaces per nesting level)
    /// so the injected method lines up with its siblings. `public`: a witness
    /// must be at least as accessible as its conformance, and lowered SignalUI
    /// has public/open conformers; `public override` is legal on any conformer.
    static func dispatchMethodSource(
        for methods: [ActionMethod],
        asOverride: Bool,
        indent: String
    ) -> String {
        let member = indent + "    "  // method body is one level deeper than the decl
        var lines: [String] = []
        lines.append("\(indent)// Auto-generated by AppKitLowering: target-action dispatch")
        lines.append("\(indent)// (turns Selector(\"…\") back into a real call — no ObjC runtime).")
        let modifiers = asOverride ? "public override func" : "public func"
        lines.append("\(indent)\(modifiers) quillPerform(_ selector: Selector, with sender: Any?) {")
        lines.append("\(member)switch selector.name {")
        for m in methods {
            lines.append("\(member)case \"\(selectorKeyForDecl(m))\": \(callExpression(m))")
        }
        // An override forwards unknown selectors up the chain so inherited
        // target-action still resolves; an NSObject-rooted conformer has nothing
        // above it, so it fails safe with `break`.
        lines.append("\(member)default: \(asOverride ? "super.quillPerform(selector, with: sender)" : "break")")
        lines.append("\(member)}")
        lines.append("\(indent)}")
        return lines.joined(separator: "\n")
    }

    /// AppKit actions take 0 or 1 (sender) param; anything else isn't a
    /// target-action, so it gets no dispatch case.
    static func emittableActions(_ methods: [ActionMethod]) -> [ActionMethod] {
        methods.filter { $0.params.count <= 1 }
    }

    /// Generated top-level extensions must be able to name every component in a
    /// nested action-handler path (`Outer.Inner.Handler`). Swift's `private`
    /// hides a nested type from a same-file extension outside the enclosing
    /// lexical scope, so the rewriter upgrades those path components to
    /// `fileprivate` before appending the extension. This is still file-private,
    /// but nameable by the generated same-file dispatch block.
    static func dispatchReachabilityClassNames(for orderedTypes: [String]) -> Set<String> {
        Set(orderedTypes.flatMap { typeName -> [String] in
            let parts = typeName.split(separator: ".").map(String.init)
            guard parts.count > 1 else { return [] }
            return Array(parts.dropFirst())
        })
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
/// `@objc` methods — the target-action handlers AppKitLowering injects a
/// `quillPerform` dispatch for — and each class's immediate superclass (to pick
/// the override vs. root-conformance shape). Methods inside protocols are skipped
/// (a protocol requirement is not a dispatchable implementation).
private final class ActionMethodCollector: SyntaxVisitor {
    private(set) var orderedTypes: [String] = []
    private(set) var byType: [String: [ActionMethod]] = [:]
    /// Qualified class name -> its immediate superclass name (the first entry of
    /// the inheritance clause; Swift requires the superclass first). `nil` (or a
    /// missing key) means "no class superclass in this file" — treated as a chain
    /// root. Only populated from `class` decls, never from extensions.
    private(set) var superclassByType: [String: String] = [:]
    private var typeStack: [String] = []
    private var protocolDepth = 0

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        // First inherited type = the superclass candidate (a leading protocol is
        // impossible in a class inheritance clause — the superclass, if any, is
        // first). A purely-protocol-conforming class has no superclass here.
        if let first = node.inheritanceClause?.inheritedTypes.first {
            superclassByType[typeStack.joined(separator: ".")] = first.type.trimmedDescription
        }
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
    private let dispatchReachabilityClassNames: Set<String>

    init(dispatchReachabilityClassNames: Set<String> = []) {
        self.dispatchReachabilityClassNames = dispatchReachabilityClassNames
        super.init()
    }

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
        let stripped = stripAttributes(super.visit(node).cast(ClassDeclSyntax.self))
        return DeclSyntax(repairGeneratedDispatchReachability(stripped))
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

    private func repairGeneratedDispatchReachability(_ node: ClassDeclSyntax) -> ClassDeclSyntax {
        guard dispatchReachabilityClassNames.contains(node.name.text) else { return node }
        var copy = node
        var didChange = false
        copy.modifiers = DeclModifierListSyntax(copy.modifiers.map { modifier in
            guard modifier.name.text == "private" else { return modifier }
            didChange = true
            var replacement = DeclModifierSyntax(name: .keyword(.fileprivate), trailingTrivia: modifier.trailingTrivia)
            replacement.leadingTrivia = modifier.leadingTrivia
            return replacement
        })
        return didChange ? copy : node
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

// MARK: - Dispatch-override injection (Pass 3)

/// Injects a `quillPerform(_:with:)` target-action dispatch method into the CLASS
/// BODY of every class that declared `@objc` action methods. A class-body method
/// is overridable (unlike the old `extension X: QuillActionDispatching { … }`,
/// whose static dispatch made per-class overrides unreachable and forced one
/// conformance per class — the source of the redundant-conformance and
/// cannot-override diagnostics). See QuillSelectorDispatching (QuillFoundation).
///
/// Per class, keyed by qualified name against the collected `@objc` actions:
///   * If the class already has a class-body `quillPerform(_:with:)` (a re-run, or
///     a hand-written one), it is left untouched — idempotent.
///   * If the immediate superclass is `NSObject` (or the class has no superclass),
///     it is a chain root: a `: QuillSelectorDispatching` conformance clause is
///     added and a non-`override` witness (with `default: break`) is injected.
///   * Otherwise the class inherits `quillPerform` from a Quill shim root
///     (UIResponder / UIPresentationController / UIBarButtonItem /
///     UIGestureRecognizer / AVPlayer) or another lowered class — possibly through
///     transparent intermediate classes that declare no actions — so an
///     `override` (with `default: super.quillPerform(…)`) is injected and no
///     conformance clause is added.
///
/// Limitation: `@objc` actions declared in an `extension` of a class defined in
/// ANOTHER file (e.g. SignalUI's `ImageEditorViewController+Blur.swift`) cannot be
/// folded into that class's single injected switch, since this pass is per-file
/// and the class decl is absent. Such actions still compile (no conformance is
/// emitted in the extension file — that would re-introduce the redundant
/// conformance) but their selectors fall to the base no-op. Same-file extension
/// actions ARE handled: the collector keys them onto the class, and the injected
/// switch calls them wherever they live.
private final class DispatchOverrideInjector: SyntaxRewriter {
    private let byType: [String: [ActionMethod]]
    private let superclassByType: [String: String]
    private var typeStack: [String] = []

    init(byType: [String: [ActionMethod]], superclassByType: [String: String]) {
        self.byType = byType
        self.superclassByType = superclassByType
        super.init()
    }

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        typeStack.append(node.name.text)
        let qualified = typeStack.joined(separator: ".")
        // Recurse first so nested classes are handled and any rewrites compose.
        let recursed = super.visit(node).cast(ClassDeclSyntax.self)
        typeStack.removeLast()

        guard let methods = byType[qualified] else { return DeclSyntax(recursed) }
        let emittable = AppKitLowering.emittableActions(methods)
        guard !emittable.isEmpty else { return DeclSyntax(recursed) }
        // Idempotent: skip a class that already carries a class-body witness.
        guard !Self.hasDispatchWitness(recursed) else { return DeclSyntax(recursed) }

        let isRoot = Self.isChainRoot(superclassByType[qualified])
        // Member indent: `typeStack` has been popped back to the ENCLOSING types,
        // so its count is this class's nesting depth; +1 for the class body.
        // 4 spaces per level matches Swift's house style.
        let indent = String(repeating: "    ", count: typeStack.count + 1)
        let methodSource = AppKitLowering.dispatchMethodSource(
            for: emittable, asOverride: !isRoot, indent: indent
        )

        var copy = recursed
        copy.memberBlock = Self.appending(methodSource, to: copy.memberBlock)
        if isRoot {
            copy = Self.addingConformance(to: copy)
        }
        return DeclSyntax(copy)
    }

    /// A class is a dispatch-chain ROOT (emit conformance + non-override witness)
    /// when its immediate superclass is `NSObject` or it has no class superclass;
    /// otherwise it inherits `quillPerform` and overrides it.
    static func isChainRoot(_ superclass: String?) -> Bool {
        guard let superclass else { return true }
        return superclass == "NSObject"
    }

    /// `true` if the class body already declares a `quillPerform(_:with:)` method
    /// (any access / `override`) — re-run guard.
    static func hasDispatchWitness(_ node: ClassDeclSyntax) -> Bool {
        node.memberBlock.members.contains { item in
            guard let fn = item.decl.as(FunctionDeclSyntax.self),
                  fn.name.text == "quillPerform" else { return false }
            let params = Array(fn.signature.parameterClause.parameters)
            return params.count == 2
                && params[0].type.trimmedDescription == "Selector"
                && params[1].type.trimmedDescription == "Any?"
        }
    }

    /// Append the rendered dispatch method (parsed as a member) to a class body,
    /// preceded by a blank line so it reads as its own member. `methodSource`
    /// carries its own indentation (comment + decl lines); the leading newlines
    /// become the parsed decl's leading trivia, keeping comments and indent.
    static func appending(_ methodSource: String, to block: MemberBlockSyntax) -> MemberBlockSyntax {
        let member = MemberBlockItemSyntax(decl: DeclSyntax("\n\n\(raw: methodSource)\n"))
        var members = block.members
        members.append(member)
        var copy = block
        copy.members = members
        return copy
    }

    /// Add `QuillSelectorDispatching` to a class's inheritance clause (creating
    /// one if absent), so an NSObject-rooted class newly conforms. Preserves the
    /// single space before the opening brace and emits a `, ` separator.
    static func addingConformance(to node: ClassDeclSyntax) -> ClassDeclSyntax {
        var copy = node
        if var clause = copy.inheritanceClause {
            // Already has inherited types (e.g. `: NSObject `). The last type
            // carries the trailing space before `{`; reuse it on the appended
            // conformance, and turn the old last type's trailing into a `, `.
            var types = clause.inheritedTypes
            var newTrailing: Trivia = .space
            if let lastIndex = types.indices.last {
                var last = types[lastIndex]
                newTrailing = last.trailingTrivia
                last.trailingTrivia = Trivia()
                last.trailingComma = .commaToken(trailingTrivia: .space)
                types[lastIndex] = last
            }
            let conformance = InheritedTypeSyntax(
                type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("QuillSelectorDispatching"))),
                trailingTrivia: newTrailing
            )
            types.append(conformance)
            clause.inheritedTypes = types
            copy.inheritanceClause = clause
        } else {
            // No inheritance clause: synthesize `: QuillSelectorDispatching `.
            // The name carries the trailing space before `{`; move it onto the
            // conformance so `class X: QuillSelectorDispatching {` spaces right.
            let nameTrailing = copy.name.trailingTrivia
            copy.name.trailingTrivia = Trivia()
            let conformance = InheritedTypeSyntax(
                type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("QuillSelectorDispatching"))),
                trailingTrivia: nameTrailing
            )
            copy.inheritanceClause = InheritanceClauseSyntax(
                colon: .colonToken(trailingTrivia: .space),
                inheritedTypes: InheritedTypeListSyntax([conformance])
            )
        }
        return copy
    }
}

// MARK: - Nonisolated NSObject-member overrides (Pass 4)

/// Prepends `nonisolated` to overrides of the genuinely-nonisolated NSObject
/// members — `init()`, `var description`, `var hash`, `var debugDescription`,
/// `func isEqual(_:)`. SignalUI builds with `-default-isolation MainActor`, which
/// would otherwise make these overrides `@MainActor` and clash with the
/// nonisolated overridden declaration ("main actor-isolated … has different actor
/// isolation from nonisolated overridden declaration").
///
/// Conservative: matches ONLY these exact NSObject member signatures, only when
/// the decl carries `override` and is not already `nonisolated` — so it never
/// touches an app's own same-named member that doesn't override NSObject's.
private final class NonisolatedNSObjectMemberRewriter: SyntaxRewriter {
    private static func hasOverride(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "override" }
    }
    private static func hasNonisolated(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "nonisolated" }
    }

    /// Insert `nonisolated` as the first modifier, re-anchoring the decl's leading
    /// trivia (newline + indent) onto it so the decl stays on its own line.
    private static func prependNonisolated<S: SyntaxProtocol & WithModifiersSyntax>(_ node: S) -> S {
        var copy = node
        let savedLeading = copy.leadingTrivia
        copy.leadingTrivia = Trivia()
        var nonisolated = DeclModifierSyntax(name: .keyword(.nonisolated), trailingTrivia: .space)
        nonisolated.leadingTrivia = Trivia()
        copy.modifiers = DeclModifierListSyntax([nonisolated] + Array(copy.modifiers))
        copy.leadingTrivia = savedLeading
        return copy
    }

    override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(FunctionDeclSyntax.self)
        guard Self.hasOverride(recursed.modifiers), !Self.hasNonisolated(recursed.modifiers) else {
            return DeclSyntax(recursed)
        }
        let params = Array(recursed.signature.parameterClause.parameters)
        let isIsEqual = recursed.name.text == "isEqual"
            && params.count == 1
            && params[0].firstName.text == "_"
            && params[0].type.trimmedDescription == "Any?"
        guard isIsEqual else { return DeclSyntax(recursed) }
        return DeclSyntax(Self.prependNonisolated(recursed))
    }

    override func visit(_ node: VariableDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(VariableDeclSyntax.self)
        guard Self.hasOverride(recursed.modifiers), !Self.hasNonisolated(recursed.modifiers) else {
            return DeclSyntax(recursed)
        }
        // Single `var name: Type` binding with an identifier pattern.
        guard recursed.bindingSpecifier.text == "var",
              recursed.bindings.count == 1,
              let binding = recursed.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type.trimmedDescription else {
            return DeclSyntax(recursed)
        }
        let name = pattern.identifier.text
        let matches = (name == "description" && type == "String")
            || (name == "debugDescription" && type == "String")
            || (name == "hash" && type == "Int")
        guard matches else { return DeclSyntax(recursed) }
        return DeclSyntax(Self.prependNonisolated(recursed))
    }

    override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(InitializerDeclSyntax.self)
        guard Self.hasOverride(recursed.modifiers), !Self.hasNonisolated(recursed.modifiers) else {
            return DeclSyntax(recursed)
        }
        // Exactly `init()` — no params, no failability, no async/throws/generics.
        guard recursed.optionalMark == nil,
              recursed.genericParameterClause == nil,
              recursed.signature.parameterClause.parameters.isEmpty,
              recursed.signature.effectSpecifiers == nil else {
            return DeclSyntax(recursed)
        }
        return DeclSyntax(Self.prependNonisolated(recursed))
    }
}
