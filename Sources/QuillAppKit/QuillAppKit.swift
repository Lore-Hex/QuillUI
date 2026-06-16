// QuillAppKit
// ===========
// Linux-only AppKit shadow. Provides type stubs for the AppKit surface
// that real Mac apps (CodeEdit, Maccy, AltTab, etc.) actually touch.
// On macOS this whole module is empty — Apple's real AppKit wins via
// the SDK. On Linux, `import AppKit` resolves to this module (the
// SwiftPM target is named `AppKit` so the swiftmodule filename matches).
//
// PHASE A goal: compile-only. Methods are stubs that satisfy the
// type-checker. Runtime behavior comes in Phase B (GTK4 backings).
//
// Surface driven from real compile errors against CodeEdit upstream —
// every type here exists because some upstream file mentions it.

#if os(Linux)

@_exported import QuillFoundation
@_exported import CoreImage
@_exported import QuillUIKit
@_exported import QuartzCore
@_exported import CoreVideo
@_exported import ImageIO
@_exported import CoreText
@_exported import CoreServices
import QuillKit
import Glibc

// MARK: - UndoManager
//
// Moved DOWN to QuillFoundation
// (Sources/QuillFoundation/UndoManagerLinuxClone.swift) so lower layers
// (RSCore/QuillRSCoreShim, Account) can share one definition without
// depending on AppKit. Re-exported here via the `@_exported import
// QuillFoundation` above, so `undoManager` uses below still resolve.

// MARK: - Geometry typealiases (NS variants of CG types)

public typealias NSPoint = CGPoint
public typealias NSSize = CGSize
public typealias NSRect = CGRect
// NSEdgeInsets comes from Foundation on Linux (a struct with
// init(top:left:bottom:right:)) — don't redeclare it, or it becomes ambiguous
// with Foundation's at any use site that imports both (e.g. conformance source
// via `import Cocoa`). The old tuple typealias only avoided this because nothing
// referenced it ambiguously.
public typealias NSRectPointer = UnsafeMutablePointer<NSRect>

// NSStringFromRect and NSRectFromString come from Foundation through QuillFoundation.

// MARK: - NSImage / NSColor / NSFont / NSScreen
//
// These are typealiased to the cross-platform RS* types in
// QuillFoundation, so `NSImage` and `UIImage` resolve to the same
// underlying class on Linux.

public typealias NSImage = RSImage
public typealias NSColor = RSColor
public typealias NSFont = RSFont
public let kUTTypeData = "public.data"
public let kUTTypeText = "public.text"
public let kUTTypeURL = "public.url"
public let kUTTypeFileURL = "public.file-url"

public struct ImageResource: Hashable, Sendable, ExpressibleByStringLiteral {
    public var name: String

    public init(name: String, bundle: Bundle? = nil) {
        self.name = name
        _ = bundle
    }

    public init(stringLiteral value: String) {
        self.init(name: value)
    }
}

public extension NSImage {
    /// Apple's `NSImage.Name` (a String). Apps construct/extend it
    /// (`NSImage.Name("StatusCircleYellow")`, `extension NSImage.Name { … }`).
    typealias Name = String
    // Apple's standard template-image names (NSImage.Name = String). Used as
    // `NSImage(named: NSImage.addTemplateName)` (WireGuard's tunnels toolbar).
    static let addTemplateName: Name = "NSAddTemplate"
    static let removeTemplateName: Name = "NSRemoveTemplate"
    static let actionTemplateName: Name = "NSActionTemplate"
    // Standard status-dot image names (WireGuard's TunnelListRow status icon).
    static let statusAvailableName: Name = "NSStatusAvailable"
    static let statusNoneName: Name = "NSStatusNone"
    static let statusPartiallyAvailableName: Name = "NSStatusPartiallyAvailable"
    static let statusUnavailableName: Name = "NSStatusUnavailable"
    static let imageTypes: [String] = [
        "public.image",
        "public.png",
        "public.jpeg",
        "public.tiff",
        "com.compuserve.gif",
    ]

    convenience init(resource: ImageResource) {
        if let image = NSImage(named: resource.name) {
            self.init(size: image.size)
            self.data = image.data
        } else {
            self.init(size: CGSize(width: 32, height: 32))
        }
    }
}
public typealias NSScreen = RSScreen

public struct NSColorSpaceName: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let deviceRGB = NSColorSpaceName(rawValue: "NSDeviceRGBColorSpace")
}

open class NSColorSpace: NSObject, @unchecked Sendable {
    public static let deviceRGB = NSColorSpace()
    public static let genericRGB = NSColorSpace()
    public static let sRGB = NSColorSpace()
    public override init() {}
}

// `NSBitmapImageRep` is the AppKit type that converts between
// raster image formats (TIFF, JPEG, PNG, …). Enchanted uses it
// to convert NSImage → JPEG bytes for upload. The Linux stub
// stores the source data and returns it back unchanged from
// `representation(using:properties:)` so callers can compile
// and round-trip arbitrary bytes; a real implementation needs a
// platform image codec (gdk-pixbuf, libpng, libjpeg).
public final class NSBitmapImageRep: @unchecked Sendable {
    public enum FileType: Int, Sendable {
        case tiff
        case bmp
        case gif
        case jpeg
        case png
        case jpeg2000
    }

    public enum PropertyKey: Hashable, Sendable {
        case compressionFactor
        case compressionMethod
    }

    private let data: Data
    /// Raw BGRA pixels + geometry when the rep was built from a CGImage
    /// (camera/snapshot path). nil when built from container bytes.
    internal let quillBGRAGeometry: (width: Int, height: Int, bytesPerRow: Int)?

    public init?(data: Data) {
        self.data = data
        self.quillBGRAGeometry = nil
    }

    /// Pixel-carrying designated init (the `init(cgImage:)` convenience in
    /// QuillAppKitCursorTrackingImaging.swift funnels through this).
    internal init(quillBGRA bgra: Data, width: Int, height: Int, bytesPerRow: Int) {
        self.data = bgra
        self.quillBGRAGeometry = (width, height, bytesPerRow)
    }

    public func representation(
        using storageType: FileType,
        properties: [PropertyKey: Any]
    ) -> Data? {
        quillRepresentation(using: storageType, properties: properties)
    }

    /// Looser key signature for upstream call sites that hand in
    /// `[String: Any]` or `[NSString: Any]` property dictionaries.
    public func representation<K, V>(
        using storageType: FileType,
        properties: [K: V]
    ) -> Data? {
        var typed: [PropertyKey: Any] = [:]
        for (key, value) in properties {
            if let propertyKey = key as? PropertyKey { typed[propertyKey] = value }
        }
        return quillRepresentation(using: storageType, properties: typed)
    }

    private func quillRepresentation(
        using storageType: FileType,
        properties: [PropertyKey: Any]
    ) -> Data? {
        #if os(Linux)
        let format: QuillBitmapEncodeFormat?
        switch storageType {
        case .png: format = .png
        case .jpeg: format = .jpeg
        case .tiff: format = .tiff
        case .bmp: format = .bmp
        case .gif, .jpeg2000: format = nil
        }
        guard let format else {
            // gdk-pixbuf has no GIF/JPEG2000 writer; fall back to the
            // pass-through so callers still see bytes (pre-rung-4 behavior).
            return data
        }
        var options: [(key: String, value: String)] = []
        if format == .jpeg {
            let factor = (properties[.compressionFactor] as? Double)
                ?? (properties[.compressionFactor] as? CGFloat).map(Double.init)
                ?? (properties[.compressionFactor] as? Float).map(Double.init)
                ?? 0.9
            let quality = Int((factor * 100).rounded())
            options.append(("quality", String(max(1, min(100, quality)))))
        }
        if format == .tiff,
           let method = properties[.compressionMethod] as? TIFFCompression {
            // gdk-pixbuf's TIFF "compression" option takes libtiff codes;
            // LZW (5) and none (1) map directly. Unsupported schemes fall
            // back to the writer default rather than failing the save.
            switch method {
            case .lzw: options.append(("compression", "5"))
            case .none: options.append(("compression", "1"))
            default: break
            }
        }
        if let geometry = quillBGRAGeometry {
            return quillEncodeBGRAPixels(
                data, width: geometry.width, height: geometry.height,
                bytesPerRow: geometry.bytesPerRow, format: format, options: options
            )
        }
        // Container bytes in: transcode to the requested format; if the bytes
        // don't decode, fall back to pass-through (Apple returns nil for
        // corrupt input, but pre-rung-4 callers relied on bytes out).
        return quillTranscodeEncodedImageData(data, format: format, options: options) ?? data
        #else
        return data
        #endif
    }
}

public extension NSColor {
    static let labelColor = NSColor()
    static let secondaryLabelColor = NSColor()
    static let tertiaryLabelColor = NSColor()
    static let quaternaryLabelColor = NSColor()
    static let textColor = NSColor()
    static let textBackgroundColor = NSColor()
    static let controlBackgroundColor = NSColor()
    static let controlAccentColor = NSColor()
    static let selectedTextBackgroundColor = NSColor()
    static let selectedContentBackgroundColor = NSColor()
    static let unemphasizedSelectedContentBackgroundColor = NSColor()
    static let separatorColor = NSColor()
    static let windowBackgroundColor = NSColor()
    static let underPageBackgroundColor = NSColor()
    static let gridColor = NSColor()
    static let highlightColor = NSColor()
    static let shadowColor = NSColor()

    // Phase B: standard hue presets with real RGB values. NSColor.black,
    // .white, .clear, .orange come from RSColor (QuillFoundation), so
    // we only declare the rest here. Values match Apple's deviceRGB
    // generic colors closely enough for common drawing.
    static let red = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
    static let green = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let blue = NSColor(red: 0, green: 0, blue: 1, alpha: 1)
    static let yellow = NSColor(red: 1, green: 1, blue: 0, alpha: 1)
    static let purple = NSColor(red: 0.5, green: 0, blue: 0.5, alpha: 1)
    static let cyan = NSColor(red: 0, green: 1, blue: 1, alpha: 1)
    static let magenta = NSColor(red: 1, green: 0, blue: 1, alpha: 1)
    static let darkGray = NSColor(red: 0.33, green: 0.33, blue: 0.33, alpha: 1)
    static let gray = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    static let lightGray = NSColor(red: 0.66, green: 0.66, blue: 0.66, alpha: 1)
    static let brown = NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)
    static let systemGreen = NSColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)
    static let systemOrange = NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1)

    struct Name: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
    }

    convenience init(name: NSColor.Name?, dynamicProvider: @escaping (NSAppearance) -> NSColor) {
        self.init()
    }
    // init(white:alpha:) lives on the RSColor class itself (QuillFoundation) —
    // one owner; a second extension copy here made the pair ambiguous from
    // modules that import both QuillAppKit and SignalServiceKitObjCPort.
    convenience init(deviceWhite: CGFloat, alpha: CGFloat) { self.init(white: deviceWhite, alpha: alpha) }
    convenience init(calibratedWhite: CGFloat, alpha: CGFloat) { self.init(white: calibratedWhite, alpha: alpha) }
    convenience init(srgbRed: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: srgbRed, green: green, blue: blue, alpha: alpha)
    }
    convenience init(deviceRed: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: deviceRed, green: green, blue: blue, alpha: alpha)
    }
    convenience init(calibratedRed: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: calibratedRed, green: green, blue: blue, alpha: alpha)
    }
    convenience init?(cgColor: CGColor) {
        let components = cgColor.components ?? [0, 0, 0, 1]
        let red = components.count > 0 ? components[0] : 0
        let green = components.count > 1 ? components[1] : red
        let blue = components.count > 2 ? components[2] : red
        let alpha = components.count > 3 ? components[3] : 1
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
        NSColor(red: _red, green: _green, blue: _blue, alpha: alpha)
    }

    func blended(withFraction f: CGFloat, of c: NSColor) -> NSColor? {
        let fraction = max(0, min(1, f))
        return NSColor(
            red: _red + (c._red - _red) * fraction,
            green: _green + (c._green - _green) * fraction,
            blue: _blue + (c._blue - _blue) * fraction,
            alpha: _alpha + (c._alpha - _alpha) * fraction
        )
    }
    func usingColorSpace(_ space: NSColorSpace) -> NSColor? { self }
    func usingColorSpaceName(_ colorSpaceName: NSColorSpaceName) -> NSColor? { self }
    var redComponent: CGFloat { _red }
    var greenComponent: CGFloat { _green }
    var blueComponent: CGFloat { _blue }
    var alphaComponent: CGFloat { _alpha }
    var hueComponent: CGFloat { 0 }
    var saturationComponent: CGFloat { 0 }
    var brightnessComponent: CGFloat { 0 }
}

open class NSGraphicsContext: NSObject, @unchecked Sendable {
    @MainActor public static var current: NSGraphicsContext? = NSGraphicsContext(cgContext: CGContext(), flipped: false)
    public let cgContext: CGContext
    public let isFlipped: Bool

    public init(cgContext: CGContext, flipped: Bool) {
        self.cgContext = cgContext
        self.isFlipped = flipped
        super.init()
    }
}

/// NSFontManager font-trait mask. WireGuard's ConfTextStorage derives its italic
/// font via `convert(_:toHaveTrait: .italicFontMask)`. Compile-only constants.
public struct NSFontTraitMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let italicFontMask = NSFontTraitMask(rawValue: 1 << 0)
    public static let boldFontMask = NSFontTraitMask(rawValue: 1 << 1)
    public static let unitalicFontMask = NSFontTraitMask(rawValue: 1 << 2)
    public static let unboldFontMask = NSFontTraitMask(rawValue: 1 << 3)
    public static let narrowFontMask = NSFontTraitMask(rawValue: 1 << 4)
    public static let expandedFontMask = NSFontTraitMask(rawValue: 1 << 5)
    public static let condensedFontMask = NSFontTraitMask(rawValue: 1 << 6)
    public static let smallCapsFontMask = NSFontTraitMask(rawValue: 1 << 7)
    public static let fixedPitchFontMask = NSFontTraitMask(rawValue: 1 << 8)
}

public extension NSFont {
    static func systemFont(ofSize: CGFloat, weight: NSFont.Weight) -> NSFont { NSFont() }
    static func boldSystemFont(ofSize: CGFloat) -> NSFont { NSFont() }
    static func monospacedSystemFont(ofSize: CGFloat, weight: NSFont.Weight) -> NSFont { NSFont() }
    static func monospacedDigitSystemFont(ofSize: CGFloat, weight: NSFont.Weight) -> NSFont { NSFont() }
    static var labelFontSize: CGFloat { 13 }
    static var systemFontSize: CGFloat { 13 }
    static var smallSystemFontSize: CGFloat { 11 }

    var fontName: String { "System" }
    var familyName: String? { "System" }

    final class TextStyle: Hashable, Sendable {
        public static let body = TextStyle()
        public static let title1 = TextStyle()
        public static let title2 = TextStyle()
        public static let headline = TextStyle()
        public static let subheadline = TextStyle()
        public static let caption1 = TextStyle()
        public static let caption2 = TextStyle()
        public func hash(into h: inout Hasher) {}
        public static func == (a: TextStyle, b: TextStyle) -> Bool { a === b }
    }
    static func preferredFont(forTextStyle style: TextStyle) -> NSFont { NSFont() }
}

open class NSFontManager: NSObject, @unchecked Sendable {
    public static let shared = NSFontManager()

    private static let fallbackFontFamilies = [
        "Courier",
        "Helvetica",
        "Menlo",
        "System",
        "Times",
    ]

    private static let fallbackFonts = [
        "Courier",
        "Courier-Bold",
        "Courier-BoldOblique",
        "Courier-Oblique",
        "Helvetica",
        "Helvetica-Bold",
        "Helvetica-BoldOblique",
        "Helvetica-Oblique",
        "Menlo-Bold",
        "Menlo-BoldItalic",
        "Menlo-Italic",
        "Menlo-Regular",
        "System",
        "System-Bold",
        "Times-Bold",
        "Times-BoldItalic",
        "Times-Italic",
        "Times-Roman",
    ]

    public func availableFonts() -> [String] { Self.fallbackFonts }
    public func availableFontFamilies() -> [String] { Self.fallbackFontFamilies }
    /// Font-trait / weight conversion. Compile-stubs (return the input font);
    /// WireGuard's ConfTextStorage derives bold/italic variants of its base font.
    public func convert(_ font: NSFont, toHaveTrait trait: NSFontTraitMask) -> NSFont { font }
    public func convert(_ font: NSFont, toNotHaveTrait trait: NSFontTraitMask) -> NSFont { font }
    public func convertWeight(_ upFlag: Bool, of font: NSFont) -> NSFont { font }
    public func availableMembers(ofFontFamily fontFamily: String) -> [[Any]]? {
        switch fontFamily {
        case "Courier":
            return [
                ["Courier", "Regular", 5, 0],
                ["Courier-Bold", "Bold", 9, 2],
                ["Courier-Oblique", "Oblique", 5, 1],
                ["Courier-BoldOblique", "Bold Oblique", 9, 3],
            ]
        case "Helvetica":
            return [
                ["Helvetica", "Regular", 5, 0],
                ["Helvetica-Bold", "Bold", 9, 2],
                ["Helvetica-Oblique", "Oblique", 5, 1],
                ["Helvetica-BoldOblique", "Bold Oblique", 9, 3],
            ]
        case "Menlo":
            return [
                ["Menlo-Regular", "Regular", 5, 0],
                ["Menlo-Bold", "Bold", 9, 2],
                ["Menlo-Italic", "Italic", 5, 1],
                ["Menlo-BoldItalic", "Bold Italic", 9, 3],
            ]
        case "System":
            return [
                ["System", "Regular", 5, 0],
                ["System-Bold", "Bold", 9, 2],
            ]
        case "Times":
            return [
                ["Times-Roman", "Roman", 5, 0],
                ["Times-Bold", "Bold", 9, 2],
                ["Times-Italic", "Italic", 5, 1],
                ["Times-BoldItalic", "Bold Italic", 9, 3],
            ]
        default:
            return nil
        }
    }
}

open class NSAppearance: NSObject, @unchecked Sendable {
    nonisolated(unsafe) public static var current: NSAppearance?

    public struct Name: RawRepresentable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let aqua = Name(rawValue: "NSAppearanceNameAqua")
        public static let darkAqua = Name(rawValue: "NSAppearanceNameDarkAqua")
        public static let vibrantLight = Name(rawValue: "NSAppearanceNameVibrantLight")
        public static let vibrantDark = Name(rawValue: "NSAppearanceNameVibrantDark")
        public static let accessibilityHighContrastAqua = Name(rawValue: "NSAppearanceNameAccessibilityHighContrastAqua")
        public static let accessibilityHighContrastDarkAqua = Name(rawValue: "NSAppearanceNameAccessibilityHighContrastDarkAqua")
        public static let accessibilityHighContrastVibrantLight = Name(rawValue: "NSAppearanceNameAccessibilityHighContrastVibrantLight")
        public static let accessibilityHighContrastVibrantDark = Name(rawValue: "NSAppearanceNameAccessibilityHighContrastVibrantDark")
    }

    public var name: Name = .aqua

    public override init() {
        super.init()
    }

    public init?(named name: NSAppearance.Name) {
        self.name = name
        super.init()
    }

    public func bestMatch(from appearances: [Name]) -> Name? {
        guard !appearances.isEmpty else { return nil }

        let available = Set(appearances)
        if available.contains(name) {
            return name
        }

        for fallback in Self.bestMatchPreferences[name] ?? [] where available.contains(fallback) {
            return fallback
        }

        return nil
    }

    private static let bestMatchPreferences: [Name: [Name]] = [
        .aqua: [
            .aqua, .accessibilityHighContrastAqua,
            .vibrantLight, .accessibilityHighContrastVibrantLight,
            .darkAqua, .accessibilityHighContrastDarkAqua,
            .vibrantDark, .accessibilityHighContrastVibrantDark
        ],
        .darkAqua: [
            .darkAqua, .accessibilityHighContrastDarkAqua,
            .vibrantDark, .accessibilityHighContrastVibrantDark,
            .aqua, .accessibilityHighContrastAqua,
            .vibrantLight, .accessibilityHighContrastVibrantLight
        ],
        .vibrantLight: [
            .vibrantLight, .accessibilityHighContrastVibrantLight,
            .aqua, .accessibilityHighContrastAqua,
            .vibrantDark, .accessibilityHighContrastVibrantDark,
            .darkAqua, .accessibilityHighContrastDarkAqua
        ],
        .vibrantDark: [
            .vibrantDark, .accessibilityHighContrastVibrantDark,
            .darkAqua, .accessibilityHighContrastDarkAqua,
            .vibrantLight, .accessibilityHighContrastVibrantLight,
            .aqua, .accessibilityHighContrastAqua
        ],
        .accessibilityHighContrastAqua: [
            .accessibilityHighContrastAqua, .aqua,
            .accessibilityHighContrastVibrantLight, .vibrantLight,
            .accessibilityHighContrastDarkAqua, .darkAqua,
            .accessibilityHighContrastVibrantDark, .vibrantDark
        ],
        .accessibilityHighContrastDarkAqua: [
            .accessibilityHighContrastDarkAqua, .darkAqua,
            .accessibilityHighContrastVibrantDark, .vibrantDark,
            .accessibilityHighContrastAqua, .aqua,
            .accessibilityHighContrastVibrantLight, .vibrantLight
        ],
        .accessibilityHighContrastVibrantLight: [
            .accessibilityHighContrastVibrantLight, .vibrantLight,
            .accessibilityHighContrastAqua, .aqua,
            .accessibilityHighContrastVibrantDark, .vibrantDark,
            .accessibilityHighContrastDarkAqua, .darkAqua
        ],
        .accessibilityHighContrastVibrantDark: [
            .accessibilityHighContrastVibrantDark, .vibrantDark,
            .accessibilityHighContrastDarkAqua, .darkAqua,
            .accessibilityHighContrastVibrantLight, .vibrantLight,
            .accessibilityHighContrastAqua, .aqua
        ]
    ]
}

// MARK: - NSResponder / NSView / NSViewController / NSWindow

// EPIC #512: Apple's NSResponder is @MainActor. The entire responder tree —
// NSView, NSControl and every view subclass, NSWindow + panels,
// NSWindowController, NSApplication, NSPopover — inherits this isolation,
// matching the macOS SDK. GTK/Qt callbacks enter via MainActor.assumeIsolated
// (the GTK main loop IS the main thread), the blessed boundary pattern.
@preconcurrency @MainActor
open class NSResponder: NSObject, @preconcurrency QuillSelectorDispatching {
    /// Linux target-action dispatch base (no ObjC runtime). AppKitLowering injects
    /// an `override` of this into every NSResponder subclass (NSView /
    /// NSViewController / NSControl / NSWindow / NSTextView / NSButton …) that
    /// declares `@objc` actions; each override switches on `selector.name` and
    /// falls through to `super.quillPerform` for inherited selectors, terminating
    /// here in a no-op. CLASS-BODY (not an extension) so the overrides are
    /// reachable through a base-class-typed reference (NSControl.sendAction casts
    /// `target as? QuillSelectorDispatching`). See QuillSelectorDispatching
    /// (QuillFoundation).
    open func quillPerform(_ selector: Selector, with sender: Any?) {}

    fileprivate weak var quillExplicitNextResponder: NSResponder?

    /// Opaque native-backend widget handle (e.g. a QWidget for QuillAppKitQt).
    /// Stored here — tied to the object's lifetime — instead of in an
    /// ObjectIdentifier-keyed side table, so a deallocated object's address
    /// being reused can never hand a new object a stale handle. Backends that
    /// prefer side tables (QuillAppKitGTK today) may ignore this.
    public var quillBackendHandle: UnsafeMutableRawPointer?

    // nonisolated: pure storage init, so nonisolated subclass inits
    // (NSViewController/NSView lowering ergonomics) can delegate to it.
    nonisolated public override init() {}
    open var nextResponder: NSResponder? {
        get { quillExplicitNextResponder }
        set { quillExplicitNextResponder = newValue }
    }
    open func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
    open func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
    open func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }
    open func rightMouseUp(with event: NSEvent) { nextResponder?.rightMouseUp(with: event) }
    open func mouseDragged(with event: NSEvent) { nextResponder?.mouseDragged(with: event) }
    open func mouseMoved(with event: NSEvent) { nextResponder?.mouseMoved(with: event) }
    open func mouseEntered(with event: NSEvent) { nextResponder?.mouseEntered(with: event) }
    open func mouseExited(with event: NSEvent) { nextResponder?.mouseExited(with: event) }
    // @MainActor: key events are delivered on the main thread, and overrides
    // (e.g. WireGuard's TunnelsListTableViewController.keyDown calling the
    // @MainActor handleRemoveTunnelAction on Delete) need that isolation. Same
    // rationale as cancelOperation below.
    @MainActor open func keyDown(with event: NSEvent) { nextResponder?.keyDown(with: event) }
    open func keyUp(with event: NSEvent) { nextResponder?.keyUp(with: event) }
    open func flagsChanged(with event: NSEvent) { nextResponder?.flagsChanged(with: event) }
    open func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    open func cursorUpdate(with event: NSEvent) { nextResponder?.cursorUpdate(with: event) }
    open func pressureChange(with event: NSEvent) { nextResponder?.pressureChange(with: event) }
    open func smartMagnify(with event: NSEvent) { nextResponder?.smartMagnify(with: event) }
    open func magnify(with event: NSEvent) { nextResponder?.magnify(with: event) }
    open func swipe(with event: NSEvent) { nextResponder?.swipe(with: event) }
    open func beginGesture(with event: NSEvent) { nextResponder?.beginGesture(with: event) }
    open func endGesture(with event: NSEvent) { nextResponder?.endGesture(with: event) }
    open func rotate(with event: NSEvent) { nextResponder?.rotate(with: event) }
    open func touchesBegan(with event: NSEvent) { nextResponder?.touchesBegan(with: event) }
    open func touchesMoved(with event: NSEvent) { nextResponder?.touchesMoved(with: event) }
    open func touchesEnded(with event: NSEvent) { nextResponder?.touchesEnded(with: event) }
    open func touchesCancelled(with event: NSEvent) { nextResponder?.touchesCancelled(with: event) }
    open func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { nextResponder?.draggingEntered(sender) ?? [] }
    open func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { nextResponder?.draggingUpdated(sender) ?? [] }
    open func draggingExited(_ sender: NSDraggingInfo?) { nextResponder?.draggingExited(sender) }
    open func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { nextResponder?.prepareForDragOperation(sender) ?? false }
    open func performDragOperation(_ sender: NSDraggingInfo) -> Bool { nextResponder?.performDragOperation(sender) ?? false }
    open func concludeDragOperation(_ sender: NSDraggingInfo?) { nextResponder?.concludeDragOperation(sender) }
    open func draggingEnded(_ sender: NSDraggingInfo?) { nextResponder?.draggingEnded(sender) }
    open func menu(for event: NSEvent) -> NSMenu? { nextResponder?.menu(for: event) }
    open class func accessibilityFocusedUIElement() -> Any? { nil }
    open func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    open var mouseDownCanMoveWindow: Bool { false }
    open var acceptsFirstResponder: Bool { false }
    open func becomeFirstResponder() -> Bool { true }
    open func resignFirstResponder() -> Bool { true }
    open func copy(_ sender: Any?) { _ = sender }
    open func paste(_ sender: Any?) { _ = sender }
    open func responds(to aSelector: Selector!) -> Bool {
        _ = aSelector
        return false
    }
    /// `cancelOperation(_:)` — the Esc / Cmd-. action method. Apple's NSResponder
    /// is @MainActor, so this method is marked @MainActor: subclass overrides that
    /// call @MainActor UI methods (e.g. WireGuard's LogViewController.cancelOperation
    /// → closeClicked()) inherit the isolation and type-check. Compile-stub; real
    /// responder-chain dispatch is a runtime concern.
    @MainActor open func cancelOperation(_ sender: Any?) {}
    /// Action-routing hook (NSResponder). WireGuard's ManageTunnelsRootViewController
    /// overrides it to forward toolbar/menu actions (handleAddEmptyTunnelAction etc.)
    /// to its child list/detail VCs. @MainActor so the override can reach those
    /// @MainActor child-VC properties. Default returns nil (no supplemental target).
    @MainActor open func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? { nil }
}

/// Mirrors `NSLayoutGuide`: a rectangular region that participates in Auto
/// Layout without being a view (lighter than a spacer view). Exposes the same
/// anchors as NSView so unmodified source can constrain to it. COMPILE-stub: the
/// anchors build real NSLayoutConstraints, but the Qt solve pass currently only
/// positions NSView items — honoring guide frames in the solve is a follow-up.
public final class NSLayoutGuide: NSObject {
    public weak var owningView: NSView?
    public var identifier: String = ""

    public override init() { super.init() }

    public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .top) }
    public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .bottom) }
    public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .leading) }
    public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .trailing) }
    public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .leading) }
    public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .trailing) }
    public var widthAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .width) }
    public var heightAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .height) }
    public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .centerX) }
    public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .centerY) }
}

public protocol NSViewToolTipOwner: AnyObject {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String
}

public extension NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        _ = (view, tag, point, data)
        return ""
    }
}

public enum NSFocusRingType: UInt, Sendable {
    case `default`, none, exterior
}

public enum NSPressureBehavior: Int, Sendable {
    case unknown = -1
    case primaryDefault = 0
    case primaryClick = 1
    case primaryGeneric = 2
    case primaryAccelerator = 3
    case primaryDeepClick = 5
}

open class NSPressureConfiguration: NSObject, @unchecked Sendable {
    public let pressureBehavior: NSPressureBehavior
    public init(pressureBehavior: NSPressureBehavior) {
        self.pressureBehavior = pressureBehavior
        super.init()
    }
}

