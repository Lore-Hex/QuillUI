// QuickLookUI shim for macOS source that embeds QLPreviewView in AppKit views.
@_exported import Foundation
@_exported import QuillFoundation
@_exported import AppKit
@_exported import QuickLook

#if os(Linux)
@MainActor
public final class QLPreviewView: NSView {
    public var previewItem: Any?
    public var shouldCloseWithWindow: Bool = false

    public func close() {
        previewItem = nil
    }
}
#endif
