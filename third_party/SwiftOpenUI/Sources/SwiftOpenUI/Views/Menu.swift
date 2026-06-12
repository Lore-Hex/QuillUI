/// An element within a Menu (item, divider, or submenu).
public enum MenuElement {
    case item(label: String, action: () -> Void)
    case divider
    case submenu(label: String, children: [MenuElement])
}

/// A single menu item with a label and action.
public struct MenuItem {
    public let label: String
    public let action: () -> Void

    public init(_ label: String, action: @escaping () -> Void) {
        self.label = quillResolveLocalizedString(label)
        self.action = action
    }
}

/// A menu divider/separator.
public struct MenuDivider {
    public init() {}
}

/// A submenu with nested menu elements.
public struct SubMenu {
    public let label: String
    public let children: [MenuElement]

    public init(_ label: String, @MenuBuilder content: () -> [MenuElement]) {
        self.label = quillResolveLocalizedString(label)
        self.children = content()
    }
}

/// A menu that can be attached to views as a context menu or popover.
public struct Menu: View {
    public typealias Body = Never

    public let title: String
    public let elements: [MenuElement]

    public init(_ title: String, @MenuBuilder content: () -> [MenuElement]) {
        self.title = quillResolveLocalizedString(title)
        self.elements = content()
    }

    public var body: Never { fatalError("Menu is a primitive view") }
}

/// Result builder for composing menu elements.
@resultBuilder
public struct MenuBuilder {
    public static func buildBlock(_ elements: [MenuElement]...) -> [MenuElement] {
        elements.flatMap { $0 }
    }

    public static func buildExpression(_ item: MenuItem) -> [MenuElement] {
        [.item(label: item.label, action: item.action)]
    }

    public static func buildExpression(_ divider: MenuDivider) -> [MenuElement] {
        [.divider]
    }

    public static func buildExpression(_ submenu: SubMenu) -> [MenuElement] {
        [.submenu(label: submenu.label, children: submenu.children)]
    }

    // No generic view catch-all here: QuillUI extends MenuBuilder with a
    // buildExpression<Content: View> that EXTRACTS real menu items from
    // Button/ForEach trees (quillMenuElements). The discard-everything
    // variant that used to live here both collided with it (ambiguous
    // buildExpression for every view in a Menu) and silently produced
    // empty menus wherever it won.

    public static func buildOptional(_ elements: [MenuElement]?) -> [MenuElement] {
        elements ?? []
    }

    public static func buildEither(first elements: [MenuElement]) -> [MenuElement] {
        elements
    }

    public static func buildEither(second elements: [MenuElement]) -> [MenuElement] {
        elements
    }
}
