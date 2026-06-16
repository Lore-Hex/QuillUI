// UITableViewInsets.swift
// =======================
// The UITableView-family separator-inset surface.
//
// `UIEdgeInsets` is now a typealias to QuillUIKit's `QuillEdgeInsets` (see
// UIKit.swift), so these accessors read/write the QuillEdgeInsets backing
// stores directly — no module-layer conversion is needed any more.
//
// contentInset / adjustedContentInset / scrollIndicatorInsets are INHERITED
// from UIScrollView's class body (QuillUIKit.swift) since the UIScrollView
// re-parent — they are `open` members now, so subclasses override them
// directly and there is no extension accessor to shadow. Only the
// table/cell-specific `separatorInset` lives here.

import QuillFoundation
import QuillUIKit

#if !os(iOS)

extension UITableView {

    /// The default inset applied to every row separator. Apple's documented
    /// default ({0, 15, 0, 0}) lives in the backing store.
    public var separatorInset: UIEdgeInsets {
        get { quillTableSeparatorInset }
        set { quillTableSeparatorInset = newValue }
    }
}

extension UITableViewCell {

    /// The per-cell separator inset override.
    public var separatorInset: UIEdgeInsets {
        get { quillCellSeparatorInset }
        set { quillCellSeparatorInset = newValue }
    }
}

#endif // !os(iOS)
