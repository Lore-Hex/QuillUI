import Foundation
import Testing
import CoreWLAN

/// Covers the Linux CoreWLAN shadow — the tiny Wi-Fi surface the macOS WireGuard
/// app uses for on-demand-by-SSID (OnDemandWiFiControls.getCurrentSSIDs):
/// `CWWiFiClient.shared().interfaces()?.compactMap { $0.ssid() }`. This was the
/// last missing framework module gating the whole macOS app from compiling
/// (found via the single-module gap-analysis spike).
@Suite("CoreWLAN shadow — Wi-Fi SSID surface")
struct CoreWLANTests {
    @Test("CWWiFiClient.shared() returns a stable shared instance")
    func sharedClient() {
        #expect(CWWiFiClient.shared() === CWWiFiClient.shared())
    }

    @Test("getCurrentSSIDs-style chain compiles and yields an empty list on Linux")
    func ssidChain() {
        // Mirrors OnDemandWiFiControls.getCurrentSSIDs() verbatim.
        let ssids = CWWiFiClient.shared().interfaces()?.compactMap { $0.ssid() } ?? []
        #expect(ssids.isEmpty)
    }

    @Test("CWInterface.ssid() is nil when unassociated (Linux default)")
    func interfaceSSID() {
        #expect(CWInterface().ssid() == nil)
    }
}
