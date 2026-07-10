#!/usr/bin/env bash

quillui_profile_copy_tree() {
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

quillui_profile_truthy_flag() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

quillui_profile_validate_generic_swiftui_inputs() {
  local source_dir="$1"
  local work_root="$2"
  local entry_type="$3"
  local backend_facade="$4"
  local root_dir="$5"

  if [[ -z "$source_dir" || -z "$work_root" || -z "$entry_type" ]]; then
    echo "generic-swiftui requires QUILLUI_PROFILE_SOURCE_DIR, QUILLUI_PROFILE_WORKDIR, and QUILLUI_PROFILE_ENTRY_TYPE" >&2
    return 64
  fi
  if [[ ! -d "$source_dir" ]]; then
    echo "generic-swiftui source directory was not found: $source_dir" >&2
    return 66
  fi
  if [[ -z "$work_root" || "$work_root" == "/" || "$work_root" == "$root_dir" ]]; then
    echo "Refusing unsafe generic-swiftui work directory: ${work_root:-<empty>}" >&2
    return 73
  fi
  if [[ "$backend_facade" == "qt" && -z "${QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY:-}" ]]; then
    echo "generic-swiftui qt facade requires QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY" >&2
    return 64
  fi
}

quillui_profile_lower_source_tree() {
  local root_dir="$1"
  local source_dir="$2"
  local source_copy="$3"
  local lowered_copy="$4"

  rm -rf "$source_copy" "$lowered_copy"
  quillui_profile_copy_tree "$source_dir" "$source_copy"
  "$root_dir/scripts/run-quill-source-lower.sh" "$source_copy" "$lowered_copy"
  "$root_dir/scripts/lower-swiftui-source-for-linux.sh" "$lowered_copy"
}

quillui_profile_prepare_lowered_source() {
  local root_dir="$1"
  local source_dir="$2"
  local work_root="$3"
  local lowered_source_cache_dir="$4"
  local reuse_lowered_source="$5"
  local source_cache_key=""
  local source_cache_entry=""

  QUILLUI_PROFILE_SOURCE_COPY="$work_root/source"
  QUILLUI_PROFILE_LOWERED_COPY="$work_root/lowered"

  if quillui_profile_truthy_flag "$reuse_lowered_source"; then
    source_cache_key="$(python3 "$root_dir/scripts/quillui-source-cache-key.py" --root-dir "$root_dir" --source-dir "$source_dir")"
    source_cache_entry="$lowered_source_cache_dir/$source_cache_key"
  fi

  if [[ -n "$source_cache_entry" \
      && -f "$source_cache_entry/.quillui-lowered-source-cache-key" \
      && -d "$source_cache_entry/source" \
      && -d "$source_cache_entry/lowered" \
      && "$(cat "$source_cache_entry/.quillui-lowered-source-cache-key")" == "$source_cache_key" ]]; then
    rm -rf "$QUILLUI_PROFILE_SOURCE_COPY" "$QUILLUI_PROFILE_LOWERED_COPY"
    quillui_profile_copy_tree "$source_cache_entry/source" "$QUILLUI_PROFILE_SOURCE_COPY"
    quillui_profile_copy_tree "$source_cache_entry/lowered" "$QUILLUI_PROFILE_LOWERED_COPY"
    echo "Reused cached generic SwiftUI lowered source: $source_cache_entry"
  else
    quillui_profile_lower_source_tree "$root_dir" "$source_dir" "$QUILLUI_PROFILE_SOURCE_COPY" "$QUILLUI_PROFILE_LOWERED_COPY"
    if [[ -n "$source_cache_entry" ]]; then
      local tmp_cache_entry="$lowered_source_cache_dir/.tmp-$source_cache_key-$$"
      rm -rf "$tmp_cache_entry"
      mkdir -p "$tmp_cache_entry"
      quillui_profile_copy_tree "$QUILLUI_PROFILE_SOURCE_COPY" "$tmp_cache_entry/source"
      quillui_profile_copy_tree "$QUILLUI_PROFILE_LOWERED_COPY" "$tmp_cache_entry/lowered"
      printf '%s\n' "$source_cache_key" > "$tmp_cache_entry/.quillui-lowered-source-cache-key"
      rm -rf "$source_cache_entry"
      mv "$tmp_cache_entry" "$source_cache_entry"
      echo "Cached generic SwiftUI lowered source: $source_cache_entry"
    fi
  fi
}
