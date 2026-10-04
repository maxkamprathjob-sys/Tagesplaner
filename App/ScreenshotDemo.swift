#if DEBUG
import Foundation
import SwiftData
import PlannerCore

/// Beispieltag ausschließlich für automatische Simulator-Screenshots im CI.
/// Wird nur mit dem Startargument -screenshotDemo in Debug-Builds verwendet
/// und schreibt in eine reine In-Memory-Datenbank.
enum ScreenshotDemo {
    static func fill(_ context: ModelContext) {
        let cal = DayMath.plannerCalendar
        let today = cal.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int = 0, dayOffset: Int = 0) -> Date {
            TimeOfDay(hour: h, minute: m).date(on: DayMath.addDays(dayOffset, to: today, calendar: cal), calendar: cal)
        }
        let items: [PlanItem] = [
            PlanItem(title: "Schlafen", day: DayMath.addDays(-1, to: today, calendar: cal),
                     interval: DateInterval(start: at(21, dayOffset: -1), end: at(7)), isTask: false, category: .sleep, isFixed: true),
            PlanItem(title: "Universität", day: today, interval: DateInterval(start: at(8), end: at(14)),
                     isTask: false, category: .uni, isFixed: true),
            PlanItem(title: "Sport", day: today, interval: DateInterval(start: at(14, 52), end: at(17)),
                     isTask: true, category: .sport, isFixed: true),
            PlanItem(title: "Für die Klausur lernen", day: today, interval: DateInterval(start: at(17, 15), end: at(19, 15)),
                     isTask: true, category: .study, priority: .veryHigh, estimatedMinutes: 120),
            PlanItem(title: "Schlafen", day: today, interval: DateInterval(start: at(21), end: at(7, dayOffset: 1)),
                     isTask: false, category: .sleep, isFixed: true),
            PlanItem(title: "Einkaufen", day: today, category: .errand, estimatedMinutes: 45),
            PlanItem(title: "E-Mail an Prof. schreiben", day: today, priority: .high, estimatedMinutes: 20),
            PlanItem(title: "Hausarbeit fertigstellen", day: today, category: .study, priority: .high,
                     estimatedMinutes: 120, deadline: at(18, dayOffset: 2)),
            PlanItem(title: "Treffen Lerngruppe", day: today, interval: DateInterval(start: at(13), end: at(14, 30)),
                     isTask: false, category: .appointment, isFixed: true)
        ]
        items.forEach { context.insert($0) }
        try? context.save()
    }
}
#endif
