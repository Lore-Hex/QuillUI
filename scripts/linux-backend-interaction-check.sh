#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-backend-interaction-smoke-open.png}"
PRODUCT="${2:-quill-gtk-interaction-smoke}"
REQUESTED_BACKEND="${3:-${QUILLUI_BACKEND:-}}"
APP_EXECUTABLE=""

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

quillui_export_backend_argument "$REQUESTED_BACKEND" "$PRODUCT"
quillui_alias_backend_build_env
quillui_alias_backend_interaction_env

INTERACTION_MODE="${QUILLUI_BACKEND_INTERACTION_MODE:-}"
if [[ -z "$INTERACTION_MODE" ]]; then
  case "$PRODUCT" in
    quill-chat-linux) INTERACTION_MODE="toolbar-menu" ;;
    quill-wireguard-qt) INTERACTION_MODE="tunnel-name-edit" ;;
    *) INTERACTION_MODE="click" ;;
  esac
  if quillui_is_backend_smoke_product "$PRODUCT"; then
    INTERACTION_MODE="open-panel"
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

wireguard_qt_import_configuration_file() {
  local fixture_path="${QUILLUI_BACKEND_IMPORT_CONFIGURATION_FILE:-$ROOT_DIR/Tests/Fixtures/WireGuard/imported-edge.conf}"
  if [[ ! -f "$fixture_path" ]]; then
    echo "WireGuard Qt import fixture is missing: $fixture_path" >&2
    return 66
  fi

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
if [[ "$PRODUCT" == "quill-wireguard-qt" ]]; then
  case "$INTERACTION_MODE" in
    import-file|file-import)
      import_file="$(wireguard_qt_import_configuration_file)" || exit $?
      app_environment+=("QUILLUI_WIREGUARD_QT_IMPORT_CONFIGURATION_FILE_ON_START=$import_file")
      ;;
  esac
fi
env "${app_environment[@]}" "$APP_EXECUTABLE" >/tmp/quillui-backend-interaction-app.log 2>&1 &
app_pid=$!

sleep 4

capture_window="root"
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

type_text() {
  DISPLAY="$DISPLAY_ID" xdotool type --clearmodifiers --delay 30 "$1"
}

wireguard_qt_import_configuration() {
  if [[ -n "${QUILLUI_BACKEND_IMPORT_CONFIGURATION:-}" ]]; then
    printf '%s' "$QUILLUI_BACKEND_IMPORT_CONFIGURATION"
    return 0
  fi

  local fixture_path
  fixture_path="$(wireguard_qt_import_configuration_file)" || return $?

  cat "$fixture_path"
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

refresh_capture_window_for_sheet_interaction() {
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
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + (window_width * 34 / 100)))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 84))}"
        click_at "$click_x" "$click_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-hello from linux}"
        sleep 1
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
        else
          settings_x="${QUILLUI_BACKEND_SETTINGS_CLICK_X:-$((window_x + 52))}"
          settings_y="${QUILLUI_BACKEND_SETTINGS_CLICK_Y:-$((window_y + window_height - 14))}"
        fi
        endpoint_x="${QUILLUI_BACKEND_ENDPOINT_CLICK_X:-$((window_x + 120))}"
        endpoint_y="${QUILLUI_BACKEND_ENDPOINT_CLICK_Y:-$((window_y + 104))}"
        click_at "$settings_x" "$settings_y"
        sleep 1
        click_at "$endpoint_x" "$endpoint_y"
        sleep 1
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-http://127.0.0.1:11434}"
        sleep 1
        ;;
      completions-panel)
        if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
          click_x="${QUILLUI_BACKEND_CLICK_X:-90}"
          click_y="${QUILLUI_BACKEND_CLICK_Y:-1244}"
        else
          click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 90))}"
          click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + window_height - 136))}"
        fi
        click_at "$click_x" "$click_y"
        sleep "$post_click_sleep"
        ;;
      history-selection)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 190))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 466))}"
        click_at "$click_x" "$click_y"
        sleep 1
        ;;
      transcript-selection|markdown-transcript-selection)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 190))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 466))}"
        sleep 2
        click_at "$click_x" "$click_y"
        sleep 1
        click_at "$click_x" "$click_y"
        sleep 1
        ;;
      long-transcript-selection)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 220))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 514))}"
        sleep 2
        click_at "$click_x" "$click_y"
        sleep 1
        click_at "$click_x" "$click_y"
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
elif [[ "$PRODUCT" == "quill-wireguard-qt" ]]; then
    case "$INTERACTION_MODE" in
      tunnel-selection|click)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 150))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 150))}"
        click_at "$click_x" "$click_y"
        sleep "$post_click_sleep"
        ;;
      tunnel-name-edit|name-edit)
        click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + 150))}"
        click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 150))}"
        name_x="${QUILLUI_BACKEND_NAME_CLICK_X:-$((window_x + 360))}"
        name_y="${QUILLUI_BACKEND_NAME_CLICK_Y:-$((window_y + 42))}"
        click_at "$click_x" "$click_y"
        sleep 0.5
        click_at "$name_x" "$name_y"
        sleep 0.5
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+a
        type_text "${QUILLUI_BACKEND_TYPE_TEXT:-Edited Tunnel}"
        sleep "$post_click_sleep"
        ;;
      import-paste|paste-import)
        import_x="${QUILLUI_BACKEND_IMPORT_CLICK_X:-$((window_x + 292))}"
        import_y="${QUILLUI_BACKEND_IMPORT_CLICK_Y:-$((window_y + 30))}"
        editor_x="${QUILLUI_BACKEND_IMPORT_EDITOR_X:-$((window_x + window_width / 2))}"
        editor_y="${QUILLUI_BACKEND_IMPORT_EDITOR_Y:-$((window_y + 230))}"
        click_at "$import_x" "$import_y"
        sleep 0.8
        click_at "$editor_x" "$editor_y"
        sleep 0.2
        import_configuration="$(wireguard_qt_import_configuration)" || exit $?
        type_text "$import_configuration"
        sleep 0.4
        DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers ctrl+Return
        sleep "$post_click_sleep"
        ;;
      import-file|file-import)
        sleep "$post_click_sleep"
        ;;
      *)
        echo "Unsupported WireGuard Qt interaction mode: $INTERACTION_MODE" >&2
        exit 64
        ;;
    esac
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
    click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 200))}"
    click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 54))}"
    click_at "$click_x" "$click_y"
    sleep 1
fi
DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"

VERIFY_PRODUCT=""
quillui_backend_interaction_verify_product "$PRODUCT" "$INTERACTION_MODE" VERIFY_PRODUCT
"$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"
