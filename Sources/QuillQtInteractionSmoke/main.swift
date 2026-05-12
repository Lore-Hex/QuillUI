import QuillInteractionSmokeSupport
import QuillUI
import QuillUIQt

private struct QuillQtInteractionSmokeApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill Qt Interaction", width: 640, height: 760) {
            QuillInteractionSmokeView(
                title: "Quill Qt Interaction",
                clickTargetTitle: "Native Qt click target",
                backendName: "Qt"
            )
        }
    }
}

QuillQtApp.run(QuillQtInteractionSmokeApp.self)
