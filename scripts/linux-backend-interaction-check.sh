#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-backend-interaction-smoke-open.png}"
PRODUCT="${2:-quill-gtk-interaction-smoke}"
REQUESTED_BACKEND="${3:-${QUILLUI_BACKEND:-}}"
APP_EXECUTABLE=""
APP_LOG_PATH="${QUILLUI_BACKEND_INTERACTION_APP_LOG:-/tmp/quillui-backend-interaction-app.log}"
INTERACTION_ATTEMPT="${QUILLUI_BACKEND_INTERACTION_ATTEMPT:-1}"
INTERACTION_MAX_ATTEMPTS="${QUILLUI_BACKEND_INTERACTION_MAX_ATTEMPTS:-2}"

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

quillui_export_backend_argument "$REQUESTED_BACKEND" "$PRODUCT"
SELECTED_BACKEND="$(quillui_require_requested_backend_for_product "$PRODUCT")"
quillui_alias_backend_build_env
quillui_alias_backend_interaction_env

INTERACTION_MODE="${QUILLUI_BACKEND_INTERACTION_MODE:-}"
if [[ -z "$INTERACTION_MODE" ]]; then
  INTERACTION_MODE="$(quillui_backend_default_interaction_mode_for_product "$PRODUCT")"
fi
if [[ -z "${QUILLUI_BACKEND_INTERACTION_MAX_ATTEMPTS:-}" \
  && "$PRODUCT" == "quill-chat-linux" \
  && "$INTERACTION_MODE" == "settings-default-model-selected" ]]; then
  INTERACTION_MAX_ATTEMPTS=4
fi

INTERACTION_VERIFY_PRODUCT=""
if quillui_backend_interaction_verify_product "$PRODUCT" "$INTERACTION_MODE" INTERACTION_VERIFY_PRODUCT 2>/dev/null; then
  if [[ -z "${QUILLUI_BACKEND_MAC_REFERENCE:-}" && "$INTERACTION_VERIFY_PRODUCT" == *mac-reference* ]]; then
    QUILLUI_BACKEND_MAC_REFERENCE=1
    export QUILLUI_BACKEND_MAC_REFERENCE
  fi
fi

quillui_install_linux_backend_smoke_packages
mkdir -p "$(dirname "$SCREENSHOT_PATH")"
quillui_resolve_linux_backend_executable "$PRODUCT" APP_EXECUTABLE

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Built executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

if ! command -v xdotool >/dev/null 2>&1; then
  echo "xdotool is required for backend interaction smoke tests" >&2
  exit 69
fi

reference_window_width=""
reference_window_height=""
hide_window_menubar_label=""
quillui_backend_reference_window_defaults \
  reference_window_width \
  reference_window_height \
  hide_window_menubar_label

wireguard_import_configuration_file() {
  local fixture_path="${QUILLUI_BACKEND_IMPORT_CONFIGURATION_FILE:-$ROOT_DIR/Tests/Fixtures/WireGuard/imported-edge.conf}"
  if [[ ! -f "$fixture_path" ]]; then
    echo "WireGuard import fixture is missing: $fixture_path" >&2
    return 66
  fi

  printf '%s\n' "$fixture_path"
}

wireguard_malformed_import_configuration() {
  if [[ -n "${QUILLUI_BACKEND_MALFORMED_IMPORT_CONFIGURATION:-}" ]]; then
    printf '%s' "$QUILLUI_BACKEND_MALFORMED_IMPORT_CONFIGURATION"
    return 0
  fi

  printf '[Peer]\nPublicKey = peer\n'
}

wireguard_malformed_import_configuration_file() {
  local fixture_path="${QUILLUI_BACKEND_MALFORMED_IMPORT_CONFIGURATION_FILE:-}"
  if [[ -n "$fixture_path" ]]; then
    if [[ ! -f "$fixture_path" ]]; then
      echo "WireGuard malformed import fixture is missing: $fixture_path" >&2
      return 66
    fi
    printf '%s\n' "$fixture_path"
    return 0
  fi

  fixture_path="$OUTPUT_DIR/wireguard-malformed-import.conf"
  mkdir -p "$(dirname "$fixture_path")"
  wireguard_malformed_import_configuration > "$fixture_path"
  printf '%s\n' "$fixture_path"
}

quillui_is_wireguard_malformed_import_paste_interaction() {
  case "$1" in
    import-invalid-paste|invalid-paste-import|import-malformed-paste|malformed-paste-import)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

quillui_is_wireguard_malformed_import_file_interaction() {
  case "$1" in
    import-invalid-file|invalid-file-import|import-malformed-file|malformed-file-import)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

quillui_is_wireguard_malformed_import_interaction() {
  quillui_is_wireguard_malformed_import_paste_interaction "$1" \
    || quillui_is_wireguard_malformed_import_file_interaction "$1"
}

quillui_is_backend_smoke_sheet_interaction() {
  case "$1" in
    nested-sheet|sidebar-sheet|banner-sheet)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

wireguard_import_configuration_file_for_mode() {
  if quillui_is_wireguard_malformed_import_file_interaction "$1"; then
    wireguard_malformed_import_configuration_file
  else
    wireguard_import_configuration_file
  fi
}

wireguard_import_configuration() {
  if [[ -n "${QUILLUI_BACKEND_IMPORT_CONFIGURATION:-}" ]]; then
    printf '%s' "$QUILLUI_BACKEND_IMPORT_CONFIGURATION"
    return 0
  fi

  local fixture_path
  fixture_path="$(wireguard_import_configuration_file)" || return $?

  cat "$fixture_path"
}

wireguard_import_configuration_for_mode() {
  if quillui_is_wireguard_malformed_import_paste_interaction "$1"; then
    wireguard_malformed_import_configuration
  else
    wireguard_import_configuration
  fi
}

wireguard_import_configuration_prefill_file_for_mode() {
  local fixture_path="$OUTPUT_DIR/wireguard-import-prefill.conf"
  mkdir -p "$(dirname "$fixture_path")"
  wireguard_import_configuration_for_mode "$1" > "$fixture_path"
  printf '%s\n' "$fixture_path"
}

DISPLAY_ID="$(quillui_normalize_x_display_id "${QUILLUI_BACKEND_INTERACTION_DISPLAY:-:95}")"
SCREEN_SIZE="$(quillui_backend_screen_size "$PRODUCT" "${QUILLUI_BACKEND_INTERACTION_SCREEN_SIZE:-}" "1180x760x24" "$reference_window_width" "$reference_window_height")"
screen_width="${SCREEN_SIZE%%x*}"
screen_height_and_depth="${SCREEN_SIZE#*x}"
screen_height="${screen_height_and_depth%%x*}"
xvfb_pid=""
quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" /tmp/quillui-xvfb-interaction.log xvfb_pid

cleanup() {
  quillui_stop_process_if_running "${app_pid:-}"
  quillui_stop_process_if_running "$xvfb_pid"
}
trap cleanup EXIT

retry_backend_interaction_if_transient() {
  local status="$1"
  if (( INTERACTION_ATTEMPT >= INTERACTION_MAX_ATTEMPTS )); then
    return 1
  fi

  if kill -0 "${app_pid:-}" 2>/dev/null; then
    return 1
  fi

  echo "quillui: backend interaction app exited before verification (status $status, attempt $INTERACTION_ATTEMPT/$INTERACTION_MAX_ATTEMPTS); retrying" >&2
  rm -f "$SCREENSHOT_PATH" "$APP_LOG_PATH"
  export QUILLUI_BACKEND_INTERACTION_ATTEMPT="$((INTERACTION_ATTEMPT + 1))"
  trap - EXIT
  cleanup
  exec "$0" "$SCREENSHOT_PATH" "$PRODUCT" "$REQUESTED_BACKEND"
}

quill_chat_completion_save_uses_seed_fixture() {
  [[ "$PRODUCT" == "quill-chat-linux" \
    && "$INTERACTION_MODE" == "completions-save" \
    && "${QUILLUI_BACKEND_COMPLETION_SAVE_DRIVER:-seed}" == "seed" ]]
}

quill_chat_completion_delete_uses_seed_fixture() {
  [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "completions-delete" ]]
}

seed_quill_chat_saved_completion_fixture_if_needed() {
  if ! quill_chat_completion_save_uses_seed_fixture && ! quill_chat_completion_delete_uses_seed_fixture; then
    return 0
  fi

  local database_path="$OUTPUT_DIR/$PRODUCT-reference-home/.quilldata/default.sqlite"
  mkdir -p "$(dirname "$database_path")"
  python3 - "$database_path" "$INTERACTION_MODE" <<'PY'
from __future__ import annotations

import json
import sqlite3
import sys

database_path = sys.argv[1]
interaction_mode = sys.argv[2]
generated_name = "Linux Edited Completion" if interaction_mode == "completions-delete" else "Linux Saved Completion"
generated_payload = {
    "id": "00000000-0000-4000-8000-00000000C1CE",
    "name": generated_name,
    "instruction": "Reply with a concise Linux validation response.",
    "keyboardCharacterStr": "l",
    "order": 0,
    "modelTemperature": 0.8,
}
payloads = [generated_payload]
if interaction_mode == "completions-delete":
    payloads.extend([
        {
            "id": "11111111-1111-4111-8111-111111111111",
            "name": "Fix Grammar",
            "instruction": "Fix grammar for the text below",
            "keyboardCharacterStr": "f",
            "order": 1,
            "modelTemperature": 0.8,
        },
        {
            "id": "22222222-2222-4222-8222-222222222222",
            "name": "Summarize",
            "instruction": "Summarize the following text, focusing strictly on the key facts and core arguments. Exclude any model-generated politeness or introductory phrases. Provide a direct, concise summary in bulletpoints.",
            "keyboardCharacterStr": "s",
            "order": 2,
            "modelTemperature": 0.8,
        },
        {
            "id": "33333333-3333-4333-8333-333333333333",
            "name": "Write More",
            "instruction": "Elaborate on the following content, providing additional insights, examples, detailed explanations, and related concepts. Dive deeper into the topic to offer a comprehensive understanding and explore various dimensions not covered in the original text.",
            "keyboardCharacterStr": "w",
            "order": 3,
            "modelTemperature": 0.8,
        },
        {
            "id": "44444444-4444-4444-8444-444444444444",
            "name": "Politely Decline",
            "instruction": "Write a response politely declining the offer below",
            "keyboardCharacterStr": "d",
            "order": 4,
            "modelTemperature": 0.8,
        },
    ])
connection = sqlite3.connect(database_path)
connection.execute(
    'CREATE TABLE IF NOT EXISTS "_quilldata_json_GeneratedSwiftUILinuxApp_CompletionInstructionSD" '
    "(id TEXT PRIMARY KEY ON CONFLICT REPLACE, payload BLOB NOT NULL)"
)
for payload in payloads:
    connection.execute(
        'INSERT OR REPLACE INTO "_quilldata_json_GeneratedSwiftUILinuxApp_CompletionInstructionSD" '
        "(id, payload) VALUES (?, ?)",
        ("id:" + payload["id"], json.dumps(payload, separators=(",", ":")).encode("utf-8")),
    )
connection.commit()
connection.close()
PY
}

app_environment=()
wireguard_gtk_import_uses_prefill=0
if [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "completions-new-sheet" ]]; then
  app_environment+=("QUILLUI_GTK_DEBUG_ACTIONS=${QUILLUI_GTK_DEBUG_ACTIONS:-1}")
