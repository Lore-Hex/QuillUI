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
///   * `#imageLiteral(resourceName: "X")` → `UIImage(named: "X")!`. Xcode's
///     asset-literal macro is unavailable on Linux; the shim provides
///     `UIImage(named:)`. Force-unwrapped because `#imageLiteral` is non-optional.
///   * `#keyPath(Type.member.path)` → `"member.path"` (the dotted member path as a
///     string literal, dropping the leading type). On Apple `#keyPath` yields the
///     ObjC key string; with no ObjC runtime on Linux the member path is what
///     KVC-string call sites (`CABasicAnimation(keyPath:)`) actually need.
///   * `.<delegateMethod>?(` → `.<delegateMethod>(` for a maintained set of UIKit
///     delegate optional-method name prefixes. On Apple these UIKit delegate
///     methods are `@objc optional`, called with a trailing `?`; the Linux shim
///     declares them as NON-optional protocol methods, so the inner `?` (between
///     the member name and the call's `(`) fails to compile. Conservatively gated:
///     only `.method?(` where `method` matches a known UIKit-delegate name, so a
///     stored optional-closure call (`foo?(args)`) is never touched.
///   * `extension <LocalClass> { override func/var … }` → the `override` members
///     are moved into the class body. Swift forbids overriding a non-`@objc`
///     method from an extension; on macOS AppKit methods are `@objc` so it's
///     allowed, but on Linux there's no `@objc`, so the override must live in the
///     class itself (e.g. WireGuard's `LogViewController.cancelOperation`). Only
///     extensions of classes defined in the same file are touched; non-`override`
///     members stay in the extension. A companion cross-file pass also relocates a
///     base class's NON-override extension method into the base's body when a
///     subclass in ANOTHER file overrides it (same Linux limitation, surfaced
///     across files via the `HierarchyMap`).
///
/// Runtime dispatch is wired by injecting a `quillPerform(_:with:)` method into
/// the CLASS BODY of every class that declared `@objc` actions (Pass 3 below);
/// the Qt/GTK control backing invokes it on click via QuillSelectorDispatching.
/// A class-body method is overridable, so subclass chains resolve dynamically;
/// see DispatchOverrideInjector and QuillSelectorDispatching (QuillFoundation).
///
/// ─────────────────────────────────────────────────────────────────────────────
/// ACTOR-ISOLATION POLICY (Pass 4 — `NonisolatedNSObjectMemberRewriter`)
/// ─────────────────────────────────────────────────────────────────────────────
/// SignalUI (and the other upstream trees) build with `-default-isolation
/// MainActor`, so every upstream class is implicitly `@MainActor`. The shim
/// modules (QuillUIKit / QuillAppKit / AVFoundation) build WITHOUT that flag, so
/// their `@MainActor` is whatever the author wrote — and Linux's `NSObject` is
/// swift-corelibs-Foundation's, whose `init()` / `isEqual` / `hash` /
/// `description` / `debugDescription` are all genuinely `nonisolated`.
///
/// Swift's override rule: **an override must have the SAME actor isolation as the
/// declaration it overrides.** A `@MainActor` member overriding a `nonisolated`
/// one (or vice-versa) is a hard error even under `-strict-concurrency=minimal`
/// once `-default-isolation` is in play, because isolation is part of the type,
/// not a concurrency *diagnostic*. So the only internally-consistent state for a
/// member is "the whole override chain agrees on isolation."
///
/// There are TWO distinct NSObject member populations, and they want OPPOSITE
/// answers — which is why a blanket pass (sig6-1's first cut) made things worse
/// (140 → 450 init mismatches):
///
///  (A) `isEqual` / `hash` / `description` / `debugDescription`.
///      No shim base ever re-declares these as `@MainActor`; the nearest
///      declaration up every chain is swift-corelibs `NSObject`'s — `nonisolated`.
///      => an override in ANY `@MainActor` upstream class MUST be `nonisolated`.
///      Applied UNCONDITIONALLY. (This part of sig6-1 was correct; kept.)
///
///  (B) `init()` / `init(coder:)` / `init(frame:)` / `init(nibName:bundle:)`.
///      The nearest init up the chain depends on the ROOT:
///        • Rooted at a `@MainActor` shim base (UIResponder → the whole
///          UIView/UIViewController forest, UIPresentationController,
///          UIBarButtonItem, UIGestureRecognizer, AVPlayer): those bases declare
///          `@MainActor` designated inits, so the forest is `@MainActor`-CONSISTENT.
///          => leave upstream inits `@MainActor` (the default). DO NOT annotate.
///          sig6-1 wrongly forced these `nonisolated`, mismatching their
///          `@MainActor` siblings/subclasses — the bulk of the 450 regression.
///        • Rooted DIRECTLY at `NSObject` with no `@MainActor` shim base between
///          (model/helper objects that happen to be `@MainActor`): the nearest
///          init is `NSObject`'s `nonisolated init()`.
///          => the overriding init MUST be `nonisolated`. We annotate explicit
///          inits AND synthesize an explicit `nonisolated override init()` into
///          such a class that has no initializer at all (so its otherwise-
///          IMPLICIT `@MainActor init()` — which sig6-1 could never reach — stops
///          mismatching `NSObject`).
///
/// Distinguishing (B)'s two cases needs GLOBAL hierarchy knowledge (a class's
/// root can be a shim base reached through intermediates in OTHER files), so the
/// init handling — like the dispatch-witness override/root decision (Pass 3) —
/// consults the cross-file `HierarchyMap` built by `lowerInPlace`'s pre-pass.
/// In single-file mode (no map) the pass falls back to the file-local superclass
/// chain plus the static shim-root set, which is exact for same-file chains.
///
/// The known `@MainActor` shim roots are enumerated in `HierarchyMap.shimRoots`
/// (grep `Sources/` for `open func quillPerform` to keep it in sync). Keeping the
/// chain consistent at its root is what drives the init-mismatch count down
/// without trading it for "call to @MainActor member from nonisolated context"
/// errors (which the *opposite* choice — nonisolated-ing the forest — would mint).
///
/// ─────────────────────────────────────────────────────────────────────────────
/// ACTOR-ISOLATION RIPPLE (Pass 5 — `DeinitMainActorIsolationRewriter`)
/// ─────────────────────────────────────────────────────────────────────────────
/// Pass 4 keeps the override-isolation MATRIX consistent (a `@MainActor` member
/// overrides a `@MainActor` base, a `nonisolated` identity member overrides
/// NSObject's). That fixes the declaration side. The FLIP side is the CALL side:
/// a `nonisolated` upstream context that TOUCHES a `@MainActor` member errors with
/// "call to main actor-isolated … in a synchronous nonisolated context" /
/// "main actor-isolated property … can not be referenced/mutated from a
/// nonisolated context".
///
/// The single largest, app-agnostic, provably-safe source of such contexts is
/// **`deinit`**. Under `-default-isolation MainActor` this bites in TWO ways:
///   1. STRUCTURAL: a `@MainActor` class has an ISOLATED deinit, so a subclass's
///      deinit — `nonisolated` by default — mismatches it ("nonisolated
///      deinitializer has different actor isolation from main actor-isolated
///      overridden declaration"). This fires on EVERY forest deinit, even an empty
///      one that touches nothing.
///   2. BODY: a forest deinit routinely touches the `@MainActor` members the rest
///      of the class uses freely (`view.removeFromSuperview()`,
///      `timer?.invalidate()` on a `@MainActor` property, nil-ing a `@MainActor`
///      child/observer, reading a `@MainActor` token) — the "main actor-isolated …
///      from a synchronous nonisolated context" ripple.
///
/// IMPORTANT — why NOT "make the shim members `nonisolated`" (the brief's first
/// instinct): it does not work for the call side, and would regress Pass 4.
/// Empirically (swiftc, Swift 6.2, `-default-isolation MainActor`):
///   • `@preconcurrency` on the CONFORMANCE only lets a `@MainActor` witness
///     SATISFY a `nonisolated` requirement; the member STAYS `@MainActor`, so the
///     call site still errors.
///   • Marking the witness/member `nonisolated` just MOVES the error inward: the
///     `nonisolated` body then "can not reference `@MainActor` property `x`".
///   • The members in the ripple (`removeFromSuperview`, `frame`,
///     `accessibilityIdentifier`, `view`) are `open` and/or mutate `@MainActor`
///     stored state, so nonisolated-ing them BOTH fails AND breaks the override
///     matrix Pass 4 fixed (every upstream `override` would then mismatch). And
///     none of that even addresses the STRUCTURAL deinit mismatch (1), which has
///     nothing to do with the body.
///
/// The clean fix for BOTH (1) and (2) is to ISOLATE the deinit itself:
/// `@MainActor deinit { … }` (Swift 6.2 isolated deinitializers, SE-0371). Its
/// isolation then MATCHES the `@MainActor` base's isolated deinit, and its body
/// runs on the main actor so the member access is legal — the runtime hops to the
/// main actor to run the deinit. No body rewrite, no `MainActor.assumeIsolated`
/// wrap, no runtime-trap risk.
///
/// So Pass 5 prepends `@MainActor` to a deinit — but ONLY for a class that PROVABLY
/// descends from a `@MainActor` UIKit/AppKit view-or-controller forest root
/// (`deinitChainReachesMainActorForestRoot`). Model/helper objects (NSObject-
/// direct, or an unknown foreign base) are LEFT ALONE: their `nonisolated` deinit
/// MATCHES NSObject's `nonisolated` base deinit, so it does not error in the first
/// place, and they may legitimately dealloc off-main (caches, network results) —
/// isolating them would be both needless and wrong. The prepend is idempotent (a
/// deinit already carrying `@MainActor` / `nonisolated` / `isolated` is skipped).
public struct AppKitLowering {
    public init() {}

    /// Lowers a single Swift source string in memory.
    ///
    /// `hierarchy` carries cross-file class→superclass knowledge gathered by
    /// `lowerInPlace`'s pre-pass; pass `nil` (the default) for single-file use,
    /// in which case Pass 3/4 fall back to the file-local superclass chain.
    public func lower(_ source: String, hierarchy: HierarchyMap? = nil) -> String {
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
        // Merge the file-local class→superclass map AND file-local action classes
        // with the cross-file one so both Pass 3 (dispatch) and Pass 4 (isolation)
        // can walk full chains even in single-file mode (no pre-pass `hierarchy`).
        let localActionClasses = Set(collector.byType.compactMap { name, methods in
            AppKitLowering.emittableActions(methods).isEmpty ? nil : HierarchyMap.simpleName(name)
        })
        let resolvedHierarchy = (hierarchy ?? HierarchyMap())
            .merging(superclassByType: collector.superclassByType,
                     actionClasses: localActionClasses,
                     knownClasses: collector.knownClasses,
                     overriddenSignatures: collector.overriddenSignaturesByType,
                     classesDeclaringNoArgInit: collector.classesDeclaringNoArgInit)
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
        // Pass 2b (cross-file): a BASE class's NON-override method declared in an
        // `extension <Base> { func m … }` must also move into the base's class body
        // when a subclass in ANOTHER file declares `override func m …`. Linux can't
        // override an extension member, so the subclass override fails unless `m`
        // lives in the base's body. Keyed off the cross-file `HierarchyMap`
        // (`someSubclassOverrides`). Also strips a stray `override` from a subclass's
        // `forwardingTarget(for:)` (declared in an extension of FOREIGN `NSObject`,
        // which can't move) — see CrossFileExtensionMemberRelocator. Idempotent.
        let relocateCollector = CrossFileExtensionRelocateCollector(
            hierarchy: resolvedHierarchy, viewMode: .sourceAccurate
        )
        relocateCollector.walk(merged)
        let relocated: Syntax = (relocateCollector.relocatableByClass.isEmpty
                                 && relocateCollector.overrideStripTargets.isEmpty)
            ? merged
            : CrossFileExtensionMemberRelocator(
                relocatableByClass: relocateCollector.relocatableByClass,
                overrideStripTargets: relocateCollector.overrideStripTargets
              ).rewrite(merged)
        // Pass 3: inject the `quillPerform(_:with:)` target-action dispatch into
        // the CLASS BODY of every class that declared @objc actions. A class-body
        // method (vs. the old `extension X: QuillActionDispatching { … }`) is
        // overridable, so the per-class override chain resolves dynamically; see
        // DispatchOverrideInjector and QuillSelectorDispatching (QuillFoundation).
        let withDispatch: Syntax = collector.byType.isEmpty
            ? relocated
            : DispatchOverrideInjector(
                byType: collector.byType,
                hierarchy: resolvedHierarchy
              ).rewrite(relocated)
        // Pass 3b: `@NSApplicationDelegateAdaptor(Foo.self)` needs to construct
        // `Foo` through a generic `init()` requirement on Linux. swift-corelibs
        // `NSObject.init()` is not `required`, so app delegates opt into the
        // existing QuillReusableView marker mechanically here.
        let withAppDelegateConstruction = NSApplicationDelegateReusableConformanceRewriter()
            .rewrite(withDispatch)
        // Pass 4: actor-isolation policy (see the type-level doc block). Always
        // `nonisolated`-annotates overrides of the genuinely-nonisolated NSObject
        // identity members (isEqual/hash/description/debugDescription); for inits
        // it only acts on classes rooted DIRECTLY at NSObject (per `hierarchy`),
        // leaving the `@MainActor`-consistent UIView/UIViewController forest alone,
        // and synthesizes a `nonisolated override init()` into an NSObject-direct
        // `@MainActor` class that declares no initializer at all.
        let withIsolation = NonisolatedNSObjectMemberRewriter(hierarchy: resolvedHierarchy)
            .rewrite(withAppDelegateConstruction)
        // Pass 5: actor-isolation RIPPLE — `deinit`. Under `-default-isolation
        // MainActor` a `@MainActor` class has an ISOLATED deinit, so a subclass's
        // (nonisolated-by-default) deinit STRUCTURALLY mismatches it AND can't touch
        // the `@MainActor` UI members it teardown-uses (`removeFromSuperview()`,
        // `timer?.invalidate()`, nil-ing a `@MainActor` child). This pass prepends
        // `@MainActor` to the deinit of a PROVABLY forest-rooted class (Swift 6.2
        // isolated deinit) — fixing both at once, the runtime hops to main to run
        // it. Model/foreign-base classes are left alone. See the type-level doc.
        let withDeinit = DeinitMainActorIsolationRewriter(hierarchy: resolvedHierarchy)
            .rewrite(withIsolation)
        // Pass 6: actor-isolation — LOCAL nested functions. A function declared inside
        // a closure or another function body is `nonisolated` by default, so under
        // `-default-isolation MainActor` it cannot touch the `@MainActor` UI state its
        // surrounding (MainActor) context uses freely (`self.view`,
        // `viewController.present(…)`, `.overrideUserInterfaceStyle`). The whole
        // SignalUI module is MainActor-by-default, so marking such LOCAL funcs
        // `@MainActor` matches their lexical surroundings and the state they touch.
        // Conservative: ONLY funcs nested in executable code (a function/closure body),
        // never top-level or type-member funcs (those already get default isolation).
        // See LocalFunctionMainActorRewriter.
        let lowered = LocalFunctionMainActorRewriter()
            .rewrite(withDeinit).description
        return FoundationLowering().lower(lowered)
    }

