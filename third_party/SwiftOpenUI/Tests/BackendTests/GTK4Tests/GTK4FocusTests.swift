import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

/// Tests for GTK4 input-state preservation across rebuilds.
///
/// The focus save/restore implementation lives in GTKViewHost (private).
/// These tests exercise it through rendered widgets and the public
/// GTKViewHost API.
final class GTK4FocusTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
    }

    // MARK: - Focusable input classification

    func testTextFieldRendersFocusableEditable() throws {
        try requireGTK()

        var text = ""
        let widget = widgetFromOpaque(gtkRenderView(
            TextField("Name", text: Binding(get: { text }, set: { text = $0 }))
        ))
        XCTAssertNotEqual(gtk_swift_widget_is_editable(widget), 0,
                          "TextField should render as a GtkEditable")
    }

    func testSecureFieldRendersFocusableEditable() throws {
        try requireGTK()

        var text = ""
        let widget = widgetFromOpaque(gtkRenderView(
            SecureField("Password", text: Binding(get: { text }, set: { text = $0 }))
        ))
        XCTAssertNotEqual(gtk_swift_widget_is_editable(widget), 0,
                          "SecureField should render as a GtkEditable")
    }

    func testSliderRendersFocusableScale() throws {
        try requireGTK()

        var value = 0.5
        let widget = widgetFromOpaque(gtkRenderView(
            Slider(value: Binding(get: { value }, set: { value = $0 }))
        ))
        XCTAssertNotEqual(gtk_swift_widget_is_scale(widget), 0,
                          "Slider should render as a GtkScale")
    }

    func testButtonIsNotFocusableInput() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") {}
        ))
        XCTAssertEqual(gtk_swift_widget_is_editable(widget), 0,
                       "Button should not be a GtkEditable")
        XCTAssertEqual(gtk_swift_widget_is_scale(widget), 0,
                       "Button should not be a GtkScale")
    }

    // MARK: - DFS ordering stability

    /// The contract that matters: two identical renders produce the same
    /// focusable-input DFS ordering. saveFocusInfo/restoreFocusInfo rely on
    /// index-based matching, so both count and order must be stable.
    func testDFSOrderIsStableAcrossIdenticalRenders() throws {
        try requireGTK()

        var text1 = ""
        var text2 = ""
        var text3 = ""
        let build = {
            widgetFromOpaque(gtkRenderView(
                VStack {
                    TextField("First", text: Binding(get: { text1 }, set: { text1 = $0 }))
                    TextField("Second", text: Binding(get: { text2 }, set: { text2 = $0 }))
                    TextField("Third", text: Binding(get: { text3 }, set: { text3 = $0 }))
                }
            ))
        }

        let types1 = collectFocusableInputTypes(in: build())
        let types2 = collectFocusableInputTypes(in: build())

        XCTAssertFalse(types1.isEmpty, "Should find at least one focusable input")
        XCTAssertEqual(types1, types2,
                       "Two identical renders must produce the same focusable-input DFS order")
    }

    func testNonEditableChildrenDoNotAddFocusableInputs() throws {
        try requireGTK()

        var text = ""

        // Render with just a TextField
        let withField = widgetFromOpaque(gtkRenderView(
            VStack {
                TextField("Input", text: Binding(get: { text }, set: { text = $0 }))
            }
        ))
        var countField = 0
        countFocusableInputs(in: withField, count: &countField)

        // Render with Text + Button + TextField
        let withExtra = widgetFromOpaque(gtkRenderView(
            VStack {
                Text("Label")
                Button("Action") {}
                TextField("Input", text: Binding(get: { text }, set: { text = $0 }))
            }
        ))
        var countExtra = 0
        countFocusableInputs(in: withExtra, count: &countExtra)

        XCTAssertEqual(countField, countExtra,
                       "Text and Button should not contribute focusable inputs")
    }

    func testSliderAddsSingleFocusableInput() throws {
        try requireGTK()

        var text = ""
        var slider = 0.5

        // TextField alone
        let fieldOnly = widgetFromOpaque(gtkRenderView(
            VStack {
                TextField("Name", text: Binding(get: { text }, set: { text = $0 }))
            }
        ))
        var countFieldOnly = 0
        countFocusableInputs(in: fieldOnly, count: &countFieldOnly)

        // TextField + Slider
        let fieldAndSlider = widgetFromOpaque(gtkRenderView(
            VStack {
                TextField("Name", text: Binding(get: { text }, set: { text = $0 }))
                Slider(value: Binding(get: { slider }, set: { slider = $0 }))
            }
        ))
        var countBoth = 0
        countFocusableInputs(in: fieldAndSlider, count: &countBoth)

        XCTAssertEqual(countBoth, countFieldOnly + 1,
                       "Adding a Slider should add exactly 1 focusable input to the DFS count")
    }

    // MARK: - TextEditor renders as GtkTextView

    func testTextEditorRendersAsTextView() throws {
        try requireGTK()

        var text = ""
        let widget = widgetFromOpaque(gtkRenderView(
            TextEditor(text: Binding(get: { text }, set: { text = $0 }))
        ))

        // TextEditor renders as GtkScrolledWindow containing a GtkTextView.
        let topTypeName = widgetTypeName(widget)
        XCTAssertEqual(topTypeName, "GtkScrolledWindow",
                       "TextEditor top-level widget should be a GtkScrolledWindow")
        let textView = findWidgetByTypeName(in: widget, typeName: "GtkTextView")
        XCTAssertNotNil(textView, "TextEditor should contain a GtkTextView")
    }

    // MARK: - Cursor position on GtkEditable

    func testEditableCursorPositionIsReadable() throws {
        try requireGTK()

        var text = "Hello"
        let widget = widgetFromOpaque(gtkRenderView(
            TextField("Field", text: Binding(get: { text }, set: { text = $0 }))
        ))
        let pos = Int(gtk_editable_get_position(OpaquePointer(widget)))
        // Without a realized window, GTK defaults cursor to 0.
        // The save/restore contract only requires the position to be
        // readable and within bounds — not a specific offset.
        XCTAssertGreaterThanOrEqual(pos, 0)
        XCTAssertLessThanOrEqual(pos, text.count)
    }

    func testEditableCursorPositionCanBeSet() throws {
        try requireGTK()

        var text = "Hello"
        let widget = widgetFromOpaque(gtkRenderView(
            TextField("Field", text: Binding(get: { text }, set: { text = $0 }))
        ))
        let editable = OpaquePointer(widget)
        gtk_editable_set_position(editable, 3)
        let pos = Int(gtk_editable_get_position(editable))
        XCTAssertEqual(pos, 3,
                       "Cursor position should round-trip through set/get")
    }

    // MARK: - suppressNextFocusRestore API

    /// Compile-time verification that suppressNextFocusRestore is public.
    /// Runtime testing of the flag requires a full GTK main loop with
    /// programmatic focus and state-triggered rebuild.
    func testSuppressNextFocusRestoreAPIIsAccessible() throws {
        try requireGTK()

        let _: (GTKViewHost) -> () -> Void = GTKViewHost.suppressNextFocusRestore
    }

    // MARK: - Identity-based rebuild focus restore

    func testTextFieldKeepsFocusAndTextWhenFocusableSiblingAppearsDuringRebuild() throws {
        try requireGTK()

        var probe = GTKFocusStructuralRebuildProbe()
        let root = widgetFromOpaque(gtkRenderView(probe))
        let window = gtk_window_new()!
        defer {
            gtk_window_destroy(windowPointer(window))
            drainMainLoop()
        }
        gtk_window_set_child(windowPointer(window), root)
        gtk_window_present(windowPointer(window))
        drainMainLoop()

        let initialFields = collectEditableWidgets(in: root)
        XCTAssertEqual(initialFields.count, 1, "Probe should start with only the composer field")
        let initialComposer = try XCTUnwrap(initialFields.first)

        guard gtk_widget_grab_focus(initialComposer) != 0 else {
            throw XCTSkip("GTK could not focus the initial TextField in this environment.")
        }
        drainMainLoop()
        guard gtk_widget_is_focus(initialComposer) != 0 else {
            throw XCTSkip("GTK focus chain is unavailable in this environment.")
        }

        gtk_editable_set_text(OpaquePointer(initialComposer), "H")
        drainMainLoop()

        let composerAfterFirstRebuild = try XCTUnwrap(
            findEditableWidget(in: root, text: "H"),
            "Composer should retain the typed text after the structural rebuild"
        )
        XCTAssertEqual(collectEditableWidgets(in: root).count, 2,
                       "Typing should insert a focusable sibling before the composer")
        XCTAssertNotEqual(gtk_widget_is_focus(composerAfterFirstRebuild), 0,
                          "Composer should regain focus by identity, not by shifted DFS index")

        gtk_editable_set_text(OpaquePointer(composerAfterFirstRebuild), "Hi")
        drainMainLoop()

        let composerAfterSecondRebuild = try XCTUnwrap(
            findEditableWidget(in: root, text: "Hi"),
            "Composer should keep accepting text after focus restoration"
        )
        XCTAssertNotEqual(gtk_widget_is_focus(composerAfterSecondRebuild), 0)
        XCTAssertEqual(probe.text, "Hi")
    }
}

