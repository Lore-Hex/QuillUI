// QuillFoundation
// =================
// Cross-platform Foundation re-exports plus the small set of Foundation-shaped
// types that don't fit anywhere more specific. Anything UIKit-, WebKit-, or
// NetNewsWire-RSCore-shaped lives in QuillUIKit / QuillWebKit / QuillRS.
//
// On macOS / iOS this is mostly a thin re-export. On Linux this is also where
// CGFloat / CGPoint / CGSize / CGRect originate (since Foundation on Linux
// doesn't ship CoreGraphics).

@_exported import Foundation
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

#if canImport(ObjectiveC)
import ObjectiveC
#else
// Linux: no Objective-C runtime. Provide a Selector stub so the many
// UIKit-shaped APIs in QuillUIKit (UIBarButtonItem, UICommand, etc.)
// can be declared without conditional compilation around each one.
public struct Selector: Hashable, Sendable {
    public let name: String
    public init(_ name: String = "") { self.name = name }
}
#endif

// MARK: - Apple-platform image / color / font / screen typealiases

#if os(macOS)
@_exported import AppKit
@_exported import CoreGraphics
@_exported import WebKit

public typealias RSImage = NSImage
public typealias RSColor = NSColor
public typealias RSFont = NSFont
public typealias RSScreen = NSScreen
public typealias UIImage = NSImage
public typealias UIColor = NSColor
public typealias UIWindow = NSWindow

public extension NSImage {
    func dataRepresentation() -> Data? {
        return self.tiffRepresentation
    }
    static var smartBadgeTemplateName: String { "NSActionTemplate" }
    func tinted(with color: NSColor) -> NSImage { self }
    static func image(with data: Data, imageResultBlock: @escaping (NSImage?) -> Void) {
        imageResultBlock(NSImage(data: data))
    }
    static func image(data: Data) async -> NSImage? {
        return NSImage(data: data)
    }
    static func scaledImageData(_ data: Data, maxPixelSize: Int) -> Data? { data }
    func maskWithColor(color: CGColor) -> NSImage? { self }

    convenience init?(systemName: String, withConfiguration: Any? = nil) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    struct SymbolConfiguration {
        public init(pointSize: CGFloat, weight: Any) {}
        public init(textStyle: Any) {}
    }
}

public extension NSScreen {
    static var maxScreenScale: CGFloat { 2.0 }
}

#elseif os(iOS)
@_exported import UIKit
@_exported import CoreGraphics
@_exported import WebKit

public typealias RSImage = UIImage
public typealias RSColor = UIColor
public typealias RSFont = UIFont
public typealias RSScreen = UIScreen

public extension UIImage {
    func dataRepresentation() -> Data? { self.pngData() }
    func tinted(with color: UIColor) -> UIImage { self }
    static func image(with data: Data, imageResultBlock: @escaping (UIImage?) -> Void) {
        imageResultBlock(UIImage(data: data))
    }
    static func image(data: Data) async -> UIImage? { UIImage(data: data) }
    static func scaledImageData(_ data: Data, maxPixelSize: Int) -> Data? { data }
    func maskWithColor(color: CGColor) -> UIImage? { self }
}

public extension UIScreen {
    static var maxScreenScale: CGFloat { 2.0 }
}
#else

// MARK: - Linux native types
//
// CGFloat / CGPoint / CGSize / CGRect are provided by Foundation on
// Linux since Swift 5.1 — declaring our own causes "ambiguous for type
// lookup" in upstream code. CGImage is the only Apple type we still
// stub here (Linux Foundation has no equivalent).

public class CGImage {}

public class RSImage: NSObject, @unchecked Sendable {
    public override init() {}
    public init?(data: Data) {
        super.init()
        self.data = data
    }
    public init?(named: String) {}
    public init?(systemName: String, withConfiguration: Any? = nil) {}
    public init(size: CGSize) {
        super.init()
        self.size = size
    }
    public struct SymbolConfiguration {
        public init(pointSize: CGFloat, weight: Any) {}
        public init(textStyle: Any) {}
    }
    public var size: CGSize = CGSize(width: 0, height: 0)
    /// Raw image bytes when the instance was constructed from
    /// `init?(data:)`. Mirrors the `NSImage(data:)` source-
    /// compatibility shape — readers reach back to the original
    /// bytes for re-encoding (e.g. `tiffRepresentation`).
    public var data: Data?
    public func pngData() -> Data? { nil }
    public func dataRepresentation() -> Data? { nil }
    public func tinted(with: Any) -> RSImage { self }
    public static func image(with data: Data, imageResultBlock: @escaping (RSImage?) -> Void) {
        imageResultBlock(RSImage())
    }
    public static func image(data: Data) async -> RSImage? { RSImage() }
    public static func scaledImageData(_ data: Data, maxPixelSize: Int) -> Data? { data }
    public static var smartBadgeTemplateName: String { "" }
    public func maskWithColor(color: Any) -> RSImage? { self }
}
public typealias UIImage = RSImage

