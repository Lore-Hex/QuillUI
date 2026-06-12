#if os(Linux)
#if QUILLUI_SWIFTUI_QT_MOUNT
@_implementationOnly import BackendQt
#else
import QuillUI
#endif

// App.main() — Apple ships this in SwiftUI (an `App` extension the `@main`
// attribute resolves), so it lives in the SwiftUI shim. On Apple platforms
// the real SwiftUI provides it; this file is Linux-only.

extension App {
    /// SwiftUI's `App.main()`: the entry point `@main` requires on an
    /// unmodified upstream app type (`@main struct FooApp: App`). Dispatches
    /// to the shared QuillApp launcher, which enters the platform backend
    /// (GTK on QuillOS Linux) on the main thread.
    @MainActor
    public static func main() {
        #if QUILLUI_SWIFTUI_QT_MOUNT
        QtBackend().run(Self.self)
        #else
        QuillApp.run(Self.self)
        #endif
    }
}
#endif
