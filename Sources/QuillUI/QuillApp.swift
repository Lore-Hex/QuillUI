#if canImport(SwiftUI)
import SwiftUI
#else
import SwiftOpenUI
#endif

#if os(Linux)
import BackendGTK4
#endif

/// Shared scene builder for QuillUI executable targets.
///
/// Keeps app entry points visually aligned across native SwiftUI and
/// SwiftOpenUI by using the same `WindowGroup`, main-actor content bridge,
/// and platform-normalized default sizing helper everywhere.
public enum QuillAppWindow {
    public static func scene<Content: View>(
        _ title: String,
        width: Double,
        height: Double,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) -> some Scene {
        WindowGroup(title) {
            QuillMainActorView.assumeIsolated {
                content()
            }
        }
        .defaultSize(width: width, height: height)
    }
}

/// Standard entry-point shim every QuillUI app calls from its
/// `main.swift`. Dispatches to the platform-appropriate runtime:
/// on Linux the default is `BackendGTK4.GTK4Backend().run(A.self)`;
/// on Apple platforms it's the SwiftUI-native `App.main()`. Lets
/// the per-app `main.swift` end with a single line —
/// `QuillApp.run(QuillFooApp.self)` — instead of repeating the
/// same `#if os(Linux) ... #else ... #endif` block in every app
/// entry point.
/// Specialized launch surfaces such as `QuillQtApp` live in their
/// own backend targets while sharing the same launch-plan fallback
/// decisions through `QuillBackendRegistry`.
///
/// The function is plain synchronous so it can be called from
/// top-level `main.swift`. Linux enters SwiftOpenUI's GTK backend
/// from the main thread; Apple platforms hand control to the
/// native SwiftUI entry point directly.
public enum QuillApp {
    public static func run<A: App>(
        _ appType: A.Type,
        preferredBackend: QuillBackendIdentifier? = nil
    ) {
        MainActor.assumeIsolated {
            #if os(Linux)
            QuillLinuxAppRuntime.run(appType, preferredBackend: preferredBackend)
            #else
            A.main()
            #endif
        }
    }
}

/// Shared launcher for backend-specific facade targets such as
/// `QuillUIGtk` and `QuillUIQt`.
public enum QuillBackendApp<Backend: QuillBackend> {
    public static func run<A: App>(_ appType: A.Type) {
        QuillApp.run(appType, preferredBackend: Backend.identifier)
    }
}

public extension QuillBackend {
    static func run<A: App>(_ appType: A.Type) {
        QuillBackendApp<Self>.run(appType)
    }
}

#if os(Linux)
enum QuillLinuxRuntimeHost: CaseIterable {
    case gtk4

    static var supportedBackends: [QuillBackendIdentifier] {
        allCases.map(\.backendIdentifier)
    }

    static func supports(_ backend: QuillBackendIdentifier) -> Bool {
        Self(backend: backend) != nil
    }

    init?(backend: QuillBackendIdentifier) {
        switch backend {
        case .gtk:
            self = .gtk4
        case .swiftUI, .qt:
            return nil
        }
    }

    init(launchPlan: QuillBackendLaunchPlan) {
        guard let host = Self(backend: launchPlan.runtime) else {
            preconditionFailure(
                "No Linux runtime host is linked for \(launchPlan.runtime.rawValue); selected \(launchPlan.selected.rawValue)."
            )
        }

        self = host
    }

    var backendIdentifier: QuillBackendIdentifier {
        switch self {
        case .gtk4:
            return .gtk
        }
    }

    func run<A: App>(_ appType: A.Type) {
        switch self {
        case .gtk4:
            GTK4Backend().run(appType)
        }
    }
}

private enum QuillLinuxAppRuntime {
    static func run<A: App>(
        _ appType: A.Type,
        preferredBackend: QuillBackendIdentifier?
    ) {
        let launchPlan = QuillBackendRegistry.launchPlan(preferred: preferredBackend)
        QuillLinuxRuntimeHost(launchPlan: launchPlan).run(appType)
    }
}
#endif