public class RSColor: NSObject, @unchecked Sendable {
    // Phase B: real RGBA storage so callers get sensible values back
    // from .redComponent / .cgColor / etc. Stored under underscore-
    // prefixed names so static peers like `NSColor.red` (an extension)
    // don't shadow the instance accessors at lookup.
    public let _red: CGFloat
    public let _green: CGFloat
    public let _blue: CGFloat
    public let _alpha: CGFloat

    public override init() {
        self._red = 0; self._green = 0; self._blue = 0; self._alpha = 1
    }
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self._red = red; self._green = green; self._blue = blue; self._alpha = alpha
    }

    public static let clear = RSColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let white = RSColor(red: 1, green: 1, blue: 1, alpha: 1)
    public static let black = RSColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let orange = RSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1)

    /// Returns a 4-tuple [R, G, B, A]. Matches CGColor.components shape.
    public var cgColor: Any? { [_red, _green, _blue, _alpha] }
    public var components: [CGFloat]? { [_red, _green, _blue, _alpha] }
    public var numberOfComponents: Int { 4 }
}
public typealias UIColor = RSColor

public class RSFont: NSObject, @unchecked Sendable {
    public let pointSize: CGFloat
    public init(pointSize: CGFloat) { self.pointSize = pointSize }
    public override init() { self.pointSize = 13 }
    public static func systemFont(ofSize size: CGFloat) -> RSFont { RSFont(pointSize: size) }
    public enum Weight { case regular, bold }
}
public typealias UIFont = RSFont

public class RSScreen: NSObject, @unchecked Sendable {
    public static let main = RSScreen()
    public let bounds: CGRect
    public override init() {
        // Phase B: read real geometry from environment if available.
        // Honors GDK_SCALE / QUILL_SCREEN env vars; falls back to a
        // sane default so headless tools that just probe .bounds get
        // a non-degenerate rect.
        let env = ProcessInfo.processInfo.environment
        if let s = env["QUILL_SCREEN"],
           let parts = Optional(s.split(separator: "x")), parts.count == 2,
           let w = Double(parts[0]), let h = Double(parts[1]) {
            self.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        } else {
            self.bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
    }
    public static var maxScreenScale: CGFloat { 2.0 }
    public var backingScaleFactor: CGFloat {
        Double(ProcessInfo.processInfo.environment["GDK_SCALE"] ?? "1").map { CGFloat($0) } ?? 1
    }
    public var visibleFrame: CGRect { bounds }
    public var frame: CGRect { bounds }
    public var depth: Int { 32 }
    public var deviceDescription: [String: Any] { [:] }
}
public typealias UIScreen = RSScreen
#endif

// MARK: - CGImage luminance (cross-platform)

public enum ImageLuminanceType: Int, Sendable {
    case regular, dark, bright
}

#if canImport(CoreGraphics)
public extension CGImage {
    func calculateLuminanceType() -> ImageLuminanceType? { .regular }
}
#else
public extension CGImage {
    func calculateLuminanceType() -> ImageLuminanceType? { .regular }
}
#endif

// MARK: - Localization

#if !os(macOS) && !os(iOS)
public func NSLocalizedString(_ key: String, comment: String) -> String { key }
#endif

// MARK: - SQL placeholder helper
//
// `NSString.rs_SQLValueList(withPlaceholders:)` is canonically declared
// upstream in RSDatabaseObjC's NSString+RSDatabase.h. We don't redeclare
// it here — doing so caused a "type of expression is ambiguous" error
// in SyncDatabase / ArticlesDatabase where both definitions were visible.

// MARK: - Bootstrapping

public enum QuillBootstrapper {
    public static func bootstrap() {}
}
