#!/usr/bin/env bash

QUILLUI_BACKEND_APP_BACKEND_IDS=(gtk qt)

quillui_backend_app_products() {
  # Canonical user-facing Quill app executable products covered by the Linux
  # backend parity loops. Support tools, generated external packages, smoke
  # fixtures, and demos stay out of this roster.
  printf '%s\n' \
    quill-enchanted \
    quill-enchanted-upstream-slice \
    quill-icecubes \
    quill-netnewswire \
    quill-codeedit \
    quill-signal \
    quill-telegram \
    quill-iina \
    quill-wireguard \
    quill-wireguard-qt
}

quillui_gtk_app_products() {
  # Legacy GTK-named entry point kept for older scripts. The backend app roster
  # is the source of truth because app binaries select GTK/Qt through
  # QUILLUI_BACKEND.
  quillui_backend_app_products
}

quillui_backend_app_backends() {
  # Backends each user-facing app must be able to request in parity smoke
  # loops. Backend-specific entry points narrow this set below so a product
  # never compiles or profiles through two mutually exclusive Linux host paths.
  printf '%s\n' "${QUILLUI_BACKEND_APP_BACKEND_IDS[@]}"
}

quillui_backend_fixed_app_backend_overrides() {
  # PRODUCT<TAB>BACKEND rows for app products whose SwiftPM target links one
  # native host stack at manifest time.
  printf '%s\t%s\n' \
    quill-wireguard gtk \
    quill-wireguard-qt qt
}

quillui_backend_fixed_backend_for_app_product() {
  local product="$1"
  local override_product
  local override_backend

  while IFS=$'\t' read -r override_product override_backend; do
    [[ -n "$override_product" ]] || continue
    override_backend="$(quillui_require_linux_build_backend_identifier "$override_backend")" || return $?
    if [[ "$product" == "$override_product" ]]; then
      echo "$override_backend"
      return 0
    fi
  done < <(quillui_backend_fixed_app_backend_overrides)

  return 1
}

quillui_backend_app_backends_for_product() {
  local fixed_backend

  if fixed_backend="$(quillui_backend_fixed_backend_for_app_product "$1")"; then
    echo "$fixed_backend"
  else
    quillui_backend_app_backends
  fi
}

quillui_backend_native_runtime_backends() {
  # Mirrors QuillBackendRegistry on Linux. Keep this as a registry instead of
  # branching in call sites so adding the native Qt host is a one-line change.
  printf '%s\n' \
    gtk
}

quillui_backend_native_product_runtime_overrides() {
  # PRODUCT<TAB>REQUESTED_BACKEND<TAB>RUNTIME_BACKEND rows for native hosts that
  # exist only behind a product-specific SwiftPM graph today.
  printf '%s\t%s\t%s\n' \
    quill-wireguard-qt qt qt
}

quillui_backend_native_runtime_backend_for_product() {
  local product="$1"
  local requested_backend
  local override_product
  local override_requested_backend
  local override_runtime_backend

  requested_backend="$(quillui_require_backend_identifier "$2")" || return $?
  while IFS=$'\t' read -r override_product override_requested_backend override_runtime_backend; do
    [[ -n "$override_product" ]] || continue
    override_requested_backend="$(quillui_require_backend_identifier "$override_requested_backend")" || return $?
    override_runtime_backend="$(quillui_require_backend_identifier "$override_runtime_backend")" || return $?
    if [[ "$product" == "$override_product" && "$requested_backend" == "$override_requested_backend" ]]; then
      echo "$override_runtime_backend"
      return 0
    fi
  done < <(quillui_backend_native_product_runtime_overrides)

  return 1
}

quillui_platform_runtime_fallback_backend() {
  local backend

  while IFS= read -r backend; do
    [[ -n "$backend" ]] || continue
    quillui_require_backend_identifier "$backend"
    return 0
  done < <(quillui_backend_native_runtime_backends)

  echo "No QuillUI platform runtime fallback backend configured." >&2
  return 70
}

quillui_backend_emit_matrix_for_product_rows() {
  local product_rows="$1"
  local product
  local backend
  local fixed_backend

  while IFS= read -r product || [[ -n "$product" ]]; do
    [[ -n "$product" ]] || continue
    if fixed_backend="$(quillui_backend_fixed_backend_for_app_product "$product")"; then
      printf '%s\t%s\n' "$product" "$fixed_backend"
    else
      for backend in "${QUILLUI_BACKEND_APP_BACKEND_IDS[@]}"; do
        [[ -n "$backend" ]] || continue
        printf '%s\t%s\n' "$product" "$backend"
      done
    fi
  done <<< "$product_rows"
}

