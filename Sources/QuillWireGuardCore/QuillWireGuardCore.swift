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
    public static let importButtonLabel = "+"
    public static let importButtonTooltip = "Import WireGuard configuration"
    public static let importActionLabel = "Import"
    public static let importFileActionLabel = "Choose File"
    public static let importCancelActionLabel = "Cancel"
    public static let importDialogTitle = "Import WireGuard Configuration"
    public static let importPlaceholder = "[Interface]\nPrivateKey = ...\n\n[Peer]\nPublicKey = ..."
    public static let importEmptyConfigurationError = "Paste a WireGuard configuration before importing."
    public static let importUnavailableError = "WireGuard import is unavailable in this build."
    public static let importNoResponseError = "WireGuard import did not return a response."
    public static let importInvalidResponseError = "WireGuard import returned invalid JSON."
    public static let importMissingTunnelError = "WireGuard import response did not include a tunnel."
    public static let importMissingConfigurationError = "Missing WireGuard configuration."
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

public enum QuillWireGuardStyle {
    public static let windowBackgroundColor = "#ffffff"
    public static let primaryTextColor = "#1d1d1f"
    public static let secondaryTextColor = "#6e6e73"
    public static let dividerColor = "#d8d8dd"
    public static let sidebarBackgroundColor = "#f7f7f8"
    public static let selectedRowBackgroundColor = "#e8eefc"
    public static let selectedRowTextColor = "#111111"
    public static let pressedButtonBackgroundColor = "#ececf0"
    public static let focusBorderColor = "#93a4c7"
    public static let detailSectionBackgroundColor = "#f4f4f5"
    public static let errorTextColor = "#a92222"

    public static let rootFontSize = 13
    public static let captionFontSize = 11
    public static let sidebarTitleFontSize = 16
    public static let backendTitleFontSize = 11
    public static let detailTitleFontSize = 22
    public static let emptyStateTitleFontSize = 22

    public static let listItemCornerRadius = 4
    public static let importButtonCornerRadius = 4
    public static let detailTitleCornerRadius = 3
    public static let importButtonVerticalPadding = 4
    public static let importButtonHorizontalPadding = 8
    public static let detailSectionPadding = 12
    public static let detailSectionTopMargin = 18

    public static let sidebarWidth = 280
    public static let sidebarMaximumWidth = 320
    public static let sidebarPadding = 14
    public static let sidebarBottomPadding = 12
    public static let detailPadding = 22
    public static let detailSpacing = 16
    public static let importDialogWidth = 560
    public static let importDialogHeight = 420
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

public struct QuillWireGuardImportResponse: Codable, Equatable, Sendable {
    public var tunnel: QuillWireGuardTunnelSnapshot?
    public var errorText: String?

    public init(tunnel: QuillWireGuardTunnelSnapshot? = nil, errorText: String? = nil) {
        self.tunnel = tunnel
        self.errorText = errorText
    }

    public static func success(tunnel: QuillWireGuardTunnel) -> QuillWireGuardImportResponse {
        QuillWireGuardImportResponse(tunnel: QuillWireGuardTunnelSnapshot(tunnel: tunnel))
    }

    public static func failure(_ errorText: String) -> QuillWireGuardImportResponse {
        QuillWireGuardImportResponse(errorText: errorText)
    }
}

public enum QuillWireGuardImportError: Equatable, Error, CustomStringConvertible, Sendable {
    case emptyConfiguration

    public var description: String {
        switch self {
        case .emptyConfiguration:
            QuillWireGuardPresentation.importEmptyConfigurationError
        }
    }
}

public enum QuillWireGuardImportService {
    public static func tunnelID(existingTunnelCount: Int) -> String {
        "imported-tunnel-\(existingTunnelCount + 1)"
    }

    public static func tunnelName(existingTunnelCount: Int) -> String {
        "Imported Tunnel \(existingTunnelCount + 1)"
    }

    public static func importConfiguration(
        _ configuration: String,
        id: String,
        name: String,
        status: QuillWireGuardTunnelStatus = .needsBackend
    ) -> QuillWireGuardImportResponse {
        do {
            let tunnel = try importTunnel(
                configuration,
                id: id,
                name: name,
                status: status
            )
            return .success(tunnel: tunnel)
        } catch let error as CustomStringConvertible {
            return .failure(error.description)
        } catch {
            return .failure(String(describing: error))
        }
    }

