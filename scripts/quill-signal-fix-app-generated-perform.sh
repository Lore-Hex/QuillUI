#!/usr/bin/env bash
# Repair target-action dispatch emitted from selector lowering when the selected
# Swift method is throwing. ObjC selectors discard thrown errors; on Linux we
# mirror that by using `try?`.
set -euo pipefail
APP="${1:?usage: quill-signal-fix-app-generated-perform.sh <Signal-app-dir>}"

python3 - "$APP" <<'PY'
import pathlib, sys

root = pathlib.Path(sys.argv[1])
replacements = {
    "src/ViewControllers/ViewOnceMessageViewController.swift": [
        ('case "applicationWillEnterForeground": applicationWillEnterForeground()',
         'case "applicationWillEnterForeground": try? applicationWillEnterForeground()'),
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

print(f"generated perform lowering: patched {changed} file(s)")
PY
