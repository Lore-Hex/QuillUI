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
    var onNewConversationTap: () -> () = {}
    @State var showSettings = false
    @State var showCompletions = false
    @State var showKeyboardShortcutas = false

    private func onSettingsTap() {
        Task {
            showSettings.toggle()
            Haptics.shared.mediumTap()
        }
    }

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
#if (os(macOS) || os(Linux))
        .focusedSceneValue(\.showSettings, $showSettings)
#endif
        .sheet(isPresented: $showSettings) {
            Settings()
        }
#if (os(macOS) || os(Linux))
        .sheet(isPresented: $showCompletions) {
            CompletionsEditor()
        }
        .sheet(isPresented: $showKeyboardShortcutas) {
            KeyboardShortcutsDemo()
        }
#endif
    }

    private var bottomActions: [QuillSidebarNavigationAction] {
        QuillSidebarNavigationAction.desktopChatUtilities(
            onCompletions: { showCompletions.toggle() },
            onShortcuts: { showKeyboardShortcutas.toggle() },
            onSettings: onSettingsTap
        )
    }
}
