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
from pathlib import Path

log, root = sys.argv[1], sys.argv[2]
repo_root = Path(root).resolve()
upstream_root = repo_root / ".upstream/signal-ios"

STRIP=['overriding non-open instance method outside of its defining module',
       'overriding non-open property outside of its defining module',
       'overriding non-open class method outside of its defining module',
       'method does not override any method from its superclass',
       'property does not override any property from its superclass',
       'initializer does not override a designated initializer from its superclass']
ADD=["overriding declaration requires an 'override' keyword"]
loc=re.compile(r'^(?P<path>.+?\.swift):(?P<line>\d+):\d+: error: (?P<msg>.+)$')
decl_re = re.compile(r'^(\s*)(.*?)(\b(?:class\s+func|static\s+func|func|var|let|init|subscript)\b.*)$')
alias_property_re = re.compile(
    r'^\s*(?:(?:public|internal|private|fileprivate|open|package|override)\s+)*'
    r'var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:[^{]+{\s*([A-Za-z_][A-Za-z0-9_]*)\s*}\s*$'
)
strip={}; add={}


def map_path(raw):
    if raw.startswith('/qui/'):
        path = repo_root / raw[len('/qui/'):]
    else:
        path = Path(raw)
        if not path.is_absolute():
            path = repo_root / path
    try:
        path.resolve().relative_to(upstream_root)
    except (FileNotFoundError, ValueError):
        return None
    return path if path.is_file() else None


for line in open(log, errors='replace'):
    m=loc.match(line.rstrip())
    if not m: continue
    f=map_path(m.group('path'))
    if f is None: continue
    ln,msg=int(m.group('line')),m.group('msg')
    if any(p in msg for p in STRIP): strip.setdefault(f,{})[ln]=msg
    elif any(p in msg for p in ADD): add.setdefault(f,set()).add(ln)


def remove_override(line):
    return re.sub(r'\boverride\s+','',line,count=1)


def add_override(line):
    if 'override' in line:
        return line
    m = decl_re.match(line)
    if not m:
        return line
    return m.group(1) + m.group(2) + 'override ' + m.group(3)


def find_decl_index(src, idx):
    for candidate in range(idx, min(len(src), idx + 4)):
        if decl_re.match(src[candidate]):
            return candidate
    return idx


def lower_nonopen_alias_property(src, idx):
    if not (0 <= idx < len(src)):
        return False
    m = alias_property_re.match(src[idx])
    if not m:
        return False
    name, backing = m.group(1), m.group(2)
    if name == backing:
        return False
    src[idx] = None
    for line_idx, line in enumerate(src):
        if line is None:
            continue
        line = line.replace(f'self.{name}?.', f'self.{backing}.')
        line = line.replace(f'self.{name}.', f'self.{backing}.')
        src[line_idx] = line
    return True


ns=na=aliases=0
files=set(strip)|set(add)
for f in files:
    src=f.read_text().split('\n')
    changed=False
    for ln,msg in strip.get(f,{}).items():
        i=ln-1
        if 0<=i<len(src) and src[i] is not None and 'override' in src[i]:
            new=remove_override(src[i])
            if new!=src[i]:
                src[i]=new; ns+=1; changed=True
        elif 'overriding non-open property outside of its defining module' in msg:
            if lower_nonopen_alias_property(src, i):
                aliases+=1; changed=True
    for ln in add.get(f,()):
        i=find_decl_index(src, ln-1)
        if 0<=i<len(src) and src[i] is not None:
            new=add_override(src[i])
            if new!=src[i]:
                src[i]=new; na+=1; changed=True
    if changed:
        f.write_text('\n'.join(line for line in src if line is not None))
print(f'override reconcile: stripped {ns}, added {na}, removed {aliases} non-open alias property declaration(s) across {len(files)} file(s)')
PY
