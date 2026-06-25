#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-enchanted-source.sh"

UPSTREAM_ROOT="$(quillui_resolve_enchanted_checkout_dir "$ROOT_DIR")"
UPSTREAM_DIR="$UPSTREAM_ROOT/Enchanted"
UPSTREAM_URL="https://github.com/gluonfield/enchanted.git"

if [[ ! -d "$UPSTREAM_DIR" ]]; then
  quillui_print_enchanted_source_missing "$UPSTREAM_DIR"
  exit 66
fi

if [[ -d "$UPSTREAM_ROOT/.git" ]]; then
  commit="$(git -C "$UPSTREAM_ROOT" log -1 --format='%h %cs %s')"
elif [[ -f "$UPSTREAM_ROOT/QUILLUI_VENDOR.md" ]]; then
  commit="$(sed -n 's/^- Commit: //p' "$UPSTREAM_ROOT/QUILLUI_VENDOR.md" | head -n 1)"
else
  commit="vendored source"
fi
swift_count="$(find "$UPSTREAM_DIR" -name '*.swift' | wc -l | tr -d ' ')"

cat <<MSG
# Upstream Enchanted Audit

Repository: $UPSTREAM_URL
Source: $UPSTREAM_ROOT
Commit: $commit
Swift files: $swift_count

## Non-Apple/Linux Port Import Inventory
MSG

for pattern in SwiftData AppKit UIKit AVFoundation Speech KeyboardShortcuts Magnet Carbon IOKit MarkdownUI Splash PhotosUI ActivityIndicatorView Vortex WrappingHStack OllamaKit AsyncAlgorithms; do
  count="$((rg --fixed-strings "import $pattern" "$UPSTREAM_DIR" -g '*.swift' || true) | wc -l | tr -d ' ')"
  if [[ "$count" != "0" ]]; then
    printf -- "- %s imports: %s\n" "$pattern" "$count"
  fi
done

cat <<'MSG'

## SwiftUI Surface To Keep Compatible
MSG

rg 'NavigationSplitView|ScrollViewReader|LazyVGrid|GridItem|@FocusState|fileImporter|onDrop|foregroundStyle|symbolEffect|confirmationDialog|contextMenu|ToolbarItem|Table\(' "$UPSTREAM_DIR" -g '*.swift' \
  | sed "s#$UPSTREAM_ROOT/##" \
  | sort
