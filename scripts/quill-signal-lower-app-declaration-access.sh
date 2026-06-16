#!/usr/bin/env bash
# Make declarations in Signal's disposable app slice internal while preserving
# `public import` normalization. The app target has no public ABI on Linux, and
# keeping upstream's public declarations causes SwiftPM to reject signatures that
# mention app-internal types.
set -euo pipefail
APP="${1:?usage: quill-signal-lower-app-declaration-access.sh <Signal-app-dir>}"

python3 - "$APP" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
if not root.exists():
    print(f"app declaration access lowering: no app dir at {root}")
    raise SystemExit(0)

decl = re.compile(r'\b(?:class|struct|enum|protocol|extension|actor|typealias|func|var|let|init|subscript)\b')
changed_files = 0
changed_lines = 0

for path in root.rglob("*.swift"):
    if "QuillPort" in path.parts:
        continue
    lines = path.read_text(errors="replace").splitlines()
    out = []
    changed = False
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith("//") or re.match(r'^\s*(?:public\s+)?import\b', line):
            out.append(line)
            continue
        m = decl.search(line)
        if not m:
            out.append(line)
            continue
        prefix = line[:m.start()]
        new_prefix = re.sub(r'(?<!\S)(?:public|open)\s+', '', prefix)
        lowered = new_prefix + line[m.start():]
        if lowered != line:
            changed = True
            changed_lines += 1
        out.append(lowered)
    if changed:
        path.write_text("\n".join(out) + ("\n" if lines else ""))
        changed_files += 1

print(f"app declaration access lowering: lowered {changed_lines} declaration line(s) across {changed_files} file(s)")
PY