    public static func importTunnel(
        _ configuration: String,
        id: String,
        name: String,
        status: QuillWireGuardTunnelStatus = .needsBackend
    ) throws -> QuillWireGuardTunnel {
        let trimmedConfiguration = configuration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedConfiguration.isEmpty else {
            throw QuillWireGuardImportError.emptyConfiguration
        }

        return try QuillWireGuardConfigParser.parse(
            trimmedConfiguration,
            id: id,
            name: name,
            status: status
        )
    }
}

public struct QuillWireGuardPresentationSnapshot: Codable, Equatable, Sendable {
    public var sidebarTitle: String
    public var backendTitle: String
    public var importButtonLabel: String
    public var importButtonTooltip: String
    public var importActionLabel: String
    public var importFileActionLabel: String
    public var importCancelActionLabel: String
    public var importDialogTitle: String
    public var importPlaceholder: String
    public var importEmptyConfigurationError: String
    public var importUnavailableError: String
    public var importNoResponseError: String
    public var importInvalidResponseError: String
    public var importMissingTunnelError: String
    public var importMissingConfigurationError: String
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

    private enum CodingKeys: String, CodingKey {
        case sidebarTitle
        case backendTitle
        case importButtonLabel
        case importButtonTooltip
        case importActionLabel
        case importFileActionLabel
        case importCancelActionLabel
        case importDialogTitle
        case importPlaceholder
        case importEmptyConfigurationError
        case importUnavailableError
        case importNoResponseError
        case importInvalidResponseError
        case importMissingTunnelError
        case importMissingConfigurationError
        case tunnelNamePlaceholder
        case emptyStateTitle
        case emptyStateMessage
        case interfaceSectionTitle
        case exportSectionTitle
        case publicKeyLabel
        case addressesLabel
        case dnsLabel
        case listenPortLabel
        case allowedIPsLabel
        case endpointLabel
        case keepAliveLabel
        case noneText
    }

