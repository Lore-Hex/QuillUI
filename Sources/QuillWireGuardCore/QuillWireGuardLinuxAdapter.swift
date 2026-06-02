import Foundation

/// A command to execute, as argv (program + arguments). Pure data — building it
/// needs no privileges, so it is fully unit-testable; running it needs root and is
/// the one piece deferred to a later slice. argv (never a shell string) means the
/// interface name can't be shell-injected.
public struct QuillWireGuardCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum QuillWireGuardRuntimeError: Error, Equatable, Sendable {
    case invalidInterfaceName(String)
}

/// Builds the `wg-quick` / `wg` / `systemctl` commands that manage a WireGuard
/// interface on Debian/Armbian-based QuillOS (systemd + the `wireguard-tools`
/// package, configs under `/etc/wireguard`). Scoped to that target per maintainer
/// guidance, so there is no cross-distro / init-system abstraction.
public enum QuillWireGuardLinuxAdapter {
    public static let configurationDirectory = "/etc/wireguard"

    /// Kernel/wg-quick interface-name rule: 1–15 chars from `[A-Za-z0-9_=+.-]`, and
    /// not `.`/`..`. Rejecting anything else blocks path traversal in
    /// `configurationPath` and keeps the name a single safe argv token.
    public static func isValidInterfaceName(_ name: String) -> Bool {
        guard (1...15).contains(name.count), name != ".", name != ".." else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_=+.-")
        return name.allSatisfy(allowed.contains)
    }

    public static func configurationPath(interface: String) -> String? {
        guard isValidInterfaceName(interface) else { return nil }
        return "\(configurationDirectory)/\(interface).conf"
    }

    /// Bring the tunnel up. Defaults to the systemd unit (`wg-quick@<iface>`), which
    /// is how QuillOS manages persistent tunnels; `useSystemd: false` calls
    /// `wg-quick up` directly. Returns nil for an invalid interface name.
    public static func activateCommand(interface: String, useSystemd: Bool = true) -> QuillWireGuardCommand? {
        guard isValidInterfaceName(interface) else { return nil }
        return useSystemd
            ? QuillWireGuardCommand(executable: "systemctl", arguments: ["start", "wg-quick@\(interface)"])
            : QuillWireGuardCommand(executable: "wg-quick", arguments: ["up", interface])
    }

    public static func deactivateCommand(interface: String, useSystemd: Bool = true) -> QuillWireGuardCommand? {
        guard isValidInterfaceName(interface) else { return nil }
        return useSystemd
            ? QuillWireGuardCommand(executable: "systemctl", arguments: ["stop", "wg-quick@\(interface)"])
            : QuillWireGuardCommand(executable: "wg-quick", arguments: ["down", interface])
    }

    /// `wg show <iface> dump` — the stable status format consumed by
    /// `QuillWireGuardStatusParser`.
    public static func statusDumpCommand(interface: String) -> QuillWireGuardCommand? {
        guard isValidInterfaceName(interface) else { return nil }
        return QuillWireGuardCommand(executable: "wg", arguments: ["show", interface, "dump"])
    }
}

/// Executes a `QuillWireGuardCommand` and returns its stdout. The real
/// implementation (Foundation.Process) lands in a later slice; orchestration is
/// generic over this seam so it is testable with a stub runner.
public protocol QuillWireGuardCommandRunner: Sendable {
    func run(_ command: QuillWireGuardCommand) throws -> String
}

/// Orchestrates tunnel activation on the Linux WireGuard runtime: builds the right
/// command and runs it via the injected runner. Fully unit-testable with a stub
/// runner; only the real process execution is deferred. Reading live status
/// (`wg show dump` -> QuillWireGuardStatusParser) joins this with the parser slice
/// in a follow-up.
public struct QuillWireGuardRuntimeController<Runner: QuillWireGuardCommandRunner>: Sendable {
    private let runner: Runner
    private let useSystemd: Bool

    public init(runner: Runner, useSystemd: Bool = true) {
        self.runner = runner
        self.useSystemd = useSystemd
    }

    public func activate(interface: String) throws {
        _ = try runner.run(try require(QuillWireGuardLinuxAdapter.activateCommand(interface: interface, useSystemd: useSystemd), interface))
    }

    public func deactivate(interface: String) throws {
        _ = try runner.run(try require(QuillWireGuardLinuxAdapter.deactivateCommand(interface: interface, useSystemd: useSystemd), interface))
    }

    private func require(_ command: QuillWireGuardCommand?, _ interface: String) throws -> QuillWireGuardCommand {
        guard let command else { throw QuillWireGuardRuntimeError.invalidInterfaceName(interface) }
        return command
    }
}
