import Foundation

/// Generates WireGuard keypairs on Linux via the `wg` CLI — the equivalent of the
/// macOS app's WireGuardKit `Curve25519` key generation, so the Linux app can
/// create a brand-new tunnel from scratch (not only import an existing config).
/// `wg genkey` emits a private key; `wg pubkey` derives the public key from the
/// private key fed on stdin. Pure given a runner, so it is unit-testable with a
/// stub and VM-demonstrable with the real `QuillWireGuardProcessRunner`.
public enum QuillWireGuardKeyService {
    public struct KeyPair: Equatable, Sendable {
        public let privateKey: String
        public let publicKey: String
        public init(privateKey: String, publicKey: String) {
            self.privateKey = privateKey
            self.publicKey = publicKey
        }
    }

    /// Generate a fresh Curve25519 keypair: `wg genkey` then `wg pubkey` (private
    /// key on stdin). Both outputs are trimmed of the trailing newline.
    public static func generateKeyPair<Runner: QuillWireGuardCommandRunner>(
        runner: Runner
    ) throws -> KeyPair {
        let privateKey = try runner
            .run(QuillWireGuardCommand(executable: "wg", arguments: ["genkey"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let publicKey = try runner
            .run(QuillWireGuardCommand(executable: "wg", arguments: ["pubkey"], standardInput: privateKey))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return KeyPair(privateKey: privateKey, publicKey: publicKey)
    }
}
