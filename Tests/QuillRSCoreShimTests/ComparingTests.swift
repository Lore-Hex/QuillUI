import Foundation
import Testing
@testable import QuillRSCoreShim

@Suite("QuillRSCoreShim — Comparing")
struct ComparingTests {
    @Test("string comparison honors localized case-insensitive ordering")
    func stringComparison() {
        #expect(compareStrings("Alpha", "bravo", ascending: true))
        #expect(!compareStrings("bravo", "Alpha", ascending: true))
        #expect(compareStrings("bravo", "Alpha", ascending: false))
    }

    @Test("value comparison supports sort closures and comparison results")
    func valueComparison() {
        #expect(compareValues(1, 2, ascending: true))
        #expect(compareValues(2, 1, ascending: false))
        #expect(compareValues(1, 2) == .orderedAscending)
        #expect(compareValues(2, 1) == .orderedDescending)
        #expect(compareValues(1, 1) == .orderedSame)
    }

    @Test("optional comparison sorts nil before values")
    func optionalComparison() {
        #expect(compareOptionals(nil as Int?, 1, ascending: true))
        #expect(!compareOptionals(nil as Int?, 1, ascending: false))
        #expect(compareOptionals(2, nil as Int?, ascending: false))
        #expect(compareOptionals(nil as Int?, 1) == .orderedAscending)
        #expect(compareOptionals(1, nil as Int?) == .orderedDescending)
        #expect(compareOptionals(nil as Int?, nil as Int?) == .orderedSame)
        #expect(compareOptionals(1, 2) == .orderedAscending)
    }
}
