// PDFKit shim for AppKit source that embeds PDF previews.
@_exported import Foundation
@_exported import QuillFoundation
@_exported import AppKit

#if os(Linux)
public final class PDFDocument: @unchecked Sendable {
    public let url: URL?

    public init?(url: URL) {
        self.url = url
    }
}

@MainActor
public final class PDFView: NSView {
    public var document: PDFDocument?
    public var backgroundColor: NSColor = .clear
}
#endif
