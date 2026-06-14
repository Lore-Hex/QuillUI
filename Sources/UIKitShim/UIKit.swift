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
// On iOS, Apple's UIKit re-exports QuartzCore — `import UIKit` alone exposes
// CALayer/CAShapeLayer/CATransaction. Signal-iOS's SignalUI relies on this
// (~4.8k of its conformance-build errors were CA* names with no QuartzCore
// import in sight). Mirror that topology here: on Linux this resolves to the
// in-tree QuartzCore shim (a declared target dependency); on Apple platforms
// it resolves to the real framework, exactly like Apple's UIKit.
@_exported import QuartzCore
import QuillKit

#if !os(iOS)

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
        self.pointSize = size; self.fontName = descriptor.name; self.fontDescriptor = descriptor
        super.init()
    }
    init(pointSize: CGFloat, fontName: String) {
        self.pointSize = pointSize; self.fontName = fontName
        self.fontDescriptor = UIFontDescriptor(name: fontName)
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
        UIFontDescriptor(
            name: design == .rounded ? ".AppleSystemUIFontRounded-Regular" : name,
            symbolicTraits: symbolicTraits
        )
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
        UIFontDescriptor(name: name, symbolicTraits: symbolicTraits.union(traits))
    }
}
public final class UIFontMetrics: @unchecked Sendable {
    public static let `default` = UIFontMetrics()
    public func scaledValue(for value: CGFloat) -> CGFloat { value }
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

// UIWindowScene, UIStatusBarManager, and UIWindowSceneDelegate moved to
// QuillUIKit (alongside UIScene) so the UIWindow class body can declare an
// `open` `init(windowScene:)` that SignalUI's OWSWindow overrides — an
// extension initializer here could not be overridden cross-module.

public extension UIWindow {
    var isKeyWindow: Bool { false }
    // safeAreaInsets: the UIView-wide extension in UIViewMargins.swift covers
    // windows too (same .zero — Linux has no notches); a second extension
    // property here can't shadow it (extension members don't override).
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
}

public extension UIColor {
    static let placeholderText = RSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
}

public class NSItemProvider: NSObject {
    public let suggestedName: String?
    private let fileURL: URL?
    private let object: Any?
    private let dataRepresentation: (data: Data, type: UTType)?

    public init?(contentsOf url: URL) {
        self.fileURL = url
        self.object = nil
        self.dataRepresentation = nil
        self.suggestedName = url.lastPathComponent
        super.init()
    }

    public init(object: Any) {
        self.fileURL = nil
        self.object = object
        self.dataRepresentation = nil
        self.suggestedName = nil
        super.init()
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.object = nil
        self.dataRepresentation = nil
        self.suggestedName = fileURL.lastPathComponent
        super.init()
    }

    public init(data: Data, type: UTType) {
        self.fileURL = nil
        self.object = nil
        self.dataRepresentation = (data, type)
        self.suggestedName = nil
        super.init()
    }

    public override init() {
        self.fileURL = nil
        self.object = nil
        self.dataRepresentation = nil
        self.suggestedName = nil
        super.init()
    }

    public func registeredContentTypes(conformingTo contentType: UTType) -> [UTType] {
        guard let url = fileURL,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: contentType)
        else { return [] }
        return [type]
    }

    public var registeredTypeIdentifiers: [String] {
        if let dataRepresentation {
            return [dataRepresentation.type.identifier]
        }
        guard let url = fileURL,
              let type = UTType(filenameExtension: url.pathExtension)
        else { return [] }
        return [type.identifier]
    }

