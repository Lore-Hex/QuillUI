import Foundation
import QuillEnchantedData
import QuillEnchantedShared
import QuillUI

@MainActor
public final class EnchantedModel: ObservableObject {
    @Published public var endpoint: String
    @Published public var models: [OllamaModel] = []
    @Published public var selectedModel: String = ""
    @Published public var conversations: [ConversationSummary] = []
    @Published public var selectedConversationID: String?
    @Published public var messages: [ChatMessage] = []
    @Published public var composerText: String = ""
    @Published public var attachmentPath: String = ""
    @Published public var pendingImageAttachments: [PendingImageAttachment] = []
    @Published public var isAttachmentDropTargeted: Bool = false
    @Published public var status: String = EnchantedCopy.readyStatus
    @Published public var isLoading: Bool = false

    private let modelContext: EnchantedModelContext?
    private var generationTask: Task<Void, Never>?
    private var didBoot = false

    public init(endpoint: String = EnchantedCopy.defaultEndpoint, store: SQLiteConversationStore? = nil) {
        self.endpoint = endpoint
        if let store {
            self.modelContext = EnchantedModelContext(persistence: store)
        } else {
            self.modelContext = try? EnchantedModelContext.default()
        }
    }

    public init(endpoint: String = EnchantedCopy.defaultEndpoint, persistence: any ConversationPersistence) {
        self.endpoint = endpoint
        self.modelContext = EnchantedModelContext(persistence: persistence)
    }

    public init(endpoint: String = EnchantedCopy.defaultEndpoint, modelContext: EnchantedModelContext) {
        self.endpoint = endpoint
        self.modelContext = modelContext
    }

