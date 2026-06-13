// Buggy outer `#if !os(macOS) && !os(iOS) && !os(visionOS)` removed —
// it was wrapping every macOS extension below in a Linux-only block,
// which made `Color(hex:)` invisible on macOS even though the inner
// `#if os(macOS) || ...` looked correct.
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
import QuillFoundation
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

    var red: Double {
        var r: CGFloat = 0
        #if canImport(AppKit)
        NSColor(self).usingColorSpace(.deviceRGB)?.getRed(&r, green: nil, blue: nil, alpha: nil)
        #elseif canImport(UIKit)
        UIColor(self).getRed(&r, green: nil, blue: nil, alpha: nil)
        #endif
        return Double(r)
    }

    var green: Double {
        var g: CGFloat = 0
        #if canImport(AppKit)
        NSColor(self).usingColorSpace(.deviceRGB)?.getRed(nil, green: &g, blue: nil, alpha: nil)
        #elseif canImport(UIKit)
        UIColor(self).getRed(nil, green: &g, blue: nil, alpha: nil)
        #endif
        return Double(g)
    }

    var blue: Double {
        var b: CGFloat = 0
        #if canImport(AppKit)
        NSColor(self).usingColorSpace(.deviceRGB)?.getRed(nil, green: nil, blue: &b, alpha: nil)
        #elseif canImport(UIKit)
        UIColor(self).getRed(nil, green: nil, blue: &b, alpha: nil)
        #endif
        return Double(b)
    }

    var alpha: Double {
        var a: CGFloat = 0
        #if canImport(AppKit)
        NSColor(self).usingColorSpace(.deviceRGB)?.getRed(nil, green: nil, blue: nil, alpha: &a)
        #elseif canImport(UIKit)
        UIColor(self).getRed(nil, green: nil, blue: nil, alpha: &a)
        #endif
        return Double(a)
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

public struct LayoutPriority: Equatable, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public var rawValue: Double
    public init(_ value: Double) { self.rawValue = value }
    public init(floatLiteral value: Double) { self.rawValue = value }
    public init(integerLiteral value: Int) { self.rawValue = Double(value) }
    public static let `default` = LayoutPriority(0.0)
    public static let required = LayoutPriority(1000.0)
}

public extension View {
    @ViewBuilder
    func quillGTKSizeRequest(width: Int = -1, height: Int = -1) -> some View {
        self
    }
}

#else
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

public typealias QuillPlatformImage = RSImage
public typealias PlatformImage = RSImage

public extension QuillPlatformImage {
    func convertImageToBase64String() -> String {
        data?.base64EncodedString() ?? ""
    }

    func aspectFittedToHeight(_ newHeight: CGFloat) -> QuillPlatformImage {
        guard let data else { return self }
        guard newHeight.isFinite else {
            recordCompatibilityWarning(
                "PlatformImage.aspectFittedToHeight",
                message: "PlatformImage.aspectFittedToHeight received a non-finite height; returning the original image."
            )
            return self
        }

        let targetHeight = Int(newHeight.rounded())
        guard targetHeight > 0 else {
            recordCompatibilityWarning(
                "PlatformImage.aspectFittedToHeight",
                message: "PlatformImage.aspectFittedToHeight received a non-positive height; returning the original image."
            )
            return self
        }

        guard let resizedData = quillScaleImageDataToHeight(data, height: targetHeight) else {
            recordCompatibilityWarning(
                "PlatformImage.aspectFittedToHeight",
                message: "PlatformImage.aspectFittedToHeight could not decode or resize image bytes with gdk-pixbuf; returning the original image."
            )
            return self
        }

        return QuillPlatformImage(data: resizedData) ?? self
    }

    func compressImageData() -> Data? {
        guard let data else { return nil }
        guard let compressed = quillCompressImageDataToJPEG(data) else {
            recordCompatibilityWarning(
                "PlatformImage.compressImageData",
                message: "PlatformImage.compressImageData could not decode or recompress image bytes with gdk-pixbuf; returning original bytes."
            )
            return data
        }

        return compressed
    }
}

