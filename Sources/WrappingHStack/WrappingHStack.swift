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
        // SwiftOpenUI's `HStack(spacing:)` takes `Int?` on Linux
        // while real SwiftUI takes `CGFloat?`. Coerce to keep the
        // public `spacing: CGFloat?` API stable for both backends.
        #if os(Linux)
        let resolvedSpacing: Int = spacing.map { Int($0) } ?? 8
        #else
        let resolvedSpacing: CGFloat = spacing ?? 8
        #endif
        return HStack(alignment: .center, spacing: resolvedSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}
