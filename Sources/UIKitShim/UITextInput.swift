// UIKitShim · UITextInput.swift
// =============================
// The UIKit text-input surface SignalUI exercises: UITextField (+ its
// delegate), the UITextInput document/position model, and the input-trait
// types that UIKit.swift's UITextView also adopts.
//
// This lives in the UIKit module (not QuillUIKit) deliberately: the trait
// enums it composes with (UIKeyboardType, UIReturnKeyType, UITextAutocorrection
// Type, …) and UIFont are declared in UIKit.swift, and a twin declaration in a
// re-exported module is the documented ambiguity trap (see LESSONS.md and the
// UIApplication note in QuillUIKit.swift). QuillUIKit's UIControl supplies the
// control core — UIControl.Event + addTarget/sendActions live in
// Sources/QuillUIKit/UITextInput.swift — and reaches consumers through this
// module's @_exported re-export.
//
// Honest Linux semantics: there is no keyboard, autocorrect engine, or glyph
// layout on QuillOS yet. The input traits are faithful STATE (stored, never
// consumed); delegate callbacks and control events fire only from the
// programmatic editing lifecycle (becomeFirstResponder / resignFirstResponder
// / sendActions). The document geometry (UITextPosition/UITextRange) is a
// REAL model over UTF-16 offsets — offset/position/textRange compute exactly,
// which is all SignalUI's FormattedNumberField caret math needs.

import Foundation
import QuillFoundation
import QuillKit
import QuillUIKit

#if !os(iOS)

// MARK: - Input-trait types

public enum UITextSpellCheckingType: Sendable {
    case `default`
    case no
    case yes
}

/// Raw values match Apple's.
public enum UIKeyboardAppearance: Int, Sendable {
    case `default` = 0
    case dark = 1
    case light = 2
}

/// iOS 18's Writing Tools opt-out knob. SignalUI's disableAiWritingTools()
/// (UIKitExtensions/UIKit+Text.swift) assigns `.none` inside
/// `if #available(iOS 18, *)` — dead at runtime here, but Swift type-checks
/// unavailable branches, so the symbols must exist. Raw values match Apple's
/// (NS/UIWritingToolsBehavior).
public enum UIWritingToolsBehavior: Int, Sendable {
    case none = -1
    case `default` = 0
    case complete = 1
    case limited = 2
}

/// Semantic-content hints for autofill. Inert on Linux (no autofill system);
/// the values are carried faithfully.
public struct UITextContentType: RawRepresentable, Equatable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let name = UITextContentType(rawValue: "name")
    public static let givenName = UITextContentType(rawValue: "given-name")
    public static let familyName = UITextContentType(rawValue: "family-name")
    public static let nickname = UITextContentType(rawValue: "nickname")
    public static let organizationName = UITextContentType(rawValue: "organization-name")
    public static let telephoneNumber = UITextContentType(rawValue: "tel")
    public static let emailAddress = UITextContentType(rawValue: "email")
    public static let URL = UITextContentType(rawValue: "URL")
    public static let username = UITextContentType(rawValue: "username")
    public static let password = UITextContentType(rawValue: "password")
    public static let newPassword = UITextContentType(rawValue: "new-password")
    public static let oneTimeCode = UITextContentType(rawValue: "one-time-code")
    public static let creditCardNumber = UITextContentType(rawValue: "cc-number")
}

public extension UIKeyboardType {
    /// iOS 10's ASCII-only number pad (SignalUI's FormattedNumberField uses
    /// it). The UIKeyboardType enum in UIKit.swift predates it; a static
    /// stand-in (rather than a new case) keeps any existing exhaustive
    /// switches valid, and keyboards are inert on Linux so the distinction
    /// from .numberPad carries no behavior anyway.
    static var asciiCapableNumberPad: UIKeyboardType { .numberPad }
}

// MARK: - UITextInput document model

