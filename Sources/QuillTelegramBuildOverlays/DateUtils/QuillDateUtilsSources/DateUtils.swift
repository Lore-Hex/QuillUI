// Swift clone of the upstream Objective-C DateUtils surface
// (packages/DateUtils/Sources/DateUtils/DateUtils.h). Formatting follows the
// upstream intent (short times, dialog dates, last-seen strings) through
// Foundation's DateFormatter; the localization hook mirrors
// setDateLocalizationFunc.
import Foundation

private final class QuillDateUtilsState: @unchecked Sendable {
    static let shared = QuillDateUtilsState()
    private let lock = NSLock()
    private var localization: ((String) -> String)?

    func setLocalization(_ block: ((String) -> String)?) {
        lock.lock()
        localization = block
        lock.unlock()
    }

    func localized(_ key: String) -> String {
        lock.lock()
        let block = localization
        lock.unlock()
        return block?(key) ?? key
    }
}

private func quillFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = format
    return formatter
}

private func quillDate(_ time: Int32) -> Date {
    Date(timeIntervalSince1970: TimeInterval(time))
}

open class DateUtils: NSObject {
    public class func stringForShortTime(_ time: Int32) -> String {
        let format = TGUse12hDateFormat() ? "h:mm a" : "HH:mm"
        return quillFormatter(format).string(from: quillDate(time))
    }

    public class func stringForDialogTime(_ time: Int32) -> String {
        stringForShortTime(time)
    }

    public class func stringForDayOfMonth(_ date: Int32, dayOfMonth: UnsafeMutablePointer<Int32>?) -> String {
        let day = Calendar.current.component(.day, from: quillDate(date))
        dayOfMonth?.pointee = Int32(day)
        return quillFormatter("MMM d").string(from: quillDate(date))
    }

    public class func stringForDayOfMonthFull(_ date: Int32, dayOfMonth: UnsafeMutablePointer<Int32>?) -> String {
        let day = Calendar.current.component(.day, from: quillDate(date))
        dayOfMonth?.pointee = Int32(day)
        return quillFormatter("MMMM d").string(from: quillDate(date))
    }

    public class func stringForDayOfWeek(_ date: Int32) -> String {
        quillFormatter("EEE").string(from: quillDate(date))
    }

    public class func stringForMessageListDate(_ date: Int32) -> String {
        let calendar = Calendar.current
        let messageDate = quillDate(date)
        if calendar.isDateInToday(messageDate) {
            return stringForShortTime(date)
        }
        if calendar.isDate(messageDate, equalTo: Date(), toGranularity: .weekOfYear) {
            return stringForDayOfWeek(date)
        }
        return quillFormatter("dd.MM.yy").string(from: messageDate)
    }

    public class func stringForLastSeen(_ date: Int32) -> String {
        QuillDateUtilsState.shared.localized("LastSeen.AtDate")
            .replacingOccurrences(of: "%@", with: stringForShortTime(date))
    }

    public class func stringForLastSeenShort(_ date: Int32) -> String {
        stringForShortTime(date)
    }

    public class func stringForRelativeLastSeen(_ date: Int32) -> String {
        let interval = Date().timeIntervalSince(quillDate(date))
        if interval < 60 { return QuillDateUtilsState.shared.localized("LastSeen.JustNow") }
        if interval < 3600 {
            return QuillDateUtilsState.shared.localized("LastSeen.MinutesAgo")
                .replacingOccurrences(of: "%d", with: String(Int(interval / 60)))
        }
        if interval < 86400 {
            return QuillDateUtilsState.shared.localized("LastSeen.HoursAgo")
                .replacingOccurrences(of: "%d", with: String(Int(interval / 3600)))
        }
        return stringForLastSeen(date)
    }

    public class func stringForUntil(_ date: Int32) -> String {
        QuillDateUtilsState.shared.localized("Time.Until")
            .replacingOccurrences(of: "%@", with: stringForShortTime(date))
    }

    public class func setDateLocalizationFunc(_ localizationF: ((String) -> String)?) {
        QuillDateUtilsState.shared.setLocalization(localizationF)
    }
}

public func NSLocalized(_ key: String, _ comment: String) -> String {
    _ = comment
    return QuillDateUtilsState.shared.localized(key)
}

public func TGUse12hDateFormat() -> Bool {
    // Mirror upstream's locale probe: 12-hour clock when the localized time
    // format contains a day-period marker.
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.dateFormat?.contains("a") ?? false
}
