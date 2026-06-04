# QuillSignal — real Signal on QuillOS

> **Status: feature-complete.** A native QuillUI/GTK Signal client over the real
> presage/libsignal Rust engine — 1:1 **and** group conversations, send (optimistic
> echo + timestamp dedup + failure banner), real-time receive + desktop
> notifications, self-spawning/self-healing engine, QR device linking. All
> real-account actions are user-gated; everything else is compile/screenshot/
> contract-test verified. See `QUILLSIGNAL_RUN.md` to build, link, and run.

## ⮕ PIVOT (2026-06-03): Rust core, not the iOS app

**Decision (user):** stop compiling `signalapp/Signal-iOS` on Linux; **pivot to
the Rust core** — the real `presage`/`libsignal` Signal protocol engine behind a
**native QuillUI UI**.

**Why:** Signal-iOS is a deeply Objective-C-coupled iOS app. Compiling its Swift
on Linux needs porting ~35 ObjC base classes *and* a mechanical pass to
strip/conditionalize `@objc`/`#selector`/NSCoding across **~200 of Signal's own
Swift files** (Linux Swift has **no ObjC interop** — 124k "ObjC interop disabled"
errors). 823/1119 SSK Swift files are clean, but they all depend on the
ObjC-coupled 26%. Multi-week source transform → not worth it vs. the Rust core,
which already builds + runs on aarch64 and reached a real device-linking
handshake (emitted `sgnl://linkdevice`).

**New deliverable:** a QuillUI app (native GTK UI) whose backend is the real
`presage`/`libsignal` Rust engine, via a unix-socket bridge daemon.

**Assets (validated, ready to integrate):**
- `quill-signal-bridge` (Rust, presage workspace member) — unix-socket daemon;
  ping/status/link-begin; emitted a real device-link URL. [parked: `/Users/jperla/claude/QuillSignal`, built in `qs-work` volume]
- `BridgeClient.swift` — Swift unix-socket client (decodes `BridgeMessage`). [parked repo]
- QuillUI `QuillSignal` fixture app (`Sources/QuillSignalCore`, `Sources/QuillSignal`) — the UI shell to rewire from fixtures to the real bridge.

**KEPT from the iOS attempt (reusable QuillUI hardening, independent of Signal):**
the Apple-framework shims — `CoreGraphics` CGFloat, `CryptoKit`→swift-crypto,
`CommonCrypto`→OpenSSL, `COSUnfairLock` os_unfair_lock, `Contacts`, +others.
The `SignalServiceKit` target is gated on `signalUpstreamPresent` and stays inert
when `.upstream/signal-ios` isn't fetched.

