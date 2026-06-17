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

quillui_solderscope_count_recordings() {
  local desktop_dir="$1"
  if [[ -z "$desktop_dir" || ! -d "$desktop_dir" ]]; then
    echo 0
    return
  fi
  find "$desktop_dir" -maxdepth 1 -type f -name 'SolderScope_*.mov' 2>/dev/null | wc -l | tr -d '[:space:]'
}

quillui_solderscope_latest_recording() {
  local desktop_dir="$1"
  if [[ -z "$desktop_dir" || ! -d "$desktop_dir" ]]; then
    return 1
  fi
  find "$desktop_dir" -maxdepth 1 -type f -name 'SolderScope_*.mov' 2>/dev/null | LC_ALL=C sort | tail -n 1
}

quillui_solderscope_verify_recording_file() {
  local movie_path="$1"
  if [[ -z "$movie_path" || ! -f "$movie_path" ]]; then
    echo "SolderScope interaction smoke did not find a finalized recording file" >&2
    return 1
  fi

  local movie_size
  movie_size="$(wc -c < "$movie_path" | tr -d '[:space:]')"
  if (( movie_size <= 500 )); then
    echo "SolderScope interaction smoke recording is too small to be a movie: $movie_path ($movie_size bytes)" >&2
    return 1
  fi

  local signature
  signature="$(dd if="$movie_path" bs=1 skip=4 count=4 2>/dev/null || true)"
  if [[ "$signature" != "ftyp" ]]; then
    echo "SolderScope interaction smoke recording is missing a QuickTime/MP4 ftyp box: $movie_path" >&2
    return 1
  fi
}

