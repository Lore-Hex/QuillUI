#!/usr/bin/env bash

QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

source "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh"

quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE
quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD

quillui_install_linux_backend_smoke_packages() {
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

quillui_resolve_linux_backend_executable() {
  local product="$1"
  local output_var="$2"

  if [[ -n "${QUILLUI_GTK_APP_EXECUTABLE:-}" ]]; then
    printf -v "$output_var" "%s" "$QUILLUI_GTK_APP_EXECUTABLE"
    return
  fi

  if [[ "$product" == "quill-chat-linux" ]]; then
    local quill_chat_app_dir="${QUILL_CHAT_DIR:-$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/../quill/clients/quill-chat}/Enchanted"
    local quill_chat_work_root="${QUILLUI_QUILL_CHAT_BUILD_WORKDIR:-$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build/quill-chat-linux}"

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
        find "$quill_chat_work_root/.build-check" -path "*/debug/$product" -type f -perm -111 2>/dev/null | head -n 1 || true
      )"
      if [[ -z "$cached_executable" ]]; then
        echo "No cached executable found for $product under $quill_chat_work_root/.build-check" >&2
        exit 66
      fi
      printf -v "$output_var" "%s" "$cached_executable"
      return
    fi

    QUILLUI_QUILL_CHAT_BUILD_WORKDIR="$quill_chat_work_root" \
      QUILLUI_QUILL_CHAT_PRODUCT_NAME="$product" \
      "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/build-quill-chat-linux.sh"

    local quill_chat_bin_path
    quill_chat_bin_path="$(swift build \
      --package-path "$quill_chat_work_root/package" \
      --scratch-path "$quill_chat_work_root/.build-check" \
      --show-bin-path)"
    printf -v "$output_var" "%s" "$quill_chat_bin_path/$product"
  else
    if [[ "${QUILLUI_GTK_SKIP_BUILD:-0}" == "1" ]]; then
      local cached_executable
      cached_executable="$(
        find "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" -path "*/debug/$product" -type f -perm -111 2>/dev/null | head -n 1 || true
      )"
      if [[ -z "$cached_executable" ]]; then
        echo "No cached executable found for $product under $QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" >&2
        exit 66
      fi
      printf -v "$output_var" "%s" "$cached_executable"
    else
      "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux"
      swift build --scratch-path "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" --product "$product"
      local bin_path
      bin_path="$(swift build --scratch-path "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" --show-bin-path)"
      printf -v "$output_var" "%s" "$bin_path/$product"
    fi
  fi
}

quillui_seed_quill_chat_reference_data() {
  local qa_home="$1"
  rm -rf "$qa_home"
  python3 "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/seed-quill-chat-reference-data.py" "$qa_home"
}
