#!/usr/bin/env bash

QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
)"

source "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-backend-products.sh"
source "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/quillui-enchanted-source.sh"

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
  local product="${2:-}"

  if [[ -z "$requested_backend" && -n "$product" ]]; then
    requested_backend="$(quillui_require_requested_backend_for_product "$product")" || return $?
  elif [[ -n "$requested_backend" && -n "$product" ]]; then
    requested_backend="$(quillui_validate_requested_backend_for_product "$product" "$requested_backend")" || return $?
  elif [[ -n "$requested_backend" ]]; then
    requested_backend="$(quillui_require_backend_identifier "$requested_backend")" || return $?
  fi

  if [[ -n "$requested_backend" ]]; then
    QUILLUI_BACKEND="$requested_backend"
    export QUILLUI_BACKEND
  fi
}

quillui_alias_backend_build_env() {
  quillui_alias_env QUILLUI_BACKEND_APP_EXECUTABLE QUILLUI_GTK_APP_EXECUTABLE QUILLUI_QT_APP_EXECUTABLE
  quillui_alias_env QUILLUI_BACKEND_SKIP_BUILD QUILLUI_GTK_SKIP_BUILD QUILLUI_QT_SKIP_BUILD
}

quillui_generated_app_backend_facade() {
  local candidate="${QUILLUI_ENCHANTED_BACKEND_FACADE:-${QUILLUI_QUILL_CHAT_BACKEND_FACADE:-${QUILLUI_APP_BACKEND_FACADE:-}}}"

  if [[ -z "$candidate" && -n "${QUILLUI_BACKEND:-}" ]]; then
    candidate="$QUILLUI_BACKEND"
  fi

  if [[ -n "$candidate" ]]; then
    quillui_require_backend_identifier "$candidate" || return $?
  fi

  return 0
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
  local selected_backend=""

  if quillui_is_quill_chat_mac_reference_product "$product"; then
    verify_product="quill-chat-linux-mac-reference"
  elif quillui_is_enchanted_mac_reference_product "$product"; then
    verify_product="quill-enchanted-mac-reference"
  else
    selected_backend="$(quillui_require_requested_backend_for_product "$product" 2>/dev/null || true)"
    if [[ -n "$selected_backend" ]]; then
      verify_product="$(quillui_backend_visual_verify_product_for_product "$product" "$selected_backend")" || return $?
    fi
  fi
  if [[ -n "${QUILLUI_BACKEND_VERIFY_PRODUCT:-}" ]]; then
    verify_product="$QUILLUI_BACKEND_VERIFY_PRODUCT"
  fi

  quillui_assign_output "$output_var" "$verify_product"
}

quillui_backend_list_selection_verify_product() {
  local product="$1"
  local selected_backend="$2"
  local verify_product=""

  if [[ "$product" == "quill-enchanted" ]]; then
    if [[ "$selected_backend" == "qt" ]]; then
      verify_product="quill-enchanted-qt-list-selection"
    else
      verify_product="quill-enchanted-list-selection"
    fi
  elif [[ "$selected_backend" == "gtk" ]] && quillui_is_backend_chat_gtk_list_selection_app_product "$product"; then
    verify_product="$product-list-selection"
  elif [[ "$selected_backend" == "gtk" ]] && quillui_is_backend_generic_gtk_list_selection_app_product "$product"; then
    verify_product="$product-gtk-list-selection"
  elif [[ "$selected_backend" == "qt" ]] && quillui_is_backend_generic_qt_app_product "$product"; then
    verify_product="$product-qt-list-selection"
  fi

  if [[ -z "$verify_product" ]]; then
    return 1
  fi

  printf '%s\n' "$verify_product"
}

