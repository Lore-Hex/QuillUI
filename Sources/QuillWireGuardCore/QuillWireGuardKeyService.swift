import Foundation

#if canImport(WireGuardKit)
import WireGuardKit
#endif

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

    /// Generate a keypair in-process via the real upstream WireGuardKit (Curve25519
    /// in WireGuardKitC) — no `wg` CLI / process runner needed. Returns nil where
    /// WireGuardKit isn't linked (e.g. the native-Qt Linux graph), so callers can
    /// fall back to `generateKeyPair(runner:)`. Preferred when available.
    public static func generateKeyPairInProcess() -> KeyPair? {
        #if canImport(WireGuardKit)
        let privateKey = PrivateKey()
        return KeyPair(privateKey: privateKey.base64Key, publicKey: privateKey.publicKey.base64Key)
        #else
        return nil
        #endif
    }
}
