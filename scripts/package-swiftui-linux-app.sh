#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-backend-products.sh"

PROFILE="${QUILLUI_APP_PROFILE:-enchanted-full-source}"
SOURCE_APP="${QUILLUI_APP_SOURCE_APP:-}"
SOURCE_SUBDIR="${QUILLUI_APP_SOURCE_SUBDIR:-}"
SOURCE_DIR="${QUILLUI_APP_SOURCE_DIR:-}"
APP_TYPE="${QUILLUI_APP_ENTRY_TYPE:-}"
PRODUCT_NAME="${QUILLUI_APP_PRODUCT_NAME:-}"
WORK_ROOT="${QUILLUI_APP_BUILD_WORKDIR:-}"
BACKEND_FACADE="${QUILLUI_APP_BACKEND_FACADE:-gtk}"
QT_RUNTIME_MODE="${QUILLUI_APP_QT_RUNTIME_MODE:-${QUILLUI_GENERATED_QT_RUNTIME_MODE:-auto}}"
QT_NATIVE_CATALOG_ENTRY="${QUILLUI_APP_QT_NATIVE_CATALOG_ENTRY:-${QUILLUI_GENERATED_QT_NATIVE_CATALOG_ENTRY:-}}"
ARTIFACT_DIR="${QUILLUI_APP_RELEASE_DIR:-}"
TARBALL_PATH="${QUILLUI_APP_RELEASE_TARBALL:-}"
APP_DISPLAY_NAME="${QUILLUI_APP_DISPLAY_NAME:-}"
APP_ID="${QUILLUI_APP_ID:-}"
APP_SUMMARY="${QUILLUI_APP_SUMMARY:-Apple Swift app running on Linux through QuillUI.}"
APP_CATEGORIES="${QUILLUI_APP_CATEGORIES:-Utility;Development;}"
APP_ICON_PATH="${QUILLUI_APP_ICON_PATH:-}"
DESKTOP_EXEC="${QUILLUI_APP_DESKTOP_EXEC:-}"
BUNDLE_SWIFT_RUNTIME="${QUILLUI_APP_BUNDLE_SWIFT_RUNTIME:-0}"
NORMALIZED_BACKEND_FACADE=""

usage() {
  cat <<MSG
Usage: $(basename "$0") (--source-dir PATH | --source-app NAME) --app-type TYPE [options]

Builds a SwiftUI-shaped app for Linux and creates a runnable release directory
without editing the app tree.

Options:
  --profile NAME        Lowering profile to use.
  --source-app NAME     Resolve source from vendor/apps/NAME first, then
                        .upstream/NAME. Use with --source-subdir for app
                        trees whose Swift sources live below the checkout root.
  --source-subdir PATH  Relative source path inside --source-app checkout.
  --source-dir PATH     Directory containing the app's Swift sources.
  --app-type TYPE       Swift App type to launch through the generated entry.
  --product-name NAME   Output executable name. Defaults from --app-type.
  --workdir PATH        Generated build work directory.
  --backend-facade NAME Select QuillUI, QuillUIGtk, or the native Qt runtime
                        for the generated entry. Allowed: swiftui, gtk, qt.
                        Defaults to gtk for release artifacts.
  --qt-runtime-mode MODE
                        Qt facade launch mode. Allowed: auto, generic, native.
  --qt-native-catalog-entry TYPE
                        QuillGenericQtAppCatalog entry used by native Qt mode.
  --artifact-dir PATH   Directory to write the runnable artifact.
  --tarball PATH        Also create a .tar.gz archive at PATH.
  --display-name NAME   Human-readable app name for metadata.
  --app-id ID           Reverse-DNS app id. Defaults to io.lorehex.PRODUCT.
  --summary TEXT        Short AppStream summary.
  --categories VALUE    Desktop file categories. Defaults to Utility;Development;.
  --icon PATH           Optional SVG or PNG icon to copy into hicolor theme dirs.
  --desktop-exec VALUE  Exec value for the .desktop file. Defaults to product name.
  --bundle-swift-runtime
                        Copy Swift toolchain runtime libraries into the artifact.
  -h, --help            Show this help.

Environment aliases:
  QUILLUI_APP_PROFILE
  QUILLUI_APP_SOURCE_APP
  QUILLUI_APP_SOURCE_SUBDIR
  QUILLUI_APP_SOURCE_DIR
  QUILLUI_APP_ENTRY_TYPE
  QUILLUI_APP_PRODUCT_NAME
  QUILLUI_APP_BUILD_WORKDIR
  QUILLUI_APP_BACKEND_FACADE
  QUILLUI_APP_QT_RUNTIME_MODE
  QUILLUI_APP_QT_NATIVE_CATALOG_ENTRY
  QUILLUI_APP_RELEASE_DIR
  QUILLUI_APP_RELEASE_TARBALL
  QUILLUI_APP_DISPLAY_NAME
  QUILLUI_APP_ID
  QUILLUI_APP_SUMMARY
  QUILLUI_APP_CATEGORIES
  QUILLUI_APP_ICON_PATH
  QUILLUI_APP_DESKTOP_EXEC
  QUILLUI_APP_BUNDLE_SWIFT_RUNTIME
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

validate_source_app_name() {
  local value="$1"

  if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "--source-app must be a simple app source name, got: $value" >&2
    exit 64
  fi
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

app_id_component() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_]+/_/g; s/^_+//; s/_+$//')"
  if [[ -z "$value" || "$value" =~ ^[0-9] ]]; then
    value="app_${value}"
  fi
  printf '%s' "$value"
}