quillui_backend_interaction_verify_product() {
  local product="$1"
  local interaction_mode="$2"
  local output_var="$3"
  local verify_product="$product"
  local app_verify_product=""
  local list_selection_verify_product=""
  local selected_backend=""

  selected_backend="$(quillui_require_requested_backend_for_product "$product" 2>/dev/null || true)"

  if app_verify_product="$(quillui_backend_app_interaction_verify_product_for_product "$product" "$selected_backend" "$interaction_mode")"; then
    verify_product="$app_verify_product"
  elif [[ "$interaction_mode" == "list-selection" ]] && list_selection_verify_product="$(quillui_backend_list_selection_verify_product "$product" "$selected_backend")"; then
    verify_product="$list_selection_verify_product"
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

quillui_backend_scoped_app_environment_names() {
  printf '%s\n' \
    QUILLUI_GTK_APP_EXECUTABLE QUILLUI_QT_APP_EXECUTABLE \
    QUILLUI_GTK_SKIP_BUILD QUILLUI_QT_SKIP_BUILD \
    QUILLUI_GTK_MAC_REFERENCE QUILLUI_QT_MAC_REFERENCE \
    QUILLUI_GTK_DEFAULT_WINDOW_WIDTH QUILLUI_QT_DEFAULT_WINDOW_WIDTH \
    QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT QUILLUI_QT_DEFAULT_WINDOW_HEIGHT \
    QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL QUILLUI_QT_HIDE_WINDOW_MENUBAR_LABEL \
    QUILLUI_GTK_LAYOUT_DEBUG QUILLUI_QT_LAYOUT_DEBUG \
    QUILLUI_GTK_VERIFY_PRODUCT QUILLUI_QT_VERIFY_PRODUCT \
    QUILLUI_GTK_VISUAL_DISPLAY QUILLUI_QT_VISUAL_DISPLAY \
    QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE \
    QUILLUI_GTK_VISUAL_SCREEN_SIZE QUILLUI_QT_VISUAL_SCREEN_SIZE \
    QUILLUI_GTK_INTERACTION_MODE QUILLUI_QT_INTERACTION_MODE \
    QUILLUI_GTK_INTERACTION_DISPLAY QUILLUI_QT_INTERACTION_DISPLAY \
    QUILLUI_GTK_INTERACTION_SCREEN_SIZE QUILLUI_QT_INTERACTION_SCREEN_SIZE \
    QUILLUI_GTK_CAPTURE_ROOT QUILLUI_QT_CAPTURE_ROOT \
    QUILLUI_GTK_POST_CLICK_SLEEP QUILLUI_QT_POST_CLICK_SLEEP \
    QUILLUI_GTK_FOCUS_PRIME QUILLUI_QT_FOCUS_PRIME \
    QUILLUI_GTK_FOCUS_PRIME_X QUILLUI_QT_FOCUS_PRIME_X \
    QUILLUI_GTK_FOCUS_PRIME_Y QUILLUI_QT_FOCUS_PRIME_Y \
    QUILLUI_GTK_FOCUS_PRIME_SLEEP QUILLUI_QT_FOCUS_PRIME_SLEEP \
    QUILLUI_GTK_CLICK_X QUILLUI_QT_CLICK_X \
    QUILLUI_GTK_CLICK_Y QUILLUI_QT_CLICK_Y \
    QUILLUI_GTK_SETTINGS_CLICK_X QUILLUI_QT_SETTINGS_CLICK_X \
    QUILLUI_GTK_SETTINGS_CLICK_Y QUILLUI_QT_SETTINGS_CLICK_Y \
    QUILLUI_GTK_ENDPOINT_CLICK_X QUILLUI_QT_ENDPOINT_CLICK_X \
    QUILLUI_GTK_ENDPOINT_CLICK_Y QUILLUI_QT_ENDPOINT_CLICK_Y \
    QUILLUI_GTK_IMPORT_CLICK_X QUILLUI_QT_IMPORT_CLICK_X \
    QUILLUI_GTK_IMPORT_CLICK_Y QUILLUI_QT_IMPORT_CLICK_Y \
    QUILLUI_GTK_IMPORT_EDITOR_X QUILLUI_QT_IMPORT_EDITOR_X \
    QUILLUI_GTK_IMPORT_EDITOR_Y QUILLUI_QT_IMPORT_EDITOR_Y \
    QUILLUI_GTK_IMPORT_CONFIGURATION QUILLUI_QT_IMPORT_CONFIGURATION \
    QUILLUI_GTK_MALFORMED_IMPORT_CONFIGURATION QUILLUI_QT_MALFORMED_IMPORT_CONFIGURATION \
    QUILLUI_GTK_IMPORT_CONFIGURATION_FILE QUILLUI_QT_IMPORT_CONFIGURATION_FILE \
    QUILLUI_GTK_MALFORMED_IMPORT_CONFIGURATION_FILE QUILLUI_QT_MALFORMED_IMPORT_CONFIGURATION_FILE \
    QUILLUI_GTK_TYPE_TEXT QUILLUI_QT_TYPE_TEXT \
    QUILLUI_GTK_GENERIC_SELECTED_INDEX_ON_START QUILLUI_QT_GENERIC_SELECTED_INDEX_ON_START \
    QUILLUI_GTK_CODEEDIT_SELECTED_FILE_INDEX_ON_START QUILLUI_QT_CODEEDIT_SELECTED_FILE_INDEX_ON_START \
    QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_QT_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START \
    QUILLUI_GTK_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START QUILLUI_QT_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START \
    QUILLUI_GTK_IINA_SELECTED_PLAYLIST_INDEX_ON_START QUILLUI_QT_IINA_SELECTED_PLAYLIST_INDEX_ON_START \
    QUILLUI_GTK_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START QUILLUI_QT_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START \
    QUILLUI_GTK_CHAT_SELECTED_THREAD_INDEX_ON_START QUILLUI_QT_CHAT_SELECTED_THREAD_INDEX_ON_START \
    QUILLUI_GTK_SIGNAL_SELECTED_THREAD_INDEX_ON_START QUILLUI_QT_SIGNAL_SELECTED_THREAD_INDEX_ON_START \
    QUILLUI_GTK_TELEGRAM_SELECTED_THREAD_INDEX_ON_START QUILLUI_QT_TELEGRAM_SELECTED_THREAD_INDEX_ON_START \
    QUILLUI_GTK_PROFILE_COMMAND QUILLUI_QT_PROFILE_COMMAND \
    QUILLUI_GTK_PROFILE_SETTLE QUILLUI_QT_PROFILE_SETTLE \
    QUILLUI_GTK_PROFILE_STEADY QUILLUI_QT_PROFILE_STEADY \
    QUILLUI_GTK_PROFILE_DISPLAY QUILLUI_QT_PROFILE_DISPLAY \
    QUILLUI_GTK_PROFILE_SCREEN_SIZE QUILLUI_QT_PROFILE_SCREEN_SIZE \
    QUILLUI_GTK_PROFILE_MAX_CPU_PCT QUILLUI_QT_PROFILE_MAX_CPU_PCT \
    QUILLUI_GTK_PROFILE_MAX_RSS_KB QUILLUI_QT_PROFILE_MAX_RSS_KB \
    QUILLUI_GTK_PROFILE_MAX_STARTUP_MS QUILLUI_QT_PROFILE_MAX_STARTUP_MS
}

quillui_unset_backend_scoped_app_environment() {
  local variable

  while IFS= read -r variable; do
    [[ -n "$variable" ]] || continue
    unset "$variable"
  done < <(quillui_backend_scoped_app_environment_names)
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

quillui_print_backend_app_log_tail() {
  local log_path="${1:-}"
  local line_count="${2:-80}"

  if [[ -z "$log_path" || ! -s "$log_path" ]]; then
    return 0
  fi
  case "$line_count" in
    ''|*[!0-9]*) line_count=80 ;;
  esac

  echo "Backend app log ($log_path):" >&2
  tail -n "$line_count" "$log_path" >&2 || true
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
    requested_backend="$(quillui_validate_requested_backend_for_product "$product" "$requested_backend")" || return $?
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
}

quillui_append_enchanted_reference_mode_environment() {
  local output_array="$1"

  quillui_append_environment_assignment "$output_array" "QUILLUI_ENCHANTED_REFERENCE_MODE=1" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QUILL_CHAT_REFERENCE_MODE=1" || return $?
}

quillui_append_enchanted_profile_mode_environment() {
  local output_array="$1"

  quillui_append_environment_assignment "$output_array" "QUILLUI_ENCHANTED_PROFILE_MODE=1" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QUILL_CHAT_PROFILE_MODE=1" || return $?
}

quillui_append_enchanted_unreachable_environment() {
  local output_array="$1"

  quillui_append_environment_assignment "$output_array" "QUILLUI_ENCHANTED_FORCE_UNREACHABLE=1" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_QUILL_CHAT_FORCE_UNREACHABLE=1" || return $?
}

quillui_append_quill_chat_fixture_data_environment() {
  local output_array="$1"
  local fixture_home="$2"

  quillui_append_enchanted_fixture_data_environment "$output_array" "$fixture_home" || return $?
  quillui_append_enchanted_reference_mode_environment "$output_array" || return $?
}

quillui_seed_enchanted_reference_data() {
  local fixture_home="$1"

  rm -rf "$fixture_home"
  python3 "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/seed-enchanted-reference-data.py" "$fixture_home"
}

quillui_append_enchanted_fixture_data_environment() {
  local output_array="$1"
  local fixture_home="$2"

  quillui_seed_enchanted_reference_data "$fixture_home" || return $?
  quillui_append_environment_assignment "$output_array" "HOME=$fixture_home" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLDATA_HOME=$fixture_home" || return $?
}

quillui_append_quill_chat_reference_environment() {
  local output_array="$1"
  local reference_home="$2"
  local reference_window_width="$3"
  local reference_window_height="$4"
  local hide_window_menubar_label="$5"

  quillui_append_quill_chat_fixture_data_environment "$output_array" "$reference_home" || return $?
  quillui_append_enchanted_unreachable_environment "$output_array" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH=$reference_window_width" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT=$reference_window_height" || return $?
  quillui_append_environment_assignment "$output_array" "QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL=$hide_window_menubar_label" || return $?
}

quillui_append_quill_chat_reference_environment_if_needed() {
  local output_array="$1"
  local product="$2"
  local output_dir="$3"
  local reference_window_width="$4"
  local reference_window_height="$5"
  local hide_window_menubar_label="$6"

  # The macOS-reference product AND the generated Enchanted product
  # (quill-enchanted-linux, the only generated app product) both need a
  # deterministic render: seeded fixtures + FORCE_UNREACHABLE (so the app does
  # NOT reach for a live Ollama endpoint, which floods NSURLErrorDomain -1004
  # and leaves the sidebar empty) + the fixed reference window. Without this the
  # generated visual smoke launched live and failed "Enchanted sidebar not
  # detected".
  if quillui_is_quill_chat_mac_reference_product "$product" \
    || quillui_is_backend_generated_app_product "$product"; then
    local reference_home="$output_dir/$product-reference-home"
    quillui_append_quill_chat_reference_environment \
      "$output_array" \
      "$reference_home" \
      "$reference_window_width" \
      "$reference_window_height" \
      "$hide_window_menubar_label" || return $?
  fi
}

quillui_append_backend_fixture_runtime_environment_if_needed() {
  local output_array="$1"
  local product="$2"

  case "$product" in
    quill-icecubes|quill-netnewswire)
      quillui_append_environment_assignment "$output_array" "QUILLUI_DISABLE_FETCH=1" || return $?
      ;;
  esac
}

