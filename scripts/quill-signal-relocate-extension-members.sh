#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: relocate the overridable
# TSOutgoingMessage members out of upstream `extension TSOutgoingMessage` blocks.
#
# Swift cannot override a member declared in an extension (on Linux there is no
# @objc dynamic dispatch), so the many TSOutgoingMessage subclasses that do
# `override var contentHint { ... }` etc. fail with "declared in extension of
# 'TSOutgoingMessage' and cannot be overridden" (~2,532 errors). The Quill port
# (Sources/SignalServiceKitObjCPort/QuillTSOutgoingMessage.swift) re-declares
# these members `open` in the CLASS body so the overrides resolve; this step
# STRIPS the now-duplicate base declarations from the upstream extensions.
#
# Idempotent + disposable-tree-only: it mutates the gitignored .upstream checkout
# in place (the SCRIPT is the durable committed artifact). Run after lowering +
# inject + strip-tests, before link-ports.
#
# Usage: scripts/quill-signal-relocate-extension-members.sh [SSK_ROOT]
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

# (relative-path, [regex,...]) -- each regex removes one base member declaration
# that the port now owns in its class body. Multi-line bodies are matched
# non-greedily up to their 4-space-indented close brace.
TARGETS = {
    "Messages/Interactions/TSOutgoingMessage.swift": [
        r'(?m)^    public func updateWithSendSuccess\(tx: DBWriteTransaction\) \{ \}\n',
        r'(?m)^    public var isStorySend: Bool \{ isGroupStoryReply \}\n',
        r'(?ms)^    var relatedUniqueIds: Set<String> \{\n.*?\n    \}\n',
        r'(?ms)^    var contentHint: SealedSenderContentHint \{\n.*?\n    \}\n',
        r'(?ms)^    func envelopeGroupIdWithTransaction\(_ transaction: DBReadTransaction\) -> Data\? \{\n.*?\n    \}\n',
        r'(?m)^    var shouldRecordSendLog: Bool \{ true \}\n',
        r'(?m)^    var encryptionStyle: EncryptionStyle \{ \.whisper \}\n',
    ],
}

total = 0
for rel, patterns in TARGETS.items():
    path = os.path.join(root, rel)
    if not os.path.exists(path):
        print(f"  warn: not found: {rel}")
        continue
    src = open(path, encoding="utf-8").read()
    removed_here = 0
    for pat in patterns:
        new, n = re.subn(pat, "", src, count=1)
        if n:
            src = new
            removed_here += 1
        # n==0 is fine on a re-run (already relocated) -- idempotent.
    open(path, "w", encoding="utf-8").write(src)
    total += removed_here
    print(f"  {rel}: removed {removed_here}/{len(patterns)} base member decls")

print(f"quill-signal-relocate-extension-members: removed {total} extension member decl(s)")
PY
