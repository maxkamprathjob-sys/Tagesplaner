import Foundation

/// Berechnet freie Zeit eines Tages unter Berücksichtigung von
/// Aufstehzeit, Schlafenszeit, Schlafblöcken, Pausen und vorhandenen Einträgen.
public struct AvailabilityCalculator: Sendable {
    public var settings: PlannerSettings
    public var calendar: Calendar

    public init(settings: PlannerSettings, calendar: Calendar) {
        self.settings = settings
        self.calendar = calendar
    }

    /// Wach-Zeitfenster eines Tages: Aufstehzeit bis Schlafenszeit.
    /// Ein Schlafblock, der früher beginnt, verkürzt das Fenster.
    public func planningWindow(for day: Date, entries: [ScheduleEntry] = []) -> DateInterval {
        let window = DayMath.interval(on: day, from: settings.wakeTime, to: settings.bedtime, calendar: calendar)
        var end = window.end
        var start = window.start
        for e in entries where e.kind == .sleep {
            // Schlaf, der innerhalb des Fensters beginnt, beendet den Planungstag.
            if e.interval.start > window.start && e.interval.start < end {
                end = e.interval.start
            }
            // Schlaf aus der Vornacht, der nach der Aufstehzeit endet, verschiebt den Start.
            if e.interval.start <= window.start && e.interval.end > start && e.interval.end < end {
                start = e.interval.end
            }
        }
        if end <= start { return DateInterval(start: start, end: start) }
        return DateInterval(start: start, end: end)
    }

    /// Freie Lücken innerhalb des Planungsfensters.
    /// - Parameter notBefore: z. B. "jetzt" – nichts in der Vergangenheit vorschlagen.
    public func freeSlots(on day: Date, entries: [ScheduleEntry], notBefore: Date? = nil) -> [DateInterval] {
        var window = planningWindow(for: day, entries: entries)
        if let nb = notBefore {
            if nb >= window.end { return [] }
            if nb > window.start { window = DateInterval(start: nb, end: window.end) }
        }
        return freeSlots(in: window, entries: entries)
    }

    /// Freie Lücken in einem beliebigen Fenster (z. B. nach der Schlafenszeit).
    public func freeSlots(in window: DateInterval, entries: [ScheduleEntry]) -> [DateInterval] {
        guard window.duration > 0 else { return [] }
        let buffer = TimeInterval(settings.bufferMinutes * 60)
        let busy = entries.map { e -> DateInterval in
            // Puffer nur um feste und externe Termine, nicht um Schlaf.
            let pad = (e.kind == .sleep) ? 0 : buffer
            return DateInterval(start: e.interval.start.addingTimeInterval(-pad),
                                end: e.interval.end.addingTimeInterval(pad))
        }
        let raw = DayMath.subtract(busy, from: window)
        let minDuration = TimeInterval(settings.minimumSlotMinutes * 60)
        return raw.compactMap { slot in
            let s = DayMath.roundUp(slot.start, toMinutes: settings.gridMinutes, calendar: calendar)
            guard s < slot.end else { return nil }
            let r = DateInterval(start: s, end: slot.end)
            return r.duration >= minDuration ? r : nil
        }
    }

    public func freeMinutes(on day: Date, entries: [ScheduleEntry], notBefore: Date? = nil) -> Int {
        freeSlots(on: day, entries: entries, notBefore: notBefore)
            .reduce(0) { $0 + DayMath.minutes($1) }
    }

    /// Zeit nach der Schlafenszeit (bis 3 Std. danach) – nur für Hinweise,
    /// niemals für automatische Vorschläge.
    public func lateWindow(for day: Date, entries: [ScheduleEntry]) -> DateInterval {
        let w = planningWindow(for: day, entries: entries)
        let bedtimeEnd = DayMath.interval(on: day, from: settings.wakeTime, to: settings.bedtime, calendar: calendar).end
        let start = min(w.end, bedtimeEnd)
        return DateInterval(start: start, duration: 3 * 3600)
    }
}
