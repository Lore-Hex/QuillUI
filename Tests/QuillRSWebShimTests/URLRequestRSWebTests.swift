import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `URLRequest.addBasicAuthorization` — sets the
/// `Authorization: Basic <base64(user:pass)>` header used by sync services.
@Suite("RSWeb clone — URLRequest.addBasicAuthorization")
struct URLRequestRSWebTests {

    @Test("sets the Basic Authorization header from username/password")
    func basicAuth() {
        var request = URLRequest(url: URL(string: "https://example.com/feed")!)
        let ok = request.addBasicAuthorization(username: "user", password: "pass")
        #expect(ok)
        // base64("user:pass") == "dXNlcjpwYXNz"
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic dXNlcjpwYXNz")
    }
}
