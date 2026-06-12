//
// QuillSignalTrust.swift -- pin chat.signal.org to Signal's own root CA for the
// URLSession (libcurl/OpenSSL) REST path on QuillOS/Linux.
//
// WHY: chat.signal.org does NOT use a public CA. Its TLS chain terminates at
// Signal's OWN self-signed root ("CN=Signal Messenger", subject==issuer), which
// the upstream iOS app pins as the trust ANCHOR (HttpSecurityPolicy.signalCaPinned
// -> Certificates.load("signal-messenger", extension: "cer")). libsignal's Rust
// transport (used for the provisioning + chat websockets) has this root compiled
// in, so those connect fine. But the verify-secondary-device PUT to
// v1/devices/link and the v2/keys prekey uploads go through swift-corelibs
// URLSession, which on Linux is backed by libcurl/OpenSSL and validates against
// the SYSTEM CA store. That store does NOT contain Signal's private root, so the
// legitimate chain is reported as "self-signed certificate in certificate chain"
// and the PUT fails.
//
// FIX: upstream pins via Security.framework/SecTrust, which doesn't exist on
// Linux. swift-corelibs-foundation's URLSession uses libcurl, and that libcurl
// trusts its COMPILED-IN default CA bundle (/etc/ssl/certs/ca-certificates.crt on
// Debian/Ubuntu) -- it ignores the OpenSSL SSL_CERT_FILE / CURL_CA_BUNDLE env
// vars (verified empirically: setting them did NOT make the PUT trust Signal's
// root). So we add Signal's root to the trust libcurl actually reads: APPEND the
// PEM to the system CA bundle (idempotent). This makes the REST path trust
// Signal's CA in addition to the public roots. (We still setenv the OpenSSL vars
// as belt-and-suspenders for any OpenSSL-direct path.) The append needs a
// writable bundle; in the QuillOS/Linux runtime the process runs with that
// access (and a production image would bake the root in at build time instead).
//
// The root cert is a public artifact (Signal ships it in their open-source app);
// embedding the PEM keeps this self-contained and independent of the disposable
// .upstream tree. Call quillInstallSignalCATrust() ONCE before any URLSession
// request (we call it at the top of main.swift, before any REST networking).
//
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Dispatch
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// User-Agent presented to Signal's REST endpoints (v1/devices/link, v2/keys,
/// the TLS probe). Signal's server enforces APP EXPIRY: it reads the client
/// version from this header and returns HTTP 499 (AppExpiry.appExpiredStatusCode)
/// for any build past its supported window. The format must match what
/// AppVersionImpl produces -- "Signal-iOS/<marketing>.<build> iOS/<os>" -- and the
/// version must be a CURRENT, non-expired Signal-iOS release. 8.14.0.1637 is the
/// latest production tag (signalapp/Signal-iOS) as of 2026-06; bump this when the
/// server starts returning 499 again (≈ every 90 days).
let quillSignalUserAgent = "Signal-iOS/8.14.0.1637 iOS/18.5"

