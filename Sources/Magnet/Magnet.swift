import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum Key: Sendable {
    case space
    case escape
}

#if canImport(AppKit)
public typealias _Modifiers = NSEvent.ModifierFlags
#else
public struct _Modifiers: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
}
#endif

public struct KeyCombo: Sendable {
    public var key: Key
    public var cocoaModifiers: _Modifiers

    public init?(key: Key, cocoaModifiers: _Modifiers) {
        self.key = key
        self.cocoaModifiers = cocoaModifiers
    }
}

public final class HotKey: @unchecked Sendable {
    public var identifier: String
    public var keyCombo: KeyCombo
    private let handler: (HotKey) -> Void

    public init(identifier: String, keyCombo: KeyCombo, handler: @escaping (HotKey) -> Void) {
        self.identifier = identifier
        self.keyCombo = keyCombo
        self.handler = handler
    }

    public func register() {}
    public func unregister() {}
    public func trigger() { handler(self) }
}