validate_app_id() {
  local value="$1"

  if [[ ! "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*){2,}$ ]]; then
    echo "--app-id must be a reverse-DNS id with at least three dot-separated parts, got: $value" >&2
    exit 64
  fi
}

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

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

require_safe_output_dir() {
  local value="$1"
  local label="$2"

  case "$value" in
    ""|"/"|"$HOME"|"$ROOT_DIR")
      echo "$label is not a safe release output directory: ${value:-<empty>}" >&2
      exit 65
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
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
    --qt-runtime-mode)
      QT_RUNTIME_MODE="${2:-}"
      shift 2
      ;;
    --qt-native-catalog-entry)
      QT_NATIVE_CATALOG_ENTRY="${2:-}"
      shift 2
      ;;
    --artifact-dir)
      ARTIFACT_DIR="${2:-}"
      shift 2
      ;;
    --tarball)
      TARBALL_PATH="${2:-}"
      shift 2
      ;;
    --display-name)
      APP_DISPLAY_NAME="${2:-}"
      shift 2
      ;;
    --app-id)
      APP_ID="${2:-}"
      shift 2
      ;;
    --summary)
      APP_SUMMARY="${2:-}"
      shift 2
      ;;
    --categories)
      APP_CATEGORIES="${2:-}"
      shift 2
      ;;
    --icon)
      APP_ICON_PATH="${2:-}"
      shift 2
      ;;
    --desktop-exec)
      DESKTOP_EXEC="${2:-}"
      shift 2
      ;;
    --bundle-swift-runtime)
      BUNDLE_SWIFT_RUNTIME=1
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
SwiftUI Linux release packaging must run on Linux because the generated app
links Linux-only compatibility and native backend products.
MSG
  exit 64
fi

if [[ -z "$SOURCE_DIR" && -z "$SOURCE_APP" ]]; then
  echo "--source-dir, --source-app, QUILLUI_APP_SOURCE_DIR, or QUILLUI_APP_SOURCE_APP is required" >&2
  usage >&2
  exit 64
fi
if [[ -n "$SOURCE_DIR" && -n "$SOURCE_APP" ]]; then
  echo "--source-dir and --source-app are mutually exclusive" >&2
  exit 64
fi
if [[ -n "$SOURCE_SUBDIR" && -z "$SOURCE_APP" ]]; then
  echo "--source-subdir requires --source-app" >&2
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
elif [[ ! -d "$SOURCE_DIR" ]]; then
  cat >&2 <<MSG
Swift app source was not found at:
  $SOURCE_DIR
MSG
  exit 66
fi

if [[ -z "$PRODUCT_NAME" ]]; then
  PRODUCT_NAME="$(default_product_name "$APP_TYPE")"
fi

if [[ -z "$APP_DISPLAY_NAME" ]]; then
  APP_DISPLAY_NAME="$PRODUCT_NAME"
fi

if [[ -z "$APP_ID" ]]; then
  APP_ID="io.lorehex.$(app_id_component "$PRODUCT_NAME")"
fi
validate_app_id "$APP_ID"
validate_boolean_flag "$BUNDLE_SWIFT_RUNTIME" "QUILLUI_APP_BUNDLE_SWIFT_RUNTIME"

if [[ -z "$DESKTOP_EXEC" ]]; then
  DESKTOP_EXEC="$PRODUCT_NAME"
