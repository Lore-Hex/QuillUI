import QuillIINACore
import QuillUI

@MainActor
struct QuillIINAApp: App {
    var body: some Scene {
        WindowGroup("Quill IINA") {
            QuillIINAContentView()
        }
        .defaultSize(width: 960, height: 600)
    }
}

QuillApp.run(QuillIINAApp.self)