    /// Lowers every `.swift` file under `sourceDir` *in place*. Mirrors
    /// `SwiftUILowering.lowerInPlace`: files unchanged by the pass aren't
    /// rewritten (no mtime churn). Returns the number of `.swift` files visited.
    ///
    /// Runs in TWO phases. The dispatch-witness override/root decision (Pass 3)
    /// and the init-isolation decision (Pass 4) both need to know a class's
    /// transitive superclass chain, which can thread through intermediate classes
    /// declared in OTHER files. Phase 1 scans every `.swift` file to build a
    /// cross-file `HierarchyMap` (class→superclass for every class, plus the set
    /// of classes that will receive a dispatch witness). Phase 2 lowers each file
    /// with that map in hand. The scan parses each file once with the lightweight
    /// `HierarchyScanner`; the full rewrite re-parses in `lower`.
    @discardableResult
    public func lowerInPlace(
        sourceDir: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        let normalizedSource = sourceDir.resolvingSymlinksInPath()

        // Phase 1: pre-pass — build the global hierarchy map from all files.
        var hierarchy = HierarchyMap()
        guard let scanEnumerator = fileManager.enumerator(
            at: normalizedSource,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        for case let fileURL as URL in scanEnumerator {
            let resolved = fileURL.resolvingSymlinksInPath()
            let resourceValues = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            guard resolved.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: resolved, encoding: .utf8)
            hierarchy.ingest(source: source)
        }

        // Phase 2: lower each file with the cross-file hierarchy in hand.
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
            let lowered = lower(original, hierarchy: hierarchy)
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

// MARK: - Cross-file hierarchy map

/// Cross-file class-inheritance knowledge built by `lowerInPlace`'s pre-pass.
/// Both the dispatch-witness override/root decision (Pass 3) and the
/// init-isolation decision (Pass 4) need to walk a class's transitive superclass
/// chain, which can thread through intermediate classes declared in OTHER files
/// (e.g. `Foo: SomeHelper` where `SomeHelper: NSObject` lives elsewhere and has
/// no `@objc` actions). The map is keyed by the **simple** (unqualified) class
/// name — Swift's source-level inheritance clause names the superclass simply, so
/// that is the only key we can match a chain against without full type resolution.
/// Nested types collapse to their leaf name here; collisions are vanishingly rare
/// in the real trees and degrade gracefully (a chain that can't be resolved is
/// treated as ending at its last known link, the conservative outcome).
public struct HierarchyMap {
    /// simple class name -> simple superclass name (first inheritance entry).
    private(set) var superclassByClass: [String: String] = [:]
    /// Simple names of classes that declare `@objc` actions (so they WILL receive
    /// an injected `quillPerform` witness — i.e. an ancestor with one means the
    /// descendant should `override` rather than newly conform).
    private(set) var classesWithActions: Set<String> = []
    /// Simple names of EVERY class declared anywhere in the tree (with or without a
    /// superclass). Under `-default-isolation MainActor` an in-tree upstream class is
    /// `@MainActor`, so its (possibly implicit) deinit is isolated — knowing a base
    /// is in-tree is how Pass 5 detects "this subclass deinit overrides a `@MainActor`
    /// base deinit" even when the chain ultimately roots at `NSObject` (the
    /// StickerPackDataSource case). Also lets a subclass-override scan find subclasses.
    private(set) var knownClasses: Set<String> = []
    /// Simple owner-type name -> function signature keys it declares with `override`
    /// (in its class body OR an extension). Drives Pass 2's CROSS-FILE relocator: a
    /// base class's NON-override method declared in an `extension` must move into the
    /// base's class body when a subclass elsewhere overrides it (extension members
    /// aren't overridable on Linux). See `someSubclassOverrides`.
    private(set) var overriddenSignaturesByClass: [String: Set<String>] = [:]
    /// Simple names of classes that declare an EXPLICIT no-arg `init()` in their body.
    /// A class WITHOUT one inherits/synthesizes its `init()`, whose isolation follows
    /// the base; a class WITH one has the isolation we choose for that decl. Used by
    /// `classHasNonisolatedNoArgInit` (Pass 4 / A3) to decide whether a base's `init()`
    /// is nonisolated: a ROOT class with no explicit `init()` has a compiler-synthesized
    /// `init()` that is genuinely `nonisolated` under `-default-isolation MainActor`
    /// (the SheetDisplayableError case), so its subclasses' `init()` overrides must be
    /// `nonisolated` to match.
    private(set) var classesDeclaringNoArgInit: Set<String> = []

    public init() {}

    /// The Apple-framework shim base classes that DECLARE a class-body
    /// `quillPerform` witness (grep `Sources/` for `open func quillPerform`). A
    /// class whose chain reaches one of these inherits a witness, so it (or a
    /// transparent intermediate) must `override`, never newly conform. These are
    /// also all `@MainActor` (UIResponder forest, etc.) or — for the AppKit
    /// roots — sit above `@MainActor` view/controller bases.
    static let dispatchShimRoots: Set<String> = [
        "UIResponder", "UIPresentationController", "UIBarButtonItem",
        "UIGestureRecognizer", "AVPlayer",
        "NSResponder", "NSMenu", "NSMenuItem", "NSAlert",
    ]

    /// Well-known PROTOCOL names that appear FIRST in a class inheritance clause in
    /// the upstream trees (`class Foo: Error`, `class Bar: CustomDebugStringConvertible`,
    /// `class Baz: Comparable`). Swift requires a class's superclass to be listed
    /// first, so a class whose first inherited type is one of these has NO class
    /// superclass — it is a ROOT class. The HierarchyScanner / ActionMethodCollector
    /// must NOT record such a name as a "superclass": doing so makes the chain walks
    /// (`dispatchWitnessIsOverride`, the init-root checks) mistake a protocol for a
    /// foreign base class. Two concrete bugs this avoids:
    ///   * `SignalAttachment: CustomDebugStringConvertible` — a no-class-superclass
    ///     class — was emitting an `override func quillPerform { … super.quillPerform }`
    ///     ("method does not override" / "'super' cannot be used … no superclass").
    ///   * `SheetDisplayableError: Error` was treated as having an `Error` base.
    /// Conservative: only the standard-library / Foundation protocols actually seen
    /// first in a class clause here. A user TYPE named identically is vanishingly
    /// unlikely; if one appeared, treating it as "no class super" degrades to the
    /// safe root outcome. Extend as new protocol-first roots surface.
    static let knownInheritedProtocolNames: Set<String> = [
        "Error", "LocalizedError", "CustomNSError",
        "CustomStringConvertible", "CustomDebugStringConvertible",
        "Comparable", "Equatable", "Hashable", "Identifiable",
        "Codable", "Decodable", "Encodable",
        "Sendable", "CaseIterable", "RawRepresentable",
        "CustomKeyboard",
    ]

    /// True iff `name` (simple, no qualifier/generics) is a known protocol that can
    /// appear first in a class inheritance clause — i.e. it is NOT a class superclass.
    static func isKnownInheritedProtocol(_ name: String) -> Bool {
        knownInheritedProtocolNames.contains(simpleName(name))
    }

    /// Shim base classes that are `@MainActor` AND declare/inherit `@MainActor`
    /// designated initializers, so an upstream subclass's init should stay
    /// `@MainActor` (the forest is isolation-consistent). A class whose init
    /// chain reaches one of these must NOT be `nonisolated`-annotated. (AppKit's
    /// `NSView`/`NSWindow` sit under the non-@MainActor `NSResponder`, but their
    /// own inits are `@MainActor`-faithful; `NSViewController` already annotates
    /// its inits `nonisolated` in the shim, so it is intentionally absent here.)
    ///
    /// This same set is the forest gate for the `deinit`-isolation pass (Pass 5,
    /// `deinitChainReachesMainActorForestRoot`). It must therefore enumerate the
    /// COMMON concrete UIView/UIControl leaf bases that upstream subclasses descend
    /// from directly (`UITextView`, `UILabel`, `UIImageView`, `UIScrollView`,
    /// `UITableView`/cell, `UICollectionView`/cell, `UIButton`, `UIStackView`, …) —
    /// not just the abstract roots — so e.g. `BodyRangesTextView: OWSTextView:
    /// UITextView` is recognized as forest-rooted even when the only foreign link in
    /// its chain is `UITextView`. All of these are `@MainActor` with `@MainActor`
    /// inits, so widening the set is sound for both the init (Pass 4) and deinit
    /// (Pass 5) decisions.
    static let mainActorInitRoots: Set<String> = [
        // Abstract roots.
        "UIResponder", "UIView", "UIViewController", "UIControl",
        "UIPresentationController", "UIBarButtonItem", "UIGestureRecognizer",
        "AVPlayer",
        // Concrete UIView/UIControl leaf bases upstream subclasses descend from.
        "UITextView", "UILabel", "UIImageView", "UIScrollView",
        "UITableView", "UITableViewCell", "UITableViewHeaderFooterView",
        "UICollectionView", "UICollectionViewCell", "UICollectionReusableView",
        "UIButton", "UIStackView", "UITextField", "UISlider", "UISwitch",
        "UIPickerView", "UIWindow", "UINavigationBar", "UIToolbar",
        "UIVisualEffectView", "UIActivityIndicatorView", "UIProgressView",
        "UIPageControl", "UISegmentedControl", "UISearchBar",
        // AppKit leaf bases.
        "NSView", "NSControl", "NSWindow", "NSButton", "NSTextView",
    ]

    /// Fold one source file's class declarations into the map (pre-pass).
    mutating func ingest(source: String) {
        let tree = Parser.parse(source: source)
        let scanner = HierarchyScanner(viewMode: .sourceAccurate)
        scanner.walk(tree)
        for (name, superName) in scanner.superclassByClass where superclassByClass[name] == nil {
            superclassByClass[name] = superName
        }
        classesWithActions.formUnion(scanner.classesWithActions)
        knownClasses.formUnion(scanner.knownClasses)
        for (owner, sigs) in scanner.overriddenSignaturesByClass {
            overriddenSignaturesByClass[owner, default: []].formUnion(sigs)
        }
        classesDeclaringNoArgInit.formUnion(scanner.classesDeclaringNoArgInit)
    }

    /// Return a copy with the file-local class→superclass entries and the
    /// file-local action-class set merged in (the local data wins for same-file
    /// classes, which is harmless — it agrees with the pre-pass — and lets
    /// single-file `lower(_:)` resolve same-file chains with no pre-pass).
    func merging(
        superclassByType localSuperclassByType: [String: String],
        actionClasses localActionClasses: Set<String> = [],
        knownClasses localKnownClasses: Set<String> = [],
        overriddenSignatures localOverriddenSignatures: [String: Set<String>] = [:],
        classesDeclaringNoArgInit localNoArgInit: Set<String> = []
    ) -> HierarchyMap {
        var copy = self
        for (qualified, superName) in localSuperclassByType {
            let simple = HierarchyMap.simpleName(qualified)
            copy.superclassByClass[simple] = HierarchyMap.simpleName(superName)
        }
        copy.classesWithActions.formUnion(localActionClasses)
        copy.knownClasses.formUnion(localKnownClasses.map(HierarchyMap.simpleName))
        for (owner, sigs) in localOverriddenSignatures {
            copy.overriddenSignaturesByClass[HierarchyMap.simpleName(owner), default: []].formUnion(sigs)
        }
        copy.classesDeclaringNoArgInit.formUnion(localNoArgInit.map(HierarchyMap.simpleName))
        return copy
    }

    /// Strip a leading type qualifier and any generic argument list, yielding the
    /// simple class name the inheritance clause would name (`Outer.Inner` ->
    /// `Inner`, `NSLayoutAnchor<X>` -> `NSLayoutAnchor`).
    static func simpleName(_ name: String) -> String {
        var n = name
        if let lt = n.firstIndex(of: "<") { n = String(n[..<lt]) }
        if let dot = n.lastIndex(of: ".") { n = String(n[n.index(after: dot)...]) }
        return n.trimmingCharacters(in: .whitespaces)
    }

    /// A class needing a dispatch witness emits `override` (vs. newly conform) iff
    /// it INHERITS a witness — i.e. walking its superclass chain reaches a
    /// dispatching ancestor (a known shim root, or an in-tree class that itself
    /// gets a witness) BEFORE reaching `NSObject`. If the chain reaches literal
    /// `NSObject` first (e.g. `Foo: NSObject`, or `Foo: SomeHelper` where the
    /// helper is a plain action-less `NSObject` subclass), the class ROOTS its
    /// own chain and newly conforms with a non-override witness. If the chain
    /// instead ends at an unknown NON-`NSObject` name (a foreign/shim base we
    /// can't see, such as `UIViewController`/`UITableViewCell`, which descend from
    /// a dispatch root), it is treated as inheriting a witness → `override`.
    func dispatchWitnessIsOverride(forClassNamed className: String) -> Bool {
        var seen: Set<String> = [HierarchyMap.simpleName(className)]
        var current = HierarchyMap.simpleName(className)
        while true {
            guard let superName = superclassByClass[current] else {
                // Chain ended. If the last link we know of is itself a foreign
                // base (current is not a class we recorded a super for and isn't
                // NSObject), `current` is that base. A bare `NSObject` super is
                // handled in-loop below; reaching here means `current` is an
                // unknown non-NSObject leaf base → it descends from a dispatch
                // root → override. (A literal root `class X {}` with no super has
                // current == X and never entered the loop body's NSObject check.)
                return current != HierarchyMap.simpleName(className) && current != "NSObject"
            }
            let simpleSuper = HierarchyMap.simpleName(superName)
            if simpleSuper == "NSObject" { return false }           // chain root
            if HierarchyMap.dispatchShimRoots.contains(simpleSuper)
                || classesWithActions.contains(simpleSuper) {
                return true                                          // inherits a witness
            }
            guard seen.insert(simpleSuper).inserted else { return false } // cycle
            current = simpleSuper
        }
    }

    /// An `@MainActor` class's `init` overrides should stay `@MainActor` (leave
    /// them alone) UNLESS we can prove the class is rooted DIRECTLY at the
    /// genuinely-`nonisolated` `NSObject` init — i.e. its superclass chain reaches
    /// literal `NSObject` (through the in-tree map) WITHOUT passing any `@MainActor`
    /// shim init-root (the UIView/UIViewController forest etc.). Only then is the
    /// overriding init `nonisolated`-annotated / synthesized.
    ///
    /// This is deliberately asymmetric/conservative: a chain that ends at an
    /// UNKNOWN foreign base (not literal `NSObject`, e.g. a real UIKit class we
    /// can't see) is treated as `@MainActor`-rooted and LEFT ALONE — most such
    /// bases are `@MainActor` UIKit view/controllers whose faithful inits are
    /// `@MainActor`, so the default keeps the chain consistent. We only act where
    /// the `NSObject` root is provable, which is exactly the model/helper-object
    /// population that drove the genuine init mismatches.
    func initChainIsMainActorRooted(forClassNamed className: String) -> Bool {
        !chainReachesLiteralNSObjectDirectly(forClassNamed: className)
    }

    /// True iff `className`'s chain reaches literal `NSObject` without passing any
    /// `@MainActor` shim init-root. False if a forest root is hit first OR the
    /// chain ends at an unknown non-`NSObject` base (foreign — leave alone).
    private func chainReachesLiteralNSObjectDirectly(forClassNamed className: String) -> Bool {
        let simple = HierarchyMap.simpleName(className)
        if HierarchyMap.mainActorInitRoots.contains(simple) { return false }
        var seen: Set<String> = [simple]
        var current = simple
        while let superName = superclassByClass[current] {
            let simpleSuper = HierarchyMap.simpleName(superName)
            if simpleSuper == "NSObject" { return true }            // provable NSObject root
            if HierarchyMap.mainActorInitRoots.contains(simpleSuper) { return false } // forest
            guard seen.insert(simpleSuper).inserted else { return false } // cycle
            current = simpleSuper
        }
        return false // chain ended at an unknown foreign base → leave alone
    }

    /// True iff `className`'s no-arg `init()` ends up `nonisolated` under
    /// `-default-isolation MainActor` — so any in-tree SUBCLASS's `init()` override
    /// must also be `nonisolated` to match (the override-isolation rule). Three
    /// nonisolated-init populations (the rest are `@MainActor` and LEFT ALONE):
    ///
    ///   1. NSObject-DIRECT (chain reaches literal `NSObject` with no forest root):
    ///      its `init()` overrides corelibs `NSObject`'s genuinely-`nonisolated`
    ///      `init()`. (The leaf NSObject-direct case Pass 4 already handles.)
    ///   2. A ROOT class (no in-tree class superclass) that declares NO explicit
    ///      `init()`: the compiler-synthesized `init()` of such a class is
    ///      `nonisolated` under `-default-isolation MainActor` (verified by repro —
    ///      the `SheetDisplayableError` case). A root class that DOES declare an
    ///      explicit `init()` gets a `@MainActor` init, so it is NOT in this set.
    ///   3. An in-tree subclass whose base (recursively) has a `nonisolated init()`
    ///      AND which declares no explicit `init()` of its own — the nonisolation
    ///      propagates down through classes that don't re-declare `init()`.
    ///
    /// A chain ending at an UNKNOWN foreign base (not literal `NSObject`, not a forest
    /// root) is treated as `@MainActor` (false) — the conservative "leave alone"
    /// outcome the init pass already uses for unknown bases.
    func classHasNonisolatedNoArgInit(forClassNamed className: String) -> Bool {
        classHasNonisolatedNoArgInit(forClassNamed: className, seen: [])
    }

    private func classHasNonisolatedNoArgInit(forClassNamed className: String, seen: Set<String>) -> Bool {
        let simple = HierarchyMap.simpleName(className)
        if HierarchyMap.mainActorInitRoots.contains(simple) { return false } // forest
        guard let superName = superclassByClass[simple] else {
            // No recorded class superclass. Two sub-cases:
            //   * `simple` is a KNOWN in-tree class → genuine ROOT class (no class
            //     super, conforms only to protocols). Its compiler-synthesized
            //     `init()` is nonisolated ONLY if it declares no explicit `init()`
            //     (population 2 — the SheetDisplayableError case).
            //   * `simple` is NOT in-tree → an UNKNOWN foreign base we can't see
            //     (e.g. `CVMeasurementObject` defined in SignalServiceKit). Treat it
            //     CONSERVATIVELY as `@MainActor` (false) — the same "leave alone"
            //     outcome the init pass uses for unknown bases; we must never synthesize
            //     a bogus `nonisolated override init()` for a class whose foreign base
            //     might be `@MainActor` (or even a non-class).
            guard knownClasses.contains(simple) else { return false }
            return !classesDeclaringNoArgInit.contains(simple)
        }
        let simpleSuper = HierarchyMap.simpleName(superName)
        if simpleSuper == "NSObject" { return true }                 // population 1 (direct)
        if HierarchyMap.mainActorInitRoots.contains(simpleSuper) { return false } // forest base
        guard !seen.contains(simpleSuper) else { return false }      // cycle guard
        // In-tree (or unknown-foreign) base: this class's `init()` follows the base's
        // unless it re-declares `init()` (then it's the decl we annotate to match).
        // Either way the effective isolation equals the base's — recurse on the base.
        return classHasNonisolatedNoArgInit(forClassNamed: simpleSuper, seen: seen.union([simple]))
    }

    /// True iff an `init()` OVERRIDE declared in `className` must be `nonisolated` to
    /// match the base `init()` it overrides — i.e. the IMMEDIATE in-tree base (or
    /// literal `NSObject`) has a `nonisolated init()`. Drives both A3 (align a
    /// subclass `init()` to its base) and the existing NSObject-direct annotation.
    /// A class with no recorded class superclass overrides nothing, so this is false
    /// for it (a root class's own `init()` decl is left `@MainActor`).
    func initOverrideShouldBeNonisolated(forClassNamed className: String) -> Bool {
        let simple = HierarchyMap.simpleName(className)
        guard let superName = superclassByClass[simple] else { return false }
        let simpleSuper = HierarchyMap.simpleName(superName)
        if simpleSuper == "NSObject" { return true }
        if HierarchyMap.mainActorInitRoots.contains(simpleSuper) { return false }
        return classHasNonisolatedNoArgInit(forClassNamed: simpleSuper)
    }

    /// True iff `className` PROVABLY descends from a `@MainActor` UIKit/AppKit
    /// view-or-controller forest root (`HierarchyMap.mainActorInitRoots` — UIView /
    /// UIViewController / UIControl / AVPlayer / NSView / NSWindow …), i.e. the
    /// class IS, or transitively inherits from, one of those bases.
    ///
    /// This is the gate for the `deinit`-isolation pass (Pass 5). Under
    /// `-default-isolation MainActor` a `@MainActor` (forest) class has an ISOLATED
    /// deinit, so a subclass's nonisolated-by-default deinit both STRUCTURALLY
    /// mismatches it and can't touch the `@MainActor` UI members it teardown-uses
    /// (`removeFromSuperview()`, releasing a `@MainActor` view/timer property,
    /// reading a `@MainActor` token). Prepending `@MainActor` to such a deinit
    /// (Swift 6.2 isolated deinit) fixes both: it matches the base and runs the
    /// body on the main actor. Sound — instances of a forest (view/controller)
    /// class are created and destroyed on the main actor.
    ///
    /// DELIBERATELY STRICTER than `!initChainIsMainActorRooted`: that predicate
    /// also returns "leave alone" for a chain ending at an UNKNOWN foreign base,
    /// which could be a genuinely `nonisolated` foreign class. Here we require a
    /// PROVABLE forest root in the (cross-file) map before isolating the deinit, so
    /// model/helper objects — whose nonisolated deinit already MATCHES NSObject's
    /// nonisolated base deinit (no error), and which may dealloc off-main (caches,
    /// network results) — are NEVER given a wrongly-isolated deinit.
    func deinitChainReachesMainActorForestRoot(forClassNamed className: String) -> Bool {
        let simple = HierarchyMap.simpleName(className)
        if HierarchyMap.mainActorInitRoots.contains(simple) { return true }
        var seen: Set<String> = [simple]
        var current = simple
        while let superName = superclassByClass[current] {
            let simpleSuper = HierarchyMap.simpleName(superName)
            if HierarchyMap.mainActorInitRoots.contains(simpleSuper) { return true } // provable forest
            if simpleSuper == "NSObject" { return false }           // model/helper root
            guard seen.insert(simpleSuper).inserted else { return false } // cycle
            current = simpleSuper
        }
        return false // chain ended at an unknown foreign base → cannot prove → leave alone
    }

    /// True iff `className`'s deinit OVERRIDES a `@MainActor` base deinit because its
    /// IMMEDIATE superclass is another IN-TREE upstream class. Under
    /// `-default-isolation MainActor` every in-tree upstream class is `@MainActor`, so
    /// even with no explicit deinit a `@MainActor` base has an IMPLICIT isolated
    /// deinit; a subclass's nonisolated-by-default deinit then mismatches it
    /// ("nonisolated deinitializer has different actor isolation from main
    /// actor-isolated overridden declaration"). This catches the case the forest
    /// check misses: an NSObject-DIRECT `@MainActor` base (e.g. SignalUI's
    /// `BaseStickerPackDataSource: NSObject`) whose in-tree subclass
    /// (`TransientStickerPackDataSource`) declares a deinit. The base roots at
    /// `NSObject`, so `deinitChainReachesMainActorForestRoot` is false, yet the base
    /// is `@MainActor` and its (implicit) deinit is isolated.
    ///
    /// CONSERVATIVE: keyed strictly on the IMMEDIATE superclass being a recorded
    /// in-tree class (`knownClasses`). A class whose immediate super is a FOREIGN
    /// base — literal `NSObject` (a genuine model/helper root, nonisolated base
    /// deinit, no mismatch) or any non-in-tree foreign class — is NOT caught here;
    /// such classes are handled (or correctly left alone) by the forest check. We do
    /// not assume a foreign immediate base is `@MainActor`, only an in-tree one.
    func deinitOverridesMainActorBaseDeinit(forClassNamed className: String) -> Bool {
        let simple = HierarchyMap.simpleName(className)
        guard let superName = superclassByClass[simple] else { return false }
        let simpleSuper = HierarchyMap.simpleName(superName)
        return knownClasses.contains(simpleSuper)
    }

    /// The combined Pass 5 gate: a deinit should be `@MainActor` iff the class either
    /// provably descends from a `@MainActor` UIKit/AppKit forest root, OR its
    /// immediate superclass is an in-tree (`@MainActor`) class whose isolated deinit
    /// it would otherwise mismatch.
    func deinitShouldBeMainActor(forClassNamed className: String) -> Bool {
        deinitChainReachesMainActorForestRoot(forClassNamed: className)
            || deinitOverridesMainActorBaseDeinit(forClassNamed: className)
    }

    /// True iff `candidate` transitively inherits from `ancestor` (strictly — a class
    /// is not its own subclass) through the in-tree superclass chain. Resolves names
    /// simply; a chain that can't be fully resolved ends conservatively (no match).
    func isSubclass(_ candidate: String, of ancestor: String) -> Bool {
        let target = HierarchyMap.simpleName(ancestor)
        var seen: Set<String> = []
        var current = HierarchyMap.simpleName(candidate)
        while let superName = superclassByClass[current] {
            let simpleSuper = HierarchyMap.simpleName(superName)
            if simpleSuper == target { return true }
            guard seen.insert(simpleSuper).inserted else { return false } // cycle
            current = simpleSuper
        }
        return false
    }

    /// True iff SOME in-tree subclass of `baseClass` declares `override`-ing a method
    /// whose signature key is `signature`. This is the cross-file signal Pass 2's
    /// relocator needs: a base class's NON-override method declared in an `extension`
    /// must move into the base's class body so the subclass override (which on Linux
    /// can't override an extension member) resolves. Scans every class that records an
    /// override of `signature` and checks whether it descends from `baseClass`.
    func someSubclassOverrides(baseClass: String, signature: String) -> Bool {
        let base = HierarchyMap.simpleName(baseClass)
        for (className, sigs) in overriddenSignaturesByClass where sigs.contains(signature) {
            if className != base, isSubclass(className, of: base) { return true }
        }
        return false
    }
}

/// Lightweight pre-pass visitor: records each class's simple name → its immediate
/// superclass simple name, and which classes declare `@objc` action methods.
/// Cheaper than the full `ActionMethodCollector` (no per-method param capture);
/// it only needs the boolean "has any @objc action" and the inheritance edge.
private final class HierarchyScanner: SyntaxVisitor {
    private(set) var superclassByClass: [String: String] = [:]
    private(set) var classesWithActions: Set<String> = []
    /// Simple names of every class declared in the file (Pass 5's in-tree base check).
    private(set) var knownClasses: Set<String> = []
    /// Simple owner-type name -> the function signature keys (`name(label:…)`) it
    /// declares with an `override` modifier — in the class body OR an extension. Used
    /// by Pass 2's cross-file relocator: a base class's NON-override extension method
    /// must move into the base body when some subclass elsewhere overrides it.
    private(set) var overriddenSignaturesByClass: [String: Set<String>] = [:]
    /// Simple names of classes that declare an EXPLICIT no-arg `init()` in their body
    /// (A3 base-init-isolation: a root class with no explicit `init()` has a
    /// `nonisolated` implicit `init()`). Only class-body inits are recorded.
    private(set) var classesDeclaringNoArgInit: Set<String> = []
    /// `typeStack` tracks the enclosing class OR extended-type name (innermost last)
    /// so a function visit knows its owning type whether it sits in a class body or
    /// an `extension` (overrides can be declared in either).
    private var typeStack: [String] = []
    private var classStack: [String] = []
    private var protocolDepth = 0

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        // Record a class-body no-arg `init()` (no params, no generics/effects) onto
        // its owning class — the A3 base-init-isolation signal.
        if protocolDepth == 0, let owner = classStack.last,
           node.signature.parameterClause.parameters.isEmpty {
            classesDeclaringNoArgInit.insert(owner)
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        classStack.append(node.name.text)
        typeStack.append(node.name.text)
        knownClasses.insert(node.name.text)
        if let first = node.inheritanceClause?.inheritedTypes.first {
            let firstSimple = HierarchyMap.simpleName(first.type.trimmedDescription)
            // Only record a CLASS superclass. A class's superclass must be listed
            // first, but a class may instead conform to a protocol with no
            // superclass (`class Foo: Error`); recording that protocol as a
            // "superclass" makes the chain walks mistake it for a foreign base.
            if !HierarchyMap.isKnownInheritedProtocol(firstSimple) {
                superclassByClass[node.name.text] = firstSimple
            }
        }
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        classStack.removeLast()
        typeStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(HierarchyMap.simpleName(node.extendedType.trimmedDescription))
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocolDepth += 1
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) { protocolDepth -= 1 }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard protocolDepth == 0 else { return .visitChildren }
        // Record overrides keyed off the enclosing TYPE (class body or extension).
        if let owner = typeStack.last,
           node.modifiers.contains(where: { $0.name.text == "override" }) {
            overriddenSignaturesByClass[owner, default: []].insert(functionSignatureKey(node))
        }
        // @objc-action witness tracking is class-body only (a protocol requirement
        // and a same-name foreign-type extension method are not dispatchable here).
        guard let owner = classStack.last else { return .visitChildren }
        let isObjc = node.attributes.contains { element in
            if case .attribute(let attr) = element {
                return attr.attributeName.trimmedDescription == "objc"
            }
            return false
        }
        // Only 0/1-param actions yield a witness, mirroring emittableActions.
        if isObjc, node.signature.parameterClause.parameters.count <= 1 {
            classesWithActions.insert(owner)
        }
        return .visitChildren
    }
}

/// A stable signature key for a function: base name plus its argument labels in
/// `name(extLabel:…)` form (a wildcard `_` label is kept as `_`). Two declarations
/// with the same Swift overload signature (which is what `override` matches against)
/// produce the same key — enough to pair a base extension method with a subclass's
/// `override` of it. Return/parameter types are intentionally excluded: Swift's
/// override matching is by full name (selector-equivalent), and the trees don't have
/// label-identical, type-different overrides of these delegate methods.
func functionSignatureKey(_ node: FunctionDeclSyntax) -> String {
    let labels = node.signature.parameterClause.parameters.map { p -> String in
        (p.firstName.text.isEmpty ? "_" : p.firstName.text) + ":"
    }.joined()
    return "\(node.name.text)(\(labels))"
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
    /// Simple names of every class declared in this file (with or without a
    /// superclass), so single-file `lower(_:)` can seed the hierarchy's
    /// `knownClasses` set for Pass 5's "deinit overrides a `@MainActor` in-tree
    /// base" check.
    private(set) var knownClasses: Set<String> = []
    /// Simple owner-type name -> function signature keys it declares with `override`
    /// (class body OR extension), so single-file `lower(_:)` can seed the hierarchy's
    /// `overriddenSignaturesByClass` for Pass 2b's cross-file relocation.
    private(set) var overriddenSignaturesByType: [String: Set<String>] = [:]
    /// Simple names of classes that declare a class-body no-arg `init()` (A3
    /// base-init-isolation seeding for single-file `lower(_:)`).
    private(set) var classesDeclaringNoArgInit: Set<String> = []
    private var typeStack: [String] = []
    /// Enclosing CLASS names (innermost last), so an init visit knows its owning
    /// class even when nested in an extension on `typeStack`.
    private var classStack: [String] = []
    private var protocolDepth = 0

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        classStack.append(node.name.text)
        knownClasses.insert(node.name.text)
        // First inherited type = the superclass candidate. A class's superclass, if
        // any, is listed first — but the first entry may instead be a PROTOCOL the
        // class conforms to with no superclass (`class Foo: Error`,
        // `class SignalAttachment: CustomDebugStringConvertible`). Recording that
        // protocol as a "superclass" makes the dispatch override/root decision treat
        // it as a foreign base (emitting a bogus `override`/`super.quillPerform` into
        // a no-superclass class). Only record a genuine class superclass.
        if let first = node.inheritanceClause?.inheritedTypes.first,
           !HierarchyMap.isKnownInheritedProtocol(HierarchyMap.simpleName(first.type.trimmedDescription)) {
            superclassByType[typeStack.joined(separator: ".")] = first.type.trimmedDescription
        }
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
        classStack.removeLast()
    }

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

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if protocolDepth == 0, let owner = classStack.last,
           node.signature.parameterClause.parameters.isEmpty {
            classesDeclaringNoArgInit.insert(owner)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard protocolDepth == 0, let owner = typeStack.last else { return .visitChildren }
        // Record overrides keyed off the enclosing type's simple name (class or
        // extension) for single-file Pass-2b cross-file relocation seeding.
        if node.modifiers.contains(where: { $0.name.text == "override" }) {
            overriddenSignaturesByType[HierarchyMap.simpleName(owner), default: []]
                .insert(functionSignatureKey(node))
        }
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
        let stripped = stripAttributes(super.visit(node).cast(FunctionDeclSyntax.self))
        // `func forwardingTarget(for:)` now overrides UIResponder's class-body
        // declaration (QuillUIKit), so the upstream `open func` (no `override`)
        // needs the `override` keyword added. BodyRangesTextView declares it
        // verbatim and calls `super.forwardingTarget(for:)`.
        return DeclSyntax(Self.addingForwardingTargetOverride(stripped))
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

    /// Adds `override` to an `open/public func forwardingTarget(for:)` that lacks
    /// it. UIResponder (QuillUIKit) now declares this method in its class body, so
    /// any subclass declaring it (BodyRangesTextView) must mark it `override`.
    /// Idempotent (skips when `override` is already present).
    static func addingForwardingTargetOverride(_ node: FunctionDeclSyntax) -> FunctionDeclSyntax {
        guard node.name.text == "forwardingTarget",
              functionSignatureKey(node) == "forwardingTarget(for:)",
              !node.modifiers.contains(where: { $0.name.text == "override" }) else {
            return node
        }
        var copy = node
        let mods = Array(node.modifiers)
        if let first = mods.first {
            // Move the decl's leading trivia (indentation) onto `override`; the
            // former-first modifier loses its leading and follows after a space.
            let overrideMod = DeclModifierSyntax(
                leadingTrivia: first.leadingTrivia,
                name: .keyword(.override),
                trailingTrivia: .space
            )
            var firstNoLead = first
            firstNoLead.leadingTrivia = []
            copy.modifiers = DeclModifierListSyntax([overrideMod, firstNoLead] + mods.dropFirst())
        } else {
            // Bare `func` (no modifiers): place `override` before the keyword.
            let leading = copy.funcKeyword.leadingTrivia
            copy.funcKeyword.leadingTrivia = []
            copy.modifiers = DeclModifierListSyntax([
                DeclModifierSyntax(leadingTrivia: leading, name: .keyword(.override), trailingTrivia: .space)
            ])
        }
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

    // Freestanding macro-expansion lowerings (`#selector` / `#imageLiteral` /
    // `#keyPath`). None of these compile on Linux (there is no ObjectiveC module,
    // and `#imageLiteral` is an Xcode literal macro), so each is rewritten to a
    // plain Swift expression. Dispatch on the macro name; non-matching macros pass
    // through untouched. Each preserves the original node's leading/trailing trivia.
    override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
        let recursed = super.visit(node)
        guard let macro = recursed.as(MacroExpansionExprSyntax.self) else {
            return recursed
        }
        switch macro.macroName.text {
        case "selector":
            // #selector(x) -> Selector("x")
            let key = Self.selectorKey(from: macro.arguments.trimmedDescription)
            return Self.replacement("Selector(\"\(Self.escapeStringLiteral(key))\")",
                                    preservingTriviaOf: node)
        case "imageLiteral":
            // #imageLiteral(resourceName: "X") -> UIImage(named: "X")!. Xcode's
            // asset-literal macro is unavailable on Linux; the shim has
            // `UIImage(named:)`. Force-unwrap because `#imageLiteral` yields a
            // non-optional `UIImage`, so an unwrapped value keeps the surrounding
            // expression's type. Only the `resourceName:` form is rewritten (the
            // only shape Xcode emits); anything else passes through.
            guard let name = Self.imageLiteralResourceName(from: macro) else { return recursed }
            return Self.replacement("UIImage(named: \"\(Self.escapeStringLiteral(name))\")!",
                                    preservingTriviaOf: node)
        case "keyPath":
            // #keyPath(Type.member.path) -> "member.path". Apple's `#keyPath`
            // yields the ObjC key string; on Linux there is no ObjC runtime, so we
            // emit the dotted MEMBER path (dropping the leading type component) as a
            // plain string literal — what every call site here (CABasicAnimation's
            // `keyPath:`, KVC string keys) actually wants.
            let key = Self.keyPathMemberString(from: macro.arguments.trimmedDescription)
            return Self.replacement("\"\(Self.escapeStringLiteral(key))\"",
                                    preservingTriviaOf: node)
        default:
            return recursed
        }
    }

    /// Build a replacement expression from `text` and re-anchor `source`'s leading
    /// and trailing trivia onto it, so the rewrite keeps its place on the line.
    private static func replacement(_ text: String, preservingTriviaOf source: some SyntaxProtocol) -> ExprSyntax {
        var replacement = ExprSyntax("\(raw: text)")
        replacement.leadingTrivia = source.leadingTrivia
        replacement.trailingTrivia = source.trailingTrivia
        return replacement
    }

    /// Escape a raw string so it is a valid Swift string-literal body.
    private static func escapeStringLiteral(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The `resourceName:` argument string of an `#imageLiteral(resourceName: "X")`
    /// macro, or `nil` if it is not that exact shape (single `resourceName:` arg
    /// whose value is a plain string literal). The returned value is the literal's
    /// CONTENT (between the quotes), so the rewrite re-quotes it itself.
    static func imageLiteralResourceName(from macro: MacroExpansionExprSyntax) -> String? {
        let args = Array(macro.arguments)
        guard args.count == 1,
              args[0].label?.text == "resourceName",
              let literal = args[0].expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        // A simple `"…"` literal has exactly one string-segment piece; reject
        // interpolated / multi-segment literals (we can't make a static name).
        let segments = Array(literal.segments)
        guard segments.count == 1,
              case .stringSegment(let seg) = segments[0] else { return nil }
        return seg.content.text
    }

    /// The member path of a `#keyPath(Type.member.path)` argument: drop the leading
    /// type component (everything up to and including the FIRST dot) and return the
    /// rest verbatim. `CALayer.cornerRadius` -> `cornerRadius`,
    /// `Foo.bar.baz` -> `bar.baz`. A path with no dot (bare `x`) is returned as-is.
    static func keyPathMemberString(from arguments: String) -> String {
        let t = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstDot = t.firstIndex(of: ".") else { return t }
        return String(t[t.index(after: firstDot)...])
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
        guard let call = recursed.as(FunctionCallExprSyntax.self) else { return recursed }
        // Strip an optional-protocol-method call's `?` (`.method?(` -> `.method(`)
        // when `method` is a known UIKit delegate optional method — see
        // `strippingOptionalProtocolCall`. Returns the call unchanged otherwise.
        let call2 = Self.strippingOptionalProtocolCall(call)
        // `NSAttributedString()` -> `NSAttributedString(string: "")`. swift-corelibs
        // ships no no-arg initializer (only `init(string:)`), and one can't be added
        // via extension (it would "override" the inherited `NSObject.init()` from an
        // extension, which Swift forbids). CVTextLabel writes the bare `NSAttributedString()`.
        if let nsCallee = call2.calledExpression.as(DeclReferenceExprSyntax.self),
           nsCallee.baseName.text == "NSAttributedString",
           call2.arguments.isEmpty,
           call2.trailingClosure == nil,
           call2.leftParen != nil {
            var replacement = ExprSyntax("NSAttributedString(string: \"\")")
            replacement.leadingTrivia = call2.leadingTrivia
            replacement.trailingTrivia = call2.trailingTrivia
            return replacement
        }
        // Member-access call rewrites for @MainActor-closure APIs whose corelibs
        // signatures take `@Sendable` blocks (so SignalUI's `{ self.mainActorMethod() }`
        // closures fail). Redirect to distinctly-named shims whose blocks are
        // non-`@Sendable`, so the closure infers @MainActor at the call site.
        if let member = call2.calledExpression.as(MemberAccessExprSyntax.self) {
            let memberName = member.declName.baseName.text
            let firstLabel = call2.arguments.first?.label?.text
            // `Timer.scheduledTimer(withTimeInterval:repeats:){…}` -> `QuillTimer.scheduledTimer(…)`
            // (NOT the `timeInterval:target:selector:` variant — gated on the first label).
            if memberName == "scheduledTimer",
               let base = member.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.text == "Timer",
               firstLabel == "withTimeInterval" {
                var newBase = DeclReferenceExprSyntax(baseName: .identifier("QuillTimer"))
                newBase.leadingTrivia = base.leadingTrivia
                var newMember = member
                newMember.base = ExprSyntax(newBase)
                var copy = call2
                copy.calledExpression = ExprSyntax(newMember)
                return ExprSyntax(copy)
            }
            // `<nc>.addObserver(forName:object:queue:using:){…}` -> `.quillAddObserver(…)`
            // (NOT the `addObserver(_:selector:name:object:)` variant — gated on `forName`).
            if memberName == "addObserver", firstLabel == "forName" {
                var newMember = member
                newMember.declName = DeclReferenceExprSyntax(baseName: .identifier("quillAddObserver"))
                var copy = call2
                copy.calledExpression = ExprSyntax(newMember)
                return ExprSyntax(copy)
            }
        }
        // Timer(timeInterval:repeats:block:) -> QuillTimer.make(…). Disjoint from
        // the strip above (this callee is the bare `Timer` identifier).
        guard let callee = call2.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "Timer",
              Self.isTimerBlockInit(call2) else {
            return ExprSyntax(call2)
        }
        var make = ExprSyntax("QuillTimer.make")
        make.leadingTrivia = call2.calledExpression.leadingTrivia
        make.trailingTrivia = call2.calledExpression.trailingTrivia
        var copy = call2
        copy.calledExpression = make
        return ExprSyntax(copy)
    }

    /// Member-name PREFIXES of UIKit/AppKit delegate optional methods. On Apple
    /// these are `@objc optional` and called with a trailing `?`
    /// (`delegate?.method?(…)`); the Linux shim declares the delegate protocols'
    /// methods as NON-optional with default impls, so that inner `?` (between the
    /// member name and the call's `(`) is "optional chaining on a non-optional
    /// value" and fails to compile. We strip ONLY that `?`, ONLY when the called
    /// expression is `<base>?.<member>` (a member access) AND `<member>` begins with
    /// one of these prefixes. The first `?` (on `<base>`) is genuine optional
    /// chaining on the optional delegate property and is left intact.
    ///
    /// RISK / why prefix-gated: a stored optional CLOSURE call (`onTap?(x)`, or a
    /// `self.handler?(x)` where `handler` is an `(() -> Void)?` property) is ALSO a
    /// `FunctionCallExprSyntax` over an `OptionalChainingExprSyntax`, and stripping
    /// its `?` would change real optional-closure semantics into a crash on nil.
    /// We avoid that two ways: (1) we only act when the chained expression is a
    /// MEMBER ACCESS (`.member`), never a bare `name?(…)` (that path stays a
    /// `DeclReferenceExprSyntax` and is skipped); (2) even for `.member?(…)`, we
    /// require `member` to match a known UIKit-delegate name prefix, so an app's own
    /// `.someClosureProperty?(…)` is left untouched. The prefix list is the closed
    /// set of UIKit delegate families that appear in the trees (navigation, text,
    /// scroll, table, collection, gesture, picker, etc.); extend as new ones surface.
    static let delegateOptionalMethodPrefixes: [String] = [
        "navigationController",
        "textView", "textField",
        "scrollView",
        "tableView",
        "collectionView",
        "gestureRecognizer",
        "pickerView",
        "imagePickerController",
        "controller",          // NSFetchedResultsController / generic delegate(controller:…)
        "webView",
        "player",
    ]

    /// If `call`'s callee is `<base>?.<member>(…)` (an `OptionalChainingExprSyntax`
    /// whose inner expression is a `MemberAccessExprSyntax`) and `<member>` matches a
    /// `delegateOptionalMethodPrefixes` entry, return the call with that outer `?`
    /// removed (callee becomes the plain `<base>?.<member>` member access). Otherwise
    /// return `call` unchanged. Idempotent: once the `?` is gone the callee is a
    /// `MemberAccessExprSyntax`, not an `OptionalChainingExprSyntax`, so it no longer
    /// matches.
    static func strippingOptionalProtocolCall(_ call: FunctionCallExprSyntax) -> FunctionCallExprSyntax {
        guard let optional = call.calledExpression.as(OptionalChainingExprSyntax.self),
              let member = optional.expression.as(MemberAccessExprSyntax.self) else {
            return call
        }
        let memberName = member.declName.baseName.text
        guard Self.delegateOptionalMethodPrefixes.contains(where: { memberName.hasPrefix($0) }) else {
            return call
        }
        // Re-anchor the dropped `?`'s trailing trivia (rare, but preserve it) onto
        // the member access, then make the member access the new callee.
        var newCallee = member
        newCallee.leadingTrivia = optional.leadingTrivia
        newCallee.trailingTrivia = optional.questionMark.trailingTrivia + member.trailingTrivia
        var copy = call
        copy.calledExpression = ExprSyntax(newCallee)
        return copy
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
        copy.memberBlock.members = kept
        return DeclSyntax(copy)
    }
}

// MARK: - Cross-file extension-member relocation (Pass 2b)

/// Function signatures whose `override` on a subclass must be STRIPPED rather than
/// relocated, because the method is declared in an `extension` of a FOREIGN base
/// (corelibs `NSObject`) that cannot be edited here. The shim provides
/// `forwardingTarget(for:)` as a non-overridable extension method on `NSObject`; a
/// subclass `override` of it ("declared in extension of NSObject and cannot be
/// overridden" / "overriding non-open instance method outside of its defining
/// module") is harmless to drop — the extension method still applies. Closed,
/// audited set; extend only with other foreign-NSObject-extension methods.
// Empty: `forwardingTarget(for:)` is now a real `open` member of UIResponder's
// CLASS BODY (QuillUIKit), so subclass declarations legitimately `override` it —
// `addingForwardingTargetOverride` ADDS the keyword rather than stripping it.
let foreignExtensionOverrideStripSignatures: Set<String> = []

/// Collects the cross-file Pass-2b work over a (Pass-2-merged) tree:
///
///  (A) RELOCATE: for each `extension <LocalClass> { func m … }` whose `m` is NOT an
///      override and whose signature SOME subclass overrides elsewhere (per the
///      cross-file `HierarchyMap.someSubclassOverrides`), records `m` to be moved into
///      `<LocalClass>`'s body. Only LOCAL classes (defined in this file) are eligible
///      targets — the class body we'd append to must be present in this file.
///
///  (B) STRIP: records every `override func` whose signature is in
///      `foreignExtensionOverrideStripSignatures` (e.g. `forwardingTarget(for:)`) so
///      the merger drops the `override` keyword.
private final class CrossFileExtensionRelocateCollector: SyntaxVisitor {
    private let hierarchy: HierarchyMap
    /// extended-type simple name -> the (non-override) extension methods to move.
    private(set) var relocatableByClass: [String: [MemberBlockItemSyntax]] = [:]
    /// `SyntaxIdentifier`s of `override func` decls whose `override` must be stripped.
    private(set) var overrideStripTargets: Set<SyntaxIdentifier> = []
    private var localClassNames: Set<String> = []

    init(hierarchy: HierarchyMap, viewMode: SyntaxTreeViewMode) {
        self.hierarchy = hierarchy
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        localClassNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let baseName = HierarchyMap.simpleName(node.extendedType.trimmedDescription)
        // (A) RELOCATE — only for an extension of a class DEFINED IN THIS FILE (we
        // can only append to a class body that is present here). A method already
        // carrying `override` is handled by the same-file `ExtensionOverrideMerger`.
        guard localClassNames.contains(baseName) else { return .visitChildren }
        for item in node.memberBlock.members {
            guard let fn = item.decl.as(FunctionDeclSyntax.self),
                  !fn.modifiers.contains(where: { $0.name.text == "override" }) else { continue }
            let signature = functionSignatureKey(fn)
            if hierarchy.someSubclassOverrides(baseClass: baseName, signature: signature) {
                relocatableByClass[baseName, default: []].append(item)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // (B) STRIP — any `override func <foreignExtensionOverride>` anywhere.
        if node.modifiers.contains(where: { $0.name.text == "override" }),
           foreignExtensionOverrideStripSignatures.contains(functionSignatureKey(node)) {
            overrideStripTargets.insert(node.id)
        }
        return .visitChildren
    }
}

/// Applies the Pass-2b plan from `CrossFileExtensionRelocateCollector`:
///   * Moves the recorded non-override extension methods into their (local) base
///     class's body, and removes them from the originating extension.
///   * Strips the `override` keyword from the recorded `forwardingTarget(for:)`-style
///     decls.
/// Idempotent: a second run finds the moved methods already in the class body (so the
/// extension no longer holds them) and the `override` already gone.
private final class CrossFileExtensionMemberRelocator: SyntaxRewriter {
    private let relocatableByClass: [String: [MemberBlockItemSyntax]]
    private let relocatedSignaturesByClass: [String: Set<String>]
    private let overrideStripTargets: Set<SyntaxIdentifier>

    init(
        relocatableByClass: [String: [MemberBlockItemSyntax]],
        overrideStripTargets: Set<SyntaxIdentifier>
    ) {
        self.relocatableByClass = relocatableByClass
        self.overrideStripTargets = overrideStripTargets
        // Pre-compute the signature set per class so the extension filter is cheap.
        var sigs: [String: Set<String>] = [:]
        for (className, items) in relocatableByClass {
            sigs[className] = Set(items.compactMap { item in
                item.decl.as(FunctionDeclSyntax.self).map(functionSignatureKey)
            })
        }
        self.relocatedSignaturesByClass = sigs
        super.init()
    }

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(ClassDeclSyntax.self)
        guard let moved = relocatableByClass[recursed.name.text], !moved.isEmpty else {
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
        let baseName = HierarchyMap.simpleName(recursed.extendedType.trimmedDescription)
        guard let movedSigs = relocatedSignaturesByClass[baseName], !movedSigs.isEmpty else {
            return DeclSyntax(recursed)
        }
        let kept = recursed.memberBlock.members.filter { item in
            guard let fn = item.decl.as(FunctionDeclSyntax.self),
                  !fn.modifiers.contains(where: { $0.name.text == "override" }) else { return true }
            return !movedSigs.contains(functionSignatureKey(fn))
        }
        guard kept.count != recursed.memberBlock.members.count else { return DeclSyntax(recursed) }
        var copy = recursed
        copy.memberBlock.members = kept
        return DeclSyntax(copy)
    }

    override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(FunctionDeclSyntax.self)
        // Strip `override` from a recorded foreign-extension override. Match against
        // the ORIGINAL node id (super.visit may rebuild children but preserves id).
        guard overrideStripTargets.contains(node.id) else { return DeclSyntax(recursed) }
        let savedLeading = recursed.leadingTrivia
        let kept = recursed.modifiers.filter { $0.name.text != "override" }
        guard kept.count != recursed.modifiers.count else { return DeclSyntax(recursed) }
        var copy = recursed
        copy.leadingTrivia = Trivia()
        copy.modifiers = kept
        // Re-anchor the decl's leading trivia onto whatever is now first (a surviving
        // modifier or the `func` keyword) so it keeps its own line + indentation.
        copy.leadingTrivia = savedLeading
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
///   * If NO strict ancestor (resolved through the cross-file `HierarchyMap`)
///     either is a known dispatch shim root OR is an in-tree class that itself
///     gets a witness, the class is the ROOT of its dispatch chain: a
///     `: QuillSelectorDispatching` conformance clause is added and a
///     non-`override` witness (with `default: break`) is injected. This is the
///     case both for `Foo: NSObject` AND for `Foo: SomeHelper` where `SomeHelper`
///     is a plain `NSObject` subclass with no actions (the bug a literal
///     `super == "NSObject"` test produced: `SomeHelper != "NSObject"` so it
///     wrongly emitted `override` of a non-existent base witness).
///   * Otherwise the class inherits `quillPerform` from a shim root
///     (UIResponder / UIPresentationController / UIBarButtonItem /
///     UIGestureRecognizer / AVPlayer / NSResponder / NSMenu / NSMenuItem /
///     NSAlert) or another lowered class — possibly through transparent
///     intermediate classes that declare no actions — so an `override` (with
///     `default: super.quillPerform(…)`) is injected and no conformance clause is
///     added. Exactly ONE class per chain declares the conformance (the root);
///     every other emits a plain `override`.
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
    private let hierarchy: HierarchyMap
    private var typeStack: [String] = []

    init(byType: [String: [ActionMethod]], hierarchy: HierarchyMap) {
        self.byType = byType
        self.hierarchy = hierarchy
        super.init()
    }

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        typeStack.append(node.name.text)
        let qualified = typeStack.joined(separator: ".")
        let simpleName = node.name.text
        // Recurse first so nested classes are handled and any rewrites compose.
        let recursed = super.visit(node).cast(ClassDeclSyntax.self)
        typeStack.removeLast()

        guard let methods = byType[qualified] else { return DeclSyntax(recursed) }
        let emittable = AppKitLowering.emittableActions(methods)
        guard !emittable.isEmpty else { return DeclSyntax(recursed) }
        // Idempotent: skip a class that already carries a class-body witness.
        guard !Self.hasDispatchWitness(recursed) else { return DeclSyntax(recursed) }

        // Hierarchy-aware: `override` iff a strict ancestor already dispatches
        // (a shim root, or an in-tree class with actions) — possibly through
        // action-less intermediates in other files. Otherwise this class roots
        // its dispatch chain and newly conforms with a non-override witness.
        let isOverride = hierarchy.dispatchWitnessIsOverride(forClassNamed: simpleName)
        let isRoot = !isOverride
        // Member indent: `typeStack` has been popped back to the ENCLOSING types,
        // so its count is this class's nesting depth; +1 for the class body.
        // 4 spaces per level matches Swift's house style.
        let indent = String(repeating: "    ", count: typeStack.count + 1)
        let methodSource = AppKitLowering.dispatchMethodSource(
            for: emittable, asOverride: isOverride, indent: indent
        )

        var copy = recursed
        copy.memberBlock = Self.appending(methodSource, to: copy.memberBlock)
        if isRoot {
            copy = Self.addingConformance(to: copy)
        }
        return DeclSyntax(copy)
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

// MARK: - NSApplicationDelegateAdaptor construction support (Pass 3b)

/// Makes `@NSApplicationDelegateAdaptor(AppDelegate.self)` usable for unmodified
/// macOS app source. On Apple, the SwiftUI wrapper can instantiate an
/// `NSObject & NSApplicationDelegate` via ObjC runtime conventions. On Linux,
/// generic construction needs an explicit `init()` protocol requirement, so the
/// SwiftUI shim constructs delegates that conform to `QuillReusableView`.
///
/// This pass is deliberately narrow: only classes that directly declare
/// `NSApplicationDelegate` gain `QuillReusableView`, and only when the no-arg
/// initializer either already exists or can be safely synthesized.
private final class NSApplicationDelegateReusableConformanceRewriter: SyntaxRewriter {
    private var classStack: [String] = []

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        classStack.append(node.name.text)
        let recursed = super.visit(node).cast(ClassDeclSyntax.self)
        classStack.removeLast()

        guard Self.inherits(recursed, "NSApplicationDelegate") else {
            return DeclSyntax(recursed)
        }

        let hasNoArgInit = Self.hasNoArgInitializer(recursed)
        guard hasNoArgInit || Self.canSynthesizeNoArgInitializer(recursed) else {
            return DeclSyntax(recursed)
        }

        let memberIndent = String(repeating: "    ", count: classStack.count + 1)
        var copy = Self.addingConformanceIfMissing(to: recursed, named: "QuillReusableView")
        copy = Self.ensuringRequiredNoArgInitializer(on: copy, memberIndent: memberIndent)
        return DeclSyntax(copy)
    }

    private static func inherits(_ node: ClassDeclSyntax, _ name: String) -> Bool {
        node.inheritanceClause?.inheritedTypes.contains { inherited in
            HierarchyMap.simpleName(inherited.type.trimmedDescription) == name
        } ?? false
    }

    private static func hasNoArgInitializer(_ node: ClassDeclSyntax) -> Bool {
        node.memberBlock.members.contains { item in
            guard let initDecl = item.decl.as(InitializerDeclSyntax.self) else { return false }
            return initDecl.signature.parameterClause.parameters.isEmpty
        }
    }

    private static func canSynthesizeNoArgInitializer(_ node: ClassDeclSyntax) -> Bool {
        !hasUninitializedStoredProperty(node)
    }

    private static func ensuringRequiredNoArgInitializer(
        on node: ClassDeclSyntax,
        memberIndent: String
    ) -> ClassDeclSyntax {
        var sawNoArgInit = false
        var copy = node
        copy.memberBlock.members = MemberBlockItemListSyntax(copy.memberBlock.members.map { item in
            guard let initDecl = item.decl.as(InitializerDeclSyntax.self),
                  initDecl.signature.parameterClause.parameters.isEmpty else {
                return item
            }
            sawNoArgInit = true
            var updated = item
            updated.decl = DeclSyntax(addingRequiredIfMissing(to: initDecl))
            return updated
        })

        guard !sawNoArgInit else { return copy }

        let hasClassSuperclass = firstInheritedClassName(copy) != nil
        let body = hasClassSuperclass ? " { super.init() }" : " {}"
        let overrideModifier = hasClassSuperclass ? " override" : ""
        let source = "\(memberIndent)// Auto-generated by AppKitLowering: constructible app delegate for @NSApplicationDelegateAdaptor"
            + "\n\(memberIndent)required\(overrideModifier) init()\(body)"
        let member = MemberBlockItemSyntax(decl: DeclSyntax("\n\n\(raw: source)\n"))
        var members = copy.memberBlock.members
        members.append(member)
        copy.memberBlock.members = members
        return copy
    }

    private static func addingRequiredIfMissing(to node: InitializerDeclSyntax) -> InitializerDeclSyntax {
        guard !node.modifiers.contains(where: { $0.name.text == "required" }) else { return node }
        var copy = node
        let savedLeading = copy.leadingTrivia
        copy.leadingTrivia = Trivia()
        let required = DeclModifierSyntax(name: .keyword(.required), trailingTrivia: .space)
        copy.modifiers = DeclModifierListSyntax([required] + Array(copy.modifiers))
        copy.leadingTrivia = savedLeading
        return copy
    }

    private static func addingConformanceIfMissing(
        to node: ClassDeclSyntax,
        named conformanceName: String
    ) -> ClassDeclSyntax {
        guard !inherits(node, conformanceName) else { return node }
        var copy = node
        if var clause = copy.inheritanceClause {
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
                type: TypeSyntax(IdentifierTypeSyntax(name: .identifier(conformanceName))),
                trailingTrivia: newTrailing
            )
            types.append(conformance)
            clause.inheritedTypes = types
            copy.inheritanceClause = clause
        } else {
            let nameTrailing = copy.name.trailingTrivia
            copy.name.trailingTrivia = Trivia()
            let conformance = InheritedTypeSyntax(
                type: TypeSyntax(IdentifierTypeSyntax(name: .identifier(conformanceName))),
                trailingTrivia: nameTrailing
            )
            copy.inheritanceClause = InheritanceClauseSyntax(
                colon: .colonToken(trailingTrivia: .space),
                inheritedTypes: InheritedTypeListSyntax([conformance])
            )
        }
        return copy
    }

    private static func firstInheritedClassName(_ node: ClassDeclSyntax) -> String? {
        guard let first = node.inheritanceClause?.inheritedTypes.first else { return nil }
        let firstSimple = HierarchyMap.simpleName(first.type.trimmedDescription)
        if HierarchyMap.isKnownInheritedProtocol(firstSimple) {
            return nil
        }
        if ["NSApplicationDelegate", "QuillReusableView", "QuillSelectorDispatching"].contains(firstSimple) {
            return nil
        }
        return firstSimple
    }

    private static func hasUninitializedStoredProperty(_ node: ClassDeclSyntax) -> Bool {
        node.memberBlock.members.contains { item in
            guard let varDecl = item.decl.as(VariableDeclSyntax.self) else { return false }
            if varDecl.modifiers.contains(where: { ["static", "class", "lazy"].contains($0.name.text) }) {
                return false
            }
            return varDecl.bindings.contains { binding in
                if let accessors = binding.accessorBlock {
                    if case .accessors(let list) = accessors.accessors {
                        if list.contains(where: { $0.accessorSpecifier.text == "get" }) {
                            return false
                        }
                    } else {
                        return false
                    }
                }
                if binding.initializer != nil { return false }
                if varDecl.bindingSpecifier.text == "var",
                   let type = binding.typeAnnotation?.type,
                   type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                    return false
                }
                return true
            }
        }
    }
}

// MARK: - Nonisolated NSObject-member overrides (Pass 4 — actor-isolation policy)

/// Implements the actor-isolation policy documented on `AppKitLowering`. Two parts:
///
///  (A) IDENTITY MEMBERS — `func isEqual(_:)`, `var description` / `var hash` /
///      `var debugDescription`. The nearest declaration up EVERY chain is
///      swift-corelibs `NSObject`'s `nonisolated` one (no shim re-declares them as
///      `@MainActor`), so an `override` in any `@MainActor` upstream class must be
///      `nonisolated`. Applied UNCONDITIONALLY (no hierarchy needed).
///
///  (B) INITIALIZERS — `init()` / `init(coder:)` / `init(frame:)` /
///      `init(nibName:bundle:)`. Whether the override must be `nonisolated` depends
///      on the class's ROOT (resolved through the cross-file `HierarchyMap`):
///        • init chain reaches a `@MainActor` shim init-root (the
///          UIView/UIViewController forest etc.) → the chain is `@MainActor`-
///          consistent; leave the override ALONE. (sig6-1 wrongly nonisolated-ed
///          these, which mismatched their `@MainActor` siblings — the 140→450
///          regression this pass undoes.)
///        • otherwise the class is rooted directly at `NSObject`'s `nonisolated`
///          init → the explicit override is `nonisolated`-annotated, AND if the
///          class declares NO initializer at all, a `nonisolated override init()`
///          is SYNTHESIZED (so its otherwise-implicit `@MainActor init()`, which
///          sig6-1 could never reach, stops mismatching `NSObject`).
///
/// Conservative: matches ONLY these exact NSObject member signatures, only when the
/// decl carries `override` and is not already `nonisolated`, so it never touches an
/// app's own same-named member that doesn't override NSObject's. In single-file
/// mode the hierarchy falls back to the file-local chain + the static shim-root
/// set, exact for same-file chains.
private final class NonisolatedNSObjectMemberRewriter: SyntaxRewriter {
    private let hierarchy: HierarchyMap
    /// Names of enclosing classes (innermost last) so a member visit knows its
    /// owner — needed for the per-class init-isolation root decision (B).
    private var classStack: [String] = []

    init(hierarchy: HierarchyMap) {
        self.hierarchy = hierarchy
        super.init()
    }

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

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        // `classStack` (before pushing) is the ENCLOSING nesting, so its current
        // count is this class's depth; +1 gives the member indent level — same
        // convention the dispatch injector uses.
        let memberIndent = String(repeating: "    ", count: classStack.count + 1)
        classStack.append(node.name.text)
        let recursed = super.visit(node).cast(ClassDeclSyntax.self)
        classStack.removeLast()
        // Synthesis: a class whose `init()` override must be `nonisolated` to match a
        // nonisolated base init (NSObject-direct, OR an in-tree base with a nonisolated
        // init — the SheetDisplayableError / StickerPackDataSource cases) but which
        // does NOT itself declare an `init()` gets an explicit
        // `nonisolated override init() { super.init() }`. This pins its otherwise
        // implicit/inherited `init()` to the base's isolation. Crucially this fires
        // EVEN when the class declares OTHER designated inits (e.g.
        // `init(stickerPackInfo:)`): such a class still implicitly overrides the base
        // `init()` and would mismatch it without an explicit nonisolated override.
        let needsNonisolatedInit = hierarchy.initOverrideShouldBeNonisolated(forClassNamed: node.name.text)
        return DeclSyntax(Self.synthesizingNonisolatedInitIfNeeded(
            recursed, needsNonisolatedInit: needsNonisolatedInit, memberIndent: memberIndent
        ))
    }

    /// If `node`'s `init()` override must be `nonisolated` (per A3, to match a
    /// nonisolated base init) and `node` declares NO no-arg `init()` of its own,
    /// append a `nonisolated override init() { super.init() }`. Idempotent (skips when
    /// an `init()` is already present — including a synthesized one from a prior run).
    /// Only acts on classes that inherit (have an inheritance clause), since a
    /// root-less class has no base `init()` to override. `memberIndent` is the
    /// class-body indentation (4 spaces / level).
    static func synthesizingNonisolatedInitIfNeeded(
        _ node: ClassDeclSyntax, needsNonisolatedInit: Bool, memberIndent: String
    ) -> ClassDeclSyntax {
        guard needsNonisolatedInit, node.inheritanceClause != nil else { return node }
        // Re-run guard / source guard: skip when the class already declares a no-arg
        // `init()` (the explicit-init `visit` annotates that one instead).
        let hasNoArgInit = node.memberBlock.members.contains { item in
            guard let initDecl = item.decl.as(InitializerDeclSyntax.self) else { return false }
            return initDecl.signature.parameterClause.parameters.isEmpty
        }
        guard !hasNoArgInit else { return node }
        // A synthesized `init() { super.init() }` initializes nothing, so it is
        // only valid when every stored property is self-initializing (has a
        // default, or is an implicitly-nil `var x: Type?`). If ANY stored
        // property lacks a default, synthesizing would emit "property not
        // initialized at super.init call" — strictly worse than leaving the
        // class's original init-isolation error. Skip such classes (conservative).
        let hasUninitializedStoredProperty = node.memberBlock.members.contains { item in
            guard let varDecl = item.decl.as(VariableDeclSyntax.self) else { return false }
            // `static`/`class` members aren't instance storage; skip them.
            if varDecl.modifiers.contains(where: { ["static", "class", "lazy"].contains($0.name.text) }) {
                return false
            }
            return varDecl.bindings.contains { binding in
                // Computed properties (accessor block with a getter) aren't storage.
                if let accessors = binding.accessorBlock {
                    // A `{ didSet }`/`{ willSet }` block is still stored; a getter is not.
                    if case .accessors(let list) = accessors.accessors {
                        let isComputed = list.contains { $0.accessorSpecifier.text == "get" }
                        if isComputed { return false }
                    } else {
                        return false // getter shorthand `{ expr }` = computed
                    }
                }
                // Has a default value → self-initializing.
                if binding.initializer != nil { return false }
                // Implicitly-nil optional → self-initializing ONLY for `var`. An
                // optional `let x: T?` gets NO implicit nil — it must be initialized
                // in an init (ActionSheetDisplayableError's `let localizedTitle: String?`).
                if varDecl.bindingSpecifier.text == "var",
                   let type = binding.typeAnnotation?.type,
                   type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                    return false
                }
                // A stored property with no default and non-optional type.
                return true
            }
        }
        // Mirror the dispatch injector's `appending`: the rendered member carries
        // its own indentation; the leading blank line reads it as its own member.
        let source: String
        if hasUninitializedStoredProperty {
            // The class has a stored property with no default, so it constructs via a
            // designated arg-init (e.g. `init(stickerPackInfo:)`), never `init()`. But
            // under -default-isolation MainActor it STILL has an (implicit) @MainActor
            // `init()` that mismatches the base's nonisolated `init()`. Provide an
            // explicit `nonisolated override init()` to fix the isolation — UNAVAILABLE
            // with a `fatalError` body so it needs no stored-property initialization and
            // is never actually callable (call sites use the real designated init).
            source = "\(memberIndent)// Auto-generated by AppKitLowering: nonisolated init() to match the base's"
                + "\n\(memberIndent)// nonisolated init() under -default-isolation MainActor. Unavailable +"
                + "\n\(memberIndent)// fatalError: this class is built via its designated initializer, never init()."
                + "\n\(memberIndent)@available(*, unavailable)"
                + "\n\(memberIndent)nonisolated override init() { fatalError(\"init() is unavailable\") }"
        } else {
            source = "\(memberIndent)// Auto-generated by AppKitLowering: nonisolated init() to match base isolation"
                + "\n\(memberIndent)// (the base init() is nonisolated under -default-isolation MainActor)."
                + "\n\(memberIndent)nonisolated override init() { super.init() }"
        }
        let member = MemberBlockItemSyntax(decl: DeclSyntax("\n\n\(raw: source)\n"))
        var copy = node
        var members = copy.memberBlock.members
        members.append(member)
        copy.memberBlock.members = members
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
        // (A) Identity member — always nonisolated, regardless of root.
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
        // (A) Identity members — always nonisolated, regardless of root.
        let matches = (name == "description" && type == "String")
            || (name == "debugDescription" && type == "String")
            || (name == "hash" && type == "Int")
        guard matches else { return DeclSyntax(recursed) }
        return DeclSyntax(Self.prependNonisolated(recursed))
    }

