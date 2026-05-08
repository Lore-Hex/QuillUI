#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${1:-$ROOT_DIR/.build-linux}"
RENDERER="$SCRATCH_PATH/checkouts/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"

if [[ ! -f "$RENDERER" ]]; then
  swift package resolve --scratch-path "$SCRATCH_PATH" >/dev/null
fi

if [[ ! -f "$RENDERER" ]]; then
  echo "SwiftOpenUI GTK renderer was not found at $RENDERER" >&2
  exit 1
fi

perl -0pi \
  -e 's/css \+= " object-fit: contain;"/css += ""/g;' \
  -e 's/css \+= " object-fit: cover; overflow: hidden;"/css += " overflow: hidden;"/g;' \
  "$RENDERER"