**Pivot plan:** (1) bring `BridgeClient.swift` into QuillUI as a `QuillSignalKit`
module. (2) rewire `QuillSignalContentView` from `QuillSignalFixtures` to the
bridge (status → link flow → conversations/messages). (3) build on Linux GTK.
(4) run daemon + app; verify the app connects and can request a link URL
(reaches Signal's servers — **no account needed** for the provisioning URL).
(5) real account link/send/receive = **PAUSE & coordinate** (needs the user's
phone). Engine build/run uses the `qs-work` cargo cache; bridge builds as the
4th member of the presage workspace.

**Engine re-verified (pivot step 2, 2026-06-03):** ran the prebuilt bridge daemon
from `qs-work` on aarch64 and round-tripped all three commands — `ping`→pong,
`status`→`{registered:false}` (presage sqlite store opens), and **`link-begin`
emitted a fresh real `sgnl://linkdevice?uuid=…&pub_key=…` URL** from Signal's
production servers. The Rust core (presage/libsignal) + bridge are alive on
QuillOS arch and reach Signal — the pivot foundation is solid. Step 1
(`QuillSignalKit` in QuillUI) also builds.

**App builds + links (pivot step 3, 2026-06-03):** `QuillSignalContentView`
rewired to the bridge (`QuillSignalModel` ObservableObject — status query + a
device-link panel driving `link-begin`). Caught the branch up to `main`
(vendored `third_party/SwiftOpenUI`) and used the **canonical Linux-GTK recipe**:
`scripts/prepare-linux-build-backend.sh --scratch-path .build-linux` (runs the
SwiftOpenUI mega-patcher `patch-swiftopenui-gtk-css.sh`, which adds
`ButtonStyleType.quillPaint*` + `gtk_swift_accessible_*` + dozens of Linux fixes)
then `swift build --scratch-path .build-linux --product quill-signal`. Build
image needs `python3`/`perl` for the patcher. Result: **`quill-signal` links into
a 13 MB aarch64 Linux ELF** at `.build-linux/aarch64-unknown-linux-gnu/debug/
quill-signal` — a native QuillUI/GTK Signal app with the real bridge client, on
QuillOS arch. **Next: run it (app + daemon) end-to-end; then extend the bridge
with conversation commands.** (`swift build --target` only emits the module;
the **`--product`** build links the executable.)

**Runtime smoke PASSED (no account):** `scripts/verify-quill-signal-smoke.sh`
builds the app, starts the presage bridge daemon, and launches `quill-signal`
offscreen under Xvfb. The running app queries the engine once and logs the real
status: `[QuillSignal] bridge status -> unlinked: not registered …` — proving the
live path **app → QuillSignalKit → unix socket → Rust bridge → presage →
libsignal store**. (Fixed: `.onAppear` re-fired `refreshStatus` on every render;
now `startOnce()` + an `isRefreshing` guard query once and never open the presage
store concurrently — which had raced on the sqlite migrations.) **The build/run
foundation is done.**

**Scannable QR + full link flow proven (no account):** the Rust bridge renders
the `sgnl://linkdevice` URL as a Unicode-block QR (`qrcode` crate, `link-qr`
event); the app shows it in a monospace `Text` link panel. An auto-link smoke
(`QUILLUI_SIGNAL_AUTOLINK=1`) drove the whole flow through the running app:
`[QuillSignal] link URL -> sgnl://… / link QR -> 1457 chars` — app → bridge →
presage → Signal → real provisioning URL + scannable QR, displayed natively.
**Genuinely ready: scan the QR in Signal → Settings → Linked Devices to link;
that completion + send/receive is the only user-gated (phone) step. After
linking, extend the bridge with list-conversations/messages/send + wire the UI.**

**UI visually verified (2026-06-03, first actual screenshot):**
`scripts/quill-signal-screenshot.sh` runs the app under a real Xvfb on a known
DISPLAY (not the offscreen-render smoke), drives `QUILLUI_SIGNAL_AUTOLINK=1`, and
captures the X root to a PNG via ImageMagick `import` (added `imagemagick` +
`x11-apps` to the build image). Read back, the link panel renders correctly: bold
**"Link this device to Signal"** title, the instruction line with `→` arrows, the
QR, the `sgnl://linkdevice?…` URL fallback, and a "Linking…" status. A
nearest-neighbour zoom of the QR confirms **all three finder patterns are clean
and square and the module grid is intact** — a valid QR by eye. One artifact: the
Dense1x2 Unicode-block QR is rendered as monospace `Text`, so font leading +
non-pure-black anti-aliasing leave faint grey seams between module-row-pairs.
Almost certainly still scannable (seams thin + dark, patterns intact), but the
**robust fix is to render the QR as a true crisp-square bitmap image** (the bridge
already has the `qrcode` crate — emit a PNG/pixel grid; show it as an image in the
GTK front-end) rather than leading-prone text. That's the next QR backlog item.

**App self-contained — auto-spawns its engine (2026-06-03):** `QuillSignalModel`
now ensures the bridge daemon before its first query: if the unix socket is
absent it spawns the bridge binary (env `QUILL_SIGNAL_BRIDGE_BIN`, else next to
the app, else `/usr/local/bin/quill-signal-bridge`) with a persistent
`QSIGNAL_DB` (`$XDG_DATA_HOME` / `~/.local/share/quill-signal/qs.db`, else
`/tmp`), off the main thread, polling ~5s for the socket. Verified without an
account: launched **only** the app (no manual daemon) under Xvfb — socket absent
→ `spawned bridge daemon pid … / bridge socket up / bridge status -> unlinked`,
socket now present. Idempotent: when a daemon is already listening the app logs
`reusing existing daemon` and never double-spawns (the screenshot smoke, which
starts its own daemon, still renders). One run of the native app now brings up
its own Rust engine — no separate daemon step.

**Crisp bitmap QR (2026-06-03, replaces the monospace-text QR):** the seams
flagged in a11e540 are gone. The bridge now also renders the provisioning URL as
a real PNG — each module an 8×8 solid black block with a 4-module quiet zone,
built from the `qrcode` module grid (`to_colors`) via the `image` crate (only the
`png` feature; decoupled from qrcode's image feature so no cross-crate version
coupling) — written to a temp file and surfaced as `qr_png_path` on the `link-qr`
event. SwiftOpenUI's `Image(filePath:)` (a real GTK `GtkPicture` via
`gtk_swift_picture_new_for_filename`) shows it in the link panel
(`.resizable().frame(260×260)`); the Unicode-block `qr` text stays as a fallback
and for the terminal CLI. Verified by screenshot + a nearest-neighbour zoom:
**solid square modules, all three finder patterns clean, zero grey row-seams** —
a high-quality scannable QR, a clear upgrade over the leading-prone text render.

**Own-message attribution (2026-06-03):** `list-messages` now emits a `from_self`
bool per message — the bridge compares each message's sender `raw_uuid()` to the
account's own ACI (`registration_data().service_ids.aci`). The app decodes it
(`BridgeStoredMessage.fromSelf`) and feeds it to `Message(fromSelf:)` instead of
the previous hardcoded `false`, so the chat bubbles right-align/style sent vs
received correctly. Both sides build clean; additive to the message path, which
stays empty until a real link (runtime-verified once linked).

