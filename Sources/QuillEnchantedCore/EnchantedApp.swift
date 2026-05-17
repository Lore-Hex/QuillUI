import QuillEnchantedShared
import QuillUI

public struct QuillEnchantedApp: App {
    public init() {}

    public var body: some Scene {
        QuillAppWindow.scene(
            EnchantedCopy.windowTitle,
            width: Double(EnchantedVisualMetrics.defaultWindowWidth),
            height: Double(EnchantedVisualMetrics.defaultWindowHeight)
        ) {
            EnchantedRootView()
        }
    }
}
