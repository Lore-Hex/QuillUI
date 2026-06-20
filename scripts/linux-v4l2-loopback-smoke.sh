#!/usr/bin/env bash
# Optional live-camera smoke for the SolderScope V4L2 capture path.
#
# Stands up a v4l2loopback virtual webcam, feeds it a YUYV test pattern with
# ffmpeg, then builds and runs QuillV4L2LiveProbe (QUILLUI_V4L2_LIVE_PROBE=1)
# against it. The probe drives the real QuillV4L2Camera end-to-end: QUERYCAP
# discovery -> S_FMT/G_FMT YUYV -> mmap ring -> STREAMON -> DQBUF loop ->
# YUYV->BGRA -> CVPixelBuffer, proving SolderScope's camera works on a live
# device.
#
# SKIPS cleanly (exit 0) wherever a real V4L2 device can't be created — the
# standard Linux CI runs inside a container that can't load kernel modules,
# and OrbStack/LinuxKit kernels lack v4l2loopback. It is meaningful on a
# real-kernel host or non-containerized runner with v4l2loopback-dkms +
# linux-headers + ffmpeg installed. Run from a real-kernel Linux dev VM:
#   scripts/linux-v4l2-loopback-smoke.sh [scratch-path]
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SCRATCH_PATH="${1:-.build-linux}"

skip() { echo "SKIP linux-v4l2-loopback-smoke: $1"; exit 0; }

command -v ffmpeg >/dev/null 2>&1 || skip "ffmpeg not installed"
command -v modprobe >/dev/null 2>&1 || skip "modprobe unavailable"
[ -d "/lib/modules/$(uname -r)" ] || skip "no kernel modules for $(uname -r) (containerized?)"

loaded_here=0
if ! lsmod 2>/dev/null | grep -q '^v4l2loopback'; then
  if sudo modprobe v4l2loopback devices=1 video_nr=0 card_label=QuillVirtualCam exclusive_caps=1 2>/dev/null; then
    loaded_here=1
  else
    skip "cannot load v4l2loopback (module not built or insufficient privilege)"
  fi
fi
[ -e /dev/video0 ] || skip "/dev/video0 did not appear after modprobe"
sudo chmod 666 /dev/video0 2>/dev/null || true

# Feed a YUYV test pattern; v4l2loopback (exclusive_caps) then presents the
# node as a capture device to the probe.
setsid ffmpeg -nostdin -re -f lavfi -i testsrc2=size=1280x720:rate=30 \
  -pix_fmt yuyv422 -f v4l2 /dev/video0 >/tmp/quillui-v4l2-feed.log 2>&1 </dev/null &
feed_pid=$!

cleanup() {
  kill "$feed_pid" 2>/dev/null || true
  [ "$loaded_here" = 1 ] && sudo modprobe -r v4l2loopback 2>/dev/null || true
}
trap cleanup EXIT

sleep 4
if ! kill -0 "$feed_pid" 2>/dev/null; then
  echo "ffmpeg feed exited early:"; tail -5 /tmp/quillui-v4l2-feed.log || true
  skip "ffmpeg could not drive /dev/video0"
fi

echo "=== virtual webcam up on /dev/video0; building + running QuillV4L2LiveProbe ==="
export QUILLUI_V4L2_LIVE_PROBE=1
export QUILLUI_LINUX_BACKEND="${QUILLUI_LINUX_BACKEND:-gtk}"
"$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
  swift build --scratch-path "$SCRATCH_PATH" --product QuillV4L2LiveProbe

bin_path="$("$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
  swift build --scratch-path "$SCRATCH_PATH" --product QuillV4L2LiveProbe --show-bin-path)"
exec "$bin_path/QuillV4L2LiveProbe"
