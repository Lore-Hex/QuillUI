import Foundation
import QuillKit

public enum OSLogPrivacy: Sendable {
    case `public`
    case `private`
}

public struct Logger: Sendable {
    public struct Message: CustomStringConvertible, Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        public var description: String

        public init(stringLiteral value: String) {
            self.description = value
        }

        public init(stringInterpolation: StringInterpolation) {
            self.description = stringInterpolation.output
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            var output = ""

            public init(literalCapacity: Int, interpolationCount: Int) {
                output.reserveCapacity(literalCapacity)
            }

            public mutating func appendLiteral(_ literal: String) {
                output += literal
            }

            public mutating func appendInterpolation<Value>(_ value: Value) {
                output += String(describing: value)
            }

            public mutating func appendInterpolation<Value>(_ value: Value, privacy: OSLogPrivacy) {
                switch privacy {
                case .public:
                    output += String(describing: value)
                case .private:
                    output += "<private>"
                }
            }
        }
    }

    public var subsystem: String
    public var category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    public func debug(_ message: Message) {
        record("Logger.debug", message)
    }

    public func info(_ message: Message) {
        record("Logger.info", message)
    }

    public func notice(_ message: Message) {
        record("Logger.notice", message)
    }

    public func warning(_ message: Message) {
        record("Logger.warning", message)
    }

    public func error(_ message: Message) {
        record("Logger.error", message, severity: .warning)
    }

    public func fault(_ message: Message) {
        record("Logger.fault", message, severity: .warning)
    }

    private func record(
        _ operation: String,
        _ message: Message,
        severity: QuillCompatibilityEvent.Severity = .info
    ) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "os",
            operation: operation,
            severity: severity,
            message: "[\(subsystem):\(category)] \(message.description)"
        )
    }
}

public struct OSLog: Sendable {
    public var subsystem: String
    public var category: String

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }
}

public enum OSLogType: Sendable {
    case `default`
    case info
    case debug
    case error
    case fault
}

public func os_log(
    _ type: OSLogType,
    dso: UnsafeRawPointer? = nil,
    log: OSLog,
    _ message: StaticString,
    _ arguments: CVarArg...
) {
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "os",
        operation: "os_log",
        severity: type == .fault || type == .error ? .warning : .info,
        message: "[\(log.subsystem):\(log.category)] \(message)"
    )
}

public struct mach_header {}

public func _dyld_image_count() -> UInt32 { 0 }

public func _dyld_get_image_name(_ imageIndex: UInt32) -> UnsafePointer<CChar>? { nil }

public func _dyld_get_image_header(_ imageIndex: UInt32) -> UnsafePointer<mach_header>? { nil }
