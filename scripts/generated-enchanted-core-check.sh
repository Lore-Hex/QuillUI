#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  cat >&2 <<'MSG'
The generated Enchanted core check requires Linux because the SwiftUI,
SwiftData, Combine, and OllamaKit compatibility products are Linux-only.
MSG
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="${ENCHANTED_SOURCE_DIR:-$ROOT_DIR/.upstream/enchanted/Enchanted}"
WORK_ROOT="${QUILLUI_GENERATED_ENCHANTED_CORE_WORKDIR:-$ROOT_DIR/.build/generated-enchanted-core-check}"
SOURCE_COPY="$WORK_ROOT/source/Enchanted"
LOWERED_COPY="$WORK_ROOT/lowered/Enchanted"
PACKAGE_DIR="$WORK_ROOT/package"
TARGET_DIR="$PACKAGE_DIR/Sources/GeneratedEnchantedCore"

if [[ -z "$WORK_ROOT" || "$WORK_ROOT" == "/" || "$WORK_ROOT" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generated work directory: ${WORK_ROOT:-<empty>}" >&2
  exit 73
fi

if [[ ! -d "$UPSTREAM_DIR" ]]; then
  cat >&2 <<MSG
Enchanted source was not found at:
  $UPSTREAM_DIR

Set ENCHANTED_SOURCE_DIR=/path/to/Enchanted and rerun.
MSG
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
  Extensions/ModelContext+Extension.swift
do
  copy_source "$source_file"
done

"$ROOT_DIR/scripts/run-quill-source-lower.sh" "$SOURCE_COPY" "$LOWERED_COPY"

find "$LOWERED_COPY" -name '*.swift' -print0 |
  xargs -0 perl -0pi -e 's/^[ \t]*\@Observable[ \t]*\n//gm'

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

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#$LOWERED_COPY/}"
  destination_file="$TARGET_DIR/$relative_path"
  mkdir -p "$(dirname "$destination_file")"
  cp "$source_file" "$destination_file"
done < <(find "$LOWERED_COPY" -name '*.swift' -print0)

cat > "$TARGET_DIR/QuillGeneratedCoreShims.swift" <<'SWIFT'
import Foundation
import SwiftData
import SwiftUI

extension LanguageModelSD: Equatable {
    var id: String { name }

    static func == (lhs: LanguageModelSD, rhs: LanguageModelSD) -> Bool {
        lhs.name == rhs.name
    }
}

extension ConversationSD: Equatable {
    static func == (lhs: ConversationSD, rhs: ConversationSD) -> Bool {
        lhs.id == rhs.id
    }
}

extension MessageSD: Equatable {
    static func == (lhs: MessageSD, rhs: MessageSD) -> Bool {
        lhs.id == rhs.id
    }
}

extension CompletionInstructionSD: Equatable {
    static func == (lhs: CompletionInstructionSD, rhs: CompletionInstructionSD) -> Bool {
        lhs.id == rhs.id
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
import OllamaKit
import SwiftData
import SwiftUI

@main
struct GeneratedEnchantedCoreCheck {
    static func main() async throws {
        let languageModel = LanguageModelSD(
            name: "llama3.2:latest",
            imageSupport: false,
            modelProvider: .ollama
        )
        let conversation = ConversationSD(name: "Generated Enchanted check")
        let message = MessageSD(content: "hello", role: "user")

        conversation.model = languageModel
        message.conversation = conversation
        conversation.messages.append(message)

        _ = SwiftDataService.shared
        _ = LanguageModelStore.shared
        _ = ConversationStore.shared
        _ = CompletionsStore.shared
        _ = OKChatRequestData.Message(role: .user, content: message.content)

        print("Generated Enchanted core compile check passed: \(conversation.name)")
    }
}
SWIFT

cat > "$PACKAGE_DIR/Package.swift" <<SWIFT
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GeneratedEnchantedCoreCheck",
    products: [
        .executable(name: "generated-enchanted-core", targets: ["GeneratedEnchantedCore"])
    ],
    dependencies: [
        .package(name: "QuillUI", path: "$ROOT_DIR")
    ],
    targets: [
        .executableTarget(
            name: "GeneratedEnchantedCore",
            dependencies: [
                .product(name: "SwiftUI", package: "QuillUI"),
                .product(name: "SwiftData", package: "QuillUI"),
                .product(name: "Combine", package: "QuillUI"),
                .product(name: "OllamaKit", package: "QuillUI")
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
  --product generated-enchanted-core

cat <<MSG

Generated Enchanted core check completed.
Source copied from:
  $UPSTREAM_DIR
Generated package:
  $PACKAGE_DIR

MSG
