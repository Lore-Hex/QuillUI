import Foundation
#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#else
import SwiftOpenUI
import QuillKit
#endif

#if os(macOS) || os(iOS) || os(visionOS)
public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b, a: UInt64
        switch cleaned.count {
        case 8:
            r = (value >> 24) & 0xff
            g = (value >> 16) & 0xff
            b = (value >> 8) & 0xff
            a = value & 0xff
        default:
            r = (value >> 16) & 0xff
            g = (value >> 8) & 0xff
            b = value & 0xff
            a = 255
        }

        self.init(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    init(rgba: UInt32) {
        self.init(
            red: Double((rgba >> 24) & 0xff) / 255.0,
            green: Double((rgba >> 16) & 0xff) / 255.0,
            blue: Double((rgba >> 8) & 0xff) / 255.0,
            opacity: Double(rgba & 0xff) / 255.0
        )
    }

    init(light: Color, dark: Color) {
        self = light
    }
}

public extension Image {
    init(data: Data) {
        #if canImport(AppKit)
        if let image = NSImage(data: data) {
            self.init(nsImage: image)
        } else {
            self.init(systemName: "photo")
        }
        #elseif canImport(UIKit)
        if let image = UIImage(data: data) {
            self.init(uiImage: image)
        } else {
            self.init(systemName: "photo")
        }
        #else
        self.init(systemName: "photo")
        #endif
    }
}
#else
public struct QuillPlatformColor: @unchecked Sendable {
    public let color: Color

    public init(_ color: Color) {
        self.color = color
    }

    public static var label: QuillPlatformColor { QuillPlatformColor(.black) }
    public static var black: QuillPlatformColor { QuillPlatformColor(.black) }
    public static var white: QuillPlatformColor { QuillPlatformColor(.white) }
    public static var systemGray: QuillPlatformColor { QuillPlatformColor(.gray) }
    public static var systemGray2: QuillPlatformColor { QuillPlatformColor(Color(red: 0.68, green: 0.68, blue: 0.70)) }
    public static var systemBlue: QuillPlatformColor { QuillPlatformColor(Color(red: 0.00, green: 0.48, blue: 1.00)) }
    public static var systemRed: QuillPlatformColor { QuillPlatformColor(Color(red: 1.00, green: 0.23, blue: 0.19)) }
    public static var pink: QuillPlatformColor { QuillPlatformColor(.pink) }
}

public extension Color {
    enum RGBColorSpace {
        case sRGB
    }

    init(_ platformColor: QuillPlatformColor) {
        self = platformColor.color
    }

    init(_ colorSpace: RGBColorSpace, red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }

    init(rgba: UInt32) {
        self.init(
            red: Double((rgba >> 24) & 0xff) / 255.0,
            green: Double((rgba >> 16) & 0xff) / 255.0,
            blue: Double((rgba >> 8) & 0xff) / 255.0,
            opacity: Double(rgba & 0xff) / 255.0
        )
    }

    init(light: Color, dark: Color) {
        self = light
    }

    init(_ assetName: String) {
        self = Self.assetColor(named: assetName)
    }

    static var foreground: Color { primary }
    static var label: Color { Color(.label) }
    static var labelCustom: Color { Color("label") }
    static var systemGray: Color { Color(.systemGray) }
    static var systemGray2: Color { Color(.systemGray2) }
    static var systemBlue: Color { Color(.systemBlue) }
    static var systemRed: Color { Color(.systemRed) }
    static var grayCustom: Color { Color("grayCustom") }
    static var gray2Custom: Color { Color("gray2Custom") }
    static var gray3Custom: Color { Color("gray3Custom") }
    static var gray4Custom: Color { Color("gray4Custom") }
    static var gray5Custom: Color { Color("gray5Custom") }
    static var bgCustom: Color { Color("bgCustom") }

    private static func assetColor(named name: String) -> Color {
        switch name {
        case "label":
            return Color(red: 0.12, green: 0.12, blue: 0.13)
        case "grayCustom":
            return Color(red: 0.56, green: 0.56, blue: 0.58)
        case "gray2Custom":
            return Color(red: 0.68, green: 0.68, blue: 0.70)
        case "gray3Custom":
            return Color(red: 0.78, green: 0.78, blue: 0.80)
        case "gray4Custom":
            return Color(red: 0.86, green: 0.86, blue: 0.88)
        case "gray5Custom":
            return Color(red: 0.91, green: 0.91, blue: 0.94)
        case "bgCustom":
            return Color(red: 0.96, green: 0.96, blue: 0.97)
        default:
            return .primary
        }
    }
}

