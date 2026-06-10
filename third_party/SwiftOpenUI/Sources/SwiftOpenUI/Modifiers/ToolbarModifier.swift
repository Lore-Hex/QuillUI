/// Placement for toolbar items.
public enum ToolbarItemPlacement: Equatable, Hashable {
    case leading
    case trailing
    case primaryAction
}

/// Visibility state for a toolbar container.
public enum ToolbarVisibility: Equatable {
    case automatic
    case visible
    case hidden
}

/// Simplified toolbar container targets.
public enum ToolbarPlacementTarget: Equatable {
    case automatic
    case navigationBar
    case bottomBar
    case tabBar
}

/// Stored toolbar configuration attached to a view tree.
public struct ToolbarConfiguration: Equatable {
    public let visibility: ToolbarVisibility?
    public let visibilityTarget: ToolbarPlacementTarget?
    public let removedPlacements: [ToolbarItemPlacement]

    public init(
        visibility: ToolbarVisibility? = nil,
        visibilityTarget: ToolbarPlacementTarget? = nil,
        removedPlacements: [ToolbarItemPlacement] = []
    ) {
        self.visibility = visibility
        self.visibilityTarget = visibilityTarget
        self.removedPlacements = removedPlacements
    }
}

public protocol ToolbarContent {
    associatedtype Body: ToolbarContent

    @ToolbarContentBuilder
    var body: Body { get }
}

extension Never: ToolbarContent {}

public protocol ToolbarContentItemsProvider {
    var toolbarContentItems: [AnyToolbarItem] { get }
}

private func flattenToolbarContent<Content: ToolbarContent>(_ content: Content) -> [AnyToolbarItem] {
    if let provider = content as? any ToolbarContentItemsProvider {
        return provider.toolbarContentItems
    }
    if Content.Body.self != Never.self {
        return flattenToolbarContent(content.body)
    }
    return []
}

/// Flattened toolbar content produced by `ToolbarContentBuilder`.
public struct ToolbarContentGroup: ToolbarContent, ToolbarContentItemsProvider {
    public typealias Body = Never

    public let items: [AnyToolbarItem]

    public init(items: [AnyToolbarItem]) {
        self.items = items
    }

    public var toolbarContentItems: [AnyToolbarItem] { items }
    public var body: Never { return fatalError("ToolbarContentGroup is primitive toolbar content") }
}

/// Result builder for composing one or more toolbar items.
@resultBuilder
public enum ToolbarContentBuilder {
    public static func buildBlock() -> ToolbarContentGroup {
        ToolbarContentGroup(items: [])
    }

    public static func buildBlock(_ components: ToolbarContentGroup...) -> ToolbarContentGroup {
        ToolbarContentGroup(items: components.flatMap(\.items))
    }

    public static func buildExpression<Content: ToolbarContent>(_ expression: Content) -> ToolbarContentGroup {
        ToolbarContentGroup(items: flattenToolbarContent(expression))
    }

    @_disfavoredOverload
    public static func buildExpression<Content: View>(_ expression: Content) -> ToolbarContentGroup {
        ToolbarContentGroup(items: [AnyToolbarItem(ToolbarItem { expression })])
    }

    public static func buildExpression(_ expression: ToolbarContentGroup) -> ToolbarContentGroup {
        expression
    }

    public static func buildOptional(_ component: ToolbarContentGroup?) -> ToolbarContentGroup {
        component ?? ToolbarContentGroup(items: [])
    }

    public static func buildEither(first component: ToolbarContentGroup) -> ToolbarContentGroup {
        component
    }

    public static func buildEither(second component: ToolbarContentGroup) -> ToolbarContentGroup {
        component
    }

    public static func buildArray(_ components: [ToolbarContentGroup]) -> ToolbarContentGroup {
        ToolbarContentGroup(items: components.flatMap(\.items))
    }

    public static func buildPartialBlock(first: ToolbarContentGroup) -> ToolbarContentGroup {
        first
    }

