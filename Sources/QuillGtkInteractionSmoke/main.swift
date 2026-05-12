import QuillInteractionSmokeSupport
import QuillUI

private struct QuillGtkInteractionSmokeApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill GTK Interaction", width: 640, height: 760) {
            QuillInteractionSmokeView(
                title: "Quill GTK Interaction",
                clickTargetTitle: "Native GTK click target",
                backendName: "GTK"
            )
        }
    }
}

QuillApp.run(QuillGtkInteractionSmokeApp.self)