open class NSView: NSResponder {
    /// Posted when a view's frame/bounds change (when posts*ChangedNotifications
    /// is set). WireGuard's LogViewController observes these to autoscroll.
    public static let frameDidChangeNotification = Notification.Name("NSViewFrameDidChangeNotification")
    public static let boundsDidChangeNotification = Notification.Name("NSViewBoundsDidChangeNotification")
    public var postsFrameChangedNotifications: Bool = false
    public var postsBoundsChangedNotifications: Bool = false
    /// `scroll(_:)` — scroll the view's content so `point` is at the origin.
    /// WireGuard's LogViewController calls it on the table to keep the tail
    /// visible. Compile-stub until the Qt scroll-view backend honors it.
    open func scroll(_ point: NSPoint) { setBoundsOrigin(point) }
    /// Hover tooltip. WireGuard sets it on detail-row buttons (ButtonRow.buttonToolTip)
    /// and table cells. Compile-stub (stored) until the Qt backend wires native tooltips.
    public var toolTip: String?
    open var frame: NSRect = .zero {
        didSet {
            guard frame != oldValue else { return }
            quillUpdateBoundsSize(from: oldValue.size, to: frame.size)
            needsLayout = true
        }
    }
    open var bounds: NSRect = .zero {
        didSet {
            if bounds != oldValue {
                needsLayout = true
            }
        }
    }
    public var subviews: [NSView] = []
    public private(set) var constraints: [NSLayoutConstraint] = []
    private var nextToolTipTag: ToolTipTag = 1
    public weak var superview: NSView?
    public weak var window: NSWindow?
    open var isHidden: Bool = false
    open var alphaValue: CGFloat = 1
    open var isOpaque: Bool { false }
    open var wantsLayer: Bool = false
    open var layer: CALayer?
    open var shadow: NSShadow?
    open var focusRingType: NSFocusRingType = .default
    open var pressureConfiguration: NSPressureConfiguration?
    public var translatesAutoresizingMaskIntoConstraints: Bool = true
    open var tag: Int = 0
    open var frameCenterRotation: CGFloat = 0
    open var animations: [String: Any]? = nil
    open var contentFilters: [Any]?
    public private(set) var gestureRecognizers: [NSGestureRecognizer] = []
    open var needsLayout: Bool = true
    private var quillNeedsDisplay: Bool = false
    open var needsDisplay: Bool {
        get { window == nil ? false : quillNeedsDisplay }
        set {
            guard newValue else { return }
            quillMarkNeedsDisplay()
        }
    }
    /// The appearance the view actually renders with (light/dark). Compile-stub
    /// (a default NSAppearance); WireGuard's ConfTextView reads it to theme its
    /// syntax colors, and overrides `viewDidChangeEffectiveAppearance()` to re-theme.
    public var effectiveAppearance: NSAppearance = NSAppearance()
    open var appearance: NSAppearance?
    open func viewDidChangeEffectiveAppearance() {}
    public var clipsToBounds: Bool = false
    public var autoresizingMask: AutoresizingMask = []
    public var identifier: NSUserInterfaceItemIdentifier?
    open var documentVisibleRect: NSRect { bounds }

    open override var nextResponder: NSResponder? {
        get { quillExplicitNextResponder ?? superview ?? window }
        set { quillExplicitNextResponder = newValue }
    }

    public struct AutoresizingMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let none: AutoresizingMask = []
        public static let width = AutoresizingMask(rawValue: 1 << 1)
        public static let height = AutoresizingMask(rawValue: 1 << 4)
        public static let minXMargin = AutoresizingMask(rawValue: 1 << 0)
        public static let maxXMargin = AutoresizingMask(rawValue: 1 << 2)
        public static let minYMargin = AutoresizingMask(rawValue: 1 << 3)
        public static let maxYMargin = AutoresizingMask(rawValue: 1 << 5)
    }

    // Convenience (not designated) so NSView matches real AppKit, where the
    // designated initializers are init(frame:)/init?(coder:) — a subclass's
    // `convenience init()` then needs no `override` (lets unmodified upstream
    // ViewControllers compile). See issue #231. `override` because this overrides
    // NSResponder's designated init(); being *convenience* is what frees subclasses.
    public override convenience init() { self.init(frame: .zero) }
    // nonisolated: pure storage (observers don't fire during init), so the
    // nonisolated convenience init() above can delegate (house model, #231).
    nonisolated public init(frame: NSRect) {
        super.init()
        self.frame = frame
        bounds = NSRect(origin: .zero, size: frame.size)
    }

    /// NSCoding designated init — `required`, exactly as on Apple (where NSView
    /// adopts NSCoding), so an unmodified upstream subclass can declare
    /// `required init?(coder:)` WITHOUT `override` and call `super.init(coder:)`
    /// (SolderScope's MicroscopeNSView does both). There is no unarchiving on
    /// Linux: the coder is ignored and the view starts zero-framed, equivalent
    /// to `init(frame: .zero)`. NOTE: because this is `required`, any NSView
    /// subclass that declares its own designated init must also declare it —
    /// real AppKit forces the exact same boilerplate, so upstream app sources
    /// already carry it; QuillAppKit's own designated-init subclasses
    /// (NSScrollView, NSButton, NSPopUpButton, NSHostingView, WKWebView)
    /// declare it alongside their inits. Convenience-only subclasses (e.g.
    /// NSTextField, NSSlider, NSStackView) inherit it automatically.
    /// Class-isolated like Apple's (no nonisolated delegation path needs it).
    public required init?(coder: NSCoder) {
        super.init()
    }

    open func addSubview(_ v: NSView) {
        insertSubview(v, at: subviews.count)
    }

    open func addSubview(_ v: NSView, positioned: NSWindow.OrderingMode, relativeTo: NSView?) {
        let index: Int
        if let relativeTo, let relativeIndex = subviews.firstIndex(where: { $0 === relativeTo }) {
            switch positioned {
            case .below:
                index = relativeIndex
            case .above, .out:
                index = relativeIndex + 1
            }
        } else {
            switch positioned {
            case .below:
                index = 0
            case .above, .out:
                index = subviews.count
            }
        }

        insertSubview(v, at: index)
    }

    open func removeFromSuperview() {
        guard let parent = superview else { return }
        parent.willRemoveSubview(self)
        viewWillMove(toSuperview: nil)
        parent.subviews.removeAll { $0 === self }
        superview = nil
        quillMoveWindowRecursively(nil)
        parent.quillMarkNeedsDisplay()
        viewDidMoveToSuperview()
    }
    open func setFrameSize(_ s: NSSize) { frame.size = s }
    open func setFrameOrigin(_ p: NSPoint) { frame.origin = p }
    open func setBoundsOrigin(_ p: NSPoint) { bounds.origin = p }
    open func scroll(to newOrigin: NSPoint) { setBoundsOrigin(newOrigin) }
    open func scrollToVisible(_ rect: NSRect) -> Bool {
        _ = rect
        return true
    }
    public func layoutSubtreeIfNeeded() {
        if needsLayout {
            layout()
            needsLayout = false
        }

        for subview in subviews {
            subview.layoutSubtreeIfNeeded()
        }
    }
    open func display() {
        quillDisplayIfWindowBacked()
    }

    open func display(_ rect: NSRect) {
        quillDisplayIfWindowBacked()
    }

    open func bitmapImageRepForCachingDisplay(in rect: NSRect) -> NSBitmapImageRep? {
        _ = rect
        return NSBitmapImageRep(data: Data())
    }

    open func cacheDisplay(in rect: NSRect, to bitmapImageRep: NSBitmapImageRep) {
        _ = (rect, bitmapImageRep)
    }

    open func displayIfNeeded() {
        quillDisplayIfWindowBacked()
    }

    open func displayIfNeededIgnoringOpacity() {
        quillDisplayIfWindowBacked()
    }

    open func invalidateIntrinsicContentSize() {
        needsLayout = true
        superview?.needsLayout = true
    }

    open func setNeedsDisplay(_ rect: NSRect) {
        guard rect.size.width > 0, rect.size.height > 0 else { return }
        quillMarkNeedsDisplay()
    }
    public func convert(_ p: NSPoint, from sourceView: NSView?) -> NSPoint {
        let windowPoint = sourceView?.quillConvertPointToWindowCoordinates(p) ?? p
        return quillConvertPointFromWindowCoordinates(windowPoint)
    }

    public func convert(_ p: NSPoint, to targetView: NSView?) -> NSPoint {
        let windowPoint = quillConvertPointToWindowCoordinates(p)
        return targetView?.quillConvertPointFromWindowCoordinates(windowPoint) ?? windowPoint
    }

    public func convert(_ r: NSRect, from sourceView: NSView?) -> NSRect {
        quillRect(
            from: convert(r.origin, from: sourceView),
            to: convert(NSPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height), from: sourceView)
        )
    }

    public func convert(_ r: NSRect, to targetView: NSView?) -> NSRect {
        quillRect(
            from: convert(r.origin, to: targetView),
            to: convert(NSPoint(x: r.origin.x + r.size.width, y: r.origin.y + r.size.height), to: targetView)
        )
    }

    open func hitTest(_ p: NSPoint) -> NSView? {
        guard !isHidden, quillBoundsContains(p) else { return nil }

        for child in subviews.reversed() {
            let childPoint = child.convert(p, from: self)
            if let hitView = child.hitTest(childPoint) {
                return hitView
            }
        }

        return self
    }

    // Computed so each anchor is bound to this view + its attribute (the native
    // layout pass reads that binding). Returning a fresh anchor per access
    // matches AppKit, where anchors are lightweight value-like handles.
    public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .top) }
    public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .bottom) }
    public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .leading) }
    public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .trailing) }
    // Absolute left/right. Under the shadow's left-to-right assumption these are
    // leading/trailing — enough for source-compat with VCs that pin to
    // leftAnchor/rightAnchor (e.g. WireGuard's ManageTunnels/TunnelDetail).
    public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .leading) }
    public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .trailing) }
    public var widthAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .width) }
    public var heightAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .height) }
    public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .centerX) }
    public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .centerY) }
    public var firstBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .firstBaseline) }
    public var lastBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .lastBaseline) }

    public private(set) var layoutGuides: [NSLayoutGuide] = []
    public func addLayoutGuide(_ guide: NSLayoutGuide) {
        layoutGuides.append(guide)
        guide.owningView = self
    }
    public func removeLayoutGuide(_ guide: NSLayoutGuide) {
        layoutGuides.removeAll { $0 === guide }
        if guide.owningView === self { guide.owningView = nil }
    }

    open func layout() {}
    open func draw(_ rect: NSRect) {}
    open func displayLayer() {}
    open var wantsUpdateLayer: Bool { false }
    open func updateLayer() {}
    @MainActor open func makeBackingLayer() -> CALayer { CALayer() }
    open func animator() -> Self { self }
    open func rotate(byDegrees angle: CGFloat) {
        frameCenterRotation += angle
    }
    open func replaceSubview(_ oldView: NSView, with newView: NSView) {
        guard let index = subviews.firstIndex(where: { $0 === oldView }) else {
            addSubview(newView)
            return
        }
        oldView.removeFromSuperview()
        insertSubview(newView, at: index)
    }
    open var isFlipped: Bool { false }
    open var canBecomeKeyView: Bool { false }
    open class var isCompatibleWithResponsiveScrolling: Bool { false }
    open var visibleRect: NSRect { bounds }
    open var inLiveResize: Bool { false }
    open func viewWillStartLiveResize() {}
    open func viewDidEndLiveResize() {}
    open func knowsPageRange(_ range: NSRangePointer) -> Bool {
        _ = range
        return false
    }
    open func viewDidChangeBackingProperties() {}
    open func performKeyEquivalent(with event: NSEvent) -> Bool {
        _ = event
        return false
    }
    open func isAccessibilityElement() -> Bool { false }
    open func accessibilityLabel() -> String? { nil }
    open func accessibilityParent() -> Any? { superview }
    open func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool {
        rect.contains(point)
    }
    open var wantsDefaultClipping: Bool { true }
    open var autoresizesSubviews: Bool = true
    public enum LayerContentsRedrawPolicy: Int, Sendable {
        case never, onSetNeedsDisplay, duringViewResize, beforeViewResize, crossfade
    }
    open var layerContentsRedrawPolicy: LayerContentsRedrawPolicy = .never
    open var acceptsTouchEvents: Bool = false
    open func addGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) {
        gestureRecognizers.append(gestureRecognizer)
        gestureRecognizer.view = self
    }
    open func removeGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) {
        gestureRecognizers.removeAll { $0 === gestureRecognizer }
        if gestureRecognizer.view === self {
            gestureRecognizer.view = nil
        }
    }
    public struct TouchTypeMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let direct = TouchTypeMask(rawValue: 1 << 0)
        public static let indirect = TouchTypeMask(rawValue: 1 << 1)
    }
    open var allowedTouchTypes: TouchTypeMask = []

    /// AppKit intrinsic content size. Default: no intrinsic size on either axis;
    /// content views (labels, buttons) and custom rows override this. A native
    /// backend may later compute it from the widget's measured size.
    open var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
    /// Sentinel meaning "no intrinsic size for this axis" (AppKit's value).
    public static let noIntrinsicMetric: CGFloat = -1

    /// Called when a recycled view (e.g. an NSTableView cell) is reused.
    open func prepareForReuse() {}
    open func viewWillDraw() {}

    /// Auto Layout content priorities. Captured for the native layout pass;
    /// currently no-ops (the solver treats required constraints as
    /// authoritative — feeding hugging/compression in is a fidelity refinement).
    open func setContentHuggingPriority(_ priority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) {}
    open func setContentCompressionResistancePriority(_ priority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) {}
    open func addConstraint(_ constraint: NSLayoutConstraint) {
        constraints.append(constraint)
        constraint.isActive = true
    }
    open func removeConstraint(_ constraint: NSLayoutConstraint) {
        constraints.removeAll { $0 === constraint }
        constraint.isActive = false
    }
    open func addConstraints(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints { addConstraint(constraint) }
    }
    open func removeConstraints(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints { removeConstraint(constraint) }
    }
    public typealias ToolTipTag = Int
    open func addToolTip(_ rect: NSRect, owner: NSViewToolTipOwner, userData data: UnsafeMutableRawPointer?) -> ToolTipTag {
        _ = (rect, owner, data)
        let tag = nextToolTipTag
        nextToolTipTag += 1
        return tag
    }
    open func removeToolTip(_ tag: ToolTipTag) { _ = tag }
    open func removeAllToolTips() {}
    open func registerForDraggedTypes(_ types: [NSPasteboard.PasteboardType]) { _ = types }
    open func unregisterDraggedTypes() {}
    open func viewWillMove(toWindow: NSWindow?) {}
    open func viewDidMoveToWindow() {}
    open func viewWillMove(toSuperview: NSView?) {}
    open func viewDidMoveToSuperview() {}
    open func viewDidHide() {}
    open func viewDidUnhide() {}
    open func updateTrackingAreas() {}
    open func resetCursorRects() {}
    open func didAddSubview(_ subview: NSView) { _ = subview }
    open func willRemoveSubview(_ subview: NSView) { _ = subview }

    public func addTrackingArea(_ a: NSTrackingArea) {
        guard !trackingAreas.contains(where: { $0 === a }) else { return }
        trackingAreas.append(a)
    }

    public func removeTrackingArea(_ a: NSTrackingArea) {
        trackingAreas.removeAll { $0 === a }
    }
    public var trackingAreas: [NSTrackingArea] = []

    public var enclosingScrollView: NSScrollView? {
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            ancestor = current.superview
        }
        return nil
    }

    private func insertSubview(_ child: NSView, at requestedIndex: Int) {
        guard child !== self else { return }

        let newWindow = window
        child.removeFromSuperview()

        child.viewWillMove(toSuperview: self)

        let index = min(max(0, requestedIndex), subviews.count)
        subviews.insert(child, at: index)
        child.superview = self
        child.quillMoveWindowRecursively(newWindow)
        quillMarkNeedsDisplay()
        didAddSubview(child)

        child.viewDidMoveToSuperview()
    }

    /// Toolkit hook: a GTK (or other) backing installs this to translate
    /// needsDisplay/setNeedsDisplay into a widget invalidation
    /// (gtk_widget_queue_draw). Fired on every mark, including propagated
    /// child marks.
    public var quillDisplayInvalidationHandler: (() -> Void)?

    private func quillMarkNeedsDisplay() {
        quillDisplayInvalidationHandler?()
        guard window != nil else {
            quillNeedsDisplay = false
            return
        }

        quillNeedsDisplay = true
        superview?.quillMarkNeedsDisplay()
    }

    private func quillClearNeedsDisplaySubtree() {
        quillNeedsDisplay = false
        for child in subviews {
            child.quillClearNeedsDisplaySubtree()
        }
    }

    private func quillDisplayIfWindowBacked() {
        guard window != nil else { return }

        viewWillDraw()
        quillClearNeedsDisplaySubtree()
    }

    private func quillBoundsContains(_ point: NSPoint) -> Bool {
        point.x >= bounds.origin.x &&
            point.y >= bounds.origin.y &&
            point.x < bounds.origin.x + bounds.size.width &&
            point.y < bounds.origin.y + bounds.size.height
    }

    private func quillConvertPointToWindowCoordinates(_ point: NSPoint) -> NSPoint {
        let pointInSuperview = NSPoint(
            x: frame.origin.x + Self.quillScaleCoordinate(
                point.x - bounds.origin.x,
                from: bounds.size.width,
                to: frame.size.width
            ),
            y: frame.origin.y + Self.quillScaleCoordinate(
                point.y - bounds.origin.y,
                from: bounds.size.height,
                to: frame.size.height
            )
        )

        return superview?.quillConvertPointToWindowCoordinates(pointInSuperview) ?? pointInSuperview
    }

    private func quillConvertPointFromWindowCoordinates(_ point: NSPoint) -> NSPoint {
        let pointInSuperview = superview?.quillConvertPointFromWindowCoordinates(point) ?? point
        return NSPoint(
            x: bounds.origin.x + Self.quillScaleCoordinate(
                pointInSuperview.x - frame.origin.x,
                from: frame.size.width,
                to: bounds.size.width
            ),
            y: bounds.origin.y + Self.quillScaleCoordinate(
                pointInSuperview.y - frame.origin.y,
                from: frame.size.height,
                to: bounds.size.height
            )
        )
    }

    private func quillRect(from origin: NSPoint, to corner: NSPoint) -> NSRect {
        NSRect(
            x: origin.x,
            y: origin.y,
            width: corner.x - origin.x,
            height: corner.y - origin.y
        )
    }

    private func quillUpdateBoundsSize(from oldFrameSize: NSSize, to newFrameSize: NSSize) {
        bounds.size.width = Self.quillScaleBoundsLength(
            bounds.size.width,
            from: oldFrameSize.width,
            to: newFrameSize.width
        )
        bounds.size.height = Self.quillScaleBoundsLength(
            bounds.size.height,
            from: oldFrameSize.height,
            to: newFrameSize.height
        )
    }

    private static func quillScaleBoundsLength(
        _ length: CGFloat,
        from oldFrameLength: CGFloat,
        to newFrameLength: CGFloat
    ) -> CGFloat {
        guard oldFrameLength != 0 else { return newFrameLength }
        return length * newFrameLength / oldFrameLength
    }

    private static func quillScaleCoordinate(
        _ value: CGFloat,
        from sourceLength: CGFloat,
        to targetLength: CGFloat
    ) -> CGFloat {
        guard sourceLength != 0 else { return 0 }
        return value * targetLength / sourceLength
    }

    fileprivate func quillSetWindowRecursively(_ newWindow: NSWindow?) {
        window = newWindow
        quillNeedsDisplay = newWindow != nil
        for child in subviews {
            child.quillSetWindowRecursively(newWindow)
        }
    }

    fileprivate func quillMoveWindowRecursively(_ newWindow: NSWindow?) {
        guard window !== newWindow else { return }
        quillViewWillMoveToWindowRecursively(newWindow)
        quillSetWindowRecursively(newWindow)
        quillViewDidMoveToWindowRecursively()
    }

    private func quillViewWillMoveToWindowRecursively(_ newWindow: NSWindow?) {
        viewWillMove(toWindow: newWindow)
        for child in subviews {
            child.quillViewWillMoveToWindowRecursively(newWindow)
        }
    }

    private func quillViewDidMoveToWindowRecursively() {
        viewDidMoveToWindow()
        for child in subviews {
            child.quillViewDidMoveToWindowRecursively()
        }
    }
}

// @MainActor: constructs NSView (isolated via NSResponder). Lowering-generated
// callers run on the main thread by AppKit contract.
@MainActor
public func QuillInstantiateView<T: NSView>(_ viewType: T.Type, frame: NSRect) -> T {
    _ = viewType
    return NSView(frame: frame) as! T
}

open class NSTrackingArea: NSObject, @unchecked Sendable {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let mouseEnteredAndExited = Options(rawValue: 1 << 0)
        public static let mouseMoved = Options(rawValue: 1 << 1)
        public static let cursorUpdate = Options(rawValue: 1 << 2)
        public static let activeAlways = Options(rawValue: 1 << 3)
        public static let activeInActiveApp = Options(rawValue: 1 << 4)
        public static let activeInKeyWindow = Options(rawValue: 1 << 5)
        public static let activeWhenFirstResponder = Options(rawValue: 1 << 6)
        public static let inVisibleRect = Options(rawValue: 1 << 7)
        public static let assumeInside = Options(rawValue: 1 << 8)
        public static let enabledDuringMouseDrag = Options(rawValue: 1 << 9)
    }
    public let rect: NSRect
    public let options: Options
    public let owner: Any?
    public let userInfo: [AnyHashable: Any]?

    public init(rect: NSRect, options: Options, owner: Any?, userInfo: [AnyHashable: Any]?) {
        self.rect = rect
        self.options = options
        self.owner = owner
        self.userInfo = userInfo
    }
}

@MainActor open class NSViewController: NSResponder {
    /// The VC that presented this one (set on present; read as
    /// `presentingViewController?.dismiss(self)`). Compile stub: nil unless set.
    public weak var presentingViewController: NSViewController?
    private var quillView: NSView = NSView()
    /// True once the view has been loaded (loadView has run). AppKit-faithful:
    /// accessing `.view` lazily loads it. Needed for rendering — a VC that builds
    /// its tree in `loadView()` (e.g. WireGuard's ButtonedDetailViewController)
    /// must have loadView run before its view can be laid out + drawn.
    public private(set) var isViewLoaded: Bool = false
    /// Load the view if it hasn't been yet: run `loadView()` then `viewDidLoad()`,
    /// matching AppKit's lazy `.view`. `isViewLoaded` is set BEFORE `loadView()`
    /// so a loadView body that assigns `self.view` (the setter) doesn't recurse.
    public func loadViewIfNeeded() {
        guard !isViewLoaded else { return }
        isViewLoaded = true
        loadView()
        viewDidLoad()
    }
    public var view: NSView {
        get {
            loadViewIfNeeded()
            if quillView.quillExplicitNextResponder == nil {
                quillView.nextResponder = self
            }
            return quillView
        }
        set {
            isViewLoaded = true
            if quillView.nextResponder === self {
                quillView.nextResponder = nil
            }
            quillView = newValue
            quillView.nextResponder = self
        }
    }
    public var children: [NSViewController] = []
    public var representedObject: Any?
    public var title: String?
    public weak var parent: NSViewController?
    public var preferredContentSize: NSSize = .zero
    public var preferredMinimumSize: NSSize = .zero
    public var preferredMaximumSize: NSSize = .zero
    // Designated init matches AppKit (init(nibName:bundle:) / init?(coder:)).
    // `nonisolated` so the (nonisolated, overriding NSResponder.init()) convenience
    // init below can delegate to it, and so subclasses' inits can call it from any
    // isolation. Only touches default-initialized stored properties + super.init().
    nonisolated public init(nibName: String?, bundle: Bundle?) { super.init() }
    // Convenience so a subclass's `init()` needs no `override` (issue #231; same
    // model as NSView). `override` because it overrides NSResponder's init().
    nonisolated public override convenience init() { self.init(nibName: nil, bundle: nil) }
    open func viewDidLoad() {}
    open func viewWillAppear() {}
    open func viewDidAppear() {}
    open func viewWillDisappear() {}
    open func viewDidDisappear() {}
    open func viewWillLayout() {}
    open func loadView() {}
    public func addChild(_ c: NSViewController) {
        guard !children.contains(where: { $0 === c }) else { return }
        c.removeFromParent()
        children.append(c)
        c.parent = self
    }

    public func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        self.parent = nil
    }
    public func presentAsSheet(_ vc: NSViewController) {}
    public func presentAsModalWindow(_ vc: NSViewController) {}
    public func dismiss(_ sender: Any?) {}
    @discardableResult
    open func presentError(_ error: any Error) -> Bool {
        _ = error
        return false
    }
    open func presentError(
        _ error: any Error,
        modalFor window: NSWindow,
        delegate: Any?,
        didPresent: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        _ = (error, window, delegate, didPresent, contextInfo)
    }
}

open class NSWindowController: NSResponder {
    public var window: NSWindow? {
        didSet {
            quillUpdateWindowControllerLink(from: oldValue)
        }
    }
    public weak var document: NSDocument?
    public var contentViewController: NSViewController?
    public init(window: NSWindow?) {
        super.init()
        self.window = window
        quillUpdateWindowControllerLink(from: nil)
    }
    public override convenience init() {
        self.init(window: nil)
    }
    public func showWindow(_ sender: Any?) { window?.makeKeyAndOrderFront(sender) }
    public func close() { window?.close() }
    open func newWindowForTab(_ sender: Any?) { _ = sender }
    public var shouldCascadeWindows: Bool = true
    public var windowFrameAutosaveName: String = ""

    private func quillUpdateWindowControllerLink(from oldWindow: NSWindow?) {
        guard oldWindow !== window else { return }
        if oldWindow?.windowController === self {
            oldWindow?.windowController = nil
        }
        if let window {
            if let existingController = window.windowController, existingController !== self {
                existingController.window = nil
            }
            window.windowController = self
        }
    }
}

open class NSStoryboard: NSObject, @unchecked Sendable {
    public typealias Name = String
    public typealias SceneIdentifier = String

    public let name: Name
    public let bundle: Bundle?

    public init(name: Name, bundle: Bundle?) {
        self.name = name
        self.bundle = bundle
        super.init()
    }

    open func instantiateController(withIdentifier identifier: SceneIdentifier) -> Any {
        let window = NSWindow()
        window.title = identifier
        return NSWindowController(window: window)
    }
}

@preconcurrency @MainActor public protocol NSWindowDelegate: AnyObject {
    func windowWillClose(_ notification: Notification)
    func windowDidBecomeKey(_ notification: Notification)
    func windowDidResignKey(_ notification: Notification)
    func windowDidResize(_ notification: Notification)
    func windowDidMove(_ notification: Notification)
    func windowDidMiniaturize(_ notification: Notification)
    func windowDidDeminiaturize(_ notification: Notification)
    func windowShouldClose(_ sender: NSWindow) -> Bool
}

public extension NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {}
    func windowDidBecomeKey(_ notification: Notification) {}
    func windowDidResignKey(_ notification: Notification) {}
    func windowDidResize(_ notification: Notification) {}
    func windowDidMove(_ notification: Notification) {}
    func windowDidMiniaturize(_ notification: Notification) {}
    func windowDidDeminiaturize(_ notification: Notification) {}
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

open class NSWindow: NSResponder {
    public static let didBecomeMainNotification = Notification.Name("NSWindowDidBecomeMainNotification")

