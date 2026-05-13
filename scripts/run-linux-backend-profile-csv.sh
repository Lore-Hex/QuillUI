#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"
quillui_alias_backend_profile_env

PROFILE_SCRIPT="${QUILLUI_BACKEND_PROFILE_COMMAND:-$ROOT_DIR/scripts/linux-backend-profile.sh}"
SETTLE_SECONDS="${QUILLUI_BACKEND_PROFILE_SETTLE:-5}"
STEADY_DELAY_SECONDS="${QUILLUI_BACKEND_PROFILE_STEADY:-20}"
CSV_PATH=""
MATRIX_COMMAND=""
ROWS=()

usage() {
  echo "Usage: $(basename "$0") [--matrix profile-matrix] CSV [PRODUCT ...]" >&2
  echo "       scripts/quillui-backend-products.sh profile-matrix | $(basename "$0") CSV" >&2
  echo "       stdin rows may be PRODUCT or PRODUCT<TAB>BACKEND" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --matrix)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--matrix requires a matrix command" >&2
        usage
        exit 64
      fi
      MATRIX_COMMAND="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage
  exit 64
fi

CSV_PATH="$1"
shift

case "$MATRIX_COMMAND" in
  ""|profile-matrix)
    ;;
  *)
    echo "Unsupported backend profile matrix command: $MATRIX_COMMAND" >&2
    usage
    exit 64
    ;;
esac

ROWS=("$@")
if [[ -n "$MATRIX_COMMAND" ]]; then
  if [[ ${#ROWS[@]} -ne 0 ]]; then
    echo "--matrix cannot be combined with explicit product rows" >&2
    usage
    exit 64
  fi
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    ROWS+=("$row")
  done < <("$ROOT_DIR/scripts/quillui-backend-products.sh" "$MATRIX_COMMAND")
elif [[ ${#ROWS[@]} -eq 0 ]]; then
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
  echo "product,requested_backend,runtime_backend,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"
  for row in "${ROWS[@]}"; do
    product="$row"
    backend=""
    requested_backend=""
    runtime_backend=""
    if [[ "$row" == *$'\t'* ]]; then
      product="${row%%$'\t'*}"
      backend="${row#*$'\t'}"
    fi
    [[ -n "$product" ]] || continue
    if [[ "$backend" == *$'\t'* ]]; then
      echo "${product:-profile-row},malformed,unknown,0,0,0,0.0,0.0,profile-row-malformed"
      continue
    fi
    if [[ -n "$backend" ]] && ! backend="$(quillui_require_backend_identifier "$backend" 2>/dev/null)"; then
      echo "$product,unsupported-backend,unknown,0,0,0,0.0,0.0,profile-row-unsupported-backend"
      continue
    fi
    if [[ -n "$backend" ]]; then
      requested_backend="$backend"
    else
      requested_backend="$(quillui_requested_backend_for_product "$product")" || {
        echo "$product,unsupported-backend,unknown,0,0,0,0.0,0.0,profile-row-unsupported-backend"
        continue
      }
    fi
    if [[ -n "$requested_backend" ]]; then
      runtime_backend="$(quillui_runtime_backend_for_backend "$requested_backend")" || {
        echo "$product,$requested_backend,unknown,0,0,0,0.0,0.0,profile-row-unsupported-runtime-backend"
        continue
      }
    fi
    row_label="$product"
    profiler_arguments=("$product" "$SETTLE_SECONDS" "$STEADY_DELAY_SECONDS")
    if [[ -n "$backend" ]]; then
      row_label="$product@$backend"
      profiler_arguments+=("$backend")
    fi
    row_path="$TMP_DIR/${row_label//[^A-Za-z0-9_.-]/_}.csv"
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
      awk \
        -v product="$product" \
        -v requested_backend="$requested_backend" \
        -v runtime_backend="$runtime_backend" \
        -v profiler_status="$status" '
        BEGIN { FS = OFS = "," }
        NF == 7 {
          exit_status = $7
          if (profiler_status != 0) {
            exit_status = "profiler-exit-" profiler_status
          }
          print product, requested_backend, runtime_backend, $2, $3, $4, $5, $6, exit_status
          next
        }
        NF >= 9 {
          $1 = product
          $2 = requested_backend
          $3 = runtime_backend
          if (profiler_status != 0) {
            $9 = "profiler-exit-" profiler_status
          }
          print
          next
        }
        NF > 0 {
          exit_status = "profiler-malformed-output"
          if (profiler_status != 0) {
            exit_status = "profiler-exit-" profiler_status
          }
          print product, requested_backend, runtime_backend, 0, 0, 0, "0.0", "0.0", exit_status
        }
      ' "$row_path"
    elif [[ "$status" -eq 0 ]]; then
      echo "$product,$requested_backend,$runtime_backend,0,0,0,0.0,0.0,profiler-empty-output"
    else
      echo "$product,$requested_backend,$runtime_backend,0,0,0,0.0,0.0,profiler-exit-$status"
    fi
  done
} | tee "$CSV_PATH"
