import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Dispatch)
import Dispatch
#endif
#if os(Linux)
import CoreFoundation
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
    case localAuthentication
    case haptics
    case accessibility
    case syntheticKeyboard
    case globalShortcuts
    case deviceEvents
    case launchAtLogin
    case updater
    case certificateTrust
    case audioSession
    case audioPlayback
    case photoPicker
    case secureStorage
    case notifications
    case cloudKit
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
        case .clipboard, .speechSynthesis, .speechRecognition, .localAuthentication:
            return .emulated
        case .globalShortcuts, .audioSession, .audioPlayback:
            return .emulated
        case .notifications:
            return .emulated
        case .haptics, .accessibility, .syntheticKeyboard,
             .deviceEvents, .launchAtLogin, .updater, .certificateTrust, .photoPicker,
             .secureStorage, .cloudKit, .networkExtension, .vpnTunnel:
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

private let quillSwiftOpenUICompatibilityFallbackNotification = Notification.Name("QuillSwiftOpenUICompatibilityFallback")

public final class QuillCompatibilityDiagnostics: @unchecked Sendable {
    public static let shared = QuillCompatibilityDiagnostics()

    private let lock = NSRecursiveLock()
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

    public func captureIsolatedEvents<Result>(
        _ body: () throws -> Result
    ) rethrows -> (result: Result, events: [QuillCompatibilityEvent]) {
        lock.lock()
        let previousEvents = storedEvents
        storedEvents.removeAll()
        let observer = NotificationCenter.default.addObserver(
            forName: quillSwiftOpenUICompatibilityFallbackNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let operation = notification.userInfo?["operation"] as? String else { return }
            let subsystem = notification.userInfo?["subsystem"] as? String ?? "QuillUI"
            let message = notification.userInfo?["message"] as? String
                ?? "\(operation) is currently a source-compatibility fallback on Linux."
            let severity = (notification.userInfo?["severity"] as? String)
                .flatMap(QuillCompatibilityEvent.Severity.init(rawValue:)) ?? .info
            self?.record(
                subsystem: subsystem,
                operation: operation,
                severity: severity,
                message: message
            )
        }

        do {
            let result = try body()
            let capturedEvents = storedEvents
            storedEvents = previousEvents
            NotificationCenter.default.removeObserver(observer)
            lock.unlock()
            return (result, capturedEvents)
        } catch {
            storedEvents = previousEvents
            NotificationCenter.default.removeObserver(observer)
            lock.unlock()
            throw error
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
    public struct OpenBackend: Sendable {
        public var name: String
        public var open: @Sendable (URL) -> Bool

        public init(name: String, open: @escaping @Sendable (URL) -> Bool) {
            self.name = name
            self.open = open
        }
    }

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var openBackend: OpenBackend?
    }

    private static let storage = Storage()
    public static let openURLLogFileEnvironmentKey = "QUILLUI_OPEN_URL_LOG_FILE"
    public static let openURLLogAssumeHandledEnvironmentKey = "QUILLUI_OPEN_URL_LOG_ASSUME_HANDLED"

    public static func installOpenBackend(_ backend: OpenBackend?) {
        storage.lock.withLock {
            storage.openBackend = backend
        }
    }

    @discardableResult
    public static func open(_ url: URL) -> Bool {
        if let backend = storage.lock.withLock({ storage.openBackend }) {
            let didOpen = backend.open(url)
            recordOpen(url, didOpen: didOpen, backendName: backend.name)
            return didOpen
        }

        if let loggedOpen = logOpenURLIfConfigured(url), loggedOpen.assumeHandled {
            recordOpen(url, didOpen: true, backendName: "file-log")
            return true
        }

        #if os(Linux)
        guard Self.linuxDesktopOpenAvailable else {
            recordOpenUnavailable(
                url,
                reason: "xdg-open requires /usr/bin/xdg-open plus DISPLAY or WAYLAND_DISPLAY on Linux."
            )
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            recordOpen(url, didOpen: true, backendName: "xdg-open")
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

    #if os(Linux)
    private static var linuxDesktopOpenAvailable: Bool {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xdg-open") else {
            return false
        }

        let env = ProcessInfo.processInfo.environment
        return env["DISPLAY"]?.isEmpty == false || env["WAYLAND_DISPLAY"]?.isEmpty == false
    }
    #endif

    private struct LoggedOpen {
        var assumeHandled: Bool
    }

    private static func logOpenURLIfConfigured(_ url: URL) -> LoggedOpen? {
        let env = ProcessInfo.processInfo.environment
        guard
            let rawPath = env[openURLLogFileEnvironmentKey],
            !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let logURL = URL(fileURLWithPath: rawPath)
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let line = "\(url.absoluteString)\n"
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                handle.write(Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        } catch {
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillKit",
                operation: "openURL",
                message: "URL open for \(url.absoluteString) could not be logged to \(rawPath): \(error.localizedDescription)"
            )
            return nil
        }

        return LoggedOpen(
            assumeHandled: environmentFlagIsEnabled(env[openURLLogAssumeHandledEnvironmentKey])
        )
    }

    private static func environmentFlagIsEnabled(_ rawValue: String?) -> Bool {
        guard let rawValue else { return false }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func recordOpen(_ url: URL, didOpen: Bool, backendName: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "openURL",
            severity: didOpen ? .info : .unsupported,
            message: "URL open for \(url.absoluteString) was handled by \(backendName)."
        )
    }

    private static func recordOpenUnavailable(_ url: URL, reason: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "openURL",
            severity: .unsupported,
            message: "URL open for \(url.absoluteString) was not attempted: \(reason)"
        )
    }
}

public final class QuillQuickLookService: @unchecked Sendable {
    public static let shared = QuillQuickLookService()

    public struct PreviewBackend: Sendable {
        public var name: String
        public var preview: @Sendable (URL) -> Bool

        public init(name: String, preview: @escaping @Sendable (URL) -> Bool) {
            self.name = name
            self.preview = preview
        }
    }

    private let lock = NSLock()
    private var previewBackend: PreviewBackend?
    private var previewedURLsValue: [URL] = []

    public init() {}

    public var previewedURLs: [URL] {
        lock.withLock { previewedURLsValue }
    }

    public func installPreviewBackend(_ backend: PreviewBackend?) {
        lock.withLock {
            previewBackend = backend
        }
    }

    public func reset() {
        lock.withLock {
            previewBackend = nil
            previewedURLsValue.removeAll()
        }
    }

    @discardableResult
    public func preview(_ url: URL) -> Bool {
        let backend = lock.withLock { previewBackend }
        let backendName: String
        let didPreview: Bool

        if let backend {
            backendName = backend.name
            didPreview = backend.preview(url)
        } else {
            backendName = "QuillWorkspace"
            didPreview = QuillWorkspace.open(url)
        }

        if didPreview {
            lock.withLock {
                previewedURLsValue.append(url)
            }
        }

        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "quickLook.preview",
            severity: didPreview ? .info : .unsupported,
            message: "QuickLook preview for \(url.absoluteString) was \(didPreview ? "handled" : "rejected") by \(backendName)."
        )
        return didPreview
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

public enum QuillSpeechRecognitionAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

public struct QuillSpeechRecognitionResult: Equatable, Sendable {
    public var formattedString: String
    public var isFinal: Bool

    public init(formattedString: String, isFinal: Bool = true) {
        self.formattedString = formattedString
        self.isFinal = isFinal
    }
}

public struct QuillSpeechRecognitionError: Error, Equatable, Sendable, CustomStringConvertible {
    public var reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var description: String { reason }
}

public final class QuillSpeechRecognitionTask: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    public func cancel() {
        lock.withLock {
            cancelled = true
        }
    }
}

public final class QuillSpeechBackend: @unchecked Sendable {
    public static let shared = QuillSpeechBackend()

    private let lock = NSLock()
    private var speaking = false
    private var paused = false
    private var pendingSpeechFinish: (@Sendable () -> Void)?
    private var synthesisVoices: [QuillSpeechVoice]
    private var recognitionAuthorizationStatus: QuillSpeechRecognitionAuthorizationStatus
    private var recognitionIsAvailable: Bool
    private var recognitionResult: QuillSpeechRecognitionResult?

