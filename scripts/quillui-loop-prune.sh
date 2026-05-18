#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${QUILLUI_LOOP_PRUNE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DRY_RUN="${QUILLUI_LOOP_PRUNE_DRY_RUN:-1}"
MAX_DAYS="${QUILLUI_LOOP_PRUNE_MAX_DAYS:-7}"
INCLUDE_BUILD_CACHE="${QUILLUI_LOOP_PRUNE_INCLUDE_BUILD_CACHE:-0}"
REPORT_USAGE="${QUILLUI_LOOP_PRUNE_REPORT_USAGE:-1}"
PRUNED_COUNT=0

require_unsigned_integer() {
  local value="$1"
  local variable_name="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "$variable_name must be an unsigned integer, got: $value" >&2
    exit 64
  fi
}

require_boolean() {
  local value="$1"
  local variable_name="$2"

  case "$value" in
    0 | 1) ;;
    *)
      echo "$variable_name must be 0 or 1, got: $value" >&2
      exit 64
      ;;
  esac
}

require_repo_root() {
  if [[ -z "$ROOT_DIR" || "$ROOT_DIR" == "/" ]]; then
    echo "refusing to prune an empty root or /" >&2
    exit 64
  fi

  if [[ ! -f "$ROOT_DIR/Package.swift" || ! -d "$ROOT_DIR/scripts" ]]; then
    echo "refusing to prune outside a QuillUI checkout: $ROOT_DIR" >&2
    exit 64
  fi
}

prune_file() {
  local path="$1"
  PRUNED_COUNT=$((PRUNED_COUNT + 1))

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] rm $path"
  else
    rm -f -- "$path"
    echo "rm $path"
  fi
}

prune_empty_dir() {
  local path="$1"
  PRUNED_COUNT=$((PRUNED_COUNT + 1))

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] rmdir $path"
  else
    rmdir -- "$path" 2>/dev/null || true
  fi
}

prune_empty_dirs() {
  local base="$1"

  [[ -d "$base" ]] || return 0

  while IFS= read -r -d '' path; do
    prune_empty_dir "$path"
  done < <(find "$base" -mindepth 1 -depth -type d -empty -mtime +"$MAX_DAYS" -print0)
}

report_path_usage() {
  local path="$1"
  local usage

  [[ -e "$path" ]] || return 0

  usage="$(du -sh "$path" 2>/dev/null | awk '{ print $1 }')" || return 0
  [[ -n "$usage" ]] || return 0

  echo "quillui loop prune usage: $usage $path"
}

report_scoped_disk_usage() {
  [[ "$REPORT_USAGE" == "1" ]] || return 0

  for scoped_path in \
    "$ROOT_DIR/.qa" \
    "$ROOT_DIR/.build-codex-loop" \
    "$ROOT_DIR/.build-linux-vm-loop" \
    "$ROOT_DIR/.build-linux-qt" \
    "$ROOT_DIR/.build/artifacts"
  do
    report_path_usage "$scoped_path"
  done
}

prune_all_files_older_than() {
  local base="$1"

  [[ -d "$base" ]] || return 0

  while IFS= read -r -d '' path; do
    prune_file "$path"
  done < <(find "$base" -type f -mtime +"$MAX_DAYS" -print0)

  prune_empty_dirs "$base"
}

prune_matching_files_older_than() {
  local base="$1"
  shift

  [[ -d "$base" ]] || return 0

  while IFS= read -r -d '' path; do
    prune_file "$path"
  done < <(find "$base" -type f \( "$@" \) -mtime +"$MAX_DAYS" -print0)

  prune_empty_dirs "$base"
}

require_unsigned_integer "$MAX_DAYS" "QUILLUI_LOOP_PRUNE_MAX_DAYS"
require_boolean "$DRY_RUN" "QUILLUI_LOOP_PRUNE_DRY_RUN"
require_boolean "$INCLUDE_BUILD_CACHE" "QUILLUI_LOOP_PRUNE_INCLUDE_BUILD_CACHE"
require_boolean "$REPORT_USAGE" "QUILLUI_LOOP_PRUNE_REPORT_USAGE"
require_repo_root

report_scoped_disk_usage

prune_matching_files_older_than \
  "$ROOT_DIR/.qa" \
  -name "*.png" -o -name "*.log" -o -name "*.txt" -o -name "*.json" -o -name "*.csv"

for artifact_dir in \
  "$ROOT_DIR/.build-codex-loop/artifacts" \
  "$ROOT_DIR/.build-linux-vm-loop/artifacts" \
  "$ROOT_DIR/.build-linux-qt/artifacts" \
  "$ROOT_DIR/.build/artifacts"
do
  prune_all_files_older_than "$artifact_dir"
done

if [[ "$INCLUDE_BUILD_CACHE" == "1" ]]; then
  for cache_dir in \
    "$ROOT_DIR/.build-codex-loop" \
    "$ROOT_DIR/.build-linux-vm-loop" \
    "$ROOT_DIR/.build-linux-qt"
  do
    prune_all_files_older_than "$cache_dir"
  done
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "quillui loop prune: dry-run matched $PRUNED_COUNT stale path(s); set QUILLUI_LOOP_PRUNE_DRY_RUN=0 to delete"
else
  echo "quillui loop prune: removed $PRUNED_COUNT stale path(s)"
fi