quillui_backend_matrix_for_products() {
  local product_rows

  product_rows="$(cat)" || return $?
  quillui_backend_emit_matrix_for_product_rows "$product_rows"
}

quillui_backend_app_matrix() {
  local product_rows

  product_rows="$(quillui_backend_app_products)" || return $?
  quillui_backend_emit_matrix_for_product_rows "$product_rows"
}

quillui_normalize_backend_identifier() {
  # Keep shell tooling aligned with QuillBackendIdentifier(environmentValue:).
  local raw_value="${1:-}"
  local normalized

  normalized="$(
    printf '%s' "$raw_value" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
  )"

  case "$normalized" in
    swiftui|swift-ui|apple|native)
      echo "swiftui"
      ;;
    gtk|gtk4)
      echo "gtk"
      ;;
    qt|qt6)
      echo "qt"
      ;;
    *)
      return 1
      ;;
  esac
}

quillui_require_backend_identifier() {
  local raw_value="${1:-}"
  local normalized_backend

  normalized_backend="$(quillui_normalize_backend_identifier "$raw_value")" || {
    echo "Unsupported QuillUI backend: $raw_value" >&2
    return 64
  }
  echo "$normalized_backend"
}

quillui_require_linux_build_backend_identifier() {
  local raw_value="${1:-}"
  local normalized_backend

  normalized_backend="$(quillui_require_backend_identifier "$raw_value")" || return $?
  case "$normalized_backend" in
    gtk|qt)
      echo "$normalized_backend"
      ;;
    *)
      echo "Unsupported QuillUI Linux build backend: $raw_value; expected gtk or qt." >&2
      return 64
      ;;
  esac
}

quillui_backend_interaction_app_products() {
  # Root app interaction smokes intentionally share the same app roster as
  # visual/profile parity checks. Keep the function separate so interaction
  # coverage can grow without changing CI call sites.
  quillui_backend_app_products
}

quillui_backend_interaction_app_matrix() {
  local product_rows

  product_rows="$(quillui_backend_interaction_app_products)" || return $?
  quillui_backend_emit_matrix_for_product_rows "$product_rows"
}

quillui_backend_generated_app_products() {
  # Generated external app products are not built from this package manifest,
  # but they still need the same requested-backend parity coverage once
  # assembled into their temporary SwiftPM packages.
  printf '%s\n' \
    quill-chat-linux
}

quillui_backend_generated_app_matrix() {
  local product_rows

  product_rows="$(quillui_backend_generated_app_products)" || return $?
  quillui_backend_emit_matrix_for_product_rows "$product_rows"
}

quillui_backend_smoke_products() {
  # Minimal backend launch fixtures shared by visual and interaction
  # smoke checks. These are intentionally separate from user-facing
  # app products so GTK/Qt backend parity can advance without changing
  # the full app matrix.
  printf '%s\n' \
    quill-gtk-interaction-smoke \
    quill-qt-interaction-smoke
}

quillui_backend_smoke_matrix() {
  local product
  local backend

  while IFS= read -r product; do
    [[ -n "$product" ]] || continue
    backend="$(quillui_require_backend_for_product "$product")"
    [[ -n "$backend" ]] || continue
    printf '%s\t%s\n' "$product" "$backend"
  done < <(quillui_backend_smoke_products)
}

quillui_backend_smoke_interaction_modes() {
  # Launch fixture interaction modes exercise the shared backend surface:
  # root button, nested buttons, and sheet presentations. Keep this list in
  # one place so GTK and Qt fixture coverage cannot drift.
  printf '%s\n' \
    open-panel \
    sidebar-button \
    banner-button \
    nested-sheet \
    sidebar-sheet \
    banner-sheet
}

quillui_normalize_backend_smoke_interaction_mode() {
  local candidate="$1"
  local mode

  case "$candidate" in
    click)
      echo "open-panel"
      return 0
      ;;
  esac

  while IFS= read -r mode; do
    if [[ "$candidate" == "$mode" ]]; then
      echo "$mode"
      return 0
    fi
  done < <(quillui_backend_smoke_interaction_modes)

  echo "Unsupported backend smoke interaction mode: $candidate" >&2
  return 64
}

