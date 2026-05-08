import Foundation
import QuillUI
import QuillKit

public typealias NSImage = QuillUI.NSImage
public typealias NSSize = CGSize
public typealias NSPoint = CGPoint
public typealias NSRect = CGRect
public typealias NSCompositingOperation = QuillUI.QuillImageCompositingOperation

public final class NSBitmapImageRep: @unchecked Sendable {
    public enum FileType: Sendable {
        case jpeg
    }

    public struct PropertyKey: Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        public static let compressionFactor = PropertyKey("compressionFactor")
    }

    private var data: Data

    public init?(data: Data) {
        self.data = data
    }

    public func representation(using type: FileType, properties: [PropertyKey: Any]) -> Data? {
        data
    }
}

public final class NSPasteboard: @unchecked Sendable {
    public struct PasteboardType: Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
        }

        public static let string = PasteboardType("public.utf8-plain-text")
        public static let tiff = PasteboardType("public.tiff")
    }

    public static let general = NSPasteboard()
    public var pasteboardItems: [NSPasteboardItem]? = []
    private var strings: [PasteboardType: String] = [:]
    private var dataValues: [PasteboardType: Data] = [:]

    public init() {}

    public func declareTypes(_ newTypes: [PasteboardType], owner: Any?) {}
    public func clearContents() { strings.removeAll(); dataValues.removeAll(); pasteboardItems = []; QuillClipboard.shared.clear() }
    public func setString(_ string: String, forType type: PasteboardType) { strings[type] = string; QuillClipboard.shared.setString(string, forType: type.rawValue) }
    public func string(forType type: PasteboardType) -> String? { strings[type] ?? QuillClipboard.shared.string(forType: type.rawValue) }
    public func setData(_ data: Data, forType type: PasteboardType) { dataValues[type] = data; QuillClipboard.shared.setData(data, forType: type.rawValue) }
    public func data(forType type: PasteboardType) -> Data? { dataValues[type] ?? QuillClipboard.shared.data(forType: type.rawValue) }
}

public final class NSPasteboardItem: @unchecked Sendable {
    private var strings: [NSPasteboard.PasteboardType: String] = [:]
    private var dataValues: [NSPasteboard.PasteboardType: Data] = [:]

    public init() {}

    public func setString(_ string: String, forType type: NSPasteboard.PasteboardType) { strings[type] = string }
    public func string(forType type: NSPasteboard.PasteboardType) -> String? { strings[type] }
    public func setData(_ data: Data, forType type: NSPasteboard.PasteboardType) { dataValues[type] = data }
    public func data(forType type: NSPasteboard.PasteboardType) -> Data? { dataValues[type] }
}

public final class NSWorkspace: @unchecked Sendable {
    public static let shared = NSWorkspace()
    public init() {}

    @discardableResult
    public func open(_ url: URL) -> Bool {
        QuillWorkspace.open(url)
    }
}

public final class NSEvent: @unchecked Sendable {
    public struct ModifierFlags: OptionSet, Sendable {
        public var rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let command = ModifierFlags(rawValue: 1 << 0)
        public static let shift = ModifierFlags(rawValue: 1 << 1)
        public static let option = ModifierFlags(rawValue: 1 << 2)
        public static let control = ModifierFlags(rawValue: 1 << 3)
    }

    public var modifierFlags: ModifierFlags
    public var keyCode: UInt16

    public init(modifierFlags: ModifierFlags = [], keyCode: UInt16 = 0) {
        self.modifierFlags = modifierFlags
        self.keyCode = keyCode
    }
}

public final class NSApplication: @unchecked Sendable {
    public var currentEvent: NSEvent?
    public init() {}
}

public let NSApp = NSApplication()