    public func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        let requestedType = UTType(typeIdentifier)
        return registeredTypeIdentifiers.contains { identifier in
            identifier == typeIdentifier || requestedType.map { UTType(identifier)?.conforms(to: $0) == true } == true
        }
    }

    public func loadItem(
        forTypeIdentifier typeIdentifier: String,
        options: [AnyHashable: Any]? = nil,
        completionHandler: @escaping (Any?, Error?) -> Void
    ) {
        _ = typeIdentifier
        _ = options
        completionHandler(fileURL ?? object, nil)
    }

    public func loadDataRepresentation(
        for contentType: UTType,
        completionHandler: @escaping (Data?, Error?) -> Void
    ) -> Progress? {
        if let dataRepresentation, dataRepresentation.type.conforms(to: contentType) {
            completionHandler(dataRepresentation.data, nil)
            return nil
        }

        if let fileURL,
           let type = UTType(filenameExtension: fileURL.pathExtension),
           type.conforms(to: contentType) {
            do {
                completionHandler(try Data(contentsOf: fileURL), nil)
            } catch {
                completionHandler(nil, error)
            }
            return nil
        }

        completionHandler(nil, NSError(
            domain: "QuillUIKit.NSItemProvider",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No data representation is available for \(contentType.identifier)."]
        ))
        return nil
    }

    public func loadDataRepresentation(
        forTypeIdentifier typeIdentifier: String,
        completionHandler: @escaping (Data?, Error?) -> Void
    ) -> Progress? {
        if let contentType = UTType(typeIdentifier) {
            return loadDataRepresentation(for: contentType, completionHandler: completionHandler)
        }
        completionHandler(nil, NSError(
            domain: "QuillUIKit.NSItemProvider",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unknown type identifier \(typeIdentifier)."]
        ))
        return nil
    }

    public func loadFileRepresentation(
        forTypeIdentifier typeIdentifier: String,
        completionHandler: @escaping (URL?, Error?) -> Void
    ) -> Progress? {
        _ = typeIdentifier
        completionHandler(fileURL, nil)
        return nil
    }

    public func canLoadObject<T: NSItemProviderReading>(ofClass aClass: T.Type) -> Bool {
        _ = aClass
        return object is T
    }

    public func loadObject<T: NSItemProviderReading>(
        ofClass aClass: T.Type,
        completionHandler: @escaping (T?, Error?) -> Void
    ) -> Progress {
        _ = aClass
        completionHandler(object as? T, nil)
        return Progress(totalUnitCount: 1)
    }

    @discardableResult
    public func loadTransferable<T: Transferable>(
        type: T.Type,
        completionHandler: @escaping (Result<T?, Error>) -> Void
    ) -> Progress {
        _ = type
        completionHandler(.success(nil))
        return Progress(totalUnitCount: 1)
    }
}

public protocol NSItemProviderReading {
    static var readableTypeIdentifiersForItemProvider: [String] { get }
    static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self
}

public extension NSItemProviderReading {
    static var readableTypeIdentifiersForItemProvider: [String] { [] }
}

extension NSString: NSItemProviderReading {
    public static var readableTypeIdentifiersForItemProvider: [String] { [UTType.text.identifier, UTType.plainText.identifier] }

    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        let value = String(data: data, encoding: .utf8) ?? ""
        return self.init(string: value)
    }
}

extension NSURL: NSItemProviderReading {
    public static var readableTypeIdentifiersForItemProvider: [String] { [UTType.url.identifier, UTType.fileURL.identifier] }

    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        let value = String(data: data, encoding: .utf8) ?? ""
        let url = typeIdentifier == UTType.fileURL.identifier ? URL(fileURLWithPath: value) : (URL(string: value) ?? URL(fileURLWithPath: value))
        return NSURL(string: url.absoluteString)! as! Self
    }
}

extension UIImage: NSItemProviderReading {
    public static var readableTypeIdentifiersForItemProvider: [String] { [UTType.image.identifier, UTType.png.identifier, UTType.jpeg.identifier] }

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

// NSTextContainer — the TextKit 1 container geometry object. Faithful CONFIG
// STATE: size / line limits / padding are stored and drive NSLayoutManager's
// uniform-advance line model (NSLayoutManagerShim.swift); there is no real
// glyph geometry on Linux. SignalUI configures these from UITextView/UILabel
// (AttachmentTextToolbar, CVTextLabel, UIKit+Text) and reads `size` back in
// enclosing-rect enumeration.
public final class NSTextContainer {
    public var lineFragmentPadding: CGFloat = 0
    public var size: CGSize = .zero
    public var maximumNumberOfLines: Int = 0
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public var widthTracksTextView = false
    public var heightTracksTextView = false
    /// Weak (Apple: unowned(unsafe)) back-reference; set by
    /// NSLayoutManager.addTextContainer(_:).
    public weak var layoutManager: NSLayoutManager?

    public init() {}
    public init(size: CGSize) {
        self.size = size
    }

