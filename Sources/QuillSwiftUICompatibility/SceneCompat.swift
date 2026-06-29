import SwiftOpenUI

public extension Window {
    func windowStyle<S: WindowStyle>(_ style: S) -> Self {
        _ = style
        return self
    }
}

public struct MenuBarExtra<Content: View, LabelContent: View>: Scene {
    public typealias Body = Never

    public let content: Content
    public let label: LabelContent

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> LabelContent
    ) {
        self.content = content()
        self.label = label()
    }

    public var body: Never {
        fatalError("MenuBarExtra is a primitive scene")
    }
}
