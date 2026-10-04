import Foundation

// MARK: - Deadlines

public struct DeadlineAssessment: Hashable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case ok = 0
        case tight = 1
        case atRisk = 2
        case overdue = 3
        public static func < (l: Level, r: Level) -> Bool { l.rawValue < r.rawValue }
    }

    public var level: Level
    public var freeMinutesUntilDeadline: Int
    public var requiredMinutes: Int
    public var message: String?
}

public enum DeadlineAnalyzer {

    /// Bewertet, ob eine Deadline gefährdet ist.
    /// - Parameters:
    ///   - scheduled: falls die Aufgabe bereits eingeplant ist
    ///   - entriesForDay: liefert die belegten Zeiträume eines Tages
    ///     (ohne die Aufgabe selbst, falls sie noch nicht eingeplant ist)
    public static func assess(task: TaskRequest,
                              scheduled: DateInterval?,
                              now: Date,
                              availability: AvailabilityCalculator,
                              entriesForDay: (Date) -> [ScheduleEntry]) -> DeadlineAssessment? {
        guard let deadline = task.deadline else { return nil }
        let cal = availability.calendar
        let required = task.durationMinutes

        if deadline <= now {
            return DeadlineAssessment(level: .overdue, freeMinutesUntilDeadline: 0, requiredMinutes: required,
                                      message: "Die Deadline ist überschritten.")
        }
        if let s = scheduled {
            if s.end <= deadline {
                return DeadlineAssessment(level: .ok, freeMinutesUntilDeadline: 0, requiredMinutes: required, message: nil)
            }
            return DeadlineAssessment(level: .atRisk, freeMinutesUntilDeadline: 0, requiredMinutes: required,
                                      message: "Die Aufgabe ist erst nach der Deadline eingeplant.")
        }

        let today = cal.startOfDay(for: now)
        let deadlineDay = cal.startOfDay(for: deadline)
        var freeToday = 0
        var freeLater = 0
        var day = today
        var guardCount = 0
        while day <= deadlineDay && guardCount < 31 {
            let slots = availability.freeSlots(on: day, entries: entriesForDay(day), notBefore: now)
            var minutes = 0
            for slot in slots {
                let end = min(slot.end, deadline)
                if end > slot.start {
                    minutes += DayMath.minutes(DateInterval(start: slot.start, end: end))
                }
            }
            if day == today { freeToday += minutes } else { freeLater += minutes }
            day = DayMath.addDays(1, to: day, calendar: cal)
            guardCount += 1
        }
        let total = freeToday + freeLater

        if total < required {
            return DeadlineAssessment(
                level: .atRisk, freeMinutesUntilDeadline: total, requiredMinutes: required,
                message: "Bis zur Deadline bleibt voraussichtlich zu wenig freie Zeit (ungefähr \(DurationText.approximate(total)) frei, \(DurationText.exact(required)) nötig).")
        }
        if deadlineDay > today && freeLater < required && freeToday > 0 {
            return DeadlineAssessment(
                level: .tight, freeMinutesUntilDeadline: total, requiredMinutes: required,
                message: "Wenn du diese Aufgabe heute nicht einplanst, wird es zeitlich knapp.")
        }
        if Double(total) < Double(required) * 1.5 {
            return DeadlineAssessment(
                level: .tight, freeMinutesUntilDeadline: total, requiredMinutes: required,
                message: "Bis zur Deadline bleibt nur wenig Puffer.")
        }
        return DeadlineAssessment(level: .ok, freeMinutesUntilDeadline: total, requiredMinutes: required, message: nil)
    }
}

// MARK: - Tagesanalyse

public struct DayLoad: Hashable, Sendable {
    public enum Level: Sendable {
        case past, relaxed, balanced, tight, full
    }

