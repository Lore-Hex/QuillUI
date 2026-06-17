import Foundation
import QuillKit
import QuillUIGtk
import QuillUIQt
import SwiftUI
import Testing
@testable import QuillUI

@Suite("QuillUI core library")
struct QuillUITests {

    // MARK: - QuillPlatform.name

    @Test("QuillPlatform.name reports the host platform")
    func quillPlatformReportsHost() {
        // The conditional inside QuillPlatform expands to the
        // build-time os check. On the CI runners we cover macOS
        // and Linux; both are non-empty and not "Unknown".
        #expect(!QuillPlatform.name.isEmpty)
        #expect(QuillPlatform.name != "Unknown")

        #if os(macOS)
        #expect(QuillPlatform.name == "macOS")
        #elseif os(Linux)
        #expect(QuillPlatform.name == "Linux")
        #elseif os(iOS)
        #expect(QuillPlatform.name == "iOS")
        #endif
    }

    // MARK: - QuillUIVersion.current

    @Test("QuillUIVersion.current is non-empty + semver-shaped")
    func quillUIVersionIsSemverShape() {
        let v = QuillUIVersion.current
        #expect(!v.isEmpty)

        // Semver-shape: at least two dots, all numeric segments.
        let parts = v.split(separator: ".")
        #expect(parts.count == 3, "version \(v) is not three dotted segments")
        #expect(parts.allSatisfy { Int($0) != nil }, "version \(v) has non-numeric parts")
    }

    // MARK: - QuillApp.run helper exists

    @Test("QuillApp.run<A: App> exists as a nonisolated static entry point")
    func quillAppRunIsCallableFromTopLevel() {
        // Verify the helper resolves at compile time. Runtime
        // invocation would call App.main() and never return,
        // so this test only confirms the type-level shape.
        let _ : (any Any.Type) -> () = { _ in /* unused */ }
        // Keep the reference so unused-symbol pruning can't omit
        // QuillApp from the binary.
        _ = QuillApp.self
        _ = QuillAppWindow.self
    }

    #if os(Linux)
    @Test("LocalizedStringKey interpolation keeps catalog keys and formatted arguments")
    func localizedStringKeyInterpolationKeepsCatalogShape() throws {
        let count = 872_850
        let key: LocalizedStringKey =
            "account.label.followers \(count) \(count, format: .number.notation(.compactName))"

        #expect(key.key == "account.label.followers %lld %@")
        #expect(key.arguments == ["872850", "872.9K"])
        #expect(Text(count, format: .number.notation(.compactName)).content == "872.9K")
    }
    #endif

    // MARK: - QuillPromptGridLayout

    @Test("QuillPromptGridLayout exposes reusable desktop prompt presets")
    func quillPromptGridLayoutPresets() {
        let clamped = QuillPromptGridLayout(columns: 0, cardWidth: 120, cardHeight: 80, spacing: 6)
        #expect(clamped.columns == 1)
        #expect(clamped.cardWidth == 120)
        #expect(clamped.cardHeight == 80)
        #expect(clamped.spacing == 6)

        #expect(QuillPromptGridLayout.compactCards == QuillPromptGridLayout())
        #expect(QuillPromptGridLayout.wideDesktopCards.columns == 4)
        #expect(QuillPromptGridLayout.wideDesktopCards.cardWidth == 302)
        #expect(QuillPromptGridLayout.wideDesktopCards.cardHeight == 128)
        #expect(QuillPromptGridLayout.wideDesktopCards.spacing == 15)
    }