private struct GTKFocusStructuralRebuildProbe: View {
    @State var text = ""
    @FocusState var composerFocused: Bool

    var body: some View {
        VStack {
            if !text.isEmpty {
                TextField("Sibling", text: .constant(""))
            }
            TextField("Composer", text: $text)
                .focused($composerFocused)
                .textFieldStyle(.plain)
                .onSubmit {}
        }
    }
}

// MARK: - Helpers

private func requireGTK(
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard gtk_is_initialized() != 0 else {
        throw XCTSkip("GTK could not initialize in this environment.", file: file, line: line)
    }
}

/// Collect GTK type names of focusable inputs in DFS order.
/// This captures both count and ordering for stability verification.
private func collectFocusableInputTypes(in widget: UnsafeMutablePointer<GtkWidget>) -> [String] {
    var result: [String] = []
    collectFocusableInputTypesWalk(in: widget, result: &result)
    return result
}

private func collectFocusableInputTypesWalk(in widget: UnsafeMutablePointer<GtkWidget>, result: inout [String]) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    if gtk_swift_widget_is_editable(widget) != 0
        || gtk_swift_widget_is_scale(widget) != 0
        || widgetTypeName(widget) == "GtkTextView" {
        result.append(widgetTypeName(widget))
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        collectFocusableInputTypesWalk(in: c, result: &result)
        child = gtk_widget_get_next_sibling(c)
    }
}

