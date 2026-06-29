// QuickLook shim for Telegram-Mac/CodeEdit preview panels; surface grows with
// the app-source ratchet.
@_exported import Foundation
@_exported import QuillFoundation

#if os(Linux)
public final class QLPreviewController: @unchecked Sendable {
    public init() {}
}
#endif
