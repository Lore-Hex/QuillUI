s/final class ConversationStore: Sendable/final class ConversationStore: \@unchecked Sendable/g;
s/(\n[ \t]*let assistantMessage = MessageSD\(content: "", role: "assistant"\))/\n        let messageHistoryForRequest = messageHistory$1/g;
s/messages: messageHistory/messages: messageHistoryForRequest/g;
s/self\?\.handleComplete\(\)/Task { \@MainActor in self?.handleComplete() }/g;
s/self\?\.handleError\(error\.localizedDescription\)/Task { \@MainActor in self?.handleError(error.localizedDescription) }/g;
s/self\?\.handleReceive\(response\)/Task { \@MainActor in self?.handleReceive(response) }/g;

# QuillData (the Linux SwiftData replacement) does not maintain the in-memory
# @Relationship inverse: `userMessage.conversation = conversation` does NOT append
# userMessage to `conversation.messages`. The genuine sendPrompt builds the Ollama
# request's messageHistory from `conversation.messages` BEFORE the new message is
# persisted, relying on SwiftData's instant inverse — so on Linux the request went
# out with messages:[]. Include the freshly-built userMessage explicitly (correct
# for new and continuing conversations; the createdAt sort keeps it last).
s/var messageHistory = conversation\.messages\b/var messageHistory = (conversation.messages + [userMessage])/g;
