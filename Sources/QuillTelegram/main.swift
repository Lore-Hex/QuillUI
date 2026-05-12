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

QuillApp.run(QuillTelegramApp.self)
