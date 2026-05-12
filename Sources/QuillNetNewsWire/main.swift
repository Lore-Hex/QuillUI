// Minimal Quill NetNewsWire app entry point.
//
// The full NetNewsWire view stack (NetNewsWireLogic target with 700+ files
// from the upstream Shared/iOS sources) is mid-port. Until that stabilizes,
// the executable uses QuillNetNewsWireCore's self-contained RSS reader
// (URLSession + XMLParser) so the split-view app shell stays buildable,
// renderable, and profile-covered on macOS and Linux.
//
// To resume the full port, re-add `NetNewsWireLogic` to this target's
// dependencies in Package.swift, restore the deep-integration main.swift
// from git history, and finish wiring AppDefaults / UISplitViewController
// shims in QuillShims.

import QuillNetNewsWireCore
import QuillUI

struct QuillNetNewsWireApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill NetNewsWire", width: 900, height: 600) {
            QuillNetNewsWireContentView()
        }
    }
}

QuillApp.run(QuillNetNewsWireApp.self)
