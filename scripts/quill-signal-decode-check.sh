#!/usr/bin/env bash
#
# quill-signal-decode-check.sh — build + run the quill-signal-bridge protocol
# decode-contract check (asserts every bridge wire shape decodes into
# QuillSignalKit's BridgeMessage). Foundation-only, so it needs NO GTK backend /
# SwiftOpenUI patcher and builds in seconds. Exits 0 if the contract holds.
#
# Run inside the quillui-signal-build image:
#   docker run --rm -v "$PWD":/qui -v qui-build-linux:/qui/.build-linux \
#     quillui-signal-build /qui/scripts/quill-signal-decode-check.sh
set -euo pipefail
cd "${QUI_ROOT:-/qui}"
swift build --scratch-path .build-linux --disable-index-store \
  --product quill-signal-decode-check
exec .build-linux/aarch64-unknown-linux-gnu/debug/quill-signal-decode-check
