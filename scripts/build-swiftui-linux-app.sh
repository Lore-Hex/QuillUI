#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"
source "$ROOT_DIR/scripts/quillui-vendored-source.sh"

PROFILE_DIR="$ROOT_DIR/scripts/profiles"
PROFILE="${QUILLUI_APP_PROFILE:-enchanted-full-source}"
SOURCE_APP="${QUILLUI_APP_SOURCE_APP:-}"
SOURCE_SUBDIR="${QUILLUI_APP_SOURCE_SUBDIR:-}"
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
PREPARED_PACKAGE_CACHE_DIR="${QUILLUI_APP_PREPARED_PACKAGE_CACHE_DIR:-}"
VENDOR_SWIFTPM_SOURCES="${QUILLUI_APP_VENDOR_SWIFTPM_SOURCES:-auto}"
VENDOR_SWIFTPM_RESOLVE="${QUILLUI_APP_VENDOR_SWIFTPM_RESOLVE:-0}"
VENDOR_SWIFTPM_STAMP_DIR="${QUILLUI_APP_VENDOR_SWIFTPM_STAMP_DIR:-}"
NORMALIZED_BACKEND_FACADE=""
ARTIFACT_PATH_FILE="${QUILLUI_APP_ARTIFACT_PATH_FILE:-}"
RUN_AFTER_BUILD=0
LIST_PROFILES=0

usage() {
  cat <<MSG
Usage: $(basename "$0") (--source-dir PATH | --source-app NAME) --app-type TYPE [options]

Builds a SwiftUI-shaped app for Linux from generated sources without editing
the app tree.

Options:
  --profile NAME        Lowering profile to use.
  --list-profiles      Show installed lowering profiles and exit.
  --source-app NAME     Resolve source from vendor/apps/NAME first, then
                        .upstream/NAME. Use with --source-subdir for app
                        trees whose Swift sources live below the checkout root.
  --source-subdir PATH  Relative source path inside --source-app checkout.
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
  --prepared-package-cache-dir PATH
                        Shared cache for QuillUI-prepared local SwiftPM
                        dependency sources. Defaults to
                        .build/quillui-prepared-packages-cache.
  --vendor-swiftpm-sources
                        Before lowering a --source-app build, scan the app's
                        Package.resolved files and copy matching local SwiftPM
                        checkouts into third_party/. This is the default for
                        --source-app builds. Uses --no-resolve by default; set
                        QUILLUI_APP_VENDOR_SWIFTPM_RESOLVE=1 to run swift
                        package resolve first.
  --artifact-path-file PATH
                        Write the built executable path to PATH for wrappers.
  --run                Run the built executable after building.
  -h, --help           Show this help.

Environment aliases:
  QUILLUI_APP_PROFILE
  QUILLUI_APP_SOURCE_APP
  QUILLUI_APP_SOURCE_SUBDIR
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
  QUILLUI_APP_PREPARED_PACKAGE_CACHE_DIR
  QUILLUI_APP_VENDOR_SWIFTPM_SOURCES=auto  Auto-vendor local SwiftPM source for
                        --source-app builds. Set 0 to disable or 1 to require.
  QUILLUI_APP_VENDOR_SWIFTPM_RESOLVE
  QUILLUI_APP_VENDOR_SWIFTPM_STAMP_DIR
                        Cache directory for successful app lockfile-to-vendored
                        dependency scans. Defaults to
                        .build/quillui-vendored-swiftpm-source-stamps.
  QUILLUI_APP_ARTIFACT_PATH_FILE
  QUILLUI_REQUIRE_VENDORED_SOURCES=0  Allow generated packages to keep URL
                        dependencies instead of requiring local vendored sources.
  QUILLUI_RUNTIME_ONLY_MACROS=0       Compile QuillUI macro plugin targets
                        during the generated app runtime build. Defaults to 1
                        because generated app sources are lowered before build.
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

validate_source_app_name() {
  local value="$1"

  if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "--source-app must be a simple app source name, got: $value" >&2
    exit 64
  fi
}

validate_boolean_flag() {
  local value="$1"
  local label="$2"

  case "$value" in
    0|1|true|false|TRUE|FALSE|yes|no|YES|NO|on|off|ON|OFF)
      ;;
    *)
      echo "$label must be a boolean flag, got: $value" >&2
      exit 64
      ;;
  esac
}

