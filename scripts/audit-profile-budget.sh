#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_ROOT="$ROOT_DIR/scripts/profiles"
PROFILE=""
MAX_LINES="${QUILLUI_PROFILE_MAX_SHELL_LINES:-50}"
MAX_TEMPLATE_LINES="${QUILLUI_PROFILE_MAX_TEMPLATE_LINES:-0}"
MAX_REWRITE_LINES="${QUILLUI_PROFILE_MAX_REWRITE_LINES:-0}"

usage() {
  echo "Usage: $(basename "$0") [--profile NAME] [--max-shell-lines N] [--max-template-lines N] [--max-rewrite-lines N]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --max-shell-lines) MAX_LINES="${2:-}"; shift 2 ;;
    --max-template-lines) MAX_TEMPLATE_LINES="${2:-}"; shift 2 ;;
    --max-rewrite-lines) MAX_REWRITE_LINES="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

[[ "$MAX_LINES" =~ ^[1-9][0-9]*$ ]] || {
  echo "--max-shell-lines must be a positive integer, got: $MAX_LINES" >&2
  exit 64
}
[[ "$MAX_TEMPLATE_LINES" =~ ^[0-9]+$ ]] || {
  echo "--max-template-lines must be a non-negative integer, got: $MAX_TEMPLATE_LINES" >&2
  exit 64
}
[[ "$MAX_REWRITE_LINES" =~ ^[0-9]+$ ]] || {
  echo "--max-rewrite-lines must be a non-negative integer, got: $MAX_REWRITE_LINES" >&2
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

profile_template_line_count() {
  local name="$1"
  local dir="$PROFILE_ROOT/$name/templates"
  local total=0
  local file
  local lines

  [[ -d "$dir" ]] || {
    echo 0
    return
  }

  while IFS= read -r -d '' file; do
    lines="$(wc -l < "$file" | tr -d '[:space:]')"
    total=$((total + lines))
  done < <(find "$dir" -type f -print0)

  echo "$total"
}

profile_rewrite_line_count() {
  local name="$1"
  local dir="$PROFILE_ROOT/$name/rewrite-rules"
  local total=0
  local file
  local lines

  [[ -d "$dir" ]] || {
    echo 0
    return
  }

  while IFS= read -r -d '' file; do
    lines="$(wc -l < "$file" | tr -d '[:space:]')"
    total=$((total + lines))
  done < <(find "$dir" -type f -print0)

  echo "$total"
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

  template_lines="$(profile_template_line_count "$profile")"
  template_path="scripts/profiles/$profile/templates"
  if (( MAX_TEMPLATE_LINES > 0 && template_lines > MAX_TEMPLATE_LINES )); then
    echo "profile template budget failed: $template_path has $template_lines lines (max $MAX_TEMPLATE_LINES)" >&2
    status=1
  elif (( MAX_TEMPLATE_LINES > 0 )); then
    echo "profile template budget ok: $template_path has $template_lines lines (max $MAX_TEMPLATE_LINES)"
  else
    echo "profile template budget report: $template_path has $template_lines lines"
  fi

  rewrite_lines="$(profile_rewrite_line_count "$profile")"
  rewrite_path="scripts/profiles/$profile/rewrite-rules"
  if (( MAX_REWRITE_LINES > 0 && rewrite_lines > MAX_REWRITE_LINES )); then
    echo "profile rewrite budget failed: $rewrite_path has $rewrite_lines lines (max $MAX_REWRITE_LINES)" >&2
    status=1
  elif (( MAX_REWRITE_LINES > 0 )); then
    echo "profile rewrite budget ok: $rewrite_path has $rewrite_lines lines (max $MAX_REWRITE_LINES)"
  else
    echo "profile rewrite budget report: $rewrite_path has $rewrite_lines lines"
  fi
done < <(emit_profiles)

exit "$status"
