#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
demo="${1:-real-conversation-accepted}"
output="${2:-.qa/signal-${demo}.png}"
log_output="${3:-${output%.png}.log}"
case "$demo" in
  conversation|real-conversation|real-conversation-accepted)
    default_width=760
    default_height=720
    ;;
  real-components)
    default_width=568
    default_height=300
    ;;
  ssk-bootstrap)
    default_width=620
    default_height=280
    ;;
  firstlight)
    default_width=390
    default_height=600
    ;;
  privacy|settings|*)
    default_width=390
    default_height=720
    ;;
esac
width="${SIGNAL_RENDER_CAPTURE_WIDTH:-$default_width}"
height="${SIGNAL_RENDER_CAPTURE_HEIGHT:-$default_height}"
if [ -n "${SIGNAL_RENDER_CAPTURE_BINARY:-}" ]; then
  binary="$SIGNAL_RENDER_CAPTURE_BINARY"
else
  bin_dir="$(swift build --show-bin-path 2>/dev/null || true)"
  binary="${bin_dir:-.build/debug}/signal-ui-render"
fi
display_id="${SIGNAL_RENDER_CAPTURE_DISPLAY:-:99}"

mkdir -p "$(dirname "$output")" "$(dirname "$log_output")"

if [ ! -x "$binary" ]; then
  echo "Signal renderer binary not found or not executable: $binary" >&2
  echo "Build it first, for example: swift build --disable-index-store -j 1 --product signal-ui-render" >&2
  exit 1
fi

for required in Xvfb import; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "$required is required for Signal render capture" >&2
    exit 1
  fi
done

prepend_env_path() {
  local name="$1"
  local path="$2"
  [ -d "$path" ] || return 0
  local current="${!name:-}"
  case ":$current:" in
    *":$path:"*) ;;
    *) export "$name"="${current:+$current:}$path" ;;
  esac
}

prepend_env_path QUILLUI_LOCALIZATION_DIRS "$ROOT/.upstream/signal-ios/Signal"
prepend_env_path QUILLUI_RESOURCE_DIRS "$ROOT/.upstream/signal-ios/Signal"
prepend_env_path QUILLUI_RESOURCE_DIRS "$ROOT/.upstream/signal-ios/SignalUI"

Xvfb "$display_id" -screen 0 "${width}x${height}x24" >"${log_output%.log}-xvfb.log" 2>&1 &
xvfb_pid=$!
app_pid=

cleanup() {
  if [ -n "${app_pid:-}" ]; then
    kill "$app_pid" 2>/dev/null || true
  fi
  kill "$xvfb_pid" 2>/dev/null || true
}
trap cleanup EXIT

export DISPLAY="$display_id" GTK_A11Y=none GSK_RENDERER="${GSK_RENDERER:-cairo}" SIGNAL_UI_RENDER_DEMO="$demo" SIGNAL_UI_RENDER_DUMP="${SIGNAL_UI_RENDER_DUMP:-1}"
"$binary" >"$log_output" 2>&1 &
app_pid=$!

sleep "${SIGNAL_RENDER_CAPTURE_DELAY:-8}"
import -window root "$output"

kill "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true

echo "Captured $demo to $output"
