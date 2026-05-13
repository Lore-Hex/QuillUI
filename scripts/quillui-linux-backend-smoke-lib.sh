#!/usr/bin/env bash

QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

source "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh"

quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE
quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD

quillui_normalize_x_display_id() {
  local value="$1"
  if [[ -z "$value" ]]; then
    echo ""
  elif [[ "$value" == :* ]]; then
    echo "$value"
  else
    echo ":$value"
  fi
}

quillui_is_quill_chat_mac_reference_product() {
  local product="$1"
  [[ "$product" == "quill-chat-linux" && "${QUILLUI_BACKEND_MAC_REFERENCE:-0}" == "1" ]]
}

quillui_append_environment_assignment() {
  local output_array="$1"
  local assignment="$2"

  # Bash 3.2 ships on macOS and has no nameref support, so the shared
  # launch-environment helper appends through the caller-provided array name.
  if [[ ! "$output_array" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Invalid environment array name: $output_array" >&2
    return 64
  fi
  eval "$output_array+=(\"\$assignment\")"
}

quillui_append_backend_launch_environment() {
  local output_array="$1"
  local product="$2"
  local display="${3:-}"
  local requested_backend="${4:-}"

  quillui_append_environment_assignment "$output_array" "GTK_A11Y=none"
  if [[ -n "$display" ]]; then
    quillui_append_environment_assignment "$output_array" "DISPLAY=$display"
  fi
  if [[ -z "$requested_backend" ]]; then
    requested_backend="$(quillui_requested_backend_for_product "$product")"
  fi
  if [[ -n "$requested_backend" ]]; then
    quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND=$requested_backend"
  fi
}

quillui_append_quill_chat_reference_environment() {
  local output_array="$1"
  local reference_home="$2"
  local reference_window_width="$3"
  local reference_window_height="$4"
  local hide_window_menubar_label="$5"

  quillui_seed_quill_chat_reference_data "$reference_home"
  quillui_append_environment_assignment "$output_array" "HOME=$reference_home"
  quillui_append_environment_assignment "$output_array" "QUILLDATA_HOME=$reference_home"
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=$reference_window_width"
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=$reference_window_height"
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label"
  quillui_append_environment_assignment "$output_array" "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH=$reference_window_width"
  quillui_append_environment_assignment "$output_array" "QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT=$reference_window_height"
  quillui_append_environment_assignment "$output_array" "QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label"
  quillui_append_environment_assignment "$output_array" "QUILLUI_QUILL_CHAT_REFERENCE_MODE=1"
  quillui_append_environment_assignment "$output_array" "QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1"
}

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

  if [[ -n "${QUILLUI_BACKEND_APP_EXECUTABLE:-}" ]]; then
    printf -v "$output_var" "%s" "$QUILLUI_BACKEND_APP_EXECUTABLE"
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

    if [[ "${QUILLUI_BACKEND_SKIP_BUILD:-0}" == "1" ]]; then
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
    if [[ "${QUILLUI_BACKEND_SKIP_BUILD:-0}" == "1" ]]; then
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
