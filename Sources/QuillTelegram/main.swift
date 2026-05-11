import QuillTelegramCore
import QuillUI

@MainActor
struct QuillTelegramApp: App {
    var body: some Scene {
        WindowGroup("Quill Telegram") {
            QuillTelegramContentView()
        }
        .defaultSize(width: 1000, height: 720)
    }
}

#if os(Linux)
import BackendGTK4

GTK4Backend().run(QuillTelegramApp.self)
#else
QuillTelegramApp.main()
#endif
