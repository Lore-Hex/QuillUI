// UIKit shim. Provides the iOS UIKit surface for upstream apps that
// `import UIKit` (Ice Cubes, NetNewsWire iOS, …) when compiled on
// platforms where Apple's real UIKit isn't available (macOS without
// Catalyst, Linux). Inlines the high-traffic types directly so
// consumers don't need to depend on QuillFoundation/QuillUIKit
// transitively.

@_exported import Foundation
@_exported import QuillFoundation
@_exported import QuillUIKit
// Re-export the UserNotifications shim so the many `import UIKit`-only SSK files
// (e.g. ExperienceUpgradeManifest) still resolve UNUserNotificationCenter & co.
// now that QuillUIKit's stub was removed in favor of the dedicated shim.
@_exported import UserNotifications
@_exported import CoreTransferable
@_exported import CoreText
// On iOS, Apple's UIKit re-exports QuartzCore — `import UIKit` alone exposes
// CALayer/CAShapeLayer/CATransaction. Signal-iOS's SignalUI relies on this
// (~4.8k of its conformance-build errors were CA* names with no QuartzCore
// import in sight). Mirror that topology here: on Linux this resolves to the
// in-tree QuartzCore shim (a declared target dependency); on Apple platforms
// it resolves to the real framework, exactly like Apple's UIKit.
@preconcurrency @_exported import QuartzCore
import QuillKit

#if !os(iOS)

public let MAXFLOAT: Float = Float.greatestFiniteMagnitude

private func recordUIKitFallback(operation: String, api: String) {
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "UIKit",
        operation: operation,
        message: "\(api) is a no-op on non-iOS platforms."
    )
}

#if canImport(AppKit) && !os(Linux)
import AppKit
public typealias UIImage = NSImage
public typealias UIColor = NSColor
public typealias UIFont = NSFont
public typealias UIScreen = NSScreen
#else
// Linux: no AppKit/UIKit fonts. Provide the UIFont surface upstream UI uses
// (scaled system fonts, the `.rounded` design). Metrics are identity on Linux.
public final class UIFont: NSObject, NSCoding, @unchecked Sendable {
    public let pointSize: CGFloat
    public let fontName: String
    public let fontDescriptor: UIFontDescriptor
    public init(descriptor: UIFontDescriptor, size: CGFloat) {
        let resolvedSize = size == 0 ? descriptor.pointSize : size
        let resolvedDescriptor = UIFontDescriptor(
            name: descriptor.name,
            symbolicTraits: descriptor.symbolicTraits
        )
        resolvedDescriptor.pointSize = resolvedSize
        self.pointSize = resolvedSize
        self.fontName = resolvedDescriptor.name
        self.fontDescriptor = resolvedDescriptor
        super.init()
    }
    init(pointSize: CGFloat, fontName: String) {
        self.pointSize = pointSize; self.fontName = fontName
        let descriptor = UIFontDescriptor(name: fontName)
        descriptor.pointSize = pointSize
        self.fontDescriptor = descriptor
        super.init()
    }
    public required init?(coder: NSCoder) {
        let decodedSize = coder.decodeDouble(forKey: "pointSize")
        self.pointSize = decodedSize == 0 ? 17 : CGFloat(decodedSize)
        self.fontName = coder.decodeObject(forKey: "fontName") as? String ?? ".AppleSystemUIFont"
        self.fontDescriptor = UIFontDescriptor(name: fontName)
        super.init()
    }
    public func encode(with coder: NSCoder) {
        coder.encode(Double(pointSize), forKey: "pointSize")
        coder.encode(fontName, forKey: "fontName")
    }
    public static func systemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(pointSize: size, fontName: ".AppleSystemUIFont")
    }
    public static func systemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(pointSize: size, fontName: ".AppleSystemUIFont")
    }
    public static func boldSystemFont(ofSize size: CGFloat) -> UIFont {
        systemFont(ofSize: size, weight: .bold)
    }
    public static func monospacedSystemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(pointSize: size, fontName: ".AppleSystemUIFontMonospaced")
    }
    // UIFont(name:size:) — failable in UIKit; inert here (no font lookup on
    // Linux), so it never actually returns nil. SSK force-unwraps it
    // (AvatarBuilder's "Inter" text-avatar font).
    public convenience init?(name: String, size: CGFloat) {
        self.init(pointSize: size, fontName: name)
    }
    // UIFont.withSize(_:) — same font (name/descriptor) at a new point size.
    public func withSize(_ size: CGFloat) -> UIFont {
        UIFont(descriptor: fontDescriptor, size: size)
    }
    // UIFont.lineHeight / .capHeight — real font metrics. There is no font engine
    // on Linux, so these are typographic approximations derived from pointSize
    // (system-font ratios: lineHeight ≈ 1.2·pointSize, capHeight ≈ 0.7·pointSize).
    // SSK uses lineHeight for text-height measurement (String+SSK.height(for:)) and
    // capHeight for vertical image-attachment centering; both degrade to approximate
    // layout on Linux (HONEST STATUS: no exact glyph metrics).
    public var lineHeight: CGFloat { pointSize * 1.2 }
    public var capHeight: CGFloat { pointSize * 0.7 }
    public struct Weight: Equatable, Sendable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let ultraLight = Weight(rawValue: -0.8)
        public static let thin = Weight(rawValue: -0.6)
        public static let light = Weight(rawValue: -0.4)
        public static let regular = Weight(rawValue: 0)
        public static let medium = Weight(rawValue: 0.23)
        public static let semibold = Weight(rawValue: 0.3)
        public static let bold = Weight(rawValue: 0.4)
        public static let heavy = Weight(rawValue: 0.56)
        public static let black = Weight(rawValue: 0.62)
    }
}
extension UIFont {
    // Equatable so SSK value types that embed a UIFont (e.g.
    // StyleDisplayConfiguration / MentionDisplayConfiguration in BodyRanges)
    // can synthesize Equatable. Compared by the inert shim's identifying
    // fields; there is no real font backing on Linux.
    public static func == (lhs: UIFont, rhs: UIFont) -> Bool {
        lhs.pointSize == rhs.pointSize
            && lhs.fontName == rhs.fontName
            && lhs.fontDescriptor.symbolicTraits == rhs.fontDescriptor.symbolicTraits
    }
}

