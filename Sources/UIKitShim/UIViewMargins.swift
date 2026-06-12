// UIViewMargins.swift — UIEdgeInsets-typed margin + safe-area surface on UIView.
//
// LAYERING: UIView and its margin STORAGE (`quillLayoutMargins`, a
// QuillEdgeInsets) live in QuillUIKit, but UIEdgeInsets and
// NSDirectionalEdgeInsets are declared in THIS module (UIKit.swift), which
// depends on QuillUIKit — so the UIKit-typed accessors are layered here over
// that storage, exactly as the comment on `quillLayoutMargins` in
// QuillUIKit.swift promises. The Bool margin flags
// (preservesSuperviewLayoutMargins / insetsLayoutMarginsFromSafeArea) need no
// UIKit-only types and live in QuillUIKit's UIViewMargins.swift.

import Foundation
import QuillFoundation
import QuillUIKit

#if !os(iOS)

public extension UIView {
    /// UIKit's layoutMargins, layered over QuillUIKit's `quillLayoutMargins`
    /// storage (8pt on every edge by default, matching UIKit). Setting margins
    /// marks the view for relayout, as UIKit does.
    /// MODEL HONESTY (same caveat as the storage): margins are recorded, but
    /// the native layout pass does not yet inset layoutMarginsGuide by them.
    var layoutMargins: UIEdgeInsets {
        get {
            let stored = quillLayoutMargins
            return UIEdgeInsets(top: stored.top, left: stored.left, bottom: stored.bottom, right: stored.right)
        }
        set {
            quillLayoutMargins = QuillEdgeInsets(top: newValue.top, left: newValue.left, bottom: newValue.bottom, right: newValue.right)
            setNeedsLayout()
        }
    }

    /// Writing-direction-relative view of the SAME margins — UIKit couples the
    /// two properties, resolving leading/trailing against the layout
    /// direction. QuillOS lays out left-to-right only, so leading == left and
    /// trailing == right.
    var directionalLayoutMargins: NSDirectionalEdgeInsets {
        get {
            let stored = quillLayoutMargins
            return NSDirectionalEdgeInsets(top: stored.top, leading: stored.left, bottom: stored.bottom, trailing: stored.right)
        }
        set {
            quillLayoutMargins = QuillEdgeInsets(top: newValue.top, left: newValue.leading, bottom: newValue.bottom, right: newValue.trailing)
            setNeedsLayout()
        }
    }

    /// Zero on QuillOS: windows are plain rectangles (no status bar, notch, or
    /// home indicator), so the safe area IS the view's bounds — the same model
    /// as safeAreaLayoutGuide (which aliases the view's own edges, see
    /// QuillUIKit.swift) and UIWindow.safeAreaInsets in UIKit.swift.
    var safeAreaInsets: UIEdgeInsets { .zero }
}

#endif // !os(iOS)
