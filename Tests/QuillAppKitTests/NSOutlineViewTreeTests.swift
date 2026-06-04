import Foundation
import Testing
import AppKit

/// Deeper coverage of QuillAppKit's reimplemented `NSOutlineView` tree logic —
/// nested expansion and expand-state preservation across collapse, which
/// NetNewsWire's sidebar (folders of feeds) relies on. Model-only (no Qt);
/// validated on the Swift Linux Backends job, since the reimplemented AppKit
/// module is Linux-only.
@MainActor
@Suite("QuillAppKit NSOutlineView — nested trees + expand-state preservation")
struct NSOutlineViewTreeTests {

    final class NestedTreeSource: NSObject, NSOutlineViewDataSource {
        // nil -> [A, B];  A -> [A1, A2];  A1 -> [A1a].  A and A1 are expandable.
        func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            switch item as? String {
            case .none: return 2
            case "A": return 2
            case "A1": return 1
            default: return 0
            }
        }
        func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            switch item as? String {
            case .none: return ["A", "B"][index]
            case "A": return ["A1", "A2"][index]
            case "A1": return "A1a"
            default: return ""
            }
        }
        func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
            ["A", "A1"].contains(item as? String ?? "")
        }
        func outlineView(_ ov: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
            item
        }
    }

    private func makeOutline() -> NSOutlineView {
        let ov = NSOutlineView()
        ov.dataSource = NestedTreeSource()
        ov.reloadData()
        return ov
    }

    @Test("nested expansion reveals deeper levels in order")
    func nestedExpansion() {
        let ov = makeOutline()
        #expect(ov.numberOfRows == 2)                       // A, B
        ov.expandItem("A"); ov.reloadData()
        #expect(ov.numberOfRows == 4)                       // A, A1, A2, B
        ov.expandItem("A1"); ov.reloadData()
        #expect(ov.numberOfRows == 5)                       // A, A1, A1a, A2, B
        #expect(ov.item(atRow: 2) as? String == "A1a")
        #expect(ov.level(forRow: 2) == 2)
    }

    @Test("collapsing a node preserves its children's expanded state")
    func collapsePreservesChildState() {
        let ov = makeOutline()
        ov.expandItem("A"); ov.expandItem("A1"); ov.reloadData()
        #expect(ov.numberOfRows == 5)
        ov.collapseItem("A"); ov.reloadData()
        #expect(ov.numberOfRows == 2)                       // A, B
        #expect(ov.isItemExpanded("A1"))                    // A1's state preserved
        ov.expandItem("A"); ov.reloadData()
        #expect(ov.numberOfRows == 5)                       // A1 comes back already-expanded
    }

    @Test("collapseChildren collapses descendants too")
    func collapseChildrenCollapsesDescendants() {
        let ov = makeOutline()
        ov.expandItem("A"); ov.expandItem("A1"); ov.reloadData()
        #expect(ov.numberOfRows == 5)
        ov.collapseItem("A", collapseChildren: true); ov.reloadData()
        #expect(!ov.isItemExpanded("A1"))
        ov.expandItem("A"); ov.reloadData()
        #expect(ov.numberOfRows == 4)                       // A, A1, A2, B — A1a stays hidden
    }
}
