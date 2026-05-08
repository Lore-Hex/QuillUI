s/await Haptics\.shared\.mediumTap\(\)/Haptics.shared.mediumTap()/g;
s/await languageModelStore\.setModel\(/languageModelStore.setModel(/g;
s/let messages = await ConversationStore\.shared\.messages/let messages = ConversationStore.shared.messages/g;
s/await Accessibility\.shared\.showAccessibilityInstructionsWindow\(\)/Accessibility.shared.showAccessibilityInstructionsWindow()/g;
s/_ = try await loadCompletions/_ = await loadCompletions/g;
s/try\? await conversationStore\.deleteAllConversations\(\)/conversationStore.deleteAllConversations()/g;