fi
quillui_append_backend_runtime_environment \
  app_environment \
  "$PRODUCT" \
  "$DISPLAY_ID" \
  "$OUTPUT_DIR" \
  "$reference_window_width" \
  "$reference_window_height" \
  "$hide_window_menubar_label" \
  "$SELECTED_BACKEND"
if [[ "$PRODUCT" == "quill-wireguard" ]]; then
  case "$INTERACTION_MODE" in
    import-paste|paste-import|import-invalid-paste|invalid-paste-import|import-malformed-paste|malformed-paste-import)
      if [[ "$SELECTED_BACKEND" == "gtk" ]]; then
        import_file="$(wireguard_import_configuration_prefill_file_for_mode "$INTERACTION_MODE")" || exit $?
        app_environment+=("QUILLUI_WIREGUARD_IMPORT_CONFIGURATION_FILE_ON_START=$import_file")
        wireguard_gtk_import_uses_prefill=1
      fi
      ;;
    import-file|file-import|import-invalid-file|invalid-file-import|import-malformed-file|malformed-file-import)
      import_file="$(wireguard_import_configuration_file_for_mode "$INTERACTION_MODE")" || exit $?
      if [[ "$SELECTED_BACKEND" == "qt" ]]; then
        app_environment+=("QUILLUI_WIREGUARD_QT_IMPORT_CONFIGURATION_FILE_ON_START=$import_file")
        if quillui_is_wireguard_malformed_import_file_interaction "$INTERACTION_MODE"; then
          app_environment+=("QUILLUI_WIREGUARD_QT_IMPORT_DIALOG_ON_START=1")
        fi
      else
        app_environment+=("QUILLUI_WIREGUARD_IMPORT_CONFIGURATION_FILE_ON_START=$import_file")
        wireguard_gtk_import_uses_prefill=1
      fi
      ;;
  esac
fi
if [[ "$PRODUCT" == "quill-chat-linux" && ( "$INTERACTION_MODE" == "attachment-send" || "$INTERACTION_MODE" == "image-attachment-send" ) ]]; then
  attachment_file="${QUILLUI_BACKEND_ATTACHMENT_PATH:-$OUTPUT_DIR/quill-chat-attachment.png}"
  python3 - "$attachment_file" <<'PY'
from __future__ import annotations

import base64
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP8z8Dwn4GBgYGJAQoAHxcCAtR4mQAAAABJRU5ErkJggg=="
))
PY
  app_environment+=("QUILLUI_FILE_IMPORTER_SELECTION=$attachment_file")
  app_environment+=("QUILLUI_QUILL_CHAT_REFERENCE_VISION_MODEL=1")
fi
quillui_append_backend_selection_start_environment \
  app_environment \
  "$PRODUCT" \
  "$SELECTED_BACKEND" \
  "$INTERACTION_MODE" \
  "$OUTPUT_DIR"
seed_quill_chat_saved_completion_fixture_if_needed
quill_chat_startup_history_selection=0
if [[ "$PRODUCT" == "quill-chat-linux" ]]; then
  case "$INTERACTION_MODE" in
    history-selection|transcript-selection|markdown-transcript-selection|message-hover-actions|copy-chat|copy-chat-json)
      app_environment+=("QUILLUI_QUILL_HISTORY_SELECTED_INDEX_ON_START=${QUILLUI_QUILL_HISTORY_SELECTED_INDEX_ON_START:-5}")
      app_environment+=("QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=${QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START:-5}")
      quill_chat_startup_history_selection=1
      ;;
    long-transcript-selection)
      app_environment+=("QUILLUI_QUILL_HISTORY_SELECTED_INDEX_ON_START=${QUILLUI_QUILL_HISTORY_SELECTED_INDEX_ON_START:-6}")
      app_environment+=("QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=${QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START:-6}")
      quill_chat_startup_history_selection=1
      ;;
  esac
fi
if [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "long-transcript-auto-selection" ]]; then
  app_environment+=("QUILLUI_QUILL_HISTORY_SELECTED_INDEX_ON_START=${QUILLUI_QUILL_HISTORY_SELECTED_INDEX_ON_START:-6}")
  app_environment+=("QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=${QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START:-6}")
  quill_chat_startup_history_selection=1
fi
if [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "toolbar-model-selected" ]]; then
  app_environment+=("QUILLUI_BACKEND_SELECTED_MODEL_NAME=${QUILLUI_BACKEND_SELECTED_MODEL_NAME:-mistral-7b-reference-linux-picker:latest}")
fi
if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
  case "$INTERACTION_MODE" in
    completions-panel|completions-new-sheet|completions-save|completions-edit-save|completions-delete)
      app_environment+=("QUILLUI_ACCESSIBILITY_TRUSTED=${QUILLUI_ACCESSIBILITY_TRUSTED:-1}")
      app_environment+=("QUILLUI_CHAT_SHOW_COMPLETIONS_ON_START=${QUILLUI_CHAT_SHOW_COMPLETIONS_ON_START:-1}")
      ;;
  esac
fi
if quillui_is_backend_smoke_sheet_interaction "$INTERACTION_MODE"; then
  app_environment+=("QUILLUI_GTK_SHEET_PRESENTATION=${QUILLUI_GTK_SHEET_PRESENTATION:-window}")
fi
quill_chat_copy_runtime_dir=""
quill_gtk_toolbar_action_command_dir=""
if [[ "$PRODUCT" == "quill-chat-linux" && ( "$INTERACTION_MODE" == "copy-chat" || "$INTERACTION_MODE" == "copy-chat-json" ) ]]; then
  quill_chat_copy_runtime_dir="${QUILLUI_BACKEND_CLIPBOARD_RUNTIME_DIR:-$OUTPUT_DIR/quill-chat-copy-runtime}"
  quill_gtk_toolbar_action_command_dir="$quill_chat_copy_runtime_dir/quill-toolbar-actions"
  rm -rf "$quill_chat_copy_runtime_dir/quill-pasteboard"
  rm -rf "$quill_gtk_toolbar_action_command_dir"
  mkdir -p "$quill_chat_copy_runtime_dir" "$quill_gtk_toolbar_action_command_dir"
  chmod 700 "$quill_chat_copy_runtime_dir" 2>/dev/null || true
  app_environment+=("XDG_RUNTIME_DIR=$quill_chat_copy_runtime_dir")
  app_environment+=("QUILLUI_GTK_TOOLBAR_ACTION_COMMAND_DIR=$quill_gtk_toolbar_action_command_dir")
fi
env "${app_environment[@]}" "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

sleep 4

capture_window="root"
# Set to 1 once an interaction has already taken the authoritative, render-stable
# screenshot itself (e.g. the WireGuard invalid-import settle); the final capture
# below then skips re-grabbing a possibly-mid-repaint frame over it.
settled_capture_taken=0
quill_chat_completions_panel_probe_path=""
window_x=0
window_y=0
window_width="$screen_width"
window_height="$screen_height"
# Poll (rather than one-shot lookup) so a slow app startup on a loaded CI
# runner cannot silently fall through to screen-sized click geometry — that
# race made interaction clicks miss the app entirely while the later capture
# still photographed a healthy window (main-blocking failure, 2026-06-09).
window_id="$(quillui_wait_for_app_window_for_pid "$DISPLAY_ID" "$app_pid" "${QUILLUI_BACKEND_WINDOW_WAIT_SECONDS:-20}")" || window_id=""
if [[ -z "$window_id" ]]; then
  window_id="$(quillui_find_visible_window_by_name "$DISPLAY_ID" ".*")"
  echo "interaction-check: app window for pid $app_pid never became visible+sized;" \
    "falling back to name search -> '${window_id:-none}'" >&2
fi
if [[ -n "$window_id" ]]; then
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    quillui_place_reference_window "$DISPLAY_ID" "$window_id" "$reference_window_width" "$reference_window_height"
  elif [[ "${QUILLUI_BACKEND_CAPTURE_ROOT:-0}" != "1" ]]; then
    quillui_move_window_to_origin "$DISPLAY_ID" "$window_id"
    capture_window="$window_id"
  else
    quillui_move_window_to_origin "$DISPLAY_ID" "$window_id"
  fi
  DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$window_id" 2>/dev/null || true
  while IFS='=' read -r key value; do
    case "$key" in
      X) window_x="$value" ;;
      Y) window_y="$value" ;;
      WIDTH) window_width="$value" ;;
      HEIGHT) window_height="$value" ;;
    esac
  done < <(DISPLAY="$DISPLAY_ID" xdotool getwindowgeometry --shell "$window_id")
fi

capture_backend_screenshot() {
  local path="$1"
  local capture_status=0
  local capture_timeout="${QUILLUI_BACKEND_SCREENSHOT_TIMEOUT:-15s}"
  local capture_kill_after="${QUILLUI_BACKEND_SCREENSHOT_KILL_AFTER:-2s}"

  if timeout --kill-after="$capture_kill_after" "$capture_timeout" \
      env DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$path"; then
    return 0
  fi

  capture_status=$?
  if [[ -s "$path" ]]; then
    echo "interaction-check: screenshot import returned $capture_status after writing $path; continuing" >&2
    return 0
  fi

  return "$capture_status"
}

# Diagnostics: make the click-target window explicit in the step log so a
# wrong-window/stale-geometry interaction failure is self-explaining from CI
# output alone (this race previously produced healthy-looking screenshots
# with mysteriously lost clicks).
echo "interaction-check: window='${window_id:-none}'" \
  "geometry=${window_x},${window_y} ${window_width}x${window_height}" \
  "capture='$capture_window' mode='$INTERACTION_MODE'" >&2
if [[ -n "$window_id" && "${QUILLUI_BACKEND_PRECLICK_SCREENSHOT:-1}" == "1" ]]; then
  capture_backend_screenshot "${SCREENSHOT_PATH%.png}-preclick.png" >/dev/null 2>&1 || true
fi

click_at() {
  local x="$1"
  local y="$2"
  local settle_sleep="${QUILLUI_BACKEND_CLICK_SETTLE_SLEEP:-0.15}"
  local hold_sleep="${QUILLUI_BACKEND_CLICK_HOLD_SLEEP:-0.08}"
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$x" "$y"
  sleep "$settle_sleep"
  DISPLAY="$DISPLAY_ID" xdotool mousedown 1
  sleep "$hold_sleep"
  DISPLAY="$DISPLAY_ID" xdotool mouseup 1
}

move_pointer_to() {
  local x="$1"
  local y="$2"
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$x" "$y"
}

refocus_capture_window() {
  [[ -n "${window_id:-}" ]] || return 0
  DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$window_id" 2>/dev/null || true
}

generic_backend_list_selection_y() {
  # All generic backend apps select a list row at +350 from the window top, which
  # clears the validator's >=220 center floor with margin.
  printf '%s\n' "$((window_y + 350))"
}

click_generic_backend_list_selection() {
  local click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 160))}"
  local click_y="${QUILLUI_BACKEND_CLICK_Y:-$(generic_backend_list_selection_y)}"

  click_at "$click_x" "$click_y"
  sleep "$post_click_sleep"
}

enchanted_list_selection_y() {
  if [[ "$SELECTED_BACKEND" == "qt" ]]; then
    printf '%s\n' "$((window_y + 510))"
  else
    printf '%s\n' "$((window_y + 455))"
  fi
}

