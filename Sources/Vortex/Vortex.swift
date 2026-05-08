import SwiftUI

public struct VortexSystem: Sendable {
    public init() {}

    public static let splash = VortexSystem()

    public func makeUniqueCopy() -> VortexSystem {
        self
    }
}

public struct VortexView<Content: View>: View {
    private let system: VortexSystem
    private let content: Content

    public init(_ system: VortexSystem, @ViewBuilder content: () -> Content) {
        self.system = system
        self.content = content()
    }

    public var body: some View {
        ZStack {
            content
        }
    }
}

