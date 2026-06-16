#!/usr/bin/env bash
# Build-log-driven access lowering for the disposable SignalApp source slice.
# Swift reports declarations as public when the declaration itself is public, or
# when it lives inside a public protocol/public extension. For app-only Linux
# lowering we can make those declarations internal when their signatures mention
# types that remain internal in the pruned app module.
#
# Usage: scripts/quill-signal-fix-app-public-access.sh <build-log> [UPSTREAM_ROOT]
#   UPSTREAM_ROOT defaults to .upstream/signal-ios
set -euo pipefail

LOG="${1:?usage: quill-signal-fix-app-public-access.sh <build-log> [UPSTREAM_ROOT]}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="${2:-$ROOT/.upstream/signal-ios}"

python3 - "$LOG" "$ROOT" "$UPSTREAM" <<'PY'
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2]).resolve()
upstream_root = Path(sys.argv[3]).resolve()

diag_re = re.compile(r"^(?P<path>.+?\.swift):(?P<line>\d+):\d+: error: (?P<msg>.+)$")
decl_re = re.compile(
    r"^(\s*)(.*?)(\b(?:func|var|let|init|subscript|class|struct|enum|protocol|typealias)\b.*)$"
)
public_container_re = re.compile(r"^\s*public\s+(?:protocol|extension)\b")


def map_path(raw):
    if raw.startswith("/qui/"):
        path = repo_root / raw[len("/qui/") :]
    else:
        path = Path(raw)
        if not path.is_absolute():
            path = repo_root / path
    try:
        path.resolve().relative_to(upstream_root)
    except (FileNotFoundError, ValueError):
        return None
    return path if path.is_file() else None


def strip_public_from_decl(line):
    match = decl_re.match(line)
    if not match:
        return line, False
    indent, prefix, rest = match.groups()
    new_prefix, count = re.subn(r"(?<!\S)public\s+", "", prefix, count=1)
    if count == 0:
        return line, False
    return indent + new_prefix + rest, True


def scope_contains(lines, start, target):
    balance = 0
    saw_open = False
    for idx in range(start, target + 1):
        # Good enough for Swift declarations: these container lines do not use
        # braces in strings before the declaration body.
        code = lines[idx].split("//", 1)[0]
        opens = code.count("{")
        closes = code.count("}")
        if opens:
            saw_open = True
        balance += opens - closes
        if idx < target and saw_open and balance <= 0:
            return False
    return saw_open and balance > 0


def public_container_for(lines, target):
    for idx in range(target, -1, -1):
        if public_container_re.match(lines[idx]) and scope_contains(lines, idx, target):
            return idx
    return None


hits = {}
with log_path.open(errors="replace") as log:
    for raw_line in log:
        match = diag_re.match(raw_line.rstrip())
        if not match:
            continue
        msg = match.group("msg")
        if (
            "internal type" not in msg
            or (
                "cannot be declared public because" not in msg
                and "must be declared internal because" not in msg
            )
        ):
            continue
        path = map_path(match.group("path"))
        if path is None:
            continue
        hits.setdefault(path, set()).add(int(match.group("line")))

decls = 0
containers = 0
changed_files = 0

for path, line_numbers in sorted(hits.items()):
    lines = path.read_text().split("\n")
    changed = False

    for line_number in sorted(line_numbers):
        idx = line_number - 1
        if not (0 <= idx < len(lines)):
            continue

        lowered, did_lower = strip_public_from_decl(lines[idx])
        if did_lower:
            lines[idx] = lowered
            decls += 1
            changed = True

        container_idx = public_container_for(lines, idx)
        if container_idx is not None:
            lowered, did_lower = strip_public_from_decl(lines[container_idx])
            if did_lower:
                lines[container_idx] = lowered
                containers += 1
                changed = True

    if changed:
        path.write_text("\n".join(lines))
        changed_files += 1

print(
    "public-access reconcile: lowered "
    f"{decls} declaration(s), {containers} public protocol/extension container(s) "
    f"across {changed_files} file(s)"
)
PY
