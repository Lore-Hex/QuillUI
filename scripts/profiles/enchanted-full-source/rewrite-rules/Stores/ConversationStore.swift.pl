s~    private func handleComplete\(\) \{
        guard let lastMesasge = messages\.last else \{ return \}
        lastMesasge\.error = false~    private func handleComplete() {
        guard let lastMesasge = messages.last else { return }
        if !currentMessageBuffer.isEmpty {
            lastMesasge.content.append(currentMessageBuffer)
            currentMessageBuffer = ""
        }
        lastMesasge.error = false~g;

s~        let assistantMessage = MessageSD\(content: "", role: "assistant"\)
        assistantMessage\.conversation = conversation
        
        conversationState = \.loading~        let assistantMessage = MessageSD(content: "", role: "assistant")
        assistantMessage.conversation = conversation

        var pendingMessages = conversation.messages.sorted{\$0.createdAt < \$1.createdAt}
        if !pendingMessages.contains(where: { \$0.id == userMessage.id }) {
            pendingMessages.append(userMessage)
        }
        if !pendingMessages.contains(where: { \$0.id == assistantMessage.id }) {
            pendingMessages.append(assistantMessage)
        }
        self.messages = pendingMessages.sorted{\$0.createdAt < \$1.createdAt}
        self.selectedConversation = conversation
        
        conversationState = .loading~g;

s~            try await reloadConversation\(conversation\)
            try\? await loadConversations\(\)~            Task { try? await self.loadConversations() }~g;
