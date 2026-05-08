s/final class ConversationStore: Sendable/final class ConversationStore: \@unchecked Sendable/g;
s/(\n[ \t]*let assistantMessage = MessageSD\(content: "", role: "assistant"\))/\n        let messageHistoryForRequest = messageHistory$1/g;
s/messages: messageHistory/messages: messageHistoryForRequest/g;
s/self\?\.handleComplete\(\)/Task { \@MainActor in self?.handleComplete() }/g;
s/self\?\.handleError\(error\.localizedDescription\)/Task { \@MainActor in self?.handleError(error.localizedDescription) }/g;
s/self\?\.handleReceive\(response\)/Task { \@MainActor in self?.handleReceive(response) }/g;
