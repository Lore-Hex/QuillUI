//
//  InputFields_macOS.swift
//  Enchanted
//

#if os(macOS) || os(Linux) || os(visionOS)
import Foundation
import SwiftUI
import QuillShims

struct InputFieldsView: View {
    @Binding var message: String
    var conversationState: ConversationState
    var onStopGenerateTap: () -> Void
    var selectedModel: LanguageModelSD?
    var onSendMessageTap: (_ prompt: String, _ model: LanguageModelSD, _ image: Image?, _ trimmingMessageId: String?) -> Void
    @Binding var editMessage: MessageSD?
    @State var isRecording = false
    @State private var selectedImage: Image?

    private var canSend: Bool {
        selectedModel != nil && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        guard let selectedModel, canSend else { return }
        onSendMessageTap(
            message,
            selectedModel,
            selectedImage,
            editMessage?.id.uuidString
        )
        isRecording = false
        editMessage = nil
        selectedImage = nil
        message = ""
    }

    var body: some View {
        HStack(spacing: 12) {
            imagePreview
            composerField
            actionButtons
        }
        .transition(.slide)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(
                    Color.gray2Custom,
                    style: StrokeStyle(lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let selectedImage {
            RemovableImage(
                image: selectedImage,
                onClick: { self.selectedImage = nil },
                height: 70
            )
            .padding(5)
        }
    }

    private var composerField: some View {
        TextField("Message", text: $message, axis: .vertical)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .clipped()
            .textFieldStyle(.plain)
            .padding(.trailing, 4)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            RecordingView(isRecording: $isRecording) { transcription in
                self.message = transcription
            }
            if selectedModel?.supportsImages ?? false {
                SimpleFloatingButton(systemImage: "photo.fill", onClick: {})
            }
            if conversationState == .loading {
                SimpleFloatingButton(systemImage: "square.fill", onClick: onStopGenerateTap)
            } else if canSend {
                SimpleFloatingButton(systemImage: "paperplane.fill", onClick: sendMessage)
            }
        }
    }
}
#endif
