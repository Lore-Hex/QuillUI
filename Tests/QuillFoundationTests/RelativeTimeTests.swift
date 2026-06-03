import Testing
import Foundation
@testable import QuillFoundation

@Suite("QuillFoundation RelativeTime")
struct RelativeTimeTests {
    /// 2024-01-15T14:00:00Z — a fixed reference so the absolute-date
    /// branch is deterministic.
    let date = Date(timeIntervalSince1970: 1_705_327_200)

    /// UTC calendar so absolute-date formatting doesn't depend on the
    /// machine's zone.
    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test("buckets seconds into now / m / h / d")
    func buckets() {
        #expect(RelativeTime.string(for: date, now: date.addingTimeInterval(30)) == "now")
        #expect(RelativeTime.string(for: date, now: date.addingTimeInterval(59)) == "now")
        #expect(RelativeTime.string(for: date, now: date.addingTimeInterval(60)) == "1m")
        #expect(RelativeTime.string(for: date, now: date.addingTimeInterval(300)) == "5m")
        #expect(RelativeTime.string(for: date, now: date.addingTimeInterval(7_200)) == "2h")
        #expect(RelativeTime.string(for: date, now: date.addingTimeInterval(259_200)) == "3d")
    }

    @Test("falls back to a short absolute date past a week (same year)")
    func absoluteSameYear() {
        #expect(RelativeTime.string(for: date, now: date.addingTimeInterval(2_592_000), calendar: utc) == "Jan 15")
    }

    @Test("absolute date gains a year across a year boundary")
    func absoluteCrossYear() {
        #expect(RelativeTime.string(for: date, now: date.addingTimeInterval(43_200_000), calendar: utc) == "Jan 15, 2024")
    }
}
