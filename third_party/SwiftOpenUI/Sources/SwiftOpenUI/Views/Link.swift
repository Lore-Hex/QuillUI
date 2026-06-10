import Foundation

/// A view that opens a URL when tapped.
public struct Link: View {
    public typealias Body = Never

    public let title: String
    public let destination: String
    public let labelView: AnyView

    /// Create a link with a string URL.
    public init(_ title: String, destination: String) {
        self.title = title
        self.destination = destination
        self.labelView = AnyView(Text(title))
    }

    /// Create a link with a URL and a custom SwiftUI label.
    public init<Label: View>(destination: URL, @ViewBuilder label: () -> Label) {
        let builtLabel = label()
        self.title = linkLabelText(from: builtLabel)
        self.destination = destination.absoluteString
        self.labelView = AnyView(builtLabel)
    }

    public var body: Never { fatalError("Link is a primitive view") }
}

private func linkLabelText<Label: View>(from label: Label) -> String {
    if let text = label as? Text {
        return text.content
    }
    return ""
}
