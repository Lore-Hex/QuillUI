#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-$ROOT/.qa/signal-chat-stub-smoke.png}"
log_output="${2:-${output%.png}.log}"
display_id="${SIGNAL_CHAT_SMOKE_DISPLAY:-:98}"
socket_path="${SIGNAL_CHAT_SMOKE_SOCKET:-/tmp/quill-signal-chat-smoke.sock}"

cd "$ROOT"
mkdir -p "$(dirname "$output")" "$(dirname "$log_output")"

if [ "${SIGNAL_CHAT_SMOKE_SKIP_BUILD:-0}" != "1" ]; then
  swift build --disable-index-store -j "${SIGNAL_CHAT_SMOKE_JOBS:-1}" --product signal-chat
fi

bin_dir="$(swift build --show-bin-path)"
binary="${SIGNAL_CHAT_SMOKE_BINARY:-$bin_dir/signal-chat}"
if [ ! -x "$binary" ]; then
  echo "signal-chat binary not found or not executable: $binary" >&2
  exit 1
fi

for required in Xvfb import python3; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "$required is required for signal-chat stub smoke" >&2
    exit 1
  fi
done

rm -f "$socket_path"
Xvfb "$display_id" -screen 0 "${SIGNAL_CHAT_SMOKE_SCREEN:-1080x700x24}" >"${log_output%.log}-xvfb.log" 2>&1 &
xvfb_pid=$!
stub_pid=
app_pid=

cleanup() {
  if [ -n "${app_pid:-}" ]; then
    kill "$app_pid" 2>/dev/null || true
  fi
  if [ -n "${stub_pid:-}" ]; then
    kill "$stub_pid" 2>/dev/null || true
  fi
  kill "$xvfb_pid" 2>/dev/null || true
  rm -f "$socket_path"
}
trap cleanup EXIT

STUB_RECV_EVERY="${SIGNAL_CHAT_SMOKE_RECV_EVERY:-3}" \
  python3 "$ROOT/scripts/signal-chat-stub-bridge.py" "$socket_path" >"${log_output%.log}-stub.log" 2>&1 &
stub_pid=$!

deadline=$((SECONDS + 10))
while [ ! -S "$socket_path" ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "signal-chat stub bridge did not create $socket_path" >&2
    exit 1
  fi
  sleep 0.1
done

DISPLAY="$display_id" \
GTK_A11Y=none \
GSK_RENDERER="${GSK_RENDERER:-cairo}" \
QSIGNAL_SOCK="$socket_path" \
"$binary" >"$log_output" 2>&1 &
app_pid=$!

sleep "${SIGNAL_CHAT_SMOKE_CAPTURE_DELAY:-7}"
DISPLAY="$display_id" import -window root "$output"

"$ROOT/scripts/verify-backend-screenshot.py" "$output" signal-chat-stub

echo "Signal chat stub smoke passed: $output"
