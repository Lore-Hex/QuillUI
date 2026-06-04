import Foundation
import Testing
import RSWeb
@testable import QuillAccount

/// Tests for the vendored `AccountError` and the minimal `RSWeb` shim
/// (`TransportError`) it depends on — Account rung 3.
@Suite("QuillAccount — AccountError + RSWeb shim")
struct AccountErrorTests {

    @Test("isCredentialsError is true only for a wrapped 401/403 TransportError")
    func credentialsError() {
        let e401 = AccountError.wrappedError(error: TransportError.httpError(status: 401), accountID: "a", accountName: "Acct")
        let e403 = AccountError.wrappedError(error: TransportError.httpError(status: 403), accountID: "a", accountName: "Acct")
        let e500 = AccountError.wrappedError(error: TransportError.httpError(status: 500), accountID: "a", accountName: "Acct")
        #expect(e401.isCredentialsError)
        #expect(e403.isCredentialsError)
        #expect(!e500.isCredentialsError)
        #expect(!AccountError.invalidParameter.isCredentialsError)
    }

    @Test("every plain case has a description; a credentials error names the account")
    func errorDescriptions() {
        let plain: [AccountError] = [
            .createErrorNotFound, .createErrorAlreadySubscribed, .opmlImportInProgress,
            .invalidParameter, .invalidResponse, .urlNotFound, .unknown,
        ]
        for error in plain { #expect(error.errorDescription?.isEmpty == false) }

        let credentials = AccountError.wrappedError(
            error: TransportError.httpError(status: 403), accountID: "a", accountName: "My Acct"
        )
        #expect(credentials.errorDescription?.contains("My Acct") == true)
        #expect(credentials.recoverySuggestion?.isEmpty == false)
    }

    @Test("RSWeb shim TransportError carries its status and a description")
    func transportError() {
        #expect(TransportError.httpError(status: 404) == .httpError(status: 404))
        #expect(TransportError.httpError(status: 404) != .httpError(status: 500))
        #expect(TransportError.httpError(status: 404).errorDescription?.contains("404") == true)
    }
}
