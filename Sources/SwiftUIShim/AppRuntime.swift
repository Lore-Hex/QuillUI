// Canonical `@main App` entry for upstream `import SwiftUI` apps on Linux.
// Backend-agnostic: the manifest graph decides which renderer is importable
// (BackendQt only resolves under QUILLUI_LINUX_BACKEND=qt + QUILLUI_QT_GENERIC=1;
// BackendGTK4 under the gtk graph), so the same upstream source runs on either.
import SwiftOpenUI
#if canImport(BackendQt)
import BackendQt
#elseif canImport(BackendGTK4)
import BackendGTK4
#endif

#if os(Linux)
public extension App {
    static func main() {
        #if canImport(BackendQt)
        QtBackend().run(Self.self)
        #elseif canImport(BackendGTK4)
        GTK4Backend().run(Self.self)
        #endif
    }
}
#endif
