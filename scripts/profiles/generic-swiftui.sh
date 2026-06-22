#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DIR="${QUILLUI_PROFILE_SOURCE_DIR:-}"
PACKAGE_ROOT="${QUILLUI_PROFILE_PACKAGE_ROOT:-}"
ENTRY_TARGET="${QUILLUI_PROFILE_ENTRY_TARGET:-}"
WORK_ROOT="${QUILLUI_PROFILE_WORKDIR:-}"
PRODUCT_NAME="${QUILLUI_PROFILE_PRODUCT_NAME:-generic-swiftui-linux}"
PACKAGE_NAME="${QUILLUI_PROFILE_PACKAGE_NAME:-GeneratedSwiftUILinuxApp}"
TARGET_NAME="${QUILLUI_PROFILE_TARGET_NAME:-GeneratedSwiftUILinuxApp}"
ENTRY_TYPE="${QUILLUI_PROFILE_ENTRY_TYPE:-}"
MAIN_TYPE="${QUILLUI_PROFILE_MAIN_TYPE:-GeneratedSwiftUILinuxMain}"
BACKEND_FACADE="${QUILLUI_GENERATED_BACKEND_FACADE:-swiftui}"
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
SOURCE_COPY="$WORK_ROOT/source"
LOWERED_COPY="$WORK_ROOT/lowered"
PACKAGE_DIR="$WORK_ROOT/package"
AUTO_LAYOUT_DIR="$WORK_ROOT/swiftpm-layout"
rm -rf "$WORK_ROOT"
mkdir -p "$SOURCE_COPY"
cp -R "$SOURCE_DIR"/. "$SOURCE_COPY"/
"$ROOT_DIR/scripts/run-quill-source-lower.sh" "$SOURCE_COPY" "$LOWERED_COPY"
"$ROOT_DIR/scripts/lower-swiftui-source-for-linux.sh" "$LOWERED_COPY"

if [[ -z "${QUILLUI_GENERATED_TARGET_LAYOUT_FILE:-}" ]]; then
  if [[ -z "$PACKAGE_ROOT" ]]; then
    if [[ -f "$SOURCE_DIR/../Package.swift" ]]; then
      PACKAGE_ROOT="$(cd "$SOURCE_DIR/.." && pwd)"
    elif [[ -f "$SOURCE_DIR/Package.swift" ]]; then
      PACKAGE_ROOT="$(cd "$SOURCE_DIR" && pwd)"
    fi
  fi

  if [[ -n "$PACKAGE_ROOT" && -f "$PACKAGE_ROOT/Package.swift" ]]; then
    mkdir -p "$AUTO_LAYOUT_DIR"
    auto_layout_file="$AUTO_LAYOUT_DIR/target-layout.tsv"
    auto_dependencies_file="$AUTO_LAYOUT_DIR/package-dependencies.swift"
    auto_layout_args=(
      --package-root "$PACKAGE_ROOT"
      --source-dir "$SOURCE_DIR"
      --app-type "$ENTRY_TYPE"
      --generated-target "$TARGET_NAME"
      --layout-out "$auto_layout_file"
      --dependencies-out "$auto_dependencies_file"
    )
    if [[ -n "$ENTRY_TARGET" ]]; then
      auto_layout_args+=(--entry-target "$ENTRY_TARGET")
    fi
    "$ROOT_DIR/scripts/swiftpm-package-layout-for-linux.py" "${auto_layout_args[@]}"
    export QUILLUI_GENERATED_TARGET_LAYOUT_FILE="$auto_layout_file"

    if [[ -n "${QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}" && -s "$auto_dependencies_file" ]]; then
      combined_dependencies_file="$AUTO_LAYOUT_DIR/package-dependencies-combined.swift"
      cat "$QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE" "$auto_dependencies_file" > "$combined_dependencies_file"
      export QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE="$combined_dependencies_file"
    elif [[ -z "${QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}" ]]; then
      export QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE="$auto_dependencies_file"
    fi
  fi
fi

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
