#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

UPSTREAM_DIR="$ROOT_DIR/.upstream/solderscope/SolderScope"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-solderscope-launch.png}"
APP_LOG_PATH="${QUILLUI_SOLDERSCOPE_APP_LOG:-/tmp/quillui-solderscope-smoke.log}"
XVFB_LOG_PATH="${QUILLUI_SOLDERSCOPE_XVFB_LOG:-/tmp/quillui-solderscope-xvfb.log}"
SCRATCH_PATH="${QUILLUI_SOLDERSCOPE_SCRATCH_PATH:-.build-linux}"
if [[ "$SCRATCH_PATH" == /* ]]; then
  BUILD_STAMP_SCRATCH_PATH="$SCRATCH_PATH"
else
  BUILD_STAMP_SCRATCH_PATH="$ROOT_DIR/$SCRATCH_PATH"
fi
SMOKE_SECONDS="${QUILLUI_SOLDERSCOPE_SMOKE_SECONDS:-${QUILLUI_SMOKE_SECONDS:-10}}"
DISPLAY_ID="${QUILLUI_SOLDERSCOPE_DISPLAY:-:93}"
SCREEN_SIZE="${QUILLUI_SOLDERSCOPE_SCREEN_SIZE:-1180x760x24}"

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

if [[ ! -d "$UPSTREAM_DIR" ]]; then
  echo "Skipping SolderScope launch smoke; upstream not found at $UPSTREAM_DIR"
  exit 0
fi

quillui_install_linux_backend_smoke_packages

for required_command in swift Xvfb import identify convert; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "$required_command is required for the SolderScope launch smoke" >&2
    exit 66
  fi
done

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

"$ROOT_DIR/scripts/prepare-linux-build-backend.sh" \
  --backend gtk \
  --scratch-path "$SCRATCH_PATH"

QUILLUI_LINUX_BACKEND=gtk \
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
  swift build --disable-index-store --scratch-path "$SCRATCH_PATH" --product QuillSolderScope
quillui_record_backend_product_build "$BUILD_STAMP_SCRATCH_PATH" QuillSolderScope gtk

BIN_PATH="$(
  QUILLUI_LINUX_BACKEND=gtk \
    "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift build --disable-index-store --scratch-path "$SCRATCH_PATH" --show-bin-path
)"
APP_EXECUTABLE="$BIN_PATH/QuillSolderScope"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Built SolderScope executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 66
fi

DISPLAY_ID="$(quillui_normalize_x_display_id "$DISPLAY_ID")"
xvfb_pid=""
app_pid=""
quillui_start_xvfb "$DISPLAY_ID" "$SCREEN_SIZE" "$XVFB_LOG_PATH" xvfb_pid

cleanup() {
  quillui_stop_process_if_running "$app_pid"
  quillui_stop_process_if_running "$xvfb_pid"
}
trap cleanup EXIT

env \
  DISPLAY="$DISPLAY_ID" \
  GDK_BACKEND=x11 \
  GTK_A11Y=none \
  GSK_RENDERER=cairo \
  QUILLUI_BACKEND=gtk \
  QUILLUI_COLOR_SCHEME=dark \
  QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=1180 \
  QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=760 \
  "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
app_pid=$!

sleep "$SMOKE_SECONDS"

if ! kill -0 "$app_pid" >/dev/null 2>&1; then
  app_status=0
  wait "$app_pid" || app_status=$?
  if [[ "$app_status" == "0" ]]; then
    app_status=1
  fi
  echo "SolderScope launch smoke exited before ${SMOKE_SECONDS}s with status $app_status" >&2
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_SOLDERSCOPE_APP_LOG_LINES:-120}"
  exit "$app_status"
fi

DISPLAY="$DISPLAY_ID" import -window root "$SCREENSHOT_PATH"

if ! kill -0 "$app_pid" >/dev/null 2>&1; then
  app_status=0
  wait "$app_pid" || app_status=$?
  if [[ "$app_status" == "0" ]]; then
    app_status=1
  fi
  echo "SolderScope launch smoke exited during screenshot capture with status $app_status" >&2
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_SOLDERSCOPE_APP_LOG_LINES:-120}"
  exit "$app_status"
fi

if "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" quill-solderscope-launch; then
  echo "SolderScope launch smoke survived ${SMOKE_SECONDS}s under Xvfb: $SCREENSHOT_PATH"
else
  verify_status=$?
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_SOLDERSCOPE_APP_LOG_LINES:-120}"
  exit "$verify_status"
fi
