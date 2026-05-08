import QuillUI

public struct QuillEnchantedApp: App {
    public init() {}

    public var body: some Scene {
        #if os(macOS) || os(iOS) || os(visionOS)
        WindowGroup("Quill Enchanted") {
            MainActor.assumeIsolated {
                EnchantedRootView()
            }
        }
        .defaultSize(width: 1180, height: 760)
        #else
        WindowGroup("Quill Enchanted") {
            MainActor.assumeIsolated {
                EnchantedRootView()
            }
        }
        .defaultWindowSize(width: 1180, height: 760)
        #endif
    }
}
