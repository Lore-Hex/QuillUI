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

TARGET_DIR="$PACKAGE_DIR/Sources/$TARGET_NAME"

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
mkdir -p "$SOURCE_COPY" "$TARGET_DIR"
cp -R "$UPSTREAM_DIR"/. "$SOURCE_COPY"/

"$ROOT_DIR/scripts/lower-swiftdata-for-quilldata.sh" "$SOURCE_COPY" "$LOWERED_COPY"

find "$LOWERED_COPY" -name '*.swift' -print0 |
  xargs -0 perl -0pi -e '
    s/^[ \t]*\@main[ \t]*\n//gm;
    s/^[ \t]*\@Observable[ \t]*\n//gm;
    s/\n[ \t]*#Preview[\s\S]*?#endif\s*\z/\n#endif\n/s;
    s/\n[ \t]*#Preview[\s\S]*\z/\n/s;
    s/os\(macOS\)(?![ \t]*\|\|[ \t]*os\(Linux\))/os(macOS) || os(Linux)/g;
    s/([:(,][ \t]*)\@MainActor[ \t]+/$1/g;
    s/^[ \t]*\@MainActor[ \t]*\n//gm;
    s/^[ \t]*\@MainActor[ \t]+//gm;
    s/: View, Sendable/: View/g;
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

cat > "$LOWERED_COPY/Helpers/Accessibility.swift" <<'SWIFT'
#if os(macOS) || os(Linux)
import Foundation
import AppKit

final class Accessibility {
    static let shared = Accessibility()

    func checkAccessibility() -> Bool { false }
    func showAccessibilityInstructionsWindow() {}
    func getSelectedText() -> String? { nil }
    func getSelectedTextAX() -> String? { nil }
    func getSelectedTextViaCopy(retryAttempts: Int = 1) -> String? { nil }
    func simulateCopyKeyPress() {}
    func simulateTyping(for string: String) {}
    static func simulatePasteCommand() {}
}
#endif
SWIFT

cat > "$LOWERED_COPY/Helpers/HotKeys.swift" <<'SWIFT'
#if os(macOS) || os(Linux)
import Foundation
import SwiftUI

enum KeyBase: CaseIterable {
    case option
    case command
    case shift
    case control

    var isPressed: Bool { false }
}

typealias CGKeyCode = UInt16

struct HotkeyCombination {
    let keyBase: [KeyBase]
    let key: CGKeyCode
    let action: () -> Void

    var keyBasePressed: Bool { false }
}

extension CGKeyCode {
    static let kVK_ANSI_V: CGKeyCode = 0x09
}

extension View {
    func addCustomHotkeys(_ hotkeys: [HotkeyCombination]) -> Self {
        self
    }
}
#endif
SWIFT

cat > "$LOWERED_COPY/Services/HotkeyService.swift" <<'SWIFT'
#if os(macOS) || os(Linux)
import Foundation
import AppKit

final class HotkeyService {
    static let shared = HotkeyService()

    func registerSingleUseSpace(modifiers: NSEvent.ModifierFlags, completion: @escaping () -> ()?) {
        _ = completion()
    }
}
#endif
SWIFT

cat > "$LOWERED_COPY/UI/macOS/PromptPanel/FloatingPanel.swift" <<'SWIFT'
#if os(macOS) || os(Linux)
import Foundation

final class FloatingPanel {
    var isVisible = false

    init() {}
    func orderOut(_ sender: Any?) { isVisible = false }
    func makeKeyAndOrderFront(_ sender: Any?) { isVisible = true }
    func close() { isVisible = false }
}
#endif
SWIFT

cat > "$LOWERED_COPY/UI/macOS/PromptPanel/PanelManager.swift" <<'SWIFT'
#if os(macOS) || os(Linux)
import Foundation

final class PanelManager: NSObject {
    var panel = FloatingPanel()

    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func hidePanel() {
        panel.orderOut(nil)
    }

    func showPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    func onSubmitMessage() {
        hidePanel()
    }

    func onSubmitCompletion(scheduledTyping: Bool) {
        hidePanel()
    }
}
#endif
SWIFT

quill_updater="$LOWERED_COPY/Application/QuillUpdater.swift"
if [[ -f "$quill_updater" ]]; then
  cat > "$quill_updater" <<'SWIFT'
#if os(macOS) || os(Linux)
import SwiftUI

final class QuillUpdater: ObservableObject {
    static let shared = QuillUpdater()

    @Published private(set) var canCheckForUpdates = false

    private init() {}

    func checkForUpdates() {}
}

struct CheckForUpdatesMenuItem: View {
    @ObservedObject private var updater = QuillUpdater.shared

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
#endif
SWIFT
fi

quill_usb_watcher="$LOWERED_COPY/Application/QuillUSBWatcher.swift"
if [[ -f "$quill_usb_watcher" ]]; then
  cat > "$quill_usb_watcher" <<'SWIFT'
#if os(macOS) || os(Linux)
import Foundation
import QuillKit

final class QuillUSBWatcher {
    static let shared = QuillUSBWatcher()

    private init() {}

    func start() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillKit",
            operation: "QuillUSBWatcher.start",
            severity: .unsupported,
            message: "Quill USB watcher has no native Linux backend yet."
        )
    }

    func stop() {}
    func autoConfigureIfNeeded() {}
}
#endif
SWIFT
fi

