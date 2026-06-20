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

    private struct TableFixture {
        let table: NSTableView
        let source: Source
        let delegate: ViewDelegate
    }

    private func makeTable() -> TableFixture {
        let tv = NSTableView()
        tv.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
        let source = Source()
        let delegate = ViewDelegate()
        tv.dataSource = source
        tv.delegate = delegate
        tv.reloadData()
        return TableFixture(table: tv, source: source, delegate: delegate)
    }

    @Test("view(atColumn:row:) builds via the delegate and caches the instance")
    func viewBasedCellsCached() {
        let fixture = makeTable()
        withExtendedLifetime((fixture.source, fixture.delegate)) {
            let tv = fixture.table
            #expect(tv.numberOfRows == 3)
            let v0 = tv.view(atColumn: 0, row: 0, makeIfNecessary: true)
            #expect(v0 != nil)
            // Second access returns the cached instance — even with makeIfNecessary: false.
            #expect(tv.view(atColumn: 0, row: 0, makeIfNecessary: false) === v0)
        }
    }

    @Test("view(atColumn:row:) is nil out of range, or uncached with makeIfNecessary false")
    func viewBoundsAndLazy() {
        let fixture = makeTable()
        withExtendedLifetime((fixture.source, fixture.delegate)) {
            let tv = fixture.table
            #expect(tv.view(atColumn: 0, row: 99, makeIfNecessary: true) == nil)   // row out of range
            #expect(tv.view(atColumn: 5, row: 0, makeIfNecessary: true) == nil)    // column out of range
            #expect(tv.view(atColumn: 0, row: 2, makeIfNecessary: false) == nil)   // not made yet
        }
    }

    @Test("reloadData clears the cell-view cache")
    func reloadClearsCache() {
        let fixture = makeTable()
        withExtendedLifetime((fixture.source, fixture.delegate)) {
            let tv = fixture.table
            _ = tv.view(atColumn: 0, row: 0, makeIfNecessary: true)   // populate the cache
            tv.reloadData()                                          // clears cachedCellViews
            #expect(tv.view(atColumn: 0, row: 0, makeIfNecessary: false) == nil)
        }
    }
}
