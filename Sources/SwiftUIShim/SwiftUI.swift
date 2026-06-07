@_exported import Foundation
@_exported import Dispatch
@_exported import QuillSwiftUICompatibility
#if os(Linux)
// Real SwiftUI source uses `@Observable` (Observation) via `import SwiftUI` —
// Apple's SwiftUI re-exports it; mirror that on Linux so the shim provides it.
@_exported import Observation
#endif

// SwiftUI's iOS-18 `@Entry` macro for `EnvironmentValues` entries, backed by
// `QuillDataMacros.QuillEntryMacro`. Generates the computed get/set + the
// private `EnvironmentKey` peer holding the default value.
@attached(accessor)
@attached(peer, names: prefixed(`__Key_`))
public macro Entry() = #externalMacro(module: "QuillDataMacros", type: "QuillEntryMacro")

// NOTE: do NOT add `@_exported import QuillUI` here. QuillUI
// declares its own `NSImage`, `FocusState`, and other
// compatibility types that collide with the matching
// definitions in `AppKit` (QuillAppKit shim) when both are
// imported. The lowering script
// `scripts/lower-observable-for-swiftopenui.py` injects
// `import QuillUI` at the file level when a file needs the
// Quill helpers — that keeps the visibility scoped instead
// of ambient.
