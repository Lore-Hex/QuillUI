import Foundation
#if os(Linux)
import Glibc
#endif

public enum QuillKitPlatform: String, Sendable {
    case linux = "Linux"
    case macOS = "macOS"
    case iOS = "iOS"
    case unknown = "Unknown"

    public static var current: QuillKitPlatform {
        #if os(Linux)
        .linux
        #elseif os(macOS)
        .macOS
        #elseif os(iOS)
        .iOS
        #else
        .unknown
        #endif
    }
}

public enum QuillKitCapability: String, CaseIterable, Sendable {
    case clipboard
    case speechSynthesis
    case speechRecognition
    case haptics
    case accessibility
    case syntheticKeyboard
    case globalShortcuts
    case deviceEvents
    case launchAtLogin
    case updater
    case certificateTrust
    case photoPicker
    case secureStorage
    case notifications
    case networkExtension
    case vpnTunnel
}

public enum QuillKitCapabilityStatus: Equatable, Sendable {
    case available
    case emulated
    case unavailable(reason: String)
}

public enum QuillKitCapabilities {
    public static func status(for capability: QuillKitCapability) -> QuillKitCapabilityStatus {
        #if os(Linux)
        switch capability {
        case .clipboard:
            return .emulated
        case .speechSynthesis, .speechRecognition, .haptics, .accessibility, .syntheticKeyboard,
             .globalShortcuts, .deviceEvents, .launchAtLogin, .updater, .certificateTrust, .photoPicker,
             .secureStorage, .notifications, .networkExtension, .vpnTunnel:
            return .unavailable(reason: "No native Linux backend has been attached yet.")
        }
        #else
        return .available
        #endif
    }
}

public struct QuillCompatibilityEvent: Equatable, Sendable {
    public enum Severity: String, Sendable {
        case info
        case warning
        case unsupported
    }

    public var subsystem: String
    public var operation: String
    public var severity: Severity
    public var message: String

    public init(
        subsystem: String,
        operation: String,
        severity: Severity,
        message: String
    ) {
        self.subsystem = subsystem
        self.operation = operation
        self.severity = severity
        self.message = message
    }
}

public final class QuillCompatibilityDiagnostics: @unchecked Sendable {
    public static let shared = QuillCompatibilityDiagnostics()

    private let lock = NSLock()
    private var storedEvents: [QuillCompatibilityEvent] = []

    public init() {}

    public var events: [QuillCompatibilityEvent] {
        lock.withLock { storedEvents }
    }

    public func record(_ event: QuillCompatibilityEvent) {
        lock.withLock {
            storedEvents.append(event)
        }
    }

    public func record(
        subsystem: String,
        operation: String,
        severity: QuillCompatibilityEvent.Severity = .unsupported,
        message: String
    ) {
        record(QuillCompatibilityEvent(
            subsystem: subsystem,
            operation: operation,
            severity: severity,
            message: message
        ))
    }

    public func clear() {
        lock.withLock {
            storedEvents.removeAll()
        }
    }
}

public final class QuillClipboard: @unchecked Sendable {
    public static let shared = QuillClipboard()

    public struct NativeStringBackend: Sendable {
        public var name: String
        public var setString: @Sendable (String) -> Bool
        public var string: @Sendable () -> String?

        public init(
            name: String,
            setString: @escaping @Sendable (String) -> Bool,
            string: @escaping @Sendable () -> String?
        ) {
            self.name = name
            self.setString = setString
            self.string = string
        }
    }

    private let lock = NSLock()
    private var stringValues: [String: String] = [:]
    private var locallyManagedStringTypes: Set<String> = []
    private var stringsWereCleared = false
    private var dataValues: [String: Data] = [:]
    private var nativeStringBackend: NativeStringBackend?

    public init() {}

    public func installNativeStringBackend(_ backend: NativeStringBackend?) {
        lock.withLock {
            nativeStringBackend = backend
        }
    }

    public func setString(_ string: String?, forType type: String = "public.utf8-plain-text") {
        let backend = lock.withLock {
            if let string {
                stringValues[type] = string
            } else {
                stringValues.removeValue(forKey: type)
            }
            locallyManagedStringTypes.insert(type)
            return nativeStringBackend
        }

        guard Self.usesNativeClipboard(forType: type) else {
            return
        }

        #if os(Linux)
        Self.writeFileBackedPasteboardString(string, forType: type)
        #endif

        let clipboardString = string ?? ""
        if backend?.setString(clipboardString) == true {
            return
        }

        #if os(Linux)
        _ = QuillLinuxClipboardBridge.setString(clipboardString)
        #endif
    }

