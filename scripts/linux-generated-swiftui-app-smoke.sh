#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCREENSHOT_PATH="${1:-}"
APP_EXECUTABLE="${2:-}"
APP_LABEL="${3:-generated-swiftui-app}"
APP_LOG_PATH="${QUILLUI_GENERATED_APP_SMOKE_LOG:-}"
DISPLAY_ID="${QUILLUI_GENERATED_APP_SMOKE_DISPLAY:-:99}"
SCREEN_SIZE="${QUILLUI_GENERATED_APP_SMOKE_SCREEN_SIZE:-1280x800x24}"
WAIT_SECONDS="${QUILLUI_GENERATED_APP_SMOKE_WAIT_SECONDS:-10}"

usage() {
  cat <<'MSG'
Usage: scripts/linux-generated-swiftui-app-smoke.sh SCREENSHOT_PATH APP_EXECUTABLE [APP_LABEL]

Launch a generated SwiftUI Linux executable under Xvfb, capture a screenshot,
and fail if the app exits early or no screenshot can be written. Window-manager
PID lookup is best-effort; the script falls back to an all-window search and
then to the root window so headless probes do not report false no-window
failures when GTK has presented the app.

Environment:
  QUILLUI_GENERATED_APP_SMOKE_DISPLAY
  QUILLUI_GENERATED_APP_SMOKE_SCREEN_SIZE
  QUILLUI_GENERATED_APP_SMOKE_WINDOW_WIDTH
  QUILLUI_GENERATED_APP_SMOKE_WINDOW_HEIGHT
  QUILLUI_GENERATED_APP_SMOKE_RESIZE_WINDOW=0 disables xdotool resize.
  QUILLUI_GENERATED_APP_SMOKE_WAIT_SECONDS
  QUILLUI_GENERATED_APP_SMOKE_LOG
  QUILLUI_GTK_DEBUG_ACTIONS=1 enables GTK scene diagnostics in the app log.
MSG
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ -z "$SCREENSHOT_PATH" || -z "$APP_EXECUTABLE" ]]; then
  usage >&2
  exit 64
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Generated SwiftUI app smoke checks must run on Linux." >&2
  exit 64
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "App executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 66
fi

if [[ "$SCREEN_SIZE" =~ ^([0-9]+)x([0-9]+)x([0-9]+)$ ]]; then
  SCREEN_WIDTH="${BASH_REMATCH[1]}"
  SCREEN_HEIGHT="${BASH_REMATCH[2]}"
else
  echo "Invalid QUILLUI_GENERATED_APP_SMOKE_SCREEN_SIZE: $SCREEN_SIZE" >&2
  exit 64
fi
WINDOW_WIDTH="${QUILLUI_GENERATED_APP_SMOKE_WINDOW_WIDTH:-${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-$SCREEN_WIDTH}}"
WINDOW_HEIGHT="${QUILLUI_GENERATED_APP_SMOKE_WINDOW_HEIGHT:-${QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT:-$SCREEN_HEIGHT}}"
RESIZE_WINDOW="${QUILLUI_GENERATED_APP_SMOKE_RESIZE_WINDOW:-1}"
AFTER_RESIZE_SECONDS="${QUILLUI_GENERATED_APP_SMOKE_AFTER_RESIZE_SECONDS:-1}"

if ! command -v Xvfb >/dev/null 2>&1; then
  echo "Xvfb is required for generated app smoke checks." >&2
  exit 69
fi

if ! command -v import >/dev/null 2>&1; then
  echo "ImageMagick import is required for generated app smoke checks." >&2
  exit 69
fi

mkdir -p "$(dirname "$SCREENSHOT_PATH")"
if [[ -z "$APP_LOG_PATH" ]]; then
  APP_LOG_PATH="$ROOT_DIR/.qa/$APP_LABEL-smoke.log"
fi
mkdir -p "$(dirname "$APP_LOG_PATH")"

xvfb_log="${TMPDIR:-/tmp}/quillui-$APP_LABEL-xvfb.log"
openbox_log="${TMPDIR:-/tmp}/quillui-$APP_LABEL-openbox.log"
xvfb_pid=""
openbox_pid=""
app_pid=""

cleanup() {
  if [[ -n "$app_pid" ]]; then kill "$app_pid" >/dev/null 2>&1 || true; fi
  if [[ -n "$openbox_pid" ]]; then kill "$openbox_pid" >/dev/null 2>&1 || true; fi
  if [[ -n "$xvfb_pid" ]]; then kill "$xvfb_pid" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

Xvfb "$DISPLAY_ID" -screen 0 "$SCREEN_SIZE" >"$xvfb_log" 2>&1 &
xvfb_pid=$!
sleep 1

if command -v openbox >/dev/null 2>&1; then
  DISPLAY="$DISPLAY_ID" openbox >"$openbox_log" 2>&1 &
  openbox_pid=$!
fi

DISPLAY="$DISPLAY_ID" \
  GTK_A11Y="${GTK_A11Y:-none}" \
  QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH="$WINDOW_WIDTH" \
  QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT="$WINDOW_HEIGHT" \
  QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL="${QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL:-1}" \
  "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

sleep "$WAIT_SECONDS"

if ! kill -0 "$app_pid" >/dev/null 2>&1; then
  echo "$APP_LABEL exited before screenshot capture." >&2
  tail -n "${QUILLUI_GENERATED_APP_SMOKE_LOG_LINES:-120}" "$APP_LOG_PATH" >&2 || true
  exit 70
fi

window_id=""
if command -v xdotool >/dev/null 2>&1; then
  window_id="$(
    DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --pid "$app_pid" --name ".*" 2>/dev/null |
      head -n 1 || true
  )"
  if [[ -z "$window_id" ]]; then
    window_id="$(
      DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --name ".*" 2>/dev/null |
        head -n 1 || true
    )"
  fi
fi

if [[ -n "$window_id" ]]; then
  DISPLAY="$DISPLAY_ID" xdotool windowmove "$window_id" 0 0 >/dev/null 2>&1 || true
  if [[ "$RESIZE_WINDOW" != "0" ]]; then
    DISPLAY="$DISPLAY_ID" xdotool windowsize "$window_id" "$WINDOW_WIDTH" "$WINDOW_HEIGHT" >/dev/null 2>&1 || true
    sleep "$AFTER_RESIZE_SECONDS"
  fi
  DISPLAY="$DISPLAY_ID" import -window "$window_id" "$SCREENSHOT_PATH"
else
  DISPLAY="$DISPLAY_ID" import -window root "$SCREENSHOT_PATH"
fi

if [[ ! -s "$SCREENSHOT_PATH" ]]; then
  echo "Generated app smoke screenshot was not written: $SCREENSHOT_PATH" >&2
  tail -n "${QUILLUI_GENERATED_APP_SMOKE_LOG_LINES:-120}" "$APP_LOG_PATH" >&2 || true
  exit 70
fi

echo "Generated app smoke ok: $APP_LABEL"
echo "  screenshot: $SCREENSHOT_PATH"
echo "  app log: $APP_LOG_PATH"
