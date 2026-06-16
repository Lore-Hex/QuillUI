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

"$TOOLING_DIR/install-profile-templates.sh" "$PROFILE_DIR/templates" "$LOWERED_COPY"

# Enchanted / Quill Chat builds against the headless single-threaded GTK backend,
# so it opts into actor-isolation stripping (`stripActorIsolation: true`). This is
# the first-class replacement for the per-app Perl actor/await/nonisolated rewrite
# rules under rewrite-rules/. It runs *before* apply-profile-rewrites so the
# still-present .pl rules are idempotent no-ops on the already-lowered source
# (belt-and-suspenders until the Perl removal clears an equivalence check).
"$TOOLING_DIR/run-quill-actor-isolation-lower.sh" "$LOWERED_COPY"

"$TOOLING_DIR/apply-profile-rewrites.sh" "$LOWERED_COPY" "$PROFILE_DIR/rewrite-rules"

clipboard_file="$LOWERED_COPY/Services/Clipboard.swift"
if [[ -f "$clipboard_file" ]]; then
  perl -0pi -e '
    s/#if os\(macOS\)\nimport AppKit\n#else\nimport UIKit\n#endif/#if os(macOS) || os(Linux)\nimport AppKit\n#else\nimport UIKit\n#endif/;
    s/#elseif os\(macOS\)/#elseif os(macOS) || os(Linux)/g;
  ' "$clipboard_file"
fi

"$TOOLING_DIR/truncate-profile-files.sh" "$LOWERED_COPY" "$PROFILE_DIR/empty-files.txt"

"$TOOLING_DIR/generate-hashable-identity-shims.sh" \
  "$LOWERED_COPY/QuillGeneratedFullSourceShims.swift" \
  LanguageModelSD:name:id:String \
  ConversationSD:id \
  MessageSD:id \
  CompletionInstructionSD:id
