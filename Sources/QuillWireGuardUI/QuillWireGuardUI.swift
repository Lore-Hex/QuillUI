import QuillUI
import QuillWireGuardCore
import SwiftUI

#if canImport(WireGuardKit)
import WireGuardKit
#endif

public enum QuillWireGuardScene {
    public static let title = QuillWireGuardAppMetadata.title
    public static let defaultWidth = QuillWireGuardAppMetadata.defaultWidth
    public static let defaultHeight = QuillWireGuardAppMetadata.defaultHeight
    public static let minimumWidth = QuillWireGuardAppMetadata.linuxMinimumWidth
    public static let minimumHeight = QuillWireGuardAppMetadata.linuxMinimumHeight

    public static func scene() -> some Scene {
        QuillAppWindow.scene(
            title,
            width: defaultWidth,
            height: defaultHeight,
            defaultSizePolicy: .linuxMinimum(width: minimumWidth, height: minimumHeight)
        ) {
            ContentView()
        }
    }
}

// Shared fallback used by Linux and by platforms where upstream
// WireGuardKit is not linked. Privileged tunnel activation stays
// behind a future backend adapter; this shell keeps configuration
// list/edit/export UI rendering consistently now.
@MainActor
public struct WireGuardFallbackConfigurationView: View {
    @State private var tunnels = QuillWireGuardFixtures.tunnels
    @State private var selectedTunnelID = QuillWireGuardFixtures.defaultTunnelID

    public init() {}

