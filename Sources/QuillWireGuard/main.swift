import QuillUI

struct QuillWireGuardApp: App {
    var body: some Scene {
        WindowGroup("Quill WireGuard") {
            ContentView()
        }
        .defaultSize(width: 800, height: 600)
    }
}

#if os(Linux)
import BackendGTK4

GTK4Backend().run(QuillWireGuardApp.self)
#else
QuillWireGuardApp.main()
#endif
