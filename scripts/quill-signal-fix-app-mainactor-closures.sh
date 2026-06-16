#!/usr/bin/env bash
# Patch known UIKit timer closures in the disposable Signal app slice so they
# retain main-actor isolation after Objective-C/AppKit lowering.
set -euo pipefail
APP="${1:?usage: quill-signal-fix-app-mainactor-closures.sh <Signal-app-dir>}"

python3 - "$APP" <<'PY'
import pathlib, sys

root = pathlib.Path(sys.argv[1])
replacements = {
    "ConversationView/CellViews/MessageTimerView.swift": [
        ("block: { [weak self] timer in", "block: { @MainActor [weak self] timer in"),
    ],
    "ConversationView/ConversationViewController+Delegates.swift": [
        ("Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in",
         "Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { @MainActor [weak self] _ in"),
        (".scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in",
         ".scheduledTimer(withTimeInterval: 5, repeats: false) { @MainActor [weak self] _ in"),
    ],
}

changed = 0
for rel, pairs in replacements.items():
    path = root / rel
    if not path.exists():
        continue
    text = path.read_text(errors="replace")
    original = text
    for old, new in pairs:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text)
        changed += 1

print(f"mainactor closure lowering: patched {changed} file(s)")
PY