    public init() {
        #if os(Linux)
        synthesisVoices = [QuillSpeechVoice.linuxDefault]
        recognitionAuthorizationStatus = .denied
        recognitionIsAvailable = false
        #else
        synthesisVoices = []
        recognitionAuthorizationStatus = .authorized
        recognitionIsAvailable = true
        #endif
        recognitionResult = nil
    }

    public func voices() -> [QuillSpeechVoice] {
        lock.withLock { synthesisVoices }
    }

    public func configureSpeechSynthesisVoices(_ voices: [QuillSpeechVoice]) {
        lock.withLock {
            synthesisVoices = voices
        }
    }

    public func resetSpeechSynthesis() {
        lock.withLock {
            speaking = false
            paused = false
            pendingSpeechFinish = nil
            #if os(Linux)
            synthesisVoices = [QuillSpeechVoice.linuxDefault]
            #else
            synthesisVoices = []
            #endif
        }
    }

    public var isSpeaking: Bool {
        lock.withLock { speaking || paused }
    }

    public var isPaused: Bool {
        lock.withLock { paused }
    }

    public func speak(_ text: String, onStart: @escaping @Sendable () -> Void, onFinish: @escaping @Sendable () -> Void) {
        lock.withLock {
            speaking = true
            paused = false
            pendingSpeechFinish = nil
        }
        onStart()
        #if os(Linux)
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "speechSynthesis",
            severity: .info,
            message: "Speech synthesis is emulated on Linux until a native backend is attached."
        )
        #endif

        let shouldFinish = lock.withLock {
            guard !paused else {
                pendingSpeechFinish = onFinish
                return false
            }
            speaking = false
            pendingSpeechFinish = nil
            return true
        }
        if shouldFinish {
            onFinish()
        }
    }

    @discardableResult
    public func stop() -> Bool {
        lock.withLock {
            speaking = false
            paused = false
            pendingSpeechFinish = nil
        }
        return true
    }

    @discardableResult
    public func pause() -> Bool {
        let didPause = lock.withLock {
            guard speaking else { return false }
            speaking = false
            paused = true
            return true
        }

        if didPause {
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillKit",
                operation: "speechSynthesis.pause",
                severity: .info,
                message: "Speech synthesis pause state is tracked by the QuillKit compatibility backend."
            )
        }
        return didPause
    }

    @discardableResult
    public func continueSpeaking() -> Bool {
        let state = lock.withLock {
            guard paused else {
                return (didContinue: false, finish: nil as (@Sendable () -> Void)?)
            }
            paused = false
            speaking = true
            let finish = pendingSpeechFinish
            pendingSpeechFinish = nil
            speaking = false
            return (didContinue: true, finish: finish)
        }

        guard state.didContinue else {
            return false
        }

        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "speechSynthesis.continue",
            severity: .info,
            message: "Speech synthesis resume state is tracked by the QuillKit compatibility backend."
        )
        state.finish?()
        return true
    }

    public var speechRecognitionAuthorizationStatus: QuillSpeechRecognitionAuthorizationStatus {
        lock.withLock { recognitionAuthorizationStatus }
    }

    public var isSpeechRecognitionAvailable: Bool {
        get { lock.withLock { recognitionIsAvailable } }
        set {
            lock.withLock {
                recognitionIsAvailable = newValue
            }
        }
    }

    public func configureSpeechRecognition(
        authorizationStatus: QuillSpeechRecognitionAuthorizationStatus,
        isAvailable: Bool,
        result: QuillSpeechRecognitionResult?
    ) {
        lock.withLock {
            recognitionAuthorizationStatus = authorizationStatus
            recognitionIsAvailable = isAvailable
            recognitionResult = result
        }
    }

    public func resetSpeechRecognition() {
        lock.withLock {
            #if os(Linux)
            recognitionAuthorizationStatus = .denied
            recognitionIsAvailable = false
            #else
            recognitionAuthorizationStatus = .authorized
            recognitionIsAvailable = true
            #endif
            recognitionResult = nil
        }
    }

    public func requestSpeechRecognitionAuthorization(
        _ handler: @escaping (QuillSpeechRecognitionAuthorizationStatus) -> Void
    ) {
        let status = lock.withLock { recognitionAuthorizationStatus }
        #if os(Linux)
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "speechRecognitionAuthorization",
            severity: status == .authorized ? .info : .unsupported,
            message: "Speech recognition authorization is provided by the QuillKit compatibility backend."
        )
        #endif
        handler(status)
    }

    @discardableResult
    public func recognitionTask(
        shouldReportPartialResults: Bool,
        resultHandler: @escaping (QuillSpeechRecognitionResult?, QuillSpeechRecognitionError?) -> Void
    ) -> QuillSpeechRecognitionTask {
        let task = QuillSpeechRecognitionTask()
        let state = lock.withLock {
            (
                status: recognitionAuthorizationStatus,
                available: recognitionIsAvailable,
                result: recognitionResult
            )
        }

        guard state.status == .authorized else {
            #if os(Linux)
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillKit",
                operation: "speechRecognitionTask",
                message: "Speech recognition requires authorized compatibility state."
            )
            #endif
            resultHandler(nil, QuillSpeechRecognitionError(reason: "Speech recognition is not authorized."))
            return task
        }

        guard state.available else {
            #if os(Linux)
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillKit",
                operation: "speechRecognitionTask",
                message: "Speech recognition is unavailable until a native Linux backend is attached."
            )
            #endif
            resultHandler(nil, QuillSpeechRecognitionError(reason: "Speech recognition is unavailable."))
            return task
        }

        #if os(Linux)
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "speechRecognitionTask",
            severity: .info,
            message: shouldReportPartialResults
                ? "Speech recognition delivered a configured compatibility result with partial reporting enabled."
                : "Speech recognition delivered a configured compatibility result."
        )
        #endif
        resultHandler(state.result, nil)
        return task
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

public enum QuillLocalAuthenticationPolicy: Int, Sendable {
    case deviceOwnerAuthenticationWithBiometrics = 1
    case deviceOwnerAuthentication = 2
}

public enum QuillBiometryType: Int, Sendable {
    case none = 0
    case touchID = 1
    case faceID = 2
    case opticID = 4
}

public enum QuillLocalAuthenticationErrorCode: Int, Sendable {
    case authenticationFailed = -1
    case userCancel = -2
    case userFallback = -3
    case systemCancel = -4
    case passcodeNotSet = -5
    case biometryNotAvailable = -106
    case biometryNotEnrolled = -107
    case biometryLockout = -108
    case notInteractive = -1004
}

public final class QuillLocalAuthenticationService: @unchecked Sendable {
    public static let shared = QuillLocalAuthenticationService()

    private let lock = NSLock()
    private var canEvaluatePolicyValue = false
    private var canEvaluateErrorCode: QuillLocalAuthenticationErrorCode?
    private var evaluationSucceeds = false
    private var evaluationErrorCode: QuillLocalAuthenticationErrorCode = .authenticationFailed
    private var currentBiometryType: QuillBiometryType = .none

    public init() {}

    public var biometryType: QuillBiometryType {
        lock.withLock { currentBiometryType }
    }

    public func configure(
        canEvaluatePolicy: Bool,
        biometryType: QuillBiometryType = .none,
        canEvaluateError: QuillLocalAuthenticationErrorCode? = nil,
        evaluationSucceeds: Bool,
        evaluationError: QuillLocalAuthenticationErrorCode = .authenticationFailed
    ) {
        lock.withLock {
            canEvaluatePolicyValue = canEvaluatePolicy
            canEvaluateErrorCode = canEvaluateError
            self.evaluationSucceeds = evaluationSucceeds
            evaluationErrorCode = evaluationError
            currentBiometryType = biometryType
        }
    }

    public func reset() {
        lock.withLock {
            canEvaluatePolicyValue = false
            canEvaluateErrorCode = nil
            evaluationSucceeds = false
            evaluationErrorCode = .authenticationFailed
            currentBiometryType = .none
        }
    }

