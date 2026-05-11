@_exported import Foundation
@_exported import Dispatch
@_exported import SwiftOpenUI

// NOTE: do NOT add `@_exported import QuillUI` here. QuillUI
// declares its own `NSImage`, `FocusState`, and other
// compatibility types that collide with the matching
// definitions in `AppKit` (QuillAppKit shim) when both are
// imported. The lowering script
// `scripts/lower-observable-for-swiftopenui.py` injects
// `import QuillUI` at the file level when a file needs the
// Quill helpers — that keeps the visibility scoped instead
// of ambient.

#if os(Linux)
// Upstream SwiftUI exposes `Font.Weight` as a nested type. SwiftOpenUI
// uses a top-level `FontWeight`. Bridge it so `SwiftUI.Font.Weight`
// resolves to the SwiftOpenUI shape without modifying upstream source.
public extension Font {
    typealias Weight = FontWeight
}

// Baseline-relative `VerticalAlignment` cases live HERE — the
// SwiftUI shim is the canonical home so that files importing
// only SwiftUI (e.g. the MarkdownUI / Splash / Vortex shims)
// can use them. QuillUI doesn't redeclare them; consumers that
// also `import QuillUI` see exactly one definition. On Linux
// SwiftOpenUI's `VerticalAlignment` only ships `.top`,
// `.center`, `.bottom`, so we downgrade baseline alignments to
// the nearest visual approximation until GTK Pango layout
// integration lands.
public extension VerticalAlignment {
    static var firstTextBaseline: VerticalAlignment { .top }
    static var lastTextBaseline: VerticalAlignment { .bottom }
}
#endif
