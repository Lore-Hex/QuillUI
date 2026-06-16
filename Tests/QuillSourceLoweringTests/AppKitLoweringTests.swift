import Foundation
import Testing
@testable import QuillSourceLowering

@Suite("AppKit target-action source lowering (SwiftSyntax)")
struct AppKitLoweringTests {
    @Test("@objc is stripped from methods")
    func objcStripped() {
        let source = """
        class C {
            @objc func buttonClicked() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(!lowered.contains("@objc"))
        #expect(lowered.contains("func buttonClicked()"))
    }

    @Test("Panel manager-style AppKit source strips Objective-C attributes")
    func panelManagerObjCAttributesStrip() {
        let source = """
        #if os(macOS)
        import SwiftUI

        class PanelManager: NSObject, NSApplicationDelegate {
            @MainActor
            @objc func togglePanel() {}

            @MainActor
            @objc func onSubmitCompletion(scheduledTyping: Bool) {}
        }
        #endif
        """
        let lowered = AppKitLowering().lower(source)
        #expect(!lowered.contains("@objc"))
        #expect(lowered.contains("#if os(macOS) || os(Linux)"))
        #expect(lowered.contains("func togglePanel()"))
        #expect(lowered.contains("func onSubmitCompletion(scheduledTyping: Bool)"))
    }

    @Test("NSApplicationDelegate classes become constructible for SwiftUI adaptor")
    func appDelegateAdaptorConformance() {
        let source = """
        #if os(macOS)
        import SwiftUI

        class PanelManager: NSObject, NSApplicationDelegate {
            var panel: FloatingPanel!

            override init() {
                super.init()
                Task {
                    await NSApp.setActivationPolicy(.regular)
                    await handleNewMessages()
                }
            }

            private func handleNewMessages() async {}

            @MainActor
            @objc func togglePanel() {}
        }
        #endif
        """
        let lowering = AppKitLowering()
        let lowered = lowering.lower(source)
        #expect(lowered.contains("#if os(macOS) || os(Linux)"))
        #expect(lowered.contains("class PanelManager: NSObject, NSApplicationDelegate, QuillSelectorDispatching, QuillReusableView {"))
        #expect(lowered.contains("nonisolated required override init()"))
        #expect(lowered.contains("MainActor.assumeIsolated"))
        #expect(lowered.contains("func togglePanel()"))
        #expect(!lowered.contains("@objc"))
        #expect(lowering.lower(lowered) == lowered)
    }

    @Test("NSApplicationDelegate lowering synthesizes reusable no-arg init")
    func appDelegateSynthesizesNoArgInit() {
        let source = """
        class AppDelegate: NSObject, NSApplicationDelegate {
            var launchCount = 0
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("class AppDelegate: NSObject, NSApplicationDelegate, QuillReusableView {"))
        #expect(lowered.contains("nonisolated required override init() { super.init() }"))
    }

