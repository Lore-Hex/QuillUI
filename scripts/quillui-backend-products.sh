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
    quill-wireguard
}

quillui_backend_generic_qt_app_products() {
  # App products backed by QuillGenericQtNativeRuntime when the manifest is
  # compiled with QUILLUI_LINUX_BACKEND=qt. Keep this in one roster so generic
  # Qt interaction coverage cannot drift app-by-app.
  printf '%s\n' \
    quill-enchanted-upstream-slice \
    quill-icecubes \
    quill-netnewswire \
    quill-codeedit \
    quill-signal \
    quill-telegram \
    quill-iina
}

quillui_gtk_app_products() {
  # Legacy GTK-named entry point kept for older scripts. The backend app roster
  # is the source of truth because app binaries select GTK/Qt through the
  # manifest-time QUILLUI_LINUX_BACKEND graph.
  quillui_backend_app_products
}

quillui_backend_app_backends() {
  # Backends each user-facing app must be able to request in parity smoke
  # loops. Each app product compiles through exactly one selected manifest
  # backend per row, so GTK and Qt coverage stay explicit without suffixing
  # Linux product names.
  printf '%s\n' "${QUILLUI_BACKEND_APP_BACKEND_IDS[@]}"
}

quillui_backend_fixed_app_backend_overrides() {
  # PRODUCT<TAB>BACKEND rows for app products whose SwiftPM target links one
  # native host stack at manifest time. Canonical app products now compile
  # through the selected QUILLUI_LINUX_BACKEND graph, so this table should stay
  # empty unless a future product truly cannot support both manifest backends.
  :
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

quillui_backend_default_app_backend() {
  local backend

  for backend in "${QUILLUI_BACKEND_APP_BACKEND_IDS[@]}"; do
    [[ -n "$backend" ]] || continue
    echo "$backend"
    return 0
  done

  echo "No QuillUI backend app backends configured." >&2
  return 65
}

quillui_backend_native_runtime_backends() {
  # Mirrors the native runtime hosts linked by generic QuillApp entry points.
  # Product-specific Qt launchers are tracked separately because they bypass the
  # generic runtime registry today.
  printf '%s\n' \
    gtk
}

quillui_backend_product_native_runtime_backends() {
  # Manifest-selected app products can compile through these native runtime
  # graphs. Keep this separate from the generic runtime registry so generated
  # facade packages do not claim a native Qt host before QuillApp links one.
  printf '%s\n' \
    gtk \
    qt
}

quillui_backend_native_product_runtime_overrides() {
  # PRODUCT<TAB>REQUESTED_BACKEND<TAB>RUNTIME_BACKEND rows for native hosts that
  # exist only behind a product-specific SwiftPM graph today.
  printf '%s\t%s\t%s\n' \
    quill-qt-interaction-smoke qt qt
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

  if quillui_backend_product_list_contains "$product" quillui_backend_app_products \
      && quillui_backend_product_has_native_runtime "$requested_backend"; then
    echo "$requested_backend"
    return 0
  fi

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

quillui_backend_build_product_rows() {
  # PRODUCT<TAB>BUILD_BACKEND rows for root SwiftPM product builds. Runtime
  # smoke matrices may request multiple backend rows, but package products still
  # compile through one manifest-time backend graph.
  case "$1" in
    fixed-app-backends)
      quillui_backend_fixed_app_backend_overrides
      ;;
    backend-apps|all-app-backends|app-matrix)
      quillui_backend_app_matrix
      ;;
    interaction-matrix)
      quillui_backend_interaction_app_matrix
      ;;
    smoke-matrix)
      quillui_backend_smoke_matrix
      ;;
    *)
      echo "Unsupported backend product build matrix: $1" >&2
      return 64
      ;;
  esac
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

quillui_backend_build_stamp_product_name() {
  local product="$1"

  if [[ -z "$product" || "$product" == *[!A-Za-z0-9_.-]* ]]; then
    echo "Unsupported QuillUI backend build stamp product: $product" >&2
    return 65
  fi

  echo "$product"
}

quillui_backend_build_stamp_path() {
  local scratch_path="$1"
  local product
  local backend

  product="$(quillui_backend_build_stamp_product_name "$2")" || return $?
  backend="$(quillui_require_linux_build_backend_identifier "$3")" || return $?
  if [[ -z "$scratch_path" ]]; then
    echo "Backend build stamp scratch path is required." >&2
    return 65
  fi

  printf '%s/.quillui-backend-products/%s.%s.backend.stamp\n' "$scratch_path" "$product" "$backend"
}

