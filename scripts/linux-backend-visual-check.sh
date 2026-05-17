#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-enchanted-backend.png}"
PRODUCT="${2:-quill-enchanted}"
REQUESTED_BACKEND="${3:-${QUILLUI_BACKEND:-}}"
APP_EXECUTABLE=""
APP_LOG_PATH="${QUILLUI_BACKEND_VISUAL_APP_LOG:-/tmp/quillui-backend-app.log}"

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

quillui_export_backend_argument "$REQUESTED_BACKEND" "$PRODUCT"
quillui_alias_backend_build_env
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
quillui_append_backend_runtime_environment \
  app_environment \
  "$PRODUCT" \
  "$DISPLAY_ID" \
  "$OUTPUT_DIR" \
  "$reference_window_width" \
  "$reference_window_height" \
  "$hide_window_menubar_label" \
  "$REQUESTED_BACKEND"
env "${app_environment[@]}" "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

sleep 4
capture_window="root"
window_id=""
if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
  window_id="$(quillui_find_quill_chat_reference_window "$DISPLAY_ID")"
else
  window_id="$(quillui_find_visible_window_for_pid "$DISPLAY_ID" "$app_pid")"
  if [[ -z "$window_id" ]]; then
    window_id="$(quillui_find_visible_window_by_name "$DISPLAY_ID" ".*")"
  fi
fi
if [[ -n "$window_id" ]]; then
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    quillui_place_reference_window "$DISPLAY_ID" "$window_id" "$reference_window_width" "$reference_window_height"
  else
    quillui_move_window_to_origin "$DISPLAY_ID" "$window_id"
  fi
  capture_window="$window_id"
fi
DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"

VERIFY_PRODUCT=""
quillui_backend_visual_verify_product "$PRODUCT" VERIFY_PRODUCT
if "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"; then
  :
else
  verify_status=$?
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_BACKEND_VISUAL_APP_LOG_LINES:-80}"
  exit "$verify_status"
fi
