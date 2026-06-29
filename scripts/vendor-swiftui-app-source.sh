#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
APP_NAME=""
SOURCE_DIR=""
SCRATCH_PATH=""
DRY_RUN=0
VENDOR_APP_SOURCE=1
VENDOR_DEPENDENCIES=1
RESOLVE_DEPENDENCIES=0
FULL_DEPENDENCIES=0
PACKAGE_RESOLVED_ARGS=()

usage() {
  cat <<'USAGE'
Usage: scripts/vendor-swiftui-app-source.sh [OPTIONS] APP [SOURCE_DIR]

Pin a SwiftUI app checkout for fast QuillUI Linux builds by copying the app
source to vendor/apps/APP and copying SwiftPM pins from its Package.resolved
files into third_party/.

Options:
  --source PATH, --from PATH
                        Source checkout to vendor. Equivalent to SOURCE_DIR.
                        When omitted, reads from .upstream/APP.
  --scratch-path PATH   SwiftPM scratch path whose checkouts/ directory is used
                        for dependency source copies. Defaults to .build.
  --resolve             Run swift package resolve before dependency vendoring.
                        Default is no-network/no-resolve.
  --no-resolve          Do not run swift package resolve before dependency
                        vendoring. This is the default.
  --full-deps           Copy full dependency checkouts instead of slim sources.
  --no-app-source       Skip vendor/apps/APP copy and only vendor dependencies.
  --no-deps             Skip third_party dependency vendoring.
  --dry-run             Print the copies that would be performed.
  -h, --help            Show this help.

Environment:
  QUILLUI_VENDOR_FORCE=1
                        Re-copy app/package source even when fingerprints match.
  QUILLUI_VENDOR_INCLUDE_DEV_PACKAGES=1
                        Include known test/tooling-only Package.resolved pins.
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

resolve_path() {
  local path="$1"

  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$path" ;;
  esac
}

append_package_resolved_files_from_source() {
  local source="$1"
  local resolved_file

  while IFS= read -r resolved_file; do
    [[ -n "$resolved_file" ]] || continue
    PACKAGE_RESOLVED_ARGS+=("--package-resolved" "$resolved_file")
  done < <(find "$source" \
    \( -name .git -o -name .build -o -name DerivedData \) -prune \
    -o -name Package.resolved -type f -print | sort)
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source|--from)
      [[ $# -ge 2 ]] || fail_usage "$1 requires a path."
      SOURCE_DIR="$2"
      shift 2
      ;;
    --source=*|--from=*)
      SOURCE_DIR="${1#*=}"
      shift
      ;;
    --scratch-path)
      [[ $# -ge 2 ]] || fail_usage "--scratch-path requires a path."
      SCRATCH_PATH="$2"
      shift 2
      ;;
    --scratch-path=*)
      SCRATCH_PATH="${1#*=}"
      shift
      ;;
    --resolve)
      RESOLVE_DEPENDENCIES=1
      shift
      ;;
    --no-resolve)
      RESOLVE_DEPENDENCIES=0
      shift
      ;;
    --full-deps)
      FULL_DEPENDENCIES=1
      shift
      ;;
    --no-app-source)
      VENDOR_APP_SOURCE=0
      shift
      ;;
    --no-deps)
      VENDOR_DEPENDENCIES=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
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
      if [[ -z "$APP_NAME" ]]; then
        APP_NAME="$1"
      elif [[ -z "$SOURCE_DIR" ]]; then
        SOURCE_DIR="$1"
      else
        fail_usage "Unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$APP_NAME" ]] || fail_usage "APP is required."
validate_app_name "$APP_NAME"

if [[ -n "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$(resolve_path "$SOURCE_DIR")"
fi
if [[ -n "$SCRATCH_PATH" ]]; then
  SCRATCH_PATH="$(resolve_path "$SCRATCH_PATH")"
fi

if [[ "$VENDOR_APP_SOURCE" == "1" ]]; then
  app_args=("$ROOT_DIR/scripts/vendor-app-source.sh")
  [[ "$DRY_RUN" == "0" ]] || app_args+=("--dry-run")
  [[ -z "$SOURCE_DIR" ]] || app_args+=("--source" "$SOURCE_DIR")
  app_args+=("$APP_NAME")
  "${app_args[@]}"
fi

if [[ "$VENDOR_DEPENDENCIES" == "1" ]]; then
  dependency_args=("$ROOT_DIR/scripts/vendor-swiftpm-sources.sh")
  if [[ "$DRY_RUN" == "1" && -n "$SOURCE_DIR" ]]; then
    append_package_resolved_files_from_source "$SOURCE_DIR"
    dependency_args+=("${PACKAGE_RESOLVED_ARGS[@]}")
  else
    dependency_args+=("--app" "$APP_NAME")
  fi
  [[ "$RESOLVE_DEPENDENCIES" == "1" ]] || dependency_args+=("--no-resolve")
  [[ "$FULL_DEPENDENCIES" == "0" ]] || dependency_args+=("--full")
  [[ "$DRY_RUN" == "0" ]] || dependency_args+=("--dry-run")
  [[ -z "$SCRATCH_PATH" ]] || dependency_args+=("--scratch-path" "$SCRATCH_PATH")
  "${dependency_args[@]}"
fi
