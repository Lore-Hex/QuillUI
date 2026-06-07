//
// QuillUI Linux shim for `NaturalLanguage`. Concrete symbols are added as
// SignalServiceKit references surface. On-device language identification needs a
// model (CoreML/NL on Apple); deferred on Linux, so NLLanguageRecognizer reports
// no dominant language (callers treat that as "unknown"). Part of the
// Signal-iOS -> QuillOS port.
//
import Foundation

// NLLanguage is a RawRepresentable wrapper over a BCP-47 language code on Apple.
// SSK only reads `.rawValue`, so the inert recognizer never produces one.
public struct NLLanguage: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let undetermined = NLLanguage("und")
    public static let english = NLLanguage("en")
}

public final class NLLanguageRecognizer: @unchecked Sendable {
    public init() {}

    /// Convenience used by String+SSK for natural text-alignment heuristics.
    /// Language identification is deferred on Linux -> nil (caller: unknown).
    public static func dominantLanguage(for string: String) -> NLLanguage? {
        _ = string
        return nil
    }

    public private(set) var dominantLanguage: NLLanguage?
    public func processString(_ string: String) { _ = string }
    public func languageHypotheses(withMaximum maxHypotheses: Int) -> [NLLanguage: Double] {
        _ = maxHypotheses
        return [:]
    }
    public func reset() { dominantLanguage = nil }
}
