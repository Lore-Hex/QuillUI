// QuillAppKitCursorTrackingImaging
// ================================
// Cursor-rect and bitmap-imaging surface, driven by SolderScope (USB-microscope
// viewer; AppKit-members conformance slice, issue #507). Additive to
// QuillAppKit.swift, which already provides NSCursor (the full standard-cursor
// set + push/pop/set), NSTrackingArea (with the complete Options set), and
// NSView.addTrackingArea/removeTrackingArea/resetCursorRects — this file adds
// only what was still missing: cursor *rects* on NSView, and
// NSBitmapImageRep's CGImage init + TIFF compression constants.

#if os(Linux)

import Foundation
import QuillFoundation

// MARK: - NSView cursor rects

extension NSView {
    /// `addCursorRect(_:cursor:)` — associates a cursor with a region of the
    /// view, valid when called from `resetCursorRects()` (SolderScope's
    /// MicroscopeNSView adds `.openHand` over its bounds; its
    /// CalibrationCanvasNSView adds `.crosshair`). The backend does not yet
    /// resolve pointer position against cursor rects, but the model stores the
    /// association so control logic can test and inspect the same AppKit surface.
    public func addCursorRect(_ rect: NSRect, cursor: NSCursor) {
        quillCursorRects.append((rect, cursor))
    }

    /// Companion to `addCursorRect` — AppKit invalidates a view's cursor
    /// rects before asking `resetCursorRects()` to re-add them.
    public func discardCursorRects() {
        quillCursorRects.removeAll()
    }
}

// MARK: - NSBitmapImageRep: CGImage init + TIFF compression

extension NSBitmapImageRep {
    /// TIFF compression schemes (Apple-exact raw values). SolderScope's
    /// SnapshotManager passes `.lzw` under the `.compressionMethod` property
    /// key; the inert `representation(using:properties:)` pass-through
    /// ignores it (no codec backend yet).
    public enum TIFFCompression: UInt, Sendable {
        case none = 1
        case ccittfax3 = 3
        case ccittfax4 = 4
        case lzw = 5
        case jpeg = 6
        case next = 32766
        case packBits = 32773
        case oldJPEG = 32865
    }

    /// `init(cgImage:)` — wrap a CGImage in a rep. Non-failable, exactly as on
    /// Apple (SolderScope chains `NSBitmapImageRep(cgImage:).representation(…)`
    /// without unwrapping). The Linux CGImage carries raw BGRA bytes when it
    /// came through the camera pipeline (CIContext.createCGImage); the rep
    /// keeps them WITH their geometry, and `representation(using:)` performs
    /// a REAL gdk-pixbuf encode (PNG/JPEG/TIFF/BMP) — snapshot files written
    /// through this path are decodable images (rung 4).
    public convenience init(cgImage: CGImage) {
        let pixels = Data(cgImage.quillBGRAPixels ?? [])
        let bytesPerRow = cgImage.quillBytesPerRow > 0
            ? cgImage.quillBytesPerRow
            : cgImage.width * 4
        self.init(
            quillBGRA: pixels,
            width: cgImage.width,
            height: cgImage.height,
            bytesPerRow: bytesPerRow
        )
    }
}

#endif
