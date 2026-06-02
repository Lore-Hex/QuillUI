import Foundation
import Testing
@testable import QuillWireGuardCore

@Suite("QuillWireGuard key service")
struct QuillWireGuardKeyServiceTests {

    /// Stub that returns canned output per `wg` subcommand and records the commands.
    final class ScriptedRunner: QuillWireGuardCommandRunner, @unchecked Sendable {
        var commands: [QuillWireGuardCommand] = []
        func run(_ command: QuillWireGuardCommand) throws -> String {
            commands.append(command)
            switch command.arguments {
            case ["genkey"]: return "PRIVATE_KEY_BASE64=\n"
            case ["pubkey"]: return "PUBLIC_KEY_BASE64=\n"
            default: return ""
            }
        }
    }

    @Test("generateKeyPair runs wg genkey then wg pubkey with the private key on stdin")
    func generatesKeyPair() throws {
        let runner = ScriptedRunner()

        let pair = try QuillWireGuardKeyService.generateKeyPair(runner: runner)

        #expect(pair.privateKey == "PRIVATE_KEY_BASE64=")  // trailing newline trimmed
        #expect(pair.publicKey == "PUBLIC_KEY_BASE64=")
        #expect(runner.commands.count == 2)
        #expect(runner.commands[0].executable == "wg" && runner.commands[0].arguments == ["genkey"])
        #expect(runner.commands[0].standardInput == nil)
        #expect(runner.commands[1].executable == "wg" && runner.commands[1].arguments == ["pubkey"])
        // The freshly generated private key is piped to `wg pubkey` via stdin.
        #expect(runner.commands[1].standardInput == "PRIVATE_KEY_BASE64=")
    }

    @Test("in-process keygen via the real WireGuardKit produces a valid base64 keypair")
    func inProcessKeygen() throws {
        guard let pair = QuillWireGuardKeyService.generateKeyPairInProcess() else {
            // WireGuardKit isn't linked in this graph (e.g. native-Qt) — nothing to assert.
            return
        }
        // base64 of a 32-byte key is 44 chars ("=" padded).
        #expect(pair.privateKey.count == 44)
        #expect(pair.publicKey.count == 44)
        #expect(pair.privateKey != pair.publicKey)
        // Round-trips through WireGuardKit's own base64 parser.
        #expect(Data(base64Encoded: pair.privateKey)?.count == 32)
        // Each call is a fresh random key.
        #expect(QuillWireGuardKeyService.generateKeyPairInProcess()?.privateKey != pair.privateKey)
    }
}