public final class UIFontDescriptor: @unchecked Sendable {
    public let name: String
    public var pointSize: CGFloat = 17
    // Symbolic traits requested on this descriptor. Inert on Linux (no real
    // font substitution) but round-tripped so `withSymbolicTraits` composes
    // and UIFont's Equatable can distinguish bold/italic variants.
    public var symbolicTraits: SymbolicTraits
    public init(name: String = ".AppleSystemUIFont", symbolicTraits: SymbolicTraits = []) {
        self.name = name
        self.symbolicTraits = symbolicTraits
    }
    public enum SystemDesign: Equatable, Sendable { case `default`, rounded, serif, monospaced }
    public func withDesign(_ design: SystemDesign) -> UIFontDescriptor? {
        let descriptor = UIFontDescriptor(
            name: design == .rounded ? ".AppleSystemUIFontRounded-Regular" : name,
            symbolicTraits: symbolicTraits
        )
        descriptor.pointSize = pointSize
        return descriptor
    }
    // Mirror of UIKit's UIFontDescriptor.SymbolicTraits. Bit values match the
    // platform constants so any compared/persisted raw values stay stable.
    public struct SymbolicTraits: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let traitItalic = SymbolicTraits(rawValue: 1 << 0)
        public static let traitBold = SymbolicTraits(rawValue: 1 << 1)
        public static let traitExpanded = SymbolicTraits(rawValue: 1 << 5)
        public static let traitCondensed = SymbolicTraits(rawValue: 1 << 6)
        public static let traitMonoSpace = SymbolicTraits(rawValue: 1 << 10)
        public static let traitVertical = SymbolicTraits(rawValue: 1 << 11)
        public static let traitUIOptimized = SymbolicTraits(rawValue: 1 << 12)
        public static let traitTightLeading = SymbolicTraits(rawValue: 1 << 15)
        public static let traitLooseLeading = SymbolicTraits(rawValue: 1 << 16)
    }
    public func withSymbolicTraits(_ traits: SymbolicTraits) -> UIFontDescriptor? {
        let descriptor = UIFontDescriptor(name: name, symbolicTraits: symbolicTraits.union(traits))
        descriptor.pointSize = pointSize
        return descriptor
    }
}
public final class UIFontMetrics: @unchecked Sendable {
    public static let `default` = UIFontMetrics()
    public func scaledValue(for value: CGFloat) -> CGFloat { value }
    public func scaledValue(for value: CGFloat, compatibleWith traitCollection: UITraitCollection?) -> CGFloat {
        _ = traitCollection
        return scaledValue(for: value)
    }
}
#endif

// UIApplication/UIApplicationState/UIScene: canonical declarations live in
// QuillUIKit (re-exported above) — declaring twins here made `UIApplication.shared`
// ambiguous once SwiftUI re-exported AppKit (whose QuillUIKit re-export exposes
// the other copy). Shared text-layout types (NSTextAlignment/NSParagraphStyle/
// NSUnderlineStyle/NSStringDrawing*/NSAttributedString.Key additions) live in
// QuillFoundation (NSTextLayoutShared.swift) for the same reason.
// NSTextAttachment/NSTextStorage stay here: their members are UIKit-flavored
// (UIImage) and cannot share a declaration with AppKit's NSImage flavor yet.



// Text alignment. On iOS this lives in UIKit (and in AppKit on macOS, where
// QuillAppKit already mirrors it). SignalServiceKit reaches it via `import
// UIKit`, so it is mirrored here too. Case order matches QuillAppKit's.

// Text layout enums + paragraph style (UIKit on iOS, AppKit on macOS). Mirrored
// here so SignalServiceKit's attributed-string code resolves them via import
// UIKit. Case order matches QuillAppKit's.





// NSTextAttachment: an inline image/data attachment in an attributed string.
// swift-corelibs Foundation has no NSTextAttachment; SSK (String+SSK) builds one
// to embed a templated image. Inert holder of image/bounds; rendering deferred.
open class NSTextAttachment: NSObject {
    public var image: UIImage?
    public var bounds: CGRect
    public var contents: Data?
    public override init() {
        self.image = nil
        self.bounds = .zero
        self.contents = nil
        super.init()
    }
}

public extension UIImage {
    enum RenderingMode: Int, Sendable {
        case automatic = 0
        case alwaysOriginal = 1
        case alwaysTemplate = 2
    }
    /// Inert on Linux: returns self (no template tinting). SSK uses
    /// .alwaysTemplate for theme-tinted glyphs; the original image suffices.
    func withRenderingMode(_ renderingMode: RenderingMode) -> UIImage {
        return self
    }

    convenience init?(data: Data, scale: CGFloat) {
        _ = scale
        self.init(data: data)
    }

    func withTintColor(_ color: UIColor, renderingMode: RenderingMode) -> UIImage {
        _ = (color, renderingMode)
        return self
    }

    static var genericAttachment: UIImage { UIImage() }
    static var viewOnceDash: UIImage { UIImage() }
    static var timer: UIImage { UIImage() }
    static var arrowRightCircle: UIImage { UIImage() }
    static var copy: UIImage { UIImage() }
    static var copyLight: UIImage { UIImage() }
    static var saveLight: UIImage { UIImage() }
    static var trashLight: UIImage { UIImage() }
}

public extension Optional where Wrapped == UIImage {
    static var genericAttachment: UIImage? { UIImage.genericAttachment }
    static var viewOnceDash: UIImage? { UIImage.viewOnceDash }
    static var timer: UIImage? { UIImage.timer }
    static var arrowRightCircle: UIImage? { UIImage.arrowRightCircle }
    static var copy: UIImage? { UIImage.copy }
    static var copyLight: UIImage? { UIImage.copyLight }
    static var saveLight: UIImage? { UIImage.saveLight }
    static var trashLight: UIImage? { UIImage.trashLight }
}

// Standard attributed-string attribute keys (UIKit/AppKit additions; not in
// swift-corelibs Foundation). Raw values match Apple's.

// Mirror of UIKit's NSUnderlineStyle. Modeled as an OptionSet (matching the
// platform, where line styles and patterns combine) with the standard raw
// values; SSK uses `.single.rawValue` for strikethrough/underline attributes.

