// UIScrollViewInsets.swift
// ========================
// (Intentionally empty.)
//
// UIScrollView's UIEdgeInsets-typed inset surface — contentInset,
// adjustedContentInset, verticalScrollIndicatorInsets,
// horizontalScrollIndicatorInsets, scrollIndicatorInsets — USED to live here
// as EXTENSION accessors, because UIEdgeInsets was a distinct struct declared
// in this module (which depends on QuillUIKit, where UIScrollView lives).
//
// But extension members "cannot be overridden", and upstream scroll-view
// subclasses (e.g. StickerPackCollectionView: `override var contentInset`
// with a `didSet`) DO override them — so each override became a second
// declaration and `self.contentInset` was ambiguous (198 errors).
//
// Fix: `UIEdgeInsets` is now `typealias UIEdgeInsets = QuillEdgeInsets`
// (UIKit.swift), and QuillEdgeInsets lives in QuillUIKit, so UIScrollView now
// declares these as `open` class-body members typed by it (QuillUIKit.swift).
// The accessors are gone from here; subclasses override the inherited
// class-body members directly. The table/cell `separatorInset` accessors that
// remained extension-only stay in UITableViewInsets.swift.

#if !os(iOS)
#endif
