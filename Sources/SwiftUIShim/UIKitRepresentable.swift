import UIKit
import SwiftOpenUI

private struct SwiftUIShimUncheckedSendableView<Content: View>: @unchecked Sendable {
    let content: Content
}

private enum QuillMainActorView {
    static func assumeIsolated<Content: View>(_ content: @MainActor () -> Content) -> Content {
        MainActor.assumeIsolated {
            SwiftUIShimUncheckedSendableView(content: content())
        }.content
    }
}

@MainActor
private protocol QuillHostedSwiftUIView: AnyObject {
    var quillHostedRootAnyView: AnyView { get }
}

@MainActor
private final class QuillUIHostingUIView<Content: View>: UIView, QuillHostedSwiftUIView {
    var rootView: Content

    init(rootView: Content) {
        self.rootView = rootView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("QuillUIHostingUIView(coder:) requires a rootView")
    }

    var quillHostedRootAnyView: AnyView {
        AnyView(rootView)
    }
}

@MainActor
open class UIHostingController<Content: View>: UIViewController {
    public var rootView: Content {
        didSet {
            if let hostedView = viewIfLoaded as? QuillUIHostingUIView<Content> {
                hostedView.rootView = rootView
            }
        }
    }

    public init(rootView: Content) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
        self.view = QuillUIHostingUIView(rootView: rootView)
    }

    // UIViewController now declares `required init?(coder:)` (Apple-faithful);
    // a subclass with its own designated init must restate it. Storyboards
    // don't exist on Linux, so it's unavailable like Apple's UIHostingController.
    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not available on Linux")
    }
}

extension UIHostingController: QuillHostedSwiftUIView {
    fileprivate var quillHostedRootAnyView: AnyView {
        AnyView(rootView)
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

    public nonisolated var body: some View {
        QuillMainActorView.assumeIsolated {
            content
        }
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

public protocol UIViewControllerRepresentable: View, _ViewMetadataExtractionBoundary {
    associatedtype UIViewControllerType: UIViewController
    associatedtype Coordinator = Void

    typealias Context = UIViewControllerRepresentableContext<Self>

    @MainActor func makeUIViewController(context: Context) -> UIViewControllerType
    @MainActor func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context)
    @MainActor func makeCoordinator() -> Coordinator
    @MainActor static func dismantleUIViewController(
        _ uiViewController: UIViewControllerType,
        coordinator: Coordinator
    )
}

public extension UIViewControllerRepresentable {
    var body: QuillUIViewControllerRepresentableHostView<Self> {
        QuillUIViewControllerRepresentableHostView(self)
    }

    @MainActor func makeCoordinator() -> Void {}

    @MainActor static func dismantleUIViewController(
        _ uiViewController: UIViewControllerType,
        coordinator: Coordinator
    ) {}
}

// StateObject's lazy factory prevents a throwaway coordinator from being
// created before the renderer restores the prior mount's storage.
@MainActor
private final class QuillUIViewControllerRepresentableMount<R: UIViewControllerRepresentable>:
    ObservableObject
{
    let coordinator: R.Coordinator
    let controller: R.UIViewControllerType

    init(_ representable: R) {
        let coordinator = representable.makeCoordinator()
        let context = R.Context(coordinator: coordinator)
        self.coordinator = coordinator
        self.controller = representable.makeUIViewController(context: context)
    }

    func update(with representable: R) -> R.UIViewControllerType {
        let context = R.Context(coordinator: coordinator)
        representable.updateUIViewController(controller, context: context)
        return controller
    }
}

/// Host view that lowers common UIKit controller representables into
/// SwiftOpenUI-native controls on non-UIKit platforms.
public struct QuillUIViewControllerRepresentableHostView<R: UIViewControllerRepresentable>:
    View,
    _ViewMetadataExtractionBoundary
{
    let representable: R
    @StateObject private var mount: QuillUIViewControllerRepresentableMount<R>

    init(_ representable: R) {
        self.representable = representable
        _mount = StateObject(
            wrappedValue: QuillUIViewControllerRepresentableMount(representable)
        )
    }

    @ViewBuilder
    public var body: some View {
        let controller = mount.update(with: representable)

        if let fontPicker = controller as? UIFontPickerViewController {
            QuillUIFontPickerControllerHost(
                controller: fontPicker,
                coordinatorRetainer: mount.coordinator
            )
        } else {
            EmptyView()
        }
    }
}

private struct QuillUIFontPickerControllerHost: View {
    let controller: UIFontPickerViewController
    private let coordinatorRetainer: Any

    init(controller: UIFontPickerViewController, coordinatorRetainer: Any) {
        self.controller = controller
        self.coordinatorRetainer = coordinatorRetainer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Font")
                .font(.headline)
            Text("Select a font for this app.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                fontButton("System", descriptorName: ".AppleSystemUIFont")
                fontButton("Rounded", descriptorName: ".AppleSystemUIFontRounded-Regular")
                fontButton("Inter", descriptorName: "Inter-Regular")
                fontButton("Atkinson Hyperlegible", descriptorName: "AtkinsonHyperlegible-Regular")
            }
            Divider()
            Button("Cancel") {
                controller.delegate?.fontPickerViewControllerDidCancel(controller)
            }
        }
        .padding()
    }

    private func fontButton(_ title: String, descriptorName: String) -> some View {
        Button(title) {
            controller.selectedFontDescriptor = UIFontDescriptor(name: descriptorName)
            controller.delegate?.fontPickerViewControllerDidPickFont(controller)
        }
    }
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

public protocol UIViewRepresentable: View, _ViewMetadataExtractionBoundary {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void

    typealias Context = UIViewRepresentableContext<Self>

    @MainActor func makeUIView(context: Context) -> UIViewType
    @MainActor func updateUIView(_ uiView: UIViewType, context: Context)
    @MainActor func makeCoordinator() -> Coordinator
    @MainActor static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator)
}

public extension UIViewRepresentable {
    var body: QuillUIViewRepresentableHostView<Self> {
        QuillUIViewRepresentableHostView(self)
    }

