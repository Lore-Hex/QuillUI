import Foundation

/// Writes a tunnel's wg-quick configuration to disk so `wg-quick` / the systemd
/// `wg-quick@<iface>` unit can bring it up. wg-quick requires the file to live at
/// `<directory>/<interface>.conf` and refuses configs that are group/world
/// readable, so the file is written 0600 (and the directory created 0700).
public enum QuillWireGuardConfigInstaller {
    /// The standard wg-quick / systemd configuration directory.
    public static let defaultDirectory = "/etc/wireguard"

    /// The on-disk path wg-quick expects for a tunnel's derived interface.
    public static func configPath(
        forInterface interface: String,
        directory: String = defaultDirectory
    ) -> String {
        "\(directory)/\(interface).conf"
    }

    /// Write `tunnel.wgQuickConfig()` to `<directory>/<interface>.conf` (0600),
    /// creating the directory (0700) if needed. Returns the written path.
    @discardableResult
    public static func install(
        tunnel: QuillWireGuardTunnel,
        directory: String = defaultDirectory,
        fileManager: FileManager = .default
    ) throws -> String {
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let interface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: tunnel.name)
        let path = configPath(forInterface: interface, directory: directory)
        try Data(tunnel.wgQuickConfig().utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        return path
    }
}

/// Activate / deactivate a tunnel by name — the seam the live UI's connect toggle
/// calls. `activate` installs the config then brings the interface up via the
/// runtime controller; `deactivate` brings it down. Pure given a controller (and,
/// for activate, a directory), so it is unit-testable with a recording runner + a
/// temp dir, and VM-demonstrable end-to-end with the real process runner.
public enum QuillWireGuardActivationService {
    /// Install the tunnel's config and bring its interface up.
    public static func activate<Runner: QuillWireGuardCommandRunner>(
        tunnel: QuillWireGuardTunnel,
        controller: QuillWireGuardRuntimeController<Runner>,
        directory: String = QuillWireGuardConfigInstaller.defaultDirectory,
        fileManager: FileManager = .default
    ) throws {
        _ = try QuillWireGuardConfigInstaller.install(
            tunnel: tunnel, directory: directory, fileManager: fileManager
        )
        try controller.activate(
            interface: QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: tunnel.name)
        )
    }

    /// Bring the named tunnel's interface down (no config write needed).
    public static func deactivate<Runner: QuillWireGuardCommandRunner>(
        tunnelNamed name: String,
        controller: QuillWireGuardRuntimeController<Runner>
    ) throws {
        try controller.deactivate(
            interface: QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: name)
        )
    }

    /// Remove a tunnel: bring it down (best-effort — it may already be down, or
    /// deactivation may need root we lack) then delete its on-disk wg-quick config.
    /// Deleting a config that isn't there is a no-op, so this is idempotent. The
    /// deactivate is best-effort so a "forget" still succeeds on a tunnel that was
    /// never up; callers needing a guaranteed teardown should `deactivate` first.
    public static func remove<Runner: QuillWireGuardCommandRunner>(
        tunnelNamed name: String,
        controller: QuillWireGuardRuntimeController<Runner>,
        directory: String = QuillWireGuardConfigInstaller.defaultDirectory,
        fileManager: FileManager = .default
    ) throws {
        try? deactivate(tunnelNamed: name, controller: controller)
        let interface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: name)
        let path = QuillWireGuardConfigInstaller.configPath(forInterface: interface, directory: directory)
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }
}
