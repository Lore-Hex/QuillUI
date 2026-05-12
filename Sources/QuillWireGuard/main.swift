import QuillUI

struct QuillWireGuardApp: App {
    var body: some Scene {
        WindowGroup("Quill WireGuard") {
            QuillMainActorView.assumeIsolated {
                ContentView()
            }
        }
        .defaultSize(width: 800, height: 600)
    }
}

QuillApp.run(QuillWireGuardApp.self)
