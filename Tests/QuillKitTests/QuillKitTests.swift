import Foundation
import Testing
import QuillKit

@Suite("QuillKit platform services")
struct QuillKitTests {
    @Test("clipboard stores strings and data by type")
    func clipboardStoresValuesByType() {
        let clipboard = QuillClipboard()
        clipboard.setString("plain", forType: "public.utf8-plain-text")
        clipboard.setString("html", forType: "public.html")
        clipboard.setData(Data([1, 2, 3]), forType: "public.png")

        #expect(clipboard.string(forType: "public.utf8-plain-text") == "plain")
        #expect(clipboard.string(forType: "public.html") == "html")
        #expect(clipboard.data(forType: "public.png") == Data([1, 2, 3]))

        clipboard.clear()
        #expect(clipboard.string(forType: "public.utf8-plain-text") == nil)
        #expect(clipboard.data(forType: "public.png") == nil)
    }

    @Test("clipboard removes nil values without clearing other types")
    func clipboardNilRemovalIsScopedToType() {
        let clipboard = QuillClipboard()
        clipboard.setString("plain", forType: "public.utf8-plain-text")
        clipboard.setString("html", forType: "public.html")
        clipboard.setData(Data([1]), forType: "public.png")
        clipboard.setData(Data([2]), forType: "public.tiff")

        clipboard.setString(nil, forType: "public.utf8-plain-text")
        clipboard.setData(nil, forType: "public.png")

        #expect(clipboard.string(forType: "public.utf8-plain-text") == nil)
        #expect(clipboard.string(forType: "public.html") == "html")
        #expect(clipboard.data(forType: "public.png") == nil)
        #expect(clipboard.data(forType: "public.tiff") == Data([2]))
    }

    @Test("diagnostics record and clear compatibility events")
    func diagnosticsRecordAndClearEvents() {
        let diagnostics = QuillCompatibilityDiagnostics()
        diagnostics.record(
            subsystem: "Test",
            operation: "fallback",
            severity: .warning,
            message: "Recorded for regression coverage."
        )

        #expect(diagnostics.events == [
            QuillCompatibilityEvent(
                subsystem: "Test",
                operation: "fallback",
                severity: .warning,
                message: "Recorded for regression coverage."
            )
        ])

        diagnostics.clear()
        #expect(diagnostics.events.isEmpty)
        diagnostics.clear()
        #expect(diagnostics.events.isEmpty)
    }

    @Test("capability matrix reports all known capabilities")
    func capabilityMatrixReportsKnownCapabilities() {
        let statuses = Dictionary(uniqueKeysWithValues: QuillKitCapability.allCases.map {
            ($0, QuillKitCapabilities.status(for: $0))
        })

        #expect(statuses.count == QuillKitCapability.allCases.count)
        #if os(Linux)
        #expect(statuses[.clipboard] == .emulated)
        #expect(statuses[.speechRecognition] == .unavailable(reason: "No native Linux backend has been attached yet."))
        #expect(statuses[.deviceEvents] == .unavailable(reason: "No native Linux backend has been attached yet."))
        #expect(statuses[.launchAtLogin] == .unavailable(reason: "No native Linux backend has been attached yet."))
        #expect(statuses[.secureStorage] == .unavailable(reason: "No native Linux backend has been attached yet."))
        #expect(statuses[.networkExtension] == .unavailable(reason: "No native Linux backend has been attached yet."))
        #expect(statuses[.vpnTunnel] == .unavailable(reason: "No native Linux backend has been attached yet."))
        #else
        #expect(statuses.values.allSatisfy { $0 == .available })
        #endif
    }

    @Test("launch service state is explicit and reversible")
    func launchServiceStateIsExplicitAndReversible() {
        let service = QuillLaunchService()
        #expect(service.isEnabled == false)
        service.register()
        #expect(service.isEnabled)
        service.unregister()
        #expect(service.isEnabled == false)
        service.unregister()
        #expect(service.isEnabled == false)
    }

    @Test("speech backend invokes lifecycle callbacks in order")
    func speechBackendInvokesCallbacksInOrder() {
        let backend = QuillSpeechBackend()
        let callbacks = LockedValue<[String]>([])

        backend.speak("hello") {
            callbacks.update { $0.append("start") }
        } onFinish: {
            callbacks.update { $0.append("finish") }
        }

        #expect(callbacks.value == ["start", "finish"])
        #expect(backend.stop())
    }

    @Test("hot key registration invokes actions when triggered")
    func hotKeyRegistrationTriggersAction() {
        let triggerCount = LockedValue(0)
        let registration = QuillHotKeyRegistration {
            triggerCount.update { $0 += 1 }
        }

        registration.trigger()
        registration.trigger()
        registration.unregister()

        #expect(triggerCount.value == 2)
    }

    @Test("profile fallback services expose reusable Linux behavior")
    func profileFallbackServicesExposeReusableBehavior() {
        QuillCompatibilityDiagnostics.shared.clear()

        let accessibility = QuillAccessibilityService()
        #expect(accessibility.checkAccessibility() == QuillAccessibility.isTrusted)
        #expect(accessibility.getSelectedText() == nil)
        accessibility.showAccessibilityInstructionsWindow()
        accessibility.simulateCopyKeyPress()
        accessibility.simulateTyping(for: "hello")
        QuillAccessibilityService.simulatePasteCommand()

        let panelManager = QuillPanelManager()
        #expect(panelManager.panel.isVisible == false)
        panelManager.showPanel()
        #expect(panelManager.panel.isVisible)
        panelManager.togglePanel()
        #expect(panelManager.panel.isVisible == false)
        panelManager.showPanel()
        panelManager.onSubmitCompletion(scheduledTyping: false)
        #expect(panelManager.panel.isVisible == false)

        var hotkeyInvoked = false
        let combination = QuillHotkeyCombination(keyBase: [.command], key: 0x09) {
            hotkeyInvoked = true
        }
        #expect(combination.keyBase == [.command])
        #expect(combination.key == 0x09)
        #expect(combination.keyBasePressed == false)
        combination.action()
        #expect(hotkeyInvoked)

        let updater = QuillUpdateService()
        #expect(updater.canCheckForUpdates == false)
        updater.checkForUpdates()

        let watcher = QuillDeviceWatcher()
        watcher.start()
        watcher.stop()
        watcher.autoConfigureIfNeeded()
        QuillDeviceLauncher.install(label: "test.launcher", subsystem: "Test")

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.contains("getSelectedTextAX"))
        #expect(operations.contains("getSelectedTextViaCopy"))
        #expect(operations.contains("showAccessibilityInstructionsWindow"))
        #expect(operations.contains("simulateCopyKeyPress"))
        #expect(operations.contains("simulateTyping"))
        #expect(operations.contains("simulatePasteCommand"))
        #expect(operations.contains("checkForUpdates"))
        #expect(operations.contains("deviceWatcher.start"))
        #expect(operations.contains("deviceLauncher.install"))
    }

    @Test("trust and accessibility report platform-specific fallback state")
    func trustAndAccessibilityUsePlatformFallbacks() {
        let certificate = QuillCertificate(data: Data([1, 2, 3]))

        #if os(Linux)
        #expect(QuillTrust.evaluate(certificate: certificate, host: "localhost") == false)
        #expect(QuillAccessibility.isTrusted == false)
        #else
        #expect(QuillTrust.evaluate(certificate: certificate, host: "localhost"))
        #expect(QuillAccessibility.isTrusted)
        #endif
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func update(_ operation: (inout Value) -> Void) {
        lock.withLock {
            operation(&storage)
        }
    }
}
