#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-backend-interaction-smoke-open.png}"
PRODUCT="${2:-quill-gtk-interaction-smoke}"
REQUESTED_BACKEND="${3:-${QUILLUI_BACKEND:-}}"
APP_EXECUTABLE=""
APP_LOG_PATH="${QUILLUI_BACKEND_INTERACTION_APP_LOG:-/tmp/quillui-backend-interaction-app.log}"

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

app_environment=()
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
    import-file|file-import|import-invalid-file|invalid-file-import|import-malformed-file|malformed-file-import)
      import_file="$(wireguard_import_configuration_file_for_mode "$INTERACTION_MODE")" || exit $?
      if [[ "$SELECTED_BACKEND" == "qt" ]]; then
        app_environment+=("QUILLUI_WIREGUARD_QT_IMPORT_CONFIGURATION_FILE_ON_START=$import_file")
        if quillui_is_wireguard_malformed_import_file_interaction "$INTERACTION_MODE"; then
          app_environment+=("QUILLUI_WIREGUARD_QT_IMPORT_DIALOG_ON_START=1")
        fi
      else
        app_environment+=("QUILLUI_FILE_IMPORTER_SELECTION=$import_file")
      fi
      ;;
  esac
fi
quillui_append_backend_selection_start_environment \
  app_environment \
  "$PRODUCT" \
  "$SELECTED_BACKEND" \
  "$INTERACTION_MODE" \
  "$OUTPUT_DIR"
if quillui_is_backend_smoke_sheet_interaction "$INTERACTION_MODE"; then
  app_environment+=("QUILLUI_GTK_SHEET_PRESENTATION=${QUILLUI_GTK_SHEET_PRESENTATION:-window}")
fi
quill_chat_copy_runtime_dir=""
if [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "copy-chat" ]]; then
  quill_chat_copy_runtime_dir="${QUILLUI_BACKEND_CLIPBOARD_RUNTIME_DIR:-$OUTPUT_DIR/quill-chat-copy-runtime}"
  rm -rf "$quill_chat_copy_runtime_dir/quill-pasteboard"
  mkdir -p "$quill_chat_copy_runtime_dir"
  chmod 700 "$quill_chat_copy_runtime_dir" 2>/dev/null || true
  app_environment+=("XDG_RUNTIME_DIR=$quill_chat_copy_runtime_dir")
fi
env "${app_environment[@]}" "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

sleep 4

capture_window="root"
# Set to 1 once an interaction has already taken the authoritative, render-stable
# screenshot itself (e.g. the WireGuard invalid-import settle); the final capture
# below then skips re-grabbing a possibly-mid-repaint frame over it.
settled_capture_taken=0
window_x=0
window_y=0
window_width="$screen_width"
window_height="$screen_height"
window_id="$(quillui_find_visible_window_for_pid "$DISPLAY_ID" "$app_pid")"
if [[ -z "$window_id" ]]; then
  window_id="$(quillui_find_visible_window_by_name "$DISPLAY_ID" ".*")"
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

click_at() {
  local x="$1"
  local y="$2"
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$x" "$y" click 1
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
      printf '%s\n' "$((window_y + 590))"
      ;;
    long-transcript)
      printf '%s\n' "$((window_y + 638))"
      ;;
    *)
      echo "Unknown Quill Chat reference history row: $1" >&2
      exit 64
      ;;
  esac
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

refresh_capture_window_for_active_child_window() {
  local attempt
  local candidate_window

  [[ "$capture_window" != "root" ]] || return 0
  [[ -n "$window_id" ]] || return 0

  for attempt in {1..20}; do
    candidate_window="$(DISPLAY="$DISPLAY_ID" xdotool getactivewindow 2>/dev/null || true)"
    if [[ -n "$candidate_window" && "$candidate_window" != "$window_id" ]]; then
      capture_window="$candidate_window"
      return 0
    fi

    candidate_window="$(quillui_find_visible_window_for_pid_except "$DISPLAY_ID" "$app_pid" "$window_id")"
    if [[ -n "$candidate_window" ]]; then
      capture_window="$candidate_window"
      return 0
    fi

    sleep 0.1
  done
}

refresh_capture_window_for_sheet_interaction() {
  refresh_capture_window_for_active_child_window
}

