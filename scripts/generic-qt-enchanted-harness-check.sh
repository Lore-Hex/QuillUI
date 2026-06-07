#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/.qa/quill-generic-qt-enchanted-harness.png}"
SUMMARY_PATH="${2:-$ROOT_DIR/.qa/quill-generic-qt-enchanted-harness.txt}"
CXX="${CXX:-clang++}"
SETTLE_SECONDS="${QUILLUI_GENERIC_QT_HARNESS_SETTLE_SECONDS:-3}"
HARNESS_MODE="${QUILLUI_GENERIC_QT_HARNESS_MODE:-home}"
VERIFY_PRODUCT="quill-enchanted-linux-qt"

case "$HARNESS_MODE" in
  home)
    VERIFY_PRODUCT="quill-enchanted-linux-qt"
    ;;
  selected-chat|list-selection)
    VERIFY_PRODUCT="quill-enchanted-linux-qt-selected-chat"
    ;;
  *)
    echo "Unsupported generic Qt Enchanted harness mode: $HARNESS_MODE" >&2
    exit 64
    ;;
esac

if ! command -v "$CXX" >/dev/null 2>&1; then
  echo "C++ compiler is required: $CXX" >&2
  exit 69
fi

for required_command in pkg-config xvfb-run import python3; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "$required_command is required for the generic Qt Enchanted harness" >&2
    exit 69
  fi
done

pkg-config --exists Qt6Widgets
mkdir -p "$(dirname "$OUTPUT_PATH")" "$(dirname "$SUMMARY_PATH")"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quill-generic-qt-harness.XXXXXX")"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

HARNESS_CPP="$TEMP_DIR/quill_generic_qt_enchanted_harness.cpp"
HARNESS_BIN="$TEMP_DIR/quill-generic-qt-enchanted-harness"

cat >"$HARNESS_CPP" <<'CPP'
#include "CQuillQt6WidgetsShim.h"

#include <cstdlib>
#include <cstring>

