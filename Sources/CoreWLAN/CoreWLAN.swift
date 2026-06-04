// CoreWLAN — Wi-Fi client surface (Linux shadow).
// =================================================
// Compile-only shadow of Apple's CoreWLAN framework, providing the tiny surface
// the macOS WireGuard app uses for its on-demand "activate on these Wi-Fi
// networks" feature (OnDemandWiFiControls.getCurrentSSIDs):
//
//     CWWiFiClient.shared().interfaces()?.compactMap { $0.ssid() }
//
// On Linux there is no CoreWLAN; real SSID discovery would go through nl80211 in
// a later runtime layer. Here the client reports no interfaces (→ empty SSID
// list), so the unmodified macOS app source recompiles and the UI degrades
// gracefully (the SSID auto-complete simply offers nothing). Surface driven from
// real upstream usage. The SwiftPM target is named `CoreWLAN`, so `import
// CoreWLAN` resolves here when a Linux target depends on it; nothing on macOS
// imports it, so Apple's framework is unaffected there.
import Foundation

/// Mirrors `CWInterface` — a single Wi-Fi interface. Only `ssid()` is used by
/// the app (to list currently-joined network names for on-demand SSID rules).
open class CWInterface {
    public init() {}
    /// The associated network's SSID, or `nil` when not associated. Always `nil`
    /// on Linux (no CoreWLAN association state); a runtime layer may override.
    open func ssid() -> String? { nil }
}

/// Mirrors `CWWiFiClient` — the entry point to Wi-Fi state. The app calls
/// `CWWiFiClient.shared().interfaces()`. `@unchecked Sendable` (no mutable
/// stored state) so the shared instance is a concurrency-safe `static let`,
/// mirroring ServiceManagement's `SMAppService`.
open class CWWiFiClient: @unchecked Sendable {
    private static let _shared = CWWiFiClient()
    public init() {}
    /// The process-wide shared client (Apple's `+[CWWiFiClient sharedWiFiClient]`,
    /// surfaced to Swift as `shared()`).
    open class func shared() -> CWWiFiClient { _shared }
    /// All Wi-Fi interfaces. Empty on Linux (no CoreWLAN); the app maps this to
    /// an empty SSID list via `compactMap { $0.ssid() }`.
    open func interfaces() -> [CWInterface]? { [] }
}
