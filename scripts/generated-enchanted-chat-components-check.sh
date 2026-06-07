#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  cat >&2 <<'MSG'
The generated Enchanted chat-components check requires Linux because the
SwiftUI, SwiftData, Combine, AppKit, AVFoundation, MarkdownUI, Splash,
ActivityIndicatorView, and OllamaKit compatibility products are Linux-only.
MSG
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-enchanted-source.sh"

UPSTREAM_DIR="$(quillui_resolve_enchanted_source_dir "$ROOT_DIR")"
WORK_ROOT="${QUILLUI_GENERATED_ENCHANTED_CHAT_WORKDIR:-$ROOT_DIR/.build/generated-enchanted-chat-components-check}"
SOURCE_COPY="$WORK_ROOT/source/Enchanted"
LOWERED_COPY="$WORK_ROOT/lowered/Enchanted"
PACKAGE_DIR="$WORK_ROOT/package"
TARGET_DIR="$PACKAGE_DIR/Sources/GeneratedEnchantedChatComponents"

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
  UI/Shared/Chat/Components/ChatMessages
do
  copy_source "$source_file"
done

"$ROOT_DIR/scripts/run-quill-source-lower.sh" "$SOURCE_COPY" "$LOWERED_COPY"

find "$LOWERED_COPY" -name '*.swift' -print0 |
  xargs -0 perl -0pi -e '
    s/^[ \t]*\@Observable[ \t]*\n//gm;
    s/\n[ \t]*#Preview[\s\S]*\z/\n/s;
    s/os\(macOS\)(?![ \t]*\|\|[ \t]*os\(Linux\))/os(macOS) || os(Linux)/g;
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

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#$LOWERED_COPY/}"
  destination_file="$TARGET_DIR/$relative_path"
  mkdir -p "$(dirname "$destination_file")"
  cp "$source_file" "$destination_file"
done < <(find "$LOWERED_COPY" -name '*.swift' -print0)

cat > "$TARGET_DIR/QuillGeneratedChatShims.swift" <<'SWIFT'
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
    @MainActor
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
SWIFT

cat > "$TARGET_DIR/GeneratedMain.swift" <<'SWIFT'
import Foundation
import SwiftData
import SwiftUI

@main
struct GeneratedEnchantedChatComponentsCheck {
    static func main() {
        let model = LanguageModelSD(
            name: "llama3.2:latest",
            imageSupport: true,
            modelProvider: .ollama
        )
        let message = MessageSD(content: "# Hello\n\n```swift\nprint(1)\n```", role: "assistant")
        let image = Image(systemName: "photo")

        _ = EmptyConversaitonView(sendPrompt: { _ in })
        _ = ModelSelectorView(modelsList: [model], selectedModel: model, onSelectModel: { _ in })
        _ = ChatMessageView(message: message, userInitials: "AI", editMessage: .constant(nil))
        _ = MessageListView(
            messages: [message],
            conversationState: .completed,
            userInitials: "AI",
            editMessage: .constant(nil)
        )
        _ = ConversationStatusView(state: .loading)
        _ = ConversationStatusView(state: .completed)
        _ = ConversationStatusView(state: .error(message: "offline"))
        _ = ReadingAloudView(onStopTap: {})
        _ = RemovableImage(image: image, onClick: {})
        _ = SelectedImageView(image: .constant(image))
        _ = MoreOptionsMenuView(copyChat: { _ in })
        _ = SimpleFloatingButton(systemImage: "photo.fill", onClick: {})

        print("Generated Enchanted chat-components compile check passed")
    }
}
SWIFT

cat > "$PACKAGE_DIR/Package.swift" <<SWIFT
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GeneratedEnchantedChatComponentsCheck",
    products: [
        .executable(name: "generated-enchanted-chat-components", targets: ["GeneratedEnchantedChatComponents"])
    ],
    dependencies: [
        .package(name: "QuillUI", path: "$ROOT_DIR")
    ],
    targets: [
        .executableTarget(
            name: "GeneratedEnchantedChatComponents",
            dependencies: [
                .product(name: "SwiftUI", package: "QuillUI"),
                .product(name: "SwiftData", package: "QuillUI"),
                .product(name: "Combine", package: "QuillUI"),
                .product(name: "OllamaKit", package: "QuillUI"),
                .product(name: "MarkdownUI", package: "QuillUI"),
                .product(name: "Splash", package: "QuillUI"),
                .product(name: "ActivityIndicatorView", package: "QuillUI"),
                .product(name: "AppKit", package: "QuillUI"),
                .product(name: "AVFoundation", package: "QuillUI")
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
  --product generated-enchanted-chat-components

cat <<MSG

Generated Enchanted chat-components check completed.
Source copied from:
  $UPSTREAM_DIR
Generated package:
  $PACKAGE_DIR

MSG
