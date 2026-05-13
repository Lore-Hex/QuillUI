import QuillUIQt
import QuillWireGuardUI

struct QuillWireGuardQtApp: App {
    var body: some Scene {
        QuillWireGuardScene.scene()
    }
}

QuillQtApp.run(QuillWireGuardQtApp.self)
