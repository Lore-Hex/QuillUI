#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/swiftpm-profile-auto-layout.sh"
source "$ROOT_DIR/scripts/swiftpm-profile-local-imports.sh"
SOURCE_DIR="${QUILLUI_PROFILE_SOURCE_DIR:-}"
WORK_ROOT="${QUILLUI_PROFILE_WORKDIR:-}"
PRODUCT_NAME="${QUILLUI_PROFILE_PRODUCT_NAME:-generic-swiftui-linux}"
PACKAGE_NAME="${QUILLUI_PROFILE_PACKAGE_NAME:-GeneratedSwiftUILinuxApp}"
TARGET_NAME="${QUILLUI_PROFILE_TARGET_NAME:-GeneratedSwiftUILinuxApp}"
ENTRY_TYPE="${QUILLUI_PROFILE_ENTRY_TYPE:-}"
MAIN_TYPE="${QUILLUI_PROFILE_MAIN_TYPE:-GeneratedSwiftUILinuxMain}"
BACKEND_FACADE="${QUILLUI_GENERATED_BACKEND_FACADE:-swiftui}"
LOWERED_SOURCE_CACHE_DIR="${QUILLUI_PROFILE_LOWERED_SOURCE_CACHE_DIR:-$ROOT_DIR/.build/quillui-lowered-source-cache}"
REUSE_LOWERED_SOURCE="${QUILLUI_PROFILE_REUSE_LOWERED_SOURCE:-1}"
if [[ -z "$SOURCE_DIR" || -z "$WORK_ROOT" || -z "$ENTRY_TYPE" ]]; then
  echo "generic-swiftui requires QUILLUI_PROFILE_SOURCE_DIR, QUILLUI_PROFILE_WORKDIR, and QUILLUI_PROFILE_ENTRY_TYPE" >&2
  exit 64
fi
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "generic-swiftui source directory was not found: $SOURCE_DIR" >&2
  exit 66
fi
if [[ -z "$WORK_ROOT" || "$WORK_ROOT" == "/" || "$WORK_ROOT" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generic-swiftui work directory: ${WORK_ROOT:-<empty>}" >&2
  exit 73
fi
if [[ "$BACKEND_FACADE" == "qt" && -z "${QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY:-}" ]]; then
  echo "generic-swiftui qt facade requires QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY" >&2
  exit 64
fi
SOURCE_COPY="$WORK_ROOT/source"; LOWERED_COPY="$WORK_ROOT/lowered"; PACKAGE_DIR="$WORK_ROOT/package"
copy_tree() {
  local from_dir="$1"
  local to_dir="$2"

  mkdir -p "$to_dir"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$from_dir"/ "$to_dir"/
  else
    rm -rf "$to_dir"
    mkdir -p "$to_dir"
    cp -R "$from_dir"/. "$to_dir"/
  fi
}

truthy_flag() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

lower_source_tree() {
  rm -rf "$SOURCE_COPY" "$LOWERED_COPY"
  copy_tree "$SOURCE_DIR" "$SOURCE_COPY"
  "$ROOT_DIR/scripts/run-quill-source-lower.sh" "$SOURCE_COPY" "$LOWERED_COPY"
  "$ROOT_DIR/scripts/lower-swiftui-source-for-linux.sh" "$LOWERED_COPY"
}

mkdir -p "$WORK_ROOT"; rm -rf "$PACKAGE_DIR"
source_cache_key=""
source_cache_entry=""
if truthy_flag "$REUSE_LOWERED_SOURCE"; then
  source_cache_key="$(python3 "$ROOT_DIR/scripts/quillui-source-cache-key.py" --root-dir "$ROOT_DIR" --source-dir "$SOURCE_DIR")"
  source_cache_entry="$LOWERED_SOURCE_CACHE_DIR/$source_cache_key"
fi

if [[ -n "$source_cache_entry" \
    && -f "$source_cache_entry/.quillui-lowered-source-cache-key" \
    && -d "$source_cache_entry/source" \
    && -d "$source_cache_entry/lowered" \
    && "$(cat "$source_cache_entry/.quillui-lowered-source-cache-key")" == "$source_cache_key" ]]; then
  rm -rf "$SOURCE_COPY" "$LOWERED_COPY"
  copy_tree "$source_cache_entry/source" "$SOURCE_COPY"
  copy_tree "$source_cache_entry/lowered" "$LOWERED_COPY"
  echo "Reused cached generic SwiftUI lowered source: $source_cache_entry"
else
  lower_source_tree
  if [[ -n "$source_cache_entry" ]]; then
    tmp_cache_entry="$LOWERED_SOURCE_CACHE_DIR/.tmp-$source_cache_key-$$"
    rm -rf "$tmp_cache_entry"
    mkdir -p "$tmp_cache_entry"
    copy_tree "$SOURCE_COPY" "$tmp_cache_entry/source"
    copy_tree "$LOWERED_COPY" "$tmp_cache_entry/lowered"
    printf '%s\n' "$source_cache_key" > "$tmp_cache_entry/.quillui-lowered-source-cache-key"
    rm -rf "$source_cache_entry"
    mv "$tmp_cache_entry" "$source_cache_entry"
    echo "Cached generic SwiftUI lowered source: $source_cache_entry"
  fi
fi
quillui_profile_maybe_derive_swiftpm_layout "$ROOT_DIR" "$SOURCE_DIR" "$WORK_ROOT" "$ENTRY_TYPE" "$TARGET_NAME"
quillui_profile_maybe_discover_local_import_dependencies "$ROOT_DIR" "$LOWERED_COPY" "$WORK_ROOT"
QUILLUI_GENERATED_SOURCES_DIR="$LOWERED_COPY" \
QUILLUI_GENERATED_SOURCE_COUNT_DIR="$SOURCE_COPY" \
QUILLUI_GENERATED_WORKDIR="$WORK_ROOT" \
QUILLUI_GENERATED_PACKAGE_DIR="$PACKAGE_DIR" \
QUILLUI_GENERATED_PACKAGE_NAME="$PACKAGE_NAME" \
QUILLUI_GENERATED_PRODUCT_NAME="$PRODUCT_NAME" \
QUILLUI_GENERATED_TARGET_NAME="$TARGET_NAME" \
QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY=1 \
QUILLUI_GENERATED_APP_ENTRY_TYPE="$ENTRY_TYPE" \
QUILLUI_GENERATED_APP_MAIN_TYPE="$MAIN_TYPE" \
QUILLUI_GENERATED_REPORT_LABEL="Generated generic SwiftUI Linux app" \
"$ROOT_DIR/scripts/generate-swiftui-linux-package.sh"