    public func canEvaluatePolicy(
        _ policy: QuillLocalAuthenticationPolicy
    ) -> (canEvaluate: Bool, error: QuillLocalAuthenticationErrorCode?) {
        let state = lock.withLock {
            (canEvaluatePolicyValue, canEvaluateErrorCode)
        }
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "localAuthentication.canEvaluatePolicy",
            severity: state.0 ? .info : .unsupported,
            message: "Local authentication policy \(policy.rawValue) is evaluated by the QuillKit compatibility backend."
        )
        return state
    }

    public func evaluatePolicy(
        _ policy: QuillLocalAuthenticationPolicy,
        localizedReason: String
    ) -> (success: Bool, error: QuillLocalAuthenticationErrorCode?) {
        let state = lock.withLock {
            (evaluationSucceeds, evaluationErrorCode)
        }
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "localAuthentication.evaluatePolicy",
            severity: state.0 ? .info : .unsupported,
            message: "Local authentication policy \(policy.rawValue) for '\(localizedReason)' is evaluated by the QuillKit compatibility backend."
        )
        return (state.0, state.0 ? nil : state.1)
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

public struct QuillHotKeyGesture: Hashable, Sendable {
    public var key: String
    public var modifiers: [String]

    public init(key: String, modifiers: [String] = []) {
        self.key = key
        self.modifiers = Array(Set(modifiers)).sorted()
    }
}

public struct QuillHotKeyDescriptor: Hashable, Sendable {
    public var identifier: String
    public var gesture: QuillHotKeyGesture

    public init(identifier: String, key: String, modifiers: [String] = []) {
        self.identifier = identifier
        self.gesture = QuillHotKeyGesture(key: key, modifiers: modifiers)
    }

    public init(identifier: String, gesture: QuillHotKeyGesture) {
        self.identifier = identifier
        self.gesture = gesture
    }
}

public final class QuillHotKeyRegistration: @unchecked Sendable {
    fileprivate let token = UUID()
    public let descriptor: QuillHotKeyDescriptor?
    private let action: @Sendable () -> Void
    private let service: QuillHotkeyService?
    private let lock = NSLock()
    private var standaloneIsRegistered = true

    public init(action: @escaping @Sendable () -> Void) {
        self.descriptor = nil
        self.service = nil
        self.action = action
    }

    fileprivate init(
        descriptor: QuillHotKeyDescriptor,
        service: QuillHotkeyService,
        action: @escaping @Sendable () -> Void
    ) {
        self.descriptor = descriptor
        self.service = service
        self.action = action
    }

    public var isRegistered: Bool {
        if let service {
            return service.isRegistered(self)
        }
        return lock.withLock { standaloneIsRegistered }
    }

    public func unregister() {
        if let service {
            service.unregister(self)
            return
        }
        lock.withLock {
            standaloneIsRegistered = false
        }
    }

    @discardableResult
    public func trigger() -> Bool {
        if let service {
            return service.trigger(self)
        }

        let shouldTrigger = lock.withLock { standaloneIsRegistered }
        guard shouldTrigger else {
            return false
        }
        action()
        return true
    }
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
        if let override = ProcessInfo.processInfo.environment["QUILLUI_ACCESSIBILITY_TRUSTED"] {
            return ["1", "true", "yes", "on"].contains(override.lowercased())
        }
        return false
        #else
        return true
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

    private let lock = NSLock()
    private var updateChecksAreEnabled = false
    private var updateCheckCountValue = 0
    private var lastUpdateCheckDate: Date?

    public init() {}

    public var canCheckForUpdates: Bool {
        lock.withLock { updateChecksAreEnabled }
    }

    public var updateCheckCount: Int {
        lock.withLock { updateCheckCountValue }
    }

    public var lastCheckDate: Date? {
        lock.withLock { lastUpdateCheckDate }
    }

    public func configure(canCheckForUpdates: Bool) {
        lock.withLock {
            updateChecksAreEnabled = canCheckForUpdates
        }
    }

    public func reset() {
        lock.withLock {
            updateChecksAreEnabled = false
            updateCheckCountValue = 0
            lastUpdateCheckDate = nil
        }
    }

    public func checkForUpdates() {
        lock.withLock {
            updateCheckCountValue += 1
            lastUpdateCheckDate = Date()
        }

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

    private struct HotKeyRecord {
        var descriptor: QuillHotKeyDescriptor
        var action: @Sendable () -> Void
    }

    private let lock = NSLock()
    private let diagnostics: QuillCompatibilityDiagnostics
    private var recordsByToken: [UUID: HotKeyRecord] = [:]
    private var tokensByIdentifier: [String: UUID] = [:]
    private var tokensByGesture: [QuillHotKeyGesture: UUID] = [:]

    public init(diagnostics: QuillCompatibilityDiagnostics = .shared) {
        self.diagnostics = diagnostics
    }

    @discardableResult
    public func register(
        descriptor: QuillHotKeyDescriptor,
        action: @escaping @Sendable () -> Void
    ) -> QuillHotKeyRegistration {
        let registration = QuillHotKeyRegistration(
            descriptor: descriptor,
            service: self,
            action: action
        )

        let conflict = lock.withLock { () -> String? in
            if tokensByIdentifier[descriptor.identifier] != nil {
                return "identifier '\(descriptor.identifier)' is already registered"
            }
            if tokensByGesture[descriptor.gesture] != nil {
                let modifiers = descriptor.gesture.modifiers.joined(separator: "+")
                return "gesture '\(descriptor.gesture.key)' with modifiers \(modifiers) is already registered"
            }

            recordsByToken[registration.token] = HotKeyRecord(
                descriptor: descriptor,
                action: action
            )
            tokensByIdentifier[descriptor.identifier] = registration.token
            tokensByGesture[descriptor.gesture] = registration.token
            return nil
        }

        if let conflict {
            diagnostics.record(
                subsystem: "QuillKit",
                operation: "registerHotKey",
                severity: .warning,
                message: "Hot key registration skipped because \(conflict)."
            )
        } else {
            #if os(Linux)
            diagnostics.record(
                subsystem: "QuillKit",
                operation: "registerHotKey",
                severity: .info,
                message: "Hot key '\(descriptor.identifier)' is registered in the process-local compatibility registry."
            )
            #endif
        }

        return registration
    }

    public func unregister(_ registration: QuillHotKeyRegistration) {
        lock.withLock {
            guard let record = recordsByToken.removeValue(forKey: registration.token) else {
                return
            }
            tokensByIdentifier.removeValue(forKey: record.descriptor.identifier)
            tokensByGesture.removeValue(forKey: record.descriptor.gesture)
        }
    }

    public func isRegistered(_ registration: QuillHotKeyRegistration) -> Bool {
        lock.withLock {
            recordsByToken[registration.token] != nil
        }
    }

    @discardableResult
    public func trigger(_ registration: QuillHotKeyRegistration) -> Bool {
        let action = lock.withLock {
            recordsByToken[registration.token]?.action
        }

        guard let action else {
            return false
        }

        action()
        return true
    }

    @discardableResult
    public func trigger(identifier: String) -> Bool {
        let action = lock.withLock { () -> (@Sendable () -> Void)? in
            guard let token = tokensByIdentifier[identifier] else {
                return nil
            }
            return recordsByToken[token]?.action
        }

        guard let action else {
            return false
        }

        action()
        return true
    }

    @discardableResult
    public func trigger(key: String, modifiers: [String] = []) -> Bool {
        let gesture = QuillHotKeyGesture(key: key, modifiers: modifiers)
        let action = lock.withLock { () -> (@Sendable () -> Void)? in
            guard let token = tokensByGesture[gesture] else {
                return nil
            }
            return recordsByToken[token]?.action
        }

        guard let action else {
            return false
        }

        action()
        return true
    }

    public var registeredHotKeys: [QuillHotKeyDescriptor] {
        lock.withLock {
            recordsByToken.values.map(\.descriptor).sorted { lhs, rhs in
                lhs.identifier < rhs.identifier
            }
        }
    }

    public func unregisterAll() {
        lock.withLock {
            recordsByToken.removeAll()
            tokensByIdentifier.removeAll()
            tokensByGesture.removeAll()
        }
    }

    @discardableResult
    public func registerSingleUseSpace<ModifierSet>(
        modifiers: ModifierSet,
        handler: () -> AnyObject?
    ) -> AnyObject? {
        let registration = register(
            descriptor: QuillHotKeyDescriptor(identifier: "single-use-space", key: "space", modifiers: ["single-use"]),
            action: {}
        )
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "registerSingleUseSpace",
            severity: .info,
            message: "Single-use space hotkey is tracked in the process-local compatibility registry."
        )
        registration.unregister()
        return handler()
    }
}

public enum QuillNotificationAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
    case ephemeral = 4
}

