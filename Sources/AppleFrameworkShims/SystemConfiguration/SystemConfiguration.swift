//
// QuillUI Linux shim for Apple's `SystemConfiguration` (the SCNetworkReachability
// subset SignalServiceKit's ReachabilityManager uses).
//
// SCNetworkReachability is Apple's network-reachability probe; there's no Linux
// equivalent. Rather than report "unreachable" (which would make the app refuse
// to attempt network), this shim reports REACHABLE so the app proceeds to make
// requests through the normal URLSession path (which does work on Linux via
// FoundationNetworking). The change-callback never fires, so reachability simply
// stays at its initial "reachable" value. HONEST STATUS: no real reachability
// monitoring on Linux; reachability is assumed-reachable.
//
import Foundation
import CoreFoundation
import Dispatch
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Opaque reachability handle (a CF type on Apple).
public final class SCNetworkReachability {}

public struct SCNetworkReachabilityFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init() { self.rawValue = 0 }
    public static let transientConnection = SCNetworkReachabilityFlags(rawValue: 1 << 0)
    public static let reachable = SCNetworkReachabilityFlags(rawValue: 1 << 1)
    public static let connectionRequired = SCNetworkReachabilityFlags(rawValue: 1 << 2)
    public static let connectionOnTraffic = SCNetworkReachabilityFlags(rawValue: 1 << 3)
    public static let interventionRequired = SCNetworkReachabilityFlags(rawValue: 1 << 4)
    public static let connectionOnDemand = SCNetworkReachabilityFlags(rawValue: 1 << 5)
    public static let isLocalAddress = SCNetworkReachabilityFlags(rawValue: 1 << 16)
    public static let isDirect = SCNetworkReachabilityFlags(rawValue: 1 << 17)
    public static let isWWAN = SCNetworkReachabilityFlags(rawValue: 1 << 18)
    public static let connectionAutomatic = SCNetworkReachabilityFlags(rawValue: 1 << 3)
}

public struct SCNetworkReachabilityContext {
    public var version: Int
    public var info: UnsafeMutableRawPointer?
    public var retain: (@convention(c) (UnsafeRawPointer) -> UnsafeRawPointer)?
    public var release: (@convention(c) (UnsafeRawPointer) -> Void)?
    public var copyDescription: (@convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>)?
    public init(
        version: Int,
        info: UnsafeMutableRawPointer?,
        retain: (@convention(c) (UnsafeRawPointer) -> UnsafeRawPointer)?,
        release: (@convention(c) (UnsafeRawPointer) -> Void)?,
        copyDescription: (@convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>)?
    ) {
        self.version = version
        self.info = info
        self.retain = retain
        self.release = release
        self.copyDescription = copyDescription
    }
}

// NOT @convention(c): the params (SCNetworkReachability class, the Flags struct)
// aren't C-representable on Linux. The callback is inert (never fires) and the
// consumer passes a non-capturing closure literal, so a plain Swift closure type
// accepts it fine.
public typealias SCNetworkReachabilityCallBack =
    (SCNetworkReachability, SCNetworkReachabilityFlags, UnsafeMutableRawPointer?) -> Void

public func SCNetworkReachabilityCreateWithAddress(
    _ allocator: CFAllocator?,
    _ address: UnsafePointer<sockaddr>
) -> SCNetworkReachability? {
    SCNetworkReachability()
}

public func SCNetworkReachabilityCreateWithName(
    _ allocator: CFAllocator?,
    _ nodename: UnsafePointer<CChar>
) -> SCNetworkReachability? {
    SCNetworkReachability()
}

/// Reports REACHABLE so the app proceeds to attempt network via URLSession.
@discardableResult
public func SCNetworkReachabilityGetFlags(
    _ target: SCNetworkReachability,
    _ flags: UnsafeMutablePointer<SCNetworkReachabilityFlags>
) -> Bool {
    flags.pointee = .reachable
    return true
}

/// Inert: the change-callback never fires (reachability never changes on Linux).
@discardableResult
public func SCNetworkReachabilitySetCallback(
    _ target: SCNetworkReachability,
    _ callout: SCNetworkReachabilityCallBack?,
    _ context: UnsafeMutablePointer<SCNetworkReachabilityContext>?
) -> Bool {
    true
}

@discardableResult
public func SCNetworkReachabilitySetDispatchQueue(
    _ target: SCNetworkReachability,
    _ queue: DispatchQueue?
) -> Bool {
    true
}
