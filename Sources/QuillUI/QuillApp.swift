#if os(Linux)
import BackendGTK4
#endif

/// Standard entry-point shim every QuillUI app calls from its
/// `main.swift`. Dispatches to the platform-appropriate runtime:
/// on Linux that's `BackendGTK4.GTK4Backend().run(appType)`; on
/// Apple platforms it's the SwiftUI-native `App.main()`. Lets
/// the per-app `main.swift` end with a single line —
/// `QuillApp.run(QuillFooApp.self)` — instead of repeating the
/// same `#if os(Linux) ... #else ... #endif` block six times.
///
/// The function is `nonisolated` so it can be called from
/// top-level `main.swift` (which is a nonisolated synchronous
/// context). `MainActor.assumeIsolated` inside asserts the
/// runtime is on the main thread — which it always is for
/// `main.swift` — and gives synchronous access to the
/// `@MainActor` `App.main()` / `GTK4Backend().run(_:)` calls.
public enum QuillApp {
    public static func run<A: App>(_ appType: A.Type) {
        MainActor.assumeIsolated {
            #if os(Linux)
            GTK4Backend().run(appType)
            #else
            appType.main()
            #endif
        }
    }
}