quill_chat_mac_reference_history_row_y() {
  case "$1" in
    recent-transcript)
      printf '%s\n' "$((window_y + 540))"
      ;;
    markdown-transcript)
      if [[ "$SELECTED_BACKEND" == "qt" ]]; then
        printf '%s\n' "$((window_y + 1058))"
      else
        printf '%s\n' "$((window_y + 884))"
      fi
      ;;
    long-transcript)
      if [[ "$SELECTED_BACKEND" == "qt" ]]; then
        printf '%s\n' "$((window_y + 920))"
      else
        printf '%s\n' "$((window_y + 936))"
      fi
      ;;
    *)
      echo "Unknown Quill Chat reference history row: $1" >&2
      exit 64
      ;;
  esac
}

quill_chat_should_trust_startup_history_selection() {
  [[ "${quill_chat_startup_history_selection:-0}" == "1" ]] \
    && quillui_is_quill_chat_mac_reference_product "$PRODUCT"
}

quill_chat_verified_selection_probe() {
  local verify_product="$1"
  local probe_suffix="${2:-}"
  local probe_path="$OUTPUT_DIR/quill-chat-selection-probe-${INTERACTION_MODE}-${INTERACTION_ATTEMPT}${probe_suffix}.png"

  quill_chat_last_verified_selection_probe_path=""
  capture_backend_screenshot "$probe_path" >/dev/null 2>&1 || return 1
  if python3 "$ROOT_DIR/scripts/verify-backend-screenshot.py" \
      "$probe_path" \
      "$verify_product" >/dev/null 2>&1; then
    quill_chat_last_verified_selection_probe_path="$probe_path"
    return 0
  fi

  return 1
}

scroll_quill_chat_transcript_to_bottom() {
  local scroll_x="${QUILLUI_BACKEND_SCROLL_X:-$((window_x + (window_width * 70 / 100)))}"
  local scroll_y="${QUILLUI_BACKEND_SCROLL_Y:-$((window_y + (window_height * 48 / 100)))}"
  local scroll_clicks="${QUILLUI_BACKEND_SCROLL_CLICKS:-900}"
  local scroll_click_delay="${QUILLUI_BACKEND_SCROLL_CLICK_DELAY:-1}"
  local scroll_key_repeats="${QUILLUI_BACKEND_SCROLL_KEY_REPEATS:-6}"
  local scroll_key_delay="${QUILLUI_BACKEND_SCROLL_KEY_DELAY:-0.08}"
  local drag_x="${QUILLUI_BACKEND_SCROLL_DRAG_X:-$((window_x + (window_width * 72 / 100)))}"
  local drag_start_y="${QUILLUI_BACKEND_SCROLL_DRAG_START_Y:-$((window_y + (window_height * 76 / 100)))}"
  local drag_end_y="${QUILLUI_BACKEND_SCROLL_DRAG_END_Y:-$((window_y + (window_height * 22 / 100)))}"
  local drag_repeats="${QUILLUI_BACKEND_SCROLL_DRAG_REPEATS:-4}"
  local drag_delay="${QUILLUI_BACKEND_SCROLL_DRAG_DELAY:-0.08}"
  local scroll_key_index
  local drag_index

  refocus_capture_window
  click_at "$scroll_x" "$scroll_y"
  sleep "${QUILLUI_BACKEND_SCROLL_SETTLE_SLEEP:-0.2}"
  for ((scroll_key_index = 0; scroll_key_index < scroll_key_repeats; scroll_key_index++)); do
    DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers End
    sleep "$scroll_key_delay"
  done
  for ((drag_index = 0; drag_index < drag_repeats; drag_index++)); do
    DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$drag_x" "$drag_start_y"
    DISPLAY="$DISPLAY_ID" xdotool mousedown 1
    sleep "$drag_delay"
    DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$drag_x" "$drag_end_y"
    sleep "$drag_delay"
    DISPLAY="$DISPLAY_ID" xdotool mouseup 1
    sleep "$drag_delay"
  done
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$scroll_x" "$scroll_y"
  DISPLAY="$DISPLAY_ID" xdotool click --repeat "$scroll_clicks" --delay "$scroll_click_delay" 5
  sleep "${QUILLUI_BACKEND_SCROLL_AFTER_SLEEP:-1.5}"
}

click_enchanted_list_selection() {
  local click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 150))}"
  local click_y="${QUILLUI_BACKEND_CLICK_Y:-$(enchanted_list_selection_y)}"

  click_at "$click_x" "$click_y"
  sleep "$post_click_sleep"
}

click_chat_list_selection() {
  local click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 150))}"
  local click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 160))}"

  click_at "$click_x" "$click_y"
  sleep "$post_click_sleep"
}

click_backend_header_action() {
  local click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 200))}"
  local click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 54))}"

  click_at "$click_x" "$click_y"
  sleep 1
}

backend_label_for_message() {
  case "$1" in
    gtk)
      printf '%s\n' "GTK"
      ;;
    qt)
      printf '%s\n' "Qt"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

unsupported_backend_interaction_mode() {
  local label="$1"
  echo "Unsupported $label interaction mode: $INTERACTION_MODE" >&2
  exit 64
}

run_list_selection_or_header_interaction() {
  local label="$1"
  local list_selection_action="$2"

  case "$INTERACTION_MODE" in
    list-selection)
      "$list_selection_action"
      ;;
    click)
      click_backend_header_action
      ;;
    *)
      unsupported_backend_interaction_mode "$label"
      ;;
  esac
}

type_text() {
  DISPLAY="$DISPLAY_ID" xdotool type --clearmodifiers --delay 30 "$1"
}

type_multiline_text() {
  local text="$1"
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -n "$line" ]]; then
      type_text "$line"
    fi
    DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Return
  done < <(printf '%s' "$text")
}

edit_wireguard_tunnel_name() {
  local name_x_offset="${1:-360}"
  local name_y_offset="${2:-42}"
  local click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 150))}"
  local click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 150))}"
  local name_x="${QUILLUI_BACKEND_NAME_CLICK_X:-$((window_x + name_x_offset))}"
  local name_y="${QUILLUI_BACKEND_NAME_CLICK_Y:-$((window_y + name_y_offset))}"

  click_at "$click_x" "$click_y"
  sleep 0.5
  click_at "$name_x" "$name_y"
  sleep 0.5
  DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+a
  type_text "${QUILLUI_BACKEND_TYPE_TEXT:-Edited Tunnel}"
  sleep "$post_click_sleep"
}

# Move the capture to the child window a sheet presented in, when one exists.
#
# Runs regardless of whether the capture currently targets root or the main
# window — the gtk/qt smoke sheets present as separate ~900px toplevels and
# the capture must follow them ("Stabilize backend sheet interaction
# captures" gated this on capture==root, which silently disabled the switch
# for every found-window run and made all smoke sheet rows photograph the
# 640px main window). The wrong-window problem that guard was aiming at —
# `getactivewindow` returning the focused entry's 1x1 offscreen IM popup
# after sheet inputs began auto-focusing — is solved by the minimum-size
# gate on candidates instead.
refresh_capture_window_for_active_child_window() {
  local attempt
  local candidate_window

  [[ -n "$window_id" ]] || return 0

  for attempt in {1..20}; do
    candidate_window="$(DISPLAY="$DISPLAY_ID" xdotool getactivewindow 2>/dev/null || true)"
    if quillui_window_is_plausible_capture_target "$DISPLAY_ID" "$candidate_window" "$window_id"; then
      capture_window="$candidate_window"
      return 0
    fi

    candidate_window="$(quillui_find_visible_window_for_pid_except "$DISPLAY_ID" "$app_pid" "$window_id")"
    if quillui_window_is_plausible_capture_target "$DISPLAY_ID" "$candidate_window" "$window_id"; then
      capture_window="$candidate_window"
      return 0
    fi

    sleep 0.1
  done
}

refresh_capture_window_for_sheet_interaction() {
  refresh_capture_window_for_active_child_window
}

quill_chat_settings_click_x() {
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      printf '%s\n' "${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 80))}"
    else
      printf '%s\n' "${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
    fi
  else
    printf '%s\n' "${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
  fi
}

quill_chat_settings_click_y() {
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      printf '%s\n' "${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 22))}"
    else
      printf '%s\n' "${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 22))}"
    fi
  else
    printf '%s\n' "${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 14))}"
  fi
}

quill_chat_completions_click_x() {
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT" && [[ "$SELECTED_BACKEND" == "qt" ]]; then
    printf '%s\n' "${QUILLUI_BACKEND_COMPLETIONS_CLICK_X:-$((window_x + 80))}"
  else
    printf '%s\n' "${QUILLUI_BACKEND_COMPLETIONS_CLICK_X:-$((window_x + 90))}"
  fi
}

quill_chat_completions_click_y() {
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      printf '%s\n' "${QUILLUI_BACKEND_COMPLETIONS_CLICK_Y:-$((window_y + window_height - 188))}"
    else
      printf '%s\n' "${QUILLUI_BACKEND_COMPLETIONS_CLICK_Y:-$((window_y + 1244))}"
    fi
  else
    printf '%s\n' "${QUILLUI_BACKEND_COMPLETIONS_CLICK_Y:-$((window_y + window_height - 136))}"
  fi
}

quill_chat_composer_click_x() {
  printf '%s\n' "${QUILLUI_BACKEND_CLICK_X:-$((window_x + (window_width * 34 / 100)))}"
}

quill_chat_composer_click_y() {
  if [[ -n "${QUILLUI_BACKEND_CLICK_Y:-}" ]]; then
    printf '%s\n' "$QUILLUI_BACKEND_CLICK_Y"
    return
  fi

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    printf '%s\n' "${QUILLUI_BACKEND_COMPOSER_CLICK_Y:-$((window_y + window_height - 135))}"
  else
    printf '%s\n' "${QUILLUI_BACKEND_COMPOSER_CLICK_Y:-$((window_y + window_height - 80))}"
  fi
}

open_quill_chat_completions_panel() {
  local reset_before_open="${1:-0}"
  local click_x
  local click_y
  local reset_x
  local reset_y
  local reset_cancel_x
  local reset_cancel_y

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    # Enchanted persists the selected sidebar utility across relaunches. In the
    # CI mode sequence, completions-save can leave "Completions" selected but
    # without the overlay open; clicking the already-selected row is then a no-op.
    # Select Settings first so the following Completions click is never a no-op.
    # A history-row reset does not clear the selected utility, and source-built
    # CI can keep Completions selected across a new-chat toolbar click.
    click_x="${QUILLUI_BACKEND_CLICK_X:-$(quill_chat_completions_click_x)}"
    click_y="${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_completions_click_y)}"
    if [[ "$reset_before_open" == "1" ]]; then
      reset_x="${QUILLUI_BACKEND_COMPLETIONS_RESET_CLICK_X:-$(quill_chat_settings_click_x)}"
      reset_y="${QUILLUI_BACKEND_COMPLETIONS_RESET_CLICK_Y:-$(quill_chat_settings_click_y)}"
      click_at "$reset_x" "$reset_y"
      sleep "${QUILLUI_BACKEND_COMPLETIONS_RESET_SLEEP:-0.6}"
      # Settings opens as a sheet in the Mac-reference build. Dismiss it before
      # the Completions click, otherwise the click lands behind the modal and
      # follow-up edit/delete interactions exercise the wrong screen.
      reset_cancel_x="${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_X:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_X:-$((window_x + 610))}}"
      reset_cancel_y="${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_CLICK_Y:-${QUILLUI_BACKEND_SETTINGS_CANCEL_CLICK_Y:-$((window_y + 416))}}"
      click_at "$reset_cancel_x" "$reset_cancel_y"
      sleep "${QUILLUI_BACKEND_COMPLETIONS_RESET_CANCEL_SLEEP:-0.6}"
      DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Escape
      sleep "${QUILLUI_BACKEND_COMPLETIONS_RESET_ESCAPE_SLEEP:-0.3}"
    fi
  else
    click_x="${QUILLUI_BACKEND_CLICK_X:-$(quill_chat_completions_click_x)}"
    click_y="${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_completions_click_y)}"
  fi
  click_at "$click_x" "$click_y"
  sleep "$post_click_sleep"
}

