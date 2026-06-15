//===----------------------------------------------------------------------===//
//
//  TableMappers.swift
//  SignalUIRender — UITableView / UITableViewCell → GTK4 mappers
//
//  These map Signal-iOS's real UIKit table views onto GTK4 widgets so they
//  display on Linux. The table mapper DRIVES THE DATA SOURCE to materialize a
//  static snapshot of rows (no recycle pool, no display pass): it asks the
//  data source for section/row counts and for each cell, renders every cell
//  via the shared render context, and stacks them in a vertical GtkBox inside
//  a GtkScrolledWindow.
//
//  Contract (built elsewhere — imported, not redefined here):
//    public typealias GtkWidgetPtr = UnsafeMutablePointer<GtkWidget>
//    @MainActor public struct UIKitGtkRenderContext { render / applyLayerStyle / measureText }
//    @MainActor public protocol UIViewGtkMapper { handles(_:) ; make(_:_:) }
//
//  QuillUIKit facts this relies on (confirmed against the Linux shim source):
//    - UITableView.dataSource: (any UITableViewDataSource)?
//    - UITableViewDataSource methods are NON-@objc with default impls, so the
//      optional ones are called DIRECTLY (no `?.method?` syntax), e.g.
//        ds.numberOfSections(in: tv)                       // default → 1
//        ds.tableView(tv, numberOfRowsInSection: section)  // required
//        ds.tableView(tv, cellForRowAt: IndexPath)         // required
//        ds.tableView(tv, titleForHeaderInSection: section) -> String?  // default → nil
//      All are @MainActor.
//    - IndexPath(row:section:) is provided by QuillUIKit (stores [section, row]).
//    - UITableViewCell.contentView is a lazily-created UIView attached as a
//      subview on first access; textLabel/detailTextLabel are UILabel?,
//      imageView is UIImageView?; accessoryType defaults to .none.
//    - UIView.subviews: [UIView]; UILabel.text: String?.
//
//  GTK pointer conventions (proven in third_party/SwiftOpenUI GTK4 backend):
//    - gtk_scrolled_window_new()! / gtk_box_new(...)! / gtk_label_new(...)!
//      return UnsafeMutablePointer<GtkWidget> (== GtkWidgetPtr).
//    - GtkScrolledWindow setters take an OpaquePointer (GTK_SCROLLED_WINDOW
//      cast); the backend uniformly passes OpaquePointer(scrolled).
//    - GtkBox append takes boxPointer(box) from CGTKBridge.
//
//===----------------------------------------------------------------------===//

import CGTK            // gtk_*, GtkWidget*
import CGTKBridge      // boxPointer (proven pointer cast)
import QuillUIKit      // UIView, UITableView, UITableViewCell, IndexPath, UITableViewDataSource
import Foundation

// MARK: - UITableView

/// Maps a `UITableView` to a `GtkScrolledWindow` wrapping a vertical `GtkBox`
/// of rendered cells. MOST-SPECIFIC: register this BEFORE the generic UIView
/// mapper so `view is UITableView` wins over `view is UIView`.
@MainActor
public enum UITableViewGtkMapper: UIViewGtkMapper {

    public static func handles(_ view: UIView) -> Bool {
        view is UITableView
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        // A static snapshot doesn't need scrolling, and GtkScrolledWindow's
        // viewport paints the dark GTK theme background and bottom-aligns short
        // content — both fought the render. Stack the materialized rows directly
        // in a vertical GtkBox; each SECTION becomes a white rounded "card" on the
        // gray canvas, the iOS grouped-table look the constraint solver would
        // otherwise produce. (.qcard/.qcell/.qsep are defined in the global CSS.)
        let outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 18)!
        gtk_widget_set_margin_top(outer, 18)
        gtk_widget_set_margin_bottom(outer, 18)

