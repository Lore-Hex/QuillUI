# QuillUI WireGuard Audit

## Overview
WireGuard Apple is a UIKit (iOS) and AppKit (macOS) application. To bring it to QuillOS/Linux, we will build a modern SwiftUI-based interface that leverages the core logic in `WireGuardKit`.

## Repository
- Source: `https://github.com/WireGuard/wireguard-apple` (cloned to `.upstream/wireguard-apple`)

## Key Components to Port

### 1. WireGuardKit (Core Logic)
- **Status:** Mostly portable Swift.
- **Components:** `TunnelConfiguration`, `PeerConfiguration`, `PrivateKey`, `Endpoint`.
- **Linux Strategy:** Reuse these models directly for parsing `.conf` files and managing state.

### 2. UI (SwiftUI + Qt Host Implementation)
- **Status:** First Linux shell implemented with QuillUI, with a native Qt6 Widgets WireGuard host available through `QUILLUI_LINUX_BACKEND=qt swift run quill-wireguard-qt`.
- **Required Views:**
    - `TunnelListView`: List of available tunnels with status indicators.
    - `TunnelDetailView`: Detailed configuration view for interface, peers, and export text.
    - `TunnelEditView`: Editor for tunnel settings (first slice edits tunnel names; interface/peer editing remains next).
    - `ImportView`: File picker or QR code scanner (using QuillUI shims).

### 3. Backend (Linux Adapter)
- **Strategy:** Instead of `NetworkExtension`, we will interface with `wg` and `wg-quick` CLI tools or `NetworkManager` via DBus.
- **Initial Milestone:** Stub the connection logic and focus on configuration management (CRUD).
- **Backend Graph:** Linux build selection is explicit: `QUILLUI_LINUX_BACKEND=gtk` uses the shared QuillUI/SwiftOpenUI path, while `QUILLUI_LINUX_BACKEND=qt` builds the Qt-only WireGuard host from the same core presentation snapshot.

## Porting Challenges
- **Privileged Operations:** Linux requires `sudo` or specific capabilities for `wg-quick`. We will likely need a helper service or specific permissions in the QuillOS environment.
- **QR Code Scanning:** Requires camera access and a decoder. We may need to shim `AVFoundation` more deeply or use a Linux library.

## Next Steps
1. Add `.conf` import parsing and file picker wiring.
2. Persist edited tunnels through QuillData instead of static fixtures.
3. Wire the privileged Linux connect/disconnect path through a backend adapter.
