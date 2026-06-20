#if os(Linux)
import Testing
import SwiftUI
import UIKit

@MainActor
struct UIViewRepresentableMountTests {
    @Test func representableDefaultBodyIsTheUIKitHost() {
        struct Probe: UIViewRepresentable {
            func makeUIView(context: Context) -> UIView { UIView() }
            func updateUIView(_ uiView: UIView, context: Context) {}
        }

        let body = Probe().body
        #expect(String(describing: type(of: body)).contains("QuillUIViewRepresentableHostView"))
    }

    @Test func controllerRepresentableDefaultBodyIsTheUIKitControllerHost() {
        struct Probe: UIViewControllerRepresentable {
            func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
            func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
        }

        let body = Probe().body
        #expect(String(describing: type(of: body)).contains("QuillUIViewControllerRepresentableHostView"))
    }

    @Test func coordinatorPatternCompilesAndFlows() {
        final class Delegate { var pinged = false }

        struct Probe: UIViewRepresentable {
            func makeCoordinator() -> Delegate { Delegate() }
            func makeUIView(context: Context) -> UIView {
                context.coordinator.pinged = true
                return UIView()
            }
            func updateUIView(_ uiView: UIView, context: Context) {}
        }

        let probe = Probe()
        let coordinator = probe.makeCoordinator()
        let context = UIViewRepresentableContext<Probe>(coordinator: coordinator)
        _ = probe.makeUIView(context: context)
        #expect(coordinator.pinged)
    }

    @Test func uiHostingControllerContentSurvivesThroughRepresentableScrollContainer() {
        @MainActor
        final class Coordinator {
            let hostingController = UIHostingController(rootView: Text("Before update"))
        }

        struct Probe: UIViewRepresentable {
            func makeCoordinator() -> Coordinator { Coordinator() }
            func makeUIView(context: Context) -> UIScrollView {
                let scrollView = UIScrollView()
                scrollView.addSubview(context.coordinator.hostingController.view)
                return scrollView
            }
            func updateUIView(_ uiView: UIScrollView, context: Context) {
                context.coordinator.hostingController.rootView = Text("After update")
            }
        }

        #expect(String(describing: type(of: UIHostingController(rootView: Text("Probe")).view!))
            .contains("QuillUIHostingUIView"))
        #expect(quillContainsAnyViewWrappingText(Probe().body.body))
    }

    @Test func controllerCoordinatorPatternCompilesAndFlows() {
        final class Delegate { var pinged = false }

        struct Probe: UIViewControllerRepresentable {
            func makeCoordinator() -> Delegate { Delegate() }
            func makeUIViewController(context: Context) -> UIViewController {
                context.coordinator.pinged = true
                return UIViewController()
            }
            func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
        }

        let probe = Probe()
        let coordinator = probe.makeCoordinator()
        let context = UIViewControllerRepresentableContext<Probe>(coordinator: coordinator)
        _ = probe.makeUIViewController(context: context)
        #expect(coordinator.pinged)
    }
}

@MainActor
private func quillContainsAnyViewWrappingText(_ value: Any, depth: Int = 0) -> Bool {
    guard depth < 8 else { return false }
    if let anyView = value as? AnyView {
        return String(describing: type(of: anyView.wrapped)).contains("Text")
            || quillContainsAnyViewWrappingText(anyView.wrapped, depth: depth + 1)
    }
    for child in Mirror(reflecting: value).children {
        if quillContainsAnyViewWrappingText(child.value, depth: depth + 1) {
            return true
        }
    }
    return false
}
#endif