        let tv = view as! UITableView
        // Guard the data source itself for nil; the optional protocol methods
        // have default impls on Linux, so they're called directly.
        if let ds = tv.dataSource {
            let sections = ds.numberOfSections(in: tv)
            for section in 0..<max(0, sections) {
                let rows = ds.tableView(tv, numberOfRowsInSection: section)
                guard rows > 0 else { continue }

                // Section header: the controller's delegate vends it via
                // viewForHeaderInSection. We render the ones supplied as a
                // customHeaderView UILabel (grouped-table caps header), placed
                // above the card like iOS.
                if let delegate = tv.delegate as? UITableViewDelegate,
                   let header = delegate.tableView(tv, viewForHeaderInSection: section),
                   header is UILabel,
                   let headerWidget = ctx.render(header) {
                    gtk_widget_set_halign(headerWidget, GTK_ALIGN_START)
                    gtk_widget_set_margin_start(headerWidget, 32)
                    gtk_widget_set_margin_top(headerWidget, 6)
                    gtk_widget_set_margin_bottom(headerWidget, 2)
                    gtk_box_append(boxPointer(outer), headerWidget)
                }

                let card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                "qcard".withCString { gtk_widget_add_css_class(card, $0) }
                gtk_widget_set_margin_start(card, 16)
                gtk_widget_set_margin_end(card, 16)
                gtk_widget_set_halign(card, GTK_ALIGN_FILL)

                for row in 0..<rows {
                    let indexPath = IndexPath(row: row, section: section)
                    let cell = ds.tableView(tv, cellForRowAt: indexPath)
                    guard let cellWidget = ctx.render(cell) else { continue }
                    "qcell".withCString { gtk_widget_add_css_class(cellWidget, $0) }
                    gtk_widget_set_hexpand(cellWidget, 1)
                    gtk_widget_set_halign(cellWidget, GTK_ALIGN_FILL)
                    // Each row keeps its natural height (no vertical stretch) so a
                    // single-row card doesn't balloon to absorb slack.
                    gtk_widget_set_valign(cellWidget, GTK_ALIGN_START)
                    gtk_box_append(boxPointer(card), cellWidget)

                    // Hairline separator between rows (inset from the leading edge,
                    // like iOS), but not after the last row.
                    if row < rows - 1 {
                        let sep = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
                        "qsep".withCString { gtk_widget_add_css_class(sep, $0) }
                        gtk_widget_set_size_request(sep, -1, 1)
                        gtk_widget_set_margin_start(sep, 16)
                        gtk_box_append(boxPointer(card), sep)
                    }
                }

                gtk_box_append(boxPointer(outer), card)
            }
        }

        ctx.applyLayerStyle(outer, view)
        return outer
    }
}

// MARK: - UITableViewCell

/// Maps a `UITableViewCell` to the GTK widget for its `contentView` (which
/// holds the cell's real subviews). When the cell uses the built-in
/// textLabel/detailTextLabel/imageView (UITableViewCellStyle) and the
/// contentView is empty, builds a horizontal box: imageView (if any) + a
/// vertical box of textLabel/detailTextLabel. A trailing "›" label stands in
/// for any non-`.none` accessoryType.
@MainActor
public enum UITableViewCellGtkMapper: UIViewGtkMapper {

    public static func handles(_ view: UIView) -> Bool {
        view is UITableViewCell
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        let cell = view as! UITableViewCell

        // The contentView holds the cell's real subviews — render THAT.
        let contentView = cell.contentView
        let body: GtkWidgetPtr

        if contentView.subviews.isEmpty {
            // Built-in style fallback: reconstruct from the standard cell
            // labels/imageView when the contentView wasn't populated directly.
            body = makeBuiltInStyleBody(cell, ctx)
        } else {
            body = ctx.render(contentView) ?? gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        }

        // Accessory (disclosure chevron etc.) → trailing "›" label. When there
        // is one, wrap the body in a horizontal box so the chevron sits at the
        // trailing edge; otherwise return the body directly.
        let result: GtkWidgetPtr
        if cell.accessoryType != .none {
            let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
            gtk_widget_set_hexpand(body, 1)
            gtk_widget_set_halign(body, GTK_ALIGN_FILL)
            gtk_box_append(boxPointer(row), body)

            let chevron = gtk_label_new("›")!
            gtk_widget_set_halign(chevron, GTK_ALIGN_END)
            gtk_box_append(boxPointer(row), chevron)
            result = row
        } else {
            result = body
        }

        // NB: we deliberately do NOT apply the cell's own backgroundColor here.
        // On the no-DB Linux render path the cell resolves a dark fill that would
        // paint over the white `.qcard` section background. The grouped card
        // provides the row background; the cell only contributes its content.
        return result
    }

    /// Build the UITableViewCellStyle body from the standard cell elements:
    /// `[ imageView | [ textLabel / detailTextLabel ] ]`.
    private static func makeBuiltInStyleBody(
        _ cell: UITableViewCell,
        _ ctx: UIKitGtkRenderContext
    ) -> GtkWidgetPtr {
        let hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)!

        if let imageView = cell.imageView, let imageWidget = ctx.render(imageView) {
            gtk_box_append(boxPointer(hbox), imageWidget)
        }

        let labelStack = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        if let textLabel = cell.textLabel, let titleWidget = ctx.render(textLabel) {
            gtk_box_append(boxPointer(labelStack), titleWidget)
        }
        if let detailLabel = cell.detailTextLabel, let detailWidget = ctx.render(detailLabel) {
            gtk_box_append(boxPointer(labelStack), detailWidget)
        }
        gtk_widget_set_hexpand(labelStack, 1)
        gtk_widget_set_halign(labelStack, GTK_ALIGN_FILL)
        gtk_box_append(boxPointer(hbox), labelStack)

        return hbox
    }
}