validate_vendor_swiftpm_sources_mode() {
  local value="$1"
  local label="$2"

  case "$value" in
    auto|AUTO|Auto|0|1|true|false|TRUE|FALSE|yes|no|YES|NO|on|off|ON|OFF)
      ;;
    *)
      echo "$label must be auto or a boolean flag, got: $value" >&2
      exit 64
      ;;
  esac
}

truthy_flag() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

vendor_swiftpm_app_stamp_key() {
  local app_name="$1"
  local checkout_dir="$2"
  local resolve_mode="$3"

  python3 - "$ROOT_DIR" "$app_name" "$checkout_dir" "$resolve_mode" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
app_name = sys.argv[2]
checkout = Path(sys.argv[3]).resolve()
resolve_mode = sys.argv[4]
excluded_dirs = {".git", ".build", "DerivedData"}

digest = hashlib.sha256()
digest.update(b"quillui-vendored-swiftpm-app/v1\0")
digest.update(app_name.encode("utf-8"))
digest.update(b"\0")
digest.update(resolve_mode.encode("utf-8"))
digest.update(b"\0")

for relative_script in ("scripts/vendor-swiftpm-sources.sh", "scripts/quillui-vendored-source.sh"):
    script = root / relative_script
    digest.update(relative_script.encode("utf-8"))
    digest.update(b"\0")
    if script.is_file():
        data = script.read_bytes()
        digest.update(str(len(data)).encode("utf-8"))
        digest.update(b":")
        digest.update(data)
    digest.update(b"\0")

for path in sorted(checkout.rglob("Package.resolved")):
    relative = path.relative_to(checkout)
    if any(part in excluded_dirs or part.startswith(".build-") for part in relative.parts):
        continue
    data = path.read_bytes()
    digest.update(str(relative).encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(len(data)).encode("utf-8"))
    digest.update(b":")
    digest.update(data)
    digest.update(b"\0")

print(digest.hexdigest())
PY
}

run_vendor_swiftpm_sources_for_app() {
  local app_name="$1"
  local checkout_dir="$2"
  local stamp_key=""
  local stamp_file=""
  local vendor_swiftpm_args=("$ROOT_DIR/scripts/vendor-swiftpm-sources.sh" "--app" "$app_name")

  if ! truthy_flag "$VENDOR_SWIFTPM_RESOLVE"; then
    vendor_swiftpm_args+=("--no-resolve")
  fi

  if truthy_flag "$VENDOR_SWIFTPM_RESOLVE" || truthy_flag "${QUILLUI_VENDOR_FORCE:-0}"; then
    "${vendor_swiftpm_args[@]}"
    return
  fi

  stamp_key="$(vendor_swiftpm_app_stamp_key "$app_name" "$checkout_dir" "$VENDOR_SWIFTPM_RESOLVE")"
  stamp_file="$VENDOR_SWIFTPM_STAMP_DIR/$app_name-$stamp_key.stamp"
  if [[ -f "$stamp_file" ]]; then
    echo "Reused vendored SwiftPM source scan: $stamp_file"
    return
  fi

  "${vendor_swiftpm_args[@]}"
  mkdir -p "$VENDOR_SWIFTPM_STAMP_DIR"
  {
    printf 'quillui-vendored-swiftpm-app/v1\n'
    printf 'app=%s\n' "$app_name"
    printf 'key=%s\n' "$stamp_key"
  } > "$stamp_file"
}

