#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_ROOT="$ROOT_DIR/scripts/profiles"
PROFILE=""
MAX_LINES="${QUILLUI_PROFILE_MAX_SHELL_LINES:-50}"

usage() {
  echo "Usage: $(basename "$0") [--profile NAME] [--max-shell-lines N]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --max-shell-lines) MAX_LINES="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

[[ "$MAX_LINES" =~ ^[1-9][0-9]*$ ]] || {
  echo "--max-shell-lines must be a positive integer, got: $MAX_LINES" >&2
  exit 64
}

emit_profiles() {
  if [[ -n "$PROFILE" ]]; then
    echo "$PROFILE"
  else
    find "$PROFILE_ROOT" -maxdepth 1 -type f -name '*.sh' -print \
      | sed -E 's#^.*/([^/]+)\.sh$#\1#' \
      | sort
  fi
}

emit_profile_shell_files() {
  local name="$1"
  local entry="$PROFILE_ROOT/$name.sh"
  local dir="$PROFILE_ROOT/$name"
  if [[ ! -f "$entry" && ! -d "$dir" ]]; then
    echo "Profile was not found: $name" >&2
    exit 66
  fi
  [[ -f "$entry" ]] && echo "$entry"
  [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -type f -name '*.sh' -print | sort
}

status=0
while IFS= read -r profile; do
  [[ -z "$profile" ]] && continue
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    lines="$(wc -l < "$file" | tr -d '[:space:]')"
    path="${file#"$ROOT_DIR/"}"
    if (( lines > MAX_LINES )); then
      echo "profile budget failed: $path has $lines lines (max $MAX_LINES)" >&2
      status=1
    else
      echo "profile budget ok: $path has $lines lines (max $MAX_LINES)"
    fi
  done < <(emit_profile_shell_files "$profile")
done < <(emit_profiles)

exit "$status"
