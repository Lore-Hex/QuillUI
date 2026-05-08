#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  cat >&2 <<'MSG'
Usage: scripts/install-profile-templates.sh TEMPLATE_DIR OUTPUT_DIR

Copies a profile template tree into a lowered source tree, preserving relative
paths. Profiles use this for generated replacement Swift files that are too
large to keep readable inside shell heredocs.
MSG
  exit 64
fi

TEMPLATE_DIR="$1"
OUTPUT_DIR="$2"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "Profile template directory was not found: $TEMPLATE_DIR" >&2
  exit 66
fi

mkdir -p "$OUTPUT_DIR"

template_root="$(cd "$TEMPLATE_DIR" && pwd)"

find "$template_root" -type f -print0 |
  while IFS= read -r -d '' template_file; do
    relative_file="${template_file#"$template_root"/}"
    output_file="$OUTPUT_DIR/$relative_file"
    mkdir -p "$(dirname "$output_file")"
    cp "$template_file" "$output_file"
  done
