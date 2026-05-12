import QuillUI

public struct QuillEnchantedApp: App {
    public init() {}

    public var body: some Scene {
        QuillAppWindow.scene("Quill Enchanted", width: 1180, height: 760) {
            EnchantedRootView()
        }
    }
}
