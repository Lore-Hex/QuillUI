#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_SCRIPT="${QUILLUI_GTK_PROFILE_COMMAND:-$ROOT_DIR/scripts/linux-gtk-profile.sh}"
SETTLE_SECONDS="${QUILLUI_GTK_PROFILE_SETTLE:-5}"
STEADY_DELAY_SECONDS="${QUILLUI_GTK_PROFILE_STEADY:-20}"
CSV_PATH=""
PRODUCTS=()

usage() {
  echo "Usage: $(basename "$0") CSV [PRODUCT ...]" >&2
  echo "       scripts/linux-gtk-app-products.sh | $(basename "$0") CSV" >&2
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  "")
    usage
    exit 64
    ;;
esac

CSV_PATH="$1"
shift

PRODUCTS=("$@")
if [[ ${#PRODUCTS[@]} -eq 0 ]]; then
  if [[ -t 0 ]]; then
    echo "No products supplied for GTK profile CSV" >&2
    usage
    exit 64
  fi
  while IFS= read -r product; do
    [[ -n "$product" ]] || continue
    PRODUCTS+=("$product")
  done
fi

if [[ ${#PRODUCTS[@]} -eq 0 ]]; then
  echo "No products supplied for GTK profile CSV" >&2
  usage
  exit 64
fi

if [[ ! -x "$PROFILE_SCRIPT" ]]; then
  echo "GTK profile command is not executable: $PROFILE_SCRIPT" >&2
  exit 66
fi

{
  echo "product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"
  for product in "${PRODUCTS[@]}"; do
    [[ -n "$product" ]] || continue
    "$PROFILE_SCRIPT" "$product" "$SETTLE_SECONDS" "$STEADY_DELAY_SECONDS" || true
  done
} | tee "$CSV_PATH"
