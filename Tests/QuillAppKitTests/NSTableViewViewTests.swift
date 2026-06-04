import Foundation
import Testing
import AppKit

/// Coverage of QuillAppKit's reimplemented `NSTableView` view-based cell path —
/// `view(atColumn:row:)` routing through the delegate plus cell-view caching,
/// which NetNewsWire's view-based timeline relies on. Model-only (no Qt);
/// validated on the Swift Linux Backends job (reimpl AppKit is Linux-only).
@MainActor
@Suite("QuillAppKit NSTableView — view-based cells + cache")
struct NSTableViewViewTests {

    final class ViewDelegate: NSObject, NSTableViewDelegate {
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            NSView()
        }
    }

    final class Source: NSObject, NSTableViewDataSource {
        func numberOfRows(in tableView: NSTableView) -> Int { 3 }
    }

    private func makeTable() -> NSTableView {
        let tv = NSTableView()
        tv.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
        tv.dataSource = Source()
        tv.delegate = ViewDelegate()
        tv.reloadData()
        return tv
    }

    @Test("view(atColumn:row:) builds via the delegate and caches the instance")
    func viewBasedCellsCached() {
        let tv = makeTable()
        #expect(tv.numberOfRows == 3)
        let v0 = tv.view(atColumn: 0, row: 0, makeIfNecessary: true)
        #expect(v0 != nil)
        // Second access returns the cached instance — even with makeIfNecessary: false.
        #expect(tv.view(atColumn: 0, row: 0, makeIfNecessary: false) === v0)
    }

    @Test("view(atColumn:row:) is nil out of range, or uncached with makeIfNecessary false")
    func viewBoundsAndLazy() {
        let tv = makeTable()
        #expect(tv.view(atColumn: 0, row: 99, makeIfNecessary: true) == nil)   // row out of range
        #expect(tv.view(atColumn: 5, row: 0, makeIfNecessary: true) == nil)    // column out of range
        #expect(tv.view(atColumn: 0, row: 2, makeIfNecessary: false) == nil)   // not made yet
    }

    @Test("reloadData clears the cell-view cache")
    func reloadClearsCache() {
        let tv = makeTable()
        _ = tv.view(atColumn: 0, row: 0, makeIfNecessary: true)   // populate the cache
        tv.reloadData()                                          // clears cachedCellViews
        #expect(tv.view(atColumn: 0, row: 0, makeIfNecessary: false) == nil)
    }
}
