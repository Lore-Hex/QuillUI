import QuillInteractionSmokeSupport
import QuillUI
import QuillUIQt

private struct QuillQtInteractionSmokeApp: App {
    var body: some Scene {
        QuillInteractionSmokeScene.scene(for: .qt)
    }
}

QuillQtApp.run(QuillQtInteractionSmokeApp.self)
