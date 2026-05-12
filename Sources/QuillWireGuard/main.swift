import QuillUI

struct QuillWireGuardApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill WireGuard", width: 800, height: 600) {
            ContentView()
        }
    }
}

QuillApp.run(QuillWireGuardApp.self)
