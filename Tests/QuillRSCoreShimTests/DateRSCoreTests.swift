import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore `Date`/`TimeInterval` rough offsets. These are the
/// "don't use the calendar" helpers RSCore source relies on, so the contract is
/// simple fixed-second arithmetic (1 day == 86400s) — no DST/calendar nuance.
@Suite("QuillRSCoreShim — Date+RSCore (rough day/hour offsets)")
struct DateRSCoreTests {

    @Test("TimeInterval(days:) is whole days of seconds")
    func timeIntervalDays() {
        #expect(TimeInterval(days: 1) == 86_400)
        #expect(TimeInterval(days: 2) == 172_800)
        #expect(TimeInterval(days: 0) == 0)
    }

    @Test("TimeInterval(hours:) is whole hours of seconds")
    func timeIntervalHours() {
        #expect(TimeInterval(hours: 1) == 3_600)
        #expect(TimeInterval(hours: 24) == 86_400)
    }

    @Test("Date.byAdding(days:) advances by whole days")
    func byAddingDays() {
        let epoch = Date(timeIntervalSince1970: 0)
        #expect(epoch.byAdding(days: 1).timeIntervalSince1970 == 86_400)
        #expect(epoch.byAdding(days: 7).timeIntervalSince1970 == 604_800)
    }

    @Test("Date.bySubtracting(days:) / bySubtracting(hours:) go backward")
    func bySubtracting() {
        let twoDays = Date(timeIntervalSince1970: 172_800)
        #expect(twoDays.bySubtracting(days: 1).timeIntervalSince1970 == 86_400)

        let twoHours = Date(timeIntervalSince1970: 7_200)
        #expect(twoHours.bySubtracting(hours: 1).timeIntervalSince1970 == 3_600)
    }
}