    public func string(forType type: String = "public.utf8-plain-text") -> String? {
        let state = lock.withLock {
            (
                value: stringValues[type],
                isLocallyManaged: locallyManagedStringTypes.contains(type),
                stringsWereCleared: stringsWereCleared,
                backend: nativeStringBackend
            )
        }

        if Self.usesNativeClipboard(forType: type) {
            if let nativeString = state.backend?.string(), !nativeString.isEmpty {
                return nativeString
            }
        }

        if state.isLocallyManaged {
            return state.value
        }

        if state.stringsWereCleared {
            return nil
        }

        if Self.usesNativeClipboard(forType: type) {
            #if os(Linux)
            if let bridgeString = QuillLinuxClipboardBridge.string(), !bridgeString.isEmpty {
                return bridgeString
            }
            if let fileBackedString = Self.fileBackedPasteboardString(forType: type) {
                return fileBackedString
            }
            #endif
        }

        return lock.withLock { stringValues[type] }
    }

    public func setData(_ data: Data?, forType type: String) {
        lock.withLock {
            dataValues[type] = data
        }
    }

    public func data(forType type: String) -> Data? {
        lock.withLock { dataValues[type] }
    }

    public func clear() {
        let backend = lock.withLock {
            stringValues.removeAll()
            locallyManagedStringTypes.removeAll()
            stringsWereCleared = true
            dataValues.removeAll()
            return nativeStringBackend
        }

        #if os(Linux)
        Self.clearFileBackedPasteboard()
        #endif

        if backend?.setString("") == true {
            return
        }

        #if os(Linux)
        _ = QuillLinuxClipboardBridge.setString("")
        #endif
    }

    private static func usesNativeClipboard(forType type: String) -> Bool {
        switch type {
        case "public.utf8-plain-text", "public.text", "public.plain-text", "NSStringPboardType":
            return true
        default:
            return false
        }
    }

    #if os(Linux)
    private static func fileBackedPasteboardRoot() -> URL {
        let base: URL
        if let runtimeDirectory = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] {
            base = URL(fileURLWithPath: runtimeDirectory)
        } else {
            base = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        return base
            .appendingPathComponent("quill-pasteboard")
            .appendingPathComponent("Apple.NSGeneralPboard")
    }

    private static func fileBackedPasteboardTypeURL(forType type: String) -> URL {
        let safeType = type.replacingOccurrences(of: "/", with: "_")
        return fileBackedPasteboardRoot()
            .appendingPathComponent("types")
            .appendingPathComponent(safeType)
    }

    private static func writeFileBackedPasteboardString(_ string: String?, forType type: String) {
        let typeURL = fileBackedPasteboardTypeURL(forType: type)
        let typeDirectory = typeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: typeDirectory,
            withIntermediateDirectories: true
        )

        if let string {
            try? Data(string.utf8).write(to: typeURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: typeURL)
        }
    }

    private static func fileBackedPasteboardString(forType type: String) -> String? {
        let typeURL = fileBackedPasteboardTypeURL(forType: type)
        return (try? Data(contentsOf: typeURL)).flatMap { data in
            String(data: data, encoding: .utf8)
        }
    }

    private static func clearFileBackedPasteboard() {
        let typeDirectory = fileBackedPasteboardRoot().appendingPathComponent("types")
        try? FileManager.default.removeItem(at: typeDirectory)
    }
    #endif
}

#if os(Linux)
private enum QuillLinuxClipboardBridge {
    private typealias SetTextFunction = @convention(c) (UnsafePointer<CChar>?) -> CInt
    private typealias GetTextFunction = @convention(c) () -> UnsafePointer<CChar>?

    static func setString(_ string: String) -> Bool {
        guard let setText = firstSymbol(
            named: [
                "quill_qt_bridge_clipboard_set_text",
                "quill_qt_native_clipboard_set_text"
            ],
            as: SetTextFunction.self
        ) else {
            return false
        }

        return string.withCString { setText($0) != 0 }
    }

    static func string() -> String? {
        guard let getText = firstSymbol(
            named: [
                "quill_qt_bridge_clipboard_text",
                "quill_qt_native_clipboard_text"
            ],
            as: GetTextFunction.self
        ),
              let value = getText()
        else {
            return nil
        }

        return String(cString: value)
    }

