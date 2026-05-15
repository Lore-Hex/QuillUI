#if os(Linux)
import CQuillQt6WidgetsShim
import QuillQtNativeRuntimeSupport

public struct QuillGenericQtAppSnapshot: Codable, Sendable {
    public static let genericSelectedIndexEnvironmentKey = "QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START"
    public static let defaultSelectedIndexEnvironmentKeys = [genericSelectedIndexEnvironmentKey]

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
    public var selectedIndexEnvironmentKeys: [String]
    public var detailTitle: String
    public var detailSubtitle: String
    public var messagesTitle: String
    public var items: [Item]
    public var sections: [Section]
    public var messages: [Message]
    public var style: Style

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

    public struct Style: Codable, Sendable {
        public var canvasColor: String
        public var sidebarColor: String
        public var cardColor: String
        public var activeCardColor: String
        public var primaryColor: String
        public var inkColor: String
        public var mutedColor: String
        public var badgeColor: String
        public var selectedMutedColor: String
        public var borderColor: String
        public var selectedBorderColor: String
        public var dividerColor: String
        public var controlBorderColor: String

        public static let desktop = Style(
            canvasColor: "#F7F8F4",
            sidebarColor: "#EEF2EA",
            cardColor: "#FFFFFF",
            activeCardColor: "#E7F0FA",
            primaryColor: "#2E5B78",
            inkColor: "#182027",
            mutedColor: "#65707A",
            badgeColor: "#295A7A",
            selectedMutedColor: "#DDEBFA",
            borderColor: "#E0E4DC",
            selectedBorderColor: "#CBDDEB",
            dividerColor: "#D8DDD4",
            controlBorderColor: "#CDD5CA"
        )

        public init(
            canvasColor: String,
            sidebarColor: String,
            cardColor: String,
            activeCardColor: String,
            primaryColor: String,
            inkColor: String,
            mutedColor: String,
            badgeColor: String,
            selectedMutedColor: String,
            borderColor: String,
            selectedBorderColor: String,
            dividerColor: String,
            controlBorderColor: String
        ) {
            self.canvasColor = canvasColor
            self.sidebarColor = sidebarColor
            self.cardColor = cardColor
            self.activeCardColor = activeCardColor
            self.primaryColor = primaryColor
            self.inkColor = inkColor
            self.mutedColor = mutedColor
            self.badgeColor = badgeColor
            self.selectedMutedColor = selectedMutedColor
            self.borderColor = borderColor
            self.selectedBorderColor = selectedBorderColor
            self.dividerColor = dividerColor
            self.controlBorderColor = controlBorderColor
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
        selectedIndexEnvironmentKeys: [String] = QuillGenericQtAppSnapshot.defaultSelectedIndexEnvironmentKeys,
        detailTitle: String,
        detailSubtitle: String,
        messagesTitle: String = "Activity",
        items: [Item],
        sections: [Section],
        messages: [Message] = [],
        style: Style = .desktop
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
        self.selectedIndexEnvironmentKeys = selectedIndexEnvironmentKeys
        self.detailTitle = detailTitle
        self.detailSubtitle = detailSubtitle
        self.messagesTitle = messagesTitle
        self.items = items
        self.sections = sections
        self.messages = messages
        self.style = style
    }
}

private enum QuillGenericQtSelectionEnvironment {
    static let chat = "QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START"
    static let codeEdit = "QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START"
    static let enchanted = "QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START"
    static let enchantedQt = "QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"
    static let iceCubes = "QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START"
    static let iina = "QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START"
    static let netNewsWire = "QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START"
    static let signal = "QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START"
    static let telegram = "QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START"

