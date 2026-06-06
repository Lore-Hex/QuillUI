//
// QuillUI Linux shim for Apple's `CFNetwork` (the system-proxy subset SSK uses).
//
// SignalServiceKit's NetworkManager reads the system proxy configuration to honor
// OS-level proxies. There's no CFNetwork on Linux, so this is INERT:
// CFNetworkCopySystemProxySettings returns nil (no system proxy), and the per-URL
// proxy lookup is never reached (the settings guard short-circuits). HONEST
// STATUS: OS-level proxy settings are not consulted on Linux.
//
import Foundation
import CoreFoundation

// Proxy-dictionary keys. NSString (not String) so the upstream
// `switch proxyConfig[kCFProxyTypeKey] as! NSObject? { case kCFProxyTypeHTTP: }`
// matches (the cases must be NSObject-comparable). nonisolated(unsafe) because a
// `let` global of the non-Sendable NSString is otherwise a concurrency error.
nonisolated(unsafe) public let kCFProxyTypeKey: NSString = "kCFProxyType"
nonisolated(unsafe) public let kCFProxyHostNameKey: NSString = "kCFProxyHostName"
nonisolated(unsafe) public let kCFProxyPortNumberKey: NSString = "kCFProxyPortNumber"
nonisolated(unsafe) public let kCFProxyUsernameKey: NSString = "kCFProxyUsername"
nonisolated(unsafe) public let kCFProxyPasswordKey: NSString = "kCFProxyPassword"
nonisolated(unsafe) public let kCFProxyAutoConfigurationURLKey: NSString = "kCFProxyAutoConfigurationURL"
nonisolated(unsafe) public let kCFProxyAutoConfigurationJavaScriptKey: NSString = "kCFProxyAutoConfigurationJavaScript"

nonisolated(unsafe) public let kCFProxyTypeNone: NSString = "kCFProxyTypeNone"
nonisolated(unsafe) public let kCFProxyTypeHTTP: NSString = "kCFProxyTypeHTTP"
nonisolated(unsafe) public let kCFProxyTypeHTTPS: NSString = "kCFProxyTypeHTTPS"
nonisolated(unsafe) public let kCFProxyTypeSOCKS: NSString = "kCFProxyTypeSOCKS"
nonisolated(unsafe) public let kCFProxyTypeFTP: NSString = "kCFProxyTypeFTP"
nonisolated(unsafe) public let kCFProxyTypeAutoConfigurationURL: NSString = "kCFProxyTypeAutoConfigurationURL"
nonisolated(unsafe) public let kCFProxyTypeAutoConfigurationJavaScript: NSString = "kCFProxyTypeAutoConfigurationJavaScript"

/// No system proxy configuration on Linux -> nil (caller treats it as "no proxy").
public func CFNetworkCopySystemProxySettings() -> Unmanaged<CFDictionary>? { nil }

/// Never reached at runtime (the settings guard short-circuits on the nil above),
/// but must type-check: returns an empty proxy list.
public func CFNetworkCopyProxiesForURL(_ url: CFURL, _ proxySettings: CFDictionary) -> Unmanaged<CFArray> {
    // swift-corelibs has no NSArray<->CFArray toll-free bridge, so build the
    // (empty) CFArray via the C constructor.
    Unmanaged.passRetained(CFArrayCreate(nil, nil, 0, nil))
}