    /// `NSWindow.FrameAutosaveName` (= String) — the type passed to
    /// `setFrameAutosaveName(_:)`. WireGuard's LogViewController builds one
    /// (`NSWindow.FrameAutosaveName("LogWindow")`) to persist window geometry.
    public typealias FrameAutosaveName = String
    public struct StyleMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let borderless: StyleMask = []
        public static let titled = StyleMask(rawValue: 1 << 0)
        public static let closable = StyleMask(rawValue: 1 << 1)
        public static let miniaturizable = StyleMask(rawValue: 1 << 2)
        public static let resizable = StyleMask(rawValue: 1 << 3)
        public static let fullSizeContentView = StyleMask(rawValue: 1 << 15)
        public static let texturedBackground = StyleMask(rawValue: 1 << 8)
        public static let unifiedTitleAndToolbar = StyleMask(rawValue: 1 << 12)
        public static let hudWindow = StyleMask(rawValue: 1 << 13)
        public static let utilityWindow = StyleMask(rawValue: 1 << 4)
        public static let docModalWindow = StyleMask(rawValue: 1 << 6)
        public static let nonactivatingPanel = StyleMask(rawValue: 1 << 7)
        public static let fullScreen = StyleMask(rawValue: 1 << 14)
    }

    public enum BackingStoreType: UInt, Sendable {
        case retained = 0, nonretained = 1, buffered = 2
    }

    public enum OrderingMode: Int, Sendable { case below, above, out }

    public enum TitleVisibility: Int, Sendable { case visible, hidden }

    // Static window-tabbing toggle — macOS Sierra+ groups windows
    // into tab groups by default; apps that don't want this set
    // `NSWindow.allowsAutomaticWindowTabbing = false`. No-op on
    // Linux but stored so reads round-trip.
    public static var allowsAutomaticWindowTabbing: Bool = true
    public static let didMoveNotification = Notification.Name("NSWindowDidMoveNotification")
    public static let didResizeNotification = Notification.Name("NSWindowDidResizeNotification")
    public static let didBecomeKeyNotification = Notification.Name("NSWindowDidBecomeKeyNotification")
    public static let didResignKeyNotification = Notification.Name("NSWindowDidResignKeyNotification")
    public static let didExitFullScreenNotification = Notification.Name("NSWindowDidExitFullScreenNotification")
    public static let didChangeOcclusionStateNotification = Notification.Name("NSWindowDidChangeOcclusionStateNotification")
    open class func windowNumber(at point: NSPoint, belowWindowWithWindowNumber windowNumber: Int) -> Int {
        _ = (point, windowNumber)
        return 0
    }

    public var menu: NSMenu?

    public struct CollectionBehavior: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let `default`: CollectionBehavior = []
        public static let canJoinAllSpaces = CollectionBehavior(rawValue: 1 << 0)
        public static let moveToActiveSpace = CollectionBehavior(rawValue: 1 << 1)
        public static let managed = CollectionBehavior(rawValue: 1 << 2)
        public static let transient = CollectionBehavior(rawValue: 1 << 3)
        public static let stationary = CollectionBehavior(rawValue: 1 << 4)
        public static let participatesInCycle = CollectionBehavior(rawValue: 1 << 5)
        public static let ignoresCycle = CollectionBehavior(rawValue: 1 << 6)
        public static let fullScreenPrimary = CollectionBehavior(rawValue: 1 << 7)
        public static let fullScreenAuxiliary = CollectionBehavior(rawValue: 1 << 8)
        public static let fullScreenAllowsTiling = CollectionBehavior(rawValue: 1 << 11)
        public static let fullScreenDisallowsTiling = CollectionBehavior(rawValue: 1 << 12)
    }

    public struct OcclusionState: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let visible = OcclusionState(rawValue: 1 << 1)
    }

    public var frame: NSRect = .zero
    public var title: String = ""
    public var subtitle: String = ""
    public var contentView: NSView? = NSView() {
        didSet {
            guard oldValue !== contentView else { return }
            oldValue?.quillMoveWindowRecursively(nil)
            contentView?.removeFromSuperview()
            contentView?.quillMoveWindowRecursively(self)
        }
    }
    public var contentViewController: NSViewController?
    /// The sheet currently presented on this window, if any (WireGuard's AppDelegate.quit
    /// checks it before terminating). Compile-stub: nil until sheets are modelled.
    public var attachedSheet: NSWindow?
    public weak var windowController: NSWindowController?
    public weak var delegate: NSWindowDelegate?
    public var styleMask: StyleMask = []
    public var collectionBehavior: CollectionBehavior = .default
    public var titleVisibility: TitleVisibility = .visible
    public var titlebarAppearsTransparent: Bool = false
    public var isOpaque: Bool = true
    public var backgroundColor: NSColor = NSColor()
    public var hasShadow: Bool = true
    public var isMovable: Bool = true
    public var isMovableByWindowBackground: Bool = false
    public var isReleasedWhenClosed: Bool = true
    /// When true, the window is transparent to mouse events (WireGuard toggles this
    /// on the edit sheet during save). Compile-stub.
    public var ignoresMouseEvents: Bool = false
    public var isVisible: Bool = false
    public var isMiniaturized: Bool = false
    public var isZoomed: Bool = false
    public var isKeyWindow: Bool = false
    public var isMainWindow: Bool = false
    open var canBecomeKey: Bool { true }
    open var canBecomeMain: Bool { true }
    open var acceptsMouseMovedEvents: Bool = false
    public var level: Level = .normal
    public var alphaValue: CGFloat = 1
    public var animationBehavior: AnimationBehavior = .default
    public var toolbar: NSToolbar?
    public var touchBar: NSTouchBar?
    public var toolbarStyle: ToolbarStyle = .automatic
    public var contentMinSize: NSSize = .zero
    public var contentMaxSize: NSSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    public var minSize: NSSize = .zero
    public var maxSize: NSSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    public var aspectRatio: NSSize = .zero
    public var contentAspectRatio: NSSize = .zero
    public var contentResizeIncrements: NSSize = .zero
    public var frameAutosaveName: String = ""
    public var currentEvent: NSEvent? { NSApp.currentEvent }
    public var identifier: NSUserInterfaceItemIdentifier?
    public var firstResponder: NSResponder?
    public var screen: NSScreen? { .main }
    open var windowNumber: Int { 0 }
    open var backingScaleFactor: CGFloat { screen?.backingScaleFactor ?? 1 }
    open var mouseLocationOutsideOfEventStream: NSPoint { NSEvent.mouseLocation }
    open var graphicsContext: Any? { nil }
    open var occlusionState: OcclusionState { .visible }
    public var representedURL: URL?
    public var appearance: NSAppearance?
    public var effectiveAppearance: NSAppearance = NSAppearance()
    public var tabbingMode: TabbingMode = .automatic
    public var tabbingIdentifier: String = ""
    private var standardWindowButtons: [WindowButton: NSButton] = [:]
    private var childWindowStorage: [NSWindow] = []
    private var tabbedWindowStorage: [NSWindow] = []
    private weak var tabbedWindowParentStorage: NSWindow?
    private var sheetWindowStorage: [NSWindow] = []
    private var sheetCompletionHandlers: [ObjectIdentifier: (NSApplication.ModalResponse) -> Void] = [:]
    private weak var sheetParentStorage: NSWindow?

    public struct Level: Equatable, Sendable {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let normal = Level(rawValue: 0)
        public static let floating = Level(rawValue: 3)
        public static let modalPanel = Level(rawValue: 8)
        public static let mainMenu = Level(rawValue: 24)
        public static let statusBar = Level(rawValue: 25)
        public static let popUpMenu = Level(rawValue: 101)
        public static let screenSaver = Level(rawValue: 1000)
    }

    public enum AnimationBehavior: Int, Sendable {
        case `default`, none, documentWindow, utilityWindow, alertPanel
    }

    public enum ToolbarStyle: Int, Sendable {
        case automatic, expanded, preference, unified, unifiedCompact
    }

    public enum WindowButton: Int, Sendable {
        case closeButton, miniaturizeButton, zoomButton, toolbarButton, documentIconButton, documentVersionsButton
    }

    public enum TabbingMode: Int, Sendable {
        case automatic, preferred, disallowed
    }

    // nonisolated (overrides NSResponder's nonisolated init). The contentView
    // back-pointer wiring is isolated work — hop via assumeIsolated, sound by
    // the AppKit contract (windows are constructed on the main thread; the GTK
    // main loop IS the main thread).
    nonisolated public override init() {
        super.init()
        MainActor.assumeIsolated {
            contentView?.quillSetWindowRecursively(self)
        }
    }

    nonisolated public init(contentRect: NSRect, styleMask: StyleMask, backing: BackingStoreType, defer: Bool) {
        super.init()
        self.frame = contentRect
        self.styleMask = styleMask
        MainActor.assumeIsolated {
            contentView?.quillSetWindowRecursively(self)
        }
    }

    public convenience init(contentRect: NSRect, styleMask: StyleMask, backing: BackingStoreType, defer: Bool, screen: NSScreen?) {
        self.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: `defer`)
        _ = screen
    }

    open func standardWindowButton(_ button: WindowButton) -> NSButton? {
        if let existing = standardWindowButtons[button] {
            return existing
        }
        let created = NSButton()
        standardWindowButtons[button] = created
        return created
    }

    /// Window hosting a view controller (WireGuard's AppDelegate manage-tunnels window).
    public convenience init(contentViewController: NSViewController) {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
    }

    open func makeKeyAndOrderFront(_ sender: Any?) { isVisible = true; isKeyWindow = true }
    open func makeKey() { isKeyWindow = true }
    open func makeMain() { isMainWindow = true }
    open func orderFront(_ sender: Any?) { isVisible = true }
    open func orderFrontRegardless() { isVisible = true }
    open func orderOut(_ sender: Any?) { isVisible = false }
    open func close() { isVisible = false }
    open func performClose(_ sender: Any?) { close() }
    open func miniaturize(_ sender: Any?) { isMiniaturized = true }
    open func deminiaturize(_ sender: Any?) { isMiniaturized = false }
    open func zoom(_ sender: Any?) { isZoomed.toggle() }
    open func toggleFullScreen(_ sender: Any?) {}
    open func setFrame(_ rect: NSRect, display: Bool) { self.frame = rect }
    open func setFrame(_ rect: NSRect, display: Bool, animate: Bool) { self.frame = rect }
    open func setFrameOrigin(_ p: NSPoint) { self.frame.origin = p }
    public func setFrameTopLeftPoint(_ p: NSPoint) { self.frame.origin = p }
    public func center() {}
    public func setContentSize(_ s: NSSize) { contentView?.frame.size = s }
    public var isOnActiveSpace: Bool { true }
    open func animator() -> Self { self }
    open func convertToScreen(_ rect: NSRect) -> NSRect {
        NSRect(
            x: frame.origin.x + rect.origin.x,
            y: frame.origin.y + rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
    open func convertFromScreen(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x - frame.origin.x,
            y: rect.origin.y - frame.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
    open func setIsVisible(_ v: Bool) { isVisible = v }
    public func setIsMiniaturized(_ v: Bool) { isMiniaturized = v }
    public func setIsZoomed(_ v: Bool) { isZoomed = v }
    open func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if firstResponder === responder { return true }
        if let responder, !responder.acceptsFirstResponder { return false }
        if let current = firstResponder, !current.resignFirstResponder() { return false }
        if let responder, !responder.becomeFirstResponder() { return false }
        firstResponder = responder
        return true
    }
    open func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        _ = (createFlag, object)
        return createFlag ? NSTextView() : nil
    }
    public func performMiniaturize(_ sender: Any?) {}
    public func performZoom(_ sender: Any?) {}
    open func performKeyEquivalent(with event: NSEvent) -> Bool {
        _ = event
        return false
    }
    open func sendEvent(_ event: NSEvent) {
        event.window = self
    }
    open func layoutIfNeeded() {
        contentView?.layoutSubtreeIfNeeded()
    }
    open func updateConstraintsIfNeeded() {}
    open func makeTouchBar() -> NSTouchBar? { nil }
    public func setFrameAutosaveName(_ name: String) -> Bool { frameAutosaveName = name; return true }
    public func saveFrame(usingName: String) {}
    public func setFrameUsingName(_ name: String) -> Bool { false }
    public func cascadeTopLeft(from: NSPoint) -> NSPoint { from }
    public func registerForDraggedTypes(_ types: [NSPasteboard.PasteboardType]) {}
    public func contentRect(forFrameRect r: NSRect) -> NSRect { r }
    public func frameRect(forContentRect r: NSRect) -> NSRect { r }
    public func addTabbedWindow(_ window: NSWindow, ordered: OrderingMode) {
        guard window !== self else { return }
        window.tabbedWindowParentStorage?.quillRemoveTabbedWindow(window, clearParent: true)
        tabbedWindowStorage.removeAll { $0 === window }
        window.tabbedWindowParentStorage = self
        switch ordered {
        case .below:
            tabbedWindowStorage.insert(window, at: 0)
        case .above, .out:
            tabbedWindowStorage.append(window)
        }
    }
    public func removeTabbedWindow(_ window: NSWindow) {
        quillRemoveTabbedWindow(window, clearParent: true)
    }
    public var tabbedWindows: [NSWindow]? { tabbedWindowStorage.isEmpty ? nil : tabbedWindowStorage }
    public func mergeAllWindows(_ sender: Any?) {}
    public func toggleTabBar(_ sender: Any?) {}
    public func addChildWindow(_ child: NSWindow, ordered: OrderingMode) {
        guard child !== self else { return }
        child.parent?.removeChildWindow(child)
        child.parent = self
        childWindowStorage.removeAll { $0 === child }
        switch ordered {
        case .below:
            childWindowStorage.insert(child, at: 0)
        case .above, .out:
            childWindowStorage.append(child)
        }
    }

    public func removeChildWindow(_ child: NSWindow) {
        childWindowStorage.removeAll { $0 === child }
        if child.parent === self {
            child.parent = nil
        }
    }

    public var childWindows: [NSWindow]? {
        childWindowStorage.isEmpty ? nil : childWindowStorage
    }
    public weak var parent: NSWindow?
    public var parentWindow: NSWindow? { parent }
    public var sheets: [NSWindow] { sheetWindowStorage }
    public var sheetParent: NSWindow? { sheetParentStorage }
    public func beginSheet(_ sheet: NSWindow, completionHandler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        guard sheet !== self else {
            completionHandler?(.abort)
            return
        }
        sheet.sheetParentStorage?.endSheet(sheet, returnCode: .abort)
        sheetWindowStorage.removeAll { $0 === sheet }
        sheetWindowStorage.append(sheet)
        sheet.sheetParentStorage = self
        sheet.isVisible = true
        let key = ObjectIdentifier(sheet)
        if let completionHandler {
            sheetCompletionHandlers[key] = completionHandler
        } else {
            sheetCompletionHandlers.removeValue(forKey: key)
        }
    }
    public func endSheet(_ sheet: NSWindow, returnCode: NSApplication.ModalResponse = .OK) {
        let key = ObjectIdentifier(sheet)
        let containedSheet = sheetWindowStorage.contains { $0 === sheet }
        sheetWindowStorage.removeAll { $0 === sheet }
        if sheet.sheetParentStorage === self {
            sheet.sheetParentStorage = nil
        }
        sheet.isVisible = false
        let completionHandler = sheetCompletionHandlers.removeValue(forKey: key)
        if containedSheet || completionHandler != nil {
            completionHandler?(returnCode)
        }
    }
    public func setAnchorAttribute(_ a: Any?, for: Any?) {}

    private func quillRemoveTabbedWindow(_ window: NSWindow, clearParent: Bool) {
        tabbedWindowStorage.removeAll { $0 === window }
        if clearParent, window.tabbedWindowParentStorage === self {
            window.tabbedWindowParentStorage = nil
        }
    }
}

// MARK: - NSPanel

open class NSPanel: NSWindow {
    public var isFloatingPanel: Bool = false
    public var becomesKeyOnlyIfNeeded: Bool = false
    public var worksWhenModal: Bool = false
}

// MARK: - NSTouchBar

open class NSTouchBar: NSObject, @unchecked Sendable {
    public weak var delegate: NSTouchBarDelegate?
    public var defaultItemIdentifiers: [NSTouchBarItem.Identifier] = []
    public var customizationIdentifier: String?
    public override init() {}
}

@preconcurrency @MainActor
public protocol NSTouchBarDelegate: AnyObject {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem?
}

public extension NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        _ = (touchBar, identifier)
        return nil
    }
}

open class NSTouchBarItem: NSObject, @unchecked Sendable {
    public struct Identifier: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public static let flexibleSpace = Identifier("NSTouchBarItemIdentifierFlexibleSpace")
        public static let fixedSpaceSmall = Identifier("NSTouchBarItemIdentifierFixedSpaceSmall")
        public static let fixedSpaceLarge = Identifier("NSTouchBarItemIdentifierFixedSpaceLarge")
    }

    public let identifier: Identifier
    public var customizationLabel: String = ""

    public init(identifier: Identifier) {
        self.identifier = identifier
        super.init()
    }
}

open class NSCustomTouchBarItem: NSTouchBarItem, @unchecked Sendable {
    public var view: NSView?
}

// MARK: - NSApplication

// NSApplication inherits @MainActor through NSResponder (EPIC #512), matching
// Apple. The old "drop @MainActor" workaround (generated Enchanted source read
// `NSApp.currentEvent` from nonisolated SwiftUI closures) is obsolete: with
// SwiftOpenUI.View now @MainActor, closures formed inside `body` inherit
// main-actor isolation, so those reads type-check without patchwork.
// @unchecked Sendable is retained (pre-existing; Apple's NSApplication is not
// Sendable, but removing it would break existing cross-module storage and it
// is inert under -strict-concurrency=minimal).
open class NSApplication: NSResponder, @unchecked Sendable {
    public static let shared = NSApplication()
    public weak var delegate: NSApplicationDelegate?
    public var mainMenu: NSMenu?
    public var windows: [NSWindow] = []
    public var keyWindow: NSWindow?
    public var mainWindow: NSWindow?
    public var orderedWindows: [NSWindow] = []
    public var orderedDocuments: [NSDocument] = []
    public var isActive: Bool = false
    private var _activationPolicy: ActivationPolicy = .regular
    public var applicationIconImage: NSImage?
    public var dockTile: NSDockTile = NSDockTile()
    public var presentationOptions: PresentationOptions = []
    public var currentEvent: NSEvent?
    public var effectiveAppearance: NSAppearance {
        NSAppearance.current ?? NSAppearance()
    }

    public enum ActivationPolicy: Int, Sendable {
        case regular, accessory, prohibited
    }
    public struct PresentationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
    }
    public enum TerminateReply: UInt, Sendable {
        case terminateCancel = 0, terminateNow = 1, terminateLater = 2
    }
    public struct ModalResponse: RawRepresentable, Equatable, Sendable {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let OK = ModalResponse(rawValue: 1)
        public static let cancel = ModalResponse(rawValue: 0)
        public static let stop = ModalResponse(rawValue: -1000)
        public static let abort = ModalResponse(rawValue: -1001)
        public static let `continue` = ModalResponse(rawValue: -1002)
        public static let alertFirstButtonReturn = ModalResponse(rawValue: 1000)
        public static let alertSecondButtonReturn = ModalResponse(rawValue: 1001)
        public static let alertThirdButtonReturn = ModalResponse(rawValue: 1002)
    }

    public func setActivationPolicy(_ p: ActivationPolicy) -> Bool { _activationPolicy = p; return true }
    /// Current activation policy (macOS is a method, not a property). WireGuard's
    /// AppDelegate calls `NSApp.activationPolicy()` to toggle dock-icon visibility.
    public func activationPolicy() -> ActivationPolicy { _activationPolicy }
    /// Standard About panel (WireGuard's AppDelegate.aboutClicked). Compile-stub.
    public struct AboutPanelOptionKey: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let applicationName = AboutPanelOptionKey(rawValue: "ApplicationName")
        public static let applicationIcon = AboutPanelOptionKey(rawValue: "ApplicationIcon")
        public static let applicationVersion = AboutPanelOptionKey(rawValue: "ApplicationVersion")
        public static let version = AboutPanelOptionKey(rawValue: "Version")
        public static let credits = AboutPanelOptionKey(rawValue: "Credits")
    }
    public func orderFrontStandardAboutPanel(options: [AboutPanelOptionKey: Any] = [:]) {}
    public func activate(ignoringOtherApps: Bool = false) { isActive = true }
    public func activate() { isActive = true }
    public func deactivate() { isActive = false }
    public func hide(_ sender: Any?) {}
    public func unhide(_ sender: Any?) {}
    public func terminate(_ sender: Any?) {}
    public func reply(toApplicationShouldTerminate: Bool) {}

    /// QuillAppKitGTK installs a real run() hook here at module init.
    /// Unmodified Mac apps that call `NSApp.run()` get the GTK loop
    /// for free if the GTK target is linked; otherwise this is a
    /// no-op (matches Apple's behavior on a non-display launch).
    public static var _runHook: (() -> Void)?

    public func run() {
        if let hook = NSApplication._runHook {
            hook()
        }
        // No hook → no-op stub. Headless tools that don't link GTK
        // still get clean returns from NSApp.run().
    }
    public func stop(_ sender: Any?) {}
    public func sendEvent(_ e: NSEvent) {
        currentEvent = e
        guard let event = NSEvent.quillApplyLocalMonitors(to: e) else { return }
        currentEvent = event
        quillDispatchEvent(event)
        NSEvent.quillNotifyGlobalMonitors(event)
    }
    public func nextEvent(matching: UInt64, until: Date?, inMode: RunLoop.Mode, dequeue: Bool) -> NSEvent? { nil }
    public func runModal(for window: NSWindow) -> ModalResponse { .OK }
    public func stopModal() {}
    public func stopModal(withCode: ModalResponse) {}
    public func beginSheet(_ sheet: NSWindow, completionHandler: ((ModalResponse) -> Void)? = nil) {
        if let parent = keyWindow ?? mainWindow ?? windows.last {
            parent.beginSheet(sheet, completionHandler: completionHandler)
        } else {
            sheet.isVisible = true
            completionHandler?(.OK)
        }
    }
    public func endSheet(_ sheet: NSWindow, returnCode: ModalResponse = .OK) {
        if let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: returnCode)
        } else {
            sheet.isVisible = false
        }
    }
    public func sendAction(_ a: Selector, to target: Any?, from sender: Any?) -> Bool {
        target != nil
    }
    public func windows(withTabIdentifier id: String) -> [NSWindow] {
        windows.filter { $0.tabbingIdentifier == id }
    }
    public func setServicesProvider(_ p: Any?) {}
    public func updateWindows() {}
    public func arrangeInFront(_ sender: Any?) {}
    public func miniaturizeAll(_ sender: Any?) {}
    public func hideOtherApplications(_ sender: Any?) {}
    public func unhideAllApplications(_ sender: Any?) {}
    public func registerForRemoteNotifications() {}
    public func unregisterForRemoteNotifications() {}

    private func quillDispatchEvent(_ event: NSEvent) {
        let eventWindow = event.window ?? keyWindow ?? mainWindow ?? windows.last
        let responder = eventWindow?.firstResponder ?? eventWindow?.contentView ?? eventWindow ?? self

        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            responder.mouseDown(with: event)
        case .leftMouseUp, .rightMouseUp:
            responder.mouseUp(with: event)
        case .leftMouseDragged, .rightMouseDragged:
            responder.mouseDragged(with: event)
        case .mouseMoved:
            responder.mouseMoved(with: event)
        case .keyDown:
            // keyDown is @MainActor (key events are main-thread); the event pump
            // dispatches on the main thread, so assume isolation for this one call.
            MainActor.assumeIsolated { responder.keyDown(with: event) }
        case .keyUp:
            responder.keyUp(with: event)
        case .flagsChanged:
            responder.flagsChanged(with: event)
        case .scrollWheel:
            responder.scrollWheel(with: event)
        case .mouseEntered, .mouseExited, .appKitDefined, .systemDefined,
             .applicationDefined, .periodic, .cursorUpdate, .magnify, .smartMagnify:
            break
        }
    }
}

// Top-level globals. @MainActor like Apple's `NSApp` global —
// NSApplication.shared is main-actor isolated via NSResponder.
@MainActor public var NSApp: NSApplication { NSApplication.shared }

open class NSDockTile: NSObject, @unchecked Sendable {
    public var badgeLabel: String?
    public var contentView: NSView?
    public var showsApplicationBadge: Bool = false
    public func display() {}
}

@preconcurrency @MainActor public protocol NSApplicationDelegate: AnyObject {
    func applicationDidFinishLaunching(_ notification: Notification)
    func applicationWillTerminate(_ notification: Notification)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    func application(_ application: NSApplication, open urls: [URL])
    func application(_ application: NSApplication, openFile filename: String) -> Bool
}

public extension NSApplicationDelegate {
    static func main() {}
    func applicationDidFinishLaunching(_ notification: Notification) {}
    func applicationWillTerminate(_ notification: Notification) {}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateNow }
    func application(_ application: NSApplication, open urls: [URL]) {}
    func application(_ application: NSApplication, openFile filename: String) -> Bool { false }
}

// MARK: - NSEvent

open class NSEvent: NSObject, @unchecked Sendable {
    public struct ModifierFlags: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let capsLock = ModifierFlags(rawValue: 1 << 16)
        public static let shift = ModifierFlags(rawValue: 1 << 17)
        public static let control = ModifierFlags(rawValue: 1 << 18)
        public static let option = ModifierFlags(rawValue: 1 << 19)
        public static let command = ModifierFlags(rawValue: 1 << 20)
        public static let numericPad = ModifierFlags(rawValue: 1 << 21)
        public static let help = ModifierFlags(rawValue: 1 << 22)
        public static let function = ModifierFlags(rawValue: 1 << 23)
        public static let deviceIndependentFlagsMask = ModifierFlags(rawValue: 0xffff_0000)
    }
    /// Mirrors `NSEvent.SpecialKey` (the subset apps check, e.g. WireGuard's
    /// `event.specialKey == .delete`). Apple models it as a struct.
    public struct SpecialKey: Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let delete = SpecialKey(rawValue: 0x7f)
        public static let backspace = SpecialKey(rawValue: 8)
        public static let carriageReturn = SpecialKey(rawValue: 13)
        public static let enter = SpecialKey(rawValue: 3)
        public static let tab = SpecialKey(rawValue: 9)
    }
    /// The special key for this event, or nil. Compile-only stub on Linux (no
    /// real key events); a runtime layer would compute it from the key code.
    public var specialKey: SpecialKey? { nil }
    public enum EventType: UInt, Sendable {
        case leftMouseDown = 1, leftMouseUp = 2, rightMouseDown = 3, rightMouseUp = 4
        case mouseMoved = 5, leftMouseDragged = 6, rightMouseDragged = 7
        case mouseEntered = 8, mouseExited = 9
        case keyDown = 10, keyUp = 11, flagsChanged = 12
        case appKitDefined = 13, systemDefined = 14, applicationDefined = 15, periodic = 16
        case cursorUpdate = 17, scrollWheel = 22, magnify = 30, smartMagnify = 32
    }
    public struct EventTypeMask: OptionSet, Sendable {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        private static func mask(_ type: NSEvent.EventType) -> EventTypeMask {
            EventTypeMask(rawValue: UInt64(1) << type.rawValue)
        }

        public static let leftMouseDown = mask(.leftMouseDown)
        public static let leftMouseUp = mask(.leftMouseUp)
        public static let rightMouseDown = mask(.rightMouseDown)
        public static let rightMouseUp = mask(.rightMouseUp)
        public static let mouseMoved = mask(.mouseMoved)
        public static let leftMouseDragged = mask(.leftMouseDragged)
        public static let rightMouseDragged = mask(.rightMouseDragged)
        public static let mouseEntered = mask(.mouseEntered)
        public static let mouseExited = mask(.mouseExited)
        public static let keyDown = mask(.keyDown)
        public static let keyUp = mask(.keyUp)
        public static let flagsChanged = mask(.flagsChanged)
        public static let appKitDefined = mask(.appKitDefined)
        public static let systemDefined = mask(.systemDefined)
        public static let applicationDefined = mask(.applicationDefined)
        public static let periodic = mask(.periodic)
        public static let cursorUpdate = mask(.cursorUpdate)
        public static let scrollWheel = mask(.scrollWheel)
        public static let any = EventTypeMask(rawValue: UInt64.max)
    }
    public var type: EventType = .keyDown
    public var modifierFlags: ModifierFlags = []
    public var keyCode: UInt16 = 0
    public var characters: String? = ""
    public var charactersIgnoringModifiers: String? = ""
    public var isARepeat: Bool = false
    public var clickCount: Int = 1
    public var deltaX: CGFloat = 0
    public var deltaY: CGFloat = 0
    public var deltaZ: CGFloat = 0
    public var scrollingDeltaX: CGFloat = 0
    public var scrollingDeltaY: CGFloat = 0
    public var hasPreciseScrollingDeltas: Bool = false
    public var magnification: CGFloat = 0
    public var stage: Int = 0
    public var locationInWindow: NSPoint = .zero
    public var timestamp: TimeInterval = 0
    public weak var window: NSWindow?
    public var phase: Phase = []
    public var momentumPhase: Phase = []
    public func locationInView(_ v: NSView?) -> NSPoint { .zero }

    public struct Phase: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let none: Phase = []
        public static let began = Phase(rawValue: 1 << 0)
        public static let stationary = Phase(rawValue: 1 << 1)
        public static let changed = Phase(rawValue: 1 << 2)
        public static let ended = Phase(rawValue: 1 << 3)
        public static let cancelled = Phase(rawValue: 1 << 4)
        public static let mayBegin = Phase(rawValue: 1 << 5)
    }

    public static var modifierFlags: ModifierFlags { [] }
    public static var mouseLocation: NSPoint { .zero }
    public static var pressedMouseButtons: Int { 0 }
    public func touches(matching phase: NSTouch.Phase, in view: NSView?) -> Set<NSTouch> {
        _ = (phase, view)
        return []
    }

    public static func keyEvent(
        with type: EventType,
        location: NSPoint,
        modifierFlags flags: ModifierFlags,
        timestamp: TimeInterval,
        windowNumber: Int,
        context: Any?,
        characters: String,
        charactersIgnoringModifiers: String,
        isARepeat: Bool,
        keyCode: UInt16
    ) -> NSEvent? {
        let event = NSEvent()
        event.type = type
        event.locationInWindow = location
        event.modifierFlags = flags
        event.timestamp = timestamp
        event.characters = characters
        event.charactersIgnoringModifiers = charactersIgnoringModifiers
        event.isARepeat = isARepeat
        event.keyCode = keyCode
        _ = (windowNumber, context)
        return event
    }

    public static func addLocalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
        let monitor = EventMonitor(mask: matching, localHandler: handler, globalHandler: nil)
        localEventMonitors.append(monitor)
        return monitor
    }

    public static func addGlobalMonitorForEvents(matching: EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Any? {
        let monitor = EventMonitor(mask: matching, localHandler: nil, globalHandler: handler)
        globalEventMonitors.append(monitor)
        return monitor
    }

    public static func removeMonitor(_ m: Any) {
        guard let monitor = m as? EventMonitor else { return }
        localEventMonitors.removeAll { $0 === monitor }
        globalEventMonitors.removeAll { $0 === monitor }
    }

    fileprivate static func quillApplyLocalMonitors(to event: NSEvent) -> NSEvent? {
        var monitoredEvent: NSEvent? = event
        for monitor in localEventMonitors {
            guard let currentEvent = monitoredEvent else { break }
            guard monitor.matches(currentEvent), let handler = monitor.localHandler else { continue }
            monitoredEvent = handler(currentEvent)
        }
        return monitoredEvent
    }

    fileprivate static func quillNotifyGlobalMonitors(_ event: NSEvent) {
        for monitor in globalEventMonitors where monitor.matches(event) {
            monitor.globalHandler?(event)
        }
    }

    private var quillEventTypeMask: EventTypeMask {
        EventTypeMask(rawValue: UInt64(1) << type.rawValue)
    }

    private final class EventMonitor {
        let mask: EventTypeMask
        let localHandler: ((NSEvent) -> NSEvent?)?
        let globalHandler: ((NSEvent) -> Void)?

        init(mask: EventTypeMask, localHandler: ((NSEvent) -> NSEvent?)?, globalHandler: ((NSEvent) -> Void)?) {
            self.mask = mask
            self.localHandler = localHandler
            self.globalHandler = globalHandler
        }

        func matches(_ event: NSEvent) -> Bool {
            mask.contains(event.quillEventTypeMask)
        }
    }

    private static var localEventMonitors: [EventMonitor] = []
    private static var globalEventMonitors: [EventMonitor] = []
}

// Apple parity (#512): gesture recognizers are @MainActor; NSClick/NSPress
// subclasses inherit.
@preconcurrency @MainActor
open class NSGestureRecognizer: NSObject {
    public enum State: Int, Sendable {
        case possible
        case began
        case changed
        case ended
        case cancelled
        case failed
    }

    public weak var view: NSView?
    public weak var target: AnyObject?
    public var action: Selector?
    public var state: State = .possible

    public init(target: AnyObject?, action: Selector?) {
        self.target = target
        self.action = action
        super.init()
    }

    public override init() {
        super.init()
    }

    public func location(in view: AnyObject?) -> NSPoint {
        _ = view
        return .zero
    }
}

open class NSClickGestureRecognizer: NSGestureRecognizer {}
open class NSPressGestureRecognizer: NSGestureRecognizer {}

public struct NSTouch: Hashable, @unchecked Sendable {
    public struct Phase: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let began = Phase(rawValue: 1 << 0)
        public static let moved = Phase(rawValue: 1 << 1)
        public static let stationary = Phase(rawValue: 1 << 2)
        public static let ended = Phase(rawValue: 1 << 3)
        public static let cancelled = Phase(rawValue: 1 << 4)
        public static let touching: Phase = [.began, .moved, .stationary]
        public static let any = Phase(rawValue: UInt.max)
    }

    public var identity: AnyHashable
    public var normalizedPosition: NSPoint
    public var phase: Phase

    public init(identity: AnyHashable = 0, normalizedPosition: NSPoint = .zero, phase: Phase = []) {
        self.identity = identity
        self.normalizedPosition = normalizedPosition
        self.phase = phase
    }

    public static func == (lhs: NSTouch, rhs: NSTouch) -> Bool {
        lhs.identity == rhs.identity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }
}

// MARK: - NSPasteboard
//
// Phase B (real backing): NSPasteboard.general is now backed by a
// real cross-process clipboard on Linux. Strategy is tiered, picked
// once at first access and cached for the process lifetime:
//   1. Wayland: shells out to wl-copy / wl-paste if both are on PATH.
//   2. X11: shells out to xclip if PATH-discoverable and DISPLAY is set.
//   3. Headless: file-backed at $XDG_RUNTIME_DIR (or /tmp) — survives
//      across processes within the same user session.
//
// On macOS, Apple's real NSPasteboard wins via the SDK and this whole
// module is empty.
//
// Per-type storage uses the file-backed path (Linux clipboards only
// natively carry plain text; non-text types stay process-local).

public protocol NSPasteboardOwner: AnyObject {
    func pasteboard(_ sender: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType)
}

