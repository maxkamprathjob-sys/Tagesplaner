import Foundation
@testable import PlannerCore

enum T {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }()

    /// Datum im Oktober 2026 (Mittwoch, 28.10.2026 als "heute").
    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return cal.date(from: c)!
    }

    static func entry(_ id: String, _ start: Date, _ end: Date, _ kind: ScheduleEntry.Kind = .fixed) -> ScheduleEntry {
        ScheduleEntry(id: id, title: id, interval: DateInterval(start: start, end: end), kind: kind)
    }

    static func hm(_ d: Date) -> String {
        TimeOfDay(date: d, calendar: cal).formatted
    }

    /// Standardtag aus der Aufgabenstellung: Uni 08–14, Sport 14:52–17, Schlaf 21–07.
    static func exampleDay() -> [ScheduleEntry] {
        [
            entry("Schlaf-Vornacht", date(27, 21), date(28, 7), .sleep),
            entry("Universität", date(28, 8), date(28, 14)),
            entry("Sport", date(28, 14, 52), date(28, 17)),
            entry("Schlafen", date(28, 21), date(29, 7), .sleep)
        ]
    }

    static let settings = PlannerSettings(wakeTime: TimeOfDay(hour: 7), bedtime: TimeOfDay(hour: 21),
                                          bufferMinutes: 0, minimumSlotMinutes: 15, gridMinutes: 5)
}
