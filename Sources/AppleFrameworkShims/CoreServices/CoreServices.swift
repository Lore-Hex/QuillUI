import Foundation
import QuillKit

@_exported import typealias QuillKit.CFString

public struct LSRolesMask: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let none = LSRolesMask([])
    public static let viewer = LSRolesMask(rawValue: 1 << 0)
    public static let editor = LSRolesMask(rawValue: 1 << 1)
    public static let shell = LSRolesMask(rawValue: 1 << 2)
    public static let all = LSRolesMask(rawValue: UInt32.max)
}

public let kLSRolesNone = LSRolesMask.none
public let kLSRolesViewer = LSRolesMask.viewer
public let kLSRolesEditor = LSRolesMask.editor
public let kLSRolesShell = LSRolesMask.shell
public let kLSRolesAll = LSRolesMask.all

public func LSCopyAllRoleHandlersForContentType(
    _ inContentType: CFString,
    _ inRoleMask: LSRolesMask
) -> Unmanaged<NSArray>? {
    _ = (inContentType, inRoleMask)
    return nil
}

public func LSCopyDefaultRoleHandlerForContentType(
    _ inContentType: CFString,
    _ inRoleMask: LSRolesMask
) -> Unmanaged<NSString>? {
    _ = (inContentType, inRoleMask)
    return nil
}

public func LSCopyApplicationURLsForBundleIdentifier(
    _ inBundleIdentifier: CFString,
    _ outError: Any?
) -> Unmanaged<NSArray>? {
    _ = (inBundleIdentifier, outError)
    return nil
}
