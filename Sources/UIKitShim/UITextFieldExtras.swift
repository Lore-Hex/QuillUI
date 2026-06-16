//===----------------------------------------------------------------------===//
//
//  UITextFieldExtras.swift
//  QuillUIKit — additive UITextField / UIScrollView surface for Linux
//
//  Members SignalUI reaches for that the class bodies (declared by other
//  owners in this module) don't yet expose. All purely additive — nothing here
//  redeclares an existing member.
//
//  Honest Linux semantics, the same MODEL-not-engine contract as the rest of
//  the module: there is no text engine and no compositor, so every value here
//  is faithfully STORED state a future backend can consume, not behavior.
//    - `adjustsFontSizeToFitWidth` / `defaultTextAttributes` are recorded but
//      inert — nothing measures, shrinks, or styles text on Linux yet (mirrors
//      UILabel.adjustsFontSizeToFitWidth in QuillUIKit.swift).
//    - `rightView` / `rightViewMode` model the overlay slot; no overlay is
//      composited, so the view is held but never laid out or drawn.
//    - `smartDashesType` / `smartQuotesType` are input traits; with no live
//      keyboard they only round-trip their stored value.
//    - `canResignFirstResponder` is honestly `true` (the field never holds an
//      input source it couldn't release), and `reloadInputViews()` is a no-op
//      because there is no input view to swap.
//    - `UIScrollView.contentScaleFactor` defaults to 1 (no Retina backing
//      store on Linux) and is stored for code that reads it back.
//
//  Storage: extensions cannot add stored properties and the class bodies live
//  elsewhere, so each stored property is backed by one @MainActor file-scope
//  dictionary keyed by ObjectIdentifier(self) — the side-table pattern used
//  across the module.
//
//===----------------------------------------------------------------------===//

import Foundation
import CoreGraphics
import QuillFoundation
import QuillUIKit

// MARK: - UITextField input-trait enums
//
// `UITextField.ViewMode` (cases never/whileEditing/unlessEditing/always) is
// ALREADY declared by the class body, so `rightViewMode` below reuses it and we
// must NOT redeclare it here. The smart-substitution traits below have no
// existing declaration anywhere in the module, so we add minimal Apple-shaped
// enums for them.

/// Whether the field performs smart dash substitution. Raw values match
/// Apple's `UITextSmartDashesType`.
public enum UITextSmartDashesType: Int, Sendable {
    case `default` = 0
    case no = 1
    case yes = 2
}

/// Whether the field performs smart quote substitution. Raw values match
/// Apple's `UITextSmartQuotesType`.
public enum UITextSmartQuotesType: Int, Sendable {
    case `default` = 0
    case no = 1
    case yes = 2
}

// MARK: - UITextField stored-property side tables

@MainActor private var _quillAdjustsFontSizeToFitWidth: [ObjectIdentifier: Bool] = [:]
@MainActor private var _quillDefaultTextAttributes: [ObjectIdentifier: [NSAttributedString.Key: Any]] = [:]
@MainActor private var _quillRightView: [ObjectIdentifier: UIView] = [:]
@MainActor private var _quillRightViewMode: [ObjectIdentifier: UITextField.ViewMode] = [:]
@MainActor private var _quillSmartDashesType: [ObjectIdentifier: UITextSmartDashesType] = [:]
@MainActor private var _quillSmartQuotesType: [ObjectIdentifier: UITextSmartQuotesType] = [:]

public extension UITextField {

    /// Recorded but inert: nothing measures or shrinks text on Linux yet
    /// (mirrors `UILabel.adjustsFontSizeToFitWidth`).
    var adjustsFontSizeToFitWidth: Bool {
        get { _quillAdjustsFontSizeToFitWidth[ObjectIdentifier(self)] ?? false }
        set { _quillAdjustsFontSizeToFitWidth[ObjectIdentifier(self)] = newValue }
    }

    /// Typing attributes applied to newly entered text. Stored as the honest
    /// model; no text engine consumes them on Linux yet.
    var defaultTextAttributes: [NSAttributedString.Key: Any] {
        get { _quillDefaultTextAttributes[ObjectIdentifier(self)] ?? [:] }
        set { _quillDefaultTextAttributes[ObjectIdentifier(self)] = newValue }
    }

    /// The overlay view shown on the trailing edge. Held but never composited.
    var rightView: UIView? {
        get { _quillRightView[ObjectIdentifier(self)] }
        set { _quillRightView[ObjectIdentifier(self)] = newValue }
    }

    /// When `rightView` would appear. Reuses the class-body `ViewMode` enum.
    var rightViewMode: UITextField.ViewMode {
        get { _quillRightViewMode[ObjectIdentifier(self)] ?? .never }
        set { _quillRightViewMode[ObjectIdentifier(self)] = newValue }
    }

    /// Smart-dash substitution trait. Round-trips its stored value; no live
    /// keyboard consumes it.
    var smartDashesType: UITextSmartDashesType {
        get { _quillSmartDashesType[ObjectIdentifier(self)] ?? .default }
        set { _quillSmartDashesType[ObjectIdentifier(self)] = newValue }
    }

    /// Smart-quote substitution trait. Round-trips its stored value; no live
    /// keyboard consumes it.
    var smartQuotesType: UITextSmartQuotesType {
        get { _quillSmartQuotesType[ObjectIdentifier(self)] ?? .default }
        set { _quillSmartQuotesType[ObjectIdentifier(self)] = newValue }
    }

    /// Honestly `true`: the field never holds an input source it could not
    /// release on Linux.
    var canResignFirstResponder: Bool { true }
}

// MARK: - UIScrollView stored-property side table

@MainActor private var _quillScrollContentScaleFactor: [ObjectIdentifier: CGFloat] = [:]

public extension UIScrollView {

    /// The scale factor of the backing store. Defaults to 1 (no Retina backing
    /// on Linux); stored for code that reads it back.
    var contentScaleFactor: CGFloat {
        get { _quillScrollContentScaleFactor[ObjectIdentifier(self)] ?? 1 }
        set { _quillScrollContentScaleFactor[ObjectIdentifier(self)] = newValue }
    }
}
