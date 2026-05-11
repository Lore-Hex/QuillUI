import QuillIINACore
import QuillUI

@MainActor
struct QuillIINAApp: App {
    var body: some Scene {
        WindowGroup("Quill IINA") {
            QuillIINAContentView()
        }
        .defaultSize(width: 960, height: 600)
    }
}

#if os(Linux)
import BackendGTK4

GTK4Backend().run(QuillIINAApp.self)
#else
QuillIINAApp.main()
#endif
