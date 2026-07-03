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
QT_RUNTIME_MODE="${QUILLUI_APP_QT_RUNTIME_MODE:-${QUILLUI_GENERATED_QT_RUNTIME_MODE:-auto}}"
QT_NATIVE_CATALOG_ENTRY="${QUILLUI_APP_QT_NATIVE_CATALOG_ENTRY:-${QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY:-}}"
TARGET_LAYOUT_FILE="${QUILLUI_APP_TARGET_LAYOUT_FILE:-}"
EXTRA_PACKAGE_DEPENDENCIES_FILE="${QUILLUI_APP_EXTRA_PACKAGE_DEPENDENCIES_FILE:-}"
EXTRA_TARGET_DEPENDENCIES_FILE="${QUILLUI_APP_EXTRA_TARGET_DEPENDENCIES_FILE:-}"
PREPARED_PACKAGE_CACHE_DIR="${QUILLUI_APP_PREPARED_PACKAGE_CACHE_DIR:-}"
BUILD_SCRATCH="${QUILLUI_APP_BUILD_SCRATCH:-}"
BUILD_SCRATCH_CACHE_DIR="${QUILLUI_APP_BUILD_SCRATCH_CACHE_DIR:-}"
REUSE_BUILD_SCRATCH="${QUILLUI_APP_REUSE_BUILD_SCRATCH:-1}"
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
  --qt-runtime-mode MODE
                        Qt facade launch mode. Allowed: auto, generic, native.
                        auto uses native when --qt-native-catalog-entry is set;
                        otherwise it compiles copied app sources through
                        QuillUIQt.
  --qt-native-catalog-entry TYPE
                        Swift expression naming the reusable
                        QuillGenericQtAppCatalog entry used by --backend-facade qt.
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
  --build-scratch PATH  SwiftPM scratch path for the generated package build.
                        Defaults to a content-addressed cache below
                        .build/quillui-generated-app-build-cache.
  --build-scratch-cache-dir PATH
                        Cache directory used when --build-scratch is omitted.
  --no-reuse-build-scratch
                        Use WORKDIR/.build-check instead of the shared
                        generated app SwiftPM scratch cache.
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
  QUILLUI_APP_QT_RUNTIME_MODE=auto     Qt facade launch mode: auto, generic,
                        or native.
  QUILLUI_APP_QT_NATIVE_CATALOG_ENTRY
  QUILLUI_APP_TARGET_LAYOUT_FILE
  QUILLUI_APP_EXTRA_PACKAGE_DEPENDENCIES_FILE
  QUILLUI_APP_EXTRA_TARGET_DEPENDENCIES_FILE
  QUILLUI_APP_PREPARED_PACKAGE_CACHE_DIR
  QUILLUI_APP_BUILD_SCRATCH
  QUILLUI_APP_BUILD_SCRATCH_CACHE_DIR
  QUILLUI_APP_REUSE_BUILD_SCRATCH=1
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

normalize_qt_runtime_mode() {
  local value="${1:-auto}"

  case "$value" in
    auto|generic|native)
      printf '%s\n' "$value"
      ;;
    *)
      echo "--qt-runtime-mode must be auto, generic, or native, got: $value" >&2
      exit 64
      ;;
  esac
}

effective_qt_runtime_mode() {
  local mode="$1"
  local catalog_entry="$2"

  if [[ "$mode" == "auto" ]]; then
    if [[ -n "$catalog_entry" ]]; then
      printf '%s\n' native
    else
      printf '%s\n' generic
    fi
    return
  fi

  printf '%s\n' "$mode"
}

truthy_flag() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

