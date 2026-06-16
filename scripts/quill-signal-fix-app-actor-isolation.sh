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
# Members that can be `nonisolated`: property/getter/method/initializer/class method.
# (deinit is handled separately by the @MainActor-deinit pass; skip it here.)
pat = re.compile(
    r"^(/qui/[^:]+\.swift):(\d+):\d+: error: main actor-isolated "
    r"(?:property|getter for property|setter for property|instance method|class method|initializer) "
    r"'[^']*' has different actor isolation from nonisolated overridden declaration")
hits = {}
for line in open(log, errors='replace'):
    m = pat.match(line.rstrip())
    if m:
        f = m.group(1).replace('/qui/', root + '/')
        hits.setdefault(f, set()).add(int(m.group(2)))
n = 0
for f, lines in hits.items():
    try: src = open(f).read().split('\n')
    except FileNotFoundError: continue
    for ln in lines:
        i = ln - 1
        if not (0 <= i < len(src)): continue
        s = src[i]
        if 'nonisolated' in s: continue
        # Insert `nonisolated ` after the leading indentation, before the first
        # declaration modifier/keyword.
        mm = re.match(r'^(\s*)(\S.*)$', s)
        if mm:
            src[i] = mm.group(1) + 'nonisolated ' + mm.group(2)
            n += 1
    open(f, 'w').write('\n'.join(src))
print(f'actor-isolation reconcile: marked {n} declarations nonisolated across {len(hits)} files')
PY
