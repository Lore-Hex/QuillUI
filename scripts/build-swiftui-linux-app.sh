#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${QUILLUI_APP_PROFILE:-enchanted-full-source}"
SOURCE_DIR="${QUILLUI_APP_SOURCE_DIR:-}"
APP_TYPE="${QUILLUI_APP_ENTRY_TYPE:-}"
PRODUCT_NAME="${QUILLUI_APP_PRODUCT_NAME:-}"
WORK_ROOT="${QUILLUI_APP_BUILD_WORKDIR:-}"
RUN_AFTER_BUILD=0

usage() {
  cat <<MSG
Usage: $(basename "$0") --source-dir PATH --app-type TYPE [options]

Builds a SwiftUI-shaped app for Linux from generated sources without editing
the app tree.

Options:
  --profile NAME        Lowering profile to use. Currently: enchanted-full-source.
  --source-dir PATH     Directory containing the app's Swift sources.
  --app-type TYPE       Swift App type to pass to GTK4Backend().run(...).
  --product-name NAME   Output executable name. Defaults from --app-type.
  --workdir PATH        Generated build work directory.
  --run                Run the built executable after building.
  -h, --help           Show this help.

Environment aliases:
  QUILLUI_APP_PROFILE
  QUILLUI_APP_SOURCE_DIR
  QUILLUI_APP_ENTRY_TYPE
  QUILLUI_APP_PRODUCT_NAME
  QUILLUI_APP_BUILD_WORKDIR
MSG
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

case "$PROFILE" in
  enchanted|enchanted-full-source)
    QUILLUI_APP_SOURCE_DIR="$SOURCE_DIR" \
    QUILLUI_GENERATED_APP_WORKDIR="$WORK_ROOT" \
    QUILLUI_GENERATED_APP_MODE=app \
    QUILLUI_GENERATED_APP_PRODUCT_NAME="$PRODUCT_NAME" \
    QUILLUI_GENERATED_APP_PACKAGE_NAME=GeneratedSwiftUILinuxApp \
    QUILLUI_GENERATED_APP_TARGET_NAME=GeneratedSwiftUILinuxApp \
    QUILLUI_GENERATED_APP_ENTRY_TYPE="$APP_TYPE" \
    QUILLUI_GENERATED_APP_MAIN_TYPE=GeneratedSwiftUILinuxMain \
    "$ROOT_DIR/scripts/generated-enchanted-full-source-check.sh"
    ;;
  *)
    cat >&2 <<MSG
Unsupported QuillUI app build profile: $PROFILE

Available profiles:
  enchanted-full-source
MSG
    exit 64
    ;;
esac

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
