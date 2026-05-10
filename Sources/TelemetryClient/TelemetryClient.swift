import Foundation

public enum TelemetryManager {
    public static func initialize(with configuration: Any) {}
    public static func send(_ signal: String, with customData: [String: String] = [:]) {}
}
