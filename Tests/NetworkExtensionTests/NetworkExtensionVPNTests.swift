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

    @Test("NEVPNError direct code members + destroyConfigurationReference (TunnelsManager usage)")
    func vpnErrorCodesAndDestroy() {
        // Mirrors TunnelsManager: NEVPNError(NEVPNError.configurationUnknown) and
        // error.code == NEVPNError.configurationInvalid.
        #expect(NEVPNError.configurationInvalid == .configurationInvalid)
        #expect(NEVPNError(NEVPNError.configurationUnknown).code == .configurationUnknown)
        let err = NEVPNError(NEVPNError.configurationStale)
        #expect(err.code == NEVPNError.configurationStale)
        // macOS-branch no-op method compiles + runs.
        NETunnelProviderProtocol().destroyConfigurationReference()
    }

    @Test("NEVPNStatus.reasserting + NEVPNError Code-pattern switch (TunnelStatus / TunnelErrors)")
    func statusReassertingAndErrorMatching() {
        #expect(NEVPNStatus.reasserting.rawValue == 4)
        // Mirrors TunnelErrors.swift: switch an NEVPNError value over Code cases (~=).
        let systemError = NEVPNError(.configurationStale)
        var matched = "other"
        switch systemError {
        case NEVPNError.configurationInvalid: matched = "invalid"
        case NEVPNError.configurationStale: matched = "stale"
        default: matched = "other"
        }
        #expect(matched == "stale")
    }

    @Test("NEOnDemandRule interface-type + SSID matching (ActivateOnDemandOption)")
    func onDemandInterfaceAndSSID() {
        // Mirrors ActivateOnDemandOption.apply: rules built with an interface type.
        let connect = NEOnDemandRuleConnect(interfaceType: .any)
        #expect(connect.interfaceTypeMatch == .any)
        let disconnect = NEOnDemandRuleDisconnect(interfaceType: .wiFi)
        #expect(disconnect.interfaceTypeMatch == .wiFi)
        // Wi-Fi rule with SSID match (the read-back path uses interfaceTypeMatch == .wiFi && ssidMatch != nil).
        let wifiRule = NEOnDemandRuleConnect()
        wifiRule.interfaceTypeMatch = .wiFi
        wifiRule.ssidMatch = ["HomeNet", "OfficeNet"]
        #expect(wifiRule.interfaceTypeMatch == .wiFi && wifiRule.ssidMatch == ["HomeNet", "OfficeNet"])
        #expect(NEOnDemandRuleInterfaceType.ethernet.rawValue == 3)
    }

    @Test("NETunnelProviderSession.startTunnel(options:)/stopTunnel() (TunnelsManager)")
    func providerSessionStartStop() throws {
        let session = NETunnelProviderSession()
        try session.startTunnel(options: ["activationAttemptId": "abc"])
        session.stopTunnel()
    }

    @Test("NEOnDemandRule.action is set by the Connect/Disconnect subtype (ActivateOnDemandOption read-back)")
    func onDemandRuleAction() {
        // ActivateOnDemandOption reads `rule.action == .connect`/`.disconnect`.
        #expect(NEOnDemandRuleConnect().action == .connect)
        #expect(NEOnDemandRuleDisconnect().action == .disconnect)
        // The interfaceType convenience init still routes through the subtype init,
        // so the action is set too.
        let r = NEOnDemandRuleConnect(interfaceType: .wiFi)
        #expect(r.action == .connect && r.interfaceTypeMatch == .wiFi)
        #expect(NEOnDemandRule().action == .ignore)   // base default
        #expect(NEOnDemandRuleAction.evaluateConnection.rawValue == 3)
    }
}