fi

if [[ -n "$APP_ICON_PATH" && ! -f "$APP_ICON_PATH" ]]; then
  echo "Icon path was not found: $APP_ICON_PATH" >&2
  exit 66
fi

if [[ -z "$WORK_ROOT" ]]; then
  WORK_ROOT="$ROOT_DIR/.build/$PRODUCT_NAME"
fi

NORMALIZED_BACKEND_FACADE="$(quillui_require_backend_identifier "$BACKEND_FACADE")"

if [[ -z "$ARTIFACT_DIR" ]]; then
  ARTIFACT_DIR="$ROOT_DIR/.build/releases/$PRODUCT_NAME-$NORMALIZED_BACKEND_FACADE"
fi

require_safe_output_dir "$ARTIFACT_DIR" "--artifact-dir"

ARTIFACT_PATH_FILE="$WORK_ROOT/.quillui-artifact-path"
BUILD_SOURCE_ARGS=()
BUILD_QT_ARGS=()
if [[ -n "$SOURCE_APP" ]]; then
  BUILD_SOURCE_ARGS=(--source-app "$SOURCE_APP")
  if [[ -n "$SOURCE_SUBDIR" ]]; then
    BUILD_SOURCE_ARGS+=(--source-subdir "$SOURCE_SUBDIR")
  fi
else
  BUILD_SOURCE_ARGS=(--source-dir "$SOURCE_DIR")
fi
if [[ -n "$QT_RUNTIME_MODE" ]]; then
  BUILD_QT_ARGS+=(--qt-runtime-mode "$QT_RUNTIME_MODE")
fi
if [[ -n "$QT_NATIVE_CATALOG_ENTRY" ]]; then
  BUILD_QT_ARGS+=(--qt-native-catalog-entry "$QT_NATIVE_CATALOG_ENTRY")
fi

"$ROOT_DIR/scripts/build-swiftui-linux-app.sh" \
  --profile "$PROFILE" \
  "${BUILD_SOURCE_ARGS[@]}" \
  --app-type "$APP_TYPE" \
  --product-name "$PRODUCT_NAME" \
  --workdir "$WORK_ROOT" \
  --backend-facade "$NORMALIZED_BACKEND_FACADE" \
  "${BUILD_QT_ARGS[@]}" \
  --artifact-path-file "$ARTIFACT_PATH_FILE"

ARTIFACT_PATH="$(cat "$ARTIFACT_PATH_FILE")"
if [[ ! -x "$ARTIFACT_PATH" ]]; then
  echo "Built artifact is not executable: $ARTIFACT_PATH" >&2
  exit 70
fi
ARTIFACT_BIN_DIR="$(dirname "$ARTIFACT_PATH")"

rm -rf "$ARTIFACT_DIR"
mkdir -p \
  "$ARTIFACT_DIR/bin" \
  "$ARTIFACT_DIR/metadata" \
  "$ARTIFACT_DIR/share/applications" \
  "$ARTIFACT_DIR/share/metainfo"
cp "$ARTIFACT_PATH" "$ARTIFACT_DIR/bin/$PRODUCT_NAME"
chmod 755 "$ARTIFACT_DIR/bin/$PRODUCT_NAME"

while IFS= read -r -d '' resource_dir; do
  cp -R "$resource_dir" "$ARTIFACT_DIR/bin/"
done < <(find "$ARTIFACT_BIN_DIR" -maxdepth 1 -type d \( -name '*.resources' -o -name '*.bundle' \) -print0)

SWIFT_RUNTIME_LIBRARY_COUNT=0
SWIFT_RUNTIME_DIR="$ARTIFACT_DIR/lib/swift/linux"
if [[ "$BUNDLE_SWIFT_RUNTIME" == "1" ]]; then
  if ! command -v ldd >/dev/null 2>&1; then
    echo "ldd is required for --bundle-swift-runtime" >&2
    exit 69
  fi

  mkdir -p "$SWIFT_RUNTIME_DIR"
  while IFS= read -r runtime_library; do
    [[ -z "$runtime_library" ]] && continue
    cp -L "$runtime_library" "$SWIFT_RUNTIME_DIR/$(basename "$runtime_library")"
    SWIFT_RUNTIME_LIBRARY_COUNT=$((SWIFT_RUNTIME_LIBRARY_COUNT + 1))
  done < <(
    ldd "$ARTIFACT_PATH" \
      | awk '
          /=>/ && $3 ~ /\/swift\/linux\// { print $3; next }
          $1 ~ /^\/.*\/swift\/linux\// { print $1; next }
        ' \
      | sort -u
  )
