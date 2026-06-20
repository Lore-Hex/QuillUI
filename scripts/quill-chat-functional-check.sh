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
RELAUNCH_SCREENSHOT_PATH="${QUILLUI_FUNCTIONAL_RELAUNCH_SCREENSHOT:-${SCREENSHOT_PATH%.png}-relaunch.png}"
VERIFY_RELAUNCH="${QUILLUI_FUNCTIONAL_VERIFY_RELAUNCH:-0}"
XVFB_LOG_PATH="${QUILLUI_FUNCTIONAL_XVFB_LOG:-$OUTPUT_DIR/quill-chat-functional-xvfb.log}"
OPENBOX_LOG_PATH="${QUILLUI_FUNCTIONAL_OPENBOX_LOG:-$OUTPUT_DIR/quill-chat-functional-openbox.log}"
MESSAGE_TEXT="${QUILLUI_FUNCTIONAL_MESSAGE:-hello from linux}"
REPLY_TEXT="${QUILLUI_FUNCTIONAL_REPLY:-Linux composer reply}"
MODEL_NAME="${QUILLUI_FUNCTIONAL_MODEL:-llava:latest}"
FUNCTIONAL_MODE="${QUILLUI_FUNCTIONAL_MODE:-composer-send}"
ATTACHMENT_PATH="${QUILLUI_FUNCTIONAL_ATTACHMENT_PATH:-$OUTPUT_DIR/quill-chat-functional-attachment.png}"
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

quillui_functional_xdotool() {
  local timeout_seconds="${QUILLUI_FUNCTIONAL_XDOTOOL_TIMEOUT:-10}"
  DISPLAY="$DISPLAY_ID" timeout "$timeout_seconds" xdotool "$@"
}

quillui_functional_click_at() {
  local x="$1"
  local y="$2"
  local settle_sleep="${QUILLUI_FUNCTIONAL_CLICK_SETTLE_SLEEP:-0.15}"
  local hold_sleep="${QUILLUI_FUNCTIONAL_CLICK_HOLD_SLEEP:-0.08}"

  quillui_functional_xdotool mousemove --sync "$x" "$y"
  sleep "$settle_sleep"
  quillui_functional_xdotool mousedown 1
  sleep "$hold_sleep"
  quillui_functional_xdotool mouseup 1
}

quillui_functional_refocus_window() {
  [[ -n "${window_id:-}" ]] || return 0
  quillui_functional_xdotool windowactivate --sync "$window_id" 2>/dev/null || true
  quillui_functional_xdotool windowfocus --sync "$window_id" 2>/dev/null || true
}

quillui_functional_default_display() {
  local candidate
  local number

  if [[ -n "${QUILLUI_FUNCTIONAL_DISPLAY:-}" ]]; then
    printf '%s\n' "$QUILLUI_FUNCTIONAL_DISPLAY"
    return 0
  fi

  for candidate in :96 :97 :98 :99; do
    number="${candidate#:}"
    if [[ ! -e "/tmp/.X${number}-lock" && ! -e "/tmp/.X11-unix/X${number}" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' ":96"
}

quillui_write_functional_attachment_fixture() {
  local path="$1"

  python3 - "$path" <<'PY'
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
}

case "$FUNCTIONAL_MODE" in
  composer-send|attachment-send|image-attachment-send)
    ;;
  *)
    echo "Unsupported Quill Chat functional mode: $FUNCTIONAL_MODE" >&2
    exit 64
    ;;
esac

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

DISPLAY_ID="$(quillui_normalize_x_display_id "$(quillui_functional_default_display)")"
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

python3 - "$MOCK_HOST" "$MOCK_PORT" "${QUILLUI_FUNCTIONAL_MOCK_START_DEADLINE:-10}" <<'PY'
import socket
import sys
import time

host = sys.argv[1]
port = int(sys.argv[2])
deadline_seconds = float(sys.argv[3])
deadline = time.time() + deadline_seconds
while time.time() < deadline:
    try:
        with socket.create_connection((host, port), timeout=0.2):
            raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
raise SystemExit("mock Ollama did not start")
PY

quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" "$XVFB_LOG_PATH" xvfb_pid
if command -v openbox >/dev/null 2>&1; then
  DISPLAY="$DISPLAY_ID" openbox >"$OPENBOX_LOG_PATH" 2>&1 &
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
if [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]]; then
  quillui_write_functional_attachment_fixture "$ATTACHMENT_PATH"
  app_environment+=("QUILLUI_FILE_IMPORTER_SELECTION=$ATTACHMENT_PATH")
fi

launch_app_instance() {
  local log_redirect="$1"

  if [[ "$log_redirect" == "append" ]]; then
    env "${app_environment[@]}" "$APP_EXECUTABLE" >>"$APP_LOG_PATH" 2>&1 &
  else
    env "${app_environment[@]}" "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
  fi
  app_pid=$!
  sleep "${QUILLUI_FUNCTIONAL_STARTUP_SLEEP:-6}"
}

