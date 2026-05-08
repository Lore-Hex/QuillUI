#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${1:-$ROOT_DIR/.build-linux}"
PACKAGE_PATH="${QUILLUI_SWIFT_PACKAGE_PATH:-$ROOT_DIR}"
RENDERER="$SCRATCH_PATH/checkouts/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
SYMBOLS="$SCRATCH_PATH/checkouts/SwiftOpenUI/Sources/SwiftOpenUISymbols/SFSymbolCompatibility.swift"

if [[ ! -f "$RENDERER" || ! -f "$SYMBOLS" ]]; then
  swift package resolve --package-path "$PACKAGE_PATH" --scratch-path "$SCRATCH_PATH" >/dev/null
fi

if [[ ! -f "$RENDERER" ]]; then
  echo "SwiftOpenUI GTK renderer was not found at $RENDERER" >&2
  exit 1
fi

if [[ ! -f "$SYMBOLS" ]]; then
  echo "SwiftOpenUI symbol compatibility map was not found at $SYMBOLS" >&2
  exit 1
fi

perl -0pi \
  -e 's/css \+= " object-fit: contain;"/css += ""/g;' \
  -e 's/css \+= " object-fit: cover; overflow: hidden;"/css += " overflow: hidden;"/g;' \
  "$RENDERER"

if ! grep -Fq '"textformat.abc"' "$SYMBOLS"; then
  perl -0pi \
    -e 's/(        "calendar":\s+"calendar_today",\n)/$1        "character.cursor.ibeam": "text_fields",\n        "checkmark.square.fill":  "check_box",\n        "keyboard":               "keyboard",\n        "keyboard.fill":          "keyboard",\n        "lightbulb":              "lightbulb",\n        "lightbulb.circle":       "lightbulb",\n        "lightbulb.circle.fill":  "lightbulb",\n        "line.3.horizontal":      "menu",\n/;' \
    -e 's/(        "pencil":\s+"edit",\n)/$1        "paperplane.fill":       "send",\n/;' \
    -e 's/(        "plus.circle.fill":\s+"add_circle",\n)/$1        "photo":                 "image",\n        "photo.fill":            "image",\n/;' \
    -e 's/(        "square.and.arrow.up":\s+"share",\n)/$1        "selection.pin.in.out":  "select_all",\n        "space":                 "space_bar",\n        "sidebar.left":           "view_sidebar",\n        "speaker.slash.fill":    "volume_off",\n        "speaker.wave.2.fill":   "volume_up",\n        "speaker.wave.3":        "volume_up",\n        "speaker.wave.3.fill":   "volume_up",\n/;' \
    -e 's/(        "square.and.pencil":\s+"edit",\n)/$1        "square":                "check_box_outline_blank",\n        "square.fill":           "stop",\n        "stop.fill":             "stop",\n/;' \
    -e 's/(        "tag.fill":\s+"label",\n)/$1        "sun.max":               "light_mode",\n        "textformat":            "text_fields",\n        "textformat.abc":        "text_fields",\n        "water.waves":           "water",\n        "waveform":              "graphic_eq",\n/;' \
    -e 's/(        "xmark.circle.fill":\s+"cancel",\n)/$1        "x.circle.fill":         "cancel",\n/;' \
    "$SYMBOLS"
fi