quillui_is_generated_enchanted_linux_product() {
  case "$1" in
    quill-enchanted-linux|quill-chat-linux)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

quillui_append_enchanted_profile_fixture_environment_if_needed() {
  local output_array="$1"
  local product="$2"
  local output_dir="$3"

  if ! quillui_is_generated_enchanted_linux_product "$product"; then
    return 0
  fi
  if quillui_is_quill_chat_mac_reference_product "$product"; then
    return 0
  fi

  local profile_home="$output_dir/$product-profile-home"
  quillui_append_enchanted_fixture_data_environment "$output_array" "$profile_home" || return $?
  quillui_append_enchanted_reference_mode_environment "$output_array" || return $?
  quillui_append_enchanted_profile_mode_environment "$output_array" || return $?
}

quillui_append_quill_chat_profile_fixture_environment_if_needed() {
  quillui_append_enchanted_profile_fixture_environment_if_needed "$@"
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
  quillui_append_backend_fixture_runtime_environment_if_needed "$output_array" "$product" || return $?
  quillui_append_quill_chat_reference_environment_if_needed \
    "$output_array" \
    "$product" \
    "$output_dir" \
    "$reference_window_width" \
    "$reference_window_height" \
    "$hide_window_menubar_label" || return $?
  quillui_unset_backend_scoped_app_environment
}

