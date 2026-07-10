/// A scrollable list that renders each child in a row.
///
/// Use with `ForEach` for data-driven content:
/// ```swift
/// List {
///     ForEach(items) { item in
///         Text(item.name)
///     }
/// }
/// ```
public struct List<Content: View>: View {
    public typealias Body = Never

    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue?>?,
        @ViewBuilder content: () -> Content
    ) {
        _ = selection
        self.content = content()
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder content: () -> Content
    ) {
        _ = selection
        self.content = content()
    }

    public var body: Never { fatalError("List is a primitive view") }
}

public extension List {
    init<Data, RowContent>(
        _ data: Data,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) where Content == ForEach<Data.Element, Data.Element.ID, RowContent>,
            Data: RandomAccessCollection,
            Data.Element: Identifiable,
            RowContent: View {
        self.content = ForEach(Array(data), content: rowContent)
    }

    init<Element, RowContent>(
        _ data: Binding<[Element]>,
        selection: Binding<Set<Element>>,
        @ViewBuilder rowContent: @escaping (Binding<Element>) -> RowContent
    ) where Content == ForEach<Binding<Element>, Element.ID, RowContent>,
            Element: Identifiable & Hashable,
            RowContent: View {
        _ = selection
        self.content = ForEach(data, content: rowContent)
    }
}
