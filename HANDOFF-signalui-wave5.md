# HANDOFF — SignalUI wave-5 error reduction (2026-06-13)

**Goal:** compile Signal-iOS (macOS source) on Linux via the quillui-signal
shim layer, targeting zero errors. Current count: **18,806** upstream errors
(down from 199K before waves 1–5).

## Context

- **Branch:** `signal/signalui-zero` in `/Users/jperla/claude/quillui-signal`
- **Docker build:** `docker run --rm -v /Users/jperla/claude/quillui-signal:/qui -v quillui-signal-build:/qui/.build quillui-signal-build bash -c 'cd /qui && QUILLUI_LINUX_BACKEND=gtk swift build --disable-index-store --target SignalUI 2>&1 | grep -c "^.*error:"'`
- **Error trajectory:** 199K→144K→110K→97.9K→62.4K→20.3K→**18,806**
- **Key methodology:** "one name, one owner" — twin declarations across co-visible modules → ambiguous lookup → cascade errors. Find the root twin, delete the disfavored copy, keep the canonical.
- **`-default-isolation MainActor`** is already in Package.swift SignalUI target (drops ~12K actor-isolation errors)
- **#Preview strip script** is in `scripts/quill-signal-strip-previews.sh` (ran once, 160 blocks from 66 files already stripped from the upstream tree)

## Worktrees with UNCOMMITTED work (commit these first)

These worktrees are at `/tmp/claude/sig5wt-N`. Each has local changes that
need to be committed to `agent/sig5-N`, then merged to `signal/signalui-zero`.

### sig5wt-2 (UIColor twin + UITraitCollection)

**Files changed:**
- `Sources/QuillAppKit/QuillAppKit.swift` — deleted the `convenience init(white:alpha:)` extension on NSColor (was twin with QuillFoundation)
- `Sources/QuillFoundation/QuillFoundation.swift` — moved `init(white:alpha:)` to the class body of RSColor; added `systemGroupedBackground` and `tertiarySystemGroupedBackground` statics
- `Sources/QuillUIKit/QuillUIKit.swift` — added `UIUserInterfaceLevel` and `UIAccessibilityContrast` enums; added `userInterfaceLevel` and `accessibilityContrast` to UITraitCollection
- `Sources/SignalServiceKitObjCPort/QuillSignalShims.swift` — deleted SSK's extension copies of `init(red:green:blue:alpha:)` and `init(white:alpha:)` (they delegated to `self.init()` losing color data; RSColor class now owns both)

**Commit command:**
```bash
cd /tmp/claude/sig5wt-2
git add Sources/QuillAppKit/QuillAppKit.swift Sources/QuillFoundation/QuillFoundation.swift Sources/QuillUIKit/QuillUIKit.swift Sources/SignalServiceKitObjCPort/QuillSignalShims.swift
git commit -m "sig5-2: UIColor one-owner (RSColor class body), UITraitCollection level/contrast"
git push origin HEAD:agent/sig5-2
```

**Then merge to signal/signalui-zero:**
```bash
cd /Users/jperla/claude/quillui-signal
git checkout signal/signalui-zero
git merge agent/sig5-2
git push origin signal/signalui-zero
```

### sig5wt-3 (no changes)

`sig5wt-3` shows as having no changes beyond the base (`git status` clean, no diff). The agent for sig5-3 may have not completed its work. Skip it — nothing to commit.

### sig5wt-4 (MetalKit — MTKView/SpoilerParticleView)

**Files changed:**
- `Sources/AppleFrameworkShims/Metal/Metal.swift` — added `threadExecutionWidth` and `maxTotalThreadsPerThreadgroup` to `MTLComputePipelineState` protocol + `QuillMTLComputePipelineState`; added `MTLGPUFamily` enum (20 cases); added `supportsFamily(_:)` to `MTLDevice` protocol + `QuillMTLDevice` (always returns false = conservative path)
- `Sources/AppleFrameworkShims/MetalKit/MTKView.swift` — **new file** (check if exists, if not it was created by the agent)

