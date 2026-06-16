#!/usr/bin/env bash
# Build-log-driven actor-isolation reconcile for the SignalApp slice. The app
# target is -default-isolation MainActor, so its overrides come out @MainActor;
# when they override a `nonisolated` base declaration (in SignalUI/SSK/QuillUIKit)
# the compiler errors "main actor-isolated X has different actor isolation from
# nonisolated overridden declaration". Fix: mark each such overriding member
# `nonisolated` to match the base. Run after a SignalApp build; iterate.
#
# Usage: scripts/quill-signal-fix-app-actor-isolation.sh <build-log>
set -euo pipefail
LOG="${1:?usage: quill-signal-fix-app-actor-isolation.sh <build-log>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$LOG" "$ROOT" <<'PY'
import re, sys
log, root = sys.argv[1], sys.argv[2]
from pathlib import Path

repo_root = Path(root).resolve()
upstream_root = repo_root / ".upstream/signal-ios"


def map_path(raw):
    if raw.startswith("/qui/"):
        path = repo_root / raw[len("/qui/"):]
    else:
        path = Path(raw)
        if not path.is_absolute():
            path = repo_root / path
    try:
        path.resolve().relative_to(upstream_root)
    except (FileNotFoundError, ValueError):
        return None
    return path if path.is_file() else None


member_pat = re.compile(
    r"^(?P<path>.+?\.swift):(?P<line>\d+):\d+: error: main actor-isolated "
    r"(?:property|getter for property|setter for property|instance method|class method|initializer) "
    r"'[^']*' has different actor isolation from nonisolated overridden declaration")
deinit_pat = re.compile(
    r"^(?P<path>.+?\.swift):(?P<line>\d+):\d+: error: nonisolated deinitializer "
    r"'deinit' has different actor isolation from main actor-isolated overridden declaration")

member_hits = {}
deinit_hits = {}
for line in open(log, errors='replace'):
    text = line.rstrip()
    m = member_pat.match(text)
    if m:
        f = map_path(m.group("path"))
        if f is not None:
            member_hits.setdefault(f, set()).add(int(m.group("line")))
        continue
    m = deinit_pat.match(text)
    if m:
        f = map_path(m.group("path"))
        if f is not None:
            deinit_hits.setdefault(f, set()).add(int(m.group("line")))

nonisolated_count = 0
mainactor_deinit_count = 0
changed_files = 0
for f in sorted(set(member_hits) | set(deinit_hits)):
    src = f.read_text().split('\n')
    changed = False

    for ln in sorted(member_hits.get(f, ())):
        i = ln - 1
        if not (0 <= i < len(src)): continue
        s = src[i]
        if 'nonisolated' in s: continue
        mm = re.match(r'^(\s*)(\S.*)$', s)
        if mm:
            src[i] = mm.group(1) + 'nonisolated ' + mm.group(2)
            nonisolated_count += 1
            changed = True

    for ln in sorted(deinit_hits.get(f, ())):
        i = ln - 1
        if not (0 <= i < len(src)): continue
        s = src[i]
        if '@MainActor' in s: continue
        if 'deinit' not in s: continue
        mm = re.match(r'^(\s*)(\S.*)$', s)
        if not mm: continue
        body = re.sub(r'\bnonisolated(?:\([^)]*\))?\s+', '', mm.group(2), count=1)
        src[i] = mm.group(1) + '@MainActor ' + body
        mainactor_deinit_count += 1
        changed = True

    if changed:
        f.write_text('\n'.join(src))
        changed_files += 1

print(
    'actor-isolation reconcile: marked '
    f'{nonisolated_count} declaration(s) nonisolated, '
    f'{mainactor_deinit_count} deinit(s) @MainActor across {changed_files} file(s)'
)
PY
