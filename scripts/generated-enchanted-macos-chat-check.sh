#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  cat >&2 <<'MSG'
The generated Enchanted macOS-chat check requires Linux because the
SwiftUI, SwiftData, Combine, AppKit, AVFoundation, Speech, MarkdownUI,
Splash, ActivityIndicatorView, and OllamaKit compatibility products are
Linux-only.
MSG
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-enchanted-source.sh"

UPSTREAM_DIR="$(quillui_resolve_enchanted_source_dir "$ROOT_DIR")"
WORK_ROOT="${QUILLUI_GENERATED_ENCHANTED_MACOS_CHAT_WORKDIR:-$ROOT_DIR/.build/generated-enchanted-macos-chat-check}"
SOURCE_COPY="$WORK_ROOT/source/Enchanted"
LOWERED_COPY="$WORK_ROOT/lowered/Enchanted"
PACKAGE_DIR="$WORK_ROOT/package"
TARGET_DIR="$PACKAGE_DIR/Sources/GeneratedEnchantedMacOSChat"

if [[ -z "$WORK_ROOT" || "$WORK_ROOT" == "/" || "$WORK_ROOT" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generated work directory: ${WORK_ROOT:-<empty>}" >&2
  exit 73
fi

if [[ ! -d "$UPSTREAM_DIR" ]]; then
  quillui_print_enchanted_source_missing "$UPSTREAM_DIR"
  exit 66
fi

rm -rf "$WORK_ROOT"
mkdir -p "$SOURCE_COPY" "$TARGET_DIR"

copy_source() {
  local relative_path="$1"
  local source_path="$UPSTREAM_DIR/$relative_path"
  local destination_path="$SOURCE_COPY/$relative_path"

  if [[ ! -e "$source_path" ]]; then
    echo "Expected Enchanted source path is missing: $source_path" >&2
    exit 66
  fi

  mkdir -p "$(dirname "$destination_path")"
  cp -R "$source_path" "$destination_path"
}

for source_section in Models Stores SwiftData; do
  copy_source "$source_section"
done

for source_file in \
  Services/OllamaService.swift \
  Services/SwiftDataService.swift \
  Services/Throttler.swift \
  Services/HapticsService.swift \
  Services/Clipboard.swift \
  Services/SpeechService.swift \
  Extensions/ModelContext+Extension.swift \
  Extensions/View+Extension.swift \
  Extensions/Button+Extension.swift \
  Extensions/Colours+Extension.swift \
  Extensions/Image+Extension.swift \
  Extensions/SplashSyntaxHighlighter+Extension.swift \
  UI/Shared/Components/SimpleFloatingButton.swift \
  UI/Shared/Chat/Components/ConversationStatusView.swift \
  UI/Shared/Chat/Components/EmptyConversaitonView.swift \
  UI/Shared/Chat/Components/MessageListVIew.swift \
  UI/Shared/Chat/Components/ModelSelectorView.swift \
  UI/Shared/Chat/Components/OptionsMenuView.swift \
  UI/Shared/Chat/Components/ReadingAloudView.swift \
  UI/Shared/Chat/Components/RemovableImage.swift \
  UI/Shared/Chat/Components/RunningBorder.swift \
  UI/Shared/Chat/Components/SelectedImageView.swift \
  UI/Shared/Chat/Components/ChatMessages \
  UI/Shared/Chat/Components/Recorder/RecordingView.swift \
  UI/Shared/Chat/Components/Recorder/SpeechRecogniser.swift \
  UI/Shared/Chat/Components/UnreachableAPIView.swift \
  UI/macOS/Components/DragAndDrop.swift \
  UI/macOS/Chat/ChatView_macOS.swift \
  UI/macOS/Chat/Components/InputFields_macOS.swift \
  UI/macOS/Chat/Components/ToolbarView_macOS.swift
do
  copy_source "$source_file"
done

"$ROOT_DIR/scripts/run-quill-source-lower.sh" "$SOURCE_COPY" "$LOWERED_COPY"

find "$LOWERED_COPY" -name '*.swift' -print0 |
  xargs -0 perl -0pi -e '
    s/^[ \t]*\@Observable[ \t]*\n//gm;
    s/\n[ \t]*#Preview[\s\S]*?#endif\s*\z/\n#endif\n/s;
    s/\n[ \t]*#Preview[\s\S]*\z/\n/s;
    s/os\(macOS\)(?![ \t]*\|\|[ \t]*os\(Linux\))/os(macOS) || os(Linux)/g;
    s/([:(,][ \t]*)\@MainActor[ \t]+/$1/g;
    s/^[ \t]*\@MainActor[ \t]*\n//gm;
    s/^[ \t]*\@MainActor[ \t]+//gm;
  '

conversation_store="$LOWERED_COPY/Stores/ConversationStore.swift"
if [[ -f "$conversation_store" ]]; then
  perl -0pi -e '
    s/final class ConversationStore: Sendable/final class ConversationStore: \@unchecked Sendable/g;
    s/(\n[ \t]*let assistantMessage = MessageSD\(content: "", role: "assistant"\))/\n        let messageHistoryForRequest = messageHistory$1/g;
    s/messages: messageHistory/messages: messageHistoryForRequest/g;
    s/self\?\.handleComplete\(\)/Task { \@MainActor in self?.handleComplete() }/g;
    s/self\?\.handleError\(error\.localizedDescription\)/Task { \@MainActor in self?.handleError(error.localizedDescription) }/g;
    s/self\?\.handleReceive\(response\)/Task { \@MainActor in self?.handleReceive(response) }/g;
  ' "$conversation_store"
fi

speech_service="$LOWERED_COPY/Services/SpeechService.swift"
if [[ -f "$speech_service" ]]; then
  perl -0pi -e '
    s/^[ \t]*\@MainActor[ \t]+final class/final class/gm;
    s/([ \t]*)synthesizer\.stopSpeaking\(at: \.immediate\)/$1_ = synthesizer.stopSpeaking(at: .immediate)/g;
  ' "$speech_service"
fi

model_selector="$LOWERED_COPY/UI/Shared/Chat/Components/ModelSelectorView.swift"
if [[ -f "$model_selector" ]]; then
  perl -0pi -e 's/([:(,][ \t]*)\@MainActor[ \t]+/$1/g' "$model_selector"
fi

clipboard="$LOWERED_COPY/Services/Clipboard.swift"
if [[ -f "$clipboard" ]]; then
  perl -0pi -e '
    s/import Foundation\n/import Foundation\nimport SwiftUI\n/;
    s/return NSImage\(data: imgData\)/return PlatformImage(data: imgData)/g;
    s/\n#endif\n[ \t]*return nil\n([ \t]*\})/\n#endif\n$1/s;
  ' "$clipboard"
fi

input_fields="$LOWERED_COPY/UI/macOS/Chat/Components/InputFields_macOS.swift"
if [[ -f "$input_fields" ]]; then
  perl -0pi -e 's/import SwiftUI/import SwiftUI\nimport AppKit/' "$input_fields"
fi

recording_view="$LOWERED_COPY/UI/Shared/Chat/Components/Recorder/RecordingView.swift"
if [[ -f "$recording_view" ]]; then
  perl -0pi -e '
    s/\nstruct MeetingView_Previews: PreviewProvider[\s\S]*\z/\n/s;
    s/await speechRecognizer\.userInit\(\)/speechRecognizer.userInit()/g;
  ' "$recording_view"
fi

speech_recogniser="$LOWERED_COPY/UI/Shared/Chat/Components/Recorder/SpeechRecogniser.swift"
if [[ -f "$speech_recogniser" ]]; then
  perl -0pi -e '
    s/import Speech/import Speech\nimport SwiftUI/;
    s/actor SpeechRecognizer/final class SpeechRecognizer/;
    s/Task \{[ \t]*\@MainActor[ \t]+in/Task {/g;
    s/Task \{[ \t]*\@MainActor[ \t]+\[errorMessage\][ \t]+in/Task { [errorMessage] in/g;
    s/^[ \t]*\@MainActor[ \t]+//gm;
    s/nonisolated private func/private func/g;
    s/await self\.setUpdateHandler/self.setUpdateHandler/g;
    s/await transcribe\(\)/transcribe()/g;
    s/await reset\(\)/reset()/g;
    s/await onUpdate\?\(message\)/onUpdate?(message)/g;
  ' "$speech_recogniser"
fi

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#$LOWERED_COPY/}"
  destination_file="$TARGET_DIR/$relative_path"
  mkdir -p "$(dirname "$destination_file")"
  cp "$source_file" "$destination_file"
done < <(find "$LOWERED_COPY" -name '*.swift' -print0)

cat > "$TARGET_DIR/QuillGeneratedMacOSChatShims.swift" <<'SWIFT'
import Foundation
import SwiftData
import SwiftUI

extension LanguageModelSD: Hashable {
    var id: String { name }

    static func == (lhs: LanguageModelSD, rhs: LanguageModelSD) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

extension ConversationSD: Hashable {
    static func == (lhs: ConversationSD, rhs: ConversationSD) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension MessageSD: Hashable {
    static func == (lhs: MessageSD, rhs: MessageSD) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension CompletionInstructionSD: Hashable {
    static func == (lhs: CompletionInstructionSD, rhs: CompletionInstructionSD) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Image {
    func render() -> PlatformImage? {
        nil
    }
}

extension PlatformImage {
    func compressImageData() -> Data? {
        data
    }

    func convertImageToBase64String() -> String {
        data?.base64EncodedString() ?? ""
    }
}

enum KeyBase {
    case option
    case command
    case shift
    case control
}

typealias CGKeyCode = UInt16

extension CGKeyCode {
    static let kVK_ANSI_V: CGKeyCode = 0x09
}

struct HotkeyCombination {
    let keyBase: [KeyBase]
    let key: CGKeyCode
    let action: () -> Void
}

extension View {
    func addCustomHotkeys(_ hotkeys: [HotkeyCombination]) -> Self {
        self
    }
}

struct Settings: View {
    var body: some View {
        Text("Settings")
    }
}

struct SidebarView: View {
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var onConversationTap: (ConversationSD) -> Void
    var onConversationDelete: (ConversationSD) -> Void
    var onDeleteDailyConversations: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(conversations) { conversation in
                Button(conversation.name) {
                    onConversationTap(conversation)
                }
                .disabled(conversation == selectedConversation)
            }
        }
        .padding()
    }
}
SWIFT

cat > "$TARGET_DIR/GeneratedMain.swift" <<'SWIFT'
import Foundation
import SwiftData
import SwiftUI

@main
struct GeneratedEnchantedMacOSChatCheck {
    static func main() {
        let model = LanguageModelSD(
            name: "llava:latest",
            imageSupport: true,
            modelProvider: .ollama
        )
        let conversation = ConversationSD(name: "How to center div in HTML?")
        let message = MessageSD(content: "# Hello\n\n```swift\nprint(1)\n```", role: "assistant")
        let image = Image(systemName: "photo")
        var draft = "Hello"
        var editMessage: MessageSD?

        _ = ChatView(
            selectedConversation: conversation,
            conversations: [conversation],
            messages: [message],
            modelsList: [model],
            onMenuTap: {},
            onNewConversationTap: {},
            onSendMessageTap: { _, _, _, _ in },
            onConversationTap: { _ in },
            conversationState: .completed,
            onStopGenerateTap: {},
            reachable: true,
            modelSupportsImages: true,
            selectedModel: model,
            onSelectModel: { _ in },
            onConversationDelete: { _ in },
            onDeleteDailyConversations: { _ in },
            userInitials: "QC",
            copyChat: { _ in }
        )
        _ = ToolbarView(
            modelsList: [model],
            selectedModel: model,
            onSelectModel: { _ in },
            onNewConversationTap: {},
            copyChat: { _ in }
        )
        _ = InputFieldsView(
            message: Binding(get: { draft }, set: { draft = $0 }),
            conversationState: .completed,
            onStopGenerateTap: {},
            selectedModel: model,
            onSendMessageTap: { _, _, _, _ in },
            editMessage: Binding(get: { editMessage }, set: { editMessage = $0 })
        )
        _ = RecordingView(isRecording: .constant(false))
        _ = DragAndDrop(cornerRadius: 10)
        _ = UnreachableAPIView()
        _ = RemovableImage(image: image, onClick: {})

        print("Generated Enchanted macOS-chat compile check passed")
    }
}
SWIFT

cat > "$PACKAGE_DIR/Package.swift" <<SWIFT
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GeneratedEnchantedMacOSChatCheck",
    products: [
        .executable(name: "generated-enchanted-macos-chat", targets: ["GeneratedEnchantedMacOSChat"])
    ],
    dependencies: [
        .package(name: "QuillUI", path: "$ROOT_DIR")
    ],
    targets: [
        .executableTarget(
            name: "GeneratedEnchantedMacOSChat",
            dependencies: [
                .product(name: "SwiftUI", package: "QuillUI"),
                .product(name: "SwiftData", package: "QuillUI"),
                .product(name: "Combine", package: "QuillUI"),
                .product(name: "OllamaKit", package: "QuillUI"),
                .product(name: "MarkdownUI", package: "QuillUI"),
                .product(name: "Splash", package: "QuillUI"),
                .product(name: "ActivityIndicatorView", package: "QuillUI"),
                .product(name: "AppKit", package: "QuillUI"),
                .product(name: "AVFoundation", package: "QuillUI"),
                .product(name: "Speech", package: "QuillUI")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
SWIFT

swift build \
  --package-path "$PACKAGE_DIR" \
  --scratch-path "$WORK_ROOT/.build-check" \
  --product generated-enchanted-macos-chat

cat <<MSG

Generated Enchanted macOS-chat check completed.
Source copied from:
  $UPSTREAM_DIR
Generated package:
  $PACKAGE_DIR

MSG
