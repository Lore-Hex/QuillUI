// QuillActionDispatching
// ======================
// The runtime contract for target-action on Linux.
//
// There is no Objective-C runtime here, so an action `Selector` cannot be
// `perform`ed dynamically. Instead the AppKit source-lowering pass
// (QuillSourceLowering's `AppKitLowering`) rewrites `#selector(x)` ->
// `Selector("x")` and makes each app class that wires up target-action conform
// to this protocol with a generated `quillPerform(_:with:)` that switches on
// the selector name. `NSControl` / `NSMenuItem` (QuillAppKit) dispatch a fired
// action by calling `target.quillPerform(action)`.
//
// This is general + automatic: any lowered app gets working dispatch with no
// hand-edits, because the conformance is generated from the app's own
// `#selector`/`@objc` usage. The `Selector` string is an opaque,
// self-consistent key — it need not match Apple's selector mangling, since
// there is no real runtime resolving it.
//
// DECLARED IN QUILLFOUNDATION (moved from QuillAppKit) because the generated
// conformance's signature references `Selector`, which on Linux originates in
// THIS module. Co-locating the protocol with `Selector` guarantees both names
// resolve in exactly the same set of files: lowered UIKit-flavored code
// (Signal-iOS's SignalUI, 76 generated conformances) never imports AppKit,
// but every such file imports UIKit / MediaPlayer / SignalServiceKit — all of
// which `@_exported`-re-export QuillFoundation (SignalServiceKit via its
// QuillPort `QuillUIKitReexport.swift` -> UIKit -> QuillFoundation) — so it
// now sees this protocol wherever it already saw `Selector`. QuillAppKit
// keeps the name visible to AppKit-flavored consumers via a `public
// typealias` (one canonical type + aliases avoids the same-named-type-in-two-
// modules ambiguity; a typealias to a protocol still works in conformance
// position).
//
// Example of what the lowering generates for a view controller:
//
//     extension MyViewController: QuillActionDispatching {
//         public func quillPerform(_ selector: Selector, with sender: Any?) {
//             switch selector.name {
//             case "saveClicked": saveClicked()
//             case "listDoubleClicked(sender:)": listDoubleClicked(sender: sender as! AnyObject)
//             default: break
//             }
//         }
//     }
//
// (`public` on the witness: the witness must be at least as accessible as the
// conformance, and SignalUI's conformers are public/open classes.)
//
// On Apple platforms the protocol is dormant (real target-action goes through
// the ObjC runtime) but compiles unmodified — `Selector` resolves to the real
// ObjC Selector via Foundation — keeping macOS `swift build`/`swift test`
// green, mirroring the unconditional `QuillSelectorDispatching` it refines.

import Foundation

public protocol QuillActionDispatching: QuillSelectorDispatching {
    /// Invoke the action identified by `selector`, passing the firing control as
    /// `sender`. The lowering generates an implementation that switches on
    /// `selector.name` and forwards `sender` to 1-arg (`@objc func foo(sender:)`)
    /// actions; the default is a no-op so a conforming type with no matching case
    /// fails safe rather than trapping.
    func quillPerform(_ selector: Selector, with sender: Any?)
}

public extension QuillActionDispatching {
    func quillPerform(_ selector: Selector, with sender: Any?) {}
}
