import XCTest
import os

final class OSTests: XCTestCase {
    
    func testOSAllocatedUnfairLock() {
        let lock = OSAllocatedUnfairLock(initialState: 42)
        let result = lock.withLock { state in
            state += 1
            return state
        }
        XCTAssertEqual(result, 43)
    }
}
