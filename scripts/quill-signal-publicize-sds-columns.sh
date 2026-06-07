#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: make `enum Columns` declarations
# public in SignalServiceKit's GRDB record types.
#
# GRDB record structs (PollRecord, AttachmentReference records, ...) declare a
# nested `enum Columns { ... }` (internal) used as ColumnExpressions. On Apple
# these conform to GRDB protocols transparently, but on Linux the conformer is a
# `public` type whose protocol requirement (matched by `Columns`) forces the enum
# to be public too: "enum 'Columns' must be declared public because it matches a
# requirement in public protocol 'TableRecord'". This prefixes `public ` to those
# nested enums.
#
# Idempotent + disposable-tree-only (the SCRIPT is the durable committed artifact).
#
# Usage: scripts/quill-signal-publicize-sds-columns.sh [SSK_ROOT]
#
set -euo pipefail

ROOT="${1:-.upstream/signal-ios/SignalServiceKit}"
if [ ! -d "$ROOT" ]; then
    echo "error: SSK root not found: $ROOT" >&2
    exit 1
fi

python3 - "$ROOT" <<'PY'
import re, sys, os

root = sys.argv[1]
# `enum Columns` at the start of a line (any indent) -> `public enum Columns`.
# The leading-whitespace-then-"enum" anchor means an already-`public enum Columns`
# (which has "public " before "enum") is skipped -> idempotent.
pat = re.compile(r'(?m)^(\s*)(enum Columns\b)')
changed_files = 0
total = 0
for dirpath, _dirs, files in os.walk(root):
    for fn in files:
        if not fn.endswith(".swift"):
            continue
        path = os.path.join(dirpath, fn)
        src = open(path, encoding="utf-8").read()
        if "enum Columns" not in src:
            continue
        new, n = pat.subn(r'\1public \2', src)
        if n:
            open(path, "w", encoding="utf-8").write(new)
            changed_files += 1
            total += n
            print(f"  {os.path.relpath(path, root)}: publicized {n} enum Columns")

print(f"quill-signal-publicize-sds-columns: publicized {total} enum(s) in {changed_files} file(s)")
PY
