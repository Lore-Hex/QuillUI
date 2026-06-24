#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
SCRATCH_PATH="$ROOT_DIR/.build"
RESOLVE=1
DRY_RUN=0
PACKAGES=()

usage() {
  cat <<'USAGE'
Usage: scripts/vendor-swiftpm-sources.sh [OPTIONS] [PACKAGE...]

Copy selected SwiftPM checkout sources into third_party/ so Package.swift can
use path dependencies instead of repeatedly creating remote working copies.

Default package set: OpenCombine

Options:
  --all                  Vendor every known SwiftPM package when its checkout exists.
  --scratch-path PATH    SwiftPM scratch path whose checkouts/ directory is used.
                         Defaults to .build.
  --no-resolve           Do not run swift package resolve before copying.
  --dry-run              Print the copies that would be performed.
  --list                 Print known package names.
  -h, --help             Show this help.
USAGE
}

known_packages() {
  cat <<'PACKAGES'
OpenCombine
GRDB.swift
swift-syntax
swift-crypto
swift-asn1
swift-protobuf
SwiftSoup
JavaScriptKit
PACKAGES
}

fail_usage() {
  echo "$1" >&2
  echo >&2
  usage >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      while IFS= read -r package; do
        PACKAGES+=("$package")
      done < <(known_packages)
      shift
      ;;
    --scratch-path)
      [[ $# -ge 2 ]] || fail_usage "--scratch-path requires a value."
      SCRATCH_PATH="$2"
      shift 2
      ;;
    --scratch-path=*)
      SCRATCH_PATH="${1#--scratch-path=}"
      shift
      ;;
    --no-resolve)
      RESOLVE=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --list)
      known_packages
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail_usage "Unsupported option: $1"
      ;;
    *)
      PACKAGES+=("$1")
      shift
      ;;
  esac
done

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  PACKAGES=(OpenCombine)
fi

case "$SCRATCH_PATH" in
  /*) ;;
  *) SCRATCH_PATH="$ROOT_DIR/$SCRATCH_PATH" ;;
esac

if [[ "$RESOLVE" == "1" && "$DRY_RUN" != "1" ]]; then
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift package resolve \
    --package-path "$ROOT_DIR" \
    --scratch-path "$SCRATCH_PATH"
fi

vendor_one() {
  local package="$1"
  local source="$SCRATCH_PATH/checkouts/$package"
  local destination="$ROOT_DIR/third_party/$package"

  if ! known_packages | grep -qx "$package"; then
    echo "error: unknown SwiftPM package '$package'. Use --list to see known packages." >&2
    return 64
  fi

  if [[ ! -d "$source" ]]; then
    if [[ -f "$destination/Package.swift" ]]; then
      echo "already vendored $package -> third_party/$package"
      return 0
    fi
    echo "warning: no checkout found for $package at $source; skipping" >&2
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "would vendor $package -> third_party/$package"
    return 0
  fi

  mkdir -p "$ROOT_DIR/third_party"
  rsync -a --delete \
    --exclude '.git' \
    --exclude '.build' \
    --exclude '.swiftpm' \
    --exclude 'Package.resolved' \
    "$source/" "$destination/"
  echo "vendored $package -> third_party/$package"
}

for package in "${PACKAGES[@]}"; do
  vendor_one "$package"
done