    override func visit(_ node: InitializerDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(InitializerDeclSyntax.self)
        guard !Self.hasNonisolated(recursed.modifiers) else { return DeclSyntax(recursed) }
        // (B) Initializer — only one of the NSObject-base designated inits, and only
        // when the base `init()` being overridden is nonisolated (NSObject-direct, OR
        // an in-tree base whose init is nonisolated — the SheetDisplayableError /
        // StickerPackDataSource cases). `init()` carries `override` (it overrides the
        // base's); `init?(coder:)` carries `required` (the NSCoding/required
        // designated-init requirement) and need not say `override`.
        guard let kind = Self.nonisolatableInitKind(recursed) else { return DeclSyntax(recursed) }
        switch kind {
        case .designatedDefault:
            guard Self.hasOverride(recursed.modifiers) else { return DeclSyntax(recursed) }
        case .coder:
            guard Self.hasOverride(recursed.modifiers) || Self.hasRequired(recursed.modifiers) else {
                return DeclSyntax(recursed)
            }
        }
        let owner = classStack.last ?? ""
        guard hierarchy.initOverrideShouldBeNonisolated(forClassNamed: owner) else {
            return DeclSyntax(recursed)
        }
        // (A2) Body-isolation refinement: a `nonisolated` init body CANNOT touch
        // `@MainActor` members (`label.backgroundColor = …`, `view.frame = …`,
        // `self.present(…)`). Such an init must stay `@MainActor` even though its base
        // init is nonisolated. Only nonisolate an init whose body is trivially
        // nonisolatable — empty, or only `super.init(...)` calls and assignments to a
        // PLAIN stored property (a bare/`self.`-qualified identifier LHS, no member
        // access chain). When uncertain, leave `@MainActor` (the conservative choice —
        // a `@MainActor` init still satisfies a nonisolated base init at a call site;
        // the only hazard the nonisolated annotation fixes is a body-less / trivial
        // override mismatch, which the trivial-body gate still covers).
        if Self.initBodyIsTriviallyNonisolatable(recursed) {
            return DeclSyntax(Self.prependNonisolated(recursed))
        }
        // Non-trivial body: make the init `nonisolated` (to match its base) and wrap
        // the body in `MainActor.assumeIsolated` so its @MainActor work type-checks —
        // but ONLY when the body STARTS with `super.init()`. If there is phase-1 work
        // before `super.init()` (e.g. `self.contentView = …` in Wallpaper), reordering
        // it past `super.init()` would break initialization, so leave the init
        // `@MainActor` (it compiled that way — those classes have @MainActor-base inits;
        // the over-approximating predicate flagged them unnecessarily).
        guard Self.initBodyStartsWithSuperInit(recursed) else {
            return DeclSyntax(recursed)
        }
        return DeclSyntax(Self.wrappingInitBodyInAssumeIsolated(recursed))
    }