    private static func firstSymbol<Function>(
        named names: [String],
        as type: Function.Type
    ) -> Function? {
        guard let handle = dlopen(nil, RTLD_NOW) else {
            return nil
        }

        for name in names {
            if let symbol = dlsym(handle, name) {
                return unsafeBitCast(symbol, to: Function.self)
            }
        }

        return nil
    }
}
#endif

public enum QuillWorkspace {
    @discardableResult
    public static func open(_ url: URL) -> Bool {
        #if os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            return true
        } catch {
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillKit",
                operation: "openURL",
                message: "xdg-open could not be launched for \(url.absoluteString): \(error.localizedDescription)"
            )
            return false
        }
        #else
        return false
        #endif
    }
}

public struct QuillSpeechVoice: Hashable, Sendable {
    public var identifier: String
    public var name: String
    public var quality: Int

    public init(identifier: String, name: String, quality: Int = 0) {
        self.identifier = identifier
        self.name = name
        self.quality = quality
    }

    public static let linuxDefault = QuillSpeechVoice(
        identifier: "quill.linux.default",
        name: "Linux Default"
    )
}

public final class QuillSpeechBackend: @unchecked Sendable {
    public static let shared = QuillSpeechBackend()

    private let lock = NSLock()
    private var speaking = false

    public init() {}

    public func voices() -> [QuillSpeechVoice] {
        #if os(Linux)
        [QuillSpeechVoice.linuxDefault]
        #else
        []
        #endif
    }

    public func speak(_ text: String, onStart: @escaping @Sendable () -> Void, onFinish: @escaping @Sendable () -> Void) {
        lock.withLock { speaking = true }
        onStart()
        #if os(Linux)
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "speechSynthesis",
            severity: .info,
            message: "Speech synthesis is emulated on Linux until a native backend is attached."
        )
        #endif
        lock.withLock { speaking = false }
        onFinish()
    }

    @discardableResult
    public func stop() -> Bool {
        lock.withLock { speaking = false }
        return true
    }
}

public final class QuillLaunchService: @unchecked Sendable {
    public static let shared = QuillLaunchService()
    private let lock = NSLock()
    private var enabled = false

    public init() {}

    public var isEnabled: Bool { lock.withLock { enabled } }

    public func register() {
        lock.withLock { enabled = true }
        #if os(Linux)
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "launchAtLogin",
            severity: .info,
            message: "Launch-at-login state is emulated on Linux until a desktop autostart backend is attached."
        )
        #endif
    }

    public func unregister() {
        lock.withLock { enabled = false }
    }
}

public struct QuillCertificate: Hashable, Sendable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }
}

public enum QuillTrust {
    public static func evaluate(certificate: QuillCertificate, host: String) -> Bool {
        #if os(Linux)
        false
        #else
        true
        #endif
    }
}

public final class QuillHotKeyRegistration: @unchecked Sendable {
    private let action: @Sendable () -> Void

    public init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    public func unregister() {}
    public func trigger() { action() }
}

public enum QuillKeyBase: CaseIterable, Sendable {
    case option
    case command
    case shift
    case control

    public var isPressed: Bool { false }
}

public struct QuillHotkeyCombination {
    public var keyBase: [QuillKeyBase]
    public var key: UInt16
    public var action: () -> Void

    public init(keyBase: [QuillKeyBase], key: UInt16, action: @escaping () -> Void) {
        self.keyBase = keyBase
        self.key = key
        self.action = action
    }

    public var keyBasePressed: Bool { false }
}

public final class QuillAccessibilityService: @unchecked Sendable {
    public static let shared = QuillAccessibilityService()

    public init() {}

    public func checkAccessibility() -> Bool {
        QuillAccessibility.isTrusted
    }

