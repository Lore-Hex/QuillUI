// UITableViewInsets.swift
// =======================
// The UIEdgeInsets-typed half of the UITableView-family inset surface.
//
// `UIEdgeInsets` is declared in this module (UIKit.swift), which DEPENDS on
// QuillUIKit where UITableView / UITableViewCell live — so, exactly like the
// `quillLayoutMargins` and UIScrollViewInsets.swift layerings, the
// QuillEdgeInsets backing stores live down in QuillUIKit
// (UITableViewExtras.swift: `quillTableContentInset` & co.) and the public
// UIEdgeInsets-typed accessors are layered here on top.
//
// NOTE: UITableView currently subclasses UIView, not UIScrollView (class
// body in QuillUIKit.swift, another owner), which is why `contentInset`
// needs its own backing here instead of inheriting UIScrollView's. When the
// table is re-parented these accessors will shadow the scroll view's; the
// two backings should be consolidated then.

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

extension UITableView {

    /// Extra padding around the table's content. Stored in
    /// `quillTableContentInset`. (Apple declares these members `open var`;
    /// extension members can't be `open`, so they are `public`.)
    public var contentInset: UIEdgeInsets {
        get { UIEdgeInsets(quillTableContentInset) }
        set { quillTableContentInset = newValue.quillValue }
    }

    /// The content inset after safe-area/keyboard adjustment — read-only,
    /// as on Apple. MODEL HONESTY: Linux has no safe areas or keyboard
    /// avoidance (`UIView.safeAreaInsets` is `.zero` in this shim), so the
    /// adjustment is always zero and this equals `contentInset`.
    public var adjustedContentInset: UIEdgeInsets {
        contentInset
    }

    /// The default inset applied to every row separator. Apple's documented
    /// default ({0, 15, 0, 0}) lives in the backing store.
    public var separatorInset: UIEdgeInsets {
        get { UIEdgeInsets(quillTableSeparatorInset) }
        set { quillTableSeparatorInset = newValue.quillValue }
    }
}

extension UITableViewCell {

    /// The per-cell separator inset override.
    public var separatorInset: UIEdgeInsets {
        get { UIEdgeInsets(quillCellSeparatorInset) }
        set { quillCellSeparatorInset = newValue.quillValue }
    }
}

#endif // !os(iOS)
