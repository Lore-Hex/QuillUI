import Foundation

public final class CHHapticEngine {
    public struct CapabilitiesForHardware: Sendable {
        public var supportsHaptics: Bool
        public init(supportsHaptics: Bool = false) {
            self.supportsHaptics = supportsHaptics
        }
    }

    public static func capabilitiesForHardware() -> CapabilitiesForHardware {
        CapabilitiesForHardware()
    }
}
