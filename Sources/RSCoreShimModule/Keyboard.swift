import AppKit

public let NSUpArrowFunctionKey = 0xF700
public let NSDownArrowFunctionKey = 0xF701
public let NSLeftArrowFunctionKey = 0xF702
public let NSRightArrowFunctionKey = 0xF703
public let NSDeleteFunctionKey = 0xF728
public let NSCarriageReturnCharacter = 0x000D
public let NSEnterCharacter = 0x0003
public let NSTabCharacter = 0x0009

public struct KeyboardConstant {
    public static let lineFeedKey = "\n".keyboardIntegerValue
    public static let returnKey = "\r".keyboardIntegerValue
    public static let spaceKey = " ".keyboardIntegerValue
}

public extension String {
    var keyboardIntegerValue: Int? {
        guard let first = utf16.first else {
            return nil
        }
        return Int(first)
    }
}

public struct KeyboardShortcut: Hashable, Sendable {
    public let key: KeyboardKey
    public let actionString: String

    public init?(dictionary: [String: Any]) {
        guard let key = KeyboardKey(dictionary: dictionary),
              let actionString = dictionary["action"] as? String
        else {
            return nil
        }

        self.key = key
        self.actionString = actionString
    }

    @MainActor public func perform(with view: NSView) {
        let action = NSSelectorFromString(actionString)
        NSApplication.shared.sendAction(action, to: nil, from: view)
    }

    public static func findMatchingShortcut(in shortcuts: Set<KeyboardShortcut>, key: KeyboardKey) -> KeyboardShortcut? {
        shortcuts.first { $0.key == key }
    }
}

public struct KeyboardKey: Hashable, Sendable {
    public let shiftKeyDown: Bool
    public let optionKeyDown: Bool
    public let commandKeyDown: Bool
    public let controlKeyDown: Bool
    public let integerValue: Int

    public var isModified: Bool {
        !shiftKeyDown && !optionKeyDown && !commandKeyDown && !controlKeyDown
    }

    public init(
        integerValue: Int,
        shiftKeyDown: Bool,
        optionKeyDown: Bool,
        commandKeyDown: Bool,
        controlKeyDown: Bool
    ) {
        self.integerValue = integerValue
        self.shiftKeyDown = shiftKeyDown
        self.optionKeyDown = optionKeyDown
        self.commandKeyDown = commandKeyDown
        self.controlKeyDown = controlKeyDown
    }

    public static let deleteKeyCode = 127

    public init(with event: NSEvent) {
        let flags = event.modifierFlags
        self.init(
            integerValue: event.charactersIgnoringModifiers?.keyboardIntegerValue ?? 0,
            shiftKeyDown: flags.contains(.shift),
            optionKeyDown: flags.contains(.option),
            commandKeyDown: flags.contains(.command),
            controlKeyDown: flags.contains(.control)
        )
    }

    public init?(dictionary: [String: Any]) {
        guard let keyString = dictionary["key"] as? String else {
            return nil
        }

        let integerValue: Int
        switch keyString {
        case "[space]":
            integerValue = " ".keyboardIntegerValue ?? 0
        case "[uparrow]":
            integerValue = NSUpArrowFunctionKey
        case "[downarrow]":
            integerValue = NSDownArrowFunctionKey
        case "[leftarrow]":
            integerValue = NSLeftArrowFunctionKey
        case "[rightarrow]":
            integerValue = NSRightArrowFunctionKey
        case "[return]":
            integerValue = NSCarriageReturnCharacter
        case "[enter]":
            integerValue = NSEnterCharacter
        case "[delete]":
            integerValue = Self.deleteKeyCode
        case "[deletefunction]":
            integerValue = NSDeleteFunctionKey
        case "[tab]":
            integerValue = NSTabCharacter
        default:
            guard let value = keyString.keyboardIntegerValue else {
                return nil
            }
            integerValue = value
        }

        self.init(
            integerValue: integerValue,
            shiftKeyDown: dictionary["shiftModifier"] as? Bool ?? false,
            optionKeyDown: dictionary["optionModifier"] as? Bool ?? false,
            commandKeyDown: dictionary["commandModifier"] as? Bool ?? false,
            controlKeyDown: dictionary["controlModifier"] as? Bool ?? false
        )
    }
}