    public func showAccessibilityInstructionsWindow() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "showAccessibilityInstructionsWindow",
            severity: .unsupported,
            message: "Accessibility permission instructions need a native Linux settings backend."
        )
    }

    public func getSelectedText() -> String? {
        getSelectedTextAX() ?? getSelectedTextViaCopy()
    }

    public func getSelectedTextAX() -> String? {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "getSelectedTextAX",
            severity: .unsupported,
            message: "Reading selected text through platform accessibility APIs is unavailable on Linux."
        )
        return nil
    }

    public func getSelectedTextViaCopy(retryAttempts: Int = 1) -> String? {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "getSelectedTextViaCopy",
            severity: .unsupported,
            message: "Reading selected text through synthetic copy is unavailable on Linux."
        )
        return nil
    }

    public func simulateCopyKeyPress() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "simulateCopyKeyPress",
            severity: .unsupported,
            message: "Synthetic copy key presses need a native Linux input backend."
        )
    }

    public func simulateTyping(for string: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "simulateTyping",
            severity: .unsupported,
            message: "Synthetic typing of \(string.count) characters needs a native Linux input backend."
        )
    }

    public static func simulatePasteCommand() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "simulatePasteCommand",
            severity: .unsupported,
            message: "Synthetic paste key presses need a native Linux input backend."
        )
    }
}

public enum QuillAccessibility {
    public static let shared = QuillAccessibilityService.shared

    public static var isTrusted: Bool {
        #if os(Linux)
        false
        #else
        true
        #endif
    }
}

public final class QuillFloatingPanel: @unchecked Sendable {
    public var isVisible = false

    public init() {}

    public func orderOut(_ sender: Any?) {
        isVisible = false
    }

    public func makeKeyAndOrderFront(_ sender: Any?) {
        isVisible = true
    }

    public func close() {
        isVisible = false
    }
}

public final class QuillPanelManager: @unchecked Sendable {
    public var panel = QuillFloatingPanel()

    public init() {}

    public func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    public func hidePanel() {
        panel.orderOut(nil)
    }

    public func showPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    public func onSubmitMessage() {
        hidePanel()
    }

    public func onSubmitCompletion(scheduledTyping: Bool) {
        hidePanel()
    }
}

public final class QuillUpdateService: @unchecked Sendable {
    public static let shared = QuillUpdateService()

    public private(set) var canCheckForUpdates = false

    public init() {}

    public func checkForUpdates() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "checkForUpdates",
            severity: .unsupported,
            message: "Software update checks need a native Linux update backend."
        )
    }
}

// Hotkey registration shim. Real implementations use Carbon's
// RegisterEventHotKey on macOS or platform-native APIs (XKB,
// libei, GTK accelerator groups). The Linux stub records a
// diagnostic and returns the closure's deregistration token so
// upstream code keeps compiling.
public final class QuillHotkeyService: @unchecked Sendable {
    public static let shared = QuillHotkeyService()

    public init() {}

    @discardableResult
    public func registerSingleUseSpace<ModifierSet>(
        modifiers: ModifierSet,
        handler: () -> AnyObject?
    ) -> AnyObject? {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "registerSingleUseSpace",
            severity: .unsupported,
            message: "Global hotkey registration needs a native Linux key-event backend."
        )
        return handler()
    }
}

// Source-level compatibility names used by Apple app ports whose originals
// wrapped AppKit, Sparkle, or hotkey platform services.
public typealias Accessibility = QuillAccessibilityService
public typealias Clipboard = QuillClipboard
public typealias KeyBase = QuillKeyBase
public typealias HotkeyCombination = QuillHotkeyCombination
public typealias FloatingPanel = QuillFloatingPanel
public typealias PanelManager = QuillPanelManager
public typealias QuillUpdater = QuillUpdateService
public typealias QuillUSBWatcher = QuillDeviceWatcher
public typealias HotkeyService = QuillHotkeyService

public final class QuillDeviceWatcher: @unchecked Sendable {
    public static let shared = QuillDeviceWatcher()

    public init() {}

    public func start() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "deviceWatcher.start",
            severity: .unsupported,
            message: "USB/device watching needs a native Linux backend."
        )
    }

    public func stop() {}
    public func autoConfigureIfNeeded() {}
}

public enum QuillDeviceLauncher {
    public static func install(label: String, subsystem: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: subsystem,
            operation: "deviceLauncher.install",
            severity: .unsupported,
            message: "LaunchAgent-style device launcher '\(label)' is unavailable on Linux."
        )
    }
}

#if os(Linux)
public typealias CFAllocator = AnyObject
public typealias CFData = Data
public typealias CFArray = [Any]
public typealias CFString = String
public typealias CFDictionary = [String: Any]
public typealias CFTypeRef = AnyObject
public typealias CFError = Error

public func CFErrorCopyDescription(_ error: CFError) -> CFString {
    error.localizedDescription
}

public struct QuillUnmanagedStringConstant: Sendable {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    public func takeUnretainedValue() -> CFString {
        value
    }
}
#endif
