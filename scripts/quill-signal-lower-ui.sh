#!/usr/bin/env bash
#
# Reproducible build-prep: lower Signal-iOS's SignalUI source so it compiles on
# QuillOS/Linux against QuillUI's UIKit layer. Edits IN PLACE in the disposable
# `.upstream` copy (produced by the upstream-fetch pipeline) -- never a pristine
# checkout you keep. Two app-agnostic transforms:
#
#   1) `import UIKit.UIGestureRecognizerSubclass` -> `import UIKit`. That Clang
#      submodule has no Linux equivalent; the Swift UIKit shim provides the
#      gesture-subclass surface in the base module. (DirectionalPanGestureRecognizer.)
#
#   2) AppKit / Objective-C target-action lowering via `quill-lower-appkit`
#      (QuillSourceLowering.AppKitLowering): strips `@objc` / `@IBAction` /
#      `@IBOutlet` / `@IBInspectable`, rewrites `#selector(x)` -> `Selector("x")`,
#      and relocates `override` members out of extensions. UIKit uses the exact
#      same `@objc` patterns as AppKit, so this is the wall-breaker for the
#      @objc-on-Linux problem (it took SignalUI's @objc errors ~5,700 -> ~100).
#
#   3) Reusable generated-source cleanup (`lower-objc-interop-for-linux.sh`):
#      removes Swift/CoreFoundation bridge casts that swift-corelibs Foundation
#      does not support and that Quill's shims accept as native Swift values.
#
# Usage: scripts/quill-signal-lower-ui.sh [SCRATCH_PATH]
#   SCRATCH_PATH defaults to .build (where quill-lower-appkit is built if absent).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${1:-$ROOT/.build}"
SUI="$ROOT/.upstream/signal-ios/SignalUI"
UI_PORT_SRC="$ROOT/Sources/SignalUIObjCPort"

if [ ! -d "$SUI" ]; then
    echo "quill-signal-lower-ui: no SignalUI upstream at $SUI; skipping"
    exit 0
fi

# (1) UIKit Clang-submodule import -> base UIKit module.
sed -i 's/^import UIKit\.UIGestureRecognizerSubclass/import UIKit/' \
    "$SUI/Views/DirectionalPanGestureRecognizer.swift" 2>/dev/null || true

# (2) @objc / target-action lowering. Build the tool on demand (cached after the
# first run), then apply it in place.
TOOL="$SCRATCH/debug/quill-lower-appkit"
swift build --scratch-path "$SCRATCH" --disable-index-store \
    --product quill-lower-appkit >/dev/null 2>&1 || true
if [ -x "$TOOL" ]; then
    "$TOOL" "$SUI"
else
    echo "quill-signal-lower-ui: quill-lower-appkit not built; @objc lowering skipped" >&2
fi

# (3) Swift/corelibs compatibility cleanup for disposable generated source.
"$ROOT/scripts/lower-objc-interop-for-linux.sh" "$SUI"

# (4) Same-module Swift ports for small ObjC categories that SignalUI excludes
# on Linux. Keep these as symlinks into the disposable upstream tree so the
# canonical Signal source remains untouched and the extension members are
# visible inside the SignalUI module.
if [ -d "$UI_PORT_SRC" ]; then
    QUILLPORT_DIR="$SUI/QuillPort"
    mkdir -p "$QUILLPORT_DIR"
    REL_PREFIX="../../../../Sources/SignalUIObjCPort"
    linked=0
    for f in "$UI_PORT_SRC"/*.swift; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        link="$QUILLPORT_DIR/$base"
        rm -f "$link"
        ln -s "$REL_PREFIX/$base" "$link"
        linked=$((linked + 1))
    done
    echo "quill-signal-lower-ui: linked $linked SignalUI port file(s) into $QUILLPORT_DIR"
fi
