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
# Usage: scripts/quill-signal-prep-app.sh [SCRATCH_PATH] [BUILD_LOG]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${1:-$ROOT/.build}"
BUILD_LOG="${QUILL_SIGNAL_APP_LOG:-${2:-$ROOT/.signalapp-target.log}}"
APP="$ROOT/.upstream/signal-ios/Signal"

if [ ! -d "$APP" ]; then
    echo "quill-signal-prep-app: no Signal app dir at $APP; skipping"
    exit 0
fi

# Remove stale same-module port symlinks from previous runs before running
# source-lowering tools. Otherwise generic lowerers can write through symlinks
# and dirty checked-in Quill port sources.
rm -rf "$APP/QuillPort"

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
    src/ViewControllers/ConversationSettings src/ViewControllers/ContextMenus \
    src/ViewControllers/Payments src/ViewControllers/Donations \
; do
    rm -rf "$APP/$sub"
done
for f in \
    "src/views/MarqueeLabel.swift" \
    "src/views/MockConversationView.swift" \
    "src/views/GroupDescriptionPreviewView.swift" \
    "src/ViewControllers/SafetyTipsViewController.swift" \
    "src/ViewControllers/MessageDetailViewController.swift" \
    "src/ViewControllers/ContactShareViewHelper.swift" \
    "src/ViewControllers/MessageReactionPicker.swift" \
    "src/ViewControllers/SendMediaNavigationController.swift" \
    "src/ViewControllers/GetStartedBannerViewController.swift" \
    "util/VolumeButtons.swift" \
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
python3 - "$APP" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
pattern = re.compile(r"^(?:public |internal |package |private |fileprivate )?import ([A-Za-z_][A-Za-z0-9_.]*)$")
for path in root.rglob("*.swift"):
    lines = path.read_text(errors="replace").splitlines()
    out = [pattern.sub(r"public import \1", line) for line in lines]
    path.write_text("\n".join(out) + ("\n" if lines else ""))
PY

# (3) UIKit Clang-submodule imports -> base UIKit module (no Linux equivalent).
python3 - "$APP" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
pattern = re.compile(r"^(public )?import UIKit\.[A-Za-z][A-Za-z0-9]*$")
for path in root.rglob("*.swift"):
    lines = path.read_text(errors="replace").splitlines()
    out = [pattern.sub("public import UIKit", line) for line in lines]
    if out != lines:
        path.write_text("\n".join(out) + ("\n" if lines else ""))
PY

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
FOUNDATION_TOOL="$SCRATCH/debug/quill-lower-foundation"
swift build --scratch-path "$SCRATCH" --disable-index-store \
    --product quill-lower-foundation >/dev/null 2>&1 || true
if [ -x "$FOUNDATION_TOOL" ]; then
    "$FOUNDATION_TOOL" "$APP"
else
    echo "quill-signal-prep-app: quill-lower-foundation not built; Foundation lowering skipped" >&2
fi

# (8) Prune separable call/donation glue extensions whose only purpose is to wire
#     the pruned subsystems into otherwise-reachable view controllers.
for glue in \
    "ConversationView/ConversationViewController+Calls.swift" \
    "ConversationView/LinkPreviewCallLink.swift" \
; do
    rm -f "$APP/$glue"
done

# (8b) Lower Objective-C optional protocol remnants in the app conversation
#      slice after the generic lowerer has stripped @objc.
"$ROOT/scripts/quill-signal-fix-app-optionals.sh" "$APP"
"$ROOT/scripts/quill-signal-fix-app-mainactor-closures.sh" "$APP"
"$ROOT/scripts/quill-signal-fix-app-layout-isolation.sh" "$APP"
"$ROOT/scripts/quill-signal-fix-app-generated-perform.sh" "$APP"
"$ROOT/scripts/quill-signal-lower-app-declaration-access.sh" "$APP"
"$ROOT/scripts/quill-signal-fix-app-generated-inits.sh"

# Swift 6 requires extension methods satisfying public protocol requirements to
# be public even in the app target after @objc lowering removes Objective-C
# dispatch. Keep this deterministic instead of depending on a previous build log.
python3 - "$APP/Usernames/Links/UsernameLinkScanQRCodeSheet.swift" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
if not path.exists():
    raise SystemExit(0)

text = path.read_text(errors="replace")
text = text.replace(
    "extension BaseMemberViewController: @retroactive MemberViewUsernameQRCodeScannerPresenter {\n"
    "    func presentUsernameQRCodeScannerFromMemberView() {",
    "extension BaseMemberViewController: @retroactive MemberViewUsernameQRCodeScannerPresenter {\n"
    "    public func presentUsernameQRCodeScannerFromMemberView() {",
)
path.write_text(text)
PY

