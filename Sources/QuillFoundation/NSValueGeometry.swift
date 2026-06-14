// NSValueGeometry.swift
// =====================
// CoreGraphics-geometry boxing for NSValue (NSValue(cgRect:) / .cgRectValue and
// the CGPoint/CGSize siblings).
//
// On Apple platforms these come from UIKit's NSValue+UIGeometry additions.
// swift-corelibs-Foundation's NSValue ships the AppKit-flavored
// `NSValue(rect:)/.rectValue`, `NSValue(point:)/.pointValue` and
// `NSValue(size:)/.sizeValue` — and on Linux `NSRect == CGRect`,
// `NSPoint == CGPoint`, `NSSize == CGSize` (they are the very same structs).
// So the faithful, value-preserving implementation is simply to delegate the
// CoreGraphics-named additions to corelibs' geometry boxing: the value round-
// trips natively (including NSValue equality), with no side table.

import Foundation

#if os(Linux)

public extension NSValue {
    /// Boxes a `CGRect`, mirroring UIKit's `NSValue(cgRect:)`.
    convenience init(cgRect rect: CGRect) {
        self.init(rect: rect)
    }

    /// Boxes a `CGPoint`, mirroring UIKit's `NSValue(cgPoint:)`.
    convenience init(cgPoint point: CGPoint) {
        self.init(point: point)
    }

    /// Boxes a `CGSize`, mirroring UIKit's `NSValue(cgSize:)`.
    convenience init(cgSize size: CGSize) {
        self.init(size: size)
    }

    /// The boxed rect (UIKit's `.cgRectValue`), read back through corelibs'
    /// `.rectValue` since the structs are identical on Linux.
    var cgRectValue: CGRect { rectValue }

    /// The boxed point (UIKit's `.cgPointValue`).
    var cgPointValue: CGPoint { pointValue }

    /// The boxed size (UIKit's `.cgSizeValue`).
    var cgSizeValue: CGSize { sizeValue }
}

#endif // os(Linux)
