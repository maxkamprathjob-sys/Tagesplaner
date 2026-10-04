import Foundation

/// Ergebnis einer Zeitsuche. Es wird NIE automatisch eingeplant –
/// die App zeigt den Vorschlag an und wartet auf Bestätigung.
public enum SchedulingResult: Hashable, Sendable {
    case suggestion(Suggestion)
    case noFit(NoFit)

    public var suggestion: Suggestion? {
        if case .suggestion(let s) = self { return s }
        return nil
    }

    public var noFit: NoFit? {
        if case .noFit(let n) = self { return n }
        return nil
    }
}

public struct Suggestion: Hashable, Sendable {
    /// Bester Vorschlag.
    public var interval: DateInterval
    /// Weitere mögliche Zeiträume ("Andere Zeit").
    public var alternatives: [DateInterval]
    /// Hinweis, falls der Vorschlag die Deadline nicht einhält.
    public var deadlineWarning: String?

    /// Alle Kandidaten in Reihenfolge (Vorschlag zuerst).
    public var allCandidates: [DateInterval] { [interval] + alternatives }
}

public struct NoFit: Hashable, Sendable {
    public var requiredMinutes: Int
    public var largestGapMinutes: Int
    public var totalFreeMinutes: Int
    /// Ungefähr fehlende Zeit (bezogen auf die größte zusammenhängende Lücke).
    public var missingMinutes: Int
    /// Zeitraum, der nur nach der Schlafenszeit passen würde (Hinweis, kein Vorschlag).
    public var afterBedtime: DateInterval?
    /// Bester Zeitraum am Folgetag, falls vorhanden.
    public var nextDay: DateInterval?
    /// Deadline würde bei Verschiebung auf morgen verpasst.
    public var deadlineBlocksNextDay: Bool
}

/// Lokale, deterministische Planungslogik – funktioniert ohne Netzwerk und ohne KI.
public struct Scheduler: Sendable {
    public var availability: AvailabilityCalculator
    public var maxAlternatives: Int

    public init(settings: PlannerSettings, calendar: Calendar, maxAlternatives: Int = 8) {
        self.availability = AvailabilityCalculator(settings: settings, calendar: calendar)
        self.maxAlternatives = maxAlternatives
    }

    private var calendar: Calendar { availability.calendar }

    /// Sucht einen Zeitraum für eine Aufgabe an einem Tag.
    /// - Parameters:
    ///   - entries: alle belegten Zeiträume, die den Tag (inkl. Vornacht) betreffen
    ///   - nextDayEntries: Einträge des Folgetags (für die Option "Auf morgen")
    ///   - window: optionale Einschränkung, z. B. "zwischen Uni und Sport"
    ///   - now: aktueller Zeitpunkt – nichts in der Vergangenheit vorschlagen
    public func suggest(_ task: TaskRequest,
                        on day: Date,
                        entries: [ScheduleEntry],
                        nextDayEntries: [ScheduleEntry]? = nil,
                        within window: DateInterval? = nil,
                        now: Date) -> SchedulingResult {
        let needed = TimeInterval(task.durationMinutes * 60)
        var slots = availability.freeSlots(on: day, entries: entries, notBefore: now)
        if let w = window {
            slots = slots.compactMap { DayMath.intersection($0, w) }
        }

        let candidates = makeCandidates(from: slots, needed: needed)
        if !candidates.isEmpty {
            var ordered = candidates
            var warning: String? = nil
            if let deadline = task.deadline {
                let meeting = candidates.filter { $0.end <= deadline }
                let missing = candidates.filter { $0.end > deadline }
                if meeting.isEmpty {
                    warning = "Kein freier Zeitraum endet vor der Deadline."
                }
                ordered = meeting + missing
            }
            let primary = ordered[0]
            let alternatives = Array(ordered.dropFirst().prefix(maxAlternatives))
            return .suggestion(Suggestion(interval: primary, alternatives: alternatives, deadlineWarning: warning))
        }

        // Kein Platz: Analyse für einen verständlichen Hinweis.
        let largest = slots.map { DayMath.minutes($0) }.max() ?? 0
        let total = slots.reduce(0) { $0 + DayMath.minutes($1) }

        var afterBedtime: DateInterval? = nil
        if window == nil {
            let late = availability.lateWindow(for: day, entries: entries)
            let nonSleep = entries.filter { $0.kind != .sleep }
            let lateSlots = availability.freeSlots(in: late, entries: nonSleep)
                .filter { $0.end > now }
                .map { DateInterval(start: max($0.start, now), end: $0.end) }
            if let fit = lateSlots.first(where: { $0.duration >= needed }) {
                afterBedtime = DateInterval(start: fit.start, duration: needed)
            }
        }

        var nextDay: DateInterval? = nil
        var deadlineBlocks = false
        if let nde = nextDayEntries {
            let tomorrow = DayMath.addDays(1, to: day, calendar: calendar)
            let tSlots = availability.freeSlots(on: tomorrow, entries: nde, notBefore: now)
            if let fit = tSlots.first(where: { $0.duration >= needed }) {
                let iv = DateInterval(start: fit.start, duration: needed)
                nextDay = iv
                if let d = task.deadline, iv.end > d { deadlineBlocks = true }
            } else if let d = task.deadline, d < DayMath.addDays(2, to: day, calendar: calendar) {
                deadlineBlocks = true
            }
        }

        return .noFit(NoFit(requiredMinutes: task.durationMinutes,
                            largestGapMinutes: largest,
                            totalFreeMinutes: total,
                            missingMinutes: max(0, task.durationMinutes - largest),
                            afterBedtime: afterBedtime,
                            nextDay: nextDay,
                            deadlineBlocksNextDay: deadlineBlocks))
    }

