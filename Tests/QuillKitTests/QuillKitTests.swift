import Foundation
import Testing
import QuillKit

@Suite("QuillKit platform services", .serialized)
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

    @Test("clipboard instance values are isolated from later native plain-text writes")
    func clipboardInstanceValuesAreIsolatedFromNativePlainTextWrites() {
        let first = QuillClipboard()
        let second = QuillClipboard()

        first.setString("first", forType: "public.utf8-plain-text")
        second.setString("second", forType: "public.utf8-plain-text")

        #expect(first.string(forType: "public.utf8-plain-text") == "first")
        #expect(second.string(forType: "public.utf8-plain-text") == "second")

        first.setString(nil, forType: "public.utf8-plain-text")
        #expect(first.string(forType: "public.utf8-plain-text") == nil)
        #expect(second.string(forType: "public.utf8-plain-text") == "second")
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

    @Test("clipboard forwards plain text through the native backend")
    func clipboardForwardsPlainTextThroughNativeBackend() {
        let clipboard = QuillClipboard()
        let writes = LockedValue<[String]>([])
        let nativeReadback = LockedValue<String?>(nil)

        clipboard.installNativeStringBackend(QuillClipboard.NativeStringBackend(
            name: "test",
            setString: { string in
                writes.update { $0.append(string) }
                nativeReadback.update { $0 = string }
                return true
            },
            string: {
                nativeReadback.value
            }
        ))

        clipboard.setString("plain")
        clipboard.setString("html", forType: "public.html")

        #expect(writes.value == ["plain"])
        #expect(clipboard.string() == "plain")
        #expect(clipboard.string(forType: "public.html") == "html")

        clipboard.clear()
        #expect(writes.value == ["plain", ""])
        #expect(clipboard.string(forType: "public.html") == nil)
    }

    @Test("clipboard keeps memory fallback when native backend cannot read")
    func clipboardKeepsMemoryFallbackWhenNativeBackendCannotRead() {
        let clipboard = QuillClipboard()
        let writes = LockedValue<[String]>([])

        clipboard.installNativeStringBackend(QuillClipboard.NativeStringBackend(
            name: "test",
            setString: { string in
                writes.update { $0.append(string) }
                return false
            },
            string: {
                nil
            }
        ))

        clipboard.setString("plain")

        #expect(writes.value == ["plain"])
        #expect(clipboard.string() == "plain")
    }

    @Test("Apple-shaped Clipboard alias uses the shared QuillKit clipboard")
    func appleShapedClipboardAliasUsesSharedQuillKitClipboard() {
        Clipboard.shared.clear()
        Clipboard.shared.setString("alias text")

        #expect(Clipboard.shared === QuillClipboard.shared)
        #expect(QuillClipboard.shared.string() == "alias text")

        Clipboard.shared.clear()
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
        #expect(statuses[.speechSynthesis] == .emulated)
        #expect(statuses[.speechRecognition] == .emulated)
        #expect(statuses[.localAuthentication] == .emulated)
        #expect(statuses[.globalShortcuts] == .emulated)
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

    @Test("update service tracks configuration and checks")
    func updateServiceTracksConfigurationAndChecks() {
        let service = QuillUpdateService()
        QuillCompatibilityDiagnostics.shared.clear()

        service.reset()
        #expect(service.canCheckForUpdates == false)
        #expect(service.updateCheckCount == 0)
        #expect(service.lastCheckDate == nil)

        service.configure(canCheckForUpdates: true)
        #expect(service.canCheckForUpdates)
        service.checkForUpdates()
        #expect(service.updateCheckCount == 1)
        #expect(service.lastCheckDate != nil)
        let checkDiagnosticsAfterFirstRun = QuillCompatibilityDiagnostics.shared.events.filter {
            $0.operation == "checkForUpdates"
        }.count

        service.configure(canCheckForUpdates: false)
        #expect(service.canCheckForUpdates == false)
        service.checkForUpdates()
        #expect(service.updateCheckCount == 2)
        #expect(QuillCompatibilityDiagnostics.shared.events.filter {
            $0.operation == "checkForUpdates"
        }.count >= checkDiagnosticsAfterFirstRun + 1)

        service.reset()
        #expect(service.canCheckForUpdates == false)
        #expect(service.updateCheckCount == 0)
        #expect(service.lastCheckDate == nil)
    }

    @Test("local authentication service exposes configurable policy state")
    func localAuthenticationServiceExposesConfigurablePolicyState() {
        let service = QuillLocalAuthenticationService()
        QuillCompatibilityDiagnostics.shared.clear()

        service.reset()
        #expect(service.biometryType == .none)
        let unavailable = service.canEvaluatePolicy(.deviceOwnerAuthentication)
        #expect(unavailable.canEvaluate == false)
        #expect(unavailable.error == nil)
        let denied = service.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock")
        #expect(denied.success == false)
        #expect(denied.error == .authenticationFailed)

        service.configure(
            canEvaluatePolicy: true,
            biometryType: .faceID,
            evaluationSucceeds: true
        )
        #expect(service.biometryType == .faceID)
        let available = service.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)
        #expect(available.canEvaluate)
        #expect(available.error == nil)
        let granted = service.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "unlock")
        #expect(granted.success)
        #expect(granted.error == nil)

        service.configure(
            canEvaluatePolicy: false,
            biometryType: .touchID,
            canEvaluateError: .passcodeNotSet,
            evaluationSucceeds: false,
            evaluationError: .userCancel
        )
        #expect(service.biometryType == .touchID)
        let passcodeMissing = service.canEvaluatePolicy(.deviceOwnerAuthentication)
        #expect(passcodeMissing.canEvaluate == false)
        #expect(passcodeMissing.error == .passcodeNotSet)
        let cancelled = service.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock")
        #expect(cancelled.success == false)
        #expect(cancelled.error == .userCancel)

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.contains("localAuthentication.canEvaluatePolicy"))
        #expect(operations.contains("localAuthentication.evaluatePolicy"))
    }

    @Test("speech backend invokes lifecycle callbacks in order")
    func speechBackendInvokesCallbacksInOrder() {
        let backend = QuillSpeechBackend()
        let callbacks = LockedValue<[String]>([])
        backend.configureSpeechSynthesisVoices([
            QuillSpeechVoice(identifier: "quill.test.voice", name: "Test Voice", quality: 1)
        ])

        #expect(backend.voices() == [
            QuillSpeechVoice(identifier: "quill.test.voice", name: "Test Voice", quality: 1)
        ])
        #expect(!backend.isSpeaking)

        backend.speak("hello") {
            #expect(backend.isSpeaking)
            callbacks.update { $0.append("start") }
        } onFinish: {
            #expect(!backend.isSpeaking)
            callbacks.update { $0.append("finish") }
        }

        #expect(callbacks.value == ["start", "finish"])
        #expect(!backend.isSpeaking)
        #expect(backend.stop())
        backend.resetSpeechSynthesis()
        #if os(Linux)
        #expect(backend.voices() == [.linuxDefault])
        #else
        #expect(backend.voices().isEmpty)
        #endif
    }

    @Test("speech recognition backend exposes configurable authorization availability and results")
    func speechRecognitionBackendExposesConfigurableState() {
        let backend = QuillSpeechBackend()
        let deliveredStatuses = LockedValue<[QuillSpeechRecognitionAuthorizationStatus]>([])
        let deliveredResults = LockedValue<[QuillSpeechRecognitionResult?]>([])
        let deliveredErrors = LockedValue<[QuillSpeechRecognitionError?]>([])

        backend.configureSpeechRecognition(
            authorizationStatus: .authorized,
            isAvailable: true,
            result: QuillSpeechRecognitionResult(formattedString: "hello linux", isFinal: false)
        )
        backend.requestSpeechRecognitionAuthorization { status in
            deliveredStatuses.update { $0.append(status) }
        }

        let task = backend.recognitionTask(shouldReportPartialResults: true) { result, error in
            deliveredResults.update { $0.append(result) }
            deliveredErrors.update { $0.append(error) }
        }

        #expect(deliveredStatuses.value == [.authorized])
        #expect(deliveredResults.value == [
            QuillSpeechRecognitionResult(formattedString: "hello linux", isFinal: false)
        ])
        #expect(deliveredErrors.value == [nil])
        #expect(!task.isCancelled)
        task.cancel()
        #expect(task.isCancelled)

        backend.configureSpeechRecognition(
            authorizationStatus: .denied,
            isAvailable: true,
            result: QuillSpeechRecognitionResult(formattedString: "ignored")
        )
        _ = backend.recognitionTask(shouldReportPartialResults: false) { result, error in
            deliveredResults.update { $0.append(result) }
            deliveredErrors.update { $0.append(error) }
        }

        #expect(deliveredResults.value.count == 2)
        #expect(deliveredResults.value[1] == nil)
        let lastError = deliveredErrors.value.last ?? nil
        #expect(lastError?.reason == "Speech recognition is not authorized.")
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

    @Test("hot key service registers triggers conflicts and unregisters")
    func hotKeyServiceRegistersTriggersConflictsAndUnregisters() {
        let diagnostics = QuillCompatibilityDiagnostics()
        let service = QuillHotkeyService(diagnostics: diagnostics)
        let triggerCount = LockedValue(0)
        let duplicateIdentifierCount = LockedValue(0)
        let duplicateGestureCount = LockedValue(0)
        let descriptor = QuillHotKeyDescriptor(
            identifier: "togglePanel",
            key: "space",
            modifiers: ["shift", "command", "command"]
        )

        let registration = service.register(descriptor: descriptor) {
            triggerCount.update { $0 += 1 }
        }

        #expect(registration.isRegistered)
        #expect(registration.descriptor == QuillHotKeyDescriptor(
            identifier: "togglePanel",
            key: "space",
            modifiers: ["command", "shift"]
        ))
        #expect(service.registeredHotKeys == [descriptor])
        #expect(service.trigger(identifier: "togglePanel"))
        #expect(service.trigger(key: "space", modifiers: ["command", "shift"]))
        #expect(triggerCount.value == 2)

        let duplicateIdentifier = service.register(
            descriptor: QuillHotKeyDescriptor(
                identifier: "togglePanel",
                key: "escape",
                modifiers: ["command"]
            )
        ) {
            duplicateIdentifierCount.update { $0 += 1 }
        }
        let duplicateGesture = service.register(
            descriptor: QuillHotKeyDescriptor(
                identifier: "otherPanel",
                key: "space",
                modifiers: ["shift", "command"]
            )
        ) {
            duplicateGestureCount.update { $0 += 1 }
        }

        #expect(!duplicateIdentifier.isRegistered)
        #expect(!duplicateGesture.isRegistered)
        #expect(!duplicateIdentifier.trigger())
        #expect(!duplicateGesture.trigger())
        #expect(duplicateIdentifierCount.value == 0)
        #expect(duplicateGestureCount.value == 0)
        #expect(diagnostics.events.filter { $0.operation == "registerHotKey" && $0.severity == .warning }.count == 2)

        registration.unregister()
        #expect(!registration.isRegistered)
        #expect(!registration.trigger())
        #expect(!service.trigger(identifier: "togglePanel"))
        #expect(service.registeredHotKeys.isEmpty)
        #expect(triggerCount.value == 2)
    }

    @Test("profile fallback services expose reusable Linux behavior")
    func profileFallbackServicesExposeReusableBehavior() {
        QuillCompatibilityDiagnostics.shared.clear()

        let accessibility = QuillAccessibilityService()
        let appleNamedAccessibility = Accessibility.shared
        #expect(appleNamedAccessibility === QuillAccessibilityService.shared)
        #expect(accessibility.checkAccessibility() == QuillAccessibility.isTrusted)
        #expect(accessibility.getSelectedText() == nil)
        accessibility.showAccessibilityInstructionsWindow()
        accessibility.simulateCopyKeyPress()
        accessibility.simulateTyping(for: "hello")
        QuillAccessibilityService.simulatePasteCommand()

        let panelManager = QuillPanelManager()
        let appleNamedPanelManager = PanelManager()
        #expect(type(of: appleNamedPanelManager.panel) == FloatingPanel.self)
        #expect(panelManager.panel.isVisible == false)
        panelManager.showPanel()
        #expect(panelManager.panel.isVisible)
        panelManager.togglePanel()
        #expect(panelManager.panel.isVisible == false)
        panelManager.showPanel()
        panelManager.onSubmitCompletion(scheduledTyping: false)
        #expect(panelManager.panel.isVisible == false)

        var hotkeyInvoked = false
        let combination = HotkeyCombination(keyBase: [.command], key: 0x09) {
            hotkeyInvoked = true
        }
        #expect(combination.keyBase == [KeyBase.command])
        #expect(combination.key == 0x09)
        #expect(combination.keyBasePressed == false)
        combination.action()
        #expect(hotkeyInvoked)

        let updater = QuillUpdater()
        updater.reset()
        #expect(updater.canCheckForUpdates == false)
        updater.configure(canCheckForUpdates: true)
        #expect(updater.canCheckForUpdates)
        updater.checkForUpdates()
        #expect(updater.updateCheckCount == 1)

        #expect(HotkeyService.shared === QuillHotkeyService.shared)

        let watcher = QuillUSBWatcher()
        watcher.start()
        watcher.stop()
        watcher.autoConfigureIfNeeded()
        QuillDeviceLauncher.install(label: "test.launcher", subsystem: "Test")
        QuillUSBLauncher.install(label: "test.usb-launcher", subsystem: "TestUSB")

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
