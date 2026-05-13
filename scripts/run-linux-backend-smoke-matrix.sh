#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"

usage() {
  cat >&2 <<'MSG'
Usage: run-linux-backend-smoke-matrix.sh [--dry-run] [--skip-repeated-products] KIND MATRIX_COMMAND OUTPUT_TEMPLATE

KIND:
  visual                         Run scripts/linux-backend-visual-check.sh for each row.
  interaction                    Run scripts/linux-backend-interaction-check.sh for each row.

MATRIX_COMMAND:
  app-matrix                     User-facing app PRODUCT<TAB>BACKEND rows.
  interaction-matrix             User-facing interaction PRODUCT<TAB>BACKEND rows.
  generated-app-matrix           Generated external app PRODUCT<TAB>BACKEND rows.
  smoke-matrix                   Backend launch fixture PRODUCT<TAB>BACKEND rows.
  smoke-interaction-matrix       Backend launch fixture PRODUCT<TAB>BACKEND<TAB>MODE rows.

OUTPUT_TEMPLATE must include {product} and {backend}; mode matrices must also
include {mode}.
Use --skip-repeated-products when consecutive backend rows can reuse one build.
Use --dry-run to print KIND<TAB>PRODUCT<TAB>BACKEND<TAB>OUTPUT<TAB>SKIP_BUILD
and, for mode rows, a trailing MODE column.
MSG
}

DRY_RUN=0
SKIP_REPEATED_PRODUCTS=0

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
  app-matrix|interaction-matrix|generated-app-matrix|smoke-matrix|smoke-interaction-matrix)
    ;;
  *)
    echo "Unsupported backend matrix command: $MATRIX_COMMAND" >&2
    usage
    exit 64
    ;;
esac

if [[ "$OUTPUT_TEMPLATE" != *"{product}"* || "$OUTPUT_TEMPLATE" != *"{backend}"* ]]; then
  echo "OUTPUT_TEMPLATE must include {product} and {backend}: $OUTPUT_TEMPLATE" >&2
  exit 64
fi

if [[ "$MATRIX_COMMAND" == "smoke-interaction-matrix" && "$KIND" != "interaction" ]]; then
  echo "smoke-interaction-matrix is only supported for interaction smokes" >&2
  exit 64
fi

if [[ "$MATRIX_COMMAND" == "smoke-interaction-matrix" && "$OUTPUT_TEMPLATE" != *"{mode}"* ]]; then
  echo "OUTPUT_TEMPLATE must include {mode} for $MATRIX_COMMAND: $OUTPUT_TEMPLATE" >&2
  exit 64
fi

if [[ "$DRY_RUN" != "1" && ! -x "$CHECK_SCRIPT" ]]; then
  echo "Backend smoke command is not executable: $CHECK_SCRIPT" >&2
  exit 66
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

quillui_run_smoke_row() {
  local product="$1"
  local backend="$2"
  local mode="${3:-}"
  local output_path
  local skip_build=0
  local smoke_environment=()

  output_path="$(quillui_smoke_output_path "$product" "$backend" "$mode")"

  if [[ "$SKIP_REPEATED_PRODUCTS" == "1" ]] && quillui_smoke_product_was_built "$product"; then
    smoke_environment+=("QUILLUI_BACKEND_SKIP_BUILD=1")
    skip_build=1
  fi
  if [[ -n "$mode" ]]; then
    smoke_environment+=("QUILLUI_BACKEND_INTERACTION_MODE=$mode")
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ -n "$mode" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$KIND" "$product" "$backend" "$output_path" "$skip_build" "$mode"
    else
      printf '%s\t%s\t%s\t%s\t%s\n' "$KIND" "$product" "$backend" "$output_path" "$skip_build"
    fi
  else
    if [[ -n "$mode" ]]; then
      echo "==> Backend $KIND smoke: $product ($backend requested, $mode mode)"
    else
      echo "==> Backend $KIND smoke: $product ($backend requested)"
    fi
    env "${smoke_environment[@]}" "$CHECK_SCRIPT" "$output_path" "$product" "$backend"
  fi

  if [[ "$SKIP_REPEATED_PRODUCTS" == "1" ]] && ! quillui_smoke_product_was_built "$product"; then
    BUILT_PRODUCTS_LIST="${BUILT_PRODUCTS_LIST}${product}"$'\n'
  fi
}

ROW_COUNT=0
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  if [[ "$row" != *$'\t'* ]]; then
    echo "Backend matrix row is missing a tab separator: $row" >&2
    exit 65
  fi

  IFS=$'\t' read -r product backend mode extra <<< "$row"
  if [[ -n "${extra:-}" ]]; then
    echo "Backend matrix row has too many columns: $row" >&2
    exit 65
  fi
  if [[ "$MATRIX_COMMAND" == "smoke-interaction-matrix" && -z "${mode:-}" ]]; then
    echo "Backend mode matrix row has an empty mode: $row" >&2
    exit 65
  fi
  if [[ "$MATRIX_COMMAND" != "smoke-interaction-matrix" && -n "${mode:-}" ]]; then
    echo "Backend matrix row has an unexpected mode column: $row" >&2
    exit 65
  fi

  backend="$(quillui_backend_identifier_or_raw "$backend")"
  if [[ -z "$product" || -z "$backend" ]]; then
    echo "Backend matrix row has an empty product or backend: $row" >&2
    exit 65
  fi

  quillui_run_smoke_row "$product" "$backend" "${mode:-}"
  ROW_COUNT=$((ROW_COUNT + 1))
done < <("$ROOT_DIR/scripts/quillui-backend-products.sh" "$MATRIX_COMMAND")

if [[ "$ROW_COUNT" -eq 0 ]]; then
  echo "No backend smoke rows listed by scripts/quillui-backend-products.sh $MATRIX_COMMAND" >&2
  exit 65
fi
