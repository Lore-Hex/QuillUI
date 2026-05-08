#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-enchanted-gtk.png}"
PRODUCT="${2:-quill-enchanted}"

install_packages() {
  if [[ "${QUILLUI_SKIP_APT:-0}" == "1" ]]; then
    return
  fi

  local packages=(
    imagemagick
    x11-apps
    xvfb
  )
  local missing=()

  for package in "${packages[@]}"; do
    if ! dpkg -s "$package" >/dev/null 2>&1; then
      missing+=("$package")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
  fi
}

install_packages

mkdir -p "$(dirname "$SCREENSHOT_PATH")"

"$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$ROOT_DIR/.build-linux"
swift build --scratch-path "$ROOT_DIR/.build-linux" --product "$PRODUCT"
BIN_PATH="$(swift build --scratch-path "$ROOT_DIR/.build-linux" --show-bin-path)"

DISPLAY_ID=":94"
Xvfb "$DISPLAY_ID" -screen 0 1180x760x24 >/tmp/quillui-xvfb.log 2>&1 &
xvfb_pid=$!

cleanup() {
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  kill "$xvfb_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 1
GTK_A11Y=none DISPLAY="$DISPLAY_ID" "$BIN_PATH/$PRODUCT" >/tmp/quillui-gtk-app.log 2>&1 &
app_pid=$!

sleep 4
DISPLAY="$DISPLAY_ID" import -window root "$SCREENSHOT_PATH"

python3 - "$SCREENSHOT_PATH" <<'PY'
import struct
import subprocess
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists() or path.stat().st_size == 0:
    raise SystemExit("Screenshot was not created")

probe = subprocess.run(
    ["identify", "-format", "%w %h %[mean]", str(path)],
    check=True,
    text=True,
    stdout=subprocess.PIPE,
)
width_text, height_text, mean_text = probe.stdout.split()
width = int(width_text)
height = int(height_text)
mean = float(mean_text)

if width < 900 or height < 600:
    raise SystemExit(f"Screenshot is unexpectedly small: {width}x{height}")

if mean <= 1000:
    raise SystemExit(f"Screenshot appears blank or near-black: mean={mean}")

sys.stdout.write(f"Visual smoke screenshot: {path} ({width}x{height}, mean={mean:.1f})\n")
PY