**Check:**
```bash
ls /tmp/claude/sig5wt-4/Sources/AppleFrameworkShims/MetalKit/
git -C /tmp/claude/sig5wt-4 diff HEAD Sources/AppleFrameworkShims/MetalKit/
```

**Commit:**
```bash
cd /tmp/claude/sig5wt-4
git add Sources/AppleFrameworkShims/Metal/Metal.swift
git add Sources/AppleFrameworkShims/MetalKit/ 2>/dev/null || true
git commit -m "sig5-4: MetalKit shim — MTLGPUFamily, supportsFamily, MTKView for SpoilerParticleView"
git push origin HEAD:agent/sig5-4
```

### sig5wt-6 (protocol-access / dispatch witness repair)

**Files changed:**
- `Sources/QuillFoundation/QuillActionDispatching.swift` — gutted the `QuillActionDispatching` protocol to be a pure refinement of `QuillSelectorDispatching` (no restated requirement, no shadowing extension)
- `Sources/QuillFoundation/QuillFoundation.swift` — moved the `quillPerform` requirement to `QuillSelectorDispatching` with proper doc comment
- `Sources/QuillSourceLowering/AppKitLowering.swift` — added `repairDispatchWitnessAccess` pass: upgrades stale `func quillPerform` (no access modifier) to `public func quillPerform` in already-lowered trees; `ExtensionOverrideMerger` class also added (moves `override` members from extensions to class bodies)
- `Tests/QuillSourceLoweringTests/AppKitLoweringTests.swift` — 3 new tests for the repair pass

**This is important:** The 1,274 "must be declared public because it matches a requirement in public protocol" errors all stem from stale lowered dispatch witnesses. The `repairDispatchWitnessAccess` tool pass fixes them on re-run. **After committing sig5wt-6, re-run the lowering script on the upstream tree:**
```bash
cd /Users/jperla/claude/quillui-signal
docker run --rm -v $(pwd):/qui -v quillui-signal-build:/qui/.build quillui-signal-build bash -c 'cd /qui && swift run --package-path Sources/QuillSourceLowering AppKitLowering Sources/.upstream/ 2>&1 | tail -20'
```
(Or the actual lowering script: `scripts/quill-signal-lower-ui.sh`)

**Commit:**
```bash
cd /tmp/claude/sig5wt-6
git add Sources/QuillFoundation/QuillActionDispatching.swift Sources/QuillFoundation/QuillFoundation.swift Sources/QuillSourceLowering/AppKitLowering.swift Tests/QuillSourceLoweringTests/AppKitLoweringTests.swift
git commit -m "sig5-6: dispatch-witness access repair — public quillPerform on re-run; override-in-extension merger"
git push origin HEAD:agent/sig5-6
```

### sig5wt-7 (MobileCoin + UIButton tweaks)

**Files changed:**
- `Sources/MobileCoin/Ledger.swift` — added `inputKeyImages` and `outputPublicKeys` (computed vars returning empty Set) to `Transaction`; added `validateAndUnmaskAmount(accountKey:)` to `Receipt`
- `Sources/UIKitShim/UIButtonConfiguration.swift` — added `adjustsImageWhenHighlighted` and `adjustsImageWhenDisabled` stored properties to UIButton via side-table
- `Sources/SignalUIObjCPort/` — **new directory** (check contents)

**Check:**
```bash
ls /tmp/claude/sig5wt-7/Sources/SignalUIObjCPort/
git -C /tmp/claude/sig5wt-7 status
```

**Commit:**
```bash
cd /tmp/claude/sig5wt-7
git add Sources/MobileCoin/Ledger.swift Sources/UIKitShim/UIButtonConfiguration.swift
git add Sources/SignalUIObjCPort/ 2>/dev/null || true
git commit -m "sig5-7: MobileCoin receipt/transaction surface; UIButton image-dimming props; SignalUIObjCPort stubs"
git push origin HEAD:agent/sig5-7
```

## Open PR #537 (generated-Enchanted compat)

