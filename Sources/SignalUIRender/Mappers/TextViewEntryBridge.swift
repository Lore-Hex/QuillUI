// TextViewEntryBridge.swift
// =========================
// CGtk4-only bridge for editable UITextView rendering. Keeping this in a file
// that does not import SwiftOpenUI's CGTK module avoids duplicate GLib symbol
// overloads while still sharing the filtered helpers in Sources/CGtk4/shim.h.

import CGtk4
import Foundation
import UIKit

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
        _ = textView.quillReplaceCharacters(
            in: NSRange(location: 0, length: currentText.utf16.count),
            with: nextText
        )
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
