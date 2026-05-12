import QuillSignalCore
import QuillUI

struct QuillSignalApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill Signal", width: 900, height: 700) {
            QuillSignalContentView()
        }
    }
}

QuillApp.run(QuillSignalApp.self)
