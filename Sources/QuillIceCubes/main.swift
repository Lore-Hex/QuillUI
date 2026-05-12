// Minimal Quill IceCubes app entry point.
//
// The full Ice Cubes view stack (Timeline, Env, AppAccountsManager, Theme,
// RouterPath, etc.) is a 50+ target port. This entry point uses
// QuillIceCubesCore's self-contained public-timeline shell to exercise
// Mastodon decoding, NavigationStack/List rendering, and the Linux GTK profile
// path through QuillUI. Wiring the full upstream view tree is a follow-up.

import QuillIceCubesCore
import QuillUI

struct QuillIceCubesApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill IceCubes", width: 800, height: 600) {
            QuillIceCubesContentView()
        }
    }
}

QuillApp.run(QuillIceCubesApp.self)
