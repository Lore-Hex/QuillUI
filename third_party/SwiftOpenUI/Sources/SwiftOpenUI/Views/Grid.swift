/// A 2D grid layout.
///
/// Two modes:
/// 1. **Auto-wrap**: flat children wrap to the next row after `columns` items.
/// 2. **Explicit rows**: use `GridRow` children for row grouping with column spans.
public struct Grid<Content: View>: View {
    public typealias Body = Never

    public let columns: Int
    public let hSpacing: Int
    public let vSpacing: Int
    public let alignment: Alignment
    public let content: Content
    public let useExplicitRows: Bool

    /// Auto-wrap initializer.
    public init(columns: Int = 2, spacing: Int = 0, @ViewBuilder content: () -> Content) {
        self.columns = max(1, columns)
        self.hSpacing = max(0, spacing)
        self.vSpacing = max(0, spacing)
        self.alignment = .center
        self.content = content()
        self.useExplicitRows = false
    }

    /// Explicit row initializer — use with GridRow children.
    public init(horizontalSpacing: Int = 0, verticalSpacing: Int = 0, @ViewBuilder content: () -> Content) {
        self.columns = 0
        self.hSpacing = max(0, horizontalSpacing)
        self.vSpacing = max(0, verticalSpacing)
        self.alignment = .center
        self.content = content()
        self.useExplicitRows = true
    }

    /// SwiftUI-shaped explicit row initializer with whole-grid alignment.
    public init(
        alignment: Alignment = .center,
        horizontalSpacing: Int = 0,
        verticalSpacing: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.columns = 0
        self.hSpacing = max(0, horizontalSpacing)
        self.vSpacing = max(0, verticalSpacing)
        self.alignment = alignment
        self.content = content()
        self.useExplicitRows = true
    }

    public var body: Never { fatalError("Grid is a primitive view") }
}
