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
@_exported import QuillUIKit
import QuillKit
import Glibc

// MARK: - UndoManager (missing from Linux Foundation)

open class UndoManager: NSObject, @unchecked Sendable {
    private struct UndoAction {
        var targetIDs: Set<ObjectIdentifier>
        var name: String
        var grouped: Bool
        var invoke: () -> Void
    }

    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []
    private var actionGroups: [[UndoAction]] = []
    private var undoing = false
    private var redoing = false
    private var registrationEnabled = true

    public override init() {
        super.init()
    }

    public func registerUndo<T: AnyObject>(withTarget target: T, handler: @escaping (T) -> Void) {
        guard registrationEnabled else { return }

        let action = UndoAction(
            targetIDs: [ObjectIdentifier(target)],
            name: undoActionName,
            grouped: false,
            invoke: { [weak target] in
                guard let target else { return }
                handler(target)
            }
        )

        if !actionGroups.isEmpty {
            actionGroups[actionGroups.count - 1].append(action)
        } else if undoing {
            appendRedoAction(action)
        } else if redoing {
            appendUndoAction(action, clearsRedo: false)
        } else {
            appendUndoAction(action, clearsRedo: true)
        }
    }

    public func beginUndoGrouping() {
        actionGroups.append([])
    }

    public func endUndoGrouping() {
        guard let group = actionGroups.popLast(), !group.isEmpty else { return }

        let groupedAction = makeGroupedAction(from: group, name: group.last?.name ?? "")

        if actionGroups.isEmpty {
            appendUndoAction(groupedAction, clearsRedo: true)
        } else {
            actionGroups[actionGroups.count - 1].append(groupedAction)
        }
    }

    public func undo() {
        guard let action = undoStack.popLast() else { return }
        undoing = true
        if action.grouped {
            actionGroups.append([])
        }
        action.invoke()
        let inverseGroup = action.grouped ? actionGroups.popLast() : nil
        undoing = false
        if let inverseGroup, !inverseGroup.isEmpty {
            appendRedoAction(makeGroupedAction(from: inverseGroup, name: action.name))
        }
        redoActionName = action.name
    }

    public func redo() {
        guard let action = redoStack.popLast() else { return }
        redoing = true
        if action.grouped {
            actionGroups.append([])
        }
        action.invoke()
        let inverseGroup = action.grouped ? actionGroups.popLast() : nil
        redoing = false
        if let inverseGroup, !inverseGroup.isEmpty {
            appendUndoAction(makeGroupedAction(from: inverseGroup, name: action.name), clearsRedo: false)
        }
        undoActionName = action.name
    }

    public func removeAllActions() {
        undoStack.removeAll()
        redoStack.removeAll()
        actionGroups.removeAll()
    }

    public func removeAllActions(withTarget target: Any) {
        guard let object = target as? AnyObject else { return }
        let targetID = ObjectIdentifier(object)
        undoStack.removeAll { $0.targetIDs.contains(targetID) }
        redoStack.removeAll { $0.targetIDs.contains(targetID) }
        actionGroups = actionGroups.map { group in
            group.filter { !$0.targetIDs.contains(targetID) }
        }
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var groupsByEvent: Bool = true
    public var levelsOfUndo: Int = 0 {
        didSet {
            trimUndoStack()
            trimRedoStack()
        }
    }
    public var undoActionName: String = ""
    public var redoActionName: String = ""
    public func setActionName(_ name: String) { undoActionName = name }
    public var isUndoing: Bool { undoing }
    public var isRedoing: Bool { redoing }
    public func disableUndoRegistration() { registrationEnabled = false }
    public func enableUndoRegistration() { registrationEnabled = true }
    public var isUndoRegistrationEnabled: Bool { registrationEnabled }

    private func appendUndoAction(_ action: UndoAction, clearsRedo: Bool) {
        undoStack.append(action)
        trimUndoStack()
        if clearsRedo {
            redoStack.removeAll()
        }
    }

    private func appendRedoAction(_ action: UndoAction) {
        redoStack.append(action)
        trimRedoStack()
    }

    private func makeGroupedAction(from group: [UndoAction], name: String) -> UndoAction {
        UndoAction(
            targetIDs: Set(group.flatMap(\.targetIDs)),
            name: name,
            grouped: true,
            invoke: {
                for action in group.reversed() {
                    action.invoke()
                }
            }
        )
    }

    private func trimUndoStack() {
        guard levelsOfUndo > 0, undoStack.count > levelsOfUndo else { return }
        undoStack.removeFirst(undoStack.count - levelsOfUndo)
    }

    private func trimRedoStack() {
        guard levelsOfUndo > 0, redoStack.count > levelsOfUndo else { return }
        redoStack.removeFirst(redoStack.count - levelsOfUndo)
    }
}

// MARK: - Geometry typealiases (NS variants of CG types)

public typealias NSPoint = CGPoint
public typealias NSSize = CGSize
public typealias NSRect = CGRect
public typealias NSEdgeInsets = (top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat)
public typealias NSRectPointer = UnsafeMutablePointer<NSRect>

// NSStringFromRect and NSRectFromString come from Foundation through QuillFoundation.

public let NSNotFound: Int = Int.max

// MARK: - NSImage / NSColor / NSFont / NSScreen
//
// These are typealiased to the cross-platform RS* types in
// QuillFoundation, so `NSImage` and `UIImage` resolve to the same
// underlying class on Linux.

public typealias NSImage = RSImage
public typealias NSColor = RSColor
public typealias NSFont = RSFont
public typealias NSScreen = RSScreen

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

    public init?(data: Data) {
        self.data = data
    }

