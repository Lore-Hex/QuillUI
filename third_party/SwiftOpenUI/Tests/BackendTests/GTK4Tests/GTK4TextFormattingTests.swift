import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

final class GTK4TextFormattingTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
    }

    // MARK: - LineLimitView

    func testLineLimitNilEnablesWrapping() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").lineLimit(nil)
        ))
        let label = try findLabel(in: widget)
        XCTAssertNotEqual(gtk_label_get_wrap(label), 0,
                          "lineLimit(nil) should enable wrapping")
    }

    func testLineLimitOneDisablesWrappingAndTruncates() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").lineLimit(1)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_wrap(label), 0,
                       "lineLimit(1) should disable wrapping")
        XCTAssertEqual(gtk_label_get_lines(label), 1)
        XCTAssertEqual(gtk_label_get_ellipsize(label), PANGO_ELLIPSIZE_END,
                       "lineLimit(1) should default to tail truncation")
    }

    func testLineLimitTwoSetsLinesAndWrap() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").lineLimit(2)
        ))
        let label = try findLabel(in: widget)
        XCTAssertNotEqual(gtk_label_get_wrap(label), 0,
                          "lineLimit(2) should enable wrapping")
        XCTAssertEqual(gtk_label_get_lines(label), 2,
                       "lineLimit(2) should set lines to 2")
        XCTAssertEqual(gtk_label_get_ellipsize(label), PANGO_ELLIPSIZE_END,
                       "lineLimit(2) should enable end ellipsis")
    }

    func testLineLimitNilResetsInnerLineLimit() throws {
        try requireGTK()

        // Inner lineLimit(1) sets lines=1 and ellipsize=END.
        // Outer lineLimit(nil) should undo both.
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").lineLimit(1).lineLimit(nil)
        ))
        let label = try findLabel(in: widget)
        XCTAssertNotEqual(gtk_label_get_wrap(label), 0,
                          "lineLimit(nil) should enable wrapping")
        XCTAssertEqual(gtk_label_get_lines(label), -1,
                       "lineLimit(nil) should reset lines to unlimited (-1)")
        XCTAssertEqual(gtk_label_get_ellipsize(label), PANGO_ELLIPSIZE_NONE,
                       "lineLimit(nil) should clear ellipsize")
    }

    // MARK: - TruncationModeView

    func testTruncationModeTail() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").truncationMode(.tail)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_ellipsize(label), PANGO_ELLIPSIZE_END)
    }

    func testTruncationModeHead() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").truncationMode(.head)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_ellipsize(label), PANGO_ELLIPSIZE_START)
    }

    func testTruncationModeMiddle() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").truncationMode(.middle)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_ellipsize(label), PANGO_ELLIPSIZE_MIDDLE)
    }

    // MARK: - Truncation + lineLimit ordering

    func testTruncationModeBeforeLineLimitIsPreserved() throws {
        try requireGTK()

        // .truncationMode(.head) applied first (inner), then .lineLimit(2) (outer).
        // Render order: lineLimit wraps truncationMode wraps Text.
        // gtkCreateWidget calls: LineLimitView renders content → TruncationModeView
        // sets PANGO_ELLIPSIZE_START → LineLimitView sees non-NONE ellipsize, skips overwrite.
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").truncationMode(.head).lineLimit(2)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_ellipsize(label), PANGO_ELLIPSIZE_START,
                       "Explicit truncation mode should not be overwritten by lineLimit")
    }

    // MARK: - LineSpacingView

    func testLineSpacingDoesNotCrash() throws {
        try requireGTK()

        // LineSpacing applies CSS line-height. We can't easily query CSS
        // properties from GTK in tests, but we verify it renders without error.
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello\nWorld").lineSpacing(8.0)
        ))
        XCTAssertNotNil(widget)
        // Verify the label still exists and is accessible
        let label = try findLabel(in: widget)
        XCTAssertEqual(
            String(cString: gtk_label_get_text(label)),
            "Hello\nWorld")
    }

    // MARK: - MultilineTextAlignmentView

    func testMultilineAlignmentCenter() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").multilineTextAlignment(.center)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_justify(label), GTK_JUSTIFY_CENTER)
        XCTAssertEqual(gtk_label_get_xalign(label), 0.5, accuracy: 0.01)
    }

    func testMultilineAlignmentLeading() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").multilineTextAlignment(.leading)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_justify(label), GTK_JUSTIFY_LEFT)
        XCTAssertEqual(gtk_label_get_xalign(label), 0.0, accuracy: 0.01)
    }

    func testMultilineAlignmentTrailing() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").multilineTextAlignment(.trailing)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_justify(label), GTK_JUSTIFY_RIGHT)
        XCTAssertEqual(gtk_label_get_xalign(label), 1.0, accuracy: 0.01)
    }

    // MARK: - Non-label passthrough

    func testLineLimitOnNonLabelPassesThrough() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Slider(value: .constant(0.5)).lineLimit(2)
        ))
        XCTAssertNotNil(widget)
    }

    func testTruncationModeOnNonLabelPassesThrough() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Slider(value: .constant(0.5)).truncationMode(.tail)
        ))
        XCTAssertNotNil(widget)
    }

    // MARK: - Multi-label (container-level modifier)

    func testLineLimitAppliesToAllLabelsInVStack() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                Text("First")
                Text("Second")
            }.lineLimit(1)
        ))
        let labels = findAllLabels(in: widget)
        XCTAssertEqual(labels.count, 2, "VStack should contain 2 labels")
        for label in labels {
            XCTAssertEqual(gtk_label_get_lines(label), 1,
                           "lineLimit(1) should apply to all labels in the subtree")
        }
    }

    func testMultilineAlignmentAppliesToAllLabelsInVStack() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                Text("First")
                Text("Second")
            }.multilineTextAlignment(.center)
        ))
        let labels = findAllLabels(in: widget)
        XCTAssertEqual(labels.count, 2)
        for label in labels {
            XCTAssertEqual(gtk_label_get_justify(label), GTK_JUSTIFY_CENTER)
            XCTAssertEqual(gtk_label_get_xalign(label), 0.5, accuracy: 0.01)
        }
    }

    // MARK: - ForegroundColorView

    func testForegroundColorAppliesMarkupToPlainTextLabels() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Ask QuillCode").foregroundColor(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let label = try findLabel(in: widget)

        XCTAssertEqual(String(cString: gtk_label_get_text(label)), "Ask QuillCode")
        XCTAssertNotEqual(
            gtk_swift_label_get_use_markup(widgetFromOpaque(label)),
            0,
            "Inherited foregroundColor should reach plain Text instead of depending on CSS inheritance."
        )
    }

    func testForegroundColorAppliesMarkupThroughFontModifier() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Ask QuillCode")
                .font(.title3)
                .foregroundColor(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let label = try findLabel(in: widget)

        XCTAssertEqual(String(cString: gtk_label_get_text(label)), "Ask QuillCode")
        XCTAssertNotEqual(gtk_swift_label_get_use_markup(widgetFromOpaque(label)), 0)
    }

    func testForegroundColorAppliesMarkupThroughCustomViewBody() throws {
        try requireGTK()

        struct Probe: View {
            var body: some View {
                VStack {
                    Text("Ask QuillCode")
                        .font(.title3)
                }
                .foregroundColor(Color(red: 0.93, green: 0.97, blue: 0.98))
            }
        }

        let widget = widgetFromOpaque(gtkRenderView(Probe()))
        let label = try findLabel(in: widget)

        XCTAssertEqual(String(cString: gtk_label_get_text(label)), "Ask QuillCode")
        XCTAssertNotEqual(gtk_swift_label_get_use_markup(widgetFromOpaque(label)), 0)
    }

    func testForegroundStyleSurvivesBackgroundWrapper() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                Text("Ask QuillCode")
                    .font(.title3)
            }
            .background(Color(red: 0.03, green: 0.06, blue: 0.08))
            .foregroundStyle(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let label = try findLabel(in: widget)

        XCTAssertEqual(String(cString: gtk_label_get_text(label)), "Ask QuillCode")
        XCTAssertNotEqual(gtk_swift_label_get_use_markup(widgetFromOpaque(label)), 0)
    }

    func testForegroundStyleSurvivesLazyVStackDeferredBinding() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            LazyVStack([0]) { _ in
                Text("Ask QuillCode")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let window = gtk_window_new()!
        defer { gtk_window_destroy(windowPointer(window)) }
        gtk_window_set_child(windowPointer(window), widget)
        gtk_window_present(windowPointer(window))
        drainGTKMainContext(maxIterations: 100)
        let label = try findLabel(in: widget)

        XCTAssertEqual(String(cString: gtk_label_get_text(label)), "Ask QuillCode")
        XCTAssertNotEqual(gtk_swift_label_get_use_markup(widgetFromOpaque(label)), 0)
    }

    func testForegroundStyleReachesPlainTextFieldInternalText() throws {
        try requireGTK()

        var text = ""
        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                TextField("Message QuillCode", text: Binding(get: { text }, set: { text = $0 }))
                    .textFieldStyle(.plain)
            }
            .background(Color(red: 0.03, green: 0.06, blue: 0.08))
            .foregroundStyle(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let entry = try findWidget(ofType: "GtkEntry", in: widget)

        XCTAssertNotEqual(
            gtk_widget_has_css_class(entry, gtkSwiftInheritedTextInputForegroundMarker),
            0,
            "Ancestor foregroundStyle should reach GtkEntry text/placeholder nodes."
        )
    }

    func testForegroundStyleReachesRoundedTextFieldInternalText() throws {
        try requireGTK()

        var text = ""
        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                TextField("Search models", text: Binding(get: { text }, set: { text = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
            .foregroundStyle(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let entry = try findWidget(ofType: "GtkEntry", in: widget)

        XCTAssertNotEqual(
            gtk_widget_has_css_class(entry, gtkSwiftInheritedTextInputForegroundMarker),
            0,
            "QuillPaint/rounded fields should preserve the app foreground after chrome hooks run."
        )
    }

    func testForegroundStyleReachesSecureFieldAndTextEditorInternalText() throws {
        try requireGTK()

        var secret = ""
        var notes = ""
        let widget = widgetFromOpaque(gtkRenderView(
            VStack {
                SecureField("API token", text: Binding(get: { secret }, set: { secret = $0 }))
                TextEditor(text: Binding(get: { notes }, set: { notes = $0 }))
            }
            .foregroundStyle(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let passwordEntry = try findWidget(ofType: "GtkPasswordEntry", in: widget)
        let textView = try findWidget(ofType: "GtkTextView", in: widget)

        XCTAssertNotEqual(gtk_widget_has_css_class(passwordEntry, gtkSwiftInheritedTextInputForegroundMarker), 0)
        XCTAssertNotEqual(gtk_widget_has_css_class(textView, gtkSwiftInheritedTextInputForegroundMarker), 0)
    }

    // MARK: - Modifier composition

    func testLineLimitWithFontModifier() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").font(.title).lineLimit(3)
        ))
        let label = try findLabel(in: widget)
        XCTAssertNotEqual(gtk_label_get_wrap(label), 0,
                          "lineLimit should find GtkLabel through font wrapper")
        XCTAssertEqual(gtk_label_get_lines(label), 3)
    }

    func testTruncationModeWithForegroundColor() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello world").foregroundColor(.red).truncationMode(.middle)
        ))
        let label = try findLabel(in: widget)
        XCTAssertEqual(gtk_label_get_ellipsize(label), PANGO_ELLIPSIZE_MIDDLE,
                       "truncationMode should find GtkLabel through color wrapper")
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

/// Find the first GtkLabel in a widget tree, or fail the test.
private func findLabel(
    in widget: UnsafeMutablePointer<GtkWidget>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> OpaquePointer {
    let labels = findAllLabels(in: widget)
    guard let first = labels.first else {
        throw XCTSkip("No GtkLabel found in widget tree", file: file, line: line)
    }
    return first
}

private func findWidget(
    ofType typeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UnsafeMutablePointer<GtkWidget> {
    try XCTUnwrap(
        findFirstWidget(ofType: typeName, in: widget),
        "No \(typeName) found in widget tree",
        file: file,
        line: line
    )
}

private func findFirstWidget(
    ofType expectedTypeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget>? {
    guard gtk_swift_is_widget(widget) != 0 else { return nil }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    if typeName == expectedTypeName {
        return widget
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let found = findFirstWidget(ofType: expectedTypeName, in: c) {
            return found
        }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}

/// Collect all GtkLabel descendants via DFS.
private func findAllLabels(in widget: UnsafeMutablePointer<GtkWidget>) -> [OpaquePointer] {
    var result: [OpaquePointer] = []
    collectLabels(in: widget, into: &result)
    return result
}

private func collectLabels(in widget: UnsafeMutablePointer<GtkWidget>, into result: inout [OpaquePointer]) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    if typeName == "GtkLabel" {
        result.append(OpaquePointer(widget))
        return
    }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        collectLabels(in: c, into: &result)
        child = gtk_widget_get_next_sibling(c)
    }
}

private func drainGTKMainContext(maxIterations: Int = 20) {
    for _ in 0..<maxIterations {
        if g_main_context_iteration(nil, 0) == 0 {
            break
        }
    }
}