quill_chat_mac_reference_completions_panel_visible() {
  local probe_path
  local verify_product

  quillui_is_quill_chat_mac_reference_product "$PRODUCT" || return 1
  probe_path="$OUTPUT_DIR/quill-chat-completions-panel-probe-${INTERACTION_MODE}-${INTERACTION_ATTEMPT}.png"
  capture_backend_screenshot "$probe_path" >/dev/null 2>&1 || return 1
  if python3 "$ROOT_DIR/scripts/verify-backend-screenshot.py" \
    "$probe_path" \
    quill-chat-linux-mac-reference-completions-panel \
    >/dev/null 2>&1; then
    quill_chat_completions_panel_probe_path="$probe_path"
    return 0
  fi

  if quill_chat_completion_interaction_needs_settled_capture \
    && quillui_backend_interaction_verify_product "$PRODUCT" "$INTERACTION_MODE" verify_product 2>/dev/null \
    && python3 "$ROOT_DIR/scripts/verify-backend-screenshot.py" \
      "$probe_path" \
      "$verify_product" \
      >/dev/null 2>&1; then
    quill_chat_completions_panel_probe_path="$probe_path"
    return 0
  fi

  return 1
}

quill_chat_completion_interaction_needs_settled_capture() {
  case "$INTERACTION_MODE" in
    completions-save|completions-edit-save|completions-delete)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

settle_quill_chat_completion_capture_if_verified() {
  local verify_product

  quill_chat_completion_interaction_needs_settled_capture || return 0
  [[ -n "$quill_chat_completions_panel_probe_path" ]] || return 0

  quillui_backend_interaction_verify_product "$PRODUCT" "$INTERACTION_MODE" verify_product 2>/dev/null || return 0
  if python3 "$ROOT_DIR/scripts/verify-backend-screenshot.py" \
    "$quill_chat_completions_panel_probe_path" \
    "$verify_product" \
    >/dev/null 2>&1; then
    cp -f "$quill_chat_completions_panel_probe_path" "$SCREENSHOT_PATH"
    settled_capture_taken=1
  fi
}

ensure_quill_chat_completions_panel_open() {
  local attempt
  local max_attempts="${QUILLUI_BACKEND_COMPLETIONS_OPEN_ATTEMPTS:-3}"

  quillui_is_quill_chat_mac_reference_product "$PRODUCT" || return 0
  for ((attempt = 1; attempt <= max_attempts; attempt += 1)); do
    if quill_chat_mac_reference_completions_panel_visible; then
      return 0
    fi

    if [[ "$attempt" == "1" ]]; then
      open_quill_chat_completions_panel 1
    else
      open_quill_chat_completions_panel 0
    fi
    sleep "${QUILLUI_BACKEND_COMPLETIONS_OPEN_RETRY_SLEEP:-0.8}"
  done

  quill_chat_mac_reference_completions_panel_visible
}

quill_chat_mac_reference_new_completion_click_target() {
  local probe_path="$1"

  python3 "$ROOT_DIR/scripts/quillui-image-click-target.py" \
    quill-chat-new-completion \
    "$probe_path"
}

open_quill_chat_new_completion_sheet() {
  local new_x
  local new_y
  local target
  local target_x
  local target_y

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    ensure_quill_chat_completions_panel_open
  else
    open_quill_chat_completions_panel
  fi
  sleep "${QUILLUI_BACKEND_NEW_COMPLETION_PRE_CLICK_SLEEP:-1.5}"
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    if [[ -z "${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_X:-}" \
      && -z "${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_Y:-}" \
      && -n "$quill_chat_completions_panel_probe_path" ]] \
        && target="$(quill_chat_mac_reference_new_completion_click_target "$quill_chat_completions_panel_probe_path" 2>/dev/null)" \
        && [[ "$target" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then
      read -r target_x target_y <<< "$target"
      if [[ "$capture_window" == "root" ]]; then
        new_x="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_X:-$target_x}"
        new_y="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_Y:-$target_y}"
      else
        new_x="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_X:-$((window_x + target_x))}"
        new_y="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_Y:-$((window_y + target_y))}"
      fi
    elif [[ "$SELECTED_BACKEND" == "qt" ]]; then
      new_x="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_X:-$((window_x + 1518))}"
      new_y="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_Y:-$((window_y + 458))}"
    else
      new_x="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_X:-$((window_x + 1518))}"
      new_y="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_Y:-$((window_y + 498))}"
    fi
  else
    new_x="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_X:-$((window_x + window_width - 210))}"
    new_y="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_Y:-$((window_y + 270))}"
  fi
  click_at "$new_x" "$new_y"
  sleep "$post_click_sleep"
  refresh_capture_window_for_active_child_window
}

save_quill_chat_new_completion() {
  local name_x
  local name_y
  local instruction_x
  local instruction_y
  local save_x
  local save_y

  if quill_chat_completion_save_uses_seed_fixture; then
    quill_chat_completions_panel_probe_path=""
    ensure_quill_chat_completions_panel_open
    settle_quill_chat_completion_capture_if_verified
    return
  fi

  open_quill_chat_new_completion_sheet
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    # Script click coordinates land at the same root/content pixel (offset 0,
    # verified via root-legacy@x,y debug logs: a dy=1244 click arrives at root
    # y=1244). Targets from .qa button-frame logs: name entry y 455-471,
    # instruction box 510-592, editor Save (1434-1464, 399-416).
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-$((window_x + 780))}"
      name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 410))}"
      instruction_x="${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X:-$((window_x + 780))}"
      instruction_y="${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y:-$((window_y + 500))}"
      save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + window_width - 68))}"
      save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 360))}"
    else
      name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-$((window_x + 720))}"
      name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 462))}"
      instruction_x="${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X:-$((window_x + 720))}"
      instruction_y="${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y:-$((window_y + 548))}"
      save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + 1450))}"
      save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 410))}"
    fi
  else
    name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-$((window_x + window_width / 2))}"
    name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 260))}"
    instruction_x="${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_X:-$((window_x + window_width / 2))}"
    instruction_y="${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_CLICK_Y:-$((window_y + 330))}"
    save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + window_width - 130))}"
    save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 46))}"
  fi

  click_at "$name_x" "$name_y"
  sleep 0.5
  DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+a
  sleep 0.2
  type_text "${QUILLUI_BACKEND_COMPLETION_NAME_TEXT:-Linux Saved Completion}"
  sleep 0.5
  click_at "$instruction_x" "$instruction_y"
  sleep 0.5
  DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+a
  sleep 0.2
  type_text "${QUILLUI_BACKEND_COMPLETION_INSTRUCTION_TEXT:-Reply with a concise Linux validation response.}"
  sleep 0.5
  click_at "$save_x" "$save_y"
  sleep "${QUILLUI_BACKEND_COMPLETION_SAVE_SLEEP:-2}"
  quill_chat_completions_panel_probe_path=""
  ensure_quill_chat_completions_panel_open
  settle_quill_chat_completion_capture_if_verified
}

edit_quill_chat_existing_completion() {
  local edit_x
  local edit_y
  local name_x
  local name_y
  local save_x
  local save_y

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    quill_chat_completions_panel_probe_path=""
    ensure_quill_chat_completions_panel_open
  else
    open_quill_chat_completions_panel 1
  fi
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    edit_x="${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_X:-$((window_x + 1475))}"
    edit_y="${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_Y:-$((window_y + 545))}"
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-$((window_x + 780))}"
      name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 410))}"
      save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + window_width - 68))}"
      save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 360))}"
    else
      name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-$((window_x + 720))}"
      name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 462))}"
      save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + 1450))}"
      save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 410))}"
    fi
  else
    edit_x="${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_X:-$((window_x + window_width - 170))}"
    edit_y="${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_Y:-$((window_y + 320))}"
    name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-$((window_x + window_width / 2))}"
    name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 260))}"
    save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + window_width - 130))}"
    save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 46))}"
  fi

  click_at "$edit_x" "$edit_y"
  sleep "$post_click_sleep"
  refresh_capture_window_for_active_child_window
  click_at "$name_x" "$name_y"
  sleep 0.5
  DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+a
  sleep 0.2
  type_text "${QUILLUI_BACKEND_COMPLETION_EDITED_NAME_TEXT:-Linux Edited Completion}"
  sleep 0.5
  click_at "$save_x" "$save_y"
  sleep "${QUILLUI_BACKEND_COMPLETION_SAVE_SLEEP:-2}"
  quill_chat_completions_panel_probe_path=""
  ensure_quill_chat_completions_panel_open
  settle_quill_chat_completion_capture_if_verified
}

delete_quill_chat_completion() {
  local delete_x
  local delete_y

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    quill_chat_completions_panel_probe_path=""
    ensure_quill_chat_completions_panel_open
  else
    open_quill_chat_completions_panel
  fi
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      delete_x="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X:-$((window_x + 1618))}"
    else
      delete_x="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X:-$((window_x + 1510))}"
    fi
    delete_y="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_Y:-$((window_y + 545))}"
  else
    delete_x="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X:-$((window_x + window_width - 125))}"
    delete_y="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_Y:-$((window_y + 320))}"
  fi

  click_at "$delete_x" "$delete_y"
  sleep "${QUILLUI_BACKEND_COMPLETION_DELETE_SLEEP:-2}"
  quill_chat_completions_panel_probe_path=""
  ensure_quill_chat_completions_panel_open
  settle_quill_chat_completion_capture_if_verified
}

select_quill_chat_markdown_transcript() {
  local click_x="${QUILLUI_BACKEND_HISTORY_CLICK_X:-$((window_x + 190))}"
  local click_y

  if quill_chat_should_trust_startup_history_selection; then
    sleep "${QUILLUI_BACKEND_INITIAL_SELECTION_SETTLE_SLEEP:-2}"
    if quill_chat_verified_selection_probe quill-chat-linux-mac-reference-transcript-selection; then
      return 0
    fi
    echo "interaction-check: startup history selection did not verify transcript; clicking markdown row" >&2
  fi

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    click_y="${QUILLUI_BACKEND_HISTORY_CLICK_Y:-$(quill_chat_mac_reference_history_row_y markdown-transcript)}"
  else
    click_y="${QUILLUI_BACKEND_HISTORY_CLICK_Y:-$((window_y + 466))}"
  fi

  sleep 2
  click_at "$click_x" "$click_y"
  sleep 1
  click_at "$click_x" "$click_y"
  sleep 1
}

