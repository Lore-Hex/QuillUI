import Foundation

/// A view that creates views from a collection of identified data.
public struct ForEach<Data, ID: Hashable, Content: View>: View, TransparentMultiChildView {
    public typealias Body = Never

    public let data: [Data]
    public let id: KeyPath<Data, ID>
    public let content: (Data) -> Content

    public var body: Never { fatalError("ForEach is a primitive view") }

    public var children: [any View] {
        data.map { content($0) }
    }
}

// MARK: - Identifiable data

public extension ForEach {
    public init<Element: Identifiable>(
        _ data: [Element],
        @ViewBuilder content: @escaping (Element) -> Content
    ) where Data == Element, ID == Element.ID {
        self.data = data
        self.id = \.id
        self.content = content
    }

    public init<C: RandomAccessCollection>(
        _ data: C,
        @ViewBuilder content: @escaping (C.Element) -> Content
    ) where C.Element: Identifiable, Data == C.Element, ID == C.Element.ID {
        self.data = Array(data)
        self.id = \.id
        self.content = content
    }
}

// MARK: - Binding collections

public extension ForEach {
    public init<Element: Identifiable>(
        _ data: Binding<[Element]>,
        @ViewBuilder content: @escaping (Binding<Element>) -> Content
    ) where Data == Binding<Element>, ID == Element.ID {
        let indices = Array(data.wrappedValue.indices)
        self.data = indices.map { index in
            Binding<Element>(
                get: { data.wrappedValue[index] },
                set: { newValue in
                    var values = data.wrappedValue
                    guard values.indices.contains(index) else { return }
                    values[index] = newValue
                    data.wrappedValue = values
                }
            )
        }
        self.id = \.wrappedValue.id
        self.content = content
    }

    public func onMove(perform action: @escaping (IndexSet, Int) -> Void) -> Self {
        _ = action
        return self
    }
}

// MARK: - Custom key path

public extension ForEach {
    public init(_ data: [Data], id: KeyPath<Data, ID>, @ViewBuilder content: @escaping (Data) -> Content) {
        self.data = data
        self.id = id
        self.content = content
    }

}

// MARK: - Range-based

public extension ForEach where Data == Int, ID == Int {
    public init(_ range: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.data = Array(range)
        self.id = \.self
        self.content = content
    }

    /// Range-based ForEach with explicit id key path (matches SwiftUI API).
    public init(_ range: Range<Int>, id: KeyPath<Int, Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.data = Array(range)
        self.id = id
        self.content = content
    }
}