open class NSPasteboard: NSObject, @unchecked Sendable {
    public struct PasteboardType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public static let string = PasteboardType(rawValue: "public.utf8-plain-text")
        public static let URL = PasteboardType(rawValue: "public.url")
        public static let fileURL = PasteboardType(rawValue: "public.file-url")
        public static let kUrl = PasteboardType(rawValue: "public.url")
        public static let kFilenames = PasteboardType(rawValue: "NSFilenamesPboardType")
        public static let html = PasteboardType(rawValue: "public.html")
        public static let pdf = PasteboardType(rawValue: "com.adobe.pdf")
        public static let png = PasteboardType(rawValue: "public.png")
        public static let tiff = PasteboardType(rawValue: "public.tiff")
        public static let rtf = PasteboardType(rawValue: "public.rtf")
        public static let color = PasteboardType(rawValue: "com.apple.cocoa.pasteboard.color")
        public static let multipleTextSelection = PasteboardType(rawValue: "NSMultipleTextSelectionPboardType")
        public static let backwardsCompatibleFileURL = PasteboardType(rawValue: "public.file-url-bwc")
    }
    public struct Name: RawRepresentable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let general = Name(rawValue: "Apple.NSGeneralPboard")
        public static let drag = Name(rawValue: "Apple.NSDragPboard")
        public static let find = Name(rawValue: "Apple.NSFindPboard")
        public static let font = Name(rawValue: "Apple.NSFontPboard")
        public static let ruler = Name(rawValue: "Apple.NSRulerPboard")
    }
    public struct PasteboardReadingOption: Hashable, RawRepresentable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let urlReadingFileURLsOnly = PasteboardReadingOption(rawValue: "NSPasteboardURLReadingFileURLsOnlyKey")
        public static let urlReadingContentsConformToTypes = PasteboardReadingOption(rawValue: "NSPasteboardURLReadingContentsConformToTypesKey")
    }

    public static let general = NSPasteboard(name: .general)
    private let name: Name
    public init(name: Name = .general) {
        self.name = name
        super.init()
    }

    public var changeCount: Int {
        _changeCountPath().flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .flatMap(Int.init) ?? 0
    }

    public var pasteboardItems: [NSPasteboardItem]? = nil
    private var declaredTypes: [PasteboardType]? = nil
    private var declaredOwner: NSPasteboardOwner? = nil
    private var ownerRequestsInFlight: Set<PasteboardType> = []

    @discardableResult
    public func clearContents() -> Int {
        pasteboardItems = nil
        declaredTypes = nil
        declaredOwner = nil
        ownerRequestsInFlight.removeAll()
        _writeClipboardString("")
        _clearFileBackedTypes()
        _bumpChangeCount()
        return changeCount
    }

    @discardableResult
    public func setString(_ s: String, forType type: PasteboardType) -> Bool {
        if declaredTypes == nil {
            _prepareToReplaceContents()
        }
        let item = NSPasteboardItem()
        item.setString(s, forType: type)
        pasteboardItems = [item]
        _rememberDeclaredType(type)

        guard type == .string else {
            _writeFileBacked(type: type, data: Data(s.utf8))
            _bumpChangeCount()
            return true
        }
        _writeClipboardString(s)
        _writeFileBacked(type: type, data: Data(s.utf8))
        _bumpChangeCount()
        return true
    }

    @discardableResult
    public func setData(_ d: Data, forType type: PasteboardType) -> Bool {
        if declaredTypes == nil {
            _prepareToReplaceContents()
        }
        let item = NSPasteboardItem()
        item.setData(d, forType: type)
        pasteboardItems = [item]
        _rememberDeclaredType(type)

        if type == .string, let s = String(data: d, encoding: .utf8) {
            _writeClipboardString(s)
        }
        _writeFileBacked(type: type, data: d)
        _bumpChangeCount()
        return true
    }

    public func string(forType type: PasteboardType) -> String? {
        if let declaredTypes, !declaredTypes.contains(type) {
            return nil
        }
        if type == .string, let s = _readClipboardString(), !s.isEmpty {
            return s
        }
        if let string = _readFileBacked(type: type).flatMap({ String(data: $0, encoding: .utf8) }) {
            return string
        }
        _requestDataFromOwnerIfNeeded(for: type)
        if type == .string, let s = _readClipboardString(), !s.isEmpty {
            return s
        }
        return _readFileBacked(type: type).flatMap { String(data: $0, encoding: .utf8) }
    }

    public func data(forType type: PasteboardType) -> Data? {
        if let declaredTypes, !declaredTypes.contains(type) {
            return nil
        }
        if type == .string, let s = _readClipboardString(), !s.isEmpty {
            return Data(s.utf8)
        }
        if let data = _readFileBacked(type: type) {
            return data
        }
        _requestDataFromOwnerIfNeeded(for: type)
        if type == .string, let s = _readClipboardString(), !s.isEmpty {
            return Data(s.utf8)
        }
        return _readFileBacked(type: type)
    }

    public func types() -> [PasteboardType]? {
        if let declaredTypes, !declaredTypes.isEmpty {
            return declaredTypes
        }
        if let pasteboardItems, !pasteboardItems.isEmpty {
            return _types(from: pasteboardItems)
        }
        let dir = _typeDir()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        return files.map { PasteboardType(rawValue: $0) }
    }

    public func availableType(from types: [PasteboardType]) -> PasteboardType? {
        guard let availableTypes = self.types(), !availableTypes.isEmpty else { return nil }
        let available = Set(availableTypes)
        return types.first { available.contains($0) }
    }

    public func canReadItem(withDataConformingToTypes types: [String]) -> Bool {
        let pasteboardTypes = types.map(PasteboardType.init(rawValue:))
        if availableType(from: pasteboardTypes) != nil {
            return true
        }
        guard let availableTypes = self.types(), !availableTypes.isEmpty else {
            return false
        }
        let availableRawValues = Set(availableTypes.map(\.rawValue))
        return types.contains { requestedType in
            availableRawValues.contains(requestedType)
                || (requestedType == "public.image" && availableRawValues.contains { rawValue in
                    rawValue == "public.png"
                        || rawValue == "public.jpeg"
                        || rawValue == "public.tiff"
                        || rawValue == "com.compuserve.gif"
                })
        }
    }

    @discardableResult
    public func declareTypes(_ types: [PasteboardType], owner: Any?) -> Int {
        pasteboardItems = nil
        declaredTypes = types
        declaredOwner = owner as? NSPasteboardOwner
        ownerRequestsInFlight.removeAll()
        _writeClipboardString("")
        _clearFileBackedTypes()
        _bumpChangeCount()
        return changeCount
    }

    public func writeObjects(_ objs: [Any]) -> Bool {
        var items: [NSPasteboardItem] = []
        var wroteAnyType = false

        for obj in objs {
            if let s = obj as? String {
                if !wroteAnyType {
                    _prepareToReplaceContents()
                }
                let item = NSPasteboardItem()
                item.setString(s, forType: .string)
                items.append(item)
                _writeClipboardString(s)
                _writeFileBacked(type: .string, data: Data(s.utf8))
                wroteAnyType = true
            } else if let item = obj as? NSPasteboardItem {
                items.append(item)
                for type in item.types {
                    guard let data = item.data(forType: type) else { continue }
                    if !wroteAnyType {
                        _prepareToReplaceContents()
                    }
                    if type == .string, let s = String(data: data, encoding: .utf8) {
                        _writeClipboardString(s)
                    }
                    _writeFileBacked(type: type, data: data)
                    wroteAnyType = true
                }
            }
        }

        if !items.isEmpty {
            pasteboardItems = items
            declaredTypes = nil
            declaredOwner = nil
            ownerRequestsInFlight.removeAll()
        }
        if wroteAnyType {
            _bumpChangeCount()
        }
        return true
    }
    public func readObjects(forClasses classes: [AnyClass], options: [PasteboardReadingOption: Any]?) -> [Any]? {
        for objectClass in classes {
            if objectClass == NSString.self, let string = _readStringObject() {
                return [string]
            }
            if objectClass == NSURL.self, let url = _readURLObject(options: options) {
                return [url]
            }
            if objectClass == NSPasteboardItem.self, let items = _readPasteboardItemObjects() {
                return items
            }
        }
        return nil
    }
    public func canReadObject(forClasses classes: [AnyClass], options: [PasteboardReadingOption: Any]?) -> Bool {
        for objectClass in classes {
            if objectClass == NSString.self, availableType(from: [.string]) != nil {
                return true
            }
            if objectClass == NSURL.self, _availableURLType(options: options) != nil {
                return true
            }
            if objectClass == NSPasteboardItem.self, let types = types(), !types.isEmpty {
                return true
            }
        }
        return false
    }
}

// MARK: NSPasteboard backing helpers (Linux)

private extension NSPasteboard {
    func _readStringObject() -> String? {
        string(forType: .string)
    }

    func _readURLObject(options: [PasteboardReadingOption: Any]?) -> NSURL? {
        guard let type = _availableURLType(options: options),
              let value = string(forType: type)
        else {
            return nil
        }

        let url: URL?
        if type == .fileURL || type == .backwardsCompatibleFileURL {
            if let parsed = URL(string: value), parsed.isFileURL {
                url = parsed
            } else {
                url = URL(fileURLWithPath: value)
            }
        } else {
            url = URL(string: value)
        }
        return url.map { $0 as NSURL }
    }

    func _availableURLType(options: [PasteboardReadingOption: Any]?) -> PasteboardType? {
        let fileURLsOnly = options?[.urlReadingFileURLsOnly].map(_truthy) ?? false
        let urlTypes: [PasteboardType] = fileURLsOnly
            ? [.fileURL, .backwardsCompatibleFileURL]
            : [.fileURL, .backwardsCompatibleFileURL, .URL]
        return availableType(from: urlTypes)
    }

    func _readPasteboardItemObjects() -> [NSPasteboardItem]? {
        if let pasteboardItems, !pasteboardItems.isEmpty {
            return pasteboardItems
        }
        guard let types = types(), !types.isEmpty else { return nil }

        let item = NSPasteboardItem()
        var capturedType = false
        for type in types {
            guard let data = data(forType: type) else { continue }
            item.setData(data, forType: type)
            capturedType = true
        }
        return capturedType ? [item] : nil
    }

    func _truthy(_ value: Any) -> Bool {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            return ["1", "true", "yes"].contains(string.lowercased())
        }
        return false
    }

    func _stateDir() -> String {
        let base = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"]
            ?? NSTemporaryDirectory()
        let dir = (base as NSString).appendingPathComponent("quill-pasteboard/\(name.rawValue)")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
    func _typeDir() -> String {
        let dir = (_stateDir() as NSString).appendingPathComponent("types")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }
    func _filePath(for type: PasteboardType) -> String {
        let safe = type.rawValue.replacingOccurrences(of: "/", with: "_")
        return (_typeDir() as NSString).appendingPathComponent(safe)
    }
    func _changeCountPath() -> String? {
        (_stateDir() as NSString).appendingPathComponent("changeCount")
    }
    func _bumpChangeCount() {
        guard let path = _changeCountPath() else { return }
        let next = changeCount + 1
        try? "\(next)".write(toFile: path, atomically: true, encoding: .utf8)
    }
    func _writeFileBacked(type: PasteboardType, data: Data) {
        try? data.write(to: URL(fileURLWithPath: _filePath(for: type)))
    }
    func _readFileBacked(type: PasteboardType) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: _filePath(for: type)))
    }
    func _clearFileBackedTypes() {
        try? FileManager.default.removeItem(atPath: _typeDir())
    }
    func _prepareToReplaceContents() {
        pasteboardItems = nil
        declaredTypes = nil
        declaredOwner = nil
        ownerRequestsInFlight.removeAll()
        _writeClipboardString("")
        _clearFileBackedTypes()
    }
    func _requestDataFromOwnerIfNeeded(for type: PasteboardType) {
        guard _readFileBacked(type: type) == nil else { return }
        guard declaredTypes?.contains(type) == true else { return }
        guard let declaredOwner else { return }
        guard !ownerRequestsInFlight.contains(type) else { return }

        ownerRequestsInFlight.insert(type)
        declaredOwner.pasteboard(self, provideDataForType: type)
        ownerRequestsInFlight.remove(type)
    }
    func _types(from items: [NSPasteboardItem]) -> [PasteboardType] {
        var ordered: [PasteboardType] = []
        for item in items {
            for type in item.types where !ordered.contains(type) {
                ordered.append(type)
            }
        }
        return ordered
    }
    func _rememberDeclaredType(_ type: PasteboardType) {
        guard var currentDeclaredTypes = declaredTypes else { return }
        if !currentDeclaredTypes.contains(type) {
            currentDeclaredTypes.append(type)
            declaredTypes = currentDeclaredTypes
        }
    }
    func _writeClipboardString(_ s: String) {
        // Tier 1: Wayland
        if _hasCommand("wl-copy"), ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil {
            _runPipeIn(["wl-copy"], stdin: s); return
        }
        // Tier 2: X11
        if _hasCommand("xclip"), ProcessInfo.processInfo.environment["DISPLAY"] != nil {
            _runPipeIn(["xclip", "-selection", "clipboard"], stdin: s); return
        }
        // Tier 3: file-backed only (already written by setString caller)
    }
    func _readClipboardString() -> String? {
        if _hasCommand("wl-paste"), ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"] != nil {
            return _runPipeOut(["wl-paste", "--no-newline"])
        }
        if _hasCommand("xclip"), ProcessInfo.processInfo.environment["DISPLAY"] != nil {
            return _runPipeOut(["xclip", "-selection", "clipboard", "-o"])
        }
        return nil
    }
    func _hasCommand(_ name: String) -> Bool {
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            if FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)") { return true }
        }
        return false
    }
    func _runPipeIn(_ argv: [String], stdin: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        let pipe = Pipe()
        p.standardInput = pipe
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            try pipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            try pipe.fileHandleForWriting.close()
            p.waitUntilExit()
        } catch {}
    }
    func _runPipeOut(_ argv: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

open class NSPasteboardItem: NSObject, @unchecked Sendable {
    private var storedStrings: [NSPasteboard.PasteboardType: String] = [:]
    private var storedData: [NSPasteboard.PasteboardType: Data] = [:]
    private var storedPropertyLists: [NSPasteboard.PasteboardType: Any] = [:]
    private var orderedTypes: [NSPasteboard.PasteboardType] = []

    public override init() {}

    @discardableResult
    public func setString(_ s: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        _remember(type)
        storedStrings[type] = s
        storedData[type] = Data(s.utf8)
        storedPropertyLists[type] = s
        return true
    }

    public func string(forType type: NSPasteboard.PasteboardType) -> String? {
        if let string = storedStrings[type] { return string }
        return storedData[type].flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    public func setData(_ d: Data, forType type: NSPasteboard.PasteboardType) -> Bool {
        _remember(type)
        storedData[type] = d
        storedStrings[type] = String(data: d, encoding: .utf8)
        return true
    }

    public func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        if let data = storedData[type] { return data }
        return storedStrings[type].map { Data($0.utf8) }
    }

    @discardableResult
    public func setPropertyList(_ p: Any, forType type: NSPasteboard.PasteboardType) -> Bool {
        _remember(type)
        storedPropertyLists[type] = p
        if let string = p as? String {
            storedStrings[type] = string
            storedData[type] = Data(string.utf8)
        }
        return true
    }

    public func propertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        storedPropertyLists[type]
    }

    public var types: [NSPasteboard.PasteboardType] { orderedTypes }

    private func _remember(_ type: NSPasteboard.PasteboardType) {
        if !orderedTypes.contains(type) {
            orderedTypes.append(type)
        }
    }
}

public protocol NSPasteboardWriting {}
public protocol NSPasteboardReading {}

// MARK: - NSWorkspace
//
// Phase B (real backing): file/URL opening goes through xdg-open
// (the freedesktop standard) when available. This matches Apple's
// NSWorkspace.open semantics on Linux: pick the user's configured
// default handler for the URL scheme or file MIME type. selectFile/
// activateFileViewerSelecting open the parent directory in the user's
// file manager (also via xdg-open). Icon lookup returns a standard
// icon-sized placeholder with diagnostics for now; real desktop icons need GIO
// bindings (GContentType + GIcon → file path), a separate Phase B target.

open class NSWorkspace: NSObject, @unchecked Sendable {
    public static let shared = NSWorkspace()
    public var notificationCenter = NotificationCenter()
    public var isVoiceOverEnabled: Bool = false
    public var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications()
    }

    public struct LaunchOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let `default` = LaunchOptions([])
        public static let async = LaunchOptions(rawValue: 1 << 0)
        public static let withoutActivation = LaunchOptions(rawValue: 1 << 1)
    }

    public struct LaunchConfigurationKey: Hashable, RawRepresentable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
    }

    @discardableResult
    public func open(_ url: URL) -> Bool {
        _xdgOpen(url.absoluteString, operation: "NSWorkspace.open(_:)")
    }

    public func open(_ url: URL, configuration: OpenConfiguration, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        let ok = _xdgOpen(url.absoluteString, operation: "NSWorkspace.open(_:configuration:completionHandler:)")
        completionHandler?(ok ? nil : nil, ok ? nil : NSError(domain: "QuillNSWorkspace", code: 1))
    }

    public func openApplication(at url: URL, configuration: OpenConfiguration, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        let ok = _xdgOpen(url.path, operation: "NSWorkspace.openApplication(at:configuration:completionHandler:)")
        completionHandler?(ok ? nil : nil, ok ? nil : NSError(domain: "QuillNSWorkspace", code: 1))
    }

    public func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        options: LaunchOptions = [],
        configuration: [LaunchConfigurationKey: Any] = [:]
    ) throws {
        _ = (applicationURL, options, configuration)
        for url in urls {
            _ = _xdgOpen(url.path, operation: "NSWorkspace.open(_:withApplicationAt:options:configuration:)")
        }
    }

    @discardableResult
    public func selectFile(_ path: String?, inFileViewerRootedAtPath: String) -> Bool {
        guard let p = path else {
            return _xdgOpen(inFileViewerRootedAtPath, operation: "NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)")
        }
        let dir = (p as NSString).deletingLastPathComponent
        let target = dir.isEmpty ? inFileViewerRootedAtPath : dir
        _recordFallback(
            operation: "NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)",
            severity: .warning,
            message: "NSWorkspace.selectFile opens the containing directory on Linux; selecting/highlighting '\(p)' is not implemented yet."
        )
        return _xdgOpen(target, operation: "NSWorkspace.selectFile(_:inFileViewerRootedAtPath:)")
    }

    public func activateFileViewerSelecting(_ urls: [URL]) {
        // On Apple this opens Finder with each URL highlighted. On
        // Linux we just open the containing directory of the first url.
        guard let first = urls.first else {
            _recordFallback(
                operation: "NSWorkspace.activateFileViewerSelecting(_:)",
                message: "NSWorkspace.activateFileViewerSelecting received no URLs; no Linux file viewer was opened."
            )
            return
        }
        _recordFallback(
            operation: "NSWorkspace.activateFileViewerSelecting(_:)",
            severity: .warning,
            message: "NSWorkspace.activateFileViewerSelecting opens the first containing directory on Linux; multi-selection highlighting is not implemented yet."
        )
        let parent = first.deletingLastPathComponent().path
        _ = _xdgOpen(parent, operation: "NSWorkspace.activateFileViewerSelecting(_:)")
    }

    public func icon(forFile path: String) -> NSImage {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillAppKit",
            operation: "NSWorkspace.icon(forFile:)",
            severity: .warning,
            message: "NSWorkspace.icon(forFile:) returns a 32x32 placeholder image for '\(path)' on Linux; desktop file icon lookup is not implemented yet."
        )
        return _placeholderIcon()
    }

    public func icon(forContentType type: Any) -> NSImage {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillAppKit",
            operation: "NSWorkspace.icon(forContentType:)",
            severity: .warning,
            message: "NSWorkspace.icon(forContentType:) returns a 32x32 placeholder image for '\(String(describing: type))' on Linux; desktop content-type icon lookup is not implemented yet."
        )
        return _placeholderIcon()
    }

    public func urlForApplication(toOpen: URL) -> URL? {
        guard let desktopID = _xdgMimeQueryDefault(toOpen) else {
            _recordFallback(
                operation: "NSWorkspace.urlForApplication(toOpen:)",
                message: "NSWorkspace.urlForApplication(toOpen:) could not find a Linux desktop application for '\(toOpen.absoluteString)'."
            )
            return nil
        }
        guard let url = _desktopApplicationURL(forDesktopID: desktopID) else {
            _recordFallback(
                operation: "NSWorkspace.urlForApplication(toOpen:)",
                message: "NSWorkspace.urlForApplication(toOpen:) resolved desktop id '\(desktopID)' but could not find a matching .desktop file."
            )
            return nil
        }
        return url
    }
    public func urlForApplication(withBundleIdentifier id: String) -> URL? {
        guard let url = _desktopApplicationURL(forDesktopID: id) else {
            _recordFallback(
                operation: "NSWorkspace.urlForApplication(withBundleIdentifier:)",
                message: "NSWorkspace.urlForApplication(withBundleIdentifier:) maps bundle identifiers to existing Linux .desktop files only; no entry was found for '\(id)'."
            )
            return nil
        }
        return url
    }

    public class OpenConfiguration: NSObject, @unchecked Sendable {
        public override init() {}
        public var arguments: [String] = []
        public var environment: [String: String] = [:]
        public var activates: Bool = true
    }
}

open class NSRunningApplication: NSObject, @unchecked Sendable {
    public struct ActivationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let activateAllWindows = ActivationOptions(rawValue: 1 << 0)
        public static let activateIgnoringOtherApps = ActivationOptions(rawValue: 1 << 1)
    }

    public static var current: NSRunningApplication {
        // NSApp is @MainActor (#512); app-state reads run on the main loop.
        let active = MainActor.assumeIsolated { NSApp.isActive }
        return NSRunningApplication(bundleIdentifier: Bundle.main.bundleIdentifier, localizedName: ProcessInfo.processInfo.processName, isActive: active)
    }

    public private(set) var bundleIdentifier: String?
    public private(set) var localizedName: String?
    public private(set) var processIdentifier: pid_t
    public var isActive: Bool

    public init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        localizedName: String? = ProcessInfo.processInfo.processName,
        processIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        isActive: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.isActive = isActive
        super.init()
    }

    public class func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [NSRunningApplication] {
        let current = NSRunningApplication.current
        guard current.bundleIdentifier == bundleIdentifier else { return [] }
        return [current]
    }

    public class func runningApplications() -> [NSRunningApplication] {
        [current]
    }

    @discardableResult
    public func activate(options: ActivationOptions = []) -> Bool {
        _ = options
        isActive = true
        let ignoring = options.contains(.activateIgnoringOtherApps)
        MainActor.assumeIsolated { NSApp.activate(ignoringOtherApps: ignoring) }
        return true
    }
}

private extension NSWorkspace {
    func _placeholderIcon() -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32))
    }

    @discardableResult
    func _xdgOpen(_ target: String, operation: String) -> Bool {
        let url = _workspaceOpenURL(for: target)
        let didOpen = QuillWorkspace.open(url)
        if !didOpen {
            _recordFallback(
                operation: operation,
                message: "\(operation) could not open '\(target)' through QuillWorkspace."
            )
        }

        return didOpen
    }
    func _workspaceOpenURL(for target: String) -> URL {
        if let url = URL(string: target), url.scheme?.isEmpty == false {
            return url
        }

        return URL(fileURLWithPath: target)
    }
    func _xdgMimeQueryDefault(_ url: URL) -> String? {
        guard _hasCommand("xdg-mime") else { return nil }
        if url.isFileURL {
            return _runForOutput(["xdg-mime", "query", "default", _xdgMimeForFile(url.path) ?? ""])
        }
        if let scheme = url.scheme {
            return _runForOutput(["xdg-mime", "query", "default", "x-scheme-handler/\(scheme)"])
        }
        return nil
    }
    func _xdgMimeForFile(_ path: String) -> String? {
        guard _hasCommand("xdg-mime") else { return nil }
        return _runForOutput(["xdg-mime", "query", "filetype", path])
    }
    func _desktopApplicationURL(forDesktopID id: String) -> URL? {
        if id.hasPrefix("/"), FileManager.default.fileExists(atPath: id) {
            return URL(fileURLWithPath: id)
        }
        let names = id.hasSuffix(".desktop") ? [id] : [id, "\(id).desktop"]
        for directory in _xdgApplicationDirectories() {
            for name in names {
                let path = (directory as NSString).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }
    func _xdgApplicationDirectories() -> [String] {
        let env = ProcessInfo.processInfo.environment
        var directories: [String] = []
        if let dataHome = env["XDG_DATA_HOME"], !dataHome.isEmpty {
            directories.append((dataHome as NSString).appendingPathComponent("applications"))
        } else if let home = env["HOME"], !home.isEmpty {
            directories.append((home as NSString).appendingPathComponent(".local/share/applications"))
        }

        let dataDirs = env["XDG_DATA_DIRS"]?.split(separator: ":").map(String.init)
            ?? ["/usr/local/share", "/usr/share"]
        directories.append(contentsOf: dataDirs.map { ($0 as NSString).appendingPathComponent("applications") })

        var seen: Set<String> = []
        return directories.filter { seen.insert($0).inserted }
    }
    func _recordFallback(operation: String, severity: QuillCompatibilityEvent.Severity = .unsupported, message: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillAppKit",
            operation: operation,
            severity: severity,
            message: message
        )
    }
    func _hasCommand(_ name: String) -> Bool {
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            if FileManager.default.isExecutableFile(atPath: "\(dir)/\(name)") { return true }
        }
        return false
    }
    func _runForOutput(_ argv: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty == false) ? s : nil
        } catch { return nil }
    }
}

// MARK: - NSCursor

open class NSCursor: NSObject {
    public static let arrow = NSCursor()
    public static let crosshair = NSCursor()
    public static let closedHand = NSCursor()
    public static let openHand = NSCursor()
    public static let pointingHand = NSCursor()
    public static let resizeLeft = NSCursor()
    public static let resizeRight = NSCursor()
    public static let resizeLeftRight = NSCursor()
    public static let resizeUp = NSCursor()
    public static let resizeDown = NSCursor()
    public static let resizeUpDown = NSCursor()
    public static let iBeam = NSCursor()
    public static let iBeamCursorForVerticalLayout = NSCursor()
    public static let operationNotAllowed = NSCursor()
    public static let dragLink = NSCursor()
    public static let dragCopy = NSCursor()
    public static let contextualMenu = NSCursor()
    public static let disappearingItem = NSCursor()
    public static var current: NSCursor { arrow }

    public override init() {}
    public init(image: NSImage, hotSpot: NSPoint) {}
    public func push() {}
    public func pop() {}
    public func set() {}
    public static func pop() {}
    public static func hide() {}
    public static func unhide() {}
    public static func setHiddenUntilMouseMoves(_ flag: Bool) {}
}

// MARK: - NSAttributedString helpers
//
// Linux Foundation already declares `NSAttributedString.Key` (it's a
// pure-Foundation type). We just extend it with the AppKit-side static
// Shared text-layout types (NSTextAlignment/NSParagraphStyle/NSUnderlineStyle/
// NSStringDrawing*/NSAttributedString.Key additions) moved to QuillFoundation
// (NSTextLayoutShared.swift) — single canonical declarations that both this
// module and the UIKit shim @_exported-import, so files seeing both worlds
// (SwiftUI re-exports AppKit; Signal imports SwiftUI + UIKit) hit no
// ambiguity. NSTextStorage stays here: its members are AppKit-flavored.




private func quillEstimatedAppKitTextRect(
    _ string: String,
    proposed size: NSSize,
    attributes: [NSAttributedString.Key: Any]?
) -> NSRect {
    let fontSize = (attributes?[.font] as? NSFont)?.pointSize ?? 13
    let characterWidth = max(1, fontSize * 0.6)
    let lineHeight = max(1, fontSize * 1.2)
    let rawWidth = CGFloat(string.count) * characterWidth
    let proposedWidth = size.width.isFinite ? max(1, size.width) : rawWidth
    let width = min(proposedWidth, max(rawWidth, characterWidth))
    let lines = max(1, ceil(rawWidth / max(1, width)))
    let proposedHeight = size.height.isFinite ? size.height : CGFloat.greatestFiniteMagnitude
    return NSRect(x: 0, y: 0, width: width, height: min(proposedHeight, lines * lineHeight))
}

public extension NSString {
    func boundingRect(
        with size: NSSize,
        options: NSStringDrawingOptions = [],
        attributes: [NSAttributedString.Key: Any]? = nil,
        context: NSStringDrawingContext? = nil
    ) -> NSRect {
        _ = (options, context)
        return quillEstimatedAppKitTextRect(self as String, proposed: size, attributes: attributes)
    }
}


open class NSTextAttachment: NSObject {
    public var image: NSImage?
    public var bounds: NSRect = .zero
    public var contents: Data?
    public var fileType: String?

    public override init() {
        super.init()
    }

    public init(data contentData: Data?, ofType uti: String?) {
        self.contents = contentData
        self.fileType = uti
        super.init()
    }

    public required init?(coder: NSCoder) {
        super.init()
    }
}

public extension NSAttributedString {
    convenience init?(rtf data: Data, documentAttributes dict: UnsafeMutablePointer<NSDictionary?>?) {
        _ = dict
        self.init(string: String(data: data, encoding: .utf8) ?? "")
    }

    convenience init(attachment: NSTextAttachment) {
        self.init(string: "\u{FFFC}", attributes: [.attachment: attachment])
    }

    func boundingRect(with size: NSSize, options: NSStringDrawingOptions = []) -> NSRect {
        _ = options
        let rawWidth = CGFloat(length) * 7
        let width = min(size.width, rawWidth)
        let lines = max(1, ceil(rawWidth / max(1, size.width)))
        return NSRect(x: 0, y: 0, width: width, height: min(size.height, lines * 14))
    }

    func boundingRect(with size: NSSize, options: NSStringDrawingOptions = [], context: Any?) -> NSRect {
        _ = context
        return boundingRect(with: size, options: options)
    }

    func doubleClick(at index: Int) -> NSRange {
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        let clamped = Swift.max(0, Swift.min(index, length - 1))
        let text = string as NSString
        let separators = CharacterSet.whitespacesAndNewlines
        var start = clamped
        var end = clamped
        while start > 0 {
            let scalar = UnicodeScalar(text.character(at: start - 1))
            if scalar.map({ separators.contains($0) }) ?? false { break }
            start -= 1
        }
        while end < length {
            let scalar = UnicodeScalar(text.character(at: end))
            if scalar.map({ separators.contains($0) }) ?? false { break }
            end += 1
        }
        return NSRange(location: start, length: Swift.max(0, end - start))
    }
}






open class NSBezierPath: NSObject, @unchecked Sendable {
    public enum Element: Int, Sendable {
        case moveTo, lineTo, curveTo, closePath
    }

    private var elements: [(Element, [NSPoint])] = []
    open var lineWidth: CGFloat = 1
    open var elementCount: Int { elements.count }

    public override init() {}

    open func move(to point: NSPoint) {
        elements.append((.moveTo, [point]))
    }

    open func line(to point: NSPoint) {
        elements.append((.lineTo, [point]))
    }

    open func curve(to endPoint: NSPoint, controlPoint1: NSPoint, controlPoint2: NSPoint) {
        elements.append((.curveTo, [controlPoint1, controlPoint2, endPoint]))
    }