quillui_record_backend_product_build() {
  local scratch_path="$1"
  local product
  local backend
  local stamp_path

  product="$(quillui_backend_build_stamp_product_name "$2")" || return $?
  backend="$(quillui_require_linux_build_backend_identifier "$3")" || return $?
  stamp_path="$(quillui_backend_build_stamp_path "$scratch_path" "$product" "$backend")" || return $?

  mkdir -p "$(dirname "$stamp_path")"
  {
    printf 'product=%s\n' "$product"
    printf 'backend=%s\n' "$backend"
  } > "$stamp_path"
}

quillui_require_backend_product_build_stamp() {
  local scratch_path="$1"
  local product
  local expected_backend
  local stamp_path
  local stamped_product=""
  local stamped_backend=""
  local key
  local value

  product="$(quillui_backend_build_stamp_product_name "$2")" || return $?
  expected_backend="$(quillui_require_linux_build_backend_identifier "$3")" || return $?
  stamp_path="$(quillui_backend_build_stamp_path "$scratch_path" "$product" "$expected_backend")" || return $?

  if [[ ! -f "$stamp_path" ]]; then
    echo "No cached backend build stamp for $product under $scratch_path; rerun without QUILLUI_BACKEND_SKIP_BUILD=1." >&2
    return 66
  fi

  while IFS='=' read -r key value; do
    case "$key" in
      product)
        stamped_product="$value"
        ;;
      backend)
        stamped_backend="$value"
        ;;
    esac
  done < "$stamp_path"

  if [[ "$stamped_product" != "$product" ]]; then
    echo "Cached backend build stamp for $product is malformed: $stamp_path" >&2
    return 66
  fi

  stamped_backend="$(quillui_require_linux_build_backend_identifier "$stamped_backend")" || {
    echo "Cached backend build stamp for $product is malformed: $stamp_path" >&2
    return 66
  }

  if [[ "$stamped_backend" != "$expected_backend" ]]; then
    echo "Cached backend build stamp for $product records QUILLUI_LINUX_BACKEND=$stamped_backend, expected $expected_backend; rerun without QUILLUI_BACKEND_SKIP_BUILD=1." >&2
    return 66
  fi

  return 0
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

quillui_backend_interaction_extra_mode_matrix() {
  # Semantic app interactions that go past the default click/select smoke live
  # here so CI can add product-specific coverage without forking the runner.
  printf '%s\t%s\t%s\n' \
    quill-wireguard gtk import-paste \
    quill-wireguard gtk import-file \
    quill-wireguard gtk import-invalid-paste \
    quill-wireguard gtk import-invalid-file \
    quill-wireguard qt import-paste \
    quill-wireguard qt import-file \
    quill-wireguard qt import-invalid-paste \
    quill-wireguard qt import-invalid-file \
    quill-enchanted qt list-selection

  local product
  while IFS= read -r product; do
    [[ -n "$product" ]] || continue
    printf '%s\t%s\t%s\n' "$product" qt list-selection
  done < <(quillui_backend_generic_qt_app_products)
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

quillui_is_backend_generic_qt_app_product() {
  quillui_backend_product_list_contains "$1" quillui_backend_generic_qt_app_products
}

quillui_backend_has_native_runtime() {
  local requested_backend

  requested_backend="$(quillui_require_backend_identifier "$1")" || return $?
  quillui_backend_product_list_contains "$requested_backend" quillui_backend_native_runtime_backends
}

quillui_backend_product_has_native_runtime() {
  local requested_backend

  requested_backend="$(quillui_require_backend_identifier "$1")" || return $?
  quillui_backend_product_list_contains "$requested_backend" quillui_backend_product_native_runtime_backends
}

quillui_alias_matches_backend() {
  local alias="$1"
  local backend="$2"
  local backend_prefix=""
  local backend_marker=""

  case "$backend" in
    gtk)
      backend_prefix="QUILLUI_GTK_"
      backend_marker="_GTK_"
      ;;
    qt)
      backend_prefix="QUILLUI_QT_"
      backend_marker="_QT_"
      ;;
    *)
      return 1
      ;;
  esac

  [[ "$alias" == "$backend_prefix"* || "$alias" == *"$backend_marker"* ]]
}

quillui_alias_matches_other_backend() {
  local alias="$1"
  local selected_backend="$2"

  case "$selected_backend" in
    gtk)
      quillui_alias_matches_backend "$alias" qt
      ;;
    qt)
      quillui_alias_matches_backend "$alias" gtk
      ;;
    *)
      return 1
      ;;
  esac
}