    /// Migrates the receiver's whole text-system group (containers + storage)
    /// from its current layout manager to `newLayoutManager`, matching Apple's
    /// documented semantics. With no layout caches on Linux this is pure
    /// object-graph rewiring.
    public func replaceLayoutManager(_ newLayoutManager: NSLayoutManager) {
        guard layoutManager !== newLayoutManager else { return }
        if let old = layoutManager {
            let migrating = old.textContainers
            old.textContainers = []
            if let storage = old.textStorage {
                storage.removeLayoutManager(old)
                if !storage.layoutManagers.contains(where: { $0 === newLayoutManager }) {
                    storage.addLayoutManager(newLayoutManager)
                }
            }
            for container in migrating where !newLayoutManager.textContainers.contains(where: { $0 === container }) {
                newLayoutManager.addTextContainer(container)
            }
        }
        if !newLayoutManager.textContainers.contains(where: { $0 === self }) {
            newLayoutManager.addTextContainer(self)
        }
    }
}

// UITextRange — a contiguous span of a text field/view's content. The rest of
// the text-input surface (UITextPosition, UITextInput, UITextField) lives in
// UITextInput.swift; positions are plain UTF-16 offsets (no layout engine on
// Linux), so a range is just a normalized offset pair.
open class UITextRange: NSObject {
    public let start: UITextPosition
    public let end: UITextPosition
    public var isEmpty: Bool { start.quillUTF16Offset == end.quillUTF16Offset }

    public override init() {
        self.start = UITextPosition()
        self.end = UITextPosition()
        super.init()
    }

    // Module-internal: ranges are minted by the textRange(from:to:) factories,
    // matching Apple's opaque construction.
    init(start: UITextPosition, end: UITextPosition) {
        self.start = start
        self.end = end
        super.init()
    }
}

/// One rect of a text selection (Apple returns an array of these from
/// `selectionRects(for:)`). The abstract base carries the geometry +
/// edge/writing-direction flags upstream reads off drag-preview rects. No glyph
/// layout on Linux means the shim never produces instances (`selectionRects`
/// returns `[]`), but the type must exist for the signature to type-check.
open class UITextSelectionRect: NSObject {
    open var rect: CGRect { .zero }
    open var writingDirection: NSWritingDirection { .natural }
    open var containsStart: Bool { false }
    open var containsEnd: Bool { false }
    open var isVertical: Bool { false }
}

// On Apple `UITextViewDelegate` refines `UIScrollViewDelegate` (a text view IS
// a scroll view). The shim keeps UITextView a UIView, so the protocol stands
// alone; every method has a default no-op so conformers implement only what
// they need (Objective-C optional-method parity).
@MainActor public protocol UITextViewDelegate: AnyObject {
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool
    func textViewShouldEndEditing(_ textView: UITextView) -> Bool
    func textViewDidBeginEditing(_ textView: UITextView)
    func textViewDidEndEditing(_ textView: UITextView)
    func textViewDidChange(_ textView: UITextView)
    func textViewDidChangeSelection(_ textView: UITextView)
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool
}

public extension UITextViewDelegate {
    @MainActor func textViewShouldBeginEditing(_ textView: UITextView) -> Bool { true }
    @MainActor func textViewShouldEndEditing(_ textView: UITextView) -> Bool { true }
    @MainActor func textViewDidBeginEditing(_ textView: UITextView) {}
    @MainActor func textViewDidEndEditing(_ textView: UITextView) {}
    @MainActor func textViewDidChange(_ textView: UITextView) {}
    @MainActor func textViewDidChangeSelection(_ textView: UITextView) {}
    @MainActor func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool { true }
    @MainActor func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool { true }
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

@MainActor public protocol UIDragSession: AnyObject {
    func location(in view: UIView?) -> CGPoint
}

public extension UIDragSession {
    @MainActor func location(in view: UIView?) -> CGPoint {
        _ = view
        return .zero
    }
}

@MainActor public final class UIDragItem: NSObject {
    public let itemProvider: NSItemProvider
    public var localObject: Any?
    public var previewProvider: (() -> UIDragPreview?)?

    public init(itemProvider: NSItemProvider) {
        self.itemProvider = itemProvider
        super.init()
    }
}

@MainActor public protocol UIDragInteractionDelegate: AnyObject {
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem]
}

public extension UIDragInteractionDelegate {
    @MainActor func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        _ = (interaction, session)
        return []
    }
}

