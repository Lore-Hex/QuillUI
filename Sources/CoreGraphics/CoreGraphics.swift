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

public struct CGEventFlags: OptionSet, Sendable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let maskCommand = CGEventFlags(rawValue: 1 << 0)
    public static let maskShift = CGEventFlags(rawValue: 1 << 1)
    public static let maskAlternate = CGEventFlags(rawValue: 1 << 2)
    public static let maskControl = CGEventFlags(rawValue: 1 << 3)
}

public enum CGEventSourceStateID: Sendable {
    case hidSystemState
    case combinedSessionState
}

public final class CGEventSource: @unchecked Sendable {
    public init?(stateID: CGEventSourceStateID) {}

    public static func keyState(_ stateID: CGEventSourceStateID, key: CGKeyCode) -> Bool {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "CoreGraphics",
            operation: "keyState",
            message: "Keyboard state polling is unavailable until a native Linux backend is attached."
        )
        return false
    }
}

public enum CGEventTapLocation: Sendable {
    case cghidEventTap
}

public final class CGEvent: @unchecked Sendable {
    public var flags: CGEventFlags = []

    public init?(keyboardEventSource source: CGEventSource?, virtualKey: CGKeyCode, keyDown: Bool) {}

    public func post(tap: CGEventTapLocation) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "CoreGraphics",
            operation: "postEvent",
            message: "Synthetic input is unavailable until a native Linux backend is attached."
        )
    }
    public func keyboardSetUnicodeString(stringLength: Int, unicodeString: UnsafePointer<UInt16>) {}
}
