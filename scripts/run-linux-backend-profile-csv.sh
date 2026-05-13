#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_SCRIPT="${QUILLUI_BACKEND_PROFILE_COMMAND:-${QUILLUI_GTK_PROFILE_COMMAND:-$ROOT_DIR/scripts/linux-backend-profile.sh}}"
SETTLE_SECONDS="${QUILLUI_BACKEND_PROFILE_SETTLE:-${QUILLUI_GTK_PROFILE_SETTLE:-5}}"
STEADY_DELAY_SECONDS="${QUILLUI_BACKEND_PROFILE_STEADY:-${QUILLUI_GTK_PROFILE_STEADY:-20}}"
CSV_PATH=""
PRODUCTS=()

usage() {
  echo "Usage: $(basename "$0") CSV [PRODUCT ...]" >&2
  echo "       scripts/quillui-backend-products.sh backend-apps | $(basename "$0") CSV" >&2
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
    echo "No products supplied for backend profile CSV" >&2
    usage
    exit 64
  fi
  while IFS= read -r product; do
    [[ -n "$product" ]] || continue
    PRODUCTS+=("$product")
  done
fi

if [[ ${#PRODUCTS[@]} -eq 0 ]]; then
  echo "No products supplied for backend profile CSV" >&2
  usage
  exit 64
fi

if [[ ! -x "$PROFILE_SCRIPT" ]]; then
  echo "Backend profile command is not executable: $PROFILE_SCRIPT" >&2
  exit 66
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quillui-profile-csv.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

{
  echo "product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"
  for product in "${PRODUCTS[@]}"; do
    [[ -n "$product" ]] || continue
    row_path="$TMP_DIR/${product//[^A-Za-z0-9_.-]/_}.csv"
    status=0
    "$PROFILE_SCRIPT" "$product" "$SETTLE_SECONDS" "$STEADY_DELAY_SECONDS" >"$row_path" || status=$?
    if [[ -s "$row_path" ]]; then
      cat "$row_path"
    elif [[ "$status" -eq 0 ]]; then
      echo "$product,0,0,0,0.0,0.0,profiler-empty-output"
    else
      echo "$product,0,0,0,0.0,0.0,profiler-exit-$status"
    fi
  done
} | tee "$CSV_PATH"