/// A position in a text field/view's content. Apple's positions are opaque
/// layout-engine handles; with no layout engine on Linux a plain UTF-16
/// offset is the faithful equivalent (and is exactly what SignalUI's caret
/// math reduces to). UITextRange — the normalized pair of these — lives in
/// UIKit.swift next to the UITextView that stores one.
open class UITextPosition: NSObject {
    /// UTF-16 offset into the owning field's text. Module-internal: outside
    /// callers compare positions through offset(from:to:), like on Apple.
    let quillUTF16Offset: Int

    public override init() {
        self.quillUTF16Offset = 0
        super.init()
    }

    init(quillUTF16Offset: Int) {
        self.quillUTF16Offset = quillUTF16Offset
        super.init()
    }
}

/// The document/position protocol — the slice SignalUI exercises.
/// (SignalUI's FormattedNumberField declares `protocol TextInput: UITextInput`
/// and conforms UITextField/UITextView to it UPSTREAM, so no conformances are
/// declared here; the classes just supply the members.)
@MainActor public protocol UITextInput: AnyObject {
    var beginningOfDocument: UITextPosition { get }
    var endOfDocument: UITextPosition { get }
    var selectedTextRange: UITextRange? { get set }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int
    func position(from position: UITextPosition, offset: Int) -> UITextPosition?
    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange?
}

/// The system input delegate. On Apple the text system observes edits through
/// it; SignalUI pokes it directly (acceptAutocorrectSuggestion). Nothing on
/// Linux installs one, so the calls are no-ops against a nil delegate.
@MainActor public protocol UITextInputDelegate: AnyObject {
    func selectionWillChange(_ textInput: UITextInput?)
    func selectionDidChange(_ textInput: UITextInput?)
    func textWillChange(_ textInput: UITextInput?)
    func textDidChange(_ textInput: UITextInput?)
}

// Default no-op implementations stand in for Objective-C optional methods.
public extension UITextInputDelegate {
    @MainActor func selectionWillChange(_ textInput: UITextInput?) {}
    @MainActor func selectionDidChange(_ textInput: UITextInput?) {}
    @MainActor func textWillChange(_ textInput: UITextInput?) {}
    @MainActor func textDidChange(_ textInput: UITextInput?) {}
}

// MARK: - UITextFieldDelegate

@MainActor public protocol UITextFieldDelegate: AnyObject {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool
    func textFieldDidBeginEditing(_ textField: UITextField)
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool
    func textFieldDidEndEditing(_ textField: UITextField)
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool
    func textFieldShouldClear(_ textField: UITextField) -> Bool
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    func textFieldDidChangeSelection(_ textField: UITextField)
}

// Default implementations mirror UIKit's optional-method defaults.
public extension UITextFieldDelegate {
    @MainActor func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool { true }
    @MainActor func textFieldDidBeginEditing(_ textField: UITextField) {}
    @MainActor func textFieldShouldEndEditing(_ textField: UITextField) -> Bool { true }
    @MainActor func textFieldDidEndEditing(_ textField: UITextField) {}
    @MainActor func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool { true }
    @MainActor func textFieldShouldClear(_ textField: UITextField) -> Bool { true }
    @MainActor func textFieldShouldReturn(_ textField: UITextField) -> Bool { true }
    @MainActor func textFieldDidChangeSelection(_ textField: UITextField) {}
}

// MARK: - UITextField

/// Single-line text control. Subclasses QuillUIKit's UIControl (the same
/// cross-module pattern as UISwitch in UIKit.swift); target-action comes from
/// the UIControl extension in QuillUIKit. Declares NO designated initializers
/// on purpose: it inherits UIView's init()/init(frame:), and will pick up
/// init?(coder:) automatically when the UIView spine grows it.
@MainActor open class UITextField: UIControl {

    /// Raw values match Apple's. The border is model-only (nothing draws it).
    public enum BorderStyle: Int, Sendable {
        case none = 0
        case line = 1
        case bezel = 2
        case roundedRect = 3
    }

