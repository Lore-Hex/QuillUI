// QuillAppKitQt — NSControl family Qt backing (M3 slice 1, issue #231).
//
// Controls are NSViews, so they compose with the NSView hierarchy + Auto Layout
// pass (QPushButton/QLabel derive QWidget). `makeQtBackingWidget` dispatches on
// the concrete AppKit type so ensureQtWidget creates the right Qt widget; the
// per-control extensions keep the Qt widget's text in sync and read it back.

import AppKit
import CQuillAppKitQt

extension NSView {
    /// Creates the Qt widget that backs this view, dispatching on the concrete
    /// AppKit type. Plain NSViews get a bare QWidget container.
    func makeQtBackingWidget() -> UnsafeMutableRawPointer? {
        if let button = self as? NSButton {
            return button.title.withCString { quill_appkit_qt_button_new($0) }
        }
        if let field = self as? NSTextField {
            // Label-style (the common case, e.g. KeyValueRow). Editable fields
            // (QLineEdit) come in a later slice.
            return field.stringValue.withCString { quill_appkit_qt_label_new($0) }
        }
        return quill_appkit_qt_view_new()
    }
}

extension NSButton {
    /// Push the current `title` into the backing QPushButton (after a change).
    public func syncQtTitle() {
        guard let handle = qtWidgetHandle else { return }
        title.withCString { quill_appkit_qt_button_set_title(handle, $0) }
    }

    /// The backing QPushButton's text — proves the C side holds it.
    public var qtButtonTitle: String? {
        guard let handle = qtWidgetHandle else { return nil }
        guard let cstr = quill_appkit_qt_button_title(handle) else { return nil }
        return String(cString: cstr)
    }
}

extension NSTextField {
    /// Push the current `stringValue` into the backing QLabel (after a change).
    public func syncQtText() {
        guard let handle = qtWidgetHandle else { return }
        stringValue.withCString { quill_appkit_qt_label_set_text(handle, $0) }
    }

    /// The backing QLabel's text.
    public var qtLabelText: String? {
        guard let handle = qtWidgetHandle else { return nil }
        guard let cstr = quill_appkit_qt_label_text(handle) else { return nil }
        return String(cString: cstr)
    }
}
