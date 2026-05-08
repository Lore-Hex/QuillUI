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
PROFILE_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLING_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ ! -d "$LOWERED_COPY" ]]; then
  echo "Lowered Enchanted source directory was not found: $LOWERED_COPY" >&2
  exit 66
fi

"$TOOLING_DIR/ensure-swift-imports.sh" "$LOWERED_COPY" AppKit \
  Application/EnchantedApp.swift \
  Extensions/UIImage+Extension.swift \
  UI/macOS/Chat/Components/InputFields_macOS.swift \
  UI/macOS/Components/PromptPanelView.swift \
  UI/macOS/MenuBar/MenuBarControlView_macOS.swift \
  UI/Shared/Settings/SettingsView.swift

"$TOOLING_DIR/ensure-swift-imports.sh" "$LOWERED_COPY" SwiftUI \
  Services/Clipboard.swift \
  UI/Shared/Chat/Components/Recorder/SpeechRecogniser.swift

"$TOOLING_DIR/install-profile-templates.sh" "$PROFILE_DIR/templates" "$LOWERED_COPY"
"$TOOLING_DIR/apply-profile-rewrites.sh" "$LOWERED_COPY" "$PROFILE_DIR/rewrite-rules"
"$TOOLING_DIR/truncate-profile-files.sh" "$LOWERED_COPY" "$PROFILE_DIR/empty-files.txt"

"$TOOLING_DIR/generate-hashable-identity-shims.sh" \
  "$LOWERED_COPY/QuillGeneratedFullSourceShims.swift" \
  LanguageModelSD:name:id:String \
  ConversationSD:id \
  MessageSD:id \
  CompletionInstructionSD:id