open_quill_chat_completions_panel() {
  local click_x
  local click_y

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    click_x="${QUILLUI_BACKEND_CLICK_X:-90}"
    click_y="${QUILLUI_BACKEND_CLICK_Y:-1244}"
  else
    click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 90))}"
    click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 136))}"
  fi
  click_at "$click_x" "$click_y"
  sleep "$post_click_sleep"
}

open_quill_chat_new_completion_sheet() {
  local new_x
  local new_y

  open_quill_chat_completions_panel
  sleep "${QUILLUI_BACKEND_NEW_COMPLETION_PRE_CLICK_SLEEP:-1.5}"
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    new_x="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_X:-1518}"
    new_y="${QUILLUI_BACKEND_NEW_COMPLETION_CLICK_Y:-498}"
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
  local save_x
  local save_y

  open_quill_chat_new_completion_sheet
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-720}"
    name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-468}"
    save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-1450}"
    save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-408}"
  else
    name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-$((window_x + window_width / 2))}"
    name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-$((window_y + 260))}"
    save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-$((window_x + window_width - 130))}"
    save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-$((window_y + 46))}"
  fi

  click_at "$name_x" "$name_y"
  sleep 0.5
  DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+a
  sleep 0.2
  type_text "${QUILLUI_BACKEND_COMPLETION_NAME_TEXT:-Linux Saved Completion}"
  sleep 0.5
  click_at "$save_x" "$save_y"
  sleep "${QUILLUI_BACKEND_COMPLETION_SAVE_SLEEP:-2}"
}

edit_quill_chat_existing_completion() {
  local edit_x
  local edit_y
  local name_x
  local name_y
  local save_x
  local save_y

  open_quill_chat_completions_panel
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    edit_x="${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_X:-1510}"
    edit_y="${QUILLUI_BACKEND_COMPLETION_EDIT_CLICK_Y:-536}"
    name_x="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_X:-720}"
    name_y="${QUILLUI_BACKEND_COMPLETION_NAME_CLICK_Y:-468}"
    save_x="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_X:-1450}"
    save_y="${QUILLUI_BACKEND_COMPLETION_SAVE_CLICK_Y:-408}"
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
}

delete_quill_chat_completion() {
  local delete_x
  local delete_y

  open_quill_chat_completions_panel
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    delete_x="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X:-1545}"
    delete_y="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_Y:-536}"
  else
    delete_x="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_X:-$((window_x + window_width - 125))}"
    delete_y="${QUILLUI_BACKEND_COMPLETION_DELETE_CLICK_Y:-$((window_y + 320))}"
  fi

  click_at "$delete_x" "$delete_y"
  sleep "${QUILLUI_BACKEND_COMPLETION_DELETE_SLEEP:-2}"
}

