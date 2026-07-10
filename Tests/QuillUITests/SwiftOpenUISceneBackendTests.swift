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

    @Test("MenuBarExtra is a core scene with a GTK fallback renderer")
    func menuBarExtraIsCoreSceneWithGTKFallbackRenderer() throws {
        let root = try packageRoot()
        let appSource = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/App/App.swift"),
            encoding: .utf8
        )
        let compatibilitySource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillSwiftUICompatibility/SceneCompat.swift"),
            encoding: .utf8
        )
        let gtkSource = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTK4Backend.swift"),
            encoding: .utf8
        )

        #expect(appSource.contains("public struct MenuBarExtra<Content: View, LabelContent: View>: Scene"))
        #expect(!compatibilitySource.contains("public struct MenuBarExtra"))
        #expect(gtkSource.contains("extension MenuBarExtra: GTKWindowRenderable"))
        #expect(gtkSource.contains("QUILLUI_GTK_MENU_BAR_EXTRA_FALLBACK"))
        #expect(gtkSource.contains("gtk_menu_button_new()"))
        #expect(gtkSource.contains("gtk_swift_popover_set_child(popover, scrolled)"))
        #expect(gtkSource.contains("MenuBarExtra presented handle="))
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
        #expect(source.contains("public static var appInfo: CommandGroupPlacement { .help }"))
        #expect(source.contains("before placement: CommandGroupPlacement"))
        #expect(source.contains("after placement: CommandGroupPlacement"))
    }

    @Test("Group supports view scene and command content")
    func groupSupportsViewSceneAndCommandContent() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("third_party/SwiftOpenUI/Sources/SwiftOpenUI/Views/Group.swift"),
            encoding: .utf8
        )

        #expect(source.contains("public struct Group<Content>"))
        #expect(source.contains("extension Group: View, PrimitiveView, MultiChildView, TransparentMultiChildView where Content: View"))
        #expect(source.contains("extension Group: Scene where Content: Scene"))
        #expect(source.contains("extension Group: Commands where Content: Commands"))
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

    @Test("Generated app smoke script falls back to root screenshots")
    func generatedAppSmokeScriptFallsBackToRootScreenshots() throws {
        let root = try packageRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/linux-generated-swiftui-app-smoke.sh"),
            encoding: .utf8
        )

        #expect(source.contains("xdotool search --onlyvisible --pid \"$app_pid\""))
        #expect(source.contains("xdotool search --onlyvisible --name \".*\""))
        #expect(source.contains("largest_visible_window()"))
        #expect(source.contains("xdotool getwindowgeometry --shell \"$candidate\""))
        #expect(source.contains("QUILLUI_GENERATED_APP_SMOKE_WINDOW_WIDTH"))
        #expect(source.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=\"$WINDOW_WIDTH\""))
        #expect(source.contains("QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=\"$WINDOW_HEIGHT\""))
        #expect(source.contains("xdotool windowmove \"$window_id\" 0 0"))
        #expect(source.contains("xdotool windowsize \"$window_id\" \"$WINDOW_WIDTH\" \"$WINDOW_HEIGHT\""))
        #expect(source.contains("import -window root \"$SCREENSHOT_PATH\""))
        #expect(source.contains("Generated app smoke ok: $APP_LABEL"))
        #expect(source.contains("QUILLUI_GTK_DEBUG_ACTIONS=1 enables GTK scene diagnostics"))
    }

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