public extension NSAttributedString {
    /// NSAttributedString(attachment:) -- wraps a text attachment in an attributed
    /// string with the attachment attribute under the U+FFFC object-replacement
    /// character (matches Apple). Image rendering is inert; the attribute is set.
    convenience init(attachment: NSTextAttachment) {
        self.init(string: "\u{FFFC}", attributes: [.attachment: attachment])
    }
}

public extension UIScene {
    enum ActivationState: Sendable {
        case unattached
        case foregroundActive
        case foregroundInactive
        case background
    }

    struct ConnectionOptions: Sendable {
        public init() {}
    }

    @MainActor var activationState: ActivationState { .foregroundActive }
}

public class UISceneSession: NSObject {
    public struct Role: Hashable, Sendable {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let windowApplication = Role("windowApplication")
    }

    public var role: Role

    public init(role: Role = .windowApplication) {
        self.role = role
        super.init()
    }
}

public class UISceneConfiguration: NSObject {
    public var name: String?
    public var sessionRole: UISceneSession.Role
    public var delegateClass: AnyClass?

    public init(name: String?, sessionRole: UISceneSession.Role) {
        self.name = name
        self.sessionRole = sessionRole
        super.init()
    }
}

public extension UIWindow {
    var isKeyWindow: Bool { false }
    @MainActor var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { scene in scene.windows.contains { $0 === self } }
    }

    var rootViewController: UIViewController? {
        get { nil }
        set { _ = newValue }
    }

    func makeKeyAndVisible() {}
    func resignKey() {}
}

@MainActor public protocol UIFontPickerViewControllerDelegate: AnyObject {
    func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController)
    func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController)
}

@MainActor open class UIFontPickerViewController: UIViewController {
    public weak var delegate: UIFontPickerViewControllerDelegate?
    public var selectedFontDescriptor: UIFontDescriptor?
    public init() {
        self.selectedFontDescriptor = UIFontDescriptor()
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        self.selectedFontDescriptor = UIFontDescriptor()
        super.init(coder: coder)
    }
}

public extension UIColor {
    static let placeholderText = RSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
}

extension UIImage: NSItemProviderReading {
    public static var readableTypeIdentifiersForItemProvider: [String] {
        [UTType.image.identifier, UTType.png.identifier, UTType.jpeg.identifier]
    }

    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        if let image = UIImage(data: data) as? Self {
            return image
        }
        return UIImage() as! Self
    }
}

public enum UIKeyboardType: Hashable, Sendable {
    case `default`
    case asciiCapable
    case numbersAndPunctuation
    case URL
    case numberPad
    case phonePad
    case namePhonePad
    case emailAddress
    case decimalPad
    case twitter
    case webSearch
}

public enum UITextAutocapitalizationType: Sendable {
    case none
    case words
    case sentences
    case allCharacters
}

public enum UITextAutocorrectionType: Sendable {
    case `default`
    case no
    case yes
}

public enum UIReturnKeyType: Sendable {
    case `default`
    case go
    case google
    case join
    case next
    case route
    case search
    case send
    case yahoo
    case done
    case emergencyCall
}

public enum UITextInlinePredictionType: Sendable {
    case `default`
    case no
    case yes
}

public struct UIDataDetectorTypes: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let phoneNumber = UIDataDetectorTypes(rawValue: 1 << 0)
    public static let link = UIDataDetectorTypes(rawValue: 1 << 1)
    public static let address = UIDataDetectorTypes(rawValue: 1 << 2)
    public static let calendarEvent = UIDataDetectorTypes(rawValue: 1 << 3)
    public static let all: UIDataDetectorTypes = [.phoneNumber, .link, .address, .calendarEvent]
}

public final class NSTextContainer {
    public var lineFragmentPadding: CGFloat = 0
    public weak var layoutManager: NSLayoutManager?
    public var size: CGSize
    public var maximumNumberOfLines: Int = 0
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public init(size: CGSize = .zero) {
        self.size = size
    }

    public func replaceLayoutManager(_ newLayoutManager: NSLayoutManager) {
        layoutManager = newLayoutManager
        if !newLayoutManager.textContainers.contains(where: { $0 === self }) {
            newLayoutManager.addTextContainer(self)
        }
    }
}

public class UITextRange: NSObject {
    public let start: UITextPosition
    public let end: UITextPosition

    public override init() {
        self.start = UITextPosition()
        self.end = UITextPosition()
        super.init()
    }

    public init(start: UITextPosition, end: UITextPosition) {
        self.start = start
        self.end = end
        super.init()
    }

    public var isEmpty: Bool { start.quillUTF16Offset == end.quillUTF16Offset }
}

@MainActor public protocol UITextViewDelegate: UIScrollViewDelegate {
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool
    func textViewDidBeginEditing(_ textView: UITextView)
    func textViewShouldEndEditing(_ textView: UITextView) -> Bool
    func textViewDidEndEditing(_ textView: UITextView)
    func textViewDidChange(_ textView: UITextView)
    func textViewDidChangeSelection(_ textView: UITextView)
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool
    func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool
}

public extension UITextViewDelegate {
    @MainActor func textViewShouldBeginEditing(_ textView: UITextView) -> Bool { true }
    @MainActor func textViewDidBeginEditing(_ textView: UITextView) {}
    @MainActor func textViewShouldEndEditing(_ textView: UITextView) -> Bool { true }
    @MainActor func textViewDidEndEditing(_ textView: UITextView) {}
    @MainActor func textViewDidChange(_ textView: UITextView) {}
    @MainActor func textViewDidChangeSelection(_ textView: UITextView) {}
    @MainActor func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool { true }
    @MainActor func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool { true }
    @MainActor func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool { true }
}

@MainActor public protocol UITextPasteConfigurationSupporting: AnyObject {}

public protocol UITextPasteDelegate: AnyObject {
    func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: UITextPasteConfigurationSupporting,
        transform item: UITextPasteItem
    )
}

public final class UITextPasteItem {
    public let itemProvider: NSItemProvider
    public init(itemProvider: NSItemProvider) {
        self.itemProvider = itemProvider
    }
    public func setNoResult() {}
    public func setDefaultResult() {}
}

@MainActor open class UITextView: UIScrollView, UITextPasteConfigurationSupporting {
    private let quillDefaultLayoutManager = NSLayoutManager()
    private let quillTextStorage = NSTextStorage(string: "")
    private var quillInputAccessoryView: UIView?
    private var quillIsFirstResponder = false