    /// Plant mehrere offene Aufgaben nacheinander. Wichtige und dringende Aufgaben
    /// wählen zuerst – sie verschwinden nicht hinter unwichtigen.
    /// Das Ergebnis sind Vorschläge; nichts wird gespeichert.
    public func planDay(_ tasks: [TaskRequest],
                        on day: Date,
                        entries: [ScheduleEntry],
                        nextDayEntries: [ScheduleEntry]? = nil,
                        now: Date) -> [(task: TaskRequest, result: SchedulingResult)] {
        var busy = entries
        var output: [(task: TaskRequest, result: SchedulingResult)] = []
        for task in Scheduler.order(tasks, now: now, calendar: calendar) {
            let result = suggest(task, on: day, entries: busy, nextDayEntries: nextDayEntries, now: now)
            if let s = result.suggestion {
                busy.append(ScheduleEntry(id: "proposal-\(task.id)", title: task.title,
                                          interval: s.interval, kind: .flexible))
            }
            output.append((task, result))
        }
        return output
    }

    /// Reihenfolge für die Planung: Deadline in den nächsten 48 Std. zuerst,
    /// dann Priorität, dann frühere Deadline, dann längere Aufgaben.
    public static func order(_ tasks: [TaskRequest], now: Date, calendar: Calendar) -> [TaskRequest] {
        let urgentLimit = now.addingTimeInterval(48 * 3600)
        func urgent(_ t: TaskRequest) -> Bool {
            guard let d = t.deadline else { return false }
            return d <= urgentLimit
        }
        return tasks.sorted { a, b in
            let ua = urgent(a), ub = urgent(b)
            if ua != ub { return ua }
            if a.priority != b.priority { return a.priority > b.priority }
            switch (a.deadline, b.deadline) {
            case let (da?, db?) where da != db: return da < db
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if a.durationMinutes != b.durationMinutes { return a.durationMinutes > b.durationMinutes }
            return a.id < b.id
        }
    }

    /// Kandidaten: Anfang jeder passenden Lücke, bei langen Lücken zusätzlich
    /// im 30-Minuten-Abstand – damit "Andere Zeit" echte Alternativen bietet.
    private func makeCandidates(from slots: [DateInterval], needed: TimeInterval) -> [DateInterval] {
        var result: [DateInterval] = []
        let step: TimeInterval = 30 * 60
        for slot in slots where slot.duration >= needed {
            var start = slot.start
            var count = 0
            while start.addingTimeInterval(needed) <= slot.end && count < 6 {
                result.append(DateInterval(start: start, duration: needed))
                start = start.addingTimeInterval(step)
                count += 1
            }
            // Auch das Ende der Lücke anbieten (z. B. direkt vor dem nächsten Termin).
            let endAligned = DateInterval(start: slot.end.addingTimeInterval(-needed), duration: needed)
            if !result.contains(endAligned) && endAligned.start > slot.start {
                let rounded = DayMath.roundUp(endAligned.start, toMinutes: availability.settings.gridMinutes, calendar: calendar)
                if rounded.addingTimeInterval(needed) <= slot.end {
                    let iv = DateInterval(start: rounded, duration: needed)
                    if !result.contains(iv) { result.append(iv) }
                }
            }
        }
        return result
    }
}
