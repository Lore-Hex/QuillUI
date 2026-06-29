import Foundation
import Testing

@Suite("SwiftOpenUI scene backend contracts")
struct SwiftOpenUISceneBackendTests {
    @Test("GTK scene renderer logs window lifecycle milestones behind debug flag")
    func gtkSceneRendererLogsWindowLifecycleMilestones() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4Backend.swift"),
            encoding: .utf8
        )

        #expect(source.contains("QUILLUI_GTK_DEBUG_ACTIONS"))
        #expect(source.contains("WindowGroup render start title="))
        #expect(source.contains("WindowGroup content render start title="))
        #expect(source.contains("WindowGroup present title="))
        #expect(source.contains("WindowGroup presented title="))
        #expect(source.contains("skip primitive scene without GTK renderer type="))
    }

    @Test("GTK scene renderer handles grouped and tuple scenes generically")
    func gtkSceneRendererHandlesGroupedAndTupleScenesGenerically() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4Backend.swift"),
            encoding: .utf8
        )

        #expect(source.contains("extension TupleScene: GTKWindowRenderable"))
        #expect(source.contains("TupleScene render scene0=\\(S0.self) scene1=\\(S1.self)"))
        #expect(source.contains("extension Group: GTKWindowRenderable where Content: Scene"))
        #expect(source.contains("Group<Scene> render content=\\(Content.self)"))
    }

    @Test("Commands builder supports scene-level command modifiers")
    func commandsBuilderSupportsSceneLevelCommandModifiers() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/App/Commands.swift"),
            encoding: .utf8
        )

        #expect(source.contains("case singleWindowList"))
        #expect(source.contains("public static func buildOptional<C: Commands>"))
        #expect(source.contains("public static func buildEither<C: Commands>(first component: C)"))
        #expect(source.contains("extension Group: TupleCommandsProtocol where Content: Commands"))
        #expect(source.contains("public extension Scene"))
        #expect(source.contains("func commands<C: Commands>(@CommandsBuilder _ commands: @escaping () -> C) -> Self"))
    }

    @Test("Window lifecycle observers expose native handles to compatibility shims")
    func windowLifecycleObserversExposeNativeHandles() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/App/Window.swift"),
            encoding: .utf8
        )

        #expect(source.contains("public enum SwiftOpenUIWindowLifecycleEventKind"))
        #expect(source.contains("public let nativeHandle: Int?"))
        #expect(source.contains("public enum SwiftOpenUIWindowLifecycle"))
        #expect(source.contains("public static func notifyWindowOpened"))
        #expect(source.contains("public static func notifyWindowClosed"))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
