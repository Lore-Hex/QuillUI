import Foundation
import QuillEnchantedShared
import QuillUI

public struct QuillEnchantedApp: App {
    public init() {}

    public var body: some Scene {
        let useReferenceSize = ProcessInfo.processInfo.environment["QUILLUI_ENCHANTED_REFERENCE_MODE"] == "1"
        let width = useReferenceSize ? 1114.0 : Double(EnchantedVisualMetrics.defaultWindowWidth)
        let height = useReferenceSize ? 721.0 : Double(EnchantedVisualMetrics.defaultWindowHeight)

        let windowTitle = useReferenceSize ? "Enchanted Reference" : EnchantedCopy.windowTitle

        return QuillAppWindow.scene(
            windowTitle,
            width: width,
            height: height
        ) {
            EnchantedRootView()
        }
    }
}
