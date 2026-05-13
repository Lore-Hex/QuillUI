#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-enchanted-gtk.png}"
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

is_quill_chat_mac_reference() {
  [[ "$PRODUCT" == "quill-chat-linux" && "${QUILLUI_GTK_MAC_REFERENCE:-0}" == "1" ]]
}

reference_window_width="${QUILLUI_GTK_DEFAULT_WINDOW_WIDTH:-2048}"
reference_window_height="${QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT:-1380}"
hide_window_menubar_label="${QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL:-1}"

DISPLAY_ID="${QUILLUI_GTK_VISUAL_DISPLAY:-:94}"
SCREEN_SIZE="${QUILLUI_GTK_SCREEN_SIZE:-1180x760x24}"
if is_quill_chat_mac_reference; then
  SCREEN_SIZE="${QUILLUI_GTK_SCREEN_SIZE:-${reference_window_width}x${reference_window_height}x24}"
fi
Xvfb "$DISPLAY_ID" -screen 0 "$SCREEN_SIZE" >/tmp/quillui-xvfb.log 2>&1 &
xvfb_pid=$!

cleanup() {
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  kill "$xvfb_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 1
if ! kill -0 "$xvfb_pid" >/dev/null 2>&1; then
  cat /tmp/quillui-xvfb.log >&2 || true
  exit 70
fi
app_environment=(GTK_A11Y=none DISPLAY="$DISPLAY_ID")
requested_backend="$(quillui_requested_backend_for_product "$PRODUCT")"
if [[ -n "$requested_backend" ]]; then
  app_environment+=(QUILLUI_BACKEND="$requested_backend")
fi
if [[ -n "${QUILLUI_GTK_LAYOUT_DEBUG:-}" ]]; then
  app_environment+=(QUILLUI_GTK_LAYOUT_DEBUG="$QUILLUI_GTK_LAYOUT_DEBUG")
fi
if is_quill_chat_mac_reference; then
  quill_chat_reference_home="$OUTPUT_DIR/quill-chat-linux-reference-home"
  quillui_seed_quill_chat_reference_data "$quill_chat_reference_home"
  app_environment+=(
    HOME="$quill_chat_reference_home"
    QUILLDATA_HOME="$quill_chat_reference_home"
    QUILLUI_GTK_DEFAULT_WINDOW_WIDTH="$reference_window_width"
    QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT="$reference_window_height"
    QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL="$hide_window_menubar_label"
    QUILLUI_QUILL_CHAT_REFERENCE_MODE=1
    QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1
  )
fi
env "${app_environment[@]}" "$APP_EXECUTABLE" >/tmp/quillui-gtk-app.log 2>&1 &
app_pid=$!

sleep 4
capture_window="root"
if is_quill_chat_mac_reference; then
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

VERIFY_PRODUCT="${QUILLUI_GTK_VERIFY_PRODUCT:-$PRODUCT}"
if is_quill_chat_mac_reference; then
  VERIFY_PRODUCT="${QUILLUI_GTK_VERIFY_PRODUCT:-quill-chat-linux-mac-reference}"
fi
"$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"
