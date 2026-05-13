#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"
quillui_alias_backend_profile_env

PROFILE_SCRIPT="${QUILLUI_BACKEND_PROFILE_COMMAND:-$ROOT_DIR/scripts/linux-backend-profile.sh}"
SETTLE_SECONDS="${QUILLUI_BACKEND_PROFILE_SETTLE:-5}"
STEADY_DELAY_SECONDS="${QUILLUI_BACKEND_PROFILE_STEADY:-20}"
CSV_PATH=""
ROWS=()

usage() {
  echo "Usage: $(basename "$0") CSV [PRODUCT ...]" >&2
  echo "       scripts/quillui-backend-products.sh profile-matrix | $(basename "$0") CSV" >&2
  echo "       stdin rows may be PRODUCT or PRODUCT<TAB>BACKEND" >&2
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

ROWS=("$@")
if [[ ${#ROWS[@]} -eq 0 ]]; then
  if [[ -t 0 ]]; then
    echo "No products supplied for backend profile CSV" >&2
    usage
    exit 64
  fi
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    ROWS+=("$row")
  done
fi

if [[ ${#ROWS[@]} -eq 0 ]]; then
  echo "No products supplied for backend profile CSV" >&2
  usage
  exit 64
fi

if [[ ! -x "$PROFILE_SCRIPT" ]]; then
  echo "Backend profile command is not executable: $PROFILE_SCRIPT" >&2
  exit 66
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/quillui-profile-csv.XXXXXX")"
BUILT_PROFILE_PRODUCTS_LIST=$'\n'
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

quillui_profile_product_was_built() {
  local candidate="$1"

  case "$BUILT_PROFILE_PRODUCTS_LIST" in
    *$'\n'"$candidate"$'\n'*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

{
  echo "product,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"
  for row in "${ROWS[@]}"; do
    product="$row"
    backend=""
    if [[ "$row" == *$'\t'* ]]; then
      product="${row%%$'\t'*}"
      backend="${row#*$'\t'}"
    fi
    if [[ -n "$backend" ]]; then
      backend="$(quillui_backend_identifier_or_raw "$backend")"
    fi
    [[ -n "$product" ]] || continue
    if [[ "$backend" == *$'\t'* ]]; then
      label="${product:-profile-row}@malformed"
      echo "$label,0,0,0,0.0,0.0,profile-row-malformed"
      continue
    fi
    label="$product"
    profiler_arguments=("$product" "$SETTLE_SECONDS" "$STEADY_DELAY_SECONDS")
    if [[ -n "$backend" ]]; then
      label="$product@$backend"
      profiler_arguments+=("$backend")
    fi
    row_path="$TMP_DIR/${label//[^A-Za-z0-9_.-]/_}.csv"
    profiler_environment=()
    if [[ -n "$backend" ]]; then
      profiler_environment+=("QUILLUI_BACKEND=$backend")
    fi
    if quillui_profile_product_was_built "$product"; then
      profiler_environment+=("QUILLUI_BACKEND_SKIP_BUILD=1")
    fi
    profile_command=(env)
    if (( ${#profiler_environment[@]} > 0 )); then
      profile_command+=("${profiler_environment[@]}")
    fi
    status=0
    "${profile_command[@]}" "$PROFILE_SCRIPT" "${profiler_arguments[@]}" >"$row_path" || status=$?
    if [[ "$status" -eq 0 ]] && ! quillui_profile_product_was_built "$product"; then
      BUILT_PROFILE_PRODUCTS_LIST="${BUILT_PROFILE_PRODUCTS_LIST}${product}"$'\n'
    fi
    if [[ -s "$row_path" ]]; then
      awk -v label="$label" 'BEGIN { FS = OFS = "," } NF > 0 { $1 = label } { print }' "$row_path"
    elif [[ "$status" -eq 0 ]]; then
      echo "$label,0,0,0,0.0,0.0,profiler-empty-output"
    else
      echo "$label,0,0,0,0.0,0.0,profiler-exit-$status"
    fi
  done
} | tee "$CSV_PATH"