/// Signal Messenger's root CA (DER from
/// SignalServiceKit/Resources/Certificates/signal-messenger.cer, PEM-encoded).
/// subject == issuer == "CN=Signal Messenger"; this is the anchor
/// chat.signal.org chains to.
private let quillSignalRootCAPEM = """
-----BEGIN CERTIFICATE-----
MIIF2zCCA8OgAwIBAgIUAMHz4g60cIDBpPr1gyZ/JDaaPpcwDQYJKoZIhvcNAQEL
BQAwdTELMAkGA1UEBhMCVVMxEzARBgNVBAgTCkNhbGlmb3JuaWExFjAUBgNVBAcT
DU1vdW50YWluIFZpZXcxHjAcBgNVBAoTFVNpZ25hbCBNZXNzZW5nZXIsIExMQzEZ
MBcGA1UEAxMQU2lnbmFsIE1lc3NlbmdlcjAeFw0yMjAxMjYwMDQ1NTFaFw0zMjAx
MjQwMDQ1NTBaMHUxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMRYw
FAYDVQQHEw1Nb3VudGFpbiBWaWV3MR4wHAYDVQQKExVTaWduYWwgTWVzc2VuZ2Vy
LCBMTEMxGTAXBgNVBAMTEFNpZ25hbCBNZXNzZW5nZXIwggIiMA0GCSqGSIb3DQEB
AQUAA4ICDwAwggIKAoICAQDEecifxMHHlDhxbERVdErOhGsLO08PUdNkATjZ1kT5
1uPf5JPiRbus9F4J/GgBQ4ANSAjIDZuFY0WOvG/i0qvxthpW70ocp8IjkiWTNiA8
1zQNQdCiWbGDU4B1sLi2o4JgJMweSkQFiyDynqWgHpw+KmvytCzRWnvrrptIfE4G
PxNOsAtXFbVH++8JO42IaKRVlbfpe/lUHbjiYmIpQroZPGPY4Oql8KM3o39ObPnT
o1WoM4moyOOZpU3lV1awftvWBx1sbTBL02sQWfHRxgNVF+Pj0fdDMMFdFJobArrL
VfK2Ua+dYN4pV5XIxzVarSRW73CXqQ+2qloPW/ynpa3gRtYeGWV4jl7eD0PmeHpK
OY78idP4H1jfAv0TAVeKpuB5ZFZ2szcySxrQa8d7FIf0kNJe9gIRjbQ+XrvnN+ZZ
vj6d+8uBJq8LfQaFhlVfI0/aIdggScapR7w8oLpvdflUWqcTLeXVNLVrg15cEDwd
lV8PVscT/KT0bfNzKI80qBq8LyRmauAqP0CDjayYGb2UAabnhefgmRY6aBE5mXxd
byAEzzCS3vDxjeTD8v8nbDq+SD6lJi0i7jgwEfNDhe9XK50baK15Udc8Cr/ZlhGM
jNmWqBd0jIpaZm1rzWA0k4VwXtDwpBXSz8oBFshiXs3FD6jHY2IhOR3ppbyd4qRU
pwIDAQABo2MwYTAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNV
HQ4EFgQUtfNLxuXWS9DlgGuMUMNnW7yx83EwHwYDVR0jBBgwFoAUtfNLxuXWS9Dl
gGuMUMNnW7yx83EwDQYJKoZIhvcNAQELBQADggIBABUeiryS0qjykBN75aoHO9bV
PrrX+DSJIB9V2YzkFVyh/io65QJMG8naWVGOSpVRwUwhZVKh3JVp/miPgzTGAo7z
hrDIoXc+ih7orAMb19qol/2Ha8OZLa75LojJNRbZoCR5C+gM8C+spMLjFf9k3JVx
dajhtRUcR0zYhwsBS7qZ5Me0d6gRXD0ZiSbadMMxSw6KfKk3ePmPb9gX+MRTS63c
8mLzVYB/3fe/bkpq4RUwzUHvoZf+SUD7NzSQRQQMfvAHlxk11TVNxScYPtxXDyiy
3Cssl9gWrrWqQ/omuHipoH62J7h8KAYbr6oEIq+Czuenc3eCIBGBBfvCpuFOgckA
XXE4MlBasEU0MO66GrTCgMt9bAmSw3TrRP12+ZUFxYNtqWluRU8JWQ4FCCPcz9pg
MRBOgn4lTxDZG+I47OKNuSRjFEP94cdgxd3H/5BK7WHUz1tAGQ4BgepSXgmjzifF
T5FVTDTl3ZnWUVBXiHYtbOBgLiSIkbqGMCLtrBtFIeQ7RRTb3L+IE9R0UB0cJB3A
Xbf1lVkOcmrdu2h8A32aCwtr5S1fBF1unlG7imPmqJfpOMWa8yIF/KWVm29JAPq8
Lrsybb0z5gg8w7ZblEuB9zOW9M3l60DXuJO6l7g+deV6P96rv2unHS8UlvWiVWDy
9qfgAJizyy3kqM4lOwBH
-----END CERTIFICATE-----
"""