    public static func buildPartialBlock(
        accumulated: ToolbarContentGroup,
        next: ToolbarContentGroup
    ) -> ToolbarContentGroup {
        ToolbarContentGroup(items: accumulated.items + next.items)
    }
}

/// A single toolbar item with placement and content.
public struct ToolbarItem<Content: View>: View, ToolbarContent, ToolbarContentItemsProvider {
    public typealias Body = Never

    public let placement: ToolbarItemPlacement
    public let content: Content

    public init(placement: ToolbarItemPlacement = .primaryAction,
                @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    public var body: Never { return fatalError("ToolbarItem is a primitive view") }
    public var toolbarContentItems: [AnyToolbarItem] { [AnyToolbarItem(self)] }
}

/// Type-erased toolbar item.
public struct AnyToolbarItem {
    public let placement: ToolbarItemPlacement
    public let wrapped: any View
    public let renderedViews: [any View]

    public init<Content: View>(_ item: ToolbarItem<Content>) {
        self.placement = item.placement
        self.wrapped = item.content
        if let multi = item.content as? MultiChildView {
            self.renderedViews = multi.children
        } else if Content.Body.self != Never.self,
                  let multi = item.content.body as? MultiChildView {
            self.renderedViews = multi.children
        } else if Content.Body.self != Never.self {
            self.renderedViews = [item.content.body]
        } else {
            self.renderedViews = [item.content]
        }
    }
}

/// Protocol for views that carry toolbar items (for NavigationStack extraction).
public protocol ToolbarProvider {
    var toolbarItems: [AnyToolbarItem] { get }
}

/// Protocol for views that carry toolbar configuration.
public protocol ToolbarConfigurationProvider {
    var toolbarConfiguration: ToolbarConfiguration { get }
}

/// A view that carries toolbar items alongside its content.
public struct ToolbarView<Content: View>: View, ToolbarProvider, ToolbarConfigurationProvider {
    public typealias Body = Never

    public let content: Content
    public let toolbarID: String?
    public let toolbarItems: [AnyToolbarItem]
    public let toolbarConfiguration: ToolbarConfiguration

    public var body: Never { fatalError("ToolbarView is a primitive view") }
}

/// A view wrapper that carries toolbar visibility/removal configuration.
public struct ToolbarConfigurationView<Content: View>: View, PrimitiveView, ToolbarConfigurationProvider {
    public typealias Body = Never

    public let content: Content
    public let toolbarConfiguration: ToolbarConfiguration

    public var body: Never { fatalError("ToolbarConfigurationView is a primitive view") }
}

private func mergeRemovedPlacements(
    existing: [ToolbarItemPlacement],
    incoming: [ToolbarItemPlacement]
) -> [ToolbarItemPlacement] {
    existing + incoming.filter { !existing.contains($0) }
}

extension View {
    /// Adds one or more toolbar items.
    public func toolbar<Items: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Items
    ) -> ToolbarView<Self> {
        let toolbarContent = content()
        return ToolbarView(
            content: self,
            toolbarID: nil,
            toolbarItems: flattenToolbarContent(toolbarContent),
            toolbarConfiguration: ToolbarConfiguration()
        )
    }

    /// Adds one or more toolbar items with a stored toolbar identifier.
    public func toolbar<Items: ToolbarContent>(
        id: String,
        @ToolbarContentBuilder content: () -> Items
    ) -> ToolbarView<Self> {
        let toolbarContent = content()
        return ToolbarView(
            content: self,
            toolbarID: id,
            toolbarItems: flattenToolbarContent(toolbarContent),
            toolbarConfiguration: ToolbarConfiguration()
        )
    }

    /// Stores toolbar visibility for a target container.
    public func toolbar(
        _ visibility: ToolbarVisibility,
        for target: ToolbarPlacementTarget
    ) -> ToolbarConfigurationView<Self> {
        ToolbarConfigurationView(
            content: self,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: visibility,
                visibilityTarget: target
            )
        )
    }

    /// Stores item placements that should be removed from the toolbar.
    public func toolbar(
        removing placements: ToolbarItemPlacement...
    ) -> ToolbarConfigurationView<Self> {
        ToolbarConfigurationView(
            content: self,
            toolbarConfiguration: ToolbarConfiguration(
                removedPlacements: placements
            )
        )
    }
}

