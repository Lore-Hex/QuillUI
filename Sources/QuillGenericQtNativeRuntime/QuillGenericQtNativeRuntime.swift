#if os(Linux)
import CQuillQt6WidgetsShim
import Foundation
import Glibc

public struct QuillGenericQtAppSnapshot: Codable, Sendable {
    public var windowTitle: String
    public var minimumWidth: Int
    public var minimumHeight: Int
    public var defaultWidth: Int
    public var defaultHeight: Int
    public var sidebarWidth: Int
    public var detailWidth: Int
    public var sidebarTitle: String
    public var sidebarSubtitle: String
    public var primaryActionTitle: String
    public var secondaryActionTitle: String
    public var listTitle: String
    public var status: String
    public var selectedIndex: Int
    public var detailTitle: String
    public var detailSubtitle: String
    public var messagesTitle: String
    public var items: [Item]
    public var sections: [Section]
    public var messages: [Message]

    public struct Item: Codable, Sendable {
        public var title: String
        public var subtitle: String
        public var badge: String
        public var height: Int
        public var detailTitle: String?
        public var detailSubtitle: String?
        public var sections: [Section]?
        public var messages: [Message]?

        public init(
            title: String,
            subtitle: String,
            badge: String = "",
            height: Int = 76,
            detailTitle: String? = nil,
            detailSubtitle: String? = nil,
            sections: [Section]? = nil,
            messages: [Message]? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.badge = badge
            self.height = height
            self.detailTitle = detailTitle
            self.detailSubtitle = detailSubtitle
            self.sections = sections
            self.messages = messages
        }
    }

    public struct Section: Codable, Sendable {
        public var title: String
        public var body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    public struct Message: Codable, Sendable {
        public var sender: String
        public var body: String

        public init(sender: String, body: String) {
            self.sender = sender
            self.body = body
        }
    }

    public init(
        windowTitle: String,
        minimumWidth: Int = 900,
        minimumHeight: Int = 620,
        defaultWidth: Int = 1040,
        defaultHeight: Int = 700,
        sidebarWidth: Int = 320,
        detailWidth: Int = 720,
        sidebarTitle: String,
        sidebarSubtitle: String,
        primaryActionTitle: String = "New",
        secondaryActionTitle: String = "Refresh",
        listTitle: String,
        status: String,
        selectedIndex: Int = 0,
        detailTitle: String,
        detailSubtitle: String,
        messagesTitle: String = "Activity",
        items: [Item],
        sections: [Section],
        messages: [Message] = []
    ) {
        self.windowTitle = windowTitle
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
        self.defaultWidth = defaultWidth
        self.defaultHeight = defaultHeight
        self.sidebarWidth = sidebarWidth
        self.detailWidth = detailWidth
        self.sidebarTitle = sidebarTitle
        self.sidebarSubtitle = sidebarSubtitle
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.listTitle = listTitle
        self.status = status
        self.selectedIndex = selectedIndex
        self.detailTitle = detailTitle
        self.detailSubtitle = detailSubtitle
        self.messagesTitle = messagesTitle
        self.items = items
        self.sections = sections
        self.messages = messages
    }
}

public enum QuillGenericQtAppCatalog {
    public static let enchantedUpstreamSlice = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Enchanted Slice",
        defaultWidth: 1120,
        defaultHeight: 720,
        sidebarTitle: "Enchanted",
        sidebarSubtitle: "Upstream-shaped Qt slice",
        primaryActionTitle: "New chat",
        secondaryActionTitle: "Models",
        listTitle: "Conversations",
        status: "Qt host uses the explicit Qt build graph",
        detailTitle: "Conversation preview",
        detailSubtitle: "A compact native Qt rendering of the upstream chat slice while the full SwiftUI tree remains on the GTK path.",
        items: [
            .init(
                title: "Auto-config test",
                subtitle: "Reply with one short phrase",
                badge: "ollama",
                detailSubtitle: "Local model setup conversation with endpoint status visible.",
                sections: [
                    .init(title: "Endpoint", body: "The selected chat keeps the Ollama endpoint and model controls in the visible shell."),
                    .init(title: "Prompt", body: "A short assistant response gives the Qt smoke a deterministic transcript landmark.")
                ],
                messages: [
                    .init(sender: "user", body: "Reply with one short phrase."),
                    .init(sender: "assistant", body: "Native Qt path is active.")
                ]
            ),
            .init(
                title: "Wedding plus-one",
                subtitle: "Draft a friendly message",
                badge: "draft",
                detailSubtitle: "Draft-writing fixture for a selected conversation.",
                sections: [
                    .init(title: "Conversation", body: "Draft state, title, and preview text stay separate from the shared chat shell."),
                    .init(title: "Composer", body: "The detail pane keeps attachment and composer controls aligned with the GTK slice.")
                ],
                messages: [
                    .init(sender: "user", body: "Draft a friendly plus-one message."),
                    .init(sender: "assistant", body: "Happy to join you at the wedding. Thanks for including me.")
                ]
            ),
            .init(
                title: "Language phrases",
                subtitle: "Practice short translations",
                detailSubtitle: "Language practice fixture with the lower row selected.",
                sections: [
                    .init(title: "Session", body: "The selected practice thread updates the title, cards, and transcript together."),
                    .init(title: "Parity", body: "This lower-row fixture prevents the Qt selection smoke from passing on header-only updates.")
                ],
                messages: [
                    .init(sender: "user", body: "Practice three short translations."),
                    .init(sender: "assistant", body: "Bonjour, gracias, and guten Abend.")
                ]
            )
        ],
        sections: [
            .init(title: "Endpoint and model controls", body: "The Qt target preserves the chat shell shape with model status, conversation selection, and prompt context."),
            .init(title: "Shared source boundary", body: "App-specific SwiftUI code stays out of the Qt graph; only a small snapshot crosses into the native host.")
        ],
        messages: [
            .init(sender: "assistant", body: "QuillUI is rendering this upstream-shaped app through the native Qt backend.")
        ]
    )

