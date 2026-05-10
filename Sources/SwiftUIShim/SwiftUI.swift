@_exported import Foundation
@_exported import Dispatch
@_exported import SwiftOpenUI
// Re-export QuillUI so `import SwiftUI` on Linux pulls in
// QuillUI's compatibility surface: `QuillObservableObject`,
// `QuillPublished`, `ButtonStyle` + `ButtonStyleConfiguration`,
// `NSImage`, `QuillHotkeyService`, `QuillCheckForUpdatesMenuItem`,
// etc. The Apple-platform branch of QuillUI.swift uses Apple's
// real SwiftUI, so this re-export is conditional to avoid pulling
// QuillUI into the macOS build path twice.
@_exported import QuillUI

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
