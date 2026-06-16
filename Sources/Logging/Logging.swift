// Logging -- Linux shim for compiling Signal-iOS SignalUI against QuillUI (QuillOS).
// Symbols added on demand as the SignalUI compile reports missing API.
import Foundation

public struct Logger: Sendable {
    public struct Message: ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
        public var description: String
        public init(stringLiteral value: String) { description = value }
        public init(_ value: String) { description = value }
    }

    public struct Metadata: ExpressibleByDictionaryLiteral, Sendable {
        public enum Value: ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
            case string(String)
            case stringConvertible(String)
            case array([Value])
            case dictionary([String: Value])

            public init(stringLiteral value: String) {
                self = .string(value)
            }

            public var description: String {
                switch self {
                case .string(let value), .stringConvertible(let value):
                    return value
                case .array(let values):
                    return values.map(\.description).joined(separator: ",")
                case .dictionary(let values):
                    return values.map { "\($0):\($1)" }.joined(separator: ",")
                }
            }
        }

        private var values: [String: Value]

        public init(dictionaryLiteral elements: (String, Value)...) {
            values = Dictionary(uniqueKeysWithValues: elements)
        }

        public subscript(_ key: String) -> Value? {
            get { values[key] }
            set { values[key] = newValue }
        }
    }

    public enum Level: Int, Sendable {
        case trace
        case debug
        case info
        case notice
        case warning
        case error
        case critical
    }

    public var label: String

    public init(label: String) {
        self.label = label
    }
}

public protocol LogHandler {
    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? { get set }
    var metadata: Logger.Metadata { get set }
    var logLevel: Logger.Level { get set }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    )
}

public enum LoggingSystem {
    nonisolated(unsafe) private static var factory: ((String) -> any LogHandler)?

    public static func bootstrap(_ factory: @escaping (String) -> any LogHandler) {
        self.factory = factory
    }

    public static func make(_ label: String) -> (any LogHandler)? {
        factory?(label)
    }
}
