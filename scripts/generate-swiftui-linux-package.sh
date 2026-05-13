#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$ROOT_DIR/scripts/quillui-backend-products.sh"
quillui_alias_env QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY QUILLUI_GENERATED_INCLUDE_GTK_BACKEND QUILLUI_GENERATED_INCLUDE_QT_BACKEND

SOURCE_DIR="${QUILLUI_GENERATED_SOURCES_DIR:-}"
SOURCE_COUNT_DIR="${QUILLUI_GENERATED_SOURCE_COUNT_DIR:-$SOURCE_DIR}"
WORK_ROOT="${QUILLUI_GENERATED_WORKDIR:-}"
PACKAGE_DIR="${QUILLUI_GENERATED_PACKAGE_DIR:-${WORK_ROOT:+$WORK_ROOT/package}}"
PACKAGE_NAME="${QUILLUI_GENERATED_PACKAGE_NAME:-GeneratedSwiftUILinuxApp}"
PRODUCT_NAME="${QUILLUI_GENERATED_PRODUCT_NAME:-swiftui-linux-app}"
TARGET_NAME="${QUILLUI_GENERATED_TARGET_NAME:-GeneratedSwiftUILinuxApp}"
BUILD_SCRATCH="${QUILLUI_GENERATED_BUILD_SCRATCH:-${WORK_ROOT:+$WORK_ROOT/.build-check}}"
INCLUDE_BACKEND_ENTRY="${QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY:-0}"
APP_ENTRY_TYPE="${QUILLUI_GENERATED_APP_ENTRY_TYPE:-}"
APP_MAIN_TYPE="${QUILLUI_GENERATED_APP_MAIN_TYPE:-GeneratedSwiftUILinuxMain}"
REPORT_LABEL="${QUILLUI_GENERATED_REPORT_LABEL:-Generated SwiftUI Linux package}"

