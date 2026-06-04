# Enchanted on Linux — Architecture & Lessons Learned

High-level guide for anyone (human or agent) working on running the **real upstream
Enchanted** chat app on Linux via QuillUI (epic #188). Captures how the port works,
the compat-layer mechanics, the framework gotchas that cost real time, the functional
test harness, and the meta-lessons about debugging this stack. Read this before diving in.

> Companion docs: `upstream-enchanted-audit.md` (source audit), `enchanted-reference-capture.md`
> (macOS reference), `checkpoints.md` (historical changelog).

---

## TL;DR — current state

- The **hand-written reimpl is fully retired** (`QuillEnchanted*` app/Qt/Core/UpstreamSlice
  deleted). The product is `quill-chat-linux`: the **genuine** upstream Enchanted source,
  lowered to Linux and rendered via the generic GTK4 backend.
- It **works for card-driven chats**: launch → connects to Ollama → fetch/select model →
  click a prompt card → real `POST /api/chat` → streamed reply rendered → conversation
  persisted to QuillData. Visually mac-close; the empty-state render is CI-gated.
- **Known gap:** *composer-typed* input loses focus after the first keystroke (a SwiftOpenUI
  focus-restore bug — see "Known open issues"). Prompt cards are the working path today.
- **Do NOT modify the genuine source.** All Linux fixes go through lowering rewrite-rules.

---

## Architecture: how `quill-chat-linux` is built

```
genuine Enchanted source (.upstream/enchanted, fetched via scripts/fetch-upstream.sh)
   │  scripts/profiles/enchanted-full-source/lower-profile-source.sh
   ▼
swift-syntax lowering  (copies → source/ → lowered/ ; rewrites @Observable etc.)
   +  perl rewrite-rules (scripts/profiles/enchanted-full-source/rewrite-rules/**.swift.pl)
   ▼
generated SPM package (.build/quill-chat-linux-gtk/package) depending on:
   QuillUI → SwiftOpenUI (GTK4 backend)   ← UI
   QuillData                              ← SwiftData replacement (SQLite)
   QuillEnchantedShared / QuillEnchantedData  ← kept compat: palette/metrics + persistence
   OllamaKit                              ← real URLSession Ollama client (streaming)
   ▼
quill-chat-linux executable (GTK4 app)
```

- Build/run one shot: `scripts/linux-backend-visual-check.sh .qa/out.png quill-chat-linux gtk`
  (builds, launches under Xvfb, screenshots, runs `verify-backend-screenshot.py`).
- After a lowering/rewrite-rule change you MUST force a re-lower:
  `rm -rf .build/quill-chat-linux-gtk/{lowered,source}` then rebuild. (Clearing only those
  two dirs keeps the dep cache; see the caching caveat below.)

---

## The lowering rewrite-rules — the compat layer (use these, not source edits)

Genuine-source-on-Linux gaps are fixed with **perl rewrite-rules**, never by editing the
upstream source. Mechanism (`scripts/apply-profile-rewrites.sh`):

- `rewrite-rules/<relative-path>.swift.pl` is applied (`perl -0pi`) to the matching lowered
  file `<relative-path>.swift` (path mirrors the `Enchanted/` tree). `__all__.pl` applies to
  every file.
- They run on the lowered copy, matching genuine syntax (the lowering preserves most code).
- Delimiters: `s/.../.../g` or `s{...}{...}g`; use `s!...!...!g` when the replacement contains
  `{ }` (e.g. inserting Swift blocks) to avoid brace-matching breakage. `<<'SWIFT' ... SWIFT`
  heredocs (with `se`) replace whole function bodies.

Worked examples already in the tree (study these to learn the pattern):
- `AppStore.swift.pl` — gate reachability polling by env (`*_FORCE_UNREACHABLE`, `*_PROFILE_MODE`).
- `ConversationStore.swift.pl` — include the new user message in the Ollama request (see QuillData
  relationship gotcha below).
- `InputFields_macOS.swift.pl` — composer layout tweaks.

---

## QuillData (SwiftData replacement) — gotchas

QuillData is the Linux SwiftData stand-in (SQLite-backed). Differences that bite:

1. **No in-memory `@Relationship` inverse.** Setting the to-one side (`message.conversation = conv`)
   does NOT auto-populate the to-many inverse (`conv.messages`) before save — unlike SwiftData,
   which reflects it instantly in memory. Code that reads `conv.messages` *before* persisting the
   new child sees stale/empty data. **This is why the first live chat turn went out with
   `messages:[]`.** Fix pattern (in `ConversationStore.swift.pl`): include the freshly-built object
   explicitly, e.g. `(conversation.messages + [userMessage])`.
2. **Frozen stable model names.** Record table names are pinned to their original reflected name
   (e.g. `"QuillEnchantedCore.QuillDataConversationRecord"`) even after the type moves modules, so
   existing DBs keep working. These string literals are **keys, not target dependencies** — keep
   them; don't "fix" them when deleting `QuillEnchantedCore`.
3. Per-type storage: `_quilldata_json_<ModuleQualifiedTypeName>` tables (id TEXT, payload BLOB).
   The reference seed (`seed-enchanted-reference-data.py`) writes to those exact table names.

---

## SwiftOpenUI (GTK4 backend) — runtime gotchas

The vendored framework lives in `third_party/SwiftOpenUI` (its own repo; per its CLAUDE.md, work
on `develop`, don't merge to its `main` without instruction). Behaviors that cost time:

1. **`.task` re-runs on every rebuild** (not once-per-view-identity like SwiftUI). Any `.task`
   that loads data → updates `@Published`/`@Observable` → schedules another rebuild → `.task`
   re-runs → **storm** (measured ~150 `GET /api/tags`/sec from Enchanted's model/conversation
   loaders). Mitigation: run-once guards (file-scope flag) or make the loader idempotent
   (`guard models.isEmpty else { return }`). The proper fix is run-once-per-identity `.task` in
   SwiftOpenUI itself.
2. **Every state change rebuilds the whole subtree** (remove old children → rebuild → re-append),
   recreating widgets. There's a "narrow path" for pure text/color mutations that updates
   in-place, but **structural** changes (e.g. a button appearing via `.showIf(...)`) force a full
   rebuild that destroys + recreates widgets.
3. **`@FocusState`/`.focused()` → `grab_focus` is wired** (`FocusedView` registers
   `onProgrammaticFocusChange`), but focus **does not survive full rebuilds reliably** — see the
   open issue. `grab_focus` on a parented-but-not-yet-**mapped** widget silently no-ops.
4. **No window manager in headless Xvfb = no keyboard routing.** Mouse clicks (positional XTEST)
   work without a WM, but keystrokes don't reach the focused GTK widget. Run **`openbox`** in the
   Xvfb for any typing test (`Ctrl+Return` send shortcut also needs it).

---

## Functional test harness (Docker)

There is no production hardware in CI; functional behavior is exercised locally in Docker.

- **Container `qui-func`** (`swift:6.2-noble`, worktree mounted at `/work`). Needs apt:
  `libsqlite3-dev libgdk-pixbuf-2.0-dev libgtk-4-dev xvfb xdotool imagemagick openbox`.
- **Mock Ollama** (`/work/.qa/mock_ollama.py`): serves `/api/version`, `/api/tags`, and a streamed
  NDJSON `/api/chat`. `OllamaKit` buffers the full body then splits NDJSON, so the mock can emit
  all lines at once.
- **Run scripts** (`/work/.qa/func_run*.sh`): start mock + Xvfb (+ openbox for typing) → launch the
  binary with `GTK_A11Y=none DISPLAY=… QUILLUI_BACKEND=gtk HOME=<tmp> QUILLDATA_HOME=<tmp>` and **no**
  `*_FORCE_UNREACHABLE` → drive via `xdotool` → screenshot → grep `mock.log` for `POST /api/chat`
  (the functional proof) → query the QuillData sqlite for persisted rows.
- The CI **Strict Mac-reference verifier** (`enchanted-parity.yml`) renders `quill-chat-linux` empty
  state (with `FORCE_UNREACHABLE` for determinism) and checks structural landmarks — it does NOT
  exercise live chat. Real functional verification is the Docker harness above.

---

## Debugging meta-lessons (these cost the most time)

1. **stdout is block-buffered when redirected.** `print()` debug logs are LOST if the app is
   `kill`ed before flush — you'll see "0 hits" and wrongly conclude a code path didn't run. Use
   **`FileHandle.standardError.write(...)`** (unbuffered), or `setvbuf`, or let the app exit cleanly.
2. **Build caching hides edits.** `rm -rf .build/.../{lowered,source}` does NOT clear SwiftOpenUI's
   compiled cache; a suspiciously fast build (~30s) means a dep wasn't recompiled. **Verify your
   change reached the binary**: `strings <binary> | grep <marker>` before trusting a result.
3. **Confirm the source path actually used.** A vendored dep (third_party) vs a fetched checkout
   changes whether your edit is compiled — check the generated package's dependency declaration.
4. **Verify-before-fix on vendored deps.** Don't blind-edit `third_party/SwiftOpenUI`; instrument
   (unbuffered) to pin the exact failure first.

---

## The reimpl-retirement playbook (for similar deletions)

- **Pinned-string contract tests** (`SourceHygieneTests`, `LinuxBackendAppMatrixTests`,
  `QuillDataSourceLoweringTests`, `QuillQtBackendManifestTests`) read `Package.swift`/scripts/sources
  as strings and `#expect(.contains(...))` exact substrings. Deleting a target/product cascades into
  many of them.
- **Grep ALL of `Tests/` (and the whole repo) before deleting** — and beware assertions composed
  **only of kept identifiers** (e.g. a deleted target's `dependencies: [...]` line where every name
  survives): a deleted-name grep misses them. (Two such lines slipped through and failed CI.)
- **Pattern:** structural delete → `swift package dump-package` (parses the macOS manifest view) →
  push → let the macOS "Build all 4 apps + test" job enumerate the authoritative pinned failures →
  fix → green. CI enumeration beats blind editing.
- When deleting a target, check whether it held **load-bearing tests for kept code** and salvage
  them into a new Core-free test target (don't silently drop coverage).

---

## Workflow conventions (this repo)

- **Keep `main` green.** One small increment per branch, branched off `origin/main`; merge promptly;
  don't hold PRs open across many ~50-min Linux-CI cycles (causes the behind-main treadmill).
- Three required checks per PR: "Build all 4 apps + test" (macOS, fast), "Strict Mac-reference
  verifier" (~4 min), "Swift Linux Backends" (~48 min, the gate).
- `gh pr merge --squash --admin` is authorized **only** for fully-green-but-behind cutover PRs
  (bypasses up-to-date only; all checks must PASS).
- Robust CI poll (more reliable than `gh run watch`): loop `gh pr checks <n>`; `rc==8` = pending.

---

## Known open issues

- **Composer-typed input loses focus (typed chats blocked).** SwiftOpenUI restores focus across
  rebuilds by **DFS index**; the Enchanted composer is editable **idx≈21** in a dense-editable tree,
  so after a structural rebuild the index lands on the wrong/non-focusable widget and `grab_focus`
  doesn't take (`isFocus=false`, even when deferred to `g_idle_add` after map). **Proper fix:
  identity-based focus restore** (re-grab the same descriptor-identity widget — the rebuild already
  computes `gtkIdentifyDescriptorTree`) in `third_party/SwiftOpenUI`. Card-driven chat is unaffected.
- **`.task` re-fetch storm** mitigated by run-once/idempotent guards (rewrite-rules); the clean fix
  is run-once-per-identity `.task` semantics in SwiftOpenUI.
- Settings/Completions sheets (`isPresented`) on the full app — unverified.
- Nothing has run on real target hardware yet (only CI/Docker Xvfb).