**Send scaffolding (2026-06-03):** the bridge has a `send` command — a
`Send { thread, body }` request that parses the recipient service id, loads a
mutable registered manager, and calls presage `send_message(recipient,
DataMessage { body, timestamp, .. }, timestamp_millis)`. The app's
`QuillSignalModel.send(to:body:)` optimistically echoes a from-self message, then
fires the bridge `send` (JSON-escaped body) off the main thread; the composer's
send button calls it (replacing the fixture `ChatDraft` path) and clears the
draft. **Safety:** send only fires on an explicit button press — never
automatically — and reaches a real account only once linked. Both sides build
clean; a launch smoke shows the unlinked path unchanged (auto-spawn + status,
app stays up) with **zero** sends invoked. Actual delivery is the user-gated
(phone) step, like link-completion.

**Cancel during linking (2026-06-03):** the link panel now shows a Cancel button
while a link is in flight (previously `beginLink` blocked ~180s with no escape).
`cancelLink()` bumps a thread-safe `LinkSession` generation — so the detached
link thread's late events and its `isLinking` cleanup are ignored (this also
guards the cancel-then-immediately-relink race) — and resets the panel to its
pre-link state at once. Verified by screenshot: the autolink path (isLinking
true) renders `Linking…  Cancel` under the QR. The orphaned thread, blocked
awaiting the phone scan, exits on its socket timeout.

**Connectivity-aware daemon reconnect / self-healing (2026-06-03):**
`ensureDaemon` now connect-*probes* the socket (new `BridgeClient.probe()`)
instead of just checking the file, so a stale socket — daemon crashed but the
file remains — is no longer wrongly reused: the app spawns a fresh daemon (which
`remove_file`s the stale socket on startup). `refreshStatus`/Retry re-ensures the
daemon before querying so the app self-heals from a crashed engine; `beginLink`
ensures it too, and `startOnce` just dispatches (each entry point ensures in its
own background context). Verified headlessly across three cases: **no socket →
spawn; stale socket (kill -9 the daemon, file remains) → detected and respawned;
live daemon → reused, no double-spawn**.

**Protocol decode-contract check (2026-06-03):** `quill-signal-decode-check` (a
standalone `executableTarget` depending only on the Foundation-only
`QuillSignalKit`, so it builds in seconds with **no GTK patcher**) asserts that
every line the Rust bridge emits decodes into `BridgeMessage` — ping, status,
`link-url`, `link-qr` (incl. the `qr_png_path` → `qrPngPath` CodingKey mapping
and the no-png fallback), `linked`, `link-error`, the `send` response, the
bad-request envelope, and forward-compat unknown-key tolerance. 25 checks, exits
0 on pass / 1 on mismatch; run via `scripts/quill-signal-decode-check.sh`. Locks
the bridge↔app wire contract against regressions.

**Wire types consolidated (2026-06-03):** the per-command response envelopes
(`BridgeConversation`/`ConversationsResponse`, `BridgeStoredMessage`/
`MessagesResponse` with the `from_self` key, `WhoamiData`/`WhoamiResponse`) moved
from app-private structs in `QuillSignalCore` to **public** types in
`QuillSignalKit/BridgeProtocol.swift` — a single source of truth shared by the
app and the check. The decode-check now also asserts the conversations envelope
(incl. a null name), the messages envelope with `from_self`
true/false/missing→nil, and whoami registered/unregistered. The GTK app builds
clean against the public types; the check stays green (now ~40 assertions).

