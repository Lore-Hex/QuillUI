#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-telegram-source.sh"

UPSTREAM_DIR="$(quillui_resolve_telegram_source_dir "$ROOT_DIR")"
WORK_ROOT="${QUILLUI_GENERATED_TELEGRAM_PACKAGE_WORKDIR:-$ROOT_DIR/.build/generated-telegram-package-check}"
CACHE_HOME="${QUILLUI_GENERATED_TELEGRAM_PACKAGE_HOME:-$ROOT_DIR/.build/generated-telegram-package-check-home}"

if [[ -z "$WORK_ROOT" || "$WORK_ROOT" == "/" || "$WORK_ROOT" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generated work directory: ${WORK_ROOT:-<empty>}" >&2
  exit 73
fi

if [[ -z "$CACHE_HOME" || "$CACHE_HOME" == "/" || "$CACHE_HOME" == "$ROOT_DIR" ]]; then
  echo "Refusing unsafe generated cache home: ${CACHE_HOME:-<empty>}" >&2
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
mkdir -p "$WORK_ROOT/logs" "$WORK_ROOT/module-cache" "$WORK_ROOT/overlaid-packages" "$CACHE_HOME"

default_packages=(
  ApiCredentials
  CAPortal
  CallVideoLayer
  ColorPalette
  Colors
  CalendarUtils
  CrashHandler
  CurrencyFormat
  DateUtils
  DetectSpeech
  Dock
  DustLayer
  EDSunriseSet
  EmojiSuggestions
  FastBlur
  FetchManager
  FoundationUtils
  GZIP
  GraphUI
  HackUtils
  HotKey
  InAppPurchaseManager
  InAppSettings
  InAppVideoServices
  InputView
  KeyboardKey
  Localization
  MediaPlayer
  MergeLists
  NumberPluralization
  OCR
  ObjcUtils
  PrivateCallScreen
  Reactions
  RingBuffer
  Spotlight
  Strings
  Svg
  TGCurrencyFormatter
  TGGifConverter
  TGModernGrowingTextView
  TGPassportMRZ
  TGUIKit
  TGVideoCameraMovie
  TelegramAudio
  TelegramMedia
  TelegramIconsTheme
  TelegramSystem
  TextRecognizing
  ThemeSettings
  Translate
  YuvConversion
  libphonenumber
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
overlay_root="$ROOT_DIR/Sources/QuillTelegramBuildOverlays"
package_mirror_root="$WORK_ROOT/overlaid-packages"
submodule_mirror_root="$WORK_ROOT/submodules"
overlaid_packages=()
swift_build_flags=()

run_reusable_apple_lowering_if_needed() {
  local source_dir="$1"

  if [[ "$(uname -s)" != "Linux" ]]; then
    return
  fi
  if ! grep -rqE '#selector|@objc|@IBAction|@IBOutlet|@NSManaged|import os\.log|layerClass' "$source_dir" 2>/dev/null; then
    return
  fi

  "$ROOT_DIR/scripts/run-quill-appkit-lower.sh" "$source_dir"
}

mirror_package_like_dir() {
  local source_dir="$1"
  local mirror_package_dir="$2"
  local overlay_name="$3"
  local overlay_dir="$overlay_root/$overlay_name"

  mkdir -p "$mirror_package_dir"
  cp -R "$source_dir"/. "$mirror_package_dir"

  if [[ -d "$overlay_dir" ]]; then
    cp -R "$overlay_dir"/. "$mirror_package_dir"
    overlaid_packages+=("$overlay_name")
  fi

  python3 "$ROOT_DIR/scripts/lower-telegram-linux-source.py" "$mirror_package_dir"
  run_reusable_apple_lowering_if_needed "$mirror_package_dir"
  python3 "$ROOT_DIR/scripts/generate-telegram-image-resource-symbols.py" "$mirror_package_dir"
  python3 "$ROOT_DIR/scripts/patch-telegram-package-manifest.py" "$mirror_package_dir" "$ROOT_DIR"
}

link_package_sibling_if_free() {
  local source_dir="$1"
  local package_name="$2"
  local package_sibling="$package_mirror_root/$package_name"

  if [[ -e "$package_sibling" || -L "$package_sibling" ]]; then
    return
  fi

  ln -s "$source_dir" "$package_sibling"
}

materialize_telegram_shared_headers() {
  local package_name="$1"
  local mirror_dir="$2"

  if [[ "$package_name" == "OpenSSLEncryptionProvider" ]]; then
    # Upstream's manifest expects the EncryptionProvider protocol header via
    # headerSearchPath("SharedHeaders/EncryptionProvider"); the EncryptionProvider
    # overlay is Swift-only, so materialize the upstream header here. The
    # openssl/ includes resolve from the system libssl-dev headers.
    local encryption_headers="$UPSTREAM_DIR/submodules/telegram-ios/submodules/EncryptionProvider/PublicHeaders"
    if [[ -d "$encryption_headers" ]]; then
      mkdir -p "$mirror_dir/SharedHeaders/EncryptionProvider"
      cp -R "$encryption_headers"/. "$mirror_dir/SharedHeaders/EncryptionProvider"
      # Swift importers compile the public-header module without the target's
      # private headerSearchPath cSettings, so the imported header must also be
      # self-contained inside PublicHeaders/.
      if [[ -d "$mirror_dir/PublicHeaders" ]]; then
        cp -R "$encryption_headers"/. "$mirror_dir/PublicHeaders"
      fi
    fi
  fi

  if [[ "$package_name" == "CryptoUtils" ]]; then
    # The overlay replaces CryptoUtils with a Swift implementation; its
    # ObjCHeaders target re-exports the upstream <CryptoUtils/Crypto.h> that
    # dependents like BuildConfig import via header propagation.
    local crypto_headers="$UPSTREAM_DIR/submodules/telegram-ios/submodules/CryptoUtils/PublicHeaders"
    if [[ -d "$crypto_headers" && -d "$mirror_dir/ObjCHeaders" ]]; then
      mkdir -p "$mirror_dir/ObjCHeaders/include"
      cp -R "$crypto_headers"/. "$mirror_dir/ObjCHeaders/include"
    fi
  fi

  if [[ "$package_name" == "Mozjpeg" ]]; then
    # Upstream vendors the real mozjpeg tree; its manifest searches
    # SharedHeaders/libmozjpeg for jpeglib/turbojpeg + the mozjpeg extensions
    # (jpeg_c_set_int_param, JINT_COMPRESS_PROFILE). jconfig.h is a build
    # product upstream, so generate a minimal one.
    local mozjpeg_source="$UPSTREAM_DIR/submodules/telegram-ios/third-party/mozjpeg/mozjpeg"
    if [[ -d "$mozjpeg_source" ]]; then
      mkdir -p "$mirror_dir/SharedHeaders/libmozjpeg"
      find "$mozjpeg_source" -maxdepth 1 -name '*.h' -exec cp {} "$mirror_dir/SharedHeaders/libmozjpeg/" \;
      cat > "$mirror_dir/SharedHeaders/libmozjpeg/jconfig.h" <<'EOF'
/* Generated minimal jconfig.h for the QuillUI Telegram compile ratchet. */
#ifndef QUILLUI_GENERATED_MOZJPEG_JCONFIG_H
#define QUILLUI_GENERATED_MOZJPEG_JCONFIG_H

#define JPEG_LIB_VERSION 62
#define C_ARITH_CODING_SUPPORTED 1
#define D_ARITH_CODING_SUPPORTED 1
#define MEM_SRCDST_SUPPORTED 1
#define BITS_IN_JSAMPLE 8
#define HAVE_STDDEF_H 1
#define HAVE_STDLIB_H 1
#define HAVE_UNSIGNED_CHAR 1
#define HAVE_UNSIGNED_SHORT 1

#endif
EOF
    fi
  fi

  if [[ "$package_name" == "libwebp" ]]; then
    local webp_headers="$UPSTREAM_DIR/submodules/telegram-ios/third-party/webp/libwebp/src/webp"
    if [[ -d "$webp_headers" ]]; then
      mkdir -p "$mirror_dir/SharedHeaders/libwebp/include"
      cp -R "$webp_headers"/. "$mirror_dir/SharedHeaders/libwebp/include"
    fi
  fi

  if [[ "$package_name" == "OpusBinding" ]]; then
    local opus_tar="$UPSTREAM_DIR/submodules/telegram-ios/third-party/opus/opus-1.5.1.tar.gz"
    if [[ -f "$opus_tar" ]]; then
      mkdir -p "$mirror_dir/SharedHeaders/libopus/include/opus"
      tar -xzf "$opus_tar" \
        -C "$mirror_dir/SharedHeaders/libopus/include/opus" \
        --strip-components=2 \
        opus-1.5.1/include/opus_types.h \
        opus-1.5.1/include/opus_defines.h \
        opus-1.5.1/include/opus.h \
        opus-1.5.1/include/opus_multistream.h \
        opus-1.5.1/include/opus_projection.h \
        opus-1.5.1/include/opus_custom.h
    fi
  fi

  if [[ "$package_name" == "FFMpegBinding" ]]; then
    local ffmpeg_source="$UPSTREAM_DIR/submodules/telegram-ios/submodules/ffmpeg/Sources/FFMpeg/ffmpeg-7.1.1"
    if [[ -d "$ffmpeg_source" ]]; then
      mkdir -p "$mirror_dir/SharedHeaders/ffmpeg/include"
      for ffmpeg_include_dir in libavcodec libavformat libavutil libswresample libswscale; do
        if [[ -d "$ffmpeg_source/$ffmpeg_include_dir" ]]; then
          while IFS= read -r ffmpeg_header; do
            relative_header="${ffmpeg_header#"$ffmpeg_source/"}"
            mkdir -p "$mirror_dir/SharedHeaders/ffmpeg/include/$(dirname "$relative_header")"
            cp "$ffmpeg_header" "$mirror_dir/SharedHeaders/ffmpeg/include/$relative_header"
          done < <(find "$ffmpeg_source/$ffmpeg_include_dir" -type f -name '*.h' -print)
        fi
      done
      cat > "$mirror_dir/SharedHeaders/ffmpeg/include/libavutil/avconfig.h" <<'EOF'
#ifndef AVUTIL_AVCONFIG_H
#define AVUTIL_AVCONFIG_H

#if defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define AV_HAVE_BIGENDIAN 1
#else
#define AV_HAVE_BIGENDIAN 0
#endif

#if defined(__x86_64__) || defined(__i386__) || defined(__aarch64__)
#define AV_HAVE_FAST_UNALIGNED 1
#else
#define AV_HAVE_FAST_UNALIGNED 0
#endif

#endif
EOF
      cat > "$mirror_dir/SharedHeaders/ffmpeg/include/config.h" <<'EOF'
#ifndef QUILLUI_GENERATED_FFMPEG_CONFIG_H
#define QUILLUI_GENERATED_FFMPEG_CONFIG_H

#define FFMPEG_CONFIGURATION "QuillUI generated Telegram package header configuration"
#define FFMPEG_LICENSE "LGPL version 2.1 or later"
#define CONFIG_SMALL 0
#define CONFIG_NETWORK 1
#define HAVE_BIGENDIAN 0
#define HAVE_FAST_UNALIGNED 1
#define HAVE_FAST_64BIT 1
#define HAVE_THREADS 1
#define HAVE_PTHREADS 1
#define HAVE_STDATOMIC_H 1
#define HAVE_SYNC_VAL_COMPARE_AND_SWAP 1
#define HAVE_UNISTD_H 1
#define HAVE_FCNTL 1
#define HAVE_MALLOC_H 1
#define HAVE_SOCKLEN_T 1
#define HAVE_STRUCT_SOCKADDR_IN6 1
#define HAVE_POLL_H 1
#define HAVE_STRUCT_POLLFD 1
#define HAVE_CLOSESOCKET 0
#define HAVE_DOS_PATHS 0
#define HAVE_IO_H 0
#define HAVE_DIRECT_H 0
#define HAVE_WINSOCK2_H 0
#define HAVE_UWP 0

#endif
EOF
      cat > "$mirror_dir/SharedHeaders/ffmpeg/include/libavutil/ffversion.h" <<'EOF'
#ifndef AVUTIL_FFVERSION_H
#define AVUTIL_FFVERSION_H
#define FFMPEG_VERSION "7.1.1"
#endif
EOF
      cat > "$mirror_dir/SharedHeaders/ffmpeg/include/libavcodec/hwconfig.h" <<'EOF'
#ifndef AVCODEC_HWCONFIG_H
#define AVCODEC_HWCONFIG_H
#endif
EOF
    fi
  fi
}

if [[ "$(uname -s)" == "Linux" ]]; then
  swift_build_flags+=(
    -Xcc "-I$objc_include_dir"
    -Xcc "-include"
    -Xcc "$objc_include_dir/QuillObjCCompatibility/Prelude.h"
    -Xcc "-fobjc-runtime=gnustep-2.0"
    -Xcc "-fblocks"
    -Xcc "-fobjc-arc"
  )

  while IFS= read -r package_manifest; do
    source_package_dir="$(dirname "$package_manifest")"
    package_name="$(basename "$source_package_dir")"
    mirror_package_dir="$package_mirror_root/$package_name"
    mirror_package_like_dir "$source_package_dir" "$mirror_package_dir" "$package_name"
  done < <(find "$UPSTREAM_DIR/packages" -mindepth 2 -maxdepth 2 -name Package.swift -print | sort)
  ln -s "$package_mirror_root" "$WORK_ROOT/packages"

  if [[ -d "$UPSTREAM_DIR/submodules" ]]; then
    mkdir -p "$submodule_mirror_root"
    if [[ -d "$UPSTREAM_DIR/submodules/telegram-ios/submodules" ]]; then
      mkdir -p "$submodule_mirror_root/telegram-ios"
      cp -R "$UPSTREAM_DIR/submodules/telegram-ios/submodules" "$submodule_mirror_root/telegram-ios/submodules"
      while IFS= read -r submodule_manifest; do
        submodule_package_dir="$(dirname "$submodule_manifest")"
        submodule_package_name="$(basename "$submodule_package_dir")"
        overlay_dir="$overlay_root/$submodule_package_name"
        if [[ -d "$overlay_dir" ]]; then
          cp -R "$overlay_dir"/. "$submodule_package_dir"
          overlaid_packages+=("$submodule_package_name")
        fi
        materialize_telegram_shared_headers "$submodule_package_name" "$submodule_package_dir"
        python3 "$ROOT_DIR/scripts/lower-telegram-linux-source.py" "$submodule_package_dir"
        run_reusable_apple_lowering_if_needed "$submodule_package_dir"
        python3 "$ROOT_DIR/scripts/generate-telegram-image-resource-symbols.py" "$submodule_package_dir"
        python3 "$ROOT_DIR/scripts/patch-telegram-package-manifest.py" "$submodule_package_dir" "$ROOT_DIR"
        link_package_sibling_if_free "$submodule_package_dir" "$submodule_package_name"
      done < <(find "$submodule_mirror_root/telegram-ios/submodules" -name Package.swift -print | sort)
      while IFS= read -r package_manifest; do
        source_package_name="$(basename "$(dirname "$package_manifest")")"
        telegram_ios_sibling="$submodule_mirror_root/telegram-ios/submodules/$source_package_name"
        if [[ -e "$telegram_ios_sibling" && ! -f "$telegram_ios_sibling/Package.swift" ]]; then
          rm -rf "$telegram_ios_sibling"
        fi
        if [[ ! -e "$telegram_ios_sibling" && ! -L "$telegram_ios_sibling" ]]; then
          ln -s "$package_mirror_root/$source_package_name" "$telegram_ios_sibling"
        fi
      done < <(find "$package_mirror_root" -mindepth 2 -maxdepth 2 -name Package.swift -print | sort)
    fi
    while IFS= read -r top_level_submodule; do
      submodule_name="$(basename "$top_level_submodule")"
      if [[ "$submodule_name" == "telegram-ios" ]]; then
        continue
      fi
      mirrored_submodule="$submodule_mirror_root/$submodule_name"
      if [[ -f "$top_level_submodule/Package.swift" ]]; then
        mirror_package_like_dir "$top_level_submodule" "$mirrored_submodule" "$submodule_name"
        materialize_telegram_shared_headers "$submodule_name" "$mirrored_submodule"
        python3 "$ROOT_DIR/scripts/patch-telegram-package-manifest.py" "$mirrored_submodule" "$ROOT_DIR"
      else
        ln -s "$top_level_submodule" "$mirrored_submodule"
      fi
      link_package_sibling_if_free "$mirrored_submodule" "$submodule_name"
    done < <(find "$UPSTREAM_DIR/submodules" -mindepth 1 -maxdepth 1 -type d -print | sort)
    while IFS= read -r mirrored_submodule_manifest; do
      python3 "$ROOT_DIR/scripts/generate-telegram-image-resource-symbols.py" "$(dirname "$mirrored_submodule_manifest")"
      python3 "$ROOT_DIR/scripts/patch-telegram-package-manifest.py" "$(dirname "$mirrored_submodule_manifest")" "$ROOT_DIR"
    done < <(find "$submodule_mirror_root" -type f -name Package.swift -print | sort)
    ln -s "$submodule_mirror_root" "$package_mirror_root/submodules"
  fi

  # Overlay-only packages: Swift replacements for upstream code that has no
  # SwiftPM manifest of its own (e.g. CodeSyntax sources, the RLottie_Xcode/
  # rlottie C++ tree). The overlay IS the package; expose it in the mirror so
  # the generated app graph can resolve the module.
  while IFS= read -r overlay_manifest; do
    overlay_package_dir="$(dirname "$overlay_manifest")"
    overlay_package_name="$(basename "$overlay_package_dir")"
    overlay_sibling="$package_mirror_root/$overlay_package_name"
    # A manifest-less sibling (the plain upstream source symlink, possibly a
    # case-insensitive-filesystem collision like rlottie vs RLottie) yields to
    # the overlay package, which is the importable module.
    if [[ -L "$overlay_sibling" && ! -f "$overlay_sibling/Package.swift" ]]; then
      rm "$overlay_sibling"
    fi
    if [[ ! -e "$overlay_sibling" && ! -L "$overlay_sibling" ]]; then
      mkdir -p "$overlay_sibling"
      cp -R "$overlay_package_dir"/. "$overlay_sibling"
      overlaid_packages+=("$overlay_package_name")
    fi
  done < <(find "$overlay_root" -mindepth 2 -maxdepth 2 -name Package.swift -print | sort)
fi

for package_name in "${packages[@]}"; do
  if [[ "$(uname -s)" == "Linux" ]]; then
    package_dir="$package_mirror_root/$package_name"
  else
    package_dir="$UPSTREAM_DIR/packages/$package_name"
  fi
  log_path="$WORK_ROOT/logs/$package_name.log"

  if [[ ! -f "$package_dir/Package.swift" ]]; then
    echo "Missing Telegram package manifest: $package_dir/Package.swift" >&2
    exit 66
  fi

  printf '==> building %s\n' "$package_name"
  if HOME="$CACHE_HOME" \
    CLANG_MODULE_CACHE_PATH="$WORK_ROOT/module-cache" \
    swift build \
      --disable-sandbox \
      --skip-update \
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

Compiled package islands:

$(printf -- '- `%s`\n' "${packages[@]}")

Generic build overlays applied:

$(if [[ ${#overlaid_packages[@]} -eq 0 ]]; then printf -- '- none\n'; else printf -- '- `%s`\n' "${overlaid_packages[@]}"; fi)

Known next blocker classes from the broader upstream package audit:

- Objective-C package shims that need deeper Foundation/AppKit runtime surface beyond the current header overlay.
- AppKit/CoreText/Cocoa packages that belong behind QuillAppKit or QuillKit compatibility.
- Missing telegram-ios submodule package dependencies for higher-level Telegram modules.
MSG

printf 'Generated Telegram package check completed: %s\n' "$WORK_ROOT"