    public init(
        sidebarTitle: String = QuillWireGuardPresentation.sidebarTitle,
        backendTitle: String = QuillWireGuardPresentation.backendTitle,
        importButtonLabel: String = QuillWireGuardPresentation.importButtonLabel,
        importButtonTooltip: String = QuillWireGuardPresentation.importButtonTooltip,
        importActionLabel: String = QuillWireGuardPresentation.importActionLabel,
        importFileActionLabel: String = QuillWireGuardPresentation.importFileActionLabel,
        importCancelActionLabel: String = QuillWireGuardPresentation.importCancelActionLabel,
        importDialogTitle: String = QuillWireGuardPresentation.importDialogTitle,
        importPlaceholder: String = QuillWireGuardPresentation.importPlaceholder,
        importEmptyConfigurationError: String = QuillWireGuardPresentation.importEmptyConfigurationError,
        importUnavailableError: String = QuillWireGuardPresentation.importUnavailableError,
        importNoResponseError: String = QuillWireGuardPresentation.importNoResponseError,
        importInvalidResponseError: String = QuillWireGuardPresentation.importInvalidResponseError,
        importMissingTunnelError: String = QuillWireGuardPresentation.importMissingTunnelError,
        importMissingConfigurationError: String = QuillWireGuardPresentation.importMissingConfigurationError,
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
        self.importButtonLabel = importButtonLabel
        self.importButtonTooltip = importButtonTooltip
        self.importActionLabel = importActionLabel
        self.importFileActionLabel = importFileActionLabel
        self.importCancelActionLabel = importCancelActionLabel
        self.importDialogTitle = importDialogTitle
        self.importPlaceholder = importPlaceholder
        self.importEmptyConfigurationError = importEmptyConfigurationError
        self.importUnavailableError = importUnavailableError
        self.importNoResponseError = importNoResponseError
        self.importInvalidResponseError = importInvalidResponseError
        self.importMissingTunnelError = importMissingTunnelError
        self.importMissingConfigurationError = importMissingConfigurationError
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            sidebarTitle: try container.decodeIfPresent(String.self, forKey: .sidebarTitle)
                ?? QuillWireGuardPresentation.sidebarTitle,
            backendTitle: try container.decodeIfPresent(String.self, forKey: .backendTitle)
                ?? QuillWireGuardPresentation.backendTitle,
            importButtonLabel: try container.decodeIfPresent(String.self, forKey: .importButtonLabel)
                ?? QuillWireGuardPresentation.importButtonLabel,
            importButtonTooltip: try container.decodeIfPresent(String.self, forKey: .importButtonTooltip)
                ?? QuillWireGuardPresentation.importButtonTooltip,
            importActionLabel: try container.decodeIfPresent(String.self, forKey: .importActionLabel)
                ?? QuillWireGuardPresentation.importActionLabel,
            importFileActionLabel: try container.decodeIfPresent(String.self, forKey: .importFileActionLabel)
                ?? QuillWireGuardPresentation.importFileActionLabel,
            importCancelActionLabel: try container.decodeIfPresent(String.self, forKey: .importCancelActionLabel)
                ?? QuillWireGuardPresentation.importCancelActionLabel,
            importDialogTitle: try container.decodeIfPresent(String.self, forKey: .importDialogTitle)
                ?? QuillWireGuardPresentation.importDialogTitle,
            importPlaceholder: try container.decodeIfPresent(String.self, forKey: .importPlaceholder)
                ?? QuillWireGuardPresentation.importPlaceholder,
            importEmptyConfigurationError: try container.decodeIfPresent(
                String.self,
                forKey: .importEmptyConfigurationError
            ) ?? QuillWireGuardPresentation.importEmptyConfigurationError,
            importUnavailableError: try container.decodeIfPresent(String.self, forKey: .importUnavailableError)
                ?? QuillWireGuardPresentation.importUnavailableError,
            importNoResponseError: try container.decodeIfPresent(String.self, forKey: .importNoResponseError)
                ?? QuillWireGuardPresentation.importNoResponseError,
            importInvalidResponseError: try container.decodeIfPresent(String.self, forKey: .importInvalidResponseError)
                ?? QuillWireGuardPresentation.importInvalidResponseError,
            importMissingTunnelError: try container.decodeIfPresent(String.self, forKey: .importMissingTunnelError)
                ?? QuillWireGuardPresentation.importMissingTunnelError,
            importMissingConfigurationError: try container.decodeIfPresent(
                String.self,
                forKey: .importMissingConfigurationError
            ) ?? QuillWireGuardPresentation.importMissingConfigurationError,
            tunnelNamePlaceholder: try container.decodeIfPresent(String.self, forKey: .tunnelNamePlaceholder)
                ?? QuillWireGuardPresentation.tunnelNamePlaceholder,
            emptyStateTitle: try container.decodeIfPresent(String.self, forKey: .emptyStateTitle)
                ?? QuillWireGuardPresentation.emptyStateTitle,
            emptyStateMessage: try container.decodeIfPresent(String.self, forKey: .emptyStateMessage)
                ?? QuillWireGuardPresentation.emptyStateMessage,
            interfaceSectionTitle: try container.decodeIfPresent(String.self, forKey: .interfaceSectionTitle)
                ?? QuillWireGuardPresentation.interfaceSectionTitle,
            exportSectionTitle: try container.decodeIfPresent(String.self, forKey: .exportSectionTitle)
                ?? QuillWireGuardPresentation.exportSectionTitle,
            publicKeyLabel: try container.decodeIfPresent(String.self, forKey: .publicKeyLabel)
                ?? QuillWireGuardPresentation.publicKeyLabel,
            addressesLabel: try container.decodeIfPresent(String.self, forKey: .addressesLabel)
                ?? QuillWireGuardPresentation.addressesLabel,
            dnsLabel: try container.decodeIfPresent(String.self, forKey: .dnsLabel)
                ?? QuillWireGuardPresentation.dnsLabel,
            listenPortLabel: try container.decodeIfPresent(String.self, forKey: .listenPortLabel)
                ?? QuillWireGuardPresentation.listenPortLabel,
            allowedIPsLabel: try container.decodeIfPresent(String.self, forKey: .allowedIPsLabel)
                ?? QuillWireGuardPresentation.allowedIPsLabel,
            endpointLabel: try container.decodeIfPresent(String.self, forKey: .endpointLabel)
                ?? QuillWireGuardPresentation.endpointLabel,
            keepAliveLabel: try container.decodeIfPresent(String.self, forKey: .keepAliveLabel)
                ?? QuillWireGuardPresentation.keepAliveLabel,
            noneText: try container.decodeIfPresent(String.self, forKey: .noneText)
                ?? QuillWireGuardPresentation.noneText
        )
    }
}