    /// When an overlay (the clear button, left/right views) shows.
    /// Raw values match Apple's.
    public enum ViewMode: Int, Sendable {
        case never = 0
        case whileEditing = 1
        case unlessEditing = 2
        case always = 3
    }

    // MARK: Text

    /// Backing storage is the plain string: SignalUI styles whole fields via
    /// font/textColor, not per-range attributes, so `attributedText` is the
    /// attributed view of the same storage and preserves only the string on
    /// round-trip (honest model — no rich storage).
    open var text: String?

    open var attributedText: NSAttributedString? {
        get { text.map { NSAttributedString(string: $0) } }
        set { text = newValue?.string }
    }

    open var attributedPlaceholder: NSAttributedString?

    /// Plain-string view of `attributedPlaceholder` (Apple couples them the
    /// same way).
    open var placeholder: String? {
        get { attributedPlaceholder?.string }
        set { attributedPlaceholder = newValue.map { NSAttributedString(string: $0) } }
    }

    open var textColor: UIColor?
    open var font: UIFont?
    open var textAlignment: NSTextAlignment = .natural
    open var borderStyle: BorderStyle = .none
    open var clearButtonMode: ViewMode = .never

    // MARK: Input traits (faithful state; no keyboard exists on Linux)

    open var keyboardType: UIKeyboardType = .default
    open var keyboardAppearance: UIKeyboardAppearance = .default
    open var returnKeyType: UIReturnKeyType = .default
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var spellCheckingType: UITextSpellCheckingType = .default
    open var isSecureTextEntry: Bool = false
    open var writingToolsBehavior: UIWritingToolsBehavior = .default
    public var textContentType: UITextContentType!

    // MARK: Delegates

    open weak var delegate: (any UITextFieldDelegate)?
    public weak var inputDelegate: (any UITextInputDelegate)?

    // MARK: Editing lifecycle
    //
    // UIKit's begin/end-editing contract, driven programmatically (there is
    // no tap-to-focus on Linux yet): become/resign consult the delegate's
    // should-hooks, flip isEditing, fire the did-hooks and the matching
    // control events. shouldChangeCharactersIn / shouldReturn / shouldClear
    // are declared (SignalUI implements them) but only a real input source
    // can drive them.

    public private(set) var isEditing = false

    @discardableResult
    open override func becomeFirstResponder() -> Bool {
        guard isEnabled else { return false }
        if isEditing { return true }
        if let delegate, !delegate.textFieldShouldBeginEditing(self) { return false }
        isEditing = true
        delegate?.textFieldDidBeginEditing(self)
        sendActions(for: .editingDidBegin)
        return true
    }

    @discardableResult
    open override func resignFirstResponder() -> Bool {
        guard isEditing else { return true }
        if let delegate, !delegate.textFieldShouldEndEditing(self) { return false }
        isEditing = false
        delegate?.textFieldDidEndEditing(self)
        sendActions(for: .editingDidEnd)
        return true
    }

    // MARK: UITextInput document geometry
    //
    // Real UTF-16 offset math (see UITextPosition above). The conformance to
    // UITextInput itself is declared upstream by SignalUI; these members
    // satisfy it.

    private var quillUTF16Length: Int { (text ?? "").utf16.count }

    public var beginningOfDocument: UITextPosition { UITextPosition() }
    public var endOfDocument: UITextPosition { UITextPosition(quillUTF16Offset: quillUTF16Length) }

    /// Caret/selection. Stored: positions are plain offsets, so a range set
    /// before a shortening edit can dangle past the new end — callers
    /// (FormattedNumberField) re-set it after every edit, and the offset math
    /// stays total either way.
    public var selectedTextRange: UITextRange?

