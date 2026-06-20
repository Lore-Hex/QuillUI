//===----------------------------------------------------------------------===//
//
//  CollectionMappers.swift
//  SignalUIRender -- UICollectionView / UICollectionViewCell -> GTK4 mappers
//
//  Like the UITableView mapper, this is a static snapshot renderer: it asks
//  QuillUIKit to reload/materialize the collection's current data source and
//  then maps the realized cells into a GTK scrolled vertical stack. It is not a
//  recycler or virtualized list yet, but it turns collection-backed UIKit
//  screens from "invisible" into rendered content.
//
//===----------------------------------------------------------------------===//

import CGTK
import CGTKBridge
import Foundation
import QuillUIKit

@MainActor
public enum UICollectionViewGtkMapper: UIViewGtkMapper {
    public static func handles(_ view: UIView) -> Bool {
        view is UICollectionView
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        let collectionView = view as! UICollectionView
        collectionView.reloadData()

        let scrolled = gtk_scrolled_window_new()!
        let stack = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(stack, 1)
        gtk_widget_set_halign(stack, GTK_ALIGN_FILL)

        if let backgroundView = collectionView.backgroundView,
           let backgroundWidget = ctx.render(backgroundView) {
            gtk_widget_set_hexpand(backgroundWidget, 1)
            gtk_widget_set_halign(backgroundWidget, GTK_ALIGN_FILL)
            gtk_box_append(boxPointer(stack), backgroundWidget)
        }

        for cell in collectionView.visibleCells {
            guard let cellWidget = ctx.render(cell) else { continue }
            gtk_widget_set_hexpand(cellWidget, 1)
            gtk_widget_set_halign(cellWidget, GTK_ALIGN_FILL)
            gtk_widget_set_valign(cellWidget, GTK_ALIGN_START)

            let frame = cell.frame
            if frame.width > 0 || frame.height > 0 {
                gtk_widget_set_size_request(
                    cellWidget,
                    frame.width > 0 ? gint(frame.width) : -1,
                    frame.height > 0 ? gint(frame.height) : -1
                )
            }
            gtk_box_append(boxPointer(stack), cellWidget)
        }

        gtk_scrolled_window_set_child(OpaquePointer(scrolled), stack)
        ctx.applyLayerStyle(scrolled, view)
        return scrolled
    }
}

@MainActor
public enum UICollectionViewCellGtkMapper: UIViewGtkMapper {
    public static func handles(_ view: UIView) -> Bool {
        view is UICollectionViewCell
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        let cell = view as! UICollectionViewCell
        let body = ctx.render(cell.contentView) ?? gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(body, 1)
        gtk_widget_set_halign(body, GTK_ALIGN_FILL)
        ctx.applyLayerStyle(body, cell)
        return body
    }
}