public struct QuillWireGuardStyleSnapshot: Codable, Equatable, Sendable {
    public var windowBackgroundColor: String
    public var primaryTextColor: String
    public var secondaryTextColor: String
    public var dividerColor: String
    public var sidebarBackgroundColor: String
    public var selectedRowBackgroundColor: String
    public var selectedRowTextColor: String
    public var pressedButtonBackgroundColor: String
    public var focusBorderColor: String
    public var detailSectionBackgroundColor: String
    public var errorTextColor: String
    public var rootFontSize: Int
    public var captionFontSize: Int
    public var sidebarTitleFontSize: Int
    public var backendTitleFontSize: Int
    public var detailTitleFontSize: Int
    public var emptyStateTitleFontSize: Int
    public var listItemCornerRadius: Int
    public var importButtonCornerRadius: Int
    public var detailTitleCornerRadius: Int
    public var importButtonVerticalPadding: Int
    public var importButtonHorizontalPadding: Int
    public var detailSectionPadding: Int
    public var detailSectionTopMargin: Int
    public var sidebarWidth: Int
    public var sidebarMaximumWidth: Int
    public var sidebarPadding: Int
    public var sidebarBottomPadding: Int
    public var detailPadding: Int
    public var detailSpacing: Int
    public var importDialogWidth: Int
    public var importDialogHeight: Int

    private enum CodingKeys: String, CodingKey {
        case windowBackgroundColor
        case primaryTextColor
        case secondaryTextColor
        case dividerColor
        case sidebarBackgroundColor
        case selectedRowBackgroundColor
        case selectedRowTextColor
        case pressedButtonBackgroundColor
        case focusBorderColor
        case detailSectionBackgroundColor
        case errorTextColor
        case rootFontSize
        case captionFontSize
        case sidebarTitleFontSize
        case backendTitleFontSize
        case detailTitleFontSize
        case emptyStateTitleFontSize
        case listItemCornerRadius
        case importButtonCornerRadius
        case detailTitleCornerRadius
        case importButtonVerticalPadding
        case importButtonHorizontalPadding
        case detailSectionPadding
        case detailSectionTopMargin
        case sidebarWidth
        case sidebarMaximumWidth
        case sidebarPadding
        case sidebarBottomPadding
        case detailPadding
        case detailSpacing
        case importDialogWidth
        case importDialogHeight
    }

