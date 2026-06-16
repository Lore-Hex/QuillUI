import Foundation
import CoreGraphics
import QuillFoundation

// MARK: - Backing storage for additive stored properties
//
// Extensions cannot declare stored properties, so each stored property below is
// backed by a @MainActor file-private global dictionary keyed by
// ObjectIdentifier(self). Optional-valued properties store the value directly;
// non-optional value properties supply a sensible default in their getter.

// MARK: UIBarButtonItem storage
@MainActor private var _quillBarButtonImageInsets: [ObjectIdentifier: QuillEdgeInsets] = [:]
@MainActor private var _quillBarButtonIsHidden: [ObjectIdentifier: Bool] = [:]
@MainActor private var _quillBarButtonTintColor: [ObjectIdentifier: UIColor] = [:]

public extension UIBarButtonItem {
    var imageInsets: QuillEdgeInsets {
        get { _quillBarButtonImageInsets[ObjectIdentifier(self)] ?? .zero }
        set { _quillBarButtonImageInsets[ObjectIdentifier(self)] = newValue }
    }

    var isHidden: Bool {
        get { _quillBarButtonIsHidden[ObjectIdentifier(self)] ?? false }
        set { _quillBarButtonIsHidden[ObjectIdentifier(self)] = newValue }
    }

    var tintColor: UIColor? {
        get { _quillBarButtonTintColor[ObjectIdentifier(self)] }
        set { _quillBarButtonTintColor[ObjectIdentifier(self)] = newValue }
    }

    func setTitleTextAttributes(_ attributes: [NSAttributedString.Key: Any]?, for state: UIControl.State) {
        // No live UIKit runtime; no-op.
    }
}

// MARK: UINavigationItem storage
@MainActor private var _quillNavItemHidesBackButton: [ObjectIdentifier: Bool] = [:]
@MainActor private var _quillNavItemTitleView: [ObjectIdentifier: UIView] = [:]
@MainActor private var _quillNavItemSearchBarPlacementAllowsToolbarIntegration: [ObjectIdentifier: Bool] = [:]

public extension UINavigationItem {
    var hidesBackButton: Bool {
        get { _quillNavItemHidesBackButton[ObjectIdentifier(self)] ?? false }
        set { _quillNavItemHidesBackButton[ObjectIdentifier(self)] = newValue }
    }

    var titleView: UIView? {
        get { _quillNavItemTitleView[ObjectIdentifier(self)] }
        set { _quillNavItemTitleView[ObjectIdentifier(self)] = newValue }
    }

    var searchBarPlacementAllowsToolbarIntegration: Bool {
        get { _quillNavItemSearchBarPlacementAllowsToolbarIntegration[ObjectIdentifier(self)] ?? false }
        set { _quillNavItemSearchBarPlacementAllowsToolbarIntegration[ObjectIdentifier(self)] = newValue }
    }
}

// MARK: UIButton storage
@MainActor private var _quillButtonIsPointerInteractionEnabled: [ObjectIdentifier: Bool] = [:]

public extension UIButton {
    var isPointerInteractionEnabled: Bool {
        get { _quillButtonIsPointerInteractionEnabled[ObjectIdentifier(self)] ?? false }
        set { _quillButtonIsPointerInteractionEnabled[ObjectIdentifier(self)] = newValue }
    }

    func performPrimaryAction() {
        // No live UIKit runtime; no-op.
    }

    // NOTE: UIContextMenuInteraction is not available in this module today, so the
    // type is modeled as Any?. Switch to UIContextMenuInteraction? once that type
    // exists in QuillUIKit. Always returns nil (no live runtime).
    var contextMenuInteraction: Any? {
        return nil
    }
}