fi

ICON_NAME="$APP_ID"
if [[ -n "$APP_ICON_PATH" ]]; then
  icon_extension="${APP_ICON_PATH##*.}"
  case "$icon_extension" in
    svg|SVG)
      icon_dir="$ARTIFACT_DIR/share/icons/hicolor/scalable/apps"
      icon_extension="svg"
      ;;
    png|PNG)
      icon_dir="$ARTIFACT_DIR/share/icons/hicolor/512x512/apps"
      icon_extension="png"
      ;;
    *)
      echo "Icon path must end in .svg or .png: $APP_ICON_PATH" >&2
      exit 64
      ;;
  esac
  mkdir -p "$icon_dir"
  cp "$APP_ICON_PATH" "$icon_dir/$APP_ID.$icon_extension"
fi

cat > "$ARTIFACT_DIR/share/applications/$APP_ID.desktop" <<MSG
[Desktop Entry]
Type=Application
Name=$APP_DISPLAY_NAME
Comment=$APP_SUMMARY
Exec=$DESKTOP_EXEC
Icon=$ICON_NAME
Terminal=false
Categories=$APP_CATEGORIES
StartupWMClass=$PRODUCT_NAME
MSG

cat > "$ARTIFACT_DIR/share/metainfo/$APP_ID.metainfo.xml" <<MSG
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$APP_ID</id>
  <name>$(xml_escape "$APP_DISPLAY_NAME")</name>
  <summary>$(xml_escape "$APP_SUMMARY")</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <launchable type="desktop-id">$APP_ID.desktop</launchable>
  <provides>
    <binary>$PRODUCT_NAME</binary>
  </provides>
</component>
MSG

cat > "$ARTIFACT_DIR/run" <<MSG
#!/usr/bin/env bash
set -euo pipefail
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
export GTK_A11Y="\${GTK_A11Y:-none}"
export QUILLUI_BACKEND="\${QUILLUI_BACKEND:-$NORMALIZED_BACKEND_FACADE}"
if [[ -d "\$DIR/lib/swift/linux" ]]; then
  export LD_LIBRARY_PATH="\$DIR/lib/swift/linux\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
fi
exec "\$DIR/bin/$PRODUCT_NAME" "\$@"
MSG
chmod 755 "$ARTIFACT_DIR/run"

{
  printf 'product=%s\n' "$PRODUCT_NAME"
  printf 'display_name=%s\n' "$APP_DISPLAY_NAME"
  printf 'app_id=%s\n' "$APP_ID"
  printf 'summary=%s\n' "$APP_SUMMARY"
  printf 'swift_runtime_bundled=%s\n' "$BUNDLE_SWIFT_RUNTIME"
  printf 'swift_runtime_dir=%s\n' "$SWIFT_RUNTIME_DIR"
  printf 'swift_runtime_library_count=%s\n' "$SWIFT_RUNTIME_LIBRARY_COUNT"
  printf 'desktop_file=%s\n' "$ARTIFACT_DIR/share/applications/$APP_ID.desktop"
  printf 'metainfo=%s\n' "$ARTIFACT_DIR/share/metainfo/$APP_ID.metainfo.xml"
  printf 'profile=%s\n' "$PROFILE"
  printf 'app_type=%s\n' "$APP_TYPE"
  printf 'backend_facade=%s\n' "$NORMALIZED_BACKEND_FACADE"
  printf 'source_dir=%s\n' "$SOURCE_DIR"
  printf 'generated_package=%s\n' "$WORK_ROOT/package"
  printf 'built_artifact=%s\n' "$ARTIFACT_PATH"
} > "$ARTIFACT_DIR/metadata/quillui-release.env"

if [[ -n "$TARBALL_PATH" ]]; then
  mkdir -p "$(dirname "$TARBALL_PATH")"
  tar -C "$(dirname "$ARTIFACT_DIR")" -czf "$TARBALL_PATH" "$(basename "$ARTIFACT_DIR")"
fi

cat <<MSG
SwiftUI Linux release artifact:
  $ARTIFACT_DIR

Launcher:
  $ARTIFACT_DIR/run
MSG

if [[ -n "$TARBALL_PATH" ]]; then
  cat <<MSG

Archive:
  $TARBALL_PATH
MSG
fi
