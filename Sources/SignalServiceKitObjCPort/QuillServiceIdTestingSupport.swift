//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//
// SignalServiceKit same-module shim for QuillOS (Track B).
//
// Upstream defines `Aci.randomForTesting()` / `Pni.randomForTesting()` (and the
// `constantForTesting` siblings) inside `#if TESTABLE_BUILD` in
// SignalServiceKit/Account/ServiceId.swift. The Linux library build does not
// define `TESTABLE_BUILD`, so those extensions are compiled out -- yet shipping
// (non-test) code references them: SignalUI's FingerprintViewController builds
// preview/debug fingerprints via `Aci.randomForTesting()`.
//
// Re-declare the testing helpers unconditionally here, mirroring upstream's
// implementation exactly (a fresh random UUID wrapped as the service id). Linked
// into <SSK>/QuillPort/ by scripts/quill-signal-link-ports.sh so it compiles in
// the SignalServiceKit module and is visible to SignalUI.
//
import Foundation
import LibSignalClient

extension Aci {
    public static func randomForTesting() -> Aci {
        Aci(fromUUID: UUID())
    }

    public static func constantForTesting(_ uuidString: String) -> Aci {
        try! ServiceId.parseFrom(serviceIdString: uuidString) as! Aci
    }
}

extension Pni {
    public static func randomForTesting() -> Pni {
        Pni(fromUUID: UUID())
    }

    public static func constantForTesting(_ serviceIdString: String) -> Pni {
        try! ServiceId.parseFrom(serviceIdString: serviceIdString) as! Pni
    }
}
