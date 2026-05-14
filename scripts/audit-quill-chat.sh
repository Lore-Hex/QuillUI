#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUILL_CHAT_DIR="${QUILL_CHAT_DIR:-$ROOT_DIR/../quill/clients/quill-chat}"
APP_DIR="$QUILL_CHAT_DIR/Enchanted"

if [[ ! -d "$APP_DIR" ]]; then
  cat >&2 <<MSG
Quill Chat source was not found at:
  $APP_DIR

Set QUILL_CHAT_DIR=/path/to/quill/clients/quill-chat and rerun.
MSG
  exit 1
fi

count_fixed() {
  local pattern="$1"
  (rg --fixed-strings "$pattern" "$APP_DIR" -g '*.swift' || true) | wc -l | tr -d ' '
}

count_regex() {
  local pattern="$1"
  (rg "$pattern" "$APP_DIR" -g '*.swift' || true) | wc -l | tr -d ' '
}

swift_files="$(find "$APP_DIR" -name '*.swift' | wc -l | tr -d ' ')"
swift_loc="$(find "$APP_DIR" -name '*.swift' -print0 | xargs -0 wc -l | tail -1 | awk '{print $1}')"
commit="$(git -C "$QUILL_CHAT_DIR" log -1 --format='%h %cs %s' 2>/dev/null || true)"
status="$(git -C "$QUILL_CHAT_DIR" status --short --branch 2>/dev/null || true)"
prototype_slice="$ROOT_DIR/Sources/QuillEnchantedUpstreamSlice/main.swift"
prototype_lines="n/a"
if [[ -f "$prototype_slice" ]]; then
  prototype_lines="$(wc -l < "$prototype_slice" | tr -d ' ')"
fi

cat <<MSG
# Quill Chat Compatibility Audit

Source: $QUILL_CHAT_DIR
Commit: ${commit:-unknown}
Swift files: $swift_files
Swift LOC: $swift_loc

## Git State

