#!/usr/bin/env bash
#
# Reproducible build-prep: lower Signal-iOS's SignalUI source so it compiles on
# QuillOS/Linux against QuillUI's UIKit layer. Edits IN PLACE in the disposable
# `.upstream` copy (produced by the upstream-fetch pipeline) -- never a pristine
# checkout you keep. App-agnostic transforms:
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
#   4) Foundation/corelibs source lowering via `quill-lower-foundation`.
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

# Remove stale same-module port symlinks from previous runs before running
# source-lowering tools. Otherwise generic lowerers can write through symlinks
# and dirty checked-in Quill port sources.
rm -rf "$SUI/QuillPort"

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
FOUNDATION_TOOL="$SCRATCH/debug/quill-lower-foundation"
swift build --scratch-path "$SCRATCH" --disable-index-store \
    --product quill-lower-foundation >/dev/null 2>&1 || true
if [ -x "$FOUNDATION_TOOL" ]; then
    "$FOUNDATION_TOOL" "$SUI"
else
    echo "quill-signal-lower-ui: quill-lower-foundation not built; Foundation lowering skipped" >&2
fi

# (3b) `UITextView` inherits `UIScrollView`, whose Swift-visible `delegate` is
# typed as `UIScrollViewDelegate?`; Apple's ObjC bridge lets `UITextView`
# narrow that property, but pure Swift cannot model the covariance without
# breaking scroll-view assignment. BodyRangesTextView's override only asserts
# `delegate === self`, so drop that assertion wrapper and use the inherited
# delegate storage.
python3 - "$SUI/Views/BodyRanges/BodyRangesTextView.swift" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
if not path.exists():
    raise SystemExit(0)

text = path.read_text(errors="replace")
old = """    override public var delegate: UITextViewDelegate? {
        didSet {
            if let delegate {
                owsAssertDebug(delegate === self)
            }
        }
    }

"""
new = ""
if old in text:
    path.write_text(text.replace(old, new, 1))
PY

# (3c) SignalUI has a few private CALayer subclasses whose overrides must match
# Quill's nonisolated QuartzCore surface under Linux default-actor-isolation
# builds. Mark the generated subclasses nonisolated rather than weakening the
# base layer API.
python3 - \
    "$SUI/ImageEditor/ImageEditorCanvasView.swift" \
    "$SUI/Stickers/EditorSticker.swift" <<'PY'
import pathlib, sys

replacements = {
    "class EditorTextLayer: CATextLayer {": "nonisolated class EditorTextLayer: CATextLayer {",
    "private class TextFrameLayer: CAShapeLayer {": "private nonisolated class TextFrameLayer: CAShapeLayer {",
    "private class AnalogClockLayer: CALayer {": "private nonisolated class AnalogClockLayer: CALayer {",
}

for filename in sys.argv[1:]:
    path = pathlib.Path(filename)
    if not path.exists():
        continue
    text = path.read_text(errors="replace")
    updated = text
    for old, new in replacements.items():
        updated = updated.replace(old, new)
    while "nonisolated nonisolated" in updated:
        updated = updated.replace("nonisolated nonisolated", "nonisolated")
    if updated != text:
        path.write_text(updated)
PY

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
