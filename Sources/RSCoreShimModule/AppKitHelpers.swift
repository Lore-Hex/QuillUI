import AppKit

@MainActor
public protocol KeyboardDelegate: AnyObject {
    func keydown(_ event: NSEvent, in view: NSView) -> Bool
}