extension ToolbarConfigurationView {
    /// Adds one or more toolbar items while preserving stored toolbar configuration.
    public func toolbar<Items: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Items
    ) -> ToolbarView<Content> {
        let toolbarContent = content()
        return ToolbarView(
            content: self.content,
            toolbarID: nil,
            toolbarItems: flattenToolbarContent(toolbarContent),
            toolbarConfiguration: toolbarConfiguration
        )
    }

    /// Adds one or more toolbar items with a stored identifier while preserving toolbar configuration.
    public func toolbar<Items: ToolbarContent>(
        id: String,
        @ToolbarContentBuilder content: () -> Items
    ) -> ToolbarView<Content> {
        let toolbarContent = content()
        return ToolbarView(
            content: self.content,
            toolbarID: id,
            toolbarItems: flattenToolbarContent(toolbarContent),
            toolbarConfiguration: toolbarConfiguration
        )
    }

    /// Updates toolbar visibility while preserving other stored toolbar configuration.
    public func toolbar(
        _ visibility: ToolbarVisibility,
        for target: ToolbarPlacementTarget
    ) -> ToolbarConfigurationView<Content> {
        ToolbarConfigurationView(
            content: content,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: visibility,
                visibilityTarget: target,
                removedPlacements: toolbarConfiguration.removedPlacements
            )
        )
    }

    /// Adds removed placements while preserving stored toolbar visibility.
    public func toolbar(
        removing placements: ToolbarItemPlacement...
    ) -> ToolbarConfigurationView<Content> {
        ToolbarConfigurationView(
            content: content,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: toolbarConfiguration.visibility,
                visibilityTarget: toolbarConfiguration.visibilityTarget,
                removedPlacements: mergeRemovedPlacements(
                    existing: toolbarConfiguration.removedPlacements,
                    incoming: placements
                )
            )
        )
    }
}

extension ToolbarView {
    /// Adds one or more toolbar items while preserving existing items and configuration.
    public func toolbar<Items: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Items
    ) -> ToolbarView<Content> {
        let toolbarContent = content()
        return ToolbarView(
            content: self.content,
            toolbarID: toolbarID,
            toolbarItems: toolbarItems + flattenToolbarContent(toolbarContent),
            toolbarConfiguration: toolbarConfiguration
        )
    }

    /// Adds one or more toolbar items with a stored identifier while preserving configuration.
    public func toolbar<Items: ToolbarContent>(
        id: String,
        @ToolbarContentBuilder content: () -> Items
    ) -> ToolbarView<Content> {
        let toolbarContent = content()
        return ToolbarView(
            content: self.content,
            toolbarID: id,
            toolbarItems: toolbarItems + flattenToolbarContent(toolbarContent),
            toolbarConfiguration: toolbarConfiguration
        )
    }

    /// Updates toolbar visibility while preserving stored items and toolbar configuration.
    public func toolbar(
        _ visibility: ToolbarVisibility,
        for target: ToolbarPlacementTarget
    ) -> ToolbarView<Content> {
        ToolbarView(
            content: content,
            toolbarID: toolbarID,
            toolbarItems: toolbarItems,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: visibility,
                visibilityTarget: target,
                removedPlacements: toolbarConfiguration.removedPlacements
            )
        )
    }

    /// Adds removed placements while preserving stored items and toolbar configuration.
    public func toolbar(
        removing placements: ToolbarItemPlacement...
    ) -> ToolbarView<Content> {
        ToolbarView(
            content: content,
            toolbarID: toolbarID,
            toolbarItems: toolbarItems,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: toolbarConfiguration.visibility,
                visibilityTarget: toolbarConfiguration.visibilityTarget,
                removedPlacements: mergeRemovedPlacements(
                    existing: toolbarConfiguration.removedPlacements,
                    incoming: placements
                )
            )
        )
    }
}