quillui_backend_smoke_interaction_verify_product() {
  local product="$1"
  local mode

  mode="$(quillui_normalize_backend_smoke_interaction_mode "$2")" || return $?
  case "$mode" in
    nested-sheet|sidebar-sheet|banner-sheet)
      printf '%s-sheet\n' "$product"
      ;;
    sidebar-button)
      printf '%s-sidebar\n' "$product"
      ;;
    banner-button)
      printf '%s-banner\n' "$product"
      ;;
    open-panel)
      printf '%s-open\n' "$product"
      ;;
  esac
}

quillui_backend_smoke_interaction_matrix() {
  local product
  local backend
  local mode

  while IFS= read -r product; do
    [[ -n "$product" ]] || continue
    backend="$(quillui_require_backend_for_product "$product")"
    [[ -n "$backend" ]] || continue
    while IFS= read -r mode; do
      [[ -n "$mode" ]] || continue
      printf '%s\t%s\t%s\n' "$product" "$backend" "$mode"
    done < <(quillui_backend_smoke_interaction_modes)
  done < <(quillui_backend_smoke_products)
}

quillui_backend_smoke_interaction_verify_matrix() {
  local product
  local backend
  local mode
  local verify_product

  while IFS=$'\t' read -r product backend mode; do
    [[ -n "$product" && -n "$backend" && -n "$mode" ]] || continue
    verify_product="$(quillui_backend_smoke_interaction_verify_product "$product" "$mode")" || return $?
    printf '%s\t%s\t%s\t%s\n' "$product" "$backend" "$mode" "$verify_product"
  done < <(quillui_backend_smoke_interaction_matrix)
}

quillui_backend_profile_products() {
  # Performance budget rows cover production-shaped app shells, generated
  # external apps, and the minimal backend launch fixtures. Keep this as a
  # composed roster so the app, generated-app, and smoke-product matrices
  # remain independently reusable.
  quillui_backend_app_products
  quillui_backend_generated_app_products
  quillui_backend_smoke_products
}

quillui_backend_product_list_contains() {
  local candidate="$1"
  local list_command="$2"
  local product

  while IFS= read -r product; do
    if [[ "$candidate" == "$product" ]]; then
      return 0
    fi
  done < <("$list_command")

  return 1
}

quillui_is_backend_smoke_product() {
  quillui_backend_product_list_contains "$1" quillui_backend_smoke_products
}

quillui_is_backend_generated_app_product() {
  quillui_backend_product_list_contains "$1" quillui_backend_generated_app_products
}

quillui_backend_has_native_runtime() {
  local requested_backend

  requested_backend="$(quillui_require_backend_identifier "$1")" || return $?
  quillui_backend_product_list_contains "$requested_backend" quillui_backend_native_runtime_backends
}

quillui_alias_env() {
  local canonical="$1"
  shift
  local alias
  local backend_prefix=""
  local backend_marker=""
  local selected_backend=""

  if [[ -n "${QUILLUI_BACKEND:-}" ]]; then
    selected_backend="$(quillui_normalize_backend_identifier "$QUILLUI_BACKEND" || true)"
  fi

  case "$selected_backend" in
    gtk)
      backend_prefix="QUILLUI_GTK_"
      backend_marker="_GTK_"
      ;;
    qt)
      backend_prefix="QUILLUI_QT_"
      backend_marker="_QT_"
      ;;
  esac

  if [[ -z "${!canonical:-}" && -n "$backend_prefix" ]]; then
    for alias in "$@"; do
      if [[ ("$alias" == "$backend_prefix"* || "$alias" == *"$backend_marker"*) && -n "${!alias:-}" ]]; then
        printf -v "$canonical" "%s" "${!alias}"
        break
      fi
    done
  fi

  if [[ -z "${!canonical:-}" ]]; then
    for alias in "$@"; do
      if [[ -n "${!alias:-}" ]]; then
        printf -v "$canonical" "%s" "${!alias}"
        break
      fi
    done
  fi

  if [[ -n "${!canonical:-}" ]]; then
    for alias in "$@"; do
      printf -v "$alias" "%s" "${!canonical}"
    done
  fi
}

# Backend-neutral names are canonical for GTK/Qt parity checks. The
# legacy QUILLUI_GTK_* names and scoped QUILLUI_QT_* names stay supported.
# When multiple names are set, the backend-neutral value wins.
quillui_alias_backend_common_env() {
  quillui_alias_env QUILLUI_BACKEND_MAC_REFERENCE QUILLUI_GTK_MAC_REFERENCE QUILLUI_QT_MAC_REFERENCE
  quillui_alias_env QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH QUILLUI_GTK_DEFAULT_WINDOW_WIDTH QUILLUI_QT_DEFAULT_WINDOW_WIDTH
  quillui_alias_env QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT QUILLUI_QT_DEFAULT_WINDOW_HEIGHT
  quillui_alias_env QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL QUILLUI_QT_HIDE_WINDOW_MENUBAR_LABEL
  quillui_alias_env QUILLUI_BACKEND_LAYOUT_DEBUG QUILLUI_GTK_LAYOUT_DEBUG QUILLUI_QT_LAYOUT_DEBUG
  quillui_alias_env QUILLUI_BACKEND_VERIFY_PRODUCT QUILLUI_GTK_VERIFY_PRODUCT QUILLUI_QT_VERIFY_PRODUCT
}

