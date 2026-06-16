#!/usr/bin/env bash
#
# SignalServiceKit Linux-prep concurrency fixes.
#
# SSK predates Swift's actor annotations and contains a small avatar-rendering
# utility that uses CAGradientLayer inside UIGraphicsImageRenderer's synchronous
# drawing closure. Apple's SDK accepts this UIKit-era pattern; Quill's
# QuartzCore shim is @MainActor to match UI-layer subclassing in SignalUI, so the
# prepared Linux copy needs this one draw block wrapped in MainActor.assumeIsolated.
#
# Usage: scripts/quill-signal-fix-ssk-concurrency.sh [SSK_ROOT]
#   SSK_ROOT defaults to .upstream/signal-ios/SignalServiceKit
set -euo pipefail

ROOT="${1:-.upstream/signal-ios/SignalServiceKit}"
FILE="$ROOT/Avatars/AvatarBuilder.swift"

if [ ! -f "$FILE" ]; then
    echo "quill-signal-fix-ssk-concurrency: AvatarBuilder not found; skipping"
    exit 0
fi

python3 - "$FILE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

if "MainActor.assumeIsolated" in src:
    print("quill-signal-fix-ssk-concurrency: AvatarBuilder already lowered")
    raise SystemExit(0)

old = """        let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
            let layer = CAGradientLayer()
            layer.frame = frame
            layer.colors = [gradient.topColor.cgColor, gradient.bottomColor.cgColor]
            layer.startPoint = CGPoint(x: 0.5, y: 0.0)
            layer.endPoint = CGPoint(x: 0.5, y: 1.0)
            layer.render(in: context.cgContext)
        }
"""

new = """        let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
            MainActor.assumeIsolated {
                let layer = CAGradientLayer()
                layer.frame = frame
                layer.colors = [gradient.topColor.cgColor, gradient.bottomColor.cgColor]
                layer.startPoint = CGPoint(x: 0.5, y: 0.0)
                layer.endPoint = CGPoint(x: 0.5, y: 1.0)
                layer.render(in: context.cgContext)
            }
        }
"""

if old not in src:
    raise SystemExit("quill-signal-fix-ssk-concurrency: expected AvatarBuilder gradient block not found")

path.write_text(src.replace(old, new, 1))
print("quill-signal-fix-ssk-concurrency: lowered AvatarBuilder gradient block")
PY