# (8c) Replay safe log-driven source lowerings from the latest SignalApp build
#      log when one is available. Each pass validates that the diagnostic path
#      still points inside .upstream/signal-ios before touching a file, so stale
#      logs become harmless no-ops after the affected source has moved on.
if [ -f "$BUILD_LOG" ]; then
    "$ROOT/scripts/quill-signal-fix-app-public-requirements.sh" "$BUILD_LOG"
    "$ROOT/scripts/quill-signal-fix-app-public-access.sh" "$BUILD_LOG" "$ROOT/.upstream/signal-ios"
    "$ROOT/scripts/quill-signal-fix-app-deinits.sh" "$BUILD_LOG"
    "$ROOT/scripts/quill-signal-fix-app-required-coders.sh" "$BUILD_LOG"
    "$ROOT/scripts/quill-signal-fix-app-actor-isolation.sh" "$BUILD_LOG"
    "$ROOT/scripts/quill-signal-fix-app-overrides.sh" "$BUILD_LOG"
else
    echo "quill-signal-prep-app: no SignalApp build log at $BUILD_LOG; log-driven app fixes skipped"
fi

# (8d) Add tiny same-file Linux factories for CVComponentState. Signal keeps the
#      designated initializer + Builder fileprivate inside CVComponentState.swift;
#      app-port files are same module but not same file, so they cannot construct
#      real render items for smoke previews without this disposable helper.
STATE_FILE="$APP/ConversationView/Components/CVComponentState.swift"
if [ -f "$STATE_FILE" ] && ! grep -q "QuillSignal CVComponentState preview factories" "$STATE_FILE"; then
    cat >> "$STATE_FILE" <<'SWIFT'

#if os(Linux)
// QuillSignal CVComponentState preview factories. Generated into the disposable
// Signal app slice so Linux renderer checks can exercise real CVRootComponents
// without weakening upstream's fileprivate initializer in the source checkout.
extension CVComponentState {
    static func quillPreviewDateHeaderState() -> CVComponentState {
        CVComponentState(
            messageCellType: .dateHeader,
            senderName: nil,
            senderAvatar: nil,
            bodyText: nil,
            bodyMedia: nil,
            genericAttachment: nil,
            paymentAttachment: nil,
            archivedPaymentAttachment: nil,
            audioAttachment: nil,
            viewOnce: nil,
            quotedReply: nil,
            sticker: nil,
            undownloadableAttachment: nil,
            contactShare: nil,
            linkPreview: nil,
            giftBadge: nil,
            systemMessage: nil,
            dateHeader: DateHeader(),
            unreadIndicator: nil,
            reactions: nil,
            typingIndicator: nil,
            threadDetails: nil,
            unknownThreadWarning: nil,
            defaultDisappearingMessageTimer: nil,
            collapseSet: nil,
            bottomButtons: nil,
            bottomLabel: nil,
            skippedDownloads: nil,
            sendFailureBadge: nil,
            messageHasBodyAttachments: false,
            hasRenderableContent: true,
            poll: nil,
        )
    }

    static func quillPreviewUnreadIndicatorState() -> CVComponentState {
        CVComponentState(
            messageCellType: .unreadIndicator,
            senderName: nil,
            senderAvatar: nil,
            bodyText: nil,
            bodyMedia: nil,
            genericAttachment: nil,
            paymentAttachment: nil,
            archivedPaymentAttachment: nil,
            audioAttachment: nil,
            viewOnce: nil,
            quotedReply: nil,
            sticker: nil,
            undownloadableAttachment: nil,
            contactShare: nil,
            linkPreview: nil,
            giftBadge: nil,
            systemMessage: nil,
            dateHeader: nil,
            unreadIndicator: UnreadIndicator(),
            reactions: nil,
            typingIndicator: nil,
            threadDetails: nil,
            unknownThreadWarning: nil,
            defaultDisappearingMessageTimer: nil,
            collapseSet: nil,
            bottomButtons: nil,
            bottomLabel: nil,
            skippedDownloads: nil,
            sendFailureBadge: nil,
            messageHasBodyAttachments: false,
            hasRenderableContent: true,
            poll: nil,
        )
    }
}
#endif
SWIFT
fi

THREAD_ASSOCIATED_DATA_FILE="$ROOT/.upstream/signal-ios/SignalServiceKit/Contacts/ThreadAssociatedData.swift"
if [ -f "$THREAD_ASSOCIATED_DATA_FILE" ] && ! grep -q "QuillSignal ThreadAssociatedData preview factory" "$THREAD_ASSOCIATED_DATA_FILE"; then
    cat >> "$THREAD_ASSOCIATED_DATA_FILE" <<'SWIFT'

#if os(Linux)
// QuillSignal ThreadAssociatedData preview factory. Generated into the
// disposable upstream copy so the SignalApp renderer bridge can build real
// CVItemModels without a database-backed thread-associated-data row.
public extension ThreadAssociatedData {
    static func quillPreview(threadUniqueId: String) -> ThreadAssociatedData {
        ThreadAssociatedData(threadUniqueId: threadUniqueId)
    }
}
#endif
SWIFT
fi

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
