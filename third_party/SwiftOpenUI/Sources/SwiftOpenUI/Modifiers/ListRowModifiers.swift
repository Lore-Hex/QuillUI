import Foundation

private func swiftOpenUIRecordCompatibilityFallback(_ operation: String, message: String) {
    NotificationCenter.default.post(
        name: Notification.Name("QuillSwiftOpenUICompatibilityFallback"),
        object: nil,
        userInfo: [
            "subsystem": "QuillUI",
            "operation": operation,
            "severity": "info",
            "message": message
        ]
    )
}

/// Protocol for views that carry SwiftUI list/form row inset metadata.
public protocol ListRowInsetsProvider {
    var listRowInsets: EdgeInsets? { get }
    var listRowContent: any View { get }
}

/// Protocol for views that carry SwiftUI list/form row separator metadata.
public protocol ListRowSeparatorProvider {
    var listRowSeparatorVisibility: Visibility { get }
    var listRowSeparatorEdges: Edge.Set { get }
    var listRowSeparatorContent: any View { get }
}

/// A wrapper that carries per-row inset metadata for List/Form renderers.
public struct ListRowInsetsView<Content: View>: View, ListRowInsetsProvider {
    public let content: Content
    public let insets: EdgeInsets?

    public init(content: Content, insets: EdgeInsets?) {
        self.content = content
        self.insets = insets
    }

    public var body: Content { content }

    public var listRowInsets: EdgeInsets? { insets }
    public var listRowContent: any View { content }
}

/// A wrapper that carries per-row separator metadata for List/Form renderers.
public struct ListRowSeparatorView<Content: View>: View, ListRowSeparatorProvider {
    public let content: Content
    public let visibility: Visibility
    public let edges: Edge.Set

    public init(content: Content, visibility: Visibility, edges: Edge.Set) {
        self.content = content
        self.visibility = visibility
        self.edges = edges
    }

    public var body: Content { content }

    public var listRowSeparatorVisibility: Visibility { visibility }
    public var listRowSeparatorEdges: Edge.Set { edges }
    public var listRowSeparatorContent: any View { content }
}

public extension View {
    /// Sets the insets for this row when rendered inside a List or Form.
    func listRowInsets(_ insets: EdgeInsets?) -> ListRowInsetsView<Self> {
        swiftOpenUIRecordCompatibilityFallback(
            "listRowInsets",
            message: "listRowInsets is preserved as list row layout metadata on Linux."
        )
        return ListRowInsetsView(content: self, insets: insets)
    }

    /// Sets row separator visibility when rendered inside a List or Form.
    func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> ListRowSeparatorView<Self> {
        swiftOpenUIRecordCompatibilityFallback(
            "listRowSeparator",
            message: "listRowSeparator is preserved as list row separator metadata on Linux."
        )
        return ListRowSeparatorView(content: self, visibility: visibility, edges: edges)
    }
}
