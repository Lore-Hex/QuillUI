// QuillAppKitQt — NSView Qt backing (M2 slice 1, issue #231).
//
// Backs the AppKit shadow's NSView with a real QWidget (the Qt analogue of
// QuillAppKitGTK's GtkBox backing). This slice covers the view *hierarchy*
// (ensureQtWidget / addSubview / contentView / child count) plus geometry
// hooks; M2 slice 2 adds the constraint-solving layout pass that feeds
// NSLayoutConstraints into QuillAutoLayout (kiwi) and applies the solved frames
// via applyQtGeometry — which is where Qt becomes more AppKit-faithful than the
// GTK backing (absolute constraint-solved frames vs gtk_box).

import AppKit
import CQuillAppKitQt

extension NSView {
    /// Lazily-created QWidget backing this view. Backed by the lifetime-tied
    /// `quillBackendHandle` slot (NSResponder) — see the note there — so view
    /// churn (e.g. NSTableView cell reuse) can't surface a stale handle.
    public var qtWidgetHandle: UnsafeMutableRawPointer? {
        get { quillBackendHandle }
        set { quillBackendHandle = newValue }
    }

    /// Create a QWidget to back this view if one doesn't exist yet.
    @discardableResult
    public func ensureQtWidget() -> UnsafeMutableRawPointer? {
        guard QuillQt.ensureInitialized() else { return nil }
        if let existing = qtWidgetHandle { return existing }
        // Dispatch on the concrete AppKit type (NSButton → QPushButton, etc.);
        // see makeQtBackingWidget in QuillAppKit+Qt+Controls.swift.
        guard let widget = makeQtBackingWidget() else { return nil }
        qtWidgetHandle = widget
        return widget
    }

    /// addSubview (maintains the AppKit subview list) + reparent the child's
    /// QWidget under this view's QWidget.
    public func addSubviewQt(_ child: NSView) {
        addSubview(child)
        guard let parent = ensureQtWidget(),
              let childWidget = child.ensureQtWidget() else { return }
        quill_appkit_qt_view_add_subview(parent, childWidget)
    }

    /// Number of direct child QWidgets (test verification).
    public var qtChildCount: Int {
        guard let handle = qtWidgetHandle else { return 0 }
        return Int(quill_appkit_qt_view_child_count(handle))
    }

    /// Apply an absolute frame to the backing QWidget. Called by the Auto
    /// Layout pass (M2 slice 2) after QuillAutoLayout solves the constraints.
    public func applyQtGeometry(x: Int32, y: Int32, width: Int32, height: Int32) {
        guard let handle = qtWidgetHandle else { return }
        quill_appkit_qt_view_set_geometry(handle, x, y, width, height)
    }

    /// Read-back of the backing QWidget's geometry.
    public var qtGeometry: (x: Int32, y: Int32, width: Int32, height: Int32) {
        guard let handle = qtWidgetHandle else { return (0, 0, 0, 0) }
        var x: Int32 = 0, y: Int32 = 0, w: Int32 = 0, h: Int32 = 0
        quill_appkit_qt_view_geometry(handle, &x, &y, &w, &h)
        return (x, y, w, h)
    }
}

extension NSWindow {
    /// Reparent the contentView's QWidget into the window (AppKit contentView ↔
    /// the window's content). Mirrors QuillAppKitGTK.attachContentViewToGtk.
    public func attachContentViewToQt() {
        guard let handle = qtWindowHandle, let contentView else { return }
        guard let viewHandle = contentView.ensureQtWidget() else { return }
        quill_appkit_qt_window_set_content_view(handle, viewHandle)
    }

    /// Show the window with its contentView attached.
    public func showAsQtWindowWithContent() {
        showAsQtWindow()
        attachContentViewToQt()
    }
}
