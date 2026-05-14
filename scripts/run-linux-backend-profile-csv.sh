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
  echo "Usage: $(basename "$0") [--matrix profile-matrix|profile-runtime-matrix] CSV [PRODUCT ...]" >&2
  echo "       scripts/quillui-backend-products.sh profile-matrix | $(basename "$0") CSV" >&2
  echo "       stdin rows may be PRODUCT, PRODUCT<TAB>BACKEND, or PRODUCT<TAB>BACKEND<TAB>RUNTIME<TAB>MODE" >&2
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
  ""|profile-matrix|profile-runtime-matrix)
    ;;
  *)
    echo "Unsupported backend profile matrix command: $MATRIX_COMMAND" >&2
    usage
    exit 64
    ;;
esac

ROWS=("$@")
if [[ -n "$MATRIX_COMMAND" ]]; then
  RUNTIME_MATRIX_COMMAND="$MATRIX_COMMAND"
  if [[ "$RUNTIME_MATRIX_COMMAND" == "profile-matrix" ]]; then
    RUNTIME_MATRIX_COMMAND="profile-runtime-matrix"
  fi
  if [[ ${#ROWS[@]} -ne 0 ]]; then
    echo "--matrix cannot be combined with explicit product rows" >&2
    usage
    exit 64
  fi
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    ROWS+=("$row")
  done < <("$ROOT_DIR/scripts/quillui-backend-products.sh" "$RUNTIME_MATRIX_COMMAND")
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

quillui_profile_build_cache_key() {
  local product="$1"
  local requested_backend="$2"
  local runtime_backend="${3:-}"

  if [[ -n "$requested_backend" ]] && quillui_is_backend_generated_app_product "$product"; then
    printf '%s:%s\n' "$product" "$requested_backend"
  elif [[ -n "$runtime_backend" ]]; then
    printf '%s:%s\n' "$product" "$runtime_backend"
  else
    printf '%s\n' "$product"
  fi
}

{
  echo "product,requested_backend,runtime_backend,runtime_mode,build_ms,startup_ms,rss_kb,cpu_pct_initial,cpu_pct_steady,exit_status"
  for row in "${ROWS[@]}"; do
    product="$row"
    backend=""
    requested_backend=""
    runtime_backend=""
    runtime_mode=""
    provided_runtime_backend=""
    provided_runtime_mode=""
    extra=""
    if [[ "$row" == *$'\t'* ]]; then
      IFS=$'\t' read -r product backend provided_runtime_backend provided_runtime_mode extra <<<"$row"
    fi
    [[ -n "$product" ]] || continue
    if [[ -n "${extra:-}" ]]; then
      echo "${product:-profile-row},malformed,unknown,unknown,0,0,0,0.0,0.0,profile-row-malformed"
      continue
    fi
    if [[ -n "$backend" ]] && ! backend="$(quillui_require_backend_identifier "$backend" 2>/dev/null)"; then
      echo "$product,unsupported-backend,unknown,unknown,0,0,0,0.0,0.0,profile-row-unsupported-backend"
      continue
    fi
    if [[ -n "$backend" ]]; then
      requested_backend="$backend"
    else
      requested_backend="$(quillui_requested_backend_for_product "$product")" || {
        echo "$product,unsupported-backend,unknown,unknown,0,0,0,0.0,0.0,profile-row-unsupported-backend"
        continue
      }
    fi
    if [[ -n "$requested_backend" ]]; then
      if [[ -n "$provided_runtime_backend" || -n "$provided_runtime_mode" ]]; then
        if [[ -z "$provided_runtime_backend" || -z "$provided_runtime_mode" ]]; then
          echo "$product,$requested_backend,unknown,unknown,0,0,0,0.0,0.0,profile-row-malformed"
          continue
        fi
        if ! provided_runtime_backend="$(quillui_require_backend_identifier "$provided_runtime_backend" 2>/dev/null)"; then
          echo "$product,$requested_backend,unknown,unknown,0,0,0,0.0,0.0,profile-row-unsupported-runtime-backend"
          continue
        fi
        if ! runtime_availability="$(quillui_backend_validate_runtime_availability_for_product "$product" "$requested_backend" "$provided_runtime_backend" "$provided_runtime_mode" 2>&1)"; then
          if [[ "$runtime_availability" == runtime_backend=* ]]; then
            echo "$product,$requested_backend,$provided_runtime_backend,$provided_runtime_mode,0,0,0,0.0,0.0,profile-row-runtime-backend-mismatch"
          else
            echo "$product,$requested_backend,$provided_runtime_backend,$provided_runtime_mode,0,0,0,0.0,0.0,profile-row-runtime-mode-mismatch"
          fi
          continue
        fi
        IFS=$'\t' read -r requested_backend runtime_backend runtime_mode <<<"$runtime_availability"
      else
        runtime_availability="$(quillui_backend_runtime_availability_for_product "$product" "$requested_backend")" || {
          echo "$product,$requested_backend,unknown,unknown,0,0,0,0.0,0.0,profile-row-unsupported-runtime-backend"
          continue
        }
        IFS=$'\t' read -r requested_backend runtime_backend runtime_mode <<<"$runtime_availability"
      fi
    fi
    row_label="$product"
    profiler_arguments=("$product" "$SETTLE_SECONDS" "$STEADY_DELAY_SECONDS")
    if [[ -n "$backend" ]]; then
      row_label="$product@$backend"
      profiler_arguments+=("$backend")
    fi
    build_cache_key="$(quillui_profile_build_cache_key "$product" "$requested_backend" "$runtime_backend")"
    row_path="$TMP_DIR/${row_label//[^A-Za-z0-9_.-]/_}.csv"
    profiler_environment=()
    if [[ -n "$backend" ]]; then
      profiler_environment+=("QUILLUI_BACKEND=$backend")
    fi
    if [[ -n "$requested_backend" ]] && quillui_is_backend_generated_app_product "$product"; then
      profiler_environment+=("QUILLUI_APP_BACKEND_FACADE=$requested_backend")
    fi
    if quillui_profile_product_was_built "$build_cache_key"; then
      profiler_environment+=("QUILLUI_BACKEND_SKIP_BUILD=1")
    fi
    profile_command=(env)
    if (( ${#profiler_environment[@]} > 0 )); then
      profile_command+=("${profiler_environment[@]}")
    fi
    status=0
    "${profile_command[@]}" "$PROFILE_SCRIPT" "${profiler_arguments[@]}" >"$row_path" || status=$?
    if [[ "$status" -eq 0 ]] && ! quillui_profile_product_was_built "$build_cache_key"; then
      BUILT_PROFILE_PRODUCTS_LIST="${BUILT_PROFILE_PRODUCTS_LIST}${build_cache_key}"$'\n'
    fi
    if [[ -s "$row_path" ]]; then
      awk \
        -v product="$product" \
        -v requested_backend="$requested_backend" \
        -v runtime_backend="$runtime_backend" \
        -v runtime_mode="$runtime_mode" \
        -v profiler_status="$status" '
        BEGIN { FS = OFS = "," }
        NF == 7 {
          exit_status = $7
          if (profiler_status != 0) {
            exit_status = "profiler-exit-" profiler_status
          }
          print product, requested_backend, runtime_backend, runtime_mode, $2, $3, $4, $5, $6, exit_status
          next
        }
        NF == 9 {
          exit_status = $9
          if (profiler_status != 0) {
            exit_status = "profiler-exit-" profiler_status
          }
          print product, requested_backend, runtime_backend, runtime_mode, $4, $5, $6, $7, $8, exit_status
          next
        }
        NF >= 10 {
          exit_status = $10
          if (profiler_status != 0) {
            exit_status = "profiler-exit-" profiler_status
          }
          print product, requested_backend, runtime_backend, runtime_mode, $5, $6, $7, $8, $9, exit_status
          next
        }
        NF > 0 {
          exit_status = "profiler-malformed-output"
          if (profiler_status != 0) {
            exit_status = "profiler-exit-" profiler_status
          }
          print product, requested_backend, runtime_backend, runtime_mode, 0, 0, 0, "0.0", "0.0", exit_status
        }
      ' "$row_path"
    elif [[ "$status" -eq 0 ]]; then
      echo "$product,$requested_backend,$runtime_backend,$runtime_mode,0,0,0,0.0,0.0,profiler-empty-output"
    else
      echo "$product,$requested_backend,$runtime_backend,$runtime_mode,0,0,0,0.0,0.0,profiler-exit-$status"
    fi
  done
} | tee "$CSV_PATH"
