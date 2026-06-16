#!/usr/bin/env bash
# Build-log-driven override reconciliation for the SignalApp slice. Cross-module
# override errors come in two opposite flavors that must be fixed in tandem and
# iterated to convergence (base-class openness flips as shims resolve):
#   - "overriding non-open ... outside of its defining module" / "does not
#     override ..."  -> the base isn't overridable here; STRIP the `override`.
#   - "overriding declaration requires an 'override' keyword"  -> the base IS
#     overridable; ADD `override` back.
# Run after each SignalApp build, passing the build log; re-run until neither
# error remains. Edits the disposable .upstream tree in place.
#
# Usage: scripts/quill-signal-fix-app-overrides.sh <build-log>
set -euo pipefail
LOG="${1:?usage: quill-signal-fix-app-overrides.sh <build-log>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$LOG" "$ROOT" <<'PY'
import re, sys
log, root = sys.argv[1], sys.argv[2]
STRIP=['overriding non-open instance method outside of its defining module',
       'overriding non-open property outside of its defining module',
       'overriding non-open class method outside of its defining module',
       'method does not override any method from its superclass',
       'property does not override any property from its superclass',
       'initializer does not override a designated initializer from its superclass']
ADD=["overriding declaration requires an 'override' keyword"]
loc=re.compile(r'^(/qui/[^:]+\.swift):(\d+):\d+: error: (.+)$')
strip={}; add={}
for line in open(log, errors='replace'):
    m=loc.match(line.rstrip())
    if not m: continue
    f,ln,msg=m.group(1).replace('/qui/', root+'/'),int(m.group(2)),m.group(3)
    if any(p in msg for p in STRIP): strip.setdefault(f,set()).add(ln)
    elif any(p in msg for p in ADD): add.setdefault(f,set()).add(ln)
ns=na=0
files=set(strip)|set(add)
for f in files:
    try: src=open(f).read().split('\n')
    except FileNotFoundError: continue
    for ln in strip.get(f,()):
        i=ln-1
        if 0<=i<len(src) and 'override' in src[i]:
            new=re.sub(r'\boverride\s+','',src[i],count=1)
            if new!=src[i]: src[i]=new; ns+=1
    for ln in add.get(f,()):
        i=ln-1
        if 0<=i<len(src) and 'override' not in src[i]:
            new=re.sub(r'\b(public |private |internal |open |fileprivate )*(func|var|let|class func|static func|init|subscript)\b',
                       lambda mm:(mm.group(0).rsplit(mm.group(2),1)[0]+'override '+mm.group(2)), src[i], count=1)
            if new!=src[i]: src[i]=new; na+=1
    open(f,'w').write('\n'.join(src))
print(f'override reconcile: stripped {ns}, added {na} across {len(files)} files')
PY
