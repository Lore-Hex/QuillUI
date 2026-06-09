//
// SignalServiceKit misc compile shims for QuillOS (Track B).
//
// Same-module fills for small Cocoa/SignalServiceKit surfaces missing on Linux,
// so the upstream Swift files that use them compile.
//
import Foundation
import UIKit

// MARK: - LocalizationNotNeeded
//
// An ObjC inline helper from Debugging/OWSAsserts.h (excluded on Linux). It just
// returns the string unchanged (annotated so the localization linter skips it).

public func LocalizationNotNeeded(_ s: String) -> String { s }

// MARK: - autoreleasepool
//
// swift-corelibs-foundation has no `autoreleasepool` on Linux (it is an ObjC
// memory construct). On Linux ARC handles this, so the pool is a no-op that just
// runs the body. The `invoking:` label covers both `autoreleasepool { … }`
// (trailing closure) and `autoreleasepool(invoking: { … })`.
//
// Signature is typed-throws (`throws(Failure)`), matching the real Swift
// ObjectiveC overlay's typed-throws migration. A single generic subsumes every
// call form: a non-throwing body infers `Failure == Never` (callable without
// `try`), an untyped-throwing body infers `Failure == any Error` (the old
// `rethrows` behavior), and a typed-throwing body — e.g. TimeGatedBatch's
// `{ () throws(E) -> … }` — propagates its precise error `E` through to the
// enclosing `throws(E)` function instead of being widened to `any Error`.

public func autoreleasepool<Result, Failure: Error>(invoking body: () throws(Failure) -> Result) throws(Failure) -> Result {
    try body()
}

// MARK: - UIColor RGB API
//
// On Linux UIColor == NSColor == RSColor (the QuillFoundation color shim), which
// lacks UIColor's standard `init(red:green:blue:alpha:)` and `getRed(...)`. Signal's
// Util/UIColor+SSK.swift (the `rgbHex` initializers) depends on both, so without
// these the whole file fails and every `UIColor(rgbHex:)` call errors. Delegates
// to the shim's `init(srgbRed:green:blue:alpha:)`; `getRed` is a stub (the shim
// does not store channel values — colors are already placeholders on Linux).

public extension UIColor {
    convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        // The cross-module color inits (white:/srgbRed:) are not all reachable from
        // this module and the RSColor shim stores no channel values anyway, so
        // delegate to the base initializer (color is a Linux placeholder).
        self.init()
    }

    // `init(white:alpha:)` lives in QuillAppKit and is not reachable from the SSK
    // module, so SSK's `UIColor(white:alpha:)` call sites fail. Define it here.
    convenience init(white: CGFloat, alpha: CGFloat) {
        self.init()
    }

    func getRed(_ red: UnsafeMutablePointer<CGFloat>?,
                green: UnsafeMutablePointer<CGFloat>?,
                blue: UnsafeMutablePointer<CGFloat>?,
                alpha: UnsafeMutablePointer<CGFloat>?) -> Bool {
        red?.pointee = 0
        green?.pointee = 0
        blue?.pointee = 0
        alpha?.pointee = 1
        return true
    }
}
