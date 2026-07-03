#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"
source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

usage() {
  cat >&2 <<'MSG'
Usage: run-linux-backend-smoke-matrix.sh [--dry-run] [--skip-repeated-products] KIND MATRIX_COMMAND OUTPUT_TEMPLATE

KIND:
  visual                         Run scripts/linux-backend-visual-check.sh for each row.
  interaction                    Run scripts/linux-backend-interaction-check.sh for each row.

MATRIX_COMMAND:
  app-matrix                     User-facing app PRODUCT<TAB>BACKEND rows.
  interaction-matrix             User-facing interaction PRODUCT<TAB>BACKEND rows.
  interaction-extra-mode-matrix  Semantic app interaction PRODUCT<TAB>BACKEND<TAB>MODE rows.
  generated-app-matrix           Generated external app PRODUCT<TAB>BACKEND rows.
  smoke-matrix                   Backend launch fixture PRODUCT<TAB>BACKEND rows.
  smoke-interaction-matrix       Backend launch fixture PRODUCT<TAB>BACKEND<TAB>MODE rows.

The runner expands these through the shared runtime matrix helpers before
launching checks, so every row carries requested backend, runtime backend, and
native/fallback mode from one registry.

OUTPUT_TEMPLATE must include {product} and {backend}; mode matrices must also
include {mode}.
Use --skip-repeated-products when consecutive backend rows can reuse one build.
Generated app rows reuse per backend facade so GTK and Qt launchers both build.
Use --dry-run to print
KIND<TAB>PRODUCT<TAB>REQUESTED_BACKEND<TAB>RUNTIME_BACKEND<TAB>RUNTIME_MODE<TAB>OUTPUT<TAB>SKIP_BUILD
and a trailing VERIFY_PRODUCT column. Mode rows place MODE before VERIFY_PRODUCT.
MSG
}

DRY_RUN=0
SKIP_REPEATED_PRODUCTS=0
# The per-row budget below wraps the product's COLD `swift build` as well as the
# smoke launch (CHECK_SCRIPT builds, then runs). The largest generated apps
# (QuillCodeApp ~1580 modules, GeneratedSwiftUILinuxApp ~1800) cold-build right at
# ~10 minutes and were being SIGTERM'd at ~99% compiled (exit 124) on loaded CI
# runners, intermittently reddening main. Give the cold build ample headroom: this
# only affects the failure/hang path (a genuinely hung smoke is still bounded, and a
# crash exits fast with a signal code, never 124), so raising it costs nothing on
# passing runs while removing the flake.
SMOKE_ROW_TIMEOUT="${QUILLUI_BACKEND_SMOKE_ROW_TIMEOUT:-20m}"
SMOKE_ROW_KILL_AFTER="${QUILLUI_BACKEND_SMOKE_ROW_KILL_AFTER:-15s}"
SMOKE_TIMEOUT_COMMAND=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-repeated-products)
      SKIP_REPEATED_PRODUCTS=1
      shift
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

if [[ $# -ne 3 ]]; then
  usage
  exit 64
fi

KIND="$1"
MATRIX_COMMAND="$2"
OUTPUT_TEMPLATE="$3"

case "$KIND" in
  visual)
    CHECK_SCRIPT="$ROOT_DIR/scripts/linux-backend-visual-check.sh"
    ;;
  interaction)
    CHECK_SCRIPT="$ROOT_DIR/scripts/linux-backend-interaction-check.sh"
    ;;
  *)
    echo "Unsupported smoke kind: $KIND" >&2
    usage
    exit 64
    ;;
esac

case "$MATRIX_COMMAND" in
  app-matrix|interaction-matrix|interaction-extra-mode-matrix|generated-app-matrix|smoke-matrix|smoke-interaction-matrix)
    ;;
  *)
    echo "Unsupported backend matrix command: $MATRIX_COMMAND" >&2
    usage
    exit 64
    ;;
esac

quillui_smoke_runtime_matrix_command() {
  case "$1" in
    app-matrix)
      echo "app-runtime-matrix"
      ;;
    interaction-matrix)
      echo "interaction-runtime-matrix"
      ;;
    interaction-extra-mode-matrix)
      echo "interaction-extra-mode-runtime-matrix"
      ;;
    generated-app-matrix)
      echo "generated-app-runtime-matrix"
      ;;
    smoke-matrix)
      echo "smoke-runtime-matrix"
      ;;
    smoke-interaction-matrix)
      echo "smoke-interaction-runtime-matrix"
      ;;
    *)
      return 64
      ;;
  esac
}

