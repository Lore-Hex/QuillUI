#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="$ROOT_DIR/.upstream/enchanted"
UPSTREAM_URL="https://github.com/gluonfield/enchanted.git"

mkdir -p "$ROOT_DIR/.upstream"

if [[ -d "$UPSTREAM_DIR/.git" ]]; then
  git -C "$UPSTREAM_DIR" fetch --depth=1 origin main >/dev/null
  git -C "$UPSTREAM_DIR" reset --hard FETCH_HEAD >/dev/null
else
  git clone --depth=1 "$UPSTREAM_URL" "$UPSTREAM_DIR" >/dev/null
fi

commit="$(git -C "$UPSTREAM_DIR" log -1 --format='%h %cs %s')"
swift_count="$(find "$UPSTREAM_DIR/Enchanted" -name '*.swift' | wc -l | tr -d ' ')"

cat <<MSG
# Upstream Enchanted Audit

Repository: $UPSTREAM_URL
Commit: $commit
Swift files: $swift_count

## Non-Apple/Linux Port Import Inventory
MSG

for pattern in SwiftData AppKit UIKit AVFoundation Speech KeyboardShortcuts Magnet Carbon MarkdownUI Splash PhotosUI ActivityIndicatorView Vortex WrappingHStack OllamaKit AsyncAlgorithms; do
  count="$(rg --fixed-strings "import $pattern" "$UPSTREAM_DIR/Enchanted" -g '*.swift' | wc -l | tr -d ' ')"
  if [[ "$count" != "0" ]]; then
    printf -- "- %s imports: %s\n" "$pattern" "$count"
  fi
done

cat <<'MSG'

## SwiftUI Surface To Keep Compatible
MSG

rg 'NavigationSplitView|ScrollViewReader|LazyVGrid|GridItem|@FocusState|fileImporter|onDrop|foregroundStyle|symbolEffect|confirmationDialog|contextMenu|ToolbarItem|Table\(' "$UPSTREAM_DIR/Enchanted" -g '*.swift' \
  | sed "s#$UPSTREAM_DIR/##" \
  | sort
