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

    func testStyledRunsCarryPerRunColorAndJoinedContent() {
        let t = Text(styledRuns: [
            Text.Run(text: "hi "),
            Text.Run(text: "@alex", color: .red),
            Text.Run(text: " and "),
            Text.Run(text: "#swift", color: .red),
        ])
        XCTAssertEqual(t.content, "hi @alex and #swift")
        XCTAssertEqual(t.runs.count, 4)
        XCTAssertNil(t.runs[0].color)
        XCTAssertEqual(t.runs[1].color, .red)
        XCTAssertNil(t.runs[2].color)
        XCTAssertEqual(t.runs[3].color, .red)
        XCTAssertTrue(t.hasStyledRuns)
    }

    func testSingleUncoloredRunStaysOnFastPath() {
        let t = Text(styledRuns: [Text.Run(text: "plain")])
        XCTAssertFalse(t.hasStyledRuns)
        XCTAssertEqual(t.content, "plain")
    }
}
