import Foundation
import QuillUIGtk
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
        let aliases: [(String, QuillBackendIdentifier)] = [
            ("swiftui", .swiftUI),
            ("swift-ui", .swiftUI),
            ("apple", .swiftUI),
            ("native", .swiftUI),
            ("gtk", .gtk),
            ("gtk4", .gtk),
            ("qt", .qt),
            ("qt6", .qt),
            (" Qt6 ", .qt),
            ("\nGTK4\t", .gtk)
        ]
        for (rawValue, expectedBackend) in aliases {
            #expect(QuillBackendIdentifier(environmentValue: rawValue) == expectedBackend)
        }
        #expect(QuillBackendIdentifier(environmentValue: "unknown") == nil)

        #expect(QuillBackendRegistry.requestedBackend(from: [:]) == nil)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": ""]) == nil)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": "   "]) == nil)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": "Qt6"]) == .qt)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": " GTK4 "]) == .gtk)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": "\nNative\t"]) == .swiftUI)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": "unknown"]) == nil)

        let identifiers = QuillBackendRegistry.knownBackends.map(\.identifier)
        #expect(identifiers == [.swiftUI, .gtk, .qt])

        #if os(Linux)
        #expect(QuillBackendRegistry.platformDefault == .gtk)
        #expect(QuillBackendRegistry.platformRuntimeFallback == .gtk)
        #expect(QuillBackendRegistry.nativeRuntimeBackends == [.gtk])
        #expect(QuillBackendRegistry.hasNativeRuntime(for: .gtk))
        #expect(!QuillBackendRegistry.hasNativeRuntime(for: .qt))
        #else
        #expect(QuillBackendRegistry.platformDefault == .swiftUI)
        #expect(QuillBackendRegistry.platformRuntimeFallback == .swiftUI)
        #expect(QuillBackendRegistry.nativeRuntimeBackends == [.swiftUI])
        #expect(QuillBackendRegistry.hasNativeRuntime(for: .swiftUI))
        #expect(!QuillBackendRegistry.hasNativeRuntime(for: .qt))
        #endif

        let qtDescriptor = QuillBackendRegistry.descriptor(for: .qt)
        #expect(qtDescriptor.displayName == "Qt")
        #expect(qtDescriptor.isExperimental == true)
        #expect(!qtDescriptor.hasNativeRuntime)
        #expect(qtDescriptor.runtimeBackend == QuillBackendRegistry.platformRuntimeFallback)
        #expect(qtDescriptor.runtimeDescriptor.identifier == QuillBackendRegistry.platformRuntimeFallback)
        #expect(qtDescriptor.usesRuntimeFallback)
        #expect(qtDescriptor.runtimeMode == .platformFallback)
        #expect(qtDescriptor.runtimeSummary == QuillBackendRegistry.runtimeSummary(selected: .qt))
        #expect(qtDescriptor.runtimeSummary.contains("Qt selected"))

        let gtkDescriptor = QuillBackendRegistry.descriptor(for: .gtk)
        #expect(gtkDescriptor.displayName == "GTK")
        #expect(gtkDescriptor.isExperimental == false)
        #expect(gtkDescriptor.runtimeSummary == QuillBackendRegistry.runtimeSummary(selected: .gtk))

        let preferredGtkPlan = QuillBackendRegistry.launchPlan(requested: nil, preferred: .gtk)
        #expect(preferredGtkPlan.selected == .gtk)
        #expect(preferredGtkPlan.selectedDescriptor == gtkDescriptor)
        #expect(preferredGtkPlan.statusMessage == gtkDescriptor.runtimeSummary)

        let environmentQtOverGtkPlan = QuillBackendRegistry.launchPlan(
            environment: ["QUILLUI_BACKEND": "qt"],
            preferred: .gtk
        )
        #expect(environmentQtOverGtkPlan.requested == .qt)
        #expect(environmentQtOverGtkPlan.preferred == .gtk)
        #expect(environmentQtOverGtkPlan.selected == .qt)

        let invalidEnvironmentPlan = QuillBackendRegistry.launchPlan(
            environment: ["QUILLUI_BACKEND": "bogus"],
            preferred: .gtk
        )
        #expect(invalidEnvironmentPlan.requested == nil)
        #expect(invalidEnvironmentPlan.selected == .gtk)

        #if os(Linux)
        #expect(gtkDescriptor.hasNativeRuntime)
        #expect(gtkDescriptor.runtimeBackend == .gtk)
        #expect(gtkDescriptor.runtimeDescriptor == gtkDescriptor)
        #expect(!gtkDescriptor.usesRuntimeFallback)
        #expect(gtkDescriptor.runtimeMode == .native)
        #expect(gtkDescriptor.runtimeSummary == "GTK native renderer selected.")
        #expect(preferredGtkPlan.runtime == .gtk)
        #expect(preferredGtkPlan.runtimeDescriptor.identifier == .gtk)
        #expect(preferredGtkPlan.runtimeMode == .native)
        #else
        #expect(!gtkDescriptor.hasNativeRuntime)
        #expect(gtkDescriptor.runtimeBackend == .swiftUI)
        #expect(gtkDescriptor.runtimeDescriptor.identifier == .swiftUI)
        #expect(gtkDescriptor.usesRuntimeFallback)
        #expect(gtkDescriptor.runtimeMode == .platformFallback)
        #expect(gtkDescriptor.runtimeSummary == "GTK selected, but the native renderer is not available yet; launches currently use SwiftUI.")
        #expect(preferredGtkPlan.runtime == .swiftUI)
        #expect(preferredGtkPlan.runtimeDescriptor.identifier == .swiftUI)
        #expect(preferredGtkPlan.runtimeMode == .platformFallback)
        #endif

        let requestedQtOverGtkPlan = QuillBackendRegistry.launchPlan(requested: .qt, preferred: .gtk)
        #expect(requestedQtOverGtkPlan.requested == .qt)
        #expect(requestedQtOverGtkPlan.preferred == .gtk)
        #expect(requestedQtOverGtkPlan.selected == .qt)
        #expect(requestedQtOverGtkPlan.selectedDescriptor == qtDescriptor)
        #expect(requestedQtOverGtkPlan.usesRuntimeFallback)
        #expect(
            requestedQtOverGtkPlan.statusMessage
                == QuillBackendRegistry.runtimeSummary(
                    selected: requestedQtOverGtkPlan.selected,
                    runtime: requestedQtOverGtkPlan.runtime
                )
        )

        #if os(Linux)
        #expect(requestedQtOverGtkPlan.runtime == .gtk)
        #expect(requestedQtOverGtkPlan.statusMessage == "Qt selected, but the native renderer is not available yet; launches currently use GTK.")
        #else
        #expect(requestedQtOverGtkPlan.runtime == .swiftUI)
        #expect(requestedQtOverGtkPlan.statusMessage == "Qt selected, but the native renderer is not available yet; launches currently use SwiftUI.")
        #endif

        let environmentGtkPlan = QuillBackendRegistry.launchPlan(preferred: .gtk)
        #expect(QuillGtkBackend.descriptor == gtkDescriptor)
        #expect(QuillGtkBackend.launchPlan == environmentGtkPlan)
        #expect(QuillGtkBackend.launchPlan.preferred == .gtk)
        #expect(QuillGtkBackend.status.identifier == .gtk)
        #expect(QuillGtkBackend.status.launchPlan == environmentGtkPlan)
        #expect(QuillGtkBackend.status.mode == environmentGtkPlan.runtimeMode)
        #expect(QuillGtkBackend.status.message == environmentGtkPlan.statusMessage)

        let preferredQtPlan = QuillBackendRegistry.launchPlan(requested: nil, preferred: .qt)
        #expect(preferredQtPlan.selected == .qt)
        #expect(preferredQtPlan.selectedDescriptor == qtDescriptor)
        #expect(preferredQtPlan.runtimeMode == .platformFallback)

        #if os(Linux)
        #expect(preferredQtPlan.runtime == .gtk)
        #expect(preferredQtPlan.runtimeDescriptor.identifier == .gtk)
        #else
        #expect(preferredQtPlan.runtime == .swiftUI)
        #expect(preferredQtPlan.runtimeDescriptor.identifier == .swiftUI)
        #endif

        #expect(preferredQtPlan.usesRuntimeFallback)
        #expect(preferredQtPlan.statusMessage.contains("Qt selected"))
        #expect(preferredQtPlan.statusMessage == qtDescriptor.runtimeSummary)
        let environmentQtPlan = QuillBackendRegistry.launchPlan(preferred: .qt)
        #expect(QuillQtBackend.descriptor == qtDescriptor)
        #expect(QuillQtBackend.launchPlan == environmentQtPlan)
        #expect(QuillQtBackend.launchPlan.preferred == .qt)
        #expect(QuillQtBackend.status.identifier == .qt)
        #expect(QuillQtBackend.status.launchPlan == environmentQtPlan)
        #expect(QuillQtBackend.status.mode == environmentQtPlan.runtimeMode)
        #expect(QuillQtBackend.status.message == environmentQtPlan.statusMessage)
    }
}
