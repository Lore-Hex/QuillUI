// UIScrollViewInsets.swift
// ========================
// The UIEdgeInsets-typed half of the UIScrollView inset surface.
//
// `UIEdgeInsets` is declared in this module (UIKit.swift), which DEPENDS on
// QuillUIKit where UIScrollView lives — so, exactly like the
// `quillLayoutMargins` layering documented in QuillUIKit/UIViewLayout.swift,
// the QuillEdgeInsets backing stores live down in QuillUIKit
// (UIScrollViewExtras.swift: `quillContentInset` & co.) and the public
// UIEdgeInsets-typed accessors are layered here on top.

import QuillFoundation
import QuillUIKit

#if !os(iOS)

/// Bridging between this module's UIEdgeInsets and QuillUIKit's
/// QuillEdgeInsets backing type (same four edges, different module layer).
private extension UIEdgeInsets {
    init(_ insets: QuillEdgeInsets) {
        self.init(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
    }

    var quillValue: QuillEdgeInsets {
        QuillEdgeInsets(top: top, left: left, bottom: bottom, right: right)
    }
}

extension UIScrollView {

    /// Extra padding around the content. Stored in `quillContentInset`;
    /// a genuine change notifies `scrollViewDidChangeAdjustedContentInset`
    /// (the backing setter does, since the adjusted inset tracks this one).
    /// (Apple declares the members here `open var`; extension members
    /// can't be `open`, so they are `public`.)
    public var contentInset: UIEdgeInsets {
        get { UIEdgeInsets(quillContentInset) }
        set { quillContentInset = newValue.quillValue }
    }

    /// The content inset after safe-area/keyboard adjustment — read-only,
    /// as on Apple. MODEL HONESTY: Linux has no safe areas or keyboard
    /// avoidance (`UIView.safeAreaInsets` is `.zero` in this shim), so
    /// whatever `contentInsetAdjustmentBehavior` says, the adjustment is
    /// always zero and this equals `contentInset`.
    public var adjustedContentInset: UIEdgeInsets {
        contentInset
    }

    /// Insets for the vertical scroll indicator. Stored configuration —
    /// nothing draws indicators on Linux.
    public var verticalScrollIndicatorInsets: UIEdgeInsets {
        get { UIEdgeInsets(quillVerticalScrollIndicatorInsets) }
        set { quillVerticalScrollIndicatorInsets = newValue.quillValue }
    }

    /// Insets for the horizontal scroll indicator.
    public var horizontalScrollIndicatorInsets: UIEdgeInsets {
        get { UIEdgeInsets(quillHorizontalScrollIndicatorInsets) }
        set { quillHorizontalScrollIndicatorInsets = newValue.quillValue }
    }

    /// The legacy unified indicator inset: Apple documents setting it as
    /// setting both per-axis values, and reading it as reading the vertical
    /// one — mirrored exactly.
    public var scrollIndicatorInsets: UIEdgeInsets {
        get { verticalScrollIndicatorInsets }
        set {
            verticalScrollIndicatorInsets = newValue
            horizontalScrollIndicatorInsets = newValue
        }
    }
}

#endif // !os(iOS)
