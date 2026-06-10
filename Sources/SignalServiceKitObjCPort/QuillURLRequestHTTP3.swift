//
// QuillURLRequestHTTP3.swift -- SignalServiceKitObjCPort (Linux/signal-only).
//
// Darwin's URLRequest exposes `assumesHTTP3Capable`, a hint that lets URLSession
// attempt HTTP/3 (QUIC). swift-corelibs-foundation's URLRequest has no such
// property and its URLSession does not implement HTTP/3 negotiation, so there is
// nothing to honor on Linux. Honest inert stand-in so OWSUrlSession compiles:
// getter reports false, setter is a no-op.
//
#if os(Linux)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension URLRequest {
    var assumesHTTP3Capable: Bool {
        get { false }
        set { _ = newValue }
    }
}
#endif
