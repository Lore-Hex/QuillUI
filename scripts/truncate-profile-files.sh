#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  cat >&2 <<'MSG'
Usage: scripts/truncate-profile-files.sh SOURCE_DIR FILE_LIST

Truncates optional profile-listed files inside a lowered source tree. FILE_LIST
contains one relative path per line; blank lines and # comments are ignored.
MSG
  exit 64
fi

SOURCE_DIR="$1"
FILE_LIST="$2"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory was not found: $SOURCE_DIR" >&2
  exit 66
fi

if [[ ! -f "$FILE_LIST" ]]; then
  exit 0
fi

while IFS= read -r relative_file || [[ -n "$relative_file" ]]; do
  relative_file="${relative_file%%#*}"
  relative_file="${relative_file#"${relative_file%%[![:space:]]*}"}"
  relative_file="${relative_file%"${relative_file##*[![:space:]]}"}"
  [[ -n "$relative_file" ]] || continue

  if [[ "$relative_file" = /* || "$relative_file" == *"/../"* || "$relative_file" == ../* || "$relative_file" == *"/.." ]]; then
    echo "Profile truncate path must stay relative to source dir: $relative_file" >&2
    exit 65
  fi

  file="$SOURCE_DIR/$relative_file"
  [[ -f "$file" ]] || continue
  : > "$file"
done < "$FILE_LIST"
