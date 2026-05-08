import Foundation
import AppKit

public enum Key: Sendable {
    case space
    case escape
}

public struct KeyCombo: Sendable {
    public var key: Key
    public var cocoaModifiers: NSEvent.ModifierFlags

    public init?(key: Key, cocoaModifiers: NSEvent.ModifierFlags) {
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

