#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-enchanted-backend.png}"
PRODUCT="${2:-quill-enchanted}"
APP_EXECUTABLE=""

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

quillui_alias_backend_visual_env

quillui_install_linux_backend_smoke_packages

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

quillui_resolve_linux_backend_executable "$PRODUCT" APP_EXECUTABLE

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Built executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

reference_window_width=""
reference_window_height=""
hide_window_menubar_label=""
quillui_backend_reference_window_defaults \
  reference_window_width \
  reference_window_height \
  hide_window_menubar_label

DISPLAY_ID="$(quillui_normalize_x_display_id "${QUILLUI_BACKEND_VISUAL_DISPLAY:-:94}")"
SCREEN_SIZE="$(
  quillui_backend_screen_size \
    "$PRODUCT" \
    "${QUILLUI_BACKEND_VISUAL_SCREEN_SIZE:-${QUILLUI_BACKEND_SCREEN_SIZE:-}}" \
    "1180x760x24" \
    "$reference_window_width" \
    "$reference_window_height"
)"
xvfb_pid=""
quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" /tmp/quillui-xvfb.log xvfb_pid

cleanup() {
  quillui_stop_process_if_running "${app_pid:-}"
  quillui_stop_process_if_running "$xvfb_pid"
}
trap cleanup EXIT

app_environment=()
quillui_append_backend_launch_environment app_environment "$PRODUCT" "$DISPLAY_ID"
quillui_append_backend_layout_debug_environment app_environment "${QUILLUI_BACKEND_LAYOUT_DEBUG:-}"
quillui_append_quill_chat_reference_environment_if_needed \
  app_environment \
  "$PRODUCT" \
  "$OUTPUT_DIR" \
  "$reference_window_width" \
  "$reference_window_height" \
  "$hide_window_menubar_label"
env "${app_environment[@]}" "$APP_EXECUTABLE" >/tmp/quillui-backend-app.log 2>&1 &
app_pid=$!

sleep 4
capture_window="root"
if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
  window_id="$(quillui_find_quill_chat_reference_window "$DISPLAY_ID")"
  if [[ -n "$window_id" ]]; then
    quillui_place_reference_window "$DISPLAY_ID" "$window_id" "$reference_window_width" "$reference_window_height"
    capture_window="$window_id"
  fi
fi
DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"

VERIFY_PRODUCT=""
quillui_backend_visual_verify_product "$PRODUCT" VERIFY_PRODUCT
"$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"
