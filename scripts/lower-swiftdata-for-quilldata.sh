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

exec "$ROOT_DIR/scripts/run-quill-source-lower.sh" "$SOURCE_DIR" "$OUTPUT_DIR"
