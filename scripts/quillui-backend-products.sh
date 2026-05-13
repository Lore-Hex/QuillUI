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

quillui_alias_env() {
  local canonical="$1"
  local legacy="$2"

  if [[ -n "${!canonical:-}" ]]; then
    printf -v "$legacy" "%s" "${!canonical}"
  fi
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
  gtk-apps                        List user-facing app products in the GTK parity matrix.
  smoke-products                  List backend launch smoke products.
  profile-products                List app and launch-smoke products for profile budgets.
  backend-for-product PRODUCT     Print the default requested backend for PRODUCT.
  requested-backend PRODUCT       Print QUILLUI_BACKEND override or PRODUCT default.
MSG
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    backend-apps)
      quillui_backend_app_products
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
