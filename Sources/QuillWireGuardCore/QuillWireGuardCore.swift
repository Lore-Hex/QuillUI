import Foundation

public enum QuillWireGuardAppMetadata {
    public static let title = "Quill WireGuard"
    public static let defaultWidth = 800.0
    public static let defaultHeight = 600.0
    public static let linuxMinimumWidth = 900.0
    public static let linuxMinimumHeight = 600.0
}

public enum QuillWireGuardBackend {
    public static var isAvailable: Bool {
        #if os(Linux)
        false
        #else
        true
        #endif
    }

    public static var statusText: String {
        #if os(Linux)
        "Configuration manager mode; connect and disconnect require a Linux backend adapter."
        #else
        "WireGuardKit backend available."
        #endif
    }
}

public enum QuillWireGuardPresentation {
    public static let sidebarTitle = "Tunnels"
    public static let backendTitle = "Backend"
    public static let tunnelNamePlaceholder = "Tunnel name"
    public static let emptyStateTitle = QuillWireGuardAppMetadata.title
    public static let emptyStateMessage = "Select a tunnel to edit and export its configuration."
    public static let interfaceSectionTitle = "Interface"
    public static let exportSectionTitle = "Export"
    public static let publicKeyLabel = "Public key"
    public static let addressesLabel = "Addresses"
    public static let dnsLabel = "DNS"
    public static let listenPortLabel = "Listen port"
    public static let allowedIPsLabel = "Allowed IPs"
    public static let endpointLabel = "Endpoint"
    public static let keepAliveLabel = "Keepalive"
    public static let noneText = "None"
}

public enum QuillWireGuardTunnelStatus: String, Codable, Sendable {
    case inactive = "Inactive"
    case active = "Active"
    case needsBackend = "Needs Backend"
}

public struct QuillWireGuardInterface: Codable, Hashable, Sendable {
    public var privateKey: String
    public var publicKey: String
    public var addresses: [String]
    public var dnsServers: [String]
    public var listenPort: UInt16?

    public init(
        privateKey: String,
        publicKey: String,
        addresses: [String],
        dnsServers: [String],
        listenPort: UInt16? = nil
    ) {
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.addresses = addresses
        self.dnsServers = dnsServers
        self.listenPort = listenPort
    }
}

public struct QuillWireGuardPeer: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var publicKey: String
    public var allowedIPs: [String]
    public var endpoint: String?
    public var persistentKeepAlive: UInt16?

    public init(
        id: String,
        name: String,
        publicKey: String,
        allowedIPs: [String],
        endpoint: String? = nil,
        persistentKeepAlive: UInt16? = nil
    ) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.allowedIPs = allowedIPs
        self.endpoint = endpoint
        self.persistentKeepAlive = persistentKeepAlive
    }
}

