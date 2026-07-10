#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$ROOT/.qa/signal-real-receive-smoke.png}"
log_output="${2:-${output%.png}.log}"
text="${SIGNAL_RENDER_SMOKE_TEXT:-Linux_receive_smoke_$(date +%s)}"

cd "$ROOT"

if [ "${SIGNAL_RENDER_SMOKE_SKIP_BUILD:-0}" != "1" ]; then
  swift build --disable-index-store -j "${SIGNAL_RENDER_SMOKE_JOBS:-1}" --product signal-ui-render
fi

bin_dir="$(swift build --show-bin-path)"
export SIGNAL_RENDER_CAPTURE_BINARY="${SIGNAL_RENDER_CAPTURE_BINARY:-$bin_dir/signal-ui-render}"
export SIGNAL_RENDER_CAPTURE_DELAY="${SIGNAL_RENDER_CAPTURE_DELAY:-18}"
export SIGNAL_UI_RENDER_INJECT_INCOMING_TEXT="$text"
export SIGNAL_UI_RENDER_INJECT_INCOMING_DELAY_MS="${SIGNAL_UI_RENDER_INJECT_INCOMING_DELAY_MS:-900}"
export SIGNAL_UI_RENDER_LOG_INTERACTIONS=1
export SIGNAL_UI_RENDER_LOG_INTERACTIONS_DELAY_MS="${SIGNAL_UI_RENDER_LOG_INTERACTIONS_DELAY_MS:-1200}"

"$ROOT/scripts/signal-render-capture.sh" real-conversation-accepted "$output" "$log_output"

require_log_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$log_output"; then
    echo "Signal receive smoke missing expected log line: $needle" >&2
    echo "Log: $log_output" >&2
    exit 1
  fi
}

require_log_line "signal-ui-render: scheduled incoming injection"
require_log_line "signal-ui-render: injected incoming message summary count=3 bodies="
require_log_line "$text"

"$ROOT/scripts/verify-backend-screenshot.py" "$output" signal-real-conversation-receive

echo "Signal receive smoke passed: $output"
