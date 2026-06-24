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

  quillui_functional_xdotool mousemove "$x" "$y"
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
quillui_append_enchanted_reference_mode_environment app_environment
if [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]]; then
  quillui_write_functional_attachment_fixture "$ATTACHMENT_PATH"
  app_environment+=("QUILLUI_FILE_IMPORTER_SELECTION=$ATTACHMENT_PATH")
  app_environment+=("QUILLUI_FILE_IMPORTER_AUTO_ATTACH=1")
  app_environment+=("QUILLUI_QUILL_CHAT_REFERENCE_VISION_MODEL=1")
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
  quill_chat_functional_composer_click_x_candidates | head -n 1
}

quill_chat_functional_composer_click_x_candidates() {
  if [[ -n "${QUILLUI_FUNCTIONAL_COMPOSER_X:-}" ]]; then
    printf '%s\n' "$QUILLUI_FUNCTIONAL_COMPOSER_X"
    return
  fi

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    local ratio
    local reference_width="${reference_window_width:-$window_width}"
    for ratio in ${QUILLUI_FUNCTIONAL_COMPOSER_X_RATIOS:-34 50 56}; do
      printf '%s\n' "$((window_x + (reference_width * ratio / 100)))"
    done
    printf '%s\n' "$((window_x + (window_width * 34 / 100)))"
  else
    printf '%s\n' "$((window_x + (window_width * 34 / 100)))"
  fi
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
    local reference_height="${reference_window_height:-$window_height}"
    for offset in ${QUILLUI_FUNCTIONAL_COMPOSER_REFERENCE_Y_OFFSETS:-135 170 100 220}; do
      printf '%s\n' "$((window_y + reference_height - offset))"
    done
    for offset in ${QUILLUI_FUNCTIONAL_COMPOSER_Y_OFFSETS:-135 310 410 220 80}; do
      printf '%s\n' "$((window_y + window_height - offset))"
    done
  else
    printf '%s\n' "$((window_y + window_height - 80))"
  fi
}

quill_chat_functional_detected_composer_click_points() {
  quillui_is_quill_chat_mac_reference_product "$PRODUCT" || return 0
  command -v import >/dev/null 2>&1 || return 0

  local probe_path="${QUILLUI_FUNCTIONAL_COMPOSER_PROBE:-$OUTPUT_DIR/quill-chat-functional-composer-probe.png}"
  if ! DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$probe_path" 2>/dev/null; then
    return 0
  fi

  python3 - "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "$window_x" "$window_y" 2>/dev/null <<'PY' || true
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

verifier_path = Path(sys.argv[1])
probe_path = Path(sys.argv[2])
window_x = int(sys.argv[3])
window_y = int(sys.argv[4])

spec = importlib.util.spec_from_file_location("verify_backend_screenshot", verifier_path)
if spec is None or spec.loader is None:
    raise SystemExit(0)

module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

image = module.Screenshot(probe_path)
left, right, top, bottom = module.content_bounds(image)
app_width = right - left + 1
app_height = bottom - top + 1

divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
divider_x = max(
    divider_search,
    key=lambda x: module.line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
)
detail_left = divider_x + 1
detail_width = right - detail_left + 1

composer_matches = []
for y in range(top + int(app_height * 0.68), bottom + 1):
    candidates = [
        segment
        for segment in image.segments_at(
            y,
            detail_left,
            right + 1,
            module.mac_reference_composer_pixel,
            min_width=int(detail_width * 0.55),
        )
        if segment.start >= detail_left + int(detail_width * 0.03)
        and segment.end <= right - int(detail_width * 0.01)
    ]
    if candidates:
        segment = max(candidates, key=lambda item: item.width)
        composer_matches.append((y, segment))

if not composer_matches:
    raise SystemExit(0)

bottom_band_floor = top + int(app_height * 0.82)
preferred_matches = [
    (y, segment)
    for y, segment in composer_matches
    if y >= bottom_band_floor
]
if not preferred_matches:
    preferred_matches = composer_matches

best_y, composer_segment = max(preferred_matches, key=lambda item: (item[0], item[1].width))
max_width = composer_segment.width
matched_rows = [
    (y, segment)
    for y, segment in preferred_matches
    if segment.width >= int(max_width * 0.95)
    and abs(segment.start - composer_segment.start) <= 8
    and abs(segment.end - composer_segment.end) <= 8
]
top_row = min((y for y, _ in matched_rows), default=best_y)
bottom_row = max((y for y, _ in matched_rows), default=best_y)
if bottom_row - top_row >= 16:
    composer_click_y = (top_row + bottom_row) // 2
elif best_y - top >= int(app_height * 0.75):
    composer_click_y = best_y - 24
else:
    composer_click_y = best_y + 24
composer_click_y = max(top, min(bottom, composer_click_y))
click_y = window_y + composer_click_y
candidate_x_values = [
    composer_segment.start + 42,
    min(composer_segment.end - 42, composer_segment.start + 300),
    int(composer_segment.center),
]

seen: set[tuple[int, int]] = set()
for candidate_x in candidate_x_values:
    point = (window_x + candidate_x, click_y)
    if point in seen:
        continue
    seen.add(point)
    print(f"{point[0]} {point[1]}")
PY
}