    private static func hasRequired(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "required" }
    }

    /// True iff `node`'s body is safe to run `nonisolated` — it touches no
    /// `@MainActor` state. Conservative: only an empty body, or a body whose every
    /// statement is one of:
    ///   * a `super.init(...)` call (always allowed — the base init handles its own
    ///     isolation), or
    ///   * an assignment whose LHS is a PLAIN stored property — a bare identifier
    ///     (`x = …`) or `self.<identifier>` (`self.x = …`) with no further member
    ///     access. An assignment to a member-access chain (`label.backgroundColor`,
    ///     `view.frame`) is treated as `@MainActor` and makes the body non-trivial.
    /// Anything else (a method call, a property read off another object, a control-
    /// flow statement) makes the body non-trivial → leave `@MainActor`.
    static func initBodyIsTriviallyNonisolatable(_ node: InitializerDeclSyntax) -> Bool {
        guard let body = node.body else { return true } // declaration-only (protocol) — vacuously fine
        for stmt in body.statements {
            switch stmt.item {
            case .expr(let expr):
                if Self.isSuperInitCall(expr) { continue }
                if Self.isPlainStoredAssignment(expr) { continue }
                if Self.isAddObserverCall(expr) { continue }
                return false
            default:
                // A declaration or a statement (if/guard/for/return/etc.) — not a
                // trivial init body.
                return false
            }
        }
        return true
    }

    /// True iff the init body's FIRST statement is `super.init()` — i.e. there is no
    /// phase-1 stored-property initialization before `super.init()` that the
    /// assume-isolated wrap would have to preserve.
    static func initBodyStartsWithSuperInit(_ node: InitializerDeclSyntax) -> Bool {
        guard let first = node.body?.statements.first,
              case .expr(let e) = first.item else { return false }
        return Self.isSuperInitCall(e)
    }

    /// Rebuilds an `init()` as `nonisolated <mods> init<sig> { super.init();
    /// MainActor.assumeIsolated { <rest of body> } }`. Used when the init must be
    /// nonisolated (to match its base) but its body touches `@MainActor` state. The
    /// existing `super.init()` (if any) is hoisted out of the wrapper; everything
    /// else runs inside `assumeIsolated`. These objects are built on the main actor.
    static func wrappingInitBodyInAssumeIsolated(_ node: InitializerDeclSyntax) -> InitializerDeclSyntax {
        guard let body = node.body else { return node }
        var rest: [String] = []
        for stmt in body.statements {
            if case .expr(let e) = stmt.item, Self.isSuperInitCall(e) { continue }
            rest.append(stmt.trimmedDescription)
        }
        let restJoined = rest.joined(separator: "\n            ")
        let mods = node.modifiers.map { $0.name.text }.joined(separator: " ")
        let modPrefix = mods.isEmpty ? "nonisolated" : "nonisolated \(mods)"
        let sig = node.signature.trimmedDescription
        let declText = """
        \(modPrefix) init\(sig) {
                super.init()
                MainActor.assumeIsolated {
                    \(restJoined)
                }
            }
        """
        guard let rebuilt = DeclSyntax("\(raw: declText)").as(InitializerDeclSyntax.self) else {
            return node
        }
        var result = rebuilt
        result.leadingTrivia = node.leadingTrivia
        return result
    }

    /// True iff `expr` is a `…addObserver(…)` call. The selector-based
    /// `NotificationCenter.default.addObserver(self, selector:name:object:)`
    /// (used in RecentStickerPackDataSource's init) is `nonisolated`, so it's
    /// safe inside a `nonisolated` init even though it's a call (unlike a
    /// `@MainActor` member assignment).
    private static func isAddObserverCall(_ expr: ExprSyntax) -> Bool {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return false
        }
        return member.declName.baseName.text == "addObserver"
    }

    /// True iff `expr` is a `super.init(...)` call.
    private static func isSuperInitCall(_ expr: ExprSyntax) -> Bool {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "init",
              member.base?.as(SuperExprSyntax.self) != nil else {
            return false
        }
        return true
    }

    /// True iff `expr` is an assignment `<lhs> = <rhs>` where `<lhs>` is a PLAIN
    /// stored property: a bare identifier (`x`) or `self.<identifier>` (`self.x`),
    /// with no deeper member-access chain. (`label.backgroundColor = …` is NOT plain.)
    private static func isPlainStoredAssignment(_ expr: ExprSyntax) -> Bool {
        guard let seq = expr.as(SequenceExprSyntax.self) else { return false }
        let elements = Array(seq.elements)
        // `lhs  =  rhs` → exactly three elements with an AssignmentExpr in the middle.
        guard elements.count == 3, elements[1].is(AssignmentExprSyntax.self) else { return false }
        let lhs = elements[0]
        // Bare identifier LHS: `x = …`.
        if lhs.is(DeclReferenceExprSyntax.self) { return true }
        // `self.x = …` — member access whose base is `self` and whose member name is a
        // plain identifier (the base must itself be `self`, not another chain).
        if let member = lhs.as(MemberAccessExprSyntax.self),
           member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) {
            return true
        }
        return false
    }

    /// Which NSObject-base init this is, if any. On a class rooted DIRECTLY at
    /// `NSObject` these genuinely override a `nonisolated` base init: `init()`
    /// (NSObject's) and `init(coder:)` (the `NSCoding`/required designated init,
    /// also nonisolated). The forest inits `init(frame:)` / `init(nibName:bundle:)`
    /// are intentionally absent: they only ever override `@MainActor`
    /// UIView/UIViewController bases, which the root check skips. No async/throws/
    /// generics.
    enum NonisolatableInitKind { case designatedDefault, coder }
    static func nonisolatableInitKind(_ node: InitializerDeclSyntax) -> NonisolatableInitKind? {
        guard node.genericParameterClause == nil,
              node.signature.effectSpecifiers == nil else { return nil }
        let params = Array(node.signature.parameterClause.parameters)
        switch params.count {
        case 0:
            return .designatedDefault                      // init()
        case 1 where params[0].firstName.text == "coder":
            return .coder                                  // [required] init?(coder:)
        default:
            return nil
        }
    }
}

