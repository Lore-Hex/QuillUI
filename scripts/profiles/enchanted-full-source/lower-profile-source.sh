#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  cat >&2 <<'MSG'
Usage: scripts/profiles/enchanted-full-source/lower-profile-source.sh GENERATED_SOURCE_DIR

Applies Enchanted/Quill Chat-specific source-shape lowering after the shared
SwiftData and SwiftUI lowering helpers have run.
MSG
  exit 64
fi

LOWERED_COPY="$1"

if [[ ! -d "$LOWERED_COPY" ]]; then
  echo "Lowered Enchanted source directory was not found: $LOWERED_COPY" >&2
  exit 66
fi

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

sidebar_button="$LOWERED_COPY/UI/Shared/Sidebar/Components/SidebarButton.swift"
if [[ -f "$sidebar_button" ]]; then
  cat > "$sidebar_button" <<'SWIFT'
//
//  SidebarButton.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct SidebarButton: View {
    var title: String
    var image: String
    var onClick: () -> ()

    var body: some View {
        QuillSidebarNavigationButton(title: title, systemImage: image, action: onClick)
    }
}
SWIFT
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

empty_conversation_view="$LOWERED_COPY/UI/Shared/Chat/Components/EmptyConversaitonView.swift"
if [[ -f "$empty_conversation_view" ]]; then
  cat > "$empty_conversation_view" <<'SWIFT'
//
//  EmptyConversaitonView.swift
//  Enchanted
//

import SwiftUI
import QuillUI

struct EmptyConversaitonView: View, KeyboardReadable {
    var sendPrompt: (String) -> Void

    private var prompts: [QuillPrompt] {
        SamplePrompts.samples.prefix(4).map { sample in
            QuillPrompt(
                id: sample.id,
                title: sample.prompt,
                systemImage: sample.type.icon
            )
        }
    }

    var body: some View {
        QuillChatEmptyState(
            brandTitle: "Quill",
            prompts: prompts,
            columns: 4,
            cardWidth: 155,
            cardHeight: 128,
            spacing: 15
        ) { prompt in
            sendPrompt(prompt.title)
        }
    }
}
SWIFT
fi

chat_view_macos="$LOWERED_COPY/UI/macOS/Chat/ChatView_macOS.swift"
if [[ -f "$chat_view_macos" ]]; then
  cat > "$chat_view_macos" <<'SWIFT'
//
//  Chat.swift
//  Enchanted
//

#if os(macOS) || os(Linux) || os(visionOS)
import SwiftUI
import QuillUI

struct ChatView: View {
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var messages: [MessageSD]
    var modelsList: [LanguageModelSD]
    var onMenuTap: () -> Void
    var onNewConversationTap: () -> Void
    var onSendMessageTap: (_ prompt: String, _ model: LanguageModelSD, _ image: Image?, _ trimmingMessageId: String?) -> Void
    var onConversationTap: (_ conversation: ConversationSD) -> Void
    var conversationState: ConversationState
    var onStopGenerateTap: () -> Void
    var reachable: Bool
    var modelSupportsImages: Bool
    var selectedModel: LanguageModelSD?
    var onSelectModel: (_ model: LanguageModelSD?) -> Void
    var onConversationDelete: (_ conversation: ConversationSD) -> Void
    var onDeleteDailyConversations: (_ date: Date) -> Void
    var userInitials: String
    var copyChat: (_ json: Bool) -> Void

    @State private var message = ""
    @State private var editMessage: MessageSD?
    @FocusState private var isFocusedInput: Bool

    private var modelMenuActions: [QuillMenuAction] {
        if modelsList.isEmpty {
            return [
                QuillMenuAction(title: "No models available", isDisabled: true) {}
            ]
        }

        return modelsList.map { model in
            let title = model.prettyVersion.isEmpty ? model.prettyName : "\(model.prettyName) \(model.prettyVersion)"
            let icon = selectedModel?.name == model.name ? "checkmark" : nil
            return QuillMenuAction(id: model.name, title: title, systemImage: icon) {
                onSelectModel(model)
            }
        }
    }

    private var optionsMenuActions: [QuillMenuAction] {
        [
            QuillMenuAction(title: "Copy Chat", systemImage: "doc.on.doc") {
                copyChat(false)
            },
            QuillMenuAction(title: "Copy Chat as JSON", systemImage: "curlybraces") {
                copyChat(true)
            }
        ]
    }

    var body: some View {
        QuillDesktopSplitLayout(title: "Quill Chat", sidebarWidth: 320) {
            SidebarView(
                selectedConversation: selectedConversation,
                conversations: conversations,
                onConversationTap: onConversationTap,
                onConversationDelete: onConversationDelete,
                onDeleteDailyConversations: onDeleteDailyConversations
            )
        } toolbar: {
            QuillToolbarActionRow {
                QuillToolbarMenuButton(
                    systemImage: "chevron.down",
                    menuWidth: 220,
                    actions: modelMenuActions
                )

                QuillToolbarMenuButton(
                    systemImage: "ellipsis",
                    showsChevron: true,
                    width: 42,
                    menuWidth: 180,
                    actions: optionsMenuActions
                )

                QuillToolbarIconButton(systemImage: "square.and.pencil", action: onNewConversationTap)
            }
        } content: {
            VStack(alignment: .center, spacing: 0) {
                if selectedConversation != nil {
                    MessageListView(
                        messages: messages,
                        conversationState: conversationState,
                        userInitials: userInitials,
                        editMessage: $editMessage
                    )
                } else {
                    EmptyConversaitonView(sendPrompt: { selectedMessage in
                        if let selectedModel = selectedModel {
                            onSendMessageTap(selectedMessage, selectedModel, nil, nil)
                        }
                    })
                }

                if !reachable {
                    UnreachableAPIView()
                }

                InputFieldsView(
                    message: $message,
                    conversationState: conversationState,
                    onStopGenerateTap: onStopGenerateTap,
                    selectedModel: selectedModel,
                    onSendMessageTap: onSendMessageTap,
                    editMessage: $editMessage
                )
                .padding()
                .frame(width: 800)
            }
        }
        .onChange(of: editMessage, initial: false) { _, newMessage in
            if let newMessage = newMessage {
                message = newMessage.content
                isFocusedInput = true
            }
        }
    }
}
#endif
SWIFT
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
