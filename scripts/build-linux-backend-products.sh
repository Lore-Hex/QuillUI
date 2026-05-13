#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null
  pwd
)"

source "$ROOT_DIR/scripts/quillui-backend-products.sh"

SCRATCH_PATH="${QUILLUI_LINUX_BUILD_SCRATCH_PATH:-.build-linux}"
DRY_RUN=0
MATRIX_COMMAND="fixed-app-backends"
MATRIX_COMMAND_SET=0

usage() {
  cat <<'USAGE'
Usage: scripts/build-linux-backend-products.sh [--dry-run] [--scratch-path PATH] [MATRIX]

Build root SwiftPM products with the manifest-time Linux backend selected by
scripts/quillui-backend-products.sh. The build plan compiles each product once,
even when the runtime smoke matrix requests both GTK and Qt rows.

Matrices:
  fixed-app-backends  Backend-specific app products only. Default.
  backend-apps        User-facing app products, one manifest backend each.
  app-matrix          User-facing runtime smoke matrix, collapsed by product.
  interaction-matrix  User-facing interaction matrix, collapsed by product.
  smoke-matrix        Backend launch fixture products.

Options:
  --dry-run           Print PRODUCT<TAB>BUILD_BACKEND rows without building.
  --scratch-path PATH Forward PATH to swift build --scratch-path.
  -h, --help          Show this help.
USAGE
}

fail_usage() {
  echo "$1" >&2
  echo >&2
  usage >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --scratch-path)
      [[ $# -ge 2 ]] || fail_usage "--scratch-path requires a value."
      SCRATCH_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      fail_usage "Unsupported option: $1"
      ;;
    *)
      if [[ "$MATRIX_COMMAND_SET" == "1" ]]; then
        fail_usage "Only one matrix command may be provided."
      fi
      MATRIX_COMMAND="$1"
      MATRIX_COMMAND_SET=1
      shift
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  if [[ "$MATRIX_COMMAND_SET" == "1" || $# -gt 1 ]]; then
    fail_usage "Only one matrix command may be provided."
  fi
  MATRIX_COMMAND="$1"
  MATRIX_COMMAND_SET=1
fi

quillui_manifest_product_rows() {
  case "$1" in
    fixed-app-backends)
      quillui_backend_fixed_app_backend_overrides
      ;;
    backend-apps)
      local product
      local backend
      while IFS= read -r product; do
        [[ -n "$product" ]] || continue
        backend="$(quillui_require_backend_for_product "$product")" || return $?
        printf '%s\t%s\n' "$product" "$backend"
      done < <(quillui_backend_app_products)
      ;;
    app-matrix)
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

quillui_manifest_backend_for_product_row() {
  local product="$1"
  local requested_backend="${2:-}"
  local manifest_backend
  local normalized_requested_backend

  manifest_backend="$(quillui_require_backend_for_product "$product")" || return $?
  if [[ -n "$requested_backend" ]]; then
    normalized_requested_backend="$(quillui_require_backend_identifier "$requested_backend")" || return $?
    if [[ "$MATRIX_COMMAND" == "fixed-app-backends" && "$normalized_requested_backend" != "$manifest_backend" ]]; then
      echo "Backend product build matrix drifted for $product: listed $normalized_requested_backend, manifest requires $manifest_backend" >&2
      return 65
    fi
  fi

  echo "$manifest_backend"
}

quillui_absolute_scratch_path() {
  case "$SCRATCH_PATH" in
    /*)
      echo "$SCRATCH_PATH"
      ;;
    *)
      echo "$ROOT_DIR/$SCRATCH_PATH"
      ;;
  esac
}

SEEN_PRODUCTS=$'\n'
ROW_COUNT=0
BUILD_COUNT=0

if [[ "$DRY_RUN" != "1" ]]; then
  "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$(quillui_absolute_scratch_path)"
fi

while IFS=$'\t' read -r product requested_backend extra; do
  [[ -n "$product" ]] || continue
  if [[ -n "${extra:-}" ]]; then
    echo "Backend product build row has too many columns: $product	$requested_backend	$extra" >&2
    exit 65
  fi

  ROW_COUNT=$((ROW_COUNT + 1))
  if [[ "$SEEN_PRODUCTS" == *$'\n'"$product"$'\n'* ]]; then
    continue
  fi
  SEEN_PRODUCTS="${SEEN_PRODUCTS}${product}"$'\n'

  build_backend="$(quillui_manifest_backend_for_product_row "$product" "$requested_backend")" || exit $?
  BUILD_COUNT=$((BUILD_COUNT + 1))

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s\t%s\n' "$product" "$build_backend"
  else
    echo "==> Build $product (QUILLUI_LINUX_BACKEND=$build_backend)"
    (
      cd "$ROOT_DIR"
      QUILLUI_LINUX_BACKEND="$build_backend" \
        swift build --scratch-path "$SCRATCH_PATH" --product "$product"
    )
  fi
done < <(quillui_manifest_product_rows "$MATRIX_COMMAND")

if [[ "$ROW_COUNT" -eq 0 ]]; then
  echo "No backend product build rows listed for $MATRIX_COMMAND" >&2
  exit 65
fi

if [[ "$DRY_RUN" != "1" ]]; then
  echo "Built $BUILD_COUNT Linux backend product(s) from $ROW_COUNT $MATRIX_COMMAND row(s)."
fi
