import XCTest
@testable import Account
@testable import NetNewsWireShared
@testable import RSCore

final class LogicTests: XCTestCase {
    @MainActor func testAccountManagerInitialization() {
        print("Testing AccountManager initialization...")
        let manager = AccountManager.shared
        XCTAssertNotNil(manager)
        print("Active accounts: \(manager.activeAccounts.count)")
    }
}
