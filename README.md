# QuillUI

QuillUI is an open-source Swift UI portability layer for bringing SwiftUI-shaped app code to Linux desktops.

The first target app is an Enchanted-inspired Ollama chat client that runs through SwiftUI on macOS and through SwiftOpenUI's GTK4 backend on Linux.

Current app targets:

1. Enchanted
2. IceCubes
3. NetNewsWire
4. CodeEdit
5. Signal iOS
6. Telegram Swift
7. IINA

Side target: WireGuard Apple.

## Current Checkpoint

- `QuillUI`: facade module that re-exports SwiftUI on Apple platforms and SwiftOpenUI elsewhere.
- `quill-enchanted`: a desktop chat app with Ollama model discovery, streaming chat completion, and local QuillData conversation history.
- Linux path: SwiftOpenUI GTK4 backend, built when the package manifest is evaluated on Linux.

## Run

On macOS:

```sh
swift run quill-enchanted
```

On Linux with GTK4 development packages installed:

```sh
curl -O "https://download.swift.org/swiftly/linux/swiftly-1.1.1-$(uname -m).tar.gz"
tar -zxf "swiftly-1.1.1-$(uname -m).tar.gz"
./swiftly init
sudo apt-get update
sudo apt-get install -y clang libgtk-4-dev libsqlite3-dev pkg-config xvfb
swift run quill-enchanted
```

You also need an Ollama server reachable at `http://localhost:11434` or the endpoint configured in the app.
