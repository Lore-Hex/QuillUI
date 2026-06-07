#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  cat >&2 <<'MSG'
The generated Enchanted full-source check requires Linux because the
SwiftUI, SwiftData, Combine, AppKit, AVFoundation, Speech, MarkdownUI,
Splash, ActivityIndicatorView, Vortex, KeyboardShortcuts, Magnet, Carbon,
AsyncAlgorithms, PhotosUI, UIKit, ApplicationServices, and CoreGraphics
compatibility products are Linux-only.
MSG
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-enchanted-source.sh"

UPSTREAM_DIR="$(quillui_resolve_enchanted_source_dir "$ROOT_DIR")"
WORK_ROOT="${QUILLUI_GENERATED_APP_WORKDIR:-${QUILLUI_GENERATED_ENCHANTED_FULL_WORKDIR:-$ROOT_DIR/.build/generated-enchanted-full-source-check}}"
SOURCE_COPY="$WORK_ROOT/source/Enchanted"
LOWERED_COPY="$WORK_ROOT/lowered/Enchanted"
PACKAGE_DIR="$WORK_ROOT/package"
MODE="${QUILLUI_GENERATED_APP_MODE:-${QUILLUI_GENERATED_ENCHANTED_MODE:-check}}"
APP_ENTRY_TYPE="${QUILLUI_GENERATED_APP_ENTRY_TYPE:-EnchantedApp}"
APP_MAIN_TYPE="${QUILLUI_GENERATED_APP_MAIN_TYPE:-GeneratedSwiftUILinuxMain}"

case "$MODE" in
  check)
    PACKAGE_NAME="${QUILLUI_GENERATED_APP_PACKAGE_NAME:-${QUILLUI_GENERATED_ENCHANTED_PACKAGE_NAME:-GeneratedEnchantedFullSourceCheck}}"
    PRODUCT_NAME="${QUILLUI_GENERATED_APP_PRODUCT_NAME:-${QUILLUI_GENERATED_ENCHANTED_PRODUCT_NAME:-generated-enchanted-full-source}}"
    TARGET_NAME="${QUILLUI_GENERATED_APP_TARGET_NAME:-${QUILLUI_GENERATED_ENCHANTED_TARGET_NAME:-GeneratedEnchantedFullSource}}"
    ;;
  app)
    PACKAGE_NAME="${QUILLUI_GENERATED_APP_PACKAGE_NAME:-${QUILLUI_GENERATED_ENCHANTED_PACKAGE_NAME:-GeneratedEnchantedLinuxApp}}"
    PRODUCT_NAME="${QUILLUI_GENERATED_APP_PRODUCT_NAME:-${QUILLUI_GENERATED_ENCHANTED_PRODUCT_NAME:-quill-enchanted-linux}}"
    TARGET_NAME="${QUILLUI_GENERATED_APP_TARGET_NAME:-${QUILLUI_GENERATED_ENCHANTED_TARGET_NAME:-GeneratedEnchantedLinuxApp}}"
    ;;
  *)
    echo "Unsupported QUILLUI_GENERATED_ENCHANTED_MODE: $MODE" >&2
    exit 64
    ;;
esac

