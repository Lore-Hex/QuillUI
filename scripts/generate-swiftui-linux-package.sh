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
BACKEND_FACADE="${QUILLUI_GENERATED_BACKEND_FACADE:-swiftui}"
APP_ENTRY_TYPE="${QUILLUI_GENERATED_APP_ENTRY_TYPE:-}"
APP_MAIN_TYPE="${QUILLUI_GENERATED_APP_MAIN_TYPE:-GeneratedSwiftUILinuxMain}"
QT_NATIVE_CATALOG_ENTRY="${QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY:-QuillGenericQtAppCatalog.enchantedUpstreamSlice}"
REPORT_LABEL="${QUILLUI_GENERATED_REPORT_LABEL:-Generated SwiftUI Linux package}"

validate_boolean_flag() {
  local value="$1"
  local label="$2"

  case "$value" in
    0|1)
      ;;
    *)
      echo "$label must be 0 or 1, got: $value" >&2
      exit 64
      ;;
  esac
}

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

normalize_generated_backend_facade() {
  local value="${1:-swiftui}"
  local normalized

  if ! normalized="$(quillui_normalize_backend_identifier "$value")"; then
    echo "QUILLUI_GENERATED_BACKEND_FACADE must be swiftui, gtk, or qt, got: $value" >&2
    exit 64
  fi

  printf '%s\n' "$normalized"
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
validate_boolean_flag "$INCLUDE_BACKEND_ENTRY" "QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY"
BACKEND_FACADE="$(normalize_generated_backend_facade "$BACKEND_FACADE")"
if [[ "$INCLUDE_BACKEND_ENTRY" != "1" && "$BACKEND_FACADE" != "swiftui" ]]; then
  echo "QUILLUI_GENERATED_BACKEND_FACADE=$BACKEND_FACADE requires QUILLUI_GENERATED_INCLUDE_BACKEND_ENTRY=1" >&2
  exit 64
fi

"$ROOT_DIR/scripts/quillui-resource-guard.sh" "$ROOT_DIR" "${TMPDIR:-/tmp}"

TARGET_DIR="$PACKAGE_DIR/Sources/$TARGET_NAME"
RESOURCE_DIR="$TARGET_DIR/Resources"
backend_import="QuillUI"
backend_runner="QuillApp"
backend_launch_statement=""
copy_source_files=1
target_dependencies=""
target_resources=""

rm -rf "$PACKAGE_DIR"
mkdir -p "$TARGET_DIR"

if [[ "$INCLUDE_BACKEND_ENTRY" == "1" ]]; then
  if [[ -z "$APP_ENTRY_TYPE" ]]; then
    echo "QUILLUI_GENERATED_APP_ENTRY_TYPE is required when backend entry generation is enabled" >&2
    exit 64
  fi

  validate_swift_type "$APP_ENTRY_TYPE" "QUILLUI_GENERATED_APP_ENTRY_TYPE"
  validate_swift_type "$APP_MAIN_TYPE" "QUILLUI_GENERATED_APP_MAIN_TYPE"
  validate_swift_type "$QT_NATIVE_CATALOG_ENTRY" "QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY"

  case "$BACKEND_FACADE" in
    swiftui)
      ;;
    gtk)
      backend_import="QuillUIGtk"
      backend_runner="QuillGtkApp"
      ;;
    qt)
      backend_import="QuillGenericQtNativeRuntime"
      backend_launch_statement="QuillGenericQtNativeApp.run($QT_NATIVE_CATALOG_ENTRY)"
      copy_source_files=0
      ;;
  esac

  if [[ -z "$backend_launch_statement" ]]; then
    backend_launch_statement="${backend_runner}.run(${APP_ENTRY_TYPE}.self)"
  fi

  cat > "$TARGET_DIR/GeneratedMain.swift" <<SWIFT
import $backend_import

@main
struct $APP_MAIN_TYPE {
    static func main() {
        $backend_launch_statement
    }
}
SWIFT
fi

if [[ "$copy_source_files" == "1" ]]; then
  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#$SOURCE_DIR/}"
    destination_file="$TARGET_DIR/$relative_path"
    mkdir -p "$(dirname "$destination_file")"
    cp "$source_file" "$destination_file"
  done < <(find "$SOURCE_DIR" -name '*.swift' -print0)

  python3 "$ROOT_DIR/scripts/copy-swiftui-linux-resources.py" \
    --source-dir "$SOURCE_DIR" \
    --output-dir "$RESOURCE_DIR"
  if [[ -d "$RESOURCE_DIR" ]]; then
    target_resources='            resources: [.copy("Resources")],
