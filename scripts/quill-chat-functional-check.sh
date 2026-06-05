#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-chat-linux-functional-composer-send.png}"
PRODUCT="${2:-quill-chat-linux}"
REQUESTED_BACKEND="${3:-gtk}"
APP_EXECUTABLE=""
APP_LOG_PATH="${QUILLUI_FUNCTIONAL_APP_LOG:-/tmp/quill-chat-functional-app.log}"
MOCK_LOG_PATH="${QUILLUI_FUNCTIONAL_MOCK_LOG:-/tmp/quill-chat-functional-ollama.log}"
RUN_HOME="${QUILLUI_FUNCTIONAL_HOME:-$OUTPUT_DIR/quill-chat-functional-home}"
MESSAGE_TEXT="${QUILLUI_FUNCTIONAL_MESSAGE:-hello from linux}"
REPLY_TEXT="${QUILLUI_FUNCTIONAL_REPLY:-Linux composer reply}"
MODEL_NAME="${QUILLUI_FUNCTIONAL_MODEL:-llava:latest}"
MOCK_HOST="${QUILLUI_FUNCTIONAL_OLLAMA_HOST:-127.0.0.1}"
MOCK_PORT="${QUILLUI_FUNCTIONAL_OLLAMA_PORT:-11434}"
mock_pid=""
DISPLAY_ID=""
xvfb_pid=""
openbox_pid=""
app_pid=""
capture_window="root"

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

quillui_export_backend_argument "$REQUESTED_BACKEND" "$PRODUCT"
SELECTED_BACKEND="$(quillui_require_requested_backend_for_product "$PRODUCT")"
quillui_alias_backend_build_env
quillui_install_linux_backend_smoke_packages

mkdir -p "$(dirname "$SCREENSHOT_PATH")"
rm -rf "$RUN_HOME"
mkdir -p "$RUN_HOME"
rm -f "$APP_LOG_PATH" "$MOCK_LOG_PATH"

quillui_resolve_linux_backend_executable "$PRODUCT" APP_EXECUTABLE
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Built executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

if ! command -v xdotool >/dev/null 2>&1; then
  echo "xdotool is required for the Quill Chat functional check" >&2
  exit 69
fi

python3 "$ROOT_DIR/scripts/mock-ollama.py" \
  --host "$MOCK_HOST" \
  --port "$MOCK_PORT" \
  --log "$MOCK_LOG_PATH" \
  --model "$MODEL_NAME" \
  --reply "$REPLY_TEXT" &
mock_pid=$!

reference_window_width=""
reference_window_height=""
hide_window_menubar_label=""
quillui_backend_reference_window_defaults \
  reference_window_width \
  reference_window_height \
  hide_window_menubar_label

DISPLAY_ID="$(quillui_normalize_x_display_id "${QUILLUI_FUNCTIONAL_DISPLAY:-:96}")"
SCREEN_SIZE="${QUILLUI_FUNCTIONAL_SCREEN_SIZE:-${reference_window_width}x${reference_window_height}x24}"
cleanup() {
  quillui_stop_process_if_running "$app_pid"
  quillui_stop_process_if_running "$openbox_pid"
  quillui_stop_process_if_running "$xvfb_pid"
  quillui_stop_process_if_running "$mock_pid"
}

on_exit() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    if [[ -n "${DISPLAY_ID:-}" ]] && command -v import >/dev/null 2>&1; then
      DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH" 2>/dev/null || true
      if [[ -f "$SCREENSHOT_PATH" ]]; then
        echo "Functional failure screenshot: $SCREENSHOT_PATH" >&2
      fi
    fi
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
    if [[ -s "$MOCK_LOG_PATH" ]]; then
      echo "Mock Ollama log ($MOCK_LOG_PATH):" >&2
      tail -n 80 "$MOCK_LOG_PATH" >&2 || true
    fi
  fi
  cleanup
  exit "$exit_code"
}
trap on_exit EXIT

python3 - "$MOCK_HOST" "$MOCK_PORT" <<'PY'
import socket
import sys
import time

host = sys.argv[1]
port = int(sys.argv[2])
deadline = time.time() + 10
while time.time() < deadline:
    try:
        with socket.create_connection((host, port), timeout=0.2):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit("mock Ollama did not start")
PY

quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" /tmp/quill-chat-functional-xvfb.log xvfb_pid
if command -v openbox >/dev/null 2>&1; then
  DISPLAY="$DISPLAY_ID" openbox >/tmp/quill-chat-functional-openbox.log 2>&1 &
  openbox_pid=$!
  sleep 1
fi

app_environment=()
quillui_append_backend_launch_environment app_environment "$PRODUCT" "$DISPLAY_ID" "$SELECTED_BACKEND"
app_environment+=(
  "HOME=$RUN_HOME"
  "QUILLDATA_HOME=$RUN_HOME"
  "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=$reference_window_width"
  "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=$reference_window_height"
  "QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label"
)
env "${app_environment[@]}" "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

sleep "${QUILLUI_FUNCTIONAL_STARTUP_SLEEP:-6}"

window_x=0
window_y=0
window_width="${reference_window_width:-1180}"
window_height="${reference_window_height:-760}"
window_id="$(quillui_find_visible_window_for_pid "$DISPLAY_ID" "$app_pid")"
if [[ -z "$window_id" ]]; then
  window_id="$(quillui_find_visible_window_by_name "$DISPLAY_ID" ".*")"
fi
if [[ -n "$window_id" ]]; then
  quillui_place_reference_window "$DISPLAY_ID" "$window_id" "$reference_window_width" "$reference_window_height"
  capture_window="$window_id"
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

click_x="${QUILLUI_FUNCTIONAL_COMPOSER_X:-$((window_x + (window_width * 56 / 100)))}"
click_y="${QUILLUI_FUNCTIONAL_COMPOSER_Y:-$((window_y + window_height - 190))}"
DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$click_x" "$click_y" click 1
sleep 1
DISPLAY="$DISPLAY_ID" xdotool type --clearmodifiers --delay 30 "$MESSAGE_TEXT"
sleep 1
DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers Return

python3 - "$MOCK_LOG_PATH" "$MESSAGE_TEXT" "$REPLY_TEXT" "$RUN_HOME" <<'PY'
from __future__ import annotations

import json
import sqlite3
import sys
import time
from pathlib import Path

mock_log = Path(sys.argv[1])
message_text = sys.argv[2]
reply_text = sys.argv[3]
home = Path(sys.argv[4])
database_path = home / ".quilldata" / "default.sqlite"


def logged_chat_request() -> dict[str, object] | None:
    if not mock_log.exists():
        return None
    for line in mock_log.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        payload = json.loads(line)
        if payload.get("path") == "/api/chat":
            return payload.get("request")
    return None


def persisted_messages() -> list[dict[str, object]]:
    if not database_path.exists():
        return []
    with sqlite3.connect(database_path) as connection:
        tables = [
            row[0]
            for row in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
            if row[0].endswith("_MessageSD")
        ]
        rows = []
        for table in tables:
            rows.extend(connection.execute(f'SELECT payload FROM "{table}"').fetchall())
    return [json.loads(bytes(row[0]).decode("utf-8")) for row in rows]


deadline = time.time() + 25
last_request = None
last_messages: list[dict[str, object]] = []
while time.time() < deadline:
    last_request = logged_chat_request()
    last_messages = persisted_messages()
    matching_request_users = [
        item
        for item in (last_request or {}).get("messages", [])
        if isinstance(item, dict)
        and item.get("role") == "user"
        and message_text in str(item.get("content", ""))
    ]
    request_ok = bool(last_request) and len(matching_request_users) == 1
    user_persisted = any(
        item.get("role") == "user" and message_text in str(item.get("content", ""))
        for item in last_messages
    )
    assistant_persisted = any(
        item.get("role") == "assistant" and reply_text in str(item.get("content", ""))
        for item in last_messages
    )
    if request_ok and user_persisted and assistant_persisted:
        print(
            "Quill Chat functional composer-send: "
            f"request_messages={len(last_request.get('messages', []))}, "
            f"persisted_messages={len(last_messages)}"
        )
        raise SystemExit(0)
    time.sleep(0.5)

print("Functional composer-send did not complete.", file=sys.stderr)
print(f"request={last_request}", file=sys.stderr)
print(f"persisted_messages={last_messages}", file=sys.stderr)
raise SystemExit(1)
PY

DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"
echo "Functional screenshot: $SCREENSHOT_PATH"
