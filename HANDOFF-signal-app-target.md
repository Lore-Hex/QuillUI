# Hand-off: compile Signal's app target (real ConversationViewController) on Linux

**Branch:** `signal/app-target` (in this repo, `/Users/jperla/claude/quillui-signal`).
**Last commit:** `1601a378` (pushed to origin).
**Status:** SignalApp target compiles as a module with **~650 unique error locations, down from 1745 (63%)**. SignalUI stays at **0 errors** throughout. Conversation core (`ConversationView/`) is ~336 of the remaining errors.

## Goal
Get Signal-iOS's main **app** target (`.upstream/signal-ios/Signal/`) compiling on Linux so the REAL `ConversationViewController` + `CVComponent` message-cell pipeline can later render through the UIKit→GTK renderer (`signal-ui-render`). The app target was NOT in the SwiftPM build at all before this campaign; only `SignalUI` + `SignalServiceKit` were reachable. This is a multi-session effort comparable to the original SignalUI sig6–sig9 campaign.

---

## Build & measure recipe (Docker; this is the ONLY way to build — host has no Swift/Linux toolchain)

```bash
cd /Users/jperla/claude/quillui-signal
docker run --rm -v /Users/jperla/claude/quillui-signal:/qui -v quillui-signal-build:/qui/.build \
  quillui-signal-build bash -c 'cd /qui && QUILLUI_LINUX_BACKEND=gtk swift build \
  --disable-index-store --target SignalApp 2>&1' > /tmp/signalapp-build.log 2>&1

# UNIQUE error locations (the real metric — raw grep is ~5-10x inflated):
grep -oE "/qui/[^ ]+\.swift:[0-9]+:[0-9]+: error:" /tmp/signalapp-build.log | sort -u | wc -l

# Category histogram:
grep -oE ": error: .*" /tmp/signalapp-build.log | sed -E "s/'[^']*'/'X'/g; s/[0-9]+/N/g" | sort | uniq -c | sort -rn | head -15
```
Always verify SignalUI is still 0 after any change to `Sources/` or `.upstream/signal-ios/SignalUI|SignalServiceKit`:
`... swift build --disable-index-store --target SignalUI ...` → unique errors must be 0.

A second `-v quillui-signal-build:/qui/.build` named volume caches the build; SignalUI/SSK are already built, so SignalApp-only changes rebuild fast (~25s). Changes to `Sources/QuillUIKit`/`UIKitShim`/`Lottie` trigger a full SignalUI rebuild (minutes).

---

## Reproducing the `.upstream` state (it is gitignored / disposable)

The `.upstream/signal-ios/` tree is a disposable copy. Tracked changes live in `Sources/` + `scripts/` + `Package.swift`. The `.upstream` transforms are reproduced by scripts. After a fresh `.upstream` fetch, run **in order**:

1. SignalUI/SSK lowering (the original SignalUI campaign — see `quill-signal-lower-ui.sh` etc.; SignalUI must reach 0 first).
2. `bash scripts/quill-signal-open-quillperform.sh` — makes lowered `quillPerform` overrides in SignalUI/SSK `open` (so the app can override cross-module). **Biggest single lever: collapsed the override family 2912→204 raw.**
3. `bash scripts/quill-signal-prep-app.sh` — preps the app dir: strip tests, prune iOS-only subsystems + non-conversation leaf screens (615→251 files), normalize imports to `public import` (kills ~47k "ambiguous implicit access level"), run the SwiftSyntax @objc/AppKit lowering + inject-foundation.
4. Build SignalApp once → then iterate the build-log-driven passes (below) until stable.

### Build-log-driven passes (run after each SignalApp build, re-run to convergence)
- `bash scripts/quill-signal-fix-app-actor-isolation.sh /tmp/signalapp-build.log` — marks app overrides `nonisolated` where they override a nonisolated base (app is `-default-isolation MainActor`). Collapsed actor-isolation 1080→~156 raw.
- `bash scripts/quill-signal-fix-app-overrides.sh /tmp/signalapp-build.log` — override reconcile. **NOTE: oscillates; prefer the openness approach (`open-quillperform`).** Use only for non-quillPerform override gaps.
- Cascade-stub generator (currently an inline python; SHOULD be made a script `scripts/quill-signal-gen-cascade-stubs.sh`): reads `cannot find type 'X'`, UNIONs with existing stub names in `Sources/SignalAppPort/QuillCascadeStubs.swift` (NEVER drop — dropping regresses), excludes framework prefixes (CN/PH/UI/NS/AV/MP/CG/CA/SF/PK/CL/CM/UN/BG/SK/WK), classifies by suffix (→ class:UIViewController / class:UIView / protocol / struct). Re-run after each prune.

