import Foundation
import QuillEnchantedShared
import QuillUI
#if canImport(SwiftUI)
import SwiftUI
#endif

@MainActor
public struct EnchantedRootView: View {
    @StateObject private var model = EnchantedModel()
    @AppStorage("quill.enchanted.ollamaEndpoint") private var endpoint = "http://localhost:11434"

    public init() {}

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 300)
                    .background(QuillColors.sidebar)

                Divider()

                chatSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(QuillColors.canvas)
            }
            .frame(minWidth: 980, minHeight: 680)
            .onAppear {
                model.boot(endpoint: endpoint)
            }
            .onChange(of: endpoint) { _, value in
                model.configureEndpoint(value)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enchanted")
                    .font(.largeTitle)
                    .foregroundColor(QuillColors.ink)
                Text("QuillUI Linux preview")
                    .font(.caption)
                    .foregroundColor(QuillColors.muted)
            }

            Button(action: model.newConversation) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                    Text("New chat")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(QuillColors.primary)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                Text("Ollama endpoint")
                    .font(.caption)
                    .foregroundColor(QuillColors.muted)
                TextField("http://localhost:11434", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Model")
                    .font(.caption)
                    .foregroundColor(QuillColors.muted)
                if model.models.isEmpty {
                    Text("No models detected")
                        .font(.caption)
                        .foregroundColor(QuillColors.warning)
                } else {
                    Picker("Model", selection: modelSelection) {
                        ForEach(model.models) { ollamaModel in
                            Text(ollamaModel.name).tag(ollamaModel.name)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                statusDot
                Text(model.status)
                    .font(.caption)
                    .foregroundColor(QuillColors.muted)
                    .frame(width: 240, alignment: .leading)
            }

            Divider()

            Text("Conversations")
                .font(.headline)
                .foregroundColor(QuillColors.ink)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.conversations.isEmpty {
                        emptyHistory
                    } else {
                        ForEach(model.conversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: conversation.id == model.selectedConversationID
                            ) {
                                model.select(conversation)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Delete chat") {
                    model.deleteSelectedConversation()
                }
                .disabled(model.selectedConversationID == nil)

                Button("Clear all") {
                    model.deleteAllConversations()
                }
                .disabled(model.conversations.isEmpty)
            }
            .font(.caption)
        }
        .padding(18)
    }

    private var chatSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            chatHeader
                .padding(18)
                .background(QuillColors.header)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if model.messages.isEmpty {
                        EmptyConversationView { prompt in
                            model.startSend(prompt)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message)
                        }
                    }

                    if model.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(model.status)
                                .foregroundColor(QuillColors.muted)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            composer
                .padding(18)
                .background(QuillColors.header)
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentTitle)
                    .font(.title2)
                    .foregroundColor(QuillColors.ink)
                    .frame(width: 560, alignment: .leading)
                Text(model.selectedModel.isEmpty ? "Choose a local model to begin" : "Using \(model.selectedModel)")
                    .font(.caption)
                    .foregroundColor(QuillColors.muted)
                    .frame(width: 560, alignment: .leading)
            }

            Spacer()

            Button("Refresh models") {
                let model = model
                Task {
                    await model.refreshModels()
                }
            }
            .disabled(model.isLoading)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isAttachmentDropTargeted {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                    Text("Drop image files to attach")
                }
                .font(.caption)
                .foregroundColor(QuillColors.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QuillColors.dropTarget)
                .cornerRadius(8)
            }

            if !model.pendingImageAttachments.isEmpty {
                attachmentTray
            }

            HStack(spacing: 8) {
                TextField("Image path or drop files here", text: attachmentPath)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    model.addAttachmentPath()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                        Text("Attach")
                    }
                }
                .disabled(model.attachmentPath.quillTrimmedNonEmpty == nil)

                Button("Clear") {
                    model.clearAttachments()
                }
                .disabled(model.pendingImageAttachments.isEmpty && model.attachmentPath.quillTrimmedNonEmpty == nil)
            }

            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: composerText)
                    .frame(minHeight: 74, maxHeight: 120)
                    .background(.white)
                    .cornerRadius(8)

                Button(action: {
                    if model.isLoading {
                        model.stopGenerating()
                    } else {
                        model.startComposerMessage()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: model.isLoading ? "square.fill" : "arrow.forward.circle.fill")
                        Text(model.isLoading ? "Stop" : "Send")
                    }
                    .padding(12)
                    .background(model.isLoading ? QuillColors.warning : QuillColors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addAttachments(urls: urls)
        } isTargeted: { isTargeted in
            model.isAttachmentDropTargeted = isTargeted
        }
    }

    private var currentTitle: String {
        model.conversations.first(where: { $0.id == model.selectedConversationID })?.title ?? "New conversation"
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { model.selectedModel },
            set: { model.selectedModel = $0 }
        )
    }

    private var composerText: Binding<String> {
        Binding(
            get: { model.composerText },
            set: { model.composerText = $0 }
        )
    }

    private var attachmentPath: Binding<String> {
        Binding(
            get: { model.attachmentPath },
            set: { model.attachmentPath = $0 }
        )
    }

    private var sendDisabled: Bool {
        if model.isLoading { return false }
        return model.composerText.quillTrimmedNonEmpty == nil && model.pendingImageAttachments.isEmpty
    }

    private var attachmentTray: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Attachments")
                .font(.caption)
                .foregroundColor(QuillColors.muted)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.pendingImageAttachments) { attachment in
                        AttachmentChip(attachment: attachment) {
                            model.removeAttachment(id: attachment.id)
                        }
                    }
                }
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(model.models.isEmpty ? QuillColors.warning : QuillColors.success)
            .frame(width: 9, height: 9)
    }

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No saved chats yet")
                .font(.subheadline)
                .foregroundColor(QuillColors.ink)
            Text("Start a chat and it will be saved locally.")
                .font(.caption)
                .foregroundColor(QuillColors.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuillColors.card)
        .cornerRadius(8)
    }
}

