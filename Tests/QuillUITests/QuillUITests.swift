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

        #expect(QuillBackendRegistry.backendRequest(from: [:]) == .unspecified)
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": ""]) == .unspecified)
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": "Qt6"]) == .valid(.qt))
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": " GTK4 "]) == .valid(.gtk))
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": "unknown"]) == .invalid(rawValue: "unknown"))
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": " unknown "]).identifier == nil)
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": "\nunknown\t"]).invalidRawValue == "unknown")

        let backendWindowWidth = "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH"
        let gtkWindowWidth = "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"
        let qtWindowWidth = "QUILLUI_QT_DEFAULT_WINDOW_WIDTH"
        let scopedWindowEnvironment = [
            gtkWindowWidth: "1200",
            qtWindowWidth: "1400"
        ]
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: scopedWindowEnvironment,
                preferred: .gtk
            ) == "1200"
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: scopedWindowEnvironment,
                preferred: .qt
            ) == "1400"
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: scopedWindowEnvironment.merging(["QUILLUI_BACKEND": "gtk"], uniquingKeysWith: { lhs, _ in lhs }),
                preferred: .qt
            ) == "1200"
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: scopedWindowEnvironment.merging([backendWindowWidth: "1600"], uniquingKeysWith: { lhs, _ in lhs }),
                preferred: .qt
            ) == "1600"
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: [gtkWindowWidth: "1200"],
                preferred: .qt
            ) == nil
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: [qtWindowWidth: "1400"],
                preferred: .gtk
            ) == nil
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: [gtkWindowWidth: "1200", "QUILLUI_BACKEND": "qt"],
                preferred: .gtk
            ) == nil
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: [qtWindowWidth: "1400", "QUILLUI_BACKEND": "gtk"],
                preferred: .qt
            ) == nil
        )

        let identifiers = QuillBackendRegistry.knownBackends.map(\.identifier)
        #expect(identifiers == [.swiftUI, .gtk, .qt])
        #expect(QuillBackendRegistry.runtimeAvailabilities.map(\.selected) == identifiers)
        #expect(
            QuillBackendRegistry.runtimeAvailabilities.map(\.rowValues)
                == QuillBackendRegistry.runtimeAvailabilities.map { availability in
                    [
                        availability.selected.rawValue,
                        availability.runtime.rawValue,
                        availability.mode.rawValue
                    ]
                }
        )

        #if os(Linux)
        #expect(QuillBackendRegistry.platformDefault == .gtk)
        #expect(QuillBackendRegistry.platformRuntimeFallback == .gtk)
        #expect(QuillBackendRegistry.nativeRuntimeBackends == [.gtk])
        #expect(QuillBackendRegistry.nativeRuntimeBackends == QuillLinuxRuntimeHost.supportedBackends)
        #expect(QuillLinuxRuntimeHost.knownHosts == [.gtk4, .qt6])
        #expect(QuillLinuxRuntimeHost.knownDescriptors.map(\.host) == [.gtk4, .qt6])
        #expect(QuillLinuxRuntimeHost.knownDescriptors.map(\.backend) == [.gtk, .qt])
        #expect(QuillLinuxRuntimeHost.knownDescriptors.map(\.displayName) == ["GTK4", "Qt6"])
        #expect(QuillLinuxRuntimeHost.linkedHosts == [.gtk4])
        #expect(QuillLinuxRuntimeHost.linkedDescriptors == QuillLinuxRuntimeHost.descriptors)
        #expect(QuillLinuxRuntimeHost.descriptors.map(\.host) == [.gtk4])
        #expect(QuillLinuxRuntimeHost.descriptors.map(\.backend) == [.gtk])
        #expect(QuillLinuxRuntimeHost.descriptors.map(\.displayName) == ["GTK4"])
        #expect(QuillLinuxRuntimeHost.platformFallbackBackend == .gtk)
        #expect(QuillLinuxRuntimeHost.knownDescriptor(for: .gtk)?.host == .gtk4)
        #expect(QuillLinuxRuntimeHost.knownDescriptor(for: .qt)?.host == .qt6)
        #expect(QuillLinuxRuntimeHost.descriptor(for: .gtk)?.host == .gtk4)
        #expect(QuillLinuxRuntimeHost.descriptor(for: .qt) == nil)
        #expect(QuillLinuxRuntimeHost.supports(.gtk))
        #expect(!QuillLinuxRuntimeHost.supports(.qt))
        #expect(QuillLinuxRuntimeHost(backend: .gtk) != nil)
        #expect(QuillLinuxRuntimeHost(backend: .qt) == nil)
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
        #expect(qtDescriptor.runtimeAvailability == QuillBackendRegistry.runtimeAvailability(for: .qt))
        #expect(qtDescriptor.runtimeBackend == QuillBackendRegistry.platformRuntimeFallback)
        #expect(qtDescriptor.runtimeDescriptor.identifier == QuillBackendRegistry.platformRuntimeFallback)
        #expect(qtDescriptor.usesRuntimeFallback)
        #expect(qtDescriptor.runtimeMode == .platformFallback)
        #expect(qtDescriptor.runtimeSummary == QuillBackendRegistry.runtimeSummary(selected: .qt))
        #expect(qtDescriptor.runtimeSummary == qtDescriptor.runtimeAvailability.summary)
        #expect(qtDescriptor.runtimeSummary == QuillBackendRegistry.runtimeSummary(availability: qtDescriptor.runtimeAvailability))
        #expect(qtDescriptor.runtimeSummary.contains("Qt selected"))
        #expect(qtDescriptor.runtimeNotes.contains("product-specific Qt host"))
        #expect(!qtDescriptor.runtimeNotes.contains("not linked yet"))

        let gtkDescriptor = QuillBackendRegistry.descriptor(for: .gtk)
        #expect(gtkDescriptor.displayName == "GTK")
        #expect(gtkDescriptor.isExperimental == false)
        #expect(gtkDescriptor.runtimeSummary == QuillBackendRegistry.runtimeSummary(selected: .gtk))
        #expect(gtkDescriptor.runtimeSummary == gtkDescriptor.runtimeAvailability.summary)

        let preferredGtkPlan = QuillBackendRegistry.launchPlan(requested: nil, preferred: .gtk)
        #expect(preferredGtkPlan.request == .unspecified)
        #expect(preferredGtkPlan.selected == .gtk)
        #expect(preferredGtkPlan.selectedDescriptor == gtkDescriptor)
        #expect(preferredGtkPlan.statusMessage == gtkDescriptor.runtimeSummary)

        let environmentQtOverGtkPlan = QuillBackendRegistry.launchPlan(
            environment: ["QUILLUI_BACKEND": "qt"],
            preferred: .gtk
        )
        #expect(environmentQtOverGtkPlan.request == .valid(.qt))
        #expect(environmentQtOverGtkPlan.requested == .qt)
        #expect(environmentQtOverGtkPlan.preferred == .gtk)
        #expect(environmentQtOverGtkPlan.selected == .qt)

        let invalidEnvironmentPlan = QuillBackendRegistry.launchPlan(
            environment: ["QUILLUI_BACKEND": "bogus"],
            preferred: .gtk
        )
        #expect(invalidEnvironmentPlan.request == .invalid(rawValue: "bogus"))
        #expect(invalidEnvironmentPlan.requested == nil)
        #expect(invalidEnvironmentPlan.selected == .gtk)
        #expect(invalidEnvironmentPlan.requestStatusMessage == "Unsupported QUILLUI_BACKEND value \"bogus\"; using GTK.")
        #expect(invalidEnvironmentPlan.statusMessages == [
            "Unsupported QUILLUI_BACKEND value \"bogus\"; using GTK.",
            invalidEnvironmentPlan.statusMessage
        ])
        #expect(invalidEnvironmentPlan.displayMessage == invalidEnvironmentPlan.statusMessages.joined(separator: " "))

        let invalidRequestPlan = QuillBackendRegistry.launchPlan(
            request: .invalid(rawValue: "bogus"),
            preferred: .qt
        )
        #expect(invalidRequestPlan.request == .invalid(rawValue: "bogus"))
        #expect(invalidRequestPlan.requested == nil)
        #expect(invalidRequestPlan.selected == .qt)
        #expect(invalidRequestPlan.requestStatusMessage == "Unsupported QUILLUI_BACKEND value \"bogus\"; using Qt.")

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
        #expect(requestedQtOverGtkPlan.request == .valid(.qt))
        #expect(requestedQtOverGtkPlan.requested == .qt)
        #expect(requestedQtOverGtkPlan.preferred == .gtk)
        #expect(requestedQtOverGtkPlan.selected == .qt)
        #expect(requestedQtOverGtkPlan.selectedDescriptor == qtDescriptor)
        #expect(requestedQtOverGtkPlan.runtimeAvailability == qtDescriptor.runtimeAvailability)
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

        let requestedQtOverGtkStatus = QuillBackendRegistry.runtimeStatus(requested: .qt, preferred: .gtk)
        #expect(requestedQtOverGtkStatus.identifier == .gtk)
        #expect(requestedQtOverGtkStatus.launchPlan == requestedQtOverGtkPlan)
        #expect(requestedQtOverGtkStatus.selected == .qt)
        #expect(requestedQtOverGtkStatus.runtime == requestedQtOverGtkPlan.runtime)
        #expect(requestedQtOverGtkStatus.usesRuntimeFallback)

        let environmentGtkPlan = QuillBackendRegistry.launchPlan(preferred: .gtk)
        let environmentGtkStatus = QuillBackendRegistry.runtimeStatus(preferred: .gtk)
        #expect(QuillGtkBackend.descriptor == gtkDescriptor)
        #expect(QuillGtkBackend.launchPlan == environmentGtkPlan)
        #expect(QuillGtkBackend.launchPlan.preferred == .gtk)
        #expect(QuillGtkBackend.status == environmentGtkStatus)
        #expect(QuillGtkBackend.status.identifier == .gtk)
        #expect(QuillGtkBackend.status.launchPlan == environmentGtkPlan)
        #expect(QuillGtkBackend.status.requested == environmentGtkPlan.requested)
        #expect(QuillGtkBackend.status.preferred == environmentGtkPlan.preferred)
        #expect(QuillGtkBackend.status.selected == environmentGtkPlan.selected)
        #expect(QuillGtkBackend.status.runtime == environmentGtkPlan.runtime)
        #expect(QuillGtkBackend.status.selectedDescriptor == environmentGtkPlan.selectedDescriptor)
        #expect(QuillGtkBackend.status.runtimeDescriptor == environmentGtkPlan.runtimeDescriptor)
        #expect(QuillGtkBackend.status.runtimeAvailability == environmentGtkPlan.runtimeAvailability)
        #expect(QuillGtkBackend.status.usesRuntimeFallback == environmentGtkPlan.usesRuntimeFallback)
        #expect(QuillGtkBackend.status.hasNativeRuntime == environmentGtkPlan.runtimeAvailability.hasNativeRuntime)
        #expect(QuillGtkBackend.status.mode == environmentGtkPlan.runtimeMode)
        #expect(QuillGtkBackend.status.runtimeMessage == environmentGtkPlan.statusMessage)
        #expect(QuillGtkBackend.status.messages == environmentGtkPlan.statusMessages)
        #expect(QuillGtkBackend.status.message == environmentGtkPlan.statusMessage)

        let invalidGtkStatus = QuillBackendRegistry.runtimeStatus(
            environment: ["QUILLUI_BACKEND": "bogus"],
            preferred: .gtk
        )
        #expect(invalidGtkStatus.identifier == .gtk)
        #expect(invalidGtkStatus.launchPlan == invalidEnvironmentPlan)
        #expect(invalidGtkStatus.requested == invalidEnvironmentPlan.requested)
        #expect(invalidGtkStatus.preferred == invalidEnvironmentPlan.preferred)
        #expect(invalidGtkStatus.selected == invalidEnvironmentPlan.selected)
        #expect(invalidGtkStatus.runtime == invalidEnvironmentPlan.runtime)
        #expect(invalidGtkStatus.runtimeAvailability == invalidEnvironmentPlan.runtimeAvailability)
        #expect(invalidGtkStatus.usesRuntimeFallback == invalidEnvironmentPlan.usesRuntimeFallback)
        #expect(invalidGtkStatus.hasNativeRuntime == invalidEnvironmentPlan.runtimeAvailability.hasNativeRuntime)
        #expect(invalidGtkStatus.runtimeMessage == invalidEnvironmentPlan.statusMessage)
        #expect(invalidGtkStatus.messages == invalidEnvironmentPlan.statusMessages)
        #expect(invalidGtkStatus.message == invalidEnvironmentPlan.displayMessage)

        let preferredQtPlan = QuillBackendRegistry.launchPlan(requested: nil, preferred: .qt)
        #expect(preferredQtPlan.selected == .qt)
        #expect(preferredQtPlan.selectedDescriptor == qtDescriptor)
        #expect(preferredQtPlan.runtimeMode == .platformFallback)
        #expect(preferredQtPlan.runtimeAvailability.mode == .platformFallback)

        #if os(Linux)
        #expect(preferredQtPlan.runtime == .gtk)
        #expect(preferredQtPlan.runtimeDescriptor.identifier == .gtk)
        #expect(QuillBackendRegistry.runtimeAvailabilities == [
            QuillBackendRuntimeAvailability(selected: .swiftUI, runtime: .gtk),
            QuillBackendRuntimeAvailability(selected: .gtk, runtime: .gtk),
            QuillBackendRuntimeAvailability(selected: .qt, runtime: .gtk)
        ])
        #expect(QuillBackendRegistry.runtimeAvailabilities.map(\.tabSeparatedRow) == [
            "swiftui\tgtk\tplatformFallback",
            "gtk\tgtk\tnative",
            "qt\tgtk\tplatformFallback"
        ])
        #else
        #expect(preferredQtPlan.runtime == .swiftUI)
        #expect(preferredQtPlan.runtimeDescriptor.identifier == .swiftUI)
        #expect(QuillBackendRegistry.runtimeAvailabilities == [
            QuillBackendRuntimeAvailability(selected: .swiftUI, runtime: .swiftUI),
            QuillBackendRuntimeAvailability(selected: .gtk, runtime: .swiftUI),
            QuillBackendRuntimeAvailability(selected: .qt, runtime: .swiftUI)
        ])
        #expect(QuillBackendRegistry.runtimeAvailabilities.map(\.tabSeparatedRow) == [
            "swiftui\tswiftui\tnative",
            "gtk\tswiftui\tplatformFallback",
            "qt\tswiftui\tplatformFallback"
        ])
        #endif

        #expect(preferredQtPlan.usesRuntimeFallback)
        #expect(preferredQtPlan.statusMessage.contains("Qt selected"))
        #expect(preferredQtPlan.statusMessage == qtDescriptor.runtimeSummary)
        let environmentQtPlan = QuillBackendRegistry.launchPlan(preferred: .qt)
        let environmentQtStatus = QuillBackendRegistry.runtimeStatus(preferred: .qt)
        #expect(QuillQtBackend.descriptor == qtDescriptor)
        #expect(QuillQtBackend.launchPlan == environmentQtPlan)
        #expect(QuillQtBackend.launchPlan.preferred == .qt)
        #expect(QuillQtBackend.status == environmentQtStatus)
        #expect(QuillQtBackend.status.identifier == .qt)
        #expect(QuillQtBackend.status.launchPlan == environmentQtPlan)
        #expect(QuillQtBackend.status.requested == environmentQtPlan.requested)
        #expect(QuillQtBackend.status.preferred == environmentQtPlan.preferred)
        #expect(QuillQtBackend.status.selected == environmentQtPlan.selected)
        #expect(QuillQtBackend.status.runtime == environmentQtPlan.runtime)
        #expect(QuillQtBackend.status.selectedDescriptor == environmentQtPlan.selectedDescriptor)
        #expect(QuillQtBackend.status.runtimeDescriptor == environmentQtPlan.runtimeDescriptor)
        #expect(QuillQtBackend.status.runtimeAvailability == environmentQtPlan.runtimeAvailability)
        #expect(QuillQtBackend.status.usesRuntimeFallback == environmentQtPlan.usesRuntimeFallback)
        #expect(QuillQtBackend.status.hasNativeRuntime == environmentQtPlan.runtimeAvailability.hasNativeRuntime)
        #expect(QuillQtBackend.status.mode == environmentQtPlan.runtimeMode)
        #expect(QuillQtBackend.status.runtimeMessage == environmentQtPlan.statusMessage)
        #expect(QuillQtBackend.status.messages == environmentQtPlan.statusMessages)
        #expect(QuillQtBackend.status.message == environmentQtPlan.statusMessage)
    }
}
