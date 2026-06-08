import SwiftOpenUI

// Linux stand-ins for SwiftUI's ShareLink / SharePreview and the `draggable`
// modifier. GTK has no system share sheet or drag-and-drop transferable pipeline,
// so these are source-compatibility shims that render a plain label / pass content
// through unchanged. Visible to vendored source via the SwiftUI shadow's
// `@_exported import QuillSwiftUICompatibility`.

public struct SharePreview<PreviewImage> {
    public init(_ title: String, image: PreviewImage) {}
}

public struct ShareLink<Label: View>: View {
    private let label: Label

    public init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    fileprivate init(_label: Label) {
        self.label = _label
    }

    public var body: some View { label }
}

extension ShareLink where Label == Text {
    public init<Item>(item: Item) {
        self.init(_label: Text("share"))
    }

    public init<Item, P>(item: Item, preview: SharePreview<P>) {
        self.init(_label: Text("share"))
    }

    public init<Item, P>(item: Item, subject: Text? = nil, message: Text? = nil, preview: SharePreview<P>) {
        self.init(_label: Text("share"))
    }
}

extension View {
    /// No-op on GTK: there is no drag-and-drop transferable export.
    public func draggable<T>(_ payload: @autoclosure @escaping () -> T) -> some View { self }
}

public struct ProgressViewStyleType: Sendable {
    public init() {}
    public static let automatic = ProgressViewStyleType()
    public static let circular = ProgressViewStyleType()
    public static let linear = ProgressViewStyleType()
}

extension View {
    public func progressViewStyle(_ style: ProgressViewStyleType) -> some View { self }
}