quillui_backend_generic_selection_environment_keys() {
  case "$1" in
    quill-codeedit)
      printf '%s\n' QUILLUI_CODEEDIT_SELECTED_FILE_INDEX_ON_START
      ;;
    quill-enchanted-upstream-slice)
      printf '%s\n' QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START
      printf '%s\n' QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START
      ;;
    quill-icecubes)
      printf '%s\n' QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START
      ;;
    quill-iina)
      printf '%s\n' QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START
      ;;
    quill-netnewswire)
      printf '%s\n' QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START
      ;;
    quill-signal)
      printf '%s\n' QUILLUI_SIGNAL_SELECTED_THREAD_INDEX_ON_START
      quillui_backend_chat_shared_selection_environment_key
      ;;
    quill-telegram)
      printf '%s\n' QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START
      quillui_backend_chat_shared_selection_environment_key
      ;;
  esac
}

quillui_backend_chat_shared_selection_environment_key() {
  printf '%s\n' QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START
}

quillui_backend_selected_index_from_environment_keys() {
  local environment_key

  for environment_key in "$@"; do
    if [[ -n "${!environment_key:-}" ]]; then
      printf '%s\n' "${!environment_key}"
      return 0
    fi
  done

  printf '%s\n' "${QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START:-0}"
}

