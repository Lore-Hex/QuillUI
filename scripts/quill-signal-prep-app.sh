#!/usr/bin/env bash
#
# Reproducible build-prep: lower Signal-iOS's main *app* target (`Signal/`) so a
# Linux-only slice of it compiles against QuillUI's UIKit + the reachable
# SignalUI / SignalServiceKit modules. This is the first step of bringing the
# real `ConversationViewController` + `CVComponent` message-cell pipeline to
# Linux (the app target is not otherwise in the SwiftPM build at all).
#
# Strategy: the 847-file app module is one all-or-nothing compilation unit, but
# whole subsystems exist only to drive iOS frameworks that have no Linux shim
# (calling -> WebRTC/CallKit, device transfer -> MultipeerConnectivity, donations
# -> PassKit, etc.). We PRUNE those (out of scope for rendering a conversation),
# then lower the remainder exactly like SignalUI (strip previews, inject
# Foundation, run the SwiftSyntax AppKit/@objc lowering, lower objc-interop).
#
# Edits IN PLACE in the disposable `.upstream` copy. Re-run after a fresh
# upstream fetch (and whenever this script or the lowering tool changes), the
# same way the SignalUI re-lower recipe is re-applied.
#
# Usage: scripts/quill-signal-prep-app.sh [SCRATCH_PATH]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${1:-$ROOT/.build}"
APP="$ROOT/.upstream/signal-ios/Signal"

if [ ! -d "$APP" ]; then
    echo "quill-signal-prep-app: no Signal app dir at $APP; skipping"
    exit 0
fi

# (0) Drop test files (XCTest / Testing) — not part of the app module.
"$ROOT/scripts/quill-signal-strip-tests.sh" "$APP"

# (1) Prune subsystems that exist only to drive un-shimmed iOS frameworks.
#     These are out of scope for the conversation-rendering slice.
for sub in Calls DeviceTransfer Backups QuickRestore Provisioning test; do
    rm -rf "$APP/$sub"
done

# (1b) Shrink to the CONVERSATION-RENDERING slice: prune non-conversation
#      subsystems + leaf screens (registration, notifications, emoji picker,
#      photo capture / media gallery, polls, stories, app launch, the chat-list
#      home UI, etc.). These are referenced only narrowly by the conversation
#      path, so their types are stubbed in QuillAppStubs instead. Keeping them
#      would mean compiling the whole app; we only need ConversationViewController
#      + the CVComponent message pipeline to render.
for sub in \
    AppLaunch Registration Notifications Emoji Megaphones Profiles Spam Sharing \
    OrphanData Accessibility Debugging Storage Expiration Avatars/Editing \
    src/ViewControllers/Photos src/ViewControllers/MediaGallery \
    src/ViewControllers/Polls src/ViewControllers/Stories \
    src/ViewControllers/HomeView src/ViewControllers/ThreadSettings \
    src/ViewControllers/Registration src/ViewControllers/DonationViewControllers \
    src/ViewControllers/AppSettings src/ViewControllers/NewGroupView \
    "src/ViewControllers/Attachment Keyboard" src/ViewControllers/GroupViewControllers \
    src/ViewControllers/ConversationSettings \
; do
    rm -rf "$APP/$sub"
done
for f in \
    "src/views/MarqueeLabel.swift" \
    "src/views/MockConversationView.swift" \
    "src/ViewControllers/SafetyTipsViewController.swift" \
    "src/ViewControllers/MessageDetailViewController.swift" \
    "src/ViewControllers/ContactShareViewHelper.swift" \
    "src/ViewControllers/MessageReactionPicker.swift" \
    "src/ViewControllers/SendMediaNavigationController.swift" \
; do
    rm -f "$APP/$f"
done

# (2) Prune any remaining file importing a framework with no Linux shim, so the
#     module isn't walled on "no such module".
# Match every import form (plain / public / internal / @_exported / attributed).
MISSING_FW='^(public |internal |fileprivate |@_exported |@preconcurrency )*import (WebRTC|MultipeerConnectivity|PassKit|CallKit|PushKit|BackgroundTasks|Intents|IntentsUI|CoreMotion|CoreLocation|LocalAuthentication|CocoaLumberjack|AVFAudio|CryptoKit|zlib)\b'
while IFS= read -r f; do
    [ -n "$f" ] && rm -f "$f"
done < <(grep -rlE "$MISSING_FW" "$APP" --include="*.swift" 2>/dev/null || true)

# (2b) Normalize import access levels. The app target mixes `public import X`
#      (re-exported modules) with plain `import X`; under Swift's
#      AccessLevelOnImport this is "ambiguous implicit access level for import"
#      (tens of thousands of errors). Make every plain/internal import `public`
#      so the access level is consistent module-wide. (@-attributed and submodule
#      imports are left as-is.)
find "$APP" -name "*.swift" -print0 | xargs -0 sed -i -E \
    's/^(public |internal |package |private |fileprivate )?import ([A-Za-z_][A-Za-z0-9_.]*)$/public import \2/'

# (3) UIKit Clang-submodule imports -> base UIKit module (no Linux equivalent).
grep -rlE '^import UIKit\.[A-Za-z]' "$APP" --include="*.swift" 2>/dev/null \
    | while IFS= read -r f; do
        sed -i -E 's/^import UIKit\.[A-Za-z][A-Za-z0-9]*/import UIKit/' "$f"
    done || true

# (4) Strip SwiftUI #Preview / PreviewProvider blocks.
"$ROOT/scripts/quill-signal-strip-previews.sh" "$APP"

# (5) Inject Foundation/CoreFoundation imports where corelibs needs them.
"$ROOT/scripts/quill-signal-inject-foundation.sh" "$APP"

# (6) AppKit / @objc / #selector lowering (the @objc-on-Linux wall-breaker), in
#     place via the same SwiftSyntax tool SignalUI uses.
TOOL="$SCRATCH/debug/quill-lower-appkit"
swift build --scratch-path "$SCRATCH" --disable-index-store \
    --product quill-lower-appkit >/dev/null 2>&1 || true
if [ -x "$TOOL" ]; then
    "$TOOL" "$APP"
else
    echo "quill-signal-prep-app: quill-lower-appkit not built; @objc lowering skipped" >&2
fi

# (7) Swift/corelibs Foundation compatibility cleanup.
"$ROOT/scripts/lower-objc-interop-for-linux.sh" "$APP"

# (8) Prune separable call/donation glue extensions whose only purpose is to wire
#     the pruned subsystems into otherwise-reachable view controllers.
for glue in \
    "ConversationView/ConversationViewController+Calls.swift" \
    "ConversationView/LinkPreviewCallLink.swift" \
; do
    rm -f "$APP/$glue"
done

# (9) Link the same-module app ports (Linux stand-ins for pruned app types) into
#     the disposable tree, the same way SignalUI's port files are linked.
PORT_SRC="$ROOT/Sources/SignalAppPort"
if [ -d "$PORT_SRC" ]; then
    PORT_DIR="$APP/QuillPort"
    mkdir -p "$PORT_DIR"
    for f in "$PORT_SRC"/*.swift; do
        [ -e "$f" ] || continue
        ln -sf "../../../../Sources/SignalAppPort/$(basename "$f")" "$PORT_DIR/$(basename "$f")"
    done
    echo "quill-signal-prep-app: linked app port file(s) into $PORT_DIR"
fi

echo "quill-signal-prep-app: prepared $(find "$APP" -name '*.swift' | wc -l | tr -d ' ') app source file(s)"