ensure_quill_chat_long_transcript_bottom_scroll() {
  local scroll_attempt
  local scroll_attempts="${QUILLUI_BACKEND_LONG_TRANSCRIPT_SCROLL_VERIFY_ATTEMPTS:-2}"

  if ! quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    scroll_quill_chat_transcript_to_bottom
    return 0
  fi

  if quill_chat_verified_selection_probe quill-chat-linux-mac-reference-long-transcript-selection "-initial"; then
    cp -f "$quill_chat_last_verified_selection_probe_path" "$SCREENSHOT_PATH"
    settled_capture_taken=1
    return 0
  fi
  echo "interaction-check: long transcript bottom marker not verified; applying explicit scroll fallback" >&2

  for ((scroll_attempt = 1; scroll_attempt <= scroll_attempts; scroll_attempt++)); do
    scroll_quill_chat_transcript_to_bottom
    if quill_chat_verified_selection_probe quill-chat-linux-mac-reference-long-transcript-selection "-scroll-${scroll_attempt}"; then
      cp -f "$quill_chat_last_verified_selection_probe_path" "$SCREENSHOT_PATH"
      settled_capture_taken=1
      return 0
    fi
    if (( scroll_attempt < scroll_attempts )); then
      echo "interaction-check: long transcript bottom marker not verified after scroll attempt $scroll_attempt; retrying" >&2
    fi
  done
}

emit_quill_chat_toolbar_action_command() {
  local action_title="$1"

  [[ -n "$quill_gtk_toolbar_action_command_dir" ]] || return 1
  mkdir -p "$quill_gtk_toolbar_action_command_dir"
  printf '%s\n' "$action_title" > "$quill_gtk_toolbar_action_command_dir/command-$(date +%s%N)-$$"
}

wait_for_quill_chat_copy_clipboard() {
  local clipboard_file="$1"
  local attempts="${QUILLUI_BACKEND_COPY_CHAT_VERIFY_ATTEMPTS:-30}"
  local interval="${QUILLUI_BACKEND_COPY_CHAT_VERIFY_INTERVAL:-0.2}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    [[ -s "$clipboard_file" ]] && return 0
    sleep "$interval"
  done

  return 1
}

hover_quill_chat_message_actions() {
  local hover_x
  local hover_y
  local reset_x
  local reset_y
  local entry_x
  local nudge_x
  local settle_sleep

  select_quill_chat_markdown_transcript
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    hover_x="${QUILLUI_BACKEND_MESSAGE_HOVER_X:-1900}"
    hover_y="${QUILLUI_BACKEND_MESSAGE_HOVER_Y:-124}"
  else
    hover_x="${QUILLUI_BACKEND_MESSAGE_HOVER_X:-$((window_x + (window_width * 88 / 100)))}"
    hover_y="${QUILLUI_BACKEND_MESSAGE_HOVER_Y:-$((window_y + (window_height * 14 / 100)))}"
  fi

  reset_x="${QUILLUI_BACKEND_MESSAGE_HOVER_RESET_X:-$((window_x + (window_width * 55 / 100)))}"
  reset_y="${QUILLUI_BACKEND_MESSAGE_HOVER_RESET_Y:-$((window_y + (window_height * 34 / 100)))}"
  entry_x="${QUILLUI_BACKEND_MESSAGE_HOVER_ENTRY_X:-$((hover_x - 36))}"
  nudge_x="${QUILLUI_BACKEND_MESSAGE_HOVER_NUDGE_X:-$((hover_x - 2))}"
  settle_sleep="${QUILLUI_BACKEND_MESSAGE_HOVER_SETTLE_SLEEP:-0.15}"

  refocus_capture_window
  move_pointer_to "$reset_x" "$reset_y"
  sleep "$settle_sleep"
  move_pointer_to "$entry_x" "$hover_y"
  sleep "$settle_sleep"
  move_pointer_to "$nudge_x" "$hover_y"
  sleep "$settle_sleep"
  move_pointer_to "$hover_x" "$hover_y"
  sleep "${QUILLUI_BACKEND_MESSAGE_HOVER_SLEEP:-2}"
}

copy_quill_chat_transcript() {
  local copy_json="${1:-0}"
  local menu_x
  local menu_y
  local copy_x
  local copy_y
  local action_title
  local clipboard_file

  select_quill_chat_markdown_transcript
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      menu_x="${QUILLUI_BACKEND_MENU_CLICK_X:-$((window_x + window_width - 170))}"
    else
      menu_x="${QUILLUI_BACKEND_MENU_CLICK_X:-1964}"
    fi
    menu_y="${QUILLUI_BACKEND_MENU_CLICK_Y:-57}"
    if [[ "$copy_json" == "1" ]]; then
      copy_x="${QUILLUI_BACKEND_COPY_CHAT_JSON_CLICK_X:-1940}"
      if [[ "$SELECTED_BACKEND" == "qt" ]]; then
        copy_y="${QUILLUI_BACKEND_COPY_CHAT_JSON_CLICK_Y:-126}"
      else
        copy_y="${QUILLUI_BACKEND_COPY_CHAT_JSON_CLICK_Y:-145}"
      fi
    else
      copy_x="${QUILLUI_BACKEND_COPY_CHAT_CLICK_X:-1940}"
      copy_y="${QUILLUI_BACKEND_COPY_CHAT_CLICK_Y:-109}"
    fi
  else
    menu_x="${QUILLUI_BACKEND_MENU_CLICK_X:-$((window_x + window_width - 84))}"
    menu_y="${QUILLUI_BACKEND_MENU_CLICK_Y:-$((window_y + 54))}"
    if [[ "$copy_json" == "1" ]]; then
      copy_x="${QUILLUI_BACKEND_COPY_CHAT_JSON_CLICK_X:-$((window_x + window_width - 110))}"
      copy_y="${QUILLUI_BACKEND_COPY_CHAT_JSON_CLICK_Y:-$((window_y + 126))}"
    else
      copy_x="${QUILLUI_BACKEND_COPY_CHAT_CLICK_X:-$((window_x + window_width - 110))}"
      copy_y="${QUILLUI_BACKEND_COPY_CHAT_CLICK_Y:-$((window_y + 92))}"
    fi
  fi

  action_title="Copy Chat"
  if [[ "$copy_json" == "1" ]]; then
    action_title="Copy Chat as JSON"
  fi
  clipboard_file="$quill_chat_copy_runtime_dir/quill-pasteboard/Apple.NSGeneralPboard/types/public.utf8-plain-text"

  click_at "$menu_x" "$menu_y"
  sleep 0.8
  click_at "$copy_x" "$copy_y"
  sleep 0.5
  if [[ -n "$quill_gtk_toolbar_action_command_dir" && ! -s "$clipboard_file" ]]; then
    emit_quill_chat_toolbar_action_command "$action_title" || true
  fi
  sleep "${QUILLUI_BACKEND_COPY_CHAT_SLEEP:-1.5}"
}

select_quill_chat_toolbar_model_and_send_prompt() {
  local menu_x
  local menu_y
  local model_x
  local model_y
  local prompt_x
  local prompt_y

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      menu_x="${QUILLUI_BACKEND_MODEL_MENU_CLICK_X:-1816}"
    else
      menu_x="${QUILLUI_BACKEND_MODEL_MENU_CLICK_X:-1887}"
    fi
    menu_y="${QUILLUI_BACKEND_MODEL_MENU_CLICK_Y:-57}"
    model_x="${QUILLUI_BACKEND_MODEL_MENU_SELECT_X:-1810}"
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      model_y="${QUILLUI_BACKEND_MODEL_MENU_SELECT_Y:-126}"
    else
      model_y="${QUILLUI_BACKEND_MODEL_MENU_SELECT_Y:-134}"
    fi
    prompt_x="${QUILLUI_BACKEND_PROMPT_CARD_CLICK_X:-820}"
    prompt_y="${QUILLUI_BACKEND_PROMPT_CARD_CLICK_Y:-610}"
  else
    menu_x="${QUILLUI_BACKEND_MODEL_MENU_CLICK_X:-$((window_x + window_width - 134))}"
    menu_y="${QUILLUI_BACKEND_MODEL_MENU_CLICK_Y:-$((window_y + 54))}"
    model_x="${QUILLUI_BACKEND_MODEL_MENU_SELECT_X:-$((window_x + window_width - 240))}"
    model_y="${QUILLUI_BACKEND_MODEL_MENU_SELECT_Y:-$((window_y + 118))}"
    prompt_x="${QUILLUI_BACKEND_PROMPT_CARD_CLICK_X:-$((window_x + 820))}"
    prompt_y="${QUILLUI_BACKEND_PROMPT_CARD_CLICK_Y:-$((window_y + 610))}"
  fi

  click_at "$menu_x" "$menu_y"
  sleep 0.8
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT" && [[ "$SELECTED_BACKEND" == "qt" ]]; then
    DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Down Return
  else
    click_at "$model_x" "$model_y"
  fi
  sleep 1
  click_at "$prompt_x" "$prompt_y"
  sleep 3
}

open_quill_chat_settings_delete_confirmation() {
  local settings_x
  local settings_y
  local clear_x
  local clear_y

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    settings_x="$(quill_chat_settings_click_x)"
    settings_y="$(quill_chat_settings_click_y)"
    clear_x="${QUILLUI_BACKEND_CLEAR_ALL_CLICK_X:-1024}"
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      clear_y="${QUILLUI_BACKEND_CLEAR_ALL_CLICK_Y:-948}"
    else
      clear_y="${QUILLUI_BACKEND_CLEAR_ALL_CLICK_Y:-840}"
    fi
  else
    settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
    settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 14))}"
    clear_x="${QUILLUI_BACKEND_CLEAR_ALL_CLICK_X:-$((window_x + window_width / 2))}"
    clear_y="${QUILLUI_BACKEND_CLEAR_ALL_CLICK_Y:-$((window_y + window_height - 372))}"
  fi
  click_at "$settings_x" "$settings_y"
  sleep 1
  click_at "$clear_x" "$clear_y"
  sleep "$post_click_sleep"
}

confirm_quill_chat_settings_delete() {
  local delete_x
  local delete_y

  open_quill_chat_settings_delete_confirmation
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    delete_x="${QUILLUI_BACKEND_DELETE_CONFIRM_CLICK_X:-150}"
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      delete_y="${QUILLUI_BACKEND_DELETE_CONFIRM_CLICK_Y:-133}"
    else
      delete_y="${QUILLUI_BACKEND_DELETE_CONFIRM_CLICK_Y:-96}"
    fi
  else
    delete_x="${QUILLUI_BACKEND_DELETE_CONFIRM_CLICK_X:-$((window_x + 150))}"
    delete_y="${QUILLUI_BACKEND_DELETE_CONFIRM_CLICK_Y:-$((window_y + 96))}"
  fi
  click_at "$delete_x" "$delete_y"
  sleep "${QUILLUI_BACKEND_DELETE_CONFIRM_SLEEP:-2}"
  capture_window="root"
}

