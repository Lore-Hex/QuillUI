import Foundation
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `HTTPMethod` and `HTTPRequestHeader` name constants.
@Suite("RSWeb clone — HTTPMethod + HTTPRequestHeader constants")
struct HTTPConstantsTests {

    @Test("HTTPMethod exposes the standard verbs")
    func methods() {
        #expect(HTTPMethod.get == "GET")
        #expect(HTTPMethod.post == "POST")
        #expect(HTTPMethod.put == "PUT")
        #expect(HTTPMethod.patch == "PATCH")
        #expect(HTTPMethod.delete == "DELETE")
    }

    @Test("HTTPRequestHeader exposes the expected header names")
    func requestHeaders() {
        #expect(HTTPRequestHeader.userAgent == "User-Agent")
        #expect(HTTPRequestHeader.authorization == "Authorization")
        #expect(HTTPRequestHeader.contentType == "Content-Type")
        #expect(HTTPRequestHeader.ifModifiedSince == "If-Modified-Since")
        #expect(HTTPRequestHeader.ifNoneMatch == "If-None-Match")
    }
}