'
  fi
fi

source_target_dependencies='                .product(name: "SwiftUI", package: "QuillUI"),
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
                .product(name: "QuillShims", package: "QuillUI")'

case "$BACKEND_FACADE" in
  qt)
    target_dependencies='                .product(name: "QuillGenericQtNativeRuntime", package: "QuillUI")'
    ;;
  gtk)
    target_dependencies="$(printf '%s,\n                .product(name: "QuillUIGtk", package: "QuillUI")' "$source_target_dependencies")"
    ;;
  swiftui)
    target_dependencies="$source_target_dependencies"
    ;;
esac

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
$target_dependencies
            ],
$target_resources
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
SWIFT

source_count="$(find "$SOURCE_COUNT_DIR" -name '*.swift' | wc -l | tr -d ' ')"
generated_count="$(find "$TARGET_DIR" -name '*.swift' | wc -l | tr -d ' ')"

if [[ "$BACKEND_FACADE" != "qt" ]]; then
  # SwiftOpenUI is now vendored in-tree (third_party/SwiftOpenUI). The synthetic
  # package consumes it TRANSITIVELY via its QuillUI path dependency, so it lives
  # at $ROOT_DIR/third_party/SwiftOpenUI — NOT under the synthetic $PACKAGE_DIR.
  # Point the patcher there explicitly; otherwise it defaults SWIFTOPENUI_ROOT to
  # $PACKAGE_DIR/third_party/SwiftOpenUI and fails with "manifest not found".
  # The patcher is idempotent (marker-guarded), so re-patching the shared in-tree
  # copy that the main build also patches is safe.
  QUILLUI_SWIFT_PACKAGE_PATH="$PACKAGE_DIR" QUILLUI_SWIFTOPENUI_ROOT="$ROOT_DIR/third_party/SwiftOpenUI" "$ROOT_DIR/scripts/patch-swiftopenui-gtk-css.sh" "$BUILD_SCRATCH"
fi

# The generated package compiles CGdkPixbuf (a system module wrapping
# <gdk-pixbuf/gdk-pixbuf.h>) regardless of backend facade, and the GTK facade
# additionally needs the gtk4 headers. The root Package.swift feeds these
# include paths to its own build via pkgConfigSwiftImporterFlags(); the
# generated scratch build needs the same, otherwise the compile fails with
# "'gdk-pixbuf/gdk-pixbuf.h' file not found" / "could not build C module
# 'CGdkPixbuf'". Mirror that here by passing pkg-config -I/-L/-l flags through.
quillui_build_args=(
  --disable-index-store
  --package-path "$PACKAGE_DIR"
  --scratch-path "$BUILD_SCRATCH"
  --product "$PRODUCT_NAME"
)

quillui_append_pkgconfig_flags() {
  local pkg="$1" flag
  if ! pkg-config --exists "$pkg" 2>/dev/null; then
    echo "warning: pkg-config has no '$pkg'; generated build may miss its include path" >&2
    return 0
  fi
  for flag in $(pkg-config --cflags-only-I "$pkg" 2>/dev/null); do
    quillui_build_args+=("-Xcc" "$flag")
  done
  for flag in $(pkg-config --libs-only-L --libs-only-l "$pkg" 2>/dev/null); do
    quillui_build_args+=("-Xlinker" "$flag")
  done
}

quillui_append_pkgconfig_flags "gdk-pixbuf-2.0"
if [[ "$BACKEND_FACADE" != "qt" ]]; then
  quillui_append_pkgconfig_flags "gtk4"
fi

if [[ "$BACKEND_FACADE" == "qt" ]]; then
  QUILLUI_LINUX_BACKEND=qt "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
    "${quillui_build_args[@]}"
else
  QUILLUI_LINUX_BACKEND=gtk "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
    "${quillui_build_args[@]}"
fi

cat <<MSG

$REPORT_LABEL completed.
Source Swift files copied: $source_count
Generated Swift files compiled: $generated_count
Product:
  $PRODUCT_NAME
Generated package:
  $PACKAGE_DIR

MSG
