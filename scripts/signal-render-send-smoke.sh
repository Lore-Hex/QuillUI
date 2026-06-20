#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$ROOT/.qa/signal-real-send-smoke.png}"
log_output="${2:-${output%.png}.log}"
text="${SIGNAL_RENDER_SMOKE_TEXT:-Linux_send_smoke_$(date +%s)}"

cd "$ROOT"

if [ "${SIGNAL_RENDER_SMOKE_SKIP_BUILD:-0}" != "1" ]; then
  swift build --disable-index-store -j "${SIGNAL_RENDER_SMOKE_JOBS:-1}" --product signal-ui-render
fi

bin_dir="$(swift build --show-bin-path)"
export SIGNAL_RENDER_CAPTURE_BINARY="${SIGNAL_RENDER_CAPTURE_BINARY:-$bin_dir/signal-ui-render}"
export SIGNAL_RENDER_CAPTURE_DELAY="${SIGNAL_RENDER_CAPTURE_DELAY:-18}"
export SIGNAL_UI_RENDER_TYPE_TEXT="$text"
export SIGNAL_UI_RENDER_CLICK_SEND=1
export SIGNAL_UI_RENDER_CLICK_SEND_DELAY_MS="${SIGNAL_UI_RENDER_CLICK_SEND_DELAY_MS:-700}"
export SIGNAL_UI_RENDER_LOG_INPUT_BODY=1
export SIGNAL_UI_RENDER_LOG_BUTTON_ACTIONS=1
export SIGNAL_UI_RENDER_LOG_INTERACTIONS=1
export SIGNAL_UI_RENDER_LOG_INTERACTIONS_DELAY_MS="${SIGNAL_UI_RENDER_LOG_INTERACTIONS_DELAY_MS:-1200}"
export SIGNAL_UI_RENDER_DRAIN_SEND_QUEUE=1
export SIGNAL_UI_RENDER_DRAIN_SEND_QUEUE_TIMEOUT_MS="${SIGNAL_UI_RENDER_DRAIN_SEND_QUEUE_TIMEOUT_MS:-6000}"

"$ROOT/scripts/signal-render-capture.sh" real-conversation-accepted "$output" "$log_output"

require_log_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$log_output"; then
    echo "Signal send smoke missing expected log line: $needle" >&2
    echo "Log: $log_output" >&2
    exit 1
  fi
}

require_log_line 'signal-ui-render: after send click body=""'
require_log_line "signal-ui-render: after send click interactions send queue drained"
require_log_line "signal-ui-render: after send click interactions count=3 bodies="
require_log_line "$text"

echo "Signal send smoke passed: $output"
