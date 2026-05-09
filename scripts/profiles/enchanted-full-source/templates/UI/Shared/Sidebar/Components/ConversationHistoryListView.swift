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
        QuillConversationHistoryList(
            items: conversations.map {
                QuillConversationHistoryItem(
                    id: $0.id.uuidString,
                    title: $0.name,
                    updatedAt: $0.updatedAt
                )
            },
            selectedID: selectedConversation?.id.uuidString,
            onSelect: { item in
                guard let conversation = conversations.first(where: { $0.id.uuidString == item.id }) else { return }
                onTap(conversation)
            }
        )
    }
}