**Real-time receive scaffolding (2026-06-03):** the bridge has a `receive`
command — opens presage `receive_messages()` (a `Stream<Received>`) and writes a
`{"event":"message",thread,sender,body,timestamp,from_self}` line per incoming
text `DataMessage` until the client disconnects (`from_self` compares the sender
to the account's own ACI). The app decodes these via a new `IncomingMessage`
(QuillSignalKit) in `QuillSignalModel.startReceiving()` — a detached stream
thread that appends each message to its conversation (creating one if the sender
is unknown), auto-started when linked alongside conversations/whoami and guarded
so only one stream runs. Both sides build clean; the decode-check gained
`IncomingMessage` asserts; a launch smoke shows the unlinked path unchanged with
**zero receive invoked**. Like send, receiving is a real-account action — it only
runs after a real link, never automatically during development.

**Message dedup by timestamp (2026-06-03):** send (optimistic), receive (stream),
and `list-messages` (reload) can all surface the same stored message; a new pure
`MessageDedup.unseen` helper (QuillSignalKit) + a per-thread set of seen Signal
timestamps in `QuillSignalModel` drops the duplicates. `loadMessages` dedups the
loaded batch and seeds the seen set; `appendIncoming` skips an already-seen
timestamp; the optimistic send records its stamp. The helper is **fully
unit-tested** in the decode-check (drops already-seen + intra-batch dups, keeps
nil-timestamp items, preserves order, mutates the seen set). GTK app + check
green; launch smoke unregressed.

**Exact send dedup via client timestamps (2026-06-03):** the bridge `send` now
accepts an optional `timestamp` (used for both the `DataMessage` and the
`send_message` call, else stamped now); the app's `send` generates one millis
timestamp and reuses it for the optimistic echo, the seen set, and the bridge
payload — so the stored/echoed copy carries the same stamp and dedups against the
optimistic message instead of appearing twice. Bridge + GTK app + decode-check
green; launch smoke unregressed.

**Chat UI visually verified (2026-06-03, first conversation-view screenshot):** a
`QUILLUI_SIGNAL_FAKELINKED=1` test hook renders the linked chat shell from
fixtures (no daemon, no account touched) so the conversation UI can be captured
(`scripts/quill-signal-screenshot.sh` gained a `QS_FAKELINKED=1` mode). Read
back, it's a polished messenger: a left sidebar of conversations
(Family/Coworker/Notes To Self) each with a last-message preview, the account
number in the title (`Quill Signal — +1 555 0100`), and a message pane with
correctly attributed bubbles — **own messages right-aligned + blue, others
left-aligned + gray** (the `fromSelf` wiring renders right), each with a sender +
time caption, over a "Message" composer + Send button. No visual bugs. This
unlocks screenshot-verification for the remaining chat-UI work.

**Send-failure banner (2026-06-03):** `QuillSignalModel.transientError` is set
when a `send` gets `ok:false` or no response from the bridge (cleared on
success); the linked view shows a dismissible light-red bar above the chat —
"Message not sent. Check your connection." + a Dismiss button (tap to clear).
Verified by screenshot via a `QUILLUI_SIGNAL_FAKEERROR=1` sub-hook (with
FAKELINKED): the banner renders full-width above the conversation with the chat
intact below; without FAKEERROR there is no banner.

**Desktop notifications on receive (2026-06-03):** a fresh incoming (non-self)
message fires a `notify-send` toast (env `QUILL_SIGNAL_NOTIFY_BIN` override, PATH
lookup, skipped silently if absent) with the contact's display name (else
"Signal") as the title and the message text as the body. The title/body logic is
a pure, **fully unit-tested** `NotificationFormat.make` helper (QuillSignalKit) —
own/empty messages produce no toast; the spawn happens inside `appendIncoming`
after dedup, so duplicates don't double-notify. Format helper green in the
decode-check; the spawn is compile-verified (fires only on real receive); a
launch smoke shows zero notifications when unlinked.

**In-app link now lands on a live chat (2026-06-03 bug fix):** previously
`beginLink`'s `linked` event only flipped `linkState` to `.linked` — so linking
via the in-app QR showed an empty, non-updating chat (no conversations, no
account number, no receive stream) until an app restart. The post-link actions
are now a shared `onBecameLinked()` (load conversations + whoami + start
receiving) called from both `refreshStatus` (startup/Retry) and `beginLink`'s
completion, so the in-app link path populates the chat and goes live
immediately. App + decode-check green; launch smoke unchanged (the path is only
reached on a real link).

**Empty-state for no conversations (2026-06-03):** when linked with an empty
conversation list, the chat pane now reads "No conversations yet. New messages
will appear here." instead of the confusing "Select a conversation" (a
conditional `placeholder`). Verified by screenshot via a
`QUILLUI_SIGNAL_FAKEEMPTY=1` sub-hook (with FAKELINKED): the empty-state renders
centered under the account title with an empty sidebar and no broken layout; the
normal fixtures chat still renders unchanged.

**Receive-stream auto-restart (2026-06-03):** the receive thread now
`ensureDaemon`s before connecting, and when the stream ends while still linked it
auto-restarts after a 5s backoff (re-checking `linkState`) — so a linked,
receiving session recovers on its own from a daemon crash/restart, which the
self-heal reconnect alone didn't cover (nothing re-ran `refreshStatus` in the
linked view). The `guard !isReceiving` prevents overlap; `Task.sleep` is async so
it doesn't block the UI; the restart only runs while `linkState == .linked`, so
an unlinked session never loops. App + decode-check green; a 10s unlinked launch
smoke shows a single status line, zero receive commands, no restart loop.

**Groups — slice 1: enumeration (2026-06-03):** `list-conversations` now also
returns groups from the presage store as `{type:"group", uuid, name}`. The uuid
is a deterministic UUID-format string from the group master key's first 16 bytes
(`group_uuid`) — the key is already random, so this is collision-free without
hashing, keeping the **app fully UUID-based with no model change** (groups appear
in the existing sidebar via the generic `BridgeConversation` decode). The bridge
will map the uuid back to the group by re-enumeration in later slices. Bridge
builds clean; the decode-check covers a group entry; the GTK app is unchanged.
(Slices ahead: GROUPS2 = `list-messages` for a group uuid → `Thread::Group`;
GROUPS3 = send to a group + receive derives the group uuid from
`DataMessage.group_v2`.)