quillui_smoke_matrix_has_mode_column() {
  case "$1" in
    interaction-extra-mode-matrix|smoke-interaction-matrix)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

RUNTIME_MATRIX_COMMAND="$(quillui_smoke_runtime_matrix_command "$MATRIX_COMMAND")"

if [[ "$OUTPUT_TEMPLATE" != *"{product}"* || "$OUTPUT_TEMPLATE" != *"{backend}"* ]]; then
  echo "OUTPUT_TEMPLATE must include {product} and {backend}: $OUTPUT_TEMPLATE" >&2
  exit 64
fi

if quillui_smoke_matrix_has_mode_column "$MATRIX_COMMAND" && [[ "$KIND" != "interaction" ]]; then
  echo "$MATRIX_COMMAND is only supported for interaction smokes" >&2
  exit 64
fi

if quillui_smoke_matrix_has_mode_column "$MATRIX_COMMAND" && [[ "$OUTPUT_TEMPLATE" != *"{mode}"* ]]; then
  echo "OUTPUT_TEMPLATE must include {mode} for $MATRIX_COMMAND: $OUTPUT_TEMPLATE" >&2
  exit 64
fi

if [[ "$DRY_RUN" != "1" && ! -x "$CHECK_SCRIPT" ]]; then
  echo "Backend smoke command is not executable: $CHECK_SCRIPT" >&2
  exit 66
fi

if [[ "$DRY_RUN" != "1" ]]; then
  "$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"
  timeout_command="${QUILLUI_BACKEND_SMOKE_TIMEOUT_COMMAND:-}"
  if [[ -z "$timeout_command" ]]; then
    if command -v timeout >/dev/null 2>&1; then
      timeout_command="timeout"
    elif command -v gtimeout >/dev/null 2>&1; then
      timeout_command="gtimeout"
    fi
  fi
  if [[ -n "$timeout_command" ]]; then
    SMOKE_TIMEOUT_COMMAND=("$timeout_command" "--kill-after=$SMOKE_ROW_KILL_AFTER" "$SMOKE_ROW_TIMEOUT")
  fi
fi

BUILT_PRODUCTS_LIST=$'\n'

quillui_smoke_product_was_built() {
  local candidate="$1"

  case "$BUILT_PRODUCTS_LIST" in
    *$'\n'"$candidate"$'\n'*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

quillui_smoke_build_cache_key() {
  local product="$1"
  local requested_backend="$2"
  local runtime_backend="${3:-}"

  if quillui_is_backend_generated_app_product "$product"; then
    printf '%s:%s\n' "$product" "$requested_backend"
  elif [[ -n "$runtime_backend" ]]; then
    printf '%s:%s\n' "$product" "$runtime_backend"
  else
    printf '%s\n' "$product"
  fi
}

quillui_smoke_output_path() {
  local product="$1"
  local backend="$2"
  local mode="${3:-}"
  local output_path="$OUTPUT_TEMPLATE"

  output_path="${output_path//\{product\}/$product}"
  output_path="${output_path//\{backend\}/$backend}"
  output_path="${output_path//\{mode\}/$mode}"
  printf '%s\n' "$output_path"
}

quillui_print_tabbed() {
  local separator=""
  local value

  for value in "$@"; do
    printf '%s%s' "$separator" "$value"
    separator=$'\t'
  done
  printf '\n'
}

quillui_smoke_visual_verify_product() {
  local product="$1"
  local requested_backend="$2"
  local verify_product

  verify_product="$(
    set -e
    quillui_runner_verify_product=""
    QUILLUI_BACKEND="$requested_backend"
    quillui_backend_visual_verify_product "$product" quillui_runner_verify_product
    printf '%s\n' "$quillui_runner_verify_product"
  )"
  printf '%s\n' "$verify_product"
}

quillui_smoke_interaction_verify_product() {
  local product="$1"
  local requested_backend="$2"
  local interaction_mode="${3:-click}"
  local verify_product

  verify_product="$(
    set -e
    quillui_runner_verify_product=""
    QUILLUI_BACKEND="$requested_backend"
    quillui_backend_interaction_verify_product "$product" "$interaction_mode" quillui_runner_verify_product
    printf '%s\n' "$quillui_runner_verify_product"
  )"
  printf '%s\n' "$verify_product"
}

