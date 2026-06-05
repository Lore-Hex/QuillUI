import Foundation
import Testing
@testable import RSWeb

/// Pins a representative spread of the vendored RSWeb `HTTPResponseCode`
/// constants — the ones NNW's sync/refresh code actually branches on.
@Suite("RSWeb clone — HTTPResponseCode")
struct HTTPResponseCodeTests {

    @Test("success + redirect codes")
    func successAndRedirect() {
        #expect(HTTPResponseCode.responseContinue == 100)
        #expect(HTTPResponseCode.OK == 200)
        #expect(HTTPResponseCode.created == 201)
        #expect(HTTPResponseCode.noContent == 204)
        #expect(HTTPResponseCode.redirectPermanent == 301)
        #expect(HTTPResponseCode.notModified == 304) // conditional GET
    }

    @Test("client-error codes")
    func clientErrors() {
        #expect(HTTPResponseCode.badRequest == 400)
        #expect(HTTPResponseCode.unauthorized == 401)
        #expect(HTTPResponseCode.forbidden == 403)
        #expect(HTTPResponseCode.notFound == 404)
        #expect(HTTPResponseCode.tooManyRequests == 429) // rate limiting
        #expect(HTTPResponseCode.imATeapot == 418)
    }

    @Test("server-error codes")
    func serverErrors() {
        #expect(HTTPResponseCode.internalServerError == 500)
        #expect(HTTPResponseCode.badGateway == 502)
        #expect(HTTPResponseCode.serviceUnavailable == 503)
    }
}
