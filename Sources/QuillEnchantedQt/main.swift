#if QUILLUI_ENCHANTED_QT_NATIVE_BACKEND
import QuillEnchantedQtNativeRuntime

QuillEnchantedQtNativeApp.run()
#else
import QuillEnchantedCore
import QuillEnchantedShared
import QuillUIQt

struct QuillEnchantedQtApp: App {
    var body: some Scene {
        QuillAppWindow.scene(
            "Quill Enchanted",
            width: Double(EnchantedVisualMetrics.defaultWindowWidth),
            height: Double(EnchantedVisualMetrics.defaultWindowHeight)
        ) {
            EnchantedRootView()
        }
    }
}

QuillQtApp.run(QuillEnchantedQtApp.self)
#endif
