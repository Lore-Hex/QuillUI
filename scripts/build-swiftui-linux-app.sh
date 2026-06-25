#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"

PROFILE_DIR="$ROOT_DIR/scripts/profiles"
PROFILE="${QUILLUI_APP_PROFILE:-enchanted-full-source}"
SOURCE_DIR="${QUILLUI_APP_SOURCE_DIR:-}"
PACKAGE_ROOT="${QUILLUI_APP_PACKAGE_ROOT:-}"
APP_TYPE="${QUILLUI_APP_ENTRY_TYPE:-}"
ENTRY_TARGET="${QUILLUI_APP_ENTRY_TARGET:-}"
PRODUCT_NAME="${QUILLUI_APP_PRODUCT_NAME:-}"
WORK_ROOT="${QUILLUI_APP_BUILD_WORKDIR:-}"
BACKEND_FACADE="${QUILLUI_APP_BACKEND_FACADE:-}"
TARGET_LAYOUT_FILE="${QUILLUI_APP_TARGET_LAYOUT_FILE:-}"
EXTRA_PACKAGE_DEPENDENCIES_FILE="${QUILLUI_APP_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}"
EXTRA_TARGET_DEPENDENCIES_FILE="${QUILLUI_APP_EXTRA_TARGET_DEPENDENCIES_FILE:-}"
NORMALIZED_BACKEND_FACADE=""
ARTIFACT_PATH_FILE="${QUILLUI_APP_ARTIFACT_PATH_FILE:-}"
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
  --package-root PATH   Optional SwiftPM package root used to auto-derive
                        multi-target layout when --target-layout-file is absent.
  --app-type TYPE       Swift App type to launch through the generated entry.
  --entry-target NAME   Optional SwiftPM executable target that owns --app-type.
                        When omitted, generic-swiftui infers it from sources.
  --product-name NAME   Output executable name. Defaults from --app-type.
  --workdir PATH        Generated build work directory.
  --backend-facade NAME Select QuillUI, QuillUIGtk, or the native Qt runtime
                        for the generated entry. Allowed: swiftui, gtk, qt.
  --target-layout-file PATH
                        TSV target layout for multi-target SwiftPM app trees.
  --extra-package-dependencies-file PATH
                        SwiftPM .package(...) lines needed by target layout deps.
  --extra-target-dependencies-file PATH
                        Target dependency tokens such as product:Name:Package.
  --artifact-path-file PATH
                        Write the built executable path to PATH for wrappers.
  --run                Run the built executable after building.
  -h, --help           Show this help.

Environment aliases:
  QUILLUI_APP_PROFILE
  QUILLUI_APP_SOURCE_DIR
  QUILLUI_APP_PACKAGE_ROOT
  QUILLUI_APP_ENTRY_TYPE
  QUILLUI_APP_ENTRY_TARGET
  QUILLUI_APP_PRODUCT_NAME
  QUILLUI_APP_BUILD_WORKDIR
  QUILLUI_APP_BACKEND_FACADE
  QUILLUI_APP_TARGET_LAYOUT_FILE
  QUILLUI_APP_EXTRA_PACKAGE_DEPENDENCIES_FILE
  QUILLUI_APP_EXTRA_TARGET_DEPENDENCIES_FILE
  QUILLUI_APP_ARTIFACT_PATH_FILE
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
    --package-root)
      PACKAGE_ROOT="${2:-}"
      shift 2
      ;;
    --app-type)
      APP_TYPE="${2:-}"
      shift 2
      ;;
    --entry-target)
      ENTRY_TARGET="${2:-}"
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
    --target-layout-file)
      TARGET_LAYOUT_FILE="${2:-}"
      shift 2
      ;;
    --extra-package-dependencies-file)
      EXTRA_PACKAGE_DEPENDENCIES_FILE="${2:-}"
      shift 2
      ;;
    --extra-target-dependencies-file)
      EXTRA_TARGET_DEPENDENCIES_FILE="${2:-}"
      shift 2
      ;;
    --artifact-path-file)
      ARTIFACT_PATH_FILE="${2:-}"
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

