//
// QuillUI Linux shim: `CryptoKit` → swift-crypto's `Crypto`.
//
// swift-crypto is Apple's own, API-compatible reimplementation of CryptoKit
// (SHA2 hashing, HMAC, AES.GCM, ChaChaPoly, Curve25519, P256/P384/P521,
// SymmetricKey, HKDF, …). Re-exporting it under the canonical module name
// `CryptoKit` lets upstream Apple code `import CryptoKit` resolve unchanged on
// Linux — SPM maps the swiftmodule filename from the target name (`CryptoKit`).
//
// Driven by Signal's SignalServiceKit, which imports CryptoKit in MasterKey and
// ~26 other files. If Signal (or other flagships) reach for a CryptoKit symbol
// swift-crypto lacks, add a focused supplement here.
//
@_exported import Crypto
