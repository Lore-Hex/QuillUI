import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard activation service")
struct QuillWireGuardActivationTests {

    /// A runner that records the commands issued (and returns canned output), so
    /// activate/deactivate can be asserted without touching the real network stack.
    final class RecordingRunner: QuillWireGuardCommandRunner, @unchecked Sendable {
        var commands: [QuillWireGuardCommand] = []
        let output: String
        init(output: String = "") { self.output = output }
        func run(_ command: QuillWireGuardCommand) throws -> String {
            commands.append(command)
            return output
        }
    }

    private func tempDir() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wg-activation-\(UUID().uuidString)").path
    }

    private var fixture: QuillWireGuardTunnel {
        QuillWireGuardFixtures.tunnels.first(where: { !$0.peers.isEmpty })
            ?? QuillWireGuardFixtures.tunnels[0]
    }

    @Test("installer writes the wg-quick config 0600 at <iface>.conf")
    func installerWritesConfig() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let tunnel = fixture

        let path = try QuillWireGuardConfigInstaller.install(tunnel: tunnel, directory: dir)

        let written = try String(contentsOfFile: path, encoding: .utf8)
        #expect(written == tunnel.wgQuickConfig())
        let perms = try (FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
        let iface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: tunnel.name)
        #expect(path.hasSuffix("/\(iface).conf"))
    }

    @Test("activate installs the config then brings the interface up")
    func activateInstallsAndUps() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let runner = RecordingRunner()
        let controller = QuillWireGuardRuntimeController(runner: runner)
        let tunnel = fixture

        try QuillWireGuardActivationService.activate(tunnel: tunnel, controller: controller, directory: dir)

        let iface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: tunnel.name)
        #expect(FileManager.default.fileExists(atPath: "\(dir)/\(iface).conf"))
        #expect(runner.commands.count == 1)
        #expect(runner.commands.last?.arguments.contains("start") == true)
        #expect(runner.commands.last?.arguments.contains("wg-quick@\(iface)") == true)
    }

    @Test("deactivate brings the interface down without writing config")
    func deactivateDowns() throws {
        let runner = RecordingRunner()
        let controller = QuillWireGuardRuntimeController(runner: runner)
        let name = fixture.name

        try QuillWireGuardActivationService.deactivate(tunnelNamed: name, controller: controller)

        let iface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: name)
        #expect(runner.commands.count == 1)
        #expect(runner.commands.last?.arguments.contains("stop") == true)
        #expect(runner.commands.last?.arguments.contains("wg-quick@\(iface)") == true)
    }

    @Test("remove deletes the installed config and attempts deactivate")
    func removeDeletesConfig() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let runner = RecordingRunner()
        let controller = QuillWireGuardRuntimeController(runner: runner)
        let tunnel = fixture

        let path = try QuillWireGuardConfigInstaller.install(tunnel: tunnel, directory: dir)
        #expect(FileManager.default.fileExists(atPath: path))

        try QuillWireGuardActivationService.remove(tunnelNamed: tunnel.name, controller: controller, directory: dir)

        #expect(!FileManager.default.fileExists(atPath: path))  // config removed
        let iface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: tunnel.name)
        #expect(runner.commands.contains { $0.arguments.contains("stop") && $0.arguments.contains("wg-quick@\(iface)") })
    }

    @Test("remove is idempotent when no config exists")
    func removeIdempotentWhenAbsent() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let controller = QuillWireGuardRuntimeController(runner: RecordingRunner())
        // No install — removing a tunnel with no on-disk config must not throw.
        try QuillWireGuardActivationService.remove(tunnelNamed: "ghost", controller: controller, directory: dir)
        let iface = QuillWireGuardLiveStatusService.interfaceName(forTunnelNamed: "ghost")
        #expect(!FileManager.default.fileExists(atPath: "\(dir)/\(iface).conf"))
    }
}
