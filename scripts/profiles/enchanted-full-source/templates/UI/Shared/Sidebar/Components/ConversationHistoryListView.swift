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
            items: historyItems,
            selectedID: selectedConversation?.id.uuidString,
            dateTitle: { $0.daysAgoString() },
            onSelect: { item in
                if let conversation = conversation(for: item) {
                    onTap(conversation)
                }
            },
            onDelete: { item in
                if let conversation = conversation(for: item) {
                    onDelete(conversation)
                }
            },
            onDeleteDay: onDeleteDailyConversations
        )
    }

    private var historyItems: [QuillConversationHistoryItem] {
        conversations.map { conversation in
            QuillConversationHistoryItem(
                id: conversation.id.uuidString,
                title: conversation.name,
                updatedAt: conversation.updatedAt
            )
        }
    }

    private func conversation(for item: QuillConversationHistoryItem) -> ConversationSD? {
        conversations.first { $0.id.uuidString == item.id }
    }
}