quill_usb_launcher="$LOWERED_COPY/Application/QuillUSBLauncher.swift"
if [[ -f "$quill_usb_launcher" ]]; then
  cat > "$quill_usb_launcher" <<'SWIFT'
#if os(macOS) || os(Linux)
import Foundation
import os

enum QuillUSBLauncher {
    static let label = "co.lorehex.quillchat.usb-launcher"
    private static let log = Logger(subsystem: "co.lorehex.quillchat", category: "usb-launcher")

    static func install() {
        log.info("Quill USB LaunchAgent install is unavailable on Linux.")
    }
}
#endif
SWIFT
fi

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#$LOWERED_COPY/}"
  destination_file="$TARGET_DIR/$relative_path"
  mkdir -p "$(dirname "$destination_file")"
  cp "$source_file" "$destination_file"
done < <(find "$LOWERED_COPY" -name '*.swift' -print0)

cat > "$TARGET_DIR/QuillGeneratedFullSourceShims.swift" <<'SWIFT'
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

struct Window<Content: View>: Scene {
    typealias Body = Never
    let title: String
    let id: String
    let content: Content

    init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.content = content()
    }

    var body: Never { fatalError("Window is a generated compatibility scene") }
}

final class NSWindow {
    static var allowsAutomaticWindowTabbing = true
}

extension Image {
    func render() -> PlatformImage? {
        nil
    }
}
SWIFT

if [[ "$MODE" == "app" ]]; then
  cat > "$TARGET_DIR/GeneratedMain.swift" <<SWIFT
import BackendGTK4

@main
struct $APP_MAIN_TYPE {
    static func main() {
        GTK4Backend().run($APP_ENTRY_TYPE.self)
    }
}
SWIFT
else
  cat > "$TARGET_DIR/GeneratedMain.swift" <<'SWIFT'
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

extra_package_dependencies=""
extra_target_dependencies=""
if [[ "$MODE" == "app" ]]; then
  extra_package_dependencies=$',
        .package(url: "https://github.com/codelynx/SwiftOpenUI", revision: "6150b964a7cb1cf3a961770f6947ed55c1a31433")'
  extra_target_dependencies=$',
                .product(name: "BackendGTK4", package: "SwiftOpenUI")'
fi

cat > "$PACKAGE_DIR/Package.swift" <<SWIFT
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "$PACKAGE_NAME",
    products: [
        .executable(name: "$PRODUCT_NAME", targets: ["$TARGET_NAME"])
    ],
    dependencies: [
        .package(name: "QuillUI", path: "$ROOT_DIR")$extra_package_dependencies
    ],
    targets: [
        .executableTarget(
            name: "$TARGET_NAME",
            dependencies: [
                .product(name: "SwiftUI", package: "QuillUI"),
                .product(name: "SwiftData", package: "QuillUI"),
                .product(name: "Combine", package: "QuillUI"),
                .product(name: "UniformTypeIdentifiers", package: "QuillUI"),
                .product(name: "OllamaKit", package: "QuillUI"),
                .product(name: "MarkdownUI", package: "QuillUI"),
                .product(name: "Splash", package: "QuillUI"),
                .product(name: "ActivityIndicatorView", package: "QuillUI"),
                .product(name: "WrappingHStack", package: "QuillUI"),
                .product(name: "Vortex", package: "QuillUI"),
                .product(name: "KeyboardShortcuts", package: "QuillUI"),
                .product(name: "Magnet", package: "QuillUI"),
                .product(name: "Carbon", package: "QuillUI"),
                .product(name: "AsyncAlgorithms", package: "QuillUI"),
                .product(name: "AppKit", package: "QuillUI"),
                .product(name: "AVFoundation", package: "QuillUI"),
                .product(name: "Speech", package: "QuillUI"),
                .product(name: "PhotosUI", package: "QuillUI"),
                .product(name: "UIKit", package: "QuillUI"),
                .product(name: "IOKit", package: "QuillUI"),
                .product(name: "Security", package: "QuillUI"),
                .product(name: "ServiceManagement", package: "QuillUI"),
                .product(name: "Sparkle", package: "QuillUI"),
                .product(name: "ApplicationServices", package: "QuillUI"),
                .product(name: "CoreGraphics", package: "QuillUI"),
                .product(name: "Alamofire", package: "QuillUI"),
                .product(name: "os", package: "QuillUI")
                $extra_target_dependencies
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
SWIFT

source_count="$(find "$SOURCE_COPY" -name '*.swift' | wc -l | tr -d ' ')"
generated_count="$(find "$TARGET_DIR" -name '*.swift' | wc -l | tr -d ' ')"

QUILLUI_SWIFT_PACKAGE_PATH="$PACKAGE_DIR" "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$WORK_ROOT/.build-check"

swift build \
  --package-path "$PACKAGE_DIR" \
  --scratch-path "$WORK_ROOT/.build-check" \
  --product "$PRODUCT_NAME"

cat <<MSG

Generated Enchanted full-source $MODE completed.
Source copied from:
  $UPSTREAM_DIR
Source Swift files copied: $source_count
Generated Swift files compiled: $generated_count
Product:
  $PRODUCT_NAME
Generated package:
  $PACKAGE_DIR

MSG
