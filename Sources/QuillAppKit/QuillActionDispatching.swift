// QuillActionDispatching
// ======================
// The runtime contract for AppKit target-action on Linux.
//
// There is no Objective-C runtime here, so an action `Selector` cannot be
// `perform`ed dynamically. Instead the AppKit source-lowering pass
// (QuillSourceLowering's `AppKitLowering`) rewrites `#selector(x)` ->
// `Selector("x")` and makes each app class that wires up target-action conform
// to this protocol with a generated `quillPerform(_:)` that switches on the
// selector name. `NSControl` / `NSMenuItem` dispatch a fired action by calling
// `target.quillPerform(action)`.
//
// This is general + automatic: any AppKit app gets working dispatch with no
// hand-edits, because the conformance is generated from the app's own
// `#selector`/`@objc` usage. The `Selector` string is an opaque, self-consistent
// key — it need not match Apple's selector mangling, since there is no real
// runtime resolving it.
//
// Example of what the lowering generates for a view controller:
//
//     extension MyViewController: QuillActionDispatching {
//         func quillPerform(_ selector: Selector, with sender: Any?) {
//             switch selector.name {
//             case "saveClicked": saveClicked()
//             case "listDoubleClicked(sender:)": listDoubleClicked(sender: sender as! AnyObject)
//             default: break
//             }
//         }
//     }

#if os(Linux)

import QuillFoundation

// CANONICAL DECLARATION MOVED to QuillFoundation/QuillActionDispatching.swift.
//
// Why: the generated conformance's `quillPerform(_ selector: Selector, …)`
// signature references `Selector`, which on Linux originates in
// QuillFoundation — declaring the protocol next to it guarantees that every
// lowered file that can resolve `Selector` also resolves the protocol. That
// includes UIKit-flavored lowered code (Signal-iOS's SignalUI) which never
// imports the AppKit shadow, but reaches QuillFoundation through the
// `@_exported` chains of UIKit / MediaPlayer / SignalServiceKit.
//
// This alias keeps the name visible to AppKit-flavored consumers (the
// `NSControl`/`NSMenuItem` `quillPerform` dispatch in QuillAppKit.swift, plus
// WireGuard's generated conformances). One canonical type + a typealias is
// the non-ambiguous shape (LESSONS.md: same-named public types across visible
// modules are ambiguous; aliases of one canonical type are fine), and a
// typealias to a protocol works in conformance position
// (`extension Foo: QuillActionDispatching`).
public typealias QuillActionDispatching = QuillFoundation.QuillActionDispatching

#endif
