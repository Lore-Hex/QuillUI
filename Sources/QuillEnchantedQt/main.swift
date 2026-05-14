#if QUILLUI_ENCHANTED_QT_NATIVE_BACKEND
import QuillEnchantedQtNativeRuntime

QuillEnchantedQtNativeApp.run()
#else
import QuillEnchantedCore
import QuillUIQt

struct QuillEnchantedQtApp: App {
    var body: some Scene {
        QuillAppWindow.scene("Quill Enchanted", width: 1180, height: 760) {
            EnchantedRootView()
        }
    }
}

QuillQtApp.run(QuillEnchantedQtApp.self)
#endif
