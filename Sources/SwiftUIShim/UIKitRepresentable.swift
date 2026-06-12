import UIKit
import SwiftOpenUI

@MainActor
open class UIHostingController<Content: View>: UIViewController {
    public var rootView: Content

    public init(rootView: Content) {
        self.rootView = rootView
        super.init()
        self.view = UIView()
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
