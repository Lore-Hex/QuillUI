import Foundation
import QuillKit
import AppKit
import UIKit
import AVFoundation
import Speech
import Magnet
import ServiceManagement
import Sparkle
import Security
import ApplicationServices
import CoreGraphics
import Alamofire
import os

enum AppleCompatibilitySmoke {
    struct AppleServiceResult {
        var pasteboardString: String?
        var pasteboardItemString: String?
        var pasteboardItemDataRoundTrip: Bool
        var pasteboardItemPropertyListRoundTrip: Bool
        var pasteboardItemTypesRoundTrip: Bool
        var uiPasteboardString: String?
        var imagesRoundTrip: Bool
        var speechStopSucceeded: Bool
        var speechRecognitionUnavailable: Bool
        var launchServiceEnabled: Bool
        var launchServiceDisabled: Bool
        var updaterUnavailable: Bool
    }

    struct DiagnosticFallbackResult {
        var operations: Set<String>
        var speechAuthorizationDenied: Bool
    }

    struct AppKitImageResult {
        var sizeRoundTrip: Bool
        var namedImagePlaceholder: Bool
        var systemImagePlaceholder: Bool
        var workspaceFileIconPlaceholder: Bool
        var workspaceContentTypeIconPlaceholder: Bool
        var bitmapRepresentationRoundTrip: Bool
        var windowTabbingRoundTrip: Bool
        var operations: Set<String>
    }

    struct OSLogResult {
        var operations: Set<String>
        var renderedPublicValue: Bool
        var redactedPrivateValue: Bool
    }

    @MainActor
    static func runAppleServiceSmoke() throws -> AppleServiceResult {
        UIPasteboard.general.string = "hello"

        NSPasteboard.general.setString("hello", forType: .string)
        let pasteboardString = NSPasteboard.general.string(forType: .string)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("item text", forType: .string)
        pasteboardItem.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        pasteboardItem.setPropertyList("item title", forType: .html)

        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==")!
        let nsImageTIFF = NSImage(data: imageData)?.tiffRepresentation
        let nsImageTranscoded = nsImageTIFF.map { data in
            let prefix = Array(data.prefix(4))
            return prefix == [0x49, 0x49, 0x2A, 0x00] || prefix == [0x4D, 0x4D, 0x00, 0x2A]
        } ?? false
        let imagesRoundTrip = nsImageTranscoded && UIImage(data: imageData)?.data == imageData

        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "hello")
        utterance.voice = AVSpeechSynthesisVoice(identifier: "quill.linux.default")
        synthesizer.speak(utterance)

        let recognizer = SFSpeechRecognizer()

        if let combo = KeyCombo(key: .space, cocoaModifiers: [.command]) {
            let hotKey = HotKey(identifier: "space", keyCombo: combo) { key in
                key.unregister()
            }
            hotKey.register()
            hotKey.trigger()
        }

        let service = SMAppService.mainApp
        try service.register()
        let launchServiceEnabled = service.status == .enabled
        try service.unregister()
        let launchServiceDisabled = service.status == .notRegistered

        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

