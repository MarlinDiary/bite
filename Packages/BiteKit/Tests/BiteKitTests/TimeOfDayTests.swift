import Foundation
import Testing
@testable import BiteKit

/// The To-Do widget's wish for someone with nothing left to do, by the time of day.
struct TimeOfDayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func theWishFollowsTheClock() {
        #expect(TimeOfDay.wish(at: at(6, 4, 59), calendar: calendar) == "Sleep well")
        #expect(TimeOfDay.wish(at: at(6, 5), calendar: calendar) == "Enjoy your morning")
        #expect(TimeOfDay.wish(at: at(6, 12), calendar: calendar) == "Enjoy your afternoon")
        #expect(TimeOfDay.wish(at: at(6, 17, 30), calendar: calendar) == "Enjoy your evening")
        #expect(TimeOfDay.wish(at: at(6, 22), calendar: calendar) == "Sleep well")
    }

    /// Every change over the next day, and none at the moment itself.
    @Test func itChangesFourTimesADay() {
        #expect(TimeOfDay.changes(after: at(6, 23, 10), calendar: calendar) == [at(7, 5), at(7, 12), at(7, 17), at(7, 22)])
        #expect(TimeOfDay.changes(after: at(6, 12), calendar: calendar) == [at(6, 17), at(6, 22), at(7, 5), at(7, 12)])
    }

    /// The day the clocks go forward is 23 hours long: the changes keep to the clock.
    @Test func theClocksGoingForwardDoesntMoveIt() {
        let night = calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 23))!
        let changes = TimeOfDay.changes(after: night, calendar: calendar)
        #expect(changes.map { calendar.component(.hour, from: $0) } == [5, 12, 17, 22])
        #expect(changes.allSatisfy { calendar.component(.day, from: $0) == 27 })
    }
}
