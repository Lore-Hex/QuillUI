import Foundation
#if os(Linux)
import Glibc
#endif

public enum NetworkStatus: Int32, Equatable {
    case notReachable = 0
    case reachableViaWiFi = 1
    case reachableViaWWAN = 2
}

public let NotReachable = NetworkStatus.notReachable
public let ReachableViaWiFi = NetworkStatus.reachableViaWiFi
public let ReachableViaWWAN = NetworkStatus.reachableViaWWAN
public let kReachabilityChangedNotification = "kNetworkReachabilityChangedNotification"

open class LegacyReachability: NSObject {
    public var reachabilityChanged: ((NetworkStatus) -> Void)?

    public static func withHostName(_ hostName: String) -> LegacyReachability {
        _ = hostName
        return LegacyReachability()
    }

    public static func withAddress(_ hostAddress: UnsafePointer<sockaddr>) -> LegacyReachability {
        _ = hostAddress
        return LegacyReachability()
    }

    public static func forInternetConnection() -> LegacyReachability {
        LegacyReachability()
    }

    public func startNotifier() -> Bool {
        true
    }

    public func stopNotifier() {
    }

    public func currentReachabilityStatus() -> NetworkStatus {
        .reachableViaWiFi
    }

    public func connectionRequired() -> Bool {
        false
    }
}