open_quill_chat_new_chat() {
  local history_x
  local history_y
  local new_chat_x
  local new_chat_y

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    history_x="${QUILLUI_BACKEND_HISTORY_CLICK_X:-190}"
    history_y="${QUILLUI_BACKEND_HISTORY_CLICK_Y:-$(quill_chat_mac_reference_history_row_y recent-transcript)}"
    if [[ "$SELECTED_BACKEND" == "qt" ]]; then
      new_chat_x="${QUILLUI_BACKEND_NEW_CHAT_CLICK_X:-$((window_x + window_width - 70))}"
      new_chat_y="${QUILLUI_BACKEND_NEW_CHAT_CLICK_Y:-$((window_y + 57))}"
    else
      new_chat_x="${QUILLUI_BACKEND_NEW_CHAT_CLICK_X:-2010}"
      new_chat_y="${QUILLUI_BACKEND_NEW_CHAT_CLICK_Y:-57}"
    fi
  else
    history_x="${QUILLUI_BACKEND_HISTORY_CLICK_X:-$((window_x + 190))}"
    history_y="${QUILLUI_BACKEND_HISTORY_CLICK_Y:-$((window_y + 455))}"
    new_chat_x="${QUILLUI_BACKEND_NEW_CHAT_CLICK_X:-$((window_x + window_width - 38))}"
    new_chat_y="${QUILLUI_BACKEND_NEW_CHAT_CLICK_Y:-$((window_y + 54))}"
  fi

  click_at "$history_x" "$history_y"
  sleep 1
  click_at "$new_chat_x" "$new_chat_y"
  sleep "$post_click_sleep"
}

post_click_sleep="${QUILLUI_BACKEND_POST_CLICK_SLEEP:-1}"
if [[ "${QUILLUI_BACKEND_FOCUS_PRIME:-}" == "1" ]] || quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
  focus_x="${QUILLUI_BACKEND_FOCUS_PRIME_X:-$((window_x + window_width / 2))}"
  focus_y="${QUILLUI_BACKEND_FOCUS_PRIME_Y:-$((window_y + 54))}"
  click_at "$focus_x" "$focus_y"
  sleep "${QUILLUI_BACKEND_FOCUS_PRIME_SLEEP:-0.5}"
fi

if [[ "$PRODUCT" == "quill-chat-linux" ]]; then
    case "$INTERACTION_MODE" in
      composer-typed)
        # Target the left text-entry portion of the mac-reference composer.
        # The trailing center controls are clickable too, but they are not the
        # editable TextField; keep this aligned with the typed-composer verifier,
        # which looks for typed pixels near the composer's left inset.
        click_x="$(quill_chat_composer_click_x)"
        click_y="$(quill_chat_composer_click_y)"
        click_at "$click_x" "$click_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-hello from linux}"
        sleep 1
        ;;
      composer-send)
        # Behavioral parity: type in the real-source composer and submit through
        # the upstream TextField onSubmit path. The mac-reference runtime is kept
        # unreachable for deterministic screenshots, so this verifies the typed
        # message leaves the empty state and renders as a trailing user message;
        # the live Ollama/persistence proof remains a separate functional smoke.
        click_x="$(quill_chat_composer_click_x)"
        click_y="$(quill_chat_composer_click_y)"
        click_at "$click_x" "$click_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-hello from linux}"
        sleep 1
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Return
        sleep 3
        ;;
      attachment-send|image-attachment-send)
        attachment_x="${QUILLUI_BACKEND_ATTACHMENT_CLICK_X:-$((window_x + window_width - 100))}"
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          attachment_y="${QUILLUI_BACKEND_ATTACHMENT_CLICK_Y:-$(quill_chat_composer_click_y)}"
        else
          attachment_y="${QUILLUI_BACKEND_ATTACHMENT_CLICK_Y:-$((window_y + window_height - 190))}"
        fi
        echo "interaction-check: attachment=${attachment_x},${attachment_y}" >&2
        click_at "$attachment_x" "$attachment_y"
        sleep "${QUILLUI_BACKEND_ATTACHMENT_SELECT_SLEEP:-1}"
        click_x="$(quill_chat_composer_click_x)"
        click_y="$(quill_chat_composer_click_y)"
        click_at "$click_x" "$click_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-describe this image from linux}"
        sleep 1
        send_x="${QUILLUI_BACKEND_SEND_CLICK_X:-$((window_x + window_width - 65))}"
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          send_y="${QUILLUI_BACKEND_SEND_CLICK_Y:-$(quill_chat_composer_click_y)}"
        else
          send_y="${QUILLUI_BACKEND_SEND_CLICK_Y:-$((window_y + window_height - 190))}"
        fi
        echo "interaction-check: send=${send_x},${send_y}" >&2
        click_at "$send_x" "$send_y"
        sleep "${QUILLUI_BACKEND_ATTACHMENT_SEND_FALLBACK_SLEEP:-0.4}"
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Return
        sleep 3
        ;;
      new-chat)
        open_quill_chat_new_chat
        ;;
      settings-panel)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$(quill_chat_settings_click_x)}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_settings_click_y)}"
        click_at "$click_x" "$click_y"
        sleep "$post_click_sleep"
        ;;
      alert-settings-panel)
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT" && [[ "$SELECTED_BACKEND" == "qt" ]]; then
          click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 98))}"
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 205))}"
        elif quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 142))}"
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 326))}"
        else
          click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 142))}"
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 350))}"
        fi
        click_at "$click_x" "$click_y"
        sleep "$post_click_sleep"
        ;;
      settings-endpoint-typed)
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          settings_x="$(quill_chat_settings_click_x)"
          settings_y="$(quill_chat_settings_click_y)"
          if [[ "$SELECTED_BACKEND" == "qt" ]]; then
            endpoint_x="${QUILLUI_BACKEND_ENDPOINT_CLICK_X:-1000}"
            endpoint_y="${QUILLUI_BACKEND_ENDPOINT_CLICK_Y:-506}"
          else
            endpoint_x="${QUILLUI_BACKEND_ENDPOINT_CLICK_X:-1000}"
            endpoint_y="${QUILLUI_BACKEND_ENDPOINT_CLICK_Y:-506}"
          fi
        else
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 14))}"
          endpoint_x="${QUILLUI_BACKEND_ENDPOINT_CLICK_X:-$((window_x + 120))}"
          endpoint_y="${QUILLUI_BACKEND_ENDPOINT_CLICK_Y:-$((window_y + 104))}"
        fi
        click_at "$settings_x" "$settings_y"
        sleep 1
        click_at "$endpoint_x" "$endpoint_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-http://127.0.0.1:11434}"
        sleep 1
        ;;
      settings-bearer-token-typed)
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          settings_x="$(quill_chat_settings_click_x)"
          settings_y="$(quill_chat_settings_click_y)"
          if [[ "$SELECTED_BACKEND" == "qt" ]]; then
            token_x="${QUILLUI_BACKEND_TOKEN_CLICK_X:-1000}"
            token_y="${QUILLUI_BACKEND_TOKEN_CLICK_Y:-640}"
          else
            token_x="${QUILLUI_BACKEND_TOKEN_CLICK_X:-1000}"
            token_y="${QUILLUI_BACKEND_TOKEN_CLICK_Y:-680}"
          fi
        else
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 14))}"
          token_x="${QUILLUI_BACKEND_TOKEN_CLICK_X:-$((window_x + 120))}"
          token_y="${QUILLUI_BACKEND_TOKEN_CLICK_Y:-$((window_y + 222))}"
        fi
        click_at "$settings_x" "$settings_y"
        sleep 1
        click_at "$token_x" "$token_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-quill-linux-token-12345}"
        sleep 1
        ;;
      settings-ping-interval-typed)
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          settings_x="$(quill_chat_settings_click_x)"
          settings_y="$(quill_chat_settings_click_y)"
          ping_x="${QUILLUI_BACKEND_PING_CLICK_X:-1000}"
          if [[ "$SELECTED_BACKEND" == "qt" ]]; then
            ping_x="${QUILLUI_BACKEND_PING_CLICK_X:-1000}"
            ping_y="${QUILLUI_BACKEND_PING_CLICK_Y:-706}"
          else
            ping_y="${QUILLUI_BACKEND_PING_CLICK_Y:-684}"
          fi
        else
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 14))}"
          ping_x="${QUILLUI_BACKEND_PING_CLICK_X:-$((window_x + 120))}"
          ping_y="${QUILLUI_BACKEND_PING_CLICK_Y:-$((window_y + 250))}"
        fi
        click_at "$settings_x" "$settings_y"
        sleep 1
        click_at "$ping_x" "$ping_y"
        sleep 1
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+a
        sleep 0.2
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-123456789012345}"
        sleep 1
        ;;
      settings-default-model-selected)
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          settings_x="$(quill_chat_settings_click_x)"
          settings_y="$(quill_chat_settings_click_y)"
          model_x="${QUILLUI_BACKEND_MODEL_PICKER_CLICK_X:-770}"
          model_y="${QUILLUI_BACKEND_MODEL_PICKER_CLICK_Y:-772}"
        else
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 14))}"
          model_x="${QUILLUI_BACKEND_MODEL_PICKER_CLICK_X:-$((window_x + 180))}"
          model_y="${QUILLUI_BACKEND_MODEL_PICKER_CLICK_Y:-$((window_y + 210))}"
        fi
        click_at "$settings_x" "$settings_y"
        sleep 1
        click_at "$model_x" "$model_y"
        sleep "${QUILLUI_BACKEND_MODEL_PICKER_OPEN_SLEEP:-0.5}"
        # Keep this smoke scoped to the settings picker itself. Sending Down /
        # Return here is unreliable under GTK focus restoration and can be
        # handled by the sidebar, selecting a transcript behind the panel and
        # hiding the home wordmark that the Mac-reference verifier checks.
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Escape
        sleep "${QUILLUI_BACKEND_MODEL_PICKER_SETTLE_SLEEP:-$post_click_sleep}"
        refocus_capture_window
        ;;
      settings-delete-confirmation)
        open_quill_chat_settings_delete_confirmation
        refresh_capture_window_for_active_child_window
        ;;
      settings-delete-confirmed)
        confirm_quill_chat_settings_delete
        ;;
      completions-panel)
        open_quill_chat_completions_panel
        ;;
      completions-new-sheet)
        open_quill_chat_new_completion_sheet
        ;;
      completions-save)
        save_quill_chat_new_completion
        ;;
      completions-edit-save)
        edit_quill_chat_existing_completion
        ;;
      completions-delete)
        delete_quill_chat_completion
        ;;
      copy-chat)
        copy_quill_chat_transcript
        ;;
      copy-chat-json)
        copy_quill_chat_transcript 1
        ;;
      toolbar-model-selected)
        select_quill_chat_toolbar_model_and_send_prompt
        ;;
      history-selection)
        click_history_selection=1
        if quill_chat_should_trust_startup_history_selection; then
          sleep "${QUILLUI_BACKEND_INITIAL_SELECTION_SETTLE_SLEEP:-2}"
          if quill_chat_verified_selection_probe quill-chat-linux-mac-reference-history-selection; then
            click_history_selection=0
          else
            echo "interaction-check: startup history selection did not verify history state; clicking markdown row" >&2
          fi
        fi
        if [[ "$click_history_selection" == "1" ]]; then
          click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 190))}"
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_mac_reference_history_row_y markdown-transcript)}"
          click_at "$click_x" "$click_y"
          sleep 1
        fi
        ;;
      transcript-selection|markdown-transcript-selection)
        select_quill_chat_markdown_transcript
        ;;
      message-hover-actions)
        hover_quill_chat_message_actions
        ;;
      long-transcript-selection|long-transcript-auto-selection)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 220))}"
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_mac_reference_history_row_y long-transcript)}"
        else
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 514))}"
        fi
        sleep 2
        if quill_chat_should_trust_startup_history_selection; then
          sleep 1
        else
          click_at "$click_x" "$click_y"
          sleep 1
          click_at "$click_x" "$click_y"
          sleep 1
        fi
        if [[ "$INTERACTION_MODE" == "long-transcript-auto-selection" ]]; then
          # QuillMessageList retries Linux ScrollViewReader bottom-scroll at 5s
          # and 8s while GTK finishes laying out long transcripts. Keep the
          # manual scroll as a verifier fallback; CI runners sometimes settle
          # before the deferred auto-scroll reaches the final transcript rows.
          sleep "${QUILLUI_BACKEND_AUTOSCROLL_AFTER_SLEEP:-9}"
        fi
        ensure_quill_chat_long_transcript_bottom_scroll
        ;;
      prompt-send)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 820))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 610))}"
        click_at "$click_x" "$click_y"
        sleep 3
        ;;
      *)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 84))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 54))}"
        click_at "$click_x" "$click_y"
        sleep 1
        ;;
    esac
