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
        let launchPlan = QuillBackendRegistry.launchPlan(preferred: preferredBackend)
        QuillBackendRuntimeContext.install(launchPlan)

        MainActor.assumeIsolated {
            #if os(Linux)
            QuillLinuxAppRuntime.run(appType, launchPlan: launchPlan)
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
struct QuillLinuxRuntimeHostDescriptor: Equatable, Sendable {
    let host: QuillLinuxRuntimeHost
    let backend: QuillBackendIdentifier
    let displayName: String
}

enum QuillLinuxRuntimeHost: CaseIterable, Sendable {
    case gtk4

    static let linkedHosts: [QuillLinuxRuntimeHost] = [.gtk4]

    static var descriptors: [QuillLinuxRuntimeHostDescriptor] {
        linkedHosts.map(\.descriptor)
    }

    static var supportedBackends: [QuillBackendIdentifier] {
        descriptors.map(\.backend)
    }

    static var platformFallbackBackend: QuillBackendIdentifier {
        guard let backend = supportedBackends.first else {
            preconditionFailure("No Linux runtime host is linked.")
        }

        return backend
    }

    static func descriptor(
        for backend: QuillBackendIdentifier
    ) -> QuillLinuxRuntimeHostDescriptor? {
        descriptors.first { $0.backend == backend }
    }

    static func supports(_ backend: QuillBackendIdentifier) -> Bool {
        descriptor(for: backend) != nil
    }

    init?(backend: QuillBackendIdentifier) {
        guard let host = Self.descriptor(for: backend)?.host else {
            return nil
        }

        self = host
    }

    init(launchPlan: QuillBackendLaunchPlan) {
        guard let host = Self(backend: launchPlan.runtime) else {
            preconditionFailure(
                "No Linux runtime host is linked for \(launchPlan.runtime.rawValue); selected \(launchPlan.selected.rawValue)."
            )
        }

        self = host
    }

    var descriptor: QuillLinuxRuntimeHostDescriptor {
        switch self {
        case .gtk4:
            return QuillLinuxRuntimeHostDescriptor(
                host: self,
                backend: .gtk,
                displayName: "GTK4"
            )
        }
    }

    var backendIdentifier: QuillBackendIdentifier {
        descriptor.backend
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
        launchPlan: QuillBackendLaunchPlan
    ) {
        QuillLinuxRuntimeHost(launchPlan: launchPlan).run(appType)
    }
}
#endif
