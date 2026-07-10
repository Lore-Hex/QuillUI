# Changelog

All notable changes to this SDK are documented here. Format roughly follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is
[Semantic Versioning](https://semver.org/).

## 0.4.0 — 2026-05-10

### Added
- Strongly-typed `ChatMessage` with `.user(_:)` / `.assistant(_:)` /
  `.system(_:)` / `.tool(callId:content:)` conveniences.
- `[ChatMessage]` overloads for `chatCompletions(...)` and
  `chatCompletionsChunks(...)`, so call sites don't have to drop down to
  `[[String: Any]]` for typed conversations.
- Streaming endpoints now drain the response body when the HTTP status is
  ≥ 400 and surface it through the regular `TrustedRouterError`
  classifier — the server's actual message reaches the caller instead of
  a generic "Error in stream response".
- `DER` namespace: extracted PKCS#1 RSAPublicKey assembly out of
  `Attestation.swift` into its own file with unit tests. The signature
  verification path is unchanged on the wire.
- User-Agent now reports the host OS and version
  (e.g. `trusted-router-swift/0.4.0 (macOS 26.4)`).
- Comprehensive test suite: 6 tests → **67 tests** (55 new in this
  release, 6 added in 0.3.3). Coverage now includes
  every status-code classification path, retry-after honoring, retry
  exhaustion, every Codable model (snake_case ↔ camelCase), every SSE
  parser frame-boundary form (LF-LF and CRLF-CRLF), the multi-byte UTF-8
  byte-split-boundary regression (fixed in 0.3.2), the `[DONE]` sentinel,
  DER encoding edge cases (leading-zero strip, high-bit padding,
  short/long-form length), and a real JWT signed-then-verified round-trip
  plus a tampered-signature rejection test.

### Changed
- `TrustedRouterConstants` is now an `enum` (uninstantiable namespace)
  rather than a `struct`.
- Trailing-slash stripping in the constructor uses a clearer loop instead
  of a no-op regex.
- DocC comments added to all top-level public types.

### Fixed
- Nothing functional in this release; 0.3.2 fixed the UTF-8 byte-drop and
  the missing-RSA-verify gaps.

## 0.3.3 — earlier

### Added
- More endpoint coverage in `TrustedRouterEndpointTests` (providers,
  credits, billing, broadcast destinations); `nonisolated(unsafe)`
  annotations on the mock-protocol storage; `SimpleAsyncBytes` helper.

## 0.3.2

### Fixed
- SSE parser dropped multi-byte UTF-8 characters that crossed network-
  buffer boundaries; switched to byte-buffered framing with decode at
  frame boundary.
- `verifyGatewayAttestation` now actually verifies the JWT signature via
  `SecKeyVerifySignature` with a hand-rolled PKCS#1 DER assembly from
  the JWK's n/e parameters.

## 0.3.1

### Changed
- Typed `Decodable` response models replaced `[String: Any]` returns.
- `iterSseEvents` got a generic typed variant.

## 0.3.0

### Added
- Initial implementation: endpoints, streaming, attestation scaffold,
  Confidential Space JWT support.
