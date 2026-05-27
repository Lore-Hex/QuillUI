import Foundation
import QuillPaint

#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Convenience: render a `PaintControl` into a PNG using CoreGraphics.
///
/// This is the "Mac reference" snapshot generator. By painting via the
/// same `PaintControl.paint(into:frame:state:)` code path that the Linux
/// Cairo (future) and Qt (future) backends use, the generated PNG IS the
/// pixel-perfect macOS reference — there's no separate "what does macOS
/// look like" data to drift from production output.
///
/// The renderer adds a margin around the control so focus rings and any
/// future shadow effects aren't clipped.
public struct MacReferenceRenderer {
    public enum Error: Swift.Error, CustomStringConvertible {
        case contextCreationFailed
        case destinationCreationFailed
        case finalizeFailed
        case imageEncodingFailed

        public var description: String {
            switch self {
            case .contextCreationFailed: return "Failed to create CGContext for snapshot."
            case .destinationCreationFailed: return "Failed to create CGImageDestination."
            case .finalizeFailed: return "Failed to finalize PNG image destination."
            case .imageEncodingFailed: return "Failed to encode CGImage from context."
            }
        }
    }

    public var margin: Double
    public var scale: Double

    /// `margin` is in paint units; `scale` is the device-pixel scale factor
    /// (2.0 = retina). The output PNG has `(canvas-paint-size * scale)`
    /// pixels per side.
    public init(margin: Double = 8, scale: Double = 2.0) {
        self.margin = margin
        self.scale = scale
    }

    /// Render `control` and return the resulting `CGImage`. The control is
    /// painted at `frame.size`, positioned `margin` paint units in from
    /// the top-left of the canvas.
    public func renderImage(
        control: PaintControl,
        frame size: PaintSize,
        state: PaintControlState
    ) throws -> CGImage {
        let canvas = PaintSize(
            width: size.width + 2 * margin,
            height: size.height + 2 * margin
        )
        let pixelWidth = max(1, Int((canvas.width * scale).rounded()))
        let pixelHeight = max(1, Int((canvas.height * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw Error.contextCreationFailed
        }

        // Start with a clear canvas so transparent regions stay transparent.
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Map PaintPoint's top-left origin to CG's bottom-left origin and
        // apply the device-pixel scale.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))

        let paintContext = CGPaintContext(cgContext: context)
        let frame = PaintRect(
            x: margin,
            y: margin,
            width: size.width,
            height: size.height
        )
        control.paint(into: paintContext, frame: frame, state: state)

        guard let image = context.makeImage() else {
            throw Error.imageEncodingFailed
        }
        return image
    }

    /// Render `control` and write the resulting PNG to `outputURL`. Creates
    /// the parent directory if needed.
    public func renderPNG(
        control: PaintControl,
        frame size: PaintSize,
        state: PaintControlState,
        outputURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let image = try renderImage(control: control, frame: size, state: state)

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw Error.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            throw Error.finalizeFailed
        }
    }
}

#endif
