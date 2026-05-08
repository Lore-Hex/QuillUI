import SwiftUI

public struct WrappingHStack<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let spacing: Int?
    private let content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: spacing ?? 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

