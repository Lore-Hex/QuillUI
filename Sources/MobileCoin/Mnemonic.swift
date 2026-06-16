// MobileCoin SDK mnemonic surface -- SignalUI's Payments/MobileCoinAPI.swift
// converts payments entropy <-> recovery passphrases via
// `Mnemonic.mnemonic(fromEntropy:)` / `Mnemonic.entropy(fromMnemonic:)` and
// validates passphrase words via `Mnemonic.words(matchingPrefix:)`.
//
// Inert on Linux: the real SDK implements BIP-39 over the English wordlist.
// The shim has no wordlist or crypto; it uses a deterministic, reversible
// hex-group encoding (4 hex chars per "word") purely so that the
// entropy -> mnemonic -> entropy round trip that SignalUI relies on holds.
// The output is NOT a BIP-39 phrase and is never interchangeable with one.

import Foundation

public enum Mnemonic {
    public static func mnemonic(fromEntropy entropy: Data) -> Result<String, InvalidInputError> {
        guard !entropy.isEmpty else {
            return .failure(InvalidInputError("entropy must not be empty"))
        }
        let hex = entropy.map { String(format: "%02x", $0) }.joined()
        // Group into 4-char pseudo-words ("a3f0 19bc ..."), reversible below.
        var words: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 4, limitedBy: hex.endIndex) ?? hex.endIndex
            words.append(String(hex[index..<end]))
            index = end
        }
        return .success(words.joined(separator: " "))
    }

    public static func entropy(fromMnemonic mnemonic: String) -> Result<Data, InvalidInputError> {
        let hex = mnemonic.split(separator: " ").joined()
        guard !hex.isEmpty, hex.count % 2 == 0 else {
            return .failure(InvalidInputError("invalid mnemonic"))
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                return .failure(InvalidInputError("invalid mnemonic"))
            }
            bytes.append(byte)
            index = next
        }
        return .success(Data(bytes))
    }

    /// Real SDK: prefix search over the BIP-39 wordlist. The shim has no
    /// wordlist, so no word ever validates (SignalUI treats this as "invalid
    /// passphrase word", which is the conservative answer on Linux).
    public static func words(matchingPrefix prefix: String) -> [String] {
        []
    }
}