**Groups — slice 2: read (2026-06-03):** `list-messages` now resolves a group —
it matches the thread uuid against each group's derived uuid (re-enumeration) and
uses `Thread::Group(master_key)`, else falls back to a contact `ServiceId` (a
bare group uuid would otherwise mis-parse as a contact ACI, so groups are checked
first). `store().messages` + the `from_self` logic then serve both contacts and
groups. Bridge builds clean; compile-verified (empty until linked).

**Groups — slice 3a: send-to-group (2026-06-03):** extracted a shared
`resolve_thread(store, thread_id)` (group-first by re-enumeration, else a contact
`ServiceId`) used by both `list-messages` and `send`. `send_text` now branches:
`Thread::Group` → `send_message_to_group(&master_key, …)`, `Thread::Contact` →
`send_message(service_id, …)`. Bridge builds clean; compile-verified, never
auto-invoked vs a real account.

**Groups — slice 3b + COMPLETE (2026-06-03):** `receive_stream` now reads
`DataMessage.group_v2` — a group message's emitted `thread` is the group's
derived uuid (`group_uuid` of `group_v2.master_key`), a 1:1 stays keyed by the
sender — so incoming group messages land in the right conversation.
**Groups is complete: enumerate + read + send + receive**, all mapped
bridge-side (group master key ↔ deterministic UUID) so the QuillUI app stayed
**100% UUID-based with zero model change** — groups flow through the same
sidebar, timeline, composer, dedup, and notifications as contacts. Compile-
verified across all slices (groups are empty until a real link).

**Receive-restart escalating backoff (2026-06-03):** the auto-restart's fixed 5s
became an escalating backoff — `5,10,20,40,60s` (capped) — so a persistently-down
engine doesn't tight-loop; it resets to 5s as soon as a message arrives
(`appendIncoming`). App + decode-check green; unlinked smoke shows the path is
never entered when not linked.

**Attachments — awareness slice + plan (2026-06-03):** *Research:* presage
exposes incoming attachments as `DataMessage.attachments: Vec<AttachmentPointer>`
(each with `content_type` / `file_name` / `size`) plus `Manager::get_attachment`
to download bytes; but **QuillChatKit's `ChatMessage` is text-only** (`body:
String`, no image slot), so inline images would require editing the *shared*
bubble protocol + renderer. *Done (clean, bridge-only):* a `display_body` helper
folds an `[attachment: <name>]` marker into the message body when attachments are
present (and surfaces attachment-only messages, previously dropped) — used by
`list-messages` + `receive`, so the user sees that an attachment arrived. *The
remaining major effort (likely user-directed):* full inline images = bridge
`get_attachment` → temp file + a `qr_png_path`-style path field, plus either a
careful QuillChatKit `ChatMessage` image-slot + bubble change (shared) or
rendering attachments outside the bubble.

**Inline image attachments — UI slice (2026-06-04, user-directed):** the shared
`ChatMessage` gained an **optional** `attachmentImagePath` (defaulted nil in a
protocol extension → backward-compatible, `quill-telegram` still builds), and
`ChatBubble` renders the image (natural size, rounded corners) above the caption,
text bubble shown only for non-empty bodies. `QuillSignalCore.Message` carries
the path; a fixture demonstrates it. Screenshot-verified via FAKELINKED: a
gradient image renders cleanly in a received bubble, aspect-correct, existing
text bubbles intact. (GTK note: `.frame(maxWidth:)`/`.scaledToFit()` on an image
aren't honored by the GTK backend → natural size is reliable, so the bridge will
downscale attachments to a sane thumbnail dimension.)

**Inline image attachments — bridge slice (2026-06-04, user-directed):** `list-messages`
now downloads received images and reports a local path. To dodge the borrow
conflict (the store's message iterator is alive while `get_attachment` needs the
manager), it runs **two passes**: pass 1 drains the iterator into rows, cloning
the first eligible image pointer per message (`first_image_attachment` — an
`image/*` content type that also carries a digest, since the digest is required
to fetch + verify); pass 2 — iterator dropped — calls `manager.get_attachment`,
decodes via the `image` crate (png/**jpeg**/gif features), downscales with
`.thumbnail(280, 280)`, and saves a PNG to a digest-keyed temp path
(`thumbnail_cache_path` → `qs-att-<first-8-digest-bytes-hex>.png`) so re-opening a
thread reuses the cached thumbnail with no re-download. Each row emits
`attachment_path` (null when absent / on any download/decode failure — the text
`[attachment: …]` marker still shows). App side: `BridgeStoredMessage` gained an
optional `attachmentPath` (key `attachment_path`) and `loadMessages` maps it into
`Message.attachmentImagePath`. 6 new bridge unit tests (15 total) cover the two
pure helpers; a decode-check asserts `attachment_path` present→set / absent→nil.
Compile-verified end-to-end (bridge build+tests, GTK app, decode-check, FAKELINKED
screenshot); the real CDN download is gated on a linked account. Live receive
still shows the text marker — opening the thread renders the image. Deferred:
receive-stream inline images (the stream holds `&mut manager`), non-image
attachment chips, webp decode.

