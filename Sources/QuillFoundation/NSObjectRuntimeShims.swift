// NSObjectRuntimeShims.swift
// ==========================
// `forwardingTarget(for:)` — the first hook in Cocoa's message forwarding.
//
// On Darwin it comes from the ObjC runtime (an unrecognized selector consults
// `-forwardingTargetForSelector:`). Linux has no ObjC runtime, and swift-
// corelibs-Foundation's NSObject does not declare this method, so SignalUI's
// `forwardingTarget(for:)` references fail to resolve. This extension supplies
// Apple's default.
//
// NOT included here: `copy()`. swift-corelibs-Foundation's NSObject ALREADY
// declares `open func copy() -> Any` (and `mutableCopy()`), routing through
// NSCopying — so adding it in an extension would be an invalid redeclaration.
// Any surviving "no member 'copy'" error is therefore on a non-NSObject
// receiver and is out of scope for an NSObject shim (see the wave-8 report).
//
// MODEL HONESTY: `forwardingTarget(for:)` returns nil — "I do not forward,"
// exactly NSObject's default. Subclasses may override it; with no ObjC runtime
// nothing actually consults it on Linux, so it is inert state.

import Foundation

#if os(Linux)

public extension NSObject {
    /// First message-forwarding hook. nil = "not forwarded," matching NSObject.
    func forwardingTarget(for aSelector: Selector) -> Any? {
        _ = aSelector
        return nil
    }
}

#endif // os(Linux)
