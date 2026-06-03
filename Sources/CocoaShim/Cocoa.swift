// Cocoa shadow module — `import Cocoa` umbrella for recompiled macOS app source.
// Cocoa re-exports AppKit + Foundation (+ CoreData on real macOS, omitted here).
// Re-exporting lets unmodified upstream files that `import Cocoa` resolve NSView,
// NSTextField, NSLayoutConstraint, etc. from the QuillAppKit shadow.
@_exported import AppKit
@_exported import Foundation
