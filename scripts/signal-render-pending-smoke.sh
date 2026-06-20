#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$ROOT/.qa/signal-real-pending-smoke.png}"
log_output="${2:-${output%.png}.log}"

cd "$ROOT"

if [ "${SIGNAL_RENDER_SMOKE_SKIP_BUILD:-0}" != "1" ]; then
  swift build --disable-index-store -j "${SIGNAL_RENDER_SMOKE_JOBS:-1}" --product signal-ui-render
fi

bin_dir="$(swift build --show-bin-path)"
export SIGNAL_RENDER_CAPTURE_BINARY="${SIGNAL_RENDER_CAPTURE_BINARY:-$bin_dir/signal-ui-render}"
export SIGNAL_RENDER_CAPTURE_DELAY="${SIGNAL_RENDER_CAPTURE_DELAY:-8}"

"$ROOT/scripts/signal-render-capture.sh" real-conversation "$output" "$log_output"

require_log_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$log_output"; then
    echo "Signal pending-request smoke missing expected log line: $needle" >&2
    echo "Log: $log_output" >&2
    exit 1
  fi
}

require_log_line "MessageRequestView"
require_log_line "Name not verified"
require_log_line 'label="Block"'
require_log_line 'label="Report"'
require_log_line 'label="Continue"'

"$ROOT/scripts/verify-backend-screenshot.py" "$output" signal-real-conversation-pending

echo "Signal pending-request smoke passed: $output"