    public weak var pasteDelegate: UITextPasteDelegate?
    public weak var inputDelegate: UITextInputDelegate?

    open var text: String! {
        get { attributedText?.string ?? "" }
        set { attributedText = NSAttributedString(string: newValue ?? "") }
    }

    open var attributedText: NSAttributedString! {
        get { NSAttributedString(attributedString: textStorage) }
        set {
            let oldText = textStorage.string
            textStorage.setAttributedString(newValue ?? NSAttributedString(string: ""))
            quillNotifyTextViewMutation(oldText != textStorage.string)
        }
    }
    open var selectedRange: NSRange = NSRange(location: 0, length: 0)
    open var selectedTextRange: UITextRange?
    open var markedTextRange: UITextRange?
    open var textContainer: NSTextContainer
    open var layoutManager: NSLayoutManager {
        textContainer.layoutManager ?? quillDefaultLayoutManager
    }
    open var textStorage: NSTextStorage {
        textContainer.layoutManager?.textStorage ?? quillTextStorage
    }
    open var textContainerInset: UIEdgeInsets = .zero {
        didSet { quillNotifyTextViewMutation(oldValue != textContainerInset) }
    }
    open var font: UIFont? {
        didSet { quillNotifyTextViewMutation(true) }
    }
    open var textColor: UIColor? {
        didSet { quillNotifyTextViewMutation(true) }
    }
    open var textAlignment: NSTextAlignment = .natural {
        didSet { quillNotifyTextViewMutation(oldValue != textAlignment) }
    }
    open var linkTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var typingAttributes: [NSAttributedString.Key: Any] = [:]
    open var adjustsFontForContentSizeCategory = false
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var spellCheckingType: UITextSpellCheckingType = .default
    open var keyboardAppearance: UIKeyboardAppearance = .default
    open var isEditable = true {
        didSet { quillNotifyTextViewMutation(oldValue != isEditable) }
    }
    open var isSelectable = true {
        didSet { quillNotifyTextViewMutation(oldValue != isSelectable) }
    }
    open var isSecureTextEntry = false
    open var dataDetectorTypes: UIDataDetectorTypes = []
    open var supportsAdaptiveImageGlyph = true
    open var allowsEditingTextAttributes = false
    open var returnKeyType: UIReturnKeyType = .default
    open var enablesReturnKeyAutomatically = false
    open var inlinePredictionType: UITextInlinePredictionType = .default
    open var keyboardType: UIKeyboardType = .default
    open var textContentType: UITextContentType!
    open var writingToolsBehavior: UIWritingToolsBehavior = .default
    open override var inputAccessoryView: UIView? {
        get { quillInputAccessoryView }
        set { quillInputAccessoryView = newValue }
    }
    open override var canBecomeFirstResponder: Bool { isEditable || isSelectable }
    open override var isFirstResponder: Bool { quillIsFirstResponder }
    private var quillTextViewDelegate: (any UITextViewDelegate)? {
        delegate as? any UITextViewDelegate
    }

    public convenience init() {
        self.init(frame: .zero, textContainer: nil)
    }

    public init(frame: CGRect, textContainer: NSTextContainer?) {
        let container = textContainer ?? NSTextContainer()
        self.textContainer = container
        super.init(frame: frame)
        if container.layoutManager == nil {
            quillTextStorage.addLayoutManager(quillDefaultLayoutManager)
            quillDefaultLayoutManager.addTextContainer(container)
        } else if container.layoutManager?.textStorage == nil {
            quillTextStorage.addLayoutManager(container.layoutManager!)
        }
    }

    public required init?(coder: NSCoder) {
        let container = NSTextContainer()
        self.textContainer = container
        super.init(coder: coder)
        quillTextStorage.addLayoutManager(quillDefaultLayoutManager)
        quillDefaultLayoutManager.addTextContainer(container)
    }