    public func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        toPosition.quillUTF16Offset - from.quillUTF16Offset
    }

    public func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        let target = position.quillUTF16Offset + offset
        guard (0...quillUTF16Length).contains(target) else { return nil }
        return UITextPosition(quillUTF16Offset: target)
    }

    public func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        fromPosition.quillUTF16Offset <= toPosition.quillUTF16Offset
            ? UITextRange(start: fromPosition, end: toPosition)
            : UITextRange(start: toPosition, end: fromPosition)
    }

    // MARK: Sizing
    //
    // Rough single-line metrics from pointSize (no glyph engine on Linux —
    // mirrors the UITextView estimate in UIKit.swift and the UIFont metric
    // approximations documented there).

    // `override`: UIView declares the open base (QuillUIKit.swift).
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let pointSize = font?.pointSize ?? 17
        let content = (text?.isEmpty == false ? text : placeholder) ?? ""
        let width = min(max(CGFloat(content.count) * pointSize * 0.6, pointSize), size.width)
        return CGSize(width: width, height: pointSize * 1.35)
    }

    public func sizeToFit() {
        var newFrame = frame
        newFrame.size = sizeThatFits(CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        frame = newFrame
    }

    // MARK: Appearance proxy
    //
    // Inert: values set on the proxy are stored but no UIAppearance machinery
    // forwards them to instances on Linux — the same contract as
    // UINavigationBar.appearance() in QuillUIKit. Theme.setupSignalAppearance
    // sets the containment-scoped cursor tint through this.

    private static let quillAppearanceProxy = UITextField()

    public static func appearance() -> UITextField { quillAppearanceProxy }

    public static func appearance(whenContainedInInstancesOf containerTypes: [AnyObject.Type]) -> UITextField {
        _ = containerTypes // container scoping needs the appearance system; inert
        return quillAppearanceProxy
    }
}

@MainActor private var quillSearchBarTextFields: [ObjectIdentifier: UITextField] = [:]
@MainActor private var quillSearchBarWritingTools: [ObjectIdentifier: UIWritingToolsBehavior] = [:]

extension UISearchBar {
    public var searchTextField: UITextField {
        let key = ObjectIdentifier(self)
        if let existing = quillSearchBarTextFields[key] { return existing }
        let created = UITextField()
        created.text = text
        quillSearchBarTextFields[key] = created
        return created
    }

    public var writingToolsBehavior: UIWritingToolsBehavior {
        get { quillSearchBarWritingTools[ObjectIdentifier(self)] ?? .default }
        set { quillSearchBarWritingTools[ObjectIdentifier(self)] = newValue }
    }
}

// MARK: - UITextView: text-input parity
//
// The stored/overridable pieces (text, selectedTextRange, the trait vars)
// are in the CLASS BODY in UIKit.swift, because SignalUI subclasses override
// them (LinkingTextView's selectedTextRange, BodyRangesTextView's text) and
// extension members can't be overridden. What's here is the pure offset math
// and the appearance proxy, which nothing overrides.

extension UITextView: UITextInput {

    private var quillUTF16Length: Int { (attributedText?.string ?? text ?? "").utf16.count }

    public var beginningOfDocument: UITextPosition { UITextPosition() }
    public var endOfDocument: UITextPosition { UITextPosition(quillUTF16Offset: quillUTF16Length) }

    public func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        toPosition.quillUTF16Offset - from.quillUTF16Offset
    }

    public func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        let target = position.quillUTF16Offset + offset
        guard (0...quillUTF16Length).contains(target) else { return nil }
        return UITextPosition(quillUTF16Offset: target)
    }

    public func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        fromPosition.quillUTF16Offset <= toPosition.quillUTF16Offset
            ? UITextRange(start: fromPosition, end: toPosition)
            : UITextRange(start: toPosition, end: fromPosition)
    }

    /// Inert appearance proxy — same contract as UITextField.appearance above.
    private static let quillAppearanceProxy = UITextView()

    public static func appearance() -> UITextView { quillAppearanceProxy }

    public static func appearance(whenContainedInInstancesOf containerTypes: [AnyObject.Type]) -> UITextView {
        _ = containerTypes // container scoping needs the appearance system; inert
        return quillAppearanceProxy
    }
}

#endif // !os(iOS)
