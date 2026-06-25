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
TARGET_LAYOUT_FILE="${QUILLUI_GENERATED_TARGET_LAYOUT_FILE:-}"
EXTRA_PACKAGE_DEPENDENCIES_FILE="${QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}"
EXTRA_TARGET_DEPENDENCIES_FILE="${QUILLUI_GENERATED_EXTRA_TARGET_DEPENDENCIES_FILE:-}"
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

validate_relative_path() {
  local value="$1"
  local label="$2"

  if [[ -z "$value" || "$value" = /* || "$value" == *"/../"* || "$value" == ../* || "$value" == *"/.." ]]; then
    echo "$label must stay relative to the generated source dir, got: ${value:-<empty>}" >&2
    exit 65
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
target_definitions=""
extra_package_dependencies=""
extra_target_dependencies=""
generated_swift_count_dir="$TARGET_DIR"

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
                .product(name: "Network", package: "QuillUI"),
                .product(name: "CryptoKit", package: "QuillUI"),
                .product(name: "Alamofire", package: "QuillUI"),
                .product(name: "os", package: "QuillUI"),
                .product(name: "QuillUI", package: "QuillUI"),
                .product(name: "QuillKit", package: "QuillUI"),
                .product(name: "QuillData", package: "QuillUI"),
                .product(name: "QuillFoundation", package: "QuillUI"),
                .product(name: "QuillShims", package: "QuillUI")'

swift_dependency_entry() {
  local dependency="$1"
  local kind=""
  local product_name=""
  local package_name=""
  local extra=""

  if [[ "$dependency" == product:* ]]; then
    IFS=: read -r kind product_name package_name extra <<<"$dependency"
    if [[ "$kind" != "product" || -z "$product_name" || -z "$package_name" || -n "${extra:-}" ]]; then
      echo "Invalid product dependency token: $dependency" >&2
      exit 65
    fi
    validate_package_token "$product_name" "product dependency name"
    validate_package_token "$package_name" "product dependency package"
    printf '                .product(name: "%s", package: "%s")' "$product_name" "$package_name"
  else
    validate_package_token "$dependency" "target dependency name"
    printf '                "%s"' "$dependency"
  fi
}

dependencies_block() {
  local dependency_list="${1:-}"
  local block="$source_target_dependencies"
  local dependency=""
  local entry=""

  IFS=, read -ra dependencies <<<"$dependency_list"
  for dependency in "${dependencies[@]}"; do
    dependency="${dependency#"${dependency%%[![:space:]]*}"}"
    dependency="${dependency%"${dependency##*[![:space:]]}"}"
    [[ -n "$dependency" ]] || continue
    entry="$(swift_dependency_entry "$dependency")"
    block="$(printf '%s,\n%s' "$block" "$entry")"
  done

  printf '%s' "$block"
}

swift_string_literal() {
  python3 - "$1" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1]))
PY
}

vendored_extra_package_dependency() {
  local package_line="$1"
  local package_url=""
  local package_name=""
  local identity=""
  local identity_lower=""
  local candidate=""
  local candidates=()
  local quoted_path=""

  package_url="$(printf '%s\n' "$package_line" | sed -nE 's/.*\.package\((name:[^,]+,[[:space:]]*)?url:[[:space:]]*"([^"]+)".*/\2/p')"
  [[ -n "$package_url" ]] || {
    printf '%s\n' "$package_line"
    return 0
  }

  package_name="$(printf '%s\n' "$package_line" | sed -nE 's/.*\.package\(name:[[:space:]]*"([^"]+)".*/\1/p')"
  identity="${package_url%%\?*}"
  identity="${identity%%#*}"
  identity="${identity##*/}"
  identity="${identity%.git}"
  identity_lower="$(printf '%s' "$identity" | tr '[:upper:]' '[:lower:]')"

  candidates=("$ROOT_DIR/third_party/$identity")
  if [[ -n "$package_name" ]]; then
    candidates+=("$ROOT_DIR/third_party/$package_name")
  fi
  candidates+=("$ROOT_DIR/third_party/$identity_lower")

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/Package.swift" ]]; then
      quoted_path="$(swift_string_literal "$candidate")"
      if [[ -n "$package_name" ]]; then
        printf '.package(name: "%s", path: %s)\n' "$package_name" "$quoted_path"
      else
        printf '.package(path: %s)\n' "$quoted_path"
      fi
      return 0
    fi
  done

  printf '%s\n' "$package_line"
}

append_target_definition() {
  local target_name="$1"
  local dependency_list="$2"
  local resources_line="$3"
  local target_kind=".target"
  local target_dependency_entries

  target_dependency_entries="$(dependencies_block "$dependency_list")"
  if [[ "$target_name" == "$TARGET_NAME" ]]; then
    target_kind=".executableTarget"
  fi
  if [[ "$target_name" == "$TARGET_NAME" && "$BACKEND_FACADE" == "gtk" ]]; then
    target_dependency_entries="$(printf '%s,\n                .product(name: "QuillUIGtk", package: "QuillUI")' "$target_dependency_entries")"
  fi
  if [[ -n "$target_definitions" ]]; then
    target_definitions+=$',
'
  fi
  target_definitions+=$(cat <<SWIFT
        $target_kind(
            name: "$target_name",
            dependencies: [
$target_dependency_entries
            ],
            path: "Sources/$target_name",
$resources_line
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
SWIFT
)
}

copy_swift_sources() {
  local source_root="$1"
  local destination_root="$2"
  local source_file
  local relative_path
  local destination_file

  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#$source_root/}"
    destination_file="$destination_root/$relative_path"
    if [[ "$(basename "$destination_file")" == "main.swift" ]]; then
      destination_file="$(dirname "$destination_file")/QuillGeneratedMainSource.swift"
    fi
    mkdir -p "$(dirname "$destination_file")"
    cp "$source_file" "$destination_file"
  done < <(find "$source_root" -name '*.swift' -print0)
}

copy_resources_line() {
  local source_root="$1"
  local target_root="$2"
  local target_resource_dir="$target_root/Resources"

  python3 "$ROOT_DIR/scripts/copy-swiftui-linux-resources.py" \
    --source-dir "$source_root" \
    --output-dir "$target_resource_dir" >/dev/null
  if [[ -d "$target_resource_dir" ]]; then
    printf '            resources: [.copy("Resources")],\n'
  fi
}

if [[ -n "$EXTRA_PACKAGE_DEPENDENCIES_FILE" ]]; then
  if [[ ! -f "$EXTRA_PACKAGE_DEPENDENCIES_FILE" ]]; then
    echo "Extra package dependency file was not found: $EXTRA_PACKAGE_DEPENDENCIES_FILE" >&2
    exit 66
  fi
  while IFS= read -r package_line || [[ -n "$package_line" ]]; do
    package_line="${package_line%%#*}"
    package_line="${package_line#"${package_line%%[![:space:]]*}"}"
    package_line="${package_line%"${package_line##*[![:space:]]}"}"
    [[ -n "$package_line" ]] || continue
    package_line="$(vendored_extra_package_dependency "$package_line")"
    extra_package_dependencies+=$(printf ',\n        %s' "$package_line")
  done < "$EXTRA_PACKAGE_DEPENDENCIES_FILE"
fi

if [[ -n "$EXTRA_TARGET_DEPENDENCIES_FILE" ]]; then
  if [[ ! -f "$EXTRA_TARGET_DEPENDENCIES_FILE" ]]; then
    echo "Extra target dependency file was not found: $EXTRA_TARGET_DEPENDENCIES_FILE" >&2
    exit 66
  fi
  while IFS= read -r dependency_line || [[ -n "$dependency_line" ]]; do
    dependency_line="${dependency_line%%#*}"
    dependency_line="${dependency_line#"${dependency_line%%[![:space:]]*}"}"
    dependency_line="${dependency_line%"${dependency_line##*[![:space:]]}"}"
    [[ -n "$dependency_line" ]] || continue
    if [[ -n "$extra_target_dependencies" ]]; then
      extra_target_dependencies+=","
    fi
    extra_target_dependencies+="$dependency_line"
  done < "$EXTRA_TARGET_DEPENDENCIES_FILE"
fi

if [[ "$copy_source_files" == "1" ]]; then
  if [[ -n "$TARGET_LAYOUT_FILE" ]]; then
    if [[ ! -f "$TARGET_LAYOUT_FILE" ]]; then
      echo "Target layout file was not found: $TARGET_LAYOUT_FILE" >&2
      exit 66
    fi

    layout_targets=$'\n'
    while IFS=$'\t' read -r layout_target layout_source_dir layout_dependencies layout_extra || [[ -n "${layout_target:-}" ]]; do
      layout_target="${layout_target%%#*}"
      [[ -n "${layout_target//[[:space:]]/}" ]] || continue
      if [[ -n "${layout_extra:-}" ]]; then
        echo "Target layout rows must have at most 3 tab-separated columns: $layout_target" >&2
        exit 65
      fi
      validate_swift_identifier "$layout_target" "target layout target name"
      validate_relative_path "$layout_source_dir" "target layout source dir"
      layout_source_root="$SOURCE_DIR/$layout_source_dir"
      if [[ ! -d "$layout_source_root" ]]; then
        echo "Target layout source directory was not found: $layout_source_root" >&2
        exit 66
      fi
      layout_target_root="$PACKAGE_DIR/Sources/$layout_target"
      mkdir -p "$layout_target_root"
      copy_swift_sources "$layout_source_root" "$layout_target_root"
      target_resources="$(copy_resources_line "$layout_source_root" "$layout_target_root")"
      layout_dependency_list="${layout_dependencies:-}"
      if [[ "$layout_target" == "$TARGET_NAME" && -n "$extra_target_dependencies" ]]; then
        if [[ -n "$layout_dependency_list" ]]; then
          layout_dependency_list+=",$extra_target_dependencies"
        else
          layout_dependency_list="$extra_target_dependencies"
        fi
      fi
      append_target_definition "$layout_target" "$layout_dependency_list" "$target_resources"
      layout_targets="${layout_targets}${layout_target}"$'\n'
    done < "$TARGET_LAYOUT_FILE"
    if [[ "$INCLUDE_BACKEND_ENTRY" == "1" && "$layout_targets" != *$'\n'"$TARGET_NAME"$'\n'* ]]; then
      echo "Target layout must include QUILLUI_GENERATED_TARGET_NAME=$TARGET_NAME when backend entry generation is enabled" >&2
      exit 65
    fi
    generated_swift_count_dir="$PACKAGE_DIR/Sources"
  else
    copy_swift_sources "$SOURCE_DIR" "$TARGET_DIR"

    target_resources="$(copy_resources_line "$SOURCE_DIR" "$TARGET_DIR")"
    append_target_definition "$TARGET_NAME" "$extra_target_dependencies" "$target_resources"
  fi
elif [[ "$BACKEND_FACADE" == "qt" ]]; then
  target_dependencies='                .product(name: "QuillGenericQtNativeRuntime", package: "QuillUI")'
fi

case "$BACKEND_FACADE" in
  qt)
    if [[ "$copy_source_files" == "1" ]]; then
      target_dependencies='                .product(name: "QuillGenericQtNativeRuntime", package: "QuillUI")'
    fi
    ;;
  gtk)
    target_dependencies="$(printf '%s,\n                .product(name: "QuillUIGtk", package: "QuillUI")' "$source_target_dependencies")"
    ;;
  swiftui)
    target_dependencies="$source_target_dependencies"
    ;;
esac

if [[ -z "$target_definitions" ]]; then
  target_definitions=$(cat <<SWIFT
        .executableTarget(
            name: "$TARGET_NAME",
            dependencies: [
$target_dependencies
            ],
$target_resources            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
SWIFT
)
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
        .package(name: "QuillUI", path: "$ROOT_DIR")$extra_package_dependencies
    ],
    targets: [
$target_definitions
    ]
)
SWIFT

source_count="$(find "$SOURCE_COUNT_DIR" -name '*.swift' | wc -l | tr -d ' ')"
generated_count="$(find "$generated_swift_count_dir" -name '*.swift' | wc -l | tr -d ' ')"

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
