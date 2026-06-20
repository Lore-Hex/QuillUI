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
    public let typedPathBinding: AnyNavigationPathBinding?

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.pathBinding = nil
        self.typedPathBinding = nil
    }

    /// SwiftUI-compatible path-based initializer for programmatic navigation.
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Content) {
        self.content = root()
        self.pathBinding = path
        self.typedPathBinding = nil
    }

    /// SwiftUI-compatible initializer for apps that bind navigation to a typed
    /// collection such as `[Route]`.
    public init<Path: RangeReplaceableCollection>(
        path: Binding<Path>,
        @ViewBuilder root: () -> Content
    ) where Path.Element: Hashable {
        self.content = root()
        self.pathBinding = nil
        self.typedPathBinding = AnyNavigationPathBinding(path)
    }

    public var body: Never { fatalError("NavigationStack is a primitive view") }
}

/// Type-erased binding used by backends for `NavigationStack(path:)` overloads
/// whose storage is a typed collection rather than `NavigationPath`.
public struct AnyNavigationPathBinding {
    public let elements: () -> [AnyHashable]
    public let append: (AnyHashable) -> Void
    public let removeLast: (Int) -> Void

    public init<Path: RangeReplaceableCollection>(
        _ path: Binding<Path>
    ) where Path.Element: Hashable {
        self.elements = {
            path.wrappedValue.map(AnyHashable.init)
        }
        self.append = { value in
            guard let typedValue = value.base as? Path.Element else { return }
            var collection = path.wrappedValue
            collection.append(typedValue)
            path.wrappedValue = collection
        }
        self.removeLast = { count in
            guard count > 0 else { return }
            var collection = path.wrappedValue
            let removeCount = Swift.min(count, collection.count)
            let removeStart = collection.index(collection.startIndex, offsetBy: collection.count - removeCount)
            collection.removeSubrange(removeStart..<collection.endIndex)
            path.wrappedValue = collection
        }
    }
}