quillui_alias_env() {
  local canonical="$1"
  shift
  local alias
  local selected_backend=""

  if [[ -n "${QUILLUI_BACKEND:-}" ]]; then
    selected_backend="$(quillui_normalize_backend_identifier "$QUILLUI_BACKEND" || true)"
  fi

  if [[ -z "${!canonical:-}" && -n "$selected_backend" ]]; then
    for alias in "$@"; do
      if quillui_alias_matches_backend "$alias" "$selected_backend" && [[ -n "${!alias:-}" ]]; then
        printf -v "$canonical" "%s" "${!alias}"
        break
      fi
    done
  fi

  if [[ -z "${!canonical:-}" ]]; then
    for alias in "$@"; do
      if [[ -n "$selected_backend" ]] && quillui_alias_matches_other_backend "$alias" "$selected_backend"; then
        continue
      fi
      if [[ -n "${!alias:-}" ]]; then
        printf -v "$canonical" "%s" "${!alias}"
        break
      fi
    done
  fi

  if [[ -n "${!canonical:-}" ]]; then
    for alias in "$@"; do
      if [[ -n "$selected_backend" ]] && quillui_alias_matches_other_backend "$alias" "$selected_backend"; then
        continue
      fi
      printf -v "$alias" "%s" "${!canonical}"
    done
  fi
}

# Backend-neutral names are canonical for GTK/Qt parity checks. The
# legacy QUILLUI_GTK_* names and scoped QUILLUI_QT_* names stay supported.
# When a backend is explicitly selected, aliases scoped to the other backend are
# never used as input. When multiple matching names are set, backend-neutral wins.
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
  quillui_alias_env QUILLUI_BACKEND_IMPORT_CLICK_X QUILLUI_GTK_IMPORT_CLICK_X QUILLUI_QT_IMPORT_CLICK_X
  quillui_alias_env QUILLUI_BACKEND_IMPORT_CLICK_Y QUILLUI_GTK_IMPORT_CLICK_Y QUILLUI_QT_IMPORT_CLICK_Y
  quillui_alias_env QUILLUI_BACKEND_IMPORT_EDITOR_X QUILLUI_GTK_IMPORT_EDITOR_X QUILLUI_QT_IMPORT_EDITOR_X
  quillui_alias_env QUILLUI_BACKEND_IMPORT_EDITOR_Y QUILLUI_GTK_IMPORT_EDITOR_Y QUILLUI_QT_IMPORT_EDITOR_Y
  quillui_alias_env QUILLUI_BACKEND_IMPORT_CONFIGURATION QUILLUI_GTK_IMPORT_CONFIGURATION QUILLUI_QT_IMPORT_CONFIGURATION
  quillui_alias_env QUILLUI_BACKEND_MALFORMED_IMPORT_CONFIGURATION QUILLUI_GTK_MALFORMED_IMPORT_CONFIGURATION QUILLUI_QT_MALFORMED_IMPORT_CONFIGURATION
  quillui_alias_env QUILLUI_BACKEND_IMPORT_CONFIGURATION_FILE QUILLUI_GTK_IMPORT_CONFIGURATION_FILE QUILLUI_QT_IMPORT_CONFIGURATION_FILE
  quillui_alias_env QUILLUI_BACKEND_MALFORMED_IMPORT_CONFIGURATION_FILE QUILLUI_GTK_MALFORMED_IMPORT_CONFIGURATION_FILE QUILLUI_QT_MALFORMED_IMPORT_CONFIGURATION_FILE
  quillui_alias_env QUILLUI_BACKEND_TYPE_TEXT QUILLUI_GTK_TYPE_TEXT QUILLUI_QT_TYPE_TEXT
  quillui_alias_env QUILLUI_GENERIC_QT_SELECTED_INDEX_ON_START QUILLUI_GTK_GENERIC_SELECTED_INDEX_ON_START QUILLUI_QT_GENERIC_SELECTED_INDEX_ON_START
  quillui_alias_env QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_GTK_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START QUILLUI_QT_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START
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
      local fixed_backend

      if quillui_backend_product_list_contains "$1" quillui_backend_app_products; then
        if fixed_backend="$(quillui_backend_fixed_backend_for_app_product "$1")"; then
          echo "$fixed_backend"
        else
          quillui_backend_default_app_backend
        fi
      else
        echo ""
      fi
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

