//
// SignalServiceKit selector-API compile shims for QuillOS (Track B).
//
// swift-corelibs-foundation on Linux has no Objective-C runtime, so the
// `Selector` type (an ObjectiveC-overlay type on Apple) and the selector-based
// Cocoa observation APIs are absent. The lowering pass rewrote `#selector(foo)`
// to the opaque token `Selector("foo")`. Re-exporting `Selector` here — SAME
// MODULE as SignalServiceKit — means every SSK file resolves it with no extra
// import, and the re-export also puts QuillFoundation in SSK's import closure,
// so QuillFoundation's `NotificationCenter.addObserver(_:selector:name:object:)`
// overload (FoundationLinuxClone.swift — the ONE owner) covers the "extra
// argument 'selector'" calls that corelibs NotificationCenter does not provide.
// Do NOT redeclare that overload here: once `Selector` unified, a local copy
// has the identical signature and makes every call ambiguous for SignalUI
// files (they see both SignalServiceKit and QuillFoundation).
//
// RUNTIME: selector-dispatched observers do NOT fire — a durable lowering pass
// should rewrite them to closures; tracked separately.
//
import Foundation

/// Opaque selector token (Apple's `Selector` lives in the ObjectiveC overlay,
/// which is absent on Linux). ONE canonical type: QuillFoundation's —
/// re-exported here so every SSK file resolves it with no extra import.
/// A second struct declaration made `Selector` ambiguous for every
/// SignalUI file (they see both SignalServiceKit and QuillFoundation).
@_exported import struct QuillFoundation.Selector