    private func quillNotifyTextViewMutation(_ changed: Bool) {
        guard changed else { return }
        invalidateIntrinsicContentSize()
        quillNotifyViewMutation()
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = max(size.width, 1)
        let lineHeight = font?.pointSize ?? 17
        let lines = max(1, ceil(Double((attributedText?.string ?? text ?? "").count) * 8.5 / width))
        return CGSize(width: width, height: CGFloat(lines) * lineHeight * 1.35)
    }

    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        _ = gestureRecognizer
        return true
    }

    open func caretRect(for position: UITextPosition) -> CGRect {
        _ = position
        let lineHeight = font?.pointSize ?? 17
        return CGRect(x: 0, y: 0, width: 1, height: lineHeight * 1.35)
    }

    open func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        _ = range
        return [UITextSelectionRect(rect: caretRect(for: range.start))]
    }

    open func scrollRangeToVisible(_ range: NSRange) {
        _ = range
    }

    open func replace(_ textRange: UITextRange, withText replacementText: String) {
        let start = min(textRange.start.quillUTF16Offset, textRange.end.quillUTF16Offset)
        let end = max(textRange.start.quillUTF16Offset, textRange.end.quillUTF16Offset)
        _ = quillReplaceCharacters(in: NSRange(location: start, length: end - start), with: replacementText)
    }

    open func unmarkText() {
        markedTextRange = nil
    }

    open func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        _ = textRange
        return UIMenu(children: suggestedActions)
    }

    public func select(_ sender: Any?) {
        _ = sender
    }

    @discardableResult
    open override func becomeFirstResponder() -> Bool {
        guard canBecomeFirstResponder else { return false }
        if quillIsFirstResponder { return true }
        if let delegate = quillTextViewDelegate, !delegate.textViewShouldBeginEditing(self) { return false }
        quillIsFirstResponder = true
        quillTextViewDelegate?.textViewDidBeginEditing(self)
        return true
    }

    @discardableResult
    open override func resignFirstResponder() -> Bool {
        guard quillIsFirstResponder else { return true }
        if let delegate = quillTextViewDelegate, !delegate.textViewShouldEndEditing(self) { return false }
        quillIsFirstResponder = false
        quillTextViewDelegate?.textViewDidEndEditing(self)
        return true
    }

    @discardableResult
    open func quillReplaceCharacters(in range: NSRange, with replacementText: String) -> Bool {
        let currentText = text ?? ""
        let normalizedRange = quillNormalizedRange(range, utf16Length: currentText.utf16.count)
        guard quillTextViewDelegate?.textView(self, shouldChangeTextIn: normalizedRange, replacementText: replacementText) ?? true else {
            return false
        }

        inputDelegate?.textWillChange(self)
        inputDelegate?.selectionWillChange(self)

        textStorage.replaceCharacters(in: normalizedRange, with: replacementText)
        let nextText = textStorage.string
        quillNotifyTextViewMutation(currentText != nextText)

        let caret = min(
            normalizedRange.location + replacementText.utf16.count,
            nextText.utf16.count
        )
        selectedRange = NSRange(location: caret, length: 0)
        let caretPosition = position(from: beginningOfDocument, offset: caret) ?? endOfDocument
        selectedTextRange = UITextRange(start: caretPosition, end: caretPosition)

        inputDelegate?.textDidChange(self)
        quillTextViewDelegate?.textViewDidChange(self)
        inputDelegate?.selectionDidChange(self)
        quillTextViewDelegate?.textViewDidChangeSelection(self)
        return true
    }

    open func insertText(_ text: String) {
        _ = quillReplaceCharacters(in: selectedRange, with: text)
    }

    open func deleteBackward() {
        let currentText = text ?? ""
        guard !currentText.isEmpty else { return }
        let range: NSRange
        if selectedRange.length > 0 {
            range = selectedRange
        } else {
            let caretOffset = max(0, min(selectedRange.location, currentText.utf16.count))
            guard caretOffset > 0 else { return }
            let caretIndex = quillStringIndex(in: currentText, utf16Offset: caretOffset)
            guard caretIndex > currentText.startIndex else { return }
            let previousIndex = currentText.index(before: caretIndex)
            let previousOffset = previousIndex.utf16Offset(in: currentText)
            range = NSRange(location: previousOffset, length: caretOffset - previousOffset)
        }
        _ = quillReplaceCharacters(in: range, with: "")
    }

    private func quillNormalizedRange(_ range: NSRange, utf16Length: Int) -> NSRange {
        guard range.location != NSNotFound else {
            return NSRange(location: utf16Length, length: 0)
        }
        let location = max(0, min(range.location, utf16Length))
        let requestedUpper = range.length > Int.max - range.location
            ? Int.max
            : range.location + max(0, range.length)
        let upper = max(location, min(requestedUpper, utf16Length))
        return NSRange(location: location, length: upper - location)
    }

    private func quillStringIndex(in string: String, utf16Offset rawOffset: Int) -> String.Index {
        guard !string.isEmpty else { return string.startIndex }
        var offset = max(0, min(rawOffset, string.utf16.count))
        while offset > 0 {
            let utf16Index = string.utf16.index(string.utf16.startIndex, offsetBy: offset)
            if let index = utf16Index.samePosition(in: string) {
                return index
            }
            offset -= 1
        }
        return string.startIndex
    }
}

@MainActor open class UITextSelectionRect: NSObject {
    open var rect: CGRect
    public init(rect: CGRect = .zero) {
        self.rect = rect
        super.init()
    }
}

@MainActor public protocol UIImagePickerControllerDelegate: AnyObject {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    )
}

public extension UIImagePickerControllerDelegate {
    @MainActor func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {}
}

@MainActor open class UIImagePickerController: UIViewController {
    public struct InfoKey: Hashable, RawRepresentable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let originalImage = InfoKey(rawValue: "UIImagePickerControllerOriginalImage")
        public static let editedImage = InfoKey(rawValue: "UIImagePickerControllerEditedImage")
        public static let mediaType = InfoKey(rawValue: "UIImagePickerControllerMediaType")
        public static let mediaURL = InfoKey(rawValue: "UIImagePickerControllerMediaURL")
        public static let referenceURL = InfoKey(rawValue: "UIImagePickerControllerReferenceURL")
        public static let cropRect = InfoKey(rawValue: "UIImagePickerControllerCropRect")
    }

    public enum SourceType: Sendable {
        case camera
        case photoLibrary
        case savedPhotosAlbum
    }

    public var sourceType: SourceType = .photoLibrary
    public var allowsEditing: Bool = false
    public var mediaTypes: [String] = []
    public weak var delegate: (any UINavigationControllerDelegate & UIImagePickerControllerDelegate)?

    public static func isSourceTypeAvailable(_ sourceType: SourceType) -> Bool {
        _ = sourceType
        return false
    }

    public static func availableMediaTypes(for sourceType: SourceType) -> [String]? {
        _ = sourceType
        return []
    }
}

// MARK: - Haptic feedback (no-op on non-iOS)

// Not @MainActor: these are inert no-op shims (no real haptics on Linux), and
// SSK's HapticFeedback constructs them from nonisolated contexts. Dropping the
// isolation only relaxes (never breaks main-actor callers) and keeps macOS green.
public class UIImpactFeedbackGenerator: NSObject {
    public enum FeedbackStyle: Int { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle = .medium) {}
    public func prepare() {
        recordUIKitFallback(operation: "hapticPrepare", api: "UIImpactFeedbackGenerator.prepare")
    }
    public func impactOccurred() {
        recordUIKitFallback(operation: "impactOccurred", api: "UIImpactFeedbackGenerator.impactOccurred")
    }
    public func impactOccurred(intensity: CGFloat) {
        recordUIKitFallback(operation: "impactOccurred", api: "UIImpactFeedbackGenerator.impactOccurred(intensity:)")
    }
}

public class UISelectionFeedbackGenerator: NSObject {
    public override init() {}
    public func prepare() {
        recordUIKitFallback(operation: "hapticPrepare", api: "UISelectionFeedbackGenerator.prepare")
    }
    public func selectionChanged() {
        recordUIKitFallback(operation: "selectionChanged", api: "UISelectionFeedbackGenerator.selectionChanged")
    }
}

public class UINotificationFeedbackGenerator: NSObject {
    public enum FeedbackType: Int { case success, warning, error }
    public override init() {}
    public func prepare() {
        recordUIKitFallback(operation: "hapticPrepare", api: "UINotificationFeedbackGenerator.prepare")
    }
    public func notificationOccurred(_ type: FeedbackType) {
        recordUIKitFallback(operation: "notificationOccurred", api: "UINotificationFeedbackGenerator.notificationOccurred")
    }
}

// MARK: - UIDevice / UIScreen extras commonly used by iOS-only upstream

