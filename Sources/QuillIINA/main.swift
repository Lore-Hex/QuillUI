import QuillIINACore
import QuillUI

struct QuillIINAApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill IINA", width: 960, height: 600) {
            QuillIINAContentView()
        }
    }
}

QuillApp.run(QuillIINAApp.self)
