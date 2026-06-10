import Foundation

/// A simple date value type for DatePicker (no Foundation dependency).
public struct DateComponents: Equatable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Creates DateComponents for today's date.
    public init() {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }
}

/// Component mask matching SwiftUI's `DatePickerComponents` surface.
public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let hourAndMinute = DatePickerComponents(rawValue: 1 << 0)
    public static let date = DatePickerComponents(rawValue: 1 << 1)
}

/// A date picker backed by a native calendar widget.
public struct DatePicker: View {
    public typealias Body = Never

    public let title: String
    public let selection: Binding<DateComponents>?
    public let onChange: ((DateComponents) -> Void)?

    /// Creates a DatePicker with a binding.
    public init(_ title: String = "", selection: Binding<DateComponents>) {
        self.title = title
        self.selection = selection
        self.onChange = nil
    }

    /// Creates a SwiftUI-compatible DatePicker with a Date binding. The current
    /// GTK renderer presents the date component; time components are preserved
    /// when callers mutate the selected day.
    public init(
        _ title: String = "",
        selection dateSelection: Binding<Date>,
        displayedComponents: DatePickerComponents = [.hourAndMinute, .date]
    ) {
        _ = displayedComponents
        self.title = title
        self.selection = Binding<DateComponents>(
            get: {
                let components = Calendar.current.dateComponents([.year, .month, .day], from: dateSelection.wrappedValue)
                return DateComponents(
                    year: components.year ?? 1970,
                    month: components.month ?? 1,
                    day: components.day ?? 1
                )
            },
            set: { newValue in
                var components = Calendar.current.dateComponents(
                    [.hour, .minute, .second, .nanosecond],
                    from: dateSelection.wrappedValue
                )
                components.year = newValue.year
                components.month = newValue.month
                components.day = newValue.day
                dateSelection.wrappedValue = Calendar.current.date(from: components) ?? dateSelection.wrappedValue
            }
        )
        self.onChange = nil
    }

    /// Creates a DatePicker with a callback.
    public init(_ title: String = "", onChange: ((DateComponents) -> Void)? = nil) {
        self.title = title
        self.selection = nil
        self.onChange = onChange
    }

    public var body: Never { fatalError("DatePicker is a primitive view") }
}
