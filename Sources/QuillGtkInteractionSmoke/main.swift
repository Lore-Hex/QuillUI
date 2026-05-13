import QuillInteractionSmokeSupport
import QuillUI
import QuillUIGtk

private struct QuillGtkInteractionSmokeApp: App {
    var body: some Scene {
        QuillInteractionSmokeScene.scene(for: .gtk)
    }
}

QuillGtkApp.run(QuillGtkInteractionSmokeApp.self)