quillui_alias_backend_visual_env() {
  quillui_alias_env QUILLUI_BACKEND_VISUAL_DISPLAY QUILLUI_GTK_VISUAL_DISPLAY QUILLUI_QT_VISUAL_DISPLAY
  quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE QUILLUI_GTK_VISUAL_SCREEN_SIZE QUILLUI_QT_VISUAL_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_VISUAL_SCREEN_SIZE QUILLUI_GTK_VISUAL_SCREEN_SIZE QUILLUI_QT_VISUAL_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE
  quillui_alias_backend_common_env
}

quillui_alias_backend_interaction_env() {
  quillui_alias_env QUILLUI_BACKEND_INTERACTION_MODE QUILLUI_GTK_INTERACTION_MODE QUILLUI_QT_INTERACTION_MODE
  quillui_alias_env QUILLUI_BACKEND_INTERACTION_DISPLAY QUILLUI_GTK_INTERACTION_DISPLAY QUILLUI_QT_INTERACTION_DISPLAY
  quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE QUILLUI_GTK_INTERACTION_SCREEN_SIZE QUILLUI_QT_INTERACTION_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_INTERACTION_SCREEN_SIZE QUILLUI_GTK_INTERACTION_SCREEN_SIZE QUILLUI_QT_INTERACTION_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_CAPTURE_ROOT QUILLUI_GTK_CAPTURE_ROOT QUILLUI_QT_CAPTURE_ROOT
  quillui_alias_env QUILLUI_BACKEND_POST_CLICK_SLEEP QUILLUI_GTK_POST_CLICK_SLEEP QUILLUI_QT_POST_CLICK_SLEEP
  quillui_alias_env QUILLUI_BACKEND_FOCUS_PRIME QUILLUI_GTK_FOCUS_PRIME QUILLUI_QT_FOCUS_PRIME
  quillui_alias_env QUILLUI_BACKEND_FOCUS_PRIME_X QUILLUI_GTK_FOCUS_PRIME_X QUILLUI_QT_FOCUS_PRIME_X
  quillui_alias_env QUILLUI_BACKEND_FOCUS_PRIME_Y QUILLUI_GTK_FOCUS_PRIME_Y QUILLUI_QT_FOCUS_PRIME_Y
  quillui_alias_env QUILLUI_BACKEND_FOCUS_PRIME_SLEEP QUILLUI_GTK_FOCUS_PRIME_SLEEP QUILLUI_QT_FOCUS_PRIME_SLEEP
  quillui_alias_env QUILLUI_BACKEND_CLICK_X QUILLUI_GTK_CLICK_X QUILLUI_QT_CLICK_X
  quillui_alias_env QUILLUI_BACKEND_CLICK_Y QUILLUI_GTK_CLICK_Y QUILLUI_QT_CLICK_Y
  quillui_alias_env QUILLUI_BACKEND_SETTINGS_CLICK_X QUILLUI_GTK_SETTINGS_CLICK_X QUILLUI_QT_SETTINGS_CLICK_X
  quillui_alias_env QUILLUI_BACKEND_SETTINGS_CLICK_Y QUILLUI_GTK_SETTINGS_CLICK_Y QUILLUI_QT_SETTINGS_CLICK_Y
  quillui_alias_env QUILLUI_BACKEND_ENDPOINT_CLICK_X QUILLUI_GTK_ENDPOINT_CLICK_X QUILLUI_QT_ENDPOINT_CLICK_X
  quillui_alias_env QUILLUI_BACKEND_ENDPOINT_CLICK_Y QUILLUI_GTK_ENDPOINT_CLICK_Y QUILLUI_QT_ENDPOINT_CLICK_Y
  quillui_alias_env QUILLUI_BACKEND_TYPE_TEXT QUILLUI_GTK_TYPE_TEXT QUILLUI_QT_TYPE_TEXT
  quillui_alias_backend_common_env
}

