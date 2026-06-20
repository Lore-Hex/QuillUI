/// A single tab page with a title and content.
public struct Tab<Content: View>: View {
    public typealias Body = Never

    public var title: String
    public var id: String
    public var content: Content
    public var label: (any View)?
    public var placement: String?
    public var badge: Int?
    public var selectionValue: AnyHashable?

    public init(
        _ title: String,
        id: String? = nil,
        selectionValue: AnyHashable? = nil,
        label: (any View)? = nil,
        placement: String? = nil,
        badge: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.id = id ?? String(title.lowercased().map { $0 == " " ? "-" : $0 })
        self.content = content()
        self.label = label
        self.placement = placement
        self.badge = badge
        self.selectionValue = selectionValue
    }

    public var body: Never { fatalError("Tab is a primitive view") }
}

/// Type-erased tab for storing heterogeneous Tab<Content> in an array.
public struct AnyTab {
    public let title: String
    public let id: String
    public let wrapped: any View
    public let label: (any View)?
    public let placement: String?
    public let badge: Int?
    public let selectionValue: AnyHashable?

    public init<Content: View>(_ tab: Tab<Content>) {
        self.title = tab.title
        self.id = tab.id
        self.wrapped = tab.content
        self.label = tab.label
        self.placement = tab.placement
        self.badge = tab.badge
        self.selectionValue = tab.selectionValue
    }
}

/// A tabbed container that switches between child pages.
public struct TabView: View {
    public typealias Body = Never

    public let tabs: [AnyTab]
    public let initialTab: Int?
    public let selectedID: String?
    public let selectionHandler: ((String) -> Void)?

    public init(initialTab: Int? = nil, @TabBuilder content: () -> [AnyTab]) {
        self.initialTab = initialTab
        self.tabs = content()
        self.selectedID = nil
        self.selectionHandler = nil
    }

    public init<Selection: Hashable>(selection: Binding<Selection>, @TabBuilder content: () -> [AnyTab]) {
        self.initialTab = nil
        let collectedTabs = content()
        self.tabs = collectedTabs
        let selectedValue = AnyHashable(selection.wrappedValue)
        self.selectedID = collectedTabs.first { $0.selectionValue == selectedValue }?.id
            ?? String(describing: selection.wrappedValue)
        self.selectionHandler = { selectedID in
            guard let value = collectedTabs.first(where: { $0.id == selectedID })?.selectionValue?.base as? Selection else {
                return
            }
            selection.wrappedValue = value
        }
    }

    public var body: Never { fatalError("TabView is a primitive view") }
}

/// Result builder for composing tabs.
@resultBuilder
public struct TabBuilder {
    public static func buildBlock(_ tabs: [AnyTab]...) -> [AnyTab] {
        tabs.flatMap { $0 }
    }

    public static func buildExpression<Content: View>(_ tab: Tab<Content>) -> [AnyTab] {
        [AnyTab(tab)]
    }

    public static func buildOptional(_ tabs: [AnyTab]?) -> [AnyTab] {
        tabs ?? []
    }

    public static func buildEither(first tabs: [AnyTab]) -> [AnyTab] {
        tabs
    }

    public static func buildEither(second tabs: [AnyTab]) -> [AnyTab] {
        tabs
    }

    public static func buildArray(_ tabs: [[AnyTab]]) -> [AnyTab] {
        tabs.flatMap { $0 }
    }
}
