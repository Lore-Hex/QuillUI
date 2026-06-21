import SwiftOpenUI

/// Top-level SwiftUI symbol rendering modes, used by sources that spell
/// `SymbolRenderingMode.palette` instead of relying on type inference.
public enum SymbolRenderingMode: Sendable {
    case monochrome
    case hierarchical
    case palette
    case multicolor
}

public struct SymbolRenderingModeView<Content: View>: View {
    public let content: Content
    public let mode: SymbolRenderingMode?

    public init(content: Content, mode: SymbolRenderingMode?) {
        self.content = content
        self.mode = mode
    }

    public var body: some View { content }
}

public extension View {
    @_disfavoredOverload
    func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> SymbolRenderingModeView<Self> {
        return SymbolRenderingModeView(content: self, mode: mode)
    }

    @_disfavoredOverload
    func foregroundStyle(_ color: Color) -> some View {
        foregroundColor(color)
    }

    @_disfavoredOverload
    func accessibilityHidden(_ hidden: Bool) -> Self {
        _ = hidden
        return self
    }
}