absolute_path_from_root() {
  local path="$1"

  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s/%s\n' "$ROOT_DIR" "$path" ;;
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

vendor_swiftpm_app_packages() {
  local app_name="$1"

  "$ROOT_DIR/scripts/vendor-swiftpm-sources.sh" \
    --app "$app_name" \
    --no-resolve \
    --print-package-list
}

run_vendor_swiftpm_sources_for_app() {
  local app_name="$1"
  local checkout_dir="$2"
  local app_packages=()
  local package=""
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

  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    app_packages+=("$package")
  done < <(vendor_swiftpm_app_packages "$app_name")

  stamp_key="$(vendor_swiftpm_app_stamp_key "$app_name" "$checkout_dir" "$VENDOR_SWIFTPM_RESOLVE")"
  stamp_file="$VENDOR_SWIFTPM_STAMP_DIR/$app_name-$stamp_key.stamp"
  if [[ -f "$stamp_file" ]]; then
    if quillui_vendored_swiftpm_app_stamp_is_valid "$ROOT_DIR" "$stamp_file"; then
      echo "Reused vendored SwiftPM source scan: $stamp_file"
      return
    fi
    echo "Vendored SwiftPM source scan stamp is stale; refreshing: $stamp_file" >&2
  fi

  if "${vendor_swiftpm_args[@]}" --check-vendored >/dev/null; then
    echo "Vendored SwiftPM package sources already cover $app_name"
    quillui_write_vendored_swiftpm_app_stamp "$ROOT_DIR" "$stamp_file" "$app_name" "$stamp_key" "${app_packages[@]}"
    return
  fi

  "${vendor_swiftpm_args[@]}"
  if ! "${vendor_swiftpm_args[@]}" --check-vendored >/dev/null; then
    cat >&2 <<MSG
Vendored SwiftPM package sources are incomplete for $app_name.
Run scripts/vendor-swiftpm-sources.sh --app $app_name --hydrate-missing or set
QUILLUI_APP_VENDOR_SWIFTPM_RESOLVE=1 when network access is deliberately allowed.
MSG
    return 66
  fi
  quillui_write_vendored_swiftpm_app_stamp "$ROOT_DIR" "$stamp_file" "$app_name" "$stamp_key" "${app_packages[@]}"
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

generated_app_build_scratch_key() {
  local lowered_source_key="$1"
  local profile="$2"
  local source_dir="$3"
  local package_root="$4"
  local app_type="$5"
  local entry_target="$6"
  local product_name="$7"
  local backend_facade="$8"
  local qt_runtime_mode="$9"
  local target_layout_file="${10}"
  local extra_package_dependencies_file="${11}"
  local extra_target_dependencies_file="${12}"
  local qt_native_catalog_entry="${13}"

  python3 - "$ROOT_DIR" "$lowered_source_key" "$profile" "$source_dir" "$package_root" \
    "$app_type" "$entry_target" "$product_name" "$backend_facade" "$qt_runtime_mode" "$target_layout_file" \
    "$extra_package_dependencies_file" "$extra_target_dependencies_file" "$qt_native_catalog_entry" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
values = {
    "lowered_source_key": sys.argv[2],
    "profile": sys.argv[3],
    "source_dir": sys.argv[4],
    "package_root": sys.argv[5],
    "app_type": sys.argv[6],
    "entry_target": sys.argv[7],
    "product_name": sys.argv[8],
    "backend_facade": sys.argv[9],
    "qt_runtime_mode": sys.argv[10],
    "qt_native_catalog_entry": sys.argv[14] if len(sys.argv) > 14 else "",
}
extra_files = [value for value in sys.argv[11:14] if value]
excluded_dirs = {".build", ".git", ".quillui-build", ".swiftpm", "DerivedData", "node_modules", "xcuserdata"}
excluded_files = {".DS_Store"}

digest = hashlib.sha256()
digest.update(b"quillui-generated-app-build-scratch/v2\0")

for key, value in sorted(values.items()):
    digest.update(key.encode("utf-8"))
    digest.update(b"\0")
    digest.update(value.encode("utf-8"))
    digest.update(b"\0")

def update_file(path: Path, namespace: str, root_for_relative: Path) -> None:
    if not path.is_file() or path.name in excluded_files:
        return
    try:
        relative = path.resolve().relative_to(root_for_relative.resolve())
    except ValueError:
        relative = path.resolve()
    try:
        data = path.read_bytes()
    except OSError:
        return
    digest.update(namespace.encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(relative).encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(len(data)).encode("utf-8"))
    digest.update(b":")
    digest.update(data)
    digest.update(b"\0")

def update_tree(path: Path, namespace: str) -> None:
    if path.is_file():
        update_file(path, namespace, path.parent)
        return
    if not path.is_dir():
        return
    for item in sorted(path.rglob("*")):
        try:
            relative = item.relative_to(path)
        except ValueError:
            continue
        if any(part in excluded_dirs for part in relative.parts):
            continue
        if item.is_file():
            update_file(item, namespace, path)

for relative in [
    "Package.swift",
    "scripts/build-swiftui-linux-app.sh",
    "scripts/generate-swiftui-linux-package.sh",
    f"scripts/profiles/{values['profile']}.sh",
    "scripts/swiftpm-profile-auto-layout.sh",
    "scripts/swiftpm-profile-local-imports.sh",
    "scripts/prepare-swiftui-linux-package-dependencies.py",
    "scripts/discover-local-swiftpm-import-dependencies.py",
    "scripts/quillui-backend-products.sh",
]:
    update_tree(root / relative, "tool")

package_root = Path(values["package_root"]).expanduser() if values["package_root"] else None
if package_root is not None:
    if not package_root.is_absolute():
        package_root = root / package_root
    update_file(package_root / "Package.swift", "package-root", package_root)
    for path in sorted(package_root.rglob("Package.resolved")):
        try:
            relative = path.relative_to(package_root)
        except ValueError:
            continue
        if any(part in excluded_dirs for part in relative.parts):
            continue
        update_file(path, "package-lock", package_root)

for value in extra_files:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = root / path
    update_tree(path, "input")

print(digest.hexdigest())
PY
}

default_generated_build_scratch() {
  local lowered_source_key
  local build_scratch_key
  local safe_product

  if ! truthy_flag "$REUSE_BUILD_SCRATCH"; then
    printf '%s\n' "$WORK_ROOT/.build-check"
    return
  fi

  lowered_source_key="$(python3 "$ROOT_DIR/scripts/quillui-source-cache-key.py" --root-dir "$ROOT_DIR" --source-dir "$SOURCE_DIR")"
  build_scratch_key="$(generated_app_build_scratch_key \
    "$lowered_source_key" "$PROFILE" "$SOURCE_DIR" "$PACKAGE_ROOT" "$APP_TYPE" "$ENTRY_TARGET" \
    "$PRODUCT_NAME" "$NORMALIZED_BACKEND_FACADE" "$EFFECTIVE_QT_RUNTIME_MODE" "$TARGET_LAYOUT_FILE" \
    "$EXTRA_PACKAGE_DEPENDENCIES_FILE" "$EXTRA_TARGET_DEPENDENCIES_FILE" "$QT_NATIVE_CATALOG_ENTRY")"
  safe_product="$(printf '%s' "$PRODUCT_NAME" | tr -c 'A-Za-z0-9_.-' '-')"
  printf '%s/%s-%s-%s\n' "$BUILD_SCRATCH_CACHE_DIR" "$safe_product" "$NORMALIZED_BACKEND_FACADE" "${build_scratch_key:0:24}"
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
    --qt-runtime-mode)
      QT_RUNTIME_MODE="${2:-}"
      shift 2
      ;;
    --qt-runtime-mode=*)
      QT_RUNTIME_MODE="${1#--qt-runtime-mode=}"
      shift
      ;;
    --qt-native-catalog-entry)
      QT_NATIVE_CATALOG_ENTRY="${2:-}"
      shift 2
      ;;
    --qt-native-catalog-entry=*)
      QT_NATIVE_CATALOG_ENTRY="${1#--qt-native-catalog-entry=}"
      shift
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
    --build-scratch)
      BUILD_SCRATCH="${2:-}"
      shift 2
      ;;
    --build-scratch=*)
      BUILD_SCRATCH="${1#--build-scratch=}"
      shift
      ;;
    --build-scratch-cache-dir)
      BUILD_SCRATCH_CACHE_DIR="${2:-}"
      shift 2
      ;;
    --build-scratch-cache-dir=*)
      BUILD_SCRATCH_CACHE_DIR="${1#--build-scratch-cache-dir=}"
      shift
      ;;
    --no-reuse-build-scratch)
      REUSE_BUILD_SCRATCH=0
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
if [[ -n "$QT_NATIVE_CATALOG_ENTRY" ]]; then
  validate_swift_type "$QT_NATIVE_CATALOG_ENTRY" "--qt-native-catalog-entry"
