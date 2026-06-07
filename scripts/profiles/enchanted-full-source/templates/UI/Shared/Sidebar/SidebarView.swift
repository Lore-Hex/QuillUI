//
//  SidebarView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct SidebarView: View {
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var onConversationTap: (_ conversation: ConversationSD) -> ()
    var onConversationDelete: (_ conversation: ConversationSD) -> ()
    var onDeleteDailyConversations: (_ date: Date) -> ()
    @State var showSettings = false
    @State var showCompletions = false
    @State var showKeyboardShortcuts = false

    var body: some View {
        QuillDesktopSidebar(bottomActions: bottomActions) {
            ConversationHistoryList(
                selectedConversation: selectedConversation,
                conversations: conversations,
                onTap: onConversationTap,
                onDelete: onConversationDelete,
                onDeleteDailyConversations: onDeleteDailyConversations
            )
        }
        .quillDesktopChatUtilitySheets(
            showSettings: $showSettings,
            showCompletions: $showCompletions,
            showShortcuts: $showKeyboardShortcuts,
            settingsFocusedValue: \.showSettings
        ) {
            Settings()
        } completions: {
            CompletionsEditor()
        } shortcuts: {
            KeyboardShortcutsDemo()
        }
    }

    private var bottomActions: [QuillSidebarNavigationAction] {
        QuillSidebarNavigationAction.desktopChatUtilityToggles(
            showCompletions: $showCompletions,
            showShortcuts: $showKeyboardShortcuts,
            showSettings: $showSettings,
            onSettings: { Task { Haptics.shared.mediumTap() } }
        )
    }
}