        return AppleServiceResult(
            pasteboardString: pasteboardString,
            pasteboardItemString: pasteboardItem.string(forType: .string),
            pasteboardItemDataRoundTrip: pasteboardItem.data(forType: .png) == Data([0x89, 0x50, 0x4E, 0x47]),
            pasteboardItemPropertyListRoundTrip: pasteboardItem.propertyList(forType: .html) as? String == "item title",
            pasteboardItemTypesRoundTrip: pasteboardItem.types == [.string, .png, .html],
            uiPasteboardString: UIPasteboard.general.string,
            imagesRoundTrip: imagesRoundTrip,
            speechStopSucceeded: synthesizer.stopSpeaking(at: .immediate),
            speechRecognitionUnavailable: recognizer?.isAvailable == false,
            launchServiceEnabled: launchServiceEnabled,
            launchServiceDisabled: launchServiceDisabled,
            updaterUnavailable: updater.updater.canCheckForUpdates == false
        )
    }

    static func runLowerLevelServiceSmoke() throws -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, Data([1, 2, 3]) as CFData) else {
            return false
        }
        let trust = SecTrust()
        guard SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess else {
            return false
        }
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust, nil) else {
            return false
        }

        guard AXIsProcessTrustedWithOptions(nil) == false else {
            return false
        }
        let element = AXUIElementCreateSystemWide()
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute, &value) == .failure else {
            return false
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)

        let trustManager = ServerTrustManager(allHostsMustBeEvaluated: false, evaluators: ["localhost": Evaluator()])
        let session = Session(serverTrustManager: trustManager)
        var responseDidFabricateData = false
        session.request("https://localhost", method: .get)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CompatibilityResponse.self) { response in
                if case .success = response.result {
                    responseDidFabricateData = true
                }
            }
        return responseDidFabricateData == false
    }

    @MainActor
    static func runDiagnosticFallbackSmoke() throws -> DiagnosticFallbackResult {
        QuillCompatibilityDiagnostics.shared.clear()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(AVSpeechUtterance(string: "hello"))

        var authorizationStatus: SFSpeechRecognizerAuthorizationStatus?
        SFSpeechRecognizer.requestAuthorization { status in
            authorizationStatus = status
        }
        _ = SFSpeechRecognizer()?.recognitionTask(with: SFSpeechAudioBufferRecognitionRequest()) { _, _ in }

        _ = CGEventSource.keyState(.combinedSessionState, key: 42)
        CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: 42, keyDown: true)?
            .post(tap: .cghidEventTap)
        QuillHotkeyService.shared.registerSingleUseSpace(modifiers: []) {
            nil
        }

        _ = SecTrustEvaluateWithError(SecTrust(), nil)

        try SMAppService.mainApp.register()
        try SMAppService.mainApp.unregister()

        return DiagnosticFallbackResult(
            operations: Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation)),
            speechAuthorizationDenied: authorizationStatus == .denied
        )
    }

    static func runAppKitImageSmoke() throws -> AppKitImageResult {
        QuillCompatibilityDiagnostics.shared.clear()

        let size = NSSize(width: 24, height: 16)
        let image = NSImage(size: size)
        let sizeRoundTrip = image.size == size
        image.lockFocus()
        image.draw(
            in: NSRect(x: 0, y: 0, width: 24, height: 16),
            from: NSRect(x: 0, y: 0, width: 12, height: 8),
            operation: .copy,
            fraction: 0.5
        )
        image.unlockFocus()

        let namedImage = NSImage(named: "StatusBarIcon")
        let systemImage = NSImage(systemName: "paperplane.fill")
        let workspaceFileIcon = NSWorkspace.shared.icon(forFile: "/tmp/enchanted-export.txt")
        let workspaceContentTypeIcon = NSWorkspace.shared.icon(forContentType: "public.plain-text")
        let encoded = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let rep = NSBitmapImageRep(data: encoded)
        NSWindow.allowsAutomaticWindowTabbing = false
        let windowTabbingRoundTrip = NSWindow.allowsAutomaticWindowTabbing == false
        NSWindow.allowsAutomaticWindowTabbing = true

        return AppKitImageResult(
            sizeRoundTrip: sizeRoundTrip,
            namedImagePlaceholder: namedImage?.size == CGSize(width: 1, height: 1),
            systemImagePlaceholder: systemImage?.size == CGSize(width: 1, height: 1),
            workspaceFileIconPlaceholder: workspaceFileIcon.size == CGSize(width: 1, height: 1),
            workspaceContentTypeIconPlaceholder: workspaceContentTypeIcon.size == CGSize(width: 1, height: 1),
            bitmapRepresentationRoundTrip: rep?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) == encoded,
            windowTabbingRoundTrip: windowTabbingRoundTrip,
            operations: Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        )
    }

    static func runOSLogSmoke() -> OSLogResult {
        QuillCompatibilityDiagnostics.shared.clear()

        let logger = Logger(subsystem: "co.lorehex.quillchat", category: "usb-launcher")
        logger.info("public value: \("visible", privacy: .public)")
        logger.error("private value: \("hidden", privacy: .private)")

        let messages = QuillCompatibilityDiagnostics.shared.events.map(\.message).joined(separator: "\n")
        return OSLogResult(
            operations: Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation)),
            renderedPublicValue: messages.contains("visible"),
            redactedPrivateValue: messages.contains("<private>") && !messages.contains("hidden")
        )
    }
}

private struct Evaluator: ServerTrustEvaluating {
    func evaluate(_ trust: SecTrust, forHost host: String) throws {}
}

private struct CompatibilityResponse: Decodable {
    var value: String
}