public struct QuillNotificationRequestRecord: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var subtitle: String
    public var body: String
    public var categoryIdentifier: String
    public var threadIdentifier: String

    public init(
        identifier: String,
        title: String = "",
        subtitle: String = "",
        body: String = "",
        categoryIdentifier: String = "",
        threadIdentifier: String = ""
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.threadIdentifier = threadIdentifier
    }
}

public final class QuillNotificationService: @unchecked Sendable {
    public static let shared = QuillNotificationService()

    public struct PresentationBackend: Sendable {
        public var name: String
        public var present: @Sendable (QuillNotificationRequestRecord) -> Bool

        public init(name: String, present: @escaping @Sendable (QuillNotificationRequestRecord) -> Bool) {
            self.name = name
            self.present = present
        }
    }

    private let lock = NSLock()
    private var currentAuthorizationStatus: QuillNotificationAuthorizationStatus = .notDetermined
    private var nextAuthorizationRequestResult = false
    private var categoryIdentifiersValue: Set<String> = []
    private var pendingRequestsByIdentifier: [String: QuillNotificationRequestRecord] = [:]
    private var deliveredNotificationsByIdentifier: [String: QuillNotificationRequestRecord] = [:]
    private var remoteNotificationsRegisteredValue = false
    private var remoteNotificationRegistrationCountValue = 0
    private var presentationBackend: PresentationBackend?

    public init() {}

    public var authorizationStatus: QuillNotificationAuthorizationStatus {
        lock.withLock { currentAuthorizationStatus }
    }

    public var categoryIdentifiers: [String] {
        lock.withLock { categoryIdentifiersValue.sorted() }
    }

    public var pendingRequestRecords: [QuillNotificationRequestRecord] {
        lock.withLock {
            pendingRequestsByIdentifier.values.sorted { $0.identifier < $1.identifier }
        }
    }

    public var deliveredNotificationRecords: [QuillNotificationRequestRecord] {
        lock.withLock {
            deliveredNotificationsByIdentifier.values.sorted { $0.identifier < $1.identifier }
        }
    }

    public var remoteNotificationsRegistered: Bool {
        lock.withLock { remoteNotificationsRegisteredValue }
    }

    public var remoteNotificationRegistrationCount: Int {
        lock.withLock { remoteNotificationRegistrationCountValue }
    }

    public func installPresentationBackend(_ backend: PresentationBackend?) {
        lock.withLock {
            presentationBackend = backend
        }
    }

    public func configureAuthorization(
        status: QuillNotificationAuthorizationStatus,
        requestResult: Bool
    ) {
        lock.withLock {
            currentAuthorizationStatus = status
            nextAuthorizationRequestResult = requestResult
        }
    }

    public func reset() {
        lock.withLock {
            currentAuthorizationStatus = .notDetermined
            nextAuthorizationRequestResult = false
            categoryIdentifiersValue.removeAll()
            pendingRequestsByIdentifier.removeAll()
            deliveredNotificationsByIdentifier.removeAll()
            remoteNotificationsRegisteredValue = false
            remoteNotificationRegistrationCountValue = 0
            presentationBackend = nil
        }
    }

    @discardableResult
    public func requestAuthorization(optionsRawValue: UInt) -> Bool {
        let granted = lock.withLock { () -> Bool in
            let granted = nextAuthorizationRequestResult
            currentAuthorizationStatus = granted ? .authorized : .denied
            return granted
        }

        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "notifications.requestAuthorization",
            severity: granted ? .info : .unsupported,
            message: "Notification authorization is handled by the QuillKit compatibility backend for options raw value \(optionsRawValue)."
        )
        return granted
    }

    public func setCategories(_ identifiers: Set<String>) {
        lock.withLock {
            categoryIdentifiersValue = identifiers
        }

        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "notifications.setCategories",
            severity: .info,
            message: "Stored \(identifiers.count) notification categories in the process-local compatibility backend."
        )
    }

    public func addRequest(
        _ record: QuillNotificationRequestRecord,
        deliverImmediately: Bool
    ) {
        let backend = lock.withLock { () -> PresentationBackend? in
            if deliverImmediately {
                pendingRequestsByIdentifier.removeValue(forKey: record.identifier)
                deliveredNotificationsByIdentifier[record.identifier] = record
            } else {
                deliveredNotificationsByIdentifier.removeValue(forKey: record.identifier)
                pendingRequestsByIdentifier[record.identifier] = record
            }
            return presentationBackend
        }

        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "notifications.addRequest",
            severity: .info,
            message: "Stored notification request '\(record.identifier)' in the process-local compatibility backend."
        )

        if deliverImmediately {
            presentDeliveredNotification(record, using: backend)
        }
    }

    private func presentDeliveredNotification(
        _ record: QuillNotificationRequestRecord,
        using backend: PresentationBackend?
    ) {
        if let backend {
            let didPresent = backend.present(record)
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillKit",
                operation: "notifications.present",
                severity: didPresent ? .info : .unsupported,
                message: "Notification request '\(record.identifier)' presentation was handled by \(backend.name)."
            )
            return
        }

        #if os(Linux)
        guard Self.linuxDesktopNotificationsAvailable else {
            recordNotificationPresentationUnavailable(
                record,
                reason: "notify-send requires /usr/bin/notify-send plus a desktop notification session on Linux."
            )
            return
        }

        let title = record.title.isEmpty ? "Notification" : record.title
        let message = [record.subtitle, record.body].filter { !$0.isEmpty }.joined(separator: "\n")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/notify-send")
        process.arguments = message.isEmpty
            ? ["--app-name=QuillUI", title]
            : ["--app-name=QuillUI", title, message]
        do {
            try process.run()
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillKit",
                operation: "notifications.present",
                severity: .info,
                message: "Notification request '\(record.identifier)' was sent through notify-send."
            )
        } catch {
            recordNotificationPresentationUnavailable(
                record,
                reason: "notify-send could not be launched: \(error.localizedDescription)"
            )
        }
        #else
        recordNotificationPresentationUnavailable(
            record,
            reason: "no desktop notification presentation backend is installed."
        )
        #endif
    }

    #if os(Linux)
    private static var linuxDesktopNotificationsAvailable: Bool {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/notify-send") else {
            return false
        }

        let env = ProcessInfo.processInfo.environment
        return env["DBUS_SESSION_BUS_ADDRESS"]?.isEmpty == false ||
            env["DISPLAY"]?.isEmpty == false ||
            env["WAYLAND_DISPLAY"]?.isEmpty == false
    }
    #endif

    private func recordNotificationPresentationUnavailable(
        _ record: QuillNotificationRequestRecord,
        reason: String
    ) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "notifications.present",
            severity: .unsupported,
            message: "Notification request '\(record.identifier)' was not presented: \(reason)"
        )
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        lock.withLock {
            for identifier in identifiers {
                deliveredNotificationsByIdentifier.removeValue(forKey: identifier)
            }
        }
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            for identifier in identifiers {
                pendingRequestsByIdentifier.removeValue(forKey: identifier)
            }
        }
    }

    public func removeAllDeliveredNotifications() {
        lock.withLock {
            deliveredNotificationsByIdentifier.removeAll()
        }
    }

    public func removeAllPendingNotificationRequests() {
        lock.withLock {
            pendingRequestsByIdentifier.removeAll()
        }
    }

    public func registerForRemoteNotifications() {
        lock.withLock {
            remoteNotificationsRegisteredValue = true
            remoteNotificationRegistrationCountValue += 1
        }

        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "notifications.registerForRemoteNotifications",
            severity: .info,
            message: "Remote notification registration is tracked by the QuillKit compatibility backend."
        )
    }

    public func unregisterForRemoteNotifications() {
        lock.withLock {
            remoteNotificationsRegisteredValue = false
        }
    }
}

public enum QuillAudioSessionCategory: Int, Sendable {
    case ambient = 0
    case soloAmbient = 1
    case playback = 2
    case record = 3
    case playAndRecord = 4
    case multiRoute = 5
}

public enum QuillAudioSessionMode: Int, Sendable {
    case videoChat = 0
    case videoRecording = 1
    case measurement = 2
    case moviePlayback = 3
    case spokenAudio = 4
}

public final class QuillAudioSessionService: @unchecked Sendable {
    public static let shared = QuillAudioSessionService()

