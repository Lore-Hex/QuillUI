#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  cat >&2 <<'MSG'
Usage: scripts/lower-swiftdata-for-quilldata.sh SOURCE_DIR OUTPUT_DIR

Compatibility wrapper for quill-source-lower. Creates a generated Linux source
copy that keeps app sources unchanged while lowering SwiftData-only syntax to
QuillData-compatible Swift.
MSG
  exit 64
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$1"
OUTPUT_DIR="$2"

if [[ -n "${QUILLUI_SOURCE_LOWER:-}" ]]; then
  exec "$QUILLUI_SOURCE_LOWER" "$SOURCE_DIR" "$OUTPUT_DIR"
fi

SOURCE_LOWER_SCRATCH_PATH="${QUILLUI_SOURCE_LOWER_SCRATCH_PATH:-$ROOT_DIR/.build/quill-source-lower-tool}"

exec swift run \
  --package-path "$ROOT_DIR" \
  --scratch-path "$SOURCE_LOWER_SCRATCH_PATH" \
  --disable-sandbox \
  quill-source-lower \
  "$SOURCE_DIR" \
  "$OUTPUT_DIR"
