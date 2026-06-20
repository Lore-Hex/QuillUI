#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$ROOT/.qa/signal-real-pending-continue-smoke.png}"
log_output="${2:-${output%.png}.log}"

cd "$ROOT"

if [ "${SIGNAL_RENDER_SMOKE_SKIP_BUILD:-0}" != "1" ]; then
  swift build --disable-index-store -j "${SIGNAL_RENDER_SMOKE_JOBS:-1}" --product signal-ui-render
fi

bin_dir="$(swift build --show-bin-path)"
export SIGNAL_RENDER_CAPTURE_BINARY="${SIGNAL_RENDER_CAPTURE_BINARY:-$bin_dir/signal-ui-render}"
export SIGNAL_RENDER_CAPTURE_DELAY="${SIGNAL_RENDER_CAPTURE_DELAY:-18}"
export SIGNAL_UI_RENDER_CLICK_BUTTON_LABEL=Continue
export SIGNAL_UI_RENDER_CLICK_BUTTON_LABEL_DELAY_MS="${SIGNAL_UI_RENDER_CLICK_BUTTON_LABEL_DELAY_MS:-700}"
export SIGNAL_UI_RENDER_LOG_BUTTON_ACTIONS=1
export SIGNAL_UI_RENDER_AUTO_CONFIRM_ACTION_SHEETS=1

"$ROOT/scripts/signal-render-capture.sh" real-conversation "$output" "$log_output"

require_log_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$log_output"; then
    echo "Signal pending-request Continue smoke missing expected log line: $needle" >&2
    echo "Log: $log_output" >&2
    exit 1
  fi
}

require_log_absent_after_rerender() {
  local needle="$1"
  python3 - "$log_output" "$needle" <<'PY'
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
needle = sys.argv[2]
text = log_path.read_text()
marker = 'signal-ui-render: rerendered UIKit tree after button label click "Continue"'
if marker not in text:
    raise SystemExit(f"Signal pending-request Continue smoke missing expected log line: {marker}")
tail = text.split(marker, 1)[1]
if needle in tail:
    raise SystemExit(
        f"Signal pending-request Continue smoke found unexpected post-rerender text: {needle}\n"
        f"Log: {log_path}"
    )
PY
}

require_log_line 'signal-ui-render: scheduled button label click "Continue"'
require_log_line "signal-ui-render: gtk button click"
require_log_line 'signal-ui-render: auto-confirmed action sheet title="Accept Request?" action="Accept"'
require_log_line 'signal-ui-render: clicked button label="Continue"'
require_log_line "signal-ui-render: pending request continuation settled dbPending=false viewModelPending=false bottomViewType=inputToolbar hasInputToolbar=true"
require_log_line 'signal-ui-render: rerendered UIKit tree after button label click "Continue"'
require_log_line "ConversationInputToolbar"
require_log_absent_after_rerender "MessageRequestView"

"$ROOT/scripts/verify-backend-screenshot.py" "$output" signal-real-conversation-accepted-request

echo "Signal pending-request Continue smoke passed: $output"
