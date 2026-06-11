#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null
  pwd
)"

source "$ROOT_DIR/scripts/quillui-backend-products.sh"

SCRATCH_PATH=".build-linux"
REQUESTED_BACKEND="${QUILLUI_LINUX_BACKEND:-gtk}"

usage() {
  cat <<'USAGE'
Usage: scripts/prepare-linux-build-backend.sh [--backend BACKEND] [--scratch-path PATH]

Prepare a SwiftPM scratch path for the selected Linux backend graph.
GTK builds patch SwiftOpenUI's CSS importer checkout; Qt builds are a no-op
because the Qt manifest graph intentionally excludes SwiftOpenUI and GTK.

Options:
  --backend BACKEND    Linux backend to prepare: gtk or qt. Defaults to
                       QUILLUI_LINUX_BACKEND, then gtk.
  --scratch-path PATH  SwiftPM scratch path to prepare. Defaults to .build-linux.
  -h, --help           Show this help.
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
    --backend)
      [[ $# -ge 2 ]] || fail_usage "--backend requires a value."
      REQUESTED_BACKEND="$2"
      shift 2
      ;;
    --backend=*)
      REQUESTED_BACKEND="${1#--backend=}"
      shift
      ;;
    --scratch-path)
      [[ $# -ge 2 ]] || fail_usage "--scratch-path requires a value."
      SCRATCH_PATH="$2"
      shift 2
      ;;
    --scratch-path=*)
      SCRATCH_PATH="${1#--scratch-path=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail_usage "Unsupported option: $1"
      ;;
  esac
done

REQUESTED_BACKEND="$(quillui_require_linux_build_backend_identifier "${REQUESTED_BACKEND:-gtk}")"

case "$REQUESTED_BACKEND" in
  gtk)
    "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$SCRATCH_PATH"

# OpenCombineDispatch guards its `extension DispatchQueue: Scheduler` (and
# OpenCombineFoundation its RunLoop twin) behind `#if !canImport(Combine)`.
# SwiftPM exposes OUR Combine shim module to dependency compiles via the
# shared build dir, so on warm builds the probe flips TRUE and the
# conformances vanish — unmodified `receive(on: DispatchQueue.main)` then
# fails ("requires DispatchQueue conform to Scheduler") depending on build
# history. Force clean-order semantics: drop the stale products so these
# targets recompile before the Combine shim exists, keeping the probe FALSE
# deterministically (matches what a clean CI build does).
for ocd in OpenCombineDispatch OpenCombineFoundation; do
    rm -rf "$SCRATCH_PATH"/*/debug/"$ocd".build            "$SCRATCH_PATH"/*/debug/Modules/"$ocd".swiftmodule            "$SCRATCH_PATH"/*/release/"$ocd".build            "$SCRATCH_PATH"/*/release/Modules/"$ocd".swiftmodule 2>/dev/null || true
done
rm -f "$SCRATCH_PATH"/*/debug/Modules/Combine.swiftmodule       "$SCRATCH_PATH"/*/release/Modules/Combine.swiftmodule 2>/dev/null || true
    ;;
  qt)
    ;;
esac
