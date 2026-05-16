import QuillEnchantedShared
import QuillUI

public struct QuillEnchantedApp: App {
    public init() {}

    public var body: some Scene {
        QuillAppWindow.scene(
            "Quill Enchanted",
            width: Double(EnchantedVisualMetrics.defaultWindowWidth),
            height: Double(EnchantedVisualMetrics.defaultWindowHeight)
        ) {
            EnchantedRootView()
        }
    }
}
