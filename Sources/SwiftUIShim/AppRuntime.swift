// Canonical `@main App` entry for upstream `import SwiftUI` apps on Linux.
// Backend-agnostic: the manifest graph decides which renderer is importable
// (BackendQt only resolves under QUILLUI_LINUX_BACKEND=qt + QUILLUI_QT_GENERIC=1;
// BackendGTK4 under the gtk graph), so the same upstream source runs on either.
import QuillKit
import SwiftOpenUI
#if canImport(BackendQt)
import BackendQt
#elseif canImport(BackendGTK4)
@_implementationOnly import BackendGTK4
@_implementationOnly import QuillAppKitGTK
#endif

#if os(Linux)
public extension App {
    static func main() {
        QuillURLSessionFixtures.installIfConfigured()
        #if canImport(BackendQt)
        QtBackend().run(Self.self)
        #elseif canImport(BackendGTK4)
        _ = QuillAppKitGTKAutoInstall.didInstall
        GTK4Backend().run(Self.self)
        #endif
    }
}
#endif
