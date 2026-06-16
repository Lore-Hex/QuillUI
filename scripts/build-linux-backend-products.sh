#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null
  pwd
)"

source "$ROOT_DIR/scripts/quillui-backend-products.sh"

SCRATCH_PATH="${QUILLUI_LINUX_BUILD_SCRATCH_PATH:-.build-linux}"
DRY_RUN=0
MATRIX_COMMAND="backend-apps"
MATRIX_COMMAND_SET=0

usage() {
  cat <<'USAGE'
Usage: scripts/build-linux-backend-products.sh [--dry-run] [--scratch-path PATH] [MATRIX]

Build root SwiftPM products with the manifest-time Linux backend selected by
scripts/quillui-backend-products.sh. The build plan compiles product/backend
pairs so canonical app products exercise both mutually exclusive Linux graphs.

Matrices:
  backend-apps        User-facing app products for every app backend. Default.
  all-app-backends    Alias for backend-apps.
  app-matrix          User-facing runtime smoke matrix.
  interaction-matrix  User-facing interaction matrix.
  fixed-app-backends  Products constrained to one build backend, if any.
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

quillui_manifest_backend_for_product_row() {
  local product="$1"
  local requested_backend="${2:-}"
  local manifest_backend
  local normalized_requested_backend

  if [[ -n "$requested_backend" ]]; then
    quillui_validate_requested_backend_for_product "$product" "$requested_backend" >/dev/null || return $?
    manifest_backend="$(quillui_require_linux_build_backend_identifier "$requested_backend")" || return $?
  else
    manifest_backend="$(quillui_require_backend_for_product "$product")" || return $?
    manifest_backend="$(quillui_require_linux_build_backend_identifier "$manifest_backend")" || return $?
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

quillui_build_backend_product() {
  local product="$1"
  local build_backend="$2"
  local output

  if ! output="$(
    cd "$ROOT_DIR"
    QUILLUI_LINUX_BACKEND="$build_backend" \
      "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
      swift build --scratch-path "$SCRATCH_PATH" --product "$product" 2>&1
  )"; then
    printf '%s\n' "$output"
    return 1
  fi

  printf '%s\n' "$output"

  # Gate the canonical Qt app product on warnings IN ITS OWN first-party code.
  # Scope to compiler diagnostics with a `<path>.swift:line:col: warning:`
  # location, then drop `third_party/` — the vendored SwiftOpenUI backend
  # carries inherent Swift-5-vs-6 (Sendable/same-type) and GTK-deprecation
  # warnings that are not this product's to fix, and gating on them just wedges
  # every canonical product. Package-manifest noise (unhandled-files notices,
  # "ignoring duplicate product", unused-dependency, pkg-config prohibited
  # flags) has no source location and is likewise excluded here — the dedicated
  # SourceHygiene manifest tests guard those. `Invalid Exclude` IS a real
  # first-party Package.swift error, so it still fails.
  if [[ "$build_backend" == "qt" ]]; then
    local product_warnings
    # `|| true` on both greps: under `set -euo pipefail` a no-match grep exits
    # 1, and the clean case (no first-party warnings) leaves grep -v with
    # nothing to emit — without this the success path would itself abort the
    # script. Keep the filter robust to an empty result.
    product_warnings="$(
      { grep -E '\.swift:[0-9]+:[0-9]+: warning:|Invalid Exclude' <<<"$output" || true; } \
        | { grep -v 'third_party/' || true; }
    )"
    if [[ -n "$product_warnings" ]]; then
      echo "Qt backend build for $product emitted first-party warnings; canonical Qt app products must stay warning-clean:" >&2
      printf '%s\n' "$product_warnings" >&2
      return 1
    fi
  fi
}

quillui_prepare_backend_once() {
  local build_backend="$1"
  local prepared_key=$'\n'"$build_backend"$'\n'

  if [[ "$PREPARED_BACKENDS" == *"$prepared_key"* ]]; then
    return 0
  fi

  "$ROOT_DIR/scripts/prepare-linux-build-backend.sh" \
    --backend "$build_backend" \
    --scratch-path "$(quillui_absolute_scratch_path)"
  PREPARED_BACKENDS="${PREPARED_BACKENDS}${build_backend}"$'\n'
}

if [[ "$DRY_RUN" != "1" ]]; then
  "$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"
fi

SEEN_BUILDS=$'\n'
PREPARED_BACKENDS=$'\n'
ROW_COUNT=0
BUILD_COUNT=0

while IFS=$'\t' read -r product requested_backend extra; do
  [[ -n "$product" ]] || continue
  if [[ -n "${extra:-}" ]]; then
    echo "Backend product build row has too many columns: $product	$requested_backend	$extra" >&2
    exit 65
  fi

  ROW_COUNT=$((ROW_COUNT + 1))
  build_backend="$(quillui_manifest_backend_for_product_row "$product" "$requested_backend")" || exit $?
  build_key="$product/$build_backend"
  if [[ "$SEEN_BUILDS" == *$'\n'"$build_key"$'\n'* ]]; then
    continue
  fi
  SEEN_BUILDS="${SEEN_BUILDS}${build_key}"$'\n'
  BUILD_COUNT=$((BUILD_COUNT + 1))

  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s\t%s\n' "$product" "$build_backend"
  else
    echo "==> Build $product (QUILLUI_LINUX_BACKEND=$build_backend)"
    quillui_prepare_backend_once "$build_backend"
    quillui_build_backend_product "$product" "$build_backend"
    quillui_record_backend_product_build "$(quillui_absolute_scratch_path)" "$product" "$build_backend"
  fi
done < <(quillui_backend_build_product_rows "$MATRIX_COMMAND")

if [[ "$ROW_COUNT" -eq 0 ]]; then
  echo "No backend product build rows listed for $MATRIX_COMMAND" >&2
  exit 65
fi

if [[ "$DRY_RUN" != "1" ]]; then
  echo "Built $BUILD_COUNT Linux backend product(s) from $ROW_COUNT $MATRIX_COMMAND row(s)."
fi