    @Test("QuillPrompt selects preferred prompt order with prefix fallback")
    func quillPromptSelectedPrompts() {
        struct Sample {
            var id: String
            var prompt: String
            var icon: String
        }

        let samples = [
            Sample(id: "a", prompt: "Alpha", icon: "a.circle"),
            Sample(id: "b", prompt: "Beta", icon: "b.circle"),
            Sample(id: "c", prompt: "Gamma", icon: "c.circle")
        ]

        let preferred = QuillPrompt.selectedPrompts(
            from: samples,
            preferredTitles: ["Gamma", "Alpha"],
            id: { $0.id },
            title: { $0.prompt },
            systemImage: { $0.icon }
        )
        #expect(preferred.map(\.id) == ["c", "a"])
        #expect(preferred.map(\.title) == ["Gamma", "Alpha"])
        #expect(preferred.map(\.systemImage) == ["c.circle", "a.circle"])

        let fallback = QuillPrompt.selectedPrompts(
            from: samples,
            preferredTitles: ["Missing", "Alpha"],
            fallbackCount: 2,
            id: { $0.id },
            title: { $0.prompt },
            systemImage: { $0.icon }
        )
        #expect(fallback.map(\.id) == ["a", "b"])

        let emptyFallback = QuillPrompt.selectedPrompts(
            from: samples,
            preferredTitles: ["Missing"],
            fallbackCount: -1,
            id: { $0.id },
            title: { $0.prompt },
            systemImage: { $0.icon }
        )
        #expect(emptyFallback.isEmpty)

        #expect(QuillPrompt.quillChatMacReferencePromptTitles == [
            "How to center div in HTML?",
            "How to do personal taxes in USA?",
            "Explain supercomputers like I'm five years old",
            "Write a text message asking a friend to be my plus-one at a wedding"
        ])

        var sentPrompt = ""
        let emptyState = QuillSelectedPromptEmptyState(
            brandTitle: "Quill",
            source: samples,
            preferredTitles: ["Beta", "Alpha"],
            id: { $0.id },
            title: { $0.prompt },
            systemImage: { $0.icon },
            sendPrompt: { sentPrompt = $0 }
        )
        #expect(emptyState.prompts.map(\.title) == ["Beta", "Alpha"])
        emptyState.sendPrompt("Beta")
        #expect(sentPrompt == "Beta")
    }

    @Test("QuillPrompt builds selected-model prompt senders")
    func quillPromptSelectedModelSender() {
        struct Model: Equatable {
            var name: String
        }

        var sent: [(String, Model, String?, Int?)] = []
        let send = QuillPrompt.selectedModelSender(
            selectedModel: Model(name: "local"),
            attachment: "image.png",
            trimmingID: 42
        ) { prompt, model, attachment, trimmingID in
            sent.append((prompt, model, attachment, trimmingID))
        }

        send("Explain SwiftUI")
        #expect(sent.count == 1)
        #expect(sent[0].0 == "Explain SwiftUI")
        #expect(sent[0].1 == Model(name: "local"))
        #expect(sent[0].2 == "image.png")
        #expect(sent[0].3 == 42)

        let nilModelSend = QuillPrompt.selectedModelSender(
            selectedModel: Optional<Model>.none,
            attachment: Optional<String>.none,
            trimmingID: Optional<Int>.none
        ) { prompt, model, attachment, trimmingID in
            sent.append((prompt, model, attachment, trimmingID))
        }
        nilModelSend("Ignored")
        #expect(sent.count == 1)
    }

    @Test("QuillChatComposer exposes reusable chat composer state")
    func quillChatComposerState() {
        var draft = "Hello"
        let composer = QuillChatComposer(
            message: Binding(get: { draft }, set: { draft = $0 }),
            isLoading: true,
            supportsImages: true,
            selectedImage: Image(systemName: "photo"),
            onSend: {}
        )

        #expect(composer.message == "Hello")
        #expect(composer.isLoading)
        #expect(composer.supportsImages)
        #expect(composer.showsRecording)
        #expect(composer.selectedImage != nil)
    }

    @Test("QuillChatComposer exposes binding-backed selected image state")
    func quillChatComposerBindingSelectedImageState() {
        var draft = "Describe this"
        var selectedImage: Image? = Image(systemName: "photo")
        let composer = QuillChatComposer(
            message: Binding(get: { draft }, set: { draft = $0 }),
            supportsImages: true,
            selectedImage: Binding(get: { selectedImage }, set: { selectedImage = $0 }),
            onSend: {}
        )

        #expect(composer.message == "Describe this")
        #expect(composer.supportsImages)
        #expect(composer.selectedImage != nil)

        selectedImage = nil
        #expect(composer.selectedImage == nil)
    }

    // MARK: - QuillMenuAction helpers

    @Test("QuillMenuAction builds disabled and selectable menu rows")
    func quillMenuActionSelectableItems() {
        struct MenuItem {
            var id: String
            var title: String
        }

        var selectedTitle: String?
        let items = [
            MenuItem(id: "a", title: "Alpha"),
            MenuItem(id: "b", title: "Beta")
        ]
        let actions = QuillMenuAction.selectableItems(
            items,
            selectedID: "b",
            emptyTitle: "No items",
            id: { $0.id },
            title: { $0.title },
            onSelect: { selectedTitle = $0.title }
        )

        #expect(actions.map(\.id) == ["a", "b"])
        #expect(actions.map(\.title) == ["Alpha", "Beta"])
        #expect(actions.map(\.systemImage) == [nil, "checkmark"])
        #expect(actions.allSatisfy { !$0.isDisabled })

        actions[0].perform()
        #expect(selectedTitle == "Alpha")

        selectedTitle = nil
        let emptyActions = QuillMenuAction.selectableItems(
            [MenuItem](),
            selectedID: Optional<String>.none,
            emptyTitle: "No items",
            id: { $0.id },
            title: { $0.title },
            onSelect: { selectedTitle = $0.title }
        )

        #expect(emptyActions.count == 1)
        #expect(emptyActions.first?.title == "No items")
        #expect(emptyActions.first?.isDisabled == true)
        emptyActions.first?.perform()
        #expect(selectedTitle == nil)

        let clipboard = QuillClipboard()
        let copy = QuillMenuAction.copyText("Copied text", clipboard: clipboard)
        #expect(copy.title == "Copy")
        #expect(copy.systemImage == "doc.on.doc")
        copy.perform()
        #expect(clipboard.string() == "Copied text")

        var didEdit = false
        let edit = QuillMenuAction.edit { didEdit = true }
        #expect(edit.title == "Edit")
        #expect(edit.systemImage == "pencil")
        edit.perform()
        #expect(didEdit)

        var didUnselect = false
        let unselect = QuillMenuAction.unselect { didUnselect = true }
        #expect(unselect.title == "Unselect")
        #expect(unselect.systemImage == "pencil")
        unselect.perform()
        #expect(didUnselect)

        let messageClipboard = QuillClipboard()
        var didSelectText = false
        var didReadAloud = false
        var didPerformExtra = false
        var didEditMessage = false
        var didUnselectMessage = false
        let messageActions = QuillMenuAction.chatMessageActions(
            content: "Message text",
            isUserMessage: true,
            isEditing: true,
            selectText: { didSelectText = true },
            readAloud: { didReadAloud = true },
            additionalActions: [
                QuillMenuAction(title: "Extra", systemImage: "sparkle") {
                    didPerformExtra = true
                }
            ],
            onEdit: { didEditMessage = true },
            onUnselect: { didUnselectMessage = true },
            clipboard: messageClipboard
        )

        #expect(messageActions.map(\.title) == ["Copy", "Select Text", "Read Aloud", "Extra", "Edit", "Unselect"])
        messageActions.forEach { $0.perform() }
        #expect(messageClipboard.string() == "Message text")
        #expect(didSelectText)
        #expect(didReadAloud)
        #expect(didPerformExtra)
        #expect(didEditMessage)
        #expect(didUnselectMessage)

        var copiedJSONValues: [Bool] = []
        let copyChatActions = QuillMenuAction.copyChatActions { copiedJSONValues.append($0) }
        #expect(copyChatActions.map(\.title) == ["Copy Chat", "Copy Chat as JSON"])
        #expect(copyChatActions.map(\.systemImage) == ["doc.on.doc", "curlybraces"])
        copyChatActions.forEach { $0.perform() }
        #expect(copiedJSONValues == [false, true])

        struct Model {
            var id: String
            var name: String
            var version: String
        }

        var selectedModelID: String?
        let modelActions = QuillMenuAction.selectableModels(
            [
                Model(id: "fast", name: "Fast", version: ""),
                Model(id: "smart", name: "Smart", version: "v2")
            ],
            selectedID: "smart",
            id: { $0.id },
            name: { $0.name },
            version: { $0.version },
            onSelect: { selectedModelID = $0.id }
        )

        #expect(modelActions.map(\.title) == ["Fast", "Smart v2"])
        #expect(modelActions.map(\.systemImage) == [nil, "checkmark"])
        modelActions[0].perform()
        #expect(selectedModelID == "fast")
    }

    @Test("QuillSheetStatusBanner exposes reusable sheet-backed status state")
    func quillSheetStatusBannerStoresConfiguration() {
        let banner = QuillSheetStatusBanner(
            message: "Offline",
            actionTitle: "Settings",
            showsActivity: true,
            horizontalPadding: 28,
            topPadding: 10,
            bottomPadding: 74
        ) {
            QuillStatusBanner(message: "Settings")
        }

        #expect(banner.message == "Offline")
        #expect(banner.actionTitle == "Settings")
        #expect(banner.showsActivity == true)
        #expect(banner.horizontalPadding == 28)
        #expect(banner.topPadding == 10)
        #expect(banner.bottomPadding == 74)

        let unreachableBanner = QuillChatUnreachableBanner {
            QuillStatusBanner(message: "Settings")
        }
        #expect(unreachableBanner.message.contains("Quill is unreachable"))
        #expect(unreachableBanner.message.contains("update your Quill API endpoint"))
        #expect(unreachableBanner.actionTitle == "Settings")
        #expect(unreachableBanner.showsActivity == false)
        #expect(unreachableBanner.horizontalPadding == 28)
        #expect(unreachableBanner.topPadding == 10)
        #expect(unreachableBanner.bottomPadding == 74)
    }

    @Test("QuillDesktopChatScaffold builds standard toolbar shells")
    func quillDesktopChatScaffoldStandardToolbarInitializer() {
        let scaffold = QuillDesktopChatScaffold(
            title: "Chat",
            sidebarWidth: 280,
            hasSelection: false,
            showsStatus: true,
            modelActions: [],
            optionsActions: [],
            onNewConversation: {}
        ) {
            Text("Sidebar")
        } selectedContent: {
            Text("Selected")
        } emptyContent: {
            Text("Empty")
        } statusContent: {
            Text("Status")
        } composer: {
            Text("Composer")
        }

        #expect(scaffold.title == "Chat")
        #expect(scaffold.sidebarWidth == 280)
        #expect(scaffold.hasSelection == false)
        #expect(scaffold.showsStatus == true)

        struct Message: Equatable {
            var content: String
        }
        let editableScaffold = QuillEditableDesktopChatScaffold(
            title: "Editable Chat",
            sidebarWidth: 300,
            hasSelection: true,
            showsStatus: false,
            modelActions: [],
            optionsActions: [],
            onNewConversation: {},
            initialDraft: "Draft",
            initialEditMessage: Optional<Message>.none,
            editContent: { (message: Message) in message.content }
        ) {
            Text("Sidebar")
        } selectedContent: { editMessage in
            Text(editMessage.wrappedValue?.content ?? "Selected")
        } emptyContent: {
            Text("Empty")
        } statusContent: {
            Text("Status")
        } composer: { draft, _ in
            Text(draft.wrappedValue)
        }

        #expect(editableScaffold.title == "Editable Chat")
        #expect(editableScaffold.sidebarWidth == 300)
        #expect(editableScaffold.hasSelection == true)
        #expect(editableScaffold.showsStatus == false)
    }

    @Test("QuillModelConversationChatScaffold owns model chat shell actions")
    @MainActor
    func quillModelConversationChatScaffoldBuildsDerivedActions() {
        struct Conversation {
            var id: String
            var title: String
            var updatedAt: Date
            var lastMessage: String
        }
        struct Model {
            var id: String
            var name: String
            var version: String
        }
        struct Prompt {
            var id: String
            var title: String
            var icon: String
        }
        struct Message: Equatable {
            var content: String
        }

        let conversations = [
            Conversation(id: "c1", title: "First", updatedAt: Date(timeIntervalSince1970: 10), lastMessage: "Hello")
        ]
        let models = [
            Model(id: "m1", name: "Small", version: "v1"),
            Model(id: "m2", name: "Large", version: "v2")
        ]
        let prompts = [
            Prompt(id: "p1", title: "Explain", icon: "questionmark.circle")
        ]
        var selectedModel = ""
        var copiedJSONValues: [Bool] = []

        let scaffold = QuillModelConversationChatScaffold(
            title: "Chat",
            conversations: conversations,
            selectedConversationID: "c1",
            models: models,
            selectedModelID: "m2",
            promptSource: prompts,
            reachable: false,
            statusMaxWidth: 888,
            onNewConversation: {},
            editContent: { (message: Message) in message.content },
            conversationID: \.id,
            conversationTitle: \.title,
            conversationUpdatedAt: \.updatedAt,
            conversationLastMessage: \.lastMessage,
            conversationDateTitle: { _ in "Today" },
            onSettings: {},
            onSelectConversation: { _ in },
            onDeleteConversation: { _ in },
            onDeleteDailyConversations: { _ in },
            modelID: \.id,
            modelName: \.name,
            modelVersion: \.version,
            onSelectModel: { selectedModel = $0.id },
            copyChat: { copiedJSONValues.append($0) },
            promptID: \.id,
            promptTitle: \.title,
            promptSystemImage: \.icon,
            sendPrompt: { _ in }
        ) { editMessage in
            Text(editMessage.wrappedValue?.content ?? "Selected")
        } composer: { draft, _ in
            Text(draft.wrappedValue)
        } settings: {
            Text("Settings")
        } completions: {
            Text("Completions")
        } shortcuts: {
            Text("Shortcuts")
        }

        #expect(scaffold.title == "Chat")
        #expect(scaffold.conversations.count == 1)
        #expect(scaffold.selectedConversationID == "c1")
        #expect(scaffold.hasSelection == true)
        #expect(scaffold.reachable == false)
        #expect(scaffold.showsStatus == true)
        #expect(scaffold.statusMaxWidth == 888)

        let modelActions = scaffold.modelActions
        #expect(modelActions.map(\.title) == ["Small v1", "Large v2"])
        #expect(modelActions[0].systemImage == nil)
        #expect(modelActions[1].systemImage == "checkmark")
        modelActions[0].perform()
        #expect(selectedModel == "m1")

        let options = scaffold.optionsActions
        #expect(options.map(\.title) == ["Copy Chat", "Copy Chat as JSON"])
        options.forEach { $0.perform() }
        #expect(copiedJSONValues == [false, true])
    }

    @Test("Editable message sync modifier accepts optional edit bindings")
    func quillSyncEditableMessageModifierCompiles() {
        struct Message: Equatable {
            var content: String
        }

        struct Probe: View {
            @State var editMessage: Message?
            @State var draft = ""
            @FocusState var isFocused: Bool

            var body: some View {
                Text(draft)
                    .quillSyncEditableMessage($editMessage, draft: $draft, isFocused: $isFocused, content: \.content)
            }
        }

        _ = Probe()
    }

    @Test("QuillSidebarNavigationAction exposes standard desktop chat utilities")
    func quillSidebarNavigationActionDesktopChatUtilities() {
        var opened: [String] = []
        let utilities = QuillSidebarNavigationAction.desktopChatUtilities(
            onCompletions: { opened.append("completions") },
            onShortcuts: { opened.append("shortcuts") },
            onSettings: { opened.append("settings") }
        )

        #if os(macOS) || os(Linux)
        #expect(utilities.map(\.title) == ["Completions", "Shortcuts", "Settings"])
        #expect(utilities.map(\.systemImage) == ["textformat.abc", "keyboard.fill", "gearshape.fill"])
        #else
        #expect(utilities.map(\.title) == ["Settings"])
        #expect(utilities.map(\.systemImage) == ["gearshape.fill"])
        #endif

        utilities.forEach { $0.perform() }
        #if os(macOS) || os(Linux)
        #expect(opened == ["completions", "shortcuts", "settings"])
        #else
        #expect(opened == ["settings"])
        #endif

        var showCompletions = false
        var showShortcuts = false
        var showSettings = false
        var tappedSettings = false
        let toggles = QuillSidebarNavigationAction.desktopChatUtilityToggles(
            showCompletions: Binding(get: { showCompletions }, set: { showCompletions = $0 }),
            showShortcuts: Binding(get: { showShortcuts }, set: { showShortcuts = $0 }),
            showSettings: Binding(get: { showSettings }, set: { showSettings = $0 }),
            onSettings: { tappedSettings = true }
        )

        #if os(macOS) || os(Linux)
        toggles[0].perform()
        #expect(showCompletions)
        #expect(!showShortcuts)
        #expect(!showSettings)

        toggles[0].perform()
        #expect(showCompletions)
        #expect(!showShortcuts)
        #expect(!showSettings)

        toggles[1].perform()
        #expect(!showCompletions)
        #expect(showShortcuts)
        #expect(!showSettings)

        toggles[2].perform()
        #expect(!showCompletions)
        #expect(!showShortcuts)
        #expect(showSettings)
        #else
        toggles.forEach { $0.perform() }
        #expect(!showCompletions)
        #expect(!showShortcuts)
        #expect(showSettings)
        #endif
        #expect(tappedSettings)
    }

    @Test("QuillDesktopChatUtilitySidebar owns utility sheet state")
    func quillDesktopChatUtilitySidebarOwnsUtilitySheetState() {
        let sidebar = QuillDesktopChatUtilitySidebar {
            Text("History")
        } settings: {
            Text("Settings")
        } completions: {
            Text("Completions")
        } shortcuts: {
            Text("Shortcuts")
        }

        #expect(sidebar.settingsFocusedValue == nil)
    }

    @Test("QuillDesktopChatUtilitySidebar supports completion sheet startup automation")
    func quillDesktopChatUtilitySidebarSupportsCompletionSheetStartupAutomation() {
        #expect(!QuillDesktopChatInitialUtilitySheet.showCompletions(environment: [:]))
        #expect(!QuillDesktopChatInitialUtilitySheet.showCompletions(environment: [
            "QUILLUI_CHAT_SHOW_COMPLETIONS_ON_START": "0"
        ]))
        #expect(QuillDesktopChatInitialUtilitySheet.showCompletions(environment: [
            "QUILLUI_CHAT_SHOW_COMPLETIONS_ON_START": "  yes "
        ]))
        #expect(QuillDesktopChatInitialUtilitySheet.showCompletions(environment: [
            "QUILLUI_QUILL_CHAT_SHOW_COMPLETIONS_ON_START": "TRUE"
        ]))
        #expect(QuillDesktopChatInitialUtilitySheet.showCompletions(environment: [
            "QUILLUI_ENCHANTED_SHOW_COMPLETIONS_ON_START": "on"
        ]))
        #expect(QuillDesktopChatInitialUtilitySheet.showCompletions(environment: [
            "QUILLUI_GTK_ENCHANTED_SHOW_COMPLETIONS_ON_START": "1"
        ]))
    }

    @Test("QuillDesktopChatConversationSidebar adapts model history into utility chrome")
    func quillDesktopChatConversationSidebarAdaptsModelHistory() {
        struct Conversation {
            var id: String
            var title: String
            var updatedAt: Date
        }

        let conversations = [
            Conversation(id: "one", title: "First", updatedAt: Date(timeIntervalSince1970: 10)),
            Conversation(id: "two", title: "Second", updatedAt: Date(timeIntervalSince1970: 20))
        ]

        let sidebar = QuillDesktopChatConversationSidebar(
            conversations: conversations,
            selectedID: "two",
            id: \.id,
            title: \.title,
            updatedAt: \.updatedAt,
            dateTitle: { "\($0.timeIntervalSince1970)" },
            onSelect: { _ in }
        ) {
            Text("Settings")
        } completions: {
            Text("Completions")
        } shortcuts: {
            Text("Shortcuts")
        }

        #expect(sidebar.conversations.count == 2)
        #expect(sidebar.selectedID == "two")
        #expect(sidebar.settingsFocusedValue == nil)
    }

    @Test("Message arrays build streaming scroll tokens from ids and last content")
    func messageArrayBuildsStreamingScrollToken() {
        struct Message: Identifiable {
            var id: String
            var content: String
        }

        let messages = [
            Message(id: "one", content: "hello"),
            Message(id: "two", content: "partial")
        ]

        #expect(messages.quillMessageListScrollToken(content: \.content) == AnyHashable("one|two|partial"))
        #expect([Message]().quillMessageListScrollToken(content: \.content) == AnyHashable("|"))
    }

    @Test("QuillEditableMessageList centralizes chat message menu actions")
    @MainActor
    func quillEditableMessageListBuildsMessageActions() {
        struct Message: Identifiable, Hashable {
            var id: String
            var role: String
            var content: String
        }

        let messages = [
            Message(id: "u1", role: "user", content: "Hello"),
            Message(id: "a1", role: "assistant", content: "World")
        ]
        var editedMessage: Message?
        var selectedText = ""
        var spokenText = ""
        var extraID = ""
        let clipboard = QuillClipboard()
        let editBinding = Binding<Message?>(
            get: { editedMessage },
            set: { editedMessage = $0 }
        )

        let list = QuillEditableMessageList(
            messages: messages,
            editingMessage: editBinding,
            content: \.content,
            isUserMessage: { $0.role == "user" },
            selectText: { selectedText = $0.content },
            readAloud: { spokenText = $0.content },
            additionalActions: { message in
                [
                    QuillMenuAction(title: "Extra") {
                        extraID = message.id
                    }
                ]
            },
            clipboard: clipboard
        ) { message in
            Text(message.content)
        } overlay: {
            EmptyView()
        }

        #expect(list.scrollToken == AnyHashable("u1|a1|World"))
        #expect(list.interactionAvailability.contains(.selectText))
        #expect(list.interactionAvailability.contains(.readAloud))

        let userActions = list.contextMenuActions(for: messages[0])
        #expect(userActions.map(\.title) == ["Copy", "Select Text", "Read Aloud", "Extra", "Edit"])
        userActions.forEach { $0.perform() }
        #expect(clipboard.string() == "Hello")
        #expect(selectedText == "Hello")
        #expect(spokenText == "Hello")
        #expect(extraID == "u1")
        #expect(editedMessage == messages[0])

        let editingActions = list.contextMenuActions(for: messages[0])
        #expect(editingActions.map(\.title).contains("Unselect"))
        editingActions.first { $0.title == "Unselect" }?.perform()
        #expect(editedMessage == nil)

        let assistantActions = list.contextMenuActions(for: messages[1])
        #expect(!assistantActions.map(\.title).contains("Edit"))

        let platformDefaultList = QuillEditableMessageList(
            messages: messages,
            editingMessage: editBinding,
            content: \.content,
            isUserMessage: { $0.role == "user" },
            interactionAvailability: .platformDefaults,
            selectText: { selectedText = $0.content },
            readAloud: { spokenText = $0.content }
        ) { message in
            Text(message.content)
        } overlay: {
            EmptyView()
        }

        let platformDefaultTitles = platformDefaultList.contextMenuActions(for: messages[0]).map(\.title)
        #if os(iOS) || os(visionOS)
        #expect(platformDefaultTitles.contains("Select Text"))
        #expect(platformDefaultTitles.contains("Read Aloud"))
        #elseif os(Linux)
        #expect(!platformDefaultTitles.contains("Select Text"))
        #expect(platformDefaultTitles.contains("Read Aloud"))
        #else
        #expect(!platformDefaultTitles.contains("Select Text"))
        #expect(!platformDefaultTitles.contains("Read Aloud"))
        #endif

        let noInteractionList = QuillEditableMessageList(
            messages: messages,
            editingMessage: editBinding,
            content: \.content,
            isUserMessage: { $0.role == "user" },
            interactionAvailability: [],
            selectText: { selectedText = $0.content },
            readAloud: { spokenText = $0.content }
        ) { message in
            Text(message.content)
        } overlay: {
            EmptyView()
        }
        let noInteractionTitles = noInteractionList.contextMenuActions(for: messages[0]).map(\.title)
        #expect(!noInteractionTitles.contains("Select Text"))
        #expect(!noInteractionTitles.contains("Read Aloud"))
        #expect(noInteractionTitles.contains("Edit"))
    }

    // MARK: - Backend registry

    @Test("Backend registry exposes SwiftUI GTK and Qt")
    func backendRegistryExposesKnownBackends() {
        let aliases: [(String, QuillBackendIdentifier)] = [
            ("swiftui", .swiftUI),
            ("swift-ui", .swiftUI),
            ("apple", .swiftUI),
            ("native", .swiftUI),
            ("gtk", .gtk),
            ("gtk4", .gtk),
            ("qt", .qt),
            ("qt6", .qt),
            (" Qt6 ", .qt),
            ("\nGTK4\t", .gtk)
        ]
        for (rawValue, expectedBackend) in aliases {
            #expect(QuillBackendIdentifier(environmentValue: rawValue) == expectedBackend)
        }
        #expect(QuillBackendIdentifier(environmentValue: "unknown") == nil)

        #expect(QuillBackendRegistry.requestedBackend(from: [:]) == nil)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": ""]) == nil)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": "   "]) == nil)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": "Qt6"]) == .qt)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": " GTK4 "]) == .gtk)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": "\nNative\t"]) == .swiftUI)
        #expect(QuillBackendRegistry.requestedBackend(from: ["QUILLUI_BACKEND": "unknown"]) == nil)

        #expect(QuillBackendRegistry.backendRequest(from: [:]) == .unspecified)
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": ""]) == .unspecified)
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": "Qt6"]) == .valid(.qt))
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": " GTK4 "]) == .valid(.gtk))
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": "unknown"]) == .invalid(rawValue: "unknown"))
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": " unknown "]).identifier == nil)
        #expect(QuillBackendRegistry.backendRequest(from: ["QUILLUI_BACKEND": "\nunknown\t"]).invalidRawValue == "unknown")

        let backendWindowWidth = "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH"
        let gtkWindowWidth = "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"
        let qtWindowWidth = "QUILLUI_QT_DEFAULT_WINDOW_WIDTH"
        let scopedWindowEnvironment = [
            gtkWindowWidth: "1200",
            qtWindowWidth: "1400"
        ]
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: scopedWindowEnvironment,
                preferred: .gtk
            ) == "1200"
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: scopedWindowEnvironment,
                preferred: .qt
            ) == "1400"
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: scopedWindowEnvironment.merging(["QUILLUI_BACKEND": "gtk"], uniquingKeysWith: { lhs, _ in lhs }),
                preferred: .qt
            ) == "1200"
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: scopedWindowEnvironment.merging([backendWindowWidth: "1600"], uniquingKeysWith: { lhs, _ in lhs }),
                preferred: .qt
            ) == "1600"
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: [gtkWindowWidth: "1200"],
                preferred: .qt
            ) == nil
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: [qtWindowWidth: "1400"],
                preferred: .gtk
            ) == nil
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: [gtkWindowWidth: "1200", "QUILLUI_BACKEND": "qt"],
                preferred: .gtk
            ) == nil
        )
        #expect(
            QuillBackendRegistry.backendScopedEnvironmentValue(
                backendWindowWidth,
                gtkLegacy: gtkWindowWidth,
                qtScoped: qtWindowWidth,
                from: [qtWindowWidth: "1400", "QUILLUI_BACKEND": "gtk"],
                preferred: .qt
            ) == nil
        )

        let identifiers = QuillBackendRegistry.knownBackends.map(\.identifier)
        #expect(identifiers == [.swiftUI, .gtk, .qt])
        #expect(QuillBackendRegistry.runtimeAvailabilities.map(\.selected) == identifiers)
        #expect(
            QuillBackendRegistry.runtimeAvailabilities.map(\.rowValues)
                == QuillBackendRegistry.runtimeAvailabilities.map { availability in
                    [
                        availability.selected.rawValue,
                        availability.runtime.rawValue,
                        availability.mode.rawValue
                    ]
                }
        )

        #if os(Linux)
        #expect(QuillBackendRegistry.platformDefault == .gtk)
        #expect(QuillBackendRegistry.platformRuntimeFallback == .gtk)
        #expect(QuillBackendRegistry.nativeRuntimeBackends == [.gtk])
        #expect(QuillBackendRegistry.nativeRuntimeBackends == QuillLinuxRuntimeHost.supportedBackends)
        #expect(QuillLinuxRuntimeHost.knownHosts == [.gtk4, .qt6])
        #expect(QuillLinuxRuntimeHost.knownDescriptors.map(\.host) == [.gtk4, .qt6])
        #expect(QuillLinuxRuntimeHost.knownDescriptors.map(\.backend) == [.gtk, .qt])
        #expect(QuillLinuxRuntimeHost.knownDescriptors.map(\.displayName) == ["GTK4", "Qt6"])
        #expect(QuillLinuxRuntimeHost.linkedHosts == [.gtk4])
        #expect(QuillLinuxRuntimeHost.linkedDescriptors == QuillLinuxRuntimeHost.descriptors)
        #expect(QuillLinuxRuntimeHost.descriptors.map(\.host) == [.gtk4])
        #expect(QuillLinuxRuntimeHost.descriptors.map(\.backend) == [.gtk])
        #expect(QuillLinuxRuntimeHost.descriptors.map(\.displayName) == ["GTK4"])
        #expect(QuillLinuxRuntimeHost.platformFallbackBackend == .gtk)
        #expect(QuillLinuxRuntimeHost.knownDescriptor(for: .gtk)?.host == .gtk4)
        #expect(QuillLinuxRuntimeHost.knownDescriptor(for: .qt)?.host == .qt6)
        #expect(QuillLinuxRuntimeHost.descriptor(for: .gtk)?.host == .gtk4)
        #expect(QuillLinuxRuntimeHost.descriptor(for: .qt) == nil)
        #expect(QuillLinuxRuntimeHost.supports(.gtk))
        #expect(!QuillLinuxRuntimeHost.supports(.qt))
        #expect(QuillLinuxRuntimeHost(backend: .gtk) != nil)
        #expect(QuillLinuxRuntimeHost(backend: .qt) == nil)
        #expect(QuillBackendRegistry.hasNativeRuntime(for: .gtk))
        #expect(!QuillBackendRegistry.hasNativeRuntime(for: .qt))
        #else
        #expect(QuillBackendRegistry.platformDefault == .swiftUI)
        #expect(QuillBackendRegistry.platformRuntimeFallback == .swiftUI)
        #expect(QuillBackendRegistry.nativeRuntimeBackends == [.swiftUI])
        #expect(QuillBackendRegistry.hasNativeRuntime(for: .swiftUI))
        #expect(!QuillBackendRegistry.hasNativeRuntime(for: .qt))
        #endif

        let qtDescriptor = QuillBackendRegistry.descriptor(for: .qt)
        #expect(qtDescriptor.displayName == "Qt")
        #expect(qtDescriptor.isExperimental == true)
        #expect(!qtDescriptor.hasNativeRuntime)
        #expect(qtDescriptor.runtimeAvailability == QuillBackendRegistry.runtimeAvailability(for: .qt))
        #expect(qtDescriptor.runtimeBackend == QuillBackendRegistry.platformRuntimeFallback)
        #expect(qtDescriptor.runtimeDescriptor.identifier == QuillBackendRegistry.platformRuntimeFallback)
        #expect(qtDescriptor.usesRuntimeFallback)
        #expect(qtDescriptor.runtimeMode == .platformFallback)
        #expect(qtDescriptor.runtimeSummary == QuillBackendRegistry.runtimeSummary(selected: .qt))
        #expect(qtDescriptor.runtimeSummary == qtDescriptor.runtimeAvailability.summary)
        #expect(qtDescriptor.runtimeSummary == QuillBackendRegistry.runtimeSummary(availability: qtDescriptor.runtimeAvailability))
        #expect(qtDescriptor.runtimeSummary.contains("Qt selected"))
        #expect(qtDescriptor.runtimeNotes.contains("canonical Linux app products"))
        #expect(qtDescriptor.runtimeNotes.contains("platform fallback"))
        #expect(!qtDescriptor.runtimeNotes.contains("not linked yet"))

        let gtkDescriptor = QuillBackendRegistry.descriptor(for: .gtk)
        #expect(gtkDescriptor.displayName == "GTK")
        #expect(gtkDescriptor.isExperimental == false)
        #expect(gtkDescriptor.runtimeSummary == QuillBackendRegistry.runtimeSummary(selected: .gtk))
        #expect(gtkDescriptor.runtimeSummary == gtkDescriptor.runtimeAvailability.summary)

        let preferredGtkPlan = QuillBackendRegistry.launchPlan(requested: nil, preferred: .gtk)
        #expect(preferredGtkPlan.request == .unspecified)
        #expect(preferredGtkPlan.selected == .gtk)
        #expect(preferredGtkPlan.selectedDescriptor == gtkDescriptor)
        #expect(preferredGtkPlan.statusMessage == gtkDescriptor.runtimeSummary)

        let environmentQtOverGtkPlan = QuillBackendRegistry.launchPlan(
            environment: ["QUILLUI_BACKEND": "qt"],
            preferred: .gtk
        )
        #expect(environmentQtOverGtkPlan.request == .valid(.qt))
        #expect(environmentQtOverGtkPlan.requested == .qt)
        #expect(environmentQtOverGtkPlan.preferred == .gtk)
        #expect(environmentQtOverGtkPlan.selected == .qt)

        let invalidEnvironmentPlan = QuillBackendRegistry.launchPlan(
            environment: ["QUILLUI_BACKEND": "bogus"],
            preferred: .gtk
        )
        #expect(invalidEnvironmentPlan.request == .invalid(rawValue: "bogus"))
        #expect(invalidEnvironmentPlan.requested == nil)
        #expect(invalidEnvironmentPlan.selected == .gtk)
        #expect(invalidEnvironmentPlan.requestStatusMessage == "Unsupported QUILLUI_BACKEND value \"bogus\"; using GTK.")
        #expect(invalidEnvironmentPlan.statusMessages == [
            "Unsupported QUILLUI_BACKEND value \"bogus\"; using GTK.",
            invalidEnvironmentPlan.statusMessage
        ])
        #expect(invalidEnvironmentPlan.displayMessage == invalidEnvironmentPlan.statusMessages.joined(separator: " "))

        let invalidRequestPlan = QuillBackendRegistry.launchPlan(
            request: .invalid(rawValue: "bogus"),
            preferred: .qt
        )
        #expect(invalidRequestPlan.request == .invalid(rawValue: "bogus"))
        #expect(invalidRequestPlan.requested == nil)
        #expect(invalidRequestPlan.selected == .qt)
        #expect(invalidRequestPlan.requestStatusMessage == "Unsupported QUILLUI_BACKEND value \"bogus\"; using Qt.")

        #if os(Linux)
        #expect(gtkDescriptor.hasNativeRuntime)
        #expect(gtkDescriptor.runtimeBackend == .gtk)
        #expect(gtkDescriptor.runtimeDescriptor == gtkDescriptor)
        #expect(!gtkDescriptor.usesRuntimeFallback)
        #expect(gtkDescriptor.runtimeMode == .native)
        #expect(gtkDescriptor.runtimeSummary == "GTK native renderer selected.")
        #expect(preferredGtkPlan.runtime == .gtk)
        #expect(preferredGtkPlan.runtimeDescriptor.identifier == .gtk)
        #expect(preferredGtkPlan.runtimeMode == .native)
        #else
        #expect(!gtkDescriptor.hasNativeRuntime)
        #expect(gtkDescriptor.runtimeBackend == .swiftUI)
        #expect(gtkDescriptor.runtimeDescriptor.identifier == .swiftUI)
        #expect(gtkDescriptor.usesRuntimeFallback)
        #expect(gtkDescriptor.runtimeMode == .platformFallback)
        #expect(gtkDescriptor.runtimeSummary == "GTK selected, but the native renderer is not available yet; launches currently use SwiftUI.")
        #expect(preferredGtkPlan.runtime == .swiftUI)
        #expect(preferredGtkPlan.runtimeDescriptor.identifier == .swiftUI)
        #expect(preferredGtkPlan.runtimeMode == .platformFallback)
        #endif

        let requestedQtOverGtkPlan = QuillBackendRegistry.launchPlan(requested: .qt, preferred: .gtk)
        #expect(requestedQtOverGtkPlan.request == .valid(.qt))
        #expect(requestedQtOverGtkPlan.requested == .qt)
        #expect(requestedQtOverGtkPlan.preferred == .gtk)
        #expect(requestedQtOverGtkPlan.selected == .qt)
        #expect(requestedQtOverGtkPlan.selectedDescriptor == qtDescriptor)
        #expect(requestedQtOverGtkPlan.runtimeAvailability == qtDescriptor.runtimeAvailability)
        #expect(requestedQtOverGtkPlan.usesRuntimeFallback)
        #expect(
            requestedQtOverGtkPlan.statusMessage
                == QuillBackendRegistry.runtimeSummary(
                    selected: requestedQtOverGtkPlan.selected,
                    runtime: requestedQtOverGtkPlan.runtime
                )
        )

        #if os(Linux)
        #expect(requestedQtOverGtkPlan.runtime == .gtk)
        #expect(requestedQtOverGtkPlan.statusMessage == "Qt selected, but the native renderer is not available yet; launches currently use GTK.")
        #else
        #expect(requestedQtOverGtkPlan.runtime == .swiftUI)
        #expect(requestedQtOverGtkPlan.statusMessage == "Qt selected, but the native renderer is not available yet; launches currently use SwiftUI.")
        #endif

        let requestedQtOverGtkStatus = QuillBackendRegistry.runtimeStatus(requested: .qt, preferred: .gtk)
        #expect(requestedQtOverGtkStatus.identifier == .gtk)
        #expect(requestedQtOverGtkStatus.launchPlan == requestedQtOverGtkPlan)
        #expect(requestedQtOverGtkStatus.selected == .qt)
        #expect(requestedQtOverGtkStatus.runtime == requestedQtOverGtkPlan.runtime)
        #expect(requestedQtOverGtkStatus.usesRuntimeFallback)

        let environmentGtkPlan = QuillBackendRegistry.launchPlan(preferred: .gtk)
        let environmentGtkStatus = QuillBackendRegistry.runtimeStatus(preferred: .gtk)
        #expect(QuillGtkBackend.descriptor == gtkDescriptor)
        #expect(QuillGtkBackend.launchPlan == environmentGtkPlan)
        #expect(QuillGtkBackend.launchPlan.preferred == .gtk)
        #expect(QuillGtkBackend.status == environmentGtkStatus)
        #expect(QuillGtkBackend.status.identifier == .gtk)
        #expect(QuillGtkBackend.status.launchPlan == environmentGtkPlan)
        #expect(QuillGtkBackend.status.requested == environmentGtkPlan.requested)
        #expect(QuillGtkBackend.status.preferred == environmentGtkPlan.preferred)
        #expect(QuillGtkBackend.status.selected == environmentGtkPlan.selected)
        #expect(QuillGtkBackend.status.runtime == environmentGtkPlan.runtime)
        #expect(QuillGtkBackend.status.selectedDescriptor == environmentGtkPlan.selectedDescriptor)
        #expect(QuillGtkBackend.status.runtimeDescriptor == environmentGtkPlan.runtimeDescriptor)
        #expect(QuillGtkBackend.status.runtimeAvailability == environmentGtkPlan.runtimeAvailability)
        #expect(QuillGtkBackend.status.usesRuntimeFallback == environmentGtkPlan.usesRuntimeFallback)
        #expect(QuillGtkBackend.status.hasNativeRuntime == environmentGtkPlan.runtimeAvailability.hasNativeRuntime)
        #expect(QuillGtkBackend.status.mode == environmentGtkPlan.runtimeMode)
        #expect(QuillGtkBackend.status.runtimeMessage == environmentGtkPlan.statusMessage)
        #expect(QuillGtkBackend.status.messages == environmentGtkPlan.statusMessages)
        #expect(QuillGtkBackend.status.message == environmentGtkPlan.statusMessage)

        let invalidGtkStatus = QuillBackendRegistry.runtimeStatus(
            environment: ["QUILLUI_BACKEND": "bogus"],
            preferred: .gtk
        )
        #expect(invalidGtkStatus.identifier == .gtk)
        #expect(invalidGtkStatus.launchPlan == invalidEnvironmentPlan)
        #expect(invalidGtkStatus.requested == invalidEnvironmentPlan.requested)
        #expect(invalidGtkStatus.preferred == invalidEnvironmentPlan.preferred)
        #expect(invalidGtkStatus.selected == invalidEnvironmentPlan.selected)
        #expect(invalidGtkStatus.runtime == invalidEnvironmentPlan.runtime)
        #expect(invalidGtkStatus.runtimeAvailability == invalidEnvironmentPlan.runtimeAvailability)
        #expect(invalidGtkStatus.usesRuntimeFallback == invalidEnvironmentPlan.usesRuntimeFallback)
        #expect(invalidGtkStatus.hasNativeRuntime == invalidEnvironmentPlan.runtimeAvailability.hasNativeRuntime)
        #expect(invalidGtkStatus.runtimeMessage == invalidEnvironmentPlan.statusMessage)
        #expect(invalidGtkStatus.messages == invalidEnvironmentPlan.statusMessages)
        #expect(invalidGtkStatus.message == invalidEnvironmentPlan.displayMessage)

        let preferredQtPlan = QuillBackendRegistry.launchPlan(requested: nil, preferred: .qt)
        #expect(preferredQtPlan.selected == .qt)
        #expect(preferredQtPlan.selectedDescriptor == qtDescriptor)
        #expect(preferredQtPlan.runtimeMode == .platformFallback)
        #expect(preferredQtPlan.runtimeAvailability.mode == .platformFallback)

        #if os(Linux)
        #expect(preferredQtPlan.runtime == .gtk)
        #expect(preferredQtPlan.runtimeDescriptor.identifier == .gtk)
        #expect(QuillBackendRegistry.runtimeAvailabilities == [
            QuillBackendRuntimeAvailability(selected: .swiftUI, runtime: .gtk),
            QuillBackendRuntimeAvailability(selected: .gtk, runtime: .gtk),
            QuillBackendRuntimeAvailability(selected: .qt, runtime: .gtk)
        ])
        #expect(QuillBackendRegistry.runtimeAvailabilities.map(\.tabSeparatedRow) == [
            "swiftui\tgtk\tplatformFallback",
            "gtk\tgtk\tnative",
            "qt\tgtk\tplatformFallback"
        ])
        #else
        #expect(preferredQtPlan.runtime == .swiftUI)
        #expect(preferredQtPlan.runtimeDescriptor.identifier == .swiftUI)
        #expect(QuillBackendRegistry.runtimeAvailabilities == [
            QuillBackendRuntimeAvailability(selected: .swiftUI, runtime: .swiftUI),
            QuillBackendRuntimeAvailability(selected: .gtk, runtime: .swiftUI),
            QuillBackendRuntimeAvailability(selected: .qt, runtime: .swiftUI)
        ])
        #expect(QuillBackendRegistry.runtimeAvailabilities.map(\.tabSeparatedRow) == [
            "swiftui\tswiftui\tnative",
            "gtk\tswiftui\tplatformFallback",
            "qt\tswiftui\tplatformFallback"
        ])
        #endif

        #expect(preferredQtPlan.usesRuntimeFallback)
        #expect(preferredQtPlan.statusMessage.contains("Qt selected"))
        #expect(preferredQtPlan.statusMessage == qtDescriptor.runtimeSummary)
        let environmentQtPlan = QuillBackendRegistry.launchPlan(preferred: .qt)
        let environmentQtStatus = QuillBackendRegistry.runtimeStatus(preferred: .qt)
        #expect(QuillQtBackend.descriptor == qtDescriptor)
        #expect(QuillQtBackend.launchPlan == environmentQtPlan)
        #expect(QuillQtBackend.launchPlan.preferred == .qt)
        #expect(QuillQtBackend.status == environmentQtStatus)
        #expect(QuillQtBackend.status.identifier == .qt)
        #expect(QuillQtBackend.status.launchPlan == environmentQtPlan)
        #expect(QuillQtBackend.status.requested == environmentQtPlan.requested)
        #expect(QuillQtBackend.status.preferred == environmentQtPlan.preferred)
        #expect(QuillQtBackend.status.selected == environmentQtPlan.selected)
        #expect(QuillQtBackend.status.runtime == environmentQtPlan.runtime)
        #expect(QuillQtBackend.status.selectedDescriptor == environmentQtPlan.selectedDescriptor)
        #expect(QuillQtBackend.status.runtimeDescriptor == environmentQtPlan.runtimeDescriptor)
        #expect(QuillQtBackend.status.runtimeAvailability == environmentQtPlan.runtimeAvailability)
        #expect(QuillQtBackend.status.usesRuntimeFallback == environmentQtPlan.usesRuntimeFallback)
        #expect(QuillQtBackend.status.hasNativeRuntime == environmentQtPlan.runtimeAvailability.hasNativeRuntime)
        #expect(QuillQtBackend.status.mode == environmentQtPlan.runtimeMode)
        #expect(QuillQtBackend.status.runtimeMessage == environmentQtPlan.statusMessage)
        #expect(QuillQtBackend.status.messages == environmentQtPlan.statusMessages)
        #expect(QuillQtBackend.status.message == environmentQtPlan.statusMessage)
    }
}
