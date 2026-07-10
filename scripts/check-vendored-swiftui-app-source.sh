#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
source "$ROOT_DIR/scripts/quillui-vendored-source.sh"

CHECK_DEPENDENCIES=1
ALL_VENDORED_APPS=0
APP_NAMES=()

usage() {
  cat <<'USAGE'
Usage: scripts/check-vendored-swiftui-app-source.sh [OPTIONS] APP...

Verify that vendored SwiftUI app snapshots are present and that their
Package.resolved pins are covered by checked-in third_party/ SwiftPM sources.

Options:
  --all-vendored-apps  Check every vendor/apps/* source snapshot.
  --no-deps            Only verify app source metadata, not SwiftPM pins.
  -h, --help           Show this help.
USAGE
}

fail_usage() {
  echo "$1" >&2
  echo >&2
  usage >&2
  exit 64
}

validate_app_name() {
  local name="$1"

  if [[ ! "$name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    fail_usage "APP must be a simple vendored app source name, got: $name"
  fi
}

add_app() {
  local app_name="$1"
  local existing

  validate_app_name "$app_name"
  if [[ ${#APP_NAMES[@]} -gt 0 ]]; then
    for existing in "${APP_NAMES[@]}"; do
      [[ "$existing" != "$app_name" ]] || return 0
    done
  fi
  APP_NAMES+=("$app_name")
}

add_all_vendored_apps() {
  local source_dir

  if [[ ! -d "$ROOT_DIR/vendor/apps" ]]; then
    return 0
  fi

  while IFS= read -r source_dir; do
    [[ -n "$source_dir" ]] || continue
    add_app "$(basename "$source_dir")"
  done < <(find "$ROOT_DIR/vendor/apps" -mindepth 1 -maxdepth 1 -type d -print | sort)
}

require_file() {
  local path="$1"
  local message="$2"

  if [[ ! -f "$path" ]]; then
    echo "$message: $path" >&2
    return 1
  fi
}

check_app_source() {
  local app_name="$1"
  local source_dir="$ROOT_DIR/vendor/apps/$app_name"
  local metadata_file="$source_dir/.quillui-vendor-source-fingerprint"
  local vendor_note="$source_dir/QUILLUI_VENDOR.md"

  if [[ ! -d "$source_dir" ]]; then
    echo "missing vendored app source: vendor/apps/$app_name" >&2
    return 1
  fi

  require_file "$metadata_file" "missing vendored app fingerprint" || return 1
  require_file "$vendor_note" "missing vendored app provenance note" || return 1

  if ! grep -Fxq "quillui-app-source-vendor/v1" "$metadata_file"; then
    echo "invalid vendored app fingerprint header: $metadata_file" >&2
    return 1
  fi
  if ! grep -Fxq "app=$app_name" "$metadata_file"; then
    echo "vendored app fingerprint does not match app=$app_name: $metadata_file" >&2
    return 1
  fi
  if ! awk -F= '$1 == "source" && length($2) > 0 { found = 1 } END { exit found ? 0 : 1 }' "$metadata_file"; then
    echo "vendored app fingerprint has no source identity: $metadata_file" >&2
    return 1
  fi

  echo "vendored app source ok: $app_name"
}

check_app_dependencies() {
  local app_name="$1"

  "$ROOT_DIR/scripts/vendor-swiftpm-sources.sh" \
    --app "$app_name" \
    --no-resolve \
    --check-vendored >/dev/null
  echo "vendored SwiftPM source pins ok: $app_name"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all-vendored-apps)
      ALL_VENDORED_APPS=1
      shift
      ;;
    --no-deps)
      CHECK_DEPENDENCIES=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail_usage "Unsupported option: $1"
      ;;
    *)
      add_app "$1"
      shift
      ;;
  esac
done

if [[ "$ALL_VENDORED_APPS" == "1" ]]; then
  add_all_vendored_apps
fi

if [[ ${#APP_NAMES[@]} -eq 0 ]]; then
  fail_usage "APP or --all-vendored-apps is required."
fi

for app_name in "${APP_NAMES[@]}"; do
  check_app_source "$app_name"
  if [[ "$CHECK_DEPENDENCIES" == "1" ]]; then
    check_app_dependencies "$app_name"
  fi
done
