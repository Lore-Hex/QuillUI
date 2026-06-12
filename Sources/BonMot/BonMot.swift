// BonMot -- Linux shim for compiling Signal-iOS SignalUI against QuillUI (QuillOS).
// Symbols are added on demand as the SignalUI compile reports missing API.
import Foundation

// BonMot's Composable surface: upstream BonMot conforms NSAttributedString
// (and String) to Composable, whose extension provides `attributedString()`.
// Signal-iOS calls it on NSTextStorage (ImageEditorCanvasView,
// BodyRangesTextView) in files that do NOT import BonMot — that resolves
// upstream (and here) via Swift's pre-MemberImportVisibility member lookup,
// which sees extension members from any module loaded by the target (other
// SignalUI files import BonMot). Declared as plain extensions, not a
// protocol, until more of Composable's surface is demanded.
public extension NSAttributedString {
    /// Returns a styled copy. The shim applies no styling (there is no
    /// StringStyle surface yet); copying preserves BonMot's snapshot
    /// semantics, which matter when the receiver is a mutable NSTextStorage.
    func attributedString() -> NSAttributedString {
        NSAttributedString(attributedString: self)
    }
}

public extension String {
    /// BonMot Composable: a String composes to an unstyled attributed string.
    func attributedString() -> NSAttributedString {
        NSAttributedString(string: self)
    }
}