quillui_alias_backend_profile_env() {
  quillui_alias_env QUILLUI_BACKEND_PROFILE_COMMAND QUILLUI_GTK_PROFILE_COMMAND QUILLUI_QT_PROFILE_COMMAND
  quillui_alias_env QUILLUI_BACKEND_PROFILE_SETTLE QUILLUI_GTK_PROFILE_SETTLE QUILLUI_QT_PROFILE_SETTLE
  quillui_alias_env QUILLUI_BACKEND_PROFILE_STEADY QUILLUI_GTK_PROFILE_STEADY QUILLUI_QT_PROFILE_STEADY
  quillui_alias_env QUILLUI_BACKEND_PROFILE_DISPLAY QUILLUI_GTK_PROFILE_DISPLAY QUILLUI_QT_PROFILE_DISPLAY
  quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE QUILLUI_GTK_PROFILE_SCREEN_SIZE QUILLUI_QT_PROFILE_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_PROFILE_SCREEN_SIZE QUILLUI_GTK_PROFILE_SCREEN_SIZE QUILLUI_QT_PROFILE_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE QUILLUI_QT_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_PROFILE_MAX_CPU_PCT QUILLUI_GTK_PROFILE_MAX_CPU_PCT QUILLUI_QT_PROFILE_MAX_CPU_PCT
  quillui_alias_env QUILLUI_BACKEND_PROFILE_MAX_RSS_KB QUILLUI_GTK_PROFILE_MAX_RSS_KB QUILLUI_QT_PROFILE_MAX_RSS_KB
  quillui_alias_env QUILLUI_BACKEND_PROFILE_MAX_STARTUP_MS QUILLUI_GTK_PROFILE_MAX_STARTUP_MS QUILLUI_QT_PROFILE_MAX_STARTUP_MS
  quillui_alias_backend_common_env
}

quillui_backend_for_product() {
  case "$1" in
    quill-qt-interaction-smoke)
      echo "qt"
      ;;
    quill-gtk-interaction-smoke|quill-chat-linux)
      echo "gtk"
      ;;
    *)
      local product
      local backend
      while IFS= read -r product; do
        if [[ "$1" == "$product" ]]; then
          while IFS= read -r backend; do
            [[ -n "$backend" ]] || continue
            echo "$backend"
            return
          done < <(quillui_backend_app_backends_for_product "$product")
          return
        fi
      done < <(quillui_backend_app_products)
      echo ""
      ;;
  esac
}

quillui_require_backend_for_product() {
  local product="$1"
  local backend

  backend="$(quillui_backend_for_product "$product")"
  if [[ -z "$backend" ]]; then
    echo "Unsupported QuillUI backend product: $product" >&2
    return 65
  fi

  echo "$backend"
}

quillui_backend_profile_matrix() {
  quillui_backend_app_matrix
  quillui_backend_generated_app_matrix
  quillui_backend_smoke_matrix
}

quillui_requested_backend_for_product() {
  if [[ -n "${QUILLUI_BACKEND:-}" ]]; then
    quillui_require_backend_identifier "$QUILLUI_BACKEND"
  else
    quillui_backend_for_product "$1"
  fi
}

quillui_require_requested_backend_for_product() {
  if [[ -n "${QUILLUI_BACKEND:-}" ]]; then
    quillui_require_backend_identifier "$QUILLUI_BACKEND"
  else
    quillui_require_backend_for_product "$1"
  fi
}

quillui_runtime_backend_for_backend() {
  local requested_backend

  requested_backend="$(quillui_require_backend_identifier "$1")" || return $?
  if quillui_backend_has_native_runtime "$requested_backend"; then
    echo "$requested_backend"
    return 0
  fi

  quillui_platform_runtime_fallback_backend
}

quillui_backend_runtime_mode_for_pair() {
  local requested_backend
  local runtime_backend

  requested_backend="$(quillui_require_backend_identifier "$1")" || return $?
  runtime_backend="$(quillui_require_backend_identifier "$2")" || return $?
  if [[ "$requested_backend" == "$runtime_backend" ]]; then
    echo "native"
  else
    echo "platformFallback"
  fi
}

quillui_backend_runtime_mode_for_backend() {
  local requested_backend
  local runtime_backend

  requested_backend="$(quillui_require_backend_identifier "$1")" || return $?
  runtime_backend="$(quillui_runtime_backend_for_backend "$requested_backend")" || return $?
  quillui_backend_runtime_mode_for_pair "$requested_backend" "$runtime_backend"
}

