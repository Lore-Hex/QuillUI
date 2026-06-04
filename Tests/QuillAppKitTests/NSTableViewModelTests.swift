import Foundation
import Testing
import AppKit

/// Model-layer tests for QuillAppKit's reimplemented `NSTableView` / `NSOutlineView`
/// — the data-source-driven row + tree logic NetNewsWire's timeline (table) and
/// sidebar (outline) rely on. These exercise pure model behavior (reloadData,
/// selection, tree flattening); Qt rendering is a separate later slice. The
/// reimplemented AppKit module only exists on Linux (macOS uses Apple's real
/// AppKit), so this suite is validated on the Swift Linux Backends job — it's
/// the first coverage of these previously-untested classes.
@MainActor
@Suite("QuillAppKit NSTableView / NSOutlineView model")
struct NSTableViewModelTests {

    // MARK: - NSTableView

    final class TableSource: NSObject, NSTableViewDataSource {
        var rows: Int
        init(rows: Int) { self.rows = rows }
        func numberOfRows(in tableView: NSTableView) -> Int { rows }
        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            "row\(row)"
        }
    }

    @Test("reloadData pulls numberOfRows from the data source")
    func tableReloadData() {
        let tv = NSTableView()
        let src = TableSource(rows: 5)
        tv.dataSource = src
        tv.reloadData()
        #expect(tv.numberOfRows == 5)
        src.rows = 2
        tv.reloadData()
        #expect(tv.numberOfRows == 2)
    }

    @Test("selectRowIndexes accepts in-range rows; out-of-range is ignored; deselectAll clears")
    func tableSelection() {
        let tv = NSTableView()
        tv.dataSource = TableSource(rows: 5)
        tv.reloadData()
        tv.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        #expect(tv.selectedRowIndexes.contains(2))
        // Row 99 is beyond numberOfRows → not selected.
        tv.selectRowIndexes(IndexSet(integer: 99), byExtendingSelection: false)
        #expect(!tv.selectedRowIndexes.contains(99))
        tv.deselectAll(nil)
        #expect(tv.selectedRowIndexes.isEmpty)
    }

    // MARK: - NSOutlineView

    final class TreeSource: NSObject, NSOutlineViewDataSource {
        // nil -> [A, B];  A -> [A1, A2];  everything else -> no children. Only A is expandable.
        func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            switch item as? String {
            case .none: return 2
            case "A": return 2
            default: return 0
            }
        }
        func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            switch item as? String {
            case .none: return ["A", "B"][index]
            case "A": return ["A1", "A2"][index]
            default: return ""
            }
        }
        func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? String) == "A"
        }
        func outlineView(_ ov: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
            item
        }
    }

    @Test("outline shows roots; expanding reveals children one level down; collapsing hides them")
    func outlineExpandCollapse() {
        let ov = NSOutlineView()
        ov.dataSource = TreeSource()
        ov.reloadData()
        #expect(ov.numberOfRows == 2)                       // A, B
        #expect(ov.item(atRow: 0) as? String == "A")
        #expect(ov.isExpandable("A"))
        #expect(!ov.isExpandable("B"))

        ov.expandItem("A")
        ov.reloadData()
        #expect(ov.numberOfRows == 4)                       // A, A1, A2, B
        #expect(ov.item(atRow: 1) as? String == "A1")
        #expect(ov.level(forRow: 0) == 0)
        #expect(ov.level(forRow: 1) == 1)

        ov.collapseItem("A")
        ov.reloadData()
        #expect(ov.numberOfRows == 2)
    }
}
