import QuillCodeEditCore
import QuillUI

@MainActor
struct QuillCodeEditApp: App {
    var body: some Scene {
        WindowGroup("Quill CodeEdit") {
            QuillCodeEditContentView()
        }
        .defaultSize(width: 1100, height: 700)
    }
}

QuillApp.run(QuillCodeEditApp.self)
