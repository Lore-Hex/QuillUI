import UIKit
import SwiftOpenUI

@MainActor
open class UIHostingController<Content: View>: UIViewController {
    public var rootView: Content

    public init(rootView: Content) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
        self.view = UIView()
    }
}

// UIHostingConfiguration (iOS 16+) wraps a SwiftUI view as a cell's
// `contentConfiguration`. On Apple it hosts the SwiftUI content inside the cell's
// content view and conforms to UIKit's UIContentConfiguration. Linux is inert: the
// view builder runs (so its body type-checks), but nothing is rendered into a cell.
// The margins/minSize/background modifiers return self for source fidelity; the only
// upstream user (RecipientPickerViewController) uses the bare initializer.
@MainActor
public struct UIHostingConfiguration<Content: View>: UIContentConfiguration {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public func margins(_ edges: Edge.Set = .all, _ length: CGFloat) -> UIHostingConfiguration<Content> {
        _ = (edges, length)
        return self
    }

    public func minSize(width: CGFloat? = nil, height: CGFloat? = nil) -> UIHostingConfiguration<Content> {
        _ = (width, height)
        return self
    }

    public func background<S: View>(@ViewBuilder content: () -> S) -> UIHostingConfiguration<Content> {
        _ = content()
        return self
    }
}

public struct UIViewControllerRepresentableContext<Representable> {
    private let coordinatorStorage: Any

    public init(coordinator: Any = ()) {
        self.coordinatorStorage = coordinator
    }
}

public extension UIViewControllerRepresentableContext where Representable: UIViewControllerRepresentable {
    var coordinator: Representable.Coordinator {
        coordinatorStorage as! Representable.Coordinator
    }
}

public protocol UIViewControllerRepresentable: View where Body == EmptyView {
    associatedtype UIViewControllerType: UIViewController
    associatedtype Coordinator = Void

    typealias Context = UIViewControllerRepresentableContext<Self>

    @MainActor func makeUIViewController(context: Context) -> UIViewControllerType
    @MainActor func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context)
    @MainActor func makeCoordinator() -> Coordinator
}

public extension UIViewControllerRepresentable {
    var body: EmptyView {
        EmptyView()
    }

    @MainActor func makeCoordinator() -> Void {}
}

public struct UIViewRepresentableContext<Representable> {
    private let coordinatorStorage: Any

    public init(coordinator: Any = ()) {
        self.coordinatorStorage = coordinator
    }
}

public extension UIViewRepresentableContext where Representable: UIViewRepresentable {
    var coordinator: Representable.Coordinator {
        coordinatorStorage as! Representable.Coordinator
    }
}

public protocol UIViewRepresentable: View where Body == EmptyView {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void

    typealias Context = UIViewRepresentableContext<Self>

    @MainActor func makeUIView(context: Context) -> UIViewType
    @MainActor func updateUIView(_ uiView: UIViewType, context: Context)
    @MainActor func makeCoordinator() -> Coordinator
}

public extension UIViewRepresentable {
    var body: EmptyView {
        EmptyView()
    }

    @MainActor func makeCoordinator() -> Void {}
}
