import Foundation
import Testing
import AppKit

/// AppKit shadow surface added so WireGuard's UnusableTunnelDetailViewController
/// compiles against QuillAppKit: NSTextField(labelWithAttributedString:) and
/// NSStackView's views-initializer + setCustomSpacing (with Foundation's
/// NSEdgeInsets). Model-only (no Qt); runs on the Swift Linux Backends job.
/// Driven from real upstream compile errors (the gap-analysis spike).
@Suite("QuillAppKit surface — UnusableTunnelDetail dependencies")
struct AppKitSurfaceTests {
    @Test("NSTextField(labelWithAttributedString:) carries the attributed string's text")
    func textFieldLabelWithAttributedString() {
        let label = NSTextField(labelWithAttributedString: NSAttributedString(string: "Public key:"))
        #expect(label.stringValue == "Public key:")
    }

    @Test("NSStackView(views:) seeds arranged subviews; edgeInsets struct + setCustomSpacing work")
    func stackViewViewsInit() {
        let a = NSView(frame: .zero)
        let b = NSView(frame: .zero)
        let stack = NSStackView(views: [a, b])
        #expect(stack.arrangedSubviews.count == 2)
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        #expect(stack.edgeInsets.top == 5 && stack.edgeInsets.right == 5)
        stack.setCustomSpacing(8, after: a) // compiles (no-op until layout models spacing)
    }
}