@MainActor public final class UIDragInteraction: NSObject, UIInteraction {
    public weak var view: UIView?
    public weak var delegate: UIDragInteractionDelegate?
    public var isEnabled = true

    public init(delegate: UIDragInteractionDelegate?) {
        self.delegate = delegate
        super.init()
    }
}

@MainActor public final class UIDragPreviewParameters: NSObject {
    public var visiblePath: UIBezierPath?
    public var backgroundColor: UIColor?

    public override init() {
        super.init()
    }

    public init(textLineRects: [CGRect]) {
        _ = textLineRects
        super.init()
    }

    public init(textLineRects: [NSValue]) {
        _ = textLineRects
        super.init()
    }
}

@MainActor public final class UIDragPreview: NSObject {
    public let view: UIView
    public let parameters: UIDragPreviewParameters?

    public init(view: UIView, parameters: UIDragPreviewParameters? = nil) {
        self.view = view
        self.parameters = parameters
        super.init()
    }
}

// On Apple, `UITextView: UIScrollView` (it scrolls its own text). The shim
// keeps it a plain `UIView` on purpose: UIScrollView's stored
// `delegate: UIScrollViewDelegate?` (QuillUIKit.swift) would collide with
// UITextView's own `delegate: UITextViewDelegate?` — Swift can't redeclare a
// settled stored property with a covariant type, and UICollectionView only
// dodges that because UICollectionViewDelegate REFINES UIScrollViewDelegate
// (UITextViewDelegate does too on Apple, but the stored-property collision
// remains). So the scroll surface SignalUI's UITextView subclasses use
// (contentOffset / contentSize / contentInset / scrollIndicatorInsets /
// setContentOffset / scrollRangeToVisible) is declared directly on this class
// body below — `open`, because BodyRangesTextView & co. override several of them.
@MainActor open class UITextView: UIView, UITextPasteConfigurationSupporting {
    open weak var delegate: UITextViewDelegate?
    open weak var pasteDelegate: UITextPasteDelegate?
    open var attributedText: NSAttributedString = NSAttributedString(string: "")
    open var selectedRange: NSRange = NSRange(location: 0, length: 0)
    open var markedTextRange: UITextRange?
    open var textContainer = NSTextContainer()
    open var textContainerInset: UIEdgeInsets = .zero

    // MARK: TextKit 1 stack (NSLayoutManagerShim.swift)
    //
    // Apple's designated initializer takes the text container; SignalUI's
    // UITextView subclasses (OWSTextView, MediaTextView, LinkingTextView,
    // BodyRangesTextView) all override/call it, and BodyRangesTextView
    // overrides `layoutManager` — so both must be declared in the class body.
    // MODEL HONESTY: the shim's text MODEL remains `attributedText` (above);
    // the layout manager/storage exposed here are real wired objects so the
    // TextKit object graph and its geometry queries work, but a storage
    // created lazily by `textStorage` is a SNAPSHOT of `attributedText` at
    // first access, not a live mirror of later `text`/`attributedText` writes.
    // (BodyRangesTextView supplies its own storage and overrides the text
    // accessors to read through it, so the real Signal composer is unaffected.)

    public init(frame: CGRect, textContainer: NSTextContainer?) {
        if let textContainer {
            self.textContainer = textContainer
        }
        super.init(frame: frame)
    }

    public convenience override init(frame: CGRect) {
        self.init(frame: frame, textContainer: nil)
    }

    public convenience init() {
        self.init(frame: .zero, textContainer: nil)
    }

    /// Strong anchors for the lazily-created default stack (the container's
    /// and manager's back-references are weak, matching Apple's ownership).
    private var quillDefaultLayoutManager: NSLayoutManager?
    private var quillDefaultTextStorage: NSTextStorage?

    open var layoutManager: NSLayoutManager {
        if let existing = textContainer.layoutManager {
            return existing
        }
        let created = NSLayoutManager()
        created.addTextContainer(textContainer)
        quillDefaultLayoutManager = created
        return created
    }

