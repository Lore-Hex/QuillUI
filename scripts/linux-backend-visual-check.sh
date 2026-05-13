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

reference_window_width="${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}"
reference_window_height="${QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT:-1380}"
hide_window_menubar_label="${QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL:-1}"

DISPLAY_ID="$(quillui_normalize_x_display_id "${QUILLUI_BACKEND_VISUAL_DISPLAY:-:94}")"
SCREEN_SIZE="$(quillui_backend_screen_size "$PRODUCT" "${QUILLUI_BACKEND_SCREEN_SIZE:-}" "1180x760x24" "$reference_window_width" "$reference_window_height")"
xvfb_pid=""
quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" /tmp/quillui-xvfb.log xvfb_pid

cleanup() {
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  kill "$xvfb_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

app_environment=()
quillui_append_backend_launch_environment app_environment "$PRODUCT" "$DISPLAY_ID"
if [[ -n "${QUILLUI_BACKEND_LAYOUT_DEBUG:-}" ]]; then
  app_environment+=(
    QUILLUI_BACKEND_LAYOUT_DEBUG="$QUILLUI_BACKEND_LAYOUT_DEBUG"
    QUILLUI_GTK_LAYOUT_DEBUG="$QUILLUI_BACKEND_LAYOUT_DEBUG"
  )
fi
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
  window_id="$(
    DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --name 'Quill Chat' 2>/dev/null | head -n 1 || true
  )"
  if [[ -z "$window_id" ]]; then
    window_id="$(
      DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --name '.*' 2>/dev/null | head -n 1 || true
    )"
  fi
  if [[ -n "$window_id" ]]; then
    DISPLAY="$DISPLAY_ID" xdotool windowmove "$window_id" 0 0
    DISPLAY="$DISPLAY_ID" xdotool windowsize "$window_id" "$reference_window_width" "$reference_window_height"
    capture_window="$window_id"
    sleep 1
  fi
fi
DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"

VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-$PRODUCT}"
if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
  VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference}"
fi
"$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"
