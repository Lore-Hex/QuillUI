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
}
