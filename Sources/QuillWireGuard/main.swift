import QuillUI

struct QuillWireGuardApp: App {
    var body: some Scene {
        WindowGroup("Quill WireGuard") {
            ContentView()
        }
        .defaultSize(width: 800, height: 600)
    }
}

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("Tunnel 1")
                Text("Tunnel 2")
            }
            .navigationTitle("Tunnels")
        } detail: {
            Text("Select a tunnel")
        }
    }
}

#if os(Linux)
import BackendGTK4

GTK4Backend().run(QuillWireGuardApp.self)
#else
QuillWireGuardApp.main()
#endif
