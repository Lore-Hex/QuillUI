import Foundation

/// Loads WireGuard tunnels from on-disk wg-quick configs — the inverse of
/// `QuillWireGuardConfigInstaller`. Scans `<directory>/*.conf`, parses each via
/// `QuillWireGuardConfigParser`, and names the tunnel after the file (which is the
/// wg interface name). This is how the live app shows the device's *real* tunnels
/// instead of the bundled fixtures.
public enum QuillWireGuardConfigLoader {
    /// The standard wg-quick / systemd configuration directory.
    public static let defaultDirectory = QuillWireGuardLinuxAdapter.configurationDirectory

    /// One config file that failed to parse — kept so the UI can surface it
    /// without dropping the whole load.
    public struct LoadFailure: Equatable, Sendable {
        public let path: String
        public let message: String
        public init(path: String, message: String) {
            self.path = path
            self.message = message
        }
    }

    public struct LoadResult: Equatable, Sendable {
        public let tunnels: [QuillWireGuardTunnel]
        public let failures: [LoadFailure]
        public init(tunnels: [QuillWireGuardTunnel], failures: [LoadFailure]) {
            self.tunnels = tunnels
            self.failures = failures
        }
    }

    /// Load + parse every `*.conf` in `directory`, in filename order. A missing
    /// directory yields an empty result (no tunnels configured yet). Per-file
    /// parse errors are collected into `failures`, never thrown, so one bad config
    /// doesn't hide the rest.
    public static func load(
        directory: String = defaultDirectory,
        fileManager: FileManager = .default
    ) -> LoadResult {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return LoadResult(tunnels: [], failures: [])
        }

        var tunnels: [QuillWireGuardTunnel] = []
        var failures: [LoadFailure] = []
        for file in entries.sorted() where file.hasSuffix(".conf") {
            let interface = String(file.dropLast(".conf".count))
            guard !interface.isEmpty else { continue }
            let path = "\(directory)/\(file)"
            do {
                let contents = try String(contentsOfFile: path, encoding: .utf8)
                tunnels.append(try QuillWireGuardConfigParser.parse(contents, id: interface, name: interface))
            } catch {
                failures.append(LoadFailure(path: path, message: "\(error)"))
            }
        }
        return LoadResult(tunnels: tunnels, failures: failures)
    }
}
