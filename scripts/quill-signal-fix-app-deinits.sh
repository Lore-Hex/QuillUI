#!/usr/bin/env bash
# Reconcile deinitializer actor isolation in disposable Signal app sources.
# Under -default-isolation MainActor, UIKit/AppKit bases can have main-actor
# deinits; source-lowered `nonisolated deinit` declarations then mismatch.
set -euo pipefail
LOG="${1:?usage: quill-signal-fix-app-deinits.sh <build-log>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$LOG" "$ROOT" <<'PY'
import pathlib, re, sys

log, root = sys.argv[1], pathlib.Path(sys.argv[2])
pat = re.compile(r"^/qui/(?P<file>[^:]+\.swift):(?P<line>\d+):\d+: error: nonisolated deinitializer 'deinit' has different actor isolation from main actor-isolated overridden declaration")
hits = {}
for line in open(log, errors="replace"):
    m = pat.match(line.rstrip())
    if m:
        hits.setdefault(root / m.group("file"), set()).add(int(m.group("line")))

changed = 0
for path, lines_to_fix in hits.items():
    if not path.exists():
        continue
    lines = path.read_text(errors="replace").splitlines()
    file_changed = False
    for lineno in sorted(lines_to_fix):
        i = lineno - 1
        if not (0 <= i < len(lines)):
            continue
        line = lines[i]
        if "nonisolated deinit" in line:
            lines[i] = line.replace("nonisolated deinit", "@MainActor deinit", 1)
            changed += 1
            file_changed = True
        elif re.match(r'^\s*deinit\b', line) and "@MainActor" not in line:
            indent = re.match(r'^(\s*)', line).group(1)
            lines[i] = indent + "@MainActor " + line[len(indent):]
            changed += 1
            file_changed = True
    if file_changed:
        path.write_text("\n".join(lines) + "\n")

print(f"deinit isolation lowering: marked {changed} deinits across {len(hits)} files")
PY
