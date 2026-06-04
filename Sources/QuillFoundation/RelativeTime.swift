import Foundation

/// Relative ("time ago") timestamp formatting for activity timelines —
/// "now", "5m", "2h", "3d" within the last week, then a short absolute
/// date ("Jan 1", or "Jan 1, 2024" across a year boundary).
///
/// Mastodon clients, RSS readers, and chat timelines all render this same
/// shape, and each tends to roll its own. This is the shared, tested
/// implementation they link instead. The core takes a `Date`; callers that
/// start from a string (e.g. an ISO8601 `created_at`) parse first, then
/// format — keeping wire-format parsing in the app layer and the display
/// logic here.
public enum RelativeTime {
    /// Format `date` relative to `now`: under a minute → `"now"`, under an
    /// hour → `"\(m)m"`, under a day → `"\(h)h"`, under a week → `"\(d)d"`,
    /// otherwise a short absolute date.
    ///
    /// `calendar` (carrying its time zone) is injectable so the
    /// absolute-date branch is deterministic in tests; apps pass `.current`
    /// to render in the viewer's zone.
    public static func string(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d" }
        return absoluteShortDate(date, now: now, calendar: calendar)
    }

    /// Short month/day date, gaining a year only when `date` and `now` fall
    /// in different calendar years. Fixed `en_US_POSIX` locale for stable,
    /// testable output.
    static func absoluteShortDate(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
