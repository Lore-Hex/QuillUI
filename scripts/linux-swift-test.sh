#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH=".build-linux"
SWIFT_TEST_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scratch-path)
      if [[ $# -lt 2 ]]; then
        echo "--scratch-path requires a value" >&2
        exit 64
      fi
      SCRATCH_PATH="$2"
      shift 2
      ;;
    --scratch-path=*)
      SCRATCH_PATH="${1#--scratch-path=}"
      shift
      ;;
    *)
      SWIFT_TEST_ARGS+=("$1")
      shift
      ;;
  esac
done

requested_backend="${QUILLUI_LINUX_BACKEND:-gtk}"
requested_backend="${requested_backend//[$'\t\r\n ']}"
requested_backend="$(printf '%s' "$requested_backend" | tr '[:upper:]' '[:lower:]')"

case "$requested_backend" in
  ""|gtk|gtk4)
    "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$SCRATCH_PATH"
    ;;
  qt|qt6)
    # The Qt manifest intentionally strips SwiftOpenUI/GTK from the package
    # graph. Patching the GTK checkout here would force a dependency that Qt
    # mode is specifically designed to avoid.
    ;;
  *)
    echo "Unsupported QUILLUI_LINUX_BACKEND value: ${QUILLUI_LINUX_BACKEND:-}" >&2
    exit 64
    ;;
esac

swift test --scratch-path "$SCRATCH_PATH" "${SWIFT_TEST_ARGS[@]}"