fi

if [[ -n "$SOURCE_APP" ]]; then
  validate_source_app_name "$SOURCE_APP"
  validate_relative_source_path "$SOURCE_SUBDIR" "--source-subdir"
fi
validate_vendor_swiftpm_sources_mode "$VENDOR_SWIFTPM_SOURCES" "QUILLUI_APP_VENDOR_SWIFTPM_SOURCES"
validate_boolean_flag "$VENDOR_SWIFTPM_RESOLVE" "QUILLUI_APP_VENDOR_SWIFTPM_RESOLVE"
validate_boolean_flag "$REUSE_BUILD_SCRATCH" "QUILLUI_APP_REUSE_BUILD_SCRATCH"
QT_RUNTIME_MODE="$(normalize_qt_runtime_mode "$QT_RUNTIME_MODE")"

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
      quillui_print_vendored_app_source_summary "$ROOT_DIR" "$SOURCE_APP"
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
if [[ -z "$BUILD_SCRATCH_CACHE_DIR" ]]; then
  BUILD_SCRATCH_CACHE_DIR="$ROOT_DIR/.build/quillui-generated-app-build-cache"
else
  BUILD_SCRATCH_CACHE_DIR="$(absolute_path_from_root "$BUILD_SCRATCH_CACHE_DIR")"