    open func close() {
        elements.append((.closePath, []))
    }

    open func appendRect(_ rect: NSRect) {
        move(to: NSPoint(x: rect.minX, y: rect.minY))
        line(to: NSPoint(x: rect.maxX, y: rect.minY))
        line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        line(to: NSPoint(x: rect.minX, y: rect.maxY))
        close()
    }

    open func appendOval(in rect: NSRect) {
        appendRect(rect)
    }

    open func append(_ path: NSBezierPath) {
        elements.append(contentsOf: path.elements)
    }

    open func element(at index: Int, associatedPoints points: UnsafeMutablePointer<NSPoint>?) -> Element {
        guard elements.indices.contains(index) else { return .closePath }
        let element = elements[index]
        for (pointIndex, point) in element.1.enumerated() {
            points?.advanced(by: pointIndex).pointee = point
        }
        return element.0
    }

    open func fill() {}
    open func stroke() {}
}

open class NSAffineTransform: NSObject, @unchecked Sendable {
    public override init() {}
    open func rotate(byDegrees angle: CGFloat) { _ = angle }
    open func translateX(by deltaX: CGFloat, yBy deltaY: CGFloat) { _ = (deltaX, deltaY) }
    open func scaleX(by scaleX: CGFloat, yBy scaleY: CGFloat) { _ = (scaleX, scaleY) }
    open func transform(_ path: NSBezierPath) -> NSBezierPath { path }
}

open class NSShadow: NSObject, @unchecked Sendable {
    open var shadowColor: NSColor?
    open var shadowOffset: NSSize = .zero
    open var shadowBlurRadius: CGFloat = 0

    public override init() {}
    open func set() {}
}

// MARK: - NSMenu / NSMenuItem

// Apple parity (#512). The existing MainActor.assumeIsolated bridges around
// delegate calls inside this class become load-bearing once NSMenuDelegate is
// isolated in the follow-up sweep.
@preconcurrency @MainActor
open class NSMenu: NSObject, @preconcurrency QuillSelectorDispatching {
    /// Linux target-action dispatch base (no ObjC runtime); roots the override
    /// chain for `@objc`-action NSMenu subclasses. Class-body, not an extension.
    /// See QuillSelectorDispatching (QuillFoundation).
    open func quillPerform(_ selector: Selector, with sender: Any?) {}

    public var title: String = ""
    open var items: [NSMenuItem] = []
    public weak var delegate: NSMenuDelegate?
    public var supermenu: NSMenu?
    public var autoenablesItems: Bool = true
    public var minimumWidth: CGFloat = 0
    public var font: NSFont?
    public var allowsContextMenuPlugIns: Bool = true
    public private(set) var isTracking: Bool = false
    public private(set) var lastPopUpPositioningItem: NSMenuItem?
    public private(set) var lastPopUpLocation: NSPoint = .zero
    public private(set) weak var lastPopUpView: NSView?

    // init(title:) is the designated init (as on macOS); init() is convenience.
    // This lets NSMenu subclasses (MainMenu/StatusMenu) declare their own `init()`
    // as a new designated init calling super.init(title:) WITHOUT an `override`
    // keyword — matching the unmodified upstream source.
    public init(title: String) { super.init(); self.title = title }
    public override convenience init() { self.init(title: "") }
    open func addItem(_ i: NSMenuItem) {
        i.menu = self
        items.append(i)
    }
    public func addItem(withTitle title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        addItem(item)
        return item
    }
    public func insertItem(_ i: NSMenuItem, at idx: Int) {
        i.menu = self
        items.insert(i, at: idx)
    }
    public func insertItem(
        withTitle title: String,
        action: Selector?,
        keyEquivalent: String,
        at index: Int
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        insertItem(item, at: index)
        return item
    }
    public func removeItem(_ i: NSMenuItem) {
        items.removeAll { $0 === i }
        if i.menu === self { i.menu = nil }
    }
    /// Number of items (WireGuard's StatusMenu uses it to compute insert indices).
    public var numberOfItems: Int { items.count }
    /// Remove the item at `index` (WireGuard's StatusMenu rebuilds the per-tunnel rows).
    public func removeItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        let i = items.remove(at: index)
        if i.menu === self { i.menu = nil }
    }
    /// The item at `index`, or nil if out of range.
    public func item(at index: Int) -> NSMenuItem? {
        items.indices.contains(index) ? items[index] : nil
    }
    public func removeAllItems() {
        for item in items where item.menu === self {
            item.menu = nil
        }
        items.removeAll()
    }
    public func indexOfItem(_ i: NSMenuItem) -> Int { items.firstIndex { $0 === i } ?? -1 }
    public func setSubmenu(_ menu: NSMenu?, for item: NSMenuItem) {
        let replacementIsSame = menu.map { replacement in
            item.submenu === replacement
        } ?? false
        if let oldSubmenu = item.submenu, oldSubmenu.supermenu === self, !replacementIsSame {
            oldSubmenu.supermenu = nil
        }
        item.submenu = menu
        menu?.supermenu = self
    }
    public func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
        lastPopUpPositioningItem = item
        lastPopUpLocation = location
        lastPopUpView = view
        update()
        isTracking = true
        // AppKit invokes menu delegates on the main thread; assumeIsolated is
        // the same bridge NSApplication.sendEvent uses for responder calls.
        if let delegate {
            MainActor.assumeIsolated { delegate.menuWillOpen(self) }
        }
        return true
    }
    public func cancelTracking() {
        guard isTracking else { return }
        isTracking = false
        if let delegate {
            MainActor.assumeIsolated { delegate.menuDidClose(self) }
        }
    }
    public func update() {
        if let delegate {
            MainActor.assumeIsolated {
                _ = delegate.numberOfItems(in: self)
                delegate.menuNeedsUpdate(self)
            }
        }
        for (index, item) in items.enumerated() {
            if let delegate {
                MainActor.assumeIsolated {
                    _ = delegate.menu(self, update: item, at: index, shouldCancel: false)
                }
            }
            if autoenablesItems, let validator = item.target as? NSMenuItemValidation {
                item.isEnabled = validator.validateMenuItem(item)
            }
        }
    }
    public static var menuBarVisible: Bool = true
    open class func popUpContextMenu(_ menu: NSMenu, with event: NSEvent, for view: NSView) {
        _ = menu.popUp(positioning: nil, at: event.locationInWindow, in: view)
    }
}

// Apple parity (#512).
@preconcurrency @MainActor
open class NSMenuItem: NSObject, @preconcurrency QuillSelectorDispatching {
    /// Linux target-action dispatch base (no ObjC runtime); roots the override
    /// chain for `@objc`-action NSMenuItem subclasses (WireGuard's StatusMenu
    /// items). Class-body, not an extension. See QuillSelectorDispatching
    /// (QuillFoundation).
    open func quillPerform(_ selector: Selector, with sender: Any?) {}

    open var title: String = ""
    public var action: Selector?
    public weak var target: AnyObject?
    public var keyEquivalent: String = ""
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags = .command
    public var image: NSImage?
    public var onStateImage: NSImage?
    public var offStateImage: NSImage?
    public var mixedStateImage: NSImage?
    public var state: StateValue = .off
    public var isEnabled: Bool = true
    public var isHidden: Bool = false
    public var isAlternate: Bool = false
    public var indentationLevel: Int = 0
    public var tag: Int = 0
    public var representedObject: Any?
    public var submenu: NSMenu?
    public weak var menu: NSMenu?
    public var attributedTitle: NSAttributedString?
    public var toolTip: String?
    public var view: NSView?
    public var identifier: NSUserInterfaceItemIdentifier?

    public typealias StateValue = NSControl.StateValue

    public init(title: String, action: Selector?, keyEquivalent: String) {
        super.init()
        self.title = title; self.action = action; self.keyEquivalent = keyEquivalent
    }
    public override init() { super.init() }
    // WireGuard's MainMenu/StatusMenu build separators with `NSMenuItem.separator()`
    // (the call form). Was a `static var separator` property (unused in-tree) — now a
    // func so those call sites resolve. separatorItem() kept as the legacy alias.
    public static func separator() -> NSMenuItem { NSMenuItem() }
    public static func separatorItem() -> NSMenuItem { NSMenuItem() }
    open var isSeparatorItem: Bool { false }
}

@preconcurrency @MainActor
public protocol NSMenuDelegate: AnyObject {
    func menuWillOpen(_ menu: NSMenu)
    func menuDidClose(_ menu: NSMenu)
    func numberOfItems(in menu: NSMenu) -> Int
    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool
    func menuNeedsUpdate(_ menu: NSMenu)
}
public extension NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {}
    func menuDidClose(_ menu: NSMenu) {}
    func numberOfItems(in menu: NSMenu) -> Int { 0 }
    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool { false }
    func menuNeedsUpdate(_ menu: NSMenu) {}
}

public protocol NSMenuItemValidation: AnyObject {
    func validateMenuItem(_ item: NSMenuItem) -> Bool
}

// MARK: - NSToolbar / NSToolbarItem

// Apple parity (#512); makes the existing per-member @MainActor annotations
// inside redundant (harmless).
@preconcurrency @MainActor
open class NSToolbar: NSObject {
    public var identifier: String = ""
    public weak var delegate: NSToolbarDelegate?
    public var displayMode: DisplayMode = .default
    public var sizeMode: SizeMode = .default
    public var allowsUserCustomization: Bool = false
    public var autosavesConfiguration: Bool = false
    public var isVisible: Bool = true
    public var items: [NSToolbarItem] = []
    public var visibleItems: [NSToolbarItem]? = nil
    public var allowsExtensionItems: Bool = false
    public var selectedItemIdentifier: NSToolbarItem.Identifier?
    public var centeredItemIdentifier: NSToolbarItem.Identifier?
    public var centeredItemIdentifiers: Set<NSToolbarItem.Identifier> = []
    public var showsBaselineSeparator: Bool = true

    public enum DisplayMode: UInt, Sendable { case `default`, iconAndLabel, iconOnly, labelOnly }
    public enum SizeMode: UInt, Sendable { case `default`, regular, small }

    public override init() { super.init() }
    public init(identifier: String) { super.init(); self.identifier = identifier }
    @MainActor
    public func insertItem(withItemIdentifier id: NSToolbarItem.Identifier, at idx: Int) {
        guard let item = delegate?.toolbar(self, itemForItemIdentifier: id, willBeInsertedIntoToolbar: true) else {
            return
        }
        let insertionIndex = max(0, min(idx, items.count))
        items.insert(item, at: insertionIndex)
        visibleItems = items
    }
    public func removeItem(at idx: Int) {
        guard items.indices.contains(idx) else { return }
        let removedItem = items.remove(at: idx)
        if selectedItemIdentifier == removedItem.itemIdentifier {
            selectedItemIdentifier = nil
        }
        visibleItems = items
    }
    @MainActor
    public func validateVisibleItems() {
        visibleItems = items
    }
}

// Apple parity (#512); NSTrackingSeparatorToolbarItem/NSToolbarItemGroup inherit.
@preconcurrency @MainActor
open class NSToolbarItem: NSObject {
    public struct Identifier: RawRepresentable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let flexibleSpace = Identifier(rawValue: "NSToolbarFlexibleSpaceItem")
        public static let space = Identifier(rawValue: "NSToolbarSpaceItem")
        public static let toggleSidebar = Identifier(rawValue: "NSToolbarToggleSidebarItem")
        public static let sidebarTrackingSeparator = Identifier(rawValue: "NSToolbarSidebarTrackingSeparatorItem")
        public static let cloudSharing = Identifier(rawValue: "NSToolbarCloudSharingItem")
        public static let print = Identifier(rawValue: "NSToolbarPrintItem")
        public static let showColors = Identifier(rawValue: "NSToolbarShowColorsItem")
        public static let showFonts = Identifier(rawValue: "NSToolbarShowFontsItem")
    }
    public var itemIdentifier: Identifier = Identifier(rawValue: "")
    public var label: String = ""
    public var paletteLabel: String = ""
    public var toolTip: String?
    public var image: NSImage?
    public var view: NSView?
    public var menuFormRepresentation: NSMenuItem?
    public weak var target: AnyObject?
    public var action: Selector?
    public var isEnabled: Bool = true
    public var visibilityPriority: Int = 0
    public var minSize: NSSize = .zero
    public var maxSize: NSSize = .zero
    public var bordered: Bool = true
    public var isBordered: Bool = true
    public var isNavigational: Bool = false
    public var possibleLabels: Set<String> = []

    public override init() { super.init() }
    public init(itemIdentifier: Identifier) { super.init(); self.itemIdentifier = itemIdentifier }
}

open class NSTrackingSeparatorToolbarItem: NSToolbarItem {}
open class NSToolbarItemGroup: NSToolbarItem {
    public var subitems: [NSToolbarItem] = []
    public var selectionMode: SelectionMode = .momentary
    public var controlRepresentation: ControlRepresentation = .automatic
    public enum SelectionMode: Int, Sendable { case selectOne, selectAny, momentary }
    public enum ControlRepresentation: Int, Sendable { case automatic, expanded, collapsed }
}

@preconcurrency @MainActor public protocol NSToolbarDelegate: AnyObject {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier]
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem?
}
public extension NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? { nil }
}

// MARK: - NSAlert / NSSavePanel / NSOpenPanel

// Apple parity (#512).
@preconcurrency @MainActor
open class NSAlert: NSObject, @preconcurrency QuillSelectorDispatching {
    /// Linux target-action dispatch base (no ObjC runtime); roots the override
    /// chain for `@objc`-action NSAlert subclasses. Class-body, not an extension.
    /// See QuillSelectorDispatching (QuillFoundation).
    open func quillPerform(_ selector: Selector, with sender: Any?) {}

    public var messageText: String = ""
    public var informativeText: String = ""
    public var icon: NSImage?
    public var alertStyle: Style = .informational
    public var showsHelp: Bool = false
    public var helpAnchor: String?
    /// The alert's panel window. Non-optional to match Apple's `NSAlert.window`
    /// (e.g. `alert.window.sheetParent` in WireGuard's DeleteTunnelsConfirmationAlert);
    /// a lazily-created compile-only stub on Linux (no real panel is shown).
    public lazy var window: NSWindow = NSWindow()
    public var buttons: [NSButton] = []
    public var accessoryView: NSView?
    public var showsSuppressionButton: Bool = false
    public var suppressionButton: NSButton?
    private var _buttonTitles: [String] = []

    public enum Style: UInt, Sendable { case warning, informational, critical }

    public override init() { super.init() }
    public convenience init(error: any Error) {
        self.init()
        self.alertStyle = .critical
        self.messageText = (error as NSError).localizedDescription
    }
    public func addButton(withTitle title: String) -> NSButton {
        let b = NSButton()
        b.title = title
        buttons.append(b)
        _buttonTitles.append(title)
        return b
    }

    /// Phase B: prints the alert to stderr and reads a digit from stdin
    /// to pick a button. If stdin isn't a TTY, returns the first
    /// button's response (matches Apple's "default" button semantics
    /// for unattended runs).
    public func runModal() -> NSApplication.ModalResponse {
        quillApplyAccessoryTextOverride()
        if let overrideResponse = quillModalResponseOverride() {
            return overrideResponse
        }

        let prefix: String
        switch alertStyle {
        case .critical:      prefix = "[!] "
        case .warning:       prefix = "[?] "
        case .informational: prefix = "[i] "
        }
        var lines = ["\n\(prefix)\(messageText)"]
        if !informativeText.isEmpty { lines.append("    \(informativeText)") }
        if _buttonTitles.isEmpty {
            lines.append("    [press enter to continue]")
        } else {
            for (i, t) in _buttonTitles.enumerated() {
                let marker = (i == 0) ? "*" : " "
                lines.append("   \(marker) \(i + 1)) \(t)")
            }
            lines.append("    choose: ")
        }
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))

        guard isatty(0) != 0,
              let line = readLine(),
              let pick = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)),
              pick >= 1, pick <= max(_buttonTitles.count, 1) else {
            // No interactive stdin → default button (first one).
            return .alertFirstButtonReturn
        }
        switch pick {
        case 1: return .alertFirstButtonReturn
        case 2: return .alertSecondButtonReturn
        case 3: return .alertThirdButtonReturn
        default: return .alertFirstButtonReturn
        }
    }

    public func beginSheetModal(for window: NSWindow, completionHandler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        let response = runModal()
        completionHandler?(response)
    }

    private func quillModalResponseOverride() -> NSApplication.ModalResponse? {
        let environment = ProcessInfo.processInfo.environment
        guard let rawValue = environment["QUILLUI_NSALERT_RESPONSE"] ?? environment["QUILLUI_NSALERT_BUTTON"] else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let numericValue = Int(trimmed) {
            if numericValue <= 0 || numericValue >= 1000 {
                return NSApplication.ModalResponse(rawValue: numericValue)
            }
            return quillAlertButtonResponse(atOneBasedIndex: numericValue)
        }

        if let index = _buttonTitles.firstIndex(where: { trimmed.caseInsensitiveCompare($0) == .orderedSame }) {
            return quillAlertButtonResponse(atOneBasedIndex: index + 1)
        }

        switch trimmed.lowercased() {
        case "default", "first", "ok", "apply":
            return .alertFirstButtonReturn
        case "second":
            return .alertSecondButtonReturn
        case "third":
            return .alertThirdButtonReturn
        case "cancel":
            if let index = _buttonTitles.firstIndex(where: { $0.caseInsensitiveCompare("Cancel") == .orderedSame }) {
                return quillAlertButtonResponse(atOneBasedIndex: index + 1)
            }
            return .cancel
        default:
            return nil
        }
    }

    private func quillAlertButtonResponse(atOneBasedIndex index: Int) -> NSApplication.ModalResponse {
        switch index {
        case 1: return .alertFirstButtonReturn
        case 2: return .alertSecondButtonReturn
        case 3: return .alertThirdButtonReturn
        default: return NSApplication.ModalResponse(rawValue: 999 + index)
        }
    }

    private func quillApplyAccessoryTextOverride() {
        let environment = ProcessInfo.processInfo.environment
        guard let accessoryText = environment["QUILLUI_NSALERT_ACCESSORY_TEXT"] else { return }
        quillFirstTextField(in: accessoryView)?.stringValue = accessoryText
    }

    private func quillFirstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let textField = view as? NSTextField {
            return textField
        }
        for subview in view.subviews {
            if let textField = quillFirstTextField(in: subview) {
                return textField
            }
        }
        return nil
    }
}

open class NSSavePanel: NSWindow {
    public var url: URL?
    public var directoryURL: URL?
    public var nameFieldStringValue: String = ""
    public var nameFieldLabel: String?
    public var allowedContentTypes: [Any] = []
    public var allowedFileTypes: [String]?
    public var canCreateDirectories: Bool = true
    public var showsHiddenFiles: Bool = false
    public var canSelectHiddenExtension: Bool = false
    public var isExtensionHidden: Bool = false
    public var prompt: String?
    public var message: String?
    public var accessoryView: NSView?
    public var treatsFilePackagesAsDirectories: Bool = false
    public var allowsOtherFileTypes: Bool = false
    open func runModal() -> NSApplication.ModalResponse { .OK }
    open func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
        completionHandler(runModal())
    }
    open func beginSheetModal(for window: NSWindow, completionHandler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        completionHandler?(runModal())
    }
}

open class NSOpenPanel: NSSavePanel {
    public var canChooseFiles: Bool = true
    public var canChooseDirectories: Bool = false
    public var allowsMultipleSelection: Bool = false
    public var resolvesAliases: Bool = true
    public var urls: [URL] = []

    open override func runModal() -> NSApplication.ModalResponse { .cancel }
}

// MARK: - NSScrollView / NSScroller / NSTextField / NSTextView / NSImageView / NSButton / NSPopUpButton / NSSearchField / NSSplitView / NSSlider

open class NSScrollView: NSView {
    public static let willStartLiveScrollNotification = Notification.Name("NSScrollViewWillStartLiveScrollNotification")
    public static let didLiveScrollNotification = Notification.Name("NSScrollViewDidLiveScrollNotification")
    public static let didEndLiveScrollNotification = Notification.Name("NSScrollViewDidEndLiveScrollNotification")

    public enum Elasticity: Int, Sendable {
        case automatic, none, allowed
    }

    /// Whether the scroll view paints its background. WireGuard's TunnelDetail table
    /// sets it false for a transparent detail view. Compile-stub (stored).
    open var drawsBackground: Bool = true
    open var backgroundColor: NSColor = .clear
    open var contentView: NSClipView = NSClipView() {
        didSet {
            quillInstallContentView(replacing: oldValue)
        }
    }
    open var documentView: NSView? {
        get { contentView.documentView }
        set {
            let oldValue = contentView.documentView
            if oldValue !== newValue {
                oldValue?.removeFromSuperview()
            }
            contentView.documentView = newValue
            guard let newValue else { return }
            if newValue.superview !== contentView {
                contentView.addSubview(newValue)
            }
        }
    }
    open var hasVerticalScroller: Bool = false
    open var hasHorizontalScroller: Bool = false
    open var verticalScroller: NSScroller?
    open var horizontalScroller: NSScroller?
    open var autohidesScrollers: Bool = true
    open var scrollerStyle: NSScroller.Style = .overlay
    open var borderType: NSBorderType = .noBorder
    open var verticalScrollElasticity: Elasticity = .automatic
    open var horizontalScrollElasticity: Elasticity = .automatic
    public var hasMagnification: Bool = false
    public var allowsMagnification: Bool = false
    public var magnification: CGFloat = 1
    public var minMagnification: CGFloat = 0.25
    public var maxMagnification: CGFloat = 4.0
    public var contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    public var automaticallyAdjustsContentInsets: Bool = true
    public convenience init() { self.init(frame: .zero) }
    // nonisolated (overrides NSView's nonisolated init(frame:)); the clip-view
    // install touches the subview tree — main-thread hop, AppKit contract.
    nonisolated public override init(frame: NSRect) {
        super.init(frame: frame)
        MainActor.assumeIsolated {
            quillInstallContentView()
        }
    }
    /// Required NSCoding init (NSView's coder init is `required`; declaring a
    /// designated init suppresses inheritance). Coder ignored — mirrors
    /// `init(frame:)` so the clip view is still installed. Class-isolated, so
    /// the install needs no hop.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        quillInstallContentView()
    }
    public func flashScrollers() {}
    open func tile() {}
    open func reflectScrolledClipView(_ clipView: NSClipView) { _ = clipView }
    private func quillInstallContentView(replacing oldValue: NSClipView? = nil) {
        if let oldValue, oldValue !== contentView {
            oldValue.removeFromSuperview()
        }
        if contentView.superview !== self {
            addSubview(contentView)
        }
    }
}

public enum NSBorderType: UInt, Sendable {
    case noBorder, lineBorder, bezelBorder, grooveBorder
}

/// Mirrors `NSBox`: a titled/bordered container. COMPILE-stub — properties are
/// stored (defaults let it inherit NSView's initializers, so `NSBox()` works);
/// a Qt backing (QGroupBox/QFrame) is a follow-up.
open class NSBox: NSView {
    public enum BoxType: UInt, Sendable { case primary, secondary, separator, oldStyle, custom }
    public enum TitlePosition: UInt, Sendable {
        case noTitle, aboveTop, atTop, belowTop, aboveBottom, atBottom, belowBottom
    }
    public enum BorderType: UInt, Sendable { case noBorder, lineBorder, bezelBorder, grooveBorder }

    public var boxType: BoxType = .primary
    public var titlePosition: TitlePosition = .atTop
    public var borderType: BorderType = .lineBorder
    public var title: String = ""
    public var titleFont: NSFont?
    public var fillColor: NSColor = NSColor()
    public var borderColor: NSColor = NSColor()
    public var borderWidth: CGFloat = 0
    public var cornerRadius: CGFloat = 0
    public var isTransparent: Bool = false
    public var contentViewMargins: NSSize = NSSize(width: 0, height: 0)
    public var contentView: NSView? {
        didSet { if let v = contentView { addSubview(v) } }
    }
    public func sizeToFit() {}
}

open class NSClipView: NSView {
    public var documentView: NSView? {
        didSet {
            // AppKit keeps the documentView inside the clip view's subview tree.
            // The shadow must too, so the Qt render pass (which walks `subviews`)
            // reaches it — VCs like WireGuard's TunnelsList/LogView set
            // `clipView.documentView = tableView` DIRECTLY, bypassing
            // NSScrollView.documentView's setter, so without this the document
            // (the whole table) is dropped from the rendered tree. Mirrors
            // NSScrollView.documentView's wiring.
            if oldValue !== documentView {
                oldValue?.removeFromSuperview()
            }
            if let documentView, documentView.superview !== self {
                addSubview(documentView)
            }
        }
    }
    open var backgroundColor: NSColor = .clear
    open var documentRect: NSRect = .zero
    open override var documentVisibleRect: NSRect {
        get { documentRect == .zero ? bounds : documentRect }
        set { documentRect = newValue }
    }
    open var contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    open func autoscroll(with event: NSEvent) -> Bool {
        _ = event
        return false
    }
}

open class NSScroller: NSView {
    public enum Style: Int, Sendable { case legacy, overlay }
    open var scrollerStyle: Style = .overlay
    public static var preferredScrollerStyle: Style { .overlay }
    open func drawKnob() {}
}

open class NSTextField: NSControl {
    public var font: NSFont?
    public var placeholderString: String?
    public var placeholderAttributedString: NSAttributedString?
    public var isEditable: Bool = false
    public var isSelectable: Bool = true
    public var isBordered: Bool = false
    public var isBezeled: Bool = false
    public var bezelStyle: BezelStyle = .squareBezel
    public var drawsBackground: Bool = false
    public var backgroundColor: NSColor?
    public var textColor: NSColor?
    public var alignment: NSTextAlignment = .natural
    public var maximumNumberOfLines: Int = 0
    public var lineBreakMode: NSLineBreakMode = .byTruncatingTail
    public var allowsDefaultTighteningForTruncation: Bool = false
    public var preferredMaxLayoutWidth: CGFloat = 0
    public weak var delegate: NSTextFieldDelegate?
    public var usesSingleLineMode: Bool = false

    /// AppKit labels/fields size to their text. Without this the Qt layout pass's
    /// intrinsic-size fallback skips the field, so it collapses to 0×0 inside an
    /// NSStackView (which positions its children purely by solved constraints).
    /// Estimate from the string (NSFont metrics are compile-only stubs here):
    /// ~7pt/char wide, ~17pt line height; a wrapping label (byWordWrapping) bounds
    /// the width to preferredMaxLayoutWidth and grows in line-height steps.
    /// Faithful text metrics (QuillTypography) refine this in a later paint rung.
    open override var intrinsicContentSize: NSSize {
        let estimatedWidth = CGFloat(stringValue.count) * 7.0
        let lineHeight: CGFloat = 17
        if lineBreakMode == .byWordWrapping {
            let bound = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : 320
            let lines = max(1, Int((estimatedWidth / bound).rounded(.up)))
            return NSSize(width: min(estimatedWidth, bound), height: CGFloat(lines) * lineHeight)
        }
        return NSSize(width: estimatedWidth, height: lineHeight)
    }

    public enum BezelStyle: UInt, Sendable { case squareBezel, roundedBezel }

    public convenience init(labelWithString string: String) {
        self.init()
        applyLabelDefaults(string: string, selectable: false, lineBreakMode: .byClipping)
    }

    public convenience init(wrappingLabelWithString string: String) {
        self.init()
        applyLabelDefaults(string: string, selectable: true, lineBreakMode: .byWordWrapping)
    }

    public convenience init(labelWithAttributedString attributedString: NSAttributedString) {
        self.init()
        applyLabelDefaults(string: attributedString.string, selectable: false, lineBreakMode: .byClipping)
        attributedStringValue = attributedString
    }

    public convenience init(string: String) {
        self.init()
        stringValue = string
        isEditable = true
        isSelectable = true
        isBordered = false
        isBezeled = true
        drawsBackground = true
        lineBreakMode = .byClipping
    }

    public static func labelWithString(_ s: String) -> NSTextField {
        NSTextField(labelWithString: s)
    }

    public static func wrappingLabelWithString(_ s: String) -> NSTextField {
        NSTextField(wrappingLabelWithString: s)
    }

    public static func textField(withString s: String) -> NSTextField {
        NSTextField(string: s)
    }

    private func applyLabelDefaults(string: String, selectable: Bool, lineBreakMode: NSLineBreakMode) {
        stringValue = string
        isEditable = false
        isSelectable = selectable
        isBordered = false
        isBezeled = false
        drawsBackground = false
        maximumNumberOfLines = 0
        self.lineBreakMode = lineBreakMode
    }
}

@preconcurrency @MainActor
public protocol NSTextFieldDelegate: AnyObject {
    func controlTextDidChange(_ obj: Notification)
    func controlTextDidBeginEditing(_ obj: Notification)
    func controlTextDidEndEditing(_ obj: Notification)
    func control(_ control: NSControl, textShouldBeginEditing: NSText) -> Bool
    func control(_ control: NSControl, textShouldEndEditing: NSText) -> Bool
}
public extension NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {}
    func controlTextDidBeginEditing(_ obj: Notification) {}
    func controlTextDidEndEditing(_ obj: Notification) {}
    func control(_ control: NSControl, textShouldBeginEditing: NSText) -> Bool { true }
    func control(_ control: NSControl, textShouldEndEditing: NSText) -> Bool { true }
}

/// NSTokenField — a token-entry text field (WireGuard's on-demand SSID list).
/// Inherits NSTextField's inits/value API; adds the token-specific surface.
open class NSTokenField: NSTextField {
    public enum TokenStyle: Int, Sendable { case `default` = 0, none, plainText, rounded, squared }
    public var tokenizingCharacterSet: CharacterSet = CharacterSet(charactersIn: ",")
    public var tokenStyle: TokenStyle = .default
    public var completionDelay: TimeInterval = 0
    public class var defaultCompletionDelay: TimeInterval { 0 }
    public class var defaultTokenizingCharacterSet: CharacterSet { CharacterSet(charactersIn: ",") }
}

/// NSTokenFieldDelegate refines NSTextFieldDelegate; on macOS its methods are
/// @objc-optional. Declared with a default impl so conformers (e.g. WireGuard's
/// OnDemandControlsRow) only override what they need.
@preconcurrency @MainActor
public protocol NSTokenFieldDelegate: NSTextFieldDelegate {
    func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]?
}
public extension NSTokenFieldDelegate {
    func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? { nil }
}

open class NSText: NSView {
    public static let didChangeNotification = Notification.Name("NSTextDidChangeNotification")
    open var string: String = ""
    /// Layout bounds for the text (WireGuard's ConfTextView sets these to size the
    /// config editor). Compile-stubs.
    public var minSize: NSSize = .zero
    public var maxSize: NSSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    public var isHorizontallyResizable: Bool = false
    public var isVerticallyResizable: Bool = false
}