    private let lock = NSLock()
    private var categoryValue: QuillAudioSessionCategory = .ambient
    private var modeValue: QuillAudioSessionMode = .spokenAudio
    private var categoryOptionsRawValueValue: UInt = 0
    private var activeValue = false
    private var setActiveOptionsRawValueValue: UInt = 0

    public init() {}

    public var category: QuillAudioSessionCategory {
        lock.withLock { categoryValue }
    }

    public var mode: QuillAudioSessionMode {
        lock.withLock { modeValue }
    }

    public var categoryOptionsRawValue: UInt {
        lock.withLock { categoryOptionsRawValueValue }
    }

    public var isActive: Bool {
        lock.withLock { activeValue }
    }

    public var setActiveOptionsRawValue: UInt {
        lock.withLock { setActiveOptionsRawValueValue }
    }

    public func reset() {
        lock.withLock {
            categoryValue = .ambient
            modeValue = .spokenAudio
            categoryOptionsRawValueValue = 0
            activeValue = false
            setActiveOptionsRawValueValue = 0
        }
    }

    public func setCategory(
        _ category: QuillAudioSessionCategory,
        mode: QuillAudioSessionMode,
        optionsRawValue: UInt = 0
    ) {
        lock.withLock {
            categoryValue = category
            modeValue = mode
            categoryOptionsRawValueValue = optionsRawValue
        }

        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "audioSession.setCategory",
            severity: .info,
            message: "Audio session category and mode are tracked by the QuillKit compatibility backend."
        )
    }

    public func setActive(_ active: Bool, optionsRawValue: UInt = 0) {
        lock.withLock {
            activeValue = active
            setActiveOptionsRawValueValue = optionsRawValue
        }

        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "audioSession.setActive",
            severity: .info,
            message: "Audio session active state is tracked by the QuillKit compatibility backend."
        )
    }
}

public struct QuillAudioEngineState: Equatable, Sendable {
    public var engineID: UUID
    public var isPrepared: Bool
    public var isRunning: Bool
    public var attachedNodeCount: Int
    public var connectionCount: Int
    public var tapCount: Int

    public init(
        engineID: UUID,
        isPrepared: Bool = false,
        isRunning: Bool = false,
        attachedNodeCount: Int = 0,
        connectionCount: Int = 0,
        tapCount: Int = 0
    ) {
        self.engineID = engineID
        self.isPrepared = isPrepared
        self.isRunning = isRunning
        self.attachedNodeCount = attachedNodeCount
        self.connectionCount = connectionCount
        self.tapCount = tapCount
    }
}

public final class QuillAudioEngineService: @unchecked Sendable {
    public static let shared = QuillAudioEngineService()

    private let lock = NSLock()
    private var statesByEngineID: [UUID: QuillAudioEngineState] = [:]
    private var tapsByNodeAndBus: Set<String> = []

    public init() {}

    public var engineStates: [QuillAudioEngineState] {
        lock.withLock {
            statesByEngineID.values.sorted { lhs, rhs in
                lhs.engineID.uuidString < rhs.engineID.uuidString
            }
        }
    }

    public func resetAll() {
        lock.withLock {
            statesByEngineID.removeAll()
            tapsByNodeAndBus.removeAll()
        }
    }

    public func state(for engineID: UUID) -> QuillAudioEngineState {
        lock.withLock {
            state(for: engineID, in: &statesByEngineID)
        }
    }

    public func registerEngine(_ engineID: UUID) {
        lock.withLock {
            _ = state(for: engineID, in: &statesByEngineID)
        }
    }

    public func prepare(engineID: UUID) {
        update(engineID: engineID, operation: "audioEngine.prepare") {
            $0.isPrepared = true
        }
    }

    public func start(engineID: UUID) {
        update(engineID: engineID, operation: "audioEngine.start") {
            $0.isPrepared = true
            $0.isRunning = true
        }
    }

    public func stop(engineID: UUID) {
        update(engineID: engineID, operation: "audioEngine.stop") {
            $0.isRunning = false
        }
    }

    public func reset(engineID: UUID) {
        update(engineID: engineID, operation: "audioEngine.reset") {
            $0.isPrepared = false
            $0.isRunning = false
            $0.attachedNodeCount = 0
            $0.connectionCount = 0
            $0.tapCount = 0
        }
        lock.withLock {
            tapsByNodeAndBus.removeAll()
        }
    }

    public func attachNode(engineID: UUID) {
        update(engineID: engineID, operation: "audioEngine.attach") {
            $0.attachedNodeCount += 1
        }
    }

    public func connect(engineID: UUID) {
        update(engineID: engineID, operation: "audioEngine.connect") {
            $0.connectionCount += 1
        }
    }

    public func installTap(engineID: UUID?, nodeID: UUID, bus: Int) {
        let key = "\(nodeID.uuidString):\(bus)"
        let didInsert = lock.withLock {
            tapsByNodeAndBus.insert(key).inserted
        }

        if let engineID, didInsert {
            update(engineID: engineID, operation: "audioEngine.installTap") {
                $0.tapCount += 1
            }
        } else {
            record(operation: "audioEngine.installTap")
        }
    }

    public func removeTap(engineID: UUID?, nodeID: UUID, bus: Int) {
        let key = "\(nodeID.uuidString):\(bus)"
        let didRemove = lock.withLock {
            tapsByNodeAndBus.remove(key) != nil
        }

        if let engineID, didRemove {
            update(engineID: engineID, operation: "audioEngine.removeTap") {
                $0.tapCount = max(0, $0.tapCount - 1)
            }
        } else {
            record(operation: "audioEngine.removeTap")
        }
    }

    private func update(
        engineID: UUID,
        operation: String,
        mutate: (inout QuillAudioEngineState) -> Void
    ) {
        lock.withLock {
            var current = state(for: engineID, in: &statesByEngineID)
            mutate(&current)
            statesByEngineID[engineID] = current
        }
        record(operation: operation)
    }

    private func state(
        for engineID: UUID,
        in states: inout [UUID: QuillAudioEngineState]
    ) -> QuillAudioEngineState {
        if let state = states[engineID] {
            return state
        }
        let state = QuillAudioEngineState(engineID: engineID)
        states[engineID] = state
        return state
    }

    private func record(operation: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: operation,
            severity: .info,
            message: "Audio engine state is tracked by the QuillKit compatibility backend."
        )
    }
}

public enum QuillAudioPlayerSource: Equatable, Sendable {
    case data(byteCount: Int)
    case url(URL)
    case named(String)
    case beep
}

public struct QuillAudioPlayerState: Equatable, Sendable {
    public var playerID: UUID
    public var source: QuillAudioPlayerSource
    public var duration: TimeInterval
    public var numberOfChannels: Int
    public var isPrepared: Bool
    public var isPlaying: Bool
    public var playCount: Int
    public var pauseCount: Int
    public var stopCount: Int
    public var currentTime: TimeInterval
    public var volume: Float
    public var numberOfLoops: Int

    public init(
        playerID: UUID,
        source: QuillAudioPlayerSource,
        duration: TimeInterval = 0,
        numberOfChannels: Int = 0,
        isPrepared: Bool = false,
        isPlaying: Bool = false,
        playCount: Int = 0,
        pauseCount: Int = 0,
        stopCount: Int = 0,
        currentTime: TimeInterval = 0,
        volume: Float = 1,
        numberOfLoops: Int = 0
    ) {
        self.playerID = playerID
        self.source = source
        self.duration = duration
        self.numberOfChannels = numberOfChannels
        self.isPrepared = isPrepared
        self.isPlaying = isPlaying
        self.playCount = playCount
        self.pauseCount = pauseCount
        self.stopCount = stopCount
        self.currentTime = currentTime
        self.volume = volume
        self.numberOfLoops = numberOfLoops
    }
}

public struct QuillSystemSoundRecord: Equatable, Sendable {
    public var soundID: UInt32
    public var url: URL?
    public var isDisposed: Bool
    public var playCount: Int
    public var alertPlayCount: Int
    public var completionRegistrationCount: Int

    public init(
        soundID: UInt32,
        url: URL? = nil,
        isDisposed: Bool = false,
        playCount: Int = 0,
        alertPlayCount: Int = 0,
        completionRegistrationCount: Int = 0
    ) {
        self.soundID = soundID
        self.url = url
        self.isDisposed = isDisposed
        self.playCount = playCount
        self.alertPlayCount = alertPlayCount
        self.completionRegistrationCount = completionRegistrationCount
    }
}

