// Minimal Quill IceCubes app entry point.
//
// The full Ice Cubes view stack (Timeline, Env, AppAccountsManager, Theme,
// RouterPath, etc.) is a 50+ target port. For now this entry point uses the
// QuillIceCubesCore stub that exercises Models + NetworkClient — proving the
// federation client + API surface works on QuillUI. Wiring the full upstream
// view tree is a follow-up.

import SwiftUI
import QuillIceCubesCore

struct QuillIceCubesApp: App {
    var body: some Scene {
        WindowGroup("Quill IceCubes") {
            QuillIceCubesContentView()
        }
        .defaultSize(width: 800, height: 600)
    }
}

#if os(Linux)
import BackendGTK4

GTK4Backend().run(QuillIceCubesApp.self)
#else
QuillIceCubesApp.main()
#endif