    @Test("@objc after a non-brace statement keeps its newline (no consecutive-statements merge)")
    func objcTriviaPreserved() {
        let source = """
        class C {
            var count = 0
            @objc func tick() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(!lowered.contains("@objc"))
        // `func` must stay on its own line — not merged onto `var count = 0`.
        #expect(!lowered.contains("0 func"))
        #expect(lowered.contains("count = 0\n"))
        #expect(lowered.contains("func tick()"))
    }

    @Test("#selector(method) becomes Selector(\"method\")")
    func selectorSimple() {
        let lowered = AppKitLowering().lower(#"button.action = #selector(buttonClicked)"#)
        #expect(lowered.contains(#"Selector("buttonClicked")"#))
        #expect(!lowered.contains("#selector"))
    }

    @Test("#selector with argument labels keeps the labels in the key")
    func selectorWithLabels() {
        let lowered = AppKitLowering().lower(#"tableView.doubleAction = #selector(listDoubleClicked(sender:))"#)
        #expect(lowered.contains(#"Selector("listDoubleClicked(sender:)")"#))
        #expect(!lowered.contains("#selector"))
    }

    @Test("Type-qualified #selector drops the type so it equals the unqualified setter (menu validation)")
    func selectorQualifierStripped() {
        let setter = AppKitLowering().lower(#"menuItem.action = #selector(handleRemoveTunnelAction)"#)
        let check  = AppKitLowering().lower(#"if menuItem.action == #selector(TunnelsListTableViewController.handleRemoveTunnelAction) {}"#)
        #expect(setter.contains(#"Selector("handleRemoveTunnelAction")"#))
        #expect(check.contains(#"Selector("handleRemoveTunnelAction")"#))
    }

    @Test("System / responder-chain #selector lowers (type qualifier dropped)")
    func selectorSystem() {
        let lowered = AppKitLowering().lower(#"menuItem.action = #selector(NSWindow.toggleFullScreen(_:))"#)
        #expect(lowered.contains(#"Selector("toggleFullScreen(_:)")"#))
    }

    @Test("Non-ObjC attributes are left intact")
    func leavesOtherAttributes() {
        let source = """
        @available(macOS 10.15, *)
        class C {}
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("@available(macOS 10.15, *)"))
    }

    /// Real-source smoke: run the pass over the entire vendored WireGuard macOS
    /// UI tree and assert it clears every `#selector` / `@objc` and is
    /// idempotent. Proves the pass handles the actual app's whole target-action
    /// surface, not just hand-written snippets. Skips when `.upstream` isn't
    /// populated (the host CI "Swift tests" job; it's fetched only for the
    /// Docker conformance build).
    @Test("Whole WireGuard macOS UI tree lowers clean + idempotently")
    func realUpstreamTreeLowersClean() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/QuillSourceLoweringTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let macUI = repoRoot
            .appendingPathComponent(".upstream/wireguard-apple/Sources/WireGuardApp/UI/macOS")
        guard FileManager.default.fileExists(atPath: macUI.path) else { return } // skip: no upstream
        // fetch-upstream lowers .upstream in place on Linux CI; these whole-tree
        // checks only hold on RAW source, so skip if the tree is already lowered.
        let probe = macUI.appendingPathComponent("ViewController/ButtonedDetailViewController.swift")
        if let probed = try? String(contentsOf: probe, encoding: .utf8), !probed.contains("#selector(") { return }

        let pass = AppKitLowering()
        var visited = 0, hadSelectorOrObjc = 0
        var stillHasObjC: [String] = []
        var notIdempotent: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: macUI, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let original = try String(contentsOf: url, encoding: .utf8)
            visited += 1
            if original.contains("#selector(") || original.contains("@objc") { hadSelectorOrObjc += 1 }

            let lowered = pass.lower(original)
            if lowered.contains("#selector(") || lowered.contains("@objc") {
                stillHasObjC.append(url.lastPathComponent)
            }
            // Idempotent: lowering already-lowered source is a no-op.
            if pass.lower(lowered) != lowered { notIdempotent.append(url.lastPathComponent) }
        }
        // Joined into the comment as a plain String value (avoids the Comment
        // string-interpolation overload-inference snag with bare interpolations).
        let leftoverList = stillHasObjC.joined(separator: ", ")
        let nonIdempotentList = notIdempotent.joined(separator: ", ")
        #expect(stillHasObjC.isEmpty, Comment(rawValue: "files still containing #selector/@objc: " + leftoverList))
        #expect(notIdempotent.isEmpty, Comment(rawValue: "non-idempotent files: " + nonIdempotentList))
        // Sanity: we actually exercised real files with the constructs.
        #expect(visited > 0)
        #expect(hadSelectorOrObjc > 0)
    }

    @Test("A representative target-action block lowers to compilable Swift")
    func representativeBlock() {
        // Mirrors the shape of ButtonedDetailViewController's wiring.
        let source = """
        class DetailVC {
            let button = NSButton()
            func setup() {
                button.target = self
                button.action = #selector(buttonClicked)
            }
            @objc func buttonClicked() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(!lowered.contains("@objc"))
        #expect(!lowered.contains("#selector"))
        #expect(lowered.contains("button.target = self"))
        #expect(lowered.contains(#"button.action = Selector("buttonClicked")"#))
        #expect(lowered.contains("func buttonClicked()"))
    }

    // MARK: - Dispatch-override injection (half-2)

    @Test("NSObject-rooted class conforms + gets a non-override class-body witness")
    func injectsRootWitness() {
        let source = """
        class VC: NSObject {
            @objc func saveClicked() {}
            @objc func listDoubleClicked(sender: AnyObject) {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        // CLASS BODY, not an extension: no `extension VC: …` is emitted.
        #expect(!lowered.contains("extension VC"))
        // Root (super == NSObject): conformance clause added, NON-override witness.
        #expect(lowered.contains("class VC: NSObject, QuillSelectorDispatching {"))
        #expect(lowered.contains("public func quillPerform(_ selector: Selector, with sender: Any?)"))
        #expect(!lowered.contains("public override func quillPerform"))
        #expect(lowered.contains(#"case "saveClicked": saveClicked()"#))
        #expect(lowered.contains(#"case "listDoubleClicked(sender:)": listDoubleClicked(sender: sender as! AnyObject)"#))
        // Root terminates the chain with `break` (NSObject has no quillPerform).
        #expect(lowered.contains("default: break"))
    }

    @Test("Subclass of a non-NSObject class gets an override with super fallthrough, no conformance")
    func injectsSubclassOverride() {
        let source = """
        class VC: UIViewController {
            @objc func tap() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        // Subclass (super != NSObject): override, NO conformance clause re-stated.
        #expect(lowered.contains("public override func quillPerform(_ selector: Selector, with sender: Any?)"))
        #expect(!lowered.contains("QuillSelectorDispatching"))   // no conformance clause
        #expect(lowered.contains(#"case "tap": tap()"#))
        // Inherited selectors forward up the chain.
        #expect(lowered.contains("default: super.quillPerform(selector, with: sender)"))
    }

    @Test("A class with no explicit superclass conforms as a root")
    func injectsRootWhenNoSuperclass() {
        let lowered = AppKitLowering().lower("class VC { @objc func tap() {} }")
        #expect(lowered.contains("class VC: QuillSelectorDispatching {"))
        #expect(lowered.contains("public func quillPerform(_ selector: Selector, with sender: Any?)"))
        #expect(!lowered.contains("override"))
        #expect(lowered.contains("default: break"))
    }

    @Test("Subclass + superclass in one file: subclass overrides, neither conformance is redundant")
    func injectsChainWithinFile() {
        let source = """
        class Base: NSObject {
            @objc func a() {}
        }
        class Sub: Base {
            @objc func b() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        // Base (root) conforms once; Sub overrides without re-conforming.
        #expect(lowered.contains("class Base: NSObject, QuillSelectorDispatching {"))
        #expect(lowered.contains("class Sub: Base {"))   // NO `, QuillSelectorDispatching`
        #expect(lowered.contains("public override func quillPerform"))
        // Exactly one conformance clause across the file (Sub does not re-state it).
        let conformanceCount = lowered.components(separatedBy: ": NSObject, QuillSelectorDispatching").count - 1
        #expect(conformanceCount == 1)
    }

    // MARK: - Hierarchy-aware dispatch (Problem A): chains through action-less bases

    @Test("Foo: HelperWithoutActions (helper is a plain NSObject subclass) ROOTS its chain — conformance + non-override, NOT a bad override")
    func injectsRootThroughActionlessHelper() {
        // The bug a literal `super == NSObject` test caused: `Helper != NSObject`
        // so Foo wrongly emitted `override` of a witness that Helper never got.
        let source = """
        class Helper: NSObject {
            func plain() {}
        }
        class Foo: Helper {
            @objc func tap() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        // Foo's chain reaches NSObject through an action-less Helper, so Foo is the
        // dispatch-chain ROOT: it newly conforms with a NON-override witness.
        #expect(lowered.contains("class Foo: Helper, QuillSelectorDispatching {"))
        #expect(lowered.contains("public func quillPerform(_ selector: Selector, with sender: Any?)"))
        #expect(!lowered.contains("public override func quillPerform"))
        #expect(lowered.contains("default: break"))      // root terminates the chain
        // Helper got no witness (no actions).
        let witnessCount = lowered.components(separatedBy: "func quillPerform(_ selector: Selector, with sender: Any?)").count - 1
        #expect(witnessCount == 1)
    }

    @Test("Deep chain A→B→C all with actions: A conforms + non-override, B & C override")
    func injectsDeepChainAllWithActions() {
        let source = """
        class A: NSObject {
            @objc func a() {}
        }
        class B: A {
            @objc func b() {}
        }
        class C: B {
            @objc func c() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        // A roots (super NSObject): conformance + non-override.
        #expect(lowered.contains("class A: NSObject, QuillSelectorDispatching {"))
        // B and C inherit a witness from A → override, no re-conformance.
        #expect(lowered.contains("class B: A {"))
        #expect(lowered.contains("class C: B {"))
        // Exactly one conformance clause across the whole chain.
        let conformanceCount = lowered.components(separatedBy: "QuillSelectorDispatching").count - 1
        #expect(conformanceCount == 1)
        // Two overrides (B, C), one non-override (A).
        let overrideCount = lowered.components(separatedBy: "public override func quillPerform").count - 1
        #expect(overrideCount == 2)
        let nonOverrideCount = lowered.components(separatedBy: "public func quillPerform(_ selector: Selector, with sender: Any?)").count - 1
        #expect(nonOverrideCount == 1)
    }

    @Test("Subclass of a shim root (UIGestureRecognizer) overrides — no conformance")
    func injectsOverrideForShimRootSubclass() {
        let source = """
        class MyTap: UIGestureRecognizer {
            @objc func fired() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        // UIGestureRecognizer is a known shim dispatch root → override, no conformance.
        #expect(lowered.contains("public override func quillPerform(_ selector: Selector, with sender: Any?)"))
        #expect(!lowered.contains("QuillSelectorDispatching"))
        #expect(lowered.contains("default: super.quillPerform(selector, with: sender)"))
    }

    @Test("Cross-file: Foo: Helper where Helper (action-less) lives in another file ROOTS its chain")
    func injectsRootThroughCrossFileActionlessHelper() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appkit-hier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Helper (no actions) in one file; Foo: Helper (with an action) in another.
        try "class Helper: NSObject { func plain() {} }"
            .write(to: tmp.appendingPathComponent("Helper.swift"), atomically: true, encoding: .utf8)
        let fooURL = tmp.appendingPathComponent("Foo.swift")
        try "class Foo: Helper { @objc func tap() {} }"
            .write(to: fooURL, atomically: true, encoding: .utf8)

        _ = try AppKitLowering().lowerInPlace(sourceDir: tmp)
        let loweredFoo = try String(contentsOf: fooURL, encoding: .utf8)
        // The cross-file pre-pass knows Helper: NSObject (action-less), so Foo is a
        // ROOT — conformance + non-override, NOT a bad override.
        #expect(loweredFoo.contains("QuillSelectorDispatching"))
        #expect(loweredFoo.contains("public func quillPerform(_ selector: Selector, with sender: Any?)"))
        #expect(!loweredFoo.contains("public override func quillPerform"))
    }

    @Test("Cross-file: Sub: Mid where Mid (with actions) is in another file → Sub overrides, no re-conformance")
    func injectsOverrideThroughCrossFileActionBase() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appkit-hier2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "class Mid: NSObject { @objc func m() {} }"
            .write(to: tmp.appendingPathComponent("Mid.swift"), atomically: true, encoding: .utf8)
        let subURL = tmp.appendingPathComponent("Sub.swift")
        try "class Sub: Mid { @objc func s() {} }"
            .write(to: subURL, atomically: true, encoding: .utf8)

        _ = try AppKitLowering().lowerInPlace(sourceDir: tmp)
        let loweredSub = try String(contentsOf: subURL, encoding: .utf8)
        // Mid (in the other file) gets a witness, so Sub inherits one → override,
        // and does NOT re-state the conformance.
        #expect(loweredSub.contains("public override func quillPerform(_ selector: Selector, with sender: Any?)"))
        #expect(!loweredSub.contains("QuillSelectorDispatching"))
        #expect(loweredSub.contains("default: super.quillPerform(selector, with: sender)"))
    }

    @Test("Sender param casts: Any? passes through, AnyObject? optional-casts, AnyObject force-casts")
    func senderCasts() {
        let source = """
        class VC: NSObject {
            @objc func a(sender: AnyObject?) {}
            @objc func copy(_ sender: Any?) {}
            @objc func b(sender: AnyObject) {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains(#"case "a(sender:)": a(sender: sender as? AnyObject)"#))
        #expect(lowered.contains(#"case "copy(_:)": copy(sender)"#))
        #expect(lowered.contains(#"case "b(sender:)": b(sender: sender as! AnyObject)"#))
    }

    @Test("@objc actions declared in a same-file extension are injected into the class body")
    func actionsInExtension() {
        let source = """
        class VC: NSObject {}
        extension VC {
            @objc func foo() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        // The switch goes into the CLASS body; it calls `foo()` (defined in the
        // extension — accessible). No `extension VC: …` conformance is emitted.
        #expect(lowered.contains("class VC: NSObject, QuillSelectorDispatching {"))
        #expect(lowered.contains(#"case "foo": foo()"#))
        #expect(!lowered.contains("extension VC: "))
    }

    @Test("Nested private action-handler path is made fileprivate for dispatch reachability")
    func nestedPrivateActionHandlerIsNameable() {
        let source = """
        class BarButton {
            private class Handler: NSObject {
                @objc func fire() {}
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("fileprivate class Handler"))
        // The witness is injected into Handler's class body (a root: super NSObject).
        #expect(lowered.contains("QuillSelectorDispatching"))
        #expect(lowered.contains(#"case "fire": fire()"#))
    }

    @Test("@objc protocol requirements do NOT get a (bogus) witness")
    func protocolRequirementsSkipped() {
        let source = """
        @objc protocol Respondable {
            @objc func undo(_ sender: Any?)
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(!lowered.contains("quillPerform"))
        #expect(!lowered.contains("QuillSelectorDispatching"))
    }

    @Test("A class with no @objc actions gets no witness")
    func noWitnessWhenNoActions() {
        let lowered = AppKitLowering().lower("class VC: NSObject { func plain() {} }")
        #expect(!lowered.contains("quillPerform"))
        #expect(!lowered.contains("QuillSelectorDispatching"))
    }

    @Test("Injection is idempotent (a re-run injects nothing more)")
    func injectionIdempotent() {
        let once = AppKitLowering().lower("class VC: NSObject { @objc func tap() {} }")
        let twice = AppKitLowering().lower(once)
        #expect(once == twice)
        let count = once.components(separatedBy: "func quillPerform(_ selector: Selector, with sender: Any?)").count - 1
        #expect(count == 1)
    }

    @Test("Injected witness is public (required on public conformers)")
    func injectedWitnessIsPublic() {
        let lowered = AppKitLowering().lower("public class VC: NSObject { @objc func tap() {} }")
        #expect(lowered.contains("public func quillPerform(_ selector: Selector, with sender: Any?)"))
    }

    @Test("An existing class-body quillPerform is left untouched (re-run / hand-written)")
    func skipsExistingWitness() {
        // Already lowered: no @objc remains, class-body override present. A re-run
        // must not double-inject or wrap it in an extension.
        let already = """
        public class VC: UIViewController {
            func tap() {}

            public override func quillPerform(_ selector: Selector, with sender: Any?) {
                switch selector.name {
                case "tap": tap()
                default: super.quillPerform(selector, with: sender)
                }
            }
        }
        """
        let lowered = AppKitLowering().lower(already)
        #expect(lowered == already)   // pure no-op
        let count = lowered.components(separatedBy: "func quillPerform").count - 1
        #expect(count == 1)
    }

    @Test("Whole WireGuard macOS UI tree: every class with @objc actions gets an injected witness")
    func realUpstreamInjectsWitnesses() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let macUI = repoRoot
            .appendingPathComponent(".upstream/wireguard-apple/Sources/WireGuardApp/UI/macOS")
        guard FileManager.default.fileExists(atPath: macUI.path) else { return } // skip: no upstream
        // fetch-upstream lowers .upstream in place on Linux CI; these whole-tree
        // checks only hold on RAW source, so skip if the tree is already lowered.
        let probe = macUI.appendingPathComponent("ViewController/ButtonedDetailViewController.swift")
        if let probed = try? String(contentsOf: probe, encoding: .utf8), !probed.contains("#selector(") { return }

        let pass = AppKitLowering()
        var generatedAny = false
        guard let enumerator = FileManager.default.enumerator(at: macUI, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let original = try String(contentsOf: url, encoding: .utf8)
            let lowered = pass.lower(original)
            if original.contains("@objc func") {
                // Files that declare @objc actions (not just an @objc protocol) get a witness.
                if lowered.contains("func quillPerform(_ selector: Selector, with sender: Any?)") { generatedAny = true }
            }
            // No `extension …: QuillSelectorDispatching` is ever emitted.
            #expect(!lowered.contains("extension") || !lowered.contains(": QuillSelectorDispatching {"))
            // Injected dispatch must be clean + idempotent.
            #expect(!lowered.contains("#selector("))
            #expect(pass.lower(lowered) == lowered)
        }
        #expect(generatedAny)
    }

    // MARK: - nonisolated NSObject-member overrides

    @Test("override of nonisolated NSObject members gets `nonisolated` prepended")
    func nonisolatedNSObjectOverrides() {
        let source = """
        class C: NSObject {
            override init() { super.init() }
            override var description: String { "c" }
            override var debugDescription: String { "c!" }
            override var hash: Int { 0 }
            override func isEqual(_ object: Any?) -> Bool { false }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("nonisolated override init()"))
        #expect(lowered.contains("nonisolated override var description: String"))
        #expect(lowered.contains("nonisolated override var debugDescription: String"))
        #expect(lowered.contains("nonisolated override var hash: Int"))
        #expect(lowered.contains("nonisolated override func isEqual(_ object: Any?) -> Bool"))
        // Idempotent: a second pass does not double-prepend.
        #expect(!lowered.contains("nonisolated nonisolated"))
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("nonisolated pass leaves non-matching members and non-overrides alone")
    func nonisolatedLeavesOthersAlone() {
        let source = """
        class C: NSObject {
            var description = 0
            override func isEqual(_ object: AnyObject) -> Bool { false }
            func hash(into h: inout Hasher) {}
            override init(frame: Int) { super.init() }
        }
        """
        let lowered = AppKitLowering().lower(source)
        // `var description = 0` is not an override and not the NSObject `String` var;
        // `isEqual(_: AnyObject)` isn't NSObject's `isEqual(_: Any?)`; `hash(into:)`
        // is Hashable, not the NSObject `var hash`; `init(frame:)` is a forest-only
        // designated init this pass never annotates.
        #expect(!lowered.contains("nonisolated override func isEqual(_ object: AnyObject)"))
        #expect(!lowered.contains("nonisolated override init(frame: Int)"))
        #expect(!lowered.contains("nonisolated var description"))
        // The class itself is still NSObject-direct, so it may receive the generic
        // no-arg init-isolation shim.
        #expect(lowered.contains("nonisolated override init() { super.init() }"))
    }

    // MARK: - actor-isolation policy (Problem B): root-aware init isolation

    @Test("init() in the UIView/UIViewController FOREST is left @MainActor (not nonisolated-ed)")
    func forestInitLeftMainActor() {
        // sig6-1 wrongly nonisolated-ed these, mismatching @MainActor siblings.
        let source = """
        class MyView: UIView {
            override init(frame: CGRect) { super.init(frame: frame) }
            override init() { super.init() }
        }
        class MyVC: UIViewController {
            override init(nibName: String?, bundle: Bundle?) { super.init(nibName: nibName, bundle: bundle) }
        }
        """
        let lowered = AppKitLowering().lower(source)
        // Forest-rooted inits keep the default @MainActor — no `nonisolated`.
        #expect(!lowered.contains("nonisolated"))
        // And no init is synthesized into a forest class.
        #expect(!lowered.contains("Auto-generated by AppKitLowering: NSObject-direct"))
    }

    @Test("init() / init?(coder:) on an NSObject-DIRECT class are nonisolated-annotated")
    func nsObjectDirectInitNonisolated() {
        let source = """
        class Model: NSObject {
            override init() { super.init() }
            required init?(coder: NSCoder) { super.init() }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("nonisolated override init() {"))
        #expect(lowered.contains("nonisolated required init?(coder: NSCoder)"))
        // Idempotent.
        #expect(AppKitLowering().lower(lowered) == lowered)
        #expect(!lowered.contains("nonisolated nonisolated"))
    }

    @Test("NSObject-direct class with NO initializer gets a synthesized nonisolated override init()")
    func nsObjectDirectSynthesizesInit() {
        let source = """
        class Model: NSObject {
            var value = 0
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("nonisolated override init() { super.init() }"))
        #expect(lowered.contains("Auto-generated by AppKitLowering: nonisolated init() to match base isolation"))
        // Idempotent: a second pass does not synthesize a second init.
        let twice = AppKitLowering().lower(lowered)
        #expect(twice == lowered)
        let initCount = lowered.components(separatedBy: "override init()").count - 1
        #expect(initCount == 1)
    }

    @Test("Forest class with NO initializer is NOT given a synthesized init")
    func forestNoSynthesizedInit() {
        let lowered = AppKitLowering().lower("class MyView: UIView { var n = 0 }")
        #expect(!lowered.contains("nonisolated"))
        #expect(!lowered.contains("override init()"))
    }

    @Test("A class with no superclass is not given a synthesized init (nothing to override)")
    func rootlessNoSynthesizedInit() {
        let lowered = AppKitLowering().lower("class Plain { var n = 0 }")
        #expect(!lowered.contains("override init()"))
        #expect(!lowered.contains("nonisolated"))
    }

    @Test("isEqual/description/hash are nonisolated even on a FOREST class (NSObject identity members)")
    func identityMembersNonisolatedEverywhere() {
        let source = """
        class MyView: UIView {
            override var description: String { "v" }
            override var hash: Int { 0 }
            override func isEqual(_ object: Any?) -> Bool { false }
        }
        """
        let lowered = AppKitLowering().lower(source)
        // Identity members override NSObject's nonisolated declarations regardless
        // of root, so they are nonisolated even in the @MainActor forest.
        #expect(lowered.contains("nonisolated override var description: String"))
        #expect(lowered.contains("nonisolated override var hash: Int"))
        #expect(lowered.contains("nonisolated override func isEqual(_ object: Any?) -> Bool"))
        // But the forest class is NOT given a synthesized init.
        #expect(!lowered.contains("Auto-generated by AppKitLowering: NSObject-direct"))
    }

    @Test("Cross-file: a class rooted at NSObject through an in-tree base gets nonisolated init synthesis; a forest subclass does not")
    func crossFileInitIsolationRoots() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appkit-iso-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // ModelBase: NSObject (in one file); ModelLeaf: ModelBase (another file) —
        // chain reaches literal NSObject → NSObject-direct → synthesize.
        try "class ModelBase: NSObject { var a = 0 }"
            .write(to: tmp.appendingPathComponent("ModelBase.swift"), atomically: true, encoding: .utf8)
        let leafURL = tmp.appendingPathComponent("ModelLeaf.swift")
        try "class ModelLeaf: ModelBase { var b = 0 }"
            .write(to: leafURL, atomically: true, encoding: .utf8)
        // ViewBase: UIView; ViewLeaf: ViewBase — forest, left alone.
        try "class ViewBase: UIView { var a = 0 }"
            .write(to: tmp.appendingPathComponent("ViewBase.swift"), atomically: true, encoding: .utf8)
        let viewLeafURL = tmp.appendingPathComponent("ViewLeaf.swift")
        try "class ViewLeaf: ViewBase { var b = 0 }"
            .write(to: viewLeafURL, atomically: true, encoding: .utf8)

        _ = try AppKitLowering().lowerInPlace(sourceDir: tmp)
        let leaf = try String(contentsOf: leafURL, encoding: .utf8)
        let viewLeaf = try String(contentsOf: viewLeafURL, encoding: .utf8)
        // ModelLeaf chain reaches NSObject (via ModelBase) → synthesized nonisolated init.
        #expect(leaf.contains("nonisolated override init() { super.init() }"))
        // ViewLeaf chain reaches the @MainActor forest (via ViewBase: UIView) → left alone.
        #expect(!viewLeaf.contains("nonisolated"))
        #expect(!viewLeaf.contains("override init()"))
    }

    // MARK: - actor-isolation RIPPLE (Pass 5): @MainActor isolated deinit

    @Test("deinit in a FOREST (UIView) class is isolated with @MainActor")
    func forestDeinitIsolated() {
        let source = """
        class MyView: UIView {
            var timer: Timer?
            deinit {
                timer?.invalidate()
                removeFromSuperview()
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("@MainActor deinit {"))
        // The body is untouched (no rewrite / re-indent).
        #expect(lowered.contains("timer?.invalidate()"))
        #expect(lowered.contains("removeFromSuperview()"))
        // No assumeIsolated wrap — isolation is on the deinit itself.
        #expect(!lowered.contains("assumeIsolated"))
        // Idempotent: a second pass does not double-annotate.
        let twice = AppKitLowering().lower(lowered)
        #expect(twice == lowered)
        let annots = lowered.components(separatedBy: "@MainActor deinit").count - 1
        #expect(annots == 1)
    }

    @Test("deinit in a UIViewController subclass is isolated (forest controller root)")
    func forestControllerDeinitIsolated() {
        let source = """
        class MyVC: UIViewController {
            deinit {
                NotificationCenter.default.removeObserver(self)
                view.removeFromSuperview()
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("@MainActor deinit {"))
        #expect(lowered.contains("view.removeFromSuperview()"))
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("an EMPTY forest deinit is STILL isolated (the mismatch is structural, not body)")
    func emptyForestDeinitIsolated() {
        // Even a body-less deinit mismatches the @MainActor base's isolated deinit.
        let lowered = AppKitLowering().lower("class MyView: UIView { deinit {} }")
        #expect(lowered.contains("@MainActor deinit {"))
    }

    @Test("deinit in an NSObject-DIRECT model class is LEFT ALONE (matches NSObject's nonisolated deinit)")
    func modelDeinitLeftAlone() {
        let source = """
        class Model: NSObject {
            var token: Int = 0
            deinit {
                token = 0
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        // A model's nonisolated deinit matches NSObject's; isolating it would be
        // needless and wrong (model objects can dealloc off-main).
        #expect(!lowered.contains("@MainActor deinit"))
    }

    @Test("deinit in a class with NO superclass is left alone (cannot prove forest root)")
    func rootlessDeinitLeftAlone() {
        let lowered = AppKitLowering().lower("class Plain { deinit { print(\"x\") } }")
        #expect(!lowered.contains("@MainActor deinit"))
    }

    @Test("deinit in a class with an UNKNOWN foreign base is left alone (cannot prove main-pinned)")
    func unknownBaseDeinitLeftAlone() {
        // SomeForeignThing is not in the map and is not a known forest root.
        let lowered = AppKitLowering().lower(
            "class C: SomeForeignThing { deinit { cleanup() } }"
        )
        #expect(!lowered.contains("@MainActor deinit"))
    }

    @Test("a deinit already carrying @MainActor / nonisolated is left untouched")
    func deinitWithIsolationLeftAlone() {
        // @MainActor already present → idempotent no-op (no double-annotation).
        let already = AppKitLowering().lower("class MyView: UIView { @MainActor deinit { cleanup() } }")
        #expect(already.components(separatedBy: "@MainActor deinit").count - 1 == 1)
        // An explicit `nonisolated deinit` is a deliberate author choice we never flip.
        let noniso = AppKitLowering().lower("class MyView: UIView { nonisolated deinit { cleanup() } }")
        #expect(!noniso.contains("@MainActor"))
        #expect(noniso.contains("nonisolated deinit"))
    }

    @Test("isolating a forest deinit preserves the body verbatim (no re-indent / rewrite)")
    func forestDeinitBodyPreserved() {
        let source = """
        class MyView: UIView {
            var children: [UIView] = []
            deinit {
                for child in children {
                    child.removeFromSuperview()
                }
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("@MainActor deinit {"))
        // Body block is byte-identical (only the attribute was prepended).
        #expect(lowered.contains("""
                for child in children {
                    child.removeFromSuperview()
                }
        """))
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("Cross-file: a deinit isolates when rooted at the forest OR when its immediate base is an in-tree @MainActor class; an NSObject-DIRECT model root is left alone")
    func crossFileDeinitForestRoots() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appkit-deinit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // ViewBase: UIView (one file); ViewLeaf: ViewBase (another) with a deinit —
        // chain reaches the forest through ViewBase → isolate.
        try "class ViewBase: UIView { var a = 0 }"
            .write(to: tmp.appendingPathComponent("ViewBase.swift"), atomically: true, encoding: .utf8)
        let viewLeafURL = tmp.appendingPathComponent("ViewLeaf.swift")
        try "class ViewLeaf: ViewBase {\n    deinit { removeFromSuperview() }\n}"
            .write(to: viewLeafURL, atomically: true, encoding: .utf8)
        // ModelBase: NSObject (NSObject-DIRECT) — its deinit is LEFT ALONE: its
        // immediate base is foreign NSObject, whose nonisolated deinit it matches.
        let modelBaseURL = tmp.appendingPathComponent("ModelBase.swift")
        try "class ModelBase: NSObject {\n    var a = 0\n    deinit { rootTeardown() }\n}"
            .write(to: modelBaseURL, atomically: true, encoding: .utf8)
        // ModelLeaf: ModelBase — its IMMEDIATE base ModelBase is an in-tree
        // (@MainActor by default-isolation) class, so ModelBase's implicit/explicit
        // deinit is isolated and ModelLeaf's deinit must match → isolate. (This is
        // the StickerPackDataSource case the widened gate fixes.)
        let modelLeafURL = tmp.appendingPathComponent("ModelLeaf.swift")
        try "class ModelLeaf: ModelBase {\n    deinit { teardown() }\n}"
            .write(to: modelLeafURL, atomically: true, encoding: .utf8)

        _ = try AppKitLowering().lowerInPlace(sourceDir: tmp)
        let viewLeaf = try String(contentsOf: viewLeafURL, encoding: .utf8)
        let modelBase = try String(contentsOf: modelBaseURL, encoding: .utf8)
        let modelLeaf = try String(contentsOf: modelLeafURL, encoding: .utf8)
        #expect(viewLeaf.contains("@MainActor deinit {"))
        // NSObject-DIRECT base: left alone (immediate base is foreign NSObject).
        #expect(modelBase.contains("rootTeardown()"))
        #expect(!modelBase.contains("@MainActor deinit"))
        // Subclass of an in-tree base: isolated (overrides the base's isolated deinit).
        #expect(modelLeaf.contains("@MainActor deinit"))
    }

    // MARK: - Linux-compat lowering (os.log / os(macOS)) — for WireGuard Tunnel/

    @Test("import os.log is rewritten to import os")
    func osLogImportRewrite() {
        let lowered = AppKitLowering().lower("import os.log\nlet x = 1\n")
        #expect(!lowered.contains("os.log"))
        #expect(lowered.contains("import os"))
        #expect(lowered.contains("let x = 1"))
    }

    @Test("#if os(macOS) is widened to include Linux; iOS untouched; idempotent")
    func osMacOSWidening() {
        let source = """
        #if os(iOS)
        let p = "ios"
        #elseif os(macOS)
        let p = "mac"
        #else
        #error("Unimplemented")
        #endif
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("os(macOS) || os(Linux)"))
        #expect(lowered.contains("#if os(iOS)"))               // iOS branch untouched
        #expect(lowered.contains(#"#error("Unimplemented")"#)) // #else preserved (now dead on Linux)
        // Idempotent: the widened form does not re-match.
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    // MARK: - Timer(timeInterval:repeats:block:) -> QuillTimer.make

    @Test("Timer(timeInterval:repeats:) trailing-closure init becomes QuillTimer.make")
    func timerTrailingClosureRewritten() {
        let source = """
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateLogEntries()
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("QuillTimer.make(timeInterval: 1, repeats: true)"))
        #expect(!lowered.contains("Timer(timeInterval:"))   // the `Timer(` init is gone
        // The closure (incl. its @MainActor call + [weak self]) is preserved verbatim.
        #expect(lowered.contains("self?.updateLogEntries()"))
        #expect(lowered.contains("[weak self]"))
        // Idempotent: QuillTimer.make is a member access, not the `Timer` identifier.
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("Timer(timeInterval:repeats:block:) explicit-block init becomes QuillTimer.make")
    func timerExplicitBlockRewritten() {
        let source = #"let t = Timer(timeInterval: 5, repeats: true, block: { _ in tick() })"#
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("QuillTimer.make(timeInterval: 5, repeats: true, block:"))
        #expect(!lowered.contains("Timer(timeInterval:"))
    }

    @Test("Timer target-action init (timeInterval:target:selector:…) is NOT rewritten")
    func timerTargetActionLeftAlone() {
        let source = #"let t = Timer(timeInterval: 1, target: self, selector: #selector(fire), userInfo: nil, repeats: true)"#
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("Timer(timeInterval: 1, target: self"))   // init untouched
        #expect(!lowered.contains("QuillTimer.make"))
        #expect(lowered.contains(#"Selector("fire")"#))                    // the #selector still lowers
    }

    @Test("Timer.scheduledTimer is NOT rewritten (only the Timer(...) init is)")
    func scheduledTimerLeftAlone() {
        let source = "let t = Timer.scheduledTimer(timeInterval: 1, repeats: true) { _ in tick() }"
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("Timer.scheduledTimer(timeInterval: 1, repeats: true)"))
        #expect(!lowered.contains("QuillTimer.make"))
    }

    // MARK: - extension { override … } merged into the local class

    @Test("override in an extension of a local class is moved into the class body")
    func extensionOverrideMergedIntoClass() {
        let source = """
        class VC: NSViewController {
            func foo() {}
        }
        extension VC {
            override func cancelOperation(_ sender: Any?) { closeClicked() }
            func helper() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        // The override moves into the class (before `extension VC`); helper stays.
        let classPos = lowered.range(of: "class VC")!.lowerBound
        let extPos = lowered.range(of: "extension VC")!.lowerBound
        let cancelPos = lowered.range(of: "override func cancelOperation")!.lowerBound
        #expect(cancelPos > classPos && cancelPos < extPos) // inside the class body
        #expect(lowered.contains("func helper()"))          // non-override stays in the extension
        // Idempotent: a second pass finds no override-in-extension.
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("override in an extension of a NON-local type is left alone")
    func extensionOverrideExternalTypeUntouched() {
        // No `class External` in the file → not a local class → not merged.
        let source = """
        extension External {
            override func foo() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        let extPos = lowered.range(of: "extension External")!.lowerBound
        let fooPos = lowered.range(of: "override func foo")!.lowerBound
        #expect(fooPos > extPos) // still inside the extension
    }

    // MARK: - #imageLiteral → UIImage(named:)! (Transform 1)

    @Test("#imageLiteral(resourceName:) becomes UIImage(named:)!")
    func imageLiteralRewritten() {
        let source = #"let img = #imageLiteral(resourceName: "clock-arabic.pdf")"#
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains(#"UIImage(named: "clock-arabic.pdf")!"#))
        #expect(!lowered.contains("#imageLiteral"))
        // Idempotent: the rewritten form has no macro to re-match.
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("#imageLiteral inside a switch/return keeps its expression position")
    func imageLiteralInReturn() {
        let source = """
        var backgroundImage: UIImage {
            switch self {
            case .arabic:
                return #imageLiteral(resourceName: "clock-arabic.pdf")
            case .baton:
                return #imageLiteral(resourceName: "clock-baton.pdf")
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains(#"return UIImage(named: "clock-arabic.pdf")!"#))
        #expect(lowered.contains(#"return UIImage(named: "clock-baton.pdf")!"#))
        #expect(!lowered.contains("#imageLiteral"))
    }

    // MARK: - #keyPath(...) → string literal (Transform 2)

    @Test("#keyPath(Type.member) becomes the dotted member string (type dropped)")
    func keyPathRewritten() {
        let source = #"let animation = CABasicAnimation(keyPath: #keyPath(CALayer.cornerRadius))"#
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains(#"keyPath: "cornerRadius""#))
        #expect(!lowered.contains("#keyPath"))
        #expect(!lowered.contains("CALayer"))   // the leading type component is dropped
        #expect(AppKitLowering().lower(lowered) == lowered)   // idempotent
    }

    @Test("#keyPath with a multi-component path keeps the member path after the type")
    func keyPathMultiComponent() {
        let source = "let s = #keyPath(Foo.bar.baz)"
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains(#""bar.baz""#))
        #expect(!lowered.contains("Foo"))
        #expect(!lowered.contains("#keyPath"))
    }

    @Test("#keyPath(CAShapeLayer.path) becomes \"path\"")
    func keyPathShapeLayer() {
        let lowered = AppKitLowering().lower("let a = #keyPath(CAShapeLayer.path)")
        #expect(lowered.contains(#""path""#))
        #expect(!lowered.contains("CAShapeLayer"))
    }

    // MARK: - strip .method?( optional-protocol-method call (Transform 3)

    @Test("delegate optional-method call .method?( has its ? stripped")
    func optionalDelegateCallStripped() {
        let source = """
        func f() {
            externalDelegate?.navigationController?(navigationController, willShow: vc, animated: animated)
        }
        """
        let lowered = AppKitLowering().lower(source)
        // The FIRST ? (on the optional `externalDelegate`) is preserved; the SECOND
        // ? (the optional-method-call ? after `.navigationController`) is removed.
        #expect(lowered.contains("externalDelegate?.navigationController(navigationController"))
        #expect(!lowered.contains(".navigationController?("))
    }

    @Test("textView delegate optional-method calls have their ? stripped")
    func optionalTextViewDelegateCallsStripped() {
        let source = """
        func g() {
            _ = bodyRangesDelegate?.textView?(textView, shouldChangeTextIn: range, replacementText: text)
            bodyRangesDelegate?.textViewDidChangeSelection?(textView)
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("bodyRangesDelegate?.textView(textView"))
        #expect(lowered.contains("bodyRangesDelegate?.textViewDidChangeSelection(textView)"))
        #expect(!lowered.contains(".textView?("))
        #expect(!lowered.contains(".textViewDidChangeSelection?("))
    }

    @Test("a bare optional-closure call foo?( is PRESERVED (not a member access)")
    func optionalClosureCallPreserved() {
        // `onTap` is a stored optional closure, not a delegate member access.
        let source = "func h() { onTap?(sender) }"
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("onTap?(sender)"))   // ? intact — real optional-closure call
    }

    @Test("a non-delegate .property?( optional-closure call is PRESERVED")
    func optionalMemberClosureCallPreserved() {
        // `.completionHandler` is not a known UIKit-delegate name, so it is left alone.
        let source = "func i() { self.completionHandler?(result) }"
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("self.completionHandler?(result)"))
    }

    @Test("optional-protocol-call strip is idempotent")
    func optionalDelegateCallStripIdempotent() {
        let source = "func j() { d?.tableView?(tableView, didSelectRowAt: indexPath) }"
        let once = AppKitLowering().lower(source)
        #expect(AppKitLowering().lower(once) == once)
        #expect(once.contains("d?.tableView(tableView"))
    }

    // MARK: - @MainActor deinit completeness (Transform 4)

    @Test("UITextView-subclass-chain deinit gets @MainActor (forest widened to UITextView)")
    func deinitForestUITextView() {
        // OWSTextView: UITextView and BodyRangesTextView: OWSTextView — the chain
        // reaches UITextView, now a recognized forest root.
        let source = """
        open class OWSTextView: UITextView {}
        open class BodyRangesTextView: OWSTextView {
            deinit {
                pickerView?.removeFromSuperview()
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("@MainActor deinit"))
    }

    @Test("deinit of a subclass of an in-tree NSObject-direct base gets @MainActor")
    func deinitInTreeNSObjectDirectBase() {
        // BaseStickerPackDataSource: NSObject is @MainActor by default-isolation, so
        // its implicit deinit is isolated; the subclass deinit must match it even
        // though the chain roots at NSObject (forest check alone is false).
        let source = """
        public class BaseStickerPackDataSource: NSObject {}
        public class TransientStickerPackDataSource: BaseStickerPackDataSource {
            deinit {
                let urls = self.temporaryFileUrls
                cleanup(urls)
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("@MainActor deinit"))
    }

    @Test("deinit of an NSObject-DIRECT model object is LEFT ALONE (off-main ok)")
    func deinitNSObjectDirectModelLeftAlone() {
        // Immediate base is foreign NSObject → nonisolated deinit matches NSObject's
        // nonisolated base deinit; isolating it would be wrong.
        let source = """
        public class MyCache: NSObject {
            deinit { flush() }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(!lowered.contains("@MainActor deinit"))
    }

    @Test("@MainActor deinit pass is idempotent")
    func deinitMainActorIdempotent() {
        let source = """
        open class V: UITextView {
            deinit { teardown() }
        }
        """
        let once = AppKitLowering().lower(source)
        #expect(once.contains("@MainActor deinit"))
        #expect(AppKitLowering().lower(once) == once)
    }

    // MARK: - cross-file extension-member relocation (Transform 5)

    @Test("base extension method overridden by a subclass elsewhere moves into the base body")
    func crossFileExtensionMethodRelocated() {
        // Single file modeling both halves: Base's method lives in an extension, and
        // Sub (a subclass) overrides it — so Base.scrollViewDidScroll must move into
        // the Base class body.
        let source = """
        open class Base: UIViewController {
            func existing() {}
        }
        extension Base {
            open func scrollViewDidScroll(_ scrollView: UIScrollView) {}
            func unrelatedHelper() {}
        }
        open class Sub: Base {
            override public func scrollViewDidScroll(_ scrollView: UIScrollView) {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        let classOpen = lowered.range(of: "class Base")!.lowerBound
        let extOpen = lowered.range(of: "extension Base")!.lowerBound
        let movedPos = lowered.range(of: "func scrollViewDidScroll")!.lowerBound
        // The moved method is now in the class body (before `extension Base`).
        #expect(movedPos > classOpen && movedPos < extOpen)
        // The unrelated, non-overridden helper stays in the extension.
        #expect(lowered.contains("func unrelatedHelper()"))
        // Idempotent.
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("a base extension method NOT overridden by any subclass stays in the extension")
    func crossFileExtensionMethodNotOverriddenStays() {
        let source = """
        open class Base: UIViewController {}
        extension Base {
            open func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {}
        }
        open class Sub: Base {
            func unrelated() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        let extOpen = lowered.range(of: "extension Base")!.lowerBound
        let methodPos = lowered.range(of: "func tableView")!.lowerBound
        #expect(methodPos > extOpen) // still in the extension
    }

    @Test("override of forwardingTarget(for:) is retained against shim class-body member")
    func forwardingTargetOverrideRetained() {
        let source = """
        open class V: UITextView {
            override open func forwardingTarget(for aSelector: Selector!) -> Any? {
                return nil
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("func forwardingTarget(for aSelector: Selector!)"))
        #expect(lowered.contains("override open func forwardingTarget"))
        // The decl keeps its own line + indentation (no merge onto the brace line).
        #expect(AppKitLowering().lower(lowered) == lowered)   // idempotent
    }

    @Test("forwardingTarget override is retained even with a class-body super call")
    func forwardingTargetOverrideWithSuperCall() {
        // The exact BodyRangesTextView shape: an `override open func forwardingTarget`
        // whose body calls `super.forwardingTarget`. The shim now provides this as a
        // class-body member, so the override is valid and must be retained.
        let source = """
        open class BodyRangesTextView: UITextView {
            override open func forwardingTarget(for aSelector: Selector!) -> Any? {
                return super.forwardingTarget(for: aSelector)
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("override open func forwardingTarget(for aSelector: Selector!)"))
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    // MARK: - Problem C: no-superclass dispatch witness

    @Test("A class with only a protocol in its inheritance clause (no superclass) gets a NON-override witness")
    func noSuperclassDispatchWitness() {
        // `SignalAttachment: CustomDebugStringConvertible` has NO class superclass — only
        // a protocol. The dispatch injector must emit the root (non-override) witness
        // form: `public func quillPerform { … default: break }` + a conformance, NEVER
        // an `override`/`super.quillPerform` (a no-superclass class can use neither).
        let source = """
        public class SignalAttachment: CustomDebugStringConvertible {
            @objc private func didReceiveMemoryWarningNotification() { }
            public var debugDescription: String { "x" }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("public func quillPerform(_ selector: Selector, with sender: Any?)"))
        #expect(!lowered.contains("override func quillPerform"))
        #expect(!lowered.contains("super.quillPerform"))
        #expect(lowered.contains("default: break"))
        #expect(lowered.contains("QuillSelectorDispatching"))
        #expect(AppKitLowering().lower(lowered) == lowered)   // idempotent
    }

    @Test("A protocol-only inheritance clause is NOT treated as a class superclass (Error / Comparable)")
    func protocolInheritanceNotASuperclass() {
        // `class Foo: Error` with @objc actions must root its own dispatch chain (the
        // protocol is not a foreign base), so the witness is non-override.
        let source = """
        public class Foo: Error {
            @objc func tap() {}
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("public func quillPerform"))
        #expect(!lowered.contains("override func quillPerform"))
        #expect(!lowered.contains("super.quillPerform"))
    }

    // MARK: - Problem A1: @MainActor on local nested functions

    @Test("Local nested functions get @MainActor; top-level and type-member funcs do not")
    func nestedLocalFunctionsMainActor() {
        let source = """
        func topLevel() {}
        class VC {
            func member() {}
            func doStuff() {
                present { modal in
                    func showToast() { self.view = nil }
                    func failed() { showToast() }
                    showToast()
                }
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        // Nested funcs inside the closure body are marked.
        #expect(lowered.contains("@MainActor func showToast()"))
        #expect(lowered.contains("@MainActor func failed()"))
        // Top-level and type-member funcs are NOT (they already get default isolation).
        #expect(!lowered.contains("@MainActor func topLevel"))
        #expect(!lowered.contains("@MainActor func member"))
        #expect(lowered.contains("func topLevel() {}"))
        #expect(lowered.contains("func member() {}"))
        // Idempotent: no double-annotation on a re-run.
        #expect(!lowered.contains("@MainActor @MainActor"))
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("A func nested in a computed-property getter is marked @MainActor")
    func nestedFunctionInAccessorMainActor() {
        let source = """
        class C {
            var n: Int {
                func helper() -> Int { 1 }
                return helper()
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("@MainActor func helper()"))
    }

    @Test("A nested func deep inside another nested func is also marked")
    func deeplyNestedFunctionMainActor() {
        let source = """
        class C {
            func f() {
                run {
                    func outer() {
                        func inner() { self.x = 1 }
                        inner()
                    }
                    outer()
                }
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("@MainActor func outer()"))
        #expect(lowered.contains("@MainActor func inner()"))
    }

    @Test("A nested func already carrying @MainActor / nonisolated is left untouched")
    func nestedFunctionWithIsolationLeftAlone() {
        let source = """
        class C {
            func f() {
                run {
                    @MainActor func a() {}
                    nonisolated func b() {}
                }
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(!lowered.contains("@MainActor @MainActor"))
        #expect(lowered.contains("nonisolated func b()"))
        #expect(!lowered.contains("@MainActor func b"))
        // The already-@MainActor one is unchanged (single annotation).
        #expect(lowered.components(separatedBy: "@MainActor func a()").count - 1 == 1)
    }

    // MARK: - Problem A2: init-body isolation refinement

    @Test("An override init() whose body touches @MainActor members is LEFT @MainActor")
    func initWithMainActorBodyLeftAlone() {
        // CVTextLabel: `override public init()` mutates `label.backgroundColor` /
        // `label.isOpaque` (@MainActor). A nonisolated init can't touch those, so it
        // must stay @MainActor even though the class is NSObject-direct.
        let source = """
        public class CVTextLabel: NSObject {
            private let label = Label()
            override public init() {
                label.backgroundColor = .clear
                label.isOpaque = false
                super.init()
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("override public init()"))
        #expect(!lowered.contains("nonisolated override public init()"))
        // And no second init is synthesized (the class already declares init()).
        #expect(!lowered.contains("Auto-generated by AppKitLowering"))
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("An override init() with a trivial body (super.init / plain stored assign) is nonisolated")
    func initWithTrivialBodyNonisolated() {
        let source = """
        class Model: NSObject {
            var n = 0
            override init() {
                n = 5
                super.init()
            }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(lowered.contains("nonisolated override init()"))
    }

    @Test("A super.init-only override init() is nonisolated (trivial body)")
    func initSuperOnlyNonisolated() {
        let lowered = AppKitLowering().lower("class Model: NSObject { override init() { super.init() } }")
        #expect(lowered.contains("nonisolated override init()"))
    }

    // MARK: - Problem A3: init-override actor alignment

    @Test("A subclass with only init(arg:) gets a synthesized nonisolated override init() to match its NSObject-direct base")
    func subclassSynthesizesNonisolatedInitToMatchBase() {
        // StickerPackDataSource: BaseStickerPackDataSource: NSObject (synth nonisolated
        // init); InstalledStickerPackDataSource has only `init(stickerPackInfo:)` yet
        // still implicitly overrides the base init() — so it needs an explicit
        // `nonisolated override init()`; Recent's explicit `override init()` is annotated.
        let source = """
        public class BaseStickerPackDataSource: NSObject { var x = 0 }
        public class InstalledStickerPackDataSource: BaseStickerPackDataSource {
            let info: Int
            public init(stickerPackInfo: Int) { self.info = stickerPackInfo; super.init() }
        }
        public class RecentStickerPackDataSource: BaseStickerPackDataSource {
            override public init() { super.init() }
        }
        """
        let lowered = AppKitLowering().lower(source)
        // Base synth.
        #expect(lowered.contains("nonisolated override init() { super.init() }"))
        // Recent annotated.
        #expect(lowered.contains("nonisolated override public init()"))
        // Installed gets an unavailable synthesized nonisolated override init() despite
        // having init(arg:), because its stored `let info` cannot be initialized by a
        // callable no-arg init.
        let installedStart = lowered.range(of: "class InstalledStickerPackDataSource")!.lowerBound
        let recentStart = lowered.range(of: "class RecentStickerPackDataSource")!.lowerBound
        let installedBody = String(lowered[installedStart..<recentStart])
        #expect(installedBody.contains("@available(*, unavailable)"))
        #expect(installedBody.contains(#"nonisolated override init() { fatalError("init() is unavailable") }"#))
        #expect(AppKitLowering().lower(lowered) == lowered)   // idempotent
    }

    @Test("A subclass of an Error-rooted base (root class, no explicit init) gets a nonisolated override init()")
    func subclassOfErrorRootedBaseSynthesizesInit() {
        // SheetDisplayableError: Error is a ROOT class with no explicit init() — its
        // compiler-synthesized init() is nonisolated under -default-isolation MainActor,
        // so subclasses must match with a nonisolated override init().
        let source = """
        open class SheetDisplayableError: Error {
            @MainActor open func showSheet() { }
        }
        open class ActionSheetDisplayableError: SheetDisplayableError {
            private let m: String?
            public init(m: String?) { self.m = m }
        }
        """
        let lowered = AppKitLowering().lower(source)
        let subStart = lowered.range(of: "class ActionSheetDisplayableError")!.lowerBound
        let subBody = String(lowered[subStart...])
        #expect(subBody.contains("@available(*, unavailable)"))
        #expect(subBody.contains(#"nonisolated override init() { fatalError("init() is unavailable") }"#))
        // The Error-root base itself is NOT given a synthesized init (it overrides nothing).
        let baseBody = String(lowered[lowered.startIndex..<subStart])
        #expect(!baseBody.contains("nonisolated override init"))
        #expect(AppKitLowering().lower(lowered) == lowered)
    }

    @Test("A class with an UNKNOWN foreign base does NOT get a synthesized init (cannot prove base init is nonisolated)")
    func unknownForeignBaseNoSynthesizedInit() {
        // `Measurement: CVMeasurementObject` — CVMeasurementObject is not in the tree, so
        // we cannot prove its init() is nonisolated; synthesizing `nonisolated override
        // init()` could be wrong (and a struct/foreign base can't even take it).
        let source = """
        public class Measurement: CVMeasurementObject {
            let size: Int
            public init(size: Int) { self.size = size }
        }
        """
        let lowered = AppKitLowering().lower(source)
        #expect(!lowered.contains("nonisolated override init"))
    }

    @Test("Cross-file A3: a subclass of an in-tree NSObject-direct base synthesizes a nonisolated init")
    func crossFileSubclassInitAlignment() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("appkit-a3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Base (NSObject-direct) in one file; subclass with only init(arg:) in another.
        try "public class DataBase: NSObject { var a = 0 }"
            .write(to: tmp.appendingPathComponent("DataBase.swift"), atomically: true, encoding: .utf8)
        let leafURL = tmp.appendingPathComponent("DataLeaf.swift")
        try "public class DataLeaf: DataBase {\n    let n: Int\n    public init(n: Int) { self.n = n; super.init() }\n}"
            .write(to: leafURL, atomically: true, encoding: .utf8)
        _ = try AppKitLowering().lowerInPlace(sourceDir: tmp)
        let leaf = try String(contentsOf: leafURL, encoding: .utf8)
        #expect(leaf.contains("@available(*, unavailable)"))
        #expect(leaf.contains(#"nonisolated override init() { fatalError("init() is unavailable") }"#))
    }
}