quillui_solderscope_safe_snapshot_desktop() {
  local desktop_dir="$1"
  [[ "$desktop_dir" == /root/* || "$desktop_dir" == /tmp/* || "$desktop_dir" == "$ROOT_DIR"/* ]]
}

quillui_solderscope_focus_window() {
  local window_id="$1"
  DISPLAY="$DISPLAY_ID" xdotool windowactivate --sync "$window_id" 2>/dev/null || true
  DISPLAY="$DISPLAY_ID" xdotool windowfocus --sync "$window_id" 2>/dev/null || true
}

quillui_solderscope_send_key() {
  local window_id="$1"
  local key="$2"
  local key_driver="${QUILLUI_SOLDERSCOPE_KEY_DRIVER:-window}"
  quillui_solderscope_focus_window "$window_id"
  case "$key_driver" in
    active)
      DISPLAY="$DISPLAY_ID" xdotool key --clearmodifiers "$key"
      ;;
    window)
      DISPLAY="$DISPLAY_ID" xdotool key --window "$window_id" --clearmodifiers "$key"
      ;;
    *)
      echo "Unsupported QUILLUI_SOLDERSCOPE_KEY_DRIVER='$key_driver' (expected active or window)" >&2
      return 64
      ;;
  esac
  sleep "${QUILLUI_SOLDERSCOPE_KEY_SETTLE_SECONDS:-0.05}"
}

quillui_solderscope_recording_saved_log_count() {
  grep -c "Recording saved:" "$APP_LOG_PATH" 2>/dev/null || true
}

quillui_solderscope_recording_started_log_count() {
  grep -c "Recording started:" "$APP_LOG_PATH" 2>/dev/null || true
}

quillui_solderscope_click_toolbar_button() {
  local window_x="$1"
  local window_y="$2"
  local window_width="$3"
  local right_offset="$4"
  local label="$5"
  local toolbar_y_offset="${6:-${QUILLUI_SOLDERSCOPE_TOOLBAR_Y_OFFSET:-38}}"
  local button_x=$((window_x + window_width - right_offset))
  local button_y=$((window_y + toolbar_y_offset))
  local reset_y=$((button_y + ${QUILLUI_SOLDERSCOPE_TOOLBAR_RETARGET_DELTA_Y:-90}))

  echo "SolderScope interaction smoke: toolbar $label click at ${button_x},${button_y}" >&2
  if [[ -n "${window_id:-}" ]]; then
    quillui_solderscope_focus_window "$window_id"
  fi
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$button_x" "$reset_y"
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$button_x" "$button_y" click 1
  sleep "${QUILLUI_SOLDERSCOPE_TOOLBAR_SETTLE_SECONDS:-0.2}"
}

quillui_solderscope_drive_snapshot_action() {
  local snapshot_driver="$1"
  local window_id="$2"
  local window_x="$3"
  local window_y="$4"
  local window_width="$5"
  local label="$6"

  case "$snapshot_driver" in
    toolbar)
      quillui_solderscope_click_toolbar_button "$window_x" "$window_y" "$window_width" \
        "${QUILLUI_SOLDERSCOPE_SNAPSHOT_BUTTON_RIGHT_OFFSET:-181}" \
        "$label" \
        "${QUILLUI_SOLDERSCOPE_SNAPSHOT_TOOLBAR_Y_OFFSET:-38}"
      ;;
    shortcut)
      quillui_solderscope_send_key "$window_id" s
      ;;
    none)
      ;;
    *)
      echo "Unsupported snapshot driver '$snapshot_driver' (expected toolbar, shortcut, or none)" >&2
      return 64
      ;;
  esac
}

quillui_solderscope_snapshot_fallback_driver() {
  local snapshot_driver="$1"
  local fallback_driver="${QUILLUI_SOLDERSCOPE_SNAPSHOT_FALLBACK_DRIVER:-auto}"
  case "$fallback_driver" in
    auto|"")
      case "$snapshot_driver" in
        toolbar) echo shortcut ;;
        shortcut) echo toolbar ;;
        *) echo none ;;
      esac
      ;;
    toolbar|shortcut|none)
      echo "$fallback_driver"
      ;;
    *)
      echo "Unsupported QUILLUI_SOLDERSCOPE_SNAPSHOT_FALLBACK_DRIVER='$fallback_driver' (expected auto, toolbar, shortcut, or none)" >&2
      return 64
      ;;
  esac
}

quillui_solderscope_drive_freeze_once() {
  local freeze_driver="$1"
  local window_id="$2"
  local window_x="$3"
  local window_y="$4"
  local window_width="$5"
  local label="${6:-freeze}"

  case "$freeze_driver" in
    toolbar)
      quillui_solderscope_click_toolbar_button "$window_x" "$window_y" "$window_width" \
        "${QUILLUI_SOLDERSCOPE_FREEZE_BUTTON_RIGHT_OFFSET:-235}" \
        "$label" \
        "${QUILLUI_SOLDERSCOPE_FREEZE_TOOLBAR_Y_OFFSET:-38}"
      ;;
    shortcut)
      quillui_solderscope_send_key "$window_id" space
      ;;
    none)
      echo "SolderScope interaction smoke: freeze skipped" >&2
      ;;
    *)
      echo "Unsupported QUILLUI_SOLDERSCOPE_FREEZE_DRIVER='$freeze_driver' (expected toolbar, shortcut, or none)" >&2
      return 64
      ;;
  esac
}

quillui_solderscope_freeze_fallback_driver() {
  local freeze_driver="$1"
  local fallback_driver="${QUILLUI_SOLDERSCOPE_FREEZE_FALLBACK_DRIVER:-auto}"
  case "$fallback_driver" in
    auto|"")
      case "$freeze_driver" in
        toolbar) echo shortcut ;;
        shortcut) echo toolbar ;;
        *) echo none ;;
      esac
      ;;
    toolbar|shortcut|none)
      echo "$fallback_driver"
      ;;
    *)
      echo "Unsupported QUILLUI_SOLDERSCOPE_FREEZE_FALLBACK_DRIVER='$fallback_driver' (expected auto, toolbar, shortcut, or none)" >&2
      return 64
      ;;
  esac
}

quillui_solderscope_wait_for_visible_frame() {
  local wait_mode="${QUILLUI_SOLDERSCOPE_WAIT_FOR_FRAME:-auto}"
  case "$wait_mode" in
    1|true|TRUE|yes|YES|auto|"")
      ;;
    0|false|FALSE|no|NO)
      return 0
      ;;
    *)
      echo "Unsupported QUILLUI_SOLDERSCOPE_WAIT_FOR_FRAME='$wait_mode' (expected auto, 1, or 0)" >&2
      return 64
      ;;
  esac

  local frame_probe_path
  frame_probe_path="$(mktemp "${TMPDIR:-/tmp}/quill-solderscope-frame.XXXXXX.png")"
  local frame_wait_deadline=$((SECONDS + ${QUILLUI_SOLDERSCOPE_FRAME_WAIT_SECONDS:-18}))
  local last_error=""
  while (( SECONDS <= frame_wait_deadline )); do
    DISPLAY="$DISPLAY_ID" import -window root "$frame_probe_path" 2>/dev/null || true
    if "$ROOT_DIR/scripts/verify-backend-screenshot.py" "$frame_probe_path" quill-solderscope-interaction >/tmp/quill-solderscope-frame-check.log 2>&1; then
      rm -f "$frame_probe_path" /tmp/quill-solderscope-frame-check.log
      echo "SolderScope interaction smoke: synthetic frame is visible before interaction" >&2
      return 0
    fi
    last_error="$(tail -n 1 /tmp/quill-solderscope-frame-check.log 2>/dev/null || true)"
    sleep "${QUILLUI_SOLDERSCOPE_FRAME_WAIT_TICK_SECONDS:-0.5}"
  done

  echo "SolderScope interaction smoke did not observe a visible synthetic frame before interaction: $last_error" >&2
  if [[ -n "${QUILLUI_SOLDERSCOPE_FRAME_PROBE_OUT:-}" ]]; then
    cp "$frame_probe_path" "$QUILLUI_SOLDERSCOPE_FRAME_PROBE_OUT" 2>/dev/null || true
  fi
  rm -f "$frame_probe_path" /tmp/quill-solderscope-frame-check.log
  return 1
}

quillui_solderscope_verify_freeze_attempt() {
  local attempt_screenshot="$1"

  DISPLAY="$DISPLAY_ID" import -window root "$attempt_screenshot" >/dev/null 2>&1 || return 1
  "$ROOT_DIR/scripts/verify-backend-screenshot.py" \
    "$attempt_screenshot" \
    quill-solderscope-freeze-interaction >/dev/null 2>&1
}

quillui_solderscope_converge_freeze() {
  local freeze_driver="$1"
  local window_id="$2"
  local window_x="$3"
  local window_y="$4"
  local window_width="$5"

  if [[ "$freeze_driver" == "none" ]]; then
    quillui_solderscope_drive_freeze_once "$freeze_driver" "$window_id" "$window_x" "$window_y" "$window_width"
    return 0
  fi

  local attempt_screenshot="${SCREENSHOT_PATH%.png}-freeze-attempt.png"
  local freeze_attempts="${QUILLUI_SOLDERSCOPE_FREEZE_ATTEMPTS:-3}"
  local attempt
  for ((attempt = 1; attempt <= freeze_attempts; attempt += 1)); do
    quillui_solderscope_drive_freeze_once "$freeze_driver" "$window_id" "$window_x" "$window_y" "$window_width"
    sleep "${QUILLUI_SOLDERSCOPE_FREEZE_VERIFY_SETTLE_SECONDS:-1}"
    if quillui_solderscope_verify_freeze_attempt "$attempt_screenshot"; then
      echo "SolderScope interaction smoke: freeze reached verified state on attempt $attempt" >&2
      return 0
    fi
    echo "SolderScope interaction smoke: freeze attempt $attempt did not show the FROZEN badge" >&2
  done

  local fallback_driver
  fallback_driver="$(quillui_solderscope_freeze_fallback_driver "$freeze_driver")" || return $?
  if [[ "$fallback_driver" != "none" && "$fallback_driver" != "$freeze_driver" ]]; then
    for ((attempt = 1; attempt <= freeze_attempts; attempt += 1)); do
      quillui_solderscope_drive_freeze_once "$fallback_driver" "$window_id" "$window_x" "$window_y" "$window_width" freeze-fallback
      sleep "${QUILLUI_SOLDERSCOPE_FREEZE_VERIFY_SETTLE_SECONDS:-1}"
      if quillui_solderscope_verify_freeze_attempt "$attempt_screenshot"; then
        echo "SolderScope interaction smoke: freeze fallback reached verified state on attempt $attempt" >&2
        return 0
      fi
      echo "SolderScope interaction smoke: freeze fallback attempt $attempt did not show the FROZEN badge" >&2
    done
  fi

  cp -f "$attempt_screenshot" "$SCREENSHOT_PATH" 2>/dev/null || true
  echo "SolderScope interaction smoke did not reach the verified frozen state after $freeze_attempts attempts" >&2
  return 1
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

SOLDERSCOPE_DRIVE_RECORDING=0
case "${QUILLUI_SOLDERSCOPE_DRIVE_RECORDING:-auto}" in
  1|true|TRUE|yes|YES)
    SOLDERSCOPE_DRIVE_RECORDING=1
    ;;
  0|false|FALSE|no|NO)
    SOLDERSCOPE_DRIVE_RECORDING=0
    ;;
  auto|"")
    if [[ "$SMOKE_MODE" == "interaction" ]] \
      && [[ "$SOLDERSCOPE_DRIVE_SNAPSHOT" != "1" ]] \
      && quillui_solderscope_safe_snapshot_desktop "$SOLDERSCOPE_DESKTOP_DIR" \
      && command -v ffmpeg >/dev/null 2>&1; then
      SOLDERSCOPE_DRIVE_RECORDING=1
    fi
    ;;
  *)
    echo "Unsupported QUILLUI_SOLDERSCOPE_DRIVE_RECORDING='${QUILLUI_SOLDERSCOPE_DRIVE_RECORDING}' (expected auto, 1, or 0)" >&2
    exit 64
    ;;
esac
SOLDERSCOPE_RECORDING_BEFORE_COUNT=0
if [[ "$SOLDERSCOPE_DRIVE_RECORDING" == "1" ]]; then
  if [[ -z "$SOLDERSCOPE_DESKTOP_DIR" ]]; then
    echo "Cannot drive SolderScope recording: desktop directory could not be resolved" >&2
    exit 66
  fi
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Cannot drive SolderScope recording: ffmpeg is required for the AVAssetWriter compatibility backend" >&2
    exit 66
  fi
  mkdir -p "$SOLDERSCOPE_DESKTOP_DIR"
  SOLDERSCOPE_RECORDING_BEFORE_COUNT="$(quillui_solderscope_count_recordings "$SOLDERSCOPE_DESKTOP_DIR")"
fi

SOLDERSCOPE_FREEZE_DRIVER="${QUILLUI_SOLDERSCOPE_FREEZE_DRIVER:-shortcut}"
if [[ "$SMOKE_MODE" == "interaction" && "$SOLDERSCOPE_FREEZE_DRIVER" != "none" ]]; then
  VERIFY_PRODUCT="quill-solderscope-freeze-interaction"
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
  quillui_solderscope_focus_window "$window_id"
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
  quillui_solderscope_wait_for_visible_frame
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$click_x" "$click_y"
  for _ in 1 2 3 4 5 6 7 8; do
    DISPLAY="$DISPLAY_ID" xdotool click 4
  done
  DISPLAY="$DISPLAY_ID" xdotool mousedown 1 mousemove --sync "$drag_end_x" "$drag_end_y" mouseup 1
  DISPLAY="$DISPLAY_ID" xdotool mousemove --sync "$click_x" "$click_y" click --repeat 2 --delay 80 1
  for _ in 1 2 3 4 5 6; do
    DISPLAY="$DISPLAY_ID" xdotool click 4
  done
  quillui_solderscope_send_key "$window_id" i
  quillui_solderscope_send_key "$window_id" h
  quillui_solderscope_send_key "$window_id" v
  quillui_solderscope_send_key "$window_id" bracketright
  quillui_solderscope_send_key "$window_id" 0
  if [[ "$SOLDERSCOPE_DRIVE_SNAPSHOT" == "1" ]]; then
    local snapshot_driver="${QUILLUI_SOLDERSCOPE_SNAPSHOT_DRIVER:-shortcut}"
    local snapshot_fallback_driver
    snapshot_fallback_driver="$(quillui_solderscope_snapshot_fallback_driver "$snapshot_driver")" || return $?
    local snapshot_fallback_sent=0
    local snapshot_attempts="${QUILLUI_SOLDERSCOPE_SNAPSHOT_ATTEMPTS:-40}"
    local snapshot_tick_seconds="${QUILLUI_SOLDERSCOPE_SNAPSHOT_TICK_SECONDS:-0.25}"
    quillui_solderscope_drive_snapshot_action "$snapshot_driver" "$window_id" "$window_x" "$window_y" "$window_width" snapshot
    local snapshot_count="$SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT"
    local attempt
    for ((attempt = 1; attempt <= snapshot_attempts; attempt += 1)); do
      snapshot_count="$(quillui_solderscope_count_snapshots "$SOLDERSCOPE_DESKTOP_DIR")"
      if (( snapshot_count > SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT )); then
        echo "SolderScope interaction smoke: snapshot saved to $SOLDERSCOPE_DESKTOP_DIR" >&2
        break
      fi
      if (( attempt == ${QUILLUI_SOLDERSCOPE_SNAPSHOT_RETRY_TICK:-5} )); then
        quillui_solderscope_drive_snapshot_action "$snapshot_driver" "$window_id" "$window_x" "$window_y" "$window_width" snapshot-retry
      fi
      if (( snapshot_fallback_sent == 0 && attempt == ${QUILLUI_SOLDERSCOPE_SNAPSHOT_FALLBACK_TICK:-8} )); then
        if [[ "$snapshot_fallback_driver" != "none" && "$snapshot_fallback_driver" != "$snapshot_driver" ]]; then
          quillui_solderscope_drive_snapshot_action "$snapshot_fallback_driver" "$window_id" "$window_x" "$window_y" "$window_width" snapshot-fallback
          snapshot_fallback_sent=1
        fi
      fi
      sleep "$snapshot_tick_seconds"
    done
    if (( snapshot_count <= SOLDERSCOPE_SNAPSHOT_BEFORE_COUNT )); then
      echo "SolderScope interaction smoke did not observe a snapshot file in $SOLDERSCOPE_DESKTOP_DIR" >&2
      return 1
    fi
  fi
  if [[ "$SOLDERSCOPE_DRIVE_RECORDING" == "1" ]]; then
    local recording_driver="${QUILLUI_SOLDERSCOPE_RECORDING_DRIVER:-shortcut}"
    local recording_start_driver="${QUILLUI_SOLDERSCOPE_RECORDING_START_DRIVER:-$recording_driver}"
    local recording_stop_driver="${QUILLUI_SOLDERSCOPE_RECORDING_STOP_DRIVER:-$recording_driver}"
    local recording_started_before
    local recording_saved_before
    recording_started_before="$(quillui_solderscope_recording_started_log_count)"
    recording_saved_before="$(quillui_solderscope_recording_saved_log_count)"
    local recording_start_retry_tick="${QUILLUI_SOLDERSCOPE_RECORDING_START_RETRY_TICK:-}"
    # Starting the ffmpeg-backed writer is asynchronous. Re-sending "r" too
    # quickly can queue a second start and leave the UI recording after the
    # stop path succeeds, so the default retry is delayed.
    local recording_start_retry_interval="${QUILLUI_SOLDERSCOPE_RECORDING_START_RETRY_INTERVAL_TICKS:-30}"
    sleep "${QUILLUI_SOLDERSCOPE_PRE_RECORDING_SETTLE_SECONDS:-0.5}"
    case "$recording_start_driver" in
      toolbar)
        quillui_solderscope_click_toolbar_button "$window_x" "$window_y" "$window_width" "${QUILLUI_SOLDERSCOPE_RECORD_BUTTON_RIGHT_OFFSET:-128}" record-start "${QUILLUI_SOLDERSCOPE_RECORD_START_TOOLBAR_Y_OFFSET:-${QUILLUI_SOLDERSCOPE_RECORD_TOOLBAR_Y_OFFSET:-38}}"
        ;;
      shortcut)
        quillui_solderscope_send_key "$window_id" r
        ;;
      *)
        echo "Unsupported QUILLUI_SOLDERSCOPE_RECORDING_START_DRIVER='$recording_start_driver' (expected toolbar or shortcut)" >&2
        return 64
        ;;
    esac
    local recording_started_count="$recording_started_before"
    local recording_started=0
    for attempt in {1..80}; do
      recording_started_count="$(quillui_solderscope_recording_started_log_count)"
      if (( recording_started_count > recording_started_before )); then
        recording_started=1
        break
      fi
      local should_retry_start=0
      if [[ -n "$recording_start_retry_tick" ]]; then
        if (( attempt == recording_start_retry_tick )); then
          should_retry_start=1
        fi
      elif (( recording_start_retry_interval > 0 && attempt % recording_start_retry_interval == 0 )); then
        should_retry_start=1
      fi
      if (( should_retry_start == 1 )); then
        case "$recording_start_driver" in
          toolbar)
            quillui_solderscope_click_toolbar_button "$window_x" "$window_y" "$window_width" "${QUILLUI_SOLDERSCOPE_RECORD_BUTTON_RIGHT_OFFSET:-128}" record-start-retry "${QUILLUI_SOLDERSCOPE_RECORD_START_TOOLBAR_Y_OFFSET:-${QUILLUI_SOLDERSCOPE_RECORD_TOOLBAR_Y_OFFSET:-38}}"
            ;;
          shortcut)
            quillui_solderscope_send_key "$window_id" r
            ;;
        esac
      fi
      sleep 0.25
    done
    if [[ "$recording_started" != "1" ]]; then
      echo "SolderScope interaction smoke did not observe the app-level Recording started log" >&2
      return 1
    fi
    sleep "${QUILLUI_SOLDERSCOPE_RECORDING_SECONDS:-2}"
    case "$recording_stop_driver" in
      toolbar)
        quillui_solderscope_click_toolbar_button "$window_x" "$window_y" "$window_width" "${QUILLUI_SOLDERSCOPE_RECORD_BUTTON_RIGHT_OFFSET:-128}" record-stop "${QUILLUI_SOLDERSCOPE_RECORD_STOP_TOOLBAR_Y_OFFSET:-${QUILLUI_SOLDERSCOPE_RECORD_TOOLBAR_Y_OFFSET:-38}}"
        ;;
      shortcut)
        quillui_solderscope_send_key "$window_id" r
        ;;
      *)
        echo "Unsupported QUILLUI_SOLDERSCOPE_RECORDING_STOP_DRIVER='$recording_stop_driver' (expected toolbar or shortcut)" >&2
        return 64
        ;;
    esac
    local recording_count="$SOLDERSCOPE_RECORDING_BEFORE_COUNT"
    local recording_path=""
    local recording_saved_count="$recording_saved_before"
    local recording_verified=0
    for attempt in {1..40}; do
      recording_saved_count="$(quillui_solderscope_recording_saved_log_count)"
      recording_count="$(quillui_solderscope_count_recordings "$SOLDERSCOPE_DESKTOP_DIR")"
      if (( recording_saved_count > recording_saved_before && recording_count > SOLDERSCOPE_RECORDING_BEFORE_COUNT )); then
        recording_path="$(quillui_solderscope_latest_recording "$SOLDERSCOPE_DESKTOP_DIR")"
        if quillui_solderscope_verify_recording_file "$recording_path" >/dev/null 2>&1; then
          recording_verified=1
          echo "SolderScope interaction smoke: recording saved to $recording_path" >&2
          break
        fi
      fi
      if (( attempt == ${QUILLUI_SOLDERSCOPE_RECORDING_STOP_RETRY_TICK:-20} )); then
        case "$recording_stop_driver" in
          toolbar)
            quillui_solderscope_click_toolbar_button "$window_x" "$window_y" "$window_width" "${QUILLUI_SOLDERSCOPE_RECORD_BUTTON_RIGHT_OFFSET:-128}" record-stop-retry "${QUILLUI_SOLDERSCOPE_RECORD_STOP_TOOLBAR_Y_OFFSET:-${QUILLUI_SOLDERSCOPE_RECORD_TOOLBAR_Y_OFFSET:-38}}"
            ;;
          shortcut)
            quillui_solderscope_send_key "$window_id" r
            ;;
        esac
      fi
      sleep 0.25
    done
    if [[ "$recording_verified" != "1" ]]; then
      if [[ -n "$recording_path" ]]; then
        quillui_solderscope_verify_recording_file "$recording_path" || true
      fi
      if (( recording_saved_count <= recording_saved_before )); then
        echo "SolderScope interaction smoke did not observe the app-level Recording saved log after stop" >&2
      fi
      echo "SolderScope interaction smoke did not observe a finalized recording file in $SOLDERSCOPE_DESKTOP_DIR" >&2
      return 1
    fi
    sleep "${QUILLUI_SOLDERSCOPE_POST_RECORDING_SETTLE_SECONDS:-0.5}"
  fi
  local freeze_driver="$SOLDERSCOPE_FREEZE_DRIVER"
  quillui_solderscope_converge_freeze "$freeze_driver" "$window_id" "$window_x" "$window_y" "$window_width"
  if [[ "${QUILLUI_SOLDERSCOPE_DRIVE_CALIBRATION:-0}" == "1" ]]; then
    quillui_solderscope_send_key "$window_id" b
    quillui_solderscope_send_key "$window_id" Escape
  fi
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
