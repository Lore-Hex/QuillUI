import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

final class GTK4ProgressViewTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
    }

    func testDeterminateProgressViewSetsFraction() throws {
        try requireGTK()

        let progress = try progressBar(from: ProgressView(value: 0.5, total: 2.0))

        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(progress)), 0.25, accuracy: 0.001)
        XCTAssertEqual(gtk_widget_has_css_class(progress, gtkSwiftIndeterminateProgressMarker), 0)
    }

    func testDeterminateProgressViewClampsFraction() throws {
        try requireGTK()

        let high = try progressBar(from: ProgressView(value: 3.0, total: 2.0))
        let low = try progressBar(from: ProgressView(value: -1.0, total: 2.0))

        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(high)), 1.0, accuracy: 0.001)
        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(low)), 0.0, accuracy: 0.001)
    }

    func testDeterminateProgressViewHandlesInvalidTotals() throws {
        try requireGTK()

        let zero = try progressBar(from: ProgressView(value: 1.0, total: 0.0))
        let infinite = try progressBar(from: ProgressView(value: 1.0, total: .infinity))
        let nan = try progressBar(from: ProgressView(value: 1.0, total: .nan))

        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(zero)), 0.0, accuracy: 0.001)
        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(infinite)), 0.0, accuracy: 0.001)
        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(nan)), 0.0, accuracy: 0.001)
    }

    func testIndeterminateProgressViewUsesPulsingBar() throws {
        try requireGTK()

        let progress = try progressBar(from: ProgressView())

        XCTAssertNotEqual(gtk_widget_has_css_class(progress, gtkSwiftIndeterminateProgressMarker), 0)
        XCTAssertGreaterThan(gtk_progress_bar_get_pulse_step(OpaquePointer(progress)), 0)
        XCTAssertEqual(gtk_widget_get_hexpand(progress), 1)
    }
}

private func progressBar(
    from view: some View,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UnsafeMutablePointer<GtkWidget> {
    try findWidget(ofType: "GtkProgressBar", in: widgetFromOpaque(gtkRenderView(view)), file: file, line: line)
}

private func requireGTK(
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard gtk_is_initialized() != 0 else {
        throw XCTSkip("GTK could not initialize in this environment.", file: file, line: line)
    }
}

private func findWidget(
    ofType expectedTypeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UnsafeMutablePointer<GtkWidget> {
    if gtkTestWidgetTypeName(widget) == expectedTypeName {
        return widget
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = try? findWidget(ofType: expectedTypeName, in: current, file: file, line: line) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    XCTFail("Expected widget tree to contain \(expectedTypeName).", file: file, line: line)
    throw XCTSkip()
}