quillui_backend_generic_selected_index_on_start() {
  local product="$1"
  local environment_key
  local environment_keys=()

  while IFS= read -r environment_key; do
    [[ -n "$environment_key" ]] || continue
    environment_keys+=("$environment_key")
  done < <(quillui_backend_generic_selection_environment_keys "$product")

  quillui_backend_selected_index_from_environment_keys "${environment_keys[@]}"
}

quillui_backend_generic_gtk_selection_environment_key() {
  local product="$1"
  local environment_key

  if ! quillui_is_backend_generic_gtk_list_selection_app_product "$product"; then
    echo "Unsupported generic GTK list-selection product: $product" >&2
    return 65
  fi

  while IFS= read -r environment_key; do
    [[ -n "$environment_key" ]] || continue
    printf '%s\n' "$environment_key"
    return 0
  done < <(quillui_backend_generic_selection_environment_keys "$product")

  echo "Missing generic GTK list-selection environment key: $product" >&2
  return 65
}

quillui_backend_chat_gtk_selection_environment_key() {
  local product="$1"
  local environment_key
  local shared_environment_key

  if ! quillui_is_backend_chat_gtk_list_selection_app_product "$product"; then
    echo "Unsupported ChatKit GTK list-selection product: $product" >&2
    return 65
  fi

  shared_environment_key="$(quillui_backend_chat_shared_selection_environment_key)" || return $?
  while IFS= read -r environment_key; do
    [[ -n "$environment_key" ]] || continue
    if [[ "$environment_key" == "$shared_environment_key" ]]; then
      continue
    fi
    printf '%s\n' "$environment_key"
    return 0
  done < <(quillui_backend_generic_selection_environment_keys "$product")

  echo "Missing ChatKit GTK selection environment key for product: $product" >&2
  return 66
}

quillui_backend_chat_gtk_selected_index_on_start() {
  local product="$1"
  local environment_key
  local shared_environment_key

  environment_key="$(quillui_backend_chat_gtk_selection_environment_key "$product")" || return $?
  if [[ -n "${!environment_key:-}" ]]; then
    printf '%s\n' "${!environment_key}"
  else
    shared_environment_key="$(quillui_backend_chat_shared_selection_environment_key)" || return $?
    printf '%s\n' "${!shared_environment_key:-1}"
  fi
}

quillui_backend_generic_qt_selected_index_on_start() {
  quillui_backend_generic_selected_index_on_start "$1"
}

quillui_backend_list_selection_start_environment_assignment() {
  local product="$1"
  local selected_backend="$2"
  local environment_key
  local selected_index

  selected_backend="$(quillui_require_backend_identifier "$selected_backend")" || return $?

  if [[ "$selected_backend" == "qt" ]] && quillui_is_backend_generic_qt_app_product "$product"; then
    selected_index="$(quillui_backend_generic_qt_selected_index_on_start "$product")" || return $?
    printf '%s\n' "QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START=$selected_index"
  elif [[ "$selected_backend" == "gtk" ]] && quillui_is_backend_generic_gtk_list_selection_app_product "$product"; then
    selected_index="$(quillui_backend_generic_selected_index_on_start "$product")" || return $?
    environment_key="$(quillui_backend_generic_gtk_selection_environment_key "$product")" || return $?
    printf '%s\n' "$environment_key=$selected_index"
  elif [[ "$product" == "quill-enchanted" ]]; then
    printf '%s\n' "QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START=${QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START:-${QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START:-0}}"
  elif [[ "$selected_backend" == "gtk" ]] && quillui_is_backend_chat_gtk_list_selection_app_product "$product"; then
    selected_index="$(quillui_backend_chat_gtk_selected_index_on_start "$product")" || return $?
    environment_key="$(quillui_backend_chat_gtk_selection_environment_key "$product")" || return $?
    printf '%s\n' "$environment_key=$selected_index"
  else
    return 1
  fi
}