    public func representation(
        using storageType: FileType,
        properties: [PropertyKey: Any]
    ) -> Data? {
        // Pass-through. Real format conversion needs a codec
        // backend; until then return the source bytes so callers
        // (e.g. Enchanted's base64 upload) see non-empty data.
        data
    }

    /// Looser key signature for upstream call sites that hand in
    /// `[String: Any]` or `[NSString: Any]` property dictionaries.
    public func representation<K, V>(
        using storageType: FileType,
        properties: [K: V]
    ) -> Data? {
        data
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

    struct Name: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
    }

    convenience init(name: NSColor.Name?, dynamicProvider: @escaping (NSAppearance) -> NSColor) {
        self.init()
    }
    convenience init(white: CGFloat, alpha: CGFloat) { self.init() }
    convenience init(deviceWhite: CGFloat, alpha: CGFloat) { self.init() }
    convenience init(calibratedWhite: CGFloat, alpha: CGFloat) { self.init() }
    convenience init(srgbRed: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.init() }
    convenience init(deviceRed: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.init() }
    convenience init(calibratedRed: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { self.init() }
    convenience init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) { self.init() }

    func withAlphaComponent(_ alpha: CGFloat) -> NSColor { self }
    func blended(withFraction f: CGFloat, of c: NSColor) -> NSColor? { self }
    func usingColorSpace(_ space: Any) -> NSColor? { self }
    var redComponent: CGFloat { _red }
    var greenComponent: CGFloat { _green }
    var blueComponent: CGFloat { _blue }
    var alphaComponent: CGFloat { _alpha }
    var hueComponent: CGFloat { 0 }
    var saturationComponent: CGFloat { 0 }
    var brightnessComponent: CGFloat { 0 }
}

public extension NSFont {
    static func systemFont(ofSize: CGFloat, weight: NSFont.Weight) -> NSFont { NSFont() }
    static func boldSystemFont(ofSize: CGFloat) -> NSFont { NSFont() }
    static func monospacedSystemFont(ofSize: CGFloat, weight: NSFont.Weight) -> NSFont { NSFont() }
    static func monospacedDigitSystemFont(ofSize: CGFloat, weight: NSFont.Weight) -> NSFont { NSFont() }
    static var labelFontSize: CGFloat { 13 }
    static var systemFontSize: CGFloat { 13 }
    static var smallSystemFontSize: CGFloat { 11 }

    var pointSize: CGFloat { 13 }
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

open class NSResponder: NSObject {
    fileprivate weak var quillExplicitNextResponder: NSResponder?

    public override init() {}
    open var nextResponder: NSResponder? {
        get { quillExplicitNextResponder }
        set { quillExplicitNextResponder = newValue }
    }
    open func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
    open func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
    open func mouseDragged(with event: NSEvent) { nextResponder?.mouseDragged(with: event) }
    open func mouseMoved(with event: NSEvent) { nextResponder?.mouseMoved(with: event) }
    open func keyDown(with event: NSEvent) { nextResponder?.keyDown(with: event) }
    open func keyUp(with event: NSEvent) { nextResponder?.keyUp(with: event) }
    open func flagsChanged(with event: NSEvent) { nextResponder?.flagsChanged(with: event) }
    open func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
    open var acceptsFirstResponder: Bool { false }
    open func becomeFirstResponder() -> Bool { true }
    open func resignFirstResponder() -> Bool { true }
}

open class NSView: NSResponder {
    public var frame: NSRect = .zero {
        didSet {
            guard frame != oldValue else { return }
            quillUpdateBoundsSize(from: oldValue.size, to: frame.size)
            needsLayout = true
        }
    }
    public var bounds: NSRect = .zero {
        didSet {
            if bounds != oldValue {
                needsLayout = true
            }
        }
    }
    public var subviews: [NSView] = []
    public weak var superview: NSView?
    public weak var window: NSWindow?
    public var isHidden: Bool = false
    public var alphaValue: CGFloat = 1
    public var wantsLayer: Bool = false
    public var layer: Any?
    public var translatesAutoresizingMaskIntoConstraints: Bool = true
    public var needsLayout: Bool = true
    private var quillNeedsDisplay: Bool = false
    public var needsDisplay: Bool {
        get { window == nil ? false : quillNeedsDisplay }
        set {
            guard newValue else { return }
            quillMarkNeedsDisplay()
        }
    }
    public var clipsToBounds: Bool = false
    public var autoresizingMask: AutoresizingMask = []
    public var identifier: NSUserInterfaceItemIdentifier?

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

    public override init() { super.init() }
    public init(frame: NSRect) {
        super.init()
        self.frame = frame
        bounds = NSRect(origin: .zero, size: frame.size)
    }

    public func addSubview(_ v: NSView) {
        insertSubview(v, at: subviews.count)
    }

