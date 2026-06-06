#if os(Linux)
import Foundation

// Compile-faithful Linux stub for the WireGuardKitGo cgo bridge — the Go tunnel engine
// (wireguard-go) exposed to Swift on Apple platforms. The Go library isn't built for the
// Linux conformance, and WireGuardAdapter only ever runs inside the macOS/iOS
// PacketTunnelProvider, so these functions never execute on Linux. They exist purely so
// WireGuard's WireGuardAdapter.swift recompiles unmodified against the Linux stack.
//
// Signatures mirror the cgo-exported C API (char*/handle/logger-callback). Call sites in
// WireGuardAdapter pass Swift Strings (implicitly bridged to `const char *`) and read
// results via `String(cString:)`.

/// wireguard-go version string (caller does `String(cString:)`); nil → "unknown".
public func wgVersion() -> UnsafeMutablePointer<CChar>? { nil }

/// Start the tunnel over `tunFd`, returning a device handle (>= 0) or a negative error.
public func wgTurnOn(_ settings: UnsafePointer<CChar>?, _ tunFd: Int32) -> Int32 { -1 }

/// Stop the device identified by `handle`.
public func wgTurnOff(_ handle: Int32) {}

/// Current UAPI configuration for `handle` (caller does `String(cString:)`).
public func wgGetConfig(_ handle: Int32) -> UnsafeMutablePointer<CChar>? { nil }

/// Apply a UAPI configuration to `handle`; returns 0 on success, negative on error.
@discardableResult
public func wgSetConfig(_ handle: Int32, _ settings: UnsafePointer<CChar>?) -> Int64 { -1 }

/// Re-bind the device's sockets (roaming / network-change handling).
public func wgBumpSockets(_ handle: Int32) {}

/// Disable a roaming workaround needed only on some mobile networks.
public func wgDisableSomeRoamingForBrokenMobileSemantics(_ handle: Int32) {}

/// Install the logging callback (context + a C function pointer). `wgSetLogger(nil, nil)` clears it.
public func wgSetLogger(_ context: UnsafeMutableRawPointer?,
                        _ logger: (@convention(c) (UnsafeMutableRawPointer?, Int32, UnsafePointer<CChar>?) -> Void)?) {}
#endif
