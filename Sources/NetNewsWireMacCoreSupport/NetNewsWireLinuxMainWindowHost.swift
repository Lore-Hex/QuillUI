import AppKit
import NetNewsWireContext

public struct NetNewsWireLinuxMainWindowSnapshot: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let toolbarIdentifier: String?
    public let splitViewItemCount: Int
    public let detailMinimumThickness: Double
    public let windowWidth: Double
    public let windowHeight: Double
    public let minimumWidth: Double
    public let minimumHeight: Double
    public let hasDetailWebView: Bool

    public init(
        title: String,
        subtitle: String,
        toolbarIdentifier: String?,
        splitViewItemCount: Int,
        detailMinimumThickness: Double,
        windowWidth: Double,
        windowHeight: Double,
        minimumWidth: Double,
        minimumHeight: Double,
        hasDetailWebView: Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self.toolbarIdentifier = toolbarIdentifier
        self.splitViewItemCount = splitViewItemCount
        self.detailMinimumThickness = detailMinimumThickness
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
        self.hasDetailWebView = hasDetailWebView
    }
}

@MainActor
public final class NetNewsWireLinuxMainWindowHost {
    public let window: NSWindow

    let splitViewController: NSSplitViewController
    let sidebarController: SidebarViewController
    let timelineController: TimelineContainerViewController
    let detailController: DetailViewController
    let detailContainer: DetailContainerView
    let mainWindowController: MainWindowController

    public init(unreadCount: Int = 7) {
        NetNewsWireContext.appDelegate = NetNewsWireContext.AppDelegate()
        NetNewsWireContext.appDelegate.unreadCount = unreadCount

        let sidebarController = Self.makeSidebarController()
        let timelineController = Self.makeTimelineController()
        let detail = Self.makeDetailController()
        let splitViewController = Self.makeSplitViewController(
            sidebarController: sidebarController,
            timelineController: timelineController,
            detailController: detail.controller
        )

        let rootController = NSViewController()
        rootController.view = splitViewController.view
        rootController.addChild(splitViewController)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = rootController

        let mainWindowController = MainWindowController(window: window)
        mainWindowController.contentViewController = rootController
        mainWindowController.articleThemePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        mainWindowController.windowDidLoad()
        mainWindowController.coalescedUpdateWindowTitle()

        self.window = window
        self.splitViewController = splitViewController
        self.sidebarController = sidebarController
        self.timelineController = timelineController
        self.detailController = detail.controller
        self.detailContainer = detail.container
        self.mainWindowController = mainWindowController
    }

    public var snapshot: NetNewsWireLinuxMainWindowSnapshot {
        let detailSplitViewItem = splitViewController.splitViewItems.indices.contains(2)
            ? splitViewController.splitViewItems[2]
            : nil

        return NetNewsWireLinuxMainWindowSnapshot(
            title: window.title,
            subtitle: window.subtitle,
            toolbarIdentifier: window.toolbar?.identifier,
            splitViewItemCount: splitViewController.splitViewItems.count,
            detailMinimumThickness: Double(detailSplitViewItem?.minimumThickness ?? 0),
            windowWidth: Double(window.frame.size.width),
            windowHeight: Double(window.frame.size.height),
            minimumWidth: Double(window.minSize.width),
            minimumHeight: Double(window.minSize.height),
            hasDetailWebView: detailContainer.contentView is DetailWebView
        )
    }

    public func refreshUnreadCount(_ unreadCount: Int) {
        NetNewsWireContext.appDelegate.unreadCount = unreadCount
        mainWindowController.coalescedUpdateWindowTitle()
    }

    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private static func makeSidebarController() -> SidebarViewController {
        let controller = SidebarViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        controller.outlineView = SidebarOutlineView(frame: controller.view.bounds)
        controller.outlineView.tableColumns = [
            NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "sidebar"))
        ]
        controller.view.addSubview(controller.outlineView)
        controller.viewDidLoad()
        return controller
    }

    private static func makeTimelineController() -> TimelineContainerViewController {
        let controller = TimelineContainerViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 600))
        controller.viewOptionsPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
        controller.newestToOldestMenuItem = NSMenuItem(title: "Newest to Oldest", action: nil, keyEquivalent: "")
        controller.oldestToNewestMenuItem = NSMenuItem(title: "Oldest to Newest", action: nil, keyEquivalent: "")
        controller.groupByFeedMenuItem = NSMenuItem(title: "Group by Feed", action: nil, keyEquivalent: "")
        controller.readFilteredButton = NSButton()
        controller.containerView = TimelineContainerView(frame: controller.view.bounds)
        controller.view.addSubview(controller.containerView)
        controller.regularTimelineViewController.tableView = TimelineTableView(frame: controller.containerView.bounds)
        controller.regularTimelineViewController.tableView.tableColumns = [
            NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "timeline"))
        ]
        controller.viewDidLoad()
        return controller
    }

    private static func makeDetailController() -> (controller: DetailViewController, container: DetailContainerView) {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 600))
        let statusBar = DetailStatusBarView(frame: NSRect(x: 0, y: 578, width: 520, height: 22))
        statusBar.urlLabel = NSTextField(labelWithString: "")

        let container = DetailContainerView(frame: rootView.bounds)
        container.detailStatusBarView = statusBar
        rootView.addSubview(container)
        rootView.addSubview(statusBar)

        let controller = DetailViewController()
        controller.view = rootView
        controller.containerView = container
        controller.statusBarView = statusBar
        controller.viewDidLoad()

        return (controller, container)
    }

    private static func makeSplitViewController(
        sidebarController: SidebarViewController,
        timelineController: TimelineContainerViewController,
        detailController: DetailViewController
    ) -> NSSplitViewController {
        let splitViewController = NSSplitViewController()
        splitViewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 600))
        splitViewController.addSplitViewItem(.sidebar(with: sidebarController))
        splitViewController.addSplitViewItem(.contentListWithViewController(timelineController))
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: detailController))
        return splitViewController
    }
}
