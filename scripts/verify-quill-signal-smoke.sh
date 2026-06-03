#!/usr/bin/env bash
#
# Runtime smoke for the QuillSignal native app (real Signal on QuillOS).
#
# Builds the quill-signal GTK app, starts the presage/libsignal bridge daemon,
# launches the app offscreen under Xvfb, and asserts the running app queried the
# REAL engine for account status (app -> QuillSignalKit -> unix socket -> Rust
# bridge -> presage -> libsignal store). No Signal account required.
#
# Run inside the quillui-signal-build image with the qs-work volume mounted, e.g.:
#   docker run --rm -v "$PWD":/qui -v qui-build-linux:/qui/.build-linux \
#     -v qs-work:/work -w /qui quillui-signal-build scripts/verify-quill-signal-smoke.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${QUILL_SIGNAL_SCRATCH:-.build-linux}"
SOCK="${QUILL_SIGNAL_SOCK:-/tmp/quill-signal-bridge.sock}"
BRIDGE="${QUILL_SIGNAL_BRIDGE:-/work/presage/target/debug/quill-signal-bridge}"
APP="$ROOT_DIR/$SCRATCH/aarch64-unknown-linux-gnu/debug/quill-signal"

cd "$ROOT_DIR"
export HOME="${HOME:-/tmp}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdgrt}"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

echo "==> building quill-signal (canonical GTK recipe)"
QUILLUI_LINUX_BACKEND=gtk scripts/prepare-linux-build-backend.sh --scratch-path "$SCRATCH" >/dev/null
QUILLUI_LINUX_BACKEND=gtk swift build --scratch-path "$SCRATCH" --disable-index-store --product quill-signal

[ -x "$APP" ] || { echo "FAIL: app binary missing at $APP"; exit 1; }
[ -x "$BRIDGE" ] || { echo "FAIL: bridge daemon missing at $BRIDGE (mount qs-work)"; exit 1; }

echo "==> starting bridge daemon"
rm -f /tmp/qs.db*
QSIGNAL_DB=/tmp/qs.db "$BRIDGE" "$SOCK" 2>/tmp/quill-signal-daemon.log &
DPID=$!
trap 'kill "$DPID" 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do [ -S "$SOCK" ] && break; sleep 0.3; done
[ -S "$SOCK" ] || { echo "FAIL: bridge daemon did not bind $SOCK"; cat /tmp/quill-signal-daemon.log; exit 1; }

echo "==> launching app offscreen under Xvfb (12s)"
GTK_A11Y=none GSK_RENDERER=cairo QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1 \
  timeout 12 xvfb-run -a "$APP" >/tmp/quill-signal-app.log 2>&1 || true

if grep -q '\[QuillSignal\] bridge status ->' /tmp/quill-signal-app.log; then
  echo "PASS: app launched and queried the real engine:"
  grep '\[QuillSignal\] bridge status ->' /tmp/quill-signal-app.log | head -1
else
  echo "FAIL: app did not query the bridge"
  tail -25 /tmp/quill-signal-app.log
  exit 1
fi
