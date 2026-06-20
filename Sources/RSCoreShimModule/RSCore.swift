import AppKit

@_exported import UIKit
@_exported import QuillRSCoreShim

public typealias RSImage = UIImage
public typealias RSScreen = UIScreen

@MainActor public final class RSAppMovementMonitor: NSObject {
    public var appMovementHandler: ((RSAppMovementMonitor) -> Bool)?

    public override init() {
        super.init()
    }

    public func quillSimulateMovement() -> Bool {
        appMovementHandler?(self) ?? false
    }
}

public final class MemoryPressureMonitor: @unchecked Sendable {
    public static let shared = MemoryPressureMonitor()

    private init() {}

    @MainActor public func start() {}
}

@MainActor public protocol SendToCommand {
    var title: String { get }
    var image: RSImage? { get }

    func canSendObject(_ object: Any?, selectedText: String?) -> Bool
    func sendObject(_ object: Any?, selectedText: String?)
}

public final class UserApp {
    public let bundleID: String
    public var icon: NSImage?
    public var existsOnDisk = false
    public var path: String?
    public var runningApplication: NSRunningApplication?

    public var isRunning: Bool {
        updateStatus()
        return runningApplication != nil
    }

    public init(bundleID: String) {
        self.bundleID = bundleID
        updateStatus()
    }

    public func updateStatus() {
        if runningApplication == nil {
            runningApplication = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }

        if let runningApplication {
            existsOnDisk = true
            path = runningApplication.bundleURL?.path
            icon = runningApplication.icon
            return
        }

        path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        existsOnDisk = path != nil
        icon = path.map { NSWorkspace.shared.icon(forFile: $0) }
    }

    public func launchIfNeeded() async -> Bool {
        updateStatus()
        if runningApplication != nil {
            return true
        }
        guard existsOnDisk, let path else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = true
        do {
            runningApplication = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: configuration
            )
            return true
        } catch {
            return false
        }
    }

    public func bringToFront() -> Bool {
        updateStatus()
        return runningApplication?.activate() ?? false
    }

    public func targetDescriptor() -> NSAppleEventDescriptor? {
        updateStatus()
        guard runningApplication != nil else {
            return nil
        }
        return NSAppleEventDescriptor()
    }
}

@MainActor public struct SendToBlogEditorApp {
    private let targetDescriptor: NSAppleEventDescriptor

    public init(
        targetDescriptor: NSAppleEventDescriptor,
        title: String?,
        body: String?,
        summary: String?,
        link: String?,
        permalink: String?,
        subject: String?,
        creator: String?,
        commentsURL: String?,
        guid: String?,
        sourceName: String?,
        sourceHomeURL: String?,
        sourceFeedURL: String?
    ) {
        self.targetDescriptor = targetDescriptor
        _ = title
        _ = body
        _ = summary
        _ = link
        _ = permalink
        _ = subject
        _ = creator
        _ = commentsURL
        _ = guid
        _ = sourceName
        _ = sourceHomeURL
        _ = sourceFeedURL
    }

    public func send() {
        _ = targetDescriptor
    }
}

nonisolated public extension Dictionary where Key == String, Value == String {
    var urlQueryString: String? {
        var components = URLComponents()
        components.queryItems = map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let query = components.percentEncodedQuery, !query.isEmpty else {
            return nil
        }
        return query
    }
}

public extension RSImage {
    convenience init?(systemSymbolName symbolName: String, accessibilityDescription: String?) {
        _ = accessibilityDescription
        self.init(systemName: symbolName)
    }

    func tinted(color: UIColor) -> RSImage? {
        withTintColor(color)
    }

    func withTintColor(_ color: UIColor, renderingMode: UIImage.RenderingMode) -> RSImage {
        _ = renderingMode
        return withTintColor(color)
    }
}

public extension UIColor {
    static var systemPurple: UIColor { UIColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1) }
    static var systemTeal: UIColor { UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1) }
    static var systemBrown: UIColor { UIColor(red: 0.64, green: 0.52, blue: 0.37, alpha: 1) }
    static var systemIndigo: UIColor { UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1) }
}

@MainActor public protocol PasteboardWriterOwner {
    var pasteboardWriter: NSPasteboardWriting { get }
}

public extension NSPasteboard {
    @MainActor func copyObjects(_ objects: [Any]) {
        guard let writers = writersFor(objects) else {
            return
        }

        clearContents()
        _ = writeObjects(writers)
    }

    func canCopyAtLeastOneObject(_ objects: [Any]) -> Bool {
        objects.contains { $0 is PasteboardWriterOwner }
    }

    static func urlString(from pasteboard: NSPasteboard) -> String? {
        pasteboard.quillURLString
    }
}

private extension NSPasteboard {
    var quillURLString: String? {
        guard let type = availableType(from: [.string]),
              let string = self.string(forType: type),
              !string.isEmpty
        else {
            return nil
        }
        return quillMayBeURL(string) ? string : nil
    }

    @MainActor func writersFor(_ objects: [Any]) -> [NSPasteboardWriting]? {
        let writers = objects.compactMap { ($0 as? PasteboardWriterOwner)?.pasteboardWriter }
        return writers.isEmpty ? nil : writers
    }

    func quillMayBeURL(_ string: String) -> Bool {
        guard !string.contains(where: \.isWhitespace) else {
            return false
        }
        if let url = URL(string: string), url.scheme != nil {
            return true
        }
        return string.contains(".")
    }
}

/// Takes a string, not a URL, but writes it as a URL when possible and as text.
public final class URLPasteboardWriter: NSObject, NSPasteboardWriting {
    public let urlString: String

    public init(urlString: String) {
        self.urlString = urlString
    }

    public static func write(urlString: String, to pasteboard: NSPasteboard) {
        write(urlStrings: [urlString], to: pasteboard)
    }

    public static func write(urlStrings: [String], to pasteboard: NSPasteboard) {
        guard !urlStrings.isEmpty else {
            return
        }

        pasteboard.clearContents()
        let items = urlStrings.map { urlString -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(urlString, forType: .string)
            if URL(string: urlString) != nil {
                item.setString(urlString, forType: .URL)
            }
            return item
        }
        _ = pasteboard.writeObjects(items)
    }

    public func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        if URL(string: urlString) != nil {
            return [.URL, .string]
        }
        return [.string]
    }

    public func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard type == .string || type == .URL else {
            return nil
        }
        return urlString
    }
}

public extension NSView {
    func asImage() -> NSImage {
        let size = bounds.size == .zero ? frame.size : bounds.size
        let image = NSImage(size: size == .zero ? NSSize(width: 1, height: 1) : size)
        image.data = Data([
            137, 80, 78, 71, 13, 10, 26, 10,
            0, 0, 0, 13, 73, 72, 68, 82,
            0, 0, 0, 1, 0, 0, 0, 1,
            8, 6, 0, 0, 0, 31, 21, 196,
            137, 0, 0, 0, 13, 73, 68, 65,
            84, 120, 156, 99, 248, 15, 4, 0,
            9, 251, 3, 253, 167, 58, 202, 239,
            0, 0, 0, 0, 73, 69, 78, 68,
            174, 66, 96, 130,
        ])
        return image
    }
}