    @MainActor func makeCoordinator() -> Void {}

    @MainActor static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {}
}

// Keep UIKit identity stable across SwiftOpenUI body rebuilds, matching
// SwiftUI's make-once/update-many representable lifecycle.
@MainActor
private final class QuillUIViewRepresentableMount<R: UIViewRepresentable>: ObservableObject {
    let coordinator: R.Coordinator
    let uiView: R.UIViewType

    init(_ representable: R) {
        let coordinator = representable.makeCoordinator()
        let context = R.Context(coordinator: coordinator)
        self.coordinator = coordinator
        self.uiView = representable.makeUIView(context: context)
    }

    func hostedContent(updatingWith representable: R) -> AnyView? {
        let context = R.Context(coordinator: coordinator)
        representable.updateUIView(uiView, context: context)
        return quillFindHostedSwiftUIView(in: coordinator)
            ?? quillFindHostedSwiftUIView(in: uiView)
    }
}

/// Host view that lowers common UIKit representables into SwiftOpenUI-native
/// controls. This keeps source compatibility for apps that wrap UIKit inputs
/// in `UIViewRepresentable` while avoiding an app-specific rewrite.
public struct QuillUIViewRepresentableHostView<R: UIViewRepresentable>:
    View,
    _ViewMetadataExtractionBoundary
{
    let representable: R
    @StateObject private var mount: QuillUIViewRepresentableMount<R>

    init(_ representable: R) {
        self.representable = representable
        _mount = StateObject(wrappedValue: QuillUIViewRepresentableMount(representable))
    }

    public var body: some View {
        if let attributedText = quillFindBinding(
            in: representable,
            as: NSMutableAttributedString.self
        ) {
            QuillAttributedTextRepresentableEditor(text: attributedText)
        } else if let plainText = quillFindBinding(in: representable, as: String.self) {
            TextEditor(text: plainText)
        } else {
            if let hostedContent = mount.hostedContent(updatingWith: representable) {
                hostedContent
            } else {
                EmptyView()
            }
        }
    }
}

private struct QuillAttributedTextRepresentableEditor: View {
    let text: Binding<NSMutableAttributedString>

    var body: some View {
        TextEditor(text: Binding<String>(
            get: { text.wrappedValue.string },
            set: { newValue in
                guard text.wrappedValue.string != newValue else { return }
                text.wrappedValue = NSMutableAttributedString(string: newValue)
            },
            quillUIIdentity: text.quillUIIdentity
        ))
    }
}

private func quillFindBinding<Value>(
    in value: Any,
    as _: Value.Type,
    depth: Int = 0
) -> Binding<Value>? {
    if let binding = value as? Binding<Value> {
        return binding
    }
    guard depth < 4 else { return nil }

    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        if let binding = quillFindBinding(in: child.value, as: Value.self, depth: depth + 1) {
            return binding
        }
    }
    return nil
}

@MainActor
private func quillFindHostedSwiftUIView(in value: Any) -> AnyView? {
    var visitedObjects = Set<ObjectIdentifier>()
    return quillFindHostedSwiftUIView(in: value, depth: 0, visitedObjects: &visitedObjects)
}

@MainActor
private func quillFindHostedSwiftUIView(
    in value: Any,
    depth: Int,
    visitedObjects: inout Set<ObjectIdentifier>
) -> AnyView? {
    if let hosted = value as? any QuillHostedSwiftUIView {
        return hosted.quillHostedRootAnyView
    }
    guard depth < 6 else { return nil }

    if let uiView = value as? UIView {
        let id = ObjectIdentifier(uiView)
        guard visitedObjects.insert(id).inserted else { return nil }
        for subview in uiView.subviews {
            if let hosted = quillFindHostedSwiftUIView(
                in: subview,
                depth: depth + 1,
                visitedObjects: &visitedObjects
            ) {
                return hosted
            }
        }
        return nil
    }

    if let controller = value as? UIViewController {
        let id = ObjectIdentifier(controller)
        guard visitedObjects.insert(id).inserted else { return nil }
        if let view = controller.viewIfLoaded,
           let hosted = quillFindHostedSwiftUIView(
            in: view,
            depth: depth + 1,
            visitedObjects: &visitedObjects
           ) {
            return hosted
        }
        for child in controller.children {
            if let hosted = quillFindHostedSwiftUIView(
                in: child,
                depth: depth + 1,
                visitedObjects: &visitedObjects
            ) {
                return hosted
            }
        }
        return nil
    }

    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .class {
        let object = value as AnyObject
        let id = ObjectIdentifier(object)
        guard visitedObjects.insert(id).inserted else { return nil }
    }

    for child in mirror.children {
        if let hosted = quillFindHostedSwiftUIView(
            in: child.value,
            depth: depth + 1,
            visitedObjects: &visitedObjects
        ) {
            return hosted
        }
    }
    return nil
}
