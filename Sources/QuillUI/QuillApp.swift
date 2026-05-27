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
public enum QuillAppDefaultSizePolicy: Equatable, Sendable {
    case requested
    case linuxAppMinimum
    case linuxMinimum(width: Double, height: Double)
}

public enum QuillAppWindow {
    public static func scene<Content: View>(
        _ title: String,
        width: Double,
        height: Double,
        defaultSizePolicy: QuillAppDefaultSizePolicy = .linuxAppMinimum,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) -> some Scene {
        let defaultSize = resolvedDefaultSize(
            width: width,
            height: height,
            policy: defaultSizePolicy
        )

        return WindowGroup(title) {
            QuillMainActorView.assumeIsolated {
                content()
            }
        }
        .defaultSize(width: defaultSize.width, height: defaultSize.height)
    }

    private static func resolvedDefaultSize(
        width: Double,
        height: Double,
        policy: QuillAppDefaultSizePolicy
    ) -> (width: Double, height: Double) {
        #if os(Linux)
        switch policy {
        case .linuxAppMinimum:
            return (max(width, 900), max(height, 600))
        case let .linuxMinimum(minimumWidth, minimumHeight):
            return (max(width, minimumWidth), max(height, minimumHeight))
        case .requested:
            return (width, height)
        }
        #else
        return (width, height)
        #endif
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
        let appTypeBox = QuillUncheckedSendableAppType(appType: appType)
        QuillBackendRuntimeContext.install(launchPlan)

        MainActor.assumeIsolated {
            #if os(Linux)
            QuillLinuxAppRuntime.run(appTypeBox.appType, launchPlan: launchPlan)
            #else
            A.main()
            #endif
        }
    }
}

private struct QuillUncheckedSendableAppType<A: App>: @unchecked Sendable {
    let appType: A.Type
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
    case qt6

    static let linkedHosts: [QuillLinuxRuntimeHost] = [.gtk4]

    static var knownHosts: [QuillLinuxRuntimeHost] {
        allCases
    }

    static var knownDescriptors: [QuillLinuxRuntimeHostDescriptor] {
        knownHosts.map(\.descriptor)
    }

    static var linkedDescriptors: [QuillLinuxRuntimeHostDescriptor] {
        linkedHosts.map(\.descriptor)
    }

    static var descriptors: [QuillLinuxRuntimeHostDescriptor] {
        linkedDescriptors
    }

    static var supportedBackends: [QuillBackendIdentifier] {
        linkedDescriptors.map(\.backend)
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
        linkedDescriptors.first { $0.backend == backend }
    }

    static func knownDescriptor(
        for backend: QuillBackendIdentifier
    ) -> QuillLinuxRuntimeHostDescriptor? {
        knownDescriptors.first { $0.backend == backend }
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
        case .qt6:
            return QuillLinuxRuntimeHostDescriptor(
                host: self,
                backend: .qt,
                displayName: "Qt6"
            )
        }
    }

    var backendIdentifier: QuillBackendIdentifier {
        descriptor.backend
    }

    func run<A: App>(_ appType: A.Type) {
        switch self {
        case .gtk4:
            QuillGTKButtonPaintAdapter.install()
            GTK4Backend().run(appType)
        case .qt6:
            preconditionFailure("Native Qt6 Linux runtime host is declared but not linked.")
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
