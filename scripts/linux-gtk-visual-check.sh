#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/.qa"
SCREENSHOT_PATH="${1:-$OUTPUT_DIR/quill-enchanted-gtk.png}"
PRODUCT="${2:-quill-enchanted}"
APP_EXECUTABLE=""

source "$ROOT_DIR/scripts/quillui-backend-products.sh"

# Backend-neutral names are canonical for new GTK/Qt parity checks.
# The legacy QUILLUI_GTK_* names stay supported so older docs and
# local scripts do not break while callers migrate.
quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE
quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD
quillui_alias_env QUILLUI_BACKEND_VISUAL_DISPLAY QUILLUI_GTK_VISUAL_DISPLAY
quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE
quillui_alias_env QUILLUI_BACKEND_VISUAL_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE
quillui_alias_env QUILLUI_BACKEND_MAC_REFERENCE QUILLUI_GTK_MAC_REFERENCE
quillui_alias_env QUILLUI_BACKEND_LAYOUT_DEBUG QUILLUI_GTK_LAYOUT_DEBUG
quillui_alias_env QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH QUILLUI_GTK_DEFAULT_WINDOW_WIDTH
quillui_alias_env QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT
quillui_alias_env QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL
quillui_alias_env QUILLUI_BACKEND_VERIFY_PRODUCT QUILLUI_GTK_VERIFY_PRODUCT

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
  if [[ -n "${QUILLUI_GTK_APP_EXECUTABLE:-}" ]]; then
    APP_EXECUTABLE="$QUILLUI_GTK_APP_EXECUTABLE"
    return
  fi

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

    if [[ "${QUILLUI_GTK_SKIP_BUILD:-0}" == "1" ]]; then
      local cached_executable
      cached_executable="$(
        find "$quill_chat_work_root/.build-check" -path "*/debug/$PRODUCT" -type f -perm -111 2>/dev/null | head -n 1 || true
      )"
      if [[ -z "$cached_executable" ]]; then
        echo "No cached executable found for $PRODUCT under $quill_chat_work_root/.build-check" >&2
        exit 66
      fi
      APP_EXECUTABLE="$cached_executable"
      return
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
    if [[ "${QUILLUI_GTK_SKIP_BUILD:-0}" == "1" ]]; then
      local cached_executable
      cached_executable="$(
        find "$ROOT_DIR/.build-linux" -path "*/debug/$PRODUCT" -type f -perm -111 2>/dev/null | head -n 1 || true
      )"
      if [[ -z "$cached_executable" ]]; then
        echo "No cached executable found for $PRODUCT under $ROOT_DIR/.build-linux" >&2
        exit 66
      fi
      APP_EXECUTABLE="$cached_executable"
    else
      "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$ROOT_DIR/.build-linux"
      swift build --scratch-path "$ROOT_DIR/.build-linux" --product "$PRODUCT"
      local bin_path
      bin_path="$(swift build --scratch-path "$ROOT_DIR/.build-linux" --show-bin-path)"
      APP_EXECUTABLE="$bin_path/$PRODUCT"
    fi
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

is_quill_chat_mac_reference() {
  [[ "$PRODUCT" == "quill-chat-linux" && "${QUILLUI_GTK_MAC_REFERENCE:-0}" == "1" ]]
}

reference_window_width="${QUILLUI_GTK_DEFAULT_WINDOW_WIDTH:-2048}"
reference_window_height="${QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT:-1380}"
hide_window_menubar_label="${QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL:-1}"

DISPLAY_ID="${QUILLUI_GTK_VISUAL_DISPLAY:-:94}"
SCREEN_SIZE="${QUILLUI_GTK_SCREEN_SIZE:-1180x760x24}"
if is_quill_chat_mac_reference; then
  SCREEN_SIZE="${QUILLUI_GTK_SCREEN_SIZE:-${reference_window_width}x${reference_window_height}x24}"
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
requested_backend="$(quillui_requested_backend_for_product "$PRODUCT")"
if [[ -n "$requested_backend" ]]; then
  app_environment+=(QUILLUI_BACKEND="$requested_backend")
fi
if [[ -n "${QUILLUI_GTK_LAYOUT_DEBUG:-}" ]]; then
  app_environment+=(QUILLUI_GTK_LAYOUT_DEBUG="$QUILLUI_GTK_LAYOUT_DEBUG")
fi
if is_quill_chat_mac_reference; then
  quill_chat_reference_home="$OUTPUT_DIR/quill-chat-linux-reference-home"
  seed_quill_chat_reference_data "$quill_chat_reference_home"
  app_environment+=(
    HOME="$quill_chat_reference_home"
    QUILLDATA_HOME="$quill_chat_reference_home"
    QUILLUI_GTK_DEFAULT_WINDOW_WIDTH="$reference_window_width"
    QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT="$reference_window_height"
    QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL="$hide_window_menubar_label"
    QUILLUI_QUILL_CHAT_REFERENCE_MODE=1
    QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1
  )
fi
env "${app_environment[@]}" "$APP_EXECUTABLE" >/tmp/quillui-gtk-app.log 2>&1 &
app_pid=$!

sleep 4
capture_window="root"
if is_quill_chat_mac_reference; then
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
    DISPLAY="$DISPLAY_ID" xdotool windowsize "$window_id" "$reference_window_width" "$reference_window_height"
    capture_window="$window_id"
    sleep 1
  fi
fi
DISPLAY="$DISPLAY_ID" import -window "$capture_window" "$SCREENSHOT_PATH"

VERIFY_PRODUCT="${QUILLUI_GTK_VERIFY_PRODUCT:-$PRODUCT}"
if is_quill_chat_mac_reference; then
  VERIFY_PRODUCT="${QUILLUI_GTK_VERIFY_PRODUCT:-quill-chat-linux-mac-reference}"
fi
"$ROOT_DIR/scripts/verify-gtk-screenshot.py" "$SCREENSHOT_PATH" "$VERIFY_PRODUCT"
