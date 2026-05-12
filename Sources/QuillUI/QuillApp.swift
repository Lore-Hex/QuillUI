#if os(Linux)
import BackendGTK4
#endif

/// Standard entry-point shim every QuillUI app calls from its
/// `main.swift`. Dispatches to the platform-appropriate runtime:
/// on Linux that's `BackendGTK4.GTK4Backend().run(A.self)`; on
/// Apple platforms it's the SwiftUI-native `App.main()`. Lets
/// the per-app `main.swift` end with a single line —
/// `QuillApp.run(QuillFooApp.self)` — instead of repeating the
/// same `#if os(Linux) ... #else ... #endif` block six times.
///
/// The function is plain synchronous so it can be called from
/// top-level `main.swift`. Linux enters SwiftOpenUI's GTK backend
/// from the main thread; Apple platforms hand control to the
/// native SwiftUI entry point directly.
public enum QuillApp {
    public static func run<A: App>(_: A.Type) {
        MainActor.assumeIsolated {
            #if os(Linux)
            GTK4Backend().run(A.self)
            #else
            A.main()
            #endif
        }
    }
}
