#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: symlink the committed ObjC-port
# Swift files into the SignalServiceKit source tree.
#
# The faithful Swift ports of Signal's ObjC core-model classes (TSInteraction,
# TSMessage, the TS*/OWS* subclasses, ...) live and are version-controlled in
# Sources/SignalServiceKitObjCPort/. SwiftPM compiles the SignalServiceKit
# *library* from the .upstream/ tree (gitignored/disposable), so each port must
# appear UNDER that tree to be compiled into the SAME module as the upstream
# Swift that subclasses it. This step symlinks every committed port into
# <SSK>/QuillPort/ using a RELATIVE path, so the link resolves both on the host
# and inside the build container (where the repo is mounted at a different
# absolute path -- an absolute symlink silently fails to compile there).
#
# Idempotent (rm + re-create each link). Run after fetching .upstream, alongside
# quill-signal-inject-foundation.sh and quill-signal-strip-tests.sh.
#
# Usage: scripts/quill-signal-link-ports.sh [SSK_ROOT]
#   SSK_ROOT defaults to .upstream/signal-ios/SignalServiceKit
#
set -euo pipefail

ROOT="${1:-.upstream/signal-ios/SignalServiceKit}"
PORT_SRC_DIR="Sources/SignalServiceKitObjCPort"

if [ ! -d "$ROOT" ]; then
    echo "error: SSK root not found: $ROOT" >&2
    exit 1
fi
if [ ! -d "$PORT_SRC_DIR" ]; then
    echo "error: port source dir not found: $PORT_SRC_DIR" >&2
    exit 1
fi

QUILLPORT_DIR="$ROOT/QuillPort"
mkdir -p "$QUILLPORT_DIR"

# Relative path from QuillPort/ back to the repo root, then into the port dir.
# QuillPort -> SignalServiceKit -> signal-ios -> .upstream -> <repo root>.
REL_PREFIX="../../../../$PORT_SRC_DIR"

linked=0
for f in "$PORT_SRC_DIR"/*.swift; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    link="$QUILLPORT_DIR/$base"
    rm -f "$link"
    ln -s "$REL_PREFIX/$base" "$link"
    linked=$((linked + 1))
done

echo "quill-signal-link-ports: linked $linked port file(s) into $QUILLPORT_DIR"
