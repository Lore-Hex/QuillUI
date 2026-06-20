// Cocoa shadow module — `import Cocoa` umbrella for recompiled macOS app source.
// Cocoa re-exports AppKit + Foundation (+ CoreData on real macOS, omitted here).
// Re-exporting lets unmodified upstream files that `import Cocoa` resolve NSView,
// NSTextField, NSLayoutConstraint, CoreText layout calls, etc. from the Quill
// Apple-framework shadows.
@_exported import CoreGraphics
@_exported import CoreImage
@_exported import CoreServices
@_exported import CoreText
@_exported import QuartzCore
@_exported import AppKit
@_exported import Foundation