    open var textStorage: NSTextStorage {
        let manager = layoutManager
        if let existing = manager.textStorage {
            return existing
        }
        let created = NSTextStorage(attributedString: attributedText)
        created.addLayoutManager(manager)
        quillDefaultTextStorage = created
        return created
    }
    open var font: UIFont?
    open var adjustsFontForContentSizeCategory = false
    open var autocapitalizationType: UITextAutocapitalizationType = .sentences
    open var autocorrectionType: UITextAutocorrectionType = .default
    open var isEditable = true
    open var isSelectable = true
    open var isScrollEnabled = true
    open var dataDetectorTypes: UIDataDetectorTypes = []
    open var allowsEditingTextAttributes = false
    open var returnKeyType: UIReturnKeyType = .default
    open var inlinePredictionType: UITextInlinePredictionType = .default
    open var keyboardType: UIKeyboardType = .default
    open var textColor: UIColor?
    open var typingAttributes: [NSAttributedString.Key: Any] = [:]
    open var textAlignment: NSTextAlignment = .natural

    // MARK: Text-input surface (protocols + trait types in UITextInput.swift)
    //
    // `text` is the plain-string view of `attributedText` (Apple couples them;
    // attributes are dropped on a plain-text write, matching a styled-storage
    // rewrite). `selectedTextRange` is the UITextRange view over the stored
    // `selectedRange`, declared in the class body — not an extension — because
    // SignalUI subclasses override it (LinkingTextView; BodyRangesTextView
    // overrides `text`). The input traits are faithful STATE: no keyboard,
    // autocorrect, or Writing Tools engine consumes them on Linux yet.

    open var text: String! {
        get { attributedText.string }
        set { attributedText = NSAttributedString(string: newValue ?? "") }
    }

    open var selectedTextRange: UITextRange? {
        get {
            UITextRange(
                start: UITextPosition(quillUTF16Offset: selectedRange.location),
                end: UITextPosition(quillUTF16Offset: selectedRange.location + selectedRange.length)
            )
        }
        set {
            guard let newValue else {
                // Apple's nil means "no selection"; the NSRange model's closest
                // honest equivalent is a collapsed caret at the start.
                selectedRange = NSRange(location: 0, length: 0)
                return
            }
            selectedRange = NSRange(
                location: newValue.start.quillUTF16Offset,
                length: newValue.end.quillUTF16Offset - newValue.start.quillUTF16Offset
            )
        }
    }

    open var keyboardAppearance: UIKeyboardAppearance = .default
    open var spellCheckingType: UITextSpellCheckingType = .default
    open var isSecureTextEntry = false
    open var linkTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var textContentType: UITextContentType!
    open var writingToolsBehavior: UIWritingToolsBehavior = .default
    open weak var inputDelegate: (any UITextInputDelegate)?

