import Foundation
import Testing
import AppKit

/// QuillAppKit NSBox (titled/bordered container) — compile + property surface
/// WireGuard's TunnelDetailTableViewController uses. New file (not
/// AppKitSurfaceTests) to avoid colliding with in-flight surface PRs.
@Suite("QuillAppKit — NSBox")
struct NSBoxTests {
    @Test("NSBox() inherits NSView init; titlePosition / fillColor / contentView work")
    func box() {
        let box = NSBox()                 // inherits NSView's convenience init()
        box.titlePosition = .noTitle
        box.fillColor = .unemphasizedSelectedContentBackgroundColor
        box.boxType = .custom
        #expect(box.titlePosition == .noTitle)
        #expect(box.boxType == .custom)

        let content = NSView(frame: .zero)
        box.contentView = content
        #expect(box.contentView === content)
        #expect(box.subviews.contains { $0 === content })  // contentView is added as a subview
    }
}
