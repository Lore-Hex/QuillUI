import Testing

#if os(Linux)
@testable import BackendGTK4
import CGTK
import CGTKBridge
import SwiftUI

@Suite("GTK text binding rebuilds", .serialized)
@MainActor
struct GTKTextBindingRebuildTests {
    @Test("separate inputs keep independent pending writes")
    func separateInputsKeepIndependentPendingWrites() throws {
        guard gtkTestDisplayIsAvailable() else { return }
        defer { gtkFlushPendingTextBindingUpdate() }

        var first = ""
        var second = ""
        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                TextField("First", text: Binding(get: { first }, set: { first = $0 }))
                TextField("Second", text: Binding(get: { second }, set: { second = $0 }))
            }
        ))
        let fields = editableWidgets(in: widget).filter {
            widgetTypeName($0) == "GtkEntry"
        }
        #expect(fields.count == 2)
        guard fields.count == 2 else { return }

        // Matching prefixes must not make edits from two controls look like
        // successive values from one control.
        gtk_editable_set_text(OpaquePointer(fields[0]), "quill")
        gtk_editable_set_text(OpaquePointer(fields[1]), "quillui")
        gtkFlushPendingTextBindingUpdate()

        #expect(first == "quill")
        #expect(second == "quillui")
    }

    @Test("owning host commits pending text before a full editor remount")
    func owningHostCommitsPendingTextBeforeFullRemount() throws {
        guard gtkTestDisplayIsAvailable() else { return }
        defer { gtkFlushPendingTextBindingUpdate() }

        var text = ""
        let binding = Binding(get: { text }, set: { text = $0 })
        let host = GTKViewHost(buildBody: {
            gtkRenderView(TextEditor(text: binding))
        })

        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(host)
        let initial = host.buildBodyWithTracking()
        GTKViewHost.setCurrentRebuilding(previousHost)
        gtk_box_append(boxPointer(host.container), widgetFromOpaque(initial))

        var expected = ""
        for character in "quilluiinputprobe" {
            expected.append(character)
            let oldEditor = try #require(textView(in: host.container))
            let oldBuffer = gtk_text_view_get_buffer(
                UnsafeMutableRawPointer(oldEditor).assumingMemoryBound(to: GtkTextView.self)
            )!
            gtk_text_buffer_set_text(oldBuffer, expected, -1)
            g_object_ref(gpointer(oldEditor))
            defer { g_object_unref(gpointer(oldEditor)) }

            #expect(text != expected)
            host.rebuild()

            #expect(text == expected)
            let rebuiltEditor = try #require(textView(in: host.container))
            #expect(UnsafeRawPointer(rebuiltEditor) != UnsafeRawPointer(oldEditor))
            #expect(textViewString(rebuiltEditor) == expected)
        }
    }
}

@MainActor
private func editableWidgets(
    in widget: UnsafeMutablePointer<GtkWidget>
) -> [UnsafeMutablePointer<GtkWidget>] {
    var result: [UnsafeMutablePointer<GtkWidget>] = []
    if gtk_swift_widget_is_editable(widget) != 0 {
        result.append(widget)
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        result.append(contentsOf: editableWidgets(in: current))
        child = gtk_widget_get_next_sibling(current)
    }
    return result
}

@MainActor
private func textView(
    in widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget>? {
    if widgetTypeName(widget) == "GtkTextView" {
        return widget
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = textView(in: current) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return nil
}

@MainActor
private func widgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

@MainActor
private func textViewString(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    let textView = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkTextView.self)
    let buffer = gtk_text_view_get_buffer(textView)!
    var start = GtkTextIter()
    var end = GtkTextIter()
    gtk_text_buffer_get_bounds(buffer, &start, &end)
    let cString = gtk_text_buffer_get_text(buffer, &start, &end, 0)!
    defer { g_free(gpointer(mutating: cString)) }
    return String(cString: cString)
}
#endif