    // `override`: UIView declares the open base (QuillUIKit.swift).
    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = max(size.width, 1)
        let lineHeight = font?.pointSize ?? 17
        let lines = max(1, ceil(Double(attributedText.string.count) * 8.5 / width))
        return CGSize(width: width, height: CGFloat(lines) * lineHeight * 1.35)
    }

    public func select(_ sender: Any?) {
        _ = sender
    }

    open func caretRect(for position: UITextPosition) -> CGRect {
        _ = position
        return CGRect(origin: .zero, size: CGSize(width: 1, height: font?.lineHeight ?? 17))
    }

    /// The bounding rect of the text in `range`. MODEL HONESTY: with no glyph
    /// layout on Linux the geometry isn't real; a degenerate caret-height rect
    /// at the origin is the honest stand-in (same as `caretRect`).
    open func firstRect(for range: UITextRange) -> CGRect {
        _ = range
        return CGRect(origin: .zero, size: CGSize(width: 0, height: font?.lineHeight ?? 17))
    }

    /// The selection-handle rects for `range`. No glyph layout means no real
    /// per-line rects; SignalUI reads this for drag-preview geometry, which
    /// degrades to "no rects" honestly. (Apple returns `[UITextSelectionRect]`.)
    open func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        _ = range
        return []
    }

    /// Replaces the text in `range` with `text`, operating on the UTF-16 model
    /// behind `attributedText` (the positions are plain offsets — see
    /// UITextPosition; NSRange is also UTF-16, so the edit is exact). Out-of-range
    /// positions clamp to the document, matching a best-effort edit; the
    /// selection collapses to the end of the inserted text, as Apple leaves the
    /// caret. Replacing with the typing attributes keeps a styled view from
    /// dropping its run attributes wholesale on a partial edit.
    open func replace(_ range: UITextRange, withText text: String) {
        let length = attributedText.length
        let lower = min(max(0, range.start.quillUTF16Offset), length)
        let upper = min(max(lower, range.end.quillUTF16Offset), length)
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        mutable.replaceCharacters(
            in: NSRange(location: lower, length: upper - lower),
            with: NSAttributedString(string: text, attributes: typingAttributes)
        )
        attributedText = mutable
        let caret = lower + text.utf16.count
        selectedRange = NSRange(location: caret, length: 0)
    }

    /// Clears any marked (in-composition) text. No input method runs on Linux,
    /// so there is never marked text to clear — the honest no-op is to drop the
    /// marked range, matching Apple committing the composition.
    open func unmarkText() {
        markedTextRange = nil
    }

    // MARK: Input traits not shared with UITextField
    //
    // Whether the Return key auto-disables until there is text. Faithful state;
    // no keyboard consumes it on Linux. (UITextField inherits this from
    // UITextInputTraits on Apple; SignalUI only sets it on text views here.)
    open var enablesReturnKeyAutomatically = false

    // MARK: Scroll surface
    //
    // On Apple UITextView IS a UIScrollView; the shim keeps it a UIView (the
    // delegate-type collision documented on the class declaration), so the slice
    // of the scroll API SignalUI's UITextView subclasses use is declared here
    // directly. `open`, because BodyRangesTextView overrides them. MODEL HONESTY:
    // there is no compositor, so these are faithful stored geometry — no actual
    // scrolling happens, and `scrollRangeToVisible` records intent only.

    open var contentSize: CGSize = .zero
    open var contentOffset: CGPoint = .zero
    open var contentInset: UIEdgeInsets = .zero
    open var scrollIndicatorInsets: UIEdgeInsets = .zero
    open var verticalScrollIndicatorInsets: UIEdgeInsets = .zero
    open var horizontalScrollIndicatorInsets: UIEdgeInsets = .zero
    /// Read-only on Apple; equals `contentInset` here (no safe areas / keyboard
    /// avoidance on Linux to adjust by). (`isScrollEnabled` is already declared
    /// above with the other UITextView config flags.)
    open var adjustedContentInset: UIEdgeInsets { contentInset }
    open var alwaysBounceVertical = false
    open var alwaysBounceHorizontal = false
    open var showsVerticalScrollIndicator = true
    open var showsHorizontalScrollIndicator = true
    open var keyboardDismissMode: UIScrollView.KeyboardDismissMode = .none

    open func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        _ = animated
        self.contentOffset = contentOffset
    }

    /// Scrolls so the characters in `range` are visible. MODEL HONESTY: nothing
    /// scrolls on Linux yet; this records the request without moving content.
    open func scrollRangeToVisible(_ range: NSRange) {
        _ = range
    }

    open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        _ = gestureRecognizer
        return true
    }
}

// UINavigationControllerDelegate moved to QuillUIKit
// (UIViewControllerSurface.swift): the UINavigationController class body
// needs the type for Apple's `open weak var delegate`, which upstream
// (OWSNavigationController) overrides. Still visible here via the
// `@_exported import QuillUIKit` above.

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

@MainActor public final class UIImagePickerController: UIViewController {
    public struct InfoKey: Hashable, RawRepresentable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let originalImage = InfoKey(rawValue: "UIImagePickerControllerOriginalImage")
    }

    public enum SourceType: Sendable {
        case camera
        case photoLibrary
        case savedPhotosAlbum
    }

    public var sourceType: SourceType = .photoLibrary
    public weak var delegate: (any UINavigationControllerDelegate & UIImagePickerControllerDelegate)?

    public static func isSourceTypeAvailable(_ sourceType: SourceType) -> Bool {
        _ = sourceType
        return false
    }
}

public enum UIInputViewStyle: Int, Sendable {
    case `default`
    case keyboard
}

@MainActor open class UIInputView: UIView {
    public var inputViewStyle: UIInputViewStyle
    public var allowsSelfSizing: Bool = false