    public var level: Level
    /// Minuten fester Termine (ohne Schlaf) an diesem Tag.
    public var fixedMinutes: Int
    /// Bereits eingeplante, noch offene Aufgaben.
    public var plannedTaskMinutes: Int
    /// Offene, noch nicht eingeplante Aufgaben mit Zeitschätzung.
    public var unplannedTaskMinutes: Int
    /// Offene Aufgaben ohne Zeitschätzung.
    public var unestimatedTaskCount: Int
    /// Freie Zeit im Wach-Fenster (ab jetzt, falls heute).
    public var freeMinutes: Int
    public var headline: String
    public var detail: String?
}

public enum DayAnalyzer {

    public static func analyze(day: Date,
                               entries: [ScheduleEntry],
                               unplannedTaskMinutes: [Int?],
                               now: Date,
                               availability: AvailabilityCalculator) -> DayLoad {
        let cal = availability.calendar
        let dayInterval = DayMath.dayInterval(containing: day, calendar: cal)
        let isPast = dayInterval.end <= now
        let isToday = dayInterval.contains(now)

        var fixed = 0
        var planned = 0
        for e in entries {
            guard let part = DayMath.intersection(e.interval, dayInterval) else { continue }
            switch e.kind {
            case .fixed, .external: fixed += DayMath.minutes(part)
            case .flexible: planned += DayMath.minutes(part)
            case .sleep: break
            }
        }
        let estimated = unplannedTaskMinutes.compactMap { $0 }.reduce(0, +)
        let unestimated = unplannedTaskMinutes.filter { $0 == nil }.count
        let free = isPast ? 0 : availability.freeMinutes(on: day, entries: entries, notBefore: isToday ? now : nil)

        if isPast {
            return DayLoad(level: .past, fixedMinutes: fixed, plannedTaskMinutes: planned,
                           unplannedTaskMinutes: estimated, unestimatedTaskCount: unestimated,
                           freeMinutes: 0, headline: "Dieser Tag ist vorbei.",
                           detail: fixed + planned > 0 ? "Verplant waren ungefähr \(DurationText.approximate(fixed + planned))." : nil)
        }

        let dayWord = isToday ? "heute" : "an diesem Tag"
        let level: DayLoad.Level
        let headline: String
        if free < 15 && estimated > 0 {
            level = .full
            headline = "Dein Tag ist vollständig verplant. Für offene Aufgaben fehlen ungefähr \(DurationText.approximate(estimated))."
        } else if free < 15 {
            level = .full
            headline = isToday ? "Für heute ist keine freie Zeit mehr eingeplant." : "Dieser Tag ist vollständig verplant."
        } else if estimated > free {
            level = .tight
            headline = "Dein Tag ist stark ausgelastet. Für offene Aufgaben fehlen ungefähr \(DurationText.approximate(estimated - free))."
        } else if Double(estimated) > Double(free) * 0.7 {
            level = .balanced
            headline = "Knapp, aber machbar: ungefähr \(DurationText.approximate(free)) frei für \(DurationText.approximate(estimated)) offene Aufgaben."
        } else {
            level = .relaxed
            headline = "Du hast \(dayWord) noch ungefähr \(DurationText.approximate(free)) freie Zeit."
        }

        var parts: [String] = []
        if fixed > 0 { parts.append("ungefähr \(DurationText.approximate(fixed)) feste Termine") }
        if planned > 0 { parts.append("\(DurationText.approximate(planned)) eingeplante Aufgaben") }
        if estimated > 0 { parts.append("ungefähr \(DurationText.approximate(estimated)) offene Aufgaben") }
        var detail: String? = parts.isEmpty ? nil : "Du hast \(dayWord) " + joinGerman(parts) + "."
        if unestimated > 0 {
            let s = unestimated == 1 ? "1 Aufgabe hat" : "\(unestimated) Aufgaben haben"
            detail = (detail.map { $0 + " " } ?? "") + "\(s) noch keine Zeitschätzung."
        }
        return DayLoad(level: level, fixedMinutes: fixed, plannedTaskMinutes: planned,
                       unplannedTaskMinutes: estimated, unestimatedTaskCount: unestimated,
                       freeMinutes: free, headline: headline, detail: detail)
    }

    static func joinGerman(_ parts: [String]) -> String {
        if parts.count <= 1 { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " und " + parts.last!
    }
}
