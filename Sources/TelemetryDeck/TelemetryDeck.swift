import Foundation

public enum TelemetryDeck {
    public static func initialize(config: Any) {}
    public static func signal(_ signal: String, parameters: [String: String] = [:]) {}
}
