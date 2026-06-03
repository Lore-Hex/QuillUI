#!/usr/bin/env bash
#
# quill-signal-screenshot.sh — capture a PNG of the running native QuillUI/GTK
# `quill-signal` app so its UI can be inspected visually (the link panel + QR).
#
# Runs a real Xvfb on a known DISPLAY (so the X root can be screenshotted — unlike
# the offscreen-render smoke), starts the presage bridge daemon, launches the app
# with QUILLUI_SIGNAL_AUTOLINK=1 (which presents the link panel and fetches the
# provisioning URL + QR from the engine), waits for it to render, then captures
# the X root window to a PNG.
#
# AUTOLINK only *begins* a link (prints the QR); it never *completes* one, so this
# touches no real Signal account. The QR is for a throwaway provisioning URL.
#
# Run inside the quillui-signal-build image (it has Xvfb + imagemagick + x11-apps):
#   docker run --rm \
#     -v "$PWD":/qui -v qui-build-linux:/qui/.build-linux -v qs-work:/work \
#     quillui-signal-build /qui/scripts/quill-signal-screenshot.sh
#
# The app + daemon binaries must already be built (see QUILLSIGNAL_RUN.md). Output
# defaults to /qui/.qs-shot.png (gitignored). Override via env:
#   QS_SHOT_OUT, QS_DISPLAY, QS_APP_BIN, QS_BRIDGE_BIN, QS_SOCK, QS_DB, QS_WAIT
set -euo pipefail

OUT="${QS_SHOT_OUT:-/qui/.qs-shot.png}"
DISP="${QS_DISPLAY:-:99}"
APP_BIN="${QS_APP_BIN:-/qui/.build-linux/aarch64-unknown-linux-gnu/debug/quill-signal}"
BRIDGE_BIN="${QS_BRIDGE_BIN:-/work/presage/target/debug/quill-signal-bridge}"
SOCK="${QS_SOCK:-/tmp/quill-signal-bridge.sock}"
DB="${QS_DB:-/tmp/qs.db}"
WAIT="${QS_WAIT:-9}"
SCREEN_SIZE="${QS_SCREEN:-1100x820x24}"

[ -x "$APP_BIN" ]    || { echo "app binary not found/executable: $APP_BIN" >&2; exit 1; }
[ -x "$BRIDGE_BIN" ] || { echo "bridge binary not found/executable: $BRIDGE_BIN" >&2; exit 1; }

export HOME="${HOME:-/tmp}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdgrt}"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

XPID="" ; DPID="" ; APID=""
cleanup() { for p in "$APID" "$DPID" "$XPID"; do [ -n "$p" ] && kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT

echo ">> Xvfb $DISP ($SCREEN_SIZE)"
Xvfb "$DISP" -screen 0 "$SCREEN_SIZE" >/tmp/qs-xvfb.log 2>&1 &
XPID=$!
sleep 2
export DISPLAY="$DISP"

echo ">> bridge daemon ($SOCK, db=$DB)"
rm -f "$DB"*
QSIGNAL_DB="$DB" "$BRIDGE_BIN" "$SOCK" >/tmp/qs-daemon.log 2>&1 &
DPID=$!
for _ in $(seq 1 40); do [ -S "$SOCK" ] && break; sleep 0.3; done
[ -S "$SOCK" ] || { echo "bridge socket never appeared" >&2; cat /tmp/qs-daemon.log >&2; exit 1; }

echo ">> app (autolink, GTK on cairo)"
QUILLUI_SIGNAL_AUTOLINK=1 GTK_A11Y=none GSK_RENDERER=cairo \
  "$APP_BIN" >/tmp/qs-app.log 2>&1 &
APID=$!

echo ">> waiting ${WAIT}s for the QR to render"
sleep "$WAIT"

echo ">> capturing X root -> $OUT"
if ! import -window root "$OUT" 2>/tmp/qs-shot.log; then
  xwd -root -display "$DISP" -silent | convert xwd:- "$OUT"
fi

echo "== app log (QuillSignal lines) =="
grep "\[QuillSignal\]" /tmp/qs-app.log | head -5 || true
ls -la "$OUT"
echo ">> done: $OUT"
