/// Protocol for extracting navigation title from a view.
public protocol NavigationTitled {
    var navigationTitle: String { get }
}

/// A container that manages a stack of views with push/pop navigation.
/// Backend renderers implement the GTK/Win32/Web-specific widget creation.
public struct NavigationStack<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let pathBinding: Binding<NavigationPath>?

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.pathBinding = nil
    }

    /// SwiftUI-compatible path-based initializer for programmatic navigation.
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Content) {
        self.content = root()
        self.pathBinding = path
    }

    /// Compatibility initializer for SwiftUI apps that bind navigation to a
    /// typed array/path. Backends currently render the root content and ignore
    /// the typed path until full value navigation is implemented for that type.
    public init<Path: RangeReplaceableCollection>(
        path: Binding<Path>,
        @ViewBuilder root: () -> Content
    ) where Path.Element: Hashable {
        _ = path
        self.content = root()
        self.pathBinding = nil
    }

    public var body: Never { fatalError("NavigationStack is a primitive view") }
}
