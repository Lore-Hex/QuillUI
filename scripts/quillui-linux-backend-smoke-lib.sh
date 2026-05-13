#!/usr/bin/env bash

QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

source "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh"

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

quillui_export_backend_argument() {
  local requested_backend="${1:-}"

  if [[ -n "$requested_backend" ]]; then
    QUILLUI_BACKEND="$(quillui_require_backend_identifier "$requested_backend")" || return $?
    export QUILLUI_BACKEND
  fi
}

quillui_alias_backend_build_env() {
  quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE QUILLUI_QT_APP_EXECUTABLE
  quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD QUILLUI_QT_SKIP_BUILD
}

quillui_generated_app_backend_facade() {
  local candidate="${QUILLUI_QUILL_CHAT_BACKEND_FACADE:-${QUILLUI_APP_BACKEND_FACADE:-}}"

  if [[ -z "$candidate" && -n "${QUILLUI_BACKEND:-}" ]]; then
    candidate="$QUILLUI_BACKEND"
  fi

  if [[ -n "$candidate" ]]; then
    quillui_require_backend_identifier "$candidate" || return $?
  fi

  return 0
}

quillui_is_quill_chat_mac_reference_product() {
  local product="$1"
  [[ "$product" == "quill-chat-linux" && "${QUILLUI_BACKEND_MAC_REFERENCE:-0}" == "1" ]]
}

quillui_backend_screen_size() {
  local product="$1"
  local requested_screen_size="$2"
  local default_screen_size="$3"
  local reference_window_width="$4"
  local reference_window_height="$5"

  if [[ -n "$requested_screen_size" ]]; then
    echo "$requested_screen_size"
  elif quillui_is_quill_chat_mac_reference_product "$product"; then
    echo "${reference_window_width}x${reference_window_height}x24"
  else
    echo "$default_screen_size"
  fi
}

quillui_backend_reference_window_defaults() {
  local width_var="$1"
  local height_var="$2"
  local hide_menubar_label_var="$3"

  quillui_assign_output "$width_var" "${QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH:-2048}" || return $?
  quillui_assign_output "$height_var" "${QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT:-1380}" || return $?
  quillui_assign_output "$hide_menubar_label_var" "${QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL:-1}" || return $?
}

quillui_find_visible_window_by_name() {
  local display_id="$1"
  local name="$2"

  DISPLAY="$display_id" xdotool search --onlyvisible --name "$name" 2>/dev/null | head -n 1 || true
}

quillui_find_visible_window_for_pid() {
  local display_id="$1"
  local pid="$2"

  DISPLAY="$display_id" xdotool search --onlyvisible --pid "$pid" 2>/dev/null | head -n 1 || true
}

quillui_find_visible_window_for_pid_except() {
  local display_id="$1"
  local pid="$2"
  local excluded_window_id="$3"

  DISPLAY="$display_id" xdotool search --onlyvisible --pid "$pid" 2>/dev/null \
    | awk -v excluded_window_id="$excluded_window_id" \
        '$0 != excluded_window_id { candidate = $0 } END { if (candidate != "") print candidate }' \
    || true
}

quillui_find_any_visible_window() {
  local display_id="$1"

  DISPLAY="$display_id" xdotool search --onlyvisible "" 2>/dev/null | head -n 1 || true
}

quillui_find_quill_chat_reference_window() {
  local display_id="$1"
  local window_id

  window_id="$(quillui_find_visible_window_by_name "$display_id" "Quill Chat")"
  if [[ -n "$window_id" ]]; then
    echo "$window_id"
    return
  fi

  quillui_find_visible_window_by_name "$display_id" ".*"
}

quillui_move_window_to_origin() {
  local display_id="$1"
  local window_id="$2"

  DISPLAY="$display_id" xdotool windowmove "$window_id" 0 0
}

quillui_place_reference_window() {
  local display_id="$1"
  local window_id="$2"
  local width="$3"
  local height="$4"

  quillui_move_window_to_origin "$display_id" "$window_id"
  DISPLAY="$display_id" xdotool windowsize "$window_id" "$width" "$height"
  sleep 1
}

quillui_backend_visual_verify_product() {
  local product="$1"
  local output_var="$2"
  local verify_product="$product"

  if quillui_is_quill_chat_mac_reference_product "$product"; then
    verify_product="quill-chat-linux-mac-reference"
  fi
  if [[ -n "${QUILLUI_BACKEND_VERIFY_PRODUCT:-}" ]]; then
    verify_product="$QUILLUI_BACKEND_VERIFY_PRODUCT"
  fi

  quillui_assign_output "$output_var" "$verify_product"
}