resolve_app_window_geometry() {
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
    quillui_functional_xdotool windowactivate "$window_id" 2>/dev/null || true
    quillui_functional_xdotool windowfocus "$window_id" 2>/dev/null || true
    while IFS='=' read -r key value; do
      case "$key" in
        X) window_x="$value" ;;
        Y) window_y="$value" ;;
        WIDTH) window_width="$value" ;;
        HEIGHT) window_height="$value" ;;
      esac
    done < <(DISPLAY="$DISPLAY_ID" timeout "${QUILLUI_FUNCTIONAL_XDOTOOL_TIMEOUT:-10}" xdotool getwindowgeometry --shell "$window_id")
  fi
}

quill_chat_functional_composer_click_x() {
  printf '%s\n' "${QUILLUI_FUNCTIONAL_COMPOSER_X:-$((window_x + (window_width * 34 / 100)))}"
}

quill_chat_functional_composer_click_y() {
  quill_chat_functional_composer_click_y_candidates | head -n 1
}

quill_chat_functional_composer_click_y_candidates() {
  if [[ -n "${QUILLUI_FUNCTIONAL_COMPOSER_Y:-}" ]]; then
    printf '%s\n' "$QUILLUI_FUNCTIONAL_COMPOSER_Y"
    return
  fi

  if [[ -n "${QUILLUI_FUNCTIONAL_COMPOSER_CLICK_Y:-}" ]]; then
    printf '%s\n' "$QUILLUI_FUNCTIONAL_COMPOSER_CLICK_Y"
    return
  fi

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    local offset
    for offset in ${QUILLUI_FUNCTIONAL_COMPOSER_Y_OFFSETS:-135 310 410 220 80}; do
      printf '%s\n' "$((window_y + window_height - offset))"
    done
  else
    printf '%s\n' "$((window_y + window_height - 80))"
  fi
}

quill_chat_functional_send_attempt() {
  local click_y="$1"
  local attachment_x
  local attachment_y
  local click_x
  local send_x
  local send_y

  if [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]]; then
    attachment_x="${QUILLUI_FUNCTIONAL_ATTACHMENT_X:-$((window_x + window_width - 70))}"
    attachment_y="${QUILLUI_FUNCTIONAL_ATTACHMENT_Y:-$click_y}"
    quillui_functional_refocus_window
    quillui_functional_click_at "$attachment_x" "$attachment_y"
    sleep "${QUILLUI_FUNCTIONAL_ATTACHMENT_SELECT_SLEEP:-1}"
  fi

  click_x="$(quill_chat_functional_composer_click_x)"
  echo "functional-check: window='${window_id:-none}' geometry=${window_x},${window_y} ${window_width}x${window_height} composer=${click_x},${click_y} mode=${FUNCTIONAL_MODE}" >&2
  quillui_functional_refocus_window
  quillui_functional_click_at "$click_x" "$click_y"
  sleep 1
  quillui_functional_xdotool type --clearmodifiers --delay 30 "$MESSAGE_TEXT"
  sleep 1
  if [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]]; then
    send_x="${QUILLUI_FUNCTIONAL_SEND_X:-$((window_x + window_width - 65))}"
    send_y="${QUILLUI_FUNCTIONAL_SEND_Y:-$click_y}"
    quillui_functional_refocus_window
    quillui_functional_click_at "$send_x" "$send_y"
  else
    quillui_functional_xdotool key --clearmodifiers Return
  fi
}

quill_chat_functional_wait_for_completion() {
  local deadline_seconds="$1"
  local report_failure="${2:-1}"

  python3 - "$MOCK_LOG_PATH" "$MESSAGE_TEXT" "$REPLY_TEXT" "$RUN_HOME" "$deadline_seconds" "$FUNCTIONAL_MODE" "$report_failure" <<'PY'
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
deadline_seconds = float(sys.argv[5])
functional_mode = sys.argv[6]
report_failure = sys.argv[7] == "1"
require_attachment = functional_mode in {"attachment-send", "image-attachment-send"}
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


def request_message_has_image(message: dict[str, object]) -> bool:
    images = message.get("images")
    return isinstance(images, list) and any(isinstance(item, str) and item for item in images)


def persisted_message_has_image(message: dict[str, object]) -> bool:
    image = message.get("image")
    return image not in (None, "", [], {})


deadline = time.time() + deadline_seconds
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
        and (not require_attachment or request_message_has_image(item))
    ]
    request_ok = bool(last_request) and len(matching_request_users) == 1
    user_persisted = any(
        item.get("role") == "user" and message_text in str(item.get("content", ""))
        and (not require_attachment or persisted_message_has_image(item))
        for item in last_messages
    )
    assistant_persisted = any(
        item.get("role") == "assistant" and reply_text in str(item.get("content", ""))
        for item in last_messages
    )
    if request_ok and user_persisted and assistant_persisted:
        print(
            f"Quill Chat functional {functional_mode}: "
            f"request_messages={len(last_request.get('messages', []))}, "
            f"persisted_messages={len(last_messages)}, "
            f"attachment_required={require_attachment}"
        )
        raise SystemExit(0)
    time.sleep(0.5)

if report_failure:
    print(f"Functional {functional_mode} did not complete.", file=sys.stderr)
    print(f"request={last_request}", file=sys.stderr)
    print(f"persisted_messages={last_messages}", file=sys.stderr)