    public nonisolated var body: some View {
        QuillMainActorView.assumeIsolated {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 280)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 800, minHeight: 560)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tunnels")
                    .font(.title3)
                    .bold()
                Spacer()
                Text("\(tunnels.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)

            Divider()

            List {
                ForEach(tunnels) { tunnel in
                    Button {
                        selectedTunnelID = tunnel.id
                    } label: {
                        tunnelRow(tunnel)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Backend")
                    .font(.caption)
                    .bold()
                    .foregroundColor(.secondary)
                Text(QuillWireGuardBackend.statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .background(Color.gray.opacity(0.06))
    }

    private func tunnelRow(_ tunnel: QuillWireGuardTunnel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tunnel.name)
                    .font(.subheadline)
                Spacer()
                Text(tunnel.status.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text("\(tunnel.interface.addresses.joined(separator: ", ")) - \(tunnel.peerSummary)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
    }

    private var detail: some View {
        Group {
            if let tunnel = selectedTunnel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            TextField("Tunnel name", text: selectedTunnelName)
                                .font(.title2)
                            Spacer()
                            Text(tunnel.status.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        section(title: "Interface") {
                            detailRow("Public key", tunnel.interface.publicKey, monospaced: true)
                            detailRow("Addresses", tunnel.interface.addresses.joined(separator: ", "))
                            detailRow("DNS", tunnel.interface.dnsServers.joined(separator: ", "))
                            if let listenPort = tunnel.interface.listenPort {
                                detailRow("Listen port", "\(listenPort)")
                            }
                        }

                        ForEach(tunnel.peers) { peer in
                            section(title: peer.name) {
                                detailRow("Public key", peer.publicKey, monospaced: true)
                                detailRow("Allowed IPs", peer.allowedIPs.joined(separator: ", "))
                                if let endpoint = peer.endpoint {
                                    detailRow("Endpoint", endpoint)
                                }
                                if let keepAlive = peer.persistentKeepAlive {
                                    detailRow("Keepalive", "\(keepAlive)s")
                                }
                            }
                        }

                        section(title: "Export") {
                            Text(tunnel.wgQuickConfig())
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Quill WireGuard")
                        .font(.title2)
                    Text("Select a tunnel to edit and export its configuration.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .bold()
                .foregroundColor(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value.isEmpty ? "None" : value)
                .font(monospaced ? .system(size: 11, design: .monospaced) : .body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedTunnel: QuillWireGuardTunnel? {
        guard let selectedTunnelID else { return nil }
        return tunnels.first(where: { $0.id == selectedTunnelID })
    }

    private var selectedTunnelName: Binding<String> {
        Binding(
            get: { selectedTunnel?.name ?? "" },
            set: { name in
                guard let selectedTunnelID,
                      let index = tunnels.firstIndex(where: { $0.id == selectedTunnelID }) else {
                    return
                }
                tunnels[index].name = name
            }
        )
    }
}

#if os(Linux)
public typealias ContentView = WireGuardFallbackConfigurationView
#else
public struct ContentView: View {
    public init() {}

    #if canImport(WireGuardKit)
    @State private var tunnels: [TunnelConfiguration] = []
    @State private var selectedTunnelName: String?

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 580)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tunnels")
                    .font(.title3).bold()
                Spacer()
                Button(action: addTunnel) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                #if !os(Linux)
                .buttonStyle(.borderless)
                #endif
                .help("Generate a new WireGuard tunnel keypair")
            }
            .padding(14)

            Divider()

            if tunnels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary)
                    Text("No tunnels yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Click + to generate a fresh\nCurve25519 keypair via\nupstream WireGuardKit.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(tunnels, id: \.name, selection: $selectedTunnelName) { tunnel in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: 9, height: 9)
                        Text(tunnel.name ?? "Unnamed")
                            .font(.subheadline)
                        Spacer()
                    }
                    .tag(tunnel.name ?? "")
                }
                .listStyle(.sidebar)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("Real upstream WireGuardKit")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
        }
        .background(Color(white: 0.97))
    }

    private var detail: some View {
        Group {
            if let selectedName = selectedTunnelName,
               let tunnel = tunnels.first(where: { $0.name == selectedName }) {
                TunnelDetailView(tunnel: tunnel)
            } else {
                emptyDetail
            }
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Quill WireGuard")
                .font(.title2).bold()
            Text("Generate a tunnel from the sidebar to inspect its interface, peer, and export details.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addTunnel() {
        let interfacePrivateKey = PrivateKey()
        var interface = InterfaceConfiguration(privateKey: interfacePrivateKey)
        if let addr = IPAddressRange(from: "10.10.10.\(tunnels.count + 2)/32") {
            interface.addresses = [addr]
        }
        if let dns = DNSServer(from: "1.1.1.1") {
            interface.dns = [dns]
        }
        interface.listenPort = UInt16(51820 + tunnels.count)

        let peerPrivateKey = PrivateKey()
        var peer = PeerConfiguration(publicKey: peerPrivateKey.publicKey)
        if let allowed = IPAddressRange(from: "0.0.0.0/0") {
            peer.allowedIPs = [allowed]
        }
        if let endpoint = Endpoint(from: "vpn.example.com:51820") {
            peer.endpoint = endpoint
        }
        peer.persistentKeepAlive = 25

        let name = "Quill Tunnel \(tunnels.count + 1)"
        let config = TunnelConfiguration(name: name, interface: interface, peers: [peer])
        tunnels.append(config)
        selectedTunnelName = name
    }
    #else
    public var body: some View {
        WireGuardFallbackConfigurationView()
    }
    #endif
}
#endif // !os(Linux) — closes the macOS ContentView variant.

#if canImport(WireGuardKit) && !os(Linux)
struct TunnelDetailView: View {
    let tunnel: TunnelConfiguration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tunnel.name ?? "Unnamed Tunnel")
                        .font(.title).bold()
                    Spacer()
                    Toggle("Active", isOn: .constant(false))
                        .toggleStyle(.switch)
                }

                groupBox(title: "Interface") {
                    detailRow("Public key", tunnel.interface.privateKey.publicKey.base64Key, mono: true)
                    if !tunnel.interface.addresses.isEmpty {
                        detailRow("Addresses", tunnel.interface.addresses.map { $0.stringRepresentation }.joined(separator: ", "))
                    }
                    if !tunnel.interface.dns.isEmpty {
                        detailRow("DNS", tunnel.interface.dns.map { $0.stringRepresentation }.joined(separator: ", "))
                    }
                    if let port = tunnel.interface.listenPort {
                        detailRow("Listen port", "\(port)")
                    }
                }

                ForEach(Array(tunnel.peers.enumerated()), id: \.offset) { index, peer in
                    groupBox(title: "Peer \(index + 1)") {
                        detailRow("Public key", peer.publicKey.base64Key, mono: true)
                        if let endpoint = peer.endpoint {
                            detailRow("Endpoint", endpoint.stringRepresentation)
                        }
                        if !peer.allowedIPs.isEmpty {
                            detailRow("Allowed IPs", peer.allowedIPs.map { $0.stringRepresentation }.joined(separator: ", "))
                        }
                        if let keepAlive = peer.persistentKeepAlive {
                            detailRow("Persistent keepalive", "\(keepAlive)s")
                        }
                    }
                }

                groupBox(title: "wg-quick config") {
                    Text(tunnel.asWgQuickConfig())
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func groupBox<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption).bold()
                .foregroundColor(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.96))
        .cornerRadius(8)
    }

    private func detailRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension TunnelConfiguration {
    /// Render a wg-quick-style config from the upstream
    /// TunnelConfiguration. Mirrors the format wg-quick(8) accepts.
    func asWgQuickConfig() -> String {
        var lines: [String] = []
        lines.append("[Interface]")
        lines.append("PrivateKey = \(self.interface.privateKey.base64Key)")
        if !self.interface.addresses.isEmpty {
            lines.append("Address = \(self.interface.addresses.map { $0.stringRepresentation }.joined(separator: ", "))")
        }
        if !self.interface.dns.isEmpty {
            lines.append("DNS = \(self.interface.dns.map { $0.stringRepresentation }.joined(separator: ", "))")
        }
        if let port = self.interface.listenPort {
            lines.append("ListenPort = \(port)")
        }
        for peer in self.peers {
            lines.append("")
            lines.append("[Peer]")
            lines.append("PublicKey = \(peer.publicKey.base64Key)")
            if !peer.allowedIPs.isEmpty {
                lines.append("AllowedIPs = \(peer.allowedIPs.map { $0.stringRepresentation }.joined(separator: ", "))")
            }
            if let endpoint = peer.endpoint {
                lines.append("Endpoint = \(endpoint.stringRepresentation)")
            }
            if let keep = peer.persistentKeepAlive {
                lines.append("PersistentKeepalive = \(keep)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
#endif
