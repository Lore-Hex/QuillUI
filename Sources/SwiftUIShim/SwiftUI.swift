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

// Upstream SwiftUI exposes baseline-relative vertical alignments
// (`.firstTextBaseline`, `.lastTextBaseline`) that SwiftOpenUI's
// `VerticalAlignment` does not. On Linux, downgrade to `.top` /
// `.bottom` — the actual baseline math isn't implemented in the
// GTK backend yet, but the closest visual approximation keeps
// upstream `HStack(alignment: .firstTextBaseline, …)` call sites
// compiling without app-side rewrites.
public extension VerticalAlignment {
    static var firstTextBaseline: VerticalAlignment { .top }
    static var lastTextBaseline: VerticalAlignment { .bottom }
}
#endif
