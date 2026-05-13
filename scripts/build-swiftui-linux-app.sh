#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_DIR="$ROOT_DIR/scripts/profiles"
PROFILE="${QUILLUI_APP_PROFILE:-enchanted-full-source}"
SOURCE_DIR="${QUILLUI_APP_SOURCE_DIR:-}"
APP_TYPE="${QUILLUI_APP_ENTRY_TYPE:-}"
PRODUCT_NAME="${QUILLUI_APP_PRODUCT_NAME:-}"
WORK_ROOT="${QUILLUI_APP_BUILD_WORKDIR:-}"
BACKEND_FACADE="${QUILLUI_APP_BACKEND_FACADE:-}"
RUN_AFTER_BUILD=0
LIST_PROFILES=0

usage() {
  cat <<MSG
Usage: $(basename "$0") --source-dir PATH --app-type TYPE [options]

Builds a SwiftUI-shaped app for Linux from generated sources without editing
the app tree.

Options:
  --profile NAME        Lowering profile to use.
  --list-profiles      Show installed lowering profiles and exit.
  --source-dir PATH     Directory containing the app's Swift sources.
  --app-type TYPE       Swift App type to launch through the generated entry.
  --product-name NAME   Output executable name. Defaults from --app-type.
  --workdir PATH        Generated build work directory.
  --backend-facade NAME Import QuillUI, QuillUIGtk, or QuillUIQt in the
                        generated entry. Allowed: swiftui, gtk, qt.
  --run                Run the built executable after building.
  -h, --help           Show this help.

Environment aliases:
  QUILLUI_APP_PROFILE
  QUILLUI_APP_SOURCE_DIR
  QUILLUI_APP_ENTRY_TYPE
  QUILLUI_APP_PRODUCT_NAME
  QUILLUI_APP_BUILD_WORKDIR
  QUILLUI_APP_BACKEND_FACADE
MSG
}

list_profiles() {
  local profile_script
  local found=0

  for profile_script in "$PROFILE_DIR"/*.sh; do
    if [[ -f "$profile_script" && -x "$profile_script" ]]; then
      found=1
      basename "$profile_script" .sh
    fi
  done

  if [[ "$found" == "0" ]]; then
    echo "No profiles found in $PROFILE_DIR" >&2
    exit 1
  fi
}

default_product_name() {
  local value="$1"
  value="$(printf '%s' "$value" | sed -E 's/App$//')"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"

  if [[ -z "$value" ]]; then
    value="swiftui"
  fi

  printf '%s-linux' "$value"
}

validate_swift_type() {
  local value="$1"
  local label="$2"

  if [[ ! "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then
    echo "$label must be a Swift type path, got: $value" >&2
    exit 64
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --list-profiles)
      LIST_PROFILES=1
      shift
      ;;
    --source-dir)
      SOURCE_DIR="${2:-}"
      shift 2
      ;;
    --app-type)
      APP_TYPE="${2:-}"
      shift 2
      ;;
    --product-name)
      PRODUCT_NAME="${2:-}"
      shift 2
      ;;
    --workdir)
      WORK_ROOT="${2:-}"
      shift 2
      ;;
    --backend-facade)
      BACKEND_FACADE="${2:-}"
      shift 2
      ;;
    --run)
      RUN_AFTER_BUILD=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ "$LIST_PROFILES" == "1" ]]; then
  list_profiles
  exit 0
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  cat >&2 <<'MSG'
The SwiftUI-to-Linux app build must run on Linux because QuillUI's SwiftUI,
SwiftData, Apple platform, GTK, OpenCombine, and package-compatibility
products are Linux-only in this toolchain.
MSG
  exit 64
fi

if [[ -z "$SOURCE_DIR" ]]; then
  echo "--source-dir or QUILLUI_APP_SOURCE_DIR is required" >&2
  usage >&2
  exit 64
fi

if [[ -z "$APP_TYPE" ]]; then
  echo "--app-type or QUILLUI_APP_ENTRY_TYPE is required" >&2
  usage >&2
  exit 64
fi

validate_swift_type "$APP_TYPE" "--app-type"

if [[ ! -d "$SOURCE_DIR" ]]; then
  cat >&2 <<MSG
Swift app source was not found at:
  $SOURCE_DIR
MSG
  exit 66
fi

if [[ -z "$PRODUCT_NAME" ]]; then
  PRODUCT_NAME="$(default_product_name "$APP_TYPE")"
fi

if [[ -z "$WORK_ROOT" ]]; then
  WORK_ROOT="$ROOT_DIR/.build/$PRODUCT_NAME"
fi

PROFILE_SCRIPT="$PROFILE_DIR/$PROFILE.sh"
if [[ ! -x "$PROFILE_SCRIPT" ]]; then
  cat >&2 <<MSG
Unsupported QuillUI app build profile: $PROFILE

Available profiles:
$(list_profiles | sed 's/^/  /')
MSG
  exit 64
fi

QUILLUI_PROFILE_SOURCE_DIR="$SOURCE_DIR" \
QUILLUI_PROFILE_WORKDIR="$WORK_ROOT" \
QUILLUI_PROFILE_MODE=app \
QUILLUI_PROFILE_PRODUCT_NAME="$PRODUCT_NAME" \
QUILLUI_PROFILE_PACKAGE_NAME=GeneratedSwiftUILinuxApp \
QUILLUI_PROFILE_TARGET_NAME=GeneratedSwiftUILinuxApp \
QUILLUI_PROFILE_ENTRY_TYPE="$APP_TYPE" \
QUILLUI_PROFILE_MAIN_TYPE=GeneratedSwiftUILinuxMain \
QUILLUI_GENERATED_BACKEND_FACADE="$BACKEND_FACADE" \
"$PROFILE_SCRIPT"

BIN_DIR="$(swift build \
  --package-path "$WORK_ROOT/package" \
  --scratch-path "$WORK_ROOT/.build-check" \
  --show-bin-path)"
ARTIFACT_PATH="$BIN_DIR/$PRODUCT_NAME"

cat <<MSG
SwiftUI Linux build artifact:
  $ARTIFACT_PATH

Generated package:
  $WORK_ROOT/package
Profile:
  $PROFILE
MSG

if [[ "$RUN_AFTER_BUILD" == "1" ]]; then
  "$ARTIFACT_PATH"
fi
