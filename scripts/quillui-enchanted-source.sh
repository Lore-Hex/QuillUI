#!/usr/bin/env bash

quillui_resolve_enchanted_source_dir() {
  local root_dir="$1"

  if [[ -n "${QUILLUI_APP_SOURCE_DIR:-}" ]]; then
    printf '%s\n' "$QUILLUI_APP_SOURCE_DIR"
    return 0
  fi

  if [[ -n "${ENCHANTED_SOURCE_DIR:-}" ]]; then
    printf '%s\n' "$ENCHANTED_SOURCE_DIR"
    return 0
  fi

  if [[ -n "${QUILL_CHAT_DIR:-}" ]]; then
    printf '%s/Enchanted\n' "$QUILL_CHAT_DIR"
    return 0
  fi

  printf '%s/.upstream/enchanted/Enchanted\n' "$root_dir"
}

quillui_print_enchanted_source_missing() {
  local source_dir="$1"

  cat >&2 <<MSG
Enchanted source was not found at:
  $source_dir

Set QUILLUI_APP_SOURCE_DIR=/path/to/Enchanted or
ENCHANTED_SOURCE_DIR=/path/to/Enchanted. QUILL_CHAT_DIR is still supported
for legacy checkouts and resolves to QUILL_CHAT_DIR/Enchanted.
MSG
}
