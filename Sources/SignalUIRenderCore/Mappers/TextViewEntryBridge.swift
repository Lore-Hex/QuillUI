// TextViewEntryBridge.swift
// =========================
// CGtk4-only bridge for editable UITextView rendering. Keeping this in a file
// that does not import SwiftOpenUI's CGTK module avoids duplicate GLib symbol
// overloads while still sharing the filtered helpers in Sources/CGtk4/shim.h.

import CGtk4
import Foundation
import QuillUIKit
import UIKit

@MainActor
private var textViewGTKEntryApplyingWidgets: Set<UInt> = []

@MainActor
func quillSignalTextViewEntryIsApplyingText(_ widget: UnsafeMutableRawPointer) -> Bool {
    textViewGTKEntryApplyingWidgets.contains(UInt(bitPattern: widget))
}

@MainActor
private final class UITextViewGTKEntryContext {
    weak var textView: UITextView?

    init(textView: UITextView) {
        self.textView = textView
    }

    func applyChangedText(_ nextText: String) {
        guard let textView else { return }
        if !textView.isFirstResponder, !textView.becomeFirstResponder() {
            return
        }
        let currentText = textView.text ?? ""
        guard currentText != nextText else { return }
        QuillUIKitMutationNotifications.withoutNotifications {
            _ = textView.quillReplaceCharacters(
                in: NSRange(location: 0, length: currentText.utf16.count),
                with: nextText
            )
        }
    }

    func activateReturnKey() {
        guard let textView else { return }
        if !textView.isFirstResponder, !textView.becomeFirstResponder() {
            return
        }
        textView.insertText("\n")
    }

    func syncFocus(from widget: UnsafeMutableRawPointer) {
        if gtk_widget_has_focus(widget.assumingMemoryBound(to: GtkWidget.self)) != 0 {
            _ = textView?.becomeFirstResponder()
        } else {
            _ = textView?.resignFirstResponder()
        }
    }
}

private let textViewGTKEntryChangedTrampoline: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = {
    editable,
    userData in
    guard let editable, let userData else { return }
    let context = Unmanaged<UITextViewGTKEntryContext>.fromOpaque(userData).takeUnretainedValue()
    guard let cString = quill_editable_get_text(UnsafeMutableRawPointer(editable)) else { return }
    let nextText = String(cString: cString)
    MainActor.assumeIsolated {
        context.applyChangedText(nextText)
    }
}

private let textViewGTKEntryActivateTrampoline: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = {
    _,
    userData in
    guard let userData else { return }
    let context = Unmanaged<UITextViewGTKEntryContext>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        context.activateReturnKey()
    }
}

private let textViewGTKEntryFocusTrampoline: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = {
    editable,
    _,
    userData in
    guard let editable, let userData else { return }
    let context = Unmanaged<UITextViewGTKEntryContext>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        context.syncFocus(from: editable)
    }
}

private let releaseTextViewGTKEntryContext: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = {
    userData,
    _ in
    guard let userData else { return }
    Unmanaged<UITextViewGTKEntryContext>.fromOpaque(userData).release()
}

@MainActor
func quillSignalTextViewEntryGetText(_ widget: UnsafeMutableRawPointer) -> String {
    guard let cString = quill_editable_get_text(widget) else { return "" }
    return String(cString: cString)
}

@MainActor
func quillSignalTextViewEntrySetText(_ widget: UnsafeMutableRawPointer, _ text: String) {
    let key = UInt(bitPattern: widget)
    textViewGTKEntryApplyingWidgets.insert(key)
    defer { textViewGTKEntryApplyingWidgets.remove(key) }
    text.withCString { quill_editable_set_text(widget, $0) }
}

@MainActor
func quillSignalTextViewEntrySetPlaceholder(_ widget: UnsafeMutableRawPointer, _ placeholder: String) {
    placeholder.withCString { quill_entry_set_placeholder_text(widget, $0) }
}

@MainActor
func quillSignalConnectTextViewEntrySignals(_ widget: UnsafeMutableRawPointer, textView: UITextView) {
    let changedContext = Unmanaged.passRetained(UITextViewGTKEntryContext(textView: textView)).toOpaque()
    quillSignalConnectTextViewEntrySignal(
        widget,
        signal: "changed",
        callback: unsafeBitCast(textViewGTKEntryChangedTrampoline, to: GCallback.self),
        context: changedContext
    )

    let activateContext = Unmanaged.passRetained(UITextViewGTKEntryContext(textView: textView)).toOpaque()
    quillSignalConnectTextViewEntrySignal(
        widget,
        signal: "activate",
        callback: unsafeBitCast(textViewGTKEntryActivateTrampoline, to: GCallback.self),
        context: activateContext
    )

    let focusContext = Unmanaged.passRetained(UITextViewGTKEntryContext(textView: textView)).toOpaque()
    quillSignalConnectTextViewEntrySignal(
        widget,
        signal: "notify::has-focus",
        callback: unsafeBitCast(textViewGTKEntryFocusTrampoline, to: GCallback.self),
        context: focusContext
    )
}

/// Test/demo hook: recursively find the first GTK editable in a rendered UIKit
/// tree and set its text through the same GtkEditable bridge used by real user
/// typing. `gtk_editable_set_text` emits `changed`, so UITextView delegates and
/// `quillReplaceCharacters` still run.
@MainActor
public func quillSignalRenderSetFirstTextEntry(in widget: UnsafeMutableRawPointer, text: String) -> Bool {
    if quill_widget_is_editable(widget) != 0 {
        quillSignalTextViewEntrySetText(widget, text)
        return true
    }

    let gtkWidget = widget.assumingMemoryBound(to: GtkWidget.self)
    var child = gtk_widget_get_first_child(gtkWidget)
    while let current = child {
        if quillSignalRenderSetFirstTextEntry(in: UnsafeMutableRawPointer(current), text: text) {
            return true
        }
        child = gtk_widget_get_next_sibling(current)
    }

    return false
}

@MainActor
public func quillSignalRenderClickButton(in widget: UnsafeMutableRawPointer, cssClass: String) -> Bool {
    if quill_widget_is_button(widget) != 0,
       cssClass.withCString({ quill_widget_has_css_class(widget, $0) }) != 0 {
        quill_signal_emit_clicked(widget)
        return true
    }

    let gtkWidget = widget.assumingMemoryBound(to: GtkWidget.self)
    var child = gtk_widget_get_first_child(gtkWidget)
    while let current = child {
        if quillSignalRenderClickButton(in: UnsafeMutableRawPointer(current), cssClass: cssClass) {
            return true
        }
        child = gtk_widget_get_next_sibling(current)
    }

    return false
}

private func quillSignalConnectTextViewEntrySignal(
    _ widget: UnsafeMutableRawPointer,
    signal: String,
    callback: GCallback,
    context: UnsafeMutableRawPointer
) {
    let destroyNotify = unsafeBitCast(releaseTextViewGTKEntryContext, to: GClosureNotify.self)
    signal.withCString { signalName in
        let _: gulong = quill_signal_connect_data(
            widget,
            signalName,
            callback,
            context,
            destroyNotify
        )
    }
}
