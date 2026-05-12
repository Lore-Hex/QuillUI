import QuillTelegramCore
import QuillUI

struct QuillTelegramApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill Telegram", width: 1000, height: 720) {
            QuillTelegramContentView()
        }
    }
}

QuillApp.run(QuillTelegramApp.self)
