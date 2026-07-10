import Foundation
import Testing
import os

/// The `os` shim provides two `os_log` free-function overloads:
///   - type-first  `os_log(_ type:, log:, _ message:, _ args:)` — used by
///     xctest-dynamic-overlay's reporter.
///   - message-first `os_log(_ message:, log:, type:, _ args:)` — Apple's PRIMARY
///     form, used by real macOS source (WireGuard's Logger.swift etc.).
/// They must coexist unambiguously (the first positional parameter is a
/// StaticString vs an OSLogType). These tests are the compile-conformance proof
/// + a guard against a future ambiguity regression. They run on the Swift Linux
/// Backends job (the `os` shim is `#if os(Linux)`).
@Suite("os shim — os_log overloads coexist")
struct OSLogOverloadTests {
    @Test("Apple-signature message-first os_log(_:log:type:) compiles + runs")
    func messageFirst() {
        os_log("plain message", log: .default, type: .error)
        os_log("with arg: %{public}s", log: .default, type: .info, "value")
        os_log("uses log/type defaults")
        os_log("type only", type: .debug)
    }

    @Test("Existing type-first os_log(_:log:_:) still resolves (no ambiguity)")
    func typeFirstStillWorks() {
        os_log(.error, log: .default, "type-first form")
        os_log(.info, "type-first, default log")
    }

    @Test("OSLogType cases carry their label")
    func osLogTypeLabels() {
        #expect(OSLogType.error.label == "ERROR")
        #expect(OSLogType.info.label == "INFO")
        #expect(OSLogType.error.rawValue == 0x10)
        #expect(OSLogType(0x01) == .info)
        #expect(OSLogType(rawValue: 0x11) == .fault)
        #expect(OSLogType(label: "debug") == .debug)
    }
}
