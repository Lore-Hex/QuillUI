#!/usr/bin/env bash

quillui_backend_for_product() {
  case "$1" in
    quill-qt-interaction-smoke)
      echo "qt"
      ;;
    quill-gtk-interaction-smoke|quill-chat-linux|quill-enchanted|quill-enchanted-upstream-slice|quill-icecubes|quill-netnewswire|quill-codeedit|quill-signal|quill-telegram|quill-iina|quill-wireguard)
      echo "gtk"
      ;;
    *)
      echo ""
      ;;
  esac
}

quillui_requested_backend_for_product() {
  if [[ -n "${QUILLUI_BACKEND:-}" ]]; then
    echo "$QUILLUI_BACKEND"
  else
    quillui_backend_for_product "$1"
  fi
}
