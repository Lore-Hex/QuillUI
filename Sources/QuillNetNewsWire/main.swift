// Minimal Quill NetNewsWire app entry point.
//
// The full NetNewsWire view stack (NetNewsWireLogic target with 700+ files
// from the upstream Shared/iOS sources) is mid-port. Until that stabilizes
// the executable uses the small QuillNetNewsWireCore stub which links a
// subset of upstream modules (RSCore, Account, RSParser, Articles).
//
// To resume the full port, re-add `NetNewsWireLogic` to this target's
// dependencies in Package.swift, restore the deep-integration main.swift
// from git history, and finish wiring AppDefaults / UISplitViewController
// shims in QuillShims.

import SwiftUI
import QuillNetNewsWireCore

// `@MainActor` so the `WindowGroup` content closure can call the
// `@MainActor` `QuillNetNewsWireContentView.init()` without
// tripping SwiftOpenUI's nonisolated-by-default `App.body` on
// Linux.
@MainActor
struct QuillNetNewsWireApp: App {
    var body: some Scene {
        WindowGroup("Quill NetNewsWire") {
            QuillNetNewsWireContentView()
        }
        .defaultSize(width: 900, height: 600)
    }
}

#if os(Linux)
import BackendGTK4

GTK4Backend().run(QuillNetNewsWireApp.self)
#else
QuillNetNewsWireApp.main()
#endif