**Relative timestamps (2026-06-04, user-directed feature 2 of 4):** the shared
`ChatTimestampFormatter` (QuillChatKit) gained `relative(_:now:)`, a chat-style
stamp that sharpens as a message ages — `Just now` (<1m) → `5m` (<1h) →
time-of-day earlier today (`9:18 AM`) → `Yesterday` → an abbreviated weekday
within the past week (`Mon`) → a short date (`Jun 4`). `now` is an injectable
parameter so the branch choice is deterministic/testable. `ChatBubble` now uses
`relative` for its caption (the absolute `formatted` stays for callers that want
it). This is in the SHARED kit, so `quill-telegram` was rebuilt green
(backward-compatible). FAKELINKED fixtures were spread across the ranges (−3d,
−1d, −8m) and the screenshot confirms `Mon` / `Yesterday` / `8m` rendering side
by side, image bubble intact. Deferred: a last-activity time on each
conversation-list row (needs a timestamp on `ChatListItem`) and date separators
between message groups.

**Live receive images (2026-06-04, user-directed feature 3 of 4):** the receive
stream can't download attachments inline (it holds the manager mutably), so the
app backfills. A new Foundation-only helper `AttachmentMarker.isPresent(in:)`
(QuillSignalKit) detects the bridge's `[attachment: …]` marker; `appendIncoming`
calls it on each pushed message and, when true, re-pulls the thread via
`loadMessages(for:)` — `list-messages` then downloads the image (digest cache →
only the new one fetches) and it backfills into the open bubble. `loadMessages`
never re-enters `appendIncoming`, so there's no trigger loop, and its
`seenTimestamps` reset stays consistent with the dedup. The trigger is a pure
function so it's unit-tested in the decode-check (text+marker→true, bare→true,
plain→false, nil→false, all green) alongside a clean `quill-signal` build; the
live CDN download is gated on a linked account. Deferred: a small settle delay if
the store write lags the event, and only refreshing the currently-open thread.

**Bridge unit tests (2026-06-03):** the bridge gained its first `cargo test`
coverage — 9 tests for the pure helpers `group_uuid` (too-short→None;
deterministic 8-4-4-4-12 lowercase hex from the first 16 master-key bytes) and
`display_body` (plain text; empty→None; attachment-only file_name→content_type→
`file` fallback; text+attachment newline-joined; multiple attachments
comma-joined). All passing; run with `cargo test -p quill-signal-bridge`.

**Sender contact names (2026-06-03):** `receive` now resolves the sender's
contact name — the bridge snapshots contacts (uuid→name) before the receive
stream borrows the manager, then emits `sender_name` per message (null for an
unsaved sender). The app (`IncomingMessage.senderName`) names a new conversation
(from an unknown thread) and the notification by the contact name instead of the
raw uuid, falling back to the uuid / "Signal". Bridge + 9 tests + app +
decode-check (incl `sender_name` value/null) green; launch smoke clean.

**Receive-error surfacing (2026-06-03):** the receive stream's `receive-error`
events (store / registration / receive failures) are no longer silently dropped
— the app sets the dismissible banner (`transientError`) with the bridge's detail
(else "Couldn't receive messages. Reconnecting…"), while the escalating-backoff
auto-restart retries underneath. `IncomingMessage` gained a `msg` field; the
decode-check covers a `receive-error` line. App + decode-check green; smoke clean.

## Historical: the abandoned Signal-iOS compile

Compile the **real `signalapp/Signal-iOS` app** on Linux/QuillOS as
**QuillUI targets**, linked against QuillUI's real Apple-framework shim
products (`UIKit`/`SwiftUI`/`AVFoundation`/`Network`/`os`/`CoreGraphics`/
`Security`/`Combine`/…), **real GRDB**, **real SwiftProtobuf**, and **real
libsignal**. (Superseded by the pivot above — kept as the record of why, and of
the reusable framework-shim work.)