raise SystemExit(1)
PY
}

launch_app_instance truncate
resolve_app_window_geometry
if [[ "${QUILLUI_FUNCTIONAL_FOCUS_PRIME:-}" == "1" ]] || quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
  focus_x="${QUILLUI_FUNCTIONAL_FOCUS_PRIME_X:-$((window_x + window_width / 2))}"
  focus_y="${QUILLUI_FUNCTIONAL_FOCUS_PRIME_Y:-$((window_y + 54))}"
  quillui_functional_refocus_window
  quillui_functional_click_at "$focus_x" "$focus_y"
  sleep "${QUILLUI_FUNCTIONAL_FOCUS_PRIME_SLEEP:-0.5}"
fi

completion_verified=0
while IFS= read -r click_y; do
  quill_chat_functional_send_attempt "$click_y"
  if quill_chat_functional_wait_for_completion "${QUILLUI_FUNCTIONAL_ATTEMPT_DEADLINE:-8}" 0; then
    completion_verified=1
    break
  fi
done < <(quill_chat_functional_composer_click_y_candidates)

if (( completion_verified == 0 )); then
  quill_chat_functional_wait_for_completion "${QUILLUI_FUNCTIONAL_SEND_DEADLINE:-25}" 1
fi

DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"
echo "Functional screenshot: $SCREENSHOT_PATH"

if [[ "$VERIFY_RELAUNCH" == "1" ]]; then
  baseline_chat_requests="$(
    python3 - "$MOCK_LOG_PATH" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

mock_log = Path(sys.argv[1])
count = 0
if mock_log.exists():
    for line in mock_log.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        if json.loads(line).get("path") == "/api/chat":
            count += 1
print(count)
PY
  )"

  quillui_stop_process_if_running "$app_pid"
  app_pid=""
  sleep 1
  capture_window="root"

  launch_app_instance append
  resolve_app_window_geometry

  history_x="${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_X:-$((window_x + 110))}"
  # The Mac-reference sidebar starts with a day header, then the first saved
  # conversation row. Click the row band rather than the header so relaunch
  # verification actually opens the persisted transcript.
  history_y="${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_Y:-$((window_y + 172))}"
  quillui_functional_xdotool mousemove "$history_x" "$history_y" click 1
  sleep "${QUILLUI_FUNCTIONAL_RELAUNCH_SETTLE_SLEEP:-3}"

  python3 - "$MOCK_LOG_PATH" "$baseline_chat_requests" "$MESSAGE_TEXT" "$REPLY_TEXT" "$RUN_HOME" "${QUILLUI_FUNCTIONAL_RELAUNCH_DEADLINE:-15}" "$FUNCTIONAL_MODE" <<'PY'
from __future__ import annotations

import json
import sqlite3
import sys
import time
from pathlib import Path

mock_log = Path(sys.argv[1])
baseline_chat_requests = int(sys.argv[2])
message_text = sys.argv[3]
reply_text = sys.argv[4]
home = Path(sys.argv[5])
deadline_seconds = float(sys.argv[6])
functional_mode = sys.argv[7]
require_attachment = functional_mode in {"attachment-send", "image-attachment-send"}
database_path = home / ".quilldata" / "default.sqlite"


def chat_request_count() -> int:
    if not mock_log.exists():
        return 0
    count = 0
    for line in mock_log.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        if json.loads(line).get("path") == "/api/chat":
            count += 1
    return count


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


def persisted_message_has_image(message: dict[str, object]) -> bool:
    image = message.get("image")
    return image not in (None, "", [], {})


deadline = time.time() + deadline_seconds
last_request_count = 0
last_messages: list[dict[str, object]] = []
while time.time() < deadline:
    last_request_count = chat_request_count()
    last_messages = persisted_messages()
    user_persisted = any(
        item.get("role") == "user" and message_text in str(item.get("content", ""))
        and (not require_attachment or persisted_message_has_image(item))
        for item in last_messages
    )
    assistant_persisted = any(
        item.get("role") == "assistant" and reply_text in str(item.get("content", ""))
        for item in last_messages
    )
    if last_request_count == baseline_chat_requests and user_persisted and assistant_persisted:
        print(
            "Quill Chat functional relaunch: "
            f"chat_requests={last_request_count}, persisted_messages={len(last_messages)}"
            f", attachment_required={require_attachment}"
        )
        raise SystemExit(0)
    time.sleep(0.5)

print("Functional relaunch persistence did not complete.", file=sys.stderr)
print(f"baseline_chat_requests={baseline_chat_requests}", file=sys.stderr)
print(f"chat_requests={last_request_count}", file=sys.stderr)
print(f"persisted_messages={last_messages}", file=sys.stderr)
raise SystemExit(1)
PY

  DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$RELAUNCH_SCREENSHOT_PATH"
  python3 "$ROOT_DIR/scripts/verify-backend-screenshot.py" \
    "$RELAUNCH_SCREENSHOT_PATH" \
    quill-chat-linux-functional-transcript
  echo "Functional relaunch screenshot: $RELAUNCH_SCREENSHOT_PATH"
fi