quillui_validate_requested_backend_for_product() {
  local product="$1"
  local requested_backend
  local fixed_backend

  requested_backend="$(quillui_require_backend_identifier "$2")" || return $?
  quillui_require_backend_for_product "$product" >/dev/null || return $?
  if fixed_backend="$(quillui_backend_fixed_backend_for_app_product "$product")"; then
    if [[ "$requested_backend" != "$fixed_backend" ]]; then
      echo "Product $product is fixed to the $fixed_backend Linux backend; requested $requested_backend would mix manifest and runtime backend paths." >&2
      return 65
    fi
  fi

  echo "$requested_backend"
}

quillui_requested_backend_for_product() {
  if [[ -n "${QUILLUI_BACKEND:-}" ]]; then
    quillui_validate_requested_backend_for_product "$1" "$QUILLUI_BACKEND"
  else
    quillui_backend_for_product "$1"
  fi
}

quillui_require_requested_backend_for_product() {
  if [[ -n "${QUILLUI_BACKEND:-}" ]]; then
    quillui_validate_requested_backend_for_product "$1" "$QUILLUI_BACKEND"
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

quillui_backend_seen_keys_contains() {
  local seen_keys="$1"
  local key="$2"

  case "$seen_keys" in
    *$'\n'"$key"$'\n'*)
      return 0
      ;;
  esac

  return 1
}

quillui_backend_validate_unique_key() {
  local seen_keys="$1"
  local key="$2"
  local table_name="$3"

  if quillui_backend_seen_keys_contains "$seen_keys" "$key"; then
    echo "$table_name contains duplicate row: $key" >&2
    return 65
  fi
}

quillui_backend_validate_app_product_reference() {
  local product="$1"
  local table_name="$2"

  if [[ -z "$product" ]]; then
    echo "$table_name contains an empty product." >&2
    return 65
  fi

  if ! quillui_backend_product_list_contains "$product" quillui_backend_app_products; then
    echo "$table_name references unknown app product: $product" >&2
    return 65
  fi
}

quillui_backend_validate_runtime_product_reference() {
  local product="$1"
  local table_name="$2"

  if [[ -z "$product" ]]; then
    echo "$table_name contains an empty product." >&2
    return 65
  fi

  if ! quillui_backend_product_list_contains "$product" quillui_backend_profile_products; then
    echo "$table_name references unknown runtime product: $product" >&2
    return 65
  fi
}

quillui_backend_validate_app_backend_ids() {
  local backend
  local normalized_backend
  local seen_keys=$'\n'

  while IFS= read -r backend; do
    [[ -n "$backend" ]] || continue
    normalized_backend="$(quillui_require_linux_build_backend_identifier "$backend")" || return $?
    if [[ "$backend" != "$normalized_backend" ]]; then
      echo "app-backends must emit canonical backend identifiers; got $backend, expected $normalized_backend." >&2
      return 65
    fi
    quillui_backend_validate_unique_key "$seen_keys" "$backend" "app-backends" || return $?
    seen_keys="${seen_keys}${backend}"$'\n'
  done < <(quillui_backend_app_backends)
}

quillui_backend_validate_product_native_runtime_backends() {
  local backend
  local normalized_backend
  local seen_keys=$'\n'

  while IFS= read -r backend; do
    [[ -n "$backend" ]] || continue
    normalized_backend="$(quillui_require_linux_build_backend_identifier "$backend")" || return $?
    if [[ "$backend" != "$normalized_backend" ]]; then
      echo "native-product-runtime-backends must emit canonical backend identifiers; got $backend, expected $normalized_backend." >&2
      return 65
    fi
    quillui_backend_validate_unique_key "$seen_keys" "$backend" "native-product-runtime-backends" || return $?
    seen_keys="${seen_keys}${backend}"$'\n'
  done < <(quillui_backend_product_native_runtime_backends)
}

quillui_backend_validate_fixed_app_backend_overrides() {
  local product
  local backend
  local extra
  local normalized_backend
  local seen_keys=$'\n'

  while IFS=$'\t' read -r product backend extra; do
    [[ -n "$product" || -n "$backend" || -n "${extra:-}" ]] || continue
    if [[ -n "${extra:-}" ]]; then
      echo "fixed-app-backends row has too many columns: $product	$backend	$extra" >&2
      return 65
    fi
    if [[ -z "$backend" ]]; then
      echo "fixed-app-backends contains an empty backend for product: $product" >&2
      return 65
    fi
    quillui_backend_validate_app_product_reference "$product" "fixed-app-backends" || return $?
    normalized_backend="$(quillui_require_linux_build_backend_identifier "$backend")" || return $?
    if [[ "$backend" != "$normalized_backend" ]]; then
      echo "fixed-app-backends must use canonical backend identifiers; $product has $backend, expected $normalized_backend." >&2
      return 65
    fi
    quillui_backend_validate_unique_key "$seen_keys" "$product" "fixed-app-backends" || return $?
    seen_keys="${seen_keys}${product}"$'\n'
  done < <(quillui_backend_fixed_app_backend_overrides)
}

