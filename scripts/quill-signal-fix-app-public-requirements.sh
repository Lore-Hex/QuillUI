#!/usr/bin/env bash
# Re-add `public` for app declarations that witness public protocol
# requirements from dependency modules. This complements the broad app
# declaration-access lowering, which is correct for app-owned ABI but too broad
# for external public protocols.
set -euo pipefail
LOG="${1:?usage: quill-signal-fix-app-public-requirements.sh <build-log>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/.upstream/signal-ios"

python3 - "$LOG" "$ROOT" "$UPSTREAM" <<'PY'
import pathlib, re, sys

log = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2]).resolve()
upstream = pathlib.Path(sys.argv[3]).resolve()
pat = re.compile(r"^(?P<path>.+?\.swift):(?P<line>\d+):\d+: error: .* must be declared public because it matches a requirement in public protocol ")
decl = re.compile(r'^(\s*)((?:(?:@[\w.()]+\s+)|(?:nonisolated\s+)|(?:override\s+)|(?:static\s+)|(?:class\s+)|(?:final\s+)|(?:mutating\s+))*)(func|var|let|init|subscript)\b')

hits = {}
for raw in log.read_text(errors="replace").splitlines():
    m = pat.match(raw)
    if not m:
        continue
    raw_path = m.group("path")
    path = root / raw_path[len("/qui/"):] if raw_path.startswith("/qui/") else pathlib.Path(raw_path)
    try:
        path.resolve().relative_to(upstream)
    except (FileNotFoundError, ValueError):
        continue
    hits.setdefault(path, set()).add(int(m.group("line")))

changed = 0
for path, lines_to_fix in hits.items():
    if not path.exists():
        continue
    lines = path.read_text(errors="replace").splitlines()
    file_changed = False
    for line_number in sorted(lines_to_fix):
        i = line_number - 1
        if not (0 <= i < len(lines)) or " public " in f" {lines[i]} ":
            continue
        m = decl.match(lines[i])
        if not m:
            continue
        lines[i] = lines[i][:m.start(3)] + "public " + lines[i][m.start(3):]
        changed += 1
        file_changed = True
    if file_changed:
        path.write_text("\n".join(lines) + "\n")

print(f"public requirement reconcile: added public to {changed} declaration(s) across {len(hits)} file(s)")
PY
