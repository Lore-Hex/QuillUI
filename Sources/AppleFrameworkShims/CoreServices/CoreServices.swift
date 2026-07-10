import Foundation
import QuillKit
import Dispatch

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

// MARK: - FSEvents

public typealias FSEventStreamEventId = UInt64
public typealias FSEventStreamEventFlags = UInt32
public typealias FSEventStreamCreateFlags = UInt32
public typealias CFTimeInterval = TimeInterval
public typealias CFIndex = Int

public final class QuillFSEventStream: @unchecked Sendable {
    public let paths: [String]
    public let flags: FSEventStreamCreateFlags
    public var queue: DispatchQueue?
    public var isStarted: Bool = false

    public init(paths: [String], flags: FSEventStreamCreateFlags) {
        self.paths = paths
        self.flags = flags
    }
}

public typealias FSEventStreamRef = QuillFSEventStream
public typealias ConstFSEventStreamRef = QuillFSEventStream

public struct FSEventStreamContext {
    public var version: CFIndex
    public var info: UnsafeMutableRawPointer?
    public var retain: (@convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?)?
    public var release: (@convention(c) (UnsafeRawPointer?) -> Void)?
    public var copyDescription: (@convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?)?

    public init(
        version: CFIndex,
        info: UnsafeMutableRawPointer?,
        retain: (@convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?)?,
        release: (@convention(c) (UnsafeRawPointer?) -> Void)?,
        copyDescription: (@convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?)?
    ) {
        self.version = version
        self.info = info
        self.retain = retain
        self.release = release
        self.copyDescription = copyDescription
    }
}

public typealias FSEventStreamCallback = (
    ConstFSEventStreamRef,
    UnsafeMutableRawPointer?,
    Int,
    UnsafeMutableRawPointer,
    UnsafePointer<FSEventStreamEventFlags>,
    UnsafePointer<FSEventStreamEventId>
) -> Void

public let kFSEventStreamEventIdSinceNow: FSEventStreamEventId = UInt64.max

public let kFSEventStreamCreateFlagNone: FSEventStreamCreateFlags = 0
public let kFSEventStreamCreateFlagUseCFTypes: FSEventStreamCreateFlags = 1 << 0
public let kFSEventStreamCreateFlagNoDefer: FSEventStreamCreateFlags = 1 << 1
public let kFSEventStreamCreateFlagWatchRoot: FSEventStreamCreateFlags = 1 << 2
public let kFSEventStreamCreateFlagIgnoreSelf: FSEventStreamCreateFlags = 1 << 3
public let kFSEventStreamCreateFlagFileEvents: FSEventStreamCreateFlags = 1 << 4
public let kFSEventStreamCreateFlagMarkSelf: FSEventStreamCreateFlags = 1 << 5
public let kFSEventStreamCreateFlagUseExtendedData: FSEventStreamCreateFlags = 1 << 6

public let kFSEventStreamEventFlagNone: FSEventStreamEventFlags = 0
public let kFSEventStreamEventFlagMustScanSubDirs: FSEventStreamEventFlags = 1 << 0
public let kFSEventStreamEventFlagUserDropped: FSEventStreamEventFlags = 1 << 1
public let kFSEventStreamEventFlagKernelDropped: FSEventStreamEventFlags = 1 << 2
public let kFSEventStreamEventFlagEventIdsWrapped: FSEventStreamEventFlags = 1 << 3
public let kFSEventStreamEventFlagHistoryDone: FSEventStreamEventFlags = 1 << 4
public let kFSEventStreamEventFlagRootChanged: FSEventStreamEventFlags = 1 << 5
public let kFSEventStreamEventFlagMount: FSEventStreamEventFlags = 1 << 6
public let kFSEventStreamEventFlagUnmount: FSEventStreamEventFlags = 1 << 7
public let kFSEventStreamEventFlagItemCreated: FSEventStreamEventFlags = 1 << 8
public let kFSEventStreamEventFlagItemRemoved: FSEventStreamEventFlags = 1 << 9
public let kFSEventStreamEventFlagItemInodeMetaMod: FSEventStreamEventFlags = 1 << 10
public let kFSEventStreamEventFlagItemRenamed: FSEventStreamEventFlags = 1 << 11
public let kFSEventStreamEventFlagItemModified: FSEventStreamEventFlags = 1 << 12
public let kFSEventStreamEventFlagItemFinderInfoMod: FSEventStreamEventFlags = 1 << 13
public let kFSEventStreamEventFlagItemChangeOwner: FSEventStreamEventFlags = 1 << 14
public let kFSEventStreamEventFlagItemXattrMod: FSEventStreamEventFlags = 1 << 15
public let kFSEventStreamEventFlagItemIsFile: FSEventStreamEventFlags = 1 << 16
public let kFSEventStreamEventFlagItemIsDir: FSEventStreamEventFlags = 1 << 17
public let kFSEventStreamEventFlagItemIsSymlink: FSEventStreamEventFlags = 1 << 18
public let kFSEventStreamEventFlagOwnEvent: FSEventStreamEventFlags = 1 << 19
public let kFSEventStreamEventFlagItemIsHardlink: FSEventStreamEventFlags = 1 << 20
public let kFSEventStreamEventFlagItemIsLastHardlink: FSEventStreamEventFlags = 1 << 21
public let kFSEventStreamEventFlagItemCloned: FSEventStreamEventFlags = 1 << 22

public let kFSEventStreamEventExtendedDataPathKey: CFString = "kFSEventStreamEventExtendedDataPathKey"
public let kFSEventStreamEventExtendedFileIDKey: CFString = "kFSEventStreamEventExtendedFileIDKey"

public func FSEventStreamCreate(
    _ allocator: Any,
    _ callback: @escaping FSEventStreamCallback,
    _ context: UnsafeMutablePointer<FSEventStreamContext>?,
    _ pathsToWatch: [String],
    _ sinceWhen: FSEventStreamEventId,
    _ latency: CFTimeInterval,
    _ flags: FSEventStreamCreateFlags
) -> FSEventStreamRef? {
    _ = (allocator, callback, context, sinceWhen, latency)
    return QuillFSEventStream(paths: pathsToWatch, flags: flags)
}

public func FSEventStreamCreate(
    _ allocator: Any,
    _ callback: @escaping FSEventStreamCallback,
    _ context: UnsafeMutablePointer<FSEventStreamContext>?,
    _ pathsToWatch: NSArray,
    _ sinceWhen: FSEventStreamEventId,
    _ latency: CFTimeInterval,
    _ flags: FSEventStreamCreateFlags
) -> FSEventStreamRef? {
    let paths = pathsToWatch.compactMap { $0 as? String }
    return FSEventStreamCreate(allocator, callback, context, paths, sinceWhen, latency, flags)
}

public func FSEventStreamSetDispatchQueue(_ streamRef: FSEventStreamRef?, _ queue: DispatchQueue?) {
    streamRef?.queue = queue
}

@discardableResult
public func FSEventStreamStart(_ streamRef: FSEventStreamRef?) -> Bool {
    streamRef?.isStarted = true
    return streamRef != nil
}

public func FSEventStreamStop(_ streamRef: FSEventStreamRef?) {
    streamRef?.isStarted = false
}

public func FSEventStreamInvalidate(_ streamRef: FSEventStreamRef?) {
    streamRef?.isStarted = false
}

public func FSEventStreamRelease(_ streamRef: FSEventStreamRef?) {
    _ = streamRef
}
