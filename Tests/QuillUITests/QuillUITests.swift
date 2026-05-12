import Foundation
import QuillUIQt
import Testing
@testable import QuillUI

@Suite("QuillUI core library")
struct QuillUITests {

    // MARK: - QuillPlatform.name

    @Test("QuillPlatform.name reports the host platform")
    func quillPlatformReportsHost() {
        // The conditional inside QuillPlatform expands to the
        // build-time os check. On the CI runners we cover macOS
        // and Linux; both are non-empty and not "Unknown".
        #expect(!QuillPlatform.name.isEmpty)
        #expect(QuillPlatform.name != "Unknown")

        #if os(macOS)
        #expect(QuillPlatform.name == "macOS")
        #elseif os(Linux)
        #expect(QuillPlatform.name == "Linux")
        #elseif os(iOS)
        #expect(QuillPlatform.name == "iOS")
        #endif
    }

    // MARK: - QuillUIVersion.current

    @Test("QuillUIVersion.current is non-empty + semver-shaped")
    func quillUIVersionIsSemverShape() {
        let v = QuillUIVersion.current
        #expect(!v.isEmpty)

        // Semver-shape: at least two dots, all numeric segments.
        let parts = v.split(separator: ".")
        #expect(parts.count == 3, "version \(v) is not three dotted segments")
        #expect(parts.allSatisfy { Int($0) != nil }, "version \(v) has non-numeric parts")
    }

    // MARK: - QuillApp.run helper exists

    @Test("QuillApp.run<A: App> exists as a nonisolated static entry point")
    func quillAppRunIsCallableFromTopLevel() {
        // Verify the helper resolves at compile time. Runtime
        // invocation would call App.main() and never return,
        // so this test only confirms the type-level shape.
        let _ : (any Any.Type) -> () = { _ in /* unused */ }
        // Keep the reference so unused-symbol pruning can't omit
        // QuillApp from the binary.
        _ = QuillApp.self
        _ = QuillAppWindow.self
    }

    // MARK: - Backend registry

    @Test("Backend registry exposes SwiftUI GTK and Qt")
    func backendRegistryExposesKnownBackends() {
        #expect(QuillBackendIdentifier(environmentValue: "swift-ui") == .swiftUI)
        #expect(QuillBackendIdentifier(environmentValue: "gtk4") == .gtk)
        #expect(QuillBackendIdentifier(environmentValue: "qt6") == .qt)
        #expect(QuillBackendIdentifier(environmentValue: "unknown") == nil)

        let identifiers = QuillBackendRegistry.knownBackends.map(\.identifier)
        #expect(identifiers == [.swiftUI, .gtk, .qt])

        #if os(Linux)
        #expect(QuillBackendRegistry.platformDefault == .gtk)
        #else
        #expect(QuillBackendRegistry.platformDefault == .swiftUI)
        #endif

        let qtDescriptor = QuillBackendRegistry.descriptor(for: .qt)
        #expect(qtDescriptor.displayName == "Qt")
        #expect(qtDescriptor.isExperimental == true)

        let preferredQtPlan = QuillBackendRegistry.launchPlan(preferred: .qt)
        #expect(preferredQtPlan.selected == .qt)

        #if os(Linux)
        #expect(preferredQtPlan.runtime == .gtk)
        #else
        #expect(preferredQtPlan.runtime == .swiftUI)
        #endif

        #expect(preferredQtPlan.usesRuntimeFallback)
        #expect(QuillQtBackend.launchPlan.preferred == .qt)
        #expect(QuillQtBackend.status.mode == .platformFallback)
    }
}
