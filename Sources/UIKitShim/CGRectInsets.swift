// CGRectInsets.swift
// ==================
// `CGRect.inset(by: UIEdgeInsets)` — the UIKit (not CoreGraphics) inset
// API: each edge moves inward independently by the matching inset, unlike
// CoreGraphics' symmetric `insetBy(dx:dy:)`.
//
// It lives in this module because `UIEdgeInsets` is declared here
// (UIKit.swift), and this module DEPENDS on QuillUIKit/QuillFoundation —
// the same layering as UIScrollViewInsets.swift.

import Foundation
import QuillFoundation

#if !os(iOS)

extension CGRect {
    /// Adjusts the rectangle by the given edge insets (positive insets
    /// shrink the rect). When the insets consume the rectangle entirely,
    /// UIKit returns CGRect.null; the same sentinel value (infinite origin,
    /// zero size) is returned here, spelled out literally because the Linux
    /// CGRect's `.null` constant isn't relied on anywhere in this tree.
    public func inset(by insets: UIEdgeInsets) -> CGRect {
        let result = CGRect(
            x: origin.x + insets.left,
            y: origin.y + insets.top,
            width: size.width - insets.left - insets.right,
            height: size.height - insets.top - insets.bottom
        )
        if result.size.width < 0 || result.size.height < 0 {
            return CGRect(x: CGFloat.infinity, y: CGFloat.infinity, width: 0, height: 0)
        }
        return result
    }
}

#endif // !os(iOS)
