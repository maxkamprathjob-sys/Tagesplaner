import Foundation
import SwiftData
import PlannerCore

/// DAS gemeinsame Datenmodell.
///
/// Ein einziger Eintrag kann gleichzeitig sein:
///  - Aufgabe (isTask = true → erscheint in der To-do-Liste)
///  - Zeitblock (start/end gesetzt → erscheint im Tagesplan)
///  - Termin (isFixed = true → wird von der Planung nie verschoben)
///
/// Tagesplan und To-do-Liste lesen dieselben Objekte. Es gibt keine Kopien,
/// daher kann eine Zeitänderung nicht in nur einer Ansicht ankommen.
@Model
final class PlanItem {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var categoryRaw: String = ItemCategory.other.rawValue

    /// Tag (00:00), zu dem der Eintrag gehört. Bei Zeitblöcken immer der Tag des Starts.
    var day: Date = Date()
    var start: Date?
    var end: Date?

    var isTask: Bool = true
    var isDone: Bool = false
    var completedAt: Date?

    var deadline: Date?
    var estimatedMinutes: Int?
    var priorityRaw: Int = Priority.normal.rawValue
    var isFixed: Bool = false

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String,
         day: Date,
         interval: DateInterval? = nil,
         isTask: Bool = true,
         category: ItemCategory = .other,
         priority: Priority = .normal,
         estimatedMinutes: Int? = nil,
         deadline: Date? = nil,
         isFixed: Bool = false,
         notes: String = "",
         calendar: Calendar = DayMath.plannerCalendar) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.categoryRaw = category.rawValue
        self.day = calendar.startOfDay(for: interval?.start ?? day)
        self.start = interval?.start
        self.end = interval?.end
        self.isTask = isTask
        self.priorityRaw = priority.rawValue
        self.estimatedMinutes = estimatedMinutes
        self.deadline = deadline
        self.isFixed = isFixed
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: Abgeleitete Werte

    var category: ItemCategory {
        get { ItemCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue; touch() }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue; touch() }
    }

    var interval: DateInterval? {
        guard let s = start, let e = end, e > s else { return nil }
        return DateInterval(start: s, end: e)
    }

    var isScheduled: Bool { interval != nil }
    var isSleep: Bool { category == .sleep }
    var isOvernight: Bool {
        guard let s = start, let e = end else { return false }
        return !Calendar.current.isDate(s, inSameDayAs: e.addingTimeInterval(-1))
    }

    /// Dauer für die Planung: eingeplante Länge, sonst Schätzung.
    var plannedMinutes: Int? {
        if let iv = interval { return DayMath.minutes(iv) }
        return estimatedMinutes
    }

    // MARK: Änderungen (halten die Invarianten ein)

    /// Setzt oder entfernt den Zeitblock. Der Tag folgt immer dem Start,
    /// damit ein Eintrag nie am falschen Tag erscheint.
    func setSchedule(_ interval: DateInterval?, calendar: Calendar = DayMath.plannerCalendar) {
        if let iv = interval {
            start = iv.start
            end = iv.end
            day = calendar.startOfDay(for: iv.start)
            if estimatedMinutes == nil && isTask { estimatedMinutes = DayMath.minutes(iv) }
        } else {
            start = nil
            end = nil
        }
        touch()
    }

    /// Verschiebt den Eintrag auf einen anderen Tag. Uhrzeiten bleiben erhalten.
    func move(toDay newDay: Date, calendar: Calendar = DayMath.plannerCalendar) {
        let target = calendar.startOfDay(for: newDay)
        if let iv = interval {
            let oldDay = calendar.startOfDay(for: iv.start)
            let offset = calendar.dateComponents([.day], from: oldDay, to: target).day ?? 0
            let s = calendar.date(byAdding: .day, value: offset, to: iv.start) ?? iv.start
            let e = calendar.date(byAdding: .day, value: offset, to: iv.end) ?? iv.end
            setSchedule(DateInterval(start: s, end: max(e, s.addingTimeInterval(60))), calendar: calendar)
        } else {
            day = target
            touch()
        }
    }

    func setDone(_ done: Bool) {
        isDone = done
        completedAt = done ? Date() : nil
        touch()
    }

    func touch() { updatedAt = Date() }

    // MARK: Brücke zur Planungslogik

    var scheduleEntry: ScheduleEntry? {
        guard let iv = interval else { return nil }
        let kind: ScheduleEntry.Kind
        if isSleep { kind = .sleep }
        else if isFixed { kind = .fixed }
        else { kind = .flexible }
        return ScheduleEntry(id: id.uuidString, title: title, interval: iv, kind: kind)
    }

    func taskRequest(defaultMinutes: Int = 60) -> TaskRequest {
        TaskRequest(id: id.uuidString, title: title,
                    durationMinutes: estimatedMinutes ?? defaultMinutes,
                    priority: priority, deadline: deadline)
    }

    /// Gehört der Eintrag zu diesem Tag (Tagesplan oder To-do-Liste)?
    func belongs(to dayInterval: DateInterval) -> Bool {
        if let iv = interval {
            return iv.start < dayInterval.end && iv.end > dayInterval.start
        }
        return day >= dayInterval.start && day < dayInterval.end
    }
}