fi

if ! NORMALIZED_BACKEND_FACADE="$(quillui_normalize_backend_identifier "${BACKEND_FACADE:-swiftui}")"; then
  echo "--backend-facade must be swiftui, gtk, or qt, got: ${BACKEND_FACADE:-<empty>}" >&2
  exit 64
fi
EFFECTIVE_QT_RUNTIME_MODE="generic"
if [[ "$NORMALIZED_BACKEND_FACADE" == "qt" ]]; then
  EFFECTIVE_QT_RUNTIME_MODE="$(effective_qt_runtime_mode "$QT_RUNTIME_MODE" "$QT_NATIVE_CATALOG_ENTRY")"
  if [[ "$EFFECTIVE_QT_RUNTIME_MODE" == "native" && -z "$QT_NATIVE_CATALOG_ENTRY" ]]; then
    echo "--qt-runtime-mode native requires --qt-native-catalog-entry, QUILLUI_APP_QT_NATIVE_CATALOG_ENTRY, or QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY" >&2
    exit 64
  fi
fi

if [[ -n "$BUILD_SCRATCH" ]]; then
  BUILD_SCRATCH="$(absolute_path_from_root "$BUILD_SCRATCH")"
else
  BUILD_SCRATCH="$(default_generated_build_scratch)"
fi
mkdir -p "$(dirname "$BUILD_SCRATCH")"
echo "==> generated app SwiftPM scratch: ${BUILD_SCRATCH#$ROOT_DIR/}"

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
QUILLUI_GENERATED_QT_RUNTIME_MODE="$EFFECTIVE_QT_RUNTIME_MODE" \
QUILLUI_GENERATED_TARGET_LAYOUT_FILE="$TARGET_LAYOUT_FILE" \
QUILLUI_GENERATED_EXTRA_PACKAGE_DEPENDENCIES_FILE="$EXTRA_PACKAGE_DEPENDENCIES_FILE" \
QUILLUI_GENERATED_EXTRA_TARGET_DEPENDENCIES_FILE="$EXTRA_TARGET_DEPENDENCIES_FILE" \
QUILLUI_GENERATED_PREPARED_PACKAGE_CACHE_DIR="$PREPARED_PACKAGE_CACHE_DIR" \
QUILLUI_GENERATED_BUILD_SCRATCH="$BUILD_SCRATCH" \
QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY="$QT_NATIVE_CATALOG_ENTRY" \
QUILLUI_REQUIRE_VENDORED_SOURCES="${QUILLUI_REQUIRE_VENDORED_SOURCES:-1}" \
"$PROFILE_SCRIPT"

quillui_generated_source_requires_macro_plugin() {
  local source_root="$1"

  grep -R -E -q --include='*.swift' '(^|[^[:alnum:]_])(@(Model|Attribute|Relationship|Transient)([^[:alnum:]_]|$)|#(Predicate|QuillPredicate)([^[:alnum:]_]|$))' "$source_root"
}

quillui_runtime_only_macros="${QUILLUI_RUNTIME_ONLY_MACROS:-1}"
validate_boolean_flag "$quillui_runtime_only_macros" "QUILLUI_RUNTIME_ONLY_MACROS"
if [[ "$quillui_runtime_only_macros" == "1" ]] && quillui_generated_source_requires_macro_plugin "$WORK_ROOT/package/Sources/GeneratedSwiftUILinuxApp"; then
  echo "==> generated source still contains Swift macro syntax; disabling runtime-only macro stubs"
  quillui_runtime_only_macros=0
fi

if [[ "$NORMALIZED_BACKEND_FACADE" == "qt" ]]; then
  BIN_DIR="$(QUILLUI_RUNTIME_ONLY_MACROS="$quillui_runtime_only_macros" QUILLUI_LINUX_BACKEND=qt "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
    --disable-index-store \
    --package-path "$WORK_ROOT/package" \
    --scratch-path "$BUILD_SCRATCH" \
    --show-bin-path)"
else
  "$ROOT_DIR/scripts/prepare-linux-build-backend.sh" \
    --backend gtk \
    --scratch-path "$BUILD_SCRATCH"
  BIN_DIR="$(QUILLUI_RUNTIME_ONLY_MACROS="$quillui_runtime_only_macros" QUILLUI_LINUX_BACKEND=gtk "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" swift build \
    --disable-index-store \
    --package-path "$WORK_ROOT/package" \
    --scratch-path "$BUILD_SCRATCH" \
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
