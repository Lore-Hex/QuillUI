import Foundation

public let PLCrashReportTextFormatiOS = 0

public final class PLCrashReporterConfig: @unchecked Sendable {
    public static func defaultConfiguration() -> PLCrashReporterConfig {
        PLCrashReporterConfig()
    }
}

public final class PLCrashReporter: @unchecked Sendable {
    public init?(configuration: PLCrashReporterConfig) {
        _ = configuration
    }

    public func enable() {}
    public func hasPendingCrashReport() -> Bool { false }
    public func loadPendingCrashReportData() -> Data? { nil }
    public func purgePendingCrashReport() {}
}

public final class PLCrashReport: @unchecked Sendable {
    public init(data: Data) throws {
        _ = data
    }
}

public enum PLCrashReportTextFormatter {
    public static func stringValue(for report: PLCrashReport, with format: Int) -> String? {
        _ = report
        _ = format
        return nil
    }
}

@MainActor public enum CrashReporter {
    public static private(set) var checkedCrashReporter: PLCrashReporter?
    public static private(set) var sentCrashLogTexts = [String]()

    public static func check(crashReporter: PLCrashReporter) {
        checkedCrashReporter = crashReporter
    }

    public static func sendCrashLogText(_ crashLogText: String) {
        sentCrashLogTexts.append(crashLogText)
    }

    public static func reset() {
        checkedCrashReporter = nil
        sentCrashLogTexts.removeAll()
    }
}