if ! NORMALIZED_BACKEND_FACADE="$(quillui_normalize_backend_identifier "${BACKEND_FACADE:-swiftui}")"; then
  echo "--backend-facade must be swiftui, gtk, or qt, got: ${BACKEND_FACADE:-<empty>}" >&2
  exit 64
fi

if [[ -n "$TARGET_LAYOUT_FILE" && ! -f "$TARGET_LAYOUT_FILE" ]]; then
  echo "--target-layout-file was not found: $TARGET_LAYOUT_FILE" >&2
  exit 66
fi

if [[ -n "$EXTRA_PACKAGE_DEPENDENCIES_FILE" && ! -f "$EXTRA_PACKAGE_DEPENDENCIES_FILE" ]]; then
  echo "--extra-package-dependencies-file was not found: $EXTRA_PACKAGE_DEPENDENCIES_FILE" >&2
  exit 66
fi

if [[ -n "$EXTRA_TARGET_DEPENDENCIES_FILE" && ! -f "$EXTRA_TARGET_DEPENDENCIES_FILE" ]]; then
  echo "--extra-target-dependencies-file was not found: $EXTRA_TARGET_DEPENDENCIES_FILE" >&2
  exit 66
fi

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

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
QUILLUI_PROFILE_PACKAGE_ROOT="$PACKAGE_ROOT" \
QUILLUI_PROFILE_WORKDIR="$WORK_ROOT" \
QUILLUI_PROFILE_MODE=app \
QUILLUI_PROFILE_PRODUCT_NAME="$PRODUCT_NAME" \
QUILLUI_PROFILE_PACKAGE_NAME=GeneratedSwiftUILinuxApp \
QUILLUI_PROFILE_TARGET_NAME=GeneratedSwiftUILinuxApp \
QUILLUI_PROFILE_ENTRY_TYPE="$APP_TYPE" \
QUILLUI_PROFILE_ENTRY_TARGET="$ENTRY_TARGET" \
QUILLUI_PROFILE_MAIN_TYPE=GeneratedSwiftUILinuxMain \
QUILLUI_GENERATED_BACKEND_FACADE="$NORMALIZED_BACKEND_FACADE" \
QUILLUI_GENERATED_TARGET_LAYOUT_FILE="$TARGET_LAYOUT_FILE" \
QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE="$EXTRA_PACKAGE_DEPENDENCIES_FILE" \
QUILLUI_GENERATED_EXTRA_TARGET_DEPENDENCIES_FILE="$EXTRA_TARGET_DEPENDENCIES_FILE" \
"$PROFILE_SCRIPT"

if [[ "$NORMALIZED_BACKEND_FACADE" == "qt" ]]; then
  BIN_DIR="$(QUILLUI_LINUX_BACKEND=qt "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
    --disable-index-store \
    --package-path "$WORK_ROOT/package" \
    --scratch-path "$WORK_ROOT/.build-check" \
    --show-bin-path)"
else
  "$ROOT_DIR/scripts/prepare-linux-build-backend.sh" \
    --backend gtk \
    --scratch-path "$WORK_ROOT/.build-check"
  BIN_DIR="$(QUILLUI_LINUX_BACKEND=gtk "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
    --disable-index-store \
    --package-path "$WORK_ROOT/package" \
    --scratch-path "$WORK_ROOT/.build-check" \
    --show-bin-path)"
fi
ARTIFACT_PATH="$BIN_DIR/$PRODUCT_NAME"

cat <<MSG
SwiftUI Linux build artifact:
  $ARTIFACT_PATH

Generated package:
  $WORK_ROOT/package
Profile:
  $PROFILE
MSG

if [[ -n "$ARTIFACT_PATH_FILE" ]]; then
  mkdir -p "$(dirname "$ARTIFACT_PATH_FILE")"
  printf '%s\n' "$ARTIFACT_PATH" > "$ARTIFACT_PATH_FILE"
fi

if [[ "$RUN_AFTER_BUILD" == "1" ]]; then
  "$ARTIFACT_PATH"
fi
