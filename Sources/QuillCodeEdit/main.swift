import QuillCodeEditCore
import QuillUI

struct QuillCodeEditApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill CodeEdit", width: 1100, height: 700) {
            QuillCodeEditContentView()
        }
    }
}

QuillApp.run(QuillCodeEditApp.self)