    public static let iceCubes = QuillGenericQtAppSnapshot(
        windowTitle: "Quill IceCubes",
        sidebarTitle: "IceCubes",
        sidebarSubtitle: "Mastodon timeline",
        primaryActionTitle: "Post",
        secondaryActionTitle: "Boosts",
        listTitle: "Timeline",
        status: "Public timeline fixture loaded",
        detailTitle: "Timeline item",
        detailSubtitle: "Fixture-backed Mastodon shell compiled through Qt without SwiftOpenUI.",
        items: [
            .init(
                title: "QuillUI",
                subtitle: "Backend parity update",
                badge: "2m",
                detailSubtitle: "Backend parity notes from the QuillUI account.",
                sections: [
                    .init(title: "Post", body: "The Qt list now drives the same detail surface for every generic app target."),
                    .init(title: "Actions", body: "Reply, boost, favorite, and share affordances stay in the same hierarchy as the GTK shell.")
                ]
            ),
            .init(
                title: "Swift on Linux",
                subtitle: "GTK and Qt builds stay explicit",
                badge: "8m",
                detailSubtitle: "Toolchain update focused on Linux app packaging.",
                sections: [
                    .init(title: "Thread", body: "The canonical product name selects exactly one backend graph through QUILLUI_LINUX_BACKEND."),
                    .init(title: "Build note", body: "SwiftPM stays deterministic because Qt-only targets do not pull in the GTK graph.")
                ]
            ),
            .init(
                title: "Mastodon",
                subtitle: "Timeline cards, replies, and boosts",
                badge: "14m",
                detailSubtitle: "Timeline interaction fixture with the lower row selected.",
                sections: [
                    .init(title: "Conversation", body: "Replies and boost counts remain visible when the selected row changes."),
                    .init(title: "Fixture", body: "This row gives the Qt screenshot smoke a stable selected-detail target.")
                ]
            )
        ],
        sections: [
            .init(title: "Timeline density", body: "Rows keep avatars, timestamps, and action affordances in the same information hierarchy as the GTK shell."),
            .init(title: "Performance path", body: "The Qt app starts from a small Codable snapshot so backend startup remains cheap and deterministic.")
        ]
    )