quillui_backend_interaction_verify_product() {
  local product="$1"
  local interaction_mode="$2"
  local output_var="$3"
  local verify_product="$product"

  if [[ "$product" == "quill-chat-linux" ]]; then
    case "$interaction_mode" in
      composer-typed)
        verify_product="quill-chat-linux-mac-reference-composer-typed"
        ;;
      settings-panel|alert-settings-panel)
        verify_product="quill-chat-linux-mac-reference-settings-panel"
        ;;
      settings-endpoint-typed)
        verify_product="quill-chat-linux-mac-reference-settings-endpoint-typed"
        ;;
      completions-panel)
        verify_product="quill-chat-linux-mac-reference-completions-panel"
        ;;
      history-selection)
        verify_product="quill-chat-linux-mac-reference-history-selection"
        ;;
      transcript-selection)
        verify_product="quill-chat-linux-mac-reference-transcript-selection"
        ;;
      markdown-transcript-selection)
        verify_product="quill-chat-linux-mac-reference-markdown-transcript-selection"
        ;;
      long-transcript-selection)
        verify_product="quill-chat-linux-mac-reference-long-transcript-selection"
        ;;
      prompt-send)
        verify_product="quill-chat-linux-mac-reference-prompt-send"
        ;;
      *)
        verify_product="quill-chat-linux-toolbar-menu"
        if quillui_is_quill_chat_mac_reference_product "$product"; then
          verify_product="quill-chat-linux-mac-reference-toolbar-menu"
        fi
        ;;
    esac
  elif [[ "$product" == "quill-wireguard-qt" ]]; then
    case "$interaction_mode" in
      tunnel-selection|click)
        verify_product="quill-wireguard-qt-tunnel-selection"
        ;;
      tunnel-name-edit|name-edit)
        verify_product="quill-wireguard-qt-name-edit"
        ;;
    esac
  elif quillui_is_backend_smoke_product "$product"; then
    verify_product="$(quillui_backend_smoke_interaction_verify_product "$product" "$interaction_mode")" || return $?
  fi

  if [[ -n "${QUILLUI_BACKEND_VERIFY_PRODUCT:-}" ]]; then
    verify_product="$QUILLUI_BACKEND_VERIFY_PRODUCT"
  fi

  quillui_assign_output "$output_var" "$verify_product"
}

