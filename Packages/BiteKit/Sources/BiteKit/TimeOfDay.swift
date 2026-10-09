import Foundation

/// What the To-Do widget wishes someone with nothing left to do: a good morning, afternoon or
/// evening, or a good night's sleep, by the clock.
public enum TimeOfDay {
    /// The hours a new part of the day starts at: morning, afternoon, evening, night.
    static let starts = [5, 12, 17, 22]

    public static func wish(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: String(localized: "Enjoy your morning", bundle: .module)
        case 12..<17: String(localized: "Enjoy your afternoon", bundle: .module)
        case 17..<22: String(localized: "Enjoy your evening", bundle: .module)
        default: String(localized: "Sleep well", bundle: .module)
        }
    }

    /// When the wish changes over the day after `date`, for a widget to change it then.
    public static func changes(after date: Date, calendar: Calendar = .current) -> [Date] {
        let end = date.addingTimeInterval(24 * 60 * 60)
        let today = calendar.startOfDay(for: date)
        return (0...1).flatMap { days -> [Date] in
            guard let day = calendar.date(byAdding: .day, value: days, to: today) else { return [] }
            return starts.compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day) }
        }
        .filter { $0 > date && $0 <= end }
    }
}