public final class QuillAudioPlayerService: @unchecked Sendable {
    public static let shared = QuillAudioPlayerService()

    private let lock = NSLock()
    private var statesByPlayerID: [UUID: QuillAudioPlayerState] = [:]
    private var systemSoundsByID: [UInt32: QuillSystemSoundRecord] = [:]
    private var nextSystemSoundID: UInt32 = 1

    public init() {}

    public var playerStates: [QuillAudioPlayerState] {
        lock.withLock {
            statesByPlayerID.values.sorted { lhs, rhs in
                lhs.playerID.uuidString < rhs.playerID.uuidString
            }
        }
    }

    public var systemSoundRecords: [QuillSystemSoundRecord] {
        lock.withLock {
            systemSoundsByID.values.sorted { lhs, rhs in
                lhs.soundID < rhs.soundID
            }
        }
    }

    public func resetAll() {
        lock.withLock {
            statesByPlayerID.removeAll()
            systemSoundsByID.removeAll()
            nextSystemSoundID = 1
        }
    }

    public func registerPlayer(
        _ playerID: UUID,
        source: QuillAudioPlayerSource,
        duration: TimeInterval = 0,
        numberOfChannels: Int = 0
    ) {
        lock.withLock {
            statesByPlayerID[playerID] = QuillAudioPlayerState(
                playerID: playerID,
                source: source,
                duration: max(0, duration),
                numberOfChannels: max(0, numberOfChannels)
            )
        }
    }

    public func state(for playerID: UUID) -> QuillAudioPlayerState? {
        lock.withLock { statesByPlayerID[playerID] }
    }

    @discardableResult
    public func prepareToPlay(playerID: UUID) -> Bool {
        updatePlayer(playerID, operation: "audioPlayer.prepareToPlay") {
            $0.isPrepared = true
        }
    }

    @discardableResult
    public func play(playerID: UUID, atTime startTime: TimeInterval? = nil) -> Bool {
        updatePlayer(playerID, operation: "audioPlayer.play") {
            if let startTime {
                $0.currentTime = max(0, startTime)
            }
            $0.isPrepared = true
            $0.isPlaying = true
            $0.playCount += 1
        }
    }

    public func pause(playerID: UUID) {
        _ = updatePlayer(playerID, operation: "audioPlayer.pause") {
            $0.isPlaying = false
            $0.pauseCount += 1
        }
    }

    @discardableResult
    public func stop(playerID: UUID) -> Bool {
        updatePlayer(playerID, operation: "audioPlayer.stop") {
            $0.isPlaying = false
            $0.stopCount += 1
        }
    }

    public func setCurrentTime(_ currentTime: TimeInterval, playerID: UUID) {
        updatePlayerWithoutDiagnostics(playerID) {
            $0.currentTime = max(0, currentTime)
        }
    }

    public func setVolume(_ volume: Float, playerID: UUID) {
        updatePlayerWithoutDiagnostics(playerID) {
            $0.volume = min(max(volume, 0), 1)
        }
    }

    public func setNumberOfLoops(_ numberOfLoops: Int, playerID: UUID) {
        updatePlayerWithoutDiagnostics(playerID) {
            $0.numberOfLoops = numberOfLoops
        }
    }

    public func createSystemSoundID(url: URL) -> UInt32 {
        let soundID = lock.withLock {
            let soundID = nextAvailableSystemSoundID()
            systemSoundsByID[soundID] = QuillSystemSoundRecord(soundID: soundID, url: url)
            return soundID
        }
        record(operation: "audioSystemSound.create")
        return soundID
    }

    public func disposeSystemSoundID(_ soundID: UInt32) {
        updateSystemSound(soundID, operation: "audioSystemSound.dispose") {
            $0.isDisposed = true
        }
    }

    public func playSystemSound(_ soundID: UInt32, alert: Bool = false) {
        updateSystemSound(soundID, operation: alert ? "audioSystemSound.playAlert" : "audioSystemSound.play") {
            if alert {
                $0.alertPlayCount += 1
            } else {
                $0.playCount += 1
            }
        }
    }

    public func addSystemSoundCompletion(_ soundID: UInt32) {
        updateSystemSound(soundID, operation: "audioSystemSound.addCompletion") {
            $0.completionRegistrationCount += 1
        }
    }

    public func removeSystemSoundCompletion(_ soundID: UInt32) {
        updateSystemSound(soundID, operation: "audioSystemSound.removeCompletion") {
            $0.completionRegistrationCount = 0
        }
    }

    public func beep() {
        let playerID = UUID()
        registerPlayer(playerID, source: .beep)
        _ = play(playerID: playerID)
        record(operation: "audioSystemSound.beep")
    }

    @discardableResult
    private func updatePlayer(
        _ playerID: UUID,
        operation: String,
        mutate: (inout QuillAudioPlayerState) -> Void
    ) -> Bool {
        let didUpdate = updatePlayerWithoutDiagnostics(playerID, mutate: mutate)
        if didUpdate {
            record(operation: operation)
        }
        return didUpdate
    }

    @discardableResult
    private func updatePlayerWithoutDiagnostics(
        _ playerID: UUID,
        mutate: (inout QuillAudioPlayerState) -> Void
    ) -> Bool {
        lock.withLock {
            guard var state = statesByPlayerID[playerID] else {
                return false
            }
            mutate(&state)
            statesByPlayerID[playerID] = state
            return true
        }
    }

    private func updateSystemSound(
        _ soundID: UInt32,
        operation: String,
        mutate: (inout QuillSystemSoundRecord) -> Void
    ) {
        lock.withLock {
            var record = systemSoundsByID[soundID] ?? QuillSystemSoundRecord(soundID: soundID)
            mutate(&record)
            systemSoundsByID[soundID] = record
        }
        record(operation: operation)
    }

    private func nextAvailableSystemSoundID() -> UInt32 {
        while systemSoundsByID[nextSystemSoundID] != nil || nextSystemSoundID == 0 {
            nextSystemSoundID &+= 1
            if nextSystemSoundID == 0 {
                nextSystemSoundID = 1
            }
        }
        let soundID = nextSystemSoundID
        nextSystemSoundID &+= 1
        if nextSystemSoundID == 0 {
            nextSystemSoundID = 1
        }
        return soundID
    }

    private func record(operation: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: operation,
            severity: .info,
            message: "Audio playback state is tracked by the QuillKit compatibility backend."
        )
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

public enum QuillUSBLauncher {
    public static func install(
        label: String = "co.lorehex.quillchat.usb-launcher",
        subsystem: String = "co.lorehex.quillchat"
    ) {
        QuillDeviceLauncher.install(label: label, subsystem: subsystem)
    }
}

#if os(Linux)
public enum QuillURLSessionFixtures {
    public static let fixtureFileEnvironmentKey = "QUILLUI_URLSESSION_FIXTURES_FILE"
    public static let debugEnvironmentKey = "QUILLUI_URLSESSION_FIXTURES_DEBUG"
    public static let responseDelayMillisecondsEnvironmentKey = "QUILLUI_URLSESSION_FIXTURE_RESPONSE_DELAY_MS"

    private static let lock = NSRecursiveLock()
    nonisolated(unsafe) private static var installed = false

    public static func installIfConfigured(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let path = environment[fixtureFileEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return
        }
        install(fixtureFileURL: URL(fileURLWithPath: path))
    }

    public static func install(fixtureFileURL: URL) {
        lock.withLock {
            QuillURLSessionFixtureProtocol.configure(fixtureFileURL: fixtureFileURL)
            if !installed {
                _ = URLProtocol.registerClass(QuillURLSessionFixtureProtocol.self)
                installed = true
            }
        }
    }

    public static func resetForTesting() {
        lock.withLock {
            if installed {
                URLProtocol.unregisterClass(QuillURLSessionFixtureProtocol.self)
                installed = false
            }
            QuillURLSessionFixtureProtocol.configure(fixtureFileURL: nil)
        }
    }

    public static func data(
        for request: URLRequest,
        fallbackSession: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        if let fixtureResponse = QuillURLSessionFixtureProtocol.directResponse(for: request) {
            return fixtureResponse
        }
        return try await fallbackSession.data(for: request)
    }

