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
        QuillDesktopChatConversationSidebar(
            conversations: conversations,
            selectedID: selectedConversation?.id.uuidString,
            settingsFocusedValue: \.showSettings,
            id: { $0.id.uuidString },
            title: { $0.name },
            updatedAt: { $0.updatedAt },
            dateTitle: { $0.daysAgoString() },
            onSettings: { Task { Haptics.shared.mediumTap() } },
            onSelect: onConversationTap,
            onDelete: onConversationDelete,
            onDeleteDay: onDeleteDailyConversations
        ) {
            Settings()
        } completions: {
            CompletionsEditor()
        } shortcuts: {
            KeyboardShortcutsDemo()
        }
    }
}
