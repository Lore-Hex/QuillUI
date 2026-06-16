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
// No longer declared here. RSColor (QuillFoundation) gained real RGBA storage
// in Phase B, and now owns `init(red:green:blue:alpha:)`, `init(white:alpha:)`,
// and both `getRed(...)` overloads as class members. The extension copies this
// file used to carry were (a) lossy — they delegated to `self.init()`, turning
// every `UIColor(rgbHex:)` black — and (b) ambiguous with the QuillAppKit /
// QuillFoundation declarations from any module importing both (SignalUI's
// "ambiguous use of 'init(white:alpha:)'"). One name, one owner: the class.
