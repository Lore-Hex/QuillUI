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

        self.messages = conversation.messages.sorted{\$0.createdAt < \$1.createdAt}
        self.selectedConversation = conversation
        
        conversationState = .loading~g;