    public init(frame: CGRect, inputViewStyle: UIInputViewStyle) {
        self.inputViewStyle = inputViewStyle
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        self.inputViewStyle = .default
        super.init(frame: .zero)
    }
}

@MainActor private var quillSearchBarTextFields: [ObjectIdentifier: UITextField] = [:]
@MainActor private var quillSearchBarWritingToolsBehavior: [ObjectIdentifier: UIWritingToolsBehavior] = [:]

public extension UISearchBar {
    var searchTextField: UITextField {
        let key = ObjectIdentifier(self)
        if let existing = quillSearchBarTextFields[key] {
            return existing
        }
        let field = UITextField(frame: .zero)
        quillSearchBarTextFields[key] = field
        addSubview(field)
        return field
    }

    var writingToolsBehavior: UIWritingToolsBehavior {
        get { quillSearchBarWritingToolsBehavior[ObjectIdentifier(self)] ?? .default }
        set { quillSearchBarWritingToolsBehavior[ObjectIdentifier(self)] = newValue }
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
#endif

public enum UIUserInterfaceIdiom: Int, Sendable {
    case unspecified = -1, phone = 0, pad = 1, tv = 2, carPlay = 3, mac = 5, vision = 6
}

// MARK: - UIEdgeInsets
//
// Layout-inset geometry (UIKit on iOS; NSEdgeInsets on macOS). SignalServiceKit
// reaches it via `import UIKit`. Only the raw four-edge value-holder lives here;
// SSK's own `UIEdgeInsets(margin:)` convenience init is an extension that builds
// on this base.
public struct UIEdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
    public static let zero = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}

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

// MARK: - UISwitch

/// `UISwitch: UIControl`. SSK only references it as a callback parameter type
/// (`switchDidChange(_ sender: UISwitch)` reading `.isOn`); never instantiated here.
@MainActor open class UISwitch: UIControl {
    nonisolated(unsafe) public var isOn: Bool = false
    public func setOn(_ on: Bool, animated: Bool) { isOn = on }
}

/// UIBezierPath. Inert on Linux (no real geometry recorded): `.cgPath` is an
/// opaque handle that the inert CGContext drawing shim accepts as `Any`. SSK uses
/// `UIBezierPath(ovalIn:)` + `.cgPath` for avatar clipping.
public final class UIBezierPath {
    public let cgPath: CGPath
    public var lineWidth: CGFloat = 1
    public init() { self.cgPath = CGPath() }
    public init(ovalIn rect: CGRect) { self.cgPath = CGPath() }
    public init(rect: CGRect) { self.cgPath = CGPath() }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) { self.cgPath = CGPath() }
    public init(cgPath: CGPath) { self.cgPath = cgPath }
    public func move(to point: CGPoint) {}
    public func addLine(to point: CGPoint) {}
    public func addCurve(to endPoint: CGPoint, controlPoint1: CGPoint, controlPoint2: CGPoint) {}
    public func addArc(withCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    public func close() {}
    public func append(_ bezierPath: UIBezierPath) {}
    public func reversing() -> UIBezierPath { UIBezierPath(cgPath: cgPath) }
    public func addClip() {}
    public func fill() {}
    public func stroke() {}
}

public enum UIDeviceOrientation: Int, Sendable {
    case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown
    public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
    public var isFlat: Bool { self == .faceUp || self == .faceDown }
    public var isValidInterfaceOrientation: Bool { isPortrait || isLandscape }
}

// UIInterfaceOrientationMask moved to QuillUIKit (UIGeometryExtras.swift,
// next to UIInterfaceOrientation): the UIViewController class body needs the
// type for Apple's `supportedInterfaceOrientations`. Still visible to
// `import UIKit` consumers via the `@_exported import QuillUIKit` above.

// MARK: - UIGraphicsImageRenderer (Linux: placeholder images)
//
// SignalServiceKit renders avatars/thumbnails into a renderer context. On Linux
// nothing is rasterized: the context's CGContext is the inert no-op from
// QuillFoundation and `.image{}` returns a blank placeholder UIImage of the
// requested size. Faithful image generation needs a real raster backend
// (Cairo/Skia) -- deferred. HONEST STATUS: produced images are blank.
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

// NSAttributedString.boundingRect — UIKit string measurement (ImageEditor
// text layers size themselves with it). Same rough estimate as
// String.boundingRect above, reading the font from the string's leading
// attributes. Linux-gated like the String version (macOS has the real one).
public extension NSAttributedString {
    func boundingRect(with size: CGSize,
                      options: NSStringDrawingOptions = [],
                      context: NSStringDrawingContext? = nil) -> CGRect {
        _ = (options, context)
        let attributes = length > 0 ? self.attributes(at: 0, effectiveRange: nil) : [:]
        return quillEstimatedTextRect(string, proposed: size, attributes: attributes)
    }
}

public final class UIGraphicsImageRendererFormat: @unchecked Sendable {
    public var scale: CGFloat = 1
    public var opaque: Bool = false
    public var prefersExtendedRange: Bool = false
    public init() {}
    public static var `default`: UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
    public static func preferred() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}

public final class UIGraphicsImageRendererContext: @unchecked Sendable {
    public let cgContext: CGContext
    public let format: UIGraphicsImageRendererFormat
    public init(cgContext: CGContext, format: UIGraphicsImageRendererFormat) {
        self.cgContext = cgContext
        self.format = format
    }
    public func fill(_ rect: CGRect) {}
    public func fill(_ rect: CGRect, blendMode: CGBlendMode) {}
    public func stroke(_ rect: CGRect) {}
    public func stroke(_ rect: CGRect, blendMode: CGBlendMode) {}
    public func clip(to rect: CGRect) {}
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