quillui_assign_output() {
  local output_var="$1"
  local value="$2"

  if [[ ! "$output_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Invalid output variable name: $output_var" >&2
    return 64
  fi

  printf -v "$output_var" "%s" "$value"
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

quillui_start_xvfb() {
  local display_id="$1"
  local screen_size="$2"
  local log_path="$3"
  local output_var="$4"

  quillui_assign_output "$output_var" "" || return $?
  Xvfb "$display_id" -screen 0 "$screen_size" >"$log_path" 2>&1 &
  local pid=$!
  quillui_assign_output "$output_var" "$pid" || return $?

  sleep 1
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    cat "$log_path" >&2 || true
    return 70
  fi
}

quillui_stop_process_if_running() {
  local pid="${1:-}"

  if [[ -n "$pid" ]]; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
}

quillui_append_backend_launch_environment() {
  local output_array="$1"
  local product="$2"
  local display="${3:-}"
  local requested_backend="${4:-}"

  quillui_append_environment_assignment "$output_array" "GTK_A11Y=none" || return $?
  if [[ -n "$display" ]]; then
    quillui_append_environment_assignment "$output_array" "DISPLAY=$display" || return $?
  fi
  if [[ -z "$requested_backend" ]]; then
    requested_backend="$(quillui_requested_backend_for_product "$product")" || return $?
  else
    requested_backend="$(quillui_require_backend_identifier "$requested_backend")" || return $?
  fi
  if [[ -n "$requested_backend" ]]; then
    quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND=$requested_backend" || return $?
  fi
}

quillui_append_backend_layout_debug_environment() {
  local output_array="$1"
  local layout_debug="${2:-}"

  if [[ -z "$layout_debug" ]]; then
    return
  fi

  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_LAYOUT_DEBUG=$layout_debug" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_GTK_LAYOUT_DEBUG=$layout_debug" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QT_LAYOUT_DEBUG=$layout_debug" || return $?
}

quillui_append_quill_chat_fixture_data_environment() {
  local output_array="$1"
  local fixture_home="$2"

  quillui_seed_quill_chat_reference_data "$fixture_home" || return $?
  quillui_append_environment_assignment "$output_array" "HOME=$fixture_home" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLDATA_HOME=$fixture_home" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QUILL_CHAT_REFERENCE_MODE=1" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1" || return $?
}

quillui_append_quill_chat_reference_environment() {
  local output_array="$1"
  local reference_home="$2"
  local reference_window_width="$3"
  local reference_window_height="$4"
  local hide_window_menubar_label="$5"

  quillui_append_quill_chat_fixture_data_environment "$output_array" "$reference_home" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=$reference_window_width" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=$reference_window_height" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH=$reference_window_width" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT=$reference_window_height" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QT_DEFAULT_WINDOW_WIDTH=$reference_window_width" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QT_DEFAULT_WINDOW_HEIGHT=$reference_window_height" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QT_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label" || return $?
}

quillui_append_quill_chat_reference_environment_if_needed() {
  local output_array="$1"
  local product="$2"
  local output_dir="$3"
  local reference_window_width="$4"
  local reference_window_height="$5"
  local hide_window_menubar_label="$6"

  if quillui_is_quill_chat_mac_reference_product "$product"; then
    local reference_home="$output_dir/quill-chat-linux-reference-home"
    quillui_append_quill_chat_reference_environment \
      "$output_array" \
      "$reference_home" \
      "$reference_window_width" \
      "$reference_window_height" \
      "$hide_window_menubar_label" || return $?
  fi
}

quillui_append_quill_chat_profile_fixture_environment_if_needed() {
  local output_array="$1"
  local product="$2"
  local output_dir="$3"

  if [[ "$product" != "quill-chat-linux" ]]; then
    return 0
  fi
  if quillui_is_quill_chat_mac_reference_product "$product"; then
    return 0
  fi

  local profile_home="$output_dir/quill-chat-linux-profile-home"
  quillui_append_quill_chat_fixture_data_environment "$output_array" "$profile_home" || return $?
}

quillui_append_backend_runtime_environment() {
  local output_array="$1"
  local product="$2"
  local display="${3:-}"
  local output_dir="$4"
  local reference_window_width="$5"
  local reference_window_height="$6"
  local hide_window_menubar_label="$7"
  local requested_backend="${8:-}"

  quillui_append_backend_launch_environment "$output_array" "$product" "$display" "$requested_backend" || return $?
  quillui_append_backend_layout_debug_environment "$output_array" "${QUILLUI_BACKEND_LAYOUT_DEBUG:-}" || return $?
  quillui_append_quill_chat_reference_environment_if_needed \
    "$output_array" \
    "$product" \
    "$output_dir" \
    "$reference_window_width" \
    "$reference_window_height" \
    "$hide_window_menubar_label" || return $?
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
    qt6-base-dev
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
    quillui_assign_output "$output_var" "$QUILLUI_BACKEND_APP_EXECUTABLE" || return $?
    return
  fi

  if [[ "$product" == "quill-chat-linux" ]]; then
    local quill_chat_app_dir="${QUILL_CHAT_DIR:-$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/../quill/clients/quill-chat}/Enchanted"
    local quill_chat_backend_facade
    local quill_chat_default_work_root="$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build/quill-chat-linux"
    local quill_chat_work_root

    quill_chat_backend_facade="$(quillui_generated_app_backend_facade)" || return $?
    if [[ -n "$quill_chat_backend_facade" ]]; then
      quill_chat_default_work_root="$quill_chat_default_work_root-$quill_chat_backend_facade"
    fi
    quill_chat_work_root="${QUILLUI_QUILL_CHAT_BUILD_WORKDIR:-$quill_chat_default_work_root}"

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
      quillui_assign_output "$output_var" "$cached_executable" || return $?
      return
    fi

    QUILLUI_QUILL_CHAT_BUILD_WORKDIR="$quill_chat_work_root" \
      QUILLUI_QUILL_CHAT_PRODUCT_NAME="$product" \
      QUILLUI_QUILL_CHAT_BACKEND_FACADE="$quill_chat_backend_facade" \
      "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/build-quill-chat-linux.sh"

    local quill_chat_bin_path
    quill_chat_bin_path="$(swift build \
      --package-path "$quill_chat_work_root/package" \
      --scratch-path "$quill_chat_work_root/.build-check" \
      --show-bin-path)"
    quillui_assign_output "$output_var" "$quill_chat_bin_path/$product" || return $?
  else
    local linux_build_backend
    linux_build_backend="$(quillui_require_backend_for_product "$product")" || return $?

    if [[ "${QUILLUI_BACKEND_SKIP_BUILD:-0}" == "1" ]]; then
      local cached_executable
      cached_executable="$(
        find "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" -path "*/debug/$product" -type f -perm -111 2>/dev/null | head -n 1 || true
      )"
      if [[ -z "$cached_executable" ]]; then
        echo "No cached executable found for $product under $QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" >&2
        exit 66
      fi
      quillui_assign_output "$output_var" "$cached_executable" || return $?
    else
      "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux"
      QUILLUI_LINUX_BACKEND="$linux_build_backend" \
        swift build --scratch-path "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" --product "$product"
      local bin_path
      bin_path="$(
        QUILLUI_LINUX_BACKEND="$linux_build_backend" \
          swift build --scratch-path "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" --show-bin-path
      )"
      quillui_assign_output "$output_var" "$bin_path/$product" || return $?
    fi
  fi
}

quillui_seed_quill_chat_reference_data() {
  local qa_home="$1"
  rm -rf "$qa_home"
  python3 "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/seed-quill-chat-reference-data.py" "$qa_home"
}