select_quill_chat_markdown_transcript() {
  local click_x="${QUILLUI_BACKEND_HISTORY_CLICK_X:-$((window_x + 190))}"
  local click_y

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

copy_quill_chat_transcript() {
  local menu_x
  local menu_y
  local copy_x
  local copy_y

  select_quill_chat_markdown_transcript
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    menu_x="${QUILLUI_BACKEND_MENU_CLICK_X:-1964}"
    menu_y="${QUILLUI_BACKEND_MENU_CLICK_Y:-57}"
    copy_x="${QUILLUI_BACKEND_COPY_CHAT_CLICK_X:-1940}"
    copy_y="${QUILLUI_BACKEND_COPY_CHAT_CLICK_Y:-109}"
  else
    menu_x="${QUILLUI_BACKEND_MENU_CLICK_X:-$((window_x + window_width - 84))}"
    menu_y="${QUILLUI_BACKEND_MENU_CLICK_Y:-$((window_y + 54))}"
    copy_x="${QUILLUI_BACKEND_COPY_CHAT_CLICK_X:-$((window_x + window_width - 110))}"
    copy_y="${QUILLUI_BACKEND_COPY_CHAT_CLICK_Y:-$((window_y + 92))}"
  fi

  click_at "$menu_x" "$menu_y"
  sleep 0.8
  click_at "$copy_x" "$copy_y"
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
    menu_x="${QUILLUI_BACKEND_MODEL_MENU_CLICK_X:-1887}"
    menu_y="${QUILLUI_BACKEND_MODEL_MENU_CLICK_Y:-57}"
    model_x="${QUILLUI_BACKEND_MODEL_MENU_SELECT_X:-1810}"
    model_y="${QUILLUI_BACKEND_MODEL_MENU_SELECT_Y:-134}"
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
  click_at "$model_x" "$model_y"
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
    settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-52}"
    settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-1366}"
    clear_x="${QUILLUI_BACKEND_CLEAR_ALL_CLICK_X:-1024}"
    clear_y="${QUILLUI_BACKEND_CLEAR_ALL_CLICK_Y:-1000}"
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
    delete_y="${QUILLUI_BACKEND_DELETE_CONFIRM_CLICK_Y:-96}"
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
    new_chat_x="${QUILLUI_BACKEND_NEW_CHAT_CLICK_X:-2010}"
    new_chat_y="${QUILLUI_BACKEND_NEW_CHAT_CLICK_Y:-57}"
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
        # Target the composer field CENTER. Measured from the mac-reference render
        # (PR #237): the composer spans x 647..1984 (center ~0.64*W) with its field
        # row at y~1257 (~window_height-123). The old x=0.34*W (~695) landed at the
        # field's far-left padding and y=window_height-84 (~1296) fell BELOW the field
        # row, so the click never focused the TextField (typed text -> pixels=0).
        # 0.56*W matches the reimpl's proven composer click; -120 sits on the field row.
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + (window_width * 56 / 100)))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 120))}"
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
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + (window_width * 56 / 100)))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 120))}"
        click_at "$click_x" "$click_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-hello from linux}"
        sleep 1
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Return
        sleep 3
        ;;
      new-chat)
        open_quill_chat_new_chat
        ;;
      settings-panel)
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          click_x="${QUILLUI_BACKEND_CLICK_X:-52}"
          click_y="${QUILLUI_BACKEND_CLICK_Y:-1366}"
        else
          click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 52))}"
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 14))}"
        fi
        click_at "$click_x" "$click_y"
        sleep "$post_click_sleep"
        ;;
      alert-settings-panel)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 142))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 274))}"
        click_at "$click_x" "$click_y"
        sleep "$post_click_sleep"
        ;;
      settings-endpoint-typed)
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-52}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-1366}"
          endpoint_x="${QUILLUI_BACKEND_ENDPOINT_CLICK_X:-650}"
          endpoint_y="${QUILLUI_BACKEND_ENDPOINT_CLICK_Y:-495}"
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
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-52}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-1366}"
          token_x="${QUILLUI_BACKEND_TOKEN_CLICK_X:-650}"
          token_y="${QUILLUI_BACKEND_TOKEN_CLICK_Y:-800}"
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
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-52}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-1366}"
          ping_x="${QUILLUI_BACKEND_PING_CLICK_X:-650}"
          ping_y="${QUILLUI_BACKEND_PING_CLICK_Y:-838}"
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
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-52}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-1366}"
          model_x="${QUILLUI_BACKEND_MODEL_PICKER_CLICK_X:-770}"
          model_y="${QUILLUI_BACKEND_MODEL_PICKER_CLICK_Y:-763}"
        else
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 14))}"
          model_x="${QUILLUI_BACKEND_MODEL_PICKER_CLICK_X:-$((window_x + 180))}"
          model_y="${QUILLUI_BACKEND_MODEL_PICKER_CLICK_Y:-$((window_y + 210))}"
        fi
        click_at "$settings_x" "$settings_y"
        sleep 1
        click_at "$model_x" "$model_y"
        sleep 0.5
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Down Return
        sleep "$post_click_sleep"
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
      toolbar-model-selected)
        select_quill_chat_toolbar_model_and_send_prompt
        ;;
      history-selection)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 190))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_mac_reference_history_row_y recent-transcript)}"
        click_at "$click_x" "$click_y"
        sleep 1
        ;;
      transcript-selection|markdown-transcript-selection)
        select_quill_chat_markdown_transcript
        ;;
      long-transcript-selection)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 220))}"
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$(quill_chat_mac_reference_history_row_y long-transcript)}"
        else
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 514))}"
        fi
        sleep 2
        click_at "$click_x" "$click_y"
        sleep 1
        click_at "$click_x" "$click_y"
        sleep 1
        scroll_x="${QUILLUI_BACKEND_SCROLL_X:-$((window_x + (window_width * 70 / 100)))}"
        scroll_y="${QUILLUI_BACKEND_SCROLL_Y:-$((window_y + (window_height * 48 / 100)))}"
        DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$scroll_x" "$scroll_y"
        DISPLAY="$DISPLAY_ID" xdotool click --repeat "${QUILLUI_BACKEND_SCROLL_CLICKS:-24}" --delay 25 5
        sleep 2
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
        import_x="${QUILLUI_BACKEND_IMPORT_CLICK_X:-$((window_x + 256))}"
        import_y="${QUILLUI_BACKEND_IMPORT_CLICK_Y:-$((window_y + 30))}"
        editor_x="${QUILLUI_BACKEND_IMPORT_EDITOR_X:-$((window_x + 520))}"
        editor_y="${QUILLUI_BACKEND_IMPORT_EDITOR_Y:-$((window_y + 190))}"
        click_at "$import_x" "$import_y"
        sleep 0.8
        click_at "$editor_x" "$editor_y"
        sleep 0.2
        import_configuration="$(wireguard_import_configuration_for_mode "$INTERACTION_MODE")" || exit $?
        type_multiline_text "$import_configuration"
        sleep 0.4
        # Submit via Ctrl+Return instead of clicking the Import button. The GTK
        # TextEditor expands to fill the panel and renders over the action row, so a
        # positional submit click can't reliably reach the button. SwiftOpenUI maps
        # Ctrl (-> .command) + Return to the button's .keyboardShortcut(.return) at the
        # window level (a plain Return would only insert a newline in the focused
        # editor). Mirrors the Qt import branch below.
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
        # The "Import from File" button is occluded by the expanding TextEditor and
        # can't be reliably clicked, and (unlike Qt) the GTK app has no on-start file
        # import hook. So drive the file import through the working paste path: load
        # the selected .conf fixture's contents into the editor and submit with
        # Ctrl+Return. On a headless Linux backend with no native file picker this is
        # the faithful file-import flow (the config comes from the fixture file).
        import_x="${QUILLUI_BACKEND_IMPORT_CLICK_X:-$((window_x + 256))}"
        import_y="${QUILLUI_BACKEND_IMPORT_CLICK_Y:-$((window_y + 30))}"
        editor_x="${QUILLUI_BACKEND_IMPORT_EDITOR_X:-$((window_x + 520))}"
        editor_y="${QUILLUI_BACKEND_IMPORT_EDITOR_Y:-$((window_y + 190))}"
        file_configuration="$(cat "$import_file")"
        click_at "$import_x" "$import_y"
        sleep 0.8
        click_at "$editor_x" "$editor_y"
        sleep 0.2
        type_multiline_text "$file_configuration"
        sleep 0.4
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
    click_at "$click_x" "$click_y"
    sleep "$post_click_sleep"
    if quillui_is_backend_smoke_sheet_interaction "$INTERACTION_MODE"; then
      refresh_capture_window_for_sheet_interaction
    fi
else
    click_backend_header_action
fi
if [[ "$settled_capture_taken" != "1" ]]; then
  DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"
fi

verify_quill_chat_copy_clipboard_if_needed() {
  [[ "$PRODUCT" == "quill-chat-linux" && "$INTERACTION_MODE" == "copy-chat" ]] || return 0

  local clipboard_file="$quill_chat_copy_runtime_dir/quill-pasteboard/Apple.NSGeneralPboard/types/public.utf8-plain-text"
  if [[ ! -s "$clipboard_file" ]]; then
    echo "Copy Chat did not write a plain-text pasteboard file: $clipboard_file" >&2
    return 65
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
  verify_quill_chat_toolbar_model_selected_if_needed || {
    model_status=$?
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_BACKEND_INTERACTION_APP_LOG_LINES:-80}"
    exit "$model_status"
  }
else
  verify_status=$?
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_BACKEND_INTERACTION_APP_LOG_LINES:-80}"
  exit "$verify_status"
fi