// `NSImage` was previously declared here as a standalone class,
// but that collided with `QuillAppKit`'s `typealias NSImage = RSImage`
// when both modules ended up in the same import scope (~500
// "ambiguous for type lookup" + "extraneous argument label 'nsImage:'"
// cascading errors on the generated Enchanted Linux build).
//
// Unify on `RSImage` from QuillFoundation. QuillUI's previous
// `NSImage`-specific API (`tiffRepresentation` going through
// gdk-pixbuf) lives in the extension below; the common image no-op
// drawing diagnostics live on `RSImage` itself so callers importing
// only AppKit / QuillFoundation see the same behavior.
public typealias NSImage = RSImage

public extension RSImage {
    /// Convenience initializer matching the old `NSImage(named:)`
    /// shim's warning-and-placeholder behavior.
    static func quillNSImageNamed(_ name: String) -> RSImage {
        if let data = QuillResourceLookup.data(
            forResource: name,
            candidateExtensions: QuillResourceLookup.commonImageExtensions
        ), let image = RSImage(data: data) {
            return image
        }

        recordCompatibilityWarning(
            "NSImage(named:)",
            message: "NSImage(named:) could not find '\(name)' in QUILLUI_RESOURCE_DIRS, SwiftPM .resources directories, or bundled Resources; returning a 32x32 placeholder image."
        )
        return RSImage(size: CGSize(width: 32, height: 32))
    }

    /// Returns the receiver's image bytes as TIFF.
    ///
    /// On Apple platforms this decodes the source data (PNG/JPEG/etc.) into
    /// pixel form and re-encodes it as TIFF. On Linux, QuillUI mirrors that
    /// path through gdk-pixbuf when the platform codec is available.
    ///
    /// TIFF input is returned unchanged on Linux. Apple may re-encode valid
    /// TIFF input, so callers should rely on "valid TIFF bytes out" rather than
    /// byte-for-byte equality across platforms.
    var tiffRepresentation: Data? {
        guard let data else { return nil }
        switch QuillImageFormatDetector.detect(data) {
        case .tiff:
            return data
        case .png, .jpeg, .gif, .bmp, .webp:
            if let transcoded = quillTranscodeImageDataToTIFF(data) {
                return transcoded
            }
            recordCompatibilityWarning(
                "NSImage.tiffRepresentation",
                message: "gdk-pixbuf failed to transcode the input image to TIFF. Apple would also return nil for unrecoverable decode failures; doing the same here."
            )
            return nil
        case .unknown:
            if let transcoded = quillTranscodeImageDataToTIFF(data) {
                return transcoded
            }
            recordCompatibilityWarning(
                "NSImage.tiffRepresentation",
                message: "NSImage.tiffRepresentation could not identify or decode the input bytes. Apple would return nil for unknown / corrupt input; doing the same here."
            )
            return nil
        }
    }

}

#if os(macOS) || os(iOS) || os(visionOS)
public enum QuillImageCompositingOperation: Sendable {
    case copy
}
#else
public typealias QuillImageCompositingOperation = QuillFoundation.QuillImageCompositingOperation
#endif

/// Identifies common image container formats from their magic-byte prefixes.
/// Used by `NSImage.tiffRepresentation` to decide whether the receiver's bytes
/// can be returned unchanged as TIFF or should be sent through the platform
/// transcoder.
@_spi(QuillTesting)
public enum QuillImageFormat: Sendable, Equatable {
    case tiff
    case png
    case jpeg
    case gif
    case bmp
    case webp
    case unknown
}

@_spi(QuillTesting)
public enum QuillImageFormatDetector {
    public static func detect(_ data: Data) -> QuillImageFormat {
        // Sniff at most the first 12 bytes; every container format below
        // identifies itself within that window.
        let bytes = data.prefix(12)
        guard bytes.count >= 2 else { return .unknown }
        let b = Array(bytes)

        // TIFF: little-endian "II*\0" or big-endian "MM\0*"
        if b.count >= 4 {
            if b[0] == 0x49, b[1] == 0x49, b[2] == 0x2A, b[3] == 0x00 { return .tiff }
            if b[0] == 0x4D, b[1] == 0x4D, b[2] == 0x00, b[3] == 0x2A { return .tiff }
        }

        // PNG: \x89 P N G \r \n \x1a \n
        if b.count >= 8,
           b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47,
           b[4] == 0x0D, b[5] == 0x0A, b[6] == 0x1A, b[7] == 0x0A {
            return .png
        }

        // JPEG: \xFF \xD8 \xFF
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF {
            return .jpeg
        }

        // GIF: "GIF87a" or "GIF89a"
        if b.count >= 6,
           b[0] == 0x47, b[1] == 0x49, b[2] == 0x46, b[3] == 0x38,
           (b[4] == 0x37 || b[4] == 0x39), b[5] == 0x61 {
            return .gif
        }

        // BMP: "BM"
        if b.count >= 2, b[0] == 0x42, b[1] == 0x4D {
            return .bmp
        }

        // WebP: "RIFF" .... "WEBP"
        if b.count >= 12,
           b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
           b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 {
            return .webp
        }

        return .unknown
    }
}