quillui_backend_runtime_availability_for_backend() {
  local requested_backend
  local runtime_backend
  local runtime_mode

  requested_backend="$(quillui_require_backend_identifier "$1")" || return $?
  runtime_backend="$(quillui_runtime_backend_for_backend "$requested_backend")" || return $?
  runtime_mode="$(quillui_backend_runtime_mode_for_pair "$requested_backend" "$runtime_backend")" || return $?
  printf '%s\t%s\t%s\n' "$requested_backend" "$runtime_backend" "$runtime_mode"
}

quillui_backend_runtime_availability_for_product() {
  local product="$1"
  local requested_backend
  local runtime_backend
  local runtime_mode

  requested_backend="$(quillui_require_backend_identifier "$2")" || return $?
  if runtime_backend="$(quillui_backend_native_runtime_backend_for_product "$product" "$requested_backend")"; then
    runtime_mode="$(quillui_backend_runtime_mode_for_pair "$requested_backend" "$runtime_backend")" || return $?
    printf '%s\t%s\t%s\n' "$requested_backend" "$runtime_backend" "$runtime_mode"
    return 0
  fi

  quillui_backend_runtime_availability_for_backend "$requested_backend"
}

quillui_backend_runtime_availabilities() {
  local requested_backend

  while IFS= read -r requested_backend; do
    [[ -n "$requested_backend" ]] || continue
    quillui_backend_runtime_availability_for_backend "$requested_backend" || return $?
  done < <(quillui_backend_app_backends)
}

quillui_backend_validate_runtime_availability_row() {
  local runtime_availability="$1"
  local runtime_backend
  local runtime_mode="${3:-}"
  local expected_requested_backend
  local expected_runtime_backend
  local expected_runtime_mode

  runtime_backend="$(quillui_require_backend_identifier "$2")" || return $?
  case "$runtime_mode" in
    native|platformFallback)
      ;;
    *)
      echo "runtime_mode=$runtime_mode is not supported" >&2
      return 65
      ;;
  esac

  IFS=$'\t' read -r expected_requested_backend expected_runtime_backend expected_runtime_mode <<<"$runtime_availability"

  if [[ "$runtime_backend" != "$expected_runtime_backend" ]]; then
    echo "runtime_backend=$runtime_backend does not match requested_backend=$expected_requested_backend expected_runtime=$expected_runtime_backend" >&2
    return 65
  fi

  if [[ "$runtime_mode" != "$expected_runtime_mode" ]]; then
    echo "runtime_mode=$runtime_mode does not match requested_backend=$expected_requested_backend expected_mode=$expected_runtime_mode" >&2
    return 65
  fi

  printf '%s\t%s\t%s\n' "$expected_requested_backend" "$expected_runtime_backend" "$expected_runtime_mode"
}

quillui_backend_validate_runtime_availability() {
  local requested_backend
  local runtime_availability

  requested_backend="$(quillui_require_backend_identifier "$1")" || return $?
  runtime_availability="$(quillui_backend_runtime_availability_for_backend "$requested_backend")" || return $?
  quillui_backend_validate_runtime_availability_row "$runtime_availability" "$2" "$3"
}

quillui_backend_validate_runtime_availability_for_product() {
  local product="$1"
  local requested_backend
  local runtime_availability

  requested_backend="$(quillui_require_backend_identifier "$2")" || return $?
  runtime_availability="$(quillui_backend_runtime_availability_for_product "$product" "$requested_backend")" || return $?
  quillui_backend_validate_runtime_availability_row "$runtime_availability" "$3" "$4"
}