public struct QuillWireGuardTunnel: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var status: QuillWireGuardTunnelStatus
    public var interface: QuillWireGuardInterface
    public var peers: [QuillWireGuardPeer]

    public init(
        id: String,
        name: String,
        status: QuillWireGuardTunnelStatus,
        interface: QuillWireGuardInterface,
        peers: [QuillWireGuardPeer]
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.interface = interface
        self.peers = peers
    }

    public var peerSummary: String {
        "\(peers.count) \(peers.count == 1 ? "peer" : "peers")"
    }

    public func wgQuickConfig() -> String {
        var lines: [String] = [
            "[Interface]",
            "PrivateKey = \(interface.privateKey)",
        ]

        if !interface.addresses.isEmpty {
            lines.append("Address = \(interface.addresses.joined(separator: ", "))")
        }

        if !interface.dnsServers.isEmpty {
            lines.append("DNS = \(interface.dnsServers.joined(separator: ", "))")
        }

        if let listenPort = interface.listenPort {
            lines.append("ListenPort = \(listenPort)")
        }

        for peer in peers {
            lines.append("")
            lines.append("[Peer]")
            lines.append("# Name = \(peer.name)")
            lines.append("PublicKey = \(peer.publicKey)")

            if !peer.allowedIPs.isEmpty {
                lines.append("AllowedIPs = \(peer.allowedIPs.joined(separator: ", "))")
            }

            if let endpoint = peer.endpoint {
                lines.append("Endpoint = \(endpoint)")
            }

            if let persistentKeepAlive = peer.persistentKeepAlive {
                lines.append("PersistentKeepalive = \(persistentKeepAlive)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

public struct QuillWireGuardInterfaceSnapshot: Codable, Equatable, Sendable {
    public var publicKey: String
    public var addressesText: String
    public var dnsServersText: String
    public var listenPortText: String?

    public init(interface: QuillWireGuardInterface) {
        self.publicKey = interface.publicKey
        self.addressesText = interface.addresses.joined(separator: ", ")
        self.dnsServersText = interface.dnsServers.joined(separator: ", ")
        self.listenPortText = interface.listenPort.map { String($0) }
    }
}

public struct QuillWireGuardPeerSnapshot: Codable, Equatable, Sendable {
    public var name: String
    public var publicKey: String
    public var allowedIPsText: String
    public var endpointText: String?
    public var keepAliveText: String?

    public init(peer: QuillWireGuardPeer) {
        self.name = peer.name
        self.publicKey = peer.publicKey
        self.allowedIPsText = peer.allowedIPs.joined(separator: ", ")
        self.endpointText = peer.endpoint
        self.keepAliveText = peer.persistentKeepAlive.map { "\($0)s" }
    }
}

public struct QuillWireGuardTunnelSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var statusText: String
    public var peerSummary: String
    public var interface: QuillWireGuardInterfaceSnapshot
    public var peers: [QuillWireGuardPeerSnapshot]
    public var wgQuickConfig: String

    public init(tunnel: QuillWireGuardTunnel) {
        self.id = tunnel.id
        self.name = tunnel.name
        self.statusText = tunnel.status.rawValue
        self.peerSummary = tunnel.peerSummary
        self.interface = QuillWireGuardInterfaceSnapshot(interface: tunnel.interface)
        self.peers = tunnel.peers.map(QuillWireGuardPeerSnapshot.init(peer:))
        self.wgQuickConfig = tunnel.wgQuickConfig()
    }
}

public struct QuillWireGuardPresentationSnapshot: Codable, Equatable, Sendable {
    public var sidebarTitle: String
    public var backendTitle: String
    public var tunnelNamePlaceholder: String
    public var emptyStateTitle: String
    public var emptyStateMessage: String
    public var interfaceSectionTitle: String
    public var exportSectionTitle: String
    public var publicKeyLabel: String
    public var addressesLabel: String
    public var dnsLabel: String
    public var listenPortLabel: String
    public var allowedIPsLabel: String
    public var endpointLabel: String
    public var keepAliveLabel: String
    public var noneText: String

    public init(
        sidebarTitle: String = QuillWireGuardPresentation.sidebarTitle,
        backendTitle: String = QuillWireGuardPresentation.backendTitle,
        tunnelNamePlaceholder: String = QuillWireGuardPresentation.tunnelNamePlaceholder,
        emptyStateTitle: String = QuillWireGuardPresentation.emptyStateTitle,
        emptyStateMessage: String = QuillWireGuardPresentation.emptyStateMessage,
        interfaceSectionTitle: String = QuillWireGuardPresentation.interfaceSectionTitle,
        exportSectionTitle: String = QuillWireGuardPresentation.exportSectionTitle,
        publicKeyLabel: String = QuillWireGuardPresentation.publicKeyLabel,
        addressesLabel: String = QuillWireGuardPresentation.addressesLabel,
        dnsLabel: String = QuillWireGuardPresentation.dnsLabel,
        listenPortLabel: String = QuillWireGuardPresentation.listenPortLabel,
        allowedIPsLabel: String = QuillWireGuardPresentation.allowedIPsLabel,
        endpointLabel: String = QuillWireGuardPresentation.endpointLabel,
        keepAliveLabel: String = QuillWireGuardPresentation.keepAliveLabel,
        noneText: String = QuillWireGuardPresentation.noneText
    ) {
        self.sidebarTitle = sidebarTitle
        self.backendTitle = backendTitle
        self.tunnelNamePlaceholder = tunnelNamePlaceholder
        self.emptyStateTitle = emptyStateTitle
        self.emptyStateMessage = emptyStateMessage
        self.interfaceSectionTitle = interfaceSectionTitle
        self.exportSectionTitle = exportSectionTitle
        self.publicKeyLabel = publicKeyLabel
        self.addressesLabel = addressesLabel
        self.dnsLabel = dnsLabel
        self.listenPortLabel = listenPortLabel
        self.allowedIPsLabel = allowedIPsLabel
        self.endpointLabel = endpointLabel
        self.keepAliveLabel = keepAliveLabel
        self.noneText = noneText
    }
}

public struct QuillWireGuardAppSnapshot: Codable, Equatable, Sendable {
    public var title: String
    public var defaultWidth: Int
    public var defaultHeight: Int
    public var minimumWidth: Int
    public var minimumHeight: Int
    public var backendStatusText: String
    public var presentation: QuillWireGuardPresentationSnapshot
    public var selectedTunnelID: QuillWireGuardTunnelSnapshot.ID?
    public var tunnels: [QuillWireGuardTunnelSnapshot]

    private enum CodingKeys: String, CodingKey {
        case title
        case defaultWidth
        case defaultHeight
        case minimumWidth
        case minimumHeight
        case backendStatusText
        case presentation
        case selectedTunnelID
        case tunnels
    }

    public init(
        title: String,
        defaultWidth: Int,
        defaultHeight: Int,
        minimumWidth: Int = Int(QuillWireGuardAppMetadata.linuxMinimumWidth),
        minimumHeight: Int = Int(QuillWireGuardAppMetadata.linuxMinimumHeight),
        backendStatusText: String,
        presentation: QuillWireGuardPresentationSnapshot = QuillWireGuardPresentationSnapshot(),
        selectedTunnelID: QuillWireGuardTunnelSnapshot.ID?,
        tunnels: [QuillWireGuardTunnelSnapshot]
    ) {
        self.title = title
        self.defaultWidth = defaultWidth
        self.defaultHeight = defaultHeight
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
        self.backendStatusText = backendStatusText
        self.presentation = presentation
        self.selectedTunnelID = selectedTunnelID
        self.tunnels = tunnels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.title = try container.decode(String.self, forKey: .title)
        self.defaultWidth = try container.decode(Int.self, forKey: .defaultWidth)
        self.defaultHeight = try container.decode(Int.self, forKey: .defaultHeight)
        self.minimumWidth = try container.decode(Int.self, forKey: .minimumWidth)
        self.minimumHeight = try container.decode(Int.self, forKey: .minimumHeight)
        self.backendStatusText = try container.decode(String.self, forKey: .backendStatusText)
        self.presentation = try container.decodeIfPresent(
            QuillWireGuardPresentationSnapshot.self,
            forKey: .presentation
        ) ?? QuillWireGuardPresentationSnapshot()
        self.selectedTunnelID = try container.decodeIfPresent(
            QuillWireGuardTunnelSnapshot.ID.self,
            forKey: .selectedTunnelID
        )
        self.tunnels = try container.decode([QuillWireGuardTunnelSnapshot].self, forKey: .tunnels)
    }

    public static var configurationManager: QuillWireGuardAppSnapshot {
        QuillWireGuardAppSnapshot(
            title: QuillWireGuardAppMetadata.title,
            defaultWidth: Int(QuillWireGuardAppMetadata.defaultWidth),
            defaultHeight: Int(QuillWireGuardAppMetadata.defaultHeight),
            minimumWidth: Int(QuillWireGuardAppMetadata.linuxMinimumWidth),
            minimumHeight: Int(QuillWireGuardAppMetadata.linuxMinimumHeight),
            backendStatusText: QuillWireGuardBackend.statusText,
            selectedTunnelID: QuillWireGuardFixtures.defaultTunnelID,
            tunnels: QuillWireGuardFixtures.tunnels.map(QuillWireGuardTunnelSnapshot.init(tunnel:))
        )
    }
}

public enum QuillWireGuardFixtures {
    public static let tunnels: [QuillWireGuardTunnel] = [
        QuillWireGuardTunnel(
            id: "sample-home",
            name: "Home Lab",
            status: .needsBackend,
            interface: QuillWireGuardInterface(
                privateKey: "0Jz5r3MR8ZkW4e7rB1kP6p1bDVLwNqJpG2i6n9cR0VM=",
                publicKey: "jzxn1x8CWRYpLxRhx8UQOVqpn4yqIPVfZ+Zpjr93ZQM=",
                addresses: ["10.8.0.2/32", "fd42:42:42::2/128"],
                dnsServers: ["1.1.1.1", "2606:4700:4700::1111"],
                listenPort: 51820
            ),
            peers: [
                QuillWireGuardPeer(
                    id: "sample-home-gateway",
                    name: "Gateway",
                    publicKey: "uwW5cY8B8C8jS6T2u7Vp7h4f0q4uK8h0jNf3X9s0WgI=",
                    allowedIPs: ["0.0.0.0/0", "::/0"],
                    endpoint: "vpn.example.com:51820",
                    persistentKeepAlive: 25
                ),
            ]
        ),
        QuillWireGuardTunnel(
            id: "sample-office",
            name: "Office",
            status: .inactive,
            interface: QuillWireGuardInterface(
                privateKey: "iMNrAjZp3IfSTF9y20l6UnZGxv7tgnTtQtEqcBae01A=",
                publicKey: "eK39Izzbrl+8x9aQbdQoSXDzf3vpqr0fqv7nlBTz3k0=",
                addresses: ["10.44.0.8/32"],
                dnsServers: ["10.44.0.1"]
            ),
            peers: [
                QuillWireGuardPeer(
                    id: "sample-office-edge",
                    name: "Office Edge",
                    publicKey: "U7m7JrZpbC9g9WMMrwvqF9WgtM4jCUoZ0UQ+1dHDxHc=",
                    allowedIPs: ["10.44.0.0/16"],
                    endpoint: "office.example.com:51820"
                ),
            ]
        ),
    ]

    public static var defaultTunnelID: QuillWireGuardTunnel.ID? {
        tunnels.first?.id
    }
}
