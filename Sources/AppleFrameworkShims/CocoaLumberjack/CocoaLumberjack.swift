//
// QuillUI Linux shim for `CocoaLumberjack`.
//
// SignalServiceKit's Debugging layer (Logger / DebugLogger / LogFormatter /
// ScrubbingLogFormatter) logs through CocoaLumberjack. CocoaLumberjack is
// unavailable on Linux, so these are inert: DDLog.log is a no-op, the file /
// TTY loggers do nothing. Log messages are still constructed and formatted, so
// the formatters compile and run; they just aren't emitted anywhere yet (a real
// Linux logging backend is deferred).
//
// Also includes the OWSLogs.h inline helpers (ddLogLevel / ShouldLogFlag /
// ShouldLogVerbose / ShouldLogDebug), which live in an excluded ObjC header and
// are bitwise-defined over DDLogLevel/DDLogFlag.
//
import Foundation

// MARK: - DateFormatter.formatterBehavior (Linux)
//
// LogFormatter sets formatter.formatterBehavior = .behavior10_4 (copied from
// CocoaLumberjack's DDLogFileFormatterDefault). swift-corelibs DateFormatter has
// no formatterBehavior/Behavior. LogFormatter imports CocoaLumberjack, so the
// inert Linux-gated shim lives here (set is a no-op; the output format is fixed
// by .dateFormat anyway). Linux-only so it cannot collide with Apple's real
// member on macOS.
#if os(Linux)
public extension DateFormatter {
    enum Behavior: UInt, Sendable {
        case `default` = 0
        case behavior10_0 = 1000
        case behavior10_4 = 1040
    }
    var formatterBehavior: Behavior {
        get { .default }
        set { _ = newValue }
    }
}
#endif

// MARK: - DDLogFlag / DDLogLevel

public struct DDLogFlag: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let error = DDLogFlag(rawValue: 1 << 0)
    public static let warning = DDLogFlag(rawValue: 1 << 1)
    public static let info = DDLogFlag(rawValue: 1 << 2)
    public static let debug = DDLogFlag(rawValue: 1 << 3)
    public static let verbose = DDLogFlag(rawValue: 1 << 4)
}

public struct DDLogLevel: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let off = DDLogLevel([])
    public static let error: DDLogLevel = [DDLogLevel(rawValue: DDLogFlag.error.rawValue)]
    public static let warning: DDLogLevel = [.error, DDLogLevel(rawValue: DDLogFlag.warning.rawValue)]
    public static let info: DDLogLevel = [.warning, DDLogLevel(rawValue: DDLogFlag.info.rawValue)]
    public static let debug: DDLogLevel = [.info, DDLogLevel(rawValue: DDLogFlag.debug.rawValue)]
    public static let verbose: DDLogLevel = [.debug, DDLogLevel(rawValue: DDLogFlag.verbose.rawValue)]
    public static let all = DDLogLevel(rawValue: .max)
}

// MARK: - OWSLogs.h inline helpers (excluded ObjC header)

/// The active log level (OWSLogs.h: DDLogLevelInfo in production).
public let ddLogLevel: DDLogLevel = .info

/// Whether the given flag is enabled at the active level.
public func ShouldLogFlag(_ flag: DDLogFlag) -> Bool {
    (ddLogLevel.rawValue & flag.rawValue) != 0
}

public func ShouldLogError() -> Bool { ddLogLevel.contains(.error) }
public func ShouldLogWarning() -> Bool { ddLogLevel.contains(.warning) }
public func ShouldLogInfo() -> Bool { ddLogLevel.contains(.info) }
public func ShouldLogDebug() -> Bool { ddLogLevel.contains(.debug) }
public func ShouldLogVerbose() -> Bool { ddLogLevel.contains(.verbose) }

// MARK: - DDLogMessage

public final class DDLogMessage: NSObject {
    public let message: String
    public let level: DDLogLevel
    public let flag: DDLogFlag
    public let context: Int
    public let file: String
    public let function: String?
    public let line: UInt
    public let tag: Any?
    public let timestamp: Date

    public init(message: String,
                level: DDLogLevel,
                flag: DDLogFlag,
                context: Int,
                file: String,
                function: String?,
                line: UInt,
                tag: Any?,
                timestamp: Date?) {
        self.message = message
        self.level = level
        self.flag = flag
        self.context = context
        self.file = file
        self.function = function
        self.line = line
        self.tag = tag
        self.timestamp = timestamp ?? Date()
        super.init()
    }
}

// MARK: - DDLogFormatter

public protocol DDLogFormatter: AnyObject {
    func format(message logMessage: DDLogMessage) -> String?
}

// MARK: - Loggers (inert)

/// Marker protocol for the logger objects passed to DDLog.add/remove.
public protocol DDLogger: AnyObject {
    var logFormatter: DDLogFormatter? { get set }
}

public final class DDLog {
    public static func add(_ logger: Any) {}
    public static func add(_ logger: Any, with level: DDLogLevel) {}
    public static func remove(_ logger: Any) {}
    /// Inert: no backend emits the message on Linux yet.
    public static func log(asynchronous: Bool, message: DDLogMessage) {}
    public static func flushLog() {}
}

public final class DDTTYLogger: DDLogger {
    nonisolated(unsafe) public static let sharedInstance: DDTTYLogger? = DDTTYLogger()
    public var logFormatter: DDLogFormatter?
    public init() {}
}

open class DDLogFileManagerDefault: NSObject {
    public var maximumNumberOfLogFiles: UInt = 0
    public var logFilesDiskQuota: UInt64 = 0
    public internal(set) var logsDirectory: String
    /// Inert: no log files are produced on Linux yet.
    public var unsortedLogFilePaths: [String] = []

    public init(logsDirectory: String?, defaultFileProtectionLevel: FileProtectionType = .completeUntilFirstUserAuthentication) {
        self.logsDirectory = logsDirectory ?? ""
        super.init()
    }

    /// Override hook used by SignalServiceKit's DebugLogFileManager.
    open func didArchiveLogFile(atPath logFilePath: String, wasRolled: Bool) {}
}

public final class DDFileLogger: DDLogger {
    public let logFileManager: DDLogFileManagerDefault
    public var logFormatter: DDLogFormatter?
    public var rollingFrequency: TimeInterval = 0
    public var maximumFileSize: UInt64 = 0

    public init(logFileManager: DDLogFileManagerDefault) {
        self.logFileManager = logFileManager
    }
}