quillui_append_backend_selection_start_environment() {
  local output_array="$1"
  local product="$2"
  local selected_backend="$3"
  local interaction_mode="$4"
  local output_dir="${5:-${QUILLUI_BACKEND_SELECTION_OUTPUT_DIR:-$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.qa}}"
  local selection_assignment

  selected_backend="$(quillui_require_backend_identifier "$selected_backend")" || return $?
  if [[ "$interaction_mode" != "list-selection" ]]; then
    return 0
  fi

  if [[ "$product" == "quill-enchanted" && "$selected_backend" == "gtk" ]]; then
    quillui_append_enchanted_fixture_data_environment \
      "$output_array" \
      "$output_dir/quill-enchanted-reference-home" || return $?
  fi

  if selection_assignment="$(quillui_backend_list_selection_start_environment_assignment "$product" "$selected_backend")"; then
    quillui_append_environment_assignment \
      "$output_array" \
      "$selection_assignment" || return $?
  fi

  return 0
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

  if [[ "$product" == "quill-enchanted-linux" || "$product" == "quill-chat-linux" ]]; then
    local enchanted_app_dir
    local enchanted_backend_facade
    local enchanted_default_work_root="$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build/$product"
    local enchanted_work_root

    enchanted_app_dir="$(quillui_resolve_enchanted_source_dir "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR")"
    enchanted_backend_facade="$(quillui_generated_app_backend_facade)" || return $?
    if [[ -n "$enchanted_backend_facade" ]]; then
      enchanted_default_work_root="$enchanted_default_work_root-$enchanted_backend_facade"
    fi
    enchanted_work_root="${QUILLUI_ENCHANTED_BUILD_WORKDIR:-${QUILLUI_QUILL_CHAT_BUILD_WORKDIR:-$enchanted_default_work_root}}"

    if [[ ! -d "$enchanted_app_dir" ]]; then
      quillui_print_enchanted_source_missing "$enchanted_app_dir"
      exit 66
    fi

    if [[ "${QUILLUI_BACKEND_SKIP_BUILD:-0}" == "1" ]]; then
      local cached_executable
      cached_executable="$(
        find "$enchanted_work_root/.build-check" -path "*/debug/$product" -type f -perm -111 2>/dev/null | head -n 1 || true
      )"
      if [[ -z "$cached_executable" ]]; then
        echo "No cached executable found for $product under $enchanted_work_root/.build-check" >&2
        exit 66
      fi
      quillui_assign_output "$output_var" "$cached_executable" || return $?
      return
    fi

    QUILLUI_ENCHANTED_BUILD_WORKDIR="$enchanted_work_root" \
      QUILLUI_ENCHANTED_PRODUCT_NAME="$product" \
      QUILLUI_ENCHANTED_BACKEND_FACADE="$enchanted_backend_facade" \
      "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/build-enchanted-linux.sh"

    local enchanted_bin_path
    if [[ "$enchanted_backend_facade" == "qt" ]]; then
      enchanted_bin_path="$(QUILLUI_LINUX_BACKEND=qt "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
        --package-path "$enchanted_work_root/package" \
        --scratch-path "$enchanted_work_root/.build-check" \
        --show-bin-path)"
    else
      enchanted_bin_path="$(swift build \
        --package-path "$enchanted_work_root/package" \
        --scratch-path "$enchanted_work_root/.build-check" \
        --show-bin-path)"
    fi
    quillui_assign_output "$output_var" "$enchanted_bin_path/$product" || return $?
  else
    local linux_build_backend
    linux_build_backend="$(quillui_require_requested_backend_for_product "$product")" || return $?

    if [[ "${QUILLUI_BACKEND_SKIP_BUILD:-0}" == "1" ]]; then
      local cached_executable
      quillui_require_backend_product_build_stamp \
        "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" \
        "$product" \
        "$linux_build_backend" || return $?
      cached_executable="$(
        find "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" -path "*/debug/$product" -type f -perm -111 2>/dev/null | head -n 1 || true
      )"
      if [[ -z "$cached_executable" ]]; then
        echo "No cached executable found for $product under $QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" >&2
        exit 66
      fi
      quillui_assign_output "$output_var" "$cached_executable" || return $?
    else
      "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/prepare-linux-build-backend.sh" \
        --backend "$linux_build_backend" \
        --scratch-path "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux"
      QUILLUI_LINUX_BACKEND="$linux_build_backend" \
        "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
        swift build --scratch-path "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" --product "$product"
      quillui_record_backend_product_build \
        "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/.build-linux" \
        "$product" \
        "$linux_build_backend" || return $?
      local bin_path
      bin_path="$(
        QUILLUI_LINUX_BACKEND="$linux_build_backend" \
          "$QUILLUI_LINUX_BACKEND_SMOKE_ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
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