@MainActor public class UIDevice: NSObject {
    nonisolated public static let current = UIDevice()
    // nonisolated init so the nonisolated `current` default value (UIDevice())
    // can be evaluated off the main actor; UIDevice has no isolated stored state.
    nonisolated public override init() { super.init() }
    nonisolated public var userInterfaceIdiom: UIUserInterfaceIdiom { .mac }
    public var name: String {
        #if canImport(AppKit)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Mac"
        #endif
    }
    /// Inert device-info strings (AppVersion reads these). nonisolated so
    /// off-main-actor callers can read them (Strings are Sendable).
    nonisolated public var systemVersion: String { "1.0" }
    nonisolated public var model: String { "QuillOS" }
    nonisolated public var orientation: UIDeviceOrientation { .portrait }

    #if os(Linux)
    /// Battery monitoring is unavailable on QuillOS; this notification name
    /// exists (inert -- never posted) so SignalServiceKit's
    /// DeviceBatteryLevelManager compiles. `nonisolated` so the file-scope
    /// Notification.Name extension that aliases it can be evaluated off the main
    /// actor. Raw value matches Apple's.
    nonisolated public static let batteryLevelDidChangeNotification = Notification.Name("UIDeviceBatteryLevelDidChangeNotification")

    /// Proximity sensor is unavailable on QuillOS. The notification name exists
    /// (inert -- never posted); proximityState is always false; enabling
    /// monitoring is a no-op. SignalServiceKit's ProximityMonitoringManager uses
    /// these. nonisolated static (Sendable) like the battery name.
    nonisolated public static let proximityStateDidChangeNotification = Notification.Name("UIDeviceProximityStateDidChangeNotification")
    nonisolated public var isBatteryMonitoringEnabled: Bool {
        get { false }
        set { _ = newValue }
    }
    nonisolated public var batteryLevel: Float { -1 }
    nonisolated public var proximityState: Bool { false }
    nonisolated public var isProximityMonitoringEnabled: Bool {
        get { false }
        set { _ = newValue }
    }

    // UIDevice+FeatureSupport.ows_setOrientation's KVC hack
    // (`setValue(_:forKey:"orientation")`) resolves to QuillFoundation's
    // NSObject KVC no-op extension (re-exported by this module); a copy here
    // would be an invalid override of an extension member.
    #endif
}

#if os(Linux)
public extension Notification.Name {
    /// ProcessInfo low-power-mode-changed notification (Foundation on Apple). Its
    /// sole SignalServiceKit consumer (DeviceBatteryLevelManager) imports UIKit,
    /// so the inert Linux shim lives here; never posted on QuillOS. Raw value
    /// matches Apple's. Linux-gated because macOS Foundation already defines it.
    static let NSProcessInfoPowerStateDidChange = Notification.Name("NSProcessInfoPowerStateDidChangeNotification")
}

public extension ProcessInfo {
    var isLowPowerModeEnabled: Bool { false }
}

public extension UIScreen {
    var brightness: CGFloat {
        get { 1 }
        set { _ = newValue }
    }
}

public extension Progress {
    var estimatedTimeRemaining: TimeInterval? { nil }
}
#endif

// MARK: - UIEdgeInsets
//
// UIKit's four-edge geometry type. The concrete storage lives in QuillUIKit so
// UIView/UIScrollView class-body members can be `open` and overrideable; this
// shim re-exports it under Apple's spelling.
public typealias UIEdgeInsets = QuillEdgeInsets

#if os(Linux)
public extension NSEdgeInsets {
    init(_ insets: UIEdgeInsets) {
        self.init(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
    }
}

public extension UIImage {
    func resizableImage(withCapInsets capInsets: UIEdgeInsets, resizingMode: ResizingMode = .tile) -> UIImage {
        resizableImage(withCapInsets: NSEdgeInsets(capInsets), resizingMode: resizingMode)
    }
}
#endif

// MARK: - NSDirectionalEdgeInsets
//
// Leading/trailing (writing-direction-relative) inset geometry. SSK reaches it
// via `import UIKit`; only the base value-holder is needed (SSK adds its own
// hMargin/vMargin/margin convenience inits in an extension).
public struct NSDirectionalEdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat
    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
    public static let zero = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

// MARK: - UISwitch + UIBezierPath

/// `UISwitch: UIControl`. SSK only references it as a callback parameter type
/// (`switchDidChange(_ sender: UISwitch)` reading `.isOn`); never instantiated here.
@MainActor open class UISwitch: UIControl {
    nonisolated(unsafe) public var isOn: Bool = false {
        didSet {
            if oldValue != isOn {
                MainActor.assumeIsolated {
                    quillNotifyViewMutation()
                }
            }
        }
    }
    public func setOn(_ on: Bool, animated: Bool) {
        _ = animated
        isOn = on
    }
}

@MainActor open class UIInputView: UIView {
    public enum Style: Int, Sendable {
        case `default`
        case keyboard
    }

    public let inputViewStyle: Style
    open var allowsSelfSizing = false

