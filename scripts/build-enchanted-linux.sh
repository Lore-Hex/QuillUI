#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-enchanted-source.sh"

APP_DIR="$(quillui_resolve_enchanted_source_dir "$ROOT_DIR")"
WORK_ROOT="${QUILLUI_ENCHANTED_BUILD_WORKDIR:-${QUILLUI_QUILL_CHAT_BUILD_WORKDIR:-$ROOT_DIR/.build/quill-chat-linux}}"
PRODUCT_NAME="${QUILLUI_ENCHANTED_PRODUCT_NAME:-${QUILLUI_QUILL_CHAT_PRODUCT_NAME:-quill-chat-linux}}"
BACKEND_FACADE="${QUILLUI_ENCHANTED_BACKEND_FACADE:-${QUILLUI_QUILL_CHAT_BACKEND_FACADE:-${QUILLUI_APP_BACKEND_FACADE:-}}}"
RUN_ARGS=()
BACKEND_FACADE_ARGS=()

usage() {
  cat <<MSG
Usage: $(basename "$0") [--backend-facade NAME] [--run]

Builds Enchanted for Linux through the generic SwiftUI Linux app builder
without editing the app tree.

Options:
  --backend-facade NAME                Select QuillUI, QuillUIGtk, or the native
                                       Qt runtime for the generated entry.
                                       Allowed: swiftui, gtk, qt.
  --run                                Run the built executable after building.
  -h, --help                           Show this help.

Environment:
  QUILLUI_APP_SOURCE_DIR               Overrides the app source directory
  ENCHANTED_SOURCE_DIR                 Overrides the app source directory
  QUILL_CHAT_DIR                       Legacy checkout root; resolves to
                                       QUILL_CHAT_DIR/Enchanted
  QUILLUI_ENCHANTED_BUILD_WORKDIR      Defaults to .build/quill-chat-linux
  QUILLUI_ENCHANTED_PRODUCT_NAME       Defaults to quill-chat-linux
  QUILLUI_ENCHANTED_BACKEND_FACADE     Optional swiftui, gtk, or qt generated
                                       entry facade.

Legacy QUILLUI_QUILL_CHAT_* environment names are still accepted.
MSG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend-facade)
      BACKEND_FACADE="${2:-}"
      shift 2
      ;;
    --run)
      RUN_ARGS+=(--run)
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
The Enchanted Linux build must run on Linux because the SwiftUI, SwiftData,
Apple platform, GTK, OpenCombine, and package-compatibility products are
Linux-only in this toolchain.
MSG
  exit 64
fi

if [[ ! -d "$APP_DIR" ]]; then
  quillui_print_enchanted_source_missing "$APP_DIR"
  exit 66
fi

if [[ -n "$BACKEND_FACADE" ]]; then
  BACKEND_FACADE_ARGS=(--backend-facade "$BACKEND_FACADE")
fi

"$ROOT_DIR/scripts/build-swiftui-linux-app.sh" \
  --profile enchanted-full-source \
  --source-dir "$APP_DIR" \
  --app-type EnchantedApp \
  --product-name "$PRODUCT_NAME" \
  --workdir "$WORK_ROOT" \
  "${BACKEND_FACADE_ARGS[@]}" \
  "${RUN_ARGS[@]}"