/// The system CA bundles libcurl may trust (Debian/Ubuntu first, then common
/// alternates). We append Signal's root to whichever writable bundle exists.
private let quillSystemCABundlePaths = [
    "/etc/ssl/certs/ca-certificates.crt",   // Debian/Ubuntu (our build image)
    "/etc/pki/tls/certs/ca-bundle.crt",     // RHEL/Fedora
    "/etc/ssl/cert.pem",                    // alpine / BSD-ish
]

/// A marker comment we write alongside the appended cert so the append is
/// idempotent across repeated runs against the same (volume-persisted) bundle.
private let quillSignalTrustMarker = "# QuillOS: Signal Messenger root CA (pinned for chat.signal.org)"

/// Make the corelibs URLSession (libcurl) REST path trust chat.signal.org by
/// adding Signal's root to the system CA bundle libcurl reads, plus setting the
/// OpenSSL env vars as a fallback. Idempotent; call once before any URLSession
/// request. Best-effort: on failure the PUT surfaces the original TLS error
/// honestly rather than silently proceeding insecurely.
@discardableResult
func quillInstallSignalCATrust() -> Bool {
    // (1) Belt-and-suspenders: a standalone PEM for any OpenSSL-direct consumer.
    let pemPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("quill-signal-root-ca.pem").path
    try? quillSignalRootCAPEM.write(toFile: pemPath, atomically: true, encoding: .utf8)
    setenv("SSL_CERT_FILE", pemPath, 1)
    setenv("CURL_CA_BUNDLE", pemPath, 1)

    // (2) The mechanism that actually works for corelibs URLSession/libcurl:
    // append Signal's root to the system CA bundle libcurl trusts by default.
    let fm = FileManager.default
    for bundle in quillSystemCABundlePaths {
        guard fm.fileExists(atPath: bundle) else { continue }
        guard let existing = try? String(contentsOfFile: bundle, encoding: .utf8) else { continue }
        if existing.contains(quillSignalTrustMarker) {
            print("signal-smoke TRUST: Signal root already present in \(bundle)")
            return true
        }
        let appended = existing + "\n" + quillSignalTrustMarker + "\n" + quillSignalRootCAPEM + "\n"
        do {
            try appended.write(toFile: bundle, atomically: true, encoding: .utf8)
            print("signal-smoke TRUST: appended Signal root CA to system bundle \(bundle)")
            return true
        } catch {
            print("signal-smoke TRUST: could not append to \(bundle): \(error)")
            // try the next candidate bundle
        }
    }
    print("signal-smoke TRUST: no writable system CA bundle found; relying on env-var fallback only")
    return false
}

/// No-scan TLS probe: hit chat.signal.org via URLSession (the SAME path the
/// link/keys PUTs use) and report whether TLS validated. ANY HTTP response means
/// the cert chain was trusted; an error mentioning the certificate means it was
/// not. Lets us verify the trust fix without consuming a single-use QR scan.
func quillSignalTLSProbe() -> String {
    guard let url = URL(string: "https://chat.signal.org/v1/config") else {
        return "TLS PROBE: bad URL"
    }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.timeoutInterval = 15
    req.setValue(quillSignalUserAgent, forHTTPHeaderField: "User-Agent")
    let sem = DispatchSemaphore(value: 0)
    var result = "TLS PROBE: no result"
    let task = URLSession.shared.dataTask(with: req) { _, response, error in
        if let http = response as? HTTPURLResponse {
            result = "TLS PROBE: OK -- TLS validated, chat.signal.org returned HTTP \(http.statusCode)"
        } else if let error {
            let msg = "\(error)"
            if msg.lowercased().contains("certificate") {
                result = "TLS PROBE: FAILED -- certificate not trusted: \(msg)"
            } else {
                result = "TLS PROBE: inconclusive (non-cert error, TLS may still be OK): \(msg)"
            }
        }
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + 20)
    return result
}
