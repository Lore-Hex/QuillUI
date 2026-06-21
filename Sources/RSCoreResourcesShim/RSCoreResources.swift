#if os(Linux)
import AppKit
import WebKit

public final class WebViewWindowController: NSWindowController {
    private let displayTitle: String
    public private(set) var displayedPath: String?

    public convenience init(title: String) {
        self.init(window: NSWindow())
        window?.title = title
    }

    override public init(window: NSWindow?) {
        self.displayTitle = window?.title ?? ""
        super.init(window: window)
    }

    override public func windowDidLoad() {
        super.windowDidLoad()
        if !displayTitle.isEmpty {
            window?.title = displayTitle
        }
    }

    public func displayContents(of path: String) {
        displayedPath = path
    }
}

@MainActor public final class IndeterminateProgressController {
    public private(set) static var isRunning = false
    public private(set) static var message: String?

    public static func beginProgressWithMessage(_ message: String) {
        isRunning = true
        self.message = message
    }

    public static func endProgress() {
        isRunning = false
        message = nil
        NSApplication.shared.stopModal()
    }
}
#endif