public extension Image {
    func render() -> PlatformImage? {
        if case .filePath(let path) = source,
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           !data.isEmpty {
            return PlatformImage(data: data)
        }

        let renderer = SwiftOpenUI.OpenUIImageRenderer(content: self)
        if let data = renderer.platformImage?.data,
           let image = PlatformImage(data: data) {
            return image
        }

        recordCompatibilityWarning(
            "Image.render",
            message: "Image.render returned nil on Linux; only file-backed images and renderer-backend-supported views can currently produce bitmap data."
        )
        return nil
    }
}

public protocol KeyboardReadable {}

public struct PlainListStyle: Sendable {
    public init() {}
}

// `ButtonRole` and the role-taking Button inits moved to
// QuillSwiftUICompatibility (SolderScopeChrome.swift) so real source that
// only `import SwiftUI`s sees them (SolderScope's alert buttons); QuillUI
// re-exports that module.

public extension TextField {
    init(_ title: String, text: Binding<String>, axis: Axis) {
        self.init(title, text: text)
    }

    init(_ title: String, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.init(title, text: text)
    }
}

// Axis.Set is the fork's typealias (Axis itself is the OptionSet) —
// the old nested struct here competed with it and was removed.

public struct LayoutPriority: Equatable, Sendable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public var rawValue: Double
    public init(_ value: Double) { self.rawValue = value }
    public init(floatLiteral value: Double) { self.rawValue = value }
    public init(integerLiteral value: Int) { self.rawValue = Double(value) }
    public static let `default` = LayoutPriority(0.0)
    public static let required = LayoutPriority(1000.0)
}

public extension Angle {
    var radians: Double {
        degrees * .pi / 180.0
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

// `OpenURLAction` moved to QuillSwiftUICompatibility/OpenURLActionCompat.swift
// (so the SwiftUI shim can surface it — with its nested `Result` — to vendored
// real source). QuillUI still sees it via its `@_exported import
// QuillSwiftUICompatibility`.

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
    private let dismissAction: () -> Void

    public init(dismiss: @escaping () -> Void = {}) {
        dismissAction = dismiss
    }

    public var wrappedValue: PresentationMode { self }

    public func dismiss() {
        dismissAction()
    }
}

private struct PresentationModeKey: EnvironmentKey {
    static let defaultValue: PresentationMode? = nil
}

public extension EnvironmentValues {
    var presentationMode: PresentationMode {
        get {
            let dismiss = self.dismiss
            return self[PresentationModeKey.self] ?? PresentationMode {
                #if os(Linux)
                if let contextualDismiss = swiftOpenUICurrentPresentationDismissAction() {
                    contextualDismiss()
                    return
                }
                #endif
                dismiss()
            }
        }
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

    @_disfavoredOverload
    @ViewBuilder
    func quillGTKSizeRequest(width: Int = -1, height: Int = -1) -> some View {
        #if os(Linux)
        if QuillBackendRuntimeContext.selectedBackend == .gtk {
            QuillGTKSizeRequestView(content: self, width: width, height: height)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if os(Linux)
import CGTK
import BackendGTK4

private func quillGTKWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

private func quillGTKOpaquePointer(_ widget: UnsafeMutablePointer<GtkWidget>) -> OpaquePointer {
    OpaquePointer(widget)
}

struct QuillGTKSizeRequestView<Content: View>: View, PrimitiveView, GTKRenderable {
    typealias Body = Never
    var content: Content
    var width: Int
    var height: Int

    var body: Never { fatalError("QuillGTKSizeRequestView is a primitive view") }

    func gtkCreateWidget() -> OpaquePointer {
        let widget = quillGTKWidgetPointer(gtkRenderView(content))
        gtk_widget_set_size_request(widget, gint(width), gint(height))
        return quillGTKOpaquePointer(widget)
    }
}
#endif
#endif
// (Removed dangling outer #endif — the buggy Linux-only outer wrapper
// at the top of this file was deleted along with this closer.)
