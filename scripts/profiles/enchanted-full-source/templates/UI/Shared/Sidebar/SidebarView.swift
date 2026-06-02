//
//  SidebarView.swift
//  Enchanted
//

import SwiftUI

struct SidebarView: View {
    @Environment(\.openWindow) var openWindow
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
        VStack(spacing: 0) {
            // Primary "New chat" action — matches the macOS Enchanted sidebar
            // (a full-width accent-blue button at the sidebar top, above the
            // conversation list). Color is the Enchanted accent #4285F4.
            Button(action: onNewConversationTap) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("New chat")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(Color(red: 0.259, green: 0.522, blue: 0.957))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)

            ConversationHistoryList(
                selectedConversation: selectedConversation,
                conversations: conversations,
                onTap: onConversationTap,
                onDelete: onConversationDelete,
                onDeleteDailyConversations: onDeleteDailyConversations
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 18) {
#if (os(macOS) || os(Linux))
                SidebarButton(title: "Completions", image: "textformat.abc", onClick: {showCompletions.toggle()})
                SidebarButton(title: "Shortcuts", image: "keyboard.fill", onClick: {showKeyboardShortcutas.toggle()})
#endif
                SidebarButton(title: "Settings", image: "gearshape.fill", onClick: onSettingsTap)
            }
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 74)
        .padding(.bottom, 18)
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
}
