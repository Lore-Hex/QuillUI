@_exported import Foundation
import QuillKit

public struct Logger: Sendable {
    public init(subsystem: String, category: String) {}

    public func debug(_ message: String) { recordOSLoggerMessage(level: "DEBUG", operation: "Logger.debug", message: message) }
    public func info(_ message: String) { recordOSLoggerMessage(level: "INFO", operation: "Logger.info", message: message) }
    public func warning(_ message: String) { recordOSLoggerMessage(level: "WARNING", operation: "Logger.warning", message: message) }
    public func error(_ message: String) { recordOSLoggerMessage(level: "ERROR", operation: "Logger.error", message: message) }
    public func fault(_ message: String) { recordOSLoggerMessage(level: "FAULT", operation: "Logger.fault", message: message) }
    public func critical(_ message: String) { recordOSLoggerMessage(level: "CRITICAL", operation: "Logger.critical", message: message) }

    public func debug(_ message: Any) { recordOSLoggerMessage(level: "DEBUG", operation: "Logger.debug", message: "\(message)") }
    public func info(_ message: Any) { recordOSLoggerMessage(level: "INFO", operation: "Logger.info", message: "\(message)") }
    public func warning(_ message: Any) { recordOSLoggerMessage(level: "WARNING", operation: "Logger.warning", message: "\(message)") }
    public func error(_ message: Any) { recordOSLoggerMessage(level: "ERROR", operation: "Logger.error", message: "\(message)") }
    public func fault(_ message: Any) { recordOSLoggerMessage(level: "FAULT", operation: "Logger.fault", message: "\(message)") }
    public func critical(_ message: Any) { recordOSLoggerMessage(level: "CRITICAL", operation: "Logger.critical", message: "\(message)") }

    public func debug(_ message: OSLogMessage) { recordOSLoggerMessage(level: "DEBUG", operation: "Logger.debug", message: message.value) }
    public func info(_ message: OSLogMessage) { recordOSLoggerMessage(level: "INFO", operation: "Logger.info", message: message.value) }
    public func warning(_ message: OSLogMessage) { recordOSLoggerMessage(level: "WARNING", operation: "Logger.warning", message: message.value) }
    public func error(_ message: OSLogMessage) { recordOSLoggerMessage(level: "ERROR", operation: "Logger.error", message: message.value) }
    public func fault(_ message: OSLogMessage) { recordOSLoggerMessage(level: "FAULT", operation: "Logger.fault", message: message.value) }
    public func critical(_ message: OSLogMessage) { recordOSLoggerMessage(level: "CRITICAL", operation: "Logger.critical", message: message.value) }

    public func log(level: OSLogType, _ message: String) { recordOSLoggerMessage(level: level.label, operation: "Logger.log", message: message) }
    public func log(level: OSLogType, _ message: OSLogMessage) { recordOSLoggerMessage(level: level.label, operation: "Logger.log", message: message.value) }
    public func log(_ message: String) { recordOSLoggerMessage(level: "DEFAULT", operation: "Logger.log", message: message) }
    public func log(_ message: OSLogMessage) { recordOSLoggerMessage(level: "DEFAULT", operation: "Logger.log", message: message.value) }
    public func notice(_ message: String) { recordOSLoggerMessage(level: "NOTICE", operation: "Logger.notice", message: message) }
    public func notice(_ message: OSLogMessage) { recordOSLoggerMessage(level: "NOTICE", operation: "Logger.notice", message: message.value) }
    public func trace(_ message: String) { recordOSLoggerMessage(level: "TRACE", operation: "Logger.trace", message: message) }
    public func trace(_ message: OSLogMessage) { recordOSLoggerMessage(level: "TRACE", operation: "Logger.trace", message: message.value) }
}

private func recordOSLoggerMessage(level: String, operation: String, message: String) {
    let renderedMessage = "\(level): \(message)"
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "os.Logger",
        operation: operation,
        severity: .info,
        message: renderedMessage
    )
    print(renderedMessage)
}

public struct OSLogType: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: UInt8

    public var label: String {
        switch rawValue {
        case Self.info.rawValue:
            return "INFO"
        case Self.debug.rawValue:
            return "DEBUG"
        case Self.error.rawValue:
            return "ERROR"
        case Self.fault.rawValue:
            return "FAULT"
        default:
            return "DEFAULT"
        }
    }

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt8) {
        self.init(rawValue: rawValue)
    }

    public init(label: String) {
        switch label.uppercased() {
        case "INFO": self = .info
        case "DEBUG": self = .debug
        case "ERROR": self = .error
        case "FAULT": self = .fault
        default: self = .default
        }
    }

    public static let `default` = OSLogType(rawValue: 0x00)
    public static let info = OSLogType(rawValue: 0x01)
    public static let debug = OSLogType(rawValue: 0x02)
    public static let error = OSLogType(rawValue: 0x10)
    public static let fault = OSLogType(rawValue: 0x11)
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
    recordOSLoggerMessage(level: type.label, operation: "os_log", message: "\(message)")
}

// Apple's PRIMARY os_log: message-first with a `type:` label. This is the form
// real macOS source uses (e.g. WireGuard's Logger.swift: `os_log(msg, log:,
// type:)` and `os_log("%{public}s", log:, type:, arg)`). Added ALONGSIDE the
// type-first overload above; the two are unambiguous because the first
// positional parameter is a StaticString here vs an OSLogType there, so any
// call resolves to exactly one.
public func os_log(
    _ message: StaticString,
    dso: UnsafeRawPointer? = nil,
    log: OSLog = .default,
    type: OSLogType = .default,
    _ args: CVarArg...
) {
    recordOSLoggerMessage(level: type.label, operation: "os_log", message: "\(message)")
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
    public mutating func appendInterpolation(_ any: Any, privacy: OSLogPrivacy = .auto) {
        value += OSLogPrivacy.render(any, privacy: privacy)
    }
    public mutating func appendInterpolation(_ any: Any, format: OSLogFormat, privacy: OSLogPrivacy = .auto) {
        value += OSLogPrivacy.render(any, privacy: privacy)
    }
}

public struct OSLogPrivacy: Equatable, Sendable {
    fileprivate enum Visibility: Sendable {
        case automatic
        case rendered
        case redacted
    }

    fileprivate let visibility: Visibility

    public init() {
        self.visibility = .automatic
    }

    fileprivate init(_ visibility: Visibility) {
        self.visibility = visibility
    }

    public static let `public` = OSLogPrivacy(.rendered)
    public static let `private` = OSLogPrivacy(.redacted)
    public static let auto = OSLogPrivacy(.automatic)
    public static let sensitive = OSLogPrivacy(.redacted)

    fileprivate static func render(_ any: Any, privacy: OSLogPrivacy) -> String {
        privacy.visibility == .redacted ? "<private>" : "\(any)"
    }
}

public struct OSLogFormat: Sendable {
    public static let auto = OSLogFormat()
    public static func fixed(precision: Int) -> OSLogFormat { OSLogFormat() }
}

public class OSAllocatedUnfairLock<T>: @unchecked Sendable {
    public init(initialState: T) { self._state = initialState }
    public func withLock<U>(_ block: (inout T) throws -> U) rethrows -> U {
        _lock.lock()
        defer { _lock.unlock() }
        return try block(&_state)
    }
    // NSLock, not an unfair lock: callers need the mutual exclusion, not the
    // priority-donation behavior.
    private let _lock = NSLock()
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