open class NSTextView: NSText {
    public static let didChangeSelectionNotification = Notification.Name("NSTextViewDidChangeSelectionNotification")
    public var textStorage: NSTextStorage? = NSTextStorage(string: "")
    public var layoutManager: NSLayoutManager? = NSLayoutManager()
    public var textContainer: NSTextContainer? = NSTextContainer()
    public var textContainerInset: NSSize = .zero
    open var allowsUndo: Bool = false
    open var isEditable: Bool = true
    open var isSelectable: Bool = true
    open var isRichText: Bool = false
    open var importsGraphics: Bool = false
    open var smartInsertDeleteEnabled: Bool = true
    open var isAutomaticQuoteSubstitutionEnabled: Bool = true
    open var isAutomaticDashSubstitutionEnabled: Bool = true
    open var isAutomaticTextReplacementEnabled: Bool = true
    open var isAutomaticSpellingCorrectionEnabled: Bool = true
    open var isContinuousSpellCheckingEnabled: Bool = true
    open var isGrammarCheckingEnabled: Bool = true
    open var continuousSpellCheckingEnabled: Bool {
        get { isContinuousSpellCheckingEnabled }
        set { isContinuousSpellCheckingEnabled = newValue }
    }
    open var grammarCheckingEnabled: Bool {
        get { isGrammarCheckingEnabled }
        set { isGrammarCheckingEnabled = newValue }
    }
    open var usesRuler: Bool = false
    open var usesFontPanel: Bool = false
    open var usesFindBar: Bool = false
    open var usesFindPanel: Bool = false
    open var rulerVisible: Bool = false
    public var selectedRange: NSRange = NSRange(location: 0, length: 0)
    public var selectedRanges: [NSValue] = []
    open var insertionPointColor: NSColor?
    open var typingAttributes: [NSAttributedString.Key: Any] = [:]
    open var selectedTextAttributes: [NSAttributedString.Key: Any] = [:]
    open var defaultParagraphStyle: NSMutableParagraphStyle?
    open var font: NSFont?
    open var textColor: NSColor?
    open var backgroundColor: NSColor?
    open var drawsBackground: Bool = true
    open var allowsDocumentBackgroundColorChange: Bool = false
    open var allowsCharacterPickerTouchBarItem: Bool = true
    public weak var delegate: NSTextViewDelegate?
    open var isAutomaticDataDetectionEnabled: Bool = false
    open var isAutomaticLinkDetectionEnabled: Bool = false
    open var isAutomaticTextCompletionEnabled: Bool = false
    open var undoManager: UndoManager? = UndoManager()
    open func hasMarkedText() -> Bool { false }
    open var textContainerOrigin: NSPoint { .zero }
    public var attributedString: NSAttributedString { NSAttributedString(string: string) }
    public func scrollToEndOfDocument(_ sender: Any?) {
        _ = sender
    }
    /// NSTextView's designated init is `init(frame:textContainer:)` (Apple-faithful;
    /// WireGuard's ConfTextView calls it). Declaring it means NSTextView stops
    /// inheriting NSView's inits, so re-declare them to keep NSTextView() /
    /// NSTextView(frame:) / NSTextView(coder:) working (zero blast radius).
    // nonisolated: pure storage, delegates to NSView's nonisolated init(frame:).
    nonisolated public init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect)
        if let container { self.textContainer = container }
    }
    nonisolated public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public convenience init() { self.init(frame: .zero, textContainer: nil) }
    nonisolated public required init?(coder: NSCoder) { super.init(frame: .zero) }
    /// Programmatic text-change hooks (compile-stubs). ConfTextView uses these to
    /// replace text + notify the layout/delegate.
    public func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool { true }
    public func didChangeText() {}
    public func setSelectedRange(_ r: NSRange) {
        selectedRange = clampedTextRange(r)
        selectedRanges = [NSValue(range: selectedRange)]
        delegate?.textViewDidChangeSelection(
            Notification(name: Notification.Name("NSTextViewDidChangeSelectionNotification"), object: self)
        )
    }
    public func scrollRangeToVisible(_ r: NSRange) {}
    open func firstRect(forCharacterRange range: NSRange, actualCharacterRange: NSRangePointer?) -> NSRect {
        actualCharacterRange?.pointee = range
        return NSRect(origin: textContainerOrigin, size: NSSize(width: 1, height: font?.pointSize ?? 14))
    }
    open func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        _ = (sendType, returnType)
        return nil
    }
    open func readSelection(from pboard: NSPasteboard) -> Bool {
        _ = pboard
        return false
    }
    open func insertNewline(_ sender: Any?) {
        insertText("\n", replacementRange: selectedRange)
    }
    public func replaceCharacters(in r: NSRange, with s: String) {
        let range = clampedTextRange(r)
        guard delegate?.textView(self, shouldChangeTextIn: range, replacementString: s) ?? true else {
            return
        }

        string = (string as NSString).replacingCharacters(in: range, with: s)
        textStorage?.setAttributedString(NSAttributedString(string: string))

        let replacementLength = (s as NSString).length
        let insertionLocation = min(range.location + replacementLength, (string as NSString).length)
        selectedRange = NSRange(location: insertionLocation, length: 0)
        selectedRanges = [NSValue(range: selectedRange)]

        delegate?.textDidChange(Notification(name: Notification.Name("NSTextDidChangeNotification"), object: self))
        delegate?.textViewDidChangeSelection(
            Notification(name: Notification.Name("NSTextViewDidChangeSelectionNotification"), object: self)
        )
    }
    public func replaceCharacters(in r: NSRange, with s: NSAttributedString) {
        replaceCharacters(in: r, with: s.string)
    }
    public func insertText(_ s: Any, replacementRange: NSRange) {
        let replacement: String
        if let attributed = s as? NSAttributedString {
            replacement = attributed.string
        } else if let string = s as? String {
            replacement = string
        } else {
            replacement = String(describing: s)
        }

        let range = replacementRange.location == NSNotFound ? selectedRange : replacementRange
        replaceCharacters(in: range, with: replacement)
    }

    private func clampedTextRange(_ range: NSRange) -> NSRange {
        let textLength = (string as NSString).length
        guard range.location != NSNotFound else {
            return NSRange(location: textLength, length: 0)
        }

        let requestedLength = max(0, range.length)
        let location = max(0, min(range.location, textLength))
        let requestedEnd: Int
        if requestedLength > textLength || range.location > Int.max - requestedLength {
            requestedEnd = textLength
        } else {
            requestedEnd = range.location + requestedLength
        }
        let end = max(location, min(requestedEnd, textLength))
        return NSRange(location: location, length: end - location)
    }
}

@preconcurrency @MainActor
public protocol NSLayoutManagerDelegate: AnyObject {}
@preconcurrency @MainActor
public protocol NSTextStorageDelegate: AnyObject {}

open class NSTextStorage: NSMutableAttributedString {
    public weak var delegate: NSTextStorageDelegate?
    public var layoutManagers: [NSLayoutManager] = []
    public func addLayoutManager(_ m: NSLayoutManager) {
        layoutManagers.append(m)
        m.textStorage = self
    }
    public func removeLayoutManager(_ m: NSLayoutManager) {
        layoutManagers.removeAll { $0 === m }
        if m.textStorage === self {
            m.textStorage = nil
        }
    }
    /// Edit-notification mask passed to `edited(_:range:changeInLength:)`. A
    /// custom NSTextStorage (e.g. WireGuard's ConfTextStorage) calls it after
    /// mutating its backing store so layout managers can re-lay-out. Compile-stub
    /// on Linux (no layout pass yet).
    public struct EditActions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let editedAttributes = EditActions(rawValue: 1 << 0)
        public static let editedCharacters = EditActions(rawValue: 1 << 1)
    }
    open func edited(_ editedMask: EditActions, range editedRange: NSRange, changeInLength delta: Int) {}
    open func processEditing() {}
    /// corelibs NSMutableAttributedString's `init()` is NOT a designated initializer,
    /// so a custom NSTextStorage (e.g. WireGuard's ConfTextStorage) can't `override
    /// init()` against it. Declare a designated `init()` here (delegating to the
    /// corelibs designated `init(string:)`) so subclasses can override it; re-declare
    /// `init(string:)` so NSTextStorage(string:) still works; + the required NSCoding init.
    public init() { super.init(string: "") }
    public override init(attributedString attrStr: NSAttributedString) { super.init(attributedString: attrStr) }
    public override init(string str: String) { super.init(string: str) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}

open class NSLayoutManager: NSObject, @unchecked Sendable {
    public override init() {}
    public weak var delegate: NSLayoutManagerDelegate?
    public weak var textStorage: NSTextStorage?
    public var textContainers: [NSTextContainer] = []
    public func addTextContainer(_ c: NSTextContainer) {
        textContainers.append(c)
        c.layoutManager = self
    }
    public func glyphRange(for container: NSTextContainer) -> NSRange {
        _ = container
        return NSRange(location: 0, length: textStorage?.length ?? 0)
    }
    public func glyphRange(forCharacterRange charRange: NSRange, actualCharacterRange: NSRangePointer?) -> NSRange {
        actualCharacterRange?.pointee = charRange
        return charRange
    }
    public func glyphRange(forBoundingRect bounds: NSRect, in container: NSTextContainer) -> NSRange {
        _ = (bounds, container)
        return NSRange(location: 0, length: textStorage?.length ?? 0)
    }
    public func characterIndexForGlyph(at glyphIndex: Int) -> Int {
        Swift.max(0, Swift.min(glyphIndex, textStorage?.length ?? glyphIndex))
    }
    public func isValidGlyphIndex(_ glyphIndex: Int) -> Bool {
        let upperBound = textStorage?.length ?? 0
        return glyphIndex >= 0 && glyphIndex < upperBound
    }
    open func ensureLayout(for textContainer: NSTextContainer) {
        _ = textContainer
    }
    open func invalidateLayout(forCharacterRange range: NSRange, actualCharacterRange: NSRangePointer?) {
        actualCharacterRange?.pointee = range
    }
    public func boundingRect(forGlyphRange glyphRange: NSRange, in container: NSTextContainer) -> NSRect {
        let used = usedRect(for: container)
        guard glyphRange.length > 0 else {
            return NSRect(x: used.minX, y: used.minY, width: 0, height: used.height)
        }
        let start = CGFloat(glyphRange.location) * 7
        let width = CGFloat(glyphRange.length) * 7
        return NSRect(x: used.minX + start, y: used.minY, width: width, height: used.height)
    }
    public func lineFragmentUsedRect(forGlyphAt glyphIndex: Int, effectiveRange: NSRangePointer?) -> NSRect {
        let clampedIndex = Swift.max(0, Swift.min(glyphIndex, Swift.max((textStorage?.length ?? 1) - 1, 0)))
        effectiveRange?.pointee = NSRange(location: clampedIndex, length: 1)
        return NSRect(x: CGFloat(clampedIndex) * 7, y: 0, width: 7, height: 14)
    }
    public func lineFragmentRect(forGlyphAt glyphIndex: Int, effectiveRange: NSRangePointer?) -> NSRect {
        lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: effectiveRange)
    }
    public func usedRect(for container: NSTextContainer) -> NSRect {
        _ = container
        let length = CGFloat(textStorage?.length ?? 0)
        return NSRect(x: 0, y: 0, width: length * 7, height: 14)
    }
}

open class NSTextContainer: NSObject, @unchecked Sendable {
    public override init() {}
    public init(size: NSSize) {}
    public var containerSize: NSSize = .zero
    /// Modern name for the container's text-layout size (containerSize is the
    /// deprecated alias). WireGuard's ConfTextView reads/sets it.
    public var size: NSSize = .zero
    public var widthTracksTextView: Bool = false
    public var heightTracksTextView: Bool = false
    public var lineFragmentPadding: CGFloat = 0
    public var maximumNumberOfLines: Int = 0
    public weak var layoutManager: NSLayoutManager?
    open var isSimpleRectangularTextContainer: Bool { true }
    open func lineFragmentRect(
        forProposedRect proposedRect: NSRect,
        at characterIndex: Int,
        writingDirection baseWritingDirection: NSWritingDirection,
        remaining remainingRect: NSRectPointer?
    ) -> NSRect {
        _ = (characterIndex, baseWritingDirection)
        remainingRect?.pointee = .zero
        return proposedRect
    }
}

@preconcurrency @MainActor
public protocol NSTextViewDelegate: NSTextDelegate {
    func textViewDidChangeSelection(_ notification: Notification)
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool
}
public extension NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {}
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool { true }
}

@preconcurrency @MainActor
public protocol NSTextDelegate: AnyObject {
    func textDidChange(_ notification: Notification)
    func textDidBeginEditing(_ notification: Notification)
    func textDidEndEditing(_ notification: Notification)
}
public extension NSTextDelegate {
    func textDidChange(_ notification: Notification) {}
    func textDidBeginEditing(_ notification: Notification) {}
    func textDidEndEditing(_ notification: Notification) {}
}

open class NSImageView: NSControl {
    public var image: NSImage?
    public var imageScaling: ImageScaling = .scaleProportionallyDown
    public var imageAlignment: ImageAlignment = .alignCenter
    public var animates: Bool = true
    public var symbolConfiguration: Any?
    public var contentTintColor: NSColor?
    public enum ImageScaling: UInt, Sendable { case scaleProportionallyDown, scaleAxesIndependently, scaleNone, scaleProportionallyUpOrDown }
    public enum ImageAlignment: UInt, Sendable { case alignCenter, alignTop, alignTopLeft, alignTopRight, alignLeft, alignBottom, alignBottomLeft, alignBottomRight, alignRight }
}

open class NSControl: NSView {
    public static let textDidChangeNotification = Notification.Name("NSControlTextDidChangeNotification")
    public static let textDidBeginEditingNotification = Notification.Name("NSControlTextDidBeginEditingNotification")
    public static let textDidEndEditingNotification = Notification.Name("NSControlTextDidEndEditingNotification")

    /// The control's backing cell (legacy AppKit). WireGuard's tunnels list reaches
    /// it as `(popup.cell as? NSPopUpButtonCell)?.arrowPosition`. NSPopUpButton seeds
    /// it with an NSPopUpButtonCell so that downcast succeeds; nil elsewhere.
    public var cell: NSCell?
    private var storedDoubleValue: Double = 0
    private var storedFloatValue: Float = 0
    private var storedIntegerValue: Int = 0
    private var storedStringValue: String = ""
    private var storedAttributedStringValue: NSAttributedString = NSAttributedString(string: "")
    private var storedObjectValue: Any?

    public weak var target: AnyObject?
    public var action: Selector?
    public var isEnabled: Bool = true
    public var isHighlighted: Bool = false
    public var doubleValue: Double {
        get { storedDoubleValue }
        set { setNumericValue(newValue, stringValue: String(newValue), objectValue: newValue) }
    }
    public var floatValue: Float {
        get { storedFloatValue }
        set { setNumericValue(Double(newValue), stringValue: String(newValue), objectValue: newValue) }
    }
    public var integerValue: Int {
        get { storedIntegerValue }
        set { setNumericValue(Double(newValue), stringValue: String(newValue), objectValue: newValue) }
    }
    public var stringValue: String {
        get { storedStringValue }
        set {
            storedStringValue = newValue
            storedAttributedStringValue = NSAttributedString(string: newValue)
            storedObjectValue = newValue
            updateNumericValues(from: newValue)
        }
    }
    public var attributedStringValue: NSAttributedString {
        get { storedAttributedStringValue }
        set {
            storedAttributedStringValue = newValue
            storedStringValue = newValue.string
            storedObjectValue = newValue
            updateNumericValues(from: newValue.string)
        }
    }
    public var objectValue: Any? {
        get { storedObjectValue }
        set { applyObjectValue(newValue) }
    }
    public var formatter: Foundation.Formatter?
    @discardableResult
    public func sendAction(_ a: Selector?, to receiver: Any?) -> Bool {
        guard isEnabled else { return false }
        guard let selector = a ?? action else { return false }
        let resolvedTarget = (receiver as AnyObject?) ?? target
        guard let resolvedTarget else { return false }
        // Dispatch to the target's lowered action handler, passing this control
        // as the sender (AppKit hands the control to `foo(sender:)` actions).
        // App classes that wire up target-action carry an injected class-body
        // `quillPerform(_:with:)` (QuillSelectorDispatching) switching on the
        // selector name. A target that doesn't conform is still a valid "had a
        // target" match (returns true, per AppKit); it just performs nothing.
        (resolvedTarget as? QuillSelectorDispatching)?.quillPerform(selector, with: self)
        return true
    }
    public func sizeToFit() {}
    public var controlSize: ControlSize = .regular
    public enum ControlSize: UInt, Sendable { case regular, small, mini, large }

    private func setNumericValue(_ value: Double, stringValue: String, objectValue: Any) {
        updateNumericValues(value)
        storedStringValue = stringValue
        storedAttributedStringValue = NSAttributedString(string: stringValue)
        storedObjectValue = objectValue
    }

    private func applyObjectValue(_ value: Any?) {
        guard let value else {
            storedObjectValue = nil
            storedStringValue = ""
            storedAttributedStringValue = NSAttributedString(string: "")
            updateNumericValues(0)
            return
        }

        storedObjectValue = value

        if let attributed = value as? NSAttributedString {
            storedAttributedStringValue = attributed
            storedStringValue = attributed.string
            updateNumericValues(from: attributed.string)
        } else if let string = value as? String {
            storedStringValue = string
            storedAttributedStringValue = NSAttributedString(string: string)
            updateNumericValues(from: string)
        } else if let number = value as? NSNumber {
            let string = number.stringValue
            storedStringValue = string
            storedAttributedStringValue = NSAttributedString(string: string)
            updateNumericValues(number.doubleValue)
        } else {
            let string = String(describing: value)
            storedStringValue = string
            storedAttributedStringValue = NSAttributedString(string: string)
            updateNumericValues(from: string)
        }
    }

    private func updateNumericValues(from string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        updateNumericValues(Double(trimmed) ?? 0)
    }

    private func updateNumericValues(_ value: Double) {
        let normalized = value.isFinite ? value : 0
        storedDoubleValue = normalized
        storedFloatValue = Float(normalized)

        if normalized >= Double(Int.min) && normalized <= Double(Int.max) {
            storedIntegerValue = Int(normalized)
        } else {
            storedIntegerValue = 0
        }
    }
}

open class NSButton: NSControl {
    private var storedTitle: String = ""
    private var storedAttributedTitle: NSAttributedString = NSAttributedString(string: "")

    /// Frame init — NSButton's title/image designated inits otherwise suppress
    /// NSView's, so subclasses like WireGuard's FillerButton (super.init(frame:)) need it.
    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }

    /// Required NSCoding init (NSView's coder init is `required`; the
    /// title/image designated inits suppress inheritance). Coder ignored.
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    public var title: String {
        get { storedTitle }
        set {
            storedTitle = newValue
            storedAttributedTitle = NSAttributedString(string: newValue)
        }
    }
    public var attributedTitle: NSAttributedString {
        get { storedAttributedTitle }
        set {
            storedAttributedTitle = newValue
            storedTitle = newValue.string
        }
    }
    public var alternateTitle: String = ""
    public var image: NSImage?
    public var alternateImage: NSImage?
    public var bezelStyle: BezelStyle = .rounded
    public var imagePosition: ImagePosition = .imageLeft
    public var keyEquivalent: String = ""
    public var keyEquivalentModifierMask: NSEvent.ModifierFlags = []
    public var state: NSControl.StateValue = .off
    public var isBordered: Bool = true
    public var isTransparent: Bool = false
    public var showsBorderOnlyWhileMouseInside: Bool = false
    public var imageHugsTitle: Bool = false
    public var symbolConfiguration: Any?
    public var buttonType: ButtonType = .momentaryPushIn

    public enum BezelStyle: UInt, Sendable { case rounded, regularSquare, disclosure, shadowlessSquare, circular, texturedSquare, helpButton, smallSquare, texturedRounded, roundRect, recessed, roundedDisclosure, inline }
    public enum ImagePosition: UInt, Sendable { case noImage, imageOnly, imageLeft, imageRight, imageBelow, imageAbove, imageOverlaps, imageLeading, imageTrailing }
    public enum ButtonType: UInt, Sendable { case momentaryLight, pushOnPushOff, toggle, `switch`, radio, momentaryChange, onOff, momentaryPushIn, accelerator, multiLevelAccelerator }

    public convenience init() { self.init(title: "", target: nil, action: nil) }
    // nonisolated: pure storage writes of inherited stored properties happen
    // through assumeIsolated (setter dispatch), per the house model (#231).
    nonisolated public init(title: String, target: Any?, action: Selector?) {
        super.init(frame: .zero)
        MainActor.assumeIsolated {
            self.title = title
            self.target = target as AnyObject?
            self.action = action
        }
    }
    nonisolated public init(image: NSImage, target: Any?, action: Selector?) {
        super.init(frame: .zero)
        MainActor.assumeIsolated {
            self.image = image
            self.target = target as AnyObject?
            self.action = action
        }
    }
    /// Programmatically click the button: fire its action at its target. The Qt
    /// backing routes a real `clicked` signal here once signal wiring lands.
    open func performClick(_ sender: Any?) {
        sendAction(action, to: target)
    }
    public func setButtonType(_ type: ButtonType) { buttonType = type }
    public static func radioButton(withTitle: String, target: Any?, action: Selector?) -> NSButton {
        let button = NSButton(title: withTitle, target: target, action: action)
        button.setButtonType(.radio)
        return button
    }
    public static func checkbox(withTitle: String, target: Any?, action: Selector?) -> NSButton {
        let button = NSButton(title: withTitle, target: target, action: action)
        button.setButtonType(.switch)
        return button
    }

    /// Intrinsic size for a push button: an estimated title width (rough
    /// system-font metric) plus standard bezel padding, at the standard
    /// rounded-button height. Without this a button pinned only by its center
    /// (e.g. WireGuard's ButtonedDetailViewController — centerX/centerY and no
    /// width/height constraint) would solve to 0×0 and render invisibly. The Qt
    /// layout pass injects this as a soft (medium-priority) size suggestion that
    /// still yields to required size/edge constraints. Faithful text metrics
    /// (QuillTypography) refine this estimate in a later paint-fidelity rung.
    open override var intrinsicContentSize: NSSize {
        // Estimate the title width (Inter ≈7.5pt/char at the 13pt system size) plus
        // the macOS push-button bezel insets — the Qt control stylesheet adds ~12pt
        // padding + a 1pt border on each side, so the box must be generous enough
        // that titles don't clip inside the rounded bezel.
        let estimatedTextWidth = CGFloat(storedTitle.count) * 7.5
        let width = max(72, estimatedTextWidth + 34)
        return NSSize(width: width, height: 32)
    }
}

public extension NSControl {
    struct StateValue: RawRepresentable, Equatable, Sendable {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let off = StateValue(rawValue: 0)
        public static let on = StateValue(rawValue: 1)
        public static let mixed = StateValue(rawValue: -1)
    }
}

open class NSSlider: NSControl {
    public var minValue: Double = 0
    public var maxValue: Double = 1
    public var altIncrementValue: Double = 0
    public var allowsTickMarkValuesOnly: Bool = false
    public var numberOfTickMarks: Int = 0
    public var tickMarkPosition: TickMarkPosition = .below
    public var sliderType: SliderType = .linear
    public var isVertical: Bool = false
    public var trackFillColor: NSColor?
    public enum TickMarkPosition: UInt, Sendable { case below, above, leading, trailing }
    public enum SliderType: UInt, Sendable { case linear, circular }
    public convenience init() { self.init(frame: .zero) }
    public convenience init(value: Double, minValue: Double, maxValue: Double, target: Any?, action: Selector?) {
        self.init()
        doubleValue = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.target = target as AnyObject?
        self.action = action
    }
}

open class NSStackView: NSView {
    public enum Orientation: Int, Sendable { case horizontal = 0, vertical = 1 }
    public enum Distribution: Int, Sendable { case equalCentering, equalSpacing, fill, fillEqually, fillProportionally, gravityAreas }
    public enum Gravity: Int, Sendable { case top, center, bottom, leading, trailing }
    public var orientation: Orientation = .horizontal
    public var alignment: NSLayoutConstraint.Attribute = .centerY
    public var distribution: Distribution = .fill
    public var spacing: CGFloat = 0
    public var edgeInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    public var arrangedSubviews: [NSView] = []
    /// Per-view trailing spacing (overrides `spacing` after that view), honored by
    /// quillSynthesizeStackConstraints().
    private var customSpacings: [ObjectIdentifier: CGFloat] = [:]
    /// Constraints generated by quillSynthesizeStackConstraints(); deactivated and
    /// rebuilt on each call so re-layout never duplicates them.
    private var synthesizedConstraints: [NSLayoutConstraint] = []
    public func addArrangedSubview(_ v: NSView) { arrangedSubviews.append(v); addSubview(v) }
    public func insertArrangedSubview(_ v: NSView, at idx: Int) { arrangedSubviews.insert(v, at: idx); addSubview(v) }
    // Per-view trailing spacing, honored by the constraint synthesis below.
    public func setCustomSpacing(_ spacing: CGFloat, after view: NSView) {
        customSpacings[ObjectIdentifier(view)] = spacing
    }
    /// Content-hugging priority for the stack axis (WireGuard's edit VC pins the
    /// container). Compile-stub.
    public func setHuggingPriority(_ priority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) {}
    public func removeArrangedSubview(_ v: NSView) {
        arrangedSubviews.removeAll { $0 === v }
    }
    // Gravity-area APIs. The shadow keeps one ordered arranged-subview list
    // (gravity isn't modeled yet — the constraint layout pass positions views),
    // so addView appends like addArrangedSubview and setViews replaces the list.
    public func addView(_ view: NSView, in gravity: Gravity) {
        addArrangedSubview(view)
    }
    public func setViews(_ views: [NSView], in gravity: Gravity) {
        arrangedSubviews.removeAll()
        for view in views { addArrangedSubview(view) }
    }
    public convenience init() { self.init(frame: .zero) }
    public convenience init(views: [NSView]) {
        self.init(frame: .zero)
        for view in views { addArrangedSubview(view) }
    }

    /// Translate this stack's orientation / spacing / custom-spacing / edgeInsets
    /// into REAL NSLayoutConstraints on its arranged subviews, so the Qt Auto
    /// Layout pass (which solves NSLayoutConstraint.quillActive) positions them.
    /// The shadow's addArrangedSubview only records the view — without these
    /// constraints arranged subviews collapse to 0×0 at the stack origin.
    ///
    /// Layout (vertical; horizontal mirrors the axes): a main-axis chain pins the
    /// first child to the stack's top + topInset, each subsequent child below the
    /// previous by `spacing` (or its recorded custom spacing), and the last child
    /// to the stack's bottom − bottomInset — so the stack sizes to its content
    /// (the shadow stack has no intrinsic size of its own). The cross axis pins
    /// every child to both stack edges (the .fill default), giving labels a
    /// definite width so a wrapping label's intrinsic height resolves. Each
    /// child's size on the unpinned axis comes from intrinsicContentSize via the
    /// Qt pass's medium-priority fallback.
    ///
    /// Idempotent: previously-synthesized constraints are deactivated and rebuilt,
    /// so calling this on every layout pass never duplicates constraints. The Qt
    /// layoutQtSubtree walk calls it before the solver collects constraints.
    public func quillSynthesizeStackConstraints() {
        NSLayoutConstraint.deactivate(synthesizedConstraints)
        synthesizedConstraints.removeAll()
        guard !arrangedSubviews.isEmpty else { return }

        let vertical = (orientation == .vertical)
        var generated: [NSLayoutConstraint] = []

        for (i, child) in arrangedSubviews.enumerated() {
            // Cross axis: pin both edges to the stack (.fill) ± insets.
            if vertical {
                generated.append(child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: edgeInsets.left))
                generated.append(child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -edgeInsets.right))
            } else {
                generated.append(child.topAnchor.constraint(equalTo: topAnchor, constant: edgeInsets.top))
                generated.append(child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -edgeInsets.bottom))
            }

            // Main axis: first child to the leading edge, others chained below/after
            // the previous by the (custom) spacing.
            if i == 0 {
                if vertical {
                    generated.append(child.topAnchor.constraint(equalTo: topAnchor, constant: edgeInsets.top))
                } else {
                    generated.append(child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: edgeInsets.left))
                }
            } else {
                let prev = arrangedSubviews[i - 1]
                let gap = customSpacings[ObjectIdentifier(prev)] ?? spacing
                if vertical {
                    generated.append(child.topAnchor.constraint(equalTo: prev.bottomAnchor, constant: gap))
                } else {
                    generated.append(child.leadingAnchor.constraint(equalTo: prev.trailingAnchor, constant: gap))
                }
            }

            // Last child closes the stack's main-axis size (content-sized stack).
            if i == arrangedSubviews.count - 1 {
                if vertical {
                    generated.append(child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -edgeInsets.bottom))
                } else {
                    generated.append(child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -edgeInsets.right))
                }
            }
        }

        NSLayoutConstraint.activate(generated)
        synthesizedConstraints = generated
    }
}

extension NSLayoutConstraint {
    /// Axis for content hugging / compression-resistance priorities.
    public enum Orientation: Int, Sendable { case horizontal = 0, vertical = 1 }

    public enum Attribute: Int, Sendable {
        case left, right, top, bottom, leading, trailing
        case width, height, centerX, centerY, lastBaseline, firstBaseline
        case notAnAttribute
    }

    public convenience init(
        item view1: Any,
        attribute attr1: Attribute,
        relatedBy relation: Relation,
        toItem view2: Any?,
        attribute attr2: Attribute,
        multiplier: CGFloat,
        constant c: CGFloat
    ) {
        self.init()
        _ = (view1, attr1, relation, view2, attr2, multiplier, c)
    }
}

open class NSProgressIndicator: NSView {
    public var minValue: Double = 0
    public var maxValue: Double = 100
    public var doubleValue: Double = 0
    public var isIndeterminate: Bool = false
    public var style: Style = .bar
    public var controlSize: NSControl.ControlSize = .regular
    public var isDisplayedWhenStopped: Bool = true
    public var usesThreadedAnimation: Bool = false
    public enum Style: UInt, Sendable { case bar, spinning }
    public func startAnimation(_ sender: Any?) {}
    public func stopAnimation(_ sender: Any?) {}
    public func incrementBy(_ delta: Double) { doubleValue += delta }
    public convenience init() { self.init(frame: .zero) }
}