int main(int argc, char **argv) {
    static const char homePayload[] = R"JSON({
        "windowTitle":"Quill Chat",
        "minimumWidth":1080,
        "minimumHeight":700,
        "defaultWidth":1180,
        "defaultHeight":760,
        "sidebarWidth":320,
        "detailWidth":860,
        "presentation":"chat",
        "selectedIndex":-1,
        "items":[
            {"title":"Auto-config test: reply with one sho...","subtitle":"","badge":"3 days ago","height":76},
            {"title":"say one short word","subtitle":"","height":44},
            {"title":"say hi in one word","subtitle":"","height":54},
            {"title":"Write a text message asking a frien...","subtitle":"","badge":"4 days ago","height":82},
            {"title":"Give me phrases to learn in a new la...","subtitle":"","badge":"7 days ago","height":82},
            {"title":"How to center div in HTML?","subtitle":"","height":50}
        ],
        "emptyStateTitle":"Quill",
        "prompts":[
            {"title":"How to center div in HTML?","systemImage":"questionmark.circle"},
            {"title":"How to do personal taxes in USA?","systemImage":"questionmark.circle"},
            {"title":"Explain supercomputers like I am five years old","systemImage":"lightbulb.circle"},
            {"title":"Write a text message asking a friend to be my plus-one at a wedding","systemImage":"lightbulb.circle"}
        ],
        "bottomNavigation":[
            {"title":"Completions","systemImage":"textformat.abc"},
            {"title":"Shortcuts","systemImage":"keyboard.fill"},
            {"title":"Settings","systemImage":"gearshape.fill"}
        ],
        "composerPlaceholder":"Message",
        "noticeTitle":"Quill is unreachable.",
        "noticeBody":"Plug Quill back in if it is unplugged, or go to Settings and update your Quill API endpoint.",
        "noticeActionTitle":"Settings",
        "style":{
            "canvasColor":"#F7F8F4",
            "sidebarColor":"#EEF2EA",
            "headerColor":"#F7F8F4",
            "promptCardColor":"#F1F1F5",
            "noticeColor":"#F8D7DA",
            "inkColor":"#202124",
            "mutedColor":"#8E9199",
            "primaryColor":"#2F80ED",
            "controlBorderColor":"#C8CFC8",
            "dividerColor":"#D8DDD4",
            "emptyStateWordmarkFontSize":46,
            "emptyStateWordmarkFontWeight":100,
            "conversationTitleFontSize":15,
            "sectionTitleFontSize":15,
            "promptGridColumns":4,
            "promptCardWidth":160,
            "promptCardHeight":128,
            "promptGridWidth":760,
            "composerMinWidth":620,
            "composerMaxWidth":800
        }
    })JSON";

    static const char selectedChatPayload[] = R"JSON({
        "windowTitle":"Quill Chat",
        "minimumWidth":1080,
        "minimumHeight":700,
        "defaultWidth":1180,
        "defaultHeight":760,
        "sidebarWidth":320,
        "detailWidth":860,
        "presentation":"chat",
        "selectedIndex":5,
        "items":[
            {"title":"Auto-config test: reply with one sho...","subtitle":"","badge":"3 days ago","height":76},
            {"title":"say one short word","subtitle":"","height":44},
            {"title":"say hi in one word","subtitle":"","height":54},
            {"title":"Write a text message asking a frien...","subtitle":"","badge":"4 days ago","height":82},
            {"title":"Give me phrases to learn in a new la...","subtitle":"","badge":"7 days ago","height":82},
            {
                "title":"How to center div in HTML?",
                "subtitle":"",
                "height":50,
                "detailSubtitle":"Selected prompt conversation.",
                "messages":[
                    {"role":"user","content":"How to center div in HTML?"},
                    {"role":"assistant","content":"Use flexbox on the parent: display: flex; justify-content: center; align-items: center."}
                ]
            }
        ],
        "emptyStateTitle":"Quill",
        "prompts":[
            {"title":"How to center div in HTML?","systemImage":"questionmark.circle"},
            {"title":"How to do personal taxes in USA?","systemImage":"questionmark.circle"},
            {"title":"Explain supercomputers like I am five years old","systemImage":"lightbulb.circle"},
            {"title":"Write a text message asking a friend to be my plus-one at a wedding","systemImage":"lightbulb.circle"}
        ],
        "bottomNavigation":[
            {"title":"Completions","systemImage":"textformat.abc"},
            {"title":"Shortcuts","systemImage":"keyboard.fill"},
            {"title":"Settings","systemImage":"gearshape.fill"}
        ],
        "composerPlaceholder":"Message",
        "noticeTitle":"Quill is unreachable.",
        "noticeBody":"Plug Quill back in if it is unplugged, or go to Settings and update your Quill API endpoint.",
        "noticeActionTitle":"Settings",
        "style":{
            "canvasColor":"#F7F8F4",
            "sidebarColor":"#EEF2EA",
            "headerColor":"#F7F8F4",
            "promptCardColor":"#F1F1F5",
            "noticeColor":"#F8D7DA",
            "inkColor":"#202124",
            "mutedColor":"#8E9199",
            "primaryColor":"#2F80ED",
            "controlBorderColor":"#C8CFC8",
            "dividerColor":"#D8DDD4",
            "emptyStateWordmarkFontSize":46,
            "emptyStateWordmarkFontWeight":100,
            "conversationTitleFontSize":15,
            "sectionTitleFontSize":15,
            "promptGridColumns":4,
            "promptCardWidth":160,
            "promptCardHeight":128,
            "promptGridWidth":760,
            "composerMinWidth":620,
            "composerMaxWidth":800
        }
    })JSON";

    const char *mode = std::getenv("QUILLUI_GENERIC_QT_HARNESS_MODE");
    const char *payload = (mode != nullptr && std::strcmp(mode, "home") != 0)
        ? selectedChatPayload
        : homePayload;
    return quill_generic_qt_run_app_json(argc, argv, payload);
}
CPP

"$CXX" -std=c++17 -fPIC \
  -I"$ROOT_DIR/Sources/CQuillQt6WidgetsShim/include" \
  -I"$ROOT_DIR/Sources/CQuillQt6WidgetsShim" \
  -I"$ROOT_DIR/Sources/CQt6Widgets" \
  $(pkg-config --cflags Qt6Widgets) \
  "$ROOT_DIR/Sources/CQuillQt6WidgetsShim/QuillGenericQt6Widgets.cpp" \
  "$HARNESS_CPP" \
  $(pkg-config --libs Qt6Widgets) \
  -o "$HARNESS_BIN"

xvfb-run -a -s "-screen 0 1180x760x24" bash -c '
set -euo pipefail
app="$1"
output_path="$2"
root_dir="$3"
summary_path="$4"
settle_seconds="$5"
verify_product="$6"
harness_mode="$7"
app_log="${summary_path%.txt}.log"

QUILLUI_GENERIC_QT_HARNESS_MODE="$harness_mode" "$app" >"$app_log" 2>&1 &
app_pid=$!
cleanup_app() {
  kill "$app_pid" >/dev/null 2>&1 || true
  wait "$app_pid" >/dev/null 2>&1 || true
}
trap cleanup_app EXIT

sleep "$settle_seconds"
import -window root "$output_path"
python3 "$root_dir/scripts/verify-backend-screenshot.py" "$output_path" "$verify_product" | tee "$summary_path"
' bash "$HARNESS_BIN" "$OUTPUT_PATH" "$ROOT_DIR" "$SUMMARY_PATH" "$SETTLE_SECONDS" "$VERIFY_PRODUCT" "$HARNESS_MODE"
