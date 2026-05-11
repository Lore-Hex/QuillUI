import QuillSignalCore
import QuillUI

// `@MainActor` so the WindowGroup's content closure can reach
// the `@MainActor QuillSignalContentView.init()` on SwiftOpenUI.
@MainActor
struct QuillSignalApp: App {
    var body: some Scene {
        WindowGroup("Quill Signal") {
            QuillSignalContentView()
        }
        .defaultSize(width: 900, height: 700)
    }
}

#if os(Linux)
import BackendGTK4

GTK4Backend().run(QuillSignalApp.self)
#else
QuillSignalApp.main()
#endif