The generator python (paste-ready):
```python
import re
log='/tmp/signalapp-build.log'
existing=set(re.findall(r'^(?:class|struct|protocol|enum) ([A-Za-z_][A-Za-z0-9_]*)', open('Sources/SignalAppPort/QuillCascadeStubs.swift').read(), re.M))
names=set(re.findall(r"cannot find type '([^']+)'", open(log,errors='replace').read()))
FW=('CN','PH','UI','NS','AV','MP','CG','CA','SF','PK','CL','CM','UN','BG','SK','WK')
def is_fw(n): return any(n.startswith(p) and len(n)>2 and n[2].isupper() for p in FW)
allnames=sorted({n for n in (existing|names) if n.isidentifier() and n[0].isupper() and not is_fw(n)})
def kind(n):
    if n.endswith(('ViewController','NavigationController')): return f'class {n}: UIViewController {{ }}'
    if n.endswith(('View','Cell')): return f'class {n}: UIView {{ }}'
    if n.endswith(('Delegate','Provider','DataSource','Protocol','Observer')): return f'protocol {n}: AnyObject {{ }}'
    return f'struct {n} {{ }}'
out=['// AUTO-GENERATED (cumulative).','import Foundation','import UIKit','import SignalServiceKit','import SignalUI','']+[kind(n) for n in allnames]
open('Sources/SignalAppPort/QuillCascadeStubs.swift','w').write('\n'.join(out)+'\n')
```

---

