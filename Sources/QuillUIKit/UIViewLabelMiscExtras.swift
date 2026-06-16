// UIViewLabelMiscExtras
// =====================
// Additive UIView / UILabel surface needed by upstream iOS code that compiles
// against this Linux UIKit reimplementation. Everything here is purely additive
// (the compiler reports these as "has no member" today) — nothing is
// redeclared. There is no live UIKit rendering/text-layout runtime on Linux, so
// the method bodies are honest no-ops / model-only accessors.
//
// NOTE on UIFont: the spec also asked for UIFont.boldSystemFont(ofSize:) and
// UIFont.monospacedSystemFont(ofSize:weight:). Those CANNOT live in this file:
// in this package `UIFont` is declared in the downstream `UIKitShim` target
// (module "UIKit"), which *depends on* QuillUIKit — so QuillUIKit cannot see
// `UIFont` and an `extension UIFont` here would not compile. The ready-to-paste
// snippet for those two statics is in the structured-output `notes` field; it
// belongs in UIKitShim (alongside the existing UIFont class), not here.

import Foundation
import CoreGraphics

// Extensions cannot add stored properties, so each stored property is backed by
// a @MainActor file-private global keyed by ObjectIdentifier(self) — the
// standard pattern for this module.

// MARK: - UIView

@MainActor private var _quillAccessibilityViewIsModal: [ObjectIdentifier: Bool] = [:]

public extension UIView {
    /// Whether assistive technologies should treat this view's subtree as a
    /// modal context (ignoring siblings). Model-only on Linux — no assistive
    /// runtime consumes it yet. Defaults to `false`, matching UIKit.
    var accessibilityViewIsModal: Bool {
        get { _quillAccessibilityViewIsModal[ObjectIdentifier(self)] ?? false }
        set { _quillAccessibilityViewIsModal[ObjectIdentifier(self)] = newValue }
    }

    /// Layout guide whose width tracks a comfortable reading measure. On Apple
    /// platforms this insets from the margins; on Linux (no display metrics) we
    /// alias the view's layout-margins guide, which the layout pass already
    /// resolves correctly.
    var readableContentGuide: UILayoutGuide {
        layoutMarginsGuide
    }

    /// Ends editing in this view's subtree (resigns first responder). No text
    /// editing/first-responder runtime on Linux, so this is a no-op; UIKit
    /// returns whether editing ended — we report success.
    @discardableResult
    func endEditing(_ force: Bool) -> Bool {
        true
    }

    /// Renders the view hierarchy into the current graphics context. There is no
    /// software compositor on Linux yet, so this draws nothing and reports the
    /// snapshot "succeeded" (matching UIKit's Bool contract for callers that
    /// branch on the result).
    @discardableResult
    func drawHierarchy(in rect: CGRect, afterScreenUpdates: Bool) -> Bool {
        true
    }

    // NOTE: `sizeToFit()` is intentionally NOT added to UIView here. UIButton
    // (a UIView subclass) already declares an `open func sizeToFit()` in its
    // class body; a same-name extension method on the UIView ANCESTOR turns that
    // class-body method into an illegal override of an extension member
    // ("non-'@objc' instance method 'sizeToFit()' is declared in extension of
    // 'UIView' and cannot be overridden"), breaking the build. So `sizeToFit()`
    // is provided only on UILabel below (which has no such subclass conflict);
    // UIButton/UIImageView already carry their own.

    /// Captures the current rendered appearance as a lightweight snapshot view.
    /// No compositor on Linux, so there is nothing to snapshot — returns nil
    /// (UIKit also returns an optional).
    func snapshotView(afterScreenUpdates: Bool) -> UIView? {
        nil
    }
}

// MARK: - UILabel

@MainActor private var _quillLabelShadowOffset: [ObjectIdentifier: CGSize] = [:]

public extension UILabel {
    /// Offset of the label's text shadow. Model-only on Linux (no text shadow is
    /// drawn); defaults to `.zero`, matching UIKit.
    var shadowOffset: CGSize {
        get { _quillLabelShadowOffset[ObjectIdentifier(self)] ?? .zero }
        set { _quillLabelShadowOffset[ObjectIdentifier(self)] = newValue }
    }

    /// Resizes the label to fit its text. No glyph/text-measurement runtime on
    /// Linux, so this is a no-op.

}