    public init(
        windowBackgroundColor: String = QuillWireGuardStyle.windowBackgroundColor,
        primaryTextColor: String = QuillWireGuardStyle.primaryTextColor,
        secondaryTextColor: String = QuillWireGuardStyle.secondaryTextColor,
        dividerColor: String = QuillWireGuardStyle.dividerColor,
        sidebarBackgroundColor: String = QuillWireGuardStyle.sidebarBackgroundColor,
        selectedRowBackgroundColor: String = QuillWireGuardStyle.selectedRowBackgroundColor,
        selectedRowTextColor: String = QuillWireGuardStyle.selectedRowTextColor,
        pressedButtonBackgroundColor: String = QuillWireGuardStyle.pressedButtonBackgroundColor,
        focusBorderColor: String = QuillWireGuardStyle.focusBorderColor,
        detailSectionBackgroundColor: String = QuillWireGuardStyle.detailSectionBackgroundColor,
        errorTextColor: String = QuillWireGuardStyle.errorTextColor,
        rootFontSize: Int = QuillWireGuardStyle.rootFontSize,
        captionFontSize: Int = QuillWireGuardStyle.captionFontSize,
        sidebarTitleFontSize: Int = QuillWireGuardStyle.sidebarTitleFontSize,
        backendTitleFontSize: Int = QuillWireGuardStyle.backendTitleFontSize,
        detailTitleFontSize: Int = QuillWireGuardStyle.detailTitleFontSize,
        emptyStateTitleFontSize: Int = QuillWireGuardStyle.emptyStateTitleFontSize,
        listItemCornerRadius: Int = QuillWireGuardStyle.listItemCornerRadius,
        importButtonCornerRadius: Int = QuillWireGuardStyle.importButtonCornerRadius,
        detailTitleCornerRadius: Int = QuillWireGuardStyle.detailTitleCornerRadius,
        importButtonVerticalPadding: Int = QuillWireGuardStyle.importButtonVerticalPadding,
        importButtonHorizontalPadding: Int = QuillWireGuardStyle.importButtonHorizontalPadding,
        detailSectionPadding: Int = QuillWireGuardStyle.detailSectionPadding,
        detailSectionTopMargin: Int = QuillWireGuardStyle.detailSectionTopMargin,
        sidebarWidth: Int = QuillWireGuardStyle.sidebarWidth,
        sidebarMaximumWidth: Int = QuillWireGuardStyle.sidebarMaximumWidth,
        sidebarPadding: Int = QuillWireGuardStyle.sidebarPadding,
        sidebarBottomPadding: Int = QuillWireGuardStyle.sidebarBottomPadding,
        detailPadding: Int = QuillWireGuardStyle.detailPadding,
        detailSpacing: Int = QuillWireGuardStyle.detailSpacing,
        importDialogWidth: Int = QuillWireGuardStyle.importDialogWidth,
        importDialogHeight: Int = QuillWireGuardStyle.importDialogHeight
    ) {
        self.windowBackgroundColor = windowBackgroundColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.dividerColor = dividerColor
        self.sidebarBackgroundColor = sidebarBackgroundColor
        self.selectedRowBackgroundColor = selectedRowBackgroundColor
        self.selectedRowTextColor = selectedRowTextColor
        self.pressedButtonBackgroundColor = pressedButtonBackgroundColor
        self.focusBorderColor = focusBorderColor
        self.detailSectionBackgroundColor = detailSectionBackgroundColor
        self.errorTextColor = errorTextColor
        self.rootFontSize = rootFontSize
        self.captionFontSize = captionFontSize
        self.sidebarTitleFontSize = sidebarTitleFontSize
        self.backendTitleFontSize = backendTitleFontSize
        self.detailTitleFontSize = detailTitleFontSize
        self.emptyStateTitleFontSize = emptyStateTitleFontSize
        self.listItemCornerRadius = listItemCornerRadius
        self.importButtonCornerRadius = importButtonCornerRadius
        self.detailTitleCornerRadius = detailTitleCornerRadius
        self.importButtonVerticalPadding = importButtonVerticalPadding
        self.importButtonHorizontalPadding = importButtonHorizontalPadding
        self.detailSectionPadding = detailSectionPadding
        self.detailSectionTopMargin = detailSectionTopMargin
        self.sidebarWidth = sidebarWidth
        self.sidebarMaximumWidth = sidebarMaximumWidth
        self.sidebarPadding = sidebarPadding
        self.sidebarBottomPadding = sidebarBottomPadding
        self.detailPadding = detailPadding
        self.detailSpacing = detailSpacing
        self.importDialogWidth = importDialogWidth
        self.importDialogHeight = importDialogHeight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            windowBackgroundColor: try container.decodeIfPresent(
                String.self,
                forKey: .windowBackgroundColor
            ) ?? QuillWireGuardStyle.windowBackgroundColor,
            primaryTextColor: try container.decodeIfPresent(String.self, forKey: .primaryTextColor)
                ?? QuillWireGuardStyle.primaryTextColor,
            secondaryTextColor: try container.decodeIfPresent(String.self, forKey: .secondaryTextColor)
                ?? QuillWireGuardStyle.secondaryTextColor,
            dividerColor: try container.decodeIfPresent(String.self, forKey: .dividerColor)
                ?? QuillWireGuardStyle.dividerColor,
            sidebarBackgroundColor: try container.decodeIfPresent(String.self, forKey: .sidebarBackgroundColor)
                ?? QuillWireGuardStyle.sidebarBackgroundColor,
            selectedRowBackgroundColor: try container.decodeIfPresent(
                String.self,
                forKey: .selectedRowBackgroundColor
            ) ?? QuillWireGuardStyle.selectedRowBackgroundColor,
            selectedRowTextColor: try container.decodeIfPresent(String.self, forKey: .selectedRowTextColor)
                ?? QuillWireGuardStyle.selectedRowTextColor,
            pressedButtonBackgroundColor: try container.decodeIfPresent(
                String.self,
                forKey: .pressedButtonBackgroundColor
            ) ?? QuillWireGuardStyle.pressedButtonBackgroundColor,
            focusBorderColor: try container.decodeIfPresent(String.self, forKey: .focusBorderColor)
                ?? QuillWireGuardStyle.focusBorderColor,
            detailSectionBackgroundColor: try container.decodeIfPresent(
                String.self,
                forKey: .detailSectionBackgroundColor
            ) ?? QuillWireGuardStyle.detailSectionBackgroundColor,
            errorTextColor: try container.decodeIfPresent(String.self, forKey: .errorTextColor)
                ?? QuillWireGuardStyle.errorTextColor,
            rootFontSize: try container.decodeIfPresent(Int.self, forKey: .rootFontSize)
                ?? QuillWireGuardStyle.rootFontSize,
            captionFontSize: try container.decodeIfPresent(Int.self, forKey: .captionFontSize)
                ?? QuillWireGuardStyle.captionFontSize,
            sidebarTitleFontSize: try container.decodeIfPresent(Int.self, forKey: .sidebarTitleFontSize)
                ?? QuillWireGuardStyle.sidebarTitleFontSize,
            backendTitleFontSize: try container.decodeIfPresent(Int.self, forKey: .backendTitleFontSize)
                ?? QuillWireGuardStyle.backendTitleFontSize,
            detailTitleFontSize: try container.decodeIfPresent(Int.self, forKey: .detailTitleFontSize)
                ?? QuillWireGuardStyle.detailTitleFontSize,
            emptyStateTitleFontSize: try container.decodeIfPresent(Int.self, forKey: .emptyStateTitleFontSize)
                ?? QuillWireGuardStyle.emptyStateTitleFontSize,
            listItemCornerRadius: try container.decodeIfPresent(Int.self, forKey: .listItemCornerRadius)
                ?? QuillWireGuardStyle.listItemCornerRadius,
            importButtonCornerRadius: try container.decodeIfPresent(Int.self, forKey: .importButtonCornerRadius)
                ?? QuillWireGuardStyle.importButtonCornerRadius,
            detailTitleCornerRadius: try container.decodeIfPresent(Int.self, forKey: .detailTitleCornerRadius)
                ?? QuillWireGuardStyle.detailTitleCornerRadius,
            importButtonVerticalPadding: try container.decodeIfPresent(Int.self, forKey: .importButtonVerticalPadding)
                ?? QuillWireGuardStyle.importButtonVerticalPadding,
            importButtonHorizontalPadding: try container.decodeIfPresent(
                Int.self,
                forKey: .importButtonHorizontalPadding
            ) ?? QuillWireGuardStyle.importButtonHorizontalPadding,
            detailSectionPadding: try container.decodeIfPresent(Int.self, forKey: .detailSectionPadding)
                ?? QuillWireGuardStyle.detailSectionPadding,
            detailSectionTopMargin: try container.decodeIfPresent(Int.self, forKey: .detailSectionTopMargin)
                ?? QuillWireGuardStyle.detailSectionTopMargin,
            sidebarWidth: try container.decodeIfPresent(Int.self, forKey: .sidebarWidth)
                ?? QuillWireGuardStyle.sidebarWidth,
            sidebarMaximumWidth: try container.decodeIfPresent(Int.self, forKey: .sidebarMaximumWidth)
                ?? QuillWireGuardStyle.sidebarMaximumWidth,
            sidebarPadding: try container.decodeIfPresent(Int.self, forKey: .sidebarPadding)
                ?? QuillWireGuardStyle.sidebarPadding,
            sidebarBottomPadding: try container.decodeIfPresent(Int.self, forKey: .sidebarBottomPadding)
                ?? QuillWireGuardStyle.sidebarBottomPadding,
            detailPadding: try container.decodeIfPresent(Int.self, forKey: .detailPadding)
                ?? QuillWireGuardStyle.detailPadding,
            detailSpacing: try container.decodeIfPresent(Int.self, forKey: .detailSpacing)
                ?? QuillWireGuardStyle.detailSpacing,
            importDialogWidth: try container.decodeIfPresent(Int.self, forKey: .importDialogWidth)
                ?? QuillWireGuardStyle.importDialogWidth,
            importDialogHeight: try container.decodeIfPresent(Int.self, forKey: .importDialogHeight)
                ?? QuillWireGuardStyle.importDialogHeight
        )
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
    public var style: QuillWireGuardStyleSnapshot
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
        case style
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
        style: QuillWireGuardStyleSnapshot = QuillWireGuardStyleSnapshot(),
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
        self.style = style
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
        self.style = try container.decodeIfPresent(
            QuillWireGuardStyleSnapshot.self,
            forKey: .style
        ) ?? QuillWireGuardStyleSnapshot()
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
