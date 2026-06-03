import XCTest
@testable import SwiftOpenUI

final class TextRichTextTests: XCTestCase {
    func testPlainTextIsOneUncoloredRun() {
        let t = Text("hello")
        XCTAssertEqual(t.content, "hello")
        XCTAssertEqual(t.runs.count, 1)
        XCTAssertNil(t.runs[0].color)
        XCTAssertFalse(t.hasStyledRuns) // plain text stays on the fast path
    }

    func testForegroundColorReturnsTextAndColorsRuns() {
        let t = Text("@alex").foregroundColor(.red)
        XCTAssertEqual(t.content, "@alex")
        XCTAssertEqual(t.runs.count, 1)
        XCTAssertEqual(t.runs[0].color, .red)
        XCTAssertTrue(t.hasStyledRuns)
    }

    func testConcatenationBuildsMultipleRuns() {
        let t = Text("hi ")
            + Text("@alex").foregroundColor(.red)
            + Text(" and ")
            + Text("#swift").foregroundColor(.red)
        XCTAssertEqual(t.content, "hi @alex and #swift")
        XCTAssertEqual(t.runs.count, 4)
        XCTAssertNil(t.runs[0].color)
        XCTAssertEqual(t.runs[1].color, .red)
        XCTAssertNil(t.runs[2].color)
        XCTAssertEqual(t.runs[3].color, .red)
        XCTAssertTrue(t.hasStyledRuns)
    }
}
