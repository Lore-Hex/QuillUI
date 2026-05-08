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
UPSTREAM_DIR="${QUILLUI_APP_SOURCE_DIR:-${ENCHANTED_SOURCE_DIR:-$ROOT_DIR/.upstream/enchanted/Enchanted}}"
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
    PRODUCT_NAME="${QUILLUI_GENERATED_APP_PRODUCT_NAME:-${QUILLUI_GENERATED_ENCHANTED_PRODUCT_NAME:-quill-chat-linux}}"
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
  cat >&2 <<MSG
Enchanted source was not found at:
  $UPSTREAM_DIR

Set QUILLUI_APP_SOURCE_DIR=/path/to/AppSources and rerun.
MSG
  exit 66
fi

rm -rf "$WORK_ROOT"
mkdir -p "$SOURCE_COPY"
cp -R "$UPSTREAM_DIR"/. "$SOURCE_COPY"/

"$ROOT_DIR/scripts/lower-swiftdata-for-quilldata.sh" "$SOURCE_COPY" "$LOWERED_COPY"
"$ROOT_DIR/scripts/lower-swiftui-source-for-linux.sh" "$LOWERED_COPY"

find "$LOWERED_COPY" -name '*.swift' -print0 |
  xargs -0 perl -0pi -e '
    s/await Haptics\.shared\.mediumTap\(\)/Haptics.shared.mediumTap()/g;
    s/await languageModelStore\.setModel\(/languageModelStore.setModel(/g;
    s/let messages = await ConversationStore\.shared\.messages/let messages = ConversationStore.shared.messages/g;
    s/await Accessibility\.shared\.showAccessibilityInstructionsWindow\(\)/Accessibility.shared.showAccessibilityInstructionsWindow()/g;
    s/_ = try await loadCompletions/_ = await loadCompletions/g;
    s/try\? await conversationStore\.deleteAllConversations\(\)/conversationStore.deleteAllConversations()/g;
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

enchanted_app="$LOWERED_COPY/Application/EnchantedApp.swift"
if [[ -f "$enchanted_app" ]]; then
  perl -0pi -e '
    s/import SwiftUI/import SwiftUI\nimport AppKit/;
    s/\@NSApplicationDelegateAdaptor\(PanelManager\.self\) var panelManager/\@State var panelManager = PanelManager()/g;
  ' "$enchanted_app"
fi

prompt_panel_view="$LOWERED_COPY/UI/macOS/Components/PromptPanelView.swift"
if [[ -f "$prompt_panel_view" ]]; then
  perl -0pi -e 's/import SwiftUI/import SwiftUI\nimport AppKit/' "$prompt_panel_view"
fi

menu_bar_control_view="$LOWERED_COPY/UI/macOS/MenuBar/MenuBarControlView_macOS.swift"
if [[ -f "$menu_bar_control_view" ]]; then
  perl -0pi -e 's/import SwiftUI/import SwiftUI\nimport AppKit/' "$menu_bar_control_view"
fi

settings_view="$LOWERED_COPY/UI/Shared/Settings/SettingsView.swift"
if [[ -f "$settings_view" ]]; then
  perl -0pi -e 's/import SwiftUI/import SwiftUI\nimport AppKit/' "$settings_view"
fi

header_view="$LOWERED_COPY/UI/Shared/Chat/Components/Header.swift"
if [[ -f "$header_view" ]]; then
  perl -0pi -e 's/Text\(selectedModel\.name\)/Text("Model")/g' "$header_view"
fi

ui_image_extension="$LOWERED_COPY/Extensions/UIImage+Extension.swift"
if [[ -f "$ui_image_extension" ]]; then
  perl -0pi -e 's/import SwiftUI/import SwiftUI\nimport AppKit/' "$ui_image_extension"
fi

view_extension="$LOWERED_COPY/Extensions/View+Extension.swift"
if [[ -f "$view_extension" ]]; then
  perl -0pi -e '
    s/let image = renderer\.nsImage/let image: PlatformImage? = nil/g;
  ' "$view_extension"
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

panel_vm="$LOWERED_COPY/UI/macOS/PromptPanel/PanelCompletionsVM.swift"
if [[ -f "$panel_vm" ]]; then
  perl -0pi -e '
    s/self\?\.handleComplete\(\)/Task { \@MainActor in self?.handleComplete() }/g;
    s/self\?\.handleError\(error\.localizedDescription\)/Task { \@MainActor in self?.handleError(error.localizedDescription) }/g;
    s/self\?\.handleReceive\(response\)/Task { \@MainActor in self?.handleReceive(response) }/g;
    s/OKCompletionOptions\(temperature: completion\.modelTemperature \?\? 0\.8\)/OKCompletionOptions(temperature: Double(completion.modelTemperature ?? 0.8))/g;
  ' "$panel_vm"
fi

completions_editor="$LOWERED_COPY/UI/macOS/CompletionsEditor/CompletionsEditor.swift"
if [[ -f "$completions_editor" ]]; then
  perl -0pi -e '
    s/completions: \$completionsStore\.completions/completions: Binding(get: { completionsStore.completions }, set: { completionsStore.completions = \$0 })/g;
  ' "$completions_editor"
fi

completions_editor_view="$LOWERED_COPY/UI/macOS/CompletionsEditor/CompletionsEditorView.swift"
if [[ -f "$completions_editor_view" ]]; then
  perl -0pi -e '
    s/ForEach\(\$completions, editActions: \.move\) \{ \$completion in/ForEach(completions) { completion in/g;
  ' "$completions_editor_view"
fi

upsert_completion_view="$LOWERED_COPY/UI/macOS/CompletionsEditor/UpsertCompletionView.swift"
if [[ -f "$upsert_completion_view" ]]; then
  perl -0pi -e '
    s/\.onChange\(of: keyboardShortcutKey\) \{ newValue in\n([ \t]*)if newValue\.count > 1 \{\n([ \t]*)keyboardShortcutKey = String\(newValue\.prefix\(1\)\)\n([ \t]*)\}\n([ \t]*)\}/.onChange(of: keyboardShortcutKey, perform: { newValue in\n$1if newValue.count > 1 {\n$2keyboardShortcutKey = String(newValue.prefix(1))\n$3}\n$4})/g;
  ' "$upsert_completion_view"
fi

for profile_replaced_file in \
  Helpers/Accessibility.swift \
  Helpers/HotKeys.swift \
  Services/HotkeyService.swift \
  UI/macOS/PromptPanel/FloatingPanel.swift \
  UI/macOS/PromptPanel/PanelManager.swift \
  Application/QuillUpdater.swift \
  Application/QuillUSBWatcher.swift \
  Application/QuillUSBLauncher.swift
do
  if [[ -f "$LOWERED_COPY/$profile_replaced_file" ]]; then
    : > "$LOWERED_COPY/$profile_replaced_file"
  fi
done

cat > "$LOWERED_COPY/QuillGeneratedProfileAliases.swift" <<'SWIFT'
import AppKit
import QuillKit
import SwiftUI

typealias Accessibility = QuillAccessibilityService
typealias KeyBase = QuillKeyBase
typealias HotkeyCombination = QuillHotkeyCombination
typealias CGKeyCode = UInt16
typealias FloatingPanel = QuillFloatingPanel
typealias PanelManager = QuillPanelManager
typealias QuillUpdater = QuillUpdateService
typealias CheckForUpdatesMenuItem = QuillCheckForUpdatesMenuItem
typealias QuillUSBWatcher = QuillDeviceWatcher
typealias HotkeyService = QuillHotkeyService

extension CGKeyCode {
    static let kVK_ANSI_V: CGKeyCode = 0x09
}

enum QuillUSBLauncher {
    static func install() {
        QuillDeviceLauncher.install(
            label: "co.lorehex.quillchat.usb-launcher",
            subsystem: "co.lorehex.quillchat"
        )
    }
}
SWIFT

cat > "$LOWERED_COPY/QuillGeneratedFullSourceShims.swift" <<'SWIFT'
import Foundation
import AppKit
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

SWIFT

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

include_gtk_backend=0
if [[ "$MODE" == "app" ]]; then
  include_gtk_backend=1
fi

QUILLUI_GENERATED_SOURCES_DIR="$LOWERED_COPY" \
QUILLUI_GENERATED_SOURCE_COUNT_DIR="$SOURCE_COPY" \
QUILLUI_GENERATED_WORKDIR="$WORK_ROOT" \
QUILLUI_GENERATED_PACKAGE_DIR="$PACKAGE_DIR" \
QUILLUI_GENERATED_PACKAGE_NAME="$PACKAGE_NAME" \
QUILLUI_GENERATED_PRODUCT_NAME="$PRODUCT_NAME" \
QUILLUI_GENERATED_TARGET_NAME="$TARGET_NAME" \
QUILLUI_GENERATED_INCLUDE_GTK_BACKEND="$include_gtk_backend" \
QUILLUI_GENERATED_APP_ENTRY_TYPE="$APP_ENTRY_TYPE" \
QUILLUI_GENERATED_APP_MAIN_TYPE="$APP_MAIN_TYPE" \
QUILLUI_GENERATED_REPORT_LABEL="Generated Enchanted full-source $MODE" \
"$ROOT_DIR/scripts/generate-swiftui-linux-package.sh"