    public init(frame: CGRect, inputViewStyle: Style) {
        self.inputViewStyle = inputViewStyle
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        self.inputViewStyle = .default
        super.init(coder: coder)
    }
}

/// UIBezierPath. Inert on Linux (no real geometry recorded): `.cgPath` is an
/// opaque handle that the inert CGContext drawing shim accepts as `Any`. SSK uses
/// `UIBezierPath(ovalIn:)` + `.cgPath` for avatar clipping.
public final class UIBezierPath: NSObject, NSCopying {
    public let cgPath: CGPath
    public var lineWidth: CGFloat = 1
    public var usesEvenOddFillRule = false
    public override init() {
        self.cgPath = CGPath()
        super.init()
    }
    public init(ovalIn rect: CGRect) {
        _ = rect
        self.cgPath = CGPath()
        super.init()
    }
    public init(rect: CGRect) {
        _ = rect
        self.cgPath = CGPath()
        super.init()
    }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        _ = (rect, cornerRadius)
        self.cgPath = CGPath()
        super.init()
    }
    public init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        _ = (rect, corners, cornerRadii)
        self.cgPath = CGPath()
        super.init()
    }
    public init(
        arcCenter center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        clockwise: Bool
    ) {
        _ = (center, radius, startAngle, endAngle, clockwise)
        self.cgPath = CGPath()
        super.init()
    }
    public init(cgPath: CGPath) {
        self.cgPath = cgPath
        super.init()
    }
    public func move(to point: CGPoint) {}
    public func addLine(to point: CGPoint) {}
    public func addArc(withCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    public func addCurve(to endPoint: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {}
    public func close() {}
    public func append(_ bezierPath: UIBezierPath) {}
    public func reversing() -> UIBezierPath { UIBezierPath(cgPath: cgPath) }
    public func apply(_ transform: CGAffineTransform) { _ = transform }
    public func copy(with zone: NSZone? = nil) -> Any { UIBezierPath(cgPath: cgPath) }
    public func addClip() {}
    public func fill() {}
    public func stroke() {}
}

public func UIRectFill(_ rect: CGRect) {
    #if os(Linux)
    guard let context = UIGraphicsGetCurrentContext() ?? QuillGraphicsContextState.currentContext else {
        return
    }
    context.setFillColor(QuillGraphicsContextState.currentFillColor)
    context.fill(rect)
    #else
    _ = rect
    #endif
}

public enum UIDeviceOrientation: Int, Sendable {
    case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown
    public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
    public var isFlat: Bool { self == .faceUp || self == .faceDown }
    public var isValidInterfaceOrientation: Bool { isPortrait || isLandscape }
}

// MARK: - UIGraphicsImageRenderer (Linux bitmap subset)
//
// SignalServiceKit renders avatars/thumbnails into a renderer context. Linux now
// supports the direct bitmap subset backed by QuillFoundation's 8-bit BGRA
// CGContext: solid rect fills, clears, and callers that draw through
// `context.cgContext`. Text and path rasterization still need a richer paint
// backend.
//
// Gated to Linux: macOS has no UIGraphicsImageRenderer and a real CGContext
// (no `init()`), so this block must not compile there -- keeps the package green
// for local `swift build` / `swift test` on macOS.
#if os(Linux)

// MARK: - NSString/String drawing (UIKit text rendering; Linux shim)
//
// AvatarBuilder + String+SSK measure and draw strings. swift-corelibs has no
// glyph layout, so boundingRect returns a rough estimate (from the .font
// attribute when present) and draw(...) is inert -- enough to compile and lay
// out roughly. Real rasterization is deferred to a Cairo/Pango paint layer.



private func quillEstimatedTextRect(_ s: String, proposed: CGSize, attributes: [NSAttributedString.Key: Any]?) -> CGRect {
    let fontSize = (attributes?[.font] as? UIFont)?.pointSize ?? 13
    let charWidth = fontSize * 0.6
    let lineHeight = fontSize * 1.2
    let singleLineWidth = CGFloat(s.count) * charWidth
    let width = min(proposed.width, max(singleLineWidth, charWidth))
    let lines = width > 0 ? CGFloat(ceil(Double(singleLineWidth / width))) : 1
    let height = min(proposed.height, max(lines, 1) * lineHeight)
    return CGRect(x: 0, y: 0, width: width, height: max(height, lineHeight))
}

public extension String {
    func boundingRect(with size: CGSize,
                      options: NSStringDrawingOptions = [],
                      attributes: [NSAttributedString.Key: Any]? = nil,
                      context: NSStringDrawingContext? = nil) -> CGRect {
        _ = (options, context)
        return quillEstimatedTextRect(self, proposed: size, attributes: attributes)
    }
    func draw(at point: CGPoint, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        _ = (point, attributes) // inert: glyph rasterization deferred on Linux
    }
    func draw(in rect: CGRect, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        _ = (rect, attributes)
    }
}

public extension NSAttributedString {
    func boundingRect(with size: CGSize,
                      options: NSStringDrawingOptions = [],
                      context: NSStringDrawingContext? = nil) -> CGRect {
        _ = (options, context)
        let attributes = length > 0 ? self.attributes(at: 0, effectiveRange: nil) : nil
        return quillEstimatedTextRect(string, proposed: size, attributes: attributes)
    }
}

public final class UIGraphicsImageRendererFormat {
    public var scale: CGFloat = 1
    public var opaque: Bool = false
    public var prefersExtendedRange: Bool = false
    public init() {}
    public static var `default`: UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
    public static func preferred() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}

public final class UIGraphicsImageRendererContext {
    public let cgContext: CGContext
    public let format: UIGraphicsImageRendererFormat
    public init(cgContext: CGContext, format: UIGraphicsImageRendererFormat) {
        self.cgContext = cgContext
        self.format = format
    }
    public func fill(_ rect: CGRect) {
        cgContext.fill(rect)
    }
    public func fill(_ rect: CGRect, blendMode: CGBlendMode) {
        cgContext.saveGState()
        cgContext.setBlendMode(blendMode)
        cgContext.fill(rect)
        cgContext.restoreGState()
    }
    public func stroke(_ rect: CGRect) {
        cgContext.stroke(rect)
    }
    public func stroke(_ rect: CGRect, blendMode: CGBlendMode) {
        cgContext.saveGState()
        cgContext.setBlendMode(blendMode)
        cgContext.stroke(rect)
        cgContext.restoreGState()
    }
    public func clip(to rect: CGRect) {
        cgContext.clip(to: rect)
    }
}

public final class UIGraphicsImageRenderer {
    public let size: CGSize
    public let format: UIGraphicsImageRendererFormat

    public init(size: CGSize, format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat()) {
        self.size = size
        self.format = format
    }
    public convenience init(bounds: CGRect, format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat()) {
        self.init(size: bounds.size, format: format)
    }

    private var resolvedScale: CGFloat {
        quillResolvedUIGraphicsScale(format.scale)
    }

    private func runActions(_ actions: (UIGraphicsImageRendererContext) -> Void) -> CGContext? {
        guard let context = quillMakeUIGraphicsBitmapContext(size: size, scale: resolvedScale) else {
            let fallback = CGContext()
            quillPushUIGraphicsContext(fallback, size: size, scale: resolvedScale)
            defer { quillPopUIGraphicsContext() }
            actions(UIGraphicsImageRendererContext(cgContext: fallback, format: format))
            return nil
        }
        quillPushUIGraphicsContext(context, size: size, scale: resolvedScale)
        defer { quillPopUIGraphicsContext() }
        actions(UIGraphicsImageRendererContext(cgContext: context, format: format))
        return context
    }

    public func image(_ actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        guard let context = runActions(actions), let cgImage = context.makeImage() else {
            return UIImage(size: size)
        }
        let image = UIImage(cgImage: cgImage, scale: resolvedScale, orientation: .up)
        image.size = size
        return image
    }
    public func pngData(_ actions: (UIGraphicsImageRendererContext) -> Void) -> Data {
        _ = runActions(actions)
        return Data()
    }
    public func jpegData(withCompressionQuality quality: CGFloat, actions: (UIGraphicsImageRendererContext) -> Void) -> Data {
        _ = quality
        _ = runActions(actions)
        return Data()
    }
}

// MARK: - Imperative UIGraphics* C-API (the pre-UIGraphicsImageRenderer style)
//
// AvatarBuilder still uses the old Begin/GetCurrentContext/GetImage/End flow. A
// minimal current-context stack backs it. Gated to Linux (these don't exist on
// macOS, and CGContext() is Linux-only).
nonisolated(unsafe) private var _uiGraphicsContextStack: [(context: CGContext, size: CGSize, scale: CGFloat)] = []

private func quillPushUIGraphicsContext(_ context: CGContext, size: CGSize, scale: CGFloat) {
    _uiGraphicsContextStack.append((context, size, scale))
    QuillGraphicsContextState.pushContext(context)
}

private func quillPopUIGraphicsContext() {
    if !_uiGraphicsContextStack.isEmpty {
        _uiGraphicsContextStack.removeLast()
    }
    QuillGraphicsContextState.popContext()
}

private func quillResolvedUIGraphicsScale(_ scale: CGFloat) -> CGFloat {
    scale.isFinite && scale > 0 ? scale : 1
}

private func quillUIGraphicsPixelDimension(_ value: CGFloat, scale: CGFloat) -> Int? {
    guard value.isFinite, value > 0 else {
        return nil
    }
    let scaled = (value * scale).rounded(.up)
    guard scaled.isFinite, scaled > 0, scaled <= CGFloat(Int.max) else {
        return nil
    }
    return Int(scaled)
}

private func quillMakeUIGraphicsBitmapContext(size: CGSize, scale: CGFloat) -> CGContext? {
    let resolvedScale = quillResolvedUIGraphicsScale(scale)
    guard let width = quillUIGraphicsPixelDimension(size.width, scale: resolvedScale),
          let height = quillUIGraphicsPixelDimension(size.height, scale: resolvedScale)
    else {
        return nil
    }
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.scaleBy(x: resolvedScale, y: resolvedScale)
    return context
}

public func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {
    _ = opaque
    let resolvedScale = quillResolvedUIGraphicsScale(scale)
    let context = quillMakeUIGraphicsBitmapContext(size: size, scale: resolvedScale) ?? CGContext()
    quillPushUIGraphicsContext(context, size: size, scale: resolvedScale)
}
public func UIGraphicsBeginImageContext(_ size: CGSize) {
    UIGraphicsBeginImageContextWithOptions(size, false, 1)
}
public func UIGraphicsGetCurrentContext() -> CGContext? {
    _uiGraphicsContextStack.last?.context
}
public func UIGraphicsGetImageFromCurrentImageContext() -> UIImage? {
    guard let top = _uiGraphicsContextStack.last else { return nil }
    guard let cgImage = top.context.makeImage() else {
        return UIImage(size: top.size)
    }
    let image = UIImage(cgImage: cgImage, scale: top.scale, orientation: .up)
    image.size = top.size
    return image
}
public func UIGraphicsEndImageContext() {
    quillPopUIGraphicsContext()
}
public func UIGraphicsPushContext(_ context: CGContext) {
    let size = CGSize(width: CGFloat(context.width), height: CGFloat(context.height))
    quillPushUIGraphicsContext(context, size: size, scale: 1)
}
public func UIGraphicsPopContext() {
    quillPopUIGraphicsContext()
}
#endif

// MARK: - NSTextStorage (TextKit)
//
// On iOS NSTextStorage lives in UIKit. SignalServiceKit's
// EditableMessageBodyTextStorage subclasses it and overrides the primitive
// attributed-string methods plus the editing hooks, so it must exist (and be
// open) here. Backed by NSMutableAttributedString; editing notifications are
// inert on Linux.

public struct NSTextStorageEditActions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let editedAttributes = NSTextStorageEditActions(rawValue: 1 << 0)
    public static let editedCharacters = NSTextStorageEditActions(rawValue: 1 << 1)
}