    public static func data(
        from url: URL,
        fallbackSession: URLSession = .shared
    ) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url), fallbackSession: fallbackSession)
    }

    public static func upload(
        for request: URLRequest,
        from bodyData: Data,
        fallbackSession: URLSession = .shared,
        delegate: URLSessionTaskDelegate? = nil
    ) async throws -> (Data, URLResponse) {
        if let fixtureResponse = QuillURLSessionFixtureProtocol.directResponse(for: request) {
            return fixtureResponse
        }
        return try await fallbackSession.upload(for: request, from: bodyData, delegate: delegate)
    }
}

private final class QuillURLSessionFixtureProtocol: URLProtocol {
    private let stateLock = NSLock()
    private var stopped = false
    private var finished = false

    private struct Fixture: Sendable {
        var method: String?
        var host: String?
        var path: String?
        var pathPattern: String?
        var pathPrefix: String?
        var query: String?
        var requestHeaders: [String: String]
        var requestBodyJSON: Data?
        var statusCode: Int
        var headers: [String: String]
        var body: Data

        func matches(_ request: URLRequest) -> Bool {
            guard let url = request.url else { return false }
            if let method, method != (request.httpMethod ?? "GET").uppercased() {
                return false
            }
            if let host, host != url.host {
                return false
            }
            if let path, path != url.path {
                return false
            }
            if let pathPattern, !Self.path(url.path, matchesPattern: pathPattern) {
                return false
            }
            if let pathPrefix, !url.path.hasPrefix(pathPrefix) {
                return false
            }
            if let query, query != (url.query ?? "") {
                return false
            }
            for (field, expectedValue) in requestHeaders
                where request.value(forHTTPHeaderField: field) != expectedValue {
                return false
            }
            if let requestBodyJSON,
               !Self.requestBody(request.httpBody, matchesJSON: requestBodyJSON) {
                return false
            }
            return true
        }

