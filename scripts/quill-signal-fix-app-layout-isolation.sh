#!/usr/bin/env bash
# Normalize a few layout diagnostics that become over-isolated under the Linux
# app build's default MainActor isolation. These are diagnostic/copy surfaces,
# not rendering behavior.
set -euo pipefail
APP="${1:?usage: quill-signal-fix-app-layout-isolation.sh <Signal-app-dir>}"

python3 - "$APP" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1]) / "ConversationView/ConversationViewLayout.swift"
if not path.exists():
    print("layout isolation lowering: no ConversationViewLayout.swift; skipping")
else:
    text = path.read_text(errors="replace")
    original = text
    text = text.replace(
        "nonisolated override var debugDescription: String {\n"
        "        ensureCurrentLayoutInfo().debugDescription\n"
        "    }",
        "nonisolated override var debugDescription: String {\n"
        "        \"<ConversationViewLayout>\"\n"
        "    }",
    )
    text = text.replace(
        "class CVCollectionViewLayoutAttributes: UICollectionViewLayoutAttributes {\n"
        "    var isStickyHeader: Bool = false",
        "class CVCollectionViewLayoutAttributes: UICollectionViewLayoutAttributes {\n"
        "    nonisolated(unsafe) var isStickyHeader: Bool = false",
    )
    text = text.replace(
        "    func copy(with zone: NSZone? = nil) -> Any {",
        "    override func copy(with zone: NSZone? = nil) -> Any {",
    )

    if text != original:
        path.write_text(text)
        print("layout isolation lowering: patched ConversationViewLayout.swift")
    else:
        print("layout isolation lowering: no ConversationViewLayout changes")

for rel, replacements in {
    "src/views/TransferProgressView.swift": [
        ("    func observeValue(\n", "    override func observeValue(\n"),
    ],
    "ConversationView/Reactions/EmojiReactorsTableView.swift": [
        ("    init() {\n", "    override init() {\n"),
    ],
}.items():
    path = pathlib.Path(sys.argv[1]) / rel
    if not path.exists():
        continue
    text = path.read_text(errors="replace")
    original = text
    for old, new in replacements:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text)
        print(f"layout isolation lowering: patched {rel}")
PY