vendor_swiftpm_sources_enabled() {
  case "${VENDOR_SWIFTPM_SOURCES:-}" in
    auto|AUTO|Auto)
      [[ -n "$SOURCE_APP" ]]
      ;;
    *)
      truthy_flag "$VENDOR_SWIFTPM_SOURCES"
      ;;
  esac
}

validate_relative_source_path() {
  local value="$1"
  local label="$2"

  if [[ -z "$value" ]]; then
    return
  fi
  case "$value" in
    /*|.*|*/../*|../*|*/..)
      echo "$label must be a relative path inside the app checkout, got: $value" >&2
      exit 64
      ;;
  esac
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
    --source-app)
      SOURCE_APP="${2:-}"
      shift 2
      ;;
    --source-subdir)
      SOURCE_SUBDIR="${2:-}"
      shift 2
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
    --prepared-package-cache-dir)
      PREPARED_PACKAGE_CACHE_DIR="${2:-}"
      shift 2
      ;;
    --prepared-package-cache-dir=*)
      PREPARED_PACKAGE_CACHE_DIR="${1#--prepared-package-cache-dir=}"
      shift
      ;;
    --vendor-swiftpm-sources)
      VENDOR_SWIFTPM_SOURCES=1
      shift
      ;;
    --no-vendor-swiftpm-sources)
      VENDOR_SWIFTPM_SOURCES=0
      shift
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

if [[ -n "$PACKAGE_ROOT" && ! -f "$PACKAGE_ROOT/Package.swift" ]]; then
  echo "--package-root does not contain Package.swift: $PACKAGE_ROOT" >&2
  exit 66
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  cat >&2 <<'MSG'
The SwiftUI-to-Linux app build must run on Linux because QuillUI's SwiftUI,
SwiftData, Apple platform, GTK, OpenCombine, and package-compatibility
products are Linux-only in this toolchain.
MSG
  exit 64
fi

if [[ -z "$SOURCE_DIR" && -z "$SOURCE_APP" ]]; then
  echo "--source-dir, --source-app, QUILLUI_APP_SOURCE_DIR, or QUILLUI_APP_SOURCE_APP is required" >&2
  usage >&2
  exit 64
fi

if [[ -z "$APP_TYPE" ]]; then
  echo "--app-type or QUILLUI_APP_ENTRY_TYPE is required" >&2
  usage >&2
  exit 64
fi

validate_swift_type "$APP_TYPE" "--app-type"

if [[ -n "$SOURCE_APP" ]]; then
  validate_source_app_name "$SOURCE_APP"
  validate_relative_source_path "$SOURCE_SUBDIR" "--source-subdir"
fi
validate_vendor_swiftpm_sources_mode "$VENDOR_SWIFTPM_SOURCES" "QUILLUI_APP_VENDOR_SWIFTPM_SOURCES"
validate_boolean_flag "$VENDOR_SWIFTPM_RESOLVE" "QUILLUI_APP_VENDOR_SWIFTPM_RESOLVE"

if truthy_flag "$VENDOR_SWIFTPM_SOURCES" && [[ -z "$SOURCE_APP" ]]; then
  echo "--vendor-swiftpm-sources requires --source-app so Package.resolved discovery has an app checkout root" >&2
  exit 64
fi

if [[ -z "$SOURCE_DIR" && -n "$SOURCE_APP" ]]; then
  if ! SOURCE_CHECKOUT_DIR="$(quillui_resolve_app_checkout_dir "$ROOT_DIR" "$SOURCE_APP")"; then
    cat >&2 <<MSG
Vendored app source was not found for:
  $SOURCE_APP

Expected one of:
  $ROOT_DIR/vendor/apps/$SOURCE_APP
  $ROOT_DIR/.upstream/$SOURCE_APP

