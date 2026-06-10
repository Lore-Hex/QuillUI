//
// QuillUIKitReexport -- on Apple, `import SignalServiceKit` transitively exposes
// the UIKit (and Foundation) surface to consumers: SSK is built against UIKit and
// its module re-exports it, so Signal's UI files that `import SignalServiceKit`
// without an explicit `import UIKit` still resolve UIView / UIColor / CGFloat /
// NSCoder / NSAttributedString and the rest. On QuillOS/Linux nothing re-exported
// it, so those ~121 SignalUI files saw thousands of "cannot find type" errors.
//
// This one re-export replicates the Apple behavior. The QuillOS UIKit shim itself
// `@_exported import`s Foundation + QuillFoundation, so re-exporting UIKit carries
// the whole transitive surface (UIKit + Foundation + CoreGraphics shadows) to
// every `import SignalServiceKit` consumer -- matching how the real Signal-iOS
// code expects to compile, with no modification to Signal's source.
//
// Compiled into the SignalServiceKit module via the QuillPort symlink
// (quill-signal-link-ports.sh), so SSK exports it.
//
@_exported import UIKit
