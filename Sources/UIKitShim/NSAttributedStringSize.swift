// NSAttributedString.size() — UIKit/AppKit's NSStringDrawing measurement
// method (SignalUI calls it ~99×: CVCapsuleLabel truncation, Tooltip popover
// sizing, …). Linux-gated like NSAttributedString.boundingRect in UIKit.swift:
// Apple platforms ship the real method, so this must not compile there.

import Foundation
import QuillFoundation

#if os(Linux)

public extension NSAttributedString {
    /// UIKit's `size()`: the bounding size of the string drawn in a single
    /// line (no wrapping).
    ///
    /// MODEL HONESTY: there is no glyph layout engine on Linux. This routes
    /// through the shim's `boundingRect(with:)` (UIKit.swift) with an
    /// unconstrained proposed size, i.e. the `quillEstimatedTextRect`
    /// estimate — char advance = 0.6 × pointSize, line height =
    /// 1.2 × pointSize, font read from the attributes at index 0 only.
    /// Widths are rough, so size()-driven truncation and popover layout are
    /// approximate, not glyph-accurate; embedded newlines are not given
    /// extra lines (matching the estimator's single-block model).
    func size() -> CGSize {
        boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)).size
    }
}

#endif
