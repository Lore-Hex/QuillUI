#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUILL_CHAT_DIR="${QUILL_CHAT_DIR:-$ROOT_DIR/../quill/clients/quill-chat}"
APP_DIR="${ENCHANTED_SOURCE_DIR:-$QUILL_CHAT_DIR/Enchanted}"
WORK_ROOT="${QUILLUI_QUILL_CHAT_BUILD_WORKDIR:-$ROOT_DIR/.build/quill-chat-linux}"
PRODUCT_NAME="${QUILLUI_QUILL_CHAT_PRODUCT_NAME:-quill-chat-linux}"
RUN_ARGS=()

usage() {
  cat <<MSG
Usage: $(basename "$0") [--run]

Builds Quill Chat for Linux through the generic SwiftUI Linux app builder
without editing the app tree.

Environment:
  QUILL_CHAT_DIR                       Defaults to ../quill/clients/quill-chat
  ENCHANTED_SOURCE_DIR                 Overrides the app source directory
  QUILLUI_QUILL_CHAT_BUILD_WORKDIR     Defaults to .build/quill-chat-linux
  QUILLUI_QUILL_CHAT_PRODUCT_NAME      Defaults to quill-chat-linux
MSG
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
The Quill Chat Linux build must run on Linux because the SwiftUI, SwiftData,
Apple platform, GTK, OpenCombine, and package-compatibility products are
Linux-only in this toolchain.
MSG
  exit 64
fi

if [[ ! -d "$APP_DIR" ]]; then
  cat >&2 <<MSG
Quill Chat source was not found at:
  $APP_DIR

Set QUILL_CHAT_DIR=/path/to/quill/clients/quill-chat or
ENCHANTED_SOURCE_DIR=/path/to/Enchanted and rerun.
MSG
  exit 66
fi

"$ROOT_DIR/scripts/build-swiftui-linux-app.sh" \
  --profile enchanted-full-source \
  --source-dir "$APP_DIR" \
  --app-type EnchantedApp \
  --product-name "$PRODUCT_NAME" \
  --workdir "$WORK_ROOT" \
  "${RUN_ARGS[@]}"
