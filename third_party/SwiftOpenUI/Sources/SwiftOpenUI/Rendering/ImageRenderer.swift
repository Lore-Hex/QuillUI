import Foundation

/// Lightweight bitmap image container used by SwiftOpenUI's Linux renderers.
///
/// Apple exposes platform-specific image classes from `ImageRenderer`
/// (`NSImage`, `UIImage`, and `CGImage`). SwiftOpenUI keeps the Linux surface
/// intentionally byte-oriented: successful renderers return PNG bytes in
/// `data`, and AppKit/UIKit shims can wrap the same value as needed.
public struct PlatformImage: Sendable {
    public var data: Data?

    public init(data: Data? = nil) {
        self.data = data
    }

    public func dataRepresentation() -> Data? {
        data
    }

    public func pngData() -> Data? {
        data
    }
}

/// Linux compatibility stand-in for SwiftUI's `CGImage` renderer output.
///
/// The value is the same byte-backed image container returned by `.nsImage`
/// and `.uiImage`. This gives source that only needs non-empty rendered image
/// bytes a single concrete representation on Linux.
public typealias CGImage = PlatformImage

public struct ImageRendererConfiguration: Sendable {
    public var width: Int
    public var height: Int
    public var scale: CGFloat

    public init(width: Int = 256, height: Int = 256, scale: CGFloat = 1) {
        self.width = width
        self.height = height
        self.scale = scale
    }
}

private final class ImageRendererBackendStorage: @unchecked Sendable {
    static let shared = ImageRendererBackendStorage()

    private let lock = NSLock()
    private var renderer: (((any View), ImageRendererConfiguration) -> Data?)?

    func install(_ renderer: @escaping ((any View), ImageRendererConfiguration) -> Data?) {
        lock.withLock {
            self.renderer = renderer
        }
    }

    func render(_ view: any View, configuration: ImageRendererConfiguration) -> Data? {
        let renderer = lock.withLock { self.renderer }
        return renderer?(view, configuration)
    }
}

public enum ImageRendererBackend {
    public static func installViewRenderer(
        _ renderer: @escaping ((any View), ImageRendererConfiguration) -> Data?
    ) {
        ImageRendererBackendStorage.shared.install(renderer)
    }

    static func render(_ view: any View, configuration: ImageRendererConfiguration) -> Data? {
        ImageRendererBackendStorage.shared.render(view, configuration: configuration)
    }
}

/// Renders a SwiftOpenUI view tree into image bytes.
///
/// The core module provides the public API and a display-independent solid
/// `Color` fast path. Platform backends install the general view renderer with
/// `ImageRendererBackend.installViewRenderer`; the GTK4 backend realizes the
/// view offscreen, snapshots it, and returns PNG bytes.
public final class OpenUIImageRenderer<Content: View> {
    public var content: Content
    public var scale: CGFloat = 1
    public var proposedSize: CGSize?

    public init(content: Content) {
        self.content = content
    }

    public var platformImage: PlatformImage? {
        renderToPlatformImage()
    }

    public var nsImage: PlatformImage? {
        renderToPlatformImage()
    }

    public var uiImage: PlatformImage? {
        renderToPlatformImage()
    }

    public var cgImage: CGImage? {
        renderToPlatformImage()
    }

    private func renderToPlatformImage() -> PlatformImage? {
        let width = max(1, Int((proposedSize?.width ?? 256).rounded()))
        let height = max(1, Int((proposedSize?.height ?? 256).rounded()))

        if let color = content as? Color,
           let png = PNGEncoder.solidRGBA(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha,
            width: width,
            height: height
           ) {
            return PlatformImage(data: png)
        }

        let configuration = ImageRendererConfiguration(width: width, height: height, scale: scale)
        guard let data = ImageRendererBackend.render(content, configuration: configuration) else {
            return nil
        }
        return PlatformImage(data: data)
    }
}

private enum PNGEncoder {
    static func solidRGBA(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double,
        width: Int,
        height: Int
    ) -> Data? {
        guard width > 0, height > 0 else { return nil }

        let rgba = [
            clampByte(red),
            clampByte(green),
            clampByte(blue),
            clampByte(alpha)
        ]

        var raw = Data()
        raw.reserveCapacity((width * 4 + 1) * height)
        for _ in 0..<height {
            raw.append(0)
            for _ in 0..<width {
                raw.append(contentsOf: rgba)
            }
        }

        return encodeRGBA(rawPixelsWithFilterBytes: raw, width: width, height: height)
    }

    private static func encodeRGBA(
        rawPixelsWithFilterBytes raw: Data,
        width: Int,
        height: Int
    ) -> Data? {
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var ihdr = Data()
        ihdr.appendUInt32BE(UInt32(width))
        ihdr.appendUInt32BE(UInt32(height))
        ihdr.append(8)
        ihdr.append(6)
        ihdr.append(0)
        ihdr.append(0)
        ihdr.append(0)
        png.appendChunk(type: "IHDR", payload: ihdr)

        var zlib = Data([0x78, 0x01])
        var offset = 0
        while offset < raw.count {
            let remaining = raw.count - offset
            let blockLength = min(65_535, remaining)
            let isFinal = offset + blockLength == raw.count
            zlib.append(isFinal ? 0x01 : 0x00)
            zlib.appendUInt16LE(UInt16(blockLength))
            zlib.appendUInt16LE(~UInt16(blockLength))
            zlib.append(raw.subdata(in: offset..<(offset + blockLength)))
            offset += blockLength
        }
        zlib.appendUInt32BE(adler32(raw))
        png.appendChunk(type: "IDAT", payload: zlib)
        png.appendChunk(type: "IEND", payload: Data())
        return png
    }

    private static func clampByte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, Int((value * 255).rounded()))))
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendChunk(type: String, payload: Data) {
        precondition(type.utf8.count == 4)

        appendUInt32BE(UInt32(payload.count))
        let typeBytes = Array(type.utf8)
        append(contentsOf: typeBytes)
        append(payload)

        var crcInput = Data(typeBytes)
        crcInput.append(payload)
        appendUInt32BE(Self.crc32(crcInput))
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
