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
    clang
    git
    imagemagick
    libgdk-pixbuf-2.0-dev
    libgtk-4-dev
    libsqlite3-dev
    pkg-config
    x11-apps
    xdotool
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

seed_quill_chat_reference_data() {
  local qa_home="$1"
  rm -rf "$qa_home"
  python3 "$ROOT_DIR/scripts/seed-quill-chat-reference-data.py" "$qa_home"
}

DISPLAY_ID=":94"
SCREEN_SIZE="${QUILLUI_GTK_SCREEN_SIZE:-1180x760x24}"
if [[ "$PRODUCT" == "quill-chat-linux" && "${QUILLUI_GTK_MAC_REFERENCE:-0}" == "1" ]]; then
  SCREEN_SIZE="${QUILLUI_GTK_SCREEN_SIZE:-2048x1380x24}"
fi
Xvfb "$DISPLAY_ID" -screen 0 "$SCREEN_SIZE" >/tmp/quillui-xvfb.log 2>&1 &
xvfb_pid=$!

cleanup() {
  if [[ -n "${app_pid:-}" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  kill "$xvfb_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 1
if ! kill -0 "$xvfb_pid" >/dev/null 2>&1; then
  cat /tmp/quillui-xvfb.log >&2 || true
  exit 70
fi
app_environment=(GTK_A11Y=none DISPLAY="$DISPLAY_ID")
if [[ -n "${QUILLUI_GTK_LAYOUT_DEBUG:-}" ]]; then
  app_environment+=(QUILLUI_GTK_LAYOUT_DEBUG="$QUILLUI_GTK_LAYOUT_DEBUG")
fi
if [[ "$PRODUCT" == "quill-chat-linux" && "${QUILLUI_GTK_MAC_REFERENCE:-0}" == "1" ]]; then
  quill_chat_reference_home="$OUTPUT_DIR/quill-chat-linux-reference-home"
  seed_quill_chat_reference_data "$quill_chat_reference_home"
  app_environment+=(
    HOME="$quill_chat_reference_home"
    QUILLDATA_HOME="$quill_chat_reference_home"
    QUILLUI_GTK_DEFAULT_WINDOW_WIDTH=2048
    QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT=1380
    QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL=1
    QUILLUI_QUILL_CHAT_REFERENCE_MODE=1
    QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1
  )
fi
env "${app_environment[@]}" "$APP_EXECUTABLE" >/tmp/quillui-gtk-app.log 2>&1 &
app_pid=$!

sleep 4
capture_window="root"
if [[ "$PRODUCT" == "quill-chat-linux" && "${QUILLUI_GTK_MAC_REFERENCE:-0}" == "1" ]]; then
  window_id="$(
    DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --name 'Quill Chat' 2>/dev/null | head -n 1 || true
  )"
  if [[ -z "$window_id" ]]; then
    window_id="$(
      DISPLAY="$DISPLAY_ID" xdotool search --onlyvisible --name '.*' 2>/dev/null | head -n 1 || true
    )"
  fi
  if [[ -n "$window_id" ]]; then
    DISPLAY="$DISPLAY_ID" xdotool windowmove "$window_id" 0 0
    DISPLAY="$DISPLAY_ID" xdotool windowsize "$window_id" 2048 1380
    capture_window="$window_id"
    sleep 1
  fi
fi
DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"

VERIFY_PRODUCT="${QUILLUI_GTK_VERIFY_PRODUCT:-$PRODUCT}"
if [[ "$PRODUCT" == "quill-chat-linux" && "${QUILLUI_GTK_MAC_REFERENCE:-0}" == "1" ]]; then
  VERIFY_PRODUCT="${QUILLUI_GTK_VERIFY_PRODUCT:-quill-chat-linux-mac-reference}"
fi
"$ROOT_DIR/scripts/verify-gtk-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"
