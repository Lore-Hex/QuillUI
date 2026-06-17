#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null
  pwd
)"
cd "$ROOT_DIR"

SCREENSHOT_PATH="${1:-$ROOT_DIR/.qa/icecubes-linux-add-account.png}"
SCRATCH_PATH="${QUILLUI_ICECUBES_SCRATCH_PATH:-.build-linux-icecubes-app}"
APP_LOG_PATH="${QUILLUI_ICECUBES_VISUAL_APP_LOG:-/tmp/quillui-icecubes-app.log}"
SCREEN_SIZE="${QUILLUI_ICECUBES_VISUAL_SCREEN_SIZE:-1000x980x24}"

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

DISPLAY_ID="$(quillui_normalize_x_display_id "${QUILLUI_ICECUBES_VISUAL_DISPLAY:-:97}")"

quillui_install_linux_backend_smoke_packages

if [[ ! -d "$ROOT_DIR/.upstream/icecubes/Packages/Models/Sources/Models" ]]; then
  echo "IceCubes upstream source is missing; run scripts/fetch-upstream.sh icecubes first." >&2
  exit 66
fi

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

QUILLUI_LINUX_BACKEND=gtk \
QUILLUI_ICECUBES=1 \
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
  swift build --disable-index-store --scratch-path "$SCRATCH_PATH" --product icecubes-linux-app

BIN_PATH="$(
  QUILLUI_LINUX_BACKEND=gtk \
  QUILLUI_ICECUBES=1 \
    "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift build --disable-index-store --scratch-path "$SCRATCH_PATH" --show-bin-path
)"
APP_EXECUTABLE="$BIN_PATH/icecubes-linux-app"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Built IceCubes executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

xvfb_pid=""
quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" /tmp/quillui-icecubes-xvfb.log xvfb_pid

cleanup() {
  quillui_stop_process_if_running "${app_pid:-}"
  quillui_stop_process_if_running "$xvfb_pid"
}
trap cleanup EXIT

QUILLDATA_HOME="${QUILLUI_ICECUBES_DATA_HOME:-$ROOT_DIR/.qa/icecubes-linux-data}"
rm -rf "$QUILLDATA_HOME"

env \
  DISPLAY="$DISPLAY_ID" \
  GTK_A11Y=none \
  GSK_RENDERER=cairo \
  QUILLUI_BACKEND=gtk \
  QUILLDATA_HOME="$QUILLDATA_HOME" \
  "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

window_id=""
for _ in $(seq 1 60); do
  if ! kill -0 "$app_pid" >/dev/null 2>&1; then
    echo "IceCubes app exited before a window was visible." >&2
    quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
    exit 1
  fi
  window_id="$(quillui_find_visible_window_for_pid "$DISPLAY_ID" "$app_pid")"
  [[ -n "$window_id" ]] && break
  sleep 0.5
done

if [[ -z "$window_id" ]]; then
  echo "IceCubes app did not map a visible window." >&2
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
  exit 1
fi

quillui_move_window_to_origin "$DISPLAY_ID" "$window_id"
sleep "${QUILLUI_ICECUBES_VISUAL_SETTLE_SECONDS:-8}"

DISPLAY="$DISPLAY_ID" import -window "$window_id" "$SCREENSHOT_PATH"

if "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" icecubes-linux-add-account; then
  echo "IceCubes visual screenshot: $SCREENSHOT_PATH"
else
  verify_status=$?
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" 120
  exit "$verify_status"
fi
