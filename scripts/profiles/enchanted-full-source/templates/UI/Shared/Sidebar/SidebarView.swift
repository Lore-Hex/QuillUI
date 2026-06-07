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

    var body: some View {
        QuillDesktopChatUtilitySidebar(
            settingsFocusedValue: \.showSettings,
            onSettings: { Task { Haptics.shared.mediumTap() } }
        ) {
            ConversationHistoryList(
                selectedConversation: selectedConversation,
                conversations: conversations,
                onTap: onConversationTap,
                onDelete: onConversationDelete,
                onDeleteDailyConversations: onDeleteDailyConversations
            )
        } settings: {
            Settings()
        } completions: {
            CompletionsEditor()
        } shortcuts: {
            KeyboardShortcutsDemo()
        }
    }
}
