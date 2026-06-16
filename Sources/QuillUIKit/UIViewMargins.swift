// UIViewMargins.swift
// ===================
// UIView margin-behavior flags (UIKit API surface). UIView's class body lives
// in QuillUIKit.swift; rather than grow it, these are extension computed
// properties backed by ObjectIdentifier side tables — the same pattern as
// UIGestureRecognizers.swift's viewGestureRecognizers.
//
// The UIEdgeInsets-typed margin accessors (layoutMargins,
// directionalLayoutMargins, safeAreaInsets) can NOT live in this module:
// UIEdgeInsets/NSDirectionalEdgeInsets are declared in the UIKit shim module,
// which depends on this one. They are layered in Sources/UIKitShim/
// UIViewMargins.swift over the quillLayoutMargins storage (QuillUIKit.swift).
//
// MODEL HONESTY: both flags are faithful STATE — recorded and returned — but
// the native layout pass does not yet consume them (no superview-margin
// propagation, and the safe area IS the view's bounds on Linux, so there is
// nothing for insetsLayoutMarginsFromSafeArea to inset).

import QuillFoundation

#if !os(iOS)

/// Side tables for the margin flags, keyed by ObjectIdentifier. Same accepted
/// trade-off as viewGestureRecognizers: entries for deallocated views are not
/// reclaimed, so a recycled allocation could in principle inherit a stale
/// flag; the values are two Bools per view, and views that never touch the
/// flags pay nothing.
@MainActor private var viewPreservesSuperviewLayoutMargins: [ObjectIdentifier: Bool] = [:]
@MainActor private var viewInsetsLayoutMarginsFromSafeArea: [ObjectIdentifier: Bool] = [:]

public extension UIView {
    /// Whether this view widens its own margins to cover its superview's
    /// margins when it crosses them. UIKit default: false.
    var preservesSuperviewLayoutMargins: Bool {
        get { viewPreservesSuperviewLayoutMargins[ObjectIdentifier(self)] ?? false }
        set { viewPreservesSuperviewLayoutMargins[ObjectIdentifier(self)] = newValue }
    }

    /// Whether layout margins are widened to keep content inside the safe
    /// area. UIKit default: true. Inert on Linux (safe area is zero — see
    /// safeAreaLayoutGuide in QuillUIKit.swift), but recorded faithfully.
    var insetsLayoutMarginsFromSafeArea: Bool {
        get { viewInsetsLayoutMarginsFromSafeArea[ObjectIdentifier(self)] ?? true }
        set { viewInsetsLayoutMarginsFromSafeArea[ObjectIdentifier(self)] = newValue }
    }
}

#endif // !os(iOS)
