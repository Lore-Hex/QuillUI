#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: fix the GRDB Row index-subscript
# inference in the generated *+SDS.swift deserializers.
#
# The SDS deserializers decode enum columns with:
#     x = row[N].flatMap { SomeEnum(rawValue: $0) }
# relying on the closure to constrain the element type so the GENERIC optional
# index subscript is chosen. GRDB 7.10 (groue/GRDB, our SPM pin) exposes only:
#     subscript(_ index: Int) -> (any DatabaseValueConvertible)?   // non-generic
#     subscript<Value: DatabaseValueConvertible>(_ index: Int) -> Value  // non-OPTIONAL
# i.e. there is NO generic *optional* index subscript, so `row[N]` (needing an
# Optional to .flatMap over) resolves to the non-generic existential overload and
# `SomeEnum(rawValue: $0)` fails: "cannot convert any DatabaseValueConvertible to
# Int/UInt/UInt64/Int32" (225 in TSInteraction+SDS alone). Signal builds against a
# GRDB fork that has the optional generic subscript, so upstream compiles there.
#
# Fix: make the typed optional explicit via the idiomatic GRDB cast, using the
# enum's own RawValue so we never need to know the concrete underlying type:
#     (row[N] as SomeEnum.RawValue?).flatMap { SomeEnum(rawValue: $0) }
# `row[N] as UInt?` (etc) selects the generic subscript with Value = Optional<...>
# (Optional conforms to DatabaseValueConvertible when Wrapped does) -- unambiguous,
# since the non-generic overload returns the existential, not the typed optional.
#
# Idempotent (after rewrite `row[N]` is followed by ` as`, no longer `.flatMap`,
# so it won't re-match) and disposable-tree-only: the SCRIPT is the durable
# artifact. Run as part of the upstream prepare (alongside inject-foundation etc).
#
# Usage: scripts/quill-signal-fix-sds-rowsubscript.sh [SSK_ROOT]
#   SSK_ROOT defaults to .upstream/signal-ios/SignalServiceKit
#
set -euo pipefail

ROOT="${1:-.upstream/signal-ios/SignalServiceKit}"

if [ ! -d "$ROOT" ]; then
    echo "error: SSK root not found: $ROOT" >&2
    exit 1
fi

python3 - "$ROOT" <<'PY'
import os, re, sys

root = sys.argv[1]
# row[<idx>].flatMap { <Enum>(rawValue: $0) }  ->
# (row[<idx>] as <Enum>.RawValue?).flatMap { <Enum>(rawValue: $0) }
pat = re.compile(r'\brow\[(\d+)\]\.flatMap \{ (\w+)\(rawValue: \$0\) \}')

changed_files = 0
changed_sites = 0
for dirpath, _dirs, files in os.walk(root):
    for name in files:
        if not name.endswith('.swift'):
            continue
        path = os.path.join(dirpath, name)
        with open(path, 'r') as f:
            src = f.read()
        new, n = pat.subn(
            lambda m: '(row[%s] as %s.RawValue?).flatMap { %s(rawValue: $0) }'
                      % (m.group(1), m.group(2), m.group(2)),
            src)
        if n:
            with open(path, 'w') as f:
                f.write(new)
            changed_files += 1
            changed_sites += n

print("quill-signal-fix-sds-rowsubscript: rewrote %d site(s) in %d file(s)"
      % (changed_sites, changed_files))
PY
