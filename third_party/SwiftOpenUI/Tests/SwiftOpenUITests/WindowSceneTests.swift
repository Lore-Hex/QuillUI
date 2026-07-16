import XCTest
@testable import SwiftOpenUI

final class WindowSceneTests: XCTestCase {
    private enum Destination: Equatable {
        case editor(String)
    }

    func testOpenWindowActionRoutesTypedValuesByWindowGroupKey() {
        var opened: [(key: String, value: Any)] = []
        let action = OpenWindowAction(
            handler: { _ in XCTFail("id handler should not receive value opens") },
            valueHandler: { key, value in opened.append((key, value)) }
        )

        action(value: Destination.editor("draft"))

        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.key, quillOpenWindowValueTypeKey(for: Destination.self))
        XCTAssertEqual(opened.first?.value as? Destination, .editor("draft"))
    }

    func testOpenWindowActionRoutesIDScopedTypedValuesByWindowGroupKey() {
        var opened: [(key: String, value: Any)] = []
        let action = OpenWindowAction(
            handler: { _ in XCTFail("id handler should not receive value opens") },
            valueHandler: { key, value in opened.append((key, value)) }
        )

        action(id: "Editor", value: Destination.editor("reply"))

        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(
            opened.first?.key,
            quillOpenWindowValueTypeKey(id: "Editor", for: Destination.self)
        )
        XCTAssertEqual(opened.first?.value as? Destination, .editor("reply"))
    }

    func testValueWindowGroupStoresDeferredContentFactory() {
        let group = WindowGroup(for: Destination.self) { destination in
            Text(Self.label(for: destination.wrappedValue))
        }

        XCTAssertFalse(group.launchesAtStartup)
        XCTAssertEqual(group.title, "Destination")
        XCTAssertEqual(group.content.content, "none")
        XCTAssertEqual(group.quillValueTypeKey, quillOpenWindowValueTypeKey(for: Destination.self))

        let openedContent = group.quillContent(forPresentedValue: Destination.editor("draft"))
        XCTAssertEqual(openedContent.content, "editor:draft")
    }

    func testValueWindowGroupMetadataSurvivesSizingModifiers() {
        let group = WindowGroup(id: "Editor", for: Destination.self) { destination in
            Text(Self.label(for: destination.wrappedValue))
        }
        .defaultSize(width: 600, height: 800)
        .windowResizability(.contentMinSize)

        XCTAssertFalse(group.launchesAtStartup)
        XCTAssertEqual(group.title, "Editor")
        XCTAssertEqual(
            group.quillValueTypeKey,
            quillOpenWindowValueTypeKey(id: "Editor", for: Destination.self)
        )
        XCTAssertEqual(group.defaultWindowWidth, 600)
        XCTAssertEqual(group.defaultWindowHeight, 800)
        XCTAssertEqual(group.windowResizability, .contentMinSize)

        let openedContent = group.quillContent(forPresentedValue: Destination.editor("reply"))
        XCTAssertEqual(openedContent.content, "editor:reply")
    }

    private static func label(for destination: Destination?) -> String {
        switch destination {
        case .editor(let text):
            return "editor:\(text)"
        case .none:
            return "none"
        }
    }
}
