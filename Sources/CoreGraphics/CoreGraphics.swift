import Foundation
import QuillKit

// CoreGraphics geometry value types live in swift-corelibs-foundation on Linux.
// Re-export CGFloat so `import CoreGraphics` (without also importing Foundation)
// resolves it — e.g. GRDB's CGFloat.swift does `#if canImport(CoreGraphics)
// import CoreGraphics` then extends `CGFloat`. Re-exporting the real
// Foundation.CGFloat (rather than declaring a new typealias) keeps a single
// canonical type, so code importing Foundation + CoreGraphics sees no ambiguity.
@_exported import struct Foundation.CGFloat

public typealias CGKeyCode = UInt16

public extension CGKeyCode {
    static let kVK_ANSI_V: CGKeyCode = 0x09
}

public struct CGEventFlags: OptionSet, Sendable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let maskNonCoalesced = CGEventFlags(rawValue: 1 << 8)
    public static let maskAlphaShift = CGEventFlags(rawValue: 1 << 16)
    public static let maskShift = CGEventFlags(rawValue: 1 << 17)
    public static let maskControl = CGEventFlags(rawValue: 1 << 18)
    public static let maskAlternate = CGEventFlags(rawValue: 1 << 19)
    public static let maskCommand = CGEventFlags(rawValue: 1 << 20)
    public static let maskNumericPad = CGEventFlags(rawValue: 1 << 21)
    public static let maskHelp = CGEventFlags(rawValue: 1 << 22)
    public static let maskSecondaryFn = CGEventFlags(rawValue: 1 << 23)
}

public enum CGEventSourceStateID: Int32, Sendable {
    case privateState = -1
    case combinedSessionState = 0
    case hidSystemState = 1
}

public final class CGEventSource: @unchecked Sendable {
    public let stateID: CGEventSourceStateID

    public init?(stateID: CGEventSourceStateID) {
        self.stateID = stateID
    }

    public static func keyState(_ stateID: CGEventSourceStateID, key: CGKeyCode) -> Bool {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "CoreGraphics",
            operation: "keyState",
            message: "Keyboard state polling is unavailable until a native Linux backend is attached."
        )
        return false
    }
}

public enum CGEventTapLocation: Int32, Sendable {
    case cghidEventTap = 0
    case cgSessionEventTap = 1
    case cgAnnotatedSessionEventTap = 2
}

public final class CGEvent: @unchecked Sendable {
    public let source: CGEventSource?
    public let virtualKey: CGKeyCode
    public let keyDown: Bool
    public var flags: CGEventFlags = []
    private var keyboardUnicodeString: [UInt16] = []

    public init?(keyboardEventSource source: CGEventSource?, virtualKey: CGKeyCode, keyDown: Bool) {
        self.source = source
        self.virtualKey = virtualKey
        self.keyDown = keyDown
    }

    public func post(tap: CGEventTapLocation) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "CoreGraphics",
            operation: "postEvent",
            message: "Synthetic input is unavailable until a native Linux backend is attached."
        )
    }

    public func keyboardSetUnicodeString(stringLength: Int, unicodeString: UnsafePointer<UInt16>?) {
        guard stringLength > 0, let unicodeString else {
            keyboardUnicodeString = []
            return
        }

        keyboardUnicodeString = Array(UnsafeBufferPointer(start: unicodeString, count: stringLength))
    }

    public func keyboardGetUnicodeString(
        maxStringLength: Int,
        actualStringLength: UnsafeMutablePointer<Int>?,
        unicodeString: UnsafeMutablePointer<UInt16>?
    ) {
        actualStringLength?.pointee = keyboardUnicodeString.count
        guard maxStringLength > 0, let unicodeString else {
            return
        }

        for index in 0..<Swift.min(maxStringLength, keyboardUnicodeString.count) {
            unicodeString.advanced(by: index).pointee = keyboardUnicodeString[index]
        }
    }
}