open class NSTextStorage: NSMutableAttributedString {
    /// NSTextStorage.EditActions is the nested spelling used by callers.
    public typealias EditActions = NSTextStorageEditActions

    public weak var delegate: AnyObject?
    public private(set) var layoutManagers: [NSLayoutManager] = []
    public internal(set) var quillUniformFontPointSize: CGFloat?

    public override init(string str: String) {
        self.quillUniformFontPointSize = nil
        super.init(string: str)
    }

    public override init(string str: String, attributes attrs: [NSAttributedString.Key: Any]? = nil) {
        self.quillUniformFontPointSize = (attrs?[.font] as? UIFont)?.pointSize
        super.init(string: str, attributes: attrs)
    }

    public override init(attributedString attrStr: NSAttributedString) {
        self.quillUniformFontPointSize = nil
        super.init(attributedString: attrStr)
    }

    public required init?(coder: NSCoder) {
        self.quillUniformFontPointSize = nil
        super.init(coder: coder)
    }

    public func addLayoutManager(_ layoutManager: NSLayoutManager) {
        if !layoutManagers.contains(where: { $0 === layoutManager }) {
            layoutManagers.append(layoutManager)
        }
        layoutManager.textStorage = self
    }

    public func removeLayoutManager(_ layoutManager: NSLayoutManager) {
        layoutManagers.removeAll { $0 === layoutManager }
        if layoutManager.textStorage === self {
            layoutManager.textStorage = nil
        }
    }

    open func processEditing() {}

    open func edited(_ editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {}

    // beginEditing()/endEditing() are inherited from NSMutableAttributedString.
    // fixAttributes(in:) is not exposed there, so declare it for the subclass.
    open func fixAttributes(in range: NSRange) {}
}

// MARK: - UI* extras Ice Cubes references

#if canImport(AppKit) && !os(Linux)
// On macOS, NSEvent.ModifierFlags is the analogue.
public typealias UIKeyModifierFlags = NSEvent.ModifierFlags
#endif

#endif // !os(iOS)
