//
//  InputFields_macOS.swift
//  Enchanted
//

#if os(macOS) || os(Linux) || os(visionOS)
import SwiftUI
import QuillUI
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
    @State private var fileDropActive = false
    @State private var fileSelectingActive = false
    @FocusState private var isFocusedInput: Bool

    private func sendMessage() {
        guard let selectedModel else { return }

        onSendMessageTap(
            message,
            selectedModel,
            selectedImage,
            editMessage?.id.uuidString
        )

        withAnimation {
            isRecording = false
            isFocusedInput = false
            editMessage = nil
            selectedImage = nil
            message = ""
        }
    }

    private func updateSelectedImage(_ image: Image) {
        selectedImage = image
    }

#if os(macOS) || os(Linux)
    var hotkeys: [HotkeyCombination] {
        [
            HotkeyCombination(keyBase: [.command], key: .kVK_ANSI_V) {
                if let nsImage = Clipboard.shared.getImage() {
                    updateSelectedImage(Image(nsImage: nsImage))
                }
            }
        ]
    }
#endif

    @ViewBuilder
    private var selectedImagePreview: some View {
        if let image = selectedImage {
            RemovableImage(
                image: image,
                onClick: { selectedImage = nil },
                height: 70
            )
            .padding(5)
        }
    }

    private var messageField: some View {
        TextField("Message", text: $message, axis: .vertical)
            .focused($isFocusedInput)
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, minHeight: 56)
            .clipped()
            .textFieldStyle(.plain)
#if os(macOS) || os(Linux)
            .onSubmit {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    message += "\n"
                } else {
                    sendMessage()
                }
            }
#endif
            .allowsHitTesting(!fileDropActive)
#if os(macOS) || os(Linux)
            .addCustomHotkeys(hotkeys)
#endif
            .padding(.trailing, 80)
    }

    private var recordingButton: some View {
        RecordingView(isRecording: $isRecording.animation()) { transcription in
            withAnimation(.easeIn(duration: 0.3)) {
                self.message = transcription
            }
        }
    }

    private var imageButton: some View {
        SimpleFloatingButton(systemImage: "photo.fill", onClick: { fileSelectingActive.toggle() })
            .showIf(selectedModel?.supportsImages ?? false)
            .fileImporter(
                isPresented: $fileSelectingActive,
                allowedContentTypes: [.png, .jpeg, .tiff],
                onCompletion: handleImportedImage
            )
    }

    @ViewBuilder
    private var sendOrStopButton: some View {
        switch conversationState {
        case .loading:
            SimpleFloatingButton(systemImage: "square.fill", onClick: onStopGenerateTap)
        default:
            SimpleFloatingButton(systemImage: "paperplane.fill", onClick: sendMessage)
                .showIf(!message.isEmpty)
        }
    }

    private var actionButtons: some View {
        HStack {
            recordingButton
            imageButton
            sendOrStopButton
        }
    }

    private var inputContent: some View {
        HStack(spacing: 20) {
            selectedImagePreview

            ZStack(alignment: .trailing) {
                messageField
                actionButtons
            }
        }
    }

    var body: some View {
        inputContent
            .transition(.slide)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .overlay(border)
            .overlay(dropOverlay)
            .animation(.default, value: fileDropActive)
            .onDrop(of: [.image], isTargeted: $fileDropActive.animation(), perform: handleDrop)
            .contentShape(Rectangle())
            .onTapGesture {
                isFocusedInput = true
            }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 28)
            .strokeBorder(
                Color.gray2Custom,
                style: StrokeStyle(lineWidth: 1)
            )
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if fileDropActive {
            DragAndDrop(cornerRadius: 10)
        }
    }

    private func handleImportedImage(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            if let imageData = try? Data(contentsOf: url) {
                selectedImage = Image(data: imageData)
            }
            url.stopAccessingSecurityScopedResource()
        case .failure(let error):
            print(error)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(for: .image) { data, error in
            if error == nil, let data {
                selectedImage = Image(data: data)
            }
        }
        return true
    }
}
#endif
