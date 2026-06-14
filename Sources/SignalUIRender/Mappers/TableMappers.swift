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

// CGTKBridge ships `boxPointer` but not a `scrolledWindowPointer`. The GTK
// scrolled-window setters are bound to take an OpaquePointer (the C
// GTK_SCROLLED_WINDOW() cast), which is exactly what the GTK4 backend passes
// everywhere (`OpaquePointer(scrolled)`). Provide the named helper the table
// mapper reads against, mirroring that proven form so the call sites stay
// legible without depending on a symbol CGTKBridge doesn't export.
@inlinable
func scrolledWindowPointer(_ ptr: GtkWidgetPtr) -> OpaquePointer {
    OpaquePointer(ptr)
}

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
        let sw = gtk_scrolled_window_new()!
        gtk_scrolled_window_set_policy(
            scrolledWindowPointer(sw),
            GTK_POLICY_AUTOMATIC,
            GTK_POLICY_AUTOMATIC
        )

        // Vertical stack of materialized rows (and optional section headers).
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!

        let tv = view as! UITableView
        // Guard the data source itself for nil; the optional protocol methods
        // have default impls on Linux, so they're called directly.
        if let ds = tv.dataSource {
            let sections = ds.numberOfSections(in: tv)
            for section in 0..<max(0, sections) {
                // Optional section header → a GtkLabel (only when present).
                if let title = ds.tableView(tv, titleForHeaderInSection: section),
                   !title.isEmpty {
                    let header = gtk_label_new(title)!
                    // Left-align the header, like a grouped-table section title.
                    gtk_widget_set_halign(header, GTK_ALIGN_START)
                    gtk_box_append(boxPointer(box), header)
                }

                let rows = ds.tableView(tv, numberOfRowsInSection: section)
                for row in 0..<max(0, rows) {
                    let indexPath = IndexPath(row: row, section: section)
                    let cell = ds.tableView(tv, cellForRowAt: indexPath)
                    if let cellWidget = ctx.render(cell) {
                        gtk_box_append(boxPointer(box), cellWidget)
                    }
                }
            }
        }

        gtk_scrolled_window_set_child(scrolledWindowPointer(sw), box)

        ctx.applyLayerStyle(sw, view)
        return sw
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

        ctx.applyLayerStyle(result, view)
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
