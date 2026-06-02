import Foundation

public enum QuillWireGuardConfigParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingInterface
    case missingInterfacePrivateKey
    case missingPeerPublicKey(index: Int)
    case invalidInteger(field: String, value: String, line: Int)
    case keyValueOutsideSection(line: Int, key: String)
    case malformedLine(line: Int, text: String)
    case unsupportedSection(line: Int, name: String)

    public var description: String {
        switch self {
        case .missingInterface:
            "WireGuard configuration is missing an [Interface] section."
        case .missingInterfacePrivateKey:
            "WireGuard configuration is missing Interface.PrivateKey."
        case let .missingPeerPublicKey(index):
            "WireGuard peer \(index) is missing PublicKey."
        case let .invalidInteger(field, value, line):
            "WireGuard \(field) value '\(value)' on line \(line) is not a valid UInt16."
        case let .keyValueOutsideSection(line, key):
            "WireGuard key '\(key)' on line \(line) appears before a section header."
        case let .malformedLine(line, text):
            "WireGuard line \(line) is not a key-value entry: \(text)"
        case let .unsupportedSection(line, name):
            "WireGuard section '\(name)' on line \(line) is not supported."
        }
    }
}

public enum QuillWireGuardConfigParser {
    public static func parse(
        _ configuration: String,
        id: String = "imported-tunnel",
        name: String = "Imported Tunnel",
        status: QuillWireGuardTunnelStatus = .inactive,
        interfacePublicKey: String = ""
    ) throws -> QuillWireGuardTunnel {
        var interface = InterfaceBuilder(publicKey: interfacePublicKey)
        var peers: [PeerBuilder] = []
        var section: Section?
        var hasInterface = false

        for (offset, rawLine) in configuration.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.isEmpty {
                continue
            }

            if let peerName = peerNameComment(from: trimmedLine), case let .peer(index) = section {
                peers[index].name = peerName
                continue
            }

            if isWholeLineComment(trimmedLine) {
                continue
            }

            let uncommentedLine = removingInlineComment(from: trimmedLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if uncommentedLine.isEmpty {
                continue
            }

            if uncommentedLine.hasPrefix("[") && uncommentedLine.hasSuffix("]") {
                let sectionName = String(uncommentedLine.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                switch sectionName {
                case "interface":
                    section = .interface
                    hasInterface = true
                case "peer":
                    peers.append(PeerBuilder(index: peers.count + 1))
                    section = .peer(peers.count - 1)
                default:
                    throw QuillWireGuardConfigParseError.unsupportedSection(
                        line: lineNumber,
                        name: sectionName
                    )
                }
                continue
            }

            guard let separator = uncommentedLine.firstIndex(of: "=") else {
                throw QuillWireGuardConfigParseError.malformedLine(line: lineNumber, text: trimmedLine)
            }

            let key = uncommentedLine[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = uncommentedLine[uncommentedLine.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty else {
                throw QuillWireGuardConfigParseError.malformedLine(line: lineNumber, text: trimmedLine)
            }

            switch section {
            case .interface:
                try applyInterfaceValue(
                    key: key,
                    value: value,
                    line: lineNumber,
                    interface: &interface
                )
            case let .peer(index):
                try applyPeerValue(key: key, value: value, line: lineNumber, peer: &peers[index])
            case nil:
                throw QuillWireGuardConfigParseError.keyValueOutsideSection(line: lineNumber, key: key)
            }
        }

        guard hasInterface else {
            throw QuillWireGuardConfigParseError.missingInterface
        }

        guard let privateKey = interface.privateKey, !privateKey.isEmpty else {
            throw QuillWireGuardConfigParseError.missingInterfacePrivateKey
        }

        return QuillWireGuardTunnel(
            id: id,
            name: name,
            status: status,
            interface: QuillWireGuardInterface(
                privateKey: privateKey,
                publicKey: interface.publicKey,
                addresses: interface.addresses,
                dnsServers: interface.dnsServers,
                listenPort: interface.listenPort,
                mtu: interface.mtu,
                extraConfigLines: interface.extraConfigLines
            ),
            peers: try peers.map { try $0.tunnelPeer(tunnelID: id) }
        )
    }

    private enum Section {
        case interface
        case peer(Int)
    }

    private struct InterfaceBuilder {
        var privateKey: String?
        var publicKey: String
        var addresses: [String] = []
        var dnsServers: [String] = []
        var listenPort: UInt16?
        var mtu: UInt16?
        var extraConfigLines: [String] = []
    }

    private struct PeerBuilder {
        var index: Int
        var name: String?
        var publicKey: String?
        var allowedIPs: [String] = []
        var endpoint: String?
        var persistentKeepAlive: UInt16?
        var preSharedKey: String?
        var extraConfigLines: [String] = []

        func tunnelPeer(tunnelID: String) throws -> QuillWireGuardPeer {
            guard let publicKey, !publicKey.isEmpty else {
                throw QuillWireGuardConfigParseError.missingPeerPublicKey(index: index)
            }

            return QuillWireGuardPeer(
                id: "\(tunnelID)-peer-\(index)",
                name: name ?? "Peer \(index)",
                publicKey: publicKey,
                allowedIPs: allowedIPs,
                endpoint: endpoint,
                persistentKeepAlive: persistentKeepAlive,
                preSharedKey: preSharedKey,
                extraConfigLines: extraConfigLines
            )
        }
    }

    private static func applyInterfaceValue(
        key: String,
        value: String,
        line: Int,
        interface: inout InterfaceBuilder
    ) throws {
        switch normalizedKey(key) {
        case "privatekey":
            interface.privateKey = value
        case "publickey":
            interface.publicKey = value
        case "address", "addresses":
            interface.addresses = commaSeparatedValues(value)
        case "dns":
            interface.dnsServers = commaSeparatedValues(value)
        case "listenport":
            interface.listenPort = try integerValue(field: key, value: value, line: line)
        case "mtu":
            interface.mtu = try integerValue(field: key, value: value, line: line)
        default:
            interface.extraConfigLines.append("\(key) = \(value)")
        }
    }

    private static func applyPeerValue(
        key: String,
        value: String,
        line: Int,
        peer: inout PeerBuilder
    ) throws {
        switch normalizedKey(key) {
        case "publickey":
            peer.publicKey = value
        case "allowedips":
            peer.allowedIPs = commaSeparatedValues(value)
        case "endpoint":
            peer.endpoint = value.isEmpty ? nil : value
        case "persistentkeepalive":
            peer.persistentKeepAlive = try integerValue(field: key, value: value, line: line)
        case "presharedkey":
            peer.preSharedKey = value.isEmpty ? nil : value
        default:
            peer.extraConfigLines.append("\(key) = \(value)")
        }
    }

    private static func normalizedKey(_ key: String) -> String {
        key.filter { !$0.isWhitespace }.lowercased()
    }

    private static func commaSeparatedValues(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func integerValue(field: String, value: String, line: Int) throws -> UInt16 {
        guard let integer = UInt16(value) else {
            throw QuillWireGuardConfigParseError.invalidInteger(field: field, value: value, line: line)
        }

        return integer
    }

    private static func peerNameComment(from line: String) -> String? {
        guard isWholeLineComment(line) else {
            return nil
        }

        let comment = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = comment.firstIndex(of: "=") else {
            return nil
        }

        let key = comment[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = comment[comment.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedKey(key) == "name", !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func isWholeLineComment(_ line: String) -> Bool {
        line.hasPrefix("#") || line.hasPrefix(";")
    }

    private static func removingInlineComment(from line: String) -> String {
        for marker in [" #", "\t#", " ;", "\t;"] {
            if let range = line.range(of: marker) {
                return String(line[..<range.lowerBound])
            }
        }

        return line
    }
}
