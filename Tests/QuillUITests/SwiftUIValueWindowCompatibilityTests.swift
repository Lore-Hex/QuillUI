#if os(Linux)
import SwiftUI
import Testing

@Suite("SwiftUI value window compatibility")
@MainActor
struct SwiftUIValueWindowCompatibilityTests {
    private enum Destination: Equatable {
        case editor(String)
    }

    @Test("openWindow(value:) matches WindowGroup(for:) registration")
    func openWindowValueMatchesWindowGroupRegistration() {
        let group = WindowGroup(for: Destination.self) { destination in
            Text(Self.label(for: destination.wrappedValue))
        }
        var opened: [(key: String, value: Any)] = []
        let action = OpenWindowAction(
            handler: { _ in },
            valueHandler: { key, value in opened.append((key, value)) }
        )

        action(value: Destination.editor("draft"))

        #expect(group.launchesAtStartup == false)
        #expect(group.content.content == "none")
        #expect(opened.count == 1)
        #expect(opened.first?.key == group.quillValueTypeKey)
        #expect(opened.first?.value as? Destination == .editor("draft"))
        #expect(
            group.quillContent(forPresentedValue: Destination.editor("draft")).content
                == "editor:draft"
        )
    }

    @Test("value WindowGroup metadata survives window modifiers")
    func valueWindowGroupMetadataSurvivesWindowModifiers() {
        let group = WindowGroup(id: "Editor", for: Destination.self) { destination in
            Text(Self.label(for: destination.wrappedValue))
        }
        .defaultSize(width: 600, height: 800)
        .windowResizability(.contentMinSize)
        var opened: [(key: String, value: Any)] = []
        let action = OpenWindowAction(
            handler: { _ in },
            valueHandler: { key, value in opened.append((key, value)) }
        )

        action(id: "Editor", value: Destination.editor("reply"))

        #expect(group.launchesAtStartup == false)
        #expect(group.title == "Editor")
        #expect(group.defaultWindowWidth == 600)
        #expect(group.defaultWindowHeight == 800)
        #expect(opened.count == 1)
        #expect(opened.first?.key == group.quillValueTypeKey)
        #expect(opened.first?.value as? Destination == .editor("reply"))
        #expect(
            group.quillContent(forPresentedValue: Destination.editor("reply")).content
                == "editor:reply"
        )
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
#endif