quill_chat_functional_action_click_y() {
  local fallback_y="$1"

  if [[ -n "${QUILLUI_FUNCTIONAL_ACTION_Y:-}" ]]; then
    printf '%s\n' "$QUILLUI_FUNCTIONAL_ACTION_Y"
    return
  fi

  if quillui_is_quill_chat_mac_reference_product "$PRODUCT"; then
    if [[ -n "$fallback_y" ]]; then
      printf '%s\n' "$fallback_y"
      return
    fi
    local reference_height="${reference_window_height:-$window_height}"
    printf '%s\n' "$((window_y + reference_height - 170))"
  else
    printf '%s\n' "$fallback_y"
  fi
}

quill_chat_functional_static_composer_click_points() {
  local click_x
  local click_y

  while IFS= read -r click_y; do
    while IFS= read -r click_x; do
      printf '%s %s\n' "$click_x" "$click_y"
    done < <(quill_chat_functional_composer_click_x_candidates)
  done < <(quill_chat_functional_composer_click_y_candidates)
}

quill_chat_functional_attachment_action_click_points() {
  [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]] || return 0

  local click_x
  local click_y
  click_y="$(quill_chat_functional_action_click_y "$(quill_chat_functional_composer_click_y)")"
  while IFS= read -r click_x; do
    printf '%s %s\n' "$click_x" "$click_y"
  done < <(quill_chat_functional_composer_click_x_candidates)
}

quill_chat_functional_detected_attachment_click_point() {
  [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]] || return 0
  command -v import >/dev/null 2>&1 || return 0

  local probe_path="${QUILLUI_FUNCTIONAL_ATTACHMENT_PROBE:-$OUTPUT_DIR/quill-chat-functional-attachment-probe.png}"
  if ! DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$probe_path" 2>/dev/null; then
    return 0
  fi

  python3 - "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "$window_x" "$window_y" 2>/dev/null <<'PY' || true
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

verifier_path = Path(sys.argv[1])
probe_path = Path(sys.argv[2])
window_x = int(sys.argv[3])
window_y = int(sys.argv[4])

spec = importlib.util.spec_from_file_location("verify_backend_screenshot", verifier_path)
if spec is None or spec.loader is None:
    raise SystemExit(0)

module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

image = module.Screenshot(probe_path)
left, right, top, bottom = module.content_bounds(image)
app_width = right - left + 1
app_height = bottom - top + 1

divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
divider_x = max(
    divider_search,
    key=lambda x: module.line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
)
detail_left = divider_x + 1
detail_width = right - detail_left + 1

search_left = max(detail_left, right - int(detail_width * 0.20))
search_right = max(search_left + 1, right - 6)
search_top = max(top, bottom - min(220, int(app_height * 0.24)))
search_bottom = max(search_top + 1, bottom - 6)

def dark(x: int, y: int) -> bool:
    r, g, b = image.rgb(x, y)
    return r + g + b < 360

columns: list[tuple[int, int, int, int]] = []
for x in range(search_left, search_right + 1):
    ys = [y for y in range(search_top, search_bottom + 1) if dark(x, y)]
    if len(ys) >= 2:
        columns.append((x, min(ys), max(ys), len(ys)))

if not columns:
    raise SystemExit(0)

groups: list[list[tuple[int, int, int, int]]] = []
current = [columns[0]]
for column in columns[1:]:
    if column[0] <= current[-1][0] + 12:
        current.append(column)
    else:
        groups.append(current)
        current = [column]
groups.append(current)

clusters: list[tuple[float, float, int, int, int]] = []
for group in groups:
    start = group[0][0]
    end = group[-1][0]
    width = end - start + 1
    total = sum(count for _, _, _, count in group)
    min_y = min(item[1] for item in group)
    max_y = max(item[2] for item in group)
    height = max_y - min_y + 1
    if total < 6 or width < 4 or width > 56 or height < 5 or height > 64:
        continue
    center_x = sum(x * count for x, _, _, count in group) / total
    center_y = sum(((min_y + max_y) / 2) * count for _, min_y, max_y, count in group) / total
    if center_y < bottom - 180:
        continue
    clusters.append((center_x, center_y, width, height, total))