quillui_backend_runtime_matrix_for_rows() {
  local row
  local product
  local requested_backend
  local runtime_backend
  local runtime_mode
  local mode
  local extra
  local runtime_availability

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r product requested_backend mode extra <<< "$row"
    if [[ -n "${extra:-}" ]]; then
      echo "Backend runtime matrix row has too many columns: $row" >&2
      return 65
    fi
    if [[ -z "$product" || -z "$requested_backend" ]]; then
      echo "Backend runtime matrix row has an empty product or backend: $row" >&2
      return 65
    fi

    runtime_availability="$(quillui_backend_runtime_availability_for_product "$product" "$requested_backend")" || return $?
    IFS=$'\t' read -r requested_backend runtime_backend runtime_mode <<< "$runtime_availability"
    if [[ -n "${mode:-}" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$product" "$requested_backend" "$runtime_backend" "$runtime_mode" "$mode"
    else
      printf '%s\t%s\t%s\t%s\n' "$product" "$requested_backend" "$runtime_backend" "$runtime_mode"
    fi
  done
}

quillui_backend_app_runtime_matrix() {
  quillui_backend_app_matrix | quillui_backend_runtime_matrix_for_rows
}

quillui_backend_interaction_app_runtime_matrix() {
  quillui_backend_interaction_app_matrix | quillui_backend_runtime_matrix_for_rows
}

quillui_backend_generated_app_runtime_matrix() {
  quillui_backend_generated_app_matrix | quillui_backend_runtime_matrix_for_rows
}

quillui_backend_smoke_runtime_matrix() {
  quillui_backend_smoke_matrix | quillui_backend_runtime_matrix_for_rows
}

quillui_backend_smoke_interaction_runtime_matrix() {
  quillui_backend_smoke_interaction_matrix | quillui_backend_runtime_matrix_for_rows
}

quillui_backend_profile_runtime_matrix() {
  quillui_backend_profile_matrix | quillui_backend_runtime_matrix_for_rows
}

quillui_runtime_backend_for_product() {
  local requested_backend
  local runtime_availability
  local runtime_backend
  local runtime_mode

  requested_backend="$(quillui_require_requested_backend_for_product "$1")" || return $?
  if [[ -n "$requested_backend" ]]; then
    runtime_availability="$(quillui_backend_runtime_availability_for_product "$1" "$requested_backend")" || return $?
    IFS=$'\t' read -r requested_backend runtime_backend runtime_mode <<< "$runtime_availability"
    echo "$runtime_backend"
  fi
}

quillui_backend_products_usage() {
  cat >&2 <<'MSG'
Usage: quillui-backend-products.sh COMMAND [ARG]

Commands:
  backend-apps                    List user-facing app products in the backend parity matrix.
  app-backends                    List backends requested for each user-facing app.
  app-matrix                      List PRODUCT<TAB>BACKEND visual smoke rows for user-facing apps.
  app-runtime-matrix              List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE rows for user-facing apps.
  interaction-apps                List user-facing app products covered by interaction smokes.
  interaction-matrix              List PRODUCT<TAB>BACKEND interaction smoke rows for user-facing apps.
  interaction-runtime-matrix      List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE rows for interaction smokes.
  generated-apps                  List generated external app products covered by backend parity smoke.
  generated-app-matrix            List PRODUCT<TAB>BACKEND rows for generated external apps.
  generated-app-runtime-matrix    List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE rows for generated external apps.
  gtk-apps                        Legacy alias for backend-apps.
  fixed-app-backends              List PRODUCT<TAB>BACKEND rows constrained to one build backend.
  native-runtime-backends         List backends linked to native Linux runtime hosts.
  native-product-runtime-overrides
                                  List PRODUCT<TAB>BACKEND<TAB>RUNTIME rows for product-specific native hosts.
  platform-runtime-fallback       Print the runtime backend used when a selected backend has no native host.
  smoke-products                  List backend launch smoke products.
  smoke-matrix                    List PRODUCT<TAB>BACKEND rows for backend launch smoke products.
  smoke-runtime-matrix            List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE launch smoke rows.
  smoke-interaction-modes         List interaction modes for backend launch smoke products.
  smoke-interaction-matrix        List PRODUCT<TAB>BACKEND<TAB>MODE rows for backend launch interaction smokes.
  smoke-interaction-runtime-matrix
                                  List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE<TAB>INTERACTION rows.
  smoke-interaction-verify-matrix List PRODUCT<TAB>BACKEND<TAB>MODE<TAB>VERIFY_PRODUCT rows.
  normalize-smoke-interaction-mode MODE
                                  Print the canonical backend launch interaction mode.
  smoke-interaction-verify-product PRODUCT MODE
                                  Print the screenshot verifier product for a launch mode.
  profile-products                List app and launch-smoke products for profile budgets.
  profile-matrix                  List PRODUCT<TAB>BACKEND rows for profile budgets.
  profile-runtime-matrix          List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE rows for profile budgets.
  normalize-backend BACKEND       Print the canonical backend identifier for a known backend alias.
  require-backend BACKEND         Print the canonical backend identifier or fail for an unknown backend.
  require-linux-build-backend BACKEND
                                  Print the canonical manifest build backend or fail unless BACKEND is gtk/qt.
  is-smoke-product PRODUCT        Exit 0 when PRODUCT is a backend launch smoke product.
  is-generated-app PRODUCT        Exit 0 when PRODUCT is a generated external app product.
  has-native-runtime BACKEND      Exit 0 when BACKEND is linked to a native Linux runtime host.
  backend-for-product PRODUCT     Print the default requested backend for PRODUCT.
  requested-backend PRODUCT       Print QUILLUI_BACKEND override or PRODUCT default.
  runtime-backend BACKEND         Print the native runtime backend used for a requested backend.
  runtime-mode BACKEND            Print native or platformFallback for a requested backend.
  runtime-availability BACKEND    Print BACKEND<TAB>RUNTIME<TAB>MODE for a requested backend.
  validate-runtime-availability BACKEND RUNTIME MODE
                                  Validate and print canonical BACKEND<TAB>RUNTIME<TAB>MODE.
  runtime-backend-for-product PRODUCT
                                  Print the native runtime backend used for PRODUCT.
  runtime-availabilities          List BACKEND<TAB>RUNTIME<TAB>MODE rows for requested app backends.
MSG
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    backend-apps)
      quillui_backend_app_products
      ;;
    app-backends)
      quillui_backend_app_backends
      ;;
    app-matrix)
      quillui_backend_app_matrix
      ;;
    app-runtime-matrix)
      quillui_backend_app_runtime_matrix
      ;;
    interaction-apps)
      quillui_backend_interaction_app_products
      ;;
    interaction-matrix)
      quillui_backend_interaction_app_matrix
      ;;
    interaction-runtime-matrix)
      quillui_backend_interaction_app_runtime_matrix
      ;;
    generated-apps)
      quillui_backend_generated_app_products
      ;;
    generated-app-matrix)
      quillui_backend_generated_app_matrix
      ;;
    generated-app-runtime-matrix)
      quillui_backend_generated_app_runtime_matrix
      ;;
    gtk-apps)
      quillui_gtk_app_products
      ;;
    fixed-app-backends)
      quillui_backend_fixed_app_backend_overrides
      ;;
    native-runtime-backends)
      quillui_backend_native_runtime_backends
      ;;
    native-product-runtime-overrides)
      quillui_backend_native_product_runtime_overrides
      ;;
    platform-runtime-fallback)
      quillui_platform_runtime_fallback_backend
      ;;
    smoke-products)
      quillui_backend_smoke_products
      ;;
    smoke-matrix)
      quillui_backend_smoke_matrix
      ;;
    smoke-runtime-matrix)
      quillui_backend_smoke_runtime_matrix
      ;;
    smoke-interaction-modes)
      quillui_backend_smoke_interaction_modes
      ;;
    smoke-interaction-matrix)
      quillui_backend_smoke_interaction_matrix
      ;;
    smoke-interaction-runtime-matrix)
      quillui_backend_smoke_interaction_runtime_matrix
      ;;
    smoke-interaction-verify-matrix)
      quillui_backend_smoke_interaction_verify_matrix
      ;;
    normalize-smoke-interaction-mode)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_normalize_backend_smoke_interaction_mode "$2"
      ;;
    smoke-interaction-verify-product)
      if [[ $# -ne 3 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_backend_smoke_interaction_verify_product "$2" "$3"
      ;;
    profile-products)
      quillui_backend_profile_products
      ;;
    profile-matrix)
      quillui_backend_profile_matrix
      ;;
    profile-runtime-matrix)
      quillui_backend_profile_runtime_matrix
      ;;
    normalize-backend)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_normalize_backend_identifier "$2"
      ;;
    require-backend)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_require_backend_identifier "$2"
      ;;
    require-linux-build-backend)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_require_linux_build_backend_identifier "$2"
      ;;
    is-smoke-product)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_is_backend_smoke_product "$2"
      ;;
    is-generated-app)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_is_backend_generated_app_product "$2"
      ;;
    has-native-runtime)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_backend_has_native_runtime "$2"
      ;;
    backend-for-product)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_require_backend_for_product "$2"
      ;;
    requested-backend)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_require_requested_backend_for_product "$2"
      ;;
    runtime-backend)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_runtime_backend_for_backend "$2"
      ;;
    runtime-mode)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_backend_runtime_mode_for_backend "$2"
      ;;
    runtime-availability)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_backend_runtime_availability_for_backend "$2"
      ;;
    validate-runtime-availability)
      if [[ $# -ne 4 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_backend_validate_runtime_availability "$2" "$3" "$4"
      ;;
    runtime-backend-for-product)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_runtime_backend_for_product "$2"
      ;;
    runtime-availabilities)
      quillui_backend_runtime_availabilities
      ;;
    --help|-h)
      quillui_backend_products_usage
      ;;
    *)
      quillui_backend_products_usage
      exit 64
      ;;
  esac
fi
