#!/usr/bin/env bash

quillui_resolve_telegram_source_dir() {
  local root_dir="$1"

  if [[ -n "${QUILLUI_APP_SOURCE_DIR:-}" ]]; then
    printf '%s\n' "$QUILLUI_APP_SOURCE_DIR"
    return 0
  fi

  if [[ -n "${TELEGRAM_SWIFT_SOURCE_DIR:-}" ]]; then
    printf '%s\n' "$TELEGRAM_SWIFT_SOURCE_DIR"
    return 0
  fi

  if [[ -n "${TELEGRAM_SOURCE_DIR:-}" ]]; then
    printf '%s\n' "$TELEGRAM_SOURCE_DIR"
    return 0
  fi

  printf '%s/.upstream/telegram-swift\n' "$root_dir"
}

quillui_print_telegram_source_missing() {
  local source_dir="$1"

  cat >&2 <<MSG
Telegram Swift source was not found at:
  $source_dir

Set QUILLUI_APP_SOURCE_DIR=/path/to/TelegramSwift or
TELEGRAM_SWIFT_SOURCE_DIR=/path/to/TelegramSwift and rerun.
TELEGRAM_SOURCE_DIR is also accepted as a short alias.
MSG
}