quillui_run_smoke_row() {
  local product="$1"
  local requested_backend="$2"
  local runtime_backend="$3"
  local runtime_mode="$4"
  local mode="${5:-}"
  local output_path
  local skip_build=0
  local build_cache_key
  local verify_product=""
  local smoke_environment=()
  local smoke_command=()

  output_path="$(quillui_smoke_output_path "$product" "$requested_backend" "$mode")"
  build_cache_key="$(quillui_smoke_build_cache_key "$product" "$requested_backend" "$runtime_backend")"

  if [[ "$SKIP_REPEATED_PRODUCTS" == "1" ]] && quillui_smoke_product_was_built "$build_cache_key"; then
    smoke_environment+=("QUILLUI_BACKEND_SKIP_BUILD=1")
    skip_build=1
  fi
  if quillui_is_backend_generated_app_product "$product"; then
    smoke_environment+=("QUILLUI_APP_BACKEND_FACADE=$requested_backend")
  fi
  if [[ -n "$mode" ]]; then
    smoke_environment+=("QUILLUI_BACKEND_INTERACTION_MODE=$mode")
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    local dry_run_fields=("$KIND" "$product" "$requested_backend" "$runtime_backend" "$runtime_mode" "$output_path" "$skip_build")
    if [[ -n "$mode" ]]; then
      dry_run_fields+=("$mode")
    fi
    if [[ "$KIND" == "visual" ]]; then
      verify_product="$(quillui_smoke_visual_verify_product "$product" "$requested_backend")"
      dry_run_fields+=("$verify_product")
    elif [[ "$KIND" == "interaction" ]]; then
      verify_product="$(quillui_smoke_interaction_verify_product "$product" "$requested_backend" "$mode")"
      dry_run_fields+=("$verify_product")
    fi
    quillui_print_tabbed "${dry_run_fields[@]}"
  else
    if [[ -n "$mode" ]]; then
      echo "==> Backend $KIND smoke: $product ($requested_backend requested, $runtime_backend runtime, $runtime_mode mode, $mode interaction)"
    else
      echo "==> Backend $KIND smoke: $product ($requested_backend requested, $runtime_backend runtime, $runtime_mode mode)"
    fi
    smoke_command=(env "${smoke_environment[@]}" "$CHECK_SCRIPT" "$output_path" "$product" "$requested_backend")
    if (( ${#SMOKE_TIMEOUT_COMMAND[@]} > 0 )); then
      "${SMOKE_TIMEOUT_COMMAND[@]}" "${smoke_command[@]}"
    else
      "${smoke_command[@]}"
    fi
  fi

  if [[ "$SKIP_REPEATED_PRODUCTS" == "1" ]] && ! quillui_smoke_product_was_built "$build_cache_key"; then
    BUILT_PRODUCTS_LIST="${BUILT_PRODUCTS_LIST}${build_cache_key}"$'\n'
  fi
}

ROW_COUNT=0
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  if [[ "$row" != *$'\t'* ]]; then
    echo "Backend matrix row is missing a tab separator: $row" >&2
    exit 65
  fi

  IFS=$'\t' read -r product backend runtime_backend runtime_mode mode extra <<< "$row"
  if [[ -n "${extra:-}" ]]; then
    echo "Backend runtime matrix row has too many columns: $row" >&2
    exit 65
  fi
  if quillui_smoke_matrix_has_mode_column "$MATRIX_COMMAND" && [[ -z "${mode:-}" ]]; then
    echo "Backend mode runtime matrix row has an empty mode: $row" >&2
    exit 65
  fi
  if ! quillui_smoke_matrix_has_mode_column "$MATRIX_COMMAND" && [[ -n "${mode:-}" ]]; then
    echo "Backend runtime matrix row has an unexpected mode column: $row" >&2
    exit 65
  fi

  if [[ -z "$product" || -z "$backend" || -z "$runtime_backend" || -z "$runtime_mode" ]]; then
    echo "Backend runtime matrix row has an empty product, backend, runtime backend, or runtime mode: $row" >&2
    exit 65
  fi
  if ! runtime_availability="$(quillui_backend_validate_runtime_availability_for_product "$product" "$backend" "$runtime_backend" "$runtime_mode")"; then
    echo "Backend runtime matrix row has invalid runtime availability: $row" >&2
    exit 65
  fi
  IFS=$'\t' read -r backend runtime_backend runtime_mode <<<"$runtime_availability"

  quillui_run_smoke_row "$product" "$backend" "$runtime_backend" "$runtime_mode" "${mode:-}"
  ROW_COUNT=$((ROW_COUNT + 1))
done < <("$ROOT_DIR/scripts/quillui-backend-products.sh" "$RUNTIME_MATRIX_COMMAND")

if [[ "$ROW_COUNT" -eq 0 ]]; then
  echo "No backend smoke rows listed by scripts/quillui-backend-products.sh $RUNTIME_MATRIX_COMMAND" >&2
  exit 65
fi
