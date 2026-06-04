import Foundation
import Testing
import NetworkExtension

/// Covers the Linux NetworkExtension VPN-management shadow (NEVPNManager /
/// NETunnelProviderManager + connection/status), the surface WireGuard's
/// TunnelsManager uses. Runs on the Swift Linux Backends job (the shadow target
/// is added only under `#if os(Linux)`).
@Suite("NetworkExtension VPN-management shadow")
struct NetworkExtensionVPNTests {
    @Test("VPN status enum + connection default status")
    func statusCore() {
        #expect(NEVPNStatus.connected.rawValue == 3)
        #expect(NEVPNConnection().status == .invalid)
    }

    @Test("NETunnelProviderManager: config + no-op-success load/save on Linux")
    func managerCore() {
        let mgr = NETunnelProviderManager()
        mgr.isEnabled = true
        let proto = NETunnelProviderProtocol()
        proto.providerConfiguration = ["k": "v"]
        proto.providerBundleIdentifier = "com.example"
        mgr.protocolConfiguration = proto
        #expect(mgr.isEnabled)
        #expect(mgr.protocolConfiguration is NETunnelProviderProtocol)
        // The connection is the message-capable provider-session subtype.
        #expect(mgr.connection is NETunnelProviderSession)

        var saved = false
        var savedErr: Error? = NEVPNError(.connectionFailed)
        mgr.saveToPreferences { err in saved = true; savedErr = err }
        #expect(saved && savedErr == nil)

        var loadedEmpty = false
        NETunnelProviderManager.loadAllFromPreferences { mgrs, err in
            loadedEmpty = (err == nil && mgrs?.isEmpty == true)
        }
        #expect(loadedEmpty)
    }

    @Test("On-demand rules + provider-message API compile")
    func onDemandAndMessages() throws {
        let mgr = NETunnelProviderManager()
        mgr.isOnDemandEnabled = true
        mgr.onDemandRules = [NEOnDemandRuleConnect(), NEOnDemandRuleDisconnect()]
        #expect(mgr.onDemandRules?.count == 2)
        let session = mgr.connection as? NETunnelProviderSession
        try session?.sendProviderMessage(Data([1, 2, 3])) { _ in }
    }
}