\`\`\`
$status
\`\`\`

## App-Side Change Budget

- Target app-side compatibility shim: <= 100 lines.
- Current Quill Chat working tree changes: $(git -C "$QUILL_CHAT_DIR" diff --shortstat 2>/dev/null || echo "unknown")
- Current QuillUI prototype slice lines: $prototype_lines
- Generated real-source core check: \`scripts/generated-enchanted-core-check.sh\` compiles upstream Models, Stores, SwiftData models, Ollama/SwiftData services, and the ModelContext extension through QuillUI/QuillData on Linux.
- Generated real-source chat-components check: \`scripts/generated-enchanted-chat-components-check.sh\` compiles the shared chat message, empty state, status, model picker, image, menu, speech, clipboard, Markdown, Splash, and button components through QuillUI/QuillData on Linux.
- Generated real-source macOS-chat check: \`scripts/generated-enchanted-macos-chat-check.sh\` compiles the real upstream \`UI/macOS/Chat\` path, including ChatView, InputFields, toolbar, recorder, unreachable banner, and DragAndDrop.
- Generated real-source full-source check: \`scripts/generated-enchanted-full-source-check.sh\` copies all upstream Enchanted Swift files and compiles 87/87 through QuillUI/QuillData/QuillKit compatibility products with generated Linux-only lowering and bridges.
- Generated local Quill Chat full-source check: \`ENCHANTED_SOURCE_DIR="$APP_DIR" QUILLUI_GENERATED_ENCHANTED_FULL_WORKDIR=/tmp/quill-chat-full-source-check scripts/generated-enchanted-full-source-check.sh\` copies this $swift_files-file Quill Chat tree and compiles it through the same generated Linux path.
- Generated Linux app build: \`scripts/build-swiftui-linux-app.sh --profile enchanted-full-source --source-dir "$APP_DIR" --app-type EnchantedApp --product-name quill-chat-linux\` is the generic build entry point; generated app launchers can use the backend-neutral QuillUI entry, QuillUIGtk, or the native QuillGenericQtNativeRuntime host; profiles are discovered from \`scripts/profiles/*.sh\`; \`scripts/build-quill-chat-linux.sh\` is only a convenience wrapper for this app.
- Interpretation: the prototype slice is scaffolding, not the desired port shape. The generated app build is now the replacement path, with an app-side shim budget of 0 committed source lines.

## Imports

MSG

for module in SwiftUI SwiftData UniformTypeIdentifiers Combine AppKit UIKit AVFoundation Speech KeyboardShortcuts Magnet Carbon ApplicationServices CoreGraphics IOKit PhotosUI Security ServiceManagement Sparkle MarkdownUI Splash ActivityIndicatorView Vortex WrappingHStack OllamaKit Alamofire AsyncAlgorithms os; do
  hits="$(count_regex "^import ${module}$")"
  if [[ "$hits" != "0" ]]; then
    printf -- "- %s: %s\n" "$module" "$hits"
  fi
done

cat <<'MSG'

## Compatibility Surface

| Surface | Hits | Status | Next action |
| --- | ---: | --- | --- |
MSG

row() {
  local label="$1"
  local pattern="$2"
  local status="$3"
  local next="$4"
  local hits
  hits="$(count_regex "$pattern")"
  printf '| %s | %s | %s | %s |\n' "$label" "$hits" "$status" "$next"
}

row '@AppStorage' '@AppStorage' 'covered' 'Keep API-compatible persistence keys.'
row '@Observable' '@Observable|ObservableObject|@StateObject' 'partial' 'Prefer real Observation on Linux where available; shim legacy ObservableObject where SwiftOpenUI needs it.'
row '@Environment/openWindow/focused values' '@Environment|openWindow|focusedSceneValue|@FocusedValue' 'covered' 'SwiftOpenUI provides openWindow/@FocusedValue; QuillUI adds focusedSceneValue alias.'
row 'NavigationSplitView' 'NavigationSplitView|NavigationSplitViewVisibility' 'covered' 'Keep testing split view against GTK.'
row 'Toolbar/menu APIs' '\.toolbar|ToolbarItem|ToolbarItemGroup|Menu\b|Label\(|CommandGroup|\.commands' 'partial-real' 'CommandGroup placement aliases, menu label/content builders, toolbar group aliases, and Button command extraction compile; refine native GTK menu rendering and shortcut metadata.'
row 'Forms/input styles' 'Form\b|Section\(|Picker\(|\.pickerStyle|\.formStyle|textContentType|disableAutocorrection|keyboardType|autocapitalization|TextFieldStyle' 'partial-real' 'SwiftUI-shaped picker/form/text-field style calls compile; map more styles to native GTK controls as they become visible.'
row 'Sheets/dialogs/context menus' '\.sheet|confirmationDialog|contextMenu' 'partial' 'Compile first; wire native GTK behavior where visible.'
row 'Grid/table layout' 'LazyVGrid|GridItem|Grid\b|Table\(' 'partial-real' 'QuillUI now includes source-compatible Table/LabeledContent shims; improve visual table rendering for NetNewsWire.'
row 'File/drop APIs' 'fileImporter|onDrop|NSItemProvider|UTType' 'partial-real' 'File URL/data drops and test/env/desktop-command imports work; replace command picker with a native GTK picker when exposed.'
row 'Visual effects' 'foregroundStyle|LinearGradient|Material|symbolEffect|matchedGeometryEffect|ViewThatFits|safeAreaInset|@Namespace' 'partial-real' 'Color/gradient foregrounds, material fallbacks, shape masks, symbolEffect, and matchedGeometryEffect now have visible approximations; exact animation parity remains future native work.'
row 'SwiftData model layer' '@Model|@Attribute|@Relationship|ModelContainer|ModelContext|FetchDescriptor|SortDescriptor|#Predicate' 'partial-real' 'QuillData covers runtime types, hasChanges, class identity-map saves, id/name/slug identity, class-safe QuillPredicate, optional wrapper defaults, and a generated-source lowering script for @Model/@Transient/#Predicate; promote that into a macro or build plugin.'
row 'Apple platform services' 'AppKit|UIKit|AVFoundation|Speech|KeyboardShortcuts|Magnet|Carbon|ApplicationServices|CoreGraphics|IOKit|PhotosUI|Security|ServiceManagement|Sparkle|Alamofire|import os' 'partial-real' 'QuillKit now owns Linux module shells with diagnostic/emulated adapters for several Apple service imports; AppKit/KeyboardShortcuts/os.Logger cover the full-source Quill Chat shape; Carbon is an explicit unavailable shell; IOKit and IOKit.usb import through a compile shell while native USB/device events remain a separate backend gap.'
row 'Third-party UI packages' 'MarkdownUI|Splash|ActivityIndicatorView|Vortex|WrappingHStack|OllamaKit|AsyncAlgorithms|Alamofire' 'partial-real' 'ActivityIndicatorView, MarkdownUI, Splash, Vortex, WrappingHStack, AsyncAlgorithms, Alamofire, and OllamaKit have Linux compatibility modules; OllamaKit has real HTTP-backed model/reachability/chat behavior plus the Quill Chat session initializer shape; improve Markdown visual fidelity against real message views next.'

cat <<'MSG'

## High-Signal Files

MSG

for file in \
  "$APP_DIR/UI/Shared/ApplicationEntry.swift" \
  "$APP_DIR/UI/Shared/Sidebar/SidebarView.swift" \
  "$APP_DIR/UI/Shared/Sidebar/Components/ConversationHistoryListView.swift" \
  "$APP_DIR/UI/macOS/Chat/ChatView_macOS.swift" \
  "$APP_DIR/UI/macOS/Chat/Components/InputFields_macOS.swift" \
  "$APP_DIR/UI/Shared/Chat/Components/EmptyConversaitonView.swift" \
  "$APP_DIR/UI/Shared/Chat/Components/ConversationStatusView.swift" \
  "$APP_DIR/UI/Shared/Chat/Components/Recorder/RecordingView.swift" \
  "$APP_DIR/Services/SwiftDataService.swift"
do
  if [[ -f "$file" ]]; then
    printf -- "- %s (%s lines)\n" "${file#$QUILL_CHAT_DIR/}" "$(wc -l < "$file" | tr -d ' ')"
  fi
done
