@_exported import Foundation

#if canImport(os)
import os
#endif

public struct Logger: Sendable {
    public init(subsystem: String, category: String) {}
    
    public func debug(_ message: String) { print("DEBUG: \(message)") }
    public func info(_ message: String) { print("INFO: \(message)") }
    public func warning(_ message: String) { print("WARNING: \(message)") }
    public func error(_ message: String) { print("ERROR: \(message)") }
    public func fault(_ message: String) { print("FAULT: \(message)") }
    public func critical(_ message: String) { print("CRITICAL: \(message)") }
    
    public func debug(_ message: Any) { print("DEBUG: \(message)") }
    public func info(_ message: Any) { print("INFO: \(message)") }
    public func warning(_ message: Any) { print("WARNING: \(message)") }
    public func error(_ message: Any) { print("ERROR: \(message)") }
    public func fault(_ message: Any) { print("FAULT: \(message)") }
    public func critical(_ message: Any) { print("CRITICAL: \(message)") }

    public func debug(_ message: OSLogMessage) { print("DEBUG: \(message.value)") }
    public func info(_ message: OSLogMessage) { print("INFO: \(message.value)") }
    public func warning(_ message: OSLogMessage) { print("WARNING: \(message.value)") }
    public func error(_ message: OSLogMessage) { print("ERROR: \(message.value)") }
    public func fault(_ message: OSLogMessage) { print("FAULT: \(message.value)") }
    public func critical(_ message: OSLogMessage) { print("CRITICAL: \(message.value)") }

    public func log(level: OSLogType, _ message: String) { print("\(level.label): \(message)") }
    public func log(level: OSLogType, _ message: OSLogMessage) { print("\(level.label): \(message.value)") }
    public func log(_ message: String) { print("DEFAULT: \(message)") }
    public func log(_ message: OSLogMessage) { print("DEFAULT: \(message.value)") }
    public func notice(_ message: String) { print("NOTICE: \(message)") }
    public func notice(_ message: OSLogMessage) { print("NOTICE: \(message.value)") }
    public func trace(_ message: String) { print("TRACE: \(message)") }
    public func trace(_ message: OSLogMessage) { print("TRACE: \(message.value)") }
}

public struct OSLogType: Sendable, Equatable {
    public let label: String
    public init(label: String) { self.label = label }
    public static let `default` = OSLogType(label: "DEFAULT")
    public static let info = OSLogType(label: "INFO")
    public static let debug = OSLogType(label: "DEBUG")
    public static let error = OSLogType(label: "ERROR")
    public static let fault = OSLogType(label: "FAULT")
}

public final class OSLog: @unchecked Sendable {
    public static let `default` = OSLog(subsystem: "default", category: "default")
    public static let disabled = OSLog(subsystem: "disabled", category: "disabled")
    public init(subsystem: String, category: String) {}
}

// Match Apple's os_log signature exactly: type-first, message last. The
// xctest-dynamic-overlay reporter calls this overload as
// `os_log(.info, dso: dso, log: log, "%@", string)`. Keeping the first
// parameter as OSLogType lets `.info` shorthand resolve correctly.
public func os_log(
    _ type: OSLogType,
    dso: UnsafeRawPointer? = nil,
    log: OSLog = .default,
    _ message: StaticString,
    _ args: CVarArg...
) {
    print("\(type.label): \(message)")
}

// Apple's Mach-O dynamic-loader API. Stubbed on Linux so packages that
// reach for it (xctest-dynamic-overlay's _DefaultReporter, which scans
// loaded images looking for SwiftUI) compile. The loop bodies become
// no-ops because the image count is zero.
public func _dyld_image_count() -> UInt32 { 0 }
public func _dyld_get_image_name(_ index: UInt32) -> UnsafePointer<CChar>? { nil }
public func _dyld_get_image_header(_ index: UInt32) -> UnsafeRawPointer? { nil }

public struct OSLogMessage: ExpressibleByStringInterpolation, Sendable {
    public let value: String
    public init(stringLiteral value: String) { self.value = value }
    public init(stringInterpolation: OSLogInterpolation) { self.value = stringInterpolation.value }
}

public struct OSLogInterpolation: StringInterpolationProtocol, Sendable {
    public var value: String
    public init(literalCapacity: Int, interpolationCount: Int) { self.value = "" }
    public mutating func appendLiteral(_ literal: String) { value += literal }
    public mutating func appendInterpolation(_ any: Any, privacy: OSLogPrivacy = .auto) { value += "\(any)" }
    public mutating func appendInterpolation(_ any: Any, format: OSLogFormat, privacy: OSLogPrivacy = .auto) { value += "\(any)" }
}

public struct OSLogPrivacy: Sendable {
    public static let `public` = OSLogPrivacy()
    public static let `private` = OSLogPrivacy()
    public static let auto = OSLogPrivacy()
}

public struct OSLogFormat: Sendable {
    public static let auto = OSLogFormat()
    public static func fixed(precision: Int) -> OSLogFormat { OSLogFormat() }
}

public class OSAllocatedUnfairLock<T>: @unchecked Sendable {
    public init(initialState: T) { self._state = initialState }
    public func withLock<U>(_ block: (inout T) throws -> U) rethrows -> U { 
        return try block(&_state)
    }
    private var _state: T
}

public struct OSSignposter: Sendable {
    public init(subsystem: String, category: String) {}
    public init(subsystem: String, category: OSSignpostCategory) {}
    public func makeSignpostID() -> Any { return 0 }
    public func begin(name: String, id: Any = 0) {}
    public func end(name: String, id: Any = 0) {}
    public func withIntervalSignpost<T>(_ name: String, id: Any = 0, _ block: () throws -> T) rethrows -> T { return try block() }
    public func beginInterval(_ name: String, id: Any = 0) -> Any { return 0 }
    public func endInterval(_ name: String, _ state: Any, _ message: String = "") {}
}

public enum OSSignpostCategory: Sendable {
    case pointsOfInterest
}
