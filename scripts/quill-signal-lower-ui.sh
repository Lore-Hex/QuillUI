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
# Usage: scripts/quill-signal-lower-ui.sh [SCRATCH_PATH]
#   SCRATCH_PATH defaults to .build (where quill-lower-appkit is built if absent).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${1:-$ROOT/.build}"
SUI="$ROOT/.upstream/signal-ios/SignalUI"

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
if [ ! -x "$TOOL" ]; then
    swift build --scratch-path "$SCRATCH" --disable-index-store \
        --product quill-lower-appkit >/dev/null 2>&1 || true
fi
if [ -x "$TOOL" ]; then
    "$TOOL" "$SUI"
else
    echo "quill-signal-lower-ui: quill-lower-appkit not built; @objc lowering skipped" >&2
fi