- **Branch:** `fix/generated-enchanted-compat` in `/tmp/claude/qmain`
- **Latest push:** f5b70739 (CFURL alias fix)
- **Status:** CI running. Three checks still pending.
- **Composer-send agent:** `a455fe49dd71af845` was working in `/tmp/claude/qfix-send` on branch `fix/gtk-composer-send`. Check if that worktree has commits:
  ```bash
  git -C /tmp/claude/qfix-send log --oneline -5
  git -C /tmp/claude/qfix-send status
  ```
- **After CI green:** `cd /tmp/claude/qmain && gh pr merge 537 --merge`
- **PR #538** (signal/signalui-zero) can merge after #537 lands on main.

## Wave-5 error count estimate

After committing and merging all 4 worktrees, run a new docker build to get r16.
The biggest buckets remaining (before these fixes):
- UIColor `init(white:alpha:)` ambiguity cascade: sig5wt-2 fixes it (~hundreds)
- "must be declared public" dispatch witnesses: sig5wt-6 + lowering re-run fixes all ~1,274
- SpoilerParticleView MTKView / MetalKit bounds: sig5wt-4 addresses root (~hundreds)
- MobileCoin / UIButton surface: sig5wt-7 addresses smaller tail

Expected r16 count: **~10,000–14,000** (rough estimate)

## Wave-6 planning (after r16)

Cluster the r16 error output by file prefix to find the next big buckets:
```bash
docker run --rm ... swift build --target SignalUI 2>&1 | grep "error:" | sed 's|/qui/Sources/||' | cut -d: -f1 | sort | uniq -c | sort -rn | head -30
```

Likely remaining clusters (based on pre-wave-5 analysis):
- `CIFilter/ows_` cascade — IceCubes uses CIFilter for image processing; shim surface incomplete
- `UITextView` / `NSTextContainer` missing members
- `UIDragInteraction` / `UIDropInteraction` protocol gaps
- `Combine` publisher chains (Signal uses heavily)
- More `UICollectionView` data source / delegate gaps

## Key files to know

| File | Purpose |
|------|---------|
| `Sources/QuillUIKit/QuillUIKit.swift` | Core UIKit class hierarchy — UIView, UIViewController, UIControl, UINavigationController, etc. |
| `Sources/UIKitShim/UIKit.swift` | UIEdgeInsets-typed members, NSText*, UIFontPicker, UITextView |
| `Sources/QuillFoundation/QuillFoundation.swift` | RSColor, Selector, NotificationCenter, URL shims |
| `Sources/SignalServiceKitObjCPort/QuillSignalShims.swift` | SSK-specific surface patches |
| `Sources/AppleFrameworkShims/Metal/Metal.swift` | Metal protocol stubs |
| `Sources/QuillSourceLowering/AppKitLowering.swift` | Source lowering tool (strips @objc, generates dispatch conformances) |
| `scripts/quill-signal-lower-ui.sh` | Runs the lowering tool on Sources/.upstream/ |
| `scripts/quill-signal-strip-previews.sh` | Strips #Preview blocks (already ran; idempotent) |

## Build commands

```bash
# Full error count (r16):
docker run --rm \
  -v /Users/jperla/claude/quillui-signal:/qui \
  -v quillui-signal-build:/qui/.build \
  quillui-signal-build bash -c \
  'cd /qui && QUILLUI_LINUX_BACKEND=gtk swift build --disable-index-store --target SignalUI 2>&1 | grep -c "^.*error:"'

# Error sample by module:
docker run --rm \
  -v /Users/jperla/claude/quillui-signal:/qui \
  -v quillui-signal-build:/qui/.build \
  quillui-signal-build bash -c \
  'cd /qui && QUILLUI_LINUX_BACKEND=gtk swift build --disable-index-store --target SignalUI 2>&1 | grep "error:" | sed "s|/qui/Sources/||" | cut -d: -f1 | sort | uniq -c | sort -rn | head -30'
```

## Always-be-merging rule

As each sig5wt-N gets committed and its branch pushed, immediately merge to
`signal/signalui-zero` and push. Do not accumulate. Run the full docker build
(r16) after all 4 are merged to get the new baseline, then scope wave-6.
