#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export QUILLUI_ENCHANTED_BUILD_WORKDIR="${QUILLUI_ENCHANTED_BUILD_WORKDIR:-${QUILLUI_QUILL_CHAT_BUILD_WORKDIR:-$ROOT_DIR/.build/quill-chat-linux}}"
export QUILLUI_ENCHANTED_PRODUCT_NAME="${QUILLUI_ENCHANTED_PRODUCT_NAME:-${QUILLUI_QUILL_CHAT_PRODUCT_NAME:-quill-chat-linux}}"

exec "$ROOT_DIR/scripts/build-enchanted-linux.sh" "$@"