    private func runActions(_ actions: @MainActor (UIGraphicsImageRendererContext) -> Void) {
        let context = UIGraphicsImageRendererContext(cgContext: CGContext(), format: format)
        MainActor.assumeIsolated {
            actions(context)
        }
    }

    /// Returns a blank placeholder image of `size` (nothing is rasterized).
    public func image(_ actions: @MainActor (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        runActions(actions)
        return UIImage(size: size)
    }
    public func pngData(_ actions: @MainActor (UIGraphicsImageRendererContext) -> Void) -> Data {
        runActions(actions)
        return Data()
    }
    public func jpegData(withCompressionQuality quality: CGFloat, actions: @MainActor (UIGraphicsImageRendererContext) -> Void) -> Data {
        runActions(actions)
        return Data()
    }
}

// MARK: - Imperative UIGraphics* C-API (the pre-UIGraphicsImageRenderer style)
//
// AvatarBuilder still uses the old Begin/GetCurrentContext/GetImage/End flow. A
// minimal current-context stack backs it: the inert CGContext records nothing and
// the produced image is a blank placeholder of the begun size. Inert -- gated to
// Linux (these don't exist on macOS, and CGContext() is Linux-only).
nonisolated(unsafe) private var _uiGraphicsContextStack: [(context: CGContext, size: CGSize)] = []

public func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {
    _uiGraphicsContextStack.append((CGContext(), size))
}
public func UIGraphicsBeginImageContext(_ size: CGSize) {
    _uiGraphicsContextStack.append((CGContext(), size))
}
public func UIGraphicsGetCurrentContext() -> CGContext? {
    _uiGraphicsContextStack.last?.context
}
public func UIGraphicsGetImageFromCurrentImageContext() -> UIImage? {
    guard let top = _uiGraphicsContextStack.last else { return nil }
    return UIImage(size: top.size)
}
public func UIGraphicsEndImageContext() {
    if !_uiGraphicsContextStack.isEmpty { _uiGraphicsContextStack.removeLast() }
}
public func UIGraphicsPushContext(_ context: CGContext) {}
public func UIGraphicsPopContext() {}
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

    /// TextKit 1 wiring (NSLayoutManagerShim.swift). The storage owns its
    /// layout managers (strong, matching Apple); managers point back weakly.
    /// Edit notifications are NOT forwarded — managers recompute geometry from
    /// the storage on every query, so there is no layout state to invalidate.
    public private(set) var layoutManagers: [NSLayoutManager] = []

    public func addLayoutManager(_ aLayoutManager: NSLayoutManager) {
        layoutManagers.append(aLayoutManager)
        aLayoutManager.textStorage = self
    }

    public func removeLayoutManager(_ aLayoutManager: NSLayoutManager) {
        layoutManagers.removeAll { $0 === aLayoutManager }
        if aLayoutManager.textStorage === self {
            aLayoutManager.textStorage = nil
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