// MARK: - Compatibility diagnostics

@inline(__always)
fileprivate func recordCompatibilityFallback(_ operation: String, message: String? = nil) {
    QuillCompatibilityDiagnostics.shared.record(
        QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: operation,
            severity: .info,
            message: message ?? "\(operation) is currently a source-compatibility fallback on Linux."
        )
    )
}

@inline(__always)
fileprivate func recordCompatibilityWarning(_ operation: String, message: String) {
    QuillCompatibilityDiagnostics.shared.record(
        QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: operation,
            severity: .warning,
            message: message
        )
    )
}

public struct QuillPlatformImage: Sendable {
    public var data: Data?

    public init(data: Data? = nil) {
        self.data = data
    }
}

public typealias PlatformImage = QuillPlatformImage

public extension QuillPlatformImage {
    func convertImageToBase64String() -> String {
        data?.base64EncodedString() ?? ""
    }

    func aspectFittedToHeight(_ newHeight: CGFloat) -> QuillPlatformImage {
        recordCompatibilityWarning(
            "PlatformImage.aspectFittedToHeight",
            message: "PlatformImage.aspectFittedToHeight returns the original image on Linux; bitmap resizing is not implemented yet."
        )
        return self
    }

    func compressImageData() -> Data? {
        recordCompatibilityWarning(
            "PlatformImage.compressImageData",
            message: "PlatformImage.compressImageData returns original bytes on Linux; JPEG recompression is not implemented yet."
        )
        return data
    }
}

public final class NSImage: @unchecked Sendable {
    public var data: Data?
    public var size: CGSize

    public init?(data: Data) {
        self.data = data
        self.size = CGSize(width: 1, height: 1)
    }

    public init(size: CGSize) {
        self.data = nil
        self.size = size
    }

    public convenience init?(named name: String) {
        recordCompatibilityWarning(
            "NSImage(named:)",
            message: "NSImage(named:) returns a blank placeholder image for '\(name)' on Linux; app assets are not loaded through AppKit yet."
        )
        self.init(size: CGSize(width: 1, height: 1))
    }

    /// On Linux this returns the original input bytes regardless of the source
    /// format. Apps that depend on actual TIFF encoding will receive
    /// mislabeled bytes; the warning is recorded so callers see it in
    /// `QuillCompatibilityDiagnostics.shared.events`.
    public var tiffRepresentation: Data? {
        recordCompatibilityWarning(
            "NSImage.tiffRepresentation",
            message: "NSImage.tiffRepresentation returns the original input bytes (no TIFF encoding) on Linux. Downstream code expecting TIFF format may behave incorrectly."
        )
        return data
    }

    public func lockFocus() {
        recordCompatibilityFallback("NSImage.lockFocus")
    }

    public func unlockFocus() {
        recordCompatibilityFallback("NSImage.unlockFocus")
    }

    public func draw(
        in destinationRect: CGRect,
        from sourceRect: CGRect,
        operation: QuillImageCompositingOperation,
        fraction: Double
    ) {
        recordCompatibilityFallback(
            "NSImage.draw",
            message: "NSImage.draw is currently a no-op on Linux; image compositing needs a real bitmap backend."
        )
    }
}

public enum QuillImageCompositingOperation: Sendable {
    case copy
}

public final class ImageRenderer<Content: View> {
    public var content: Content
    public var scale: CGFloat = 1.0

    public init(content: Content) {
        self.content = content
        recordCompatibilityWarning(
            "ImageRenderer.init",
            message: "ImageRenderer is not yet implemented on Linux; uiImage/nsImage will return nil and any image export paths will silently fail."
        )
    }

    public var uiImage: PlatformImage? {
        recordCompatibilityWarning(
            "ImageRenderer.uiImage",
            message: "ImageRenderer.uiImage returned nil on Linux; image export is not yet supported."
        )
        return nil
    }