private struct ConversationRow: View {
    var conversation: ConversationSummary
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(conversation.title)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? .white : QuillColors.ink)
                    .lineLimit(1)
                if !conversation.lastMessage.isEmpty {
                    Text(conversation.lastMessage)
                        .font(.caption)
                        .foregroundColor(isSelected ? QuillColors.selectedMuted : QuillColors.muted)
                        .lineLimit(2)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? QuillColors.primary : QuillColors.card)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyConversationView: View {
    var send: (String) -> Void

    private let prompts = EnchantedPromptCatalog.emptyConversationTitles

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ask your local model")
                    .font(.title)
                    .foregroundColor(QuillColors.ink)
                Text("This is the first QuillUI Enchanted checkpoint: local Swift UI, Ollama chat, and QuillData history.")
                    .foregroundColor(QuillColors.muted)
                    .frame(width: 620, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(prompts, id: \.self) { prompt in
                    Button(action: { send(prompt) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill")
                            Text(prompt)
                                .frame(width: 540, alignment: .leading)
                        }
                        .padding(12)
                        .frame(width: 620, alignment: .leading)
                        .background(QuillColors.card)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 620, alignment: .leading)
                }
            }
        }
        .padding(26)
        .frame(maxWidth: 680, alignment: .leading)
    }
}

private struct MessageBubble: View {
    var message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(labelColor)
                if message.role == .user {
                    Text(message.content)
                        .foregroundColor(textColor)
                        .lineSpacing(3)
                } else {
                    MarkdownMessageView(markdown: message.content, foregroundColor: textColor)
                }
            }
            .padding(13)
            .frame(maxWidth: 680, alignment: .leading)
            .background(backgroundColor)
            .cornerRadius(10)

            if message.role != .user {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var label: String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Enchanted"
        case .system:
            return "System"
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return QuillColors.primary
        case .assistant:
            return QuillColors.card
        case .system:
            return QuillColors.system
        }
    }

    private var labelColor: Color {
        message.role == .user ? QuillColors.selectedMuted : QuillColors.muted
    }

    private var textColor: Color {
        message.role == .user ? .white : QuillColors.ink
    }
}

enum QuillColors {
    static var canvas: Color { Color(hex: "#F6F7F2") }
    static var sidebar: Color { Color(hex: "#EEF1EA") }
    static var header: Color { Color(hex: "#FBFCF7") }
    static var card: Color { Color(hex: "#FFFFFF") }
    static var primary: Color { Color(hex: "#315B7D") }
    static var success: Color { Color(hex: "#2F8F64") }
    static var warning: Color { Color(hex: "#B86A31") }
    static var system: Color { Color(hex: "#E8EDF3") }
    static var ink: Color { Color(hex: "#172026") }
    static var muted: Color { Color(hex: "#6C747C") }
    static var selectedMuted: Color { Color(hex: "#DDEBFA") }
    static var quoteRule: Color { Color(hex: "#8AA5B7") }
    static var codeBlock: Color { Color(hex: "#EEF3F4") }
    static var dropTarget: Color { Color(hex: "#E1F0EA") }
}

private struct AttachmentChip: View {
    var attachment: PendingImageAttachment
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundColor(QuillColors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.caption)
                    .foregroundColor(QuillColors.ink)
                    .lineLimit(1)
                Text(attachment.formattedByteCount)
                    .font(.caption2)
                    .foregroundColor(QuillColors.muted)
            }

            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(QuillColors.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(QuillColors.card)
        .cornerRadius(8)
    }
}