// MARK: - deinit MainActor isolation (Pass 5 — actor-isolation ripple)

/// Prepends `@MainActor` to a `deinit` declared in a class that PROVABLY descends
/// from a `@MainActor` UIKit/AppKit view-or-controller forest root. See the
/// type-level "ACTOR-ISOLATION RIPPLE (Pass 5)" doc block for the full rationale;
/// in brief:
///
///   * Under `-default-isolation MainActor`, a `@MainActor` class has an ISOLATED
///     deinit, so a subclass's deinit — `nonisolated` by default — STRUCTURALLY
///     mismatches it: "nonisolated deinitializer has different actor isolation from
///     main actor-isolated overridden declaration." This fires on EVERY forest
///     deinit, even an empty one.
///   * On top of that, a forest deinit routinely touches the `@MainActor` UI
///     members the rest of the class uses (`view.removeFromSuperview()`,
///     `timer?.invalidate()` on a `@MainActor` property, nil-ing a `@MainActor`
///     child) — the "main actor-isolated … from a synchronous nonisolated context"
///     ripple.
///   * `@MainActor` on the deinit (Swift 6.2 isolated deinit, SE-0371) fixes BOTH
///     at once: the deinit's isolation now MATCHES the base's isolated deinit, AND
///     the body runs on the main actor so the member access is legal. The runtime
///     hops to the main actor to run the deinit — no `assumeIsolated`, no body
///     rewrite, no runtime trap risk.
///
/// CONSERVATIVE GATES (combined in `deinitShouldBeMainActor`):
///   * Either the class provably descends from a `@MainActor` UIKit/AppKit forest
///     root (`deinitChainReachesMainActorForestRoot`), OR its IMMEDIATE superclass
///     is another in-tree upstream class (`deinitOverridesMainActorBaseDeinit`) —
///     which under `-default-isolation MainActor` is `@MainActor`, so even its
///     implicit deinit is isolated and a subclass deinit must match it (the
///     `BaseStickerPackDataSource`/`TransientStickerPackDataSource` case, where the
///     base roots at `NSObject` so the forest check alone is false).
///   * Model/helper objects whose IMMEDIATE base is FOREIGN — literal `NSObject`, or
///     an unknown non-in-tree base — are LEFT ALONE: their nonisolated deinit
///     MATCHES NSObject's (or the unknown foreign base's presumed nonisolated)
///     deinit, so it does not error; isolating it would be both unnecessary and
///     wrong (those objects can legitimately dealloc off-main). We only annotate
///     where the base's isolated deinit is provable (forest root, or in-tree base).
///   * Idempotent: a deinit that already carries `@MainActor` / `nonisolated` /
///     `isolated` is left untouched, so a re-run is a no-op. (A hand-written
///     `nonisolated deinit` is a deliberate author choice — though it will not
///     compile against a `@MainActor` base, that is the author's bug to see, not
///     ours to silently flip.)
///
/// `deinit` carries no parameters and no isolation in source by default, so this
/// is a pure attribute prepend — the body is never touched.
private final class DeinitMainActorIsolationRewriter: SyntaxRewriter {
    private let hierarchy: HierarchyMap
    /// Enclosing class names (innermost last) so a `deinit` knows its owner — the
    /// `deinitShouldBeMainActor` gate is keyed off the owning class.
    private var classStack: [String] = []