Run scripts/fetch-upstream.sh $SOURCE_APP, add the checkout under
vendor/apps/$SOURCE_APP, or pass --source-dir explicitly.
MSG
    exit 66
  fi
  if [[ -n "$SOURCE_SUBDIR" ]]; then
    SOURCE_DIR="$SOURCE_CHECKOUT_DIR/$SOURCE_SUBDIR"
  else
    SOURCE_DIR="$SOURCE_CHECKOUT_DIR"
  fi
  case "$SOURCE_CHECKOUT_DIR" in
    "$ROOT_DIR/vendor/apps/$SOURCE_APP")
      echo "==> using vendored $SOURCE_APP source at vendor/apps/$SOURCE_APP"
      ;;
    "$ROOT_DIR/.upstream/$SOURCE_APP")
      echo "==> using upstream $SOURCE_APP source at .upstream/$SOURCE_APP"
      ;;
    *)
      echo "==> using $SOURCE_APP source at $SOURCE_CHECKOUT_DIR"
      ;;
  esac
  if [[ -z "$PACKAGE_ROOT" && -f "$SOURCE_CHECKOUT_DIR/Package.swift" ]]; then
    PACKAGE_ROOT="$SOURCE_CHECKOUT_DIR"
  fi
fi

if [[ -z "$VENDOR_SWIFTPM_STAMP_DIR" ]]; then
  VENDOR_SWIFTPM_STAMP_DIR="$ROOT_DIR/.build/quillui-vendored-swiftpm-source-stamps"
fi
case "$VENDOR_SWIFTPM_STAMP_DIR" in
  /*) ;;
  *) VENDOR_SWIFTPM_STAMP_DIR="$ROOT_DIR/$VENDOR_SWIFTPM_STAMP_DIR" ;;
esac

if vendor_swiftpm_sources_enabled; then
  run_vendor_swiftpm_sources_for_app "$SOURCE_APP" "$SOURCE_CHECKOUT_DIR"
fi

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

if [[ -z "$PREPARED_PACKAGE_CACHE_DIR" ]]; then
  PREPARED_PACKAGE_CACHE_DIR="$ROOT_DIR/.build/quillui-prepared-packages-cache"
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
QUILLUI_GENERATED_PREPARED_PACKAGE_CACHE_DIR="$PREPARED_PACKAGE_CACHE_DIR" \
QUILLUI_REQUIRE_VENDORED_SOURCES="${QUILLUI_REQUIRE_VENDORED_SOURCES:-1}" \
"$PROFILE_SCRIPT"

if [[ "$NORMALIZED_BACKEND_FACADE" == "qt" ]]; then
  BIN_DIR="$(QUILLUI_RUNTIME_ONLY_MACROS="${QUILLUI_RUNTIME_ONLY_MACROS:-1}" QUILLUI_LINUX_BACKEND=qt "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
    --disable-index-store \
    --package-path "$WORK_ROOT/package" \
    --scratch-path "$WORK_ROOT/.build-check" \
    --show-bin-path)"
else
  "$ROOT_DIR/scripts/prepare-linux-build-backend.sh" \
    --backend gtk \
    --scratch-path "$WORK_ROOT/.build-check"
  BIN_DIR="$(QUILLUI_RUNTIME_ONLY_MACROS="${QUILLUI_RUNTIME_ONLY_MACROS:-1}" QUILLUI_LINUX_BACKEND=gtk "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
    --disable-index-store \
    --package-path "$WORK_ROOT/package" \
    --scratch-path "$WORK_ROOT/.build-check" \
    --show-bin-path)"
fi
ARTIFACT_PATH="$BIN_DIR/$PRODUCT_NAME"
GENERATED_APP_RESOURCES_DIR="$WORK_ROOT/package/Sources/GeneratedSwiftUILinuxApp/Resources"
if [[ -d "$GENERATED_APP_RESOURCES_DIR" ]]; then
  python3 "$ROOT_DIR/scripts/materialize-swiftui-linux-main-bundle-resources.py" \
    --resources-dir "$GENERATED_APP_RESOURCES_DIR" \
    --bundle-dir "$BIN_DIR"
fi

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