    public func addSubview(_ v: NSView, positioned: NSWindow.OrderingMode, relativeTo: NSView?) {
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

    public func removeFromSuperview() {
        guard let parent = superview else { return }
        viewWillMove(toSuperview: nil)
        parent.subviews.removeAll { $0 === self }
        superview = nil
        quillMoveWindowRecursively(nil)
        parent.quillMarkNeedsDisplay()
        viewDidMoveToSuperview()
    }
    public func setFrameSize(_ s: NSSize) { frame.size = s }
    public func setFrameOrigin(_ p: NSPoint) { frame.origin = p }
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

    open func displayIfNeeded() {
        quillDisplayIfWindowBacked()
    }

    open func displayIfNeededIgnoringOpacity() {
        quillDisplayIfWindowBacked()
    }

    public func setNeedsDisplay(_ rect: NSRect) {
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

    public func hitTest(_ p: NSPoint) -> NSView? {
        guard !isHidden, quillBoundsContains(p) else { return nil }

        for child in subviews.reversed() {
            let childPoint = child.convert(p, from: self)
            if let hitView = child.hitTest(childPoint) {
                return hitView
            }
        }

        return self
    }

    public var topAnchor = NSLayoutYAxisAnchor()
    public var bottomAnchor = NSLayoutYAxisAnchor()
    public var leadingAnchor = NSLayoutXAxisAnchor()
    public var trailingAnchor = NSLayoutXAxisAnchor()
    public var widthAnchor = NSLayoutDimension()
    public var heightAnchor = NSLayoutDimension()
    public var centerXAnchor = NSLayoutXAxisAnchor()
    public var centerYAnchor = NSLayoutYAxisAnchor()
    public var firstBaselineAnchor = NSLayoutYAxisAnchor()
    public var lastBaselineAnchor = NSLayoutYAxisAnchor()

    open func layout() {}
    open func draw(_ rect: NSRect) {}
    open func viewWillDraw() {}
    open func viewWillMove(toWindow: NSWindow?) {}
    open func viewDidMoveToWindow() {}
    open func viewWillMove(toSuperview: NSView?) {}
    open func viewDidMoveToSuperview() {}
    open func updateTrackingAreas() {}
    open func resetCursorRects() {}

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

        child.viewDidMoveToSuperview()
    }

    private func quillMarkNeedsDisplay() {
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
    private var quillView: NSView = NSView()
    public var view: NSView {
        get {
            if quillView.quillExplicitNextResponder == nil {
                quillView.nextResponder = self
            }
            return quillView
        }
        set {
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
    public override init() { super.init() }
    open func viewDidLoad() {}
    open func viewWillAppear() {}
    open func viewDidAppear() {}
    open func viewWillDisappear() {}
    open func viewDidDisappear() {}
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
    public func showWindow(_ sender: Any?) { window?.makeKeyAndOrderFront(sender) }
    public func close() { window?.close() }
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

@MainActor public protocol NSWindowDelegate: AnyObject {
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
    public var isVisible: Bool = false
    public var isMiniaturized: Bool = false
    public var isZoomed: Bool = false
    public var isKeyWindow: Bool = false
    public var isMainWindow: Bool = false
    public var canBecomeKey: Bool = true
    public var canBecomeMain: Bool = true
    public var level: Level = .normal
    public var alphaValue: CGFloat = 1
    public var animationBehavior: AnimationBehavior = .default
    public var toolbar: NSToolbar?
    public var toolbarStyle: ToolbarStyle = .automatic
    public var contentMinSize: NSSize = .zero
    public var contentMaxSize: NSSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    public var minSize: NSSize = .zero
    public var maxSize: NSSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    public var aspectRatio: NSSize = .zero
    public var contentAspectRatio: NSSize = .zero
    public var contentResizeIncrements: NSSize = .zero
    public var frameAutosaveName: String = ""
    public var identifier: NSUserInterfaceItemIdentifier?
    public var firstResponder: NSResponder?
    public var screen: NSScreen? { .main }
    public var representedURL: URL?
    public var appearance: NSAppearance?
    public var effectiveAppearance: NSAppearance = NSAppearance()
    public var standardWindowButton: ((WindowButton) -> NSButton?)?
    public var tabbingMode: TabbingMode = .automatic
    public var tabbingIdentifier: String = ""
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

    public override init() {
        super.init()
        contentView?.quillSetWindowRecursively(self)
    }

    public init(contentRect: NSRect, styleMask: StyleMask, backing: BackingStoreType, defer: Bool) {
        super.init()
        self.frame = contentRect
        self.styleMask = styleMask
        contentView?.quillSetWindowRecursively(self)
    }

    public func makeKeyAndOrderFront(_ sender: Any?) { isVisible = true; isKeyWindow = true }
    public func makeKey() { isKeyWindow = true }
    public func makeMain() { isMainWindow = true }
    public func orderFront(_ sender: Any?) { isVisible = true }
    public func orderOut(_ sender: Any?) { isVisible = false }
    public func close() { isVisible = false }
    public func performClose(_ sender: Any?) { close() }
    public func miniaturize(_ sender: Any?) { isMiniaturized = true }
    public func deminiaturize(_ sender: Any?) { isMiniaturized = false }
    public func zoom(_ sender: Any?) { isZoomed.toggle() }
    public func toggleFullScreen(_ sender: Any?) {}
    public func setFrame(_ rect: NSRect, display: Bool) { self.frame = rect }
    public func setFrame(_ rect: NSRect, display: Bool, animate: Bool) { self.frame = rect }
    public func setFrameOrigin(_ p: NSPoint) { self.frame.origin = p }
    public func setFrameTopLeftPoint(_ p: NSPoint) { self.frame.origin = p }
    public func center() {}
    public func setContentSize(_ s: NSSize) { contentView?.frame.size = s }
    public func setIsVisible(_ v: Bool) { isVisible = v }
    public func setIsMiniaturized(_ v: Bool) { isMiniaturized = v }
    public func setIsZoomed(_ v: Bool) { isZoomed = v }
    public func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if firstResponder === responder { return true }
        if let responder, !responder.acceptsFirstResponder { return false }
        if let current = firstResponder, !current.resignFirstResponder() { return false }
        if let responder, !responder.becomeFirstResponder() { return false }
        firstResponder = responder
        return true
    }
    public func performMiniaturize(_ sender: Any?) {}
    public func performZoom(_ sender: Any?) {}
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

// MARK: - NSApplication

// Drop `@MainActor` from the Linux NSApplication stub. Real
// AppKit's NSApplication has main-actor isolation, but our
// Linux stub is just compile-time scaffolding — generated
// Enchanted source reads `NSApp.currentEvent` from nonisolated
// SwiftUI closures, which the unannotated class allows without
// the `nonisolated(unsafe)` patchwork that broke the init().
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
    public var activationPolicy: ActivationPolicy = .regular
    public var dockTile: NSDockTile = NSDockTile()
    public var presentationOptions: PresentationOptions = []
    public var currentEvent: NSEvent?

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

    public func setActivationPolicy(_ p: ActivationPolicy) -> Bool { activationPolicy = p; return true }
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
            responder.keyDown(with: event)
        case .keyUp:
            responder.keyUp(with: event)
        case .flagsChanged:
            responder.flagsChanged(with: event)
        case .scrollWheel:
            responder.scrollWheel(with: event)
        case .mouseEntered, .mouseExited, .appKitDefined, .systemDefined,
             .applicationDefined, .periodic, .cursorUpdate:
            break
        }
    }
}

// Top-level globals. NSApplication itself is no longer
// `@MainActor` (see comment above) so the accessor doesn't
// need any isolation override.
public var NSApp: NSApplication { NSApplication.shared }

open class NSDockTile: NSObject, @unchecked Sendable {
    public var badgeLabel: String?
    public var contentView: NSView?
    public var showsApplicationBadge: Bool = false
    public func display() {}
}

@MainActor public protocol NSApplicationDelegate: AnyObject {
    func applicationDidFinishLaunching(_ notification: Notification)
    func applicationWillTerminate(_ notification: Notification)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    func application(_ application: NSApplication, open urls: [URL])
    func application(_ application: NSApplication, openFile filename: String) -> Bool
}

public extension NSApplicationDelegate {
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
    public enum EventType: UInt, Sendable {
        case leftMouseDown = 1, leftMouseUp = 2, rightMouseDown = 3, rightMouseUp = 4
        case mouseMoved = 5, leftMouseDragged = 6, rightMouseDragged = 7
        case mouseEntered = 8, mouseExited = 9
        case keyDown = 10, keyUp = 11, flagsChanged = 12
        case appKitDefined = 13, systemDefined = 14, applicationDefined = 15, periodic = 16
        case cursorUpdate = 17, scrollWheel = 22
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
    public struct PasteboardType: RawRepresentable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let string = PasteboardType(rawValue: "public.utf8-plain-text")
        public static let URL = PasteboardType(rawValue: "public.url")
        public static let fileURL = PasteboardType(rawValue: "public.file-url")
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

    @discardableResult
    public func open(_ url: URL) -> Bool {
        _xdgOpen(url.absoluteString)
    }

    public func open(_ url: URL, configuration: OpenConfiguration, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        let ok = _xdgOpen(url.absoluteString)
        completionHandler?(ok ? nil : nil, ok ? nil : NSError(domain: "QuillNSWorkspace", code: 1))
    }

    public func openApplication(at url: URL, configuration: OpenConfiguration, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        let ok = _xdgOpen(url.path)
        completionHandler?(ok ? nil : nil, ok ? nil : NSError(domain: "QuillNSWorkspace", code: 1))
    }

    @discardableResult
    public func selectFile(_ path: String?, inFileViewerRootedAtPath: String) -> Bool {
        guard let p = path else { return _xdgOpen(inFileViewerRootedAtPath) }
        let dir = (p as NSString).deletingLastPathComponent
        return _xdgOpen(dir.isEmpty ? inFileViewerRootedAtPath : dir)
    }

    public func activateFileViewerSelecting(_ urls: [URL]) {
        // On Apple this opens Finder with each URL highlighted. On
        // Linux we just open the containing directory of the first url.
        guard let first = urls.first else { return }
        let parent = first.deletingLastPathComponent().path
        _ = _xdgOpen(parent)
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
        guard let cmd = _xdgMimeQueryDefault(toOpen) else { return nil }
        return URL(fileURLWithPath: "/usr/share/applications/\(cmd)")
    }
    public func urlForApplication(withBundleIdentifier id: String) -> URL? {
        // Not really applicable on Linux. Best-effort return.
        URL(fileURLWithPath: "/usr/share/applications/\(id).desktop")
    }

    public class OpenConfiguration: NSObject, @unchecked Sendable {
        public override init() {}
        public var arguments: [String] = []
        public var environment: [String: String] = [:]
        public var activates: Bool = true
    }
}

private extension NSWorkspace {
    func _placeholderIcon() -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32))
    }