    init(hierarchy: HierarchyMap) {
        self.hierarchy = hierarchy
        super.init()
    }

    override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        classStack.append(node.name.text)
        let recursed = super.visit(node).cast(ClassDeclSyntax.self)
        classStack.removeLast()
        return DeclSyntax(recursed)
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> DeclSyntax {
        let recursed = super.visit(node).cast(DeinitializerDeclSyntax.self)
        guard let owner = classStack.last,
              hierarchy.deinitShouldBeMainActor(forClassNamed: owner),
              !Self.hasIsolationAttributeOrModifier(recursed) else {
            return DeclSyntax(recursed)
        }
        return DeclSyntax(Self.prependingMainActor(recursed))
    }

    /// True iff the deinit already states its isolation — `@MainActor` (the form
    /// this pass emits, so re-runs are no-ops), or an explicit `nonisolated` /
    /// `isolated` modifier (a deliberate author choice we never override).
    static func hasIsolationAttributeOrModifier(_ node: DeinitializerDeclSyntax) -> Bool {
        let hasMainActorAttr = node.attributes.contains { element in
            if case .attribute(let attr) = element {
                return attr.attributeName.trimmedDescription == "MainActor"
            }
            return false
        }
        let hasIsolationModifier = node.modifiers.contains {
            $0.name.text == "nonisolated" || $0.name.text == "isolated"
        }
        return hasMainActorAttr || hasIsolationModifier
    }

