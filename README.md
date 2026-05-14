# QuillUI

QuillUI is an open-source Swift UI portability layer for bringing
SwiftUI-shaped app code to Linux desktops while keeping the same app scenes
usable on Apple platforms.

The Linux runtime and build graph are selected separately. `QUILLUI_BACKEND`
requests `gtk` or `qt` at launch for backend smoke/profile parity; GTK remains
the current native SwiftUI-shaped renderer while generic Qt-requested rows make
their fallback status visible. Native Qt targets use the SwiftPM manifest-time
selector `QUILLUI_LINUX_BACKEND=qt`, which requires Qt6 Widgets and swaps the
selected target graph to Qt dependencies instead of GTK dependencies.

`QuillChatKit` is a reusable SwiftUI chat chrome library product for Signal,
Telegram, and native SwiftUI clients on macOS/iOS. Its native SwiftUI boundary
is checked with `scripts/check-quillchatkit-ios.sh`, which builds the library
against the iOS simulator SDK at the package's iOS 14 floor. The default
`ChatAppearance.standard` tokens preserve the desktop app chrome, while
`ChatAppearance.touch` and `ChatAppearance.platformDefault` provide touch-first
density profiles for iOS clients without a UIKit or QuillUI dependency.
`ChatSplitShell` is available on iOS 16+ / macOS 13+ for apps that want the
same split-view chat routing used by the Linux Signal and Telegram targets.

Current backend parity app targets:

1. `quill-enchanted`
2. `quill-enchanted-upstream-slice`
3. `quill-icecubes`
4. `quill-netnewswire`
5. `quill-codeedit`
6. `quill-signal`
7. `quill-telegram`
8. `quill-iina`
9. `quill-wireguard`
10. `quill-wireguard-qt`

Generated external app coverage also includes `quill-chat-linux` when the
local Quill Chat checkout is available.

## Current Checkpoint

- `QuillUI`: facade module that re-exports SwiftUI on Apple platforms and SwiftOpenUI elsewhere.
- `quill-enchanted`: a desktop chat app with Ollama model discovery, streaming chat completion, and local QuillData conversation history.
- `QuillUIGtk` / `QuillUIQt`: backend-specific launch targets sharing the same app scene and smoke-test contracts.
- `quill-wireguard` / `quill-wireguard-qt`: GTK/default and native Qt WireGuard launch targets fed by the shared `QuillWireGuardCore` presentation snapshot.
- `scripts/quillui-backend-products.sh`: canonical app, generated-app, smoke, and profile rosters for GTK/Qt parity loops.
- `scripts/run-linux-backend-smoke-matrix.sh`: shared visual/interaction matrix runner so local and CI GTK/Qt smoke rows stay identical.

## Run

On macOS:

```sh
swift run quill-enchanted
```

On Linux with backend smoke dependencies installed:

```sh
curl -O "https://download.swift.org/swiftly/linux/swiftly-1.1.1-$(uname -m).tar.gz"
tar -zxf "swiftly-1.1.1-$(uname -m).tar.gz"
./swiftly init
sudo apt-get update
sudo apt-get install -y git imagemagick libgdk-pixbuf-2.0-dev libgtk-4-dev libsqlite3-dev pkg-config x11-apps xdotool xvfb
swift run quill-enchanted
QUILLUI_BACKEND=gtk swift run quill-signal
QUILLUI_BACKEND=qt swift run quill-signal
sudo apt-get install -y qt6-base-dev
QUILLUI_LINUX_BACKEND=qt swift run quill-wireguard-qt
```

You also need an Ollama server reachable at `http://localhost:11434` or the endpoint configured in the app.

Backend parity checks:

```sh
scripts/quillui-backend-products.sh app-matrix
scripts/run-linux-backend-smoke-matrix.sh --dry-run visual app-matrix '.qa/{product}-{backend}.png'
scripts/run-linux-backend-smoke-matrix.sh --dry-run interaction interaction-matrix '.qa/{product}-interaction-{backend}.png'
scripts/run-linux-backend-smoke-matrix.sh --dry-run interaction interaction-extra-mode-matrix '.qa/{product}-{mode}-{backend}.png'
scripts/linux-backend-check.sh
```