## Key files (tracked)
- `Package.swift` — `SignalApp` target over `.upstream/signal-ios/Signal`, gated on a pruned-tree marker (`ConversationView` exists && `Calls` doesn't). Deps mirror SignalUI's closure.
- `scripts/quill-signal-prep-app.sh` — app-dir prep + prune list (extend the prune lists here when you prune more).
- `scripts/quill-signal-open-quillperform.sh` — quillPerform→open (revert `final` classes to public; the known-final list grows as the build flags them with "members of 'final' classes ... use 'public'").
- `scripts/quill-signal-fix-app-actor-isolation.sh`, `scripts/quill-signal-fix-app-overrides.sh` — build-log-driven passes.
- `Sources/SignalAppPort/QuillAppStubs.swift` — hand-maintained app-type stubs (CallService/SignalCall/DonateViewController/etc.).
- `Sources/SignalAppPort/QuillCascadeStubs.swift` — AUTO-GENERATED cumulative cascade stubs (53 types).
- UIKit/Lottie shim member files authored by parallel agents: `Sources/QuillUIKit/UISegmentedControl.swift`, `UISwipeActions.swift`, `UIDocumentPickerAndTransitions.swift`, `UIKitProgressGestureShims.swift`, `UIKitSheetTabBarShims.swift`, `UICollectionViewDiffableDataSource.swift`, `UIViewLabelMiscExtras.swift`, `UIKitBridgeAdditions.swift`, `QuillUIKitMissingMembers+Pasteboard.swift`; `Sources/UIKitShim/UIContentViewConfiguration.swift`, `UITextFieldExtras.swift`; `Sources/Lottie/LottieAnimationView+Shims.swift`.

---

## Gotchas / lessons (READ before editing shims)
- **Module layering**: `UIView`/`UIControl`/`UIViewController`/`UIButton`/`UIBarButtonItem` are in **QuillUIKit**. `UITextField`/`UIFont`/`NSItemProvider`/`UIEdgeInsets`(typealias) are in **UIKitShim** (depends on QuillUIKit). `UIColor`/`UIImage`/`QuillEdgeInsets`/`RSColor` are in **QuillFoundation**. A shim file that references `UITextField` must live in UIKitShim; inside QuillUIKit use `QuillEdgeInsets` not `UIEdgeInsets`. `UIColor.gray` does NOT exist (use `UIColor(white:alpha:)`); `.label` does.
- Shim files compiled INTO QuillUIKit must NOT `import UIKit` (they ARE UIKit). Add `import QuillFoundation` for UIColor/UIImage.
- **Extensions can't add stored properties** → use the side-table pattern: `@MainActor private var _storage: [ObjectIdentifier: T] = [:]`. For **nonisolated** types (UIPasteboard/UIApplication) use `nonisolated(unsafe) private var`.
- Don't add `UIView.sizeToFit` in an extension — `UIButton` overrides it in its class body and you can't override an extension method.
- **Parallel-agent workflows work great** (used 3×, ~14 agents). Agents CAN read+write the repo. Always integrate the FINAL versions from the workflow's JSON `result` (the transport HTML-escapes the source → `html.unescape` it). Spec module placement + the side-table pattern in the prompt (agents author blind to layering otherwise).
- `quill-signal-fix-app-overrides.sh` oscillates for `quillPerform` — don't use it for that; openness is the fix.

---

## Remaining ~650 — roadmap (priority order)

### 1. (HIGHEST ROI) Un-prune the real DI layer instead of stubbing it
The has-no-member raw counts are INFLATED (same few members ×many usages). The unique work is small. The crux types feed REAL logic, so empty stubs cascade. Un-prune their real definitions (deps are SSK = reachable):
- **`ViewControllerContext`** — used only ~9 ways: `.shared`, `.db`, `.editManager`, `: ViewControllerContext`. It's referenced from SignalUI too (`ModalActivityIndicatorViewController.swift`). Find its real defining file (pruned — grep a pristine `.upstream` fetch BEFORE prep prunes it) and un-prune, OR write a properly-typed stub: `static let shared`, `db` (SSK `SDSDatabaseStorage`/`DB`), `editManager`.
- Same approach for `ConversationInputTextView` (2 refs), `ContactShareViewHelper`.

### 2. Fill the 53 cascade-stub members (PARALLELIZABLE — fan out agents)
Only **53 unique members across 22 stub types** (raw counts inflated). Author properly-typed members by reading each type's usage in the kept conversation code. Workflow pattern: one agent per cluster of stub types, each reads usage + authors a typed stub into a hand-maintained `Sources/SignalAppPort/QuillRichStubs.swift`; then add those type names to the cascade generator's exclude set so it doesn't recreate them as empty structs (collision). Full list:

```json
{
"ChatHistoryContextMenuInteraction": ["cancelPresentationGesture","contextMenuVisible","dismissMenu","itemViewModel","keyboardWasActive","view"],
"ContactShareViewHelper": ["audioCall","delegate","sendMessage","showAddToContactsPrompt","showInviteContact","videoCall"],
"Emoji": ["angry","neutralFace","slightlyFrowningFace","slightlySmilingFace","smiley"],
"SendMediaNavigationController": ["attachmentLimits","pushViewController","showingApprovalWithPickedLibraryMedia","showingCameraFirst","showingNativePicker"],
"ConversationSettingsPresentationMode": ["default","showAllMedia","showMemberRequests","showVerification"],
"GroupDescriptionPreviewView": ["descriptionText","font","groupName"],
"ViewControllerContext": ["db","editManager","shared"],
"BadgeIssueSheetAction": ["dismiss","openDonationView"],
"MediaPresentationContext": ["animationDuration","mediaOverlayViews"],
"MediaViewShape": ["rectangle","variableRoundedCorners"],
"OsExpiry": ["enforcedAfter","minimumIosMajorVersion"],
"SafetyTipsType": ["contact","group"],
"UpgradableDevice": ["canUpgrade","iosMajorVersion"],
"CallService": ["callServiceState"],
"ContextMenuTargetedPreviewAccessory": ["AccessoryAlignment"],
"DeviceProvisioningURL": ["linkType"],
"GroupViewHelper": ["delegate"],
"Location": ["prepareAttachment"],
"LocationPicker": ["delegate"],
"Media": ["gallery"],
"MockConversationView": ["customChatColor"],
"SignalCall": ["mode"]
}
```
**Enum quick-wins** (make these `enum` with the cases, not the generator's default `struct`): `Emoji`, `ConversationSettingsPresentationMode`, `SafetyTipsType`, `MediaViewShape` (`variableRoundedCorners` may need an associated value — check usage).

### 3. deinit isolation (remaining actor errors)
"nonisolated deinitializer 'deinit' has different actor isolation from main actor-isolated overridden declaration" — apply the SignalUI @MainActor-deinit lowering (task #33) to the app, or prune the few files.

### 4. cannot-find-scope identifiers (~2456 raw)
Free funcs / enum cases / globals from pruned files — can't stub like types. Per-case: un-prune the definer or prune the user. Lowest priority / most tedious.

### After SignalApp reaches 0
Rendering the real CVC ALSO needs a DB/`SSKEnvironment` bootstrap (a `ThreadViewModel` + seeded `TSInteraction` messages). `SignalServiceKit` is reachable; a minimal in-memory GRDB + `SetCurrentAppContext` bootstrap is the follow-on effort (separate from compiling). See `Sources/SignalUIRender/SettingsDemo.swift` for the no-DB app-context bootstrap pattern already used to render the real Settings screen.

## Related context
- Memory: `signal-app-target-campaign.md`, `signalui-wave5.md` (SignalUI 0-error recipe), `signalui-gtk-renderer.md` (the renderer that will consume CVC).
- The UIKit→GTK renderer (`signal-ui-render` target) already renders the REAL Settings screen (`OWSTableViewController2`) and a ConversationStyle-driven chat on Linux — see `.qa/signal-settings-on-linux.png`, `.qa/signal-conversation-on-linux.png`.