if not clusters:
    raise SystemExit(0)

clusters.sort(key=lambda item: item[0])
target = clusters[-2] if len(clusters) >= 2 else clusters[-1]
print(f"{window_x + round(target[0])} {window_y + round(target[1])}")
PY
}

quill_chat_functional_composer_click_points() {
  if [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]]; then
    {
      quill_chat_functional_detected_composer_click_points
      quill_chat_functional_static_composer_click_points
      quill_chat_functional_attachment_action_click_points
    }
  else
    {
      quill_chat_functional_detected_composer_click_points
      quill_chat_functional_static_composer_click_points
    }
  fi | awk -v max_points="${QUILLUI_FUNCTIONAL_COMPOSER_MAX_POINTS:-8}" '
    !seen[$1 "," $2]++ {
      print
      emitted += 1
      if (emitted >= max_points) {
        exit
      }
    }
  '
}

quill_chat_functional_detected_relaunch_history_click_point() {
  quillui_is_quill_chat_mac_reference_product "$PRODUCT" || return 0
  command -v import >/dev/null 2>&1 || return 0

  local probe_path="${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_PROBE:-$OUTPUT_DIR/quill-chat-functional-relaunch-history-probe.png}"
  if ! DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$probe_path" 2>/dev/null; then
    return 0
  fi

  python3 - "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$probe_path" "$window_x" "$window_y" 2>/dev/null <<'PY' || true
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

verifier_path = Path(sys.argv[1])
probe_path = Path(sys.argv[2])
window_x = int(sys.argv[3])
window_y = int(sys.argv[4])

spec = importlib.util.spec_from_file_location("verify_backend_screenshot", verifier_path)
if spec is None or spec.loader is None:
    raise SystemExit(0)

module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

image = module.Screenshot(probe_path)
left, right, top, bottom = module.content_bounds(image)
app_width = right - left + 1
app_height = bottom - top + 1

divider_search = range(left + int(app_width * 0.23), left + int(app_width * 0.34))
divider_x = max(
    divider_search,
    key=lambda x: module.line_column_score(image, x, top + int(app_height * 0.04), bottom - 40),
)
sidebar_left = left + 16
sidebar_right = max(sidebar_left + 1, divider_x - 16)
scan_top = top + int(app_height * 0.18)
scan_bottom = bottom - int(app_height * 0.12)

rows: list[tuple[int, int]] = []
for y in range(scan_top, scan_bottom):
    dark_pixels = sum(
        1
        for x in range(sidebar_left, sidebar_right)
        if sum(image.rgb(x, y)) < 430
    )
    if dark_pixels >= 12:
        rows.append((y, dark_pixels))

if not rows:
    raise SystemExit(0)

groups: list[list[tuple[int, int]]] = []
current = [rows[0]]
for row in rows[1:]:
    if row[0] <= current[-1][0] + 2:
        current.append(row)
    else:
        groups.append(current)
        current = [row]
groups.append(current)

group = max(groups, key=lambda item: sum(count for _, count in item))
click_y = (group[0][0] + group[-1][0]) // 2
sidebar_width = divider_x - left
click_x = left + min(max(int(sidebar_width * 0.38), 140), max(140, sidebar_width - 40))
print(f"{window_x + click_x} {window_y + click_y}")
PY
}

quill_chat_functional_static_relaunch_history_click_points() {
  local history_x
  local history_y
  local ratio

  if [[ -n "${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_X:-}" && -n "${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_Y:-}" ]]; then
    printf '%s %s\n' "$QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_X" "$QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_Y"
    return
  fi

  history_x="${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_X:-$((window_x + 220))}"
  for ratio in ${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_Y_RATIOS:-44 47 40 52 35 58}; do
    history_y="${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_Y:-$((window_y + (window_height * ratio / 100)))}"
    printf '%s %s\n' "$history_x" "$history_y"
  done
}

quill_chat_functional_relaunch_history_click_points() {
  {
    quill_chat_functional_detected_relaunch_history_click_point
    quill_chat_functional_static_relaunch_history_click_points
  } | awk -v max_points="${QUILLUI_FUNCTIONAL_RELAUNCH_HISTORY_MAX_POINTS:-8}" '
    !seen[$1 "," $2]++ {
      print
      emitted += 1
      if (emitted >= max_points) {
        exit
      }
    }
  '
}

quill_chat_functional_submit_methods() {
  case "$FUNCTIONAL_MODE" in
    attachment-send|image-attachment-send)
      printf 'button\nreturn\n'
      ;;
    *)
      printf 'return\nbutton\n'
      ;;
  esac
}

