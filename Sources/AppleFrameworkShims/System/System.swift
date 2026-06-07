//
// QuillUI Linux shim for `System` (apple/swift-system). swift-system is not a
// package dep here, so this provides the FileDescriptor / FilePath surface SSK's
// Cryptography (streaming attachment AES-CBC over a file) uses. Unlike most
// shims this is FAITHFUL, not inert: it is a thin wrapper over the POSIX
// open/lseek/read/close, so the file I/O actually works on Linux. Part of the
// Signal-iOS -> QuillOS port.
//
import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Minimal stand-in for swift-system's Errno (callers only need it to be an Error).
public struct Errno: Error, Equatable, RawRepresentable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static var current: Errno {
        #if canImport(Glibc)
        return Errno(rawValue: errno)
        #else
        return Errno(rawValue: -1)
        #endif
    }
}

public struct FilePath {
    public var string: String
    public init(_ string: String) { self.string = string }
    /// Failable URL init (SSK: FilePath(url)); only file URLs map to a path.
    public init?(_ url: URL) {
        guard url.isFileURL else { return nil }
        self.string = url.path
    }
    public var description: String { string }
}

public struct FileDescriptor {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }

    public struct AccessMode: RawRepresentable, Equatable, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }
        #if canImport(Glibc)
        public static let readOnly = AccessMode(rawValue: O_RDONLY)
        public static let writeOnly = AccessMode(rawValue: O_WRONLY)
        public static let readWrite = AccessMode(rawValue: O_RDWR)
        #else
        public static let readOnly = AccessMode(rawValue: 0)
        public static let writeOnly = AccessMode(rawValue: 1)
        public static let readWrite = AccessMode(rawValue: 2)
        #endif
    }

    public enum SeekOrigin: Sendable {
        case start, current, end
        fileprivate var whence: Int32 {
            #if canImport(Glibc)
            switch self {
            case .start: return SEEK_SET
            case .current: return SEEK_CUR
            case .end: return SEEK_END
            }
            #else
            switch self { case .start: return 0; case .current: return 1; case .end: return 2 }
            #endif
        }
    }

    public static func open(_ path: FilePath, _ mode: AccessMode) throws -> FileDescriptor {
        #if canImport(Glibc)
        let fd = Glibc.open(path.string, mode.rawValue)
        guard fd >= 0 else { throw Errno.current }
        return FileDescriptor(rawValue: fd)
        #else
        throw Errno(rawValue: -1)
        #endif
    }

    @discardableResult
    public func seek(offset: Int64, from: SeekOrigin) throws -> Int64 {
        #if canImport(Glibc)
        let result = lseek(rawValue, off_t(offset), from.whence)
        guard result >= 0 else { throw Errno.current }
        return Int64(result)
        #else
        throw Errno(rawValue: -1)
        #endif
    }

    @discardableResult
    public func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        #if canImport(Glibc)
        guard let base = buffer.baseAddress, buffer.count > 0 else { return 0 }
        let n = Glibc.read(rawValue, base, buffer.count)
        guard n >= 0 else { throw Errno.current }
        return n
        #else
        return 0
        #endif
    }

    public func close() throws {
        #if canImport(Glibc)
        _ = Glibc.close(rawValue)
        #endif
    }
}
