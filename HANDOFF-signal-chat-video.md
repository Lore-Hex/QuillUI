# HANDOFF — Signal chat demo video for Brian Acton (2026-06-10)

**Goal:** a UI-centric demo video showing a native Signal client on QuillOS
(Linux ARM64) **sending and receiving real messages** — to send to Brian Acton
for funding. User said: UI front and center, send/receive is the key shot.
(A first video — terminal-centric, live SSK production reconnect — is DONE:
`~/Desktop/signal-quillos-demo.mp4` + `.qa/signal-quillos-demo.mp4`. User found
it too terminal-heavy; superseded by this effort.)

## What is DONE (all committed/pushed, branch signal/ssk-live-link-connect)

- **signal-chat app** (`Sources/SignalChat/`, commit 4306b702): full native
  QuillUI GTK chat window — conversation list (avatars/snippets/selection),
  thread view (in/out bubbles, group sender labels, Image(filePath:) thumbs,
  color emoji), composer (Enter-to-send + Send button). Data layer: line-JSON
  unix-socket client + ChatStore (bg threads, long-lived `receive` stream, UI
  polls generation counter on 0.4s Timer).
  Build (6s): `docker run --rm -v <worktree>:/qui -v qui-build:/qui/.build
  quillui-signal-build bash -c 'cd /qui && QUILLUI_LINUX_BACKEND=gtk swift build
  --disable-index-store --product signal-chat'`
- **Interaction-VERIFIED against stub** (`scripts/signal-chat-stub-bridge.py`,
  also `.qa/stub-bridge.py`): send, live receive, thread switch, auto-scroll,
  emoji — xdotool-driven, screenshots `.qa/sc-{a,b,c,d}-*.png`.
- **signal-ui** (Track B SSK account card, commit 275d4e83) + STEP J/K/L
  lessons in LESSONS.md (read STEP K/L: stale-module canImport cascade;
  .background(Color) not ZStack{Color}; onAppear re-fires per re-render —
  idempotency-guard; avatar pills need outer clamp frame).

## UPDATE 12:0x — LINKED ✅

The QR scan SUCCEEDED: `{"event":"linked","ok":true, aci 15c960a4-0d62-4e9c-
bb97-a79d858d88c8, number 13059511381}` — store `/work/quill-signal-chat.db`
is a REGISTERED presage device ("QuillOS"). whoami confirms. Receive stream
running in qs-bridge (`/tmp/recv.log`). Waiting on CONTACT SYNC (0
conversations at first check — user asked to open Signal on phone + send a
Note-to-Self to push sync/seed a thread). Once a thread exists → stage take in
qs-video2 (STOP qs-bridge container first — single store owner!) per
choreography below.

## (historical) the real-account link — was blocked on QR scan

The chat backend is quill-signal-bridge (presage/libsignal, Track A — real
Signal protocol). Its June-4 store died with a container /tmp; a FRESH link is
needed. SSK's Device #2 login (quill-signal-account.sqlite) CANNOT power chat —
SSK send/receive is not yet implemented (that's the next Track B milestone).
User pushback noted: "I've already connected the app" — explained each client
is its own device slot; one 15s scan needed.

**Runtime right now (containers left RUNNING):**
- `qs-bridge`: runs `/work/presage/target/debug/quill-signal-bridge
  /tmp/quill-signal.sock` with env `QSIGNAL_DB=/work/quill-signal-chat.db`
  (fresh store, NOT the SSK sqlite), `QSIGNAL_QR_PNG=/qa/link-qr.png`
  (mounted: `<worktree>/.qa` → `/qa`, `qs-work` → `/work`). A babysitter loop
  re-runs `/qa/bridge-link.py` forever: each cycle emits a fresh QR
  (~4 min lifetime) and overwrites `/qa/link-qr.png`; touches `/qa/LINKED`
  on success. Log: `/tmp/link.log` in the container.
- `qs-video2`: prepped recorder (ffmpeg/openbox/xterm/xdotool/
  fonts-noto-color-emoji installed) with worktree+qui-build+qs-work mounts.
  Staging script: `.qa/chat-stage.sh` (bridge+Xvfb+openbox+app+window
  placement; recording driven manually via docker exec ffmpeg).
- v1 video tooling: `.qa/video-demo.sh`, `.qa/video-record.sh`,
  `.qa/video-post.sh` (title/end cards via drawtext textfile= — NOTE: this
  ffmpeg's drawtext truncates by extra UTF-8 bytes; ASCII-only card text).

**Last error:** user's phone said "invalid response from service" on scan —
almost certainly a STALE QR (they expire ~4 min; Preview doesn't auto-reload;
the chat-app file chips don't render for this user — use `open <png>` to show
QR in Preview, and `open`/cp to Desktop for videos). Next attempt: make sure
the scan happens within ~1-2 min of QR generation; re-`open` the PNG right
before they scan. If repeated fresh-QR scans still fail with the same error,
THEN suspect presage provisioning vs current Signal app version (bridge linked
fine June 4; presage rev 6793c3e in /work/presage).

## The take, once linked (choreography agreed with user)

1. Verify: `{"cmd":"whoami"}` → user's number (+13059511381). `list-conversations`
   → contact sync (NOTE: no message history syncs to new devices — only
   contacts; threads fill from link-time forward).
2. Ask user which conversation is safe for a real on-camera send (default:
   Note to Self).
3. Stage in qs-video2 via `.qa/chat-stage.sh` (window 1080x700 at +100+30 on
   1280x800 Xvfb), start ffmpeg x11grab, then: pause on real conversation list
   → xdotool click composer → type+Enter a message (arrives on user's REAL
   phone) → user replies from phone → bubble pops in live (receive stream) →
   optional thread switch → stop.
4. Post: ASCII title/end cards + concat (reuse video-post.sh pattern).
   Deliver via cp to ~/Desktop + `open` (user cannot click chat file chips).

## Key paths / facts

- Worktree: /Users/jperla/claude/quillui-signal (branch signal/ssk-live-link-connect,
  pushed through 4306b702). Bridge source: /Users/jperla/claude/QuillSignal/
  quill-signal-bridge/src/main.rs (workspace copy at /work/presage/quill-signal-bridge
  is CURRENT; binary /work/presage/target/debug/quill-signal-bridge rebuilt today).
- Bridge protocol: see agent-extracted spec — commands ping/status/whoami/
  list-conversations/list-messages/send/link-begin(stream)/receive(stream);
  envelope {ok,cmd,msg,data}; threads = contact ACI or derived group uuid;
  receive events carry sender_name; list-messages does NOT (resolve via
  conversations list).
- Stub run: `python3 scripts/signal-chat-stub-bridge.py /tmp/quill-signal.sock`
  (STUB_RECV_EVERY=8 for fast scripted incoming), app env QSIGNAL_SOCK.
- User context: phone +13059511381; "Brian Acton video" = funding pitch; user
  wants FAST. Honest-framing note: no native macOS Signal exists (Desktop is
  Electron, already on Linux) — Signal-iOS source is the only native codebase;
  explained and accepted.
