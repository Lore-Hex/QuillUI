@_exported import Foundation
@_exported import Dispatch
@_exported import QuillSwiftUICompatibility
// On macOS, Apple's SwiftUI re-exports AppKit — real Mac apps lean on that:
// a file with only `import SwiftUI` freely uses NSView/NSEvent/NSCursor and,
// via AppKit's own re-exports, CALayer + QuillFoundation's CoreGraphics types.
// QuillOS is the macOS-flavored desktop, so mirror that topology. First
// conformance driver: rjwalters/SolderScope (compiled unmodified on Linux).
@_exported import AppKit

// NOTE: do NOT add `@_exported import QuillUI` here. QuillUI
// declares its own `NSImage`, `FocusState`, and other
// compatibility types that collide with the matching
// definitions in `AppKit` (QuillAppKit shim) when both are
// imported. The lowering script
// `scripts/lower-observable-for-swiftopenui.py` injects
// `import QuillUI` at the file level when a file needs the
// Quill helpers — that keeps the visibility scoped instead
// of ambient.
