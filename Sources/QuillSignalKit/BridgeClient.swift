//
// QuillSignalKit — Swift client for the quill-signal-bridge daemon.
//
// The bridge is a small Rust process that wraps presage/libsignal (the real
// Signal protocol engine) and exposes it over a unix socket with a line-
// delimited-JSON protocol. This client is how the QuillUI Signal app talks to
// it. Raw Glibc/Darwin sockets — cross-platform, Foundation-only, no QuillUI
// dependency so it can be reused/tested standalone.
//
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public enum BridgeError: Error { case socket, connect(Int32), badPath }

/// One JSON line from the bridge — either a {ok,cmd,msg} response or a {event,...} event.
public struct BridgeMessage: Codable, Sendable {
    public let ok: Bool?
    public let cmd: String?
    public let msg: String?
    public let event: String?
    public let url: String?
    public let qr: String?
}

/// Minimal unix-socket client for quill-signal-bridge's line-delimited-JSON protocol.
public final class BridgeClient {
    private let path: String
    public init(path: String) { self.path = path }

    /// Default socket path the bridge daemon listens on.
    public static let defaultSocketPath = "/tmp/quill-signal-bridge.sock"

    private func makeSocket() -> Int32 {
        #if canImport(Glibc)
        return socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        return socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
    }

    private func openConnection() throws -> Int32 {
        let fd = makeSocket()
        guard fd >= 0 else { throw BridgeError.socket }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < cap else { close(fd); throw BridgeError.badPath }
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: cap) { c in
                for (i, b) in bytes.enumerated() { c[i] = CChar(bitPattern: b) }
                c[bytes.count] = 0
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard rc == 0 else { let e = errno; close(fd); throw BridgeError.connect(e) }
        return fd
    }

    /// Open the connection and return the fd; caller reads lines + closes.
    public func open() throws -> Int32 { try openConnection() }

    /// Write one command line (newline appended) to an open fd.
    public func send(_ line: String, on fd: Int32) {
        var out = line
        if !out.hasSuffix("\n") { out += "\n" }
        out.withCString { _ = write(fd, $0, strlen($0)) }
    }

    /// Read one '\n'-terminated line from an open fd (nil on EOF).
    public func readLine(on fd: Int32) -> String? {
        var buf = [UInt8]()
        var byte: UInt8 = 0
        while true {
            let n = read(fd, &byte, 1)
            if n <= 0 { return buf.isEmpty ? nil : String(decoding: buf, as: UTF8.self) }
            if byte == 0x0A { break }
            buf.append(byte)
        }
        return String(decoding: buf, as: UTF8.self)
    }

    /// Convenience: one command -> first response line.
    public func request(_ line: String) throws -> String {
        let fd = try openConnection()
        defer { close(fd) }
        send(line, on: fd)
        return readLine(on: fd) ?? ""
    }

    public func command(_ cmd: String) throws -> String { try request("{\"cmd\":\"\(cmd)\"}") }

    public func decode(_ s: String) -> BridgeMessage? {
        guard let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BridgeMessage.self, from: d)
    }

    /// Send one command, then stream every response/event line to `onLine` until it returns false,
    /// EOF, or a socket read-timeout (timeoutSeconds > 0).
    public func stream(_ line: String, timeoutSeconds: Int = 0, onLine: (String) -> Bool) throws {
        let fd = try openConnection()
        defer { close(fd) }
        if timeoutSeconds > 0 {
            var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }
        send(line, on: fd)
        while let l = readLine(on: fd) {
            if !onLine(l) { break }
        }
    }
}
