#!/usr/bin/env bash

quillui_gtk_app_products() {
  # User-facing Quill app executable products first covered by the Linux GTK
  # parity loops. Support tools, generated external packages, smoke fixtures,
  # and demos stay out of this roster.
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

quillui_backend_app_products() {
  # Canonical Linux backend app roster. It currently matches the GTK app
  # matrix because app binaries select GTK/Qt through QUILLUI_BACKEND.
  quillui_gtk_app_products
}

quillui_backend_app_backends() {
  # Backends each user-facing app must be able to request in parity smoke
  # loops. Qt currently falls through the shared launch-plan fallback until
  # the native renderer is linked, but keeping it in the app matrix now makes
  # accidental GTK-only assumptions visible.
  printf '%s\n' \
    gtk \
    qt
}

quillui_backend_app_matrix() {
  local product
  local backend

  while IFS= read -r product; do
    [[ -n "$product" ]] || continue
    while IFS= read -r backend; do
      [[ -n "$backend" ]] || continue
      printf '%s\t%s\n' "$product" "$backend"
    done < <(quillui_backend_app_backends)
  done < <(quillui_backend_app_products)
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

quillui_backend_profile_products() {
  # Performance budget rows cover both production-shaped app shells and the
  # minimal backend launch fixtures. Keep this as a composed roster so the app
  # matrix and smoke-product matrix remain independently reusable.
  quillui_backend_app_products
  quillui_backend_smoke_products
}

quillui_is_backend_smoke_product() {
  local candidate="$1"
  local product

  while IFS= read -r product; do
    if [[ "$candidate" == "$product" ]]; then
      return 0
    fi
  done < <(quillui_backend_smoke_products)

  return 1
}

quillui_alias_env() {
  local canonical="$1"
  local legacy="$2"

  if [[ -n "${!canonical:-}" ]]; then
    printf -v "$legacy" "%s" "${!canonical}"
  elif [[ -n "${!legacy:-}" ]]; then
    printf -v "$canonical" "%s" "${!legacy}"
  fi
}

# Backend-neutral names are canonical for GTK/Qt parity checks. The
# legacy QUILLUI_GTK_* names stay supported while local scripts migrate.
# When both are set, the backend-neutral value wins.
quillui_alias_backend_common_env() {
  quillui_alias_env QUILLUI_BACKEND_MAC_REFERENCE QUILLUI_GTK_MAC_REFERENCE
  quillui_alias_env QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH QUILLUI_GTK_DEFAULT_WINDOW_WIDTH
  quillui_alias_env QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT
  quillui_alias_env QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL
  quillui_alias_env QUILLUI_BACKEND_VERIFY_PRODUCT QUILLUI_GTK_VERIFY_PRODUCT
}

quillui_alias_backend_visual_env() {
  quillui_alias_env QUILLUI_BACKEND_VISUAL_DISPLAY QUILLUI_GTK_VISUAL_DISPLAY
  quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_VISUAL_SCREEN_SIZE QUILLUI_GTK_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_LAYOUT_DEBUG QUILLUI_GTK_LAYOUT_DEBUG
  quillui_alias_backend_common_env
}

quillui_alias_backend_interaction_env() {
  quillui_alias_env QUILLUI_BACKEND_INTERACTION_MODE QUILLUI_GTK_INTERACTION_MODE
  quillui_alias_env QUILLUI_BACKEND_INTERACTION_DISPLAY QUILLUI_GTK_INTERACTION_DISPLAY
  quillui_alias_env QUILLUI_BACKEND_SCREEN_SIZE QUILLUI_GTK_INTERACTION_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_INTERACTION_SCREEN_SIZE QUILLUI_GTK_INTERACTION_SCREEN_SIZE
  quillui_alias_env QUILLUI_BACKEND_CAPTURE_ROOT QUILLUI_GTK_CAPTURE_ROOT
  quillui_alias_env QUILLUI_BACKEND_POST_CLICK_SLEEP QUILLUI_GTK_POST_CLICK_SLEEP
  quillui_alias_env QUILLUI_BACKEND_FOCUS_PRIME QUILLUI_GTK_FOCUS_PRIME
  quillui_alias_env QUILLUI_BACKEND_FOCUS_PRIME_X QUILLUI_GTK_FOCUS_PRIME_X
  quillui_alias_env QUILLUI_BACKEND_FOCUS_PRIME_Y QUILLUI_GTK_FOCUS_PRIME_Y
  quillui_alias_env QUILLUI_BACKEND_FOCUS_PRIME_SLEEP QUILLUI_GTK_FOCUS_PRIME_SLEEP
  quillui_alias_env QUILLUI_BACKEND_CLICK_X QUILLUI_GTK_CLICK_X
  quillui_alias_env QUILLUI_BACKEND_CLICK_Y QUILLUI_GTK_CLICK_Y
  quillui_alias_env QUILLUI_BACKEND_SETTINGS_CLICK_X QUILLUI_GTK_SETTINGS_CLICK_X
  quillui_alias_env QUILLUI_BACKEND_SETTINGS_CLICK_Y QUILLUI_GTK_SETTINGS_CLICK_Y
  quillui_alias_env QUILLUI_BACKEND_ENDPOINT_CLICK_X QUILLUI_GTK_ENDPOINT_CLICK_X
  quillui_alias_env QUILLUI_BACKEND_ENDPOINT_CLICK_Y QUILLUI_GTK_ENDPOINT_CLICK_Y
  quillui_alias_env QUILLUI_BACKEND_TYPE_TEXT QUILLUI_GTK_TYPE_TEXT
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
      while IFS= read -r product; do
        if [[ "$1" == "$product" ]]; then
          echo "gtk"
          return
        fi
      done < <(quillui_backend_app_products)
      echo ""
      ;;
  esac
}

quillui_backend_profile_matrix() {
  local product
  local backend

  quillui_backend_app_matrix
  while IFS= read -r product; do
    [[ -n "$product" ]] || continue
    backend="$(quillui_backend_for_product "$product")"
    [[ -n "$backend" ]] || continue
    printf '%s\t%s\n' "$product" "$backend"
  done < <(quillui_backend_smoke_products)
}

quillui_requested_backend_for_product() {
  if [[ -n "${QUILLUI_BACKEND:-}" ]]; then
    echo "$QUILLUI_BACKEND"
  else
    quillui_backend_for_product "$1"
  fi
}

quillui_backend_products_usage() {
  cat >&2 <<'MSG'
Usage: quillui-backend-products.sh COMMAND [ARG]

Commands:
  backend-apps                    List user-facing app products in the backend parity matrix.
  app-backends                    List backends requested for each user-facing app.
  app-matrix                      List PRODUCT<TAB>BACKEND visual smoke rows for user-facing apps.
  gtk-apps                        List user-facing app products in the GTK parity matrix.
  smoke-products                  List backend launch smoke products.
  profile-products                List app and launch-smoke products for profile budgets.
  profile-matrix                  List PRODUCT<TAB>BACKEND rows for profile budgets.
  is-smoke-product PRODUCT        Exit 0 when PRODUCT is a backend launch smoke product.
  backend-for-product PRODUCT     Print the default requested backend for PRODUCT.
  requested-backend PRODUCT       Print QUILLUI_BACKEND override or PRODUCT default.
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
    gtk-apps)
      quillui_gtk_app_products
      ;;
    smoke-products)
      quillui_backend_smoke_products
      ;;
    profile-products)
      quillui_backend_profile_products
      ;;
    profile-matrix)
      quillui_backend_profile_matrix
      ;;
    is-smoke-product)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_is_backend_smoke_product "$2"
      ;;
    backend-for-product)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_backend_for_product "$2"
      ;;
    requested-backend)
      if [[ $# -ne 2 ]]; then
        quillui_backend_products_usage
        exit 64
      fi
      quillui_requested_backend_for_product "$2"
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
