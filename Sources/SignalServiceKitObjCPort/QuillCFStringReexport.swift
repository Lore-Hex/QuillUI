//
// QuillCFStringReexport -- on Apple, `CFString` reaches Signal's Swift through
// the SDK umbrella (Foundation re-exports CoreFoundation), so SignalUI's
// Attachments/NormalizedImage.swift can use bare `CFString` -- `[CFString:
// Any]` option dictionaries and `as CFString` casts feeding the CGImageSource
// / CGImageDestination shims -- while importing only Foundation /
// SignalServiceKit / UniformTypeIdentifiers.
//
// On QuillOS/Linux, QuillKit owns the ONE canonical CFString alias
// (`public typealias CFString = String`, Sources/QuillKit/QuillKit.swift);
// the Security shim already re-exports QuillKit for its importers. None of
// NormalizedImage's imports carried the alias, so it failed with "cannot find
// type 'CFString' in scope". This re-exports EXACTLY the one typealias (not
// all of QuillKit) through SignalServiceKit, the same way
// QuillUIKitReexport.swift carries the UIKit surface and
// Sources/CoreGraphics/CGQuillFoundationReexports.swift scopes its CG names.
//
// It must stay the QuillKit alias, NOT corelibs CoreFoundation's opaque
// CFString: `String as CFString` does not bridge on Linux, and the ImageIO
// shim signatures take URL/Any?, so the String alias is the only type that
// typechecks NormalizedImage's casts. (If the inject-foundation prepare step
// is ever run over the SignalUI tree, its CoreFoundation rule must skip --
// or strip -- `import CoreFoundation` there, exactly like the existing
// Security-files rule, or the two CFStrings become ambiguous.)
//
// Compiled into the SignalServiceKit module via the QuillPort symlink
// (quill-signal-link-ports.sh), so SSK exports it.
//
@_exported import typealias QuillKit.CFString
