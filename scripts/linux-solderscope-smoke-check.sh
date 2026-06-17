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
SMOKE_MODE="${2:-${QUILLUI_SOLDERSCOPE_SMOKE_MODE:-launch}}"
VERIFY_PRODUCT="quill-solderscope-launch"
case "$SMOKE_MODE" in
  launch)
    VERIFY_PRODUCT="quill-solderscope-launch"
    ;;
  visual)
    VERIFY_PRODUCT="quill-solderscope-visual"
    ;;
  interaction)
    VERIFY_PRODUCT="quill-solderscope-interaction"
    ;;
  *)
    echo "Unsupported SolderScope smoke mode '$SMOKE_MODE' (expected launch, visual, or interaction)" >&2
    exit 64
    ;;
esac

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

if [[ ! -d "$UPSTREAM_DIR" ]]; then
  echo "Skipping SolderScope launch smoke; upstream not found at $UPSTREAM_DIR"
  exit 0
fi

quillui_install_linux_backend_smoke_packages

for required_command in swift Xvfb import identify convert xdotool; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "$required_command is required for the SolderScope launch smoke" >&2
    exit 66
  fi
done

quillui_solderscope_resolve_desktop_dir() {
  swift -e 'import Foundation; print(FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? "")' 2>/dev/null || true
}

quillui_solderscope_count_snapshots() {
  local desktop_dir="$1"
  if [[ -z "$desktop_dir" || ! -d "$desktop_dir" ]]; then
    echo 0
    return
  fi
  find "$desktop_dir" -maxdepth 1 -type f -name 'SolderScope_*.png' 2>/dev/null | wc -l | tr -d '[:space:]'
}

