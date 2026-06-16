#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: strip `#Preview { ... }` blocks
# from the Signal-iOS source tree.
#
# Xcode 15's `#Preview` is a freestanding macro vended by the (closed-source)
# SwiftUI/PreviewsMacros toolchain plugin — pure dev-tooling, never part of the
# shipping product. There is no such macro on Linux, so every use is a hard
# `error: no macro named 'Preview'` (517× in the Track B build). Dropping the
# blocks is exactly what Apple does for release builds, so a brace-balanced
# strip is faithful.
#
# What it removes, per occurrence:
#   - any contiguous attribute lines directly above (`@available(iOS 17, *)`,
#     `@MainActor`, ...) — an orphaned attribute is itself a compile error;
#   - the `#Preview` line, its optional `("Name", ...)` argument list, and the
#     trailing closure through the MATCHING brace (string- and comment-aware,
#     so braces inside literals/comments don't unbalance the scan).
# Surrounding `#if DEBUG` wrappers are left alone (an empty region compiles).
#
# Mutates the disposable, gitignored `.upstream` checkout IN PLACE — the
# committed SCRIPT is the durable artifact. Idempotent (re-run = 0 removals).
# Run after fetch, alongside quill-signal-inject-foundation.sh and
# quill-signal-strip-tests.sh. NOTE (LESSONS.md "pipeline mechanics gotcha"):
# the build does NOT run this for you; re-run it against `.upstream` yourself.
#
# Usage: scripts/quill-signal-strip-previews.sh [SIGNAL_ROOT]
#   SIGNAL_ROOT defaults to .upstream/signal-ios (SignalUI + SignalServiceKit
#   are scanned; Pods/, .git/ and the QuillPort symlink overlay are skipped).
#
set -euo pipefail

ROOT="${1:-.upstream/signal-ios}"

if [ ! -d "$ROOT" ]; then
    echo "error: signal-ios root not found: $ROOT" >&2
    exit 1
fi

python3 - "$ROOT" <<'PY'
import os
import re
import sys

ROOT = sys.argv[1]
PREVIEW_RE = re.compile(r'(?m)^[ \t]*#Preview\b')
SKIP_DIRS = {".git", "Pods", "QuillPort"}


def scan_code(src, i, openers, closers):
    """Advance through src from i, skipping strings and comments, tracking the
    depth of openers/closers. Returns the index of the closer that brings the
    depth back to zero, or -1. i must point at the opener."""
    n = len(src)
    depth = 0
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            d = 1
            i += 2
            while i + 1 < n and d:
                if src[i] == "/" and src[i + 1] == "*":
                    d += 1
                    i += 2
                elif src[i] == "*" and src[i + 1] == "/":
                    d -= 1
                    i += 2
                else:
                    i += 1
            continue
        if c == '"':
            if src.startswith('"""', i):
                j = src.find('"""', i + 3)
                i = n if j < 0 else j + 3
                continue
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                elif src[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            continue
        if c in openers:
            depth += 1
        elif c in closers:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def strip_file(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    if "#Preview" not in src:
        return 0
    removed = 0
    pos = 0
    while True:
        m = PREVIEW_RE.search(src, pos)
        if not m:
            break
        n = len(src)
        # Walk back over contiguous attribute lines (@available, @MainActor, ...).
        block_start = m.start()
        while True:
            prev_nl = src.rfind("\n", 0, block_start)
            if prev_nl < 0:
                break
            prev_start = src.rfind("\n", 0, prev_nl) + 1
            if not src[prev_start:prev_nl].strip().startswith("@"):
                break
            block_start = prev_start
        # Optional balanced ("Name", ...) argument list after the macro name.
        i = m.end()
        while i < n and src[i] in " \t":
            i += 1
        if i < n and src[i] == "(":
            close = scan_code(src, i, "(", ")")
            if close < 0:
                print(f"warning: unbalanced #Preview args in {path}; left as-is",
                      file=sys.stderr)
                pos = m.end()
                continue
            i = close + 1
        while i < n and src[i] in " \t\r\n":
            i += 1
        if i >= n or src[i] != "{":
            print(f"warning: #Preview without trailing closure in {path}; left as-is",
                  file=sys.stderr)
            pos = m.end()
            continue
        close = scan_code(src, i, "{", "}")
        if close < 0:
            print(f"warning: unbalanced #Preview block in {path}; left as-is",
                  file=sys.stderr)
            pos = m.end()
            continue
        end = src.find("\n", close)
        end = n if end < 0 else end + 1
        src = src[:block_start] + src[end:]
        pos = block_start
        removed += 1
    if removed:
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)
    return removed


total = 0
files = 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for name in filenames:
        if not name.endswith(".swift"):
            continue
        path = os.path.join(dirpath, name)
        if os.path.islink(path):
            continue
        n = strip_file(path)
        if n:
            total += n
            files += 1

print(f"quill-signal-strip-previews: removed {total} #Preview block(s) from {files} file(s)")
PY
