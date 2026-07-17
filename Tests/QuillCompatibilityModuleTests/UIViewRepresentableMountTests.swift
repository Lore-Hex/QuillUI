#if os(Linux)
import Testing
import SwiftUI
import UIKit

@MainActor
private final class HostedLifecycleCoordinator {
    let hostingController = UIHostingController(rootView: Text("Initial"))
}

@MainActor
private struct HostedLifecycleProbe: UIViewRepresentable {
    static var makeCount = 0
    static var updateCount = 0
    static var coordinatorIDs: [ObjectIdentifier] = []
    static var viewIDs: [ObjectIdentifier] = []

    func makeCoordinator() -> HostedLifecycleCoordinator {
        Self.makeCount += 1
        return HostedLifecycleCoordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.addSubview(context.coordinator.hostingController.view)
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        Self.updateCount += 1
        Self.coordinatorIDs.append(ObjectIdentifier(context.coordinator))
        Self.viewIDs.append(ObjectIdentifier(uiView))
        context.coordinator.hostingController.rootView = Text("Update \(Self.updateCount)")
    }

    static func reset() {
        makeCount = 0
        updateCount = 0
        coordinatorIDs = []
        viewIDs = []
    }
}

@MainActor
private final class ControllerLifecycleCoordinator {}

@MainActor
private struct ControllerLifecycleProbe: UIViewControllerRepresentable {
    static var makeCount = 0
    static var updateCount = 0
    static var coordinatorIDs: [ObjectIdentifier] = []
    static var controllerIDs: [ObjectIdentifier] = []

    func makeCoordinator() -> ControllerLifecycleCoordinator {
        Self.makeCount += 1
        return ControllerLifecycleCoordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        Self.updateCount += 1
        Self.coordinatorIDs.append(ObjectIdentifier(context.coordinator))
        Self.controllerIDs.append(ObjectIdentifier(uiViewController))
    }

    static func reset() {
        makeCount = 0
        updateCount = 0
        coordinatorIDs = []
        controllerIDs = []
    }
}

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

    @Test func restoredUIViewRepresentableMountReusesCoordinatorAndView() throws {
        HostedLifecycleProbe.reset()

        let firstHost = HostedLifecycleProbe().body
        #expect(HostedLifecycleProbe.makeCount == 0)
        let firstStorage = try #require(quillStateStorage(in: firstHost))
        #expect(quillContainsAnyViewWrappingText(firstHost.body))

        let secondHost = HostedLifecycleProbe().body
        #expect(HostedLifecycleProbe.makeCount == 1)
        let secondStorage = try #require(quillStateStorage(in: secondHost))
        secondStorage.anyStorage.restoreValue(from: firstStorage.anyStorage)
        #expect(quillContainsAnyViewWrappingText(secondHost.body))

        #expect(HostedLifecycleProbe.makeCount == 1)
        #expect(HostedLifecycleProbe.updateCount == 2)
        #expect(Set(HostedLifecycleProbe.coordinatorIDs).count == 1)
        #expect(Set(HostedLifecycleProbe.viewIDs).count == 1)
    }

    @Test func restoredUIViewControllerRepresentableMountReusesCoordinatorAndController() throws {
        ControllerLifecycleProbe.reset()

        let firstHost = ControllerLifecycleProbe().body
        #expect(ControllerLifecycleProbe.makeCount == 0)
        let firstStorage = try #require(quillStateStorage(in: firstHost))
        _ = firstHost.body

        let secondHost = ControllerLifecycleProbe().body
        #expect(ControllerLifecycleProbe.makeCount == 1)
        let secondStorage = try #require(quillStateStorage(in: secondHost))
        secondStorage.anyStorage.restoreValue(from: firstStorage.anyStorage)
        _ = secondHost.body

        #expect(ControllerLifecycleProbe.makeCount == 1)
        #expect(ControllerLifecycleProbe.updateCount == 2)
        #expect(Set(ControllerLifecycleProbe.coordinatorIDs).count == 1)
        #expect(Set(ControllerLifecycleProbe.controllerIDs).count == 1)
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

private func quillStateStorage(in value: Any) -> AnyStateStorageProvider? {
    Mirror(reflecting: value).children
        .compactMap { $0.value as? AnyStateStorageProvider }
        .first
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
