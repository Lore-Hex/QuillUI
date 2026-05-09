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

### 2. UI (SwiftUI Implementation)
- **Status:** To be built from scratch using QuillUI.
- **Required Views:**
    - `TunnelListView`: List of available tunnels with status indicators (on/off).
    - `TunnelDetailView`: Detailed configuration view (Form-based).
    - `TunnelEditView`: Editor for tunnel settings (Interface, Peers).
    - `ImportView`: File picker or QR code scanner (using QuillUI shims).

### 3. Backend (Linux Adapter)
- **Strategy:** Instead of `NetworkExtension`, we will interface with `wg` and `wg-quick` CLI tools or `NetworkManager` via DBus.
- **Initial Milestone:** Stub the connection logic and focus on configuration management (CRUD).

## Porting Challenges
- **Privileged Operations:** Linux requires `sudo` or specific capabilities for `wg-quick`. We will likely need a helper service or specific permissions in the QuillOS environment.
- **QR Code Scanning:** Requires camera access and a decoder. We may need to shim `AVFoundation` more deeply or use a Linux library.

## Next Steps
1. Scaffold `QuillWireGuard` target in `Package.swift`.
2. Implement basic `TunnelConfiguration` storage using `QuillData`.
3. Build the `TunnelListView` using `QuillUI`.