    /// Insert `@MainActor` as the deinit's leading attribute, re-anchoring the
    /// decl's leading trivia (newline + indent) onto the new attribute so the
    /// deinit stays on its own line at its original indentation. Mirrors Pass 4's
    /// `prependNonisolated` trivia handling, for attributes instead of modifiers.
    static func prependingMainActor(_ node: DeinitializerDeclSyntax) -> DeinitializerDeclSyntax {
        var copy = node
        let savedLeading = copy.leadingTrivia
        copy.leadingTrivia = Trivia()
        let attr = AttributeSyntax(
            attributeName: TypeSyntax(IdentifierTypeSyntax(name: .identifier("MainActor"))),
            trailingTrivia: .space
        )
        copy.attributes = AttributeListSyntax([.attribute(attr)] + Array(copy.attributes))
        copy.leadingTrivia = savedLeading
        return copy
    }
}

// MARK: - Local nested-function MainActor isolation (Pass 6 — actor-isolation)

/// Prepends `@MainActor` to a LOCAL nested function — one declared inside a
/// function/closure body, not as a type member or top-level decl.
///
/// Under `-default-isolation MainActor` every type and top-level decl in SignalUI is
/// implicitly `@MainActor`, but a LOCAL function declared inside a method or closure
/// body is `nonisolated` by default (local funcs do NOT inherit the enclosing actor
/// isolation). So when such a local func touches the `@MainActor` UI state its
/// surrounding context uses freely it errors with "call to main actor-isolated … in a
/// synchronous nonisolated context" / "property … can not be referenced from a
/// nonisolated context". Real example (ImageEditorViewController+Blur):
///
///     { modal in
///         func showToast() {                                 // nonisolated local func
///             let inset = self.view.safeAreaInsets.bottom + 90   // @MainActor self.view → error
///             toast.presentToastView(from: .bottom, of: self.view, inset: inset)
///         }
///     }
///
/// Marking the local func `@MainActor` matches its lexical surroundings (the whole
/// module is MainActor-by-default) and the UI state it touches; its call sites are
/// the same `@MainActor` closures/funcs, so they call it without a context error.
///
/// CONSERVATIVE:
///   * Only LOCAL funcs — a `FunctionDeclSyntax` whose enclosing scope is executable
///     code (a function/closure/accessor/control-flow body), tracked by a body-depth
///     counter. A TYPE-MEMBER func (in a `MemberBlockSyntax`, which does not bump the
///     counter) and a TOP-LEVEL func (visited at depth 0) already get default
///     isolation and are NEVER touched.
///   * Idempotent: a local func already carrying `@MainActor` (the form this emits) or
///     an explicit `nonisolated` modifier (a deliberate author choice) is left alone.
private final class LocalFunctionMainActorRewriter: SyntaxRewriter {
    /// Depth of enclosing executable-code bodies (function/closure/accessor/control-
    /// flow `CodeBlock`s and closure bodies). A `FunctionDecl` visited at depth > 0
    /// is a LOCAL nested function. Type member blocks do NOT bump this, so type
    /// members and top-level decls stay at depth 0.
    private var bodyDepth = 0

