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
}