open class NSPopUpButton: NSButton {
    public var menu: NSMenu? = NSMenu() {
        didSet { reconcileSelectionAfterMenuChange() }
    }
    public var pullsDown: Bool = false
    public private(set) var indexOfSelectedItem: Int = -1
    public private(set) var selectedItem: NSMenuItem?
    public private(set) var titleOfSelectedItem: String?
    public var itemArray: [NSMenuItem] { menu?.items ?? [] }
    public var numberOfItems: Int { itemArray.count }
    public func addItem(withTitle title: String) {
        let owningMenu = ensureMenu()
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        owningMenu.addItem(item)
        if selectedItem == nil {
            selectItem(item, at: owningMenu.items.count - 1)
        }
    }
    public func addItems(withTitles titles: [String]) { for t in titles { addItem(withTitle: t) } }
    public func selectItem(at idx: Int) {
        guard let items = menu?.items, idx >= 0, idx < items.count else { return }
        selectItem(items[idx], at: idx)
    }
    public func selectItem(withTitle title: String) {
        guard let items = menu?.items, let index = items.firstIndex(where: { $0.title == title }) else { return }
        selectItem(items[index], at: index)
    }
    public func selectItem(withTag tag: Int) -> Bool {
        guard let items = menu?.items, let index = items.firstIndex(where: { $0.tag == tag }) else { return false }
        selectItem(items[index], at: index)
        return true
    }
    public func itemTitles() -> [String] { menu?.items.map(\.title) ?? [] }
    public func removeAllItems() {
        menu?.removeAllItems()
        clearSelection()
    }
    public func itemTitle(at idx: Int) -> String {
        guard let items = menu?.items, idx >= 0, idx < items.count else { return "" }
        return items[idx].title
    }
    public func removeItem(at idx: Int) {
        guard let items = menu?.items, idx >= 0, idx < items.count else { return }
        let removedItem = items[idx]
        let removedSelectedItem = removedItem === selectedItem
        menu?.removeItem(removedItem)
        if removedSelectedItem {
            selectNearestItem(afterRemovingIndex: idx)
        } else {
            reconcileSelectionAfterMenuChange()
        }
    }
    public func itemWithTitle(_ t: String) -> NSMenuItem? {
        menu?.items.first { $0.title == t }
    }
    nonisolated public override init(frame: NSRect) {
        super.init(frame: frame)
        MainActor.assumeIsolated { self.cell = NSPopUpButtonCell() }
    }
    nonisolated public init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame)
        MainActor.assumeIsolated {
            self.pullsDown = pullsDown
            self.cell = NSPopUpButtonCell()
        }
    }
    /// Required NSCoding init (NSView's coder init is `required`; the
    /// designated inits above suppress inheritance). Coder ignored — mirrors
    /// the designated inits' cell setup. Class-isolated, so no hop needed.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.cell = NSPopUpButtonCell()
    }
    public convenience init() { self.init(frame: .zero, pullsDown: false) }
    public override convenience init(title: String, target: Any?, action: Selector?) {
        self.init(frame: .zero, pullsDown: false)
        self.title = title
        self.target = target as AnyObject?
        self.action = action
    }
    public func select(_ item: NSMenuItem?) {
        guard let item, let items = menu?.items, let index = items.firstIndex(where: { $0 === item }) else {
            return
        }
        selectItem(item, at: index)
    }

    private func ensureMenu() -> NSMenu {
        if let menu { return menu }
        let newMenu = NSMenu()
        menu = newMenu
        return newMenu
    }

    private func selectItem(_ item: NSMenuItem, at index: Int) {
        selectedItem = item
        indexOfSelectedItem = index
        titleOfSelectedItem = item.title
    }

    private func selectNearestItem(afterRemovingIndex removedIndex: Int) {
        guard let items = menu?.items, !items.isEmpty else {
            clearSelection()
            return
        }
        let replacementIndex = min(removedIndex, items.count - 1)
        selectItem(items[replacementIndex], at: replacementIndex)
    }

    private func reconcileSelectionAfterMenuChange() {
        guard let items = menu?.items, !items.isEmpty else {
            clearSelection()
            return
        }
        if let selectedItem, let index = items.firstIndex(where: { $0 === selectedItem }) {
            selectItem(selectedItem, at: index)
        } else {
            selectItem(items[0], at: 0)
        }
    }

    private func clearSelection() {
        selectedItem = nil
        titleOfSelectedItem = nil
        indexOfSelectedItem = -1
    }
}

open class NSPopUpButtonCell: NSCell, @unchecked Sendable {
    public var arrowPosition: ArrowPosition = .arrowAtBottom
    public enum ArrowPosition: UInt, Sendable { case noArrow, arrowAtCenter, arrowAtBottom }
    public override init() { super.init() }
}

open class NSSearchField: NSTextField {
    public var searchMenuTemplate: NSMenu?
    public var sendsSearchStringImmediately: Bool = false
    public var sendsWholeSearchString: Bool = false
    public var maximumRecents: Int = 10
    public var recentSearches: [String] = []
    public var recentsAutosaveName: String?
    public weak var searchDelegate: NSSearchFieldDelegate?
}

@preconcurrency @MainActor
public protocol NSSearchFieldDelegate: NSTextFieldDelegate {
    func searchFieldDidStartSearching(_ sender: NSSearchField)
    func searchFieldDidEndSearching(_ sender: NSSearchField)
}
public extension NSSearchFieldDelegate {
    func searchFieldDidStartSearching(_ sender: NSSearchField) {}
    func searchFieldDidEndSearching(_ sender: NSSearchField) {}
}

open class NSSplitView: NSView {
    public static let didResizeSubviewsNotification = Notification.Name("NSSplitViewDidResizeSubviewsNotification")

    public weak var delegate: NSSplitViewDelegate?
    public var isVertical: Bool = false
    public var arrangedSubviews: [NSView] = []
    public var dividerStyle: DividerStyle = .thick
    public var dividerThickness: CGFloat {
        switch dividerStyle {
        case .thick:
            9
        case .thin:
            1
        case .paneSplitter:
            10
        }
    }
    public var holdingPriorityForSubviewAtIndex: (Int) -> Float = { _ in 250 }
    public var autosaveName: String?
    public func addArrangedSubview(_ v: NSView) {
        guard !arrangedSubviews.contains(where: { $0 === v }) else { return }
        arrangedSubviews.append(v)
        addSubview(v)
    }
    public func insertArrangedSubview(_ v: NSView, at idx: Int) {
        guard !arrangedSubviews.contains(where: { $0 === v }) else { return }
        let relativeSubview = idx < subviews.count ? subviews[idx] : nil
        arrangedSubviews.insert(v, at: idx)
        if let relativeSubview {
            addSubview(v, positioned: .below, relativeTo: relativeSubview)
        } else {
            addSubview(v)
        }
    }
    public func insertArrangedSubview(_ v: AnyObject, at idx: Int) {
        _ = (v, idx)
    }
    public func removeArrangedSubview(_ v: NSView) {
        arrangedSubviews.removeAll { $0 === v }
        v.removeFromSuperview()
    }
    public func setPosition(_ pos: CGFloat, ofDividerAt idx: Int) {
        guard idx >= 0, idx < arrangedSubviews.count - 1 else { return }

        let leadingView = arrangedSubviews[idx]
        let trailingView = arrangedSubviews[idx + 1]
        let leadingOrigin = primaryOrigin(of: leadingView)
        let trailingEnd = primaryMax(of: trailingView)
        guard trailingEnd > leadingOrigin else {
            resizeSubview(leadingView, primaryOrigin: leadingOrigin, primaryLength: 0)
            resizeSubview(trailingView, primaryOrigin: leadingOrigin, primaryLength: 0)
            notifyDidResizeSubviews()
            return
        }

        let dividerPosition = min(max(pos, leadingOrigin), max(leadingOrigin, trailingEnd - dividerThickness))
        let trailingOrigin = min(dividerPosition + dividerThickness, trailingEnd)
        resizeSubview(
            leadingView,
            primaryOrigin: leadingOrigin,
            primaryLength: max(0, dividerPosition - leadingOrigin)
        )
        resizeSubview(
            trailingView,
            primaryOrigin: trailingOrigin,
            primaryLength: max(0, trailingEnd - trailingOrigin)
        )
        notifyDidResizeSubviews()
    }
    public func adjustSubviews() {
        guard !arrangedSubviews.isEmpty else { return }

        let availableLength = max(0, primaryLength(of: self) - dividerThickness * CGFloat(arrangedSubviews.count - 1))
        var allocatedLength: CGFloat = 0
        var cursor: CGFloat = 0

        for (idx, subview) in arrangedSubviews.enumerated() {
            let remainingViews = CGFloat(arrangedSubviews.count - idx)
            let subviewLength: CGFloat
            if idx == arrangedSubviews.count - 1 {
                subviewLength = max(0, availableLength - allocatedLength)
            } else {
                subviewLength = ceil(max(0, availableLength - allocatedLength) / remainingViews)
            }
            resizeSubview(subview, primaryOrigin: cursor, primaryLength: subviewLength)
            allocatedLength += subviewLength
            cursor += subviewLength + dividerThickness
        }
    }
    public enum DividerStyle: Int, Sendable { case thick = 1, thin = 2, paneSplitter = 3 }

    private func primaryLength(of view: NSView) -> CGFloat {
        isVertical ? view.frame.width : view.frame.height
    }

    private func primaryOrigin(of view: NSView) -> CGFloat {
        isVertical ? view.frame.minX : view.frame.minY
    }

    private func primaryMax(of view: NSView) -> CGFloat {
        isVertical ? view.frame.maxX : view.frame.maxY
    }

    private func resizeSubview(_ view: NSView, primaryOrigin: CGFloat, primaryLength: CGFloat) {
        let crossLength = isVertical ? frame.height : frame.width
        if isVertical {
            view.frame = NSRect(x: primaryOrigin, y: 0, width: primaryLength, height: crossLength)
        } else {
            view.frame = NSRect(x: 0, y: primaryOrigin, width: crossLength, height: primaryLength)
        }
    }

    private func notifyDidResizeSubviews() {
        let notification = Notification(name: Self.didResizeSubviewsNotification, object: self)
        NotificationCenter.default.post(notification)
        delegate?.splitViewDidResizeSubviews(notification)
    }
}

@preconcurrency @MainActor
public protocol NSSplitViewDelegate: AnyObject {
    func splitView(_ splitView: NSSplitView, canCollapseSubview: NSView) -> Bool
    func splitViewDidResizeSubviews(_ notification: Notification)
}
public extension NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, canCollapseSubview: NSView) -> Bool { false }
    func splitViewDidResizeSubviews(_ notification: Notification) {}
}

public typealias NSSplitViewDividerIndex = Int

open class NSSplitViewController: NSViewController {
    public var splitViewItems: [NSSplitViewItem] = []
    public func addSplitViewItem(_ i: NSSplitViewItem) {
        guard !splitViewItems.contains(where: { $0 === i }) else { return }
        splitViewItems.append(i)
        splitView.addArrangedSubview(i.viewController.view)
        addChild(i.viewController)
    }
    public func insertSplitViewItem(_ i: NSSplitViewItem, at idx: Int) {
        guard !splitViewItems.contains(where: { $0 === i }) else { return }
        splitViewItems.insert(i, at: idx)
        splitView.insertArrangedSubview(i.viewController.view, at: idx)
        addChild(i.viewController)
    }
    public func removeSplitViewItem(_ i: NSSplitViewItem) {
        guard splitViewItems.contains(where: { $0 === i }) else { return }
        splitViewItems.removeAll { $0 === i }
        splitView.removeArrangedSubview(i.viewController.view)
        i.viewController.removeFromParent()
    }
    public var splitView: NSSplitView = NSSplitView()
}

// Apple parity (#512).
@preconcurrency @MainActor
open class NSSplitViewItem: NSObject {
    public var viewController: NSViewController = NSViewController()
    public var behavior: Behavior = .default
    public var collapseBehavior: CollapseBehavior = .default
    public var minimumThickness: CGFloat = -1
    public var maximumThickness: CGFloat = -1
    public var preferredThicknessFraction: CGFloat = -1
    public var holdingPriority: Float = 250
    public var titlebarSeparatorStyle: NSTitlebarSeparatorStyle = .automatic
    public var canCollapse: Bool = true
    public var canCollapseFromWindowResize: Bool = true
    public var isCollapsed: Bool = false
    public var allowsFullHeightLayout: Bool = false
    public var automaticMaximumThickness: CGFloat = -1
    public enum Behavior: Int, Sendable { case `default`, sidebar, contentList, inspector }
    public enum CollapseBehavior: Int, Sendable { case `default`, preferResizingSplitViewWithFixedSiblings, preferResizingSiblingsWithFixedSplitView, useConstraints }
    public override init() { super.init() }
    public init(viewController: NSViewController) { super.init(); self.viewController = viewController }
    public static func sidebar(with viewController: NSViewController) -> NSSplitViewItem {
        let i = NSSplitViewItem(viewController: viewController); i.behavior = .sidebar; return i
    }
    public static func contentListWithViewController(_ vc: NSViewController) -> NSSplitViewItem {
        let i = NSSplitViewItem(viewController: vc); i.behavior = .contentList; return i
    }
    public static func inspector(with viewController: NSViewController) -> NSSplitViewItem {
        let i = NSSplitViewItem(viewController: viewController); i.behavior = .inspector; return i
    }
}

public enum NSTitlebarSeparatorStyle: Int, Sendable {
    case automatic, none, line, shadow
}

// MARK: - NSOutlineView / NSTableView

open class NSTableView: NSControl {
    public static let selectionDidChangeNotification = Notification.Name("NSTableViewSelectionDidChangeNotification")
    /// Auto row-height mode (WireGuard's LogViewController log table). No-op on Linux.
    public var usesAutomaticRowHeights: Bool = false

    /// Row-selection highlight style. WireGuard's TunnelDetail table uses `.none`
    /// (no highlight on the read-only detail rows). Compile-stub (stored).
    public enum SelectionHighlightStyle: Int, Sendable {
        case none = -1, regular = 0, sourceList = 1
    }
    public var selectionHighlightStyle: SelectionHighlightStyle = .regular

    public weak var delegate: NSTableViewDelegate?
    public weak var dataSource: NSTableViewDataSource?
    public var headerView: NSTableHeaderView? = NSTableHeaderView()
    public var tableColumns: [NSTableColumn] = []
    public var rowHeight: CGFloat = 17
    public var intercellSpacing: NSSize = NSSize(width: 3, height: 2)
    /// Cells materialized into the live view tree by the Qt render pass
    /// (NSTableView.quillMaterializeRowsIntoSubtree) — the shadow keeps cell views
    /// in private caches, so rendering needs them promoted to `subviews`. Tracked
    /// so a re-render clears the prior set instead of duplicating rows. Render-only.
    public var quillMaterializedCells: [NSView] = []
    public var quillMaterializedConstraints: [NSLayoutConstraint] = []
    public var allowsMultipleSelection: Bool = false
    public var allowsEmptySelection: Bool = true
    public var allowsColumnSelection: Bool = false
    public var allowsColumnReordering: Bool = true
    public var allowsColumnResizing: Bool = true
    public var usesAlternatingRowBackgroundColors: Bool = false
    public var gridStyleMask: GridLineStyle = []
    public var gridColor: NSColor = NSColor()
    public var backgroundColor: NSColor = NSColor()
    public var selectedRow: Int = -1
    public var selectedRowIndexes: IndexSet = IndexSet()
    public var selectedColumnIndexes: IndexSet = IndexSet()
    public var clickedRow: Int = -1
    public var clickedColumn: Int = -1
    public var numberOfRows: Int = 0
    public var numberOfColumns: Int { tableColumns.count }
    public var rowSizeStyle: RowSizeStyle = .default
    public var style: Style = .automatic
    public var floatsGroupRows: Bool = false
    public var doubleAction: Selector?
    public var menu: NSMenu?
    public var sortDescriptors: [NSSortDescriptor] = []
    public var autosaveName: String?
    public var autosaveTableColumns: Bool = false
    public var columnAutoresizingStyle: ColumnAutoresizingStyle = .uniformColumnAutoresizingStyle

    private struct CellKey: Hashable {
        var column: Int
        var row: Int
    }

    private var cachedRowViews: [Int: NSTableRowView] = [:]
    private var cachedCellViews: [CellKey: NSView] = [:]

    public struct GridLineStyle: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let solidVerticalGridLineMask = GridLineStyle(rawValue: 1 << 0)
        public static let solidHorizontalGridLineMask = GridLineStyle(rawValue: 1 << 1)
        public static let dashedHorizontalGridLineMask = GridLineStyle(rawValue: 1 << 3)
    }
    public enum RowSizeStyle: Int, Sendable { case `default` = -1, custom = 0, small, medium, large }
    public enum Style: Int, Sendable { case automatic, fullWidth, inset, sourceList, plain }
    public enum ColumnAutoresizingStyle: Int, Sendable {
        case noColumnAutoresizing = 0
        case uniformColumnAutoresizingStyle = 1
        case sequentialColumnAutoresizingStyle = 2
        case reverseSequentialColumnAutoresizingStyle = 3
        case lastColumnOnlyAutoresizingStyle = 4
        case firstColumnOnlyAutoresizingStyle = 5
    }

    public func reloadData() {
        let rowCount = MainActor.assumeIsolated { dataSource?.numberOfRows(in: self) ?? 0 }
        replaceLoadedRows(count: rowCount)
    }

    public func reloadData(forRowIndexes rowIndexes: IndexSet, columnIndexes: IndexSet) {
        for row in rowIndexes {
            if let rowView = cachedRowViews.removeValue(forKey: row) {
                if let delegate {
                    MainActor.assumeIsolated { delegate.tableView(self, didRemove: rowView, forRow: row) }
                }
            }
            if columnIndexes.isEmpty {
                cachedCellViews.keys
                    .filter { $0.row == row }
                    .forEach { cachedCellViews.removeValue(forKey: $0) }
            } else {
                for column in columnIndexes {
                    cachedCellViews.removeValue(forKey: CellKey(column: column, row: row))
                }
            }
        }
    }

    public func selectRowIndexes(_ rowIndexes: IndexSet, byExtendingSelection: Bool) {
        var accepted = IndexSet()
        for row in rowIndexes where row >= 0 && row < numberOfRows {
            guard shouldSelectRow(row) else { continue }
            accepted.insert(row)
            if !allowsMultipleSelection { break }
        }

        var nextSelection = byExtendingSelection ? selectedRowIndexes.union(accepted) : accepted
        if !allowsMultipleSelection, let first = nextSelection.first {
            nextSelection = IndexSet(integer: first)
        }
        if nextSelection.isEmpty && !allowsEmptySelection {
            return
        }
        setSelectedRowIndexes(nextSelection)
    }

    public func deselectRow(_ row: Int) {
        guard selectedRowIndexes.contains(row) else { return }
        var nextSelection = selectedRowIndexes
        nextSelection.remove(row)
        if nextSelection.isEmpty && !allowsEmptySelection {
            return
        }
        setSelectedRowIndexes(nextSelection)
    }

    public func deselectAll(_ sender: Any?) {
        guard allowsEmptySelection else { return }
        setSelectedRowIndexes(IndexSet())
    }
    public func scrollRowToVisible(_ row: Int) {}
    public func rowView(atRow row: Int, makeIfNecessary: Bool) -> NSTableRowView? {
        guard row >= 0 && row < numberOfRows else { return nil }
        if let rowView = cachedRowViews[row] {
            return rowView
        }
        guard makeIfNecessary, let rowView = makeRowView(forRow: row) else {
            return nil
        }
        rowView.isSelected = selectedRowIndexes.contains(row)
        cachedRowViews[row] = rowView
        if let delegate {
            MainActor.assumeIsolated { delegate.tableView(self, didAdd: rowView, forRow: row) }
        }
        return rowView
    }

    public func view(atColumn column: Int, row: Int, makeIfNecessary: Bool) -> NSView? {
        guard row >= 0 && row < numberOfRows && column >= 0 && column < tableColumns.count else {
            return nil
        }
        let key = CellKey(column: column, row: row)
        if let cached = cachedCellViews[key] {
            return cached
        }
        guard makeIfNecessary else { return nil }
        let view = makeCellView(forColumn: column, row: row)
        if let view {
            cachedCellViews[key] = view
        }
        return view
    }

    public func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        cachedCellViews.values.first { $0.identifier == identifier }
    }
    public func register(nib: Any?, forIdentifier: NSUserInterfaceItemIdentifier) {}
    public func register(_ cellClass: AnyClass?, forCellReuseIdentifier: String) {}
    public func addTableColumn(_ column: NSTableColumn) { tableColumns.append(column) }

    public func removeTableColumn(_ column: NSTableColumn) {
        guard let index = tableColumns.firstIndex(where: { $0 === column }) else { return }
        tableColumns.remove(at: index)
        let oldCellViews = cachedCellViews
        cachedCellViews.removeAll()
        for (key, view) in oldCellViews {
            if key.column < index {
                cachedCellViews[key] = view
            } else if key.column > index {
                cachedCellViews[CellKey(column: key.column - 1, row: key.row)] = view
            }
        }
        selectedColumnIndexes = shiftedColumnSelection(afterRemovingColumnAt: index)
    }

    public func column(withIdentifier identifier: NSUserInterfaceItemIdentifier) -> Int {
        tableColumns.firstIndex { $0.identifier == identifier } ?? -1
    }

    public func tableColumn(withIdentifier identifier: NSUserInterfaceItemIdentifier) -> NSTableColumn? {
        tableColumns.first { $0.identifier == identifier }
    }
    public func beginUpdates() {}
    public func endUpdates() {}
    public func insertRows(at rowIndexes: IndexSet, withAnimation _: AnimationOptions) {
        let insertedRows = validInsertionRows(from: rowIndexes)
        guard !insertedRows.isEmpty else { return }

        recacheRowViews { shiftedRowAfterInsertion(row: $0, insertedRows: insertedRows) }
        recacheCellViews { shiftedRowAfterInsertion(row: $0, insertedRows: insertedRows) }
        numberOfRows += insertedRows.count
        setSelectedRowIndexes(shiftedSelectionAfterInsertion(insertedRows), notify: false)
        clickedRow = clickedRow >= 0 ? shiftedRowAfterInsertion(row: clickedRow, insertedRows: insertedRows) : clickedRow
    }

    public func removeRows(at rowIndexes: IndexSet, withAnimation _: AnimationOptions) {
        let removedRows = existingRows(from: rowIndexes)
        guard !removedRows.isEmpty else { return }

        for row in removedRows {
            if let rowView = cachedRowViews[row] {
                if let delegate {
                    MainActor.assumeIsolated { delegate.tableView(self, didRemove: rowView, forRow: row) }
                }
            }
        }
        recacheRowViews { shiftedRowAfterRemoval(row: $0, removedRows: removedRows) }
        recacheCellViews { shiftedRowAfterRemoval(row: $0, removedRows: removedRows) }
        numberOfRows -= removedRows.count
        setSelectedRowIndexes(shiftedSelectionAfterRemoval(removedRows), notify: false)
        clickedRow = shiftedRowAfterRemoval(row: clickedRow, removedRows: removedRows) ?? -1
    }

    public func moveRow(at oldIndex: Int, to newIndex: Int) {
        guard oldIndex >= 0, oldIndex < numberOfRows, newIndex >= 0, newIndex < numberOfRows, oldIndex != newIndex else {
            return
        }

        recacheRowViews { movedRow(row: $0, from: oldIndex, to: newIndex) }
        recacheCellViews { movedRow(row: $0, from: oldIndex, to: newIndex) }
        setSelectedRowIndexes(movedSelection(from: oldIndex, to: newIndex), notify: false)
        clickedRow = clickedRow >= 0 ? movedRow(row: clickedRow, from: oldIndex, to: newIndex) : clickedRow
    }
    public func setDropRow(_ row: Int, dropOperation: DropOperation) {}
    public func enumerateAvailableRowViews(_ block: (NSTableRowView, Int) -> Void) {
        for row in cachedRowViews.keys.sorted() {
            if let rowView = cachedRowViews[row] {
                block(rowView, row)
            }
        }
    }

    public func noteHeightOfRows(withIndexesChanged indexes: IndexSet) {
        _ = indexes
    }

    public func row(for view: NSView) -> Int {
        if let row = cachedRowViews.first(where: { $0.value === view })?.key {
            return row
        }
        return cachedCellViews.first(where: { $0.value === view })?.key.row ?? -1
    }

    /// `row(at:)` — the row index under a point in the table's coordinates.
    /// WireGuard's LogViewController uses it to detect scrolled-to-end.
    /// Compile-stub (-1 = no row) until Qt-backed hit-testing lands.
    open func row(at point: NSPoint) -> Int { -1 }
    open func rect(ofRow row: Int) -> NSRect {
        guard row >= 0, row < numberOfRows else { return .zero }
        let y = CGFloat(row) * (rowHeight + intercellSpacing.height)
        let delegateHeight = heightOfRow(row)
        let height = delegateHeight > 0 ? delegateHeight : rowHeight
        return NSRect(x: 0, y: y, width: bounds.width, height: height)
    }
    open func rows(in rect: NSRect) -> NSRange {
        guard numberOfRows > 0 else { return NSRange(location: NSNotFound, length: 0) }
        let stride = max(rowHeight + intercellSpacing.height, 1)
        let start = max(0, Int(floor(rect.minY / stride)))
        guard start < numberOfRows else { return NSRange(location: NSNotFound, length: 0) }
        let end = min(numberOfRows, Int(ceil(rect.maxY / stride)))
        return NSRange(location: start, length: max(0, end - start))
    }

    public func column(for view: NSView) -> Int {
        cachedCellViews.first(where: { $0.value === view })?.key.column ?? -1
    }

    public func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        guard row >= 0 && row < numberOfRows && column >= 0 && column < tableColumns.count else {
            return .zero
        }
        let x = tableColumns.prefix(column).reduce(CGFloat(0)) { partial, tableColumn in
            partial + tableColumn.width + intercellSpacing.width
        }
        let y = CGFloat(row) * (rowHeight + intercellSpacing.height)
        let delegateHeight = heightOfRow(row)
        let height = delegateHeight > 0 ? delegateHeight : rowHeight
        return NSRect(x: x, y: y, width: tableColumns[column].width, height: height)
    }

    private func validInsertionRows(from rowIndexes: IndexSet) -> IndexSet {
        var validRows = IndexSet()
        for row in rowIndexes {
            guard row >= 0, row <= numberOfRows + validRows.count else { continue }
            validRows.insert(row)
        }
        return validRows
    }

    private func existingRows(from rowIndexes: IndexSet) -> IndexSet {
        var rows = IndexSet()
        for row in rowIndexes where row >= 0 && row < numberOfRows {
            rows.insert(row)
        }
        return rows
    }

    private func recacheRowViews(_ transform: (Int) -> Int?) {
        let oldRowViews = cachedRowViews
        cachedRowViews.removeAll()
        for (row, rowView) in oldRowViews {
            guard let nextRow = transform(row) else { continue }
            cachedRowViews[nextRow] = rowView
        }
    }

    private func recacheCellViews(_ transform: (Int) -> Int?) {
        let oldCellViews = cachedCellViews
        cachedCellViews.removeAll()
        for (key, view) in oldCellViews {
            guard let nextRow = transform(key.row) else { continue }
            cachedCellViews[CellKey(column: key.column, row: nextRow)] = view
        }
    }

    private func shiftedRowAfterInsertion(row: Int, insertedRows: IndexSet) -> Int {
        var shiftedRow = row
        for insertedRow in insertedRows where insertedRow <= shiftedRow {
            shiftedRow += 1
        }
        return shiftedRow
    }

    private func shiftedRowAfterRemoval(row: Int, removedRows: IndexSet) -> Int? {
        guard row >= 0, !removedRows.contains(row) else { return nil }
        var shiftedRow = row
        for removedRow in removedRows where removedRow < row {
            shiftedRow -= 1
        }
        return shiftedRow
    }

    private func movedRow(row: Int, from oldIndex: Int, to newIndex: Int) -> Int {
        if row == oldIndex {
            return newIndex
        }
        if oldIndex < newIndex, row > oldIndex, row <= newIndex {
            return row - 1
        }
        if newIndex < oldIndex, row >= newIndex, row < oldIndex {
            return row + 1
        }
        return row
    }

    private func shiftedSelectionAfterInsertion(_ insertedRows: IndexSet) -> IndexSet {
        var shiftedSelection = IndexSet()
        for row in selectedRowIndexes {
            shiftedSelection.insert(shiftedRowAfterInsertion(row: row, insertedRows: insertedRows))
        }
        return clampedRowIndexes(shiftedSelection)
    }

    private func shiftedSelectionAfterRemoval(_ removedRows: IndexSet) -> IndexSet {
        var shiftedSelection = IndexSet()
        for row in selectedRowIndexes {
            if let shiftedRow = shiftedRowAfterRemoval(row: row, removedRows: removedRows) {
                shiftedSelection.insert(shiftedRow)
            }
        }
        return clampedRowIndexes(shiftedSelection)
    }

    private func movedSelection(from oldIndex: Int, to newIndex: Int) -> IndexSet {
        var shiftedSelection = IndexSet()
        for row in selectedRowIndexes {
            shiftedSelection.insert(movedRow(row: row, from: oldIndex, to: newIndex))
        }
        return clampedRowIndexes(shiftedSelection)
    }

    private func clampedRowIndexes(_ rowIndexes: IndexSet) -> IndexSet {
        var clamped = IndexSet()
        for row in rowIndexes where row >= 0 && row < numberOfRows {
            clamped.insert(row)
            if !allowsMultipleSelection { break }
        }
        return clamped
    }

    private func setSelectedRowIndexes(_ rowIndexes: IndexSet, notify: Bool = true) {
        let oldSelection = selectedRowIndexes
        selectedRowIndexes = rowIndexes
        selectedRow = rowIndexes.first ?? -1
        for (row, rowView) in cachedRowViews {
            rowView.isSelected = rowIndexes.contains(row)
        }
        guard notify && oldSelection != rowIndexes else { return }
        let notification = Notification(name: Self.selectionDidChangeNotification, object: self)
        MainActor.assumeIsolated {
            if self is NSOutlineView,
               let outlineDelegate = delegate as? NSOutlineViewDelegate {
                outlineDelegate.outlineViewSelectionDidChange(notification)
            } else {
                delegate?.tableViewSelectionDidChange(notification)
            }
        }
    }

    fileprivate func replaceLoadedRows(count: Int, selectedRowIndexes rowIndexes: IndexSet? = nil) {
        numberOfRows = max(0, count)
        cachedRowViews.removeAll()
        cachedCellViews.removeAll()
        setSelectedRowIndexes(clampedRowIndexes(rowIndexes ?? selectedRowIndexes), notify: false)
    }

    private func shouldSelectRow(_ row: Int) -> Bool {
        MainActor.assumeIsolated {
            if let outlineView = self as? NSOutlineView,
               let item = outlineView.item(atRow: row),
               let outlineDelegate = delegate as? NSOutlineViewDelegate {
                return outlineDelegate.outlineView(outlineView, shouldSelectItem: item)
            }
            return delegate?.tableView(self, shouldSelectRow: row) ?? true
        }
    }

    private func makeRowView(forRow row: Int) -> NSTableRowView? {
        MainActor.assumeIsolated {
            if let outlineView = self as? NSOutlineView,
               let item = outlineView.item(atRow: row),
               let outlineDelegate = delegate as? NSOutlineViewDelegate {
                return outlineDelegate.outlineView(outlineView, rowViewForItem: item)
            }
            return delegate?.tableView(self, rowViewForRow: row)
        }
    }

    private func makeCellView(forColumn column: Int, row: Int) -> NSView? {
        let tableColumn = tableColumns[column]
        return MainActor.assumeIsolated {
            if let outlineView = self as? NSOutlineView,
               let item = outlineView.item(atRow: row),
               let outlineDelegate = delegate as? NSOutlineViewDelegate {
                return outlineDelegate.outlineView(outlineView, viewFor: tableColumn, item: item)
            }
            return delegate?.tableView(self, viewFor: tableColumn, row: row)
        }
    }

    private func heightOfRow(_ row: Int) -> CGFloat {
        MainActor.assumeIsolated {
            if let outlineView = self as? NSOutlineView,
               let item = outlineView.item(atRow: row),
               let outlineDelegate = delegate as? NSOutlineViewDelegate {
                return outlineDelegate.outlineView(outlineView, heightOfRowByItem: item)
            }
            return delegate?.tableView(self, heightOfRow: row) ?? 0
        }
    }

    private func shiftedColumnSelection(afterRemovingColumnAt removedIndex: Int) -> IndexSet {
        var shifted = IndexSet()
        for column in selectedColumnIndexes {
            if column < removedIndex {
                shifted.insert(column)
            } else if column > removedIndex {
                shifted.insert(column - 1)
            }
        }
        return shifted
    }

    public struct AnimationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let effectFade = AnimationOptions(rawValue: 1)
        public static let effectGap = AnimationOptions(rawValue: 2)
        public static let slideUp = AnimationOptions(rawValue: 0x10)
        public static let slideDown = AnimationOptions(rawValue: 0x20)
        public static let slideLeft = AnimationOptions(rawValue: 0x30)
        public static let slideRight = AnimationOptions(rawValue: 0x40)
    }
    public enum DropOperation: UInt, Sendable { case on, above }
}