    public func boot(endpoint: String? = nil) {
        if let endpoint {
            self.endpoint = endpoint
        }
        guard !didBoot else { return }
        didBoot = true
        reloadConversations()
        if let selectedIndex = EnchantedInitialSelection.selectedConversationIndex(count: conversations.count) {
            selectedConversationID = conversations[selectedIndex].id
            reloadMessages()
        } else if selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
            reloadMessages()
        }
        Task {
            await refreshModels()
        }
    }

    public func configureEndpoint(_ endpoint: String) {
        guard self.endpoint != endpoint else { return }
        self.endpoint = endpoint
        Task {
            await refreshModels()
        }
    }

    public func refreshModels() async {
        do {
            status = EnchantedCopy.checkingOllamaStatus
            let client = try OllamaClient(baseURL: endpoint)
            let fetched = try await client.fetchModels()
            models = fetched
            if selectedModel.isEmpty || !fetched.contains(where: { $0.name == selectedModel }) {
                selectedModel = fetched.first?.name ?? ""
            }
            status = fetched.isEmpty ? EnchantedCopy.noOllamaModelsStatus : EnchantedCopy.connectedStatus
        } catch {
            models = []
            status = EnchantedCopy.startOllamaStatus
        }
    }

    public func newConversation() {
        do {
            let created = try requireModelContext().insert(ConversationDraft(title: EnchantedCopy.newConversationTitle))
            selectedConversationID = created.id
            reloadConversations()
            messages = []
            status = EnchantedCopy.newConversationTitle
        } catch {
            status = EnchantedCopy.couldNotCreateConversationStatus(error.localizedDescription)
        }
    }

    public func select(_ conversation: ConversationSummary) {
        selectedConversationID = conversation.id
        reloadMessages()
    }

    public func deleteSelectedConversation() {
        guard let selectedConversationID else { return }
        deleteConversation(id: selectedConversationID)
    }

    public func delete(_ conversation: ConversationSummary) {
        deleteConversation(id: conversation.id)
    }

    public func selectModel(named modelName: String?) {
        selectedModel = modelName ?? ""
    }

    public func startSend(
        _ prompt: String,
        attachments: [PendingImageAttachment] = [],
        trimmingMessageID: String? = nil
    ) {
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            await self?.send(prompt, attachments: attachments, trimmingMessageID: trimmingMessageID)
        }
    }

    public func stopGenerating() {
        generationTask?.cancel()
        if isLoading {
            status = EnchantedCopy.stoppingStatus
        } else {
            status = EnchantedCopy.readyStatus
        }
    }

    @discardableResult
    public func trimConversation(from messageID: String) -> Bool {
        do {
            let modelContext = try requireModelContext()
            guard let selectedConversationID else { return false }
            let originalCount = messages.count
            try modelContext.deleteMessages(in: selectedConversationID, from: messageID)
            reloadConversations()
            reloadMessages()
            guard messages.count < originalCount else {
                status = EnchantedCopy.messageUnavailableStatus
                return false
            }
            status = EnchantedCopy.conversationTrimmedStatus
            return true
        } catch {
            status = EnchantedCopy.couldNotTrimConversationStatus(error.localizedDescription)
            return false
        }
    }

    private func deleteConversation(id conversationID: String) {
        do {
            try requireModelContext().deleteConversation(id: conversationID)
            reloadConversations()
            if selectedConversationID == conversationID {
                selectedConversationID = conversations.first?.id
                reloadMessages()
            }
        } catch {
            status = EnchantedCopy.couldNotDeleteConversationStatus(error.localizedDescription)
        }
    }

    public func deleteAllConversations() {
        do {
            try requireModelContext().deleteAllConversations()
            conversations = []
            selectedConversationID = nil
            messages = []
            status = EnchantedCopy.historyClearedStatus
        } catch {
            status = EnchantedCopy.couldNotClearHistoryStatus(error.localizedDescription)
        }
    }

    public func sendComposerMessage() async {
        let attachments = pendingImageAttachments
        guard let prompt = composerText.quillTrimmedNonEmpty ?? (attachments.isEmpty ? nil : PendingImageAttachment.defaultPrompt(for: attachments)) else {
            return
        }
        composerText = ""
        attachmentPath = ""
        pendingImageAttachments = []
        await send(prompt, attachments: attachments)
    }

    public func startComposerMessage() {
        let attachments = pendingImageAttachments
        guard let prompt = composerText.quillTrimmedNonEmpty ?? (attachments.isEmpty ? nil : PendingImageAttachment.defaultPrompt(for: attachments)) else {
            return
        }
        composerText = ""
        attachmentPath = ""
        pendingImageAttachments = []
        startSend(prompt, attachments: attachments)
    }

    @discardableResult
    public func addAttachmentPath() -> Bool {
        let urls = PendingImageAttachment.fileURLs(from: attachmentPath)
        guard !urls.isEmpty else { return false }

        let accepted = addAttachments(urls: urls)
        if accepted {
            attachmentPath = ""
        }
        return accepted
    }

    @discardableResult
    public func addAttachments(urls: [URL]) -> Bool {
        var accepted = false
        var lastError: String?

        for url in urls {
            do {
                let attachment = try PendingImageAttachment(fileURL: url)
                if pendingImageAttachments.contains(where: { $0.fileURL == attachment.fileURL }) {
                    continue
                }
                pendingImageAttachments.append(attachment)
                accepted = true
            } catch {
                lastError = error.localizedDescription
            }
        }

        if accepted {
            status = EnchantedCopy.imageReadyStatus(count: pendingImageAttachments.count)
        } else if let lastError {
            status = lastError
        }

        return accepted
    }

    public func removeAttachment(id: String) {
        pendingImageAttachments.removeAll { $0.id == id }
        status = pendingImageAttachments.isEmpty ? EnchantedCopy.readyStatus : EnchantedCopy.imageReadyStatus(count: pendingImageAttachments.count)
    }

    public func clearAttachments() {
        pendingImageAttachments = []
        attachmentPath = ""
        status = EnchantedCopy.attachmentsClearedStatus
    }

    public func send(
        _ prompt: String,
        attachments: [PendingImageAttachment] = [],
        trimmingMessageID: String? = nil
    ) async {
        var assistantDraftID: String?
        do {
            let encodedImages = try attachments.map { try $0.base64EncodedContent() }
            let modelContext = try requireModelContext()
            if let trimmingMessageID, let selectedConversationID {
                try modelContext.deleteMessages(in: selectedConversationID, from: trimmingMessageID)
                reloadConversations()
                reloadMessages()
            }
            let conversationID = try ensureConversation(for: prompt)
            let displayContent = PendingImageAttachment.displayContent(prompt: prompt, attachments: attachments)
            let userMessage = ChatMessage(conversationID: conversationID, role: .user, content: displayContent)
            try modelContext.insert(userMessage)
            reloadConversations()
            reloadMessages()

            isLoading = true
            status = EnchantedCopy.openingStreamStatus
            let currentEndpoint = endpoint
            let currentModel = selectedModel
            let currentMessages = messages
            let client = try OllamaClient(baseURL: currentEndpoint)

            let assistantID = UUID().uuidString
            assistantDraftID = assistantID
            var streamedReply = ""
            messages.append(
                ChatMessage(
                    id: assistantID,
                    conversationID: conversationID,
                    role: .assistant,
                    content: ""
                )
            )

            let stream = try client.streamChat(
                model: currentModel,
                messages: currentMessages,
                imagesForLastUserMessage: encodedImages
            )
            for try await chunk in stream {
                try Task.checkCancellation()
                streamedReply += chunk
                updateAssistantDraft(id: assistantID, content: streamedReply)
                status = EnchantedCopy.streamingResponseStatus
            }
            try Task.checkCancellation()

            let finalContent = streamedReply.quillTrimmedNonEmpty ?? EnchantedCopy.emptyOllamaResponse
            updateAssistantDraft(id: assistantID, content: finalContent)
            try modelContext.insert(ChatMessage(
                id: assistantID,
                conversationID: conversationID,
                role: .assistant,
                content: finalContent
            ))
            reloadConversations()
            reloadMessages()
            status = EnchantedCopy.readyStatus
        } catch is CancellationError {
            if let assistantDraftID {
                messages.removeAll { $0.id == assistantDraftID && $0.content.isEmpty }
            }
            status = EnchantedCopy.stoppedStatus
        } catch {
            status = error.localizedDescription
        }
        generationTask = nil
        isLoading = false
    }

    private func updateAssistantDraft(id: String, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }

    private func reloadConversations() {
        do {
            conversations = try requireModelContext().fetchConversations()
        } catch {
            status = EnchantedCopy.couldNotLoadConversationsStatus(error.localizedDescription)
        }
    }

    private func reloadMessages() {
        guard let selectedConversationID else {
            messages = []
            return
        }
        do {
            messages = try requireModelContext().fetchMessages(for: selectedConversationID)
        } catch {
            status = EnchantedCopy.couldNotLoadMessagesStatus(error.localizedDescription)
        }
    }

    private func ensureConversation(for prompt: String) throws -> String {
        if let selectedConversationID {
            let currentMessages = try requireModelContext().fetchMessages(for: selectedConversationID)
            if currentMessages.isEmpty {
                try requireModelContext().updateConversationTitle(id: selectedConversationID, title: prompt.quillTitle())
            }
            return selectedConversationID
        }

        let created = try requireModelContext().insert(ConversationDraft(title: prompt.quillTitle()))
        selectedConversationID = created.id
        return created.id
    }

    private func requireModelContext() throws -> EnchantedModelContext {
        if let modelContext { return modelContext }
        throw ConversationStoreError.openFailed(EnchantedCopy.conversationPersistenceUnavailableStatus)
    }
}