quillui_backend_validate_native_product_runtime_overrides() {
  local product
  local requested_backend
  local runtime_backend
  local extra
  local normalized_requested_backend
  local normalized_runtime_backend
  local seen_keys=$'\n'

  while IFS=$'\t' read -r product requested_backend runtime_backend extra; do
    [[ -n "$product" || -n "$requested_backend" || -n "$runtime_backend" || -n "${extra:-}" ]] || continue
    if [[ -n "${extra:-}" ]]; then
      echo "native-product-runtime-overrides row has too many columns: $product	$requested_backend	$runtime_backend	$extra" >&2
      return 65
    fi
    if [[ -z "$requested_backend" || -z "$runtime_backend" ]]; then
      echo "native-product-runtime-overrides contains an empty backend: $product	$requested_backend	$runtime_backend" >&2
      return 65
    fi
    quillui_backend_validate_runtime_product_reference "$product" "native-product-runtime-overrides" || return $?
    normalized_requested_backend="$(quillui_require_linux_build_backend_identifier "$requested_backend")" || return $?
    normalized_runtime_backend="$(quillui_require_linux_build_backend_identifier "$runtime_backend")" || return $?
    if [[ "$requested_backend" != "$normalized_requested_backend" || "$runtime_backend" != "$normalized_runtime_backend" ]]; then
      echo "native-product-runtime-overrides must use canonical backend identifiers: $product	$requested_backend	$runtime_backend" >&2
      return 65
    fi
    if [[ "$requested_backend" != "$runtime_backend" ]]; then
      echo "native-product-runtime-overrides rows must map to a matching native runtime backend: $product	$requested_backend	$runtime_backend" >&2
      return 65
    fi
    quillui_backend_validate_native_app_runtime_override "$product" "$requested_backend" || return $?
    quillui_validate_requested_backend_for_product "$product" "$requested_backend" >/dev/null || return $?
    quillui_backend_validate_unique_key "$seen_keys" "$product/$requested_backend" "native-product-runtime-overrides" || return $?
    seen_keys="${seen_keys}${product}/${requested_backend}"$'\n'
  done < <(quillui_backend_native_product_runtime_overrides)
}

quillui_backend_validate_native_app_runtime_override() {
  local product="$1"
  local requested_backend="$2"
  local fixed_backend

  if ! quillui_backend_product_list_contains "$product" quillui_backend_app_products; then
    return 0
  fi

  if ! fixed_backend="$(quillui_backend_fixed_backend_for_app_product "$product")"; then
    echo "native-product-runtime-overrides references app product $product without a fixed-app-backends row; canonical app products should compile through the backend matrix unless they are true single-backend exceptions." >&2
    return 65
  fi

  if [[ "$fixed_backend" != "$requested_backend" ]]; then
    echo "native-product-runtime-overrides app product $product requests $requested_backend but fixed-app-backends uses $fixed_backend." >&2
    return 65
  fi
}

quillui_backend_validate_interaction_extra_mode_matrix() {
  local product
  local backend
  local mode
  local extra
  local normalized_backend
  local seen_keys=$'\n'

  while IFS=$'\t' read -r product backend mode extra; do
    [[ -n "$product" || -n "$backend" || -n "$mode" || -n "${extra:-}" ]] || continue
    if [[ -n "${extra:-}" ]]; then
      echo "interaction-extra-mode-matrix row has too many columns: $product	$backend	$mode	$extra" >&2
      return 65
    fi
    if [[ -z "$backend" || -z "$mode" ]]; then
      echo "interaction-extra-mode-matrix contains an empty backend or mode: $product	$backend	$mode" >&2
      return 65
    fi
    quillui_backend_validate_app_product_reference "$product" "interaction-extra-mode-matrix" || return $?
    normalized_backend="$(quillui_require_linux_build_backend_identifier "$backend")" || return $?
    if [[ "$backend" != "$normalized_backend" ]]; then
      echo "interaction-extra-mode-matrix must use canonical backend identifiers; $product/$mode has $backend, expected $normalized_backend." >&2
      return 65
    fi
    quillui_validate_requested_backend_for_product "$product" "$backend" >/dev/null || return $?
    quillui_backend_validate_unique_key "$seen_keys" "$product/$backend/$mode" "interaction-extra-mode-matrix" || return $?
    seen_keys="${seen_keys}${product}/${backend}/${mode}"$'\n'
  done < <(quillui_backend_interaction_extra_mode_matrix)
}

