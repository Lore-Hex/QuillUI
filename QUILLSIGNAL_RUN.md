# Running QuillSignal & linking your account

QuillSignal is real Signal on QuillOS: the **presage/libsignal Rust engine**
(behind the `quill-signal-bridge` unix-socket daemon) + a **native QuillUI/GTK
app** (`quill-signal`). See `SIGNAL_PORT.md` for the full design + status.

Three pieces:

| Piece | What | Where |
|-------|------|-------|
| **bridge daemon** | wraps presage/libsignal; line-JSON over a unix socket (`ping`/`status`/`link-begin`) | built in the `qs-work` Docker volume: `/work/presage/target/debug/quill-signal-bridge` |
| **`qsignal-cli`** | terminal client; `link` prints a scannable QR | `/Users/jperla/claude/QuillSignal/QuillSignalClient` → `.build/debug/qsignal-cli` |
| **`quill-signal`** | the native QuillUI/GTK app (link panel → conversations) | `.build-linux/aarch64-unknown-linux-gnu/debug/quill-signal` (needs a display) |

## Link your real account (the one user-gated step — needs your phone)

The GTK app needs a display; the **terminal QR via `qsignal-cli` is the easy
path**. All in one container (the bridge daemon binary lives in `qs-work`):

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

> Linking, sending, and receiving touch your real Signal account — done by you,
> never automatically.

## Run the native GTK app

Build (canonical Linux-GTK recipe):

```sh
docker run --rm -v /Users/jperla/claude/quillui-signal:/qui \
  -v qui-build-linux:/qui/.build-linux -v qs-work:/work quillui-signal-build bash -c '
    cd /qui
    QUILLUI_LINUX_BACKEND=gtk scripts/prepare-linux-build-backend.sh --scratch-path .build-linux
    QUILLUI_LINUX_BACKEND=gtk swift build --scratch-path .build-linux --disable-index-store --product quill-signal
  '
```

Smoke it offscreen (no account): `scripts/verify-quill-signal-smoke.sh` inside the
`quillui-signal-build` image (mount `qs-work`). On real QuillOS hardware (with a
display) the app shows the link panel + QR directly. The app connects to the
bridge on `/tmp/quill-signal-bridge.sock`, so start the daemon there:
`quill-signal-bridge /tmp/quill-signal-bridge.sock`.

## After linking (next work)

The bridge currently does `status` + `link-begin`. Once linked, extend it with
`list-conversations` / `list-messages` / `send` (presage already supports these)
and wire them into `QuillSignalContentView` (replacing the fixture conversations
in `Sources/QuillSignalCore`).
