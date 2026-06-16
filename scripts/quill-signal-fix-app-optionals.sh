#!/usr/bin/env bash
# Lower Objective-C optional protocol surface left in the Signal app slice.
# The app target builds with Objective-C interop disabled on Linux, so optional
# protocol requirements become ordinary Swift requirements with defaults and the
# matching optional-call syntax is made direct.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/.upstream/signal-ios/Signal}"
FILE="$APP/ConversationView/Components/CVComponent.swift"

if [ ! -f "$FILE" ]; then
    echo "quill-signal-fix-app-optionals: no CVComponent.swift at $FILE; skipping"
    exit 0
fi

python3 - "$FILE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("protocol CVComponentView {\n", "protocol CVComponentView: AnyObject {\n")
text = text.replace("    optional func canHandleDoubleTapGesture(_ sender: UIGestureRecognizer) -> Bool",
                    "    func canHandleDoubleTapGesture(_ sender: UIGestureRecognizer) -> Bool")
text = text.replace("    optional func contextMenuContentView() -> UIView?",
                    "    func contextMenuContentView() -> UIView?")
text = text.replace("    optional func contextMenuAuxiliaryContentView() -> UIView?",
                    "    func contextMenuAuxiliaryContentView() -> UIView?")
text = text.replace("    optional func contextMenuPresentationWillBegin()",
                    "    func contextMenuPresentationWillBegin()")
text = text.replace("    optional func contextMenuPresentationDidEnd()",
                    "    func contextMenuPresentationDidEnd()")

defaults = """

extension CVComponentView {
    public func canHandleDoubleTapGesture(_ sender: UIGestureRecognizer) -> Bool {
        _ = sender
        return false
    }

    public func contextMenuContentView() -> UIView? { nil }
    public func contextMenuAuxiliaryContentView() -> UIView? { nil }
    public func contextMenuPresentationWillBegin() {}
    public func contextMenuPresentationDidEnd() {}
}
"""
if "extension CVComponentView {\n    public func canHandleDoubleTapGesture" not in text and "extension CVComponentView {\n    func canHandleDoubleTapGesture" not in text:
    marker = "public struct CVComponentAndView {" if "public struct CVComponentAndView {" in text else "struct CVComponentAndView {"
    text = text.replace(marker, defaults + "\n" + marker)

path.write_text(text)
PY

python3 - "$APP" <<'PY'
import sys
from pathlib import Path

app = Path(sys.argv[1])
for rel in [
    "ConversationView/ConversationViewController+MessageActions.swift",
    "ConversationView/CVCell.swift",
    "ConversationView/ConversationSearch.swift",
    "util/TextHelper.swift",
    "src/views/TypingIndicatorView.swift",
    "src/ViewControllers/PinnedMessages/PinnedMessagesDetailsViewController.swift",
]:
    path = app / rel
    if not path.exists():
        continue
    text = path.read_text()
    for old, new in [
        (".canHandleDoubleTapGesture?(", ".canHandleDoubleTapGesture("),
        (".contextMenuContentView?(", ".contextMenuContentView("),
        (".contextMenuAuxiliaryContentView?(", ".contextMenuAuxiliaryContentView("),
        (".contextMenuPresentationWillBegin?(", ".contextMenuPresentationWillBegin("),
        (".contextMenuPresentationDidEnd?(", ".contextMenuPresentationDidEnd("),
        (".didPresentSearchController?(", ".didPresentSearchController("),
        (".didDismissSearchController?(", ".didDismissSearchController("),
        ("textView.delegate?.textViewDidChange(textView)",
         "(textView.delegate as? UITextViewDelegate)?.textViewDidChange(textView)"),
        ("[CFTimeInterval]()", "Array<CFTimeInterval>()"),
    ]:
        text = text.replace(old, new)
    path.write_text(text)
PY

echo "quill-signal-fix-app-optionals: lowered CVComponentView optional surface"
