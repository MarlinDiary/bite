import Foundation

/// When Statistics says a page last changed, on the phone and the Mac alike.
enum ModifiedDate {
    /// "Today at 21:13" and "Yesterday at 09:05", then the date.
    static func text(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