    public static let netNewsWire = QuillGenericQtAppSnapshot(
        windowTitle: "Quill NetNewsWire",
        sidebarTitle: "NetNewsWire",
        sidebarSubtitle: "RSS reader",
        primaryActionTitle: "Add feed",
        secondaryActionTitle: "Refresh",
        listTitle: "Feeds",
        status: "3 unread articles",
        selectedIndex: 1,
        detailTitle: "Article reader",
        detailSubtitle: "Self-contained RSS fixtures rendered by the native Qt backend.",
        items: [
            .init(
                title: "Swift.org",
                subtitle: "Language and toolchain updates",
                badge: "1",
                detailSubtitle: "Unread language and toolchain article selected.",
                sections: [
                    .init(title: "Article", body: "Swift.org fixture content keeps source, title, and unread count visible in the Qt reader."),
                    .init(title: "Reader chrome", body: "The article body reuses the same detail-card renderer as the other generic apps.")
                ]
            ),
            .init(
                title: "Point-Free",
                subtitle: "Composable app architecture notes",
                badge: "2",
                detailSubtitle: "Composable architecture feed selected by default.",
                sections: [
                    .init(title: "Article", body: "The selected feed row exposes a stable headline, excerpt, and unread badge."),
                    .init(title: "Navigation", body: "Feed selection changes the detail cards without rebuilding the Qt window.")
                ]
            ),
            .init(
                title: "QuillUI",
                subtitle: "Linux compatibility reports",
                detailSubtitle: "Linux compatibility report fixture with the lower row selected.",
                sections: [
                    .init(title: "Article", body: "The report summarizes backend parity work across GTK and Qt canonical products."),
                    .init(title: "Smoke target", body: "The lower feed row gives the list-selection check a row-specific reader surface.")
                ]
            )
        ],
        sections: [
            .init(title: "Reader layout", body: "The Qt target mirrors the three-pane reader rhythm with feed selection, unread counts, and article detail."),
            .init(title: "Parser boundary", body: "RSS parsing remains in shared Swift core; Qt consumes a presentation snapshot.")
        ]
    )