    public var nsImage: PlatformImage? {
        recordCompatibilityWarning(
            "ImageRenderer.nsImage",
            message: "ImageRenderer.nsImage returned nil on Linux; image export is not yet supported."
        )
        return nil
    }
}

public extension Image {
    func render() -> PlatformImage? {
        recordCompatibilityWarning(
            "Image.render",
            message: "Image.render returned nil on Linux; rendering SwiftUI images to bitmap data is not yet supported."
        )
        return nil
    }
}

public protocol KeyboardReadable {}

public struct PlainListStyle: Sendable {
    public init() {}
}

public enum ButtonRole {
    case cancel
    case destructive
}

public extension Button where Label == Text {
    init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(title, action: action)
    }
}

public extension Button {
    init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.init(action: action, label: label)
    }
}

public extension TextField {
    init(_ title: String, text: Binding<String>, axis: Axis) {
        self.init(title, text: text)
    }

    init(_ title: String, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.init(title, text: text)
    }
}

/// Process-lifetime cache for `Image(data:)` so identical Data values do not
/// rewrite the temp file on every call. Without this, a chat or feed UI that
/// renders the same image many times leaks a fresh PNG to disk per render.
private final class QuillImageDataCache: @unchecked Sendable {
    static let shared = QuillImageDataCache()

    private let lock = NSLock()
    private var urlsByContent: [Data: URL] = [:]

    func materialize(_ data: Data, in directory: URL) -> URL {
        return lock.withLock {
            if let existing = urlsByContent[data],
               FileManager.default.fileExists(atPath: existing.path) {
                return existing
            }
            let url = directory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                recordCompatibilityWarning(
                    "Image(data:)",
                    message: "Failed to materialize image data to \(url.path): \(error.localizedDescription)"
                )
            }
            urlsByContent[data] = url
            return url
        }
    }
}

public extension Image {
    init(_ name: String) {
        self.init(resource: name)
    }

    init(data: Data) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillUIImages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            recordCompatibilityWarning(
                "Image(data:)",
                message: "Failed to create QuillUIImages temp directory: \(error.localizedDescription)"
            )
        }
        let fileURL = QuillImageDataCache.shared.materialize(data, in: directory)
        self.init(filePath: fileURL.path)
    }
}

public extension Binding {
    func animation(_ animation: Animation? = nil) -> Binding<Value> {
        recordCompatibilityFallback("Binding.animation")
        return self
    }
}

public struct OpenURLAction: Sendable {
    private let handler: @Sendable (URL) -> Bool

    public init(handler: @escaping @Sendable (URL) -> Bool = OpenURLAction.defaultHandler) {
        self.handler = handler
    }

    @discardableResult
    public func callAsFunction(_ url: URL) -> Bool {
        handler(url)
    }

    public static func defaultHandler(_ url: URL) -> Bool {
        #if os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

private struct OpenURLKey: EnvironmentKey {
    static let defaultValue = OpenURLAction()
}

public extension EnvironmentValues {
    var openURL: OpenURLAction {
        get { self[OpenURLKey.self] }
        set { self[OpenURLKey.self] = newValue }
    }
}

public struct PresentationMode: @unchecked Sendable {
    private let dismissAction: @Sendable () -> Void

    public init(dismiss: @escaping @Sendable () -> Void = {}) {
        dismissAction = dismiss
    }

    public var wrappedValue: PresentationMode { self }

    public func dismiss() {
        dismissAction()
    }
}

private struct PresentationModeKey: EnvironmentKey {
    static let defaultValue = PresentationMode()
}

public extension EnvironmentValues {
    var presentationMode: PresentationMode {
        get { self[PresentationModeKey.self] }
        set { self[PresentationModeKey.self] = newValue }
    }
}

public extension View {
    @ViewBuilder
    func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        if let colorScheme {
            environment(\.colorScheme, colorScheme)
        } else {
            self
        }
    }

    func listStyle(_ style: PlainListStyle) -> Self {
        recordCompatibilityFallback("listStyle(PlainListStyle)")
        return self
    }

    func task(priority: TaskPriority = .userInitiated, _ action: @escaping @Sendable () async -> Void) -> OnAppearView<Self> {
        onAppear {
            Task(priority: priority) {
                await action()
            }
        }
    }
}
#endif
