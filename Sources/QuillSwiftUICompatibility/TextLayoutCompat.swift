import SwiftOpenUI

public extension View {
    func baselineOffset(_ baselineOffset: Double) -> some View {
        self
    }
}

public extension Text {
    func baselineOffset(_ baselineOffset: Double) -> Text {
        _ = baselineOffset
        return self
    }

    func monospaced() -> Text {
        self
    }

    func fontDesign(_ design: Font.Design?) -> Text {
        _ = design
        return self
    }
}

public extension Font {
    static func custom(_ name: String, size: Double, relativeTo textStyle: Font.TextStyle) -> Font {
        _ = name
        _ = textStyle
        return .system(size: size)
    }

    /// Apple's fixed-size `Font.custom(_:size:)` (no Dynamic Type scaling).
    /// SignalSymbols loads a custom glyph font at an absolute point size; with
    /// no custom-font loader on Linux this resolves to the system font.
    static func custom(_ name: String, size: Double) -> Font {
        _ = name
        return .system(size: size)
    }

    func bold() -> Font { self.weight(.bold) }
}

public extension ToolbarItemPlacement {
    static var automatic: ToolbarItemPlacement { .primaryAction }
    static var principal: ToolbarItemPlacement { .primaryAction }
    static var navigation: ToolbarItemPlacement { .leading }
    static var navigationBarLeading: ToolbarItemPlacement { .leading }
    static var navigationBarTrailing: ToolbarItemPlacement { .trailing }
    static var topBarLeading: ToolbarItemPlacement { .leading }
    static var topBarTrailing: ToolbarItemPlacement { .trailing }
    static var cancellationAction: ToolbarItemPlacement { .leading }
    static var confirmationAction: ToolbarItemPlacement { .trailing }
    static var destructiveAction: ToolbarItemPlacement { .trailing }
    static var bottomBar: ToolbarItemPlacement { .primaryAction }
}

public struct ToolbarItemGroup<Content: View>: ToolbarContent, ToolbarContentItemsProvider {
    public typealias Body = Never

    public let placement: ToolbarItemPlacement
    public let content: Content

    public init(
        placement: ToolbarItemPlacement = .primaryAction,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }

    public var toolbarContentItems: [AnyToolbarItem] {
        [AnyToolbarItem(ToolbarItem(placement: placement) { content })]
    }

    public var body: Never {
        return fatalError("ToolbarItemGroup is primitive toolbar content")
    }
}
