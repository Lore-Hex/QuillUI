// QuillCoreTelephony.swift
//
// CoreTelephony is a Darwin-only framework that exposes the cellular radio's
// carrier/PLMN info. QuillOS (Linux, no cellular modem) has no such framework.
// This is an honest INERT stand-in so SignalServiceKit's
// RegistrationSessionManagerImpl.getMccMnc() compiles.
// serviceSubscriberCellularProviders returns nil, which makes the call site's
// guard take the fallback branch -- the faithful result for a device with no
// cellular radio.
//
#if os(Linux)
import Foundation

/// Inert stand-in for CoreTelephony's CTCarrier. All properties nil (no modem).
public final class CTCarrier {
    public var mobileCountryCode: String? { nil }
    public var mobileNetworkCode: String? { nil }
    public var isoCountryCode: String? { nil }
    public var carrierName: String? { nil }
    public init() {}
}

/// Inert stand-in for CoreTelephony's CTTelephonyNetworkInfo. No subscribers.
public final class CTTelephonyNetworkInfo {
    public init() {}
    public var serviceSubscriberCellularProviders: [String: CTCarrier]? { nil }
}
#endif
