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

    // nonisolated witness for the nonisolated provider protocol; the
    // isolated ToolbarItem construction hops (backend main loop == main
    // thread wherever toolbar erasure runs).
    nonisolated public var toolbarContentItems: [AnyToolbarItem] {
        let box = QuillToolbarHopBox(value: (placement, content))
        return MainActor.assumeIsolated {
            [AnyToolbarItem(ToolbarItem(placement: box.value.0) { box.value.1 })]
        }
    }

    public var body: Never {
        return fatalError("ToolbarItemGroup is primitive toolbar content")
    }
}

/// Crosses non-Sendable view values into assumeIsolated hops (single
/// thread: backend main loop). Same pattern as the V4L2 delivery box.
private struct QuillToolbarHopBox<T>: @unchecked Sendable { let value: T }
