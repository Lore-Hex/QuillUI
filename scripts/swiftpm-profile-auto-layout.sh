#!/usr/bin/env bash

quillui_profile_maybe_derive_swiftpm_layout() {
  local root_dir="$1"
  local source_dir="$2"
  local work_root="$3"
  local entry_type="$4"
  local target_name="$5"
  local package_root="${QUILLUI_PROFILE_PACKAGE_ROOT:-}"
  local entry_target="${QUILLUI_PROFILE_ENTRY_TARGET:-}"

  [[ -z "${QUILLUI_GENERATED_TARGET_LAYOUT_FILE:-}" ]] || return 0

  if [[ -z "$package_root" ]]; then
    if [[ -f "$source_dir/../Package.swift" ]]; then
      package_root="$(cd "$source_dir/.." && pwd)"
    elif [[ -f "$source_dir/Package.swift" ]]; then
      package_root="$(cd "$source_dir" && pwd)"
    fi
  fi

  [[ -n "$package_root" && -f "$package_root/Package.swift" ]] || return 0

  local auto_layout_dir="$work_root/swiftpm-layout"
  local auto_layout_file="$auto_layout_dir/target-layout.tsv"
  local auto_dependencies_file="$auto_layout_dir/package-dependencies.swift"
  local auto_layout_args=(
    --package-root "$package_root"
    --source-dir "$source_dir"
    --app-type "$entry_type"
    --generated-target "$target_name"
    --layout-out "$auto_layout_file"
    --dependencies-out "$auto_dependencies_file"
  )

  mkdir -p "$auto_layout_dir"
  if [[ -n "$entry_target" ]]; then
    auto_layout_args+=(--entry-target "$entry_target")
  fi
  "$root_dir/scripts/swiftpm-package-layout-for-linux.py" "${auto_layout_args[@]}"
  export QUILLUI_GENERATED_TARGET_LAYOUT_FILE="$auto_layout_file"

  if [[ -n "${QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}" && -s "$auto_dependencies_file" ]]; then
    local combined_dependencies_file="$auto_layout_dir/package-dependencies-combined.swift"
    cat "$QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE" "$auto_dependencies_file" > "$combined_dependencies_file"
    export QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE="$combined_dependencies_file"
  elif [[ -z "${QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}" ]]; then
    export QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE="$auto_dependencies_file"
  fi
}
