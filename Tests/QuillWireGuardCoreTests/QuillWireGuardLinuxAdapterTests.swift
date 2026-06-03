import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard Linux adapter + runtime controller")
struct QuillWireGuardLinuxAdapterTests {

    @Test("activate/deactivate default to systemd; wg-quick when requested")
    func activationCommands() {
        #expect(QuillWireGuardLinuxAdapter.activateCommand(interface: "wg0")
            == QuillWireGuardCommand(executable: "systemctl", arguments: ["start", "wg-quick@wg0"]))
        #expect(QuillWireGuardLinuxAdapter.deactivateCommand(interface: "wg0")
            == QuillWireGuardCommand(executable: "systemctl", arguments: ["stop", "wg-quick@wg0"]))
        #expect(QuillWireGuardLinuxAdapter.activateCommand(interface: "wg0", useSystemd: false)
            == QuillWireGuardCommand(executable: "wg-quick", arguments: ["up", "wg0"]))
        #expect(QuillWireGuardLinuxAdapter.deactivateCommand(interface: "wg0", useSystemd: false)
            == QuillWireGuardCommand(executable: "wg-quick", arguments: ["down", "wg0"]))
    }

    @Test("status dump command and configuration path")
    func statusAndPath() {
        #expect(QuillWireGuardLinuxAdapter.statusDumpCommand(interface: "wg0")
            == QuillWireGuardCommand(executable: "wg", arguments: ["show", "wg0", "dump"]))
        #expect(QuillWireGuardLinuxAdapter.configurationPath(interface: "wg0") == "/etc/wireguard/wg0.conf")
    }

    @Test("rejects invalid interface names (empty, traversal, metachars, too long)")
    func rejectsInvalidNames() {
        for name in ["", ".", "..", "a/b", "with space", "tunnel;rm", "x/../y", String(repeating: "x", count: 16)] {
            #expect(QuillWireGuardLinuxAdapter.isValidInterfaceName(name) == false, "should reject \(name)")
            #expect(QuillWireGuardLinuxAdapter.activateCommand(interface: name) == nil)
            #expect(QuillWireGuardLinuxAdapter.configurationPath(interface: name) == nil)
        }
        for name in ["wg0", "home-vpn", "corp_1", "a", String(repeating: "y", count: 15)] {
            #expect(QuillWireGuardLinuxAdapter.isValidInterfaceName(name) == true, "should accept \(name)")
        }
    }

    /// Records the commands it is asked to run and returns canned stdout.
    final class StubRunner: QuillWireGuardCommandRunner, @unchecked Sendable {
        let output: String
        var commands: [QuillWireGuardCommand] = []
        init(output: String = "") { self.output = output }
        func run(_ command: QuillWireGuardCommand) throws -> String {
            commands.append(command)
            return output
        }
    }

    @Test("controller activate/deactivate run the expected commands")
    func controllerActivation() throws {
        let runner = StubRunner()
        let controller = QuillWireGuardRuntimeController(runner: runner)
        try controller.activate(interface: "wg0")
        try controller.deactivate(interface: "wg0")
        #expect(runner.commands == [
            QuillWireGuardCommand(executable: "systemctl", arguments: ["start", "wg-quick@wg0"]),
            QuillWireGuardCommand(executable: "systemctl", arguments: ["stop", "wg-quick@wg0"]),
        ])
    }

    @Test("controller rejects an invalid interface name and runs nothing")
    func controllerRejectsInvalidName() {
        let runner = StubRunner()
        let controller = QuillWireGuardRuntimeController(runner: runner)
        #expect(throws: QuillWireGuardRuntimeError.invalidInterfaceName("bad/name")) {
            try controller.activate(interface: "bad/name")
        }
        #expect(runner.commands.isEmpty)
    }

    @Test("controller runs `wg show dump` and parses it via the slice-1 parser")
    func controllerParsesStatus() throws {
        let dump = "priv=\tpub=\t51820\toff\npeer=\t(none)\t1.2.3.4:51820\t0.0.0.0/0\t1717171717\t100\t200\t25"
        let runner = StubRunner(output: dump)
        let status = try QuillWireGuardRuntimeController(runner: runner).currentStatus(interface: "wg0")
        #expect(status?.peers.first?.rxBytes == 100)
        #expect(status?.peers.first?.txBytes == 200)
        #expect(runner.commands == [QuillWireGuardCommand(executable: "wg", arguments: ["show", "wg0", "dump"])])
    }

    @Test("process runner captures stdout from a real command")
    func processRunnerCapturesStdout() throws {
        let out = try QuillWireGuardProcessRunner().run(
            QuillWireGuardCommand(executable: "echo", arguments: ["hello", "world"])
        )
        #expect(out == "hello world\n")
    }

    @Test("process runner throws QuillWireGuardRuntimeError on a non-zero exit")
    func processRunnerThrowsOnFailure() {
        #expect(throws: QuillWireGuardRuntimeError.self) {
            try QuillWireGuardProcessRunner().run(
                QuillWireGuardCommand(executable: "false", arguments: [])
            )
        }
    }

    @Test("process runner feeds standardInput to the command's stdin")
    func processRunnerFeedsStdin() throws {
        // `cat` with no args echoes stdin to stdout, proving the pipe is wired.
        let out = try QuillWireGuardProcessRunner().run(
            QuillWireGuardCommand(executable: "cat", arguments: [], standardInput: "piped-key-data")
        )
        #expect(out == "piped-key-data")
    }
}
