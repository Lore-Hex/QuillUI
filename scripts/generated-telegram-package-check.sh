#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-telegram-source.sh"

UPSTREAM_DIR="$(quillui_resolve_telegram_source_dir "$ROOT_DIR")"
WORK_ROOT="${QUILLUI_GENERATED_TELEGRAM_PACKAGE_WORKDIR:-$ROOT_DIR/.build/generated-telegram-package-check}"

if [[ -z "$WORK_ROOT" || "$WORK_ROOT" == "/" || "$WORK_ROOT" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generated work directory: ${WORK_ROOT:-<empty>}" >&2
  exit 73
fi

if [[ ! -d "$UPSTREAM_DIR" ]]; then
  quillui_print_telegram_source_missing "$UPSTREAM_DIR"
  exit 66
fi

if [[ ! -d "$UPSTREAM_DIR/packages" ]]; then
  echo "Telegram Swift packages directory was not found at: $UPSTREAM_DIR/packages" >&2
  exit 66
fi

rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT/logs" "$WORK_ROOT/home" "$WORK_ROOT/module-cache"

default_packages=(
  CAPortal
  CalendarUtils
  CurrencyFormat
  DateUtils
  EDSunriseSet
  EmojiSuggestions
  FoundationUtils
  GZIP
  HackUtils
  KeyboardKey
  MergeLists
  NumberPluralization
  TGCurrencyFormatter
  TGPassportMRZ
)

if [[ -n "${QUILLUI_TELEGRAM_PACKAGE_CHECK_PACKAGES:-}" ]]; then
  # shellcheck disable=SC2206
  packages=($QUILLUI_TELEGRAM_PACKAGE_CHECK_PACKAGES)
else
  packages=("${default_packages[@]}")
fi

if [[ ${#packages[@]} -eq 0 ]]; then
  echo "No Telegram packages requested." >&2
  exit 64
fi

printf 'Telegram source: %s\n' "$UPSTREAM_DIR"
printf 'Swift platform: %s\n' "$(uname -s)"
printf 'Package compile set: %s\n' "${packages[*]}"

objc_include_dir="$ROOT_DIR/Sources/QuillObjCCompatibility/include"
swift_build_flags=()
if [[ "$(uname -s)" == "Linux" ]]; then
  swift_build_flags+=(
    -Xcc "-I$objc_include_dir"
    -Xcc "-include"
    -Xcc "$objc_include_dir/QuillObjCCompatibility/Prelude.h"
    -Xcc "-fobjc-runtime=gnustep-2.0"
    -Xcc "-fblocks"
    -Xcc "-fobjc-arc"
  )
fi

for package_name in "${packages[@]}"; do
  package_dir="$UPSTREAM_DIR/packages/$package_name"
  log_path="$WORK_ROOT/logs/$package_name.log"

  if [[ ! -f "$package_dir/Package.swift" ]]; then
    echo "Missing Telegram package manifest: $package_dir/Package.swift" >&2
    exit 66
  fi

  printf '==> building %s\n' "$package_name"
  if HOME="$WORK_ROOT/home" \
    CLANG_MODULE_CACHE_PATH="$WORK_ROOT/module-cache" \
    swift build \
      --disable-sandbox \
      --jobs 1 \
      --package-path "$package_dir" \
      --scratch-path "$WORK_ROOT/.build/$package_name" \
      "${swift_build_flags[@]}" \
      >"$log_path" 2>&1
  then
    printf 'ok %s\n' "$package_name"
  else
    printf 'failed %s; log: %s\n' "$package_name" "$log_path" >&2
    sed -n '1,80p' "$log_path" >&2
    exit 1
  fi
done

cat > "$WORK_ROOT/README.md" <<MSG
# Generated Telegram Package Check

Source: \`$UPSTREAM_DIR\`

Compiled unchanged package islands:

$(printf -- '- `%s`\n' "${packages[@]}")

Known next blocker classes from the broader upstream package audit:

- Objective-C package shims that need deeper Foundation/AppKit runtime surface beyond the current header overlay.
- AppKit/CoreText/Cocoa packages that belong behind QuillAppKit or QuillKit compatibility.
- Darwin-only system probes such as \`sysctlbyname\` in \`TelegramSystem\`.
- Missing telegram-ios submodule package dependencies for higher-level Telegram modules.
MSG

printf 'Generated Telegram package check completed: %s\n' "$WORK_ROOT"