/// Count focusable inputs (GtkEditable, GtkTextView, GtkScale) via DFS walk.
private func countFocusableInputs(in widget: UnsafeMutablePointer<GtkWidget>, count: inout Int) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    if gtk_swift_widget_is_editable(widget) != 0
        || gtk_swift_widget_is_scale(widget) != 0
        || widgetTypeName(widget) == "GtkTextView" {
        count += 1
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        countFocusableInputs(in: c, count: &count)
        child = gtk_widget_get_next_sibling(c)
    }
}

private func collectEditableWidgets(in widget: UnsafeMutablePointer<GtkWidget>) -> [UnsafeMutablePointer<GtkWidget>] {
    var result: [UnsafeMutablePointer<GtkWidget>] = []
    collectEditableWidgetsWalk(in: widget, result: &result)
    return result
}

private func collectEditableWidgetsWalk(
    in widget: UnsafeMutablePointer<GtkWidget>,
    result: inout [UnsafeMutablePointer<GtkWidget>]
) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    if gtk_swift_widget_is_editable(widget) != 0 {
        result.append(widget)
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        collectEditableWidgetsWalk(in: c, result: &result)
        child = gtk_widget_get_next_sibling(c)
    }
}

private func findEditableWidget(
    in widget: UnsafeMutablePointer<GtkWidget>,
    text: String
) -> UnsafeMutablePointer<GtkWidget>? {
    collectEditableWidgets(in: widget).first { editable in
        guard let cText = gtk_editable_get_text(OpaquePointer(editable)) else { return false }
        return String(cString: cText) == text
    }
}

/// Find a widget by GTK type name via DFS walk.
private func findWidgetByTypeName(in widget: UnsafeMutablePointer<GtkWidget>, typeName: String) -> UnsafeMutablePointer<GtkWidget>? {
    guard gtk_swift_is_widget(widget) != 0 else { return nil }
    if widgetTypeName(widget) == typeName {
        return widget
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let found = findWidgetByTypeName(in: c, typeName: typeName) {
            return found
        }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}

private func widgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func drainMainLoop(limit: Int = 100) {
    for _ in 0..<limit {
        if g_main_context_iteration(nil, 0) == 0 {
            break
        }
    }
}