quill_chat_functional_send_attempt_index=0

quill_chat_functional_send_attempt() {
  local click_x="$1"
  local click_y="$2"
  local submit_method="${3:-return}"
  local attachment_x
  local attachment_y
  local send_x
  local send_y
  local should_clear_before_type=1

  quill_chat_functional_send_attempt_index=$((quill_chat_functional_send_attempt_index + 1))
  if (( quill_chat_functional_send_attempt_index == 1 )) \
      && [[ "$FUNCTIONAL_MODE" == "composer-send" ]] \
      && [[ "${QUILLUI_FUNCTIONAL_CLEAR_FIRST_ATTEMPT:-0}" != "1" ]]; then
    should_clear_before_type=0
  fi

  if [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]]; then
    attachment_x="${QUILLUI_FUNCTIONAL_ATTACHMENT_X:-$((window_x + window_width - 100))}"
    attachment_y="${QUILLUI_FUNCTIONAL_ATTACHMENT_Y:-$(quill_chat_functional_action_click_y "$click_y")}"
  fi

  echo "functional-check: window='${window_id:-none}' geometry=${window_x},${window_y} ${window_width}x${window_height} composer=${click_x},${click_y} mode=${FUNCTIONAL_MODE} submit=${submit_method}" >&2
  quillui_functional_refocus_window
  quillui_functional_click_at "$click_x" "$click_y"
  sleep 1
  if (( should_clear_before_type == 1 )); then
    quillui_functional_xdotool key --clearmodifiers ctrl+a BackSpace 2>/dev/null || true
    sleep 0.2
  fi
  quillui_functional_xdotool type --clearmodifiers --delay "${QUILLUI_FUNCTIONAL_TYPE_DELAY:-60}" "$MESSAGE_TEXT"
  sleep "${QUILLUI_FUNCTIONAL_TYPE_SETTLE_SLEEP:-1.5}"

  if [[ "$FUNCTIONAL_MODE" == "attachment-send" || "$FUNCTIONAL_MODE" == "image-attachment-send" ]]; then
    detected_attachment_point="$(quill_chat_functional_detected_attachment_click_point | head -n 1 || true)"
    if [[ -n "$detected_attachment_point" ]]; then
      read -r attachment_x attachment_y <<< "$detected_attachment_point"
    fi
    quillui_functional_refocus_window
    echo "functional-check: attachment=${attachment_x},${attachment_y}" >&2
    quillui_functional_click_at "$attachment_x" "$attachment_y"
    sleep "${QUILLUI_FUNCTIONAL_ATTACHMENT_SELECT_SLEEP:-1}"
  fi

  if [[ "$submit_method" == "button" ]]; then
    send_x="${QUILLUI_FUNCTIONAL_SEND_X:-$((window_x + window_width - 65))}"
    send_y="${QUILLUI_FUNCTIONAL_SEND_Y:-$(quill_chat_functional_action_click_y "$click_y")}"
    quillui_functional_refocus_window
    echo "functional-check: send=${send_x},${send_y}" >&2
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


def logged_chat_requests() -> list[dict[str, object]]:
    if not mock_log.exists():
        return []
    requests: list[dict[str, object]] = []
    for line in mock_log.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        payload = json.loads(line)
        if payload.get("path") == "/api/chat":
            request = payload.get("request")
            if isinstance(request, dict):
                requests.append(request)
    return requests


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


def message_content_matches(message: dict[str, object]) -> bool:
    content = str(message.get("content", ""))
    return message_text in content


