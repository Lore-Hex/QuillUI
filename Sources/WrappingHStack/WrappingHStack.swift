import SwiftUI

public struct WrappingHStack<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    // Convenience initializer mirroring the upstream WrappingHStack signature
    // that takes `Int?` for spacing — keep source compat for callers using
    // either Int or CGFloat literal arguments.
    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int?,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing.map { CGFloat($0) }
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: spacing ?? 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}