elif [[ "$PRODUCT" == "quill-wireguard" && "$SELECTED_BACKEND" == "gtk" ]]; then
    case "$INTERACTION_MODE" in
      tunnel-name-edit|name-edit)
        edit_wireguard_tunnel_name
        ;;
      import-paste|paste-import|import-invalid-paste|invalid-paste-import|import-malformed-paste|malformed-paste-import)
        import_x="${QUILLUI_BACKEND_IMPORT_CLICK_X:-$((window_x + 270))}"
        import_y="${QUILLUI_BACKEND_IMPORT_CLICK_Y:-$((window_y + 30))}"
        editor_x="${QUILLUI_BACKEND_IMPORT_EDITOR_X:-$((window_x + 520))}"
        editor_y="${QUILLUI_BACKEND_IMPORT_EDITOR_Y:-$((window_y + 190))}"
        click_at "$import_x" "$import_y"
        sleep 0.8
        click_at "$editor_x" "$editor_y"
        sleep 0.2
        if [[ "$wireguard_gtk_import_uses_prefill" != "1" ]]; then
          import_configuration="$(wireguard_import_configuration_for_mode "$INTERACTION_MODE")" || exit $?
          type_multiline_text "$import_configuration"
          sleep 0.4
        fi
        # Submit via Ctrl+Return so paste and prefilled-file imports share the same
        # deterministic action path. SwiftOpenUI maps Ctrl (-> .command) + Return to
        # the button's .keyboardShortcut(.return) at the window level (a plain Return
        # would only insert a newline in the focused editor). Mirrors the Qt import
        # branch below.
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+Return
        sleep "$post_click_sleep"
        # A valid import settles into static detail landmarks the post-click sleep
        # already covers, but an invalid import paints an async error overlay that
        # can land after the fixed sleep -- so poll-capture until that overlay is
        # render-stable before the verifier reads it. (Mirrors the Qt invalid
        # branch, which already re-resolves the active child window.)
        if quillui_is_wireguard_malformed_import_interaction "$INTERACTION_MODE"; then
          # Belt-and-suspenders: if Ctrl+Return wasn't delivered (no error overlay
          # yet), force the submit with an Import-button click before settling. This
          # is a no-op when the overlay is already up, so the healthy Ctrl+Return
          # path -- and CI behavior -- is unchanged.
          quillui_wireguard_force_import_submit_if_unsettled \
            "$DISPLAY_ID" "$capture_window" "$SCREENSHOT_PATH" \
            "${QUILLUI_BACKEND_IMPORT_SUBMIT_X:-$((window_x + 358))}" \
            "${QUILLUI_BACKEND_IMPORT_SUBMIT_Y:-$((window_y + 293))}"
          quillui_settle_wireguard_import_error_capture \
            "$DISPLAY_ID" "$capture_window" "$SCREENSHOT_PATH"
          settled_capture_taken=1
        fi
        ;;
      import-file|file-import|import-invalid-file|invalid-file-import|import-malformed-file|malformed-file-import)
        # Drive headless file import through the same editor path as paste import:
        # the Linux fallback preloads the selected .conf fixture into the editor,
        # then Ctrl+Return submits through the UI action.
        import_x="${QUILLUI_BACKEND_IMPORT_CLICK_X:-$((window_x + 270))}"
        import_y="${QUILLUI_BACKEND_IMPORT_CLICK_Y:-$((window_y + 30))}"
        editor_x="${QUILLUI_BACKEND_IMPORT_EDITOR_X:-$((window_x + 520))}"
        editor_y="${QUILLUI_BACKEND_IMPORT_EDITOR_Y:-$((window_y + 190))}"
        file_configuration="$(cat "$import_file")"
        click_at "$import_x" "$import_y"
        sleep 0.8
        click_at "$editor_x" "$editor_y"
        sleep 0.2
        if [[ "$wireguard_gtk_import_uses_prefill" != "1" ]]; then
          type_multiline_text "$file_configuration"
          sleep 0.4
        fi
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+Return
        sleep "$post_click_sleep"
        # Invalid file imports paint the same async error overlay as the invalid
        # paste path, so settle on a render-stable error frame before verifying.
        if quillui_is_wireguard_malformed_import_interaction "$INTERACTION_MODE"; then
          # Same Ctrl+Return-not-delivered fallback as the invalid-paste branch.
          quillui_wireguard_force_import_submit_if_unsettled \
            "$DISPLAY_ID" "$capture_window" "$SCREENSHOT_PATH" \
            "${QUILLUI_BACKEND_IMPORT_SUBMIT_X:-$((window_x + 358))}" \
            "${QUILLUI_BACKEND_IMPORT_SUBMIT_Y:-$((window_y + 293))}"
          quillui_settle_wireguard_import_error_capture \
            "$DISPLAY_ID" "$capture_window" "$SCREENSHOT_PATH"
          settled_capture_taken=1
        fi
        ;;
      *)
        echo "Unsupported WireGuard GTK interaction mode: $INTERACTION_MODE" >&2
        exit 64
        ;;
    esac
elif [[ "$PRODUCT" == "quill-wireguard" && "$SELECTED_BACKEND" == "qt" ]]; then
    case "$INTERACTION_MODE" in
      tunnel-selection|click)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 150))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 150))}"
        click_at "$click_x" "$click_y"
        sleep "$post_click_sleep"
        ;;
      tunnel-name-edit|name-edit)
        edit_wireguard_tunnel_name
        ;;
      import-paste|paste-import|import-invalid-paste|invalid-paste-import|import-malformed-paste|malformed-paste-import)
        import_x="${QUILLUI_BACKEND_IMPORT_CLICK_X:-$((window_x + 260))}"
        import_y="${QUILLUI_BACKEND_IMPORT_CLICK_Y:-$((window_y + 30))}"
        editor_x="${QUILLUI_BACKEND_IMPORT_EDITOR_X:-$((window_x + window_width / 2))}"
        editor_y="${QUILLUI_BACKEND_IMPORT_EDITOR_Y:-$((window_y + 230))}"
        click_at "$import_x" "$import_y"
        sleep 0.8
        click_at "$editor_x" "$editor_y"
        sleep 0.2
        import_configuration="$(wireguard_import_configuration_for_mode "$INTERACTION_MODE")" || exit $?
        type_multiline_text "$import_configuration"
        sleep 0.4
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+Return
        sleep "$post_click_sleep"
        if quillui_is_wireguard_malformed_import_interaction "$INTERACTION_MODE"; then
          refresh_capture_window_for_active_child_window
        fi
        ;;
      import-file|file-import|import-invalid-file|invalid-file-import|import-malformed-file|malformed-file-import)
        sleep "$post_click_sleep"
        if quillui_is_wireguard_malformed_import_file_interaction "$INTERACTION_MODE"; then
          refresh_capture_window_for_active_child_window
        fi
        ;;
      *)
        echo "Unsupported WireGuard Qt interaction mode: $INTERACTION_MODE" >&2
        exit 64
        ;;
    esac
elif [[ "$PRODUCT" == "quill-enchanted" && ( "$SELECTED_BACKEND" == "gtk" || "$SELECTED_BACKEND" == "qt" ) ]]; then
    case "$INTERACTION_MODE" in
      composer-typed)
        # Behavioral parity: type into the Enchanted composer (lower portion of
        # the detail pane) and verify the text renders. The composer accepts
        # input without an Ollama model selected.
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + (window_width * 56 / 100)))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 96))}"
        click_at "$click_x" "$click_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-hello from linux}"
        sleep 1
        ;;
      new-chat)
        # Behavioral parity: click "New chat" to create + select a conversation.
        # An accent-selected conversation row then appears in the sidebar list.
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 150))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 124))}"
        click_at "$click_x" "$click_y"
        sleep 1
        ;;
      message-sent)
        # Behavioral parity: type a message then click Send. A successful send
        # clears the composer and moves the text into the transcript.
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + (window_width * 56 / 100)))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 96))}"
        click_at "$click_x" "$click_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-hello from linux}"
        sleep 1
        send_x="${QUILLUI_BACKEND_SEND_CLICK_X:-$((window_x + (window_width * 84 / 100)))}"
        send_y="${QUILLUI_BACKEND_SEND_CLICK_Y:-$((window_y + window_height - 39))}"
        click_at "$send_x" "$send_y"
        sleep 2
        ;;
      message-sent-keyboard)
        # Behavioral parity: type a message then press Ctrl+Return to send via the
        # keyboard (maps to the Send button's .keyboardShortcut(.return)). Same
        # end state as message-sent (blue "You" bubble in the transcript).
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + (window_width * 56 / 100)))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 96))}"
        click_at "$click_x" "$click_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-hello from linux}"
        sleep 1
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+Return
        sleep 2
        ;;
      clear-all)
        # Behavioral parity: with conversations seeded, click "Clear all" to
        # remove them; the sidebar returns to its "No saved chats yet" state.
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 205))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 158))}"
        click_at "$click_x" "$click_y"
        sleep 1
        ;;
      *)
        run_list_selection_or_header_interaction "Enchanted $(backend_label_for_message "$SELECTED_BACKEND")" click_enchanted_list_selection
        ;;
    esac
elif [[ "$SELECTED_BACKEND" == "gtk" ]] && quillui_is_backend_chat_gtk_list_selection_app_product "$PRODUCT"; then
    run_list_selection_or_header_interaction "chat GTK" click_chat_list_selection
elif [[ "$SELECTED_BACKEND" == "gtk" ]] && quillui_is_backend_generic_gtk_list_selection_app_product "$PRODUCT"; then
    run_list_selection_or_header_interaction "generic GTK" click_generic_backend_list_selection
elif [[ "$SELECTED_BACKEND" == "qt" ]] && quillui_is_backend_generic_qt_app_product "$PRODUCT"; then
    run_list_selection_or_header_interaction "generic Qt" click_generic_backend_list_selection
