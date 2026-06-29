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
    init(
        _ data: [Data],
        @ViewBuilder content: @escaping (Data) -> Content
    ) where Data: Identifiable, ID == Data.ID {
        self.data = data
        self.id = \.id
        self.content = content
    }

    init<C: RandomAccessCollection>(
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
    init<Element: Identifiable>(
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

    init<Element: Identifiable>(
        _ data: Binding<[Element]>,
        id: KeyPath<Element, ID>,
        @ViewBuilder content: @escaping (Binding<Element>) -> Content
    ) where Data == Binding<Element>, ID == Element.ID {
        _ = id
        self.init(data, content: content)
    }

    init<Element>(
        _ data: Binding<[Element]>,
        id keyPath: KeyPath<Element, ID>,
        @ViewBuilder content: @escaping (Binding<Element>) -> Content
    ) where Data == Binding<Element> {
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
        self.id = (\Binding<Element>.wrappedValue).appending(path: keyPath)
        self.content = content
    }

    func onMove(perform action: @escaping (IndexSet, Int) -> Void) -> Self {
        _ = action
        return self
    }
}

// MARK: - Custom key path

public extension ForEach {
    init(_ data: [Data], id: KeyPath<Data, ID>, @ViewBuilder content: @escaping (Data) -> Content) {
        self.data = data
        self.id = id
        self.content = content
    }

    init<C: RandomAccessCollection>(
        _ data: C,
        id: KeyPath<C.Element, ID>,
        @ViewBuilder content: @escaping (C.Element) -> Content
    ) where Data == C.Element {
        self.data = Array(data)
        self.id = id
        self.content = content
    }
}

// MARK: - Range-based

public extension ForEach where Data == Int, ID == Int {
    init(_ range: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.data = Array(range)
        self.id = \.self
        self.content = content
    }

    /// Range-based ForEach with explicit id key path (matches SwiftUI API).
    init(_ range: Range<Int>, id: KeyPath<Int, Int>, @ViewBuilder content: @escaping (Int) -> Content) {
        self.data = Array(range)
        self.id = id
        self.content = content
    }
}