    public static let codeEdit = QuillGenericQtAppSnapshot(
        windowTitle: "Quill CodeEdit",
        minimumWidth: 980,
        defaultWidth: 1180,
        defaultHeight: 740,
        sidebarTitle: "CodeEdit",
        sidebarSubtitle: "Workspace shell",
        primaryActionTitle: "Open",
        secondaryActionTitle: "Search",
        listTitle: "Files",
        status: "Fixture workspace loaded",
        detailTitle: "Editor preview",
        detailSubtitle: "Qt native workbench for file tree, tabs, diagnostics, and editor chrome.",
        items: [
            .init(
                title: "Package.swift",
                subtitle: "SwiftPM manifest",
                badge: "M",
                detailSubtitle: "Manifest fixture showing selected backend dependencies.",
                sections: [
                    .init(title: "Editor", body: "The manifest row highlights product routing, target dependencies, and backend selection."),
                    .init(title: "Diagnostics", body: "The modified badge remains visible without requiring the full CodeEdit plugin graph.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "Package graph selects exactly one Linux backend.")
                ]
            ),
            .init(
                title: "QuillUI.swift",
                subtitle: "Backend facade",
                detailSubtitle: "Facade source fixture for the shared app entry point.",
                sections: [
                    .init(title: "Editor", body: "The facade row keeps the app entry point and scene metadata in the detail pane."),
                    .init(title: "Navigation", body: "Changing file rows updates the same Qt workbench surface.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "No stale detail content after file selection.")
                ]
            ),
            .init(
                title: "BackendRegistry.swift",
                subtitle: "Linux runtime selection",
                detailSubtitle: "Backend registry fixture with the lower file row selected.",
                sections: [
                    .init(title: "Editor", body: "The selected registry row describes GTK and Qt runtime identifiers in one place."),
                    .init(title: "Parity", body: "This row makes the Qt screenshot assert detail-body updates, not just sidebar selection.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "Runtime registry matches the explicit backend matrix.")
                ]
            )
        ],
        sections: [
            .init(title: "Workbench", body: "The Qt app compiles without CodeEdit's plugin graph while keeping the visible file tree and editor panels."),
            .init(title: "Diagnostics", body: "Fixture diagnostics give screenshot and smoke checks stable landmarks.")
        ],
        messages: [
            .init(sender: "diagnostic", body: "No Qt graph warnings are expected for this target.")
        ]
    )

    public static let signal = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Signal",
        sidebarTitle: "Signal",
        sidebarSubtitle: "Private messaging",
        primaryActionTitle: "Compose",
        secondaryActionTitle: "Archive",
        listTitle: "Chats",
        status: "End-to-end encrypted fixture state",
        detailTitle: "Conversation",
        detailSubtitle: "Shared chat shell rendered through Qt for parity with the GTK Signal target.",
        items: [
            .init(
                title: "Mira Patel",
                subtitle: "Lunch moved to 12:30",
                badge: "2",
                detailSubtitle: "Direct message thread with unread replies.",
                sections: [
                    .init(title: "Thread state", body: "Unread badges, preview text, and encrypted conversation chrome stay app-specific."),
                    .init(title: "Parity target", body: "The Qt pane now follows the selected chat instead of showing a static fallback.")
                ],
                messages: [
                    .init(sender: "Mira", body: "Lunch moved to 12:30."),
                    .init(sender: "You", body: "Works for me.")
                ]
            ),
            .init(
                title: "Design review",
                subtitle: "Wireframes are ready",
                detailSubtitle: "Group thread for product review notes.",
                sections: [
                    .init(title: "Thread state", body: "Group chat fixtures keep participants, attachment context, and delivery status in one shared model."),
                    .init(title: "Visual contract", body: "Selection-driven detail content gives GTK and Qt parity checks more meaningful landmarks.")
                ],
                messages: [
                    .init(sender: "Ari", body: "Wireframes are ready for the review."),
                    .init(sender: "You", body: "I will compare the desktop and Linux captures.")
                ]
            ),
            .init(
                title: "Family",
                subtitle: "Photos from the trip",
                badge: "5",
                detailSubtitle: "Media-heavy chat fixture for the lower selected row.",
                sections: [
                    .init(title: "Thread state", body: "The selected chat keeps media previews and unread state separate from the shared shell."),
                    .init(title: "Backend behavior", body: "Changing rows updates headers, detail cards, and messages through one Qt host path.")
                ],
                messages: [
                    .init(sender: "Sam", body: "Added the photos from the trip."),
                    .init(sender: "You", body: "Saving them after this build passes.")
                ]
            )
        ],
        sections: [
            .init(title: "Shared chat chrome", body: "Signal and Telegram use the same high-level chat layout contracts, with only app-specific fixture data changing."),
            .init(title: "Qt compile path", body: "The canonical quill-signal product now resolves to this Qt host when QUILLUI_LINUX_BACKEND=qt.")
        ],
        messages: [
            .init(sender: "Mira", body: "Can you check the latest Linux screenshot?"),
            .init(sender: "You", body: "Qt and GTK now use explicit build paths.")
        ]
    )

    public static let telegram = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Telegram",
        defaultWidth: 1100,
        defaultHeight: 720,
        sidebarTitle: "Telegram",
        sidebarSubtitle: "Channels and folders",
        primaryActionTitle: "New message",
        secondaryActionTitle: "Folders",
        listTitle: "Chats",
        status: "Pinned channels visible",
        detailTitle: "Channel preview",
        detailSubtitle: "Foldered chat list and channel activity rendered by the Qt backend.",
        items: [
            .init(
                title: "Swift Linux",
                subtitle: "Qt backend milestone",
                badge: "12",
                detailSubtitle: "Channel thread for Swift-on-Linux backend updates.",
                sections: [
                    .init(title: "Channel", body: "Unread count and channel preview stay attached to the selected Telegram row."),
                    .init(title: "Milestone", body: "Qt backend work shares the same chat shell renderer as Signal.")
                ],
                messages: [
                    .init(sender: "Swift Linux", body: "Qt backend milestone reached for canonical products."),
                    .init(sender: "You", body: "Keep GTK and Qt rows explicit.")
                ]
            ),
            .init(
                title: "Release ops",
                subtitle: "Nightly smoke passed",
                badge: "pin",
                detailSubtitle: "Pinned release operations channel selected.",
                sections: [
                    .init(title: "Channel", body: "Pinned state and smoke status stay visible in the selected row detail."),
                    .init(title: "Operations", body: "The detail pane uses the shared generic Qt cards instead of Telegram-only widgets.")
                ],
                messages: [
                    .init(sender: "Release ops", body: "Nightly smoke passed for the Qt matrix."),
                    .init(sender: "You", body: "Push the next atomic main commit after validation.")
                ]
            ),
            .init(
                title: "QuillUI Core",
                subtitle: "Backend registry changes",
                detailSubtitle: "Core engineering channel with the lower row selected.",
                sections: [
                    .init(title: "Channel", body: "Registry changes and backend contracts are visible in the selected channel detail."),
                    .init(title: "Shared shell", body: "Telegram stays app-specific through data while sharing the native Qt host.")
                ],
                messages: [
                    .init(sender: "QuillUI Core", body: "Backend registry changes landed on main."),
                    .init(sender: "You", body: "Next pass is app parity coverage.")
                ]
            )
        ],
        sections: [
            .init(title: "Folders", body: "Telegram keeps app-specific folders and unread badges on top of the shared chat layout."),
            .init(title: "DRY shell", body: "The Qt preview shares the same generic native shell as Signal, IceCubes, CodeEdit, IINA, and NetNewsWire.")
        ],
        messages: [
            .init(sender: "Release ops", body: "Canonical Qt products are building without suffix names.")
        ]
    )

    public static let iina = QuillGenericQtAppSnapshot(
        windowTitle: "Quill IINA",
        minimumWidth: 960,
        minimumHeight: 600,
        defaultWidth: 1080,
        defaultHeight: 660,
        sidebarTitle: "IINA",
        sidebarSubtitle: "Media player",
        primaryActionTitle: "Open media",
        secondaryActionTitle: "Playlist",
        listTitle: "Playlist",
        status: "Playback fixture paused at 01:24",
        selectedIndex: 1,
        detailTitle: "Player chrome",
        detailSubtitle: "Native Qt player layout with playlist, inspector, and playback status landmarks.",
        items: [
            .init(
                title: "Launch trailer",
                subtitle: "1080p H.264",
                badge: "3:12",
                detailSubtitle: "Video playlist item with transport controls visible.",
                sections: [
                    .init(title: "Now playing", body: "The trailer row keeps codec, duration, and playback state in the detail surface."),
                    .init(title: "Inspector", body: "Playlist selection updates metadata without replacing the native Qt window.")
                ]
            ),
            .init(
                title: "Linux smoke capture",
                subtitle: "720p VP9",
                badge: "1:24",
                detailSubtitle: "Default Linux smoke capture selected in the playlist.",
                sections: [
                    .init(title: "Now playing", body: "The smoke capture row mirrors the paused playback fixture used by GTK checks."),
                    .init(title: "Performance", body: "The native Qt host renders a stable player surface from a small snapshot.")
                ]
            ),
            .init(
                title: "Audio sample",
                subtitle: "AAC stereo",
                badge: "0:48",
                detailSubtitle: "Audio-only playlist fixture with the lower row selected.",
                sections: [
                    .init(title: "Now playing", body: "Audio-only selection swaps video metadata for waveform and channel context."),
                    .init(title: "Parity", body: "The lower row gives the Qt smoke a selected playlist detail target.")
                ]
            )
        ],
        sections: [
            .init(title: "Transport controls", body: "The Qt shell exposes the same player state hierarchy that GTK smoke screenshots assert."),
            .init(title: "Playlist", body: "Stable playlist rows give visual and interaction tests deterministic targets.")
        ]
    )
}

public enum QuillGenericQtNativeApp {
    public static func run(_ snapshot: QuillGenericQtAppSnapshot) -> Never {
        var launchSnapshot = snapshot
        if let selectedIndex = selectedIndexOverride(
            ProcessInfo.processInfo.environment["QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START"],
            itemCount: launchSnapshot.items.count
        ) {
            launchSnapshot.selectedIndex = selectedIndex
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(launchSnapshot)
            let payload = String(decoding: data, as: UTF8.self)
            let exitCode = payload.withCString { payloadPointer in
                quill_generic_qt_run_app_json(
                    CommandLine.argc,
                    CommandLine.unsafeArgv,
                    payloadPointer
                )
            }
            exit(Int32(exitCode))
        } catch {
            fputs("quill-generic-qt: failed to encode Qt payload: \(error)\n", stderr)
            exit(70)
        }
    }

    private static func selectedIndexOverride(_ value: String?, itemCount: Int) -> Int? {
        guard itemCount > 0, let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestedIndex = Int(trimmedValue) else {
            return nil
        }

        return min(max(requestedIndex, 0), itemCount - 1)
    }
}
#endif
