#!/usr/bin/env bash
# Make the lowered `quillPerform(_:with:)` overrides in SignalUI/SignalServiceKit
# `open` so the SignalApp target (a separate module) can override them. The
# @objc/#selector lowering emits `public override func quillPerform`; cross-module
# subclasses (the app's view controllers subclassing OWSViewController /
# OWSTableViewController2 / etc.) can only override it if it's `open`.
#
# `final` classes can't have `open` members, so those few are reverted to public
# (the app never subclasses them across the module boundary). The list grows as
# the SignalUI build surfaces more "members of 'final' classes ... use 'public'".
#
# Run after the SignalUI/SSK lowering, before building. Idempotent.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for d in SignalUI SignalServiceKit; do
    DIR="$ROOT/.upstream/signal-ios/$d"
    [ -d "$DIR" ] || continue
    find "$DIR" -name "*.swift" -print0 | xargs -0 sed -i \
        -e "s/public override func quillPerform/open override func quillPerform/g" \
        -e "s/public func quillPerform/open func quillPerform/g"
    find "$DIR" -name "*.swift" -print0 | xargs -0 sed -i -E \
        "s/^([[:space:]]*)override func quillPerform/\1open override func quillPerform/g"
done

# Revert `open` -> `public` on quillPerform in known `final` classes.
for f in \
    "SignalUI/AttachmentApproval/AttachmentApprovalViewController.swift" \
    "SignalUI/SafetyNumbers/FingerprintViewController.swift" \
; do
    p="$ROOT/.upstream/signal-ios/$f"
    [ -f "$p" ] && sed -i "s/open override func quillPerform/public override func quillPerform/g" "$p"
done

echo "quill-signal-open-quillperform: opened quillPerform across SignalUI/SSK"