    @discardableResult
    func _xdgOpen(_ target: String) -> Bool {
        guard _hasCommand("xdg-open") else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["xdg-open", target]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            // Don't waitUntilExit() — xdg-open forks the real handler
            // and may stay attached. Detach instead.
            return true
        } catch { return false }
    }
    func _xdgMimeQueryDefault(_ url: URL) -> String? {
        if url.isFileURL {
            return _runForOutput(["xdg-mime", "query", "default", _xdgMimeForFile(url.path) ?? ""])
        }
        if let scheme = url.scheme {
            return _runForOutput(["xdg-mime", "query", "default", "x-scheme-handler/\(scheme)"])
        }
        return nil
    }
    func _xdgMimeForFile(_ path: String) -> String? {
        _runForOutput(["xdg-mime", "query", "filetype", path])
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
// keys that upstream code reads (`.font`, `.foregroundColor`, etc.).

public extension NSAttributedString.Key {
    static let font = NSAttributedString.Key(rawValue: "NSFont")
    static let foregroundColor = NSAttributedString.Key(rawValue: "NSColor")
    static let backgroundColor = NSAttributedString.Key(rawValue: "NSBackgroundColor")
    static let paragraphStyle = NSAttributedString.Key(rawValue: "NSParagraphStyle")
    static let underlineStyle = NSAttributedString.Key(rawValue: "NSUnderline")
    static let underlineColor = NSAttributedString.Key(rawValue: "NSUnderlineColor")
    static let strikethroughStyle = NSAttributedString.Key(rawValue: "NSStrikethrough")
    static let strikethroughColor = NSAttributedString.Key(rawValue: "NSStrikethroughColor")
    static let kern = NSAttributedString.Key(rawValue: "NSKern")
    static let link = NSAttributedString.Key(rawValue: "NSLink")
    static let attachment = NSAttributedString.Key(rawValue: "NSAttachment")
    static let baselineOffset = NSAttributedString.Key(rawValue: "NSBaselineOffset")
    static let writingDirection = NSAttributedString.Key(rawValue: "NSWritingDirection")
}

open class NSMutableParagraphStyle: NSObject, @unchecked Sendable {
    public override init() {}
    public var alignment: NSTextAlignment = .natural
    public var lineHeightMultiple: CGFloat = 0
    public var lineSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var firstLineHeadIndent: CGFloat = 0
    public var headIndent: CGFloat = 0
    public var tailIndent: CGFloat = 0
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public var minimumLineHeight: CGFloat = 0
    public var maximumLineHeight: CGFloat = 0
    public var baseWritingDirection: NSWritingDirection = .natural
    public var defaultTabInterval: CGFloat = 0
    public var tabStops: [Any] = []
}

public enum NSTextAlignment: Int, Sendable {
    case left, right, center, justified, natural
}

public enum NSLineBreakMode: Int, Sendable {
    case byWordWrapping, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle
}

public enum NSWritingDirection: Int, Sendable {
    case natural = -1, leftToRight = 0, rightToLeft = 1
}

// MARK: - NSMenu / NSMenuItem

open class NSMenu: NSObject {
    public var title: String = ""
    public var items: [NSMenuItem] = []
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

    public override init() { super.init() }
    public init(title: String) { super.init(); self.title = title }
    public func addItem(_ i: NSMenuItem) {
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
    public func removeItem(_ i: NSMenuItem) {
        items.removeAll { $0 === i }
        if i.menu === self { i.menu = nil }
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
    @MainActor
    public func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
        lastPopUpPositioningItem = item
        lastPopUpLocation = location
        lastPopUpView = view
        update()
        isTracking = true
        delegate?.menuWillOpen(self)
        return true
    }
    @MainActor
    public func cancelTracking() {
        guard isTracking else { return }
        isTracking = false
        delegate?.menuDidClose(self)
    }
    @MainActor
    public func update() {
        _ = delegate?.numberOfItems(in: self)
        delegate?.menuNeedsUpdate(self)
        for (index, item) in items.enumerated() {
            _ = delegate?.menu(self, update: item, at: index, shouldCancel: false)
            if autoenablesItems, let validator = item.target as? NSMenuItemValidation {
                item.isEnabled = validator.validateMenuItem(item)
            }
        }
    }
    public static var menuBarVisible: Bool = true
}

open class NSMenuItem: NSObject {
    public var title: String = ""
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

    public struct StateValue: RawRepresentable, Sendable {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let off = StateValue(rawValue: 0)
        public static let on = StateValue(rawValue: 1)
        public static let mixed = StateValue(rawValue: -1)
    }

    public init(title: String, action: Selector?, keyEquivalent: String) {
        super.init()
        self.title = title; self.action = action; self.keyEquivalent = keyEquivalent
    }
    public override init() { super.init() }
    public static var separator: NSMenuItem { NSMenuItem() }
    public static func separatorItem() -> NSMenuItem { NSMenuItem() }
}

@MainActor public protocol NSMenuDelegate: AnyObject {
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

@MainActor public protocol NSToolbarDelegate: AnyObject {
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

open class NSAlert: NSObject {
    public var messageText: String = ""
    public var informativeText: String = ""
    public var icon: NSImage?
    public var alertStyle: Style = .informational
    public var showsHelp: Bool = false
    public var helpAnchor: String?
    public weak var window: NSWindow?
    public var buttons: [NSButton] = []
    public var accessoryView: NSView?
    public var showsSuppressionButton: Bool = false
    public var suppressionButton: NSButton?
    private var _buttonTitles: [String] = []

    public enum Style: UInt, Sendable { case warning, informational, critical }

    public override init() { super.init() }
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
    public func runModal() -> NSApplication.ModalResponse { .OK }
    public func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {}
}

open class NSOpenPanel: NSSavePanel {
    public var canChooseFiles: Bool = true
    public var canChooseDirectories: Bool = false
    public var allowsMultipleSelection: Bool = false
    public var resolvesAliases: Bool = true
    public var urls: [URL] = []
}

// MARK: - NSScrollView / NSScroller / NSTextField / NSTextView / NSImageView / NSButton / NSPopUpButton / NSSearchField / NSSplitView / NSSlider

open class NSScrollView: NSView {
    public var contentView: NSClipView = NSClipView() {
        didSet {
            quillInstallContentView(replacing: oldValue)
        }
    }
    public var documentView: NSView? {
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
    public var hasVerticalScroller: Bool = false
    public var hasHorizontalScroller: Bool = false
    public var verticalScroller: NSScroller?
    public var horizontalScroller: NSScroller?
    public var autohidesScrollers: Bool = true
    public var scrollerStyle: NSScroller.Style = .overlay
    public var borderType: BorderType = .noBorder
    public var hasMagnification: Bool = false
    public var allowsMagnification: Bool = false
    public var magnification: CGFloat = 1
    public var minMagnification: CGFloat = 0.25
    public var maxMagnification: CGFloat = 4.0
    public var contentInsets: NSEdgeInsets = (0, 0, 0, 0)
    public var automaticallyAdjustsContentInsets: Bool = true
    public override init() {
        super.init()
        quillInstallContentView()
    }
    public override init(frame: NSRect) {
        super.init(frame: frame)
        quillInstallContentView()
    }
    public func flashScrollers() {}
    public enum BorderType: UInt, Sendable { case noBorder, lineBorder, bezelBorder, grooveBorder }

    private func quillInstallContentView(replacing oldValue: NSClipView? = nil) {
        if let oldValue, oldValue !== contentView {
            oldValue.removeFromSuperview()
        }
        if contentView.superview !== self {
            addSubview(contentView)
        }
    }
}

open class NSClipView: NSView {
    public var documentView: NSView?
    public var documentRect: NSRect = .zero
    public var documentVisibleRect: NSRect = .zero
}

open class NSScroller: NSView {
    public enum Style: Int, Sendable { case legacy, overlay }
}

open class NSTextField: NSControl {
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

    public enum BezelStyle: UInt, Sendable { case squareBezel, roundedBezel }

    public convenience init(labelWithString string: String) {
        self.init()
        applyLabelDefaults(string: string, selectable: false, lineBreakMode: .byClipping)
    }

    public convenience init(wrappingLabelWithString string: String) {
        self.init()
        applyLabelDefaults(string: string, selectable: true, lineBreakMode: .byWordWrapping)
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

open class NSText: NSView {
    public var string: String = ""
}

open class NSTextView: NSText {
    public var textStorage: NSTextStorage? = NSTextStorage(string: "")
    public var layoutManager: NSLayoutManager? = NSLayoutManager()
    public var textContainer: NSTextContainer? = NSTextContainer()
    public var textContainerInset: NSSize = .zero
    public var allowsUndo: Bool = false
    public var isEditable: Bool = true
    public var isSelectable: Bool = true
    public var isRichText: Bool = false
    public var importsGraphics: Bool = false
    public var smartInsertDeleteEnabled: Bool = true
    public var isAutomaticQuoteSubstitutionEnabled: Bool = true
    public var isAutomaticDashSubstitutionEnabled: Bool = true
    public var isAutomaticTextReplacementEnabled: Bool = true
    public var isAutomaticSpellingCorrectionEnabled: Bool = true
    public var continuousSpellCheckingEnabled: Bool = true
    public var grammarCheckingEnabled: Bool = true
    public var usesRuler: Bool = false
    public var usesFontPanel: Bool = false
    public var usesFindBar: Bool = false
    public var usesFindPanel: Bool = false
    public var rulerVisible: Bool = false
    public var selectedRange: NSRange = NSRange(location: 0, length: 0)
    public var selectedRanges: [NSValue] = []
    public var insertionPointColor: NSColor?
    public var typingAttributes: [NSAttributedString.Key: Any] = [:]
    public var defaultParagraphStyle: NSMutableParagraphStyle?
    public var font: NSFont?
    public var textColor: NSColor?
    public var backgroundColor: NSColor?
    public var drawsBackground: Bool = true
    public weak var delegate: NSTextViewDelegate?
    public var attributedString: NSAttributedString { NSAttributedString(string: string) }
    public func setSelectedRange(_ r: NSRange) {
        selectedRange = clampedTextRange(r)
        selectedRanges = [NSValue(range: selectedRange)]
        delegate?.textViewDidChangeSelection(
            Notification(name: Notification.Name("NSTextViewDidChangeSelectionNotification"), object: self)
        )
    }
    public func scrollRangeToVisible(_ r: NSRange) {}
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

open class NSTextStorage: NSMutableAttributedString {
    public weak var delegate: AnyObject?
    public var layoutManagers: [NSLayoutManager] = []
    public func addLayoutManager(_ m: NSLayoutManager) { layoutManagers.append(m) }
    public func removeLayoutManager(_ m: NSLayoutManager) {}
}

open class NSLayoutManager: NSObject, @unchecked Sendable {
    public override init() {}
    public weak var textStorage: NSTextStorage?
    public var textContainers: [NSTextContainer] = []
    public func addTextContainer(_ c: NSTextContainer) { textContainers.append(c) }
}

open class NSTextContainer: NSObject, @unchecked Sendable {
    public override init() {}
    public init(size: NSSize) {}
    public var containerSize: NSSize = .zero
    public var widthTracksTextView: Bool = false
    public var heightTracksTextView: Bool = false
    public var lineFragmentPadding: CGFloat = 0
    public weak var layoutManager: NSLayoutManager?
}

public protocol NSTextViewDelegate: NSTextDelegate {
    func textViewDidChangeSelection(_ notification: Notification)
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool
}
public extension NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {}
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool { true }
}

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
    public enum ImageScaling: UInt, Sendable { case scaleProportionallyDown, scaleAxesIndependently, scaleNone, scaleProportionallyUpOrDown }
    public enum ImageAlignment: UInt, Sendable { case alignCenter, alignTop, alignTopLeft, alignTopRight, alignLeft, alignBottom, alignBottomLeft, alignBottomRight, alignRight }
}

open class NSControl: NSView {
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
    public var tag: Int = 0
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
    public func sendAction(_ a: Selector?, to receiver: Any?) -> Bool {
        guard isEnabled else { return false }
        guard (a ?? action) != nil else { return false }
        let resolvedTarget = (receiver as AnyObject?) ?? target
        guard resolvedTarget != nil else { return false }
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

    public override init() { super.init() }
    public init(title: String, target: Any?, action: Selector?) { super.init(); self.title = title; self.target = target as AnyObject?; self.action = action }
    public init(image: NSImage, target: Any?, action: Selector?) { super.init(); self.image = image; self.target = target as AnyObject?; self.action = action }
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
    public override init() { super.init() }
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
    public var edgeInsets: NSEdgeInsets = (0, 0, 0, 0)
    public var arrangedSubviews: [NSView] = []
    public func addArrangedSubview(_ v: NSView) { arrangedSubviews.append(v); addSubview(v) }
    public func insertArrangedSubview(_ v: NSView, at idx: Int) { arrangedSubviews.insert(v, at: idx); addSubview(v) }
    public func removeArrangedSubview(_ v: NSView) {
        arrangedSubviews.removeAll { $0 === v }
    }
    public override init() { super.init() }
}

extension NSLayoutConstraint {
    public enum Attribute: Int, Sendable {
        case left, right, top, bottom, leading, trailing
        case width, height, centerX, centerY, lastBaseline, firstBaseline
        case notAnAttribute
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
    public override init() { super.init() }
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
    public init(frame: NSRect, pullsDown: Bool) { super.init(); self.pullsDown = pullsDown }
    public override init() { super.init() }

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

open class NSPopUpButtonCell: NSObject {
    public var menu: NSMenu? = NSMenu()
    public var pullsDown: Bool = false
    public var arrowPosition: ArrowPosition = .arrowAtBottom
    public enum ArrowPosition: UInt, Sendable { case noArrow, arrowAtCenter, arrowAtBottom }
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

@MainActor open class NSTableView: NSControl {
    public static let selectionDidChangeNotification = Notification.Name("NSTableViewSelectionDidChangeNotification")

    public weak var delegate: NSTableViewDelegate?
    public weak var dataSource: NSTableViewDataSource?
    public var headerView: NSTableHeaderView? = NSTableHeaderView()
    public var tableColumns: [NSTableColumn] = []
    public var rowHeight: CGFloat = 17
    public var intercellSpacing: NSSize = NSSize(width: 3, height: 2)
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

    public func reloadData() {
        replaceLoadedRows(count: dataSource?.numberOfRows(in: self) ?? 0)
    }

    public func reloadData(forRowIndexes rowIndexes: IndexSet, columnIndexes: IndexSet) {
        for row in rowIndexes {
            if let rowView = cachedRowViews.removeValue(forKey: row) {
                delegate?.tableView(self, didRemove: rowView, forRow: row)
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
        delegate?.tableView(self, didAdd: rowView, forRow: row)
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
                delegate?.tableView(self, didRemove: rowView, forRow: row)
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
    public func registerForDraggedTypes(_ types: [NSPasteboard.PasteboardType]) {}
    public func enumerateAvailableRowViews(_ block: (NSTableRowView, Int) -> Void) {
        for row in cachedRowViews.keys.sorted() {
            if let rowView = cachedRowViews[row] {
                block(rowView, row)
            }
        }
    }

    public func row(for view: NSView) -> Int {
        if let row = cachedRowViews.first(where: { $0.value === view })?.key {
            return row
        }
        return cachedCellViews.first(where: { $0.value === view })?.key.row ?? -1
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
        if self is NSOutlineView,
           let outlineDelegate = delegate as? NSOutlineViewDelegate {
            outlineDelegate.outlineViewSelectionDidChange(notification)
        } else {
            delegate?.tableViewSelectionDidChange(notification)
        }
    }

    fileprivate func replaceLoadedRows(count: Int, selectedRowIndexes rowIndexes: IndexSet? = nil) {
        numberOfRows = max(0, count)
        cachedRowViews.removeAll()
        cachedCellViews.removeAll()
        setSelectedRowIndexes(clampedRowIndexes(rowIndexes ?? selectedRowIndexes), notify: false)
    }

    private func shouldSelectRow(_ row: Int) -> Bool {
        if let outlineView = self as? NSOutlineView,
           let item = outlineView.item(atRow: row),
           let outlineDelegate = delegate as? NSOutlineViewDelegate {
            return outlineDelegate.outlineView(outlineView, shouldSelectItem: item)
        }
        return delegate?.tableView(self, shouldSelectRow: row) ?? true
    }

    private func makeRowView(forRow row: Int) -> NSTableRowView? {
        if let outlineView = self as? NSOutlineView,
           let item = outlineView.item(atRow: row),
           let outlineDelegate = delegate as? NSOutlineViewDelegate {
            return outlineDelegate.outlineView(outlineView, rowViewForItem: item)
        }
        return delegate?.tableView(self, rowViewForRow: row)
    }

    private func makeCellView(forColumn column: Int, row: Int) -> NSView? {
        let tableColumn = tableColumns[column]
        if let outlineView = self as? NSOutlineView,
           let item = outlineView.item(atRow: row),
           let outlineDelegate = delegate as? NSOutlineViewDelegate {
            return outlineDelegate.outlineView(outlineView, viewFor: tableColumn, item: item)
        }
        return delegate?.tableView(self, viewFor: tableColumn, row: row)
    }

    private func heightOfRow(_ row: Int) -> CGFloat {
        if let outlineView = self as? NSOutlineView,
           let item = outlineView.item(atRow: row),
           let outlineDelegate = delegate as? NSOutlineViewDelegate {
            return outlineDelegate.outlineView(outlineView, heightOfRowByItem: item)
        }
        return delegate?.tableView(self, heightOfRow: row) ?? 0
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

open class NSTableHeaderView: NSView {}
open class NSTableRowView: NSView {
    public var isSelected: Bool = false
    public var isEmphasized: Bool = false
    public var isGroupRowStyle: Bool = false
}
open class NSTableCellView: NSView {
    public var textField: NSTextField?
    public var imageView: NSImageView?
    public var objectValue: Any?
    public var rowSizeStyle: NSTableView.RowSizeStyle = .default
    public var backgroundStyle: BackgroundStyle = .normal
    public enum BackgroundStyle: Int, Sendable { case normal, emphasized, raised, lowered }
}

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

@MainActor public protocol NSTableViewDelegate: AnyObject {
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

@MainActor public protocol NSTableViewDataSource: AnyObject {
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
        (delegate as? NSOutlineViewDelegate)?.outlineViewItemDidExpand(
            Notification(name: Notification.Name("NSOutlineViewItemDidExpandNotification"), object: self)
        )
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
        (delegate as? NSOutlineViewDelegate)?.outlineViewItemDidCollapse(
            Notification(name: Notification.Name("NSOutlineViewItemDidCollapseNotification"), object: self)
        )
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
        max(0, outlineDataSource?.outlineView(self, numberOfChildrenOfItem: item) ?? 0)
    }

    public func child(_ index: Int, ofItem item: Any?) -> Any? {
        guard index >= 0 && index < numberOfChildren(ofItem: item) else { return nil }
        return outlineDataSource?.outlineView(self, child: index, ofItem: item)
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
        return outlineDataSource?.outlineView(self, isItemExpandable: item) ?? false
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

@MainActor public protocol NSOutlineViewDelegate: NSTableViewDelegate {
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

@MainActor public protocol NSOutlineViewDataSource: NSTableViewDataSource {
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

open class NSDocument: NSObject {
    public var fileURL: URL?
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
    public enum ChangeType: UInt, Sendable { case changeDone, changeUndone, changeRedone, changeCleared, changeReadOtherContents, changeAutosaved, changeDiscardable }
}

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
}

// MARK: - NSHostingView / NSHostingController / NSViewRepresentable bridges

public class NSHostingView<Content>: NSView {
    public var rootView: Content
    public init(rootView: Content) { self.rootView = rootView; super.init() }
}

public class NSHostingController<Content>: NSViewController {
    public var rootView: Content
    public init(rootView: Content) { self.rootView = rootView; super.init() }
}

// SwiftUI bridging protocols (these get re-exported by the SwiftUI shim
// too — declared here so `import AppKit` alone is enough).
public protocol NSViewRepresentable: AnyObject {
    associatedtype NSViewType: NSView
    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSViewType
    func updateNSView(_ nsView: NSViewType, context: NSViewRepresentableContext<Self>)
}
public protocol NSViewControllerRepresentable: AnyObject {
    associatedtype NSViewControllerType: NSViewController
    func makeNSViewController(context: NSViewControllerRepresentableContext<Self>) -> NSViewControllerType
    func updateNSViewController(_ nsViewController: NSViewControllerType, context: NSViewControllerRepresentableContext<Self>)
}
public struct NSViewRepresentableContext<Coordinator> {
    public let coordinator: Coordinator? = nil
}
public struct NSViewControllerRepresentableContext<Coordinator> {
    public let coordinator: Coordinator? = nil
}

// MARK: - NSStatusBar / NSStatusItem (menu-bar widgets)

open class NSStatusBar: NSObject {
    public static let system = NSStatusBar()
    public func statusItem(withLength: CGFloat) -> NSStatusItem { NSStatusItem() }
    public func removeStatusItem(_ item: NSStatusItem) {}
    public static var variableLength: CGFloat { -1 }
    public static var squareLength: CGFloat { -2 }
    public var thickness: CGFloat = 22
}

open class NSStatusItem: NSObject {
    public var button: NSStatusBarButton? = NSStatusBarButton()
    public var menu: NSMenu?
    public var length: CGFloat = -1
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

public enum NSRectEdge: UInt, Sendable {
    case minX, minY, maxX, maxY
}

// MARK: - NSVisualEffectView / NSGlassEffectView

open class NSVisualEffectView: NSView {
    public var material: Material = .titlebar
    public var blendingMode: BlendingMode = .behindWindow
    public var state: State = .followsWindowActiveState
    public var isEmphasized: Bool = false
    public var maskImage: NSImage?
    public enum Material: Int, Sendable {
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

open class NSAnimationContext: NSObject {
    public static var current: NSAnimationContext = NSAnimationContext()
    public var duration: TimeInterval = 0.25
    public var timingFunction: Any?
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
    public init?(named: NSSharingService.Name) {}
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

open class NSSound: NSObject, @unchecked Sendable {
    public init?(named: String) {}
    public init?(contentsOf: URL, byReference: Bool) {}
    public init?(data: Data) {}
    public func play() -> Bool { false }
    public func stop() -> Bool { false }

    /// Phase B: emits the terminal bell character (BEL, \x07) to stderr.
    /// Most terminal emulators map this to either a flash or an audible
    /// tone depending on user preference, which is the closest Linux
    /// analogue to Apple's NSSound.beep() system alert.
    public static func beep() {
        FileHandle.standardError.write(Data([0x07]))
    }
}

public protocol NSDraggingInfo: AnyObject {
    var draggingPasteboard: NSPasteboard { get }
    var draggingLocation: NSPoint { get }
    var draggingSource: Any? { get }
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
    public init(stringLiteral value: String) { self.rawValue = value }
}

// MARK: - NSEnvironmentKey for SwiftUI windowing (the `\.window` key that
//          some views read; SwiftUI shim re-exports the protocol).

public struct NSWindowEnvironmentKey {
    public static let defaultValue: NSWindow? = nil
}

// MARK: - NSCell (legacy, but referenced)

open class NSCell: NSObject, @unchecked Sendable {
    public override init() {}
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
