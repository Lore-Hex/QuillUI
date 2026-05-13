#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-backend-interaction-smoke-open.png}"
PRODUCT="${2:-quill-gtk-interaction-smoke}"
APP_EXECUTABLE=""

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

quillui_alias_backend_interaction_env

INTERACTION_MODE="${QUILLUI_BACKEND_INTERACTION_MODE:-}"
if [[ -z "$INTERACTION_MODE" ]]; then
  case "$PRODUCT" in
    quill-chat-linux) INTERACTION_MODE="toolbar-menu" ;;
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

reference_window_width="${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}"
reference_window_height="${QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT:-1380}"
hide_window_menubar_label="${QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL:-1}"

DISPLAY_ID="$(quillui_normalize_x_display_id "${QUILLUI_BACKEND_INTERACTION_DISPLAY:-:95}")"
SCREEN_SIZE="$(quillui_backend_screen_size "$PRODUCT" "${QUILLUI_BACKEND_INTERACTION_SCREEN_SIZE:-}" "1180x760x24" "$reference_window_width" "$reference_window_height")"
screen_width="${SCREEN_SIZE%%x*}"
screen_height_and_depth="${SCREEN_SIZE#*x}"
screen_height="${screen_height_and_depth%%x*}"
xvfb_pid=""
quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" /tmp/quillui-xvfb-interaction.log xvfb_pid

cleanup() {
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  kill "$xvfb_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

app_environment=()
quillui_append_backend_launch_environment app_environment "$PRODUCT" "$DISPLAY_ID"
quillui_append_quill_chat_reference_environment_if_needed \
  app_environment \
  "$PRODUCT" \
  "$OUTPUT_DIR" \
  "$reference_window_width" \
  "$reference_window_height" \
  "$hide_window_menubar_label"
env "${app_environment[@]}" "$APP_EXECUTABLE" >/tmp/quillui-backend-interaction-app.log 2>&1 &
app_pid=$!

sleep 4

capture_window="root"
window_x=0
window_y=0
window_width="$screen_width"
window_height="$screen_height"
window_id="$(
  DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --pid "$app_pid" 2>/dev/null | head -n 1 || true
)"
if [[ -z "$window_id" ]]; then
  window_id="$(
    DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --name '.*' 2>/dev/null | head -n 1 || true
  )"
fi
if [[ -n "$window_id" ]]; then
  DISPLAY="$DISPLAY_ID" xdotool windowmove "$window_id" 0 0
  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    DISPLAY="$DISPLAY_ID" xdotool windowsize "$window_id" "$reference_window_width" "$reference_window_height"
    sleep 1
  elif [[ "${QUILLUI_BACKEND_CAPTURE_ROOT:-0}" != "1" ]]; then
    capture_window="$window_id"
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
elif quillui_is_backend_smoke_product "$PRODUCT"; then
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
else
    click_x="${QUILLUI_BACKEND_CLICK_X:-$((window_x + window_width - 200))}"
    click_y="${QUILLUI_BACKEND_CLICK_Y:-$((window_y + 54))}"
    click_at "$click_x" "$click_y"
    sleep 1
fi
DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"

if [[ "$PRODUCT" == "quill-chat-linux" ]]; then
  case "$INTERACTION_MODE" in
    composer-typed)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-composer-typed}"
      ;;
    settings-panel)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-settings-panel}"
      ;;
    alert-settings-panel)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-settings-panel}"
      ;;
    settings-endpoint-typed)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-settings-endpoint-typed}"
      ;;
    completions-panel)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-completions-panel}"
      ;;
    history-selection)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-history-selection}"
      ;;
    transcript-selection)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-transcript-selection}"
      ;;
    markdown-transcript-selection)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-markdown-transcript-selection}"
      ;;
    long-transcript-selection)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-long-transcript-selection}"
      ;;
    prompt-send)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-prompt-send}"
      ;;
    *)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-toolbar-menu}"
      if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
        VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-quill-chat-linux-mac-reference-toolbar-menu}"
      fi
      ;;
  esac
  "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"
elif quillui_is_backend_smoke_product "$PRODUCT"; then
  smoke_prefix="$PRODUCT"
  case "$INTERACTION_MODE" in
    nested-sheet|sidebar-sheet|banner-sheet)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-${smoke_prefix}-sheet}"
      ;;
    sidebar-button)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-${smoke_prefix}-sidebar}"
      ;;
    banner-button)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-${smoke_prefix}-banner}"
      ;;
    open-panel|*)
      VERIFY_PRODUCT="${QUILLUI_BACKEND_VERIFY_PRODUCT:-${smoke_prefix}-open}"
      ;;
  esac
  "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"
else
  "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$PRODUCT"
fi
