import QuillInteractionSmokeSupport
import QuillUI

private struct QuillGtkInteractionSmokeApp: App {
    var body: some Scene {
        QuillInteractionSmokeScene.scene(for: .gtk)
    }
}

QuillApp.run(QuillGtkInteractionSmokeApp.self)