        private static func requestBody(_ body: Data?, matchesJSON expected: Data) -> Bool {
            guard let body,
                  let object = try? JSONSerialization.jsonObject(with: body),
                  JSONSerialization.isValidJSONObject(object),
                  let canonical = try? JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys]
                  ) else {
                return false
            }
            return canonical == expected
        }

        private static func path(_ path: String, matchesPattern pattern: String) -> Bool {
            let pathComponents = path.split(separator: "/", omittingEmptySubsequences: false)
            let patternComponents = pattern.split(separator: "/", omittingEmptySubsequences: false)
            var pathIndex = 0
            var patternIndex = 0

            while patternIndex < patternComponents.count {
                let token = patternComponents[patternIndex]
                if token == "**" {
                    return true
                }
                guard pathIndex < pathComponents.count else {
                    return false
                }
                let pathComponent = pathComponents[pathIndex]
                let isPlaceholder = token.hasPrefix("{") && token.hasSuffix("}") && token.count > 2
                if token != "*" && !isPlaceholder && token != pathComponent {
                    return false
                }
                if (token == "*" || isPlaceholder) && pathComponent.isEmpty {
                    return false
                }
                pathIndex += 1
                patternIndex += 1
            }

            return pathIndex == pathComponents.count
        }
    }

    private final class DeliveryContext: @unchecked Sendable {
        enum Result {
            case failure(URLError)
            case success(HTTPURLResponse, Fixture)
        }

        weak var owner: QuillURLSessionFixtureProtocol?
        let result: Result

        init(owner: QuillURLSessionFixtureProtocol, result: Result) {
            self.owner = owner
            self.result = result
        }

        func deliver() {
            guard let owner, owner.beginDelivery(), let client = owner.client else { return }
            switch result {
            case .failure(let error):
                QuillURLSessionFixtureProtocol.debugLog(
                    "deliver \(owner.debugIdentifier) failure \(owner.request.url?.absoluteString ?? "<nil>")"
                )
                client.urlProtocol(owner, didFailWithError: error)
            case .success(let response, let fixture):
                QuillURLSessionFixtureProtocol.debugLog(
                    "deliver \(owner.debugIdentifier) success \(owner.request.url?.absoluteString ?? "<nil>")"
                )
                QuillURLSessionFixtureProtocol.recordStateMutationIfNeeded(
                    for: owner.request,
                    fixture: fixture
                )
                client.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed)
                if !fixture.body.isEmpty {
                    client.urlProtocol(owner, didLoad: fixture.body)
                }
                client.urlProtocolDidFinishLoading(owner)
            }
        }
    }

    private static let lock = NSRecursiveLock()
    nonisolated(unsafe) private static var fixtureFileURL: URL?
    nonisolated(unsafe) private static var cachedFileSignature: String?
    nonisolated(unsafe) private static var cachedFixtures: [Fixture] = []
    nonisolated(unsafe) private static var cachedStatusBodiesByID: [String: Data] = [:]
    private static let deliveryQueue = DispatchQueue(label: "co.lorehex.QuillURLSessionFixtures.delivery")

    fileprivate static func configure(fixtureFileURL: URL?) {
        lock.withLock {
            self.fixtureFileURL = fixtureFileURL
            cachedFileSignature = nil
            cachedFixtures = []
            cachedStatusBodiesByID = [:]
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: "QuillURLSessionFixtureHandled", in: request) == nil else {
            return false
        }
        return fixture(matching: request) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let fixture = Self.fixture(matching: request), let url = request.url else {
            Self.debugLog("start \(debugIdentifier) unsupported \(request.url?.absoluteString ?? "<nil>")")
            let context = DeliveryContext(owner: self, result: .failure(URLError(.unsupportedURL)))
            Self.scheduleDelivery { context.deliver() }
            return
        }

        Self.debugLog("start \(debugIdentifier) \(request.httpMethod ?? "GET") \(url.absoluteString)")

        var responseHeaders = fixture.headers
        if responseHeaders["Content-Length"] == nil {
            responseHeaders["Content-Length"] = String(fixture.body.count)
        }
        if responseHeaders["Content-Type"] == nil {
            responseHeaders["Content-Type"] = "application/json"
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: fixture.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: responseHeaders
        )!

        let context = DeliveryContext(owner: self, result: .success(response, fixture))
        Self.scheduleDelivery { context.deliver() }
    }

    override func stopLoading() {
        stateLock.withLock {
            stopped = true
        }
        Self.debugLog("stop \(debugIdentifier) \(request.url?.absoluteString ?? "<nil>")")
    }

    private func beginDelivery() -> Bool {
        let shouldDeliver = stateLock.withLock {
            guard !stopped, !finished else { return false }
            finished = true
            return true
        }
        if !shouldDeliver {
            Self.debugLog("skip \(debugIdentifier) stopped-or-finished \(request.url?.absoluteString ?? "<nil>")")
        }
        return shouldDeliver
    }

    private var debugIdentifier: String {
        String(UInt(bitPattern: ObjectIdentifier(self)), radix: 16)
    }

    private static func scheduleDelivery(_ delivery: @escaping @Sendable () -> Void) {
        let delay = responseDelay()
        switch delay {
        case .never:
            deliveryQueue.async(execute: delivery)
        default:
            deliveryQueue.asyncAfter(deadline: .now() + delay, execute: delivery)
        }
    }

    private static func responseDelay() -> DispatchTimeInterval {
        let rawValue = ProcessInfo.processInfo.environment[
            QuillURLSessionFixtures.responseDelayMillisecondsEnvironmentKey
        ]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawValue, !rawValue.isEmpty, let milliseconds = Int(rawValue), milliseconds > 0 else {
            return .never
        }
        return .milliseconds(milliseconds)
    }

    private static func fixture(matching request: URLRequest) -> Fixture? {
        lock.withLock {
            loadFixturesIfNeeded()
            let match = cachedFixtures.first { $0.matches(request) }
            debugLog("\(match == nil ? "miss" : "match") \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "<nil>")")
            guard let match else { return nil }
            return fixtureApplyingStateOverlay(match, request: request)
        }
    }

    fileprivate static func directResponse(for request: URLRequest) -> (Data, URLResponse)? {
        guard let fixture = fixture(matching: request), let url = request.url else {
            return nil
        }

        var responseHeaders = fixture.headers
        if responseHeaders["Content-Length"] == nil {
            responseHeaders["Content-Length"] = String(fixture.body.count)
        }
        if responseHeaders["Content-Type"] == nil {
            responseHeaders["Content-Type"] = "application/json"
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: fixture.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: responseHeaders
        ) else {
            return nil
        }

        debugLog("direct \(request.httpMethod ?? "GET") \(url.absoluteString)")
        recordStateMutationIfNeeded(for: request, fixture: fixture)
        return (fixture.body, response)
    }

    private static func fixtureApplyingStateOverlay(
        _ fixture: Fixture,
        request: URLRequest
    ) -> Fixture {
        guard (request.httpMethod ?? "GET").uppercased() == "GET",
              let url = request.url else {
            return fixture
        }

        if let statusID = statusIDForStatusGET(url),
           let body = cachedStatusBodiesByID[statusID] {
            if let overlay = statusStateOverlayBody(for: fixture.body) {
                var updated = fixture
                updated.body = overlay.body
                debugLog("state overlay GET \(url.absoluteString) status=\(statusID) patches=\(overlay.replacements)")
                return updated
            }

            var updated = fixture
            updated.body = body
            debugLog("state overlay GET \(url.absoluteString) status=\(statusID) replacement")
            return updated
        }

        guard let overlay = statusStateOverlayBody(for: fixture.body) else {
            return fixture
        }

        var updated = fixture
        updated.body = overlay.body
        debugLog("state overlay GET \(url.absoluteString) statuses=\(overlay.replacements)")
        return updated
    }

    private static func recordStateMutationIfNeeded(
        for request: URLRequest,
        fixture: Fixture
    ) {
        guard (request.httpMethod ?? "GET").uppercased() == "POST",
              let url = request.url,
              let statusID = statusIDForStatusActionPOST(url) else {
            return
        }

        cachedStatusBodiesByID[statusID] = statusBodyForStateOverlay(from: fixture.body)
        debugLog("state overlay POST \(url.absoluteString) status=\(statusID)")
    }

    private static func statusIDForStatusGET(_ url: URL) -> String? {
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 4,
              components[0] == "api",
              components[1] == "v1",
              components[2] == "statuses" else {
            return nil
        }
        return String(components[3])
    }

    private static func statusIDForStatusActionPOST(_ url: URL) -> String? {
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 5,
              components[0] == "api",
              components[1] == "v1",
              components[2] == "statuses" else {
            return nil
        }
        switch components[4] {
        case "reblog", "unreblog", "favourite", "unfavourite", "bookmark", "unbookmark":
            return String(components[3])
        default:
            return nil
        }
    }

    private static func statusBodyForStateOverlay(from body: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let dictionary = object as? [String: Any] else {
            return body
        }

        let statusObject: Any
        if let reblog = dictionary["reblog"] as? [String: Any] {
            statusObject = reblog
        } else {
            statusObject = dictionary
        }
        guard JSONSerialization.isValidJSONObject(statusObject),
              let data = try? JSONSerialization.data(withJSONObject: statusObject, options: [.sortedKeys]) else {
            return body
        }
        return data
    }

    private static func statusStateOverlayBody(for body: Data) -> (body: Data, replacements: Int)? {
        guard !cachedStatusBodiesByID.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body) else {
            return nil
        }

        var replacements = 0
        let updated = applyingStatusStateOverlay(to: object, replacements: &replacements)
        guard replacements > 0,
              JSONSerialization.isValidJSONObject(updated),
              let data = try? JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys]) else {
            return nil
        }
        return (data, replacements)
    }

    private static func applyingStatusStateOverlay(
        to object: Any,
        replacements: inout Int
    ) -> Any {
        if let array = object as? [Any] {
            return array.map { applyingStatusStateOverlay(to: $0, replacements: &replacements) }
        }

        guard var dictionary = object as? [String: Any] else {
            return object
        }

        if let id = dictionary["id"] as? String,
           isStatusDictionary(dictionary),
           let replacement = cachedStatusDictionary(for: id) {
            mergeStatusActionState(from: replacement, into: &dictionary)
            replacements += 1
            return dictionary
        }

        for (key, value) in dictionary {
            dictionary[key] = applyingStatusStateOverlay(to: value, replacements: &replacements)
        }
        return dictionary
    }

    private static func cachedStatusDictionary(for id: String) -> [String: Any]? {
        guard let body = cachedStatusBodiesByID[id],
              let object = try? JSONSerialization.jsonObject(with: body) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func isStatusDictionary(_ dictionary: [String: Any]) -> Bool {
        dictionary["reblogs_count"] != nil
            || dictionary["favourites_count"] != nil
            || dictionary["replies_count"] != nil
            || dictionary["reblogged"] != nil
            || dictionary["favourited"] != nil
            || dictionary["bookmarked"] != nil
            || dictionary["content"] != nil
    }

    private static func mergeStatusActionState(
        from replacement: [String: Any],
        into dictionary: inout [String: Any]
    ) {
        for key in statusActionStateKeys where replacement.keys.contains(key) {
            dictionary[key] = replacement[key]
        }
    }

    private static let statusActionStateKeys: Set<String> = [
        "reblogs_count",
        "reblogged",
        "favourites_count",
        "favourited",
        "favorites_count",
        "favorited",
        "bookmarks_count",
        "bookmarked",
        "quotes_count"
    ]

    private static func loadFixturesIfNeeded() {
        guard let fixtureFileURL else {
            cachedFileSignature = nil
            cachedFixtures = []
            return
        }

        let signature = fixtureFileSignature(for: fixtureFileURL)
        guard signature != cachedFileSignature else { return }

        cachedFileSignature = signature
        cachedFixtures = (try? loadFixtures(from: fixtureFileURL)) ?? []
        debugLog("loaded \(cachedFixtures.count) fixtures from \(fixtureFileURL.path)")
    }

    private static func fixtureFileSignature(for url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? NSNumber
        let modified = attributes?[.modificationDate] as? Date
        return "\(url.path)|\(size?.int64Value ?? -1)|\(modified?.timeIntervalSince1970 ?? -1)"
    }

    private static func loadFixtures(from url: URL) throws -> [Fixture] {
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data)
        let fixtureObjects: [[String: Any]]
        if let dictionary = root as? [String: Any],
           let fixtures = dictionary["fixtures"] as? [[String: Any]] {
            fixtureObjects = fixtures
        } else if let fixtures = root as? [[String: Any]] {
            fixtureObjects = fixtures
        } else {
            fixtureObjects = []
        }

        return fixtureObjects.compactMap { object in
            let path = object["path"] as? String
            let pathPattern = object["pathPattern"] as? String
            let pathPrefix = object["pathPrefix"] as? String
            guard path?.isEmpty == false
                || pathPattern?.isEmpty == false
                || pathPrefix?.isEmpty == false else {
                return nil
            }
            let method = (object["method"] as? String)?.uppercased()
            let host = object["host"] as? String
            let query = object["query"] as? String
            let requestHeaders = object["requestHeaders"] as? [String: String] ?? [:]
            let requestBodyJSON = canonicalJSONData(from: object["requestBody"])
            let statusCode = object["status"] as? Int ?? object["statusCode"] as? Int ?? 200
            let headers = object["headers"] as? [String: String] ?? [:]
            let body = fixtureBodyData(from: object)
            return Fixture(
                method: method,
                host: host,
                path: path,
                pathPattern: pathPattern,
                pathPrefix: pathPrefix,
                query: query,
                requestHeaders: requestHeaders,
                requestBodyJSON: requestBodyJSON,
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        }
    }

    private static func canonicalJSONData(from object: Any?) -> Data? {
        guard let object,
              JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func fixtureBodyData(from object: [String: Any]) -> Data {
        if let string = object["bodyString"] as? String {
            return Data(string.utf8)
        }
        if let base64 = object["bodyBase64"] as? String,
           let data = Data(base64Encoded: base64) {
            return data
        }
        guard let body = object["body"] else {
            return Data()
        }
        if JSONSerialization.isValidJSONObject(body),
           let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) {
            return data
        }
        return Data(String(describing: body).utf8)
    }

    private static func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment[QuillURLSessionFixtures.debugEnvironmentKey] == "1" else {
            return
        }
        if let data = ("[QuillURLSessionFixtures] \(message)\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
#endif

#if os(Linux)
public typealias CFAllocator = AnyObject
public typealias CFData = Data
public typealias CFArray = [Any]
public typealias CFString = String
public typealias CFDictionary = [String: Any]
public typealias CFTypeRef = AnyObject

public func CFErrorCopyDescription(_ error: CoreFoundation.CFError) -> CFString {
    String(describing: error)
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