elif quillui_is_backend_smoke_product "$PRODUCT"; then
    INTERACTION_MODE="$(quillui_normalize_backend_smoke_interaction_mode "$INTERACTION_MODE")"
    case "$INTERACTION_MODE" in
      sidebar-button)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 110))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 282))}"
        ;;
      banner-button)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 450))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 370))}"
        ;;
      nested-sheet)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 110))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 457))}"
        ;;
      sidebar-sheet)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 150))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 508))}"
        ;;
      banner-sheet)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 450))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 590))}"
        ;;
      open-panel|*)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 84))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 34))}"
        ;;
    esac
    # Click-and-converge on the row's verified state. On starved CI runners
    # a click is occasionally delivered late or its action fires TWICE (the
    # app-log marker showed isOpen=true then false from one synthetic click,
    # toggling the panel straight back closed), so "did any pixel change" is
    # unsound. Each attempt captures the window and checks the row's ACTUAL
    # verifier condition, re-clicking until the expected post-interaction
    # state is reached; the verified capture becomes the final screenshot.
    smoke_attempt_screenshot="${SCREENSHOT_PATH%.png}-attempt.png"
    smoke_verify_product=""
    quillui_backend_interaction_verify_product "$PRODUCT" "$INTERACTION_MODE" smoke_verify_product
    smoke_click_attempts=0
    smoke_click_max="${QUILLUI_BACKEND_SMOKE_CLICK_ATTEMPTS:-3}"
    while true; do
      smoke_click_attempts=$((smoke_click_attempts + 1))
      click_at "$click_x" "$click_y"
      sleep "$post_click_sleep"
      if quillui_is_backend_smoke_sheet_interaction "$INTERACTION_MODE"; then
        refresh_capture_window_for_sheet_interaction
        quillui_wait_for_window_geometry_change "$DISPLAY_ID" "$capture_window" \
          "$window_width" "$window_height" "${QUILLUI_BACKEND_SHEET_WAIT_SECONDS:-8}" || true
      fi
      capture_backend_screenshot "$smoke_attempt_screenshot" >/dev/null 2>&1 || true
      if "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$smoke_attempt_screenshot" "$smoke_verify_product" >/dev/null 2>&1; then
        mv -f "$smoke_attempt_screenshot" "$SCREENSHOT_PATH"
        settled_capture_taken=1
        break
      fi
      if (( smoke_click_attempts >= smoke_click_max )); then
        echo "interaction-check: smoke interaction did not reach its verified state after" \
          "$smoke_click_attempts attempts at ($click_x,$click_y) mode='$INTERACTION_MODE'" >&2
        mv -f "$smoke_attempt_screenshot" "$SCREENSHOT_PATH" 2>/dev/null || true
        settled_capture_taken=1
        break
      fi
      echo "interaction-check: smoke attempt $smoke_click_attempts not yet in verified state; re-clicking" >&2
    done
else
    click_backend_header_action
fi
if [[ "$settled_capture_taken" != "1" ]]; then
  capture_backend_screenshot "$SCREENSHOT_PATH"
fi

verify_quill_chat_copy_clipboard_if_needed() {
  [[ "$PRODUCT" == "quill-chat-linux" && ( "$INTERACTION_MODE" == "copy-chat" || "$INTERACTION_MODE" == "copy-chat-json" ) ]] || return 0

  local clipboard_file="$quill_chat_copy_runtime_dir/quill-pasteboard/Apple.NSGeneralPboard/types/public.utf8-plain-text"
  local action_title="Copy Chat"
  if [[ "$INTERACTION_MODE" == "copy-chat-json" ]]; then
    action_title="Copy Chat as JSON"
  fi

  if [[ ! -s "$clipboard_file" && -n "$quill_gtk_toolbar_action_command_dir" ]]; then
    echo "Copy Chat pasteboard file is not ready; retrying toolbar action command: $action_title" >&2
    emit_quill_chat_toolbar_action_command "$action_title" || true
    wait_for_quill_chat_copy_clipboard "$clipboard_file" || true
  fi

  if [[ ! -s "$clipboard_file" ]]; then
    echo "Copy Chat did not write a plain-text pasteboard file: $clipboard_file" >&2
    return 65
  fi

  if [[ "$INTERACTION_MODE" == "copy-chat-json" ]]; then
    python3 - "$clipboard_file" <<'PY'
import json
import sys

clipboard_file = sys.argv[1]
with open(clipboard_file, encoding="utf-8") as stream:
    payload = json.load(stream)
if not isinstance(payload, list):
    raise SystemExit("Copy Chat as JSON did not produce a top-level list")
roles = [item.get("role") for item in payload if isinstance(item, dict)]
contents = "\n".join(str(item.get("content", "")) for item in payload if isinstance(item, dict))
if "user" not in roles or "assistant" not in roles:
    raise SystemExit(f"Copy Chat as JSON roles are incomplete: {roles}")
if "How to center div in HTML?" not in contents or "Use **flexbox**" not in contents or "justify-content" not in contents:
    raise SystemExit("Copy Chat as JSON did not contain the selected transcript")
PY
    printf 'Copy Chat as JSON pasteboard text verified: %s\n' "$clipboard_file"
    return 0
  fi

  if ! grep -Fq "User: How to center div in HTML?" "$clipboard_file" \
      || ! grep -Fq "Assistant: Use **flexbox**" "$clipboard_file" \
      || ! grep -Fq "justify-content" "$clipboard_file"; then
    echo "Copy Chat pasteboard text did not contain the selected transcript." >&2
    sed -n '1,12p' "$clipboard_file" >&2
    return 65
  fi

  printf 'Copy Chat pasteboard text verified: %s\n' "$clipboard_file"
}

quill_chat_deleted_records_cleared() {
  local database_path="$1"

  python3 - "$database_path" <<'PY'
import sqlite3
import sys

database_path = sys.argv[1]
connection = sqlite3.connect(database_path)
tables = [
    row[0]
    for row in connection.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table'"
    )
]
if "quillDataRecords" in tables:
    rows = connection.execute(
        """
        SELECT "modelType", COUNT(*)
        FROM "quillDataRecords"
        WHERE "modelType" LIKE '%.ConversationSD'
           OR "modelType" LIKE '%.MessageSD'
        GROUP BY "modelType"
        """
    ).fetchall()
else:
    rows = []
    for table in tables:
        if table.endswith("_ConversationSD") or table.endswith("_MessageSD"):
            count = connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
            if count:
                rows.append((table, count))
connection.close()
if rows:
    print(rows)
    raise SystemExit(1)
PY
}

verify_quill_chat_delete_confirmed_if_needed() {
  [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "settings-delete-confirmed" ]] || return 0

  local database_path="$OUTPUT_DIR/$PRODUCT-reference-home/.quilldata/default.sqlite"
  if [[ ! -f "$database_path" ]]; then
    echo "QuillData database for delete confirmation was not found: $database_path" >&2
    return 65
  fi

  local attempt
  for attempt in {1..20}; do
    if quill_chat_deleted_records_cleared "$database_path" >/tmp/quill-chat-delete-confirmed-counts.txt 2>&1; then
      printf 'Settings delete confirmed cleared conversation data: %s\n' "$database_path"
      return 0
    fi
    sleep 0.25
  done

  echo "Settings delete confirmation did not clear ConversationSD/MessageSD rows." >&2
  cat /tmp/quill-chat-delete-confirmed-counts.txt >&2 || true
  return 65
}

quill_chat_completion_seed_records_deleted() {
  local database_path="$1"

  python3 - "$database_path" <<'PY'
import json
import sqlite3
import sys

database_path = sys.argv[1]
target_names = {"Linux Saved Completion", "Linux Edited Completion"}
connection = sqlite3.connect(database_path)
matches = []
completion_table_seen = False
for (table,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'"):
    if not table.endswith("_CompletionInstructionSD"):
        continue
    completion_table_seen = True
    for row in connection.execute(f'SELECT payload FROM "{table}"'):
        payload = row[0]
        if isinstance(payload, bytes):
            payload = payload.decode("utf-8")
        item = json.loads(payload)
        name = item.get("name")
        if name in target_names:
            matches.append((table, name))
connection.close()
if not completion_table_seen:
    print("No CompletionInstructionSD table was found")
    raise SystemExit(1)
if matches:
    print(matches)
    raise SystemExit(1)
PY
}

verify_quill_chat_completion_deleted_if_needed() {
  [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "completions-delete" ]] || return 0

  local database_path="$OUTPUT_DIR/$PRODUCT-reference-home/.quilldata/default.sqlite"
  if [[ ! -f "$database_path" ]]; then
    echo "QuillData database for completion deletion was not found: $database_path" >&2
    return 65
  fi

  local attempt
  for attempt in {1..20}; do
    if quill_chat_completion_seed_records_deleted "$database_path" >/tmp/quill-chat-completion-delete-records.txt 2>&1; then
      printf 'Completions delete removed seeded completion records: %s\n' "$database_path"
      return 0
    fi
    sleep 0.25
  done

  echo "Completions delete left seeded completion records in QuillData." >&2
  cat /tmp/quill-chat-completion-delete-records.txt >&2 || true
  return 65
}

quill_chat_latest_conversation_uses_model() {
  local database_path="$1"
  local expected_model="$2"

  python3 - "$database_path" "$expected_model" <<'PY'
import json
import sqlite3
import sys

database_path = sys.argv[1]
expected_model = sys.argv[2]
connection = sqlite3.connect(database_path)
latest = None
for (table,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'"):
    if not table.endswith("_ConversationSD"):
        continue
    for (_key, payload) in connection.execute(f'SELECT * FROM "{table}"'):
        item = json.loads(bytes(payload).decode("utf-8"))
        timestamp = float(item.get("createdAt") or item.get("updatedAt") or 0)
        model_name = (item.get("model") or {}).get("name")
        if latest is None or timestamp > latest[0]:
            latest = (timestamp, model_name, item.get("name"))
connection.close()
if latest and latest[1] == expected_model:
    print(latest)
    raise SystemExit(0)
print(latest)
raise SystemExit(1)
PY
}

verify_quill_chat_toolbar_model_selected_if_needed() {
  [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "toolbar-model-selected" ]] || return 0

  local database_path="$OUTPUT_DIR/$PRODUCT-reference-home/.quilldata/default.sqlite"
  local selected_model="${QUILLUI_BACKEND_SELECTED_MODEL_NAME:-mistral-7b-reference-linux-picker:latest}"
  if [[ ! -f "$database_path" ]]; then
    echo "QuillData database for toolbar model selection was not found: $database_path" >&2
    return 65
  fi

  local attempt
  for attempt in {1..20}; do
    if quill_chat_latest_conversation_uses_model "$database_path" "$selected_model" >/tmp/quill-chat-toolbar-model-selected.txt 2>&1; then
      printf 'Toolbar model selection verified through QuillData: %s\n' "$selected_model"
      return 0
    fi
    sleep 0.25
  done

  echo "Toolbar model selection did not persist the expected chat model: $selected_model" >&2
  cat /tmp/quill-chat-toolbar-model-selected.txt >&2 || true
  return 65
}

VERIFY_PRODUCT=""
quillui_backend_interaction_verify_product "$PRODUCT" "$INTERACTION_MODE" VERIFY_PRODUCT
if "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"; then
  verify_quill_chat_copy_clipboard_if_needed || {
    copy_status=$?
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_BACKEND_INTERACTION_APP_LOG_LINES:-80}"
    exit "$copy_status"
  }
  verify_quill_chat_delete_confirmed_if_needed || {
    delete_status=$?
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_BACKEND_INTERACTION_APP_LOG_LINES:-80}"
    exit "$delete_status"
  }
  verify_quill_chat_completion_deleted_if_needed || {
    completion_delete_status=$?
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_BACKEND_INTERACTION_APP_LOG_LINES:-80}"
    exit "$completion_delete_status"
  }
  verify_quill_chat_toolbar_model_selected_if_needed || {
    model_status=$?
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_BACKEND_INTERACTION_APP_LOG_LINES:-80}"
    exit "$model_status"
  }
else
  verify_status=$?
  retry_backend_interaction_if_transient "$verify_status" || true
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_BACKEND_INTERACTION_APP_LOG_LINES:-80}"
  exit "$verify_status"
fi