/// Compat constraint for `NSTableView.dequeueReusableCell<T>()`, which constructs
/// a fresh cell via `T()`. On macOS that compiles because NSView is an `@objc`
/// class (the ObjC runtime guarantees `init()`); on Linux NSView is plain Swift,
/// so constructing a generic class value needs a `required init()`. Rather than
/// force `required init()` onto NSView (which would cascade to *every* NSView
/// subclass repo-wide), the WireGuard reuse extension is lowered to constrain its
/// cell type to `NSView & QuillReusableView`, and the handful of cell types it
/// dequeues conform (each with a `required init()`). App-agnostic: any AppKit app
/// whose `dequeueReusableCell` constructs `T()` reuses this.
public protocol QuillReusableView: AnyObject {
    init()
}

open class NSTableHeaderView: NSView {}
open class NSTableRowView: NSView {
    public var isSelected: Bool = false
    public var isEmphasized: Bool = false
    public var isGroupRowStyle: Bool = false
    open var backgroundColor: NSColor = .clear
}
open class NSTableCellView: NSView {
    public var textField: NSTextField?
    public var imageView: NSImageView?
    public var objectValue: Any?
    public var rowSizeStyle: NSTableView.RowSizeStyle = .default
    public var backgroundStyle: BackgroundStyle = .normal
    public enum BackgroundStyle: Int, Sendable { case normal, emphasized, raised, lowered }
}

// Apple parity (#512).
@preconcurrency @MainActor
open class NSTableColumn: NSObject {
    public var identifier: NSUserInterfaceItemIdentifier
    public var title: String = ""
    public var width: CGFloat = 100
    public var minWidth: CGFloat = 10
    public var maxWidth: CGFloat = 1000
    public var headerCell: Any?
    public var headerToolTip: String?
    public var sortDescriptorPrototype: NSSortDescriptor?
    public var resizingMask: ResizingOptions = []
    public var isHidden: Bool = false
    public var isEditable: Bool = true
    public init(identifier: NSUserInterfaceItemIdentifier) { self.identifier = identifier; super.init() }
    public override init() { self.identifier = NSUserInterfaceItemIdentifier(""); super.init() }
    public struct ResizingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let autoresizingMask = ResizingOptions(rawValue: 1 << 0)
        public static let userResizingMask = ResizingOptions(rawValue: 1 << 1)
    }
}

@preconcurrency @MainActor
public protocol NSTableViewDelegate: AnyObject {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView?
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat
    func tableViewSelectionDidChange(_ notification: Notification)
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int)
    func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int)
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor])
}
public extension NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { nil }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { nil }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 0 }
    func tableViewSelectionDidChange(_ notification: Notification) {}
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {}
    func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {}
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {}
}

@preconcurrency @MainActor
public protocol NSTableViewDataSource: AnyObject {
    func numberOfRows(in tableView: NSTableView) -> Int
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any?
}
public extension NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 0 }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { nil }
}

open class NSOutlineView: NSTableView {
    private enum OutlineItemKey: Hashable {
        case object(ObjectIdentifier)
        case hashable(AnyHashable)
        case description(String)
    }

    private struct VisibleOutlineItem {
        var item: Any
        var parent: Any?
        var level: Int
    }

    public var indentationPerLevel: CGFloat = 16
    public var indentationMarkerFollowsCell: Bool = true
    public var autoresizesOutlineColumn: Bool = true
    public var outlineTableColumn: NSTableColumn?
    public var autosaveExpandedItems: Bool = false

    private var expandedItems: Set<OutlineItemKey> = []
    private var visibleItems: [VisibleOutlineItem] = []
    private var rowByItem: [OutlineItemKey: Int] = [:]
    private var parentByItem: [OutlineItemKey: Any?] = [:]
    private var levelByItem: [OutlineItemKey: Int] = [:]

    private var outlineDataSource: NSOutlineViewDataSource? {
        dataSource as? NSOutlineViewDataSource
    }

    public override func reloadData() {
        let selectedItems = selectedRowIndexes.compactMap { row -> OutlineItemKey? in
            guard row >= 0 && row < visibleItems.count else { return nil }
            return key(for: visibleItems[row].item)
        }

        rebuildVisibleItems()

        var nextSelection = IndexSet()
        for (row, entry) in visibleItems.enumerated() {
            guard let key = key(for: entry.item), selectedItems.contains(key) else { continue }
            nextSelection.insert(row)
        }
        replaceLoadedRows(count: visibleItems.count, selectedRowIndexes: nextSelection)
    }

    public func reloadItem(_ item: Any?, reloadChildren: Bool = false) {
        reloadData()
    }

    public func expandItem(_ item: Any?) {
        expandItem(item, expandChildren: false)
    }

    public func expandItem(_ item: Any?, expandChildren: Bool) {
        guard let item, isExpandable(item), let key = key(for: item) else { return }
        expandedItems.insert(key)
        if expandChildren {
            expandDescendants(of: item)
        }
        reloadData()
        if let outlineDelegate = delegate as? NSOutlineViewDelegate {
            MainActor.assumeIsolated {
                outlineDelegate.outlineViewItemDidExpand(
                    Notification(name: Notification.Name("NSOutlineViewItemDidExpandNotification"), object: self)
                )
            }
        }
    }

    public func collapseItem(_ item: Any?) {
        collapseItem(item, collapseChildren: false)
    }

    public func collapseItem(_ item: Any?, collapseChildren: Bool) {
        guard let item else {
            expandedItems.removeAll()
            reloadData()
            return
        }
        if let key = key(for: item) {
            expandedItems.remove(key)
        }
        if collapseChildren {
            collapseDescendants(of: item)
        }
        reloadData()
        if let outlineDelegate = delegate as? NSOutlineViewDelegate {
            MainActor.assumeIsolated {
                outlineDelegate.outlineViewItemDidCollapse(
                    Notification(name: Notification.Name("NSOutlineViewItemDidCollapseNotification"), object: self)
                )
            }
        }
    }

    public func isItemExpanded(_ item: Any?) -> Bool {
        guard let key = key(for: item) else { return false }
        return expandedItems.contains(key)
    }

    public func item(atRow row: Int) -> Any? {
        guard row >= 0 && row < visibleItems.count else { return nil }
        return visibleItems[row].item
    }

    public func row(forItem item: Any?) -> Int {
        guard let key = key(for: item) else { return -1 }
        return rowByItem[key] ?? -1
    }

    public func parent(forItem item: Any?) -> Any? {
        guard let key = key(for: item) else { return nil }
        return parentByItem[key] ?? nil
    }

    public func childIndex(forItem item: Any) -> Int {
        let parent = parent(forItem: item)
        for index in 0..<numberOfChildren(ofItem: parent) {
            guard let candidate = child(index, ofItem: parent), itemsMatch(candidate, item) else { continue }
            return index
        }
        return -1
    }

    public func numberOfChildren(ofItem item: Any?) -> Int {
        MainActor.assumeIsolated {
            max(0, outlineDataSource?.outlineView(self, numberOfChildrenOfItem: item) ?? 0)
        }
    }

    public func child(_ index: Int, ofItem item: Any?) -> Any? {
        guard index >= 0 && index < numberOfChildren(ofItem: item) else { return nil }
        return MainActor.assumeIsolated {
            outlineDataSource?.outlineView(self, child: index, ofItem: item)
        }
    }

    public func selectRowIndexesInOutlineView(_ s: IndexSet) {
        selectRowIndexes(s, byExtendingSelection: false)
    }

    public func level(forItem item: Any?) -> Int {
        guard let key = key(for: item) else { return -1 }
        return levelByItem[key] ?? -1
    }

    public func level(forRow row: Int) -> Int {
        guard row >= 0 && row < visibleItems.count else { return -1 }
        return visibleItems[row].level
    }

    public func isExpandable(_ item: Any?) -> Bool {
        guard let item else { return false }
        return MainActor.assumeIsolated {
            outlineDataSource?.outlineView(self, isItemExpandable: item) ?? false
        }
    }

    private func rebuildVisibleItems() {
        visibleItems.removeAll()
        rowByItem.removeAll()
        parentByItem.removeAll()
        levelByItem.removeAll()
        appendChildren(of: nil, level: 0)
    }

    private func appendChildren(of parent: Any?, level: Int) {
        for index in 0..<numberOfChildren(ofItem: parent) {
            guard let item = child(index, ofItem: parent) else { continue }
            let row = visibleItems.count
            visibleItems.append(VisibleOutlineItem(item: item, parent: parent, level: level))
            if let key = key(for: item) {
                rowByItem[key] = row
                parentByItem[key] = parent
                levelByItem[key] = level
            }
            if isItemExpanded(item) {
                appendChildren(of: item, level: level + 1)
            }
        }
    }

    private func expandDescendants(of item: Any) {
        for index in 0..<numberOfChildren(ofItem: item) {
            guard let child = child(index, ofItem: item), isExpandable(child) else { continue }
            if let key = key(for: child) {
                expandedItems.insert(key)
            }
            expandDescendants(of: child)
        }
    }

    private func collapseDescendants(of item: Any) {
        for index in 0..<numberOfChildren(ofItem: item) {
            guard let child = child(index, ofItem: item) else { continue }
            if let key = key(for: child) {
                expandedItems.remove(key)
            }
            collapseDescendants(of: child)
        }
    }

    private func key(for item: Any?) -> OutlineItemKey? {
        guard let item else { return nil }
        if Mirror(reflecting: item).displayStyle == .class {
            return .object(ObjectIdentifier(item as AnyObject))
        }
        if let hashable = item as? AnyHashable {
            return .hashable(hashable)
        }
        return .description(String(reflecting: item))
    }

    private func itemsMatch(_ lhs: Any, _ rhs: Any) -> Bool {
        guard let lhsKey = key(for: lhs), let rhsKey = key(for: rhs) else { return false }
        return lhsKey == rhsKey
    }
}

@preconcurrency @MainActor
public protocol NSOutlineViewDelegate: NSTableViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView?
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView?
    func outlineViewSelectionDidChange(_ notification: Notification)
    func outlineViewItemDidExpand(_ notification: Notification)
    func outlineViewItemDidCollapse(_ notification: Notification)
}
public extension NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { nil }
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat { 0 }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { nil }
    func outlineViewSelectionDidChange(_ notification: Notification) {}
    func outlineViewItemDidExpand(_ notification: Notification) {}
    func outlineViewItemDidCollapse(_ notification: Notification) {}
}

@preconcurrency @MainActor
public protocol NSOutlineViewDataSource: NSTableViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any?
}
public extension NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { item ?? () }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? { nil }
}

// MARK: - Document support

// Apple parity (#512): NSDocument is @MainActor in the macOS SDK.
@preconcurrency @MainActor
open class NSDocument: NSObject {
    open var fileURL: URL?
    public var fileType: String?
    public var fileModificationDate: Date?
    private var explicitDisplayName: String?
    public var displayName: String {
        get { explicitDisplayName ?? fileURL?.lastPathComponent ?? "" }
        set { explicitDisplayName = newValue.isEmpty ? nil : newValue }
    }
    public var isDocumentEdited: Bool = false
    public var hasUnautosavedChanges: Bool = false
    public var windowControllers: [NSWindowController] = []
    open var windowForSheet: NSWindow? { windowControllers.first?.window }
    public weak var undoManager: UndoManager?
    private var changeCountDepth: Int = 0

    public override init() { super.init() }
    public init(contentsOf url: URL, ofType type: String) throws {
        super.init()
        self.fileURL = url
        self.fileType = type
    }
    open func makeWindowControllers() {}
    open func addWindowController(_ wc: NSWindowController) {
        if !windowControllers.contains(where: { $0 === wc }) {
            wc.document?.removeWindowController(wc)
            windowControllers.append(wc)
        }
        wc.document = self
    }
    open func removeWindowController(_ wc: NSWindowController) {
        windowControllers.removeAll { $0 === wc }
        if wc.document === self {
            wc.document = nil
        }
    }
    open func showWindows() {
        for windowController in windowControllers {
            windowController.showWindow(self)
        }
    }
    open func close() {
        for windowController in windowControllers {
            windowController.close()
        }
    }
    open func read(from url: URL, ofType typeName: String) throws {
        _ = (url, typeName)
    }
    open func read(from data: Data, ofType: String) throws {}
    open func data(ofType: String) throws -> Data { Data() }
    open func write(to url: URL, ofType: String) throws {}
    open func save(_ sender: Any?) { updateChangeCount(.changeCleared) }
    open func saveAs(_ sender: Any?) {}
    open func saveTo(_ sender: Any?) {}
    open func revertToSaved(_ sender: Any?) { updateChangeCount(.changeCleared) }
    open func updateChangeCount(_ change: ChangeType) {
        switch change {
        case .changeDone, .changeRedone, .changeReadOtherContents:
            changeCountDepth += 1
        case .changeUndone, .changeDiscardable:
            changeCountDepth = max(0, changeCountDepth - 1)
        case .changeCleared, .changeAutosaved:
            changeCountDepth = 0
        }
        isDocumentEdited = changeCountDepth > 0
        hasUnautosavedChanges = isDocumentEdited
    }
    @discardableResult
    open func presentError(_ error: any Error) -> Bool {
        _ = error
        return false
    }
    open func validateMenuItem(_ item: NSMenuItem) -> Bool {
        _ = item
        return true
    }
    public enum ChangeType: UInt, Sendable { case changeDone, changeUndone, changeRedone, changeCleared, changeReadOtherContents, changeAutosaved, changeDiscardable }
}

// Apple parity (#512).
@preconcurrency @MainActor
open class NSDocumentController: NSObject {
    public static let shared = NSDocumentController()
    public var documents: [NSDocument] = []
    public var currentDocument: NSDocument?
    public var documentClassNames: [String] = []
    public func addDocument(_ document: NSDocument) {
        if !documents.contains(where: { $0 === document }) {
            documents.append(document)
        }
        currentDocument = document
    }
    public func removeDocument(_ document: NSDocument) {
        documents.removeAll { $0 === document }
        if currentDocument === document {
            currentDocument = documents.last
        }
    }
    public func openDocument(withContentsOf url: URL, display: Bool, completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        if let document = documents.first(where: { $0.fileURL == url }) {
            currentDocument = document
            if display {
                document.showWindows()
            }
            completionHandler(document, true, nil)
            return
        }

        do {
            let document = try NSDocument(contentsOf: url, ofType: url.pathExtension)
            addDocument(document)
            if display {
                document.makeWindowControllers()
                document.showWindows()
            }
            completionHandler(document, false, nil)
        } catch {
            completionHandler(nil, false, error)
        }
    }
    public func newDocument(_ sender: Any?) {}
    public func openDocument(_ sender: Any?) {}
    @discardableResult
    public func presentError(_ error: any Error) -> Bool {
        _ = error
        return false
    }
}

// MARK: - NSHostingView / NSHostingController / NSViewRepresentable bridges

public class NSHostingView<Content>: NSView {
    public var rootView: Content
    public init(rootView: Content) { self.rootView = rootView; super.init(frame: .zero) }
    public var fittingSize: NSSize {
        let intrinsic = intrinsicContentSize
        if intrinsic != .zero { return intrinsic }
        if frame.size != .zero { return frame.size }
        return NSSize(width: 640, height: 420)
    }
    public override init(frame: NSRect) {
        fatalError("NSHostingView(frame:) requires a rootView")
    }
    /// Required NSCoding init (NSView's coder init is `required`). Like
    /// `init(frame:)`, unsupported — a generic SwiftUI root view cannot be
    /// unarchived.
    public required init?(coder: NSCoder) {
        fatalError("NSHostingView(coder:) requires a rootView")
    }
}

public class NSHostingController<Content>: NSViewController {
    public var rootView: Content
    public init(rootView: Content) { self.rootView = rootView; super.init(nibName: nil, bundle: nil) }
}

// NSViewRepresentable / NSViewControllerRepresentable moved to the SwiftUI
// shim (Sources/SwiftUIShim/NSViewRepresentable.swift) — Apple ships them in
// SwiftUI, not AppKit (`import AppKit` alone does not resolve them on macOS),
// and the old AnyObject-constrained shape here rejected every real STRUCT
// conformer (e.g. SolderScope's `struct MicroscopeView: NSViewRepresentable`).
// SwiftUI re-exports AppKit, so SwiftUI-importing files see both worlds.

// MARK: - NSStatusBar / NSStatusItem (menu-bar widgets)

// Apple parity (#512).
@preconcurrency @MainActor
open class NSStatusBar: NSObject {
    public static let system = NSStatusBar()
    public func statusItem(withLength: CGFloat) -> NSStatusItem { NSStatusItem() }
    public func removeStatusItem(_ item: NSStatusItem) {}
    public static var variableLength: CGFloat { -1 }
    public static var squareLength: CGFloat { -2 }
    public var thickness: CGFloat = 22
}

// Apple parity (#512).
@preconcurrency @MainActor
open class NSStatusItem: NSObject {
    public var button: NSStatusBarButton? = NSStatusBarButton()
    public var menu: NSMenu?
    public var length: CGFloat = -1
    /// Apple's status-item length sentinels live on NSStatusItem:
    /// `squareLength` = square item matching the bar height; `variableLength`
    /// = sized to content. WireGuard uses `NSStatusItem.squareLength`.
    public static var squareLength: CGFloat { -2 }
    public static var variableLength: CGFloat { -1 }
    public var visible: Bool = true
    public var behavior: Behavior = []
    public var autosaveName: String = ""
    public struct Behavior: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let removalAllowed = Behavior(rawValue: 1 << 1)
        public static let terminationOnRemoval = Behavior(rawValue: 1 << 2)
    }
}

open class NSStatusBarButton: NSButton {}

// MARK: - NSPopover / NSPopoverDelegate

open class NSPopover: NSResponder {
    public var contentViewController: NSViewController?
    public var contentSize: NSSize = .zero
    public var behavior: Behavior = .applicationDefined
    public var animates: Bool = true
    public var isShown: Bool = false
    public var isDetached: Bool = false
    public weak var delegate: NSPopoverDelegate?
    public private(set) var lastPresentationRect: NSRect = .zero
    public private(set) weak var lastPresentationView: NSView?
    public private(set) var lastPresentationEdge: NSRectEdge = .minY
    public enum Behavior: Int, Sendable { case applicationDefined, transient, semitransient }
    public func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        lastPresentationRect = positioningRect
        lastPresentationView = positioningView
        lastPresentationEdge = preferredEdge

        guard !isShown else { return }

        delegate?.popoverWillShow(Notification(name: .NSPopoverWillShow, object: self))
        isShown = true
        delegate?.popoverDidShow(Notification(name: .NSPopoverDidShow, object: self))
    }
    public func performClose(_ sender: Any?) {
        close()
    }
    public func close() {
        guard isShown else { return }
        guard delegate?.popoverShouldClose(self) ?? true else { return }

        delegate?.popoverWillClose(Notification(name: .NSPopoverWillClose, object: self))
        isShown = false
        delegate?.popoverDidClose(Notification(name: .NSPopoverDidClose, object: self))
    }
}

@preconcurrency @MainActor
public protocol NSPopoverDelegate: AnyObject {
    func popoverWillShow(_ notification: Notification)
    func popoverDidShow(_ notification: Notification)
    func popoverWillClose(_ notification: Notification)
    func popoverDidClose(_ notification: Notification)
    func popoverShouldClose(_ popover: NSPopover) -> Bool
}
public extension NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {}
    func popoverDidShow(_ notification: Notification) {}
    func popoverWillClose(_ notification: Notification) {}
    func popoverDidClose(_ notification: Notification) {}
    func popoverShouldClose(_ popover: NSPopover) -> Bool { true }
}

public extension NSNotification.Name {
    static let NSPopoverWillShow = NSNotification.Name(rawValue: "NSPopoverWillShowNotification")
    static let NSPopoverDidShow = NSNotification.Name(rawValue: "NSPopoverDidShowNotification")
    static let NSPopoverWillClose = NSNotification.Name(rawValue: "NSPopoverWillCloseNotification")
    static let NSPopoverDidClose = NSNotification.Name(rawValue: "NSPopoverDidCloseNotification")
}

// MARK: - NSVisualEffectView / NSGlassEffectView

open class NSVisualEffectView: NSView {
    public var material: Material = .titlebar
    public var blendingMode: BlendingMode = .behindWindow
    public var state: State = .followsWindowActiveState
    public var isEmphasized: Bool = false
    public var maskImage: NSImage?
    public enum Material: Int, Sendable {
        case light = 0, dark = 1, ultraDark = 2
        case titlebar = 3, selection = 4, menu = 5, popover = 6, sidebar = 7, headerView = 10
        case sheet = 11, windowBackground = 12, hudWindow = 13, fullScreenUI = 15
        case toolTip = 17, contentBackground = 18, underWindowBackground = 21, underPageBackground = 22
    }
    public enum BlendingMode: Int, Sendable { case behindWindow, withinWindow }
    public enum State: Int, Sendable { case followsWindowActiveState, active, inactive }
}

open class NSGlassEffectView: NSView {
    public var contentView: NSView?
    public var cornerRadius: CGFloat = 0
    public var tintColor: NSColor?
}

// MARK: - NSAnimationContext

// Apple parity (#512).
@preconcurrency @MainActor
open class NSAnimationContext: NSObject {
    public static var current: NSAnimationContext = NSAnimationContext()
    public var duration: TimeInterval = 0.25
    public var timingFunction: CAMediaTimingFunction?
    public var allowsImplicitAnimation: Bool = false
    public var completionHandler: (() -> Void)?
    public static func runAnimationGroup(_ block: (NSAnimationContext) -> Void, completionHandler: (() -> Void)? = nil) {
        block(.current)
        completionHandler?()
    }
    public static func runAnimationGroup(_ block: (NSAnimationContext) -> Void) {
        block(.current)
    }
    public static func beginGrouping() {}
    public static func endGrouping() {}
}

// MARK: - NSHapticFeedback

open class NSHapticFeedbackManager: NSObject {
    public static func defaultPerformer() -> NSHapticFeedbackPerformer { _DefaultPerformer() }
}
public protocol NSHapticFeedbackPerformer: AnyObject {
    func perform(_ pattern: FeedbackPattern, performanceTime: PerformanceTime)
    typealias FeedbackPattern = NSHapticFeedbackPattern
    typealias PerformanceTime = NSHapticFeedbackPerformanceTime
}
private final class _DefaultPerformer: NSObject, NSHapticFeedbackPerformer {
    func perform(_ pattern: NSHapticFeedbackPattern, performanceTime: NSHapticFeedbackPerformanceTime) {}
}
public enum NSHapticFeedbackPattern: Int, Sendable { case generic, alignment, levelChange }
public enum NSHapticFeedbackPerformanceTime: Int, Sendable { case `default`, now, drawCompleted }

// MARK: - NSSharingService / NSSound / NSItemProvider helpers / NSDraggingInfo

open class NSSharingService: NSObject, @unchecked Sendable {
    public var recipients: [String] = []
    public var subject: String = ""

    public init?(named: NSSharingService.Name) {}
    public func canPerform(withItems items: [Any]) -> Bool {
        _ = items
        return false
    }
    public func perform(withItems: [Any]) {}
    public struct Name: RawRepresentable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let postOnTwitter = Name(rawValue: "")
        public static let composeMessage = Name(rawValue: "")
        public static let composeEmail = Name(rawValue: "")
    }
    public static func sharingServices(forItems: [Any]) -> [NSSharingService] { [] }
}

open class NSSpeechSynthesizer: NSObject, @unchecked Sendable {
    public init?(voice: String?) {
        _ = voice
        super.init()
    }

    public func startSpeaking(_ string: String) -> Bool {
        _ = string
        return false
    }

    public func stopSpeaking() {}
}

open class NSSound: NSObject, @unchecked Sendable {
    private let quillPlayerID = UUID()

    public init?(named: String) {
        super.init()
        QuillAudioPlayerService.shared.registerPlayer(
            quillPlayerID,
            source: .named(named)
        )
    }

    public init?(contentsOf url: URL, byReference: Bool) {
        super.init()
        QuillAudioPlayerService.shared.registerPlayer(
            quillPlayerID,
            source: .url(url)
        )
    }

    public init?(data: Data) {
        super.init()
        QuillAudioPlayerService.shared.registerPlayer(
            quillPlayerID,
            source: .data(byteCount: data.count)
        )
    }

    public func play() -> Bool {
        QuillAudioPlayerService.shared.play(playerID: quillPlayerID)
    }

    public func stop() -> Bool {
        QuillAudioPlayerService.shared.stop(playerID: quillPlayerID)
    }

    /// Phase B: emits the terminal bell character (BEL, \x07) to stderr.
    /// Most terminal emulators map this to either a flash or an audible
    /// tone depending on user preference, which is the closest Linux
    /// analogue to Apple's NSSound.beep() system alert.
    public static func beep() {
        QuillAudioPlayerService.shared.beep()
        FileHandle.standardError.write(Data([0x07]))
    }
}

public protocol NSDraggingInfo: AnyObject {
    var draggingPasteboard: NSPasteboard { get }
    var draggingLocation: NSPoint { get }
    var draggingSource: Any? { get }
    var draggingSourceOperationMask: NSDragOperation { get }
    var draggingSequenceNumber: Int { get }
    var draggingFormation: NSDraggingFormation { get set }
    var animatesToDestination: Bool { get set }
    var numberOfValidItemsForDrop: Int { get set }
}
public enum NSDraggingFormation: Int, Sendable { case `default`, none, pile, list, stack }
public struct NSDragOperation: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let none: NSDragOperation = []
    public static let copy = NSDragOperation(rawValue: 1)
    public static let link = NSDragOperation(rawValue: 2)
    public static let generic = NSDragOperation(rawValue: 4)
    public static let `private` = NSDragOperation(rawValue: 8)
    public static let move = NSDragOperation(rawValue: 16)
    public static let delete = NSDragOperation(rawValue: 32)
    public static let every: NSDragOperation = [.copy, .link, .generic, .private, .move, .delete]
}

// MARK: - Accessibility

open class NSAccessibility: NSObject {}
public protocol NSAccessibilityProtocol {}

// MARK: - NSUserInterfaceItemIdentifier

public struct NSUserInterfaceItemIdentifier: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Apple's unlabeled convenience init (`NSUserInterfaceItemIdentifier("x")`),
    /// used by WireGuard's table-column setup.
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

// MARK: - NSEnvironmentKey for SwiftUI windowing (the `\.window` key that
//          some views read; SwiftUI shim re-exports the protocol).

public struct NSWindowEnvironmentKey {
    public static let defaultValue: NSWindow? = nil
}

// MARK: - NSCell (legacy, but referenced)

// Apple parity (#512): Apple's NSCell is @MainActor (NSPopUpButtonCell
// inherits). @unchecked Sendable retained — pre-existing deviation (Apple's
// NSCell is not Sendable); inert under minimal checking and existing
// cross-actor storage keeps compiling.
@preconcurrency @MainActor
open class NSCell: NSObject, @unchecked Sendable {
    // nonisolated: pure storage (empty), so isolated-and-nonisolated init
    // paths alike (e.g. NSPopUpButton's nonisolated init(frame:)) can construct
    // cells; also required to override NSObject's nonisolated init().
    nonisolated public override init() {}
    public var title: String = ""
    public var stringValue: String = ""
    public var representedObject: Any?
    public var isEditable: Bool = false
    public var isEnabled: Bool = true
    public var state: NSControl.StateValue = .off
    public var alignment: NSTextAlignment = .natural
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public var truncatesLastVisibleLine: Bool = false
    public var wraps: Bool = false
    public var allowsMixedState: Bool = false
}

// MARK: - Selection-related types

open class NSResponderChain: NSObject {}

// MARK: - NSXPCConnection (used by services)

open class NSXPCConnection: NSObject, @unchecked Sendable {
    public init(serviceName: String) {}
    public init(machServiceName: String, options: Options = []) {}
    public init(listenerEndpoint: NSXPCListenerEndpoint) {}
    public var remoteObjectInterface: NSXPCInterface?
    public var exportedInterface: NSXPCInterface?
    public var exportedObject: Any?
    public func resume() {}
    public func suspend() {}
    public func invalidate() {}
    public func remoteObjectProxy() -> Any? { nil }
    public func remoteObjectProxyWithErrorHandler(_ h: @escaping (Error) -> Void) -> Any? { nil }
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let privileged = Options(rawValue: 1 << 12)
    }
}
open class NSXPCListenerEndpoint: NSObject, @unchecked Sendable {}
open class NSXPCInterface: NSObject, @unchecked Sendable {
    public init(with: Any) {}
    public static func interface(with: Any) -> NSXPCInterface { NSXPCInterface(with: ()) }
}

// MARK: - Globals

public func NSHumanReadableCopyright() -> String { "" }
public func NSFullUserName() -> String {
    ProcessInfo.processInfo.environment["USER"] ?? "user"
}
public func NSFindPanelAction() {}

// MARK: - File handle availability notification helper used by some
// IDE-shaped apps' subprocess plumbing

public extension NSNotification.Name {
    static let NSFileHandleDataAvailable = NSNotification.Name(rawValue: "NSFileHandleDataAvailableNotification")
}

#endif // os(Linux)
