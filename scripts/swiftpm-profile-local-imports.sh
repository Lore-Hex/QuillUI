#!/usr/bin/env bash

quillui_profile_combine_dependency_file() {
  local current_file="$1"
  local discovered_file="$2"
  local combined_file="$3"

  if [[ -n "$current_file" && -s "$discovered_file" ]]; then
    cat "$current_file" "$discovered_file" > "$combined_file"
    printf '%s\n' "$combined_file"
  elif [[ -n "$current_file" ]]; then
    printf '%s\n' "$current_file"
  elif [[ -s "$discovered_file" ]]; then
    printf '%s\n' "$discovered_file"
  fi
}

quillui_profile_maybe_discover_local_import_dependencies() {
  local root_dir="$1"
  local source_dir="$2"
  local work_root="$3"
  local import_dir="$work_root/local-swiftpm-imports"
  local package_dependencies_file="$import_dir/package-dependencies.swift"
  local target_dependencies_file="$import_dir/target-dependencies.txt"
  local combined_package_dependencies_file="$import_dir/package-dependencies-combined.swift"
  local combined_target_dependencies_file="$import_dir/target-dependencies-combined.txt"
  local next_package_dependencies_file=""
  local next_target_dependencies_file=""
  local discover_args=(
    --root-dir "$root_dir"
    --source-dir "$source_dir"
    --package-dependencies-out "$package_dependencies_file"
    --target-dependencies-out "$target_dependencies_file"
  )

  mkdir -p "$import_dir"
  if [[ -n "${QUILLUI_PROFILE_RESOLVED_PACKAGE_ROOT:-}" ]]; then
    discover_args+=(--exclude-package-root "$QUILLUI_PROFILE_RESOLVED_PACKAGE_ROOT")
  elif [[ -n "${QUILLUI_PROFILE_PACKAGE_ROOT:-}" ]]; then
    discover_args+=(--exclude-package-root "$QUILLUI_PROFILE_PACKAGE_ROOT")
  fi
  "$root_dir/scripts/discover-local-swiftpm-import-dependencies.py" "${discover_args[@]}"

  next_package_dependencies_file="$(quillui_profile_combine_dependency_file "${QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}" "$package_dependencies_file" "$combined_package_dependencies_file")"
  if [[ -n "$next_package_dependencies_file" ]]; then
    export QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE="$next_package_dependencies_file"
  fi

  next_target_dependencies_file="$(quillui_profile_combine_dependency_file "${QUILLUI_GENERATED_EXTRA_TARGET_DEPENDENCIES_FILE:-}" "$target_dependencies_file" "$combined_target_dependencies_file")"
  if [[ -n "$next_target_dependencies_file" ]]; then
    export QUILLUI_GENERATED_EXTRA_TARGET_DEPENDENCIES_FILE="$next_target_dependencies_file"
  fi
}
