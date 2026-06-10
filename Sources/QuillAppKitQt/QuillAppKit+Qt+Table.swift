// QuillAppKitQt — NSTableView Qt rendering (component ladder, issue #231).
//
// AppKit's NSTableView keeps its cell/row views in PRIVATE caches and never adds
// them to `subviews`; the macOS table machinery draws them itself. Our Qt render
// pass (realizeQtSubtree → layoutQtSubtree → grabQtWindowPNG) only walks the
// `subviews` tree, so a rendered table would be empty. This slice promotes the
// data source's rows into the real view tree so they render — the prerequisite
// for rendering any real table-backed VC (WireGuard's tunnel list, log view, …).
//
// Approach: drive the existing data-source/delegate path to build each row's REAL
// cell view, add it as a subview, and pin it with synthesized constraints (full
// width, fixed row height, vertically chained by intercellSpacing) so the kiwi
// layout pass positions it. No native QTableView / C++ change — it reuses the
// proven NSView→Qt machinery, exactly like NSStackView's constraint synthesis.

import AppKit
import QuillUIKit

extension NSTableView {
    /// Materialize the data source's rows as real subviews so the Qt render pass
    /// reaches them. Reloads the row count, builds each row's cell via the
    /// delegate's `viewFor` (which populates the cell's labels/images at bind
    /// time), adds it to the view tree, and pins it into a vertical run. Idempotent
    /// — a prior materialized set is removed first, so re-rendering never stacks
    /// duplicate rows. Call after the table is in the window, before layout.
    public func quillMaterializeRowsIntoSubtree() {
        // Clear any previously materialized cells (idempotent re-render).
        NSLayoutConstraint.deactivate(quillMaterializedConstraints)
        quillMaterializedConstraints.removeAll()
        for cell in quillMaterializedCells { cell.removeFromSuperview() }
        quillMaterializedCells.removeAll()

        reloadData()
        guard !tableColumns.isEmpty else { return }

        var generated: [NSLayoutConstraint] = []
        var previous: NSView?
        let rowH = max(rowHeight, 24)
        for row in 0..<numberOfRows {
            guard let cell = view(atColumn: 0, row: row, makeIfNecessary: true) else { continue }
            addSubview(cell)
            cell.translatesAutoresizingMaskIntoConstraints = false
            generated.append(cell.leadingAnchor.constraint(equalTo: leadingAnchor))
            generated.append(cell.trailingAnchor.constraint(equalTo: trailingAnchor))
            generated.append(cell.heightAnchor.constraint(equalToConstant: rowH))
            if let previous {
                generated.append(cell.topAnchor.constraint(equalTo: previous.bottomAnchor,
                                                           constant: intercellSpacing.height))
            } else {
                generated.append(cell.topAnchor.constraint(equalTo: topAnchor))
            }
            quillMaterializedCells.append(cell)
            previous = cell
        }
        NSLayoutConstraint.activate(generated)
        quillMaterializedConstraints = generated
    }
}
