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
/// same `#if os(Linux) ... #else ... #endif` block six times.
/// Specialized launch surfaces such as `QuillQtApp` live in their
/// own backend targets while sharing `QuillBackendRegistry`.
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

#if os(Linux)
private enum QuillLinuxAppRuntime {
    static func run<A: App>(
        _ appType: A.Type,
        preferredBackend: QuillBackendIdentifier?
    ) {
        let launchPlan = QuillBackendRegistry.launchPlan(preferred: preferredBackend)

        switch launchPlan.runtime {
        case .swiftUI, .gtk, .qt:
            GTK4Backend().run(appType)
        }
    }
}
#endif