validate_swift_identifier() {
  local value="$1"
  local label="$2"

  if [[ ! "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "$label must be a Swift identifier, got: $value" >&2
    exit 64
  fi
}

validate_package_token() {
  local value="$1"
  local label="$2"

  if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "$label must contain only letters, digits, dot, underscore, or hyphen, got: $value" >&2
    exit 64
  fi
}

validate_swift_type() {
  local value="$1"
  local label="$2"

  if [[ ! "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]]; then
    echo "$label must be a Swift type path, got: $value" >&2
    exit 64
  fi
}

if [[ "$(uname -s)" != "Linux" ]]; then
  cat >&2 <<'MSG'
The generated SwiftUI Linux package builder must run on Linux because the
compatibility module products are Linux-only in this toolchain.
MSG
  exit 64
fi

if [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
  echo "QUILLUI_GENERATED_SOURCES_DIR must point to a directory of Swift sources" >&2
  exit 66
fi

if [[ -z "$PACKAGE_DIR" || "$PACKAGE_DIR" == "/" || "$PACKAGE_DIR" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generated package directory: ${PACKAGE_DIR:-<empty>}" >&2
  exit 73
fi

if [[ -z "$BUILD_SCRATCH" ]]; then
  echo "QUILLUI_GENERATED_BUILD_SCRATCH or QUILLUI_GENERATED_WORKDIR is required" >&2
  exit 64
fi

validate_package_token "$PACKAGE_NAME" "QUILLUI_GENERATED_PACKAGE_NAME"
validate_package_token "$PRODUCT_NAME" "QUILLUI_GENERATED_PRODUCT_NAME"
validate_swift_identifier "$TARGET_NAME" "QUILLUI_GENERATED_TARGET_NAME"

TARGET_DIR="$PACKAGE_DIR/Sources/$TARGET_NAME"

rm -rf "$PACKAGE_DIR"
mkdir -p "$TARGET_DIR"

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#$SOURCE_DIR/}"
  destination_file="$TARGET_DIR/$relative_path"
  mkdir -p "$(dirname "$destination_file")"
  cp "$source_file" "$destination_file"
done < <(find "$SOURCE_DIR" -name '*.swift' -print0)

if [[ "$INCLUDE_BACKEND_ENTRY" == "1" ]]; then
  if [[ -z "$APP_ENTRY_TYPE" ]]; then
    echo "QUILLUI_GENERATED_APP_ENTRY_TYPE is required when backend entry generation is enabled" >&2
    exit 64
  fi

  validate_swift_type "$APP_ENTRY_TYPE" "QUILLUI_GENERATED_APP_ENTRY_TYPE"
  validate_swift_type "$APP_MAIN_TYPE" "QUILLUI_GENERATED_APP_MAIN_TYPE"

  cat > "$TARGET_DIR/GeneratedMain.swift" <<SWIFT
import QuillUI

@main
struct $APP_MAIN_TYPE {
    static func main() {
        QuillApp.run($APP_ENTRY_TYPE.self)
    }
}
SWIFT
fi

cat > "$PACKAGE_DIR/Package.swift" <<SWIFT
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "$PACKAGE_NAME",
    products: [
        .executable(name: "$PRODUCT_NAME", targets: ["$TARGET_NAME"])
    ],
    dependencies: [
        .package(name: "QuillUI", path: "$ROOT_DIR")
    ],
    targets: [
        .executableTarget(
            name: "$TARGET_NAME",
            dependencies: [
                .product(name: "SwiftUI", package: "QuillUI"),
                .product(name: "SwiftData", package: "QuillUI"),
                .product(name: "Combine", package: "QuillUI"),
                .product(name: "UniformTypeIdentifiers", package: "QuillUI"),
                .product(name: "OllamaKit", package: "QuillUI"),
                .product(name: "MarkdownUI", package: "QuillUI"),
                .product(name: "Splash", package: "QuillUI"),
                .product(name: "ActivityIndicatorView", package: "QuillUI"),
                .product(name: "WrappingHStack", package: "QuillUI"),
                .product(name: "Vortex", package: "QuillUI"),
                .product(name: "KeyboardShortcuts", package: "QuillUI"),
                .product(name: "Magnet", package: "QuillUI"),
                .product(name: "Carbon", package: "QuillUI"),
                .product(name: "AsyncAlgorithms", package: "QuillUI"),
                .product(name: "AppKit", package: "QuillUI"),
                .product(name: "AVFoundation", package: "QuillUI"),
                .product(name: "Speech", package: "QuillUI"),
                .product(name: "PhotosUI", package: "QuillUI"),
                .product(name: "UIKit", package: "QuillUI"),
                .product(name: "IOKit", package: "QuillUI"),
                .product(name: "Security", package: "QuillUI"),
                .product(name: "ServiceManagement", package: "QuillUI"),
                .product(name: "Sparkle", package: "QuillUI"),
                .product(name: "ApplicationServices", package: "QuillUI"),
                .product(name: "CoreGraphics", package: "QuillUI"),
                .product(name: "Alamofire", package: "QuillUI"),
                .product(name: "os", package: "QuillUI"),
                // QuillUI core surface — Quill-specific helper
                // types referenced by the generated Enchanted source
                // (QuillObservableObject typealias, QuillHotkeyService,
                // QuillCheckForUpdatesMenuItem, etc.) live in the
                // main `QuillUI` module.
                .product(name: "QuillUI", package: "QuillUI"),
                .product(name: "QuillKit", package: "QuillUI"),
                .product(name: "QuillData", package: "QuillUI"),
                .product(name: "QuillFoundation", package: "QuillUI"),
                .product(name: "QuillShims", package: "QuillUI")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
SWIFT

source_count="$(find "$SOURCE_COUNT_DIR" -name '*.swift' | wc -l | tr -d ' ')"
generated_count="$(find "$TARGET_DIR" -name '*.swift' | wc -l | tr -d ' ')"

QUILLUI_SWIFT_PACKAGE_PATH="$PACKAGE_DIR" "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$BUILD_SCRATCH"

swift build \
  --package-path "$PACKAGE_DIR" \
  --scratch-path "$BUILD_SCRATCH" \
  --product "$PRODUCT_NAME"

cat <<MSG

$REPORT_LABEL completed.
Source Swift files copied: $source_count
Generated Swift files compiled: $generated_count
Product:
  $PRODUCT_NAME
Generated package:
  $PACKAGE_DIR

MSG
