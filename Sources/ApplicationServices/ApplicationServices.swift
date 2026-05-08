import Foundation
@_exported import QuillKit

public final class AXUIElement: @unchecked Sendable {
    public init() {}
}

public enum AXError: Int32, Sendable {
    case success = 0
    case failure = -1
}

public let kAXTrustedCheckOptionPrompt = QuillUnmanagedStringConstant("AXTrustedCheckOptionPrompt")
public let kAXFocusedApplicationAttribute: CFString = "AXFocusedApplication"
public let kAXFocusedUIElementAttribute: CFString = "AXFocusedUIElement"
public let kAXSelectedTextAttribute: CFString = "AXSelectedText"

public func AXIsProcessTrustedWithOptions(_ options: CFDictionary?) -> Bool {
    QuillAccessibility.isTrusted
}

public func AXUIElementCreateSystemWide() -> AXUIElement {
    AXUIElement()
}

public func AXUIElementCopyAttributeValue(_ element: AXUIElement, _ attribute: CFString, _ value: UnsafeMutablePointer<AnyObject?>) -> AXError {
    .failure
}