quillui_solderscope_safe_snapshot_desktop() {
  local desktop_dir="$1"
  [[ "$desktop_dir" == /root/* || "$desktop_dir" == /tmp/* || "$desktop_dir" == "$ROOT_DIR"/* ]]
}

SOLDERSCOPE_DESKTOP_DIR="$(quillui_solderscope_resolve_desktop_dir)"
SOLDERSCOPE_DRIVE_SNAPSHOT=0
case "${QUILLUI_SOLDERSCOPE_DRIVE_SNAPSHOT:-auto}" in
  1|true|TRUE|yes|YES)
    SOLDERSCOPE_DRIVE_SNAPSHOT=1
    ;;
  0|false|FALSE|no|NO)
    SOLDERSCOPE_DRIVE_SNAPSHOT=0
    ;;
  auto|"")
    if [[ "$SMOKE_MODE" == "interaction" ]] && quillui_solderscope_safe_snapshot_desktop "$SOLDERSCOPE_DESKTOP_DIR"; then
      SOLDERSCOPE_DRIVE_SNAPSHOT=1
    fi
    ;;
  *)
    echo "Unsupported QUILLUI_SOLDERSCOPE_DRIVE_SNAPSHOT='${QUILLUI_SOLDERSCOPE_DRIVE_SNAPSHOT}' (expected auto, 1, or 0)" >&2
    exit 64
    ;;
esac
SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT=0
if [[ "$SOLDERSCOPE_DRIVE_SNAPSHOT" == "1" ]]; then
  if [[ -z "$SOLDERSCOPE_DESKTOP_DIR" ]]; then
    echo "Cannot drive SolderScope snapshot: desktop directory could not be resolved" >&2
    exit 66
  fi
  mkdir -p "$SOLDERSCOPE_DESKTOP_DIR"
  SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT="$(quillui_solderscope_count_snapshots "$SOLDERSCOPE_DESKTOP_DIR")"
fi

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

if [[ "${QUILLUI_SOLDERSCOPE_SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT_DIR/scripts/prepare-linux-build-backend.sh" \
    --backend gtk \
    --scratch-path "$SCRATCH_PATH"

  QUILLUI_LINUX_BACKEND=gtk \
    "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift build --disable-index-store --scratch-path "$SCRATCH_PATH" --product QuillSolderScope
  quillui_record_backend_product_build "$BUILD_STAMP_SCRATCH_PATH" QuillSolderScope gtk
fi

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

quillui_drive_solderscope_interaction() {
  local window_id=""
  local window_x=0
  local window_y=0
  local window_width=1180
  local window_height=760
  local click_x=590
  local click_y=380
  local drag_end_x=650
  local drag_end_y=420

  window_id="$(quillui_wait_for_app_window_for_pid "$DISPLAY_ID" "$app_pid" "${QUILLUI_SOLDERSCOPE_WINDOW_WAIT_SECONDS:-20}")" || window_id=""
  if [[ -z "$window_id" ]]; then
    echo "SolderScope interaction smoke could not find a visible app window; capturing root window" >&2
    return 0
  fi

  quillui_move_window_to_origin "$DISPLAY_ID" "$window_id"
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

  click_x=$((window_x + window_width / 2))
  click_y=$((window_y + window_height / 2))
  drag_end_x=$((click_x + 80))
  drag_end_y=$((click_y + 55))
  echo "SolderScope interaction smoke: window=$window_id geometry=${window_x},${window_y} ${window_width}x${window_height}" >&2
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$click_x" "$click_y"
  for _ in 1 2 3 4 5 6 7 8; do
    DISPLAY="$DISPLAY_ID" xdotool click 4
  done
  DISPLAY="$DISPLAY_ID" xdotool mousedown 1 mousemove --sync "$drag_end_x" "$drag_end_y" mouseup 1
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$click_x" "$click_y" click --repeat 2 --delay 80 1
  for _ in 1 2 3 4 5 6; do
    DISPLAY="$DISPLAY_ID" xdotool click 4
  done
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" i
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" h
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" v
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" bracketright
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" 0
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" b
  sleep 0.2
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" b
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" space
  sleep 0.2
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" space
  if [[ "$SOLDERSCOPE_DRIVE_SNAPSHOT" == "1" ]]; then
    DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" s
    local snapshot_count="$SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      snapshot_count="$(quillui_solderscope_count_snapshots "$SOLDERSCOPE_DESKTOP_DIR")"
      if (( snapshot_count > SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT )); then
        echo "SolderScope interaction smoke: snapshot saved to $SOLDERSCOPE_DESKTOP_DIR" >&2
        break
      fi
      sleep 0.2
    done
    if (( snapshot_count <= SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT )); then
      echo "SolderScope interaction smoke did not observe a snapshot file in $SOLDERSCOPE_DESKTOP_DIR" >&2
      return 1
    fi
  fi
  DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" Escape
  sleep 1
}

app_env=(
  DISPLAY="$DISPLAY_ID"
  GDK_BACKEND=x11
  GTK_A11Y=none
  GSK_RENDERER=cairo
  QUILLUI_BACKEND=gtk
  QUILLUI_COLOR_SCHEME=dark
  QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=1180
  QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=760
)

if [[ "$SMOKE_MODE" == "interaction" ]]; then
  app_env+=(
    QUILL_AVFOUNDATION_SYNTHETIC_CAMERA="${QUILL_AVFOUNDATION_SYNTHETIC_CAMERA:-1}"
    QUILL_AVFOUNDATION_SYNTHETIC_WIDTH="${QUILL_AVFOUNDATION_SYNTHETIC_WIDTH:-640}"
    QUILL_AVFOUNDATION_SYNTHETIC_HEIGHT="${QUILL_AVFOUNDATION_SYNTHETIC_HEIGHT:-480}"
    QUILL_AVFOUNDATION_SYNTHETIC_FPS="${QUILL_AVFOUNDATION_SYNTHETIC_FPS:-12}"
  )
fi

env "${app_env[@]}" "$APP_EXECUTABLE" >"$APP_LOG_PATH" 2>&1 &
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

if [[ "$SMOKE_MODE" == "interaction" ]]; then
  quillui_drive_solderscope_interaction
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

if "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"; then
  echo "SolderScope $SMOKE_MODE smoke survived ${SMOKE_SECONDS}s under Xvfb: $SCREENSHOT_PATH"
else
  verify_status=$?
  quillui_print_backend_app_log_tail "$APP_LOG_PATH" "${QUILLUI_SOLDERSCOPE_APP_LOG_LINES:-120}"
  exit "$verify_status"
fi
