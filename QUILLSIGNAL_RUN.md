# Running QuillSignal & linking your account

QuillSignal is **real Signal on QuillOS**: the **presage/libsignal Rust engine**
(behind the `quill-signal-bridge` unix-socket daemon) driving a **native
QuillUI/GTK app** (`quill-signal`). It is a feature-complete Signal client —
**1:1 and group** conversations, sending (with an optimistic echo, exact
timestamp dedup, and a failure banner), **real-time receive** with desktop
notifications, a self-spawning + self-healing engine, and device linking by QR.
See `SIGNAL_PORT.md` for the full design + grind log.

Three pieces:

| Piece | What | Where |
|-------|------|-------|
| **bridge daemon** | wraps presage/libsignal; line-JSON over a unix socket — `ping`/`status`/`whoami`/`link-begin`/`list-conversations`/`list-messages`/`send`/`receive` | built in the `qs-work` Docker volume: `/work/presage/target/debug/quill-signal-bridge` |
| **`quill-signal`** | the native QuillUI/GTK app (link panel → conversations); auto-spawns + self-heals the daemon | `.build-linux/aarch64-unknown-linux-gnu/debug/quill-signal` (needs a display) |
| **`qsignal-cli`** | terminal client; `link` prints a scannable QR — the easy headless link path | `/Users/jperla/claude/QuillSignal/QuillSignalClient` → `.build/debug/qsignal-cli` |

## Build

**The app** (canonical Linux-GTK recipe):

```sh
docker run --rm -v /Users/jperla/claude/quillui-signal:/qui \
  -v qui-build-linux:/qui/.build-linux -v qs-work:/work quillui-signal-build bash -c '
    cd /qui
    QUILLUI_LINUX_BACKEND=gtk scripts/prepare-linux-build-backend.sh --scratch-path .build-linux
    QUILLUI_LINUX_BACKEND=gtk swift build --scratch-path .build-linux --disable-index-store --product quill-signal
  '
```

**The bridge** (builds as the 4th member of the presage workspace in `qs-work`):

```sh
docker run --rm -v /Users/jperla/claude/QuillSignal:/qs -v qs-work:/work \
  -e CARGO_HOME=/work/cargo rust:latest bash -c '
    apt-get update -qq && apt-get install -y -qq protobuf-compiler cmake clang git python3 >/dev/null 2>&1
    cp -r /qs/quill-signal-bridge/src /work/presage/quill-signal-bridge/
    cp /qs/quill-signal-bridge/Cargo.toml /work/presage/quill-signal-bridge/Cargo.toml
    cd /work/presage && cargo build -p quill-signal-bridge
  '
```

## Link your real account (the one user-gated step — needs your phone)

The GTK app shows the link panel + a crisp QR directly on QuillOS hardware (and
the in-app link now lands on a populated, live chat). The **terminal QR via
`qsignal-cli` is the easy headless path**, all in one container (the daemon
binary lives in `qs-work`):

```sh
docker run --rm -it -v /Users/jperla/claude/QuillSignal:/qs -v qs-work:/work \
  swift:6.2-noble bash -c '
    cd /qs/QuillSignalClient && swift build
    # keep your linked account in a persistent, passphrase-encrypted store:
    export QSIGNAL_DB=/work/quillsignal-account.db
    /work/presage/target/debug/quill-signal-bridge /tmp/qs.sock &
    sleep 1
    QSIGNAL_SOCK=/tmp/qs.sock QSIGNAL_LINK_TIMEOUT=120 .build/debug/qsignal-cli link
  '
```

1. A QR prints in the terminal.
2. On your phone: **Signal → Settings → Linked Devices → Link New Device** → scan it.
3. The daemon finishes linking and prints `>> Linked!`. Your account now lives in
   `qs-work:/work/quillsignal-account.db` (reuse it via `QSIGNAL_DB`).

> **Linking, sending, and receiving touch your real Signal account — done by you,
> never automatically.** The app only ever begins a link / sends / receives on
> your explicit action (or, for receive, once you have linked).

## Run the app

The app is **self-contained**: on launch it auto-spawns the bridge daemon if one
isn't already listening on `/tmp/quill-signal-bridge.sock` (override the binary
with `QUILL_SIGNAL_BRIDGE_BIN`, the account DB with `QSIGNAL_DB`, default
`~/.local/share/quill-signal/qs.db`), reuses an already-listening one, and
respawns it if it crashes. Point `QSIGNAL_DB` at the store you linked above.

### What works once linked

- **Conversations** — your contacts **and groups** in the sidebar, with a
  last-message preview and the linked phone number in the title.
- **Timeline** — a conversation's messages, your own right-aligned + blue, others
  left-aligned + gray (own/other attribution comes from the engine).
- **Send** — type + Send: an optimistic echo appears instantly; the message is
  delivered via presage (to a contact or a group). A failure shows a dismissible
  banner; duplicates are de-duped by Signal timestamp.
- **Receive** — incoming messages stream in live and fire a desktop notification
  (`notify-send`, override `QUILL_SIGNAL_NOTIFY_BIN`); the stream auto-restarts if
  the engine restarts.

## Preview / verify without an account (dev)

- **Chat-UI screenshot** (fixtures, no daemon, no account):
  ```sh
  docker run --rm -v /Users/jperla/claude/quillui-signal:/qui \
    -v qui-build-linux:/qui/.build-linux quillui-signal-build \
    bash -c 'QS_FAKELINKED=1 /qui/scripts/quill-signal-screenshot.sh'
  ```
  writes `.qs-shot.png`. `-e QUILLUI_SIGNAL_FAKEEMPTY=1` shows the empty-state;
  `-e QUILLUI_SIGNAL_FAKEERROR=1` shows the send-failure banner.
- **Offscreen runtime smoke** (app ↔ bridge ↔ presage, no account):
  `scripts/verify-quill-signal-smoke.sh` in the `quillui-signal-build` image.
- **Wire-protocol contract check** (fast, no GTK):
  `scripts/quill-signal-decode-check.sh` — asserts every bridge response/event
  decodes into `QuillSignalKit`'s types.