    static func appSpecific(_ environmentKeys: String...) -> [String] {
        environmentKeys + QuillGenericQtAppSnapshot.defaultSelectedIndexEnvironmentKeys
    }
}

public enum QuillGenericQtAppCatalog {
    public static let quillChat = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Chat",
        defaultWidth: 1120,
        defaultHeight: 720,
        sidebarTitle: "Quill Chat",
        sidebarSubtitle: "Local AI workspace",
        primaryActionTitle: "New chat",
        secondaryActionTitle: "Models",
        listTitle: "Conversations",
        status: "Qt native runtime",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.chat
        ),
        detailTitle: "Conversation preview",
        detailSubtitle: "A generated Quill Chat package running through the Qt native host.",
        messagesTitle: "Transcript",
        items: [
            .init(
                title: "Model readiness",
                subtitle: "Check the local endpoint",
                badge: "ready",
                detailSubtitle: "Endpoint and model status remain visible beside the transcript.",
                sections: [
                    .init(title: "Endpoint", body: "The native shell keeps the selected model, endpoint state, and conversation list in the same layout across Linux backends."),
                    .init(title: "Result", body: "A short response confirms that generated packages are linked to the Qt native runtime.")
                ],
                messages: [
                    .init(sender: "user", body: "Confirm the local model is available."),
                    .init(sender: "assistant", body: "The generated Qt launcher is active.")
                ]
            ),
            .init(
                title: "Code review",
                subtitle: "Summarize pending changes",
                badge: "draft",
                detailSubtitle: "Review prompt with a compact response draft.",
                sections: [
                    .init(title: "Prompt", body: "The selected thread can carry app-specific context without duplicating launcher code."),
                    .init(title: "Draft", body: "Generated Quill Chat and canonical generic Qt apps share the same runtime renderer and catalog model.")
                ],
                messages: [
                    .init(sender: "user", body: "Summarize the next Linux parity gap."),
                    .init(sender: "assistant", body: "Generated Qt packages now compile against the native Qt runtime.")
                ]
            ),
            .init(
                title: "Planning note",
                subtitle: "Track desktop consistency",
                badge: "qa",
                detailSubtitle: "Desktop consistency checklist for the next loop.",
                sections: [
                    .init(title: "GTK", body: "The generated GTK launcher continues to use QuillUIGtk and QuillGtkApp."),
                    .init(title: "Qt", body: "The generated Qt launcher bypasses the fallback registry and enters QuillGenericQtNativeRuntime directly.")
                ],
                messages: [
                    .init(sender: "user", body: "Keep GTK and Qt explicit."),
                    .init(sender: "assistant", body: "The package generator now selects one native backend path per request.")
                ]
            )
        ],
        sections: [
            .init(title: "Generated app runtime", body: "The temporary package links QuillGenericQtNativeRuntime when QUILLUI_GENERATED_BACKEND_FACADE=qt is selected."),
            .init(title: "Shared renderer", body: "Quill Chat uses the same generic Qt catalog renderer as the smaller native app shells, keeping the implementation DRY.")
        ],
        messages: [
            .init(sender: "assistant", body: "Quill Chat is running through the generated Qt native entry.")
        ]
    )

    public static let enchantedUpstreamSlice = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Enchanted Slice",
        defaultWidth: 1120,
        defaultHeight: 720,
        sidebarTitle: "Enchanted",
        sidebarSubtitle: "Local AI conversations",
        primaryActionTitle: "New chat",
        secondaryActionTitle: "Models",
        listTitle: "Conversations",
        status: "Local model ready",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.enchanted,
            QuillGenericQtSelectionEnvironment.enchantedQt
        ),
        detailTitle: "Conversation preview",
        detailSubtitle: "A compact chat workspace with model status, recent prompts, and draft replies.",
        items: [
            .init(
                title: "Auto-config check",
                subtitle: "Reply with one short phrase",
                badge: "ollama",
                detailSubtitle: "Local model setup conversation with endpoint status visible.",
                sections: [
                    .init(title: "Endpoint", body: "The selected chat keeps the Ollama endpoint, model choice, and readiness status close to the transcript."),
                    .init(title: "Prompt", body: "A short assistant response confirms the local model is reachable before a longer session starts.")
                ],
                messages: [
                    .init(sender: "user", body: "Reply with one short phrase."),
                    .init(sender: "assistant", body: "Local model is ready.")
                ]
            ),
            .init(
                title: "Wedding plus-one",
                subtitle: "Draft a friendly message",
                badge: "draft",
                detailSubtitle: "Friendly draft-writing conversation.",
                sections: [
                    .init(title: "Conversation", body: "Draft state, title, and preview text stay easy to scan while the reply is refined."),
                    .init(title: "Composer", body: "Attachment context and the message composer remain close to the conversation.")
                ],
                messages: [
                    .init(sender: "user", body: "Draft a friendly plus-one message."),
                    .init(sender: "assistant", body: "Happy to join you at the wedding. Thanks for including me.")
                ]
            ),
            .init(
                title: "Language phrases",
                subtitle: "Practice short translations",
                detailSubtitle: "Language practice with the lower row selected.",
                sections: [
                    .init(title: "Session", body: "The selected practice thread updates the title, cards, and transcript together."),
                    .init(title: "Practice set", body: "The lower row keeps a distinct prompt, response, and detail card for quick review.")
                ],
                messages: [
                    .init(sender: "user", body: "Practice three short translations."),
                    .init(sender: "assistant", body: "Bonjour, gracias, and guten Abend.")
                ]
            )
        ],
        sections: [
            .init(title: "Endpoint and model controls", body: "The chat shell keeps model status, conversation selection, and prompt context in one workspace."),
            .init(title: "Conversation state", body: "Each row carries its own title, detail cards, and transcript so selection changes feel immediate.")
        ],
        messages: [
            .init(sender: "assistant", body: "The selected conversation is ready for a local-model response.")
        ]
    )

    public static let iceCubes = QuillGenericQtAppSnapshot(
        windowTitle: "Quill IceCubes",
        sidebarTitle: "IceCubes",
        sidebarSubtitle: "Mastodon timeline",
        primaryActionTitle: "Post",
        secondaryActionTitle: "Boosts",
        listTitle: "Timeline",
        status: "Public timeline loaded",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.iceCubes
        ),
        detailTitle: "Timeline item",
        detailSubtitle: "Mastodon-style timeline with replies, boosts, and post detail.",
        items: [
            .init(
                title: "Mastodon Design",
                subtitle: "Timeline polish update",
                badge: "2m",
                detailSubtitle: "Design notes from the product account.",
                sections: [
                    .init(title: "Post", body: "The selected timeline row opens a focused view with author, timestamp, and excerpt."),
                    .init(title: "Actions", body: "Reply, boost, favorite, and share affordances stay in a predictable hierarchy.")
                ]
            ),
            .init(
                title: "Swift on Linux",
                subtitle: "Desktop packaging notes",
                badge: "8m",
                detailSubtitle: "Toolchain update focused on Linux app packaging.",
                sections: [
                    .init(title: "Thread", body: "The post collects packaging notes, release steps, and a short checklist for desktop builds."),
                    .init(title: "Build note", body: "The update is grouped with related replies so the thread can be reviewed quickly.")
                ]
            ),
            .init(
                title: "Mastodon",
                subtitle: "Timeline cards, replies, and boosts",
                badge: "14m",
                detailSubtitle: "Open conversation with replies and boosts.",
                sections: [
                    .init(title: "Conversation", body: "Replies and boost counts remain visible when the selected row changes."),
                    .init(title: "Thread detail", body: "The lower row carries a distinct conversation preview for selection checks.")
                ]
            )
        ],
        sections: [
            .init(title: "Timeline density", body: "Rows keep avatars, timestamps, and action affordances in a compact, repeatable hierarchy."),
            .init(title: "Responsive updates", body: "Selection changes update detail cards and messages without disturbing the timeline list.")
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
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.netNewsWire
        ),
        detailTitle: "Article reader",
        detailSubtitle: "RSS reader with feed selection, unread counts, and article excerpts.",
        items: [
            .init(
                title: "Swift.org",
                subtitle: "Language and toolchain updates",
                badge: "1",
                detailSubtitle: "Unread language and toolchain article selected.",
                sections: [
                    .init(title: "Article", body: "The Swift.org entry keeps source, title, and unread count visible in the reader."),
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
                title: "Linux Weekly",
                subtitle: "Desktop compatibility report",
                detailSubtitle: "Desktop compatibility article selected for reading.",
                sections: [
                    .init(title: "Article", body: "The report summarizes desktop polish, packaging notes, and recently fixed regressions."),
                    .init(title: "Reader state", body: "The lower feed row gives the reader a distinct article surface.")
                ]
            )
        ],
        sections: [
            .init(title: "Reader layout", body: "The reader keeps feed selection, unread counts, and article detail in a steady three-pane rhythm."),
            .init(title: "Article state", body: "Each feed row carries the headline, excerpt, and selected-state detail needed for fast scanning.")
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
        status: "Workspace loaded",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.codeEdit
        ),
        detailTitle: "Editor preview",
        detailSubtitle: "Workbench with file tree, tabs, diagnostics, and editor chrome.",
        items: [
            .init(
                title: "Package.swift",
                subtitle: "Package manifest",
                badge: "M",
                detailSubtitle: "Manifest preview with package products and targets.",
                sections: [
                    .init(title: "Editor", body: "The manifest row highlights products, target dependencies, and package metadata."),
                    .init(title: "Diagnostics", body: "The modified badge remains visible while the file preview changes.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "Package metadata is ready for review.")
                ]
            ),
            .init(
                title: "QuillUI.swift",
                subtitle: "Application entry point",
                detailSubtitle: "Source preview for the shared app entry point.",
                sections: [
                    .init(title: "Editor", body: "The facade row keeps the app entry point and scene metadata in the detail pane."),
                    .init(title: "Navigation", body: "Changing file rows updates the same workbench surface.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "No stale detail content after file selection.")
                ]
            ),
            .init(
                title: "ProjectNavigator.swift",
                subtitle: "Workspace navigation",
                detailSubtitle: "Project navigator source file selected.",
                sections: [
                    .init(title: "Editor", body: "The selected navigator row describes file grouping, search state, and outline metadata."),
                    .init(title: "Selection", body: "This row makes the editor preview update beyond the sidebar selection.")
                ],
                messages: [
                    .init(sender: "diagnostic", body: "Navigator selection updates the editor preview.")
                ]
            )
        ],
        sections: [
            .init(title: "Workbench", body: "The app keeps the visible file tree, editor panels, and diagnostics in a compact desktop layout."),
            .init(title: "Diagnostics", body: "Diagnostics stay attached to the selected file so review context remains clear.")
        ],
        messages: [
            .init(sender: "diagnostic", body: "No warnings are expected for this target.")
        ]
    )

    public static let signal = QuillGenericQtAppSnapshot(
        windowTitle: "Quill Signal",
        sidebarTitle: "Signal",
        sidebarSubtitle: "Private messaging",
        primaryActionTitle: "Compose",
        secondaryActionTitle: "Archive",
        listTitle: "Chats",
        status: "End-to-end encrypted",
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.signal,
            QuillGenericQtSelectionEnvironment.chat
        ),
        detailTitle: "Conversation",
        detailSubtitle: "Private messaging layout with chat list, unread badges, and thread detail.",
        items: [
            .init(
                title: "Mira Patel",
                subtitle: "Lunch moved to 12:30",
                badge: "2",
                detailSubtitle: "Direct message thread with unread replies.",
                sections: [
                    .init(title: "Thread state", body: "Unread badges, preview text, and encrypted conversation chrome stay app-specific."),
                    .init(title: "Conversation detail", body: "The detail pane follows the selected chat instead of showing a static fallback.")
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
                    .init(title: "Thread state", body: "Group chat state keeps participants, attachment context, and delivery status in one model."),
                    .init(title: "Visual contract", body: "Selection-driven detail content gives each chat a meaningful preview.")
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
                detailSubtitle: "Weekend photo thread with media previews.",
                sections: [
                    .init(title: "Thread state", body: "The selected chat keeps media previews and unread state separate from the shared shell."),
                    .init(title: "Conversation detail", body: "Changing rows updates headers, detail cards, and messages together.")
                ],
                messages: [
                    .init(sender: "Sam", body: "Added the photos from the trip."),
                    .init(sender: "You", body: "Saving them after this build passes.")
                ]
            )
        ],
        sections: [
            .init(title: "Chat chrome", body: "Signal keeps a dense chat list, unread badges, and selected-thread messages in one workspace."),
            .init(title: "Message state", body: "Conversation rows update the header, detail cards, and recent messages together.")
        ],
        messages: [
            .init(sender: "Mira", body: "Can you check the latest screenshots?"),
            .init(sender: "You", body: "I will review them before the meeting.")
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
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.telegram,
            QuillGenericQtSelectionEnvironment.chat
        ),
        detailTitle: "Channel preview",
        detailSubtitle: "Foldered chat list with pinned channels and recent activity.",
        items: [
            .init(
                title: "Swift Linux",
                subtitle: "Desktop packaging notes",
                badge: "12",
                detailSubtitle: "Channel thread for Swift-on-Linux updates.",
                sections: [
                    .init(title: "Channel", body: "Unread count and channel preview stay attached to the selected Telegram row."),
                    .init(title: "Milestone", body: "The channel collects release notes, packaging steps, and migration reminders.")
                ],
                messages: [
                    .init(sender: "Swift Linux", body: "Desktop packaging notes are ready for review."),
                    .init(sender: "You", body: "Keep the release checklist explicit.")
                ]
            ),
            .init(
                title: "Release ops",
                subtitle: "Nightly checks passed",
                badge: "pin",
                detailSubtitle: "Pinned release operations channel selected.",
                sections: [
                    .init(title: "Channel", body: "Pinned state and check status stay visible in the selected row detail."),
                    .init(title: "Operations", body: "The detail pane keeps release notes, owners, and current status together.")
                ],
                messages: [
                    .init(sender: "Release ops", body: "Nightly checks passed for the release train."),
                    .init(sender: "You", body: "I will review the report before publishing.")
                ]
            ),
            .init(
                title: "Core Team",
                subtitle: "Project board updates",
                detailSubtitle: "Core engineering channel with the lower row selected.",
                sections: [
                    .init(title: "Channel", body: "Project board changes and owner updates are visible in the selected channel detail."),
                    .init(title: "Shared shell", body: "Telegram keeps folders, pinned channels, and channel previews in the same chat layout.")
                ],
                messages: [
                    .init(sender: "Core Team", body: "Project board changes landed this morning."),
                    .init(sender: "You", body: "Next pass is app coverage.")
                ]
            )
        ],
        sections: [
            .init(title: "Folders", body: "Telegram keeps app-specific folders and unread badges on top of the shared chat layout."),
            .init(title: "Channels", body: "Pinned channels, unread counts, and previews remain clear across the selected chat.")
        ],
        messages: [
            .init(sender: "Release ops", body: "Nightly checks are ready for review.")
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
        status: "Paused at 01:24",
        selectedIndex: 1,
        selectedIndexEnvironmentKeys: QuillGenericQtSelectionEnvironment.appSpecific(
            QuillGenericQtSelectionEnvironment.iina
        ),
        detailTitle: "Player chrome",
        detailSubtitle: "Player layout with playlist, inspector, and playback status.",
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
                title: "Conference demo",
                subtitle: "720p VP9",
                badge: "1:24",
                detailSubtitle: "Conference demo selected in the playlist.",
                sections: [
                    .init(title: "Now playing", body: "The selected row keeps codec, elapsed time, and paused state visible."),
                    .init(title: "Performance", body: "The player surface updates metadata without replacing the surrounding controls.")
                ]
            ),
            .init(
                title: "Audio sample",
                subtitle: "AAC stereo",
                badge: "0:48",
                detailSubtitle: "Audio-only playlist item selected.",
                sections: [
                    .init(title: "Now playing", body: "Audio-only selection swaps video metadata for waveform and channel context."),
                    .init(title: "Playlist detail", body: "The lower row keeps a distinct detail surface for audio playback.")
                ]
            )
        ],
        sections: [
            .init(title: "Transport controls", body: "The player exposes a steady hierarchy for playback state, duration, and metadata."),
            .init(title: "Playlist", body: "Playlist rows keep titles, durations, codecs, and selected-state detail easy to compare.")
        ]
    )
}

public enum QuillGenericQtNativeApp {
    public static func run(_ snapshot: QuillGenericQtAppSnapshot) -> Never {
        var launchSnapshot = snapshot
        if let selectedIndex = QuillQtNativeRuntimeSupport.boundedIndexOverride(
            environmentKeys: launchSnapshot.selectedIndexEnvironmentKeys,
            count: launchSnapshot.items.count
        ) {
            launchSnapshot.selectedIndex = selectedIndex
        }

        QuillQtNativeRuntimeSupport.runEncodedPayload(
            launchSnapshot,
            executableName: QuillQtNativeRuntimeSupport.executableName(fallback: "quill-generic-qt")
        ) { payloadPointer in
            quill_generic_qt_run_app_json(
                CommandLine.argc,
                CommandLine.unsafeArgv,
                payloadPointer
            )
        }
    }
}
#endif
