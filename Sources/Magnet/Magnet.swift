import Foundation
#if canImport(AppKit)
import AppKit
#endif
import QuillKit

public enum Key: Hashable, Sendable {
    case space
    case escape
    case character(Character)

    var quillKeyName: String {
        switch self {
        case .space:
            return "space"
        case .escape:
            return "escape"
        case .character(let character):
            return String(character)
        }
    }
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

    var quillDescriptorModifiers: [String] {
        var names: [String] = []
        if cocoaModifiers.contains(.command) {
            names.append("command")
        }
        if cocoaModifiers.contains(.option) {
            names.append("option")
        }
        if cocoaModifiers.contains(.control) {
            names.append("control")
        }
        if cocoaModifiers.contains(.shift) {
            names.append("shift")
        }
        if cocoaModifiers.contains(.function) {
            names.append("function")
        }
        return names
    }
}

public final class HotKey: @unchecked Sendable {
    public var identifier: String
    public var keyCombo: KeyCombo
    private let handler: (HotKey) -> Void
    private var registration: QuillHotKeyRegistration?

    public private(set) var isRegistered = false

    public init(identifier: String, keyCombo: KeyCombo, handler: @escaping (HotKey) -> Void) {
        self.identifier = identifier
        self.keyCombo = keyCombo
        self.handler = handler
    }

    public func register() {
        if registration?.isRegistered == true {
            isRegistered = true
            return
        }

        let descriptor = QuillHotKeyDescriptor(
            identifier: identifier,
            key: keyCombo.key.quillKeyName,
            modifiers: keyCombo.quillDescriptorModifiers
        )
        registration = QuillHotkeyService.shared.register(descriptor: descriptor) { [weak self] in
            guard let self else {
                return
            }
            self.handler(self)
        }
        isRegistered = registration?.isRegistered == true
    }

    public func unregister() {
        registration?.unregister()
        registration = nil
        isRegistered = false
    }

    public func trigger() { handler(self) }

    @discardableResult
    public static func trigger(identifier: String) -> Bool {
        QuillHotkeyService.shared.trigger(identifier: identifier)
    }

    @discardableResult
    public static func trigger(keyCombo: KeyCombo) -> Bool {
        QuillHotkeyService.shared.trigger(
            key: keyCombo.key.quillKeyName,
            modifiers: keyCombo.quillDescriptorModifiers
        )
    }
}