Branch `signal/real-backend` (off `main`). Upstream source lives under
`.upstream/` (per-worktree, gitignored — fetch, don't commit).

## Verified facts (2026-06-03)

- **Signal-iOS is NOT a SwiftPM package** — it's CocoaPods + Xcode
  (`Podfile`, `Pods/`, `Signal.xcodeproj`). So we author the SPM targets
  ourselves, pointing at its source dirs (the WireGuard upstream-slice
  pattern, but inverted to `#if os(Linux)` because Signal builds *on* Linux).
- **`SignalServiceKit` = 1412 Swift + 32 `.m` + 38 `.h` (18M).** ~95% Swift;
  the ObjC layer (the `<Foundation/Foundation.h>` blocker) is small + excludable.
- **Import frequency across SignalServiceKit** (drives shim needs):
  `Foundation` 925 · `LibSignalClient` 469 · `GRDB` 230 · `XCTest` 187 ·
  `UIKit` 56 · `Testing` 49 · `CryptoKit` 26 · `SwiftProtobuf` 23 ·
  `SignalRingRTC` 20 · `Contacts` 15 · `AVFoundation` 7 · `SDWebImage` 6 ·
  `Intents`/`CommonCrypto`/`CocoaLumberjack` 5 · `Network`/`LocalAuthentication`/
  `PassKit`/`UniformTypeIdentifiers`/`ObjectiveC` 4 · `os`/`Security`/`zlib`/
  `QuartzCore`/`ImageIO`/`libPhoneNumber_iOS` 2.
- **`LibSignalClient` (469) gates everything** → wire libsignal first.

## Pod → SPM dependency map

| Pod | Plan |
|-----|------|
| `LibSignalClient` v0.94.1 | **real** — `.upstream/libsignal` (cloned), build `libsignal_ffi.a`, wire `SignalFfi` + `LibSignalClient` targets |
| `SwiftProtobuf` 1.36.1 | real SPM pkg — **added** to `quillDataPackageDependencies` |
| `GRDB.swift/SQLCipher` | QuillUI already deps `GRDB.swift` 7.0.0 (plain SQLite first; SQLCipher later) |
| `SignalRingRTC` v2.69.1 | **defer** — exclude `Calls/` for first compile (WebRTC+Rust) |
| `MobileCoin` / `LibMobileCoin` | **defer** — exclude `Payments/` (optional) |
| `libPhoneNumber-iOS` | **defer / shim** — 2 imports |
| `SDWebImage*` / `libwebp` | **defer** — UI image loading |
| `BonMot`/`PureLayout`/`lottie-ios` | app-target UI; later |
| `CocoaLumberjack` | logging shim later |

## libsignal wiring recipe (verified from libsignal v0.94.1 swift/Package.swift)

- `SignalFfi` = `.systemLibrary` at `.upstream/libsignal/swift/Sources/SignalFfi`;
  its `module.modulemap` declares `header "signal_ffi.h"` + `link "signal_ffi"`.
- `LibSignalClient` = `.target` deps `["SignalFfi"]`, Linux links `stdc++`,
  `-L<dir with libsignal_ffi.a>`.
- Build the static lib: `cargo build -p libsignal-ffi --release` (crate at
  `rust/bridge/ffi`) → `.upstream/libsignal/target/release/libsignal_ffi.a`.
  Reuse the `qs-work` Docker cargo cache. Build v0.94.1 fresh (FFI symbol
  version must match the Swift wrapper — do **not** reuse presage's older FFI).
- The Swift wrapper compiles independently of the `.a`; the `.a` is only
  needed when a downstream executable/test links.

## Exclude strategy for SignalServiceKit (first compile)

- All tests: `XCTest` (187) + `Testing` (49) files, `Mocks/`.
- ObjC: 32 `.m` + 38 `.h` (`SignalServiceKit.h`, `*-Prefix.pch`).
- `Calls/` (RingRTC), `Payments/` (MobileCoin).
- Non-source resources SPM would reject: `.proto` (13), `.crt`/`.cer`/`.encrypted`
  certs, `.png`/`.webp`, `.py`, `.md`, `Protos/Makefile` → exclude or `.copy`.

## Milestone ladder

1. ✅ Clone real libsignal v0.94.1 → `.upstream/libsignal`.
2. ✅ Scaffold `SignalFfi` + `LibSignalClient` targets + `SwiftProtobuf` dep +
   `signalUpstreamPresent`/`libsignalUpstreamPresent` gates; manifest parses
   (`swift package dump-package` exit 0, 186 targets).
3. ✅ Build `libsignal_ffi.a` (aarch64, **194MB**, exit 0, rustc 1.96.0-nightly
   pin) + compile real `LibSignalClient` Swift wrapper on Linux: `Build of
   target: 'LibSignalClient' complete!` exit 0, **132 files, zero source edits**
   (`swiftLanguageMode(.v5)`). Real libsignal Rust FFI + Swift API both build on
   aarch64/Linux against QuillUI.
4. 🔄 `SignalServiceKit` target **wired** (1412 Swift, ObjC + tests/Calls/Payments
   + resources excluded — 94 exclude entries) vs QuillUI shims (UIKit/AVFoundation/
   Network/os/Security/CoreGraphics) + LibSignalClient + GRDB + SwiftProtobuf.
   NOTE: generated `.pb.swift` ARE checked in (kept). First baseline = 677 errors
   but **all of it was a build-env artifact**: GRDB's `GRDBSQLite` C module needs
   `sqlite3.h` → fixed by apt `libsqlite3-dev`; 230 GRDB-importing files cascaded.
   **True baseline (sqlite fixed) = 47 errors**, and the build doesn't even reach
   SSK yet — 46 are one root in GRDB: `Core/Support/CoreGraphics/CGFloat.swift`
   `cannot find type 'CGFloat'`. QuillUI's `CoreGraphics` shim makes
   `canImport(CoreGraphics)` true so GRDB compiles its CG support, but the shim
   never re-exported `CGFloat`. **Fix (QuillUI shim):** `@_exported import struct
   Foundation.CGFloat` in `Sources/CoreGraphics/CoreGraphics.swift` (verifying).

## Build environment (Docker, swift:6.2-noble, arm64)

Use the prebuilt **`quillui-signal-build`** image (`docker/quillui-signal-build.Dockerfile`
= swift:6.2-noble + libgtk-4-dev/libgdk-pixbuf-2.0-dev/libcairo2-dev/libsqlite3-dev/
libssl-dev/pkg-config/clang/protobuf-compiler/cmake/git) rather than per-run `apt`
— apt intermittently dropped libsqlite3-dev/libssl-dev, breaking GRDBSQLite /
CommonCrypto. Env: `QUILLUI_LINUX_BACKEND=gtk`.
Build with **`swift build --disable-index-store`** — swift-crypto's BoringSSL C++
(and the apt clang) reject SwiftPM's Apple-only `-index-store-path` flag.
Mounts: worktree → `/qui`, `qui-build` volume → `/qui/.build`. libsignal `.a`
build reuses `qs-work` cargo cache with `CARGO_HOME=/work/cargo`.
5. ⬜ Grind errors (cascade-cause playbook); extend QuillUI shims where Signal
   needs APIs they lack — commit each shim addition + each error-count drop.

## ⚠ Central challenge — Signal's ObjC core-model layer

~35 `.m/.h` files implement Signal's base model + util layer in **Objective-C**:
`TSInteraction`/`TSMessage`/`TSIncomingMessage`/`TSOutgoingMessage`/`TSErrorMessage`/
`TSInfoMessage`/`TSGroupModel`/`TSQuotedMessage`, the storage base
(`BaseModel`/`TSYapDatabaseObject`), and macros (`OWSAsserts`/`OWSLogs`/
`DebuggerUtils`). They `#import <Foundation/Foundation.h>` (the ObjC Foundation
umbrella), which **does not exist on swift-corelibs-foundation** — and Linux
Swift can't mix GNUstep ObjC-Foundation with the Swift Foundation the rest of the
code uses. **Hundreds of Swift files subclass/use these types.**

→ The real milestone-4/5 work is **porting this ObjC layer to Swift** (faithful
reimplementations on Linux), not just filling shim gaps. This is the crux of
"Signal on QuillOS" and the bulk of the remaining effort. The baseline build
(ObjC excluded) quantifies how much Swift depends on them.
6. ⬜ `SignalUI`, then the `Signal` app target.

## Grind log (SignalServiceKit, vs QuillUI shims)

Each fix unblocks a deeper layer, so the count rises when a dependency clears and
the build reaches further. "Top blocker" = dominant error after that fix.

| # | Fix | Top blocker after |
|---|-----|-------------------|
| 0 | sqlite3.h env (apt `libsqlite3-dev`) | 47: GRDB `CGFloat` |
| 1 | CoreGraphics re-export `Foundation.CGFloat` (6fdd83a) | 2263: reached SSK, `no such module CryptoKit` |
| 2 | `CryptoKit` shim → swift-crypto `Crypto` + `--disable-index-store` | 2263: `no such module CommonCrypto` |
| 3 | `CommonCrypto` shim → OpenSSL EVP (AES) | 2263: `no such module SignalRingRTC` |
| 4 | `SignalRingRTC` faithful type-shim (calling deferred) | 2263: `no such module os.lock` |
| 5 | `os_unfair_lock` C spinlock (COSUnfairLock) + 1-line TSMutex import patch | 1: CommonCrypto `openssl/evp.h` (flaky libssl-dev) |
| 6 | prebuilt `quillui-signal-build` image (deps baked, no flaky apt) | 2263: `no such module Contacts` |
| 7 | `Contacts` shim (value types real, store access deferred) | 2263: `no such module libPhoneNumber_iOS` |
| 8 | `libPhoneNumber_iOS` shim (best-effort E164) | 2263: `no such module ContactsUI` |
| 9 | batch 27 placeholder Apple-framework shims (ContactsUI/Intents/PassKit/…) | 2263: `no such module UniformTypeIdentifiers` (QuillUI has it — missing SSK dep edge) |
| 10 | add UniformTypeIdentifiers to SSK deps … | _(in progress)_ |

## Status

Real libsignal (Rust FFI + Swift) builds on aarch64/Linux; SignalServiceKit
target compiles its dependency graph (LibSignalClient/GRDB/SwiftProtobuf/
swift-crypto) and is now grinding through its own 1412 Swift files — adding one
QuillUI shim per missing Apple module, heading toward the ObjC-core-layer port.
The fixtures `QuillSignalCore`/`QuillSignal` app and the parked presage bridge
are placeholders the real compiled Signal-iOS supersedes. Real account link/send
needs the user's phone — far off; first it has to compile.