deadline = time.time() + deadline_seconds
last_request = None
last_requests: list[dict[str, object]] = []
last_messages: list[dict[str, object]] = []
while time.time() < deadline:
    last_requests = logged_chat_requests()
    last_request = last_requests[-1] if last_requests else None
    last_messages = persisted_messages()
    matching_request = None
    for request in reversed(last_requests):
        matching_request_users = [
            item
            for item in request.get("messages", [])
            if isinstance(item, dict)
            and item.get("role") == "user"
            and message_content_matches(item)
            and (not require_attachment or request_message_has_image(item))
        ]
        if len(matching_request_users) == 1:
            matching_request = request
            break
    request_ok = matching_request is not None
    if matching_request is not None:
        last_request = matching_request
    user_persisted = any(
        item.get("role") == "user" and message_content_matches(item)
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

quill_chat_functional_wait_for_matching_request() {
  local deadline_seconds="$1"

  python3 - "$MOCK_LOG_PATH" "$MESSAGE_TEXT" "$FUNCTIONAL_MODE" "$deadline_seconds" <<'PY'
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

mock_log = Path(sys.argv[1])
message_text = sys.argv[2]
functional_mode = sys.argv[3]
deadline_seconds = float(sys.argv[4])
require_attachment = functional_mode in {"attachment-send", "image-attachment-send"}


def logged_chat_requests() -> list[dict[str, object]]:
    if not mock_log.exists():
        return []
    requests: list[dict[str, object]] = []
    for line in mock_log.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        payload = json.loads(line)
        if payload.get("path") == "/api/chat":
            request = payload.get("request")
            if isinstance(request, dict):
                requests.append(request)
    return requests


def request_message_has_image(message: dict[str, object]) -> bool:
    images = message.get("images")
    return isinstance(images, list) and any(isinstance(item, str) and item for item in images)


def message_content_matches(message: dict[str, object]) -> bool:
    content = str(message.get("content", ""))
    return message_text in content


deadline = time.time() + deadline_seconds
while time.time() < deadline:
    for request in reversed(logged_chat_requests()):
        matching_request_users = [
            item
            for item in request.get("messages", [])
            if isinstance(item, dict)
            and item.get("role") == "user"
            and message_content_matches(item)
            and (not require_attachment or request_message_has_image(item))
        ]
        if len(matching_request_users) == 1:
            print(f"functional-check: matching request observed for {functional_mode}", file=sys.stderr)
            raise SystemExit(0)
    time.sleep(0.25)

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
while read -r click_x click_y; do
  [[ -n "$click_x" && -n "$click_y" ]] || continue
  while IFS= read -r submit_method; do
    [[ -n "$submit_method" ]] || continue
    quill_chat_functional_send_attempt "$click_x" "$click_y" "$submit_method"
    if quill_chat_functional_wait_for_completion "${QUILLUI_FUNCTIONAL_ATTEMPT_DEADLINE:-8}" 0; then
      completion_verified=1
      break 2
    fi
    if quill_chat_functional_wait_for_matching_request "${QUILLUI_FUNCTIONAL_REQUEST_OBSERVED_DEADLINE:-2}"; then
      if quill_chat_functional_wait_for_completion "${QUILLUI_FUNCTIONAL_SEND_DEADLINE:-25}" 1; then
        completion_verified=1
        break 2
      fi
      exit 1
    fi
  done < <(quill_chat_functional_submit_methods)
done < <(quill_chat_functional_composer_click_points)

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

  mapfile -t relaunch_history_points < <(quill_chat_functional_relaunch_history_click_points)
  if [[ ${#relaunch_history_points[@]} -eq 0 ]]; then
    relaunch_history_points=("$((window_x + 220)) $((window_y + window_height / 2))")
  fi
  read -r history_x history_y <<< "${relaunch_history_points[0]}"
  echo "functional-check: relaunch history=${history_x},${history_y}" >&2
  quillui_functional_refocus_window
  quillui_functional_click_at "$history_x" "$history_y"
  sleep 0.8
  quillui_functional_click_at "$history_x" "$history_y"
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


def message_content_matches(message: dict[str, object]) -> bool:
    content = str(message.get("content", ""))
    return message_text in content


deadline = time.time() + deadline_seconds
last_request_count = 0
last_messages: list[dict[str, object]] = []
while time.time() < deadline:
    last_request_count = chat_request_count()
    last_messages = persisted_messages()
    user_persisted = any(
        item.get("role") == "user" and message_content_matches(item)
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

  relaunch_visual_verified=0
  for relaunch_history_point in "${relaunch_history_points[@]}"; do
    read -r history_x history_y <<< "$relaunch_history_point"
    echo "functional-check: relaunch visual history=${history_x},${history_y}" >&2
    quillui_functional_refocus_window
    quillui_functional_click_at "$history_x" "$history_y"
    sleep "${QUILLUI_FUNCTIONAL_RELAUNCH_VISUAL_SETTLE_SLEEP:-1}"
    DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$RELAUNCH_SCREENSHOT_PATH"
    if python3 "$ROOT_DIR/scripts/verify-backend-screenshot.py" \
      "$RELAUNCH_SCREENSHOT_PATH" \
      quill-chat-linux-functional-transcript; then
      relaunch_visual_verified=1
      break
    fi
  done
  if (( relaunch_visual_verified == 0 )); then
    python3 "$ROOT_DIR/scripts/verify-backend-screenshot.py" \
      "$RELAUNCH_SCREENSHOT_PATH" \
      quill-chat-linux-functional-transcript
  fi
  echo "Functional relaunch screenshot: $RELAUNCH_SCREENSHOT_PATH"
fi