    override func visit(_ node: CodeBlockSyntax) -> CodeBlockSyntax {
        bodyDepth += 1
        let recursed = super.visit(node)
        bodyDepth -= 1
        return recursed
    }

    override func visit(_ node: ClosureExprSyntax) -> ExprSyntax {
        bodyDepth += 1
        let recursed = super.visit(node)
        bodyDepth -= 1
        return recursed
    }

    override func visit(_ node: AccessorBlockSyntax) -> AccessorBlockSyntax {
        // A computed property's accessor body is executable code: an IMPLICIT getter
        // is a bare `CodeBlockItemListSyntax` (not wrapped in a `CodeBlockSyntax`), so
        // a func nested there would otherwise be missed. Explicit `get`/`set`/`didSet`
        // accessor bodies ARE `CodeBlockSyntax` (already counted), but bumping here too
        // is harmless — a nested func is local at depth > 0 either way.
        bodyDepth += 1
        let recursed = super.visit(node)
        bodyDepth -= 1
        return recursed
    }

    override func visit(_ node: FunctionDeclSyntax) -> DeclSyntax {
        // Capture whether THIS decl is local before recursing into its own body
        // (which bumps `bodyDepth` for its nested children).
        let isLocal = bodyDepth > 0
        let recursed = super.visit(node).cast(FunctionDeclSyntax.self)
        guard isLocal, !Self.hasMainActorOrNonisolated(recursed) else {
            return DeclSyntax(recursed)
        }
        return DeclSyntax(Self.prependingMainActor(recursed))
    }

    /// True iff the func already states its isolation — `@MainActor` (the form this
    /// emits, so re-runs are no-ops) or an explicit `nonisolated` modifier (a
    /// deliberate author choice we never override).
    static func hasMainActorOrNonisolated(_ node: FunctionDeclSyntax) -> Bool {
        let hasMainActorAttr = node.attributes.contains { element in
            if case .attribute(let attr) = element {
                return attr.attributeName.trimmedDescription == "MainActor"
            }
            return false
        }
        let hasNonisolated = node.modifiers.contains { $0.name.text == "nonisolated" }
        return hasMainActorAttr || hasNonisolated
    }

    /// Insert `@MainActor` as the func's leading attribute, re-anchoring the decl's
    /// leading trivia (newline + indent) onto the new attribute so the func stays on
    /// its own line at its original indentation. Mirrors Pass 5's deinit handling.
    static func prependingMainActor(_ node: FunctionDeclSyntax) -> FunctionDeclSyntax {
        var copy = node
        let savedLeading = copy.leadingTrivia
        copy.leadingTrivia = Trivia()
        let attr = AttributeSyntax(
            attributeName: TypeSyntax(IdentifierTypeSyntax(name: .identifier("MainActor"))),
            trailingTrivia: .space
        )
        copy.attributes = AttributeListSyntax([.attribute(attr)] + Array(copy.attributes))
        copy.leadingTrivia = savedLeading
        return copy
    }
}
