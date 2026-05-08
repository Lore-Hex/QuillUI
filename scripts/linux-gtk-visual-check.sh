#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-enchanted-gtk.png}"
PRODUCT="${2:-quill-enchanted}"
APP_EXECUTABLE=""

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

build_and_resolve_executable() {
  if [[ "$PRODUCT" == "quill-chat-linux" ]]; then
    local quill_chat_app_dir="${QUILL_CHAT_DIR:-$ROOT_DIR/../quill/clients/quill-chat}/Enchanted"
    local quill_chat_work_root="${QUILLUI_QUILL_CHAT_BUILD_WORKDIR:-$ROOT_DIR/.build/quill-chat-linux}"

    if [[ ! -d "$quill_chat_app_dir" ]]; then
      cat >&2 <<MSG
Quill Chat source was not found at:
  $quill_chat_app_dir

Set QUILL_CHAT_DIR=/path/to/quill/clients/quill-chat or pass a different
SwiftPM product as the second argument.
MSG
      exit 66
    fi

    QUILLUI_QUILL_CHAT_BUILD_WORKDIR="$quill_chat_work_root" \
    QUILLUI_QUILL_CHAT_PRODUCT_NAME="$PRODUCT" \
    "$ROOT_DIR/scripts/build-quill-chat-linux.sh"

    local quill_chat_bin_path
    quill_chat_bin_path="$(swift build \
      --package-path "$quill_chat_work_root/package" \
      --scratch-path "$quill_chat_work_root/.build-check" \
      --show-bin-path)"
    APP_EXECUTABLE="$quill_chat_bin_path/$PRODUCT"
  else
    "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$ROOT_DIR/.build-linux"
    swift build --scratch-path "$ROOT_DIR/.build-linux" --product "$PRODUCT"
    local bin_path
    bin_path="$(swift build --scratch-path "$ROOT_DIR/.build-linux" --show-bin-path)"
    APP_EXECUTABLE="$bin_path/$PRODUCT"
  fi
}

build_and_resolve_executable

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Built executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

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
GTK_A11Y=none DISPLAY="$DISPLAY_ID" "$APP_EXECUTABLE" >/tmp/quillui-gtk-app.log 2>&1 &
app_pid=$!

sleep 4
DISPLAY="$DISPLAY_ID" import -window root "$SCREENSHOT_PATH"

"$ROOT_DIR/scripts/verify-gtk-screenshot.py" "$SCREENSHOT_PATH" "$PRODUCT"
