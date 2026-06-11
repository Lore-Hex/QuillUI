import Foundation

private var bridgingTrace: ((String?, String?) -> Void)?
private var bridgingShortTrace: ((String?, String?) -> Void)?
private var loggingEnabled = false

public func NetworkRegisterLoggingFunction() {}

public func NetworkSetLoggingEnabled(_ value: Bool) {
    loggingEnabled = value
}

public func setBridgingTraceFunction(_ f: ((String?, String?) -> Void)?) {
    bridgingTrace = f
}

public func setBridgingShortTraceFunction(_ f: ((String?, String?) -> Void)?) {
    bridgingShortTrace = f
}

public func QuillNetworkLog(_ domain: String, _ message: String, short: Bool = false) {
    guard loggingEnabled else { return }
    if short {
        bridgingShortTrace?(domain, message)
    } else {
        bridgingTrace?(domain, message)
    }
}
