//
//  ConversationHistoryList.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct ConversationHistoryList: View {
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var onTap: (_ conversation: ConversationSD) -> ()
    var onDelete: (_ conversation: ConversationSD) -> ()
    var onDeleteDailyConversations: (_ date: Date) -> ()

    var body: some View {
        QuillDateGroupedConversationHistoryList(
            items: conversations,
            selectedID: selectedConversation?.id.uuidString,
            id: { $0.id.uuidString },
            title: { $0.name },
            updatedAt: { $0.updatedAt },
            dateTitle: { $0.daysAgoString() },
            onSelect: onTap,
            onDelete: onDelete,
            onDeleteDay: onDeleteDailyConversations
        )
    }
}
