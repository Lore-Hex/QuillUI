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

public protocol QuillActionDispatching: AnyObject {
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

#endif