quillui_backend_validate_integrity() {
  quillui_backend_validate_app_backend_ids || return $?
  quillui_backend_validate_product_native_runtime_backends || return $?
  quillui_backend_validate_fixed_app_backend_overrides || return $?
  quillui_backend_validate_native_product_runtime_overrides || return $?
  quillui_backend_validate_interaction_extra_mode_matrix || return $?
  quillui_backend_app_runtime_matrix >/dev/null || return $?
  quillui_backend_interaction_app_runtime_matrix >/dev/null || return $?
  quillui_backend_interaction_extra_mode_runtime_matrix >/dev/null || return $?
  quillui_backend_generated_app_runtime_matrix >/dev/null || return $?
  quillui_backend_smoke_runtime_matrix >/dev/null || return $?
  quillui_backend_smoke_interaction_runtime_matrix >/dev/null || return $?
  quillui_backend_profile_runtime_matrix >/dev/null || return $?
  echo "backend product matrix ok"
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

quillui_backend_interaction_extra_mode_runtime_matrix() {
  quillui_backend_interaction_extra_mode_matrix | quillui_backend_runtime_matrix_for_rows
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
  generic-qt-apps                 List app products backed by the shared generic Qt runtime.
  build-product-matrix MATRIX     List PRODUCT<TAB>BUILD_BACKEND rows for package builds.
  app-backends                    List backends requested for each user-facing app.
  app-matrix                      List PRODUCT<TAB>BACKEND visual smoke rows for user-facing apps.
  app-runtime-matrix              List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE rows for user-facing apps.
  interaction-apps                List user-facing app products covered by interaction smokes.
  interaction-matrix              List PRODUCT<TAB>BACKEND interaction smoke rows for user-facing apps.
  interaction-runtime-matrix      List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE rows for interaction smokes.
  interaction-extra-mode-matrix   List PRODUCT<TAB>BACKEND<TAB>MODE rows for semantic app interactions.
  interaction-extra-mode-runtime-matrix
                                  List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE<TAB>INTERACTION rows.
  generated-apps                  List generated external app products covered by backend parity smoke.
  generated-app-matrix            List PRODUCT<TAB>BACKEND rows for generated external apps.
  generated-app-runtime-matrix    List PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE rows for generated external apps.
  gtk-apps                        Legacy alias for backend-apps.
  fixed-app-backends              List PRODUCT<TAB>BACKEND rows constrained to one build backend.
  native-runtime-backends         List backends linked to native Linux runtime hosts.
  native-product-runtime-backends List backends available through product-specific native runtime graphs.
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
  is-generic-qt-app PRODUCT       Exit 0 when PRODUCT uses the shared generic Qt runtime.
  has-native-runtime BACKEND      Exit 0 when BACKEND is linked to a native Linux runtime host.
  backend-for-product PRODUCT     Print the default requested backend for PRODUCT.
  requested-backend PRODUCT       Print QUILLUI_BACKEND override or PRODUCT default.
  runtime-backend BACKEND         Print the native runtime backend used for a requested backend.
  runtime-mode BACKEND            Print native or platformFallback for a requested backend.
  runtime-availability BACKEND    Print BACKEND<TAB>RUNTIME<TAB>MODE for a requested backend.
  validate-runtime-availability BACKEND RUNTIME MODE
                                  Validate and print canonical BACKEND<TAB>RUNTIME<TAB>MODE.
  validate-integrity             Validate product/backend override and smoke matrix tables.
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
    generic-qt-apps)
      quillui_backend_generic_qt_app_products
      ;;
    build-product-matrix)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_backend_build_product_rows "$2"
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
    interaction-extra-mode-matrix)
      quillui_backend_interaction_extra_mode_matrix
      ;;
    interaction-extra-mode-runtime-matrix)
      quillui_backend_interaction_extra_mode_runtime_matrix
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
    native-product-runtime-backends)
      quillui_backend_product_native_runtime_backends
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
    is-generic-qt-app)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_is_backend_generic_qt_app_product "$2"
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
    validate-integrity)
      quillui_backend_validate_integrity
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