validate_swift_type() {
  local value="$1"
  local label="$2"

  if [[ ! "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then
    echo "$label must be a Swift type path, got: $value" >&2
    exit 64
  fi
}

validate_swift_type "$APP_ENTRY_TYPE" "QUILLUI_GENERATED_APP_ENTRY_TYPE"
validate_swift_type "$APP_MAIN_TYPE" "QUILLUI_GENERATED_APP_MAIN_TYPE"

if [[ -z "$WORK_ROOT" || "$WORK_ROOT" == "/" || "$WORK_ROOT" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generated work directory: ${WORK_ROOT:-<empty>}" >&2
  exit 73
fi

if [[ ! -d "$UPSTREAM_DIR" ]]; then
  quillui_print_enchanted_source_missing "$UPSTREAM_DIR"
  exit 66
fi

rm -rf "$WORK_ROOT"
mkdir -p "$SOURCE_COPY"
cp -R "$UPSTREAM_DIR"/. "$SOURCE_COPY"/

"$ROOT_DIR/scripts/run-quill-source-lower.sh" "$SOURCE_COPY" "$LOWERED_COPY"
"$ROOT_DIR/scripts/lower-swiftui-source-for-linux.sh" "$LOWERED_COPY"

"$ROOT_DIR/scripts/profiles/enchanted-full-source/lower-profile-source.sh" "$LOWERED_COPY"

if [[ "$MODE" != "app" ]]; then
  cat > "$LOWERED_COPY/GeneratedMain.swift" <<'SWIFT'
import Foundation
import SwiftData
import SwiftUI

@main
struct GeneratedEnchantedFullSourceCheck {
    static func main() {
        let model = LanguageModelSD(
            name: "llava:latest",
            imageSupport: true,
            modelProvider: .ollama
        )
        let conversation = ConversationSD(name: "How to center div in HTML?")
        let message = MessageSD(content: "# Hello\n\n```swift\nprint(1)\n```", role: "assistant")
        let completion = CompletionInstructionSD(
            name: "Summarize",
            keyboardCharacterStr: "s",
            instruction: "Summarize {{text}}",
            order: 0,
            modelTemperature: 0.2
        )
        let image = Image(systemName: "photo")
        var draft = "Hello"
        var editMessage: MessageSD?
        var completions = [completion]

        _ = EnchantedApp()
        _ = ApplicationEntry()
        _ = Chat(languageModelStore: .shared, conversationStore: .shared, appStore: .shared)
        _ = Voice(languageModelStore: .shared, conversationStore: .shared, appStore: .shared)
        _ = VoiceView()
        _ = Settings()
        _ = SettingsView(
            ollamaUri: .constant("http://localhost:11434"),
            systemPrompt: .constant("Be concise."),
            vibrations: .constant(true),
            colorScheme: .constant(.system),
            defaultOllamModel: .constant(model.name),
            ollamaBearerToken: .constant(""),
            appUserInitials: .constant("QC"),
            pingInterval: .constant("5"),
            voiceIdentifier: .constant("quill.linux.default"),
            save: {},
            checkServer: {},
            deleteAll: {},
            ollamaLangugeModels: [model],
            voices: []
        )
        _ = SidebarView(
            selectedConversation: conversation,
            conversations: [conversation],
            onConversationTap: { _ in },
            onConversationDelete: { _ in },
            onDeleteDailyConversations: { _ in }
        )
        _ = KeyboardShortcutsDemo()
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
        _ = PromptPanelView(onSubmit: { _, _ in }, onLayoutUpdate: {}, imageSupport: true)
        _ = CompletionsEditor()
        _ = CompletionsEditorView(
            completions: Binding(get: { completions }, set: { completions = $0 }),
            onSave: {},
            onDelete: { _ in },
            accessibilityAccess: true,
            requestAccessibilityAccess: {}
        )
        _ = UpsertCompletionView(completion: completion, onSave: {})
        _ = CompletionButtonView(name: "Summarize", keyboardCharacter: "s") {}
        _ = PanelCompletionsView(completions: [completion], completionInWindow: { _, _ in }, completionInApp: { _ in })
        _ = PromptPanel(
            completionsPanelVM: CompletionsPanelVM(),
            onSubmitPanel: {},
            onSubmitCompletion: { _ in },
            onLayoutUpdate: {}
        )
        _ = MenuBarControlView(notifications: [])
        _ = MenuBarControl()
        _ = Menus()

        print("Generated Enchanted full-source compile check passed")
    }
}
SWIFT
fi

include_backend_entry=0
if [[ "$MODE" == "app" ]]; then
  include_backend_entry=1
fi

QUILLUI_GENERATED_SOURCES_DIR="$LOWERED_COPY" \
QUILLUI_GENERATED_SOURCE_COUNT_DIR="$SOURCE_COPY" \
QUILLUI_GENERATED_WORKDIR="$WORK_ROOT" \
QUILLUI_GENERATED_PACKAGE_DIR="$PACKAGE_DIR" \
QUILLUI_GENERATED_PACKAGE_NAME="$PACKAGE_NAME" \
QUILLUI_GENERATED_PRODUCT_NAME="$PRODUCT_NAME" \
QUILLUI_GENERATED_TARGET_NAME="$TARGET_NAME" \
QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY="$include_backend_entry" \
QUILLUI_GENERATED_APP_ENTRY_TYPE="$APP_ENTRY_TYPE" \
QUILLUI_GENERATED_APP_MAIN_TYPE="$APP_MAIN_TYPE" \
QUILLUI_GENERATED_REPORT_LABEL="Generated Enchanted full-source $MODE" \
"$ROOT_DIR/scripts/generate-swiftui-linux-package.sh"
